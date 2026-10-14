#!/usr/bin/env python3
"""Validate durable deletion tombstones and emit safe SQL for database restore."""

import hashlib
import json
import re
import sys
from pathlib import Path, PurePosixPath

UUID_PATTERN = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
OBJECT_KEY_PATTERN = re.compile(r"^[A-Za-z0-9._/-]{1,512}$")


def fail(message: str) -> None:
    raise SystemExit(f"invalid deletion tombstone: {message}")


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
            key = event.get("storage_path")
            if not isinstance(key, str) or not OBJECT_KEY_PATTERN.fullmatch(key):
                fail(f"invalid storage key in {relative}")
            parts = key.split("/")
            if key.startswith("/") or "\\" in key or any(part in ("", ".", "..") for part in parts):
                fail(f"unsafe storage key in {relative}")
            if PurePosixPath(key).as_posix() != key:
                fail(f"noncanonical storage key in {relative}")
            digest = hashlib.sha256(key.encode("utf-8")).hexdigest()
            if relative != f"objects/{digest}.json":
                fail(f"object path does not match event in {relative}")
            objects.add(key)
            continue

        fail(f"unknown event kind in {relative}")

    return accounts, objects


def write_replay_artifacts(accounts: set[str], objects: set[str], output_sql: Path, delete_directory: Path) -> None:
    statements = ["BEGIN;"]
    statements.extend(f"DELETE FROM users WHERE id = '{user_id}'::uuid;" for user_id in sorted(accounts))
    statements.extend(f"DELETE FROM files WHERE storage_path = '{key}';" for key in sorted(objects))
    statements.append("COMMIT;")
    output_sql.write_text("\n".join(statements) + "\n", encoding="utf-8")

    delete_directory.mkdir(mode=0o700)
    sorted_objects = sorted(objects)
    for batch_index in range(0, len(sorted_objects), 1000):
        batch = sorted_objects[batch_index : batch_index + 1000]
        payload = {"Objects": [{"Key": key} for key in batch], "Quiet": True}
        batch_path = delete_directory / f"delete-{batch_index // 1000 + 1:06}.json"
        batch_path.write_text(json.dumps(payload, separators=(",", ":")) + "\n", encoding="utf-8")


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit("usage: apply-deletion-tombstones.py JOURNAL_DIRECTORY OUTPUT_SQL DELETE_OBJECTS_DIRECTORY")
    directory = Path(sys.argv[1])
    output_sql = Path(sys.argv[2])
    delete_directory = Path(sys.argv[3])
    accounts, objects = load_tombstones(directory)
    write_replay_artifacts(accounts, objects, output_sql, delete_directory)


if __name__ == "__main__":
    main()
