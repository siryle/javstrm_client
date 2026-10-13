#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift run JavStrmVerification
build_directory="$(swift build --show-bin-path)"
swiftc -typecheck -swift-version 6 -I "$build_directory" -I "$build_directory/Modules" \
  JavStrm/App/AppSession.swift JavStrm/App/CredentialStore.swift
swiftc -frontend -parse JavStrm/App/*.swift JavStrm/UI/*.swift JavStrm/Features/*.swift
plutil -lint JavStrm/Resources/Info.plist JavStrm/Resources/PrivacyInfo.xcprivacy \
  JavStrm.xcodeproj/project.pbxproj
python3 - <<'PY'
from pathlib import Path
import json
import plistlib
import subprocess
import xml.etree.ElementTree as ET

root = Path.cwd()
for path in (root / "JavStrm/Resources").rglob("*.json"):
    json.loads(path.read_text())
ET.parse(root / "JavStrm.xcodeproj/xcshareddata/xcschemes/JavStrm.xcscheme")
ET.parse(root / "JavStrm.xcodeproj/project.xcworkspace/contents.xcworkspacedata")
data = subprocess.check_output(["plutil", "-convert", "xml1", "-o", "-", "JavStrm.xcodeproj/project.pbxproj"])
project = plistlib.loads(data)
objects = project["objects"]
referenced = {
    item["path"] for item in objects.values()
    if item.get("isa") == "PBXFileReference" and item.get("lastKnownFileType") == "sourcecode.swift"
}
actual = {str(p.relative_to(root)) for p in (root / "JavStrm").rglob("*.swift")}
assert referenced == actual, "Xcode source references do not match Swift files; regenerate the project."
assert (root / "JavStrm/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png").exists()
print("PASS: Xcode source references, scheme, asset catalogs and property lists")
PY
