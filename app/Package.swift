// swift-tools-version: 6.0

import PackageDescription

import Foundation

let engineLib = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("../engine/out").standardized.path

let package = Package(
    name: "Nami",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(name: "Nami", targets: ["Nami"]),
    ],
    targets: [
        .binaryTarget(
            name: "MobileVLCKit",
            path: "Vendor/MobileVLCKit.xcframework"
        ),
        // C shim around the Go torrent engine (libnami.a).
        .target(
            name: "NamiEngine",
            linkerSettings: [
                .unsafeFlags(["-L\(engineLib)", "-lnami"]),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("Security"),
                .linkedLibrary("resolv"),
            ]
        ),
        .target(
            name: "Nami",
            dependencies: ["NamiEngine", "MobileVLCKit"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("QuartzCore"),
                .linkedFramework("CoreText"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CFNetwork"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("OpenGLES"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedLibrary("c++"),
                .linkedLibrary("xml2"),
                .linkedLibrary("z"),
                .linkedLibrary("bz2"),
                .linkedLibrary("iconv"),
            ]
        ),
    ]
)
