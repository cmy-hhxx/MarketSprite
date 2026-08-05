// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QuoteDatabase",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "QuoteDatabase", targets: ["QuoteDatabase"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "QuoteDatabase",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        )
    ]
)
