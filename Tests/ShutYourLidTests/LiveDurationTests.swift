import Foundation
import Testing
@testable import LidModeFeature

@Suite("Live duration updates", .serialized)
@MainActor struct LiveDurationTests {
    let ac = LidPowerReading(onBattery: false, batteryPercent: 80, thermalSeriousOrWorse: false, lidClosed: false)
    func file() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("live-duration-\(UUID()).json") }

    @Test("reschedule leaves sleep disabled and uses a new monotonic deadline")
    func reschedule() throws {
        let power = LidModeCoreTests.FakePmset(), clock = DurationAndBatteryTests.Clock(), url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        let core = LidModeController(settings: power, stateURL: url, now: { clock.wall }, elapsed: { clock.elapsed })
        let original = try core.enable(maxMinutes: 240, batteryFloor: 10, power: ac)
        clock.elapsed += 20
        let revised = try core.updateDuration(maxMinutes: 1, power: ac)
        #expect(revised.active && revised.sleepDisabledNow && power.sets == [true])
        #expect(revised.enabledAt == original.enabledAt && revised.expiresAt == clock.wall + 60)
        clock.wall -= 86_400
        clock.elapsed += 59
        #expect(core.tick(power: ac) == nil)
        clock.elapsed += 1
        #expect(core.tick(power: ac) == .timeLimit && !power.flag)
    }

    @Test("inactive and expired sessions cannot be revived by changing duration")
    func noRevival() throws {
        let power = LidModeCoreTests.FakePmset(), clock = DurationAndBatteryTests.Clock(), url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        let core = LidModeController(settings: power, stateURL: url, now: { clock.wall }, elapsed: { clock.elapsed })
        #expect(try !core.updateDuration(maxMinutes: 720, power: ac).active)
        #expect(power.sets.isEmpty)
        _ = try core.enable(maxMinutes: 1, batteryFloor: 10, power: ac)
        clock.elapsed += 60
        let result = try core.updateDuration(maxMinutes: 720, power: ac)
        #expect(!result.active && result.lastStopReason == .timeLimit && !power.flag)
    }

    @Test("battery protection takes priority over changing duration and still sleeps")
    func safety() throws {
        let power = LidModeCoreTests.FakePmset(), url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        let core = LidModeController(settings: power, stateURL: url)
        _ = try core.enable(maxMinutes: 240, batteryFloor: 10, power: ac)
        let low = LidPowerReading(onBattery: true, batteryPercent: 10, thermalSeriousOrWorse: false, lidClosed: false)
        let result = try core.updateDuration(maxMinutes: 720, power: low)
        #expect(!result.active && result.lastStopReason == .batteryFloor && power.sleeps == 1)
    }

    @Test("duration bounds remain enforced in the privileged helper")
    func bounds() throws {
        let power = LidModeCoreTests.FakePmset(), clock = DurationAndBatteryTests.Clock(), url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        let core = LidModeController(settings: power, stateURL: url, now: { clock.wall }, elapsed: { clock.elapsed })
        _ = try core.enable(maxMinutes: 30, batteryFloor: 10, power: ac)
        #expect(try core.updateDuration(maxMinutes: Int.max, power: ac).expiresAt == clock.wall + 43_200)
        #expect(try core.updateDuration(maxMinutes: -10, power: ac).expiresAt == clock.wall + 60)
        #expect(power.sets == [true])
    }

    @Test("persistence failure retains the original deadline")
    func writeFailure() throws {
        let power = LidModeCoreTests.FakePmset(), clock = DurationAndBatteryTests.Clock(), url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        let core = LidModeController(settings: power, stateURL: url, now: { clock.wall }, elapsed: { clock.elapsed })
        let original = try core.enable(maxMinutes: 30, batteryFloor: 10, power: ac)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { _ = try core.updateDuration(maxMinutes: 720, power: ac) }
        #expect(core.status().expiresAt == original.expiresAt && power.sets == [true])
    }

    @Test("slider updates coalesce; deadline changes only after helper confirmation")
    func coalescing() async throws {
        var updates: [Int] = []
        var pending: CheckedContinuation<LidModeStatus?, Never>?
        let old = Date().addingTimeInterval(3600), new = Date().addingTimeInterval(5400)
        let model = LidModeModel(system: .init(serviceState: { .enabled }, register: {}, openLoginItems: {}, call: { request in
            if case .updateDuration(let minutes) = request {
                updates.append(minutes)
                return await withCheckedContinuation { pending = $0 }
            }
            if case .disable = request { return LidModeStatus() }
            return LidModeStatus(active: true, sleepDisabledNow: true, expiresAt: old)
        }))
        await model.refresh()
        model.setDuration(minutes: 30); model.setDuration(minutes: 60); model.setDuration(minutes: 90)
        #expect(model.maxMinutes == 90 && model.canChangeDuration && model.phase == .on(until: old))
        try await Task.sleep(for: .milliseconds(700))
        #expect(updates == [90] && model.phase == .on(until: old))
        pending?.resume(returning: LidModeStatus(active: true, sleepDisabledNow: true, expiresAt: new))
        for _ in 0..<20 { await Task.yield() }
        #expect(model.phase == .on(until: new))
        await model.setEnabled(false)
    }

    @Test("turning off cancels a queued edit and ignores a late update reply")
    func stopWins() async throws {
        var pending: CheckedContinuation<LidModeStatus?, Never>?
        var updates = 0
        let model = LidModeModel(system: .init(serviceState: { .enabled }, register: {}, openLoginItems: {}, call: { request in
            if case .updateDuration = request {
                updates += 1
                return await withCheckedContinuation { pending = $0 }
            }
            if case .disable = request { return LidModeStatus() }
            return LidModeStatus(active: true, sleepDisabledNow: true, expiresAt: Date()+3600)
        }))
        await model.refresh()
        model.setDuration(minutes: 30)
        await model.setEnabled(false)
        try await Task.sleep(for: .milliseconds(400))
        #expect(updates == 0 && !model.isOn)
        await model.setEnabled(true)
        model.setDuration(minutes: 90)
        try await Task.sleep(for: .milliseconds(700))
        #expect(updates == 1)
        await model.setEnabled(false)
        pending?.resume(returning: LidModeStatus(active: true, sleepDisabledNow: true, expiresAt: Date()+5400))
        for _ in 0..<20 { await Task.yield() }
        #expect(!model.isOn)
    }
    @Test("failed live edit requests shutdown instead of leaving the old lease running")
    func failedEditStops() async throws {
        var disables = 0
        let model = LidModeModel(system: .init(serviceState: { .enabled }, register: {}, openLoginItems: {}, call: { request in
            if case .updateDuration = request { return LidModeStatus(active: true, sleepDisabledNow: true, error: "write failed") }
            if case .disable = request { disables += 1; return LidModeStatus() }
            return LidModeStatus(active: true, sleepDisabledNow: true, expiresAt: Date()+3600)
        }))
        await model.refresh()
        model.setDuration(minutes: 90)
        try await Task.sleep(for: .milliseconds(700))
        #expect(disables == 1 && model.phase == .failed("write failed"))
    }

}
