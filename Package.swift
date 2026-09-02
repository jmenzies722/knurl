// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Knurl",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .executable(name: "Knurl", targets: ["Knurl"]),
        .library(name: "KnurlCore", targets: ["KnurlCore"]),
        .library(name: "KnurlLink", targets: ["KnurlLink"]),
        .library(name: "KnurlAgents", targets: ["KnurlAgents"]),
    ],
    targets: [
        .target(name: "KnurlLink"),
        .target(name: "KnurlCore"),
        .target(name: "KnurlAgents"),
        .executableTarget(
            name: "Knurl",
            dependencies: ["KnurlCore", "KnurlLink", "KnurlAgents"],
            linkerSettings: [
                .linkedFramework("MusicKit"),
                .linkedFramework("_MusicKit_SwiftUI"),
                .linkedFramework("AVKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech"),
                .linkedFramework("AppIntents"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("IOKit"),
            ]
        ),
        .testTarget(
            name: "KnurlCoreTests",
            dependencies: ["KnurlCore", "KnurlLink"]
        ),
        .testTarget(
            name: "KnurlAgentsTests",
            dependencies: ["KnurlAgents"]
        ),
    ]
)
