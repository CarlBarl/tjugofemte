// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "BudgetCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "BudgetCore", targets: ["BudgetCore"]),
    ],
    targets: [
        .target(name: "BudgetCore"),
        .testTarget(name: "BudgetCoreTests", dependencies: ["BudgetCore"]),
    ]
)
