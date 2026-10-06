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

// An existing table reconciled to add an optional @ForeignKey column.
struct AddedForeignKeyChild: Codable, TableNameProvider {
    static let tableName = "added_fk_child"
    @PrimaryKey var id: Int
    let name: String?
    @ForeignKey(PerfectSQLiteTests.TestTable1.self, onDelete: cascade, onUpdate: cascade) var parentId: Int?
}

struct ReconcileParent: Codable {
    @PrimaryKey var id: Int
    let name: String?
    let kids: [ReconcileKid]?
}

struct ReconcileKid: Codable {
    @PrimaryKey var id: Int
    @ForeignKey(ReconcileParent.self, onDelete: cascade, onUpdate: cascade) var parentId: Int
    let note: String?
}

// ReconcileKid without its `note` column.
struct ReducedReconcileKid: Codable, TableNameProvider {
    static let tableName = ReconcileKid.CRUDTableName
    @PrimaryKey var id: Int
    @ForeignKey(ReconcileParent.self, onDelete: cascade, onUpdate: cascade) var parentId: Int
}

struct RestrictParent: Codable {
    @PrimaryKey var id: Int
    let kids: [RestrictKid]?
}

struct RestrictKid: Codable {
    @PrimaryKey var id: Int
    @ForeignKey(RestrictParent.self, onDelete: restrict, onUpdate: restrict) var parentId: Int
}

struct CaseChangedTable: Codable, TableNameProvider {
    static let tableName = "case_changed"
    @PrimaryKey var id: Int
    let name: String?
    let added: Int?
}

