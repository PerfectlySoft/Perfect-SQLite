import Testing
import Foundation
import PerfectCRUD
@testable import PerfectSQLite

let testDBName = "/tmp/crud_sqlite_test.db"
typealias DBConfiguration = SQLiteDatabaseConfiguration

func getDB(reset: Bool = true) throws -> Database<DBConfiguration> {
    if reset { unlink(testDBName) }
    return Database(configuration: try DBConfiguration(testDBName))
}

@Suite(.serialized) struct PerfectSQLiteTests {

    struct TestTable1: Codable, TableNameProvider {
        enum CodingKeys: String, CodingKey {
            case id, name, integer = "int", double = "doub", blob, subTables
        }
        static let tableName = "test_table_1"
        @PrimaryKey var id: Int
        let name: String?
        let integer: Int?
        let double: Double?
        let blob: [UInt8]?
        let subTables: [TestTable2]?
        init(id: Int, name: String? = nil, integer: Int? = nil,
             double: Double? = nil, blob: [UInt8]? = nil, subTables: [TestTable2]? = nil) {
            self.id = id; self.name = name; self.integer = integer
            self.double = double; self.blob = blob; self.subTables = subTables
        }
    }

    struct TestTable2: Codable {
        @PrimaryKey var id: UUID
        @ForeignKey(TestTable1.self, onDelete: cascade, onUpdate: cascade) var parentId: Int
        let date: Date
        let name: String?
        let int: Int?
        let doub: Double?
        let blob: [UInt8]?
        init(id: UUID, parentId: Int, date: Date, name: String? = nil,
             int: Int? = nil, doub: Double? = nil, blob: [UInt8]? = nil) {
            _id = .init(wrappedValue: id)
            _parentId = .init(TestTable1.self, onDelete: cascade, onUpdate: cascade, wrappedValue: parentId)
            self.date = date; self.name = name; self.int = int; self.doub = doub; self.blob = blob
        }
    }

    init() { CRUDClearTableStructureCache() }

    func getTestDB() throws -> Database<DBConfiguration> {
        let db = try getDB()
        try db.create(TestTable1.self, policy: .dropTable)
        try db.transaction {
            try db.table(TestTable1.self).insert((1...5).map { num -> TestTable1 in
                let n = UInt8(num)
                let blob: [UInt8]? = (num % 2 != 0) ? nil : [UInt8](arrayLiteral: n+1, n+2, n+3, n+4, n+5)
                return TestTable1(id: num, name: "This is name bind \(num)", integer: num, double: Double(num), blob: blob)
            })
        }
        try db.transaction {
            try db.table(TestTable2.self).insert((1...5).flatMap { parentId -> [TestTable2] in
                (1...5).map { num -> TestTable2 in
                    let n = UInt8(num)
                    return TestTable2(id: UUID(), parentId: parentId, date: Date(),
                                      name: num % 2 == 0 ? "This is name bind \(num)" : "me",
                                      int: num, doub: Double(num),
                                      blob: [UInt8](arrayLiteral: n+1, n+2, n+3, n+4, n+5))
                }
            })
        }
        return try getDB(reset: false)
    }

    @Test func create1() throws {
        let db = try getDB()
        try db.create(TestTable1.self, policy: .dropTable)
        try db.table(TestTable2.self).index(\.parentId)
        let t1 = db.table(TestTable1.self)
        let t2 = db.table(TestTable2.self)
        let subId = UUID()
        try db.transaction {
            try t1.insert(TestTable1(id: 2000, name: "New One", integer: 40))
            try t2.insert([TestTable2(id: subId, parentId: 2000, date: Date(), name: "Me"),
                           TestTable2(id: UUID(), parentId: 2000, date: Date(), name: "Not Me")])
        }
        let j21 = try t1.join(\.subTables, on: \.id, equals: \.parentId)
        let j2  = j21.where(\TestTable1.id == 2000 && \TestTable2.name == "Me")
        let j3  = j21.where(\TestTable1.id > 20 && !(\TestTable1.name == "Me" || \TestTable1.name == "You"))
        #expect(try j3.count() == 1)
        try db.transaction {
            let rows = try j2.select().map { $0 }
            #expect(try j2.count() == 1)
            #expect(rows.count == 1)
            let obj = try #require(rows.first)
            #expect(obj.id == 2000)
            let subs = try #require(obj.subTables)
            #expect(subs.count == 1)
            #expect(subs[0].id == subId)
        }
        try db.create(TestTable1.self)
        #expect(try j2.count() == 1)
        try db.create(TestTable1.self, policy: .dropTable)
        #expect(try j2.select().map({ $0 }).count == 0)
    }

