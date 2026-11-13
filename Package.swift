// swift-tools-version: 6.0
import PackageDescription
import Foundation

let nativeTarget: Target
let nativeDependency: Target.Dependency
let nativeLinkerSettings: [LinkerSetting]

#if os(Linux)
nativeTarget = .systemLibrary(
    name: "OpenLVFFI",
    pkgConfig: "openlv-ffi",
    providers: []
)
nativeDependency = "OpenLVFFI"
nativeLinkerSettings = []
#else
if ProcessInfo.processInfo.environment["OPENLV_USE_LOCAL_NATIVE"] == "1" {
    nativeTarget = .binaryTarget(name: "OpenLVFFI", path: "Native/OpenLVFFI.xcframework")
} else {
// BEGIN RELEASE BINARY TARGET
nativeTarget = .binaryTarget(name: "OpenLVFFI", path: "Native/OpenLVFFI.xcframework")
// END RELEASE BINARY TARGET
}
nativeDependency = "OpenLVFFI"
nativeLinkerSettings = [
    .linkedFramework("Security"),
    .linkedFramework("SystemConfiguration"),
    .linkedLibrary("resolv"),
]
#endif

let package = Package(
    name: "OpenLV",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "OpenLV", targets: ["OpenLV"]),
        .executable(name: "openlv-example", targets: ["SessionDemo"]),
    ],
    dependencies: [
        .package(url: "https://github.com/21-DOT-DEV/swift-secp256k1.git", exact: "0.21.1"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", exact: "1.9.0"),
    ],
    targets: [
        nativeTarget,
        .target(
            name: "OpenLVNative",
            dependencies: [nativeDependency],
            linkerSettings: nativeLinkerSettings
        ),
        .target(name: "OpenLV", dependencies: ["OpenLVNative"]),
        .executableTarget(
            name: "SessionDemo",
            dependencies: [
                "OpenLV",
                .product(name: "P256K", package: "swift-secp256k1"),
                .product(name: "CryptoSwift", package: "CryptoSwift"),
            ],
            path: "Examples/SessionDemo"
        ),
        .testTarget(name: "OpenLVBehaviorTests", dependencies: ["OpenLV", "SessionDemo"]),
    ]
)
