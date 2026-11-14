// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clawd",
    platforms: [.macOS(.v14)],
    targets: [
        // Kleiner Objective-C-Helfer: fängt NSExceptions ab, die Swift nicht fangen kann.
        .target(name: "ObjCExceptions", path: "Sources/ObjCExceptions"),
        .executableTarget(name: "Clawd", dependencies: ["ObjCExceptions"], path: "Sources/Clawd"),
        .testTarget(name: "ClawdTests", dependencies: ["Clawd"], path: "Tests/ClawdTests"),
    ]
)
