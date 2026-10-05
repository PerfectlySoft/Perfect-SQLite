//
//  SQLiteCRUD.swift
//
//  Created by Kyle Jessup on 2017-11-28.
//

import Foundation
import PerfectCRUD
#if canImport(SQLite3)
import SQLite3
#else
import PerfectCSQLite
#endif

public struct SQLiteCRUDError: Error, CustomStringConvertible {
	public let description: String
	init(_ m: String) {
		description = m
		CRUDLogging.log(.error, m)
	}
}

// maps column name to position which must be computed once before row reading action
typealias SQLiteCRUDColumnMap = [String:Int]

class SQLiteCRUDRowReader<K: CodingKey>: KeyedDecodingContainerProtocol, @unchecked Sendable {
	typealias Key = K
	var codingPath: [CodingKey] = []
	var allKeys: [Key] = []
	let database: SQLite
	let statement: SQLiteStmt
	let columns: SQLiteCRUDColumnMap
	// the SQLiteStmt has been successfully step()ed to the next row
	init(_ db: SQLite, stat: SQLiteStmt, columns cols: SQLiteCRUDColumnMap) {
		database = db
		statement = stat
		columns = cols
	}
	func columnPosition(_ key: Key) throws -> Int {
		guard let pos = columns[key.stringValue] else {
			throw CRUDDecoderError("Unrecognized key: \(key.stringValue)")
		}
		return pos
	}
	func contains(_ key: Key) -> Bool {
		return nil != columns[key.stringValue]
	}
	func decodeNil(forKey key: Key) throws -> Bool {
		return statement.isNull(position: try columnPosition(key))
	}
	func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
		return statement.columnInt(position: try columnPosition(key)) == 1
	}
	func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
		return statement.columnInt(position: try columnPosition(key))
	}
	func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
		return type.init(statement.columnInt(position: try columnPosition(key)))
	}
	func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
		return type.init(statement.columnInt(position: try columnPosition(key)))
	}
	func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
		return statement.columnInt32(position: try columnPosition(key))
	}
	func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
		return statement.columnInt64(position: try columnPosition(key))
	}
	func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
		return type.init(statement.columnInt(position: try columnPosition(key)))
	}
	func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
		return type.init(statement.columnInt(position: try columnPosition(key)))
	}
	func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
		return type.init(statement.columnInt(position: try columnPosition(key)))
	}
	func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
		return type.init(statement.columnInt(position: try columnPosition(key)))
	}
	func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
		return type.init(statement.columnInt(position: try columnPosition(key)))
	}
	func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
		return type.init(statement.columnDouble(position: try columnPosition(key)))
	}
	func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
		return statement.columnDouble(position: try columnPosition(key))
	}
	func decode(_ type: String.Type, forKey key: Key) throws -> String {
		return statement.columnText(position: try columnPosition(key))
	}
	func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T : Decodable {
		let position = try columnPosition(key)
		guard let special = SpecialType(type) else {
			throw CRUDDecoderError("Unsupported type: \(type) for key: \(key.stringValue)")
		}
		switch special {
		case .uint8Array:
			let ret: [UInt8] = statement.columnIntBlob(position: position)
			return ret as! T
		case .int8Array:
			let ret: [Int8] = statement.columnIntBlob(position: position)
			return ret as! T
		case .data:
			let bytes: [UInt8] = statement.columnIntBlob(position: position)
			return Data(bytes) as! T
		case .uuid:
			let str = statement.columnText(position: position)
			guard let uuid = UUID(uuidString: str) else {
				throw CRUDDecoderError("Invalid UUID string \(str).")
			}
			return uuid as! T
		case .date:
			let str = statement.columnText(position: position)
			guard let date = Date(fromISO8601: str) else {
				throw CRUDDecoderError("Invalid Date string \(str).")
			}
			return date as! T
		case .url:
			let str = statement.columnText(position: position)
			guard let url = URL(string: str) else {
				throw CRUDDecoderError("Invalid URL string \(str).")
			}
			return url as! T
		case .codable:
			guard let data = statement.columnText(position: position).data(using: .utf8) else {
				throw CRUDDecoderError("Unsupported type: \(type) for key: \(key.stringValue)")
			}
			return try JSONDecoder().decode(type, from: data)
		case .wrapped:
			let decoder = CRUDColumnValueDecoder(source: KeyedDecodingContainer(self), key: key)
			return try T(from: decoder)
		}
	}
	func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
		throw CRUDDecoderError("Unimplimented nestedContainer")
	}
	func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
		throw CRUDDecoderError("Unimplimented nestedUnkeyedContainer")
	}
	func superDecoder() throws -> Decoder {
		throw CRUDDecoderError("Unimplimented superDecoder")
	}
	func superDecoder(forKey key: Key) throws -> Decoder {
		throw CRUDDecoderError("Unimplimented superDecoder")
	}
}

