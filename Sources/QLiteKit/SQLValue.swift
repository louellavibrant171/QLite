import Foundation

/// A single value as stored by SQLite's dynamic type system.
public enum SQLValue: Hashable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    /// The SQLite storage class name (`NULL`, `INTEGER`, `REAL`, `TEXT`, `BLOB`).
    public var storageClass: String {
        switch self {
        case .null: return "NULL"
        case .integer: return "INTEGER"
        case .real: return "REAL"
        case .text: return "TEXT"
        case .blob: return "BLOB"
        }
    }

    /// Human readable representation used by the table views and exporters.
    public var displayString: String {
        switch self {
        case .null: return "NULL"
        case .integer(let v): return String(v)
        case .real(let v): return String(v)
        case .text(let v): return v
        case .blob(let data): return "<BLOB \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))>"
        }
    }

    /// Text suitable for round-tripping through an editor field. Blobs are hex encoded.
    public var editableString: String {
        switch self {
        case .blob(let data): return "x'" + data.map { String(format: "%02x", $0) }.joined() + "'"
        default: return displayString
        }
    }

    public var isNull: Bool { if case .null = self { return true }; return false }

    public var intValue: Int64? {
        switch self {
        case .integer(let v): return v
        case .real(let v): return Int64(v)
        case .text(let v): return Int64(v)
        default: return nil
        }
    }

    public var stringValue: String? {
        switch self {
        case .text(let v): return v
        case .integer(let v): return String(v)
        case .real(let v): return String(v)
        default: return nil
        }
    }

    /// Coerces user entered text into a value honouring the column's declared type affinity.
    /// - Parameters:
    ///   - text: raw text typed by the user.
    ///   - declaredType: the column's declared type, e.g. `INTEGER`, `VARCHAR(20)`.
    public static func coerce(_ text: String, declaredType: String?) -> SQLValue {
        let affinity = TypeAffinity.of(declaredType)
        switch affinity {
        case .integer:
            if let i = Int64(text) { return .integer(i) }
            if let d = Double(text) { return .real(d) }
            return .text(text)
        case .real, .numeric:
            if let i = Int64(text), affinity == .numeric { return .integer(i) }
            if let d = Double(text) { return .real(d) }
            return .text(text)
        case .blob:
            if let data = Data(hexLiteral: text) { return .blob(data) }
            return .text(text)
        case .text:
            return .text(text)
        }
    }
}

/// SQLite's five type affinities, derived from a column's declared type.
public enum TypeAffinity: String {
    case integer = "INTEGER"
    case text = "TEXT"
    case blob = "BLOB"
    case real = "REAL"
    case numeric = "NUMERIC"

    /// Implements the affinity determination rules from the SQLite documentation.
    public static func of(_ declaredType: String?) -> TypeAffinity {
        guard let declared = declaredType?.uppercased(), !declared.isEmpty else { return .blob }
        if declared.contains("INT") { return .integer }
        if declared.contains("CHAR") || declared.contains("CLOB") || declared.contains("TEXT") { return .text }
        if declared.contains("BLOB") { return .blob }
        if declared.contains("REAL") || declared.contains("FLOA") || declared.contains("DOUB") { return .real }
        return .numeric
    }
}

extension Data {
    /// Parses `x'ABCD'` / `ABCD` style hex literals produced by `SQLValue.editableString`.
    init?(hexLiteral: String) {
        var hex = hexLiteral.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.lowercased().hasPrefix("x'") && hex.hasSuffix("'") {
            hex = String(hex.dropFirst(2).dropLast())
        }
        guard !hex.isEmpty, hex.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }
}
