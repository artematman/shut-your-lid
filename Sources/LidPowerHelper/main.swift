import Foundation
import Darwin
import IOKit.ps
#if canImport(LidModeFeature)
import LidModeFeature
#endif

/// LidPowerHelper — LaunchDaemon embedded in Shut Your Lid, registered with
/// SMAppService and approved once by the user in System Settings. Runs as
/// root only to set and restore the sleep-disabled flag (see LidModeCore).
/// Accepts connections only from the signed Shut Your Lid of the same team.

let appBundleID = "com.artemkharitonov.shutyourlid"
let stateURL = URL(fileURLWithPath: "/Library/Application Support/ShutYourLid/\(appBundleID).lid-mode.json")
// The daemon owns its persistence directory; never trust a user-created path.
guard getuid() == 0 else { exit(1) }
let stateDirectory = stateURL.deletingLastPathComponent()
do {
    try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let attributes = try FileManager.default.attributesOfItem(atPath: stateDirectory.path)
    guard attributes[.type] as? FileAttributeType == .typeDirectory,
          (attributes[.ownerAccountID] as? NSNumber)?.intValue == 0 else { exit(1) }
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stateDirectory.path)
} catch { exit(1) }
let controller = LidModeController(settings: PmsetPowerSettings(), stateURL: stateURL)
controller.recoverOnLaunch()

func powerReading() -> LidPowerReading {
    var descriptions: [[String: Any]]?
    if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
       let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
        descriptions = list.compactMap { IOPSGetPowerSourceDescription(blob, $0)?.takeUnretainedValue() as? [String: Any] }
    }
    let battery = LidPowerTelemetry.decode(descriptions)
    let thermal = ProcessInfo.processInfo.thermalState
    return LidPowerReading(onBattery: battery.onBattery, batteryPercent: battery.percent,
                           thermalSeriousOrWorse: thermal == .serious || thermal == .critical,
                           lidClosed: lidClosed())
}

func lidClosed() -> Bool {
    let root = IORegistryGetRootEntry(kIOMainPortDefault)
    defer { IOObjectRelease(root) }
    guard let value = IORegistryEntrySearchCFProperty(root, kIOServicePlane, "AppleClamshellState" as CFString, kCFAllocatorDefault,
                                                     IOOptionBits(kIORegistryIterateRecursively)) else { return false }
    return (value as? Bool) ?? false
}

final class Endpoint: NSObject, LidPowerControl {
    func status(reply: @escaping @Sendable (Data) -> Void) { reply(LidModeWire.encode(controller.status())) }
    func enable(maxMinutes: Int, batteryFloor: Int, reply: @escaping @Sendable (Data) -> Void) {
        do { reply(LidModeWire.encode(try controller.enable(maxMinutes: maxMinutes, batteryFloor: batteryFloor, power: powerReading()))) }
        catch {
            var status = controller.status()
            status.error = String(describing: error)
            reply(LidModeWire.encode(status))
        }
    }
    func updateDuration(maxMinutes: Int, reply: @escaping @Sendable (Data) -> Void) {
        do { reply(LidModeWire.encode(try controller.updateDuration(maxMinutes: maxMinutes, power: powerReading()))) }
        catch {
            var status = controller.status()
            status.error = String(describing: error)
            reply(LidModeWire.encode(status))
        }
    }
    func disable(reply: @escaping @Sendable (Data) -> Void) { reply(LidModeWire.encode(controller.disable(reason: .user))) }
    func heartbeat(reply: @escaping @Sendable (Data) -> Void) { reply(LidModeWire.encode(controller.heartbeat())) }
}

/// `connections` is touched only on the main queue (accept and invalidation
/// both hop there, in order).
final class Listener: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    var connections = 0
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(LidPowerHelperIdentity.clientRequirement(appBundleID: appBundleID, team: "8XZ7Z4UR6C"))
        connection.exportedInterface = NSXPCInterface(with: LidPowerControl.self)
        connection.exportedObject = Endpoint()
        DispatchQueue.main.async { self.connections += 1 }
        // The app is gone (quit, crash, SIGKILL): the lease ends with it.
        connection.invalidationHandler = {
            DispatchQueue.main.async {
                self.connections -= 1
                if self.connections <= 0 { _ = controller.disable(reason: .appGone) }
            }
        }
        connection.resume()
        return true
    }
}

// launchd ends the job with SIGTERM (background item switched off, app
// removed, update). Restore normal sleep before exiting, outside the POSIX
// handler: the default action is ignored and a dispatch source on the main
// queue does the work. A failed restore exits non-zero so it is never
// reported as clean; the record stays for the next launch to retry.
signal(SIGTERM, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler {
    exit(controller.prepareForTermination() ? 0 : 1)
}
termination.resume()

let delegate = Listener()
let listener = NSXPCListener(machServiceName: LidPowerHelperIdentity.label(forApp: appBundleID))
listener.delegate = delegate
listener.resume()

// Guards every 10 s while active; exit when idle so nothing stays running.
var idleSince = LidMonotonicTime.now()
let timer = DispatchSource.makeTimerSource(queue: .main)
timer.schedule(deadline: .now() + 10, repeating: 10)
timer.setEventHandler {
    if controller.status().active, LegacyModeConflict.isPresent() {
        _ = controller.disable(reason: .failed)
    } else {
        controller.tick(power: powerReading())
    }
    let status = controller.status()
    if status.active || status.error != nil {
        idleSince = LidMonotonicTime.now()
    } else if delegate.connections == 0, LidMonotonicTime.now() - idleSince > 60 {
        exit(0)
    }
}
timer.resume()
dispatchMain()
