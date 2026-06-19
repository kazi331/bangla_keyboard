import SwiftUI
import BanglaEngine
import BanglaStorage
import BanglaXPC

@main
struct BanglaSettingsApp: App {
    @NSApplicationDelegateAdaptor(SettingsAppDelegate.self) var delegate
    @StateObject private var model = AppSettingsModel()

    var body: some Scene {
        Settings {
            SettingsRoot(model: model)
        }
        // A tiny menu-bar presence so the app can host the XPC listener even when
        // no settings window is open.
        MenuBarExtra("BanglaIME", systemImage: "character.bubble") {
            Text("Bangla IME \(model.version)")
            Divider()
            Button("Open Settings…") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Sets up the embedded XPC listener on launch.
final class SettingsAppDelegate: NSObject, NSApplicationDelegate, NSXPCListenerDelegate {
    private var listener: NSXPCListener?
    private var service: BanglaXPCService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let svc = BanglaXPCService()
        let listener = NSXPCListener(machServiceName: BanglaXPCConstants.serviceLabel)
        listener.delegate = self
        listener.resume()
        self.listener = listener
        self.service = svc
        NSLog("BanglaIME XPC listener armed: \(BanglaXPCConstants.serviceLabel) (available=\(svc.available))")
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let svc = service else { return false }
        connection.exportedInterface = NSXPCInterface(with: BanglaXPProtocol.self)
        connection.exportedObject = svc
        connection.resume()
        return true
    }
}