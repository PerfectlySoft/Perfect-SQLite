# Perfect - SQLite Connector

[![GitHub version](https://badge.fury.io/gh/PerfectlySoft%2FPerfect-SQLite.svg)](https://badge.fury.io/gh/PerfectlySoft%2FPerfect-SQLite)

This project provides a Swift wrapper around the SQLite 3 library.

This package builds with Swift Package Manager and is part of the [Perfect](https://github.com/PerfectlySoft/Perfect) project. It was written to be stand-alone and so does not require PerfectLib or any other components.

Ensure you have installed and activated the latest Swift 3.0 tool chain.

To learn more, you can read the full documentation guide [here](https://github.com/PerfectlySoft/PerfectDocs/blob/master/guide/SQLite.md) or jump to the example [here](#Usage-Example)

## Linux Build Notes

Ensure that you have installed sqlite3.

```
sudo apt-get install sqlite3
```

## Building

Add this project as a dependency in your Package.swift file.

```
.Package(url: "https://github.com/PerfectlySoft/Perfect-SQLite.git", versions: Version(0,0,0)..<Version(10,0,0))
```

## Usage Example

Let’s assume you’d like to host a blog in Swift. First we need tables. Assuming you’ve created an SQLite file `./db/database`, we simply need to connect and add the tables. 

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

Finally, we retrieve posts and post titles from an SQLite database full of blog content. Each id, post, and title is appended to a dictionary for use elsewhere. 

``` swift
let dbPath = "./db/database"
Var contentDict = [String: Any]()

do {
	let sqlite = try SQLite(dbPath)
		defer {
			sqlite.close() // This makes sure we close our connection.
		}
	
	let demoStatement = "SELECT post_title, post_content FROM posts ORDER BY id DESC LIMIT :1"
	
	try sqlite.forEachRow(statement: demoStatement, doBindings {
		
		(statement: SQLiteStmt) -> () in
		
		let bindValue = 5
		try statement.bind(position: 1, bindValue)
		
	}) {(statement: SQLiteStmt, i:Int) -> () in

        self.contentDict.append([
                "id": statement.columnText(position: 0),
                "second_field": statement.columnText(position: 1),
                "third_field": statement.columnText(position: 2)
            ])
  }
	
} catch {
	//Handle Errors
}
```

## Repository Layout

We have finished refactoring Perfect to support Swift Package Manager. The Perfect project has been split up into the following repositories:

* [Perfect](https://github.com/PerfectlySoft/Perfect) - This repository contains the core PerfectLib and will continue to be the main landing point for the project.
* [PerfectTemplate](https://github.com/PerfectlySoft/PerfectTemplate) - A simple starter project which compiles with SPM into a stand-alone executable HTTP server. This repository is ideal for starting on your own Perfect based project.
* [PerfectDocs](https://github.com/PerfectlySoft/PerfectDocs) - Contains all API reference related material.
* [PerfectExamples](https://github.com/PerfectlySoft/PerfectExamples) - All the Perfect example projects and documentation.
* [PerfectEverything](https://github.com/PerfectlySoft/PerfectEverything) - This umbrella repository allows one to pull in all the related Perfect modules in one go, including the servers, examples, database connectors and documentation. This is a great place to start for people wishing to get up to speed with Perfect.
* [PerfectServer](https://github.com/PerfectlySoft/PerfectServer) - Contains the PerfectServer variants, including the stand-alone HTTP and FastCGI servers. Those wishing to do a manual deployment should clone and build from this repository.
* [Perfect-Redis](https://github.com/PerfectlySoft/Perfect-Redis) - Redis database connector.
* [Perfect-SQLite](https://github.com/PerfectlySoft/Perfect-SQLite) - SQLite3 database connector.
* [Perfect-PostgreSQL](https://github.com/PerfectlySoft/Perfect-PostgreSQL) - PostgreSQL database connector.
* [Perfect-MySQL](https://github.com/PerfectlySoft/Perfect-MySQL) - MySQL database connector.
* [Perfect-MongoDB](https://github.com/PerfectlySoft/Perfect-MongoDB) - MongoDB database connector.
* [Perfect-FastCGI-Apache2.4](https://github.com/PerfectlySoft/Perfect-FastCGI-Apache2.4) - Apache 2.4 FastCGI module; required for the Perfect FastCGI server variant.

The database connectors are all stand-alone and can be used outside of the Perfect framework and server.

## Further Information
For more information on the Perfect project, please visit [perfect.org](http://perfect.org).
