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
        // System SQLite for Linux, which has no SQLite3 module like Apple's SDK.
        // Apple platforms keep importing SQLite3 (see `#if canImport(SQLite3)`).
        // Prefixed name: target names must be unique across a package graph,
        // and plain `CSQLite` is common.
        .systemLibrary(
            name: "PerfectCSQLite",
            pkgConfig: "sqlite3",
            providers: [
                .apt(["libsqlite3-dev"]),
                .yum(["sqlite-devel"]),
            ]
        ),
        .target(
            name: "PerfectSQLite",
            dependencies: [
                .product(name: "PerfectCRUD", package: "Perfect-CRUD"),
                .target(name: "PerfectCSQLite", condition: .when(platforms: [.linux])),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PerfectSQLiteTests",
            dependencies: ["PerfectSQLite"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
