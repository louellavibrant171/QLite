import Foundation

/// Serialises result sets to the formats offered by the Export menu.
public enum Exporter {
    public enum Format: String, CaseIterable, Identifiable {
        case csv = "CSV"
        case tsv = "TSV"
        case json = "JSON"
        case sql = "SQL INSERT"

        public var id: String { rawValue }

        public var fileExtension: String {
            switch self {
            case .csv: return "csv"
            case .tsv: return "tsv"
            case .json: return "json"
            case .sql: return "sql"
            }
        }
    }

    public static func string(from result: ResultSet, format: Format, tableName: String = "exported") -> String {
        switch format {
        case .csv: return delimited(result, separator: ",")
        case .tsv: return delimited(result, separator: "\t")
        case .json: return json(result)
        case .sql: return insertStatements(result, tableName: tableName)
        }
    }

    private static func delimited(_ result: ResultSet, separator: String) -> String {
        var lines = [result.columnNames.map { escape($0, separator: separator) }.joined(separator: separator)]
        for row in result.rows {
            lines.append(row.map { escape($0.isNull ? "" : $0.displayString, separator: separator) }.joined(separator: separator))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func escape(_ field: String, separator: String) -> String {
        guard field.contains(separator) || field.contains("\"") || field.contains("\n") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func json(_ result: ResultSet) -> String {
        let objects: [[String: Any]] = result.rows.map { row in
            var object: [String: Any] = [:]
            for (index, name) in result.columnNames.enumerated() where index < row.count {
                switch row[index] {
                case .null: object[name] = NSNull()
                case .integer(let v): object[name] = v
                case .real(let v): object[name] = v
                case .text(let v): object[name] = v
                case .blob(let data): object[name] = data.base64EncodedString()
                }
            }
            return object
        }
        guard let data = try? JSONSerialization.data(withJSONObject: objects,
                                                     options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let string = String(data: data, encoding: .utf8) else { return "[]" }
        return string + "\n"
    }

    private static func insertStatements(_ result: ResultSet, tableName: String) -> String {
        let columns = result.columnNames.map { quoteIdentifier($0) }.joined(separator: ", ")
        return result.rows.map { row in
            let values = row.map { value -> String in
                switch value {
                case .null: return "NULL"
                case .integer(let v): return String(v)
                case .real(let v): return String(v)
                case .text(let v): return quoteLiteral(v)
                case .blob(let data): return "x'" + data.map { String(format: "%02x", $0) }.joined() + "'"
                }
            }.joined(separator: ", ")
            return "INSERT INTO \(quoteIdentifier(tableName)) (\(columns)) VALUES (\(values));"
        }.joined(separator: "\n") + "\n"
    }
}
