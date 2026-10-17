// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PianoCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "PianoCore", targets: ["PianoCore"]),
    ],
    targets: [
        .target(name: "PianoCore"),
        .testTarget(name: "PianoCoreTests", dependencies: ["PianoCore"]),
    ]
)
