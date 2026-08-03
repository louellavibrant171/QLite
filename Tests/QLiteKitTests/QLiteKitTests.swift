import XCTest
@testable import QLiteKit

final class QLiteKitTests: XCTestCase {
    private var url: URL!
    private var db: Database!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("qlite-tests-\(UUID().uuidString).sqlite")
        db = try Database(url: url)
        try db.execute("""
        CREATE TABLE people (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            age INTEGER,
            photo BLOB
        );
        CREATE INDEX idx_people_name ON people (name);
        CREATE VIEW adults AS SELECT * FROM people WHERE age >= 18;
        INSERT INTO people (name, age) VALUES ('Ada', 36), ('Linus', 17), ('Grace', 45);
        """)
    }

    override func tearDownWithError() throws {
        db.close()
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Connection

    func testFileDetection() throws {
        XCTAssertTrue(Database.isSQLiteFile(at: url))
        let text = url.appendingPathExtension("txt")
        try "not a database".write(to: text, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: text) }
        XCTAssertFalse(Database.isSQLiteFile(at: text))
    }

    func testQueryReturnsTypedValues() throws {
        let result = try db.query("SELECT name, age FROM people ORDER BY name")
        XCTAssertEqual(result.columnNames, ["name", "age"])
        XCTAssertEqual(result.rows.count, 3)
        XCTAssertEqual(result.rows[0][0], .text("Ada"))
        XCTAssertEqual(result.rows[0][1], .integer(36))
    }

    func testBlobRoundTrip() throws {
        let data = Data([0x00, 0x01, 0xFE, 0xFF])
        try db.run("INSERT INTO people (name, photo) VALUES (?, ?)", [.text("Blobby"), .blob(data)])
        let value = try db.scalar("SELECT photo FROM people WHERE name = ?", [.text("Blobby")])
        XCTAssertEqual(value, .blob(data))
    }

    func testTransactionRollsBackOnError() {
        struct Boom: Error {}
        XCTAssertThrowsError(try db.transaction {
            try db.run("INSERT INTO people (name) VALUES ('Temp')")
            throw Boom()
        })
        let count = try? db.scalar("SELECT COUNT(*) FROM people WHERE name = 'Temp'").intValue
        XCTAssertEqual(count, 0)
    }

    // MARK: - Schema

    func testSchemaReaderListsObjects() throws {
        let reader = SchemaReader(database: db)
        let objects = try reader.objects()
        XCTAssertTrue(objects.contains { $0.kind == .table && $0.name == "people" })
        XCTAssertTrue(objects.contains { $0.kind == .index && $0.name == "idx_people_name" })
        XCTAssertTrue(objects.contains { $0.kind == .view && $0.name == "adults" })
        XCTAssertFalse(objects.contains { $0.name.hasPrefix("sqlite_") })
    }

    func testTableDetails() throws {
        let reader = SchemaReader(database: db)
        let object = try XCTUnwrap(try reader.objects().first { $0.name == "people" })
        let details = try reader.details(for: object)
        XCTAssertEqual(details.columns.map(\.name), ["id", "name", "age", "photo"])
        XCTAssertEqual(details.rowCount, 3)
        XCTAssertTrue(details.hasRowID)
        XCTAssertEqual(details.primaryKeyColumns.map(\.name), ["id"])
        XCTAssertTrue(details.columns[1].isNotNull)
        XCTAssertTrue(details.indexes.contains { $0.name == "idx_people_name" })
    }

    func testForeignKeyReporting() throws {
        try db.execute("""
        CREATE TABLE pets (
            id INTEGER PRIMARY KEY,
            owner_id INTEGER REFERENCES people(id) ON DELETE CASCADE
        );
        """)
        let keys = try SchemaReader(database: db).foreignKeys(of: "pets")
        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(keys[0].referencedTable, "people")
        XCTAssertEqual(keys[0].referencedColumn, "id")
        XCTAssertEqual(keys[0].onDelete, "CASCADE")
    }

    // MARK: - Schema editing

    func testCreateAndAlterTable() throws {
        let editor = SchemaEditor(database: db)
        try editor.createTable(name: "cities", columns: [
            ColumnDefinition(name: "id", type: "INTEGER", isPrimaryKey: true, isAutoIncrement: true),
            ColumnDefinition(name: "name", type: "TEXT", isNotNull: true),
            ColumnDefinition(name: "population", type: "INTEGER")
        ])
        try editor.addColumn(ColumnDefinition(name: "country", type: "TEXT"), to: "cities")
        try editor.renameColumn(in: "cities", from: "population", to: "residents")
        try editor.renameTable(from: "cities", to: "towns")

        let reader = SchemaReader(database: db)
        let columns = try reader.columns(of: "towns")
        XCTAssertEqual(columns.map(\.name), ["id", "name", "residents", "country"])

        try editor.dropColumn(in: "towns", name: "country")
        XCTAssertEqual(try reader.columns(of: "towns").count, 3)

        try editor.dropTable("towns")
        XCTAssertFalse(try reader.objects().contains { $0.name == "towns" })
    }

    func testCompositePrimaryKey() throws {
        let editor = SchemaEditor(database: db)
        try editor.createTable(name: "memberships", columns: [
            ColumnDefinition(name: "person_id", type: "INTEGER", isPrimaryKey: true),
            ColumnDefinition(name: "group_id", type: "INTEGER", isPrimaryKey: true),
            ColumnDefinition(name: "joined", type: "TEXT")
        ])
        let columns = try SchemaReader(database: db).columns(of: "memberships")
        XCTAssertEqual(columns.filter(\.isPrimaryKey).map(\.name), ["person_id", "group_id"])
    }

    func testCreateIndexAndDrop() throws {
        let editor = SchemaEditor(database: db)
        try editor.createIndex(name: "idx_people_age", table: "people", columns: ["age"], unique: false)
        let reader = SchemaReader(database: db)
        XCTAssertTrue(try reader.indexes(of: "people").contains { $0.name == "idx_people_age" })
        try editor.dropIndex("idx_people_age")
        XCTAssertFalse(try reader.indexes(of: "people").contains { $0.name == "idx_people_age" })
    }

    func testRejectsReservedIdentifiers() {
        let editor = SchemaEditor(database: db)
        XCTAssertThrowsError(try editor.createTable(name: "sqlite_bad", columns: [ColumnDefinition(name: "a")]))
        XCTAssertThrowsError(try editor.createTable(name: "  ", columns: [ColumnDefinition(name: "a")]))
    }

    // MARK: - Data editing

    private func makeStore(_ table: String = "people") throws -> TableDataStore {
        let reader = SchemaReader(database: db)
        let object = try XCTUnwrap(try reader.objects().first { $0.name == table })
        return TableDataStore(database: db, details: try reader.details(for: object))
    }

    func testPagingAndSorting() throws {
        let store = try makeStore()
        let firstPage = try store.page(limit: 2, offset: 0, sort: ColumnSort(column: "name", ascending: true))
        XCTAssertEqual(firstPage.totalRows, 3)
        XCTAssertEqual(firstPage.rows.count, 2)
        XCTAssertEqual(firstPage.rows.map { $0.values[1] }, [.text("Ada"), .text("Grace")])

        let secondPage = try store.page(limit: 2, offset: 2, sort: ColumnSort(column: "name", ascending: true))
        XCTAssertEqual(secondPage.rows.count, 1)
        XCTAssertEqual(secondPage.rows[0].values[1], .text("Linus"))
    }

    func testFiltering() throws {
        let store = try makeStore()
        let page = try store.page(limit: 10, offset: 0, filter: "age >= 18")
        XCTAssertEqual(page.totalRows, 2)
    }

    func testInsertUpdateDelete() throws {
        let store = try makeStore()
        let rowID = try store.insert(values: ["name": .text("Alan"), "age": .integer(41)])
        XCTAssertGreaterThan(rowID, 0)

        var page = try store.page(limit: 10, offset: 0, filter: "name = 'Alan'")
        var row = try XCTUnwrap(page.rows.first)
        XCTAssertEqual(try store.update(row: row, column: "age", to: .integer(42)), 1)

        page = try store.page(limit: 10, offset: 0, filter: "name = 'Alan'")
        row = try XCTUnwrap(page.rows.first)
        XCTAssertEqual(row.values[2], .integer(42))

        XCTAssertEqual(try store.update(row: row, values: ["name": .text("Alan Turing"), "age": .null]), 1)
        page = try store.page(limit: 10, offset: 0, filter: "name = 'Alan Turing'")
        row = try XCTUnwrap(page.rows.first)
        XCTAssertTrue(row.values[2].isNull)

        XCTAssertEqual(try store.delete(rows: [row]), 1)
        XCTAssertEqual(try store.page(limit: 10, offset: 0).totalRows, 3)
    }

    func testWithoutRowIDTableUsesPrimaryKey() throws {
        try SchemaEditor(database: db).createTable(name: "settings", columns: [
            ColumnDefinition(name: "key", type: "TEXT", isPrimaryKey: true),
            ColumnDefinition(name: "value", type: "TEXT")
        ], withoutRowID: true)

        let store = try makeStore("settings")
        XCTAssertFalse(store.details.hasRowID)
        XCTAssertTrue(store.isEditable)

        _ = try store.insert(values: ["key": .text("theme"), "value": .text("dark")])
        let row = try XCTUnwrap(try store.page(limit: 10, offset: 0).rows.first)
        XCTAssertEqual(try store.update(row: row, column: "value", to: .text("light")), 1)
        XCTAssertEqual(try db.scalar("SELECT value FROM settings WHERE key = 'theme'"), .text("light"))
    }

    func testViewsAreNotEditable() throws {
        let store = try makeStore("adults")
        XCTAssertFalse(store.isEditable)
        XCTAssertNotNil(store.editabilityReason)
    }

    func testIdentifierQuotingSurvivesHostileNames() throws {
        let editor = SchemaEditor(database: db)
        try editor.createTable(name: "we\"ird", columns: [ColumnDefinition(name: "col\"umn", type: "TEXT")])
        let store = try makeStore("we\"ird")
        _ = try store.insert(values: ["col\"umn": .text("ok")])
        XCTAssertEqual(try store.page(limit: 10, offset: 0).totalRows, 1)
    }

    // MARK: - Query runner

    func testRunsMultipleStatements() throws {
        let runner = QueryRunner(database: db)
        let execution = runner.run("""
        UPDATE people SET age = age + 1;
        SELECT name, age FROM people ORDER BY name;
        """)
        XCTAssertNil(execution.error)
        XCTAssertEqual(execution.statements.count, 2)
        XCTAssertEqual(execution.statements[0].affectedRows, 3)
        XCTAssertEqual(execution.displayedResult?.resultSet?.rows.count, 3)
    }

    func testReportsSyntaxErrors() {
        let execution = QueryRunner(database: db).run("SELECT * FROM nope;")
        XCTAssertNotNil(execution.error)
    }

    func testRowLimitIsEnforced() throws {
        try db.execute("CREATE TABLE numbers (n INTEGER)")
        try db.transaction {
            for n in 0..<50 { try db.run("INSERT INTO numbers VALUES (?)", [.integer(Int64(n))]) }
        }
        let execution = QueryRunner(database: db, maxRows: 10).run("SELECT * FROM numbers")
        XCTAssertEqual(execution.displayedResult?.resultSet?.rows.count, 10)
    }

    func testExplain() throws {
        let plan = try QueryRunner(database: db).explain("SELECT * FROM people WHERE name = 'Ada'")
        XCTAssertFalse(plan.rows.isEmpty)
    }

    // MARK: - Values and export

    func testTypeAffinity() {
        XCTAssertEqual(TypeAffinity.of("VARCHAR(20)"), .text)
        XCTAssertEqual(TypeAffinity.of("BIGINT"), .integer)
        XCTAssertEqual(TypeAffinity.of("DOUBLE"), .real)
        XCTAssertEqual(TypeAffinity.of("BLOB"), .blob)
        XCTAssertEqual(TypeAffinity.of(nil), .blob)
        XCTAssertEqual(TypeAffinity.of("DATETIME"), .numeric)
    }

    func testValueCoercion() {
        XCTAssertEqual(SQLValue.coerce("42", declaredType: "INTEGER"), .integer(42))
        XCTAssertEqual(SQLValue.coerce("4.5", declaredType: "REAL"), .real(4.5))
        XCTAssertEqual(SQLValue.coerce("hello", declaredType: "TEXT"), .text("hello"))
        XCTAssertEqual(SQLValue.coerce("x'00ff'", declaredType: "BLOB"), .blob(Data([0x00, 0xFF])))
    }

    func testCSVExportEscapesFields() {
        let set = ResultSet(columnNames: ["a", "b"],
                            rows: [[.text("plain"), .text("with,comma")],
                                   [.null, .text("quote\"inside")]])
        let csv = Exporter.string(from: set, format: .csv)
        XCTAssertTrue(csv.contains("\"with,comma\""))
        XCTAssertTrue(csv.contains("\"quote\"\"inside\""))
    }

    func testJSONExport() throws {
        let set = ResultSet(columnNames: ["n"], rows: [[.integer(1)], [.null]])
        let json = Exporter.string(from: set, format: .json)
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]
        XCTAssertEqual(parsed?.count, 2)
    }

    func testSQLExportQuotesLiterals() {
        let set = ResultSet(columnNames: ["name"], rows: [[.text("O'Hara")]])
        let sql = Exporter.string(from: set, format: .sql, tableName: "people")
        XCTAssertTrue(sql.contains("'O''Hara'"))
    }

    // MARK: - Summary used by QuickLook

    func testDatabaseSummary() throws {
        let summary = try DatabaseSummary.load(url: url, maxTables: 5, sampleRowCount: 2)
        XCTAssertEqual(summary.tableCount, 1)
        XCTAssertEqual(summary.viewCount, 1)
        XCTAssertEqual(summary.indexCount, 1)
        let people = try XCTUnwrap(summary.tables.first)
        XCTAssertEqual(people.rowCount, 3)
        XCTAssertEqual(people.sampleRows.count, 2)
        XCTAssertTrue(summary.headline.contains("1 table"))
    }
}

