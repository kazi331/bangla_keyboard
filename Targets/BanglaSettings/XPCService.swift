import Foundation
import BanglaStorage
import BanglaXPC

/// Concrete implementation of `BanglaXPProtocol`, backed by the shared user.db
/// and shared UserDefaults. Hosted by the Settings app's XPC listener.
final class BanglaXPCService: NSObject, BanglaXPProtocol {
    private let pool: ConnectionPool?
    private let startupError: String?

    /// Non-throwing so it can be used as `exportedObject`; captures any failure.
    init() {
        var pool: ConnectionPool? = nil
        var err: String? = nil
        do {
            try SharedPaths.ensureSupportDir()
            let p = try ConnectionPool(path: SharedPaths.userDB.path, kind: .user)
            try Migration.migrate(p)
            pool = p
        } catch {
            err = "\(error)"
        }
        self.pool = pool
        self.startupError = err
        super.init()
        if let e = err { NSLog("BanglaXPCService storage init failed: \(e)") }
    }

    var available: Bool { pool != nil }

    private var defaults: UserDefaults { SharedDefaults.defaults }

    func getActiveLayout(withReply reply: @escaping (String) -> Void) {
        reply(defaults.string(forKey: SharedDefaults.Key.activeLayout) ?? "avro-phonetic")
    }

    func setActiveLayout(_ layoutId: String, withReply reply: @escaping (Bool) -> Void) {
        defaults.set(layoutId, forKey: SharedDefaults.Key.activeLayout)
        reply(true)
    }

    func getTelemetryOptIn(withReply reply: @escaping (Bool) -> Void) {
        reply(defaults.bool(forKey: SharedDefaults.Key.telemetryOptIn))
    }

    func setTelemetryOptIn(_ enabled: Bool, withReply reply: @escaping (Bool) -> Void) {
        defaults.set(enabled, forKey: SharedDefaults.Key.telemetryOptIn)
        reply(true)
    }

    func vacuumUserDB(withReply reply: @escaping (Bool) -> Void) {
        guard let pool else { reply(false); return }
        do { try pool.connection().exec("VACUUM;"); reply(true) }
        catch { NSLog("vacuum failed: \(error)"); reply(false) }
    }

    func burnHistory(withReply reply: @escaping (Bool) -> Void) {
        guard let pool else { reply(false); return }
        do { try UserRepository(pool: pool).burnHistory(); reply(true) }
        catch { NSLog("burnHistory failed: \(error)"); reply(false) }
    }

    func reloadLexicon(withReply reply: @escaping (Bool) -> Void) {
        // The lexicon is bundled and read-only; reload is a no-op signal that the
        // IME should reopen its read-only connection. Always succeeds.
        reply(true)
    }

    func imeVersion(withReply reply: @escaping (String) -> Void) {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        reply(v)
    }
}