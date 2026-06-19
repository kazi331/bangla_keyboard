import Foundation
import SwiftUI
import Combine
import BanglaStorage
import BanglaXPC

/// Observable settings model backed by shared UserDefaults + the user.db.
final class AppSettingsModel: ObservableObject {
    @Published var activeLayout: String { didSet { SharedDefaults.defaults.set(activeLayout, forKey: SharedDefaults.Key.activeLayout) } }
    @Published var candidateCount: Int { didSet { SharedDefaults.defaults.set(candidateCount, forKey: SharedDefaults.Key.candidateCount) } }
    @Published var autoCapitalize: Bool { didSet { SharedDefaults.defaults.set(autoCapitalize, forKey: SharedDefaults.Key.autoCapitalize) } }
    @Published var showLatinHints: Bool { didSet { SharedDefaults.defaults.set(showLatinHints, forKey: SharedDefaults.Key.showLatinHints) } }
    @Published var telemetryOptIn: Bool { didSet { SharedDefaults.defaults.set(telemetryOptIn, forKey: SharedDefaults.Key.telemetryOptIn) } }

    @Published var version: String = "0.0.0"
    @Published var status: String = ""
    @Published var userWordCount: Int = 0
    @Published var commitCount: Int = 0

    let layouts: [(id: String, name: String)]

    private let pool: ConnectionPool?

    init() {
        let d = SharedDefaults.defaults
        self.activeLayout = d.string(forKey: SharedDefaults.Key.activeLayout) ?? "avro-phonetic"
        self.candidateCount = (d.object(forKey: SharedDefaults.Key.candidateCount) as? Int) ?? 9
        self.autoCapitalize = d.object(forKey: SharedDefaults.Key.autoCapitalize) as? Bool ?? true
        self.showLatinHints = d.object(forKey: SharedDefaults.Key.showLatinHints) as? Bool ?? true
        self.telemetryOptIn = d.object(forKey: SharedDefaults.Key.telemetryOptIn) as? Bool ?? false
        self.version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

        // Static layout catalog (kept in sync with the bundled layout JSONs).
        self.layouts = [
            ("avro-phonetic", "Avro Phonetic"),
            ("borno", "Borno Phonetic"),
            ("probhat", "Probhat (fixed)"),
            ("munir-optical", "Munir Optical (fixed)"),
            ("national-jatiya", "National Jatiya (fixed)"),
        ]

        var p: ConnectionPool? = nil
        do {
            try SharedPaths.ensureSupportDir()
            p = try ConnectionPool(path: SharedPaths.userDB.path, kind: .user)
            try Migration.migrate(p!)
        } catch {
            self.status = "Storage unavailable: \(error.localizedDescription)"
        }
        self.pool = p
        refreshStats()
    }

    func refreshStats() {
        guard let pool else { return }
        let conn = try? pool.connection()
        userWordCount = (try? conn?.query("SELECT COUNT(*) FROM user_word;", map: { $0.int(0) }).first) ?? 0 ?? 0
        commitCount = (try? conn?.query("SELECT COUNT(*) FROM commit_log;", map: { $0.int(0) }).first) ?? 0 ?? 0
    }

    func burnHistory() {
        guard let pool else { return }
        do { try UserRepository(pool: pool).burnHistory(); status = "History cleared."; refreshStats() }
        catch { status = "Failed: \(error.localizedDescription)" }
    }

    func vacuum() {
        guard let pool else { return }
        do { try pool.connection().exec("VACUUM;"); status = "Database vacuumed." }
        catch { status = "Vacuum failed: \(error.localizedDescription)" }
    }

    func importDictionary(from url: URL) {
        guard let data = try? Data(contentsOf: url) else { status = "Could not read file."; return }
        guard let pool else { return }
        let repo = UserRepository(pool: pool)
        var n = 0
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2 else { continue }
            try? repo.upsertUserWord(bangla: parts[1], latinHint: parts[0], customFreq: 0.6)
            n += 1
        }
        status = "Imported \(n) entries."
        refreshStats()
    }

    func exportDictionary(to url: URL) {
        guard let pool else { return }
        let conn = try? pool.connection()
        let rows = (try? conn?.query("SELECT COALESCE(latin_hint,''), bangla FROM user_word ORDER BY bangla;", map: { "\($0.text(0))\t\($0.text(1))" })) ?? [] ?? []
        let text = (rows).joined(separator: "\n") + "\n"
        try? text.write(to: url, atomically: true, encoding: .utf8)
        status = "Exported \(rows.count) entries."
    }
}