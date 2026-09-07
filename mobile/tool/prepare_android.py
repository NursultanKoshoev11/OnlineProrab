from pathlib import Path
import re
import subprocess


def ensure_android_platform() -> None:
    android_dir = Path("android")
    ios_dir = Path("ios")
    if android_dir.exists() and ios_dir.exists():
        return
    subprocess.run(
        [
            "flutter",
            "create",
            "--platforms=android,ios",
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


def configure_app_labels() -> None:
    strings = Path("android/app/src/main/res/values/strings.xml")
    if strings.exists():
        text = strings.read_text(encoding="utf-8")
        text = re.sub(
            r'(<string\s+name="app_name">).*?(</string>)',
            r'\1STROY\2',
            text,
            count=1,
        )
        strings.write_text(text, encoding="utf-8")

    manifest = Path("android/app/src/main/AndroidManifest.xml")
    if manifest.exists():
        text = manifest.read_text(encoding="utf-8")
        text = re.sub(
            r'android:label="[^"]*"',
            'android:label="STROY"',
            text,
            count=1,
        )
        manifest.write_text(text, encoding="utf-8")

    plist = Path("ios/Runner/Info.plist")
    if plist.exists():
        text = plist.read_text(encoding="utf-8")
        text = re.sub(
            r'(<key>CFBundleDisplayName</key>\s*<string>).*?(</string>)',
            r'\1STROY\2',
            text,
            count=1,
        )
        text = re.sub(
            r'(<key>CFBundleName</key>\s*<string>).*?(</string>)',
            r'\1STROY\2',
            text,
            count=1,
        )
        plist.write_text(text, encoding="utf-8")


def configure_ios_printing() -> None:
    podfile = Path("ios/Podfile")
    if not podfile.exists():
        return
    text = podfile.read_text(encoding="utf-8")
    if "use_frameworks!" not in text:
        text = text.replace("target 'Runner' do", "target 'Runner' do\n  use_frameworks!")
        podfile.write_text(text, encoding="utf-8")


def main() -> None:
    ensure_android_platform()
    configure_min_sdk()
    configure_main_manifest()
    configure_app_labels()
    configure_ios_printing()


if __name__ == "__main__":
    main()
