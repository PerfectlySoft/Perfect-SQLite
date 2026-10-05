import Testing
import Foundation
import PerfectCRUD
@testable import PerfectSQLite

// TestTable1 without its `int` column.
struct ReducedTestTable1: Codable, TableNameProvider {
    static let tableName = PerfectSQLiteTests.TestTable1.tableName
    @PrimaryKey var id: Int
    let name: String?
    let doub: Double?
    let blob: [UInt8]?
}

// TestTable1 without its `int` column and with a new column its rows have no value for.
struct ReducedRequiredTestTable1: Codable, TableNameProvider {
    static let tableName = PerfectSQLiteTests.TestTable1.tableName
    @PrimaryKey var id: Int
    let name: String?
    let doub: Double?
    let blob: [UInt8]?
    let required: Int
}

// TestTable2 without its `doub` column.
struct ReducedTestTable2: Codable, TableNameProvider {
    static let tableName = PerfectSQLiteTests.TestTable2.CRUDTableName
    @PrimaryKey var id: UUID
    @ForeignKey(PerfectSQLiteTests.TestTable1.self, onDelete: cascade, onUpdate: cascade) var parentId: Int
    let date: Date
    let name: String?
    let int: Int?
    let blob: [UInt8]?
}

// A table whose `id`, which another table references, is removed.
struct KeyRemovedParent: Codable, TableNameProvider {
    static let tableName = "key_removed_parent"
    @PrimaryKey var code: Int
    let name: String?
}

struct TwoSubTablesParent: Codable {
    @PrimaryKey var id: Int
    let alphas: [TwoSubTablesAlpha]?
    let betas: [TwoSubTablesBeta]?
}

struct TwoSubTablesAlpha: Codable {
    @PrimaryKey var id: Int
    @ForeignKey(TwoSubTablesParent.self, onDelete: cascade, onUpdate: cascade) var alphaParentId: Int
}

struct TwoSubTablesBeta: Codable {
    @PrimaryKey var id: Int
    @ForeignKey(TwoSubTablesParent.self, onDelete: cascade, onUpdate: cascade) var betaParentId: Int
}

struct ForeignKeyInfo: Equatable {
    let table: String
    let from: String
    let onDelete: String
}

extension PerfectSQLiteTests {
    func foreignKeys(_ db: Database<DBConfiguration>, of table: String) throws -> [ForeignKeyInfo] {
        var ret: [ForeignKeyInfo] = []
        try db.configuration.sqlite.forEachRow(statement: "PRAGMA foreign_key_list(\"\(table)\")") { stmt, _ in
            ret.append(.init(table: stmt.columnText(position: 2),
                             from: stmt.columnText(position: 3),
                             onDelete: stmt.columnText(position: 6)))
        }
        return ret
    }

    func columnNames(_ db: Database<DBConfiguration>, of table: String) throws -> [String] {
        var ret: [String] = []
        try db.configuration.sqlite.forEachRow(statement: "PRAGMA table_info(\"\(table)\")") { stmt, _ in
            ret.append(stmt.columnText(position: 1))
        }
        return ret
    }

    func tableNames(_ db: Database<DBConfiguration>) throws -> [String] {
        var ret: [String] = []
        try db.configuration.sqlite.forEachRow(statement: "SELECT name FROM sqlite_master WHERE type = 'table'") { stmt, _ in
            ret.append(stmt.columnText(position: 0))
        }
        return ret
    }

    // Removing a column from a table with a @ForeignKey rebuilds it with its FOREIGN KEY.
    @Test func reconcileRemovingColumnKeepsForeignKey() throws {
        let db = try getTestDB()
        try db.create(ReducedTestTable2.self, policy: [.reconcileTable, .shallow])
        let childTable = TestTable2.CRUDTableName
        #expect(try !columnNames(db, of: childTable).contains("doub"))
        #expect(try foreignKeys(db, of: childTable) == [.init(table: TestTable1.tableName, from: "parentId", onDelete: "CASCADE")])
        #expect(try db.table(ReducedTestTable2.self).count() == 25)
        try db.table(TestTable1.self).where(\TestTable1.id == 1).delete()
        #expect(try db.table(ReducedTestTable2.self).count() == 20)
    }

    // Removing a column from a table other tables reference leaves their FOREIGN KEYs
    // pointing at it, and their rows in place.
    @Test func reconcileRemovingColumnKeepsReferencesToTable() throws {
        let db = try getTestDB()
        try db.create(ReducedTestTable1.self, policy: [.reconcileTable, .shallow])
        let childTable = TestTable2.CRUDTableName
        #expect(try !columnNames(db, of: TestTable1.tableName).contains("int"))
        #expect(try db.table(ReducedTestTable1.self).count() == 5)
        #expect(try db.table(TestTable2.self).count() == 25)
        #expect(try foreignKeys(db, of: childTable) == [.init(table: TestTable1.tableName, from: "parentId", onDelete: "CASCADE")])
        #expect(try !tableNames(db).contains { $0.hasPrefix("temp_") })
        try db.table(ReducedTestTable1.self).where(\ReducedTestTable1.id == 2).delete()
        #expect(try db.table(TestTable2.self).count() == 20)
    }

