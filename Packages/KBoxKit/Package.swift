// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KBoxKit",
    platforms: [.macOS("15.0"), .iOS("26.0")],
    products: [
        .library(name: "KBoxKit", targets: ["KBoxKit"]),
    ],
    targets: [
        .target(name: "KBoxKit"),
        .testTarget(name: "KBoxKitTests", dependencies: ["KBoxKit"]),
    ]
)
