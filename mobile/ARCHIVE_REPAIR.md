# Extraction recovery and compatibility

The original ZIP is intact. The first PowerShell extraction produced zero-filled working files; a later direct ZIP read recovered their original contents. The original ZIP was never modified.

Original legacy modules, documentation and tests have been restored. The app entry point opens the original redesign implementation and now sets readable Android system-bar colors. API configuration keeps the original production default and build-time override, with normalized URL paths.

Android wrapper files were generated from the installed Flutter SDK where needed. Debug builds no longer require production release-signing variables during Gradle configuration. The original cross-drive Kotlin cache workaround is present. Legacy screen calls were updated to the current repository and file-picker APIs, and static analysis now includes those previously excluded files.

The redesign and demo corrections are described in DESIGN_NOTES.md and QA_REPORT.md.