struct UnicodeCaseTable: Codable, TableNameProvider {
    enum CodingKeys: String, CodingKey {
        case id, cafe = "CAFÉ"
    }
    static let tableName = "unicode_case"
    @PrimaryKey var id: Int
    let cafe: String?
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
        _ = try db.transaction {
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
        _ = try db.transaction {
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

    func intValues(_ db: Database<DBConfiguration>, _ sql: String) throws -> [Int?] {
        var ret: [Int?] = []
        try db.configuration.sqlite.forEachRow(statement: sql) { stmt, _ in
            ret.append(stmt.isNull(position: 0) ? nil : stmt.columnInt(position: 0))
        }
        return ret
    }

    // A @ForeignKey column added by reconciling gets its FOREIGN KEY.
    @Test func reconcileAddingForeignKeyColumnKeepsConstraint() throws {
        let db = try getTestDB()
        try db.sql("CREATE TABLE added_fk_child (id INT PRIMARY KEY, name TEXT)")
        try db.sql("INSERT INTO added_fk_child VALUES (1, 'one'), (2, 'two')")
        try db.create(AddedForeignKeyChild.self, policy: .reconcileTable)
        #expect(try foreignKeys(db, of: "added_fk_child") == [.init(table: TestTable1.tableName, from: "parentId", onDelete: "CASCADE")])
        #expect(try intValues(db, "SELECT parentId FROM added_fk_child ORDER BY id") == [nil, nil])
        try db.sql("UPDATE added_fk_child SET parentId = 2 WHERE id = 1")
        #expect(throws: (any Error).self) {
            try db.sql("UPDATE added_fk_child SET parentId = 99 WHERE id = 2")
        }
        try db.table(TestTable1.self).where(\TestTable1.id == 2).delete()
        #expect(try intValues(db, "SELECT id FROM added_fk_child") == [2])
    }

    // Reconciling an existing table creates its missing sub-tables.
    @Test func reconcileCreatesMissingSubTables() throws {
        let db = try getDB()
        try db.create(ReconcileParent.self, policy: .shallow)
        #expect(try !tableNames(db).contains(ReconcileKid.CRUDTableName))
        try db.create(ReconcileParent.self, policy: .reconcileTable)
        #expect(try columnNames(db, of: ReconcileKid.CRUDTableName) == ["id", "parentId", "note"])
        #expect(try foreignKeys(db, of: ReconcileKid.CRUDTableName) == [.init(table: ReconcileParent.CRUDTableName, from: "parentId", onDelete: "CASCADE")])
    }

    // Reconciling an existing table reconciles its existing sub-tables.
    @Test func reconcileReconcilesExistingSubTables() throws {
        let db = try getDB()
        try db.create(ReconcileParent.self, policy: .shallow)
        try db.create(ReducedReconcileKid.self, policy: .shallow)
        try db.sql("INSERT INTO \(ReconcileParent.CRUDTableName) VALUES (1, 'one')")
        try db.sql("INSERT INTO \(ReconcileKid.CRUDTableName) VALUES (1, 1)")
        try db.create(ReconcileParent.self, policy: .reconcileTable)
        #expect(try columnNames(db, of: ReconcileKid.CRUDTableName) == ["id", "parentId", "note"])
        #expect(try db.table(ReconcileKid.self).count() == 1)
    }

    // .dropTable drops a table's sub-tables before it: with foreign_keys on, dropping a parent
    // first fails while a RESTRICT child has rows.
    @Test func dropTableDropsSubTablesFirst() throws {
        let db = try getDB()
        try db.create(RestrictParent.self, policy: .dropTable)
        try db.sql("INSERT INTO \(RestrictParent.CRUDTableName) VALUES (1)")
        try db.sql("INSERT INTO \(RestrictKid.CRUDTableName) VALUES (1, 1)")
        try db.create(RestrictParent.self, policy: .dropTable)
        #expect(try db.table(RestrictParent.self).count() == 0)
        #expect(try db.table(RestrictKid.self).count() == 0)
        #expect(try foreignKeys(db, of: RestrictKid.CRUDTableName) == [.init(table: RestrictParent.CRUDTableName, from: "parentId", onDelete: "RESTRICT")])
    }

    // A column whose name differs only in case is the same column: its data is kept, and it's
    // renamed to the model's spelling so rows decode.
    @Test func reconcileMatchesColumnNamesIgnoringCase() throws {
        let db = try getDB()
        // A column to remove, so the table is rebuilt.
        try db.sql("CREATE TABLE case_changed (ID INT PRIMARY KEY, Name TEXT, gone INT)")
        try db.sql("INSERT INTO case_changed VALUES (1, 'one', 0)")
        try db.create(CaseChangedTable.self, policy: .reconcileTable)
        #expect(try columnNames(db, of: "case_changed") == ["id", "name", "added"])
        #expect(try db.table(CaseChangedTable.self).first()?.name == "one")
        // Nothing to remove: the columns are renamed in place.
        try db.sql("DROP TABLE case_changed")
        try db.sql("CREATE TABLE case_changed (ID INT PRIMARY KEY, Name TEXT)")
        try db.sql("INSERT INTO case_changed VALUES (1, 'one')")
        try db.create(CaseChangedTable.self, policy: .reconcileTable)
        #expect(try columnNames(db, of: "case_changed") == ["id", "name", "added"])
        #expect(try db.table(CaseChangedTable.self).first()?.name == "one")
    }

    // SQLite folds only ASCII letters, so "café" and "CAFÉ" are different columns.
    @Test func reconcileFoldsOnlyASCIICase() throws {
        let db = try getDB()
        try db.sql("CREATE TABLE unicode_case (id INT PRIMARY KEY, \"café\" TEXT, \"CAFÉ\" TEXT)")
        try db.sql("INSERT INTO unicode_case VALUES (1, 'lower', 'upper')")
        try db.create(UnicodeCaseTable.self, policy: .reconcileTable)
        #expect(try columnNames(db, of: "unicode_case") == ["id", "CAFÉ"])
        #expect(try db.table(UnicodeCaseTable.self).first()?.cafe == "upper")
        try db.sql("DROP TABLE unicode_case")
        try db.sql("CREATE TABLE unicode_case (id INT PRIMARY KEY, \"café\" TEXT)")
        try db.create(UnicodeCaseTable.self, policy: .reconcileTable)
        #expect(try columnNames(db, of: "unicode_case") == ["id", "CAFÉ"])
    }
}
