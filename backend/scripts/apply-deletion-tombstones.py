#!/usr/bin/env python3
"""Validate durable deletion tombstones and emit safe SQL for database restore."""

import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

UUID_PATTERN = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
OBJECT_KEY_PATTERN = re.compile(r"^[A-Za-z0-9._/-]{1,512}$")
HEX_PATH_PATTERN = re.compile(r"^(?:[0-9a-fA-F]{2})+$")
DELETE_BATCH_SIZE = 1000


def fail(message: str) -> None:
    raise SystemExit(f"invalid deletion tombstone: {message}")


def validate_storage_key(key: object, label: str) -> str:
    if not isinstance(key, str) or not OBJECT_KEY_PATTERN.fullmatch(key):
        fail(f"invalid storage key in {label}")
    parts = key.split("/")
    if key.startswith("/") or "\\" in key or any(part in ("", ".", "..") for part in parts):
        fail(f"unsafe storage key in {label}")
    if PurePosixPath(key).as_posix() != key:
        fail(f"noncanonical storage key in {label}")
    return key


def load_tombstones(directory: Path) -> tuple[set[str], set[str]]:
    if directory.is_symlink() or not directory.is_dir():
        fail("journal directory is missing or unsafe")

    accounts: set[str] = set()
    objects: set[str] = set()
    for path in sorted(directory.rglob("*")):
        if path.is_symlink():
            fail("journal may not contain symbolic links")
        relative = path.relative_to(directory).as_posix()
        if path.is_dir():
            if relative not in {"accounts", "objects"}:
                fail(f"unexpected directory in {relative}")
            continue
        if not path.is_file() or path.suffix != ".json" or len(PurePosixPath(relative).parts) != 2:
            fail(f"unexpected journal entry in {relative}")
        try:
            event = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as error:
            fail(f"cannot read {relative}: {error}")
        if not isinstance(event, dict) or event.get("version") != 1:
            fail(f"unsupported schema in {relative}")

        if event.get("kind") == "account":
            user_id = event.get("user_id")
            if not isinstance(user_id, str) or not UUID_PATTERN.fullmatch(user_id):
                fail(f"invalid account ID in {relative}")
            if relative != f"accounts/{user_id}.json":
                fail(f"account path does not match event in {relative}")
            accounts.add(user_id)
            continue

        if event.get("kind") == "object":
            key = validate_storage_key(event.get("storage_path"), relative)
            digest = hashlib.sha256(key.encode("utf-8")).hexdigest()
            if relative != f"objects/{digest}.json":
                fail(f"object path does not match event in {relative}")
            objects.add(key)
            continue

        fail(f"unknown event kind in {relative}")

    return accounts, objects


def write_replay_artifacts(accounts: set[str], objects: set[str], output_sql: Path, delete_directory: Path) -> None:
    statements = ["BEGIN;"]
    for user_id in sorted(accounts):
        statements.append(f"DELETE FROM files WHERE uploaded_by = '{user_id}'::uuid;")
        statements.append(f"DELETE FROM users WHERE id = '{user_id}'::uuid;")
    statements.extend(f"DELETE FROM files WHERE storage_path = '{key}';" for key in sorted(objects))
    statements.append("COMMIT;")
    output_sql.write_text("\n".join(statements) + "\n", encoding="utf-8")

    delete_directory.mkdir(mode=0o700)
    write_delete_batches(objects, delete_directory)


def read_delete_batch_keys(delete_directory: Path) -> set[str]:
    if delete_directory.is_symlink() or not delete_directory.is_dir():
        fail("S3 deletion batch directory is missing or unsafe")
    objects: set[str] = set()
    for path in sorted(delete_directory.iterdir()):
        if path.is_symlink() or not path.is_file() or not re.fullmatch(r"delete-[0-9]{6}\.json", path.name):
            fail(f"unexpected S3 deletion batch in {path.name}")
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as error:
            fail(f"cannot read S3 deletion batch {path.name}: {error}")
        batch = payload.get("Objects") if isinstance(payload, dict) else None
        if not isinstance(batch, list):
            fail(f"invalid S3 deletion batch in {path.name}")
        for item in batch:
            if not isinstance(item, dict):
                fail(f"invalid S3 deletion key in {path.name}")
            objects.add(validate_storage_key(item.get("Key"), path.name))
    return objects


