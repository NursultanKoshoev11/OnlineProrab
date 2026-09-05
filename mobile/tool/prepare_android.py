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

    permissions = [
        '<uses-permission android:name="android.permission.INTERNET" />',
        '<uses-permission android:name="android.permission.RECORD_AUDIO" />',
    ]
    insertion = ""
    for permission in permissions:
        if permission not in text:
            insertion += f"\n    {permission}"
    if insertion:
        text = text[: manifest_close + 1] + insertion + text[manifest_close + 1 :]

    application_tag = "<application"
    application_index = text.find(application_tag)
    if application_index < 0:
        raise RuntimeError("Android application tag was not generated")

    recognition_action = 'android:name="android.speech.RecognitionService"'
    if recognition_action not in text:
        queries = (
            "    <queries>\n"
            "        <intent>\n"
            "            <action android:name=\"android.speech.RecognitionService\" />\n"
            "        </intent>\n"
            "    </queries>\n\n"
        )
        text = text[:application_index] + queries + text[application_index:]

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