    // Inside a transaction foreign_keys can't be turned off, so dropping a referenced table
    // would fire the ON DELETE CASCADE of the tables referencing it.
    @Test func reconcileRemovingColumnInTransaction() throws {
        let db = try getTestDB()
        #expect(throws: SQLiteCRUDError.self) {
            try db.transaction {
                try db.create(ReducedTestTable1.self, policy: [.reconcileTable, .shallow])
            }
        }
        #expect(try columnNames(db, of: TestTable1.tableName).contains("int"))
        #expect(try db.table(TestTable2.self).count() == 25)
        // A table nothing references can still be rebuilt in one.
        try db.transaction {
            try db.create(ReducedTestTable2.self, policy: [.reconcileTable, .shallow])
        }
        let childTable = TestTable2.CRUDTableName
        #expect(try !columnNames(db, of: childTable).contains("doub"))
        #expect(try foreignKeys(db, of: childTable) == [.init(table: TestTable1.tableName, from: "parentId", onDelete: "CASCADE")])
        #expect(try db.table(TestTable2.self).count() == 25)
    }

    // A rebuild that fails part way leaves the table as it was, foreign_keys on, and no
    // transaction open.
    @Test func reconcileRemovingColumnFailureRollsBack() throws {
        let db = try getTestDB()
        #expect(throws: (any Error).self) {
            try db.create(ReducedRequiredTestTable1.self, policy: [.reconcileTable, .shallow])
        }
        #expect(try columnNames(db, of: TestTable1.tableName).contains("int"))
        #expect(try db.table(TestTable1.self).count() == 5)
        #expect(try db.table(TestTable2.self).count() == 25)
        #expect(try !tableNames(db).contains { $0.hasPrefix("temp_") })
        var foreignKeysOn = 0
        try db.configuration.sqlite.forEachRow(statement: "PRAGMA foreign_keys") { stmt, _ in
            foreignKeysOn = stmt.columnInt(position: 0)
        }
        #expect(foreignKeysOn == 1)
        try db.transaction {
            try db.table(TestTable1.self).where(\TestTable1.id == 3).delete()
        }
        #expect(try db.table(TestTable2.self).count() == 20)
    }

    // Removing a column another table's FOREIGN KEY references would leave that table
    // failing every write with "foreign key mismatch".
    @Test func reconcileRemovingReferencedColumnFails() throws {
        let db = try getDB()
        try db.sql("CREATE TABLE key_removed_parent (id INT PRIMARY KEY, name TEXT, code INT)")
        try db.sql("CREATE TABLE key_removed_child (id INT PRIMARY KEY, pid INT REFERENCES key_removed_parent(id) ON DELETE CASCADE)")
        try db.sql("INSERT INTO key_removed_parent VALUES (1, 'one', 10), (2, 'two', 20)")
        try db.sql("INSERT INTO key_removed_child VALUES (1, 1), (2, 2)")
        #expect(throws: (any Error).self) {
            try db.create(KeyRemovedParent.self, policy: [.reconcileTable, .shallow])
        }
        #expect(try columnNames(db, of: "key_removed_parent").contains("id"))
        try db.sql("DELETE FROM key_removed_parent WHERE id = 1")
        try db.sql("INSERT INTO key_removed_child VALUES (3, 2)")
        var children = 0
        try db.configuration.sqlite.forEachRow(statement: "SELECT count(*) FROM key_removed_child") { stmt, _ in
            children = stmt.columnInt(position: 0)
        }
        #expect(children == 2)
    }

    // Each sub-table's CREATE gets its own FOREIGN KEY clauses only.
    @Test func subTablesGetOnlyTheirOwnForeignKeys() throws {
        let db = try getDB()
        try db.create(TwoSubTablesParent.self, policy: .dropTable)
        let parent = TwoSubTablesParent.CRUDTableName
        #expect(try foreignKeys(db, of: parent).isEmpty)
        #expect(try foreignKeys(db, of: TwoSubTablesAlpha.CRUDTableName) == [.init(table: parent, from: "alphaParentId", onDelete: "CASCADE")])
        #expect(try foreignKeys(db, of: TwoSubTablesBeta.CRUDTableName) == [.init(table: parent, from: "betaParentId", onDelete: "CASCADE")])
    }
}