struct SQLiteColumnInfo: Codable {
	let cid: Int
	let name: String
	let type: String
	let notnull: Int
	let dflt_value: String
	let pk: Bool
}

extension String {
	// The form SQLite compares identifiers in: only ASCII letters are case-insensitive, so
	// "café" and "CAFÉ" are different names to it (lowercased() would make them one).
	var sqliteFolded: String {
		var folded = String.UnicodeScalarView()
		for scalar in unicodeScalars {
			if ("A"..."Z").contains(scalar), let lower = Unicode.Scalar(scalar.value + 32) {
				folded.append(lower)
			} else {
				folded.append(scalar)
			}
		}
		return String(folded)
	}
}

class SQLiteGenDelegate: SQLGenDelegate, @unchecked Sendable {
	let database: SQLite
	var parentTableStack: [TableStructure] = []
	var bindings: Bindings = []
	var extraCreate: [String] = []
	
	init(_ db: SQLite) {
		database = db
	}
	
	func getCreateIndexSQL(forTable name: String, on columns: [String], unique: Bool) throws -> [String] {
		let stat =
		"""
		CREATE \(unique ? "UNIQUE " : "")INDEX IF NOT EXISTS \(try quote(identifier: "index_\(columns.joined(separator: "_"))"))
		ON \(try quote(identifier: name)) (\(try columns.map{try quote(identifier: $0)}.joined(separator: ",")))
		"""
		return [stat]
	}
	
	// The table and (unless .shallow) its sub-tables, each created or reconciled, with the
	// tables a FOREIGN KEY references before the tables referencing them. Sub-tables used to
	// be reached only after a CREATE, so reconciling an existing table never created or
	// reconciled its sub-tables, and .dropTable dropped a parent before its children, which
	// fails with foreign_keys on when a RESTRICT or NO ACTION child has rows. Drops are now
	// done children first.
	//
	// Reconciling a sub-table removes the columns its type doesn't have, as for the table
	// itself (use .shallow to leave sub-tables alone). The statements aren't run in one
	// transaction: a step that fails leaves the tables before it changed.
	func getCreateTableSQL(forTable: TableStructure, policy: TableCreatePolicy) throws -> [String] {
		var tables: [TableStructure] = []
		func collect(_ table: TableStructure) {
			guard !tables.contains(where: { $0.tableName.sqliteFolded == table.tableName.sqliteFolded }) else {
				return
			}
			tables.append(table)
			if !policy.contains(.shallow) {
				table.subTables.forEach(collect)
			}
		}
		collect(forTable)
		var ordered: [TableStructure] = []
		var remaining = tables
		while !remaining.isEmpty {
			let pending = Set(remaining.map { $0.tableName.sqliteFolded })
			let next = remaining.firstIndex { table in
				!table.columns.contains { column in
					column.properties.contains {
						if case .foreignKey(let target, _, _, _) = $0 {
							return target.sqliteFolded != table.tableName.sqliteFolded && pending.contains(target.sqliteFolded)
						}
						return false
					}
				}
			} ?? remaining.startIndex
			ordered.append(remaining.remove(at: next))
		}
		var sql: [String] = []
		if policy.contains(.dropTable) {
			sql += try ordered.reversed().map { "DROP TABLE IF EXISTS \(try quote(identifier: $0.tableName))" }
		}
		for table in ordered {
			parentTableStack.append(table)
			defer {
				parentTableStack.removeLast()
			}
			sql += try getCreateOrReconcileSQL(forTable: table, policy: policy) {
				// A rebuild runs immediately, so the statements for the tables before it run
				// first, keeping the tables in order.
				for stat in sql {
					CRUDLogging.log(.query, stat)
					try database.execute(statement: stat)
				}
				sql = []
			}
		}
		return sql
	}

