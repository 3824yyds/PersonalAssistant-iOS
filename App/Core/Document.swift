import Foundation

public enum AppError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// Keeps optional Android fields intact instead of silently discarding data during migration.
public enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), int(Int64), double(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int64.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public var object: [String: JSONValue] { if case .object(let v) = self { return v }; return [:] }
    public var array: [JSONValue] { if case .array(let v) = self { return v }; return [] }
    public var text: String { if case .string(let v) = self { return v }; return "" }
    public var number: Int64 { if case .int(let v) = self { return v }; return 0 }
    public var flag: Bool { if case .bool(let v) = self { return v }; return false }
}

public struct Item: Codable, Equatable, Identifiable, Sendable {
    public var raw: [String: JSONValue]
    public init(_ raw: [String: JSONValue] = [:]) { self.raw = raw }
    public init(from decoder: Decoder) throws { raw = try [String: JSONValue](from: decoder) }
    public func encode(to encoder: Encoder) throws { try raw.encode(to: encoder) }
    public var id: String { text("id", fallback: text("accountId", fallback: text("assetId", fallback: text("month") + "|" + text("currency") + "|" + text("category")))) }
    public func text(_ key: String, fallback: String = "") -> String { raw[key]?.text ?? fallback }
    public func int(_ key: String, fallback: Int64 = 0) -> Int64 { raw[key]?.number ?? fallback }
    public func bool(_ key: String, fallback: Bool = false) -> Bool { raw[key]?.flag ?? fallback }
    public func items(_ key: String) -> [Item] { (raw[key]?.array ?? []).map { Item($0.object) } }
    public func strings(_ key: String) -> [String] { (raw[key]?.array ?? []).map(\.text) }
    public mutating func set(_ key: String, _ value: String) { raw[key] = .string(value) }
    public mutating func set(_ key: String, _ value: Int64) { raw[key] = .int(value) }
    public mutating func set(_ key: String, _ value: Bool) { raw[key] = .bool(value) }
    public mutating func set(_ key: String, items: [Item]) { raw[key] = .array(items.map { .object($0.raw) }) }
    public static func make(_ values: [String: JSONValue] = [:]) -> Item {
        var item = Item(values); item.set("id", UUID().uuidString.lowercased()); return item
    }
    public var date: Date { Date(timeIntervalSince1970: Double(int("date")) / 1000) }
}

public struct Document: Codable, Equatable, Sendable {
    public var root: Item
    public init(root: Item = Item(["version": .int(4), "scope": .string("all")])) { self.root = root }
    public init(from decoder: Decoder) throws {
        root = try Item(from: decoder)
        records = records.map { item in
            var r = item
            for (key, value) in ["kind":"expense","currency":"CNY","category":"其他","account":"默认账户"] where r.raw[key] == nil { r.set(key,value) }
            return r
        }
        accounts = accounts.map { item in
            var a = item
            if a.raw["currency"] == nil { a.set("currency","CNY") }
            if a.raw["type"] == nil { a.set("type","cash") }
            return a
        }
    }
    public func encode(to encoder: Encoder) throws { try root.encode(to: encoder) }
    public var records: [Item] { get { root.items("records") } set { root.set("records", items: newValue) } }
    public var notes: [Item] { get { root.items("notes") } set { root.set("notes", items: newValue) } }
    public var accounts: [Item] { get { root.items("accounts") } set { root.set("accounts", items: newValue) } }
    public var settings: Item { get { Item(root.raw["settings"]?.object ?? [:]) } set { root.raw["settings"] = .object(newValue.raw) } }
    public var wallet: Item { get { Item(root.raw["wallet"]?.object ?? [:]) } set { root.raw["wallet"] = .object(newValue.raw) } }
    public var currency: String { settings.text("currency", fallback: "CNY") }
    public mutating func upsert(_ item: Item, in key: String) {
        var values = root.items(key); values.removeAll { $0.id == item.id }; values.append(item); root.set(key, items: values)
    }
    public mutating func upsertWallet(_ item: Item, in key: String) {
        var w = wallet; var values = w.items(key); values.removeAll { $0.id == item.id }; values.append(item); w.set(key, items: values); wallet = w
    }
    public func encoded() throws -> Data { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return try e.encode(self) }
    public func validated() throws -> Document {
        guard (1...4).contains(root.int("version", fallback: 4)), root.text("scope", fallback: "all") == "all" else { throw AppError.message("请选择完整备份；当前不合并局部备份") }
        guard records.count <= 20_000, notes.count <= 10_000, accounts.count <= 500,
              Set(records.map(\.id)).count == records.count, Set(notes.map(\.id)).count == notes.count,
              Set(accounts.map(\.id)).count == accounts.count else { throw AppError.message("资料数量过多或包含重复标识") }
        for r in records {
            guard UUID(uuidString: r.id) != nil, !r.text("title").isEmpty, r.text("title").count <= 200,
                  r.text("body").count <= 100_000, r.int("date") > 0,
                  Money.currencies.contains(r.text("currency", fallback: "CNY")),
                  r.text("kind") == "reminder" || (1...Money.maximum).contains(r.int("cents")) else { throw AppError.message("账目内容或金额无效，请核对备份") }
        }
        for n in notes { guard UUID(uuidString: n.id) != nil, !n.text("title").isEmpty, n.text("title").count <= 200, n.text("body").count <= 100_000 else { throw AppError.message("笔记内容无效") } }
        for a in accounts { guard UUID(uuidString: a.id) != nil, !a.text("name").isEmpty, Money.currencies.contains(a.text("currency", fallback: "CNY")), (-Money.maximum...Money.maximum).contains(a.int("openingCents")) else { throw AppError.message("账户资料无效") } }
        guard Set(accounts.map { $0.text("currency", fallback: "CNY") + "|" + $0.text("name") }).count == accounts.count else { throw AppError.message("同币种账户名称重复") }
        let expenses = Dictionary(uniqueKeysWithValues: records.filter { $0.text("kind") == "expense" }.map { ($0.id, $0) })
        for (id, refunds) in Dictionary(grouping: records.filter { $0.text("kind") == "refund" }, by: { $0.text("linkId") }) {
            guard let expense = expenses[id], refunds.allSatisfy({ $0.text("currency") == expense.text("currency") }), refunds.reduce(Int64(0), { $0 + $1.int("cents") }) <= expense.int("cents") else { throw AppError.message("退款缺少原支出或累计退款超过原金额") }
        }
        try Validation.extra(self)
        return self
    }
}

public enum Clock {
    public static var milliseconds: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
    public static func day(_ date: Date = Date()) -> String { let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date) }
    public static func month(_ date: Date = Date()) -> String { String(day(date).prefix(7)) }
    public static func date(_ value: String) -> Date? { let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false; return f.date(from: value) }
}
