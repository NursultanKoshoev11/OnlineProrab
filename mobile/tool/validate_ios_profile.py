#!/usr/bin/env python3
"""Validate a CMS-decoded App Store provisioning profile."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import plistlib
import re
import sys
from pathlib import Path
from typing import Any


_TEAM_ID = re.compile(r"[A-Z0-9]{10}\Z")
_PROFILE_UUID = re.compile(
    r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\Z"
)
_BUNDLE_ID = re.compile(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+\Z")


class ProfileValidationError(ValueError):
    """Raised when a provisioning profile cannot sign this App Store app."""


def validate_profile(
    profile: dict[str, Any],
    *,
    team_id: str,
    bundle_id: str,
    now: datetime | None = None,
) -> str:
    if not _TEAM_ID.fullmatch(team_id):
        raise ProfileValidationError("team ID must contain 10 uppercase letters or digits")
    if not _BUNDLE_ID.fullmatch(bundle_id):
        raise ProfileValidationError("bundle ID is invalid")

    expiration = profile.get("ExpirationDate")
    if not isinstance(expiration, datetime):
        raise ProfileValidationError("profile has no valid expiration date")
    if expiration.tzinfo is None:
        expiration = expiration.replace(tzinfo=timezone.utc)
    current_time = now or datetime.now(timezone.utc)
    if current_time.tzinfo is None:
        current_time = current_time.replace(tzinfo=timezone.utc)
    if expiration <= current_time:
        raise ProfileValidationError("App Store provisioning profile is expired")

    team_identifiers = profile.get("TeamIdentifier")
    if not isinstance(team_identifiers, list) or team_id not in team_identifiers:
        raise ProfileValidationError("provisioning profile belongs to a different Apple team")

    prefixes = profile.get("ApplicationIdentifierPrefix")
    entitlements = profile.get("Entitlements")
    if not isinstance(prefixes, list) or not isinstance(entitlements, dict):
        raise ProfileValidationError("profile is missing application identifier data")
    application_identifier = entitlements.get("application-identifier")
    if not isinstance(application_identifier, str) or not any(
        application_identifier == f"{prefix}.{bundle_id}" for prefix in prefixes
    ):
        raise ProfileValidationError("provisioning profile does not match the app bundle ID")
    if entitlements.get("get-task-allow") is not False:
        raise ProfileValidationError("profile is not configured for App Store distribution")
    if profile.get("ProvisionedDevices") or profile.get("ProvisionsAllDevices"):
        raise ProfileValidationError("development, ad hoc, and enterprise profiles are not supported")

    profile_uuid = profile.get("UUID")
    if not isinstance(profile_uuid, str) or not _PROFILE_UUID.fullmatch(profile_uuid):
        raise ProfileValidationError("profile UUID is invalid")
    return profile_uuid


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", required=True, type=Path)
    parser.add_argument("--team-id", required=True)
    parser.add_argument("--bundle-id", required=True)
    args = parser.parse_args()

    try:
        with args.profile.open("rb") as stream:
            profile = plistlib.load(stream)
        if not isinstance(profile, dict):
            raise ProfileValidationError("decoded provisioning profile is not a dictionary")
        print(validate_profile(profile, team_id=args.team_id, bundle_id=args.bundle_id))
    except (OSError, plistlib.InvalidFileException, ProfileValidationError) as error:
        print(f"Invalid App Store provisioning profile: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