	private func getCreateOrReconcileSQL(forTable: TableStructure, policy: TableCreatePolicy, beforeRebuild: () throws -> ()) throws -> [String] {
		if !policy.contains(.dropTable),
				policy.contains(.reconcileTable),
				let existingColumns = getExistingColumnData(forTable: forTable.tableName),
				!existingColumns.isEmpty {
			// SQLite column names are case-insensitive (for ASCII letters). Keyed as given, a column whose name
			// only changed case looked removed and added, so the rebuild lost its data.
			let existingColumnMap: [String:SQLiteColumnInfo] = .init(existingColumns.map { ($0.name.sqliteFolded, $0) }, uniquingKeysWith: { first, _ in first })
			let newColumnMap: [String:TableStructure.Column] = .init(forTable.columns.map { ($0.name.sqliteFolded, $0) }, uniquingKeysWith: { first, _ in first })
			
			let addColumns = forTable.columns.filter { existingColumnMap[$0.name.sqliteFolded] == nil }
			let removeColumns = existingColumns.filter { newColumnMap[$0.name.sqliteFolded] == nil }
			
			if !removeColumns.isEmpty {
				// The rebuilt table takes the model's spelling of every column.
				let sharedColumns = existingColumns.filter { newColumnMap[$0.name.sqliteFolded] != nil }.map { $0.name }
				try beforeRebuild()
				try rebuildTable(forTable, copying: sharedColumns)
				return []
			}
			// A result column is named as the table spells it and rows are decoded by the
			// model's spelling, so a column that only changed case is renamed to match.
			let renames = try forTable.columns.compactMap { column -> String? in
				guard let existing = existingColumnMap[column.name.sqliteFolded], existing.name != column.name else {
					return nil
				}
				return """
				ALTER TABLE \(try quote(identifier: forTable.tableName)) RENAME COLUMN \(try quote(identifier: existing.name)) TO \(try quote(identifier: column.name))
				"""
			}
			// A new @ForeignKey column gets its FOREIGN KEY as a column constraint; ADD COLUMN
			// can't add a table constraint.
			return try renames + addColumns.map {
				let nameType = try getColumnDefinition($0, foreignKeysInline: true)
				return """
				ALTER TABLE \(try quote(identifier: forTable.tableName)) ADD COLUMN \(nameType)
				"""
			}
		}
		return [
			"""
			CREATE TABLE IF NOT EXISTS \(try quote(identifier: forTable.tableName)) (
				\(try getTableDefinition(forTable))
			)
			"""]
	}

	// The column definitions plus the FOREIGN KEY clauses getColumnDefinition(_:) collects for
	// them. It starts and ends with no clauses collected, so one table's clauses can't end up
	// in another table's CREATE.
	private func getTableDefinition(_ table: TableStructure) throws -> String {
		extraCreate = []
		defer {
			extraCreate = []
		}
		let columnDefs = try table.columns.map { try getColumnDefinition($0) }
		return (columnDefs + extraCreate).joined(separator: ",\n\t")
	}