/// Covers WAL/journal sidecar handling and the file-type helpers added for the Settings window.
final class DatabaseFileTests: XCTestCase {
    private var directory: URL!
    /// Kept open on purpose: SQLite checkpoints and deletes the -wal file when the last
    /// connection closes cleanly, and these tests need a WAL that still holds rows.
    private var writer: Database?

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("qlite-file-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        writer?.close()
        writer = nil
        try? FileManager.default.removeItem(at: directory)
    }

    /// Creates a WAL database holding one checkpointed row and one row that only exists in
    /// the `-wal` file. The writing connection stays open in `writer`.
    @discardableResult
    private func makeWALDatabase(named name: String = "wal.sqlite") throws -> URL {
        let url = directory.appendingPathComponent(name)
        let db = try Database(url: url)
        try db.execute("PRAGMA journal_mode = WAL")
        try db.execute("CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT)")
        try db.run("INSERT INTO notes (body) VALUES (?)", [.text("checkpointed")])
        try db.checkpointWAL()
        try db.run("INSERT INTO notes (body) VALUES (?)", [.text("only in wal")])
        writer = db
        return url
    }

    func testPrimaryURLStripsSidecarSuffixes() {
        let base = URL(fileURLWithPath: "/tmp/app.db")
        for suffix in DatabaseFile.sidecarSuffixes {
            let sidecar = URL(fileURLWithPath: "/tmp/app.db" + suffix)
            XCTAssertEqual(DatabaseFile.primaryURL(for: sidecar), base)
        }
        XCTAssertEqual(DatabaseFile.primaryURL(for: base), base)
    }

