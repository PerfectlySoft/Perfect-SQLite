// swift-tools-version:5.1
// Generated automatically by Perfect Assistant
// Date: 2018-12-25 02:23:42 +0000
import PackageDescription

#if os(Linux)
let package = Package(
	name: "PerfectSQLite",
	products: [
		.library(name: "PerfectSQLite", targets: ["PerfectSQLite"])
	],
	dependencies: [
		.package(url: "https://github.com/PerfectlySoft/Perfect-CRUD.git", from: "2.0.0"),
		.package(url: "https://github.com/PerfectlySoft/Perfect-sqlite3-support.git", from: "3.0.0"),
	],
	targets: [
		.target(name: "PerfectSQLite", dependencies: ["PerfectCRUD"]),
		.testTarget(name: "PerfectSQLiteTests", dependencies: ["PerfectSQLite"])
	]
)
#else
let package = Package(
	name: "PerfectSQLite",
	platforms: [
		.macOS(.v10_15)
	],
	products: [
		.library(name: "PerfectSQLite", targets: ["PerfectSQLite"])
	],
	dependencies: [
		.package(url: "https://github.com/PerfectlySoft/Perfect-CRUD.git", from: "2.0.0")
	],
	targets: [
		.target(name: "PerfectSQLite", dependencies: ["PerfectCRUD"]),
		.testTarget(name: "PerfectSQLiteTests", dependencies: ["PerfectSQLite"])
	]
)
#endif