	// Removes columns by rebuilding the table, since ALTER TABLE DROP COLUMN refuses PRIMARY
	// KEY, UNIQUE, indexed and FOREIGN KEY columns. It follows the procedure in
	// https://www.sqlite.org/lang_altertable.html#otheralter: the new table is created under a
	// temporary name, filled, the old table dropped and the new one renamed into its place,
	// with foreign_keys off. Renaming the old table out of the way instead (as this used to)
	// rewrites the FOREIGN KEY references of other tables to the temporary name, and dropping
	// it then deletes their rows through ON DELETE CASCADE.
	//
	// It runs the statements itself instead of returning them, so it can roll the rebuild back
	// and turn foreign_keys back on if a step fails, and fail on rows `PRAGMA
	// foreign_key_check` reports. The old table's indexes and triggers are dropped with it, as
	// they were before.
	private func rebuildTable(_ table: TableStructure, copying sharedColumns: [String]) throws {
		let name = table.tableName
		let nameQ = try quote(identifier: name)
		let tempNameQ = try quote(identifier: "temp_\(name)_temp")
		let columnList = try sharedColumns.map { try quote(identifier: $0) }.joined(separator: ",")
		let statements = [
			// Not IF NOT EXISTS: a table left with this name holds someone's data.
			"""
			CREATE TABLE \(tempNameQ) (
				\(try getTableDefinition(table))
			)
			""",
			"""
			INSERT INTO \(tempNameQ) (\(columnList))
			SELECT \(columnList)
			FROM \(nameQ)
			""",
			"DROP TABLE \(nameQ)",
			"ALTER TABLE \(tempNameQ) RENAME TO \(nameQ)"
		]
		var foreignKeysSetting = 0
		try database.forEachRow(statement: "PRAGMA foreign_keys") { stmt, _ in
			foreignKeysSetting = stmt.columnInt(position: 0)
		}
		let foreignKeysOn = foreignKeysSetting != 0
		// The other tables with a FOREIGN KEY referencing this one.
		var referencingTables: [String] = []
		if foreignKeysOn {
			try database.forEachRow(statement: """
				SELECT DISTINCT m.name FROM sqlite_master AS m, pragma_foreign_key_list(m.name) AS f
				WHERE m.type = 'table' AND lower(m.name) <> lower(?1) AND lower(f."table") = lower(?1)
				""", doBindings: { try $0.bind(position: 1, name) }) { stmt, _ in
				referencingTables.append(stmt.columnText(position: 0))
			}
			// PRAGMA foreign_keys does nothing inside a transaction. There, dropping the old
			// table deletes its rows first, firing the ON DELETE actions of every table
			// referencing it, the new table included when it references itself.
			if sqlite3_get_autocommit(database.sqlite3) == 0 {
				let referencesItself = table.columns.contains { column in
					column.properties.contains {
						if case .foreignKey(let target, _, _, _) = $0 {
							return target.sqliteFolded == name.sqliteFolded
						}
						return false
					}
				}
				if referencesItself || !referencingTables.isEmpty {
					throw SQLiteCRUDError("Can't remove columns from \(name) inside a transaction while foreign_keys is on, because a FOREIGN KEY references it.")
				}
			} else {
				try database.execute(statement: "PRAGMA foreign_keys = OFF")
			}
		}
		defer {
			if foreignKeysOn {
				do {
					try database.execute(statement: "PRAGMA foreign_keys = ON")
				} catch {
					CRUDLogging.log(.error, "Could not turn foreign_keys back on after rebuilding \(name): \(error)")
				}
			}
		}
		try database.execute(statement: "SAVEPOINT perfect_crud_rebuild")
		do {
			for stat in statements {
				CRUDLogging.log(.query, stat)
				try database.execute(statement: stat)
			}
			if foreignKeysOn {
				// The rebuilt table as a child, then the tables referencing it. Those fail with
				// "foreign key mismatch" if a column they reference was removed (or lost the
				// PRIMARY KEY or UNIQUE index it needs).
				var violations = 0
				for checked in [name] + referencingTables {
					try database.forEachRow(statement: "PRAGMA foreign_key_check(\(try quote(identifier: checked)))") { _, _ in
						violations += 1
					}
				}
				if violations > 0 {
					throw SQLiteCRUDError("Removing columns from \(name) would leave \(violations) row(s) violating FOREIGN KEY constraints.")
				}
			}
			try database.execute(statement: "RELEASE perfect_crud_rebuild")
		} catch {
			try? database.execute(statement: "ROLLBACK TO perfect_crud_rebuild")
			try? database.execute(statement: "RELEASE perfect_crud_rebuild")
			throw error
		}
	}

