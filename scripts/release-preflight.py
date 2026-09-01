#!/usr/bin/env python3
# Aagedal Media Player
# Copyright © 2026 Truls Aagedal
# SPDX-License-Identifier: GPL-3.0-or-later

"""Validate release metadata and artifacts before publishing.

The source-tree checks intentionally avoid network access. They verify that the
candidate is newer than the public appcast, that all release metadata agrees,
and that the bundled ffmpeg is the reviewed Apple Silicon artifact. Passing an
exported app adds code-signing, bundle-version, and architecture checks.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import plistlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parent.parent
PROJECT_FILE = ROOT / "Aagedal Media Player.xcodeproj" / "project.pbxproj"
SCHEME_FILE = (
    ROOT
    / "Aagedal Media Player.xcodeproj"
    / "xcshareddata"
    / "xcschemes"
    / "Aagedal Media Player.xcscheme"
)
INFO_PLIST = ROOT / "Aagedal Media Player" / "Info.plist"
ENTITLEMENTS = ROOT / "Aagedal Media Player" / "Aagedal_Media_Player.entitlements"
FFMPEG = ROOT / "Aagedal Media Player" / "Binaries" / "ffmpeg"
FFMPEG_CHECKSUM = ROOT / "checksums" / "ffmpeg.sha256"
APPCAST = ROOT / "appcast.xml"
CHANGELOG = ROOT / "CHANGELOG.md"

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
SPARKLE = f"{{{SPARKLE_NS}}}"
EXPECTED_TEAM_ID = "3R5QGG9DW6"
EXPECTED_REPOSITORY = "aagedal/Aagedal-Media-Player"
EXPECTED_FEED_URL = (
    "https://raw.githubusercontent.com/"
    f"{EXPECTED_REPOSITORY}/main/appcast.xml"
)


class Validation:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.checks = 0

    def require(self, condition: bool, message: str) -> None:
        self.checks += 1
        if not condition:
            self.errors.append(message)

    def equal(self, actual: object, expected: object, label: str) -> None:
        self.require(actual == expected, f"{label}: expected {expected!r}, found {actual!r}")


@dataclass(frozen=True, order=True)
class Version:
    components: tuple[int, ...]

    @classmethod
    def parse(cls, value: str, label: str) -> "Version":
        if not re.fullmatch(r"\d+(?:\.\d+)*", value):
            raise ValueError(f"{label} must contain only dot-separated integers: {value!r}")
        return cls(tuple(int(component) for component in value.split(".")))


@dataclass(frozen=True)
class AppcastItem:
    version: str
    build: int
    title: str
    minimum_system_version: str
    url: str
    length: str
    signature: str


def unique_project_setting(project: str, name: str, validation: Validation) -> str:
    values = set(re.findall(rf"\b{re.escape(name)} = ([^;]+);", project))
    validation.require(bool(values), f"project has no {name} setting")
    validation.require(len(values) <= 1, f"project has inconsistent {name} settings: {sorted(values)}")
    return next(iter(values), "")


def decode_base64(value: str, expected_size: int, label: str, validation: Validation) -> None:
    try:
        decoded = base64.b64decode(value, validate=True)
    except ValueError:
        validation.require(False, f"{label} is not valid Base64")
        return
    validation.equal(len(decoded), expected_size, f"{label} decoded byte count")


def parse_appcast(path: Path, validation: Validation) -> list[AppcastItem]:
    try:
        root = ET.parse(path).getroot()
    except (ET.ParseError, OSError) as error:
        validation.require(False, f"cannot parse {path}: {error}")
        return []

    channel = root.find("channel")
    validation.require(channel is not None, "appcast has no channel")
    if channel is None:
        return []
    validation.equal(channel.findtext("title"), "Aagedal Media Player", "appcast channel title")
    validation.equal(
        channel.findtext("link"),
        f"https://github.com/{EXPECTED_REPOSITORY}",
        "appcast channel link",
    )

    items: list[AppcastItem] = []
    for element in channel.findall("item"):
        enclosure = element.find("enclosure")
        try:
            item = AppcastItem(
                version=(element.findtext(f"{SPARKLE}shortVersionString") or "").strip(),
                build=int((element.findtext(f"{SPARKLE}version") or "0").strip()),
                title=(element.findtext("title") or "").strip(),
                minimum_system_version=(
                    element.findtext(f"{SPARKLE}minimumSystemVersion") or ""
                ).strip(),
                url=enclosure.attrib.get("url", "") if enclosure is not None else "",
                length=enclosure.attrib.get("length", "") if enclosure is not None else "",
                signature=(
                    enclosure.attrib.get(f"{SPARKLE}edSignature", "")
                    if enclosure is not None
                    else ""
                ),
            )
        except ValueError:
            validation.require(False, "appcast contains a non-integer sparkle:version")
            continue
        items.append(item)
    validation.require(bool(items), "appcast contains no release items")
    return items


def command(*arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(arguments, text=True, capture_output=True, check=False)


def validate_appcast_items(
    items: list[AppcastItem], deployment_target: str, validation: Validation
) -> None:
    validation.equal(len({item.version for item in items}), len(items), "unique appcast versions")
    validation.equal(len({item.build for item in items}), len(items), "unique appcast builds")
    validation.equal(
        [item.build for item in items],
        sorted((item.build for item in items), reverse=True),
        "appcast newest-first build order",
    )
    try:
        versions = [Version.parse(item.version, "appcast version") for item in items]
        validation.equal(versions, sorted(versions, reverse=True), "appcast newest-first version order")
    except ValueError as error:
        validation.require(False, str(error))

    for item in items:
        label = f"appcast {item.version} ({item.build})"
        try:
            Version.parse(item.version, f"{label} version")
        except ValueError as error:
            validation.require(False, str(error))
        validation.equal(item.title, f"Version {item.version}", f"{label} title")
        validation.equal(
            item.minimum_system_version,
            deployment_target,
            f"{label} minimum system version",
        )
        validation.require(item.length.isdigit() and int(item.length) > 0, f"{label} length is invalid")
        decode_base64(item.signature, 64, f"{label} EdDSA signature", validation)

        parsed_url = urlparse(item.url)
        expected_name = f"Aagedal_Media_Player_{item.version.replace('.', '-')}.zip"
        expected_path = f"/{EXPECTED_REPOSITORY}/releases/download/{item.version}/{expected_name}"
        validation.equal(parsed_url.scheme, "https", f"{label} enclosure URL scheme")
        validation.equal(parsed_url.netloc, "github.com", f"{label} enclosure URL host")
        validation.equal(parsed_url.path, expected_path, f"{label} enclosure URL path")


def validate_ffmpeg(validation: Validation) -> None:
    validation.require(FFMPEG.is_file(), f"bundled ffmpeg is missing: {FFMPEG}")
    if not FFMPEG.is_file():
        return
    validation.require(bool(FFMPEG.stat().st_mode & 0o111), "bundled ffmpeg is not executable")

    checksum_text = FFMPEG_CHECKSUM.read_text().strip() if FFMPEG_CHECKSUM.is_file() else ""
    match = re.fullmatch(r"([0-9a-f]{64})\s+ffmpeg", checksum_text)
    validation.require(match is not None, "ffmpeg.sha256 must contain '<sha256>  ffmpeg'")
    actual_hash = hashlib.sha256(FFMPEG.read_bytes()).hexdigest()
    if match:
        validation.equal(actual_hash, match.group(1), "bundled ffmpeg SHA-256")

    result = command("/usr/bin/lipo", "-archs", str(FFMPEG))
    validation.equal(result.returncode, 0, "lipo ffmpeg inspection exit status")
    if result.returncode == 0:
        validation.equal(result.stdout.strip(), "arm64", "bundled ffmpeg architecture")

    result = command("/usr/bin/codesign", "--verify", "--strict", "--verbose=2", str(FFMPEG))
    signature_error = (result.stderr or result.stdout).strip()
    validation.require(
        result.returncode == 0,
        "bundled ffmpeg strict code-signature verification failed"
        + (f": {signature_error}" if signature_error else ""),
    )
    details = command("/usr/bin/codesign", "-dvvv", str(FFMPEG))
    signature_details = details.stderr + details.stdout
    validation.require(
        f"TeamIdentifier={EXPECTED_TEAM_ID}" in signature_details,
        f"bundled ffmpeg is not signed by team {EXPECTED_TEAM_ID}",
    )
    validation.require(
        "Authority=Developer ID Application:" in signature_details,
        "bundled ffmpeg does not have a Developer ID Application signature",
    )
    validation.require(
        "flags=0x10000(runtime)" in signature_details,
        "bundled ffmpeg lacks hardened runtime",
    )
    validation.require("Timestamp=" in signature_details, "bundled ffmpeg lacks a secure timestamp")

    capability_commands = {
        "decoder": ("-decoders", ("aac", "flac", "pcm_f32le")),
        "encoder": ("-encoders", ("pcm_f32le",)),
        "muxer": ("-muxers", ("f32le", "null")),
        "filter": ("-filters", ("ebur128",)),
    }
    for capability, (option, required_names) in capability_commands.items():
        result = command(str(FFMPEG), "-hide_banner", option)
        validation.equal(result.returncode, 0, f"ffmpeg {capability} listing exit status")
        for name in required_names:
            validation.require(
                re.search(rf"(?m)^\s*[A-Z.]+\s+{re.escape(name)}(?:\s|$)", result.stdout)
                is not None,
                f"bundled ffmpeg lacks required {capability} {name}",
            )


def validate_scheme(validation: Validation) -> None:
    try:
        launch = ET.parse(SCHEME_FILE).getroot().find("LaunchAction")
    except (ET.ParseError, OSError) as error:
        validation.require(False, f"cannot parse shared scheme: {error}")
        return
    validation.require(launch is not None, "shared scheme has no LaunchAction")
    if launch is None:
        return
    # Xcode serializes the disabled Metal API Validation choice as mode "1".
    validation.equal(
        launch.attrib.get("enableGPUValidationMode"),
        "1",
        "shared scheme Metal API Validation disabled mode",
    )
    validation.require(
        launch.attrib.get("disableMainThreadChecker") != "YES",
        "Main Thread Checker must remain enabled",
    )
    validation.require(
        launch.attrib.get("disablePerformanceAntipatternChecker") != "YES",
        "Thread Performance Checker must remain enabled",
    )


def validate_exported_app(
    app: Path, version: str, build: int, validation: Validation
) -> None:
    validation.require(app.is_dir(), f"exported app does not exist: {app}")
    if not app.is_dir():
        return

    app_info_path = app / "Contents" / "Info.plist"
    try:
        with app_info_path.open("rb") as file:
            app_info = plistlib.load(file)
    except (OSError, plistlib.InvalidFileException) as error:
        validation.require(False, f"cannot read exported app Info.plist: {error}")
        return
    validation.equal(app_info.get("CFBundleShortVersionString"), version, "exported app version")
    validation.equal(str(app_info.get("CFBundleVersion", "")), str(build), "exported app build")

    executable_name = app_info.get("CFBundleExecutable", "Aagedal Media Player")
    executable = app / "Contents" / "MacOS" / executable_name
    result = command("/usr/bin/lipo", "-archs", str(executable))
    validation.equal(result.returncode, 0, "lipo exported executable inspection exit status")
    if result.returncode == 0:
        validation.equal(result.stdout.strip(), "arm64", "exported app architecture")

    result = command("/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app))
    signature_error = (result.stderr or result.stdout).strip()
    validation.require(
        result.returncode == 0,
        "exported app strict code-signature verification failed"
        + (f": {signature_error}" if signature_error else ""),
    )
    details = command("/usr/bin/codesign", "-dvvv", str(app))
    signature_details = details.stderr + details.stdout
    validation.require(
        f"TeamIdentifier={EXPECTED_TEAM_ID}" in signature_details,
        f"exported app is not signed by team {EXPECTED_TEAM_ID}",
    )
    validation.require(
        "Authority=Developer ID Application:" in signature_details,
        "exported app does not have a Developer ID Application signature",
    )
    validation.require("flags=0x10000(runtime)" in signature_details, "exported app lacks hardened runtime")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", help="candidate marketing version (defaults to project setting)")
    parser.add_argument("--build", type=int, help="candidate build number (defaults to project setting)")
    parser.add_argument(
        "--state",
        choices=("candidate", "published"),
        default="candidate",
        help="candidate must be newer than the appcast; published must match its newest item",
    )
    parser.add_argument("--app", type=Path, help="exported .app to verify")
    parser.add_argument(
        "--appcast",
        type=Path,
        default=APPCAST,
        help="appcast to verify (used by release.sh to validate a pending update)",
    )
    arguments = parser.parse_args()
    validation = Validation()

    project = PROJECT_FILE.read_text()
    project_version = unique_project_setting(project, "MARKETING_VERSION", validation)
    project_build_text = unique_project_setting(project, "CURRENT_PROJECT_VERSION", validation)
    deployment_target = unique_project_setting(project, "MACOSX_DEPLOYMENT_TARGET", validation)
    architectures = unique_project_setting(project, "ARCHS", validation)
    validation.equal(architectures, "arm64", "project architecture")
    validation.require("ENABLE_HARDENED_RUNTIME = YES;" in project, "hardened runtime is not enabled")
    validation.require("ENABLE_APP_SANDBOX = NO;" in project, "App Sandbox decision changed without review")
    validation.require("CODE_SIGN_STYLE = Automatic;" in project, "automatic code signing is not configured")

    version = arguments.version or project_version
    try:
        parsed_version = Version.parse(version, "candidate version")
    except ValueError as error:
        validation.require(False, str(error))
        parsed_version = Version(())
    try:
        project_build = int(project_build_text)
    except ValueError:
        validation.require(False, f"project build is not an integer: {project_build_text!r}")
        project_build = 0
    build = arguments.build if arguments.build is not None else project_build
    validation.require(build > 0, "candidate build must be a positive integer")

    changelog = CHANGELOG.read_text()
    validation.require(
        re.search(rf"^## \[{re.escape(version)}\](?:\s|$)", changelog, re.MULTILINE) is not None,
        f"CHANGELOG.md has no section for [{version}]",
    )

    with INFO_PLIST.open("rb") as file:
        info = plistlib.load(file)
    validation.equal(info.get("SUFeedURL"), EXPECTED_FEED_URL, "Sparkle feed URL")
    public_key = str(info.get("SUPublicEDKey", ""))
    decode_base64(public_key, 32, "Sparkle public EdDSA key", validation)

    with ENTITLEMENTS.open("rb") as file:
        entitlements = plistlib.load(file)
    validation.equal(
        entitlements,
        {"com.apple.security.cs.disable-library-validation": True},
        "release entitlements",
    )

    items = parse_appcast(arguments.appcast.resolve(), validation)
    validate_appcast_items(items, deployment_target, validation)
    for item in items:
        validation.require(
            re.search(rf"^## \[{re.escape(item.version)}\](?:\s|$)", changelog, re.MULTILINE)
            is not None,
            f"CHANGELOG.md has no section for published appcast version [{item.version}]",
        )
    if items:
        newest = max(items, key=lambda item: item.build)
        try:
            newest_version = Version.parse(newest.version, "newest appcast version")
        except ValueError as error:
            validation.require(False, str(error))
            newest_version = Version(())
        if arguments.state == "candidate":
            validation.require(
                parsed_version > newest_version,
                f"candidate version {version} must be newer than appcast version {newest.version}",
            )
            validation.require(
                build > newest.build,
                f"candidate build {build} must be newer than appcast build {newest.build}",
            )
        else:
            validation.equal(version, newest.version, "published appcast version")
            validation.equal(build, newest.build, "published appcast build")

    validate_scheme(validation)
    validate_ffmpeg(validation)
    if arguments.app:
        validate_exported_app(arguments.app.resolve(), version, build, validation)

    if validation.errors:
        print(f"Release preflight FAILED ({len(validation.errors)} error(s)):", file=sys.stderr)
        for error in validation.errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    artifact = f" and {arguments.app}" if arguments.app else ""
    print(
        f"Release preflight passed {validation.checks} checks for "
        f"{version} ({build}) [{arguments.state}]{artifact}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
