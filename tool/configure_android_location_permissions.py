#!/usr/bin/env python3
"""Add only the foreground location permissions required by Go-Ride's map picker.

The repository generates its Android platform during CI. Keeping this small,
idempotent patch in source ensures CI and local Android builds use the same
permission configuration without requesting background location access.
"""
from pathlib import Path
import sys


def main() -> int:
    manifest = Path("android/app/src/main/AndroidManifest.xml")
    if not manifest.is_file():
        print(
            f"Android manifest not found at {manifest}. "
            "Run 'flutter create --platforms=android --org com.goride .' first.",
            file=sys.stderr,
        )
        return 1

    content = manifest.read_text(encoding="utf-8")
    marker = "<application"
    marker_index = content.find(marker)
    if marker_index < 0:
        print(f"Could not find <application> in {manifest}.", file=sys.stderr)
        return 1

    required_permissions = (
        '<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />',
        '<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />',
    )
    missing = [item for item in required_permissions if item not in content]
    if not missing:
        print("Foreground location permissions already configured.")
        return 0

    line_start = content.rfind("\n", 0, marker_index) + 1
    insertion = "".join(f"    {permission}\n" for permission in missing)
    content = content[:line_start] + insertion + content[line_start:]
    manifest.write_text(content, encoding="utf-8")
    print("Configured foreground coarse and fine location permissions.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
