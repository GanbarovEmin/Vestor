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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.9.2")
    ],
    targets: [
        .executableTarget(
            name: "MyInvest",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ]
        ),
        .testTarget(name: "MyInvestTests", dependencies: ["MyInvest"])
    ],
    swiftLanguageModes: [.v5]
)
