import Foundation

/// Fixed operations between Shut Your Lid and `LidPowerHelper`. No command,
/// path or credential crosses: the app can only ask to enable, disable,
/// update the remaining duration, heartbeat or read the status; the helper answers with `LidModeStatus` JSON.
@objc public protocol LidPowerControl {
    func status(reply: @escaping @Sendable (Data) -> Void)
    func enable(maxMinutes: Int, batteryFloor: Int, reply: @escaping @Sendable (Data) -> Void)
    func updateDuration(maxMinutes: Int, reply: @escaping @Sendable (Data) -> Void)
    func disable(reply: @escaping @Sendable (Data) -> Void)
    func heartbeat(reply: @escaping @Sendable (Data) -> Void)
}

public enum LidPowerHelperIdentity {
    /// launchd label = Mach service name = plist name (without .plist), per bundle id.
    public static func label(forApp bundleID: String) -> String { bundleID + ".power" }
    public static func plistName(forApp bundleID: String) -> String { label(forApp: bundleID) + ".plist" }
    /// Only the signed Shut Your Lid of the same team may connect.
    public static func clientRequirement(appBundleID: String, team: String) -> String {
        #"anchor apple generic and identifier ""# + appBundleID + #"" and certificate leaf[subject.OU] = ""# + team + #"""#
    }
}

/// Status encoded for the wire; errors travel inside it.
public enum LidModeWire {
    public static func encode(_ status: LidModeStatus) -> Data { (try? JSONEncoder().encode(status)) ?? Data() }
    public static func decode(_ data: Data) -> LidModeStatus? { try? JSONDecoder().decode(LidModeStatus.self, from: data) }
}
