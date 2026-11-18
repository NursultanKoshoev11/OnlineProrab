from pathlib import Path
import json
import re
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


def configure_firebase_android() -> None:
    """Create the build-only Google services file from firebase_options.dart.

    The app intentionally keeps Firebase configuration in Dart so the same
    options work for Android and iOS. The Android Google Services and
    Crashlytics Gradle plugins still need the Android Firebase App ID at build
    time to upload mappings and native symbols, so generate their public
    configuration without adding a credential to the repository.
    """
    options_path = Path("lib/firebase_options.dart")
    if not options_path.exists():
        raise RuntimeError("Firebase options file is missing")
    source = options_path.read_text(encoding="utf-8")

    def option(name: str) -> str:
        match = re.search(
            rf"^\s*{re.escape(name)}:\s*'([^']+)'", source, re.MULTILINE
        )
        if match is None:
            raise RuntimeError(f"Firebase Android option {name!r} is missing")
        return match.group(1)

    config = {
        "project_info": {
            "project_number": option("messagingSenderId"),
            "project_id": option("projectId"),
            "storage_bucket": option("storageBucket"),
        },
        "client": [
            {
                "client_info": {
                    "mobilesdk_app_id": option("appId"),
                    "android_client_info": {"package_name": "kg.com.stroy.app"},
                },
                "oauth_client": [],
                "api_key": [{"current_key": option("apiKey")}],
                "services": {
                    "appinvite_service": {"other_platform_oauth_client": []}
                },
            }
        ],
        "configuration_version": "1",
    }
    generated_path = Path("android/app/google-services.json")
    generated_path.write_text(
        json.dumps(config, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )


def configure_crashlytics_gradle() -> None:
    """Apply Firebase plugins to both checked-in and freshly generated Gradle files."""
    settings_candidates = [Path("android/settings.gradle.kts"), Path("android/settings.gradle")]
    settings_path = next((path for path in settings_candidates if path.exists()), None)
    if settings_path is None:
        raise RuntimeError("Android settings Gradle file was not generated")
    settings = settings_path.read_text(encoding="utf-8")
    settings_plugins = (
        '    id("com.google.gms.google-services") version "4.6.0" apply false\n'
        '    id("com.google.firebase.crashlytics") version "3.0.8" apply false\n'
    )
    if 'id("com.google.gms.google-services")' not in settings:
        settings = settings.replace("plugins {\n", "plugins {\n" + settings_plugins, 1)
    settings_path.write_text(settings, encoding="utf-8")

    app_candidates = [Path("android/app/build.gradle.kts"), Path("android/app/build.gradle")]
    app_path = next((path for path in app_candidates if path.exists()), None)
    if app_path is None:
        raise RuntimeError("Android app Gradle file was not generated")
    app = app_path.read_text(encoding="utf-8")
    if 'id("com.google.gms.google-services")' not in app:
        plugin_insertion = (
            '    id("com.google.gms.google-services")\n'
            '    id("com.google.firebase.crashlytics")\n'
        )
        for android_plugin in (
            '    id("com.android.application")\n',
            '    id "com.android.application"\n',
            "    id 'com.android.application'\n",
        ):
            if android_plugin in app:
                app = app.replace(android_plugin, android_plugin + plugin_insertion, 1)
                break
        else:
            raise RuntimeError("Android application plugin was not found")
    if app_path.suffix == ".kts":
        if "CrashlyticsExtension" not in app:
            app = app.replace(
                "plugins {\n",
                "import com.google.firebase.crashlytics.buildtools.gradle.CrashlyticsExtension\n\n"
                "plugins {\n",
                1,
            )
            app = app.replace(
                "        release {\n",
                "        release {\n"
                "            configure<CrashlyticsExtension> {\n"
                "                mappingFileUploadEnabled = true\n"
                "                nativeSymbolUploadEnabled = true\n"
                "            }\n",
                1,
            )
    elif "firebaseCrashlytics" not in app:
        app += (
            "\n\nfirebaseCrashlytics {\n"
            "    mappingFileUploadEnabled true\n"
            "    nativeSymbolUploadEnabled true\n"
            "}\n"
        )
    app_path.write_text(app, encoding="utf-8")


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
        if attribute == "android:usesCleartextTraffic" and f"{attribute}=" in text:
            text = re.sub(
                rf'{re.escape(attribute)}="[^"]*"',
                f'{attribute}="{value}"',
                text,
                count=1,
            )
            continue
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
    configure_firebase_android()
    configure_crashlytics_gradle()
    configure_main_manifest()
    configure_app_labels()
    configure_ios_printing()


if __name__ == "__main__":
    main()
