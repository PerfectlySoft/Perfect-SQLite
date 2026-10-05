# Perfect - SQLite Connector

<p align="center">
    <a href="https://developer.apple.com/swift/" target="_blank">
        <img src="https://img.shields.io/badge/Swift-6.2-orange.svg?style=flat" alt="Swift 6.2">
    </a>
    <a href="#building">
        <img src="https://img.shields.io/badge/Platforms-macOS%2012%2B%20%7C%20Linux-lightgray.svg?style=flat" alt="Platforms macOS 12+ | Linux">
    </a>
    <a href="./LICENSE" target="_blank">
        <img src="https://img.shields.io/badge/License-Apache-lightgrey.svg?style=flat" alt="License Apache">
    </a>
</p>

This project provides a Swift wrapper around the SQLite 3 C library, plus a [Perfect-CRUD](https://github.com/PerfectlySoft/Perfect-CRUD) database driver built on top of it.

**Modernized for Swift 6.** Requires **swift-tools-version 6.2** and builds under full **Swift 6 language mode** (strict concurrency checking on for both the library and test targets). Supports **macOS 12+** (`platforms: [.macOS(.v12)]`) and **Linux** (tested with Swift 6.2.4, 6.3.2 and 6.4 on Ubuntu 24.04). iOS/tvOS/watchOS aren't declared or tested.

The pre-Swift-6 version of this package is preserved on the [`legacy`](../../tree/legacy) branch.

## What's in this package

`Sources/PerfectSQLite` contains two files:

- **`SQLite.swift`** — a thin, synchronous Swift wrapper around the SQLite3 C API: the `SQLite` class (open/close/prepare/execute/`forEachRow`/transactions) and `SQLiteStmt` (bind-by-position/name, column reading).
- **`SQLiteCRUD.swift`** — about two-thirds of the package's source — implements the integration that lets [Perfect-CRUD](https://github.com/PerfectlySoft/Perfect-CRUD)'s typed query builder target a SQLite database: `SQLiteCRUDRowReader` (a `KeyedDecodingContainer` bridge from SQLite columns to `Codable` types), `SQLiteGenDelegate`/`SQLiteExeDelegate` (PerfectCRUD's `SQLGenDelegate`/`SQLExeDelegate`), and `SQLiteDatabaseConfiguration: DatabaseConfigurationProtocol`.

Both `SQLite` and `SQLiteStmt` (and the CRUD delegate classes) are marked `@unchecked Sendable` rather than being actors — there is no async/await anywhere in this module. This is a manual Sendable opt-out around raw `OpaquePointer`/mutable C-backed state: none of these types are internally thread-safe, so callers are responsible for serializing their own access to a given `SQLite`/`SQLiteStmt` instance.

## Dependencies

This package has a single dependency:

```swift
dependencies: [
    .package(url: "https://github.com/PerfectlySoft/Perfect-CRUD.git", branch: "main"),
],
```

It depends on **Perfect-CRUD** (product `PerfectCRUD`) for the ORM integration layer, and has no remote/external package dependencies otherwise — only the system SQLite3 C library. On macOS that comes from the SDK's `SQLite3` module; on Linux the package's `PerfectCSQLite` system-library target links the distribution's `libsqlite3` (found via `pkg-config sqlite3`).

## Where this fits

This package is real, tested, working code. It backs one of the five session drivers in
**Perfect-Session** (`SQLiteSessionDriver.swift` imports `PerfectSQLite` and uses the raw `SQLite`
API below).

## Building

Add this project as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/PerfectlySoft/Perfect-SQLite.git", branch: "main"),
],
```

and add `"PerfectSQLite"` to your target's `dependencies` array. You need the Swift 6.2 toolchain (or newer).

- **macOS:** SQLite ships with the macOS 12+ SDK; nothing else to install. If the build fails on `PerfectCSQLite` (`no such module 'PerfectCSQLite'` or `unable to resolve module dependency: 'PerfectCSQLite'`), the SDK's `SQLite3` module wasn't found: check the selected toolchain and SDK (`xcode-select -p`, `xcrun --show-sdk-path`).
- **Linux:** install the SQLite development package (`sqlite-devel` on Fedora/RHEL), e.g. on Debian/Ubuntu:

  ```bash
  apt-get install libsqlite3-dev
  ```

  Without it the build fails with `'sqlite3.h' file not found`, and SwiftPM suggests the package to install.

## Usage Example — raw SQLite API

Let's assume you'd like to host a blog in Swift. First we need tables. Opening `./db/database` creates the SQLite file if it doesn't exist (the `db` directory must already exist), so we simply need to connect and add the tables.

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
let featuredImageURI = "/images/test.png"

do {
   let sqlite = try SQLite(dbPath)
   defer {
     sqlite.close()
   }

   try sqlite.execute(statement: "INSERT INTO posts (post_title, post_content, featured_image_uri) VALUES (?1,?2,?3)") {
     (stmt:SQLiteStmt) -> () in

     try stmt.bind(position: 1, postTitle)
     try stmt.bind(position: 2, postContent)
     try stmt.bind(position: 3, featuredImageURI)
   }
 } catch {
   //Handle Errors
 }
```

Finally, we retrieve the five newest posts. Each row is appended to an array of dictionaries for use elsewhere.

``` swift
let dbPath = "./db/database"
var contentRows = [[String: String]]()

do {
	let sqlite = try SQLite(dbPath)
		defer {
			sqlite.close() // This makes sure we close our connection.
		}
	
	let demoStatement = "SELECT id, post_title, post_content FROM posts ORDER BY id DESC LIMIT ?1"
	
	try sqlite.forEachRow(statement: demoStatement, doBindings: {
		
		(statement: SQLiteStmt) -> () in
		
		let bindValue = 5
		try statement.bind(position: 1, bindValue)
		
	}) {(statement: SQLiteStmt, i:Int) -> () in

        contentRows.append([
                "id": statement.columnText(position: 0),
                "post_title": statement.columnText(position: 1),
                "post_content": statement.columnText(position: 2)
            ])
  }
	
} catch {
	//Handle Errors
}
```

## Usage — Perfect-CRUD integration

For typed, Codable-based access instead of raw SQL, create a Perfect-CRUD `Database` with a `SQLiteDatabaseConfiguration` (its first argument is the database file path; by default it runs `PRAGMA foreign_keys = ON`) and use the normal query-builder API (`create`, `table(...)`, `insert(...)`, `where(...)`, `select()`, etc.). This is what `SQLiteCRUD.swift` implements.

```swift
import PerfectCRUD
import PerfectSQLite

struct Post: Codable {
	let id: Int
	let title: String
}

let db = Database(configuration: try SQLiteDatabaseConfiguration("./db/database"))
try db.create(Post.self, policy: .reconcileTable)
let posts = db.table(Post.self)
try posts.insert(Post(id: 1, title: "Hello"))
for post in try posts.where(\Post.id == 1).select() {
	print(post.title)
}
```

See `Sources/PerfectSQLite/SQLiteCRUD.swift` and the [Perfect-CRUD](https://github.com/PerfectlySoft/Perfect-CRUD) README for the CRUD API itself.

## Further Information

See `docs/` in this repository for the older generated API docs (raw `SQLite`/`SQLiteStmt` only), or the [Perfect-CRUD](https://github.com/PerfectlySoft/Perfect-CRUD) package for the ORM layer this package integrates with.
