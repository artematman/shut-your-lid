import Foundation
import Testing

@testable import LidModeFeature

/// MOCK level: the lid-closed mode's controller and switch with fake power
/// settings — no real `pmset`, no SMAppService, no change to this Mac's sleep.
/// The real check (closed lid for minutes with a running task) needs the owner.
@Suite("Lid-closed mode", .serialized)
struct LidModeCoreTests {
    final class FakePmset: LidPowerSettings, @unchecked Sendable {
        var flag = false
        var failSet = false
        var ignoreSet = false
        var sets: [Bool] = []
        var sleeps = 0
        func sleepDisabled() throws -> Bool { flag }
        func setSleepDisabled(_ value: Bool) throws {
            sets.append(value)
            if failSet { throw LidModeError.notApplied("authorization denied") }
            if !ignoreSet { flag = value }
        }
        func sleepNow() { sleeps += 1 }
    }

    final class Clock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 1_800_000_000) }

    static let cool = LidPowerReading(onBattery: false, batteryPercent: 80, thermalSeriousOrWorse: false, lidClosed: false)

    private func make(_ pmset: FakePmset, _ clock: Clock, url: URL? = nil) -> (LidModeController, URL) {
        let file = url ?? FileManager.default.temporaryDirectory.appendingPathComponent("lid-\(UUID().uuidString).json")
        return (LidModeController(settings: pmset, stateURL: file, now: { clock.now }, elapsed: { clock.now.timeIntervalSince1970 }), file)
    }

    @Test("on: flag set and VERIFIED, state written first; off: previous value restored and state removed")
    func onOff() throws {
        let pmset = FakePmset(); let clock = Clock()
        let (controller, file) = make(pmset, clock)
        let on = try controller.enable(maxMinutes: 240, batteryFloor: 20, power: Self.cool)
        #expect(on.active && on.sleepDisabledNow && pmset.flag)
        #expect(FileManager.default.fileExists(atPath: file.path))
        let off = controller.disable(reason: .user)
        #expect(!off.active && !off.sleepDisabledNow && !pmset.flag)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("authorization/apply failure: never reported as on; failed restoration retains its recovery record")
    func failures() {
        let pmset = FakePmset(); pmset.failSet = true
        let (controller, file) = make(pmset, Clock())
        #expect(throws: LidModeError.self) { _ = try controller.enable(maxMinutes: 60, batteryFloor: 20, power: Self.cool) }
        #expect(!controller.status().active && !pmset.flag && FileManager.default.fileExists(atPath: file.path))
        let silent = FakePmset(); silent.ignoreSet = true   // pmset "succeeds" but nothing changes
        let (c2, f2) = make(silent, Clock())
        #expect(throws: LidModeError.self) { _ = try c2.enable(maxMinutes: 60, batteryFloor: 20, power: Self.cool) }
        #expect(!c2.status().active && !FileManager.default.fileExists(atPath: f2.path))
    }

    @Test("refuses to start hot or on a low battery")
    func refusesUnsafeStart() {
        let (controller, _) = make(FakePmset(), Clock())
        #expect(throws: LidModeError.tooHot) {
            _ = try controller.enable(maxMinutes: 60, batteryFloor: 20, power: .init(onBattery: false, batteryPercent: 90, thermalSeriousOrWorse: true, lidClosed: false))
        }
        #expect(throws: LidModeError.batteryTooLow(15)) {
            _ = try controller.enable(maxMinutes: 60, batteryFloor: 20, power: .init(onBattery: true, batteryPercent: 15, thermalSeriousOrWorse: false, lidClosed: false))
        }
    }

    @Test("helper crash / SIGKILL / reboot: the next launch restores the previous value from the state file")
    func recoveryAfterCrash() throws {
        let pmset = FakePmset(); let clock = Clock()
        let (first, file) = make(pmset, clock)
        _ = try first.enable(maxMinutes: 240, batteryFloor: 20, power: Self.cool)
        // The process dies here; the flag is still set on the machine.
        #expect(pmset.flag)
        let (relaunched, _) = make(pmset, clock, url: file)
        let status = relaunched.recoverOnLaunch()
        #expect(!pmset.flag && !status.active && status.lastStopReason == .recoveredAfterRestart)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("guards: battery floor, heat, time limit, lost heartbeat → restored; with the lid closed the Mac is asked to sleep")
    func guards() throws {
        for (reading, advance, expected) in [
            (LidPowerReading(onBattery: true, batteryPercent: 20, thermalSeriousOrWorse: false, lidClosed: true), 0.0, LidModeStatus.StopReason.batteryFloor),
            (LidPowerReading(onBattery: false, batteryPercent: 90, thermalSeriousOrWorse: true, lidClosed: true), 0, .thermal),
            (Self.cool, 241 * 60, .timeLimit),
            (Self.cool, 91, .heartbeatLost),
        ] {
            let pmset = FakePmset(); let clock = Clock()
            let (controller, _) = make(pmset, clock)
            _ = try controller.enable(maxMinutes: 240, batteryFloor: 20, power: Self.cool)
            clock.now = clock.now.addingTimeInterval(advance)
            let reason = controller.tick(power: reading)
            #expect(reason == expected && !pmset.flag, "\(expected)")
            #expect(pmset.sleeps == (reading.lidClosed || expected == .batteryFloor ? 1 : 0))
        }
        // Heartbeats keep it on.
        let pmset = FakePmset(); let clock = Clock()
        let (controller, _) = make(pmset, clock)
        _ = try controller.enable(maxMinutes: 240, batteryFloor: 20, power: Self.cool)
        for _ in 0..<5 { clock.now = clock.now.addingTimeInterval(60); _ = controller.heartbeat(); #expect(controller.tick(power: Self.cool) == nil) }
        #expect(pmset.flag)
    }

    @Test("an existing foreign flag blocks enable and is never cleared")
    func foreignFlag() throws {
        let pmset = FakePmset(); pmset.flag = true          // set by another tool before us
        let (controller, _) = make(pmset, Clock())
        #expect(throws: LidModeError.self) { _ = try controller.enable(maxMinutes: 60, batteryFloor: 20, power: Self.cool) }
        #expect(pmset.flag && pmset.sets.isEmpty)
        let untouched = FakePmset(); untouched.flag = true
        let (c2, _) = make(untouched, Clock())
        _ = c2.disable(reason: .user)
        #expect(untouched.flag && untouched.sets.isEmpty, "never cleared a flag it did not set")
    }

    @Test("pmset -g parsing: SleepDisabled appears only while set")
    func parsing() {
        #expect(PmsetPowerSettings.parseSleepDisabled(" SleepDisabled\t\t1\n sleep 1\n"))
        #expect(!PmsetPowerSettings.parseSleepDisabled(" SleepDisabled\t\t0\n"))
        #expect(!PmsetPowerSettings.parseSleepDisabled(" sleep                1 (sleep prevented by powerd)\n standby 1\n"))
    }

    @Test("only the signed Shut Your Lid of the same team may talk to the helper")
    func identity() {
        #expect(LidPowerHelperIdentity.label(forApp: "com.artemkharitonov.shutyourlid") == "com.artemkharitonov.shutyourlid.power")
        let requirement = LidPowerHelperIdentity.clientRequirement(appBundleID: "com.artemkharitonov.shutyourlid", team: "8XZ7Z4UR6C")
        #expect(requirement.contains(#"identifier "com.artemkharitonov.shutyourlid""#) && requirement.contains("8XZ7Z4UR6C") && requirement.hasPrefix("anchor apple generic"))
    }
}

@MainActor
@Suite("Lid-closed switch", .serialized)
struct LidModeSwitchTests {
    @MainActor final class FakeSystem {
        var service: LidModeModel.ServiceState = .notRegistered
        var registerResult: LidModeModel.ServiceState = .requiresApproval
        var helper: LidModeStatus? = LidModeStatus(active: true, sleepDisabledNow: true, expiresAt: Date().addingTimeInterval(3600))
        var opened = 0
        var requests: [String] = []
        func system() -> LidModeModel.System {
            LidModeModel.System(
                serviceState: { self.service },
                register: { self.service = self.registerResult; if self.registerResult == .requiresApproval { throw NSError(domain: "SMAppServiceErrorDomain", code: 1) } },
                openLoginItems: { self.opened += 1 },
                call: { request in
                    self.requests.append(String(describing: request).components(separatedBy: "(").first ?? "")
                    if case .disable = request { return LidModeStatus(active: false, sleepDisabledNow: false, lastStopReason: .user) }
                    return self.helper
                })
        }
    }

    @Test("first time: registers, waits for the system approval, opens Login Items; never shows «on» before the helper confirms")
    func approvalFlow() async {
        let fake = FakeSystem()
        let model = LidModeModel(system: fake.system())
        await model.setEnabled(true)
        #expect(model.phase == .needsApproval && !model.isOn && fake.opened == 1)
        #expect(fake.requests.isEmpty, "nothing was asked of the helper yet")
        fake.service = .enabled                      // the user approved in System Settings
        await model.refresh()                        // back in Shut Your Lid
        #expect(model.isOn && fake.requests == ["enable"])
    }

    @Test("refused / revoked approval, helper error or silence: the switch stays off with the reason")
    func refusals() async {
        let fake = FakeSystem(); fake.service = .requiresApproval
        let model = LidModeModel(system: fake.system())
        await model.setEnabled(true)
        #expect(!model.isOn && model.phase == .needsApproval)
        fake.service = .enabled; fake.helper = LidModeStatus(active: false, sleepDisabledNow: false, error: "notApplied")
        await model.setEnabled(true)
        #expect(!model.isOn && model.phase == .failed("notApplied"))
        fake.helper = nil
        await model.setEnabled(true)
        #expect(!model.isOn)
        if case .failed = model.phase {} else { Issue.record("silence is a failure, not on") }
        fake.service = .notFound
        await model.setEnabled(true)
        if case .unavailable = model.phase {} else { Issue.record("no helper in the bundle") }
    }

    @Test("off returns normal sleep (helper confirms) and remembers why it turned itself off")
    func offAndStopReason() async {
        let fake = FakeSystem(); fake.service = .enabled
        let model = LidModeModel(system: fake.system())
        await model.setEnabled(true)
        #expect(model.isOn)
        await model.setEnabled(false)
        #expect(model.phase == .off && fake.requests.last == "disable")
        fake.helper = LidModeStatus(active: false, sleepDisabledNow: false, lastStopReason: .batteryFloor)
        await model.refresh()
        #expect(model.lastStop == .batteryFloor)
    }
}
