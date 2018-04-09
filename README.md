# Perfect - SQLite Connector


<p align="center">
    <a href="http://perfect.org/get-involved.html" target="_blank">
        <img src="http://perfect.org/assets/github/perfect_github_2_0_0.jpg" alt="Get Involed with Perfect!" width="854" />
    </a>
</p>

<p align="center">
    <a href="https://github.com/PerfectlySoft/Perfect" target="_blank">
        <img src="http://www.perfect.org/github/Perfect_GH_button_1_Star.jpg" alt="Star Perfect On Github" />
    </a>  
    <a href="http://stackoverflow.com/questions/tagged/perfect" target="_blank">
        <img src="http://www.perfect.org/github/perfect_gh_button_2_SO.jpg" alt="Stack Overflow" />
    </a>  
    <a href="https://twitter.com/perfectlysoft" target="_blank">
        <img src="http://www.perfect.org/github/Perfect_GH_button_3_twit.jpg" alt="Follow Perfect on Twitter" />
    </a>  
    <a href="http://perfect.ly" target="_blank">
        <img src="http://www.perfect.org/github/Perfect_GH_button_4_slack.jpg" alt="Join the Perfect Slack" />
    </a>
</p>

<p align="center">
    <a href="https://developer.apple.com/swift/" target="_blank">
        <img src="https://img.shields.io/badge/Swift-4.0-orange.svg?style=flat" alt="Swift 4.0">
    </a>
    <a href="https://developer.apple.com/swift/" target="_blank">
        <img src="https://img.shields.io/badge/Platforms-OS%20X%20%7C%20Linux%20-lightgray.svg?style=flat" alt="Platforms OS X | Linux">
    </a>
    <a href="http://perfect.org/licensing.html" target="_blank">
        <img src="https://img.shields.io/badge/License-Apache-lightgrey.svg?style=flat" alt="License Apache">
    </a>
    <a href="http://twitter.com/PerfectlySoft" target="_blank">
        <img src="https://img.shields.io/badge/Twitter-@PerfectlySoft-blue.svg?style=flat" alt="PerfectlySoft Twitter">
    </a>
    <a href="http://perfect.ly" target="_blank">
        <img src="http://perfect.ly/badge.svg" alt="Slack Status">
    </a>
</p>

This project provides a Swift wrapper around the SQLite 3 library.

This package builds with Swift Package Manager and is part of the [Perfect](https://github.com/PerfectlySoft/Perfect) project. It was written to be stand-alone and so does not require PerfectLib or any other components.

Ensure you have installed and activated the latest Swift 4.0 tool chain.

To learn more, you can read the full documentation guide [here](https://github.com/PerfectlySoft/PerfectDocs/blob/master/guide/SQLite.md) or jump to the example [here](#Usage-Example)


## Linux Build Notes

Ensure that you have installed sqlite3.

```
sudo apt-get install sqlite3
```

## Building

Add this project as a dependency in your Package.swift file.

```
.Package(url: "https://github.com/PerfectlySoft/Perfect-SQLite.git", majorVersion: 3)
```

### Edge Case
If you encounter error like such ``` sqlite3.h file not found ``` during ```$ swift build ```, one solution is to install the sqlite3-dev i.e. ```$ sudo apt-get install libsqlite3-dev```


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
var contentDict = [String: Any]()

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

## Further Information
For more information on the Perfect project, please visit [perfect.org](http://www.perfect.org/docs/SQLite.html).
