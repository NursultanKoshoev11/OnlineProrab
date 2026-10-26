from pathlib import Path
import re
import sys


DEFAULT_BUNDLE_ID = "kg.com.stroy.app"
BUNDLE_ID_PATTERN = re.compile(r"[A-Za-z][A-Za-z0-9-]*(?:\.[A-Za-z][A-Za-z0-9-]*)+")
PRODUCT_BUNDLE_PATTERN = re.compile(
    r"PRODUCT_BUNDLE_IDENTIFIER = ([A-Za-z][A-Za-z0-9-]*(?:\.[A-Za-z][A-Za-z0-9-]*)+);"
)


def configure_bundle_id(bundle_id: str) -> None:
    if len(bundle_id) > 255 or BUNDLE_ID_PATTERN.fullmatch(bundle_id) is None:
        raise ValueError("iOS bundle ID must be a reverse-DNS identifier without wildcards")

    project_file = Path(__file__).resolve().parents[1] / "ios" / "Runner.xcodeproj" / "project.pbxproj"
    text = project_file.read_bytes().decode("utf-8")
    identifiers = [match.group(1) for match in PRODUCT_BUNDLE_PATTERN.finditer(text)]
    app_ids = {identifier for identifier in identifiers if not identifier.endswith(".RunnerTests")}
    test_ids = {
        identifier.removesuffix(".RunnerTests")
        for identifier in identifiers
        if identifier.endswith(".RunnerTests")
    }
    if len(identifiers) != 6 or len(app_ids) != 1 or len(test_ids) != 1 or app_ids != test_ids:
        raise RuntimeError("Runner.xcodeproj bundle ID settings did not match the expected template")

    current_bundle_id = next(iter(app_ids))
    if current_bundle_id == bundle_id:
        return

    text = PRODUCT_BUNDLE_PATTERN.sub(
        lambda match: (
            f"PRODUCT_BUNDLE_IDENTIFIER = {bundle_id}.RunnerTests;"
            if match.group(1).endswith(".RunnerTests")
            else f"PRODUCT_BUNDLE_IDENTIFIER = {bundle_id};"
        ),
        text,
    )

    project_file.write_bytes(text.encode("utf-8"))


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: python3 tool/configure_ios_bundle_id.py <bundle-id>")
    try:
        configure_bundle_id(sys.argv[1].strip())
    except (OSError, RuntimeError, ValueError) as error:
        raise SystemExit(str(error)) from error


if __name__ == "__main__":
    main()
