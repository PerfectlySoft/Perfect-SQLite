import Testing
import Foundation
import PerfectCRUD
@testable import PerfectSQLite

// SQLite's double-quoted string literal misfeature (DQS): with it on, a
// double-quoted name that matches no column is read as a string literal.
// CRUD's Dynamic API quotes caller-supplied field names with `"`, so a
// misspelled field silently compared two constants, and a caller who also
// controls the value could match every row (`"nmae" = 'nmae'`). The macOS
// SDK SQLite and Ubuntu's libsqlite3 both ship with DQS on.
@Suite(.serialized) struct DoubleQuotedStringTests {

    let dbName = "/tmp/crud_sqlite_dqs_test.db"
    struct Count: Codable { let c: Int }

    func makeDB() throws -> Database<SQLiteDatabaseConfiguration> {
        unlink(dbName)
        let db = Database(configuration: try SQLiteDatabaseConfiguration(dbName))
        try db.sql(#"CREATE TABLE "dqs_victim" ("id" INTEGER PRIMARY KEY, "name" TEXT)"#)
        try db.sql(#"INSERT INTO "dqs_victim" ("id", "name") VALUES (1, 'a'), (2, 'b'), (3, 'c')"#)
        return db
    }

    func count(_ db: Database<SQLiteDatabaseConfiguration>, _ whereClause: String = "") throws -> Int {
        try db.sql(#"SELECT COUNT(*) AS c FROM "dqs_victim" "# + whereClause, Count.self)[0].c
    }

    // Any SQLiteError isn't enough: broken quoting would be a syntax error.
    func expectNoSuchColumn(_ body: () throws -> Any,
                            sourceLocation: SourceLocation = #_sourceLocation) throws {
        let error = #expect(throws: SQLiteError.self, sourceLocation: sourceLocation) { _ = try body() }
        #expect(error?.description.contains("no such column") == true,
                "\(String(describing: error))", sourceLocation: sourceLocation)
    }

    @Test func dynamicDeleteWithUnknownFieldThrows() throws {
        let db = try makeDB()
        // DQS on: `DELETE ... WHERE 'nmae' = 'nmae'` deleted all three rows.
        try expectNoSuchColumn {
            try db.mutate(DynamicMutation(
                action: .delete, table: "dqs_victim",
                predicates: [.init(field: "nmae", comparison: .equal, value: .string("nmae"))]))
        }
        #expect(try count(db) == 3)
        // A misspelled field whose comparison is false must throw too, not
        // quietly delete nothing.
        try expectNoSuchColumn {
            try db.mutate(DynamicMutation(
                action: .delete, table: "dqs_victim",
                predicates: [.init(field: "nmae", comparison: .equal, value: .string("a"))]))
        }
        // Known fields still work. (`affectedRows` is always 0 on this
        // connector, so count rows instead.)
        _ = try db.mutate(DynamicMutation(
            action: .delete, table: "dqs_victim",
            predicates: [.init(field: "name", comparison: .equal, value: .string("a"))]))
        #expect(try count(db) == 2)
    }

    @Test func dynamicUpdateWithUnknownFieldThrows() throws {
        let db = try makeDB()
        // DQS on: `UPDATE ... SET "name" = 'z' WHERE 'nmae' = 'nmae'` rewrote every row.
        try expectNoSuchColumn {
            try db.mutate(DynamicMutation(
                action: .update, table: "dqs_victim",
                values: ["name": .string("z")],
                predicates: [.init(field: "nmae", comparison: .equal, value: .string("nmae"))]))
        }
        #expect(try count(db, #"WHERE "name" = 'z'"#) == 0)
        // Other comparisons go through the same quoting.
        try expectNoSuchColumn {
            try db.mutate(DynamicMutation(
                action: .update, table: "dqs_victim",
                values: ["name": .string("z")],
                predicates: [.init(field: "nmae", comparison: .notEqual, value: .string("x"))]))
        }
        #expect(try count(db, #"WHERE "name" = 'z'"#) == 0)
        _ = try db.mutate(DynamicMutation(
            action: .update, table: "dqs_victim",
            values: ["name": .string("z")],
            predicates: [.init(field: "id", comparison: .equal, value: .int(2))]))
        #expect(try count(db, #"WHERE "name" = 'z'"#) == 1)
    }

    @Test func doubleQuotedNameIsNeverAStringLiteral() throws {
        let db = try makeDB()
        // DML: an unknown "..." is "no such column", not the string 'nmae'.
        try expectNoSuchColumn {
            try db.sql(#"DELETE FROM "dqs_victim" WHERE "nmae" = 'nmae'"#)
        }
        #expect(try count(db) == 3)
        // DDL: same for an index on a column that doesn't exist.
        try expectNoSuchColumn {
            try db.sql(#"CREATE INDEX "dqs_idx" ON "dqs_victim" ("nosuch")"#)
        }
        // Single-quoted string literals are unaffected.
        #expect(try count(db, #"WHERE "name" = 'b'"#) == 1)
    }
}
