import SQLite3

public struct SQLiteError: Error, CustomStringConvertible {
    public let code: Int
    public let description: String
    public init(code: Int, description: String) {
        self.code = code
        self.description = description
    }
}

public class SQLite {

    let path: String
    var sqlite3 = OpaquePointer(bitPattern: 0)

    public init(_ path: String, readOnly: Bool = false, busyTimeoutMillis: Int = 600000) throws {
        self.path = path
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        let res = sqlite3_open_v2(path, &self.sqlite3, flags, nil)
        if res != SQLITE_OK {
            throw SQLiteError(code: Int(res), description: "Unable to open database \(path)")
        }
        sqlite3_busy_timeout(self.sqlite3, Int32(busyTimeoutMillis))
    }

    public func close() {
        if self.sqlite3 != nil {
            sqlite3_close(self.sqlite3)
            self.sqlite3 = nil
        }
    }

    public func close<T>(after: (SQLite) -> T) -> T {
        defer { close() }
        return after(self)
    }

    deinit { close() }

    public func prepare(statement stat: String) throws -> SQLiteStmt {
        var statPtr = OpaquePointer(bitPattern: 0)
        let tail = UnsafeMutablePointer<UnsafePointer<Int8>?>(nil as OpaquePointer?)
        let res = sqlite3_prepare_v2(self.sqlite3, stat, Int32(stat.utf8.count), &statPtr, tail)
        try checkRes(res)
        return SQLiteStmt(db: self.sqlite3, stat: statPtr)
    }

    public func lastInsertRowID() -> Int { Int(sqlite3_last_insert_rowid(self.sqlite3)) }
    public func totalChanges() -> Int    { Int(sqlite3_total_changes(self.sqlite3)) }
    public func changes() -> Int         { Int(sqlite3_changes(self.sqlite3)) }
    public func errCode() -> Int         { Int(sqlite3_errcode(self.sqlite3)) }

    public func errMsg() -> String {
        String(cString: sqlite3_errmsg(self.sqlite3))
    }

    public func execute(statement: String) throws {
        try forEachRow(statement: statement, doBindings: { _ in }) { _, _ in }
    }

    public func execute(statement: String, doBindings: (SQLiteStmt) throws -> ()) throws {
        try forEachRow(statement: statement, doBindings: doBindings) { _, _ in }
    }

    public func execute(statement: String, count: Int, doBindings: (SQLiteStmt, Int) throws -> ()) throws {
        let stat = try prepare(statement: statement)
        defer { stat.finalize() }
        for idx in 1...count {
            try doBindings(stat, idx)
            try forEachRowBody(stat: stat) { _, _ in }
            let _ = try stat.reset()
        }
    }

    public func doWithTransaction(closure: () throws -> ()) throws {
        try execute(statement: "BEGIN")
        do {
            try closure()
            try execute(statement: "COMMIT")
        } catch {
            try execute(statement: "ROLLBACK")
            throw error
        }
    }

    public func forEachRow(statement: String, handleRow: (SQLiteStmt, Int) throws -> ()) throws {
        let stat = try prepare(statement: statement)
        defer { stat.finalize() }
        try forEachRowBody(stat: stat, handleRow: handleRow)
    }

    public func forEachRow(statement: String,
                           doBindings: (SQLiteStmt) throws -> (),
                           handleRow: (SQLiteStmt, Int) throws -> ()) throws {
        let stat = try prepare(statement: statement)
        defer { stat.finalize() }
        try doBindings(stat)
        try forEachRowBody(stat: stat, handleRow: handleRow)
    }

    func forEachRowBody(stat: SQLiteStmt, handleRow: (SQLiteStmt, Int) throws -> ()) throws {
        var r = stat.step()
        guard r == SQLITE_ROW || r == SQLITE_DONE else {
            try checkRes(r)
            return
        }
        var rowNum = 1
        while r == SQLITE_ROW {
            try handleRow(stat, rowNum)
            rowNum += 1
            r = stat.step()
        }
    }

    func checkRes(_ res: Int32) throws { try checkRes(Int(res)) }

    func checkRes(_ res: Int) throws {
        if res != Int(SQLITE_OK) {
            throw SQLiteError(code: res, description: String(cString: sqlite3_errmsg(self.sqlite3)))
        }
    }
}

extension SQLite: @unchecked Sendable {}

public class SQLiteStmt {

    let db: OpaquePointer?
    var stat: OpaquePointer?

    typealias sqlite_destructor = @convention(c) (UnsafeMutableRawPointer?) -> Void

    init(db: OpaquePointer?, stat: OpaquePointer?) {
        self.db = db
        self.stat = stat
    }

    public func close()    { finalize() }
    public func finalize() {
        if self.stat != nil {
            sqlite3_finalize(self.stat!)
            self.stat = nil
        }
    }

    public func step() -> Int32 {
        guard self.stat != nil else { return SQLITE_MISUSE }
        return sqlite3_step(self.stat!)
    }

    // MARK: bind by position

    public func bind(position: Int, _ d: Double)  throws { try checkRes(sqlite3_bind_double(self.stat!, Int32(position), d)) }
    public func bind(position: Int, _ i: Int32)   throws { try checkRes(sqlite3_bind_int(self.stat!, Int32(position), i)) }
    public func bind(position: Int, _ i: Int)     throws { try checkRes(sqlite3_bind_int64(self.stat!, Int32(position), Int64(i))) }
    public func bind(position: Int, _ i: Int64)   throws { try checkRes(sqlite3_bind_int64(self.stat!, Int32(position), i)) }

