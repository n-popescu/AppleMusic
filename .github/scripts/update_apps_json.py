#!/usr/bin/env python3
"""Regenerates apps.json (the SideStore/AltStore source file) for the
current CI build. Reads RUN_NUMBER, COMMIT_SHA, IPA_SIZE, BUILD_DATE, and
MARKETING_VERSION from the environment (set by
.github/workflows/ios-build.yml) and writes the result to apps.json in the
current working directory.
"""
import json
import os

RUN_NUMBER = os.environ["RUN_NUMBER"]
COMMIT_SHA = os.environ["COMMIT_SHA"]
IPA_SIZE = int(os.environ["IPA_SIZE"])
BUILD_DATE = os.environ["BUILD_DATE"]
# Matches whatever MARKETING_VERSION was actually baked into this build (see
# ios-build.yml's build-unsigned-ipa job) — it auto-bumps every run now, so
# this must not be hardcoded or SideStore would show a version that doesn't
# match what Settings reports inside the app itself.
MARKETING_VERSION = os.environ["MARKETING_VERSION"]

data = {
    "name": "Lucent",
    "identifier": "com.lucent.source",
    "sourceURL": "https://raw.githubusercontent.com/n-popescu/AppleMusic/main/apps.json",
    "apps": [
        {
            "name": "Lucent",
            "bundleIdentifier": "com.lucent.app",
            "developerName": "n-popescu",
            "subtitle": "Sign into a different Apple Music account than your device's",
            "localizedDescription": (
                "A native SwiftUI Apple Music client that signs in through "
                "Apple's own music.apple.com — independent of whichever "
                "Apple ID this iPhone uses for iCloud. Unsigned build; "
                "SideStore/AltStore handles signing and installation."
            ),
            "iconURL": "https://raw.githubusercontent.com/n-popescu/AppleMusic/main/MusicGlass/MusicGlass/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png",
            "category": "music",
            "versions": [
                {
                    "version": MARKETING_VERSION,
                    "buildVersion": RUN_NUMBER,
                    "date": BUILD_DATE,
                    "size": IPA_SIZE,
                    "minOSVersion": "17.0",
                    "downloadURL": "https://github.com/n-popescu/AppleMusic/releases/download/v1.0.0/Lucent-1.0.0-unsigned.ipa",
                    "localizedDescription": "Build {} (commit {})".format(RUN_NUMBER, COMMIT_SHA[:7]),
                }
            ],
        }
    ],
}

with open("apps.json", "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
