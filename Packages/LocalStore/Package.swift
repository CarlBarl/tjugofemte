// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "LocalStore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "LocalStore", targets: ["LocalStore"]),
    ],
    dependencies: [
        .package(path: "../BudgetCore"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
    ],
    targets: [
        .target(name: "LocalStore", dependencies: ["BudgetCore", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "LocalStoreTests", dependencies: ["LocalStore"]),
    ]
)
