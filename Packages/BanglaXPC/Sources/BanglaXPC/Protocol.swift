import Foundation

/// XPC protocol between Settings app (listener) and IME extension (client).
/// Must be @objc to cross XPC.
@objc public protocol BanglaXPProtocol {
    func getActiveLayout(withReply reply: @escaping (String) -> Void)
    func setActiveLayout(_ layoutId: String, withReply reply: @escaping (Bool) -> Void)
    func getTelemetryOptIn(withReply reply: @escaping (Bool) -> Void)
    func setTelemetryOptIn(_ enabled: Bool, withReply reply: @escaping (Bool) -> Void)
    func vacuumUserDB(withReply reply: @escaping (Bool) -> Void)
    func burnHistory(withReply reply: @escaping (Bool) -> Void)
    func reloadLexicon(withReply reply: @escaping (Bool) -> Void)
    func imeVersion(withReply reply: @escaping (String) -> Void)
}

public enum BanglaXPCConstants {
    /// Mach service name advertised by the Settings app's XPC listener.
    /// Production deployment requires registering this in a launchd plist and
    /// granting the Mach-lookup entitlement; see docs/INSTALL.md.
    public static let serviceLabel = "com.banglaime.xpc"
    public static let suiteIdentifier = SharedDefaults.suiteName
    /// Bundle identifiers. The IME id MUST contain `.inputmethod.` for macOS to
    /// recognise it as an input method.
    public static let imeBundleIdentifier = "com.banglaime.inputmethod.BanglaIME"
    public static let settingsBundleIdentifier = "com.banglaime.BanglaSettings"
    public static let appVersionKey = "app_version"
}