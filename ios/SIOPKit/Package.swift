// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SIOPKit",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "SIOPKit", targets: ["SIOPKit"]),
        .executable(name: "siop-issue", targets: ["siop-issue"]),
    ],
    targets: [
        .target(name: "SIOPKit"),
        .executableTarget(name: "siop-issue", dependencies: ["SIOPKit"]),
        .testTarget(name: "SIOPKitTests", dependencies: ["SIOPKit"]),
    ]
)