def write_delete_batches(objects: set[str], delete_directory: Path) -> None:
    if delete_directory.is_symlink() or not delete_directory.is_dir():
        fail("S3 deletion batch directory is missing or unsafe")
    for path in sorted(delete_directory.iterdir()):
        if path.is_symlink() or not path.is_file() or not re.fullmatch(r"delete-[0-9]{6}\.json", path.name):
            fail(f"unexpected S3 deletion batch in {path.name}")
        path.unlink()
    sorted_objects = sorted(objects)
    for batch_index in range(0, len(sorted_objects), DELETE_BATCH_SIZE):
        batch = sorted_objects[batch_index : batch_index + DELETE_BATCH_SIZE]
        payload = {"Objects": [{"Key": key} for key in batch], "Quiet": True}
        batch_path = delete_directory / f"delete-{batch_index // DELETE_BATCH_SIZE + 1:06}.json"
        batch_path.write_text(json.dumps(payload, separators=(",", ":")) + "\n", encoding="utf-8")


def prepare_outbox_replay_artifacts(
    encoded_paths_file: Path,
    tombstone_directory: Path,
    delete_directory: Path,
    completion_sql_file: Path,
) -> None:
    if encoded_paths_file.is_symlink() or not encoded_paths_file.is_file():
        fail("database deletion outbox export is missing or unsafe")
    try:
        encoded_paths = encoded_paths_file.read_text(encoding="ascii").splitlines()
    except (OSError, UnicodeError) as error:
        fail(f"cannot read database deletion outbox export: {error}")

    queued_objects: set[str] = set()
    for encoded_path in encoded_paths:
        if not HEX_PATH_PATTERN.fullmatch(encoded_path):
            fail("database deletion outbox contains an invalid encoded storage key")
        try:
            key = bytes.fromhex(encoded_path).decode("utf-8")
        except (ValueError, UnicodeError) as error:
            fail(f"database deletion outbox contains an invalid storage key: {error}")
        queued_objects.add(validate_storage_key(key, "database deletion outbox"))

    if tombstone_directory.is_symlink() or tombstone_directory.exists():
        fail("recovery tombstone staging directory already exists or is unsafe")
    tombstone_objects = tombstone_directory / "objects"
    tombstone_objects.mkdir(parents=True, mode=0o700)
    created_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    for key in sorted(queued_objects):
        digest = hashlib.sha256(key.encode("utf-8")).hexdigest()
        event = {
            "version": 1,
            "kind": "object",
            "storage_path": key,
            "created_at_utc": created_at,
        }
        (tombstone_objects / f"{digest}.json").write_text(
            json.dumps(event, separators=(",", ":")) + "\n", encoding="utf-8"
        )

    combined_objects = read_delete_batch_keys(delete_directory) | queued_objects
    write_delete_batches(combined_objects, delete_directory)
    statements = ["BEGIN;"]
    statements.extend(
        f"DELETE FROM file_storage_deletions WHERE storage_path = '{key}';" for key in sorted(queued_objects)
    )
    statements.append("COMMIT;")
    completion_sql_file.write_text("\n".join(statements) + "\n", encoding="utf-8")


def main() -> None:
    if len(sys.argv) == 6 and sys.argv[1] == "--apply-outbox":
        prepare_outbox_replay_artifacts(
            Path(sys.argv[2]), Path(sys.argv[3]), Path(sys.argv[4]), Path(sys.argv[5])
        )
        return
    if len(sys.argv) != 4:
        raise SystemExit(
            "usage: apply-deletion-tombstones.py JOURNAL_DIRECTORY OUTPUT_SQL DELETE_OBJECTS_DIRECTORY\n"
            "   or: apply-deletion-tombstones.py --apply-outbox HEX_PATHS_FILE TOMBSTONE_DIRECTORY DELETE_OBJECTS_DIRECTORY COMPLETION_SQL_FILE"
        )
    directory = Path(sys.argv[1])
    output_sql = Path(sys.argv[2])
    delete_directory = Path(sys.argv[3])
    accounts, objects = load_tombstones(directory)
    write_replay_artifacts(accounts, objects, output_sql, delete_directory)


if __name__ == "__main__":
    main()
