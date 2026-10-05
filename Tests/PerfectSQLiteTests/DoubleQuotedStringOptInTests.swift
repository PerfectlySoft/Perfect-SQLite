import Testing
import Foundation
import PerfectCRUD
@testable import PerfectSQLite

// `doubleQuotedStrings: true` restores SQLite's legacy reading of "..." as a
// string literal for apps whose raw SQL depends on it.
@Suite(.serialized) struct DoubleQuotedStringOptInTests {

    let dbName = "/tmp/crud_sqlite_dqs_optin_test.db"
    struct Count: Codable { let c: Int }

    @Test func optInRestoresLegacyStringLiterals() throws {
        unlink(dbName)
        let db = Database(configuration: try SQLiteDatabaseConfiguration(dbName, doubleQuotedStrings: true))
        try db.sql(#"CREATE TABLE "t" ("id" INTEGER PRIMARY KEY, "name" TEXT)"#)
        try db.sql(#"INSERT INTO "t" ("id", "name") VALUES (1, "legacy")"#)
        #expect(try db.sql(#"SELECT COUNT(*) AS c FROM "t" WHERE "name" = "legacy""#, Count.self)[0].c == 1)
        try db.sql(#"CREATE INDEX "t_idx" ON "t" ("nosuch")"#)
    }

    @Test func rawSQLiteDefaultsOffAndOptsIn() throws {
        unlink(dbName)
        do {
            let sqlite = try SQLite(dbName)
            defer { sqlite.close() }
            try sqlite.execute(statement: #"CREATE TABLE "t" ("id" INTEGER)"#)
            #expect(throws: SQLiteError.self) {
                try sqlite.execute(statement: #"INSERT INTO "t" ("id") VALUES ("x")"#)
            }
        }
        let legacy = try SQLite(dbName, doubleQuotedStrings: true)
        defer { legacy.close() }
        try legacy.execute(statement: #"INSERT INTO "t" ("id") VALUES ("x")"#)
        var n = 0
        try legacy.forEachRow(statement: #"SELECT COUNT(*) FROM "t""#) { st, _ in n = st.columnInt(position: 0) }
        #expect(n == 1)
    }

    // Views and triggers written with "..." strings while the fallback was on
    // are stored as text and re-parsed on use, so they break when a database
    // is opened with it off; `doubleQuotedStrings: true` keeps them working.
    @Test func storedViewsAndTriggersNeedOptIn() throws {
        unlink(dbName)
        do {
            let legacy = try SQLite(dbName, doubleQuotedStrings: true)
            defer { legacy.close() }
            try legacy.execute(statement: #"CREATE TABLE "t" ("id" INTEGER)"#)
            try legacy.execute(statement: #"CREATE TABLE "log" ("msg" TEXT)"#)
            try legacy.execute(statement: #"CREATE TRIGGER "t_ins" AFTER INSERT ON "t" BEGIN INSERT INTO "log" VALUES ("trig"); END"#)
            try legacy.execute(statement: #"CREATE VIEW "v" AS SELECT "lit" AS x"#)
        }
        do {
            let sqlite = try SQLite(dbName)
            defer { sqlite.close() }
            #expect(throws: SQLiteError.self) { try sqlite.execute(statement: #"INSERT INTO "t" VALUES (1)"#) }
            #expect(throws: SQLiteError.self) { try sqlite.execute(statement: #"SELECT * FROM "v""#) }
        }
        let legacy = try SQLite(dbName, doubleQuotedStrings: true)
        defer { legacy.close() }
        try legacy.execute(statement: #"INSERT INTO "t" VALUES (1)"#)
        var x = ""
        try legacy.forEachRow(statement: #"SELECT x FROM "v""#) { st, _ in x = st.columnText(position: 0) }
        #expect(x == "lit")
    }

    // The pre-existing initializers are still there as function references.
    @Test func originalInitializersStillExist() throws {
        let open: (String, Bool, Int) throws -> SQLite = SQLite.init(_:readOnly:busyTimeoutMillis:)
        let config: (String, [String]) throws -> SQLiteDatabaseConfiguration = SQLiteDatabaseConfiguration.init(_:_:)
        unlink(dbName)
        try open(dbName, false, 1000).close()
        _ = try config(dbName, [])
    }
}
