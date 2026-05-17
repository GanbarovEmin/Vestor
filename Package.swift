// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MyInvest",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MyInvest", targets: ["MyInvest"])
    ],
    targets: [
        .executableTarget(name: "MyInvest"),
        .testTarget(name: "MyInvestTests", dependencies: ["MyInvest"])
    ],
    swiftLanguageModes: [.v5]
)
