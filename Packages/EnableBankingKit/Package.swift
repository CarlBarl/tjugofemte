// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "EnableBankingKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "EnableBankingKit", targets: ["EnableBankingKit"]),
    ],
    targets: [
        .target(name: "EnableBankingKit"),
        .testTarget(name: "EnableBankingKitTests", dependencies: ["EnableBankingKit"]),
    ]
)
