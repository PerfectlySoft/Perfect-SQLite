import Testing
import Foundation
import PerfectCRUD
@testable import PerfectSQLite

// Perfect-CRUD's pool and async methods need `C: Sendable`. Before
// SQLiteDatabaseConfiguration conformed, none of this compiled.
@Suite(.serialized) struct AsyncPoolTests {

    let dbName = "/tmp/crud_sqlite_async_pool_test.db"

    struct AsyncRow: Codable, Sendable, TableNameProvider {
        static let tableName = "async_row"
        let id: Int
        let name: String
    }

    func reset() throws {
        unlink(dbName)
        let db = Database(configuration: try SQLiteDatabaseConfiguration(dbName))
        try db.create(AsyncRow.self, policy: .dropTable)
    }

    @Test func asyncRoundTrip() async throws {
        try reset()
        let db = Database(configuration: try SQLiteDatabaseConfiguration(dbName))
        let table = db.table(AsyncRow.self)
        try await table.insertAsync(AsyncRow(id: 1, name: "one"))
        try await table.insertAsync([AsyncRow(id: 2, name: "two"), AsyncRow(id: 3, name: "three")])
        let inserted = try await db.transactionAsync { () throws -> Int in
            try db.table(AsyncRow.self).insert(AsyncRow(id: 4, name: "four"))
            return try db.table(AsyncRow.self).count()
        }
        #expect(inserted == 4)
        // A failing transaction rolls back.
        await #expect(throws: SQLiteCRUDError.self) {
            try await db.transactionAsync { () throws -> Int in
                try db.table(AsyncRow.self).insert(AsyncRow(id: 5, name: "five"))
                throw SQLiteCRUDError("roll back")
            }
        }
        let rows = try await table.order(by: \.id).fetchAll()
        #expect(rows.map(\.id) == [1, 2, 3, 4])
        let three = try await table.where(\AsyncRow.id == 3).firstAsync()
        #expect(three?.name == "three")
        // CRUD 3.0.0 has updateAsync/deleteAsync only on a whole Table, not after where(),
        // so a targeted change goes through transactionAsync.
        try await db.transactionAsync {
            try db.table(AsyncRow.self).where(\AsyncRow.id == 3).update(AsyncRow(id: 3, name: "THREE"))
            try db.table(AsyncRow.self).where(\AsyncRow.id == 1).delete()
        }
        let names = try await db.sqlAsync(#"SELECT "id", "name" FROM "async_row" ORDER BY "id""#, AsyncRow.self)
        #expect(names.map(\.name) == ["two", "THREE", "four"])
    }

    @Test func connectionPool() async throws {
        try reset()
        let path = dbName
        let pool = try DatabaseConnectionPool<SQLiteDatabaseConfiguration>(
            configuration: .init(minConnections: 1, maxConnections: 3)) {
            try SQLiteDatabaseConfiguration(path)
        }
        try await pool.prewarm()
        // More concurrent tasks than connections: each gets a connection of its own
        // while it runs, and the rest wait for one to come back.
        try await withThrowingTaskGroup(of: Void.self) { group in
            for id in 1...12 {
                group.addTask {
                    try await pool.withConnection { db in
                        try await db.table(AsyncRow.self).insertAsync(AsyncRow(id: id, name: "row \(id)"))
                    }
                }
            }
            try await group.waitForAll()
        }
        #expect(await pool.currentSize <= 3)
        #expect(await pool.availableCount == pool.currentSize)
        let count = try await pool.withConnection { db in
            try await db.table(AsyncRow.self).fetchAll().count
        }
        #expect(count == 12)
        // Manual acquire/release.
        let conn = try await pool.acquire()
        let ids = try Database(configuration: conn).table(AsyncRow.self).order(by: \.id).select().map(\.id)
        await pool.release(conn)
        #expect(ids == Array(1...12))
    }
}
