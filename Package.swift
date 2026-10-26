// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Mura",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "mura", targets: ["mura"])
    ],
    targets: [
        .target(name: "MuraCore"),
        .executableTarget(name: "mura", dependencies: ["MuraCore"]),
        .testTarget(name: "MuraCoreTests", dependencies: ["MuraCore"])
    ]
)
