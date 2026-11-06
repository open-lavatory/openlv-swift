#!/usr/bin/env python3
"""Prepare a complete Apple XCFramework ZIP and a remote SwiftPM manifest.

This only creates local release candidates; it never publishes or edits Package.swift.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import stat
import subprocess
import tempfile
from urllib.parse import urlsplit
import zipfile


ROOT = Path(__file__).resolve().parent.parent
ARCHIVE_NAME = "OpenLVFFI.xcframework.zip"
LOCAL_TARGET = '.binaryTarget(name: "OpenLVFFI", path: "Native/OpenLVFFI.xcframework")'
REQUIRED_SLICES = {
    ("macos", ""): {"arm64", "x86_64"},
    ("ios", ""): {"arm64"},
    ("ios", "simulator"): {"arm64", "x86_64"},
}


def validate_url(url):
    parsed = urlsplit(url)
    if (
        parsed.scheme != "https" or not parsed.hostname
        or parsed.username is not None or parsed.password is not None
        or parsed.query or parsed.fragment
        or not parsed.path.endswith("/" + ARCHIVE_NAME)
        or not url.isascii() or any(c.isspace() or c in '\\"' for c in url)
    ):
        raise ValueError(f"Use an HTTPS release URL ending in /{ARCHIVE_NAME}, without credentials, query, or fragment.")


def child_path(parent, value):
    if not isinstance(value, str) or not value or Path(value).is_absolute() or ".." in Path(value).parts:
        raise ValueError(f"Invalid XCFramework relative path: {value!r}")
    path = parent / value
    if path.resolve() == parent.resolve() or not path.resolve().is_relative_to(parent.resolve()):
        raise ValueError(f"XCFramework path escapes its directory: {value!r}")
    return path


def archive_architectures(path):
    result = subprocess.run(
        ["xcrun", "lipo", "-archs", str(path)], check=True, capture_output=True, text=True
    )
    return set(result.stdout.split())


def validate_framework(bundle):
    if not bundle.is_dir():
        raise ValueError("Missing XCFramework; run ./scripts/build-native.sh --all first.")
    if bundle.is_symlink() or any(p.is_symlink() for p in bundle.rglob("*")):
        raise ValueError("Release XCFramework must not contain symbolic links.")
    with (bundle / "Info.plist").open("rb") as file:
        info = plistlib.load(file)
    if info.get("CFBundlePackageType") != "XFWK" or info.get("XCFrameworkFormatVersion") != "1.0":
        raise ValueError("Unsupported XCFramework metadata.")
    seen = set()
    identifiers = set()
    reference_headers = None
    for library in info.get("AvailableLibraries", []):
        key = (library.get("SupportedPlatform"), library.get("SupportedPlatformVariant", ""))
        expected = REQUIRED_SLICES.get(key)
        if expected is None or key in seen:
            raise ValueError(f"Unexpected or duplicate XCFramework slice: {key}")
        seen.add(key)
        architectures = library.get("SupportedArchitectures", [])
        if set(architectures) != expected or len(architectures) != len(expected):
            raise ValueError(f"Slice {key} requires architectures {sorted(expected)}.")
        identifier = library.get("LibraryIdentifier")
        directory = child_path(bundle, identifier)
        if identifier in identifiers:
            raise ValueError(f"Duplicate library identifier: {identifier}")
        identifiers.add(identifier)
        archive = child_path(directory, library.get("LibraryPath"))
        if archive.suffix != ".a" or not archive.is_file():
            raise ValueError(f"Missing static archive: {archive}")
        if archive_architectures(archive) != expected:
            raise ValueError(f"Archive architectures do not match metadata: {archive}")
        headers = child_path(directory, library.get("HeadersPath"))
        contents = tuple((headers / name).read_bytes() for name in ("OpenLVFFI.h", "module.modulemap"))
        if not all(contents):
            raise ValueError(f"Empty UniFFI headers: {headers}")
        if reference_headers is not None and contents != reference_headers:
            raise ValueError("UniFFI headers differ between XCFramework slices.")
        reference_headers = contents
    if seen != set(REQUIRED_SLICES):
        raise ValueError("Release requires universal macOS, iOS device, and universal iOS Simulator slices; run --all.")


def write_archive(bundle, destination):
    # Fixed timestamps, permissions, and order make identical input bytes reproducible.
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(bundle.rglob("*")):
            if not path.is_file():
                continue
            entry = zipfile.ZipInfo(str(Path(bundle.name) / path.relative_to(bundle)), (1980, 1, 1, 0, 0, 0))
            entry.create_system = 3
            entry.external_attr = (stat.S_IFREG | 0o644) << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            with path.open("rb") as source, archive.open(entry, "w", force_zip64=True) as target:
                shutil.copyfileobj(source, target)


def prepare_release(root, url, output):
    validate_url(url)
    source = (root / "Package.swift").read_text()
    if source.count(LOCAL_TARGET) != 1:
        raise ValueError("Expected one local OpenLVFFI target; review remote manifest generation.")
    bundle = root / "Native/OpenLVFFI.xcframework"
    if output.resolve() == root.resolve():
        raise ValueError("Release output must not overwrite the source package manifest.")
    if output.resolve().is_relative_to(bundle.resolve()):
        raise ValueError("Release output must be outside the XCFramework.")
    validate_framework(bundle)
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output) as temporary:
        staging = Path(temporary)
        archive = staging / ARCHIVE_NAME
        write_archive(bundle, archive)
        # SwiftPM's binary ZIP checksum is SHA-256 of the ZIP's exact bytes.
        digest = hashlib.sha256()
        with archive.open("rb") as file:
            for block in iter(lambda: file.read(1024 * 1024), b""):
                digest.update(block)
        checksum = digest.hexdigest()
        target = f'.binaryTarget(name: "OpenLVFFI", url: {json.dumps(url)}, checksum: "{checksum}")'
        (staging / "Package.swift").write_text(source.replace(LOCAL_TARGET, target))
        (staging / (ARCHIVE_NAME + ".sha256")).write_text(f"{checksum}  {ARCHIVE_NAME}\n")
        for path in staging.iterdir():
            path.replace(output / path.name)
    return checksum


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", required=True, help="Immutable HTTPS URL where the ZIP will be published")
    parser.add_argument("--output", type=Path, default=ROOT / ".native-build/release")
    args = parser.parse_args()
    try:
        checksum = prepare_release(ROOT, args.url, args.output)
    except (ValueError, OSError, plistlib.InvalidFileException, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Release preparation failed: {error}\n")
    print(f"Prepared {args.output / ARCHIVE_NAME}\nSwiftPM checksum: {checksum}")
    print(f"Remote manifest: {args.output / 'Package.swift'} (root Package.swift is unchanged)")


if __name__ == "__main__":
    main()