    func testExtensionMatchingIsCaseInsensitive() {
        XCTAssertTrue(DatabaseFile.hasDatabaseExtension(URL(fileURLWithPath: "/tmp/a.SQLite")))
        XCTAssertTrue(DatabaseFile.hasDatabaseExtension(URL(fileURLWithPath: "/tmp/a.db3")))
        XCTAssertFalse(DatabaseFile.hasDatabaseExtension(URL(fileURLWithPath: "/tmp/a.txt")))
        XCTAssertTrue(DatabaseFile.hasDatabaseExtension(URL(fileURLWithPath: "/tmp/a.custom"),
                                                        allowed: ["custom"]))
    }

    func testSidecarDetection() throws {
        let url = try makeWALDatabase()
        let sidecars = DatabaseSidecars.detect(for: url)
        XCTAssertNotNil(sidecars.wal)
        XCTAssertNotNil(sidecars.shm)
        XCTAssertTrue(sidecars.hasPendingWAL)
        XCTAssertEqual(sidecars.wal?.name, "wal.sqlite-wal")
    }

    func testUncommittedWALRowsAreVisible() throws {
        let url = try makeWALDatabase()
        let opened = try XCTUnwrap(Database.openForReading(url: url))
        defer { opened.database.close() }
        XCTAssertFalse(opened.walIsStale)
        XCTAssertEqual(try opened.database.scalar("SELECT COUNT(*) FROM notes").intValue, 2)
    }

