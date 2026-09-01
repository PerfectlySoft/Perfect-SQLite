# Perfect - SQLite Connector

<p align="center">
    <a href="https://developer.apple.com/swift/" target="_blank">
        <img src="https://img.shields.io/badge/Swift-6.2-orange.svg?style=flat" alt="Swift 6.2">
    </a>
    <a href="https://developer.apple.com/macos/" target="_blank">
        <img src="https://img.shields.io/badge/Platforms-macOS%2012%2B-lightgray.svg?style=flat" alt="Platforms macOS 12+">
    </a>
    <a href="./LICENSE" target="_blank">
        <img src="https://img.shields.io/badge/License-Apache-lightgrey.svg?style=flat" alt="License Apache">
    </a>
</p>

This project provides a Swift wrapper around the SQLite 3 C library, plus a [Perfect-CRUD](https://github.com/PerfectlySoft/Perfect-CRUD) database driver built on top of it.

**Modernized for Swift 6.** Requires **swift-tools-version 6.2** and builds under full **Swift 6 language mode** (strict concurrency checking on for both the library and test targets). Declares `platforms: [.macOS(.v12)]` — this is a **macOS-only** package today; no Linux (or iOS/tvOS/watchOS) platform is declared in `Package.swift`.

The pre-Swift-6 version of this package is preserved on the [`legacy`](../../tree/legacy) branch.

## What's in this package

`Sources/PerfectSQLite` contains two files:

- **`SQLite.swift`** — a thin, synchronous Swift wrapper around the SQLite3 C API: the `SQLite` class (open/close/prepare/execute/`forEachRow`/transactions) and `SQLiteStmt` (bind-by-position/name, column reading).
- **`SQLiteCRUD.swift`** — roughly half the package's source — implements the integration that lets [Perfect-CRUD](../Perfect-CRUD)'s typed query builder target a SQLite database: `SQLiteCRUDRowReader` (a `KeyedDecodingContainer` bridge from SQLite columns to `Codable` types), `SQLiteGenDelegate`/`SQLiteExeDelegate` (PerfectCRUD's `SQLGenDelegate`/`SQLExeDelegate`), and `SQLiteDatabaseConfiguration: DatabaseConfigurationProtocol`.

Both `SQLite` and `SQLiteStmt` (and the CRUD delegate classes) are marked `@unchecked Sendable` rather than being actors — there is no async/await anywhere in this module. This is a manual Sendable opt-out around raw `OpaquePointer`/mutable C-backed state: none of these types are internally thread-safe, so callers are responsible for serializing their own access to a given `SQLite`/`SQLiteStmt` instance.

## Dependencies

This package has a single dependency:

```swift
dependencies: [
    .package(url: "https://github.com/PerfectlySoft/Perfect-CRUD.git", branch: "main"),
],
```

It depends on **Perfect-CRUD** (product `PerfectCRUD`) for the ORM integration layer, and has no remote/external package dependencies otherwise — only the system SQLite3 C library.

## Where this fits

This package is real, tested, working code — it is one of the four backend session drivers consumed
by **Perfect-Session** (`SQLiteSessionDriver.swift` does `import PerfectSQLite` directly and uses
the CRUD integration above).

## Building

Add this project as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/PerfectlySoft/Perfect-SQLite.git", branch: "main"),
],
```

and add `"PerfectSQLite"` to your target's `dependencies` array. Ensure you have the Swift 6.2 toolchain (or newer) installed and a macOS 12+ SDK, and that `sqlite3` is available (it ships with macOS). If you encounter `sqlite3.h file not found` during `swift build`, verify your active toolchain and SDK are correctly selected.

## Usage Example — raw SQLite API

Let's assume you'd like to host a blog in Swift. First we need tables. Assuming you've created an SQLite file `./db/database`, we simply need to connect and add the tables.

```swift
let dbPath = "./db/database"

do {
	let sqlite = try SQLite(dbPath)
	defer {  
		sqlite.close()
	}

	try sqlite.execute(statement: "CREATE TABLE IF NOT EXISTS posts (id INTEGER PRIMARY KEY NOT NULL, post_title TEXT NOT NULL, post_content TEXT NOT NULL, featured_image_uri TEXT NOT NULL)")
} catch {
	print("Failure creating database tables") //Handle Errors
}
```

Next, we would need to add some content.

```swift
let dbPath = "./db/database"
let postTitle = "Test Title"
let postContent = "Lorem ipsum dolor sit amet…"

do {
   let sqlite = try SQLite(dbPath)
   defer {
     sqlite.close()
   }

   try sqlite.execute(statement: "INSERT INTO posts (post_title, post_content) VALUES (:1,:2)") {
     (stmt:SQLiteStmt) -> () in

     try stmt.bind(position: 1, postTitle)
     try stmt.bind(position: 2, postContent)
   }
 } catch {
		//Handle Errors
 }
```

Finally, we retrieve posts and post titles from an SQLite database full of blog content. Each row is appended to an array of dictionaries for use elsewhere.

``` swift
let dbPath = "./db/database"
var contentRows = [[String: String]]()

do {
	let sqlite = try SQLite(dbPath)
		defer {
			sqlite.close() // This makes sure we close our connection.
		}
	
	let demoStatement = "SELECT post_title, post_content FROM posts ORDER BY id DESC LIMIT :1"
	
	try sqlite.forEachRow(statement: demoStatement, doBindings: {
		
		(statement: SQLiteStmt) -> () in
		
		let bindValue = 5
		try statement.bind(position: 1, bindValue)
		
	}) {(statement: SQLiteStmt, i:Int) -> () in

        contentRows.append([
                "id": statement.columnText(position: 0),
                "second_field": statement.columnText(position: 1),
                "third_field": statement.columnText(position: 2)
            ])
  }
	
} catch {
	//Handle Errors
}
```

## Usage — Perfect-CRUD integration

For typed, Codable-based access instead of raw SQL, register a `SQLiteDatabaseConfiguration` with Perfect-CRUD's `Database` type and use its normal query-builder API (`table(...)`, `select()`, `insert(...)`, etc.) against a local SQLite file — this is the path `SQLiteCRUD.swift` implements, and the one Perfect-Session's `SQLiteSessionDriver` relies on. See `Sources/PerfectSQLite/SQLiteCRUD.swift` and the [Perfect-CRUD](../Perfect-CRUD) README for the CRUD API itself.

## Further Information

See `docs/` in this repository, or the [Perfect-CRUD](../Perfect-CRUD) package for the ORM layer this package integrates with.