    @Test func create2() throws {
        let db = try getTestDB()
        try db.create(TestTable1.self, policy: .dropTable)
        try db.table(TestTable2.self).index(\.parentId, \.date)
        let t1 = db.table(TestTable1.self)
        try t1.insert(TestTable1(id: 2000, name: "New One", integer: 40))
        let j2 = try t1.where(\TestTable1.id == 2000).select()
        #expect(j2.map({ $0 }).count == 1)
        #expect(j2.map({ $0 })[0].id == 2000)
        try db.create(TestTable1.self)
        #expect(j2.map({ $0 }).count == 1)
        try db.create(TestTable1.self, policy: .dropTable)
        #expect(j2.map({ $0 }).count == 0)
    }

    @Test func create3() throws {
        struct FakeTestTable1: Codable, TableNameProvider {
            enum CodingKeys: String, CodingKey { case id, name, double = "doub", double2 = "doub2", blob, subTables }
            static let tableName = "test_table_1"
            let id: Int; let name: String?; let double2: Double?; let double: Double?
            let blob: [UInt8]?; let subTables: [TestTable2]?
        }
        let db = try getTestDB()
        try db.create(TestTable1.self, policy: [.dropTable, .shallow])
        try db.table(TestTable1.self).insert(TestTable1(id: 2000, name: "New One", integer: 40))
        try db.create(FakeTestTable1.self, policy: [.reconcileTable, .shallow])
        let row = try db.table(FakeTestTable1.self).where(\FakeTestTable1.id == 2000).select().map { $0 }
        #expect(row.count == 1)
        #expect(row[0].id == 2000)
    }

    @Test func selectAll() throws {
        let db = try getTestDB()
        for row in try db.table(TestTable1.self).select() {
            #expect(row.subTables == nil)
        }
    }

    @Test func selectIn() throws {
        let db = try getTestDB()
        let table = db.table(TestTable1.self)
        #expect(try table.where(\TestTable1.id ~ [2, 4]).count() == 2)
        #expect(try table.where(\TestTable1.id !~ [2, 4]).count() == 3)
    }

    @Test func selectLikeString() throws {
        let db = try getTestDB()
        let table = db.table(TestTable2.self)
        #expect(try table.where(\TestTable2.name %=% "me").count() == 25)
        #expect(try table.where(\TestTable2.name =% "me").count()  == 15)
        #expect(try table.where(\TestTable2.name %= "me").count()  == 15)
        #expect(try table.where(\TestTable2.name %!=% "me").count() == 0)
        #expect(try table.where(\TestTable2.name !=% "me").count() == 10)
        #expect(try table.where(\TestTable2.name %!= "me").count() == 10)
    }

