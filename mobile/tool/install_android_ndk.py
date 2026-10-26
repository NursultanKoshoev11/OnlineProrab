from __future__ import annotations

import os
import platform
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path


ANDROID_GRADLE_FILE = Path("android/app/build.gradle.kts")
INSTALL_ATTEMPTS = 3


def configured_ndk_version() -> str:
    text = ANDROID_GRADLE_FILE.read_text(encoding="utf-8")
    match = re.search(
        r'^\s*ndkVersion\s*=\s*"(?P<version>\d+\.\d+\.\d+)"\s*$',
        text,
        flags=re.MULTILINE,
    )
    if match is None:
        raise RuntimeError(f"Could not find a pinned NDK version in {ANDROID_GRADLE_FILE}")
    return match.group("version")


def sdk_root() -> Path:
    value = os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME")
    if not value:
        raise RuntimeError("ANDROID_SDK_ROOT or ANDROID_HOME must point to the Android SDK")
    root = Path(value).expanduser().resolve()
    if not root.is_dir():
        raise RuntimeError(f"Android SDK directory does not exist: {root}")
    return root


def sdkmanager_path(root: Path) -> Path:
    executable = "sdkmanager.bat" if os.name == "nt" else "sdkmanager"
    latest = root / "cmdline-tools" / "latest" / "bin" / executable
    if latest.is_file():
        return latest

    command_line_tools = root / "cmdline-tools"
    candidates = sorted(
        path
        for path in command_line_tools.glob(f"*/bin/{executable}")
        if path.is_file()
    )
    if not candidates:
        raise RuntimeError(f"Could not find {executable} under {command_line_tools}")
    return candidates[-1]


def host_ndk_compiler_paths(ndk_dir: Path) -> list[Path]:
    prebuilt = ndk_dir / "toolchains" / "llvm" / "prebuilt"
    host = platform.system()
    if host == "Linux":
        names = ["linux-x86_64"]
        executable = "clang"
    elif host == "Windows":
        names = ["windows-x86_64"]
        executable = "clang.exe"
    elif host == "Darwin":
        names = ["darwin-arm64", "darwin-x86_64"]
        executable = "clang"
    else:
        return []
    return [prebuilt / name / "bin" / executable for name in names]


def is_installed(root: Path, version: str) -> bool:
    ndk_dir = root / "ndk" / version
    properties = ndk_dir / "source.properties"
    if not properties.is_file():
        return False
    revisions = {
        line.strip()
        for line in properties.read_text(encoding="utf-8").splitlines()
        if line.strip().startswith("Pkg.Revision =")
    }
    return revisions == {f"Pkg.Revision = {version}"} and any(
        path.is_file() for path in host_ndk_compiler_paths(ndk_dir)
    )


def remove_partial_install(root: Path, version: str) -> None:
    ndk_parent = (root / "ndk").resolve()
    partial = ndk_parent / version
    if not partial.exists() and not partial.is_symlink():
        return
    resolved = partial.resolve()
    if resolved.parent != ndk_parent or resolved.name != version:
        raise RuntimeError(f"Refusing to remove NDK path outside the SDK: {resolved}")
    shutil.rmtree(resolved)


def main() -> int:
    version = configured_ndk_version()
    root = sdk_root()
    manager = sdkmanager_path(root)
    if is_installed(root, version):
        print(f"Android NDK {version} is installed and verified")
        return 0

    for attempt in range(1, INSTALL_ATTEMPTS + 1):
        print(f"Installing Android NDK {version} (attempt {attempt}/{INSTALL_ATTEMPTS})")
        result = subprocess.run(
            [str(manager), f"--sdk_root={root}", "--install", f"ndk;{version}"],
            check=False,
        )
        if result.returncode == 0 and is_installed(root, version):
            print(f"Android NDK {version} installed and verified")
            return 0

        print(f"Android NDK install attempt {attempt} did not produce a valid toolchain")
        remove_partial_install(root, version)
        if attempt < INSTALL_ATTEMPTS:
            time.sleep(attempt * 5)

    print(f"Failed to install a valid Android NDK {version} after {INSTALL_ATTEMPTS} attempts", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
