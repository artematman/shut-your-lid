import Foundation
import Testing
@testable import LidModeFeature

@Suite("Failure recovery", .serialized)
struct RecoveryTests {
 final class Power: LidPowerSettings, @unchecked Sendable {
  var flag = false
  var failRead = false
  var failRestore = false
  var ignoredRestore = false
  func sleepDisabled() throws -> Bool {
   if failRead { throw LidModeError.notApplied("read failed") }; return flag
  }
  func setSleepDisabled(_ value: Bool) throws {
   if !value && failRestore { throw LidModeError.notApplied("restore failed") }
   if !value && ignoredRestore { return }
   flag = value
  }
  func sleepNow() {}
 }
 let cool = LidPowerReading(onBattery: false, batteryPercent: 80, thermalSeriousOrWorse: false, lidClosed: false)
 func url() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("recovery-\(UUID()).json") }

 @Test("failed restoration keeps recovery record, reports error and retries on tick")
 func failedRestore() throws {
  let power=Power(); let file=url(); defer { try? FileManager.default.removeItem(at:file) }
  let controller=LidModeController(settings:power,stateURL:file)
  _ = try controller.enable(maxMinutes:240,batteryFloor:20,power:cool)
  power.failRestore=true
  let status=controller.disable(reason:.user)
  #expect(status.error != nil && !status.active && power.flag)
  #expect(FileManager.default.fileExists(atPath:file.path))
  power.failRestore=false
  #expect(controller.tick(power:cool) == .failed)
  #expect(!power.flag && !FileManager.default.fileExists(atPath:file.path))
 }
 @Test("restart with failed restore blocks enable until restoration succeeds")
 func failedRecovery() throws {
  let power=Power();let file=url();defer { try? FileManager.default.removeItem(at:file) }
  let first=LidModeController(settings:power,stateURL:file)
  _ = try first.enable(maxMinutes:240,batteryFloor:20,power:cool)
  power.failRestore=true
  let restarted=LidModeController(settings:power,stateURL:file)
  #expect(restarted.recoverOnLaunch().error != nil)
  #expect(throws:LidModeError.self) { _ = try restarted.enable(maxMinutes:240,batteryFloor:20,power:cool) }
  power.failRestore=false
  #expect(restarted.recoverOnLaunch().error == nil && !power.flag)
 }
 @Test("corrupt record restores normal sleep, verifies it, then removes the file and allows enable")
 func corruptRecordRestores() throws {
  let power=Power();let file=url();defer { try? FileManager.default.removeItem(at:file) }
  power.flag=true
  try Data("invalid".utf8).write(to:file)
  let controller=LidModeController(settings:power,stateURL:file)
  let status=controller.recoverOnLaunch()
  #expect(status.error == nil && !power.flag && !FileManager.default.fileExists(atPath:file.path))
  _ = try controller.enable(maxMinutes:240,batteryFloor:20,power:cool)
  #expect(power.flag)
 }
 @Test("corrupt record with a failed or ignored reset keeps the file and the error, blocks enable and retries on tick")
 func corruptRecordFailedReset() throws {
  for ignored in [false, true] {
   let power=Power();let file=url();defer { try? FileManager.default.removeItem(at:file) }
   power.flag=true
   if ignored { power.ignoredRestore=true } else { power.failRestore=true }
   try Data("invalid".utf8).write(to:file)
   let controller=LidModeController(settings:power,stateURL:file)
   #expect(controller.recoverOnLaunch().error != nil)
   #expect(power.flag && FileManager.default.fileExists(atPath:file.path))
   #expect(throws:LidModeError.self) { _ = try controller.enable(maxMinutes:240,batteryFloor:20,power:cool) }
   #expect(controller.tick(power:cool) == .failed && controller.status().error != nil)
   power.failRestore=false; power.ignoredRestore=false
   _ = controller.tick(power:cool)
   #expect(!power.flag && !FileManager.default.fileExists(atPath:file.path) && controller.status().error == nil)
  }
 }
 @Test("no recovery file: launch, termination and ticks never touch a flag set by someone else")
 func noFileLeavesFlag() {
  let power=Power();let file=url()
  power.flag=true
  let controller=LidModeController(settings:power,stateURL:file)
  #expect(controller.recoverOnLaunch().error == nil)
  #expect(controller.tick(power:cool) == nil)
  #expect(controller.prepareForTermination())
  #expect(power.flag)
 }
 @Test("termination restores normal sleep, confirms it and refuses any new lease")
 func terminationRestores() throws {
  let power=Power();let file=url();defer { try? FileManager.default.removeItem(at:file) }
  let controller=LidModeController(settings:power,stateURL:file)
  _ = try controller.enable(maxMinutes:240,batteryFloor:20,power:cool)
  #expect(power.flag)
  #expect(controller.prepareForTermination())
  #expect(!power.flag && !FileManager.default.fileExists(atPath:file.path))
  #expect(throws:LidModeError.self) { _ = try controller.enable(maxMinutes:240,batteryFloor:20,power:cool) }
  #expect(try !controller.updateDuration(maxMinutes:60,power:cool).active && !power.flag)
 }
 @Test("termination with a failed restore reports failure and keeps the record for the next launch")
 func terminationFailedRestore() throws {
  let power=Power();let file=url();defer { try? FileManager.default.removeItem(at:file) }
  let controller=LidModeController(settings:power,stateURL:file)
  _ = try controller.enable(maxMinutes:240,batteryFloor:20,power:cool)
  power.failRestore=true
  #expect(!controller.prepareForTermination())
  #expect(power.flag && FileManager.default.fileExists(atPath:file.path))
  power.failRestore=false
  let relaunched=LidModeController(settings:power,stateURL:file)
  #expect(relaunched.recoverOnLaunch().error == nil && !power.flag)
 }
 @Test("a read failure never defaults to sleep enabled or changes pmset")
 func readFailure() {
  let power=Power();power.failRead=true
  let controller=LidModeController(settings:power,stateURL:url())
  #expect(throws:LidModeError.self) { _ = try controller.enable(maxMinutes:240,batteryFloor:20,power:cool) }
  #expect(controller.status().error != nil && !power.flag)
 }
 @Test("successful command with unchanged flag is still a restoration failure")
 func ignoredRestoration() throws {
  let power=Power();let file=url();defer { try? FileManager.default.removeItem(at:file) }
  let controller=LidModeController(settings:power,stateURL:file)
  _ = try controller.enable(maxMinutes:240,batteryFloor:20,power:cool)
  power.ignoredRestore=true
  #expect(controller.disable(reason:.user).error != nil)
  #expect(power.flag && FileManager.default.fileExists(atPath:file.path))
 }
 @Test("client disconnect restores its own lease")
 func appGone() throws {
  let power=Power();let file=url();defer { try? FileManager.default.removeItem(at:file) }
  let controller=LidModeController(settings:power,stateURL:file)
  _ = try controller.enable(maxMinutes:240,batteryFloor:20,power:cool)
  let status=controller.disable(reason:.appGone)
  #expect(!power.flag && status.lastStopReason == .appGone)
 }
 @Test("lease allows heartbeat at 90 seconds and expires after 90")
 func leaseBoundary() throws {
  final class Clock { var date=Date() }
  let clock=Clock();let power=Power();let file=url();defer { try? FileManager.default.removeItem(at:file) }
  let controller=LidModeController(settings:power,stateURL:file,now:{clock.date},elapsed:{clock.date.timeIntervalSince1970})
  _ = try controller.enable(maxMinutes:240,batteryFloor:20,power:cool)
  clock.date += 90
  #expect(controller.tick(power:cool) == nil)
  clock.date += 1
  #expect(controller.tick(power:cool) == .heartbeatLost && !power.flag)
 }
}
@MainActor @Suite("Revoked permission", .serialized)
struct RevocationTests {
 @Test(arguments:[LidModeModel.ServiceState.requiresApproval,.notRegistered])
 func revocation(_ next:LidModeModel.ServiceState) async {
  let fake=LidModeSwitchTests.FakeSystem();fake.service = .enabled
  let model=LidModeModel(system:fake.system());await model.setEnabled(true)
  #expect(model.isOn)
  fake.service=next;await model.refresh();#expect(!model.isOn)
 }
 @Test("helper restoration failure keeps switch off with the reported error")
 func restorationError() async {
  let fake=LidModeSwitchTests.FakeSystem();fake.service = .enabled
  fake.helper=LidModeStatus(active:true,sleepDisabledNow:true,error:"restore failed")
  let model=LidModeModel(system:fake.system());await model.refresh()
  #expect(model.phase == .failed("restore failed") && !model.isOn)
  let failing = LidModeModel(system: .init(serviceState: { .enabled }, register: {}, openLoginItems: {}, call: { _ in LidModeStatus(sleepDisabledNow: true, error: "restore failed") }))
  await failing.setEnabled(false)
  #expect(failing.phase == .failed("restore failed"))
 }
}

