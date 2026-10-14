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
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            sql_path = root / "apply.sql"
            delete_directory = root / "delete-objects"
            MODULE.write_replay_artifacts(
                {"7cbcf034-8122-4d2d-92fd-f704dcdf8752"},
                {storage_path},
                sql_path,
                delete_directory,
            )

            sql = sql_path.read_text(encoding="utf-8")
            manifest = json.loads((delete_directory / "delete-000001.json").read_text(encoding="utf-8"))

        self.assertIn("DELETE FROM users", sql)
        self.assertIn(f"DELETE FROM files WHERE storage_path = '{storage_path}';", sql)
        self.assertEqual(manifest["Objects"], [{"Key": storage_path}])
        self.assertTrue(manifest["Quiet"])

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
