import Foundation

public struct Layout: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let kind: LayoutKind
    public let keymap: [String: String]              // for fixed layouts
    public let rules: [PhoneticRule]                 // for phonetic layouts
    public let vowelSigns: [String: String]
    public let independentVowels: [String: String]  // standalone vowel forms (word-start)
    public let consonantEndings: [String: String]
    public let specials: [String: String]

    public enum LayoutKind: String, Sendable, Hashable {
        case phonetic
        case fixed
    }

    public init(
        id: String,
        name: String,
        kind: LayoutKind,
        keymap: [String: String] = [:],
        rules: [PhoneticRule] = [],
        vowelSigns: [String: String] = [:],
        independentVowels: [String: String] = [:],
        consonantEndings: [String: String] = [:],
        specials: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.keymap = keymap
        self.rules = rules
        self.vowelSigns = vowelSigns
        self.independentVowels = independentVowels
        self.consonantEndings = consonantEndings
        self.specials = specials
    }
}

public struct PhoneticRule: Sendable, Hashable, Codable {
    public let match: String
    public let output: String
    public let weight: Double
    public let overrides: [String]
    public let alternates: [String]

    public init(match: String, output: String, weight: Double = 1.0,
                overrides: [String] = [], alternates: [String] = []) {
        self.match = match
        self.output = output
        self.weight = weight
        self.overrides = overrides
        self.alternates = alternates
    }

    enum CodingKeys: String, CodingKey {
        case match, output, weight, overrides, alternates
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.match = try c.decode(String.self, forKey: .match)
        self.output = try c.decode(String.self, forKey: .output)
        self.weight = try c.decodeIfPresent(Double.self, forKey: .weight) ?? 1.0
        self.overrides = try c.decodeIfPresent([String].self, forKey: .overrides) ?? []
        self.alternates = try c.decodeIfPresent([String].self, forKey: .alternates) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(match, forKey: .match)
        try c.encode(output, forKey: .output)
        try c.encode(weight, forKey: .weight)
        try c.encode(overrides, forKey: .overrides)
        try c.encode(alternates, forKey: .alternates)
    }
}

/// On-disk layout file format (Avro-compatible subset).
struct LayoutFile: Codable {
    let name: String
    let id: String
    let type: String                  // "phonetic" | "fixed"
    let keymap: [String: String]?
    let rules: [PhoneticRule]?
    let vowels: [String: String]?
    let independentVowels: [String: String]?
    let consonantEnding: [String: String]?
    let specials: [String: String]?
}

public enum LayoutError: Error {
    case fileNotFound(String)
    case decodeFailure(String)
    case invalidKind(String)
}

public enum LayoutLoader {
    public static func load(from url: URL) throws -> Layout {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LayoutError.fileNotFound(url.path)
        }
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(LayoutFile.self, from: data)
        let kind: Layout.LayoutKind
        switch decoded.type.lowercased() {
        case "phonetic": kind = .phonetic
        case "fixed":    kind = .fixed
        default: throw LayoutError.invalidKind(decoded.type)
        }
        return Layout(
            id: decoded.id,
            name: decoded.name,
            kind: kind,
            keymap: decoded.keymap ?? [:],
            rules: decoded.rules ?? [],
            vowelSigns: decoded.vowels ?? [:],
            independentVowels: decoded.independentVowels ?? [:],
            consonantEndings: decoded.consonantEnding ?? [:],
            specials: decoded.specials ?? [:]
        )
    }

    public static func loadAll(fromDirectory dir: URL) throws -> [Layout] {
        let urls = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try urls.map { try load(from: $0) }
    }
}