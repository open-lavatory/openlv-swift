// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenLV",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "OpenLV", targets: ["OpenLV"]),
        .executable(name: "openlv-example", targets: ["SessionDemo"]),
    ],
    targets: [
        .binaryTarget(name: "OpenLVFFI", path: "Native/OpenLVFFI.xcframework"),
        .target(
            name: "OpenLVNative",
            dependencies: ["OpenLVFFI"],
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("SystemConfiguration"),
                .linkedLibrary("resolv"),
            ]
        ),
        .target(name: "OpenLV", dependencies: ["OpenLVNative"]),
        .executableTarget(name: "SessionDemo", dependencies: ["OpenLV"], path: "Examples/SessionDemo"),
        .testTarget(name: "OpenLVTests", dependencies: ["OpenLV"]),
    ]
)