    func testImmutableOpenIgnoresTheWAL() throws {
        let url = try makeWALDatabase()
        let db = try Database(url: url, mode: .immutable)
        defer { db.close() }
        // Only the checkpointed row is part of the main file.
        XCTAssertEqual(try db.scalar("SELECT COUNT(*) FROM notes").intValue, 1)
    }

    func testSnapshotCopiesSidecarsAndSeesWALRows() throws {
        let url = try makeWALDatabase()
        let snapshot = try DatabaseSnapshot.make(of: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot.url.path + "-wal"))
        let db = try Database(url: snapshot.url, mode: .readWrite, createIfMissing: false)
        defer { db.close() }
        XCTAssertEqual(try db.scalar("SELECT COUNT(*) FROM notes").intValue, 2)
    }

    func testCheckpointMovesWALIntoMainFile() throws {
        let url = try makeWALDatabase()
        XCTAssertGreaterThan(try XCTUnwrap(writer).checkpointWAL(), 0)

        let immutable = try Database(url: url, mode: .immutable)
        defer { immutable.close() }
        XCTAssertEqual(try immutable.scalar("SELECT COUNT(*) FROM notes").intValue, 2)
    }

    func testSummaryIncludesWALState() throws {
        let url = try makeWALDatabase()
        let summary = try DatabaseSummary.load(url: url)
        XCTAssertGreaterThan(summary.pendingWALBytes, 0)
        XCTAssertFalse(summary.walIsStale)
        XCTAssertEqual(summary.tables.first?.rowCount, 2)
    }

    func testOpeningANonDatabaseFails() throws {
        let text = directory.appendingPathComponent("notes.txt")
        try "hello".write(to: text, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try Database(url: text, mode: .readWrite, createIfMissing: false))
        XCTAssertNil(Database.openForReading(url: text))
    }
}
