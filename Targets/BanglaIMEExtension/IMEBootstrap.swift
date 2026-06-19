import Foundation
import BanglaEngine
import BanglaStorage
import BanglaXPC

/// One-time bootstrapping of the IME: loads bundled layouts, opens the
/// read-only lexicon and read/write user databases, and constructs the shared
/// `IMEEngine` actor. Also keeps a synchronous `PhoneticResolver` cache so the
/// controller's hot path (marked-text updates) never crosses an actor hop.
final class IMEBootstrap {
    static let shared = IMEBootstrap()

    let layouts: [Layout]
    let engine: IMEEngine
    let lexiconRepo: LexiconRepository?
    let userRepo: UserRepository?
    let sessionRepo: SessionRepository?
    private var resolverCache: [String: PhoneticResolver] = [:]

    var activeLayoutId: String {
        SharedDefaults.defaults.string(forKey: SharedDefaults.Key.activeLayout) ?? "avro-phonetic"
    }

    private init() {
        let bundle = Bundle.main
        var loadedLayouts: [Layout] = []
        let layoutsURL = SharedPaths.bundledLayouts(in: bundle)
        if FileManager.default.fileExists(atPath: layoutsURL.path) {
            loadedLayouts = (try? LayoutLoader.loadAll(fromDirectory: layoutsURL)) ?? []
        }
        // Fallback to the package layout dir during in-process tests.
        if loadedLayouts.isEmpty {
            let dev = URL(fileURLWithPath: #file)
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/layouts")
            loadedLayouts = (try? LayoutLoader.loadAll(fromDirectory: dev)) ?? []
        }
        self.layouts = loadedLayouts

        let lexURL = SharedPaths.bundledLexicon(in: bundle)
        var lexiconRepo: LexiconRepository? = nil
        if FileManager.default.fileExists(atPath: lexURL.path) {
            if let pool = try? ConnectionPool(path: lexURL.path, kind: .lexicon) {
                lexiconRepo = LexiconRepository(pool: pool)
            }
        }

        var userRepo: UserRepository? = nil
        var sessionRepo: SessionRepository? = nil
        if let _ = try? SharedPaths.ensureSupportDir() {
            if let pool = try? ConnectionPool(path: SharedPaths.userDB.path, kind: .user) {
                try? Migration.migrate(pool)
                userRepo = UserRepository(pool: pool)
                sessionRepo = SessionRepository(pool: pool)
            }
        }

        self.lexiconRepo = lexiconRepo
        self.userRepo = userRepo
        self.sessionRepo = sessionRepo
        self.engine = IMEEngine(
            layouts: loadedLayouts,
            lexiconRepo: lexiconRepo,
            userRepo: userRepo,
            sessionRepo: sessionRepo
        )
    }

    func layout(for id: String) -> Layout? { layouts.first { $0.id == id } }

    /// Synchronous resolver for the marked-text hot path.
    func resolver(for layoutId: String) -> PhoneticResolver? {
        if let cached = resolverCache[layoutId] { return cached }
        guard let layout = layout(for: layoutId) else { return nil }
        let r = PhoneticResolver(layout: layout)
        resolverCache[layoutId] = r
        return r
    }
}