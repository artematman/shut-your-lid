import Foundation
/// Read-only migration gate. Never uses Island's XPC, permissions or state files.
public enum LegacyModeConflict {
 public static func isPresent() -> Bool {
  for label in ["local.artem.islandpro.beta.power", "local.artem.islandpro.power"] {
   if succeeds("/bin/launchctl", ["print", "system/" + label]) { return true }
  }
  return succeeds("/usr/bin/pgrep", ["-f", "/Contents/MacOS/(IslandPowerHelper|IslandPro|NotchFlowApp)"])
 }
 private static func succeeds(_ path: String, _ arguments: [String]) -> Bool {
  let process = Process(); process.executableURL = URL(fileURLWithPath: path); process.arguments = arguments
  process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
  do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 } catch { return true }
 }
}
