import Foundation
import BanglaXPC

/// XPC client used by the IME to reach the Settings app's listener.
///
/// The IME reads most preferences directly from the shared UserDefaults suite
/// (cheaper than an IPC round-trip per keystroke). This client is used for the
/// coarser, occasional operations the Settings app owns (vacuum, burn history,
/// version handshake). Connections are created lazily and torn down after each
/// call. If the Settings app isn't running, calls fail soft (return nil/false)
/// rather than blocking the input path.
final class BanglaXPCClient {
    static let shared = BanglaXPCClient()

    private func makeConnection() -> NSXPCConnection? {
        let connection = NSXPCConnection(machServiceName: BanglaXPCConstants.serviceLabel)
        connection.remoteObjectInterface = NSXPCInterface(with: BanglaXPProtocol.self)
        connection.resume()
        return connection
    }

    func activeLayout() -> String? {
        guard let connection = makeConnection(),
              let proxy = connection.remoteObjectProxy as? BanglaXPProtocol else { return nil }
        var result: String?
        let group = DispatchGroup()
        group.enter()
        proxy.getActiveLayout { layout in result = layout; group.leave() }
        _ = group.wait(timeout: .now() + 1)
        connection.invalidate()
        return result
    }

    func burnHistory() -> Bool {
        guard let connection = makeConnection(),
              let proxy = connection.remoteObjectProxy as? BanglaXPProtocol else { return false }
        var result = false
        let group = DispatchGroup()
        group.enter()
        proxy.burnHistory { ok in result = ok; group.leave() }
        _ = group.wait(timeout: .now() + 1)
        connection.invalidate()
        return result
    }

    func vacuum() -> Bool {
        guard let connection = makeConnection(),
              let proxy = connection.remoteObjectProxy as? BanglaXPProtocol else { return false }
        var result = false
        let group = DispatchGroup()
        group.enter()
        proxy.vacuumUserDB { ok in result = ok; group.leave() }
        _ = group.wait(timeout: .now() + 1)
        connection.invalidate()
        return result
    }
}