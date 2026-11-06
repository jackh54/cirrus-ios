// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JMAPKit",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "JMAPKit", targets: ["JMAPKit"]),
    ],
    targets: [
        .target(name: "JMAPKit"),
        .testTarget(name: "JMAPKitTests", dependencies: ["JMAPKit"]),
    ],
    swiftLanguageModes: [.v6]
)
