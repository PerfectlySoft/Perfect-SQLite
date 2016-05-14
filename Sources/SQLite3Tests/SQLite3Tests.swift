//
//  Perfect_SQLite3Tests.swift
//  Perfect-SQLite3Tests
//
//  Created by Kyle Jessup on 2016-04-09.
//  Copyright © 2016 PerfectlySoft. All rights reserved.
//

import XCTest
import Darwin
@testable import SQLite

let testDb = "/tmp/sqlitetest.db"

class Perfect_SQLite3Tests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
		Darwin.unlink(testDb)
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
					try stmt.bind(position: 5, [Int8](arrayLiteral: num+1, num+2, num+3, num+4, num+5))
				}
			}
			
			try sqlite.forEachRow(statement: "SELECT name,int,doub,blob FROM test ORDER BY id") {
				(stmt: SQLiteStmt, num: Int) -> () in
				
				let name = stmt.columnText(position: 0)
				let int = stmt.columnInt(position: 1)
				let doub = stmt.columnDouble(position: 2)
				let blob = stmt.columnBlob(position: 3)
				
				XCTAssert(name == "This is name bind \(num)")
				XCTAssert(int == num)
				XCTAssert(doub == Double(num))
				
				let model: [Int8] = [1, 2, 3, 4, 5]
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
}
