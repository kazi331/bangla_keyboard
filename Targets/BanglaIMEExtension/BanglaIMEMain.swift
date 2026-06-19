import Cocoa
import InputMethodKit

/// Custom NSApplication subclass so we can attach the app delegate before the
/// run loop starts (IMK input methods are background-only agents; this lets us
/// own the launch sequence without relying on a storyboard/Info.main).
final class NSManualApplication: NSApplication {
    private let appDelegate = BanglaAppDelegate()
    override init() {
        super.init()
        self.delegate = appDelegate
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }
}

@main
final class BanglaAppDelegate: NSObject, NSApplicationDelegate {
    private var server: IMKServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Touch the shared bootstrap so layout loading / DB open failures are
        // logged early rather than on the first keystroke.
        _ = IMEBootstrap.shared

        let connectionName = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String
        server = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier)
        NSLog("BanglaIME: IMKServer started (connection=\(connectionName ?? "nil"))")
    }

    func applicationWillTerminate(_ notification: Notification) {
        server = nil
    }
}