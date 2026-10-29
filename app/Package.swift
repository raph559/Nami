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
    dependencies: [
        // libmpv and FFmpeg, LGPL build (no GPL modules).
        .package(url: "https://github.com/mpvkit/MPVKit.git", exact: "1.0.0"),
    ],
    targets: [
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
            dependencies: ["NamiEngine", .product(name: "MPVKit", package: "MPVKit")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                // Record the real SDK (27.0) rather than the minimum iOS: iOS, and
                // LiveContainer's SDK spoofing, read it to turn on the current UI
                // (Liquid Glass tab bar and sheets) instead of the iOS 17 look.
                .unsafeFlags(["-Xlinker", "-platform_version", "-Xlinker", "ios", "-Xlinker", "17.0", "-Xlinker", "27.0"]),
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
