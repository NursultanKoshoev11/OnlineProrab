#!/usr/bin/env python3
"""Fail when the configured Android target SDK is below the Play policy floor."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--minimum", type=int, required=True)
    arguments = parser.parse_args()

    gradle_file = Path(__file__).parents[1] / "android" / "app" / "build.gradle.kts"
    contents = gradle_file.read_text(encoding="utf-8")
    match = re.search(r"(?m)^\s*targetSdk\s*=\s*(\d+)\s*$", contents)
    if match is None:
        print(f"Could not find a numeric targetSdk assignment in {gradle_file}.", file=sys.stderr)
        return 1

    target_sdk = int(match.group(1))
    if target_sdk < arguments.minimum:
        print(
            f"Android target SDK {target_sdk} is below the required minimum {arguments.minimum}.",
            file=sys.stderr,
        )
        return 1

    print(f"Android target SDK {target_sdk} meets the required minimum {arguments.minimum}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
