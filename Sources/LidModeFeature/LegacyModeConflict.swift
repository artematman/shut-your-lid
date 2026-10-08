import Foundation

/// Read-only migration gate. A running Island UI is not a power controller.
/// Only its registered daemon or an actual helper process can conflict.
/// The controller separately refuses an already-set system sleep flag.
public enum LegacyModeConflict {
    public static func isPresent() -> Bool { isPresent(probe: succeeds) }

    static func isPresent(probe: (String, [String]) -> Bool) -> Bool {
        for label in ["local.artem.islandpro.beta.power", "local.artem.islandpro.power"] {
            if probe("/bin/launchctl", ["print", "system/" + label]) { return true }
        }
        return probe("/usr/bin/pgrep", ["-x", "IslandPowerHelper"])
    }

    private static func succeeds(_ path: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch { return true }
    }
}
