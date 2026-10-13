#!/usr/bin/env python3
"""Inspect the IPA container and device build metadata; no extraction needed."""
import argparse
import hashlib
import json
import plistlib
from pathlib import Path
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument("ipa", type=Path)
expectation = parser.add_mutually_exclusive_group()
expectation.add_argument("--expect-unsigned", action="store_true")
expectation.add_argument("--expect-signed", action="store_true")
args = parser.parse_args()

with zipfile.ZipFile(args.ipa) as archive:
    corrupt = archive.testzip()
    if corrupt:
        raise SystemExit(f"Corrupt ZIP entry: {corrupt}")
    names = set(archive.namelist())
    prefix = "Payload/JavStrm.app/"
    info = plistlib.loads(archive.read(prefix + "Info.plist"))
    binary = prefix + info["CFBundleExecutable"]
    if binary not in names:
        raise SystemExit("The app executable is missing.")
    if info.get("DTPlatformName") != "iphoneos":
        raise SystemExit("This is not an iPhoneOS device build.")
    signature = prefix + "_CodeSignature/CodeResources" in names
    provisioning = prefix + "embedded.mobileprovision" in names
    if args.expect_unsigned and (signature or provisioning):
        raise SystemExit("Expected an unsigned app, but signing material is present.")
    if args.expect_signed and not (signature and provisioning):
        raise SystemExit("Expected a signed iOS app with a provisioning profile.")

digest = hashlib.sha256()
with args.ipa.open("rb") as package_file:
    for chunk in iter(lambda: package_file.read(1024 * 1024), b""):
        digest.update(chunk)

report = {
    "file": str(args.ipa.resolve()),
    "sha256": digest.hexdigest(),
    "bytes": args.ipa.stat().st_size,
    "bundle_id": info["CFBundleIdentifier"],
    "app_name": info.get("CFBundleDisplayName", info.get("CFBundleName")),
    "version": info["CFBundleShortVersionString"],
    "build": info["CFBundleVersion"],
    "minimum_os": info.get("MinimumOSVersion"),
    "platform": info["DTPlatformName"],
    "sdk": info.get("DTSDKName"),
    "signature_present": signature,
    "provisioning_profile_present": provisioning,
    "note": "Container validation only; signed builds also require codesign verification and a device install.",
}
report_path = args.ipa.with_suffix(".json")
report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
print(json.dumps(report, indent=2, ensure_ascii=False))
