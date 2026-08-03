import Foundation

/// Outcome of running a SQL script through the query editor.
public struct QueryExecution {
    public struct StatementResult: Identifiable {
        public let id = UUID()
        public let sql: String
        public let resultSet: ResultSet?
        public let affectedRows: Int
        public let duration: TimeInterval
        public let isReadOnly: Bool

        public init(sql: String,
                    resultSet: ResultSet?,
                    affectedRows: Int,
                    duration: TimeInterval,
                    isReadOnly: Bool) {
            self.sql = sql
            self.resultSet = resultSet
            self.affectedRows = affectedRows
            self.duration = duration
            self.isReadOnly = isReadOnly
        }
    }

    public var statements: [StatementResult] = []
    public var error: Error?
    public var totalDuration: TimeInterval = 0

    public init() {}

    /// The rows shown in the result grid: those of the last statement that returned any.
    public var displayedResult: StatementResult? {
        statements.last(where: { ($0.resultSet?.columnNames.isEmpty == false) }) ?? statements.last
    }

    public var summary: String {
        if let error { return error.localizedDescription }
        guard !statements.isEmpty else { return "Nothing to run." }
        let changed = statements.reduce(0) { $0 + $1.affectedRows }
        let returned = displayedResult?.resultSet?.rows.count ?? 0
        var parts = ["\(statements.count) statement\(statements.count == 1 ? "" : "s")"]
        if returned > 0 { parts.append("\(returned) row\(returned == 1 ? "" : "s") returned") }
        if changed > 0 { parts.append("\(changed) row\(changed == 1 ? "" : "s") affected") }
        parts.append(String(format: "%.1f ms", totalDuration * 1000))
        return parts.joined(separator: " · ")
    }
}

/// Executes free-form SQL, splitting scripts into individual statements.
public struct QueryRunner {
    private let db: Database
    /// Cap on rows materialised per statement, so a runaway `SELECT` cannot exhaust memory.
    public var maxRows: Int

    public init(database: Database, maxRows: Int = 10_000) {
        self.db = database
        self.maxRows = maxRows
    }

    public func run(_ script: String) -> QueryExecution {
        var execution = QueryExecution()
        var remaining = script
        let started = Date()

        while !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                let statement = try db.prepare(remaining)
                let consumed = remaining.count - statement.tail.count
                let sql = String(remaining.prefix(max(0, consumed))).trimmingCharacters(in: .whitespacesAndNewlines)
                remaining = statement.tail

                if statement.isEmpty {
                    if remaining.isEmpty { break } else { continue }
                }

                let statementStart = Date()
                var resultSet: ResultSet?
                if statement.columnCount > 0 {
                    var set = ResultSet(columnNames: statement.columnNames)
                    while try statement.step() {
                        if set.rows.count >= maxRows { break }
                        set.rows.append(statement.currentRow())
                    }
                    resultSet = set
                } else {
                    while try statement.step() {}
                }

                execution.statements.append(.init(sql: sql,
                                                  resultSet: resultSet,
                                                  affectedRows: statement.isReadOnly ? 0 : db.changes,
                                                  duration: Date().timeIntervalSince(statementStart),
                                                  isReadOnly: statement.isReadOnly))
            } catch {
                execution.error = error
                break
            }
        }

        execution.totalDuration = Date().timeIntervalSince(started)
        return execution
    }

    /// Runs `EXPLAIN QUERY PLAN` for a single statement.
    public func explain(_ sql: String) throws -> ResultSet {
        try db.query("EXPLAIN QUERY PLAN \(sql)")
    }
}
