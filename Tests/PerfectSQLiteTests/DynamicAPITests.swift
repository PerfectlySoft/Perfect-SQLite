import Testing
import Foundation
import PerfectCRUD
@testable import PerfectSQLite

// Perfect-CRUD's Dynamic API (select / mutate / execute) on this connector.
@Suite(.serialized) struct DynamicAPITests {

    let dbName = "/tmp/crud_sqlite_dynamic_test.db"
    struct Count: Codable { let c: Int }

    func makeDB() throws -> Database<SQLiteDatabaseConfiguration> {
        unlink(dbName)
        let db = Database(configuration: try SQLiteDatabaseConfiguration(dbName))
        try db.sql(#"CREATE TABLE "dyn" ("id" INTEGER PRIMARY KEY, "name" TEXT, "n" INTEGER)"#)
        try db.sql(#"INSERT INTO "dyn" ("id", "name", "n") VALUES (1, 'a', 10), (2, 'b', 20), (3, 'c', NULL)"#)
        return db
    }

    func count(_ db: Database<SQLiteDatabaseConfiguration>) throws -> Int {
        try db.sql(#"SELECT COUNT(*) AS c FROM "dyn""#, Count.self)[0].c
    }

    @Test func dynamicSelectReturnsRows() throws {
        let db = try makeDB()
        let all = try db.select(DynamicQuery(table: "dyn", orderings: [.init(field: "id")]))
        #expect(all.rows.count == 3)
        #expect(all.rows[0]["id"] == .int(1))
        #expect(all.rows[0]["name"] == .string("a"))
        #expect(all.rows[2]["n"] == .null)
        let some = try db.select(DynamicQuery(
            table: "dyn", fields: ["name"],
            predicates: [.init(field: "n", comparison: .greaterThan, value: .int(15))]))
        #expect(some.rows == [DynamicRow(["name": .string("b")])])
    }

    @Test func dynamicExecuteReturnsRows() throws {
        let db = try makeDB()
        let result = try db.execute(DynamicSQL(
            sql: #"SELECT "id", "name" FROM "dyn" WHERE "id" >= ? ORDER BY "id""#,
            bindings: [.int(2)]))
        #expect(result.rows.map { $0["id"] } == [.int(2), .int(3)])
        #expect(result.rows.map { $0["name"] } == [.string("b"), .string("c")])
        // A single statement with a trailing `;` and comment is still one statement.
        let one = try db.execute(DynamicSQL(sql: "SELECT 1 AS x; -- done\n  ", allowsMultipleStatements: true))
        #expect(one.rows == [DynamicRow(["x": .int(1)])])
    }

    // sqlite3_prepare_v2 stops after the first statement, so with
    // allowsMultipleStatements the second INSERT used to be dropped silently.
    @Test func dynamicExecuteRefusesMultipleStatements() throws {
        let db = try makeDB()
        let sql = #"INSERT INTO "dyn" ("id") VALUES (10); INSERT INTO "dyn" ("id") VALUES (11)"#
        let error = #expect(throws: SQLiteCRUDError.self) {
            try db.execute(DynamicSQL(sql: sql, allowsMultipleStatements: true))
        }
        #expect(error?.description.contains("more than one statement") == true)
        #expect(try count(db) == 3) // neither statement ran
        // A second statement that can't be prepared yet (its table doesn't exist) is
        // still refused rather than ignored.
        #expect(throws: SQLiteCRUDError.self) {
            try db.execute(DynamicSQL(
                sql: #"CREATE TABLE "later" ("id" INTEGER); INSERT INTO "later" VALUES (1)"#,
                allowsMultipleStatements: true))
        }
        #expect(throws: SQLiteCRUDError.self) {
            try db.sql(#"DELETE FROM "dyn" WHERE "id" = 1; /* c */ DELETE FROM "dyn""#)
        }
        #expect(try count(db) == 3)
    }

    // `.uint` binds as CRUD's `.uinteger64`; above Int64.max it used to trap in `Int(i)`.
    @Test func unsignedValuesOutOfRangeThrow() throws {
        let db = try makeDB()
        let max = Int64.max
        _ = try db.mutate(DynamicMutation(action: .insert, table: "dyn",
                                          values: ["id": .int(4), "n": .uint(UInt64(max))]))
        let row = try db.select(DynamicQuery(
            table: "dyn", predicates: [.init(field: "id", comparison: .equal, value: .int(4))]))
        #expect(row.rows.first?["n"] == .int(max))
        let error = #expect(throws: SQLiteCRUDError.self) {
            try db.mutate(DynamicMutation(action: .insert, table: "dyn",
                                          values: ["id": .int(5), "n": .uint(UInt64.max)]))
        }
        #expect(error?.description.contains("doesn't fit") == true)
        #expect(throws: SQLiteCRUDError.self) {
            try db.execute(DynamicSQL(sql: "SELECT ? AS x", bindings: [.uint(UInt64(max) + 1)]))
        }
        // A typed comparison with a UInt binds `.uinteger`, which trapped the same way.
        struct Unsigned: Codable, TableNameProvider {
            static let tableName = "dyn_unsigned"
            let id: Int
            let u: UInt
        }
        try db.sql(#"CREATE TABLE "dyn_unsigned" ("id" INTEGER PRIMARY KEY, "u" INTEGER)"#)
        try db.sql(#"INSERT INTO "dyn_unsigned" VALUES (1, 5)"#)
        #expect(try db.table(Unsigned.self).where(\Unsigned.u < UInt(6)).count() == 1)
        #expect(throws: SQLiteCRUDError.self) {
            try db.table(Unsigned.self).where(\Unsigned.u < UInt.max).count()
        }
        // Typed UInt/UInt64 properties don't reach this code: CRUD 3.0.0's encoder converts
        // them to `.integer(Int(value))` itself (and traps there above Int.max).
    }
}