    public func bind(position: Int, _ s: String) throws {
        try checkRes(sqlite3_bind_text(self.stat!, Int32(position), s, Int32(s.utf8.count),
                                       unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite_destructor.self)))
    }

    public func bind(position: Int, _ b: [Int8]) throws {
        try checkRes(sqlite3_bind_blob(self.stat!, Int32(position), b, Int32(b.count),
                                       unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite_destructor.self)))
    }

    public func bind(position: Int, _ b: [UInt8]) throws {
        try checkRes(sqlite3_bind_blob(self.stat!, Int32(position), b, Int32(b.count),
                                       unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite_destructor.self)))
    }

    public func bindZeroBlob(position: Int, count: Int) throws {
        try checkRes(sqlite3_bind_zeroblob(self.stat!, Int32(position), Int32(count)))
    }

    public func bindNull(position: Int) throws {
        try checkRes(sqlite3_bind_null(self.stat!, Int32(position)))
    }

    // MARK: bind by name

    public func bind(name: String, _ d: Double)  throws { try bind(position: try bindParameterIndex(name: name), d) }
    public func bind(name: String, _ i: Int32)   throws { try bind(position: try bindParameterIndex(name: name), i) }
    public func bind(name: String, _ i: Int)     throws { try bind(position: try bindParameterIndex(name: name), i) }
    public func bind(name: String, _ i: Int64)   throws { try bind(position: try bindParameterIndex(name: name), i) }
    public func bind(name: String, _ s: String)  throws { try bind(position: try bindParameterIndex(name: name), s) }

    public func bind(name: String, _ b: [Int8]) throws {
        try checkRes(sqlite3_bind_text(self.stat!, Int32(try bindParameterIndex(name: name)), b, Int32(b.count),
                                       unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite_destructor.self)))
    }

    public func bindZeroBlob(name: String, count: Int) throws {
        try checkRes(sqlite3_bind_zeroblob(self.stat!, Int32(try bindParameterIndex(name: name)), Int32(count)))
    }

    public func bindNull(name: String) throws {
        try checkRes(sqlite3_bind_null(self.stat!, Int32(try bindParameterIndex(name: name))))
    }

    public func bindParameterIndex(name: String) throws -> Int {
        let idx = sqlite3_bind_parameter_index(self.stat!, name)
        guard idx != 0 else {
            throw SQLiteError(code: Int(SQLITE_MISUSE), description: "The indicated bind parameter name was not found.")
        }
        return Int(idx)
    }

    public func reset() throws -> Int {
        let res = sqlite3_reset(self.stat!)
        try checkRes(res)
        return Int(res)
    }

    // MARK: column reading

    public func columnCount() -> Int { Int(sqlite3_column_count(self.stat!)) }

    public func columnName(position: Int) -> String {
        String(cString: sqlite3_column_name(self.stat!, Int32(position)))
    }

    public func columnDeclType(position: Int) -> String {
        guard let ptr = sqlite3_column_decltype(self.stat!, Int32(position)) else { return "" }
        return String(cString: ptr)
    }

    @available(*, deprecated, renamed: "columnIntBlob")
    public func columnBlob(position: Int) -> [Int8] { columnIntBlob(position: position) }

    public func columnIntBlob<I: BinaryInteger>(position: Int) -> [I] {
        let vp    = sqlite3_column_blob(self.stat!, Int32(position))
        let vpLen = Int(sqlite3_column_bytes(self.stat!, Int32(position)))
        guard vpLen > 0 else { return [] }
        var ret = [I]()
        if var bytesPtr = vp?.bindMemory(to: I.self, capacity: vpLen) {
            for _ in 0..<vpLen {
                ret.append(bytesPtr.pointee)
                bytesPtr = bytesPtr.successor()
            }
        }
        return ret
    }

    public func columnDouble(position: Int) -> Double { Double(sqlite3_column_double(self.stat!, Int32(position))) }
    public func columnInt(position: Int)   -> Int    { Int(sqlite3_column_int64(self.stat!, Int32(position))) }
    public func columnInt32(position: Int) -> Int32  { sqlite3_column_int(self.stat!, Int32(position)) }
    public func columnInt64(position: Int) -> Int64  { sqlite3_column_int64(self.stat!, Int32(position)) }

    public func columnText(position: Int) -> String {
        guard let ptr = sqlite3_column_text(self.stat!, Int32(position)) else { return "" }
        return ptr.withMemoryRebound(to: CChar.self, capacity: 0) { String(cString: $0) }
    }

    public func columnType(position: Int) -> Int32 { sqlite3_column_type(self.stat!, Int32(position)) }

    public func isInteger(position: Int) -> Bool { SQLITE_INTEGER == columnType(position: position) }
    public func isFloat(position: Int)   -> Bool { SQLITE_FLOAT   == columnType(position: position) }
    public func isText(position: Int)    -> Bool { SQLITE_TEXT    == columnType(position: position) }
    public func isBlob(position: Int)    -> Bool { SQLITE_BLOB    == columnType(position: position) }
    public func isNull(position: Int)    -> Bool { SQLITE_NULL    == columnType(position: position) }

    func checkRes(_ res: Int32) throws { try checkRes(Int(res)) }

    func checkRes(_ res: Int) throws {
        if res != Int(SQLITE_OK) {
            throw SQLiteError(code: res, description: String(cString: sqlite3_errmsg(self.db!)))
        }
    }

    deinit { finalize() }
}

extension SQLiteStmt: @unchecked Sendable {}
