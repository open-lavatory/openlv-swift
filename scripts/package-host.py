"""Package the macOS host archive in the standard XCFramework directory format."""
import pathlib
import plistlib
import shutil
import sys

root = pathlib.Path(__file__).resolve().parent.parent
arch = sys.argv[1]
identifier = f"macos-{arch}"
bundle = root / "Native/OpenLVFFI.xcframework"
if bundle.exists():
    shutil.rmtree(bundle)
library = bundle / identifier
library.mkdir(parents=True)
shutil.copy2(root / "rust/target/release/libopenlv_swift_ffi.a", library)
shutil.copytree(root / ".native-build/Headers", library / "Headers")
with (bundle / "Info.plist").open("wb") as file:
    plistlib.dump({
        "CFBundlePackageType": "XFWK",
        "XCFrameworkFormatVersion": "1.0",
        "AvailableLibraries": [{
            "LibraryIdentifier": identifier,
            "LibraryPath": "libopenlv_swift_ffi.a",
            "HeadersPath": "Headers",
            "SupportedArchitectures": [arch],
            "SupportedPlatform": "macos",
        }],
    }, file)
