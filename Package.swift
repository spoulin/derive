// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Derive",
    platforms: [.macOS(.v13)],
    targets: [.executableTarget(name: "Derive", path: "Sources/Derive")]
)
