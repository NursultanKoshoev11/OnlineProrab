#!/usr/bin/env python3
"""Validate STROY's first-party iOS privacy manifest and packaged copy."""

from __future__ import annotations

import argparse
import plistlib
from pathlib import Path
import sys


EXPECTED_DATA_TYPES = {
    "NSPrivacyCollectedDataTypePhoneNumber",
    "NSPrivacyCollectedDataTypeUserID",
    "NSPrivacyCollectedDataTypeOtherUserContent",
    "NSPrivacyCollectedDataTypeSearchHistory",
    "NSPrivacyCollectedDataTypeOtherFinancialInfo",
    "NSPrivacyCollectedDataTypePhotosorVideos",
    "NSPrivacyCollectedDataTypeAudioData",
}
APP_FUNCTIONALITY = "NSPrivacyCollectedDataTypePurposeAppFunctionality"


def load_manifest(path: Path) -> dict:
    try:
        with path.open("rb") as source:
            value = plistlib.load(source)
    except (OSError, plistlib.InvalidFileException) as error:
        raise ValueError(f"cannot read privacy manifest {path}: {error}") from error
    if not isinstance(value, dict):
        raise ValueError(f"privacy manifest must be a plist dictionary: {path}")
    return value


def validate(value: dict) -> None:
    if value.get("NSPrivacyTracking") is not False:
        raise ValueError("NSPrivacyTracking must be false")
    if value.get("NSPrivacyTrackingDomains") != []:
        raise ValueError("NSPrivacyTrackingDomains must be empty")
    if value.get("NSPrivacyAccessedAPITypes") != []:
        raise ValueError("review required-reason API declarations before changing this check")

    entries = value.get("NSPrivacyCollectedDataTypes")
    if not isinstance(entries, list):
        raise ValueError("NSPrivacyCollectedDataTypes must be an array")
    by_type = {entry.get("NSPrivacyCollectedDataType"): entry for entry in entries}
    if set(by_type) != EXPECTED_DATA_TYPES:
        raise ValueError(
            "collected data types differ from the reviewed inventory: "
            f"{sorted(by_type)}"
        )
    for data_type, entry in by_type.items():
        if entry.get("NSPrivacyCollectedDataTypeTracking") is not False:
            raise ValueError(f"tracking must be false for {data_type}")
        if entry.get("NSPrivacyCollectedDataTypePurposes") != [APP_FUNCTIONALITY]:
            raise ValueError(f"unexpected purpose for {data_type}")
        expected_linked = data_type != "NSPrivacyCollectedDataTypeAudioData"
        if entry.get("NSPrivacyCollectedDataTypeLinked") is not expected_linked:
            raise ValueError(f"unexpected user-linkage declaration for {data_type}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--app-bundle",
        type=Path,
        help="also verify that the compiled app contains the same manifest",
    )
    args = parser.parse_args()

    manifest_path = Path(__file__).resolve().parents[1] / "ios" / "Runner" / "PrivacyInfo.xcprivacy"
    try:
        source = load_manifest(manifest_path)
        validate(source)
        if args.app_bundle is not None:
            packaged_path = args.app_bundle / "PrivacyInfo.xcprivacy"
            packaged = load_manifest(packaged_path)
            validate(packaged)
            if packaged != source:
                raise ValueError("compiled app privacy manifest differs from the reviewed source")
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1
    print("STROY iOS privacy manifest is valid and packaged as expected")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