    @Test func selectJoin() throws {
        let db = try getTestDB()
        let j2 = try db.table(TestTable1.self)
            .order(by: \TestTable1.name)
            .join(\.subTables, on: \.id, equals: \.parentId)
            .order(by: \.id)
            .where(\TestTable2.name == "me")
        let count = try j2.count()
        let rows  = try j2.select().map { $0 }
        #expect(count != 0)
        #expect(count == rows.count)
        for row in rows { #expect(!(row.subTables?.isEmpty ?? true)) }
    }

    @Test func insert1() throws {
        let db = try getTestDB()
        let t1 = db.table(TestTable1.self)
        let newOne = TestTable1(id: 2000, name: "New One", integer: 40)
        try t1.insert(newOne)
        let j1 = t1.where(\TestTable1.id == newOne.id)
        #expect(try j1.count() == 1)
        #expect(try j1.select().map({ $0 })[0].id == 2000)
    }

    @Test func insert2() throws {
        let db = try getTestDB()
        let t1 = db.table(TestTable1.self)
        let newOne = TestTable1(id: 2000, name: "New One", integer: 40)
        try t1.insert(newOne, ignoreKeys: \TestTable1.integer)
        let rows = try t1.where(\TestTable1.id == newOne.id).select().map { $0 }
        #expect(rows.count == 1)
        #expect(rows[0].id == 2000)
        #expect(rows[0].integer == nil)
    }

    @Test func insert3() throws {
        let db = try getTestDB()
        let t1 = db.table(TestTable1.self)
        try t1.insert([TestTable1(id: 2000, name: "New One", integer: 40),
                       TestTable1(id: 2001, name: "New One", integer: 40)],
                      setKeys: \TestTable1.id, \TestTable1.integer)
        let rows = try t1.where(\TestTable1.id == 2000).select().map { $0 }
        #expect(rows.count == 1)
        #expect(rows[0].id == 2000)
        #expect(rows[0].integer == 40)
        #expect(rows[0].name == nil)
    }

    @Test func update() throws {
        let db = try getTestDB()
        let newOne = TestTable1(id: 2000, name: "New One", integer: 40)
        let newId: Int = try db.transaction {
            try db.table(TestTable1.self).insert(newOne)
            try db.table(TestTable1.self).where(\TestTable1.id == newOne.id)
                .update(TestTable1(id: 2000, name: "New👻One Updated", integer: 41), setKeys: \.name)
            return newOne.id
        }
        let rows = try db.table(TestTable1.self).where(\TestTable1.id == newId).select().map { $0 }
        #expect(rows.count == 1)
        #expect(rows[0].id == 2000)
        #expect(rows[0].name == "New👻One Updated")
        #expect(rows[0].integer == 40)
    }

    @Test func delete() throws {
        let db = try getTestDB()
        let t1 = db.table(TestTable1.self)
        let newOne = TestTable1(id: 2000, name: "New One", integer: 40)
        try t1.insert(newOne)
        let query = t1.where(\TestTable1.id == newOne.id)
        #expect(try query.select().map({ $0 }).count == 1)
        try query.delete()
        #expect(try query.select().map({ $0 }).count == 0)
    }

    @Test func selectLimit() throws {
        let db = try getTestDB()
        #expect(try db.table(TestTable1.self).limit(3, skip: 2).count() == 3)
    }

    @Test func selectLimitWhere() throws {
        let db = try getTestDB()
        let j2 = db.table(TestTable1.self).limit(3).where(\TestTable1.id > 3)
        #expect(try j2.count() == 2)
        #expect(try j2.select().map({ $0 }).count == 2)
    }

    @Test func selectOrderLimitWhere() throws {
        let db = try getTestDB()
        let j2 = db.table(TestTable1.self).order(by: \TestTable1.id).limit(3).where(\TestTable1.id > 3)
        #expect(try j2.count() == 2)
        #expect(try j2.select().map({ $0 }).count == 2)
    }

    @Test func selectWhereNull() throws {
        let db = try getTestDB()
        let t1 = db.table(TestTable1.self)
        #expect(try t1.where(\TestTable1.blob == nil).count() > 0)
        #expect(try t1.where(\TestTable1.blob != nil).count() > 0)
    }

    @Test func personThing() throws {
        struct PhoneNumber: Codable { let personId: UUID; let planetCode: Int; let number: String }
        struct Person: Codable { let id: UUID; let firstName: String; let lastName: String; let phoneNumbers: [PhoneNumber]? }
        let db = Database(configuration: try SQLiteDatabaseConfiguration(testDBName))
        try db.create(Person.self, policy: .reconcileTable)
        let personTable  = db.table(Person.self)
        let numbersTable = db.table(PhoneNumber.self)
        try numbersTable.index(\.personId)
        let owen = Person(id: UUID(), firstName: "Owen", lastName: "Lars", phoneNumbers: nil)
        let beru = Person(id: UUID(), firstName: "Beru", lastName: "Lars", phoneNumbers: nil)
        try personTable.insert([owen, beru])
        try numbersTable.insert([
            PhoneNumber(personId: owen.id, planetCode: 12, number: "555-555-1212"),
            PhoneNumber(personId: owen.id, planetCode: 15, number: "555-555-2222"),
            PhoneNumber(personId: beru.id, planetCode: 12, number: "555-555-1212")])
        let query = try personTable
            .order(by: \.lastName, \.firstName)
            .join(\.phoneNumbers, on: \.id, equals: \.personId)
            .order(descending: \.planetCode)
            .where(\Person.lastName == "Lars" && \PhoneNumber.planetCode == 12)
            .select()
        var count = 0
        for _ in query { count += 1 }
        #expect(count > 0)
    }

    @Test func standardJoin() throws {
        struct Parent: Codable { let id: Int; let children: [Child]?; init(id i: Int) { id = i; children = nil } }
        struct Child: Codable { let id: Int; let parentId: Int }
        let db = try getTestDB()
        try db.transaction {
            try db.create(Parent.self, policy: [.shallow, .dropTable]).insert(Parent(id: 1))
            try db.create(Child.self, policy: [.shallow, .dropTable])
                .insert([Child(id: 1, parentId: 1), Child(id: 2, parentId: 1), Child(id: 3, parentId: 1)])
        }
        let parent = try #require(try db.table(Parent.self).join(\.children, on: \.id, equals: \.parentId).where(\Parent.id == 1).first())
        let children = try #require(parent.children)
        #expect(children.count == 3)
        for child in children { #expect(child.parentId == parent.id) }
    }

    @Test func junctionJoin() throws {
        struct Student: Codable { let id: Int; let classes: [Class]?; init(id i: Int) { id = i; classes = nil } }
        struct Class:   Codable { let id: Int; let students: [Student]?; init(id i: Int) { id = i; students = nil } }
        struct StudentClasses: Codable { let studentId: Int; let classId: Int }
        let db = try getTestDB()
        try db.transaction {
            try db.create(Student.self, policy: [.dropTable, .shallow]).insert(Student(id: 1))
            try db.create(Class.self,   policy: [.dropTable, .shallow]).insert([Class(id: 1), Class(id: 2), Class(id: 3)])
            try db.create(StudentClasses.self, policy: [.dropTable, .shallow])
                .insert([StudentClasses(studentId: 1, classId: 1),
                         StudentClasses(studentId: 1, classId: 2),
                         StudentClasses(studentId: 1, classId: 3)])
        }
        let student = try #require(try db.table(Student.self)
            .join(\.classes, with: StudentClasses.self, on: \.id, equals: \.studentId, and: \.id, is: \.classId)
            .where(\Student.id == 1).first())
        let classes = try #require(student.classes)
        #expect(classes.count == 3)
    }

    @Test func selfJoin() throws {
        struct Me: Codable { let id: Int; let parentId: Int; let mes: [Me]?; init(id i: Int, parentId p: Int) { id = i; parentId = p; mes = nil } }
        let db = try getTestDB()
        try db.transaction {
            try db.create(Me.self, policy: .dropTable)
                .insert([Me(id: 1, parentId: 0), Me(id: 2, parentId: 1),
                         Me(id: 3, parentId: 1), Me(id: 4, parentId: 1), Me(id: 5, parentId: 1)])
        }
        let me = try #require(try db.table(Me.self).join(\.mes, on: \.id, equals: \.parentId).where(\Me.id == 1).first())
        #expect(try #require(me.mes).count == 4)
    }

    @Test func codableProperty() throws {
        struct Sub: Codable { let id: Int }
        struct Top: Codable { let id: Int; let sub: Sub? }
        let db = try getTestDB()
        try db.create(Sub.self); try db.create(Top.self)
        let t1 = Top(id: 1, sub: Sub(id: 1))
        try db.table(Top.self).insert(t1)
        let top = try #require(try db.table(Top.self).where(\Top.id == 1).first())
        #expect(top.sub?.id == t1.sub?.id)
    }

    @Test func badDecoding() throws {
        struct Top:  Codable, TableNameProvider { static let tableName = "Top"; let id: Int }
        struct NTop: Codable, TableNameProvider { static let tableName = "Top"; let nid: Int }
        let db = try getTestDB()
        try db.create(Top.self, policy: .dropTable)
        try db.table(Top.self).insert(Top(id: 1))
        #expect(throws: (any Error).self) {
            _ = try db.table(NTop.self).first()
        }
    }