	func getExistingColumnData(forTable: String) -> [SQLiteColumnInfo]? {
		do {
			let prep = try database.prepare(statement: "PRAGMA table_info(\(try quote(identifier: forTable)))")
			let exeDelegate = SQLiteExeDelegate(database, stat: prep)
			var ret: [SQLiteColumnInfo] = []
			while try exeDelegate.hasNext() {
				let rowDecoder = CRUDRowDecoder<ColumnKey>(delegate: exeDelegate)
				ret.append(try SQLiteColumnInfo(from: rowDecoder))
			}
			return ret
		} catch {
			return nil
		}
	}
	private func getTypeName(_ type: Any.Type) throws -> String {
		let typeName: String
		switch type {
		case is Int.Type:
			typeName = "INT"
		case is Int8.Type:
			typeName = "INT"
		case is Int16.Type:
			typeName = "INT"
		case is Int32.Type:
			typeName = "INT"
		case is Int64.Type:
			typeName = "INT"
		case is UInt.Type:
			typeName = "INT"
		case is UInt8.Type:
			typeName = "INT"
		case is UInt16.Type:
			typeName = "INT"
		case is UInt32.Type:
			typeName = "INT"
		case is UInt64.Type:
			typeName = "INT"
		case is Double.Type:
			typeName = "REAL"
		case is Float.Type:
			typeName = "REAL"
		case is Bool.Type:
			typeName = "INT"
		case is String.Type:
			typeName = "TEXT"
		default:
			guard let special = SpecialType(type) else {
				throw SQLiteCRUDError("Unsupported SQL column type \(type)")
			}
			switch special {
			case .uint8Array:
				typeName = "BLOB"
			case .int8Array:
				typeName = "BLOB"
			case .data:
				typeName = "BLOB"
			case .uuid:
				typeName = "TEXT"
			case .date:
				typeName = "TEXT"
			case .url:
				typeName = "TEXT"
			case .codable:
				typeName = "TEXT"
			case .wrapped:
				guard let w = type as? WrappedCodableProvider.Type else {
					throw SQLiteCRUDError("Unsupported SQL column type \(type)")
				}
				return try getTypeName(w)
			}
		}
		return typeName
	}
	// A @ForeignKey column's FOREIGN KEY clause is collected into `extraCreate`, or with
	// `foreignKeysInline` (for ADD COLUMN) appended to the definition as a column constraint.
	func getColumnDefinition(_ column: TableStructure.Column, foreignKeysInline: Bool = false) throws -> String {
		let name = try quote(identifier: column.name)
		let type = column.type
		let typeName = try getTypeName(type)
		var addendum = ""
		var references: [String] = []
		for prop in column.properties {
			switch prop {
			case .primaryKey:
				addendum += " PRIMARY KEY"
			case .foreignKey(let table, let column, let onDelete, let onUpdate):
				var str = "REFERENCES \(try quote(identifier: table))(\(try quote(identifier: column)))"
				let scenarios = [(" ON DELETE ", onDelete), (" ON UPDATE ", onUpdate)]
				for (scenario, action) in scenarios {
					str += scenario
					switch action {
					case .ignore:
						str += "NO ACTION"
					case .restrict:
						str += "RESTRICT"
					case .setNull:
						str += "SET NULL"
					case .setDefault:
						str += "SET DEFAULT"
					case .cascade:
						str += "CASCADE"
					}
				}
				if foreignKeysInline {
					references.append(str)
				} else {
					extraCreate.append("FOREIGN KEY(\(name)) \(str)")
				}
			}
		}
		if !column.properties.contains(.primaryKey) && !column.optional {
			addendum += " NOT NULL"
		}
		return (["\(name) \(typeName)\(addendum)"] + references).joined(separator: " ")
	}
	func getBinding(for expr: CRUDExpression) throws -> String {
		bindings.append(("?", expr))
		return "?"
	}
	// Standard SQL identifier quoting: an embedded `"` is doubled, so a name
	// can't end the quoted identifier early (the Dynamic API passes
	// caller-supplied table and field names through here).
	//
	// Escaped per Unicode scalar, not with replacingOccurrences: that matches
	// whole Characters, so a `"` followed by a combining mark (U+0301) would
	// not match and would reach the SQL unescaped.
	func quote(identifier: String) throws -> String {
		var escaped = String.UnicodeScalarView()
		for scalar in identifier.unicodeScalars {
			if scalar == "\"" {
				escaped.append(scalar)
			}
			escaped.append(scalar)
		}
		return "\"\(String(escaped))\""
	}
}

// maps column name to position which must be computed once before row reading action
typealias SQLiteColumnMap = [String:Int]

