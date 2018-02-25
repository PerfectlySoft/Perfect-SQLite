// swift-tools-version:4.0
// Generated automatically by Perfect Assistant Application
// Date: 2017-12-08 19:01:12 +0000
import PackageDescription
let package = Package(
	name: "PerfectSQLite",
	products: [
		.library(name: "PerfectSQLite", targets: ["PerfectSQLite"])
	],
	dependencies: [
		.package(url: "https://github.com/PerfectlySoft/Perfect-CRUD.git", .branch("master")),
		.package(url: "https://github.com/PerfectlySoft/Perfect-sqlite3-support.git", from: "3.0.0"),
	],
	targets: [
		.target(name: "PerfectSQLite", dependencies: ["PerfectCRUD"]),
		.testTarget(name: "PerfectSQLiteTests", dependencies: ["PerfectSQLite"])
	]
)
