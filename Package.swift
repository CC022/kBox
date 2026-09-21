// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "kBox",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "kBox", targets: ["KBoxApp"]),
    ],
    targets: [
        // Thin @main entry point; everything else lives in KBoxKit so it can be previewed and tested.
        .executableTarget(name: "KBoxApp", dependencies: ["KBoxKit"]),
        .target(name: "KBoxKit"),
        .testTarget(name: "KBoxKitTests", dependencies: ["KBoxKit"]),
    ]
)