    @Test func allPrimTypes() throws {
        struct AllTypes: Codable {
            let int: Int; let uint: UInt; let int64: Int64; let uint64: UInt64
            let int32: Int32?; let uint32: UInt32?; let int16: Int16; let uint16: UInt16
            let int8: Int8?; let uint8: UInt8?; let double: Double; let float: Float
            let string: String; let bytes: [Int8]; let ubytes: [UInt8]?; let b: Bool
        }
        let db = try getTestDB()
        try db.create(AllTypes.self, policy: .dropTable)
        let model = AllTypes(int: 1, uint: 2, int64: 3, uint64: 4, int32: 5, uint32: 6,
                             int16: 7, uint16: 8, int8: 9, uint8: 10, double: 11, float: 12,
                             string: "13", bytes: [1, 4], ubytes: [1, 4], b: true)
        try db.table(AllTypes.self).insert(model)
        let f = try #require(try db.table(AllTypes.self).where(\AllTypes.int == 1).first())
        #expect(f.int == model.int); #expect(f.uint == model.uint)
        #expect(f.string == model.string); #expect(f.b == model.b)
        #expect(f.bytes == model.bytes); #expect(f.ubytes! == model.ubytes!)
    }

    @Test func bespokeSQL() throws {
        let db = try getTestDB()
        let r = try db.sql("SELECT * FROM \(TestTable1.CRUDTableName) WHERE id = 2", TestTable1.self)
        #expect(r.count == 1)
    }

    @Test func urlColumn() throws {
        struct TableWithURL: Codable { let id: Int; let url: URL }
        let db = try getTestDB()
        try db.create(TableWithURL.self)
        let newOne = TableWithURL(id: 2000, url: URL(string: "http://localhost/")!)
        try db.table(TableWithURL.self).insert(newOne)
        let rows = try db.table(TableWithURL.self).where(\TableWithURL.id == 2000).select().map { $0 }
        #expect(rows.count == 1)
        #expect(rows[0].url.absoluteString == "http://localhost/")
    }

    @Test func lastInsertId() throws {
        struct Item: Codable, Equatable { let id: Int?; var def: Int?; init(id: Int, def: Int? = nil) { self.id = id; self.def = def } }
        let db = try getTestDB()
        try db.sql("DROP TABLE IF EXISTS \(Item.CRUDTableName)")
        try db.sql("CREATE TABLE \(Item.CRUDTableName) (id INT PRIMARY KEY, def INT DEFAULT 42)")
        let id = try db.table(Item.self)
            .insert(Item(id: 0, def: 0), ignoreKeys: \Item.id)
            .lastInsertId()
        #expect(id == 1)
    }
}
