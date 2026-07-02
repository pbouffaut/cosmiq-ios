// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CosmiqKit",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "CosmiqKit", targets: ["CosmiqKit"])
    ],
    targets: [
        .target(name: "CosmiqKit"),
        .testTarget(name: "CosmiqKitTests", dependencies: ["CosmiqKit"]),
    ]
)
