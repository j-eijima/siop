// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SIOPKit",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "SIOPKit", targets: ["SIOPKit"]),
    ],
    targets: [
        .target(name: "SIOPKit"),
        .testTarget(name: "SIOPKitTests", dependencies: ["SIOPKit"]),
    ]
)
