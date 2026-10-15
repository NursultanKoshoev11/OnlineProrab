import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("apply-deletion-tombstones.py")
SPEC = importlib.util.spec_from_file_location("apply_deletion_tombstones", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class DeletionTombstoneTests(unittest.TestCase):
    def test_loads_account_and_object_tombstones(self):
        user_id = "7cbcf034-8122-4d2d-92fd-f704dcdf8752"
        storage_path = "projects/2026/receipt.pdf"
        digest = hashlib.sha256(storage_path.encode()).hexdigest()
        with tempfile.TemporaryDirectory() as temporary_directory:
            journal = Path(temporary_directory)
            (journal / "accounts").mkdir()
            (journal / "objects").mkdir()
            (journal / "accounts" / f"{user_id}.json").write_text(
                json.dumps({"version": 1, "kind": "account", "user_id": user_id}), encoding="utf-8"
            )
            (journal / "objects" / f"{digest}.json").write_text(
                json.dumps({"version": 1, "kind": "object", "storage_path": storage_path}), encoding="utf-8"
            )

            accounts, objects = MODULE.load_tombstones(journal)

        self.assertEqual(accounts, {user_id})
        self.assertEqual(objects, {storage_path})

    def test_writes_sql_and_batched_s3_delete_manifest(self):
        storage_path = "projects/2026/receipt.pdf"
        user_id = "7cbcf034-8122-4d2d-92fd-f704dcdf8752"
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            sql_path = root / "apply.sql"
            delete_directory = root / "delete-objects"
            MODULE.write_replay_artifacts(
                {user_id},
                {storage_path},
                sql_path,
                delete_directory,
            )

            sql = sql_path.read_text(encoding="utf-8")
            manifest = json.loads((delete_directory / "delete-000001.json").read_text(encoding="utf-8"))

        delete_user_files = f"DELETE FROM files WHERE uploaded_by = '{user_id}'::uuid;"
        delete_user = f"DELETE FROM users WHERE id = '{user_id}'::uuid;"
        self.assertIn(delete_user_files, sql)
        self.assertIn(delete_user, sql)
        self.assertLess(sql.index(delete_user_files), sql.index(delete_user))
        self.assertIn(f"DELETE FROM files WHERE storage_path = '{storage_path}';", sql)
        self.assertEqual(manifest["Objects"], [{"Key": storage_path}])
        self.assertTrue(manifest["Quiet"])

    def test_records_outbox_objects_before_deleting_them(self):
        explicit_object = "project/nested/deleted-by-tombstone.bin"
        account_object = "project/nested/deleted-account-file.bin"
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            delete_directory = root / "delete-objects"
            MODULE.write_replay_artifacts(set(), {explicit_object}, root / "apply.sql", delete_directory)
            outbox_paths = root / "pending-paths.hex"
            outbox_paths.write_text(account_object.encode("utf-8").hex() + "\n", encoding="ascii")
            tombstone_directory = root / "recovery-tombstones"
            completion_sql = root / "complete-outbox.sql"

            MODULE.prepare_outbox_replay_artifacts(
                outbox_paths, tombstone_directory, delete_directory, completion_sql
            )

            digest = hashlib.sha256(account_object.encode("utf-8")).hexdigest()
            tombstone = json.loads(
                (tombstone_directory / "objects" / f"{digest}.json").read_text(encoding="utf-8")
            )
            batches = [json.loads(path.read_text(encoding="utf-8")) for path in delete_directory.glob("*.json")]
            completion = completion_sql.read_text(encoding="utf-8")

        self.assertEqual(tombstone["kind"], "object")
        self.assertEqual(tombstone["storage_path"], account_object)
        self.assertEqual(
            {item["Key"] for batch in batches for item in batch["Objects"]},
            {explicit_object, account_object},
        )
        self.assertIn(f"DELETE FROM file_storage_deletions WHERE storage_path = '{account_object}';", completion)

    def test_rejects_unsafe_database_outbox_paths(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            delete_directory = root / "delete-objects"
            delete_directory.mkdir()
            outbox_paths = root / "pending-paths.hex"
            outbox_paths.write_text(b"../outside".hex() + "\n", encoding="ascii")
            with self.assertRaises(SystemExit):
                MODULE.prepare_outbox_replay_artifacts(
                    outbox_paths, root / "recovery-tombstones", delete_directory, root / "complete-outbox.sql"
                )

    def test_rejects_unexpected_files_and_unsafe_object_keys(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            journal = Path(temporary_directory)
            (journal / "accounts").mkdir()
            (journal / "apply.sql").write_text("SELECT 1;", encoding="utf-8")
            with self.assertRaises(SystemExit):
                MODULE.load_tombstones(journal)

        with tempfile.TemporaryDirectory() as temporary_directory:
            journal = Path(temporary_directory)
            (journal / "objects").mkdir()
            storage_path = "objects/receipt' OR true"
            digest = hashlib.sha256(storage_path.encode()).hexdigest()
            (journal / "objects" / f"{digest}.json").write_text(
                json.dumps({"version": 1, "kind": "object", "storage_path": storage_path}), encoding="utf-8"
            )
            with self.assertRaises(SystemExit):
                MODULE.load_tombstones(journal)

    def test_rejects_symbolic_links(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            journal = root / "journal"
            journal.mkdir()
            target = root / "target.json"
            target.write_text("{}", encoding="utf-8")
            try:
                (journal / "accounts").symlink_to(target)
            except (NotImplementedError, OSError):
                self.skipTest("symbolic links are unavailable")
            with self.assertRaises(SystemExit):
                MODULE.load_tombstones(journal)


if __name__ == "__main__":
    unittest.main()