class SQLiteExeDelegate: SQLExeDelegate, @unchecked Sendable {
	let database: SQLite
	let statement: SQLiteStmt
	let columnMap: SQLiteColumnMap
	init(_ db: SQLite, stat: SQLiteStmt) {
		database = db
		statement = stat
		var m = SQLiteColumnMap()
		let count = statement.columnCount()
		for i in 0..<count {
			let name = statement.columnName(position: i)
			m[name] = i
		}
		columnMap = m
	}
	func bind(_ binds: Bindings, skip: Int) throws {
		_ = try statement.reset()
		var i = skip + 1
		try binds[skip...].forEach {
			let (_, expr) = $0
			try bindOne(position: i, expr: expr)
			i += 1
		}
	}
	func hasNext() throws -> Bool {
		let step = statement.step()
		guard step == SQLITE_ROW || step == SQLITE_DONE else {
			throw SQLiteCRUDError(database.errMsg())
		}
		return step == SQLITE_ROW
	}
	func next<A>() -> KeyedDecodingContainer<A>? where A : CodingKey {
		return KeyedDecodingContainer(SQLiteCRUDRowReader<A>(database, stat: statement, columns: columnMap))
	}
	func nextDynamicRow() throws -> DynamicRow? {
		var values: [String: DynamicValue] = [:]
		for (name, position) in columnMap {
			values[name] = sqliteDynamicValue(statement, position: position)
		}
		return DynamicRow(values)
	}
	private func bindOne(position: Int, expr: CRUDExpression) throws {
		switch expr {
		case .lazy(let e):
			try bindOne(position: position, expr: e())
		case .decimal(let d):
			try statement.bind(position: position, d)
		case .string(let s):
			try statement.bind(position: position, s)
		case .blob(let b):
			try statement.bind(position: position, b)
		case .bool(let b):
			try statement.bind(position: position, b ? 1 : 0)
		case .null:
			try statement.bindNull(position: position)
		case .date(let d):
			try statement.bind(position: position, d.iso8601())
		case .url(let u):
			try statement.bind(position: position, u.absoluteString)
		case .uuid(let u):
			try statement.bind(position: position, u.uuidString)
		case .column(_), .and(_, _), .or(_, _),
			 .equality(_, _), .inequality(_, _),
			 .not(_), .lessThan(_, _), .lessThanEqual(_, _),
			 .greaterThan(_, _), .greaterThanEqual(_, _),
			 .keyPath(_), .in(_, _), .like(_, _, _, _):
			throw SQLiteCRUDError("Asked to bind unsupported expression type: \(expr)")
		case .integer(let i):
			try statement.bind(position: position, i)
		case .uinteger(let i):
			try statement.bind(position: position, Int(i))
		case .integer64(let i):
			try statement.bind(position: position, Int(i))
		case .uinteger64(let i):
			try statement.bind(position: position, Int(i))
		case .integer32(let i):
			try statement.bind(position: position, Int(i))
		case .uinteger32(let i):
			try statement.bind(position: position, Int(i))
		case .integer16(let i):
			try statement.bind(position: position, Int(i))
		case .uinteger16(let i):
			try statement.bind(position: position, Int(i))
		case .integer8(let i):
			try statement.bind(position: position, Int(i))
		case .uinteger8(let i):
			try statement.bind(position: position, Int(i))
		case .float(let d):
			try statement.bind(position: position, Double(d))
		case .sblob(let b):
			try statement.bind(position: position, b.map{UInt8(bitPattern: $0)})
		}
	}
}

func sqliteDynamicValue(_ statement: SQLiteStmt, position: Int) -> DynamicValue {
	if statement.isNull(position: position) {
		return .null
	} else if statement.isInteger(position: position) {
		return .int(statement.columnInt64(position: position))
	} else if statement.isFloat(position: position) {
		return .double(statement.columnDouble(position: position))
	} else if statement.isBlob(position: position) {
		return .bytes(statement.columnIntBlob(position: position))
	}
	return .string(statement.columnText(position: position))
}

public struct SQLiteDatabaseConfiguration: DatabaseConfigurationProtocol {
	public var sqlGenDelegate: SQLGenDelegate {
		return SQLiteGenDelegate(sqlite)
	}
	public func sqlExeDelegate(forSQL sql: String) throws -> SQLExeDelegate {
		let prep = try sqlite.prepare(statement: sql)
		return SQLiteExeDelegate(sqlite, stat: prep)
	}
	public let name: String
	public let sqlite: SQLite
	public init(_ n: String, _ pragmas: [String] = ["PRAGMA foreign_keys = ON"]) throws {
		name = n
		sqlite = try SQLite(n)
		for pragma in pragmas {
			try sqlite.execute(statement: pragma)
		}
	}
	public init(url: String?,
				name: String?,
				host: String?,
				port: Int?,
				user: String?,
				pass: String?) throws {
		guard let n = name else {
			throw SQLiteCRUDError("Database name must be provided.")
		}
		try self.init(n)
	}
}

public extension Insert {
	func lastInsertId() throws -> Int? {
		let exeDelegate = try databaseConfiguration.sqlExeDelegate(forSQL: "SELECT last_insert_rowid()")
		guard try exeDelegate.hasNext(), let next: KeyedDecodingContainer<ColumnKey> = try exeDelegate.next() else {
			throw CRUDSQLGenError("Did not get return value from statement \"SELECT last_insert_rowid()\".")
		}
		let value = try next.decode(Int.self, forKey: ColumnKey(stringValue: "last_insert_rowid()")!)
		return value
	}
}
