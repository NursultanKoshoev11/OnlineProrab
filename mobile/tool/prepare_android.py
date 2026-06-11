from pathlib import Path
import subprocess


def ensure_android_platform() -> None:
    android_dir = Path("android")
    if android_dir.exists():
        return
    subprocess.run(
        [
            "flutter",
            "create",
            "--platforms=android",
            "--org=com.onlineprorab",
            "--project-name=online_prorab",
            ".",
        ],
        check=True,
    )


def configure_min_sdk() -> None:
    candidates = [
        Path("android/app/build.gradle.kts"),
        Path("android/app/build.gradle"),
    ]
    for path in candidates:
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        replacements = {
            "minSdk = flutter.minSdkVersion": "minSdk = 23",
            "minSdkVersion flutter.minSdkVersion": "minSdkVersion 23",
        }
        for old, new in replacements.items():
            text = text.replace(old, new)
        path.write_text(text, encoding="utf-8")
        return
    raise RuntimeError("Android app Gradle file was not generated")


def configure_main_manifest() -> None:
    manifest = Path("android/app/src/main/AndroidManifest.xml")
    if not manifest.exists():
        raise RuntimeError("Android main manifest was not generated")

    text = manifest.read_text(encoding="utf-8")
    manifest_tag = "<manifest"
    manifest_index = text.find(manifest_tag)
    if manifest_index < 0:
        raise RuntimeError("Android manifest root tag is invalid")
    manifest_close = text.find(">", manifest_index)
    if manifest_close < 0:
        raise RuntimeError("Android manifest root tag is not closed")

    permission = '<uses-permission android:name="android.permission.INTERNET" />'
    if permission not in text:
        text = (
            text[: manifest_close + 1]
            + f"\n    {permission}"
            + text[manifest_close + 1 :]
        )

    application_tag = "<application"
    if application_tag not in text:
        raise RuntimeError("Android application tag was not generated")

    attributes = {
        "android:allowBackup": "false",
        "android:fullBackupContent": "false",
        "android:usesCleartextTraffic": "false",
    }
    for attribute, value in attributes.items():
        if f"{attribute}=" in text:
            continue
        text = text.replace(
            application_tag,
            f'{application_tag}\n        {attribute}="{value}"',
            1,
        )

    manifest.write_text(text, encoding="utf-8")


def main() -> None:
    ensure_android_platform()
    configure_min_sdk()
    configure_main_manifest()


if __name__ == "__main__":
    main()
