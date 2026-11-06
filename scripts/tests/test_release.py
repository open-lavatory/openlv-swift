"""Exercise release packaging with tiny real Mach-O archives, without full Xcode."""
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("prepare_release", ROOT / "scripts/prepare-release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
URL = "https://example.invalid/releases/0.1.0/OpenLVFFI.xcframework.zip"


class ReleaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.fixture.cleanup)
        cls.fixture_root = Path(cls.fixture.name)
        bundle = cls.fixture_root / "Native/OpenLVFFI.xcframework"
        bundle.mkdir(parents=True)
        (cls.fixture_root / "Package.swift").write_text((ROOT / "Package.swift").read_text())
        libraries = []
        for platform, variant, architectures, triple in [
            ("macos", "", ["arm64", "x86_64"], "apple-macos13.0"),
            ("ios", "", ["arm64"], "apple-ios16.0"),
            ("ios", "simulator", ["arm64", "x86_64"], "apple-ios16.0-simulator"),
        ]:
            identifier = "-".join(filter(None, [platform, "_".join(architectures), variant]))
            directory = bundle / identifier
            headers = directory / "Headers"
            headers.mkdir(parents=True)
            (headers / "OpenLVFFI.h").write_text("int smoke(void);\n")
            (headers / "module.modulemap").write_text('module OpenLVFFI { header "OpenLVFFI.h" export * }\n')
            archives = []
            for arch in architectures:
                obj = cls.fixture_root / f"{identifier}-{arch}.o"
                subprocess.run(
                    ["xcrun", "clang", "-target", f"{arch}-{triple}", "-c", "-x", "c", "-", "-o", str(obj)],
                    input="int smoke(void) { return 0; }\n", text=True, check=True, capture_output=True,
                )
                archive = obj.with_suffix(".a")
                subprocess.run(["xcrun", "ar", "rcs", str(archive), str(obj)], check=True, capture_output=True)
                archives.append(str(archive))
            subprocess.run(
                ["xcrun", "lipo", "-create", *archives, "-output", str(directory / "libopenlv_swift_ffi.a")],
                check=True, capture_output=True,
            )
            libraries.append(dict(
                LibraryIdentifier=identifier, LibraryPath="libopenlv_swift_ffi.a", HeadersPath="Headers",
                SupportedPlatform=platform, SupportedArchitectures=architectures,
                **({"SupportedPlatformVariant": variant} if variant else {}),
            ))
        with (bundle / "Info.plist").open("wb") as file:
            plistlib.dump(dict(CFBundlePackageType="XFWK", XCFrameworkFormatVersion="1.0", AvailableLibraries=libraries), file)

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        shutil.copytree(self.fixture_root / "Native", self.root / "Native")
        shutil.copy2(self.fixture_root / "Package.swift", self.root)
        self.bundle = self.root / "Native/OpenLVFFI.xcframework"
        self.output = self.root / "release"

    def change_metadata(self, change):
        path = self.bundle / "Info.plist"
        info = plistlib.loads(path.read_bytes())
        change(info["AvailableLibraries"])
        path.write_bytes(plistlib.dumps(info))

    def test_reproducible_zip_checksum_and_remote_manifest(self):
        original = (self.root / "Package.swift").read_bytes()
        checksum = release.prepare_release(self.root, URL, self.output)
        archive = self.output / release.ARCHIVE_NAME
        first = archive.read_bytes()
        self.assertEqual(checksum, hashlib.sha256(first).hexdigest())
        actual = subprocess.check_output(["swift", "package", "compute-checksum", str(archive)], text=True).strip()
        self.assertEqual(checksum, actual)
        self.assertEqual((self.root / "Package.swift").read_bytes(), original)
        manifest = (self.output / "Package.swift").read_text()
        self.assertIn(f'url: "{URL}", checksum: "{checksum}"', manifest)
        self.assertEqual(manifest.replace(f'.binaryTarget(name: "OpenLVFFI", url: "{URL}", checksum: "{checksum}")', release.LOCAL_TARGET), original.decode())
        parsed = json.loads(subprocess.check_output(["swift", "package", "--package-path", str(self.output), "dump-package"], text=True))
        binary = next(target for target in parsed["targets"] if target["name"] == "OpenLVFFI")
        self.assertEqual(binary["url"], URL)
        self.assertEqual(binary["checksum"], checksum)
        with zipfile.ZipFile(archive) as zipped:
            expected = {"OpenLVFFI.xcframework/" + str(path.relative_to(self.bundle)) for path in self.bundle.rglob("*") if path.is_file()}
            self.assertEqual(set(zipped.namelist()), expected)
            for path in self.bundle.rglob("*"):
                if path.is_file():
                    self.assertEqual(zipped.read("OpenLVFFI.xcframework/" + str(path.relative_to(self.bundle))), path.read_bytes())
        for path in self.bundle.rglob("*"):
            path.touch()
        self.assertEqual(release.prepare_release(self.root, URL, self.output), checksum)
        self.assertEqual(archive.read_bytes(), first)

    def test_host_only_and_missing_simulator_are_rejected(self):
        self.change_metadata(lambda libraries: libraries.pop())
        with self.assertRaisesRegex(ValueError, "Release requires"):
            release.prepare_release(self.root, URL, self.output)
        self.change_metadata(lambda libraries: libraries.pop())
        with self.assertRaisesRegex(ValueError, "Release requires"):
            release.prepare_release(self.root, URL, self.output)
        self.assertFalse(self.output.exists())

    def test_archive_architectures_are_checked(self):
        macos = self.bundle / "macos-arm64_x86_64/libopenlv_swift_ffi.a"
        device = self.bundle / "ios-arm64/libopenlv_swift_ffi.a"
        shutil.copy2(device, macos)
        with self.assertRaisesRegex(ValueError, "architectures do not match"):
            release.prepare_release(self.root, URL, self.output)

    def test_different_headers_are_rejected(self):
        (self.bundle / "ios-arm64/Headers/OpenLVFFI.h").write_text("int stale(void);\n")
        with self.assertRaisesRegex(ValueError, "headers differ"):
            release.prepare_release(self.root, URL, self.output)

    def test_duplicate_slices_and_escaping_paths_are_rejected(self):
        self.change_metadata(lambda libraries: libraries.append(libraries[0]))
        with self.assertRaisesRegex(ValueError, "duplicate XCFramework slice"):
            release.prepare_release(self.root, URL, self.output)
        self.change_metadata(lambda libraries: libraries[0].update(LibraryIdentifier="../outside"))
        with self.assertRaisesRegex(ValueError, "relative path"):
            release.prepare_release(self.root, URL, self.output)

    def test_symlinks_are_rejected(self):
        (self.bundle / "outside").symlink_to(self.root / "Package.swift")
        with self.assertRaisesRegex(ValueError, "symbolic links"):
            release.prepare_release(self.root, URL, self.output)

    def test_release_url_validation(self):
        for url in [URL.replace("https:", "http:"), URL + "?token=secret", URL + "#fragment",
                    URL.replace("example.invalid", "user:secret@example.invalid"), URL.replace(".zip", ".tar.gz")]:
            with self.subTest(url=url), self.assertRaisesRegex(ValueError, "HTTPS release URL"):
                release.prepare_release(self.root, url, self.output)
        self.assertFalse(self.output.exists())

    def test_output_cannot_overwrite_source_or_enter_framework(self):
        original = (self.root / "Package.swift").read_bytes()
        for output in [self.root, self.bundle / "release"]:
            with self.subTest(output=output), self.assertRaisesRegex(ValueError, "Release output"):
                release.prepare_release(self.root, URL, output)
        self.assertEqual((self.root / "Package.swift").read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
