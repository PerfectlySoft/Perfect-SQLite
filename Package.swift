// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PerfectSQLite",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "PerfectSQLite", targets: ["PerfectSQLite"]),
    ],
    dependencies: [
        .package(url: "https://github.com/PerfectlySoft/Perfect-CRUD.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "PerfectSQLite",
            dependencies: [.product(name: "PerfectCRUD", package: "Perfect-CRUD")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PerfectSQLiteTests",
            dependencies: ["PerfectSQLite"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
