// swift-tools-version: 6.0
import PackageDescription

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
nativeTarget = .binaryTarget(name: "OpenLVFFI", path: "Native/OpenLVFFI.xcframework")
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
    targets: [
        nativeTarget,
        .target(
            name: "OpenLVNative",
            dependencies: [nativeDependency],
            linkerSettings: nativeLinkerSettings
        ),
        .target(name: "OpenLV", dependencies: ["OpenLVNative"]),
        .executableTarget(name: "SessionDemo", dependencies: ["OpenLV"], path: "Examples/SessionDemo"),
        .testTarget(name: "OpenLVBehaviorTests", dependencies: ["OpenLV"]),
    ]
)
