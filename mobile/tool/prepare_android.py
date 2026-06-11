from pathlib import Path
import subprocess


def main() -> None:
    android_dir = Path("android")
    if not android_dir.exists():
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
        break
    else:
        raise RuntimeError("Android app Gradle file was not generated")

    manifest = Path("android/app/src/main/AndroidManifest.xml")
    if manifest.exists():
        text = manifest.read_text(encoding="utf-8")
        application_tag = "<application"
        if "android:allowBackup=" not in text and application_tag in text:
            text = text.replace(
                application_tag,
                '<application\n        android:allowBackup="false"\n        android:fullBackupContent="false"',
                1,
            )
        manifest.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    main()