@MainActor @Suite("Migration gate")
struct MigrationTests {
 @Test("legacy conflict blocks registration and all helper requests")
 func conflict() async {
  var registered = false
  var requested = false
  var opened = false
  let model = LidModeModel(system: .init(preflight: { "legacy conflict" }, serviceState: { .notRegistered }, register: { registered = true }, openLoginItems: { opened = true }, call: { _ in requested = true; return nil }))
  await model.setEnabled(true)
  #expect(model.phase == .failed("legacy conflict") && !model.isOn)
  #expect(!registered && !requested && !opened)
 }
}

@Suite("Helper launch constraint")
struct HelperLaunchConstraintTests {
 @Test("daemon plist pins launchd to the Developer ID helper of the expected team and identifier")
 func spawnConstraint() throws {
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let app = "com.artemkharitonov.shutyourlid"
  // Same substitution as Scripts/build-app.sh.
  let text = try String(contentsOf: root.appendingPathComponent("App/power.plist.template"), encoding: .utf8)
   .replacingOccurrences(of: "__LABEL__", with: LidPowerHelperIdentity.label(forApp: app))
   .replacingOccurrences(of: "__APP_ID__", with: app)
  let plist = try #require(try PropertyListSerialization.propertyList(from: Data(text.utf8), format: nil) as? [String: Any])
  let constraint = try #require(plist["SpawnConstraint"] as? [String: Any])
  #expect(Set(constraint.keys) == ["team-identifier", "signing-identifier", "validation-category"])
  #expect(constraint["team-identifier"] as? String == "8XZ7Z4UR6C")
  #expect(constraint["signing-identifier"] as? String == LidPowerHelperIdentity.label(forApp: app))
  #expect(constraint["validation-category"] as? Int == 6)   // Developer ID
  #expect(plist["BundleProgram"] as? String == "Contents/MacOS/LidPowerHelper")
  // The app-side XPC requirement for the helper names the same identity.
  let requirement = LidPowerHelperIdentity.clientRequirement(appBundleID: LidPowerHelperIdentity.label(forApp: app), team: "8XZ7Z4UR6C")
  #expect(requirement.contains(#"identifier "com.artemkharitonov.shutyourlid.power""#) && requirement.contains("8XZ7Z4UR6C"))
 }
}
