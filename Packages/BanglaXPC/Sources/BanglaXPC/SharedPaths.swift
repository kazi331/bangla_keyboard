import Foundation

/// Filesystem locations shared by the IME extension and the Settings app.
/// Kept in BanglaXPC so both sides agree without a storage dependency.
public enum SharedPaths {
    /// Per-user application support directory for BanglaIME.
    public static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("BanglaIME", isDirectory: true)
    }

    /// Read-write user database (history, n-grams, prefs, autoreplace).
    public static var userDB: URL {
        supportDir.appendingPathComponent("user.db")
    }

    /// Bundled read-only lexicon (copied into the app bundle at build time).
    public static func bundledLexicon(in bundle: Bundle) -> URL {
        bundle.url(forResource: "lexicon", withExtension: "db")
            ?? bundle.bundleURL.appendingPathComponent("Contents/Resources/lexicon.db")
    }

    /// Bundled layouts directory.
    public static func bundledLayouts(in bundle: Bundle) -> URL {
        bundle.url(forResource: "layouts", withExtension: nil)
            ?? bundle.bundleURL.appendingPathComponent("Contents/Resources/layouts")
    }

    public static func ensureSupportDir() throws {
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    }
}

/// UserDefaults suite shared between IME and Settings.
public enum SharedDefaults {
    public static let suiteName = "group.com.banglaime"

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    public enum Key {
        public static let activeLayout = "active_layout"
        public static let telemetryOptIn = "telemetry_opt_in"
        public static let autoCapitalize = "auto_capitalize"
        public static let showLatinHints = "show_latin_hints"
        public static let candidateCount = "candidate_count"
    }
}