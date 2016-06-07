import XCTest

import SQLiteTestSuite

var tests = [XCTestCaseEntry]()
tests += SQLiteTestSuite.allTests()
XCTMain(tests)
