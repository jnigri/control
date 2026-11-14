// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Control",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Control")
    ],
    // Everything runs on the main thread, so Swift 6's thread-safety checks
    // would only add annotations everywhere. Swift 5 mode keeps the code plain.
    swiftLanguageModes: [.v5]
)
