//
//  SQLiteTests.swift
//  Perfect-SQLite
//
//  Created by Kyle Jessup on 2016-04-09.
//  Copyright © 2016 PerfectlySoft. All rights reserved.
//

import XCTest
#if os(Linux)
    import SwiftGlibc
	import Dispatch
#else
    import Darwin
#endif

@testable import PerfectSQLite

let testDb = "/tmp/sqlitetest.db"

class PerfectSQLiteTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
		unlink(testDb)
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
	func testSQLite() {
		
		do {
			
			let sqlite = try SQLite(testDb)
			
			try sqlite.execute(statement: "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT, int, doub, blob)")
			
			try sqlite.doWithTransaction {
				try sqlite.execute(statement: "INSERT INTO test (id,name,int,doub,blob) VALUES (?,?,?,?,?)", count: 5) {
					(stmt: SQLiteStmt, num: Int) throws -> () in
					
					try stmt.bind(position: 1, num)
					try stmt.bind(position: 2, "This is name bind \(num)")
					try stmt.bind(position: 3, num)
					try stmt.bind(position: 4, Double(num))
					let num = Int8(num)
					try stmt.bind(position: 5, [Int8](arrayLiteral: num+1, num+2, num+3, num+4, num+5))
				}
			}
			
			try sqlite.forEachRow(statement: "SELECT name,int,doub,blob FROM test ORDER BY id") {
				(stmt: SQLiteStmt, num: Int) -> () in
				
				let name = stmt.columnText(position: 0)
				let int = stmt.columnInt(position: 1)
				let doub = stmt.columnDouble(position: 2)
				let blob: [Int8] = stmt.columnIntBlob(position: 3)
				
				XCTAssert(name == "This is name bind \(num)")
				XCTAssert(int == num)
				XCTAssert(doub == Double(num))
				
				let model: [Int8] = [1, 2, 3, 4, 5]
				let num = Int8(num)
				for idx in 0..<blob.count {
					XCTAssert(model[idx] + num == blob[idx])
				}
			}
			
			sqlite.close()
			
		} catch let e {
			XCTAssert(false, "Exception while testing SQLite \(e)")
			return
		}
	}

	func testKeyViolation() {
		
		do {
			
			let sqlite = try SQLite(testDb)
			try sqlite.execute(statement: "CREATE TABLE test (id INTEGER PRIMARY KEY)")
			try sqlite.execute(statement: "INSERT INTO test VALUES (1)")
			try sqlite.execute(statement: "INSERT INTO test VALUES (1)")
			XCTAssert(false)
			sqlite.close()
			
		} catch let e {
			XCTAssert(true, "Exception while testing SQLite \(e)")
			return
		}
	}
	
	func testHandleRowThrowing() {
		do {
			
			let sqlite = try SQLite(testDb)
			try sqlite.execute(statement: "CREATE TABLE test (id INTEGER PRIMARY KEY)")
			try sqlite.execute(statement: "INSERT INTO test VALUES (1)")
			try sqlite.execute(statement: "INSERT INTO test VALUES (2)")
			try sqlite.forEachRow(statement: "SELECT * FROM test;") {
				stmt, num in
				throw SQLiteError.Error(code: 99, msg: "TEST")
			}
			XCTAssert(false)
			sqlite.close()
			
		} catch let e {
			guard let error = e as? SQLiteError else {
				XCTAssert(false)
				return
			}
			XCTAssertEqual("\(error)", "Error(code: 99, msg: \"TEST\")", "Exception while testing SQLite.")
			return
		}
	}


	func testParamBinding() {

		do {

			let sqlite = try SQLite(testDb)

			try sqlite.execute(statement: "CREATE TABLE testtext (id TEXT PRIMARY KEY NOT NULL, url TEXT NOT NULL, akey TEXT NOT NULL)")


			try sqlite.execute(statement: "INSERT INTO testtext (id, url, akey) VALUES(?,?,?)", count: 1) {
				(stmt: SQLiteStmt, num: Int) throws -> () in

				try stmt.bind(position: 1, "860bdc6f-49e5-4719-9604-45f46306fe5b")
				try stmt.bind(position: 2, "http://www.perfect.org")
				try stmt.bind(position: 3, "epuT6ZdN")
			}
			try sqlite.execute(statement: "INSERT INTO testtext (id, url, akey) VALUES(?,?,?)", count: 1) {
				(stmt: SQLiteStmt, num: Int) throws -> () in

				try stmt.bind(position: 1, "2eb6d068-280d-44e9-b364-5792d889f577")
				try stmt.bind(position: 2, "http://www.treefrog.ca")
				try stmt.bind(position: 3, "tcMBSxPO")
			}



			var id = ""
			var url = ""
			var akey = ""
			let option = "epuT6ZdN"

			try sqlite.forEachRow(statement: "SELECT id, url, akey FROM testtext WHERE akey = ?", doBindings: {

				(statement: SQLiteStmt) -> () in
				try statement.bind(position: 1, option)

			}, handleRow: {(statement: SQLiteStmt, i:Int) -> () in
				id = String(statement.columnText(position: 0))
				url = String(statement.columnText(position: 1))
				akey = String(statement.columnText(position: 2))
			})

			XCTAssert(id == "860bdc6f-49e5-4719-9604-45f46306fe5b", "ID does not match \(id)")
			XCTAssert(url == "http://www.perfect.org", "URL does not match.")
			XCTAssert(akey == "epuT6ZdN", "akey does not match.")



			sqlite.close()

		} catch let e {
			XCTAssert(false, "Exception while testing SQLite \(e)")
			return
		}
	}

	func testMultiThread1() {
		do {
			let sqlite = try SQLite(testDb)
			defer {
				sqlite.close()
			}
			try sqlite.execute(statement: "CREATE TABLE test (id INTEGER PRIMARY KEY)")
		} catch let e {
			XCTAssert(false, "Exception while testing SQLite \(e)")
			return
		}
		do {
			
			let expect = self.expectation(description: "Worker thread")
			
			DispatchQueue.global(qos: .default).async {
				defer {
					expect.fulfill()
				}
				for loop in 1...10 {
					do {
						let sqlite = try SQLite(testDb)
						defer {
							sqlite.close()
						}
						try sqlite.execute(statement: "SELECT * FROM test")
					} catch {
						XCTAssert(false, "Exception while testing SQLite \(error) in loop \(loop)")
					}
				}
			}
		
			let sqlite = try SQLite(testDb)
			defer {
				sqlite.close()
			}
			
			for i in 1...1000 {
				try sqlite.execute(statement: "INSERT INTO test (id) VALUES (\(i))")
			}
		} catch let e {
			XCTAssert(false, "Exception while testing SQLite \(e)")
			return
		}
		self.waitForExpectations(timeout: 1000.0) {
			_ in
			
		}
	}
	
	func testNullChecking() {
		do {
			let sqlite = try SQLite(testDb)
			
			try sqlite.execute(statement: "CREATE TABLE testNullChecking (id TEXT PRIMARY KEY NOT NULL, name TEXT, int, doub, blob)")
			
			// Insert a row where all fields are null
			try sqlite.doWithTransaction {
				try sqlite.execute(statement: "INSERT INTO testNullChecking (id,name,int,doub,blob) VALUES (?,?,?,?,?)") {
					(stmt: SQLiteStmt) throws -> () in
					
					try stmt.bind(position: 1, "null_row")
					try stmt.bind(position: 2, nil)
					try stmt.bind(position: 3, nil)
					try stmt.bind(position: 4, nil)
					try stmt.bind(position: 5, nil)
				}
			}

			// Insert a row where none of the fields are null
			try sqlite.doWithTransaction {
				try sqlite.execute(statement: "INSERT INTO testNullChecking (id,name,int,doub,blob) VALUES (?,?,?,?,?)") {
					(stmt: SQLiteStmt) throws -> () in
					
					try stmt.bind(position: 1, "nonnull_row")
					try stmt.bind(position: 2, "World peace")
					try stmt.bind(position: 3, 42)
					try stmt.bind(position: 4, Double(42))
					try stmt.bind(position: 5, [Int8](arrayLiteral: 0, 1, 2, 3))
				}
			}
			
			// Verify that all the fields are null
			try sqlite.forEachRow(statement: "SELECT name,int,doub,blob FROM testNullChecking WHERE id = ?", doBindings: {(stmt: SQLiteStmt) -> () in
				try stmt.bind(position: 1, "null_row")
			}, handleRow: {(stmt: SQLiteStmt, i:Int) -> () in
				let allNull = stmt.isNull(position: 0) && stmt.isNull(position: 1) && stmt.isNull(position: 2) && stmt.isNull(position: 3)
				XCTAssertTrue(allNull)

				let oneOrMoreHasData = stmt.isText(position: 0) || stmt.isInteger(position: 1) || stmt.isFloat(position: 2) || stmt.isBlob(position: 3)
				XCTAssertFalse(oneOrMoreHasData)
			})
			
			// Verify that none of the fields are null
			try sqlite.forEachRow(statement: "SELECT name,int,doub,blob FROM testNullChecking WHERE id = ?", doBindings: {(stmt: SQLiteStmt) -> () in
				try stmt.bind(position: 1, "nonnull_row")
			}, handleRow: {(stmt: SQLiteStmt, i:Int) -> () in
				let oneOrMoreIsNull = stmt.isNull(position: 0) || stmt.isNull(position: 1) || stmt.isNull(position: 2) || stmt.isNull(position: 3)
				XCTAssertFalse(oneOrMoreIsNull)

				let allHasData = stmt.isText(position: 0) && stmt.isInteger(position: 1) && stmt.isFloat(position: 2) && stmt.isBlob(position: 3)
				XCTAssertTrue(allHasData)
			})
			
			sqlite.close()
			
		} catch let e {
			XCTAssert(false, "Exception while testing SQLite \(e)")
			return
		}
	}
}

extension PerfectSQLiteTests {
    static var allTests : [(String, (PerfectSQLiteTests) -> () throws -> ())] {
        return [
			("testSQLite", testSQLite),
			("testKeyViolation", testKeyViolation),
			("testParamBinding", testParamBinding),
			("testHandleRowThrowing", testHandleRowThrowing),
			("testMultiThread1", testMultiThread1),
			("testNullChecking", testNullChecking)
        ]
    }
}

