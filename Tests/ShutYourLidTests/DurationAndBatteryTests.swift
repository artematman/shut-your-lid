import Foundation
import IOKit.ps
import Testing
@testable import LidModeFeature

@Suite("Duration, battery and monotonic safety", .serialized)
struct DurationAndBatteryTests {
    final class Clock { var wall = Date(timeIntervalSince1970: 1_800_000_000); var elapsed: TimeInterval = 100 }
    let ac = LidPowerReading(onBattery: false, batteryPercent: 70, thermalSeriousOrWorse: false, lidClosed: false)
    func file() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("duration-\(UUID()).json") }

    @Test(arguments: [30, 60, 120, 240, 480, 720, 37])
    func exactDuration(_ minutes: Int) throws {
        let power = LidModeCoreTests.FakePmset(), clock = Clock(), url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = LidModeController(settings: power, stateURL: url, now: { clock.wall }, elapsed: { clock.elapsed })
        let status = try controller.enable(maxMinutes: minutes, batteryFloor: 10, power: ac)
        #expect(status.expiresAt == clock.wall.addingTimeInterval(Double(minutes * 60)))
        clock.elapsed += Double(minutes * 60 - 1)
        _ = controller.heartbeat()
        #expect(controller.tick(power: ac) == nil)
        clock.elapsed += 1
        #expect(controller.tick(power: ac) == .timeLimit && !power.flag)
    }

    @Test(arguments: [-86_400.0, 86_400.0])
    func wallClockDoesNotChangeLease(_ jump: Double) throws {
        let power = LidModeCoreTests.FakePmset(), clock = Clock(), url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = LidModeController(settings: power, stateURL: url, now: { clock.wall }, elapsed: { clock.elapsed })
        _ = try controller.enable(maxMinutes: 30, batteryFloor: 10, power: ac)
        clock.wall += jump; clock.elapsed += 89
        #expect(controller.tick(power: ac) == nil)
        #expect(controller.status().expiresAt == clock.wall.addingTimeInterval(1800 - 89))
        clock.elapsed += 2
        #expect(controller.tick(power: ac) == .heartbeatLost && !power.flag)
    }

    @Test("wall-clock corrections cannot extend or shorten the selected duration")
    func wallClockDoesNotChangeDuration() throws {
        let power = LidModeCoreTests.FakePmset(), clock = Clock(), url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = LidModeController(settings: power, stateURL: url, now: { clock.wall }, elapsed: { clock.elapsed })
        _ = try controller.enable(maxMinutes: 1, batteryFloor: 10, power: ac)
        clock.wall -= 86400; clock.elapsed += 59
        #expect(controller.tick(power: ac) == nil)
        clock.elapsed += 1
        #expect(controller.tick(power: ac) == .timeLimit)
    }

    @Test(arguments: [10, 9, 0])
    func tenPercentSleepsWithOpenLid(_ percent: Int) throws {
        let power = LidModeCoreTests.FakePmset(), url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = LidModeController(settings: power, stateURL: url)
        _ = try controller.enable(maxMinutes: 240, batteryFloor: 0, power: ac)
        #expect(controller.status().batteryFloor == 10)
        #expect(controller.tick(power: .init(onBattery: true, batteryPercent: percent, thermalSeriousOrWorse: false, lidClosed: false)) == .batteryFloor)
        #expect(!power.flag && power.sleeps == 1)
    }

    @Test(arguments: [10, 9, 0])
    func refusesStartAtTenPercent(_ percent: Int) {
        let power = LidModeCoreTests.FakePmset()
        let controller = LidModeController(settings: power, stateURL: file())
        #expect(throws: LidModeError.batteryTooLow(percent)) {
            _ = try controller.enable(maxMinutes: 30, batteryFloor: 10,
                power: .init(onBattery: true, batteryPercent: percent, thermalSeriousOrWorse: false, lidClosed: false))
        }
        #expect(!power.flag && power.sets.isEmpty)
    }

    @Test("11 percent on battery and 10 percent on known AC do not stop a running mode")
    func boundaryAndAC() throws {
        let power = LidModeCoreTests.FakePmset(), url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = LidModeController(settings: power, stateURL: url)
        _ = try controller.enable(maxMinutes: 30, batteryFloor: 10, power: ac)
        #expect(controller.tick(power: .init(onBattery: true, batteryPercent: 11, thermalSeriousOrWorse: false, lidClosed: false)) == nil)
        #expect(controller.tick(power: .init(onBattery: false, batteryPercent: 10, thermalSeriousOrWorse: false, lidClosed: false)) == nil)
        #expect(power.flag && power.sleeps == 0)
    }

    @Test(arguments: [
        LidPowerReading(onBattery: nil, batteryPercent: 80, thermalSeriousOrWorse: false, lidClosed: true),
        LidPowerReading(onBattery: true, batteryPercent: nil, thermalSeriousOrWorse: false, lidClosed: true),
        LidPowerReading(onBattery: true, batteryPercent: -1, thermalSeriousOrWorse: false, lidClosed: true),
        LidPowerReading(onBattery: true, batteryPercent: 101, thermalSeriousOrWorse: false, lidClosed: true)
    ])
    func missingTelemetryFailsClosed(_ unknown: LidPowerReading) throws {
        let power = LidModeCoreTests.FakePmset(), url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = LidModeController(settings: power, stateURL: url)
        #expect(throws: LidModeError.telemetryUnavailable) { _ = try controller.enable(maxMinutes: 30, batteryFloor: 10, power: unknown) }
        #expect(!power.flag && power.sets.isEmpty)
        _ = try controller.enable(maxMinutes: 30, batteryFloor: 10, power: ac)
        #expect(controller.tick(power: unknown) == .telemetryUnavailable)
        #expect(!power.flag && power.sleeps == 1)
    }

    @Test("battery guard remembers sleep across a failed restore")
    func sleepAfterRetry() throws {
        let power = LidModeCoreTests.FakePmset(), url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = LidModeController(settings: power, stateURL: url)
        _ = try controller.enable(maxMinutes: 30, batteryFloor: 10, power: ac)
        power.failSet = true
        #expect(controller.tick(power: .init(onBattery: true, batteryPercent: 10, thermalSeriousOrWorse: false, lidClosed: false)) == .batteryFloor)
        #expect(power.sleeps == 0 && power.flag && controller.status().error != nil)
        power.failSet = false
        _ = controller.tick(power: ac)
        #expect(!power.flag && power.sleeps == 1)
    }

    @Test("sleep command failure is reported and retried after normal sleep is restored")
    func failedSleepCommand() throws {
        final class Power: LidPowerSettings, @unchecked Sendable {
            var flag = false
            var refuseSleep = true
            var sleepCalls = 0
            func sleepDisabled() throws -> Bool { flag }
            func setSleepDisabled(_ value: Bool) throws { flag = value }
            func sleepNow() throws {
                sleepCalls += 1
                if refuseSleep { throw LidModeError.notApplied("sleep failed") }
            }
        }
        let power = Power(), url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = LidModeController(settings: power, stateURL: url)
        _ = try controller.enable(maxMinutes: 30, batteryFloor: 10, power: ac)
        _ = controller.tick(power: .init(onBattery: true, batteryPercent: 10, thermalSeriousOrWorse: false, lidClosed: false))
        #expect(!power.flag && controller.status().error != nil && power.sleepCalls == 1)
        #expect(throws: LidModeError.self) { _ = try controller.enable(maxMinutes: 30, batteryFloor: 10, power: ac) }
        #expect(!power.flag)
        power.refuseSleep = false
        _ = controller.tick(power: ac)
        #expect(controller.status().error == nil && power.sleepCalls == 2)
    }

    @Test("IOPS missing, malformed and peripheral sources never default to AC")
    func decodeTelemetry() {
        let battery: [String: Any] = [kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue, kIOPSCurrentCapacityKey: 10, kIOPSMaxCapacityKey: 100]
        #expect(LidPowerTelemetry.decode([battery]).onBattery == true)
        #expect(LidPowerTelemetry.decode([battery]).percent == 10)
        #expect(LidPowerTelemetry.decode(nil).onBattery == nil)
        #expect(LidPowerTelemetry.decode([]).onBattery == nil)
        #expect(LidPowerTelemetry.decode([[:]]).onBattery == nil)
        #expect(LidPowerTelemetry.decode([battery, battery]).onBattery == nil)
        var malformed = battery; malformed[kIOPSMaxCapacityKey] = 0
        #expect(LidPowerTelemetry.decode([malformed]).percent == nil)
        malformed[kIOPSPowerSourceStateKey] = "Unknown"
        #expect(LidPowerTelemetry.decode([malformed]).onBattery == nil)
        var peripheral = battery; peripheral[kIOPSTypeKey] = "UPS"
        #expect(LidPowerTelemetry.decode([peripheral]).onBattery == nil)
        #expect(LidPowerTelemetry.decode([peripheral, battery]).percent == 10)
    }
}

@MainActor @Suite("Duration preference", .serialized)
struct DurationPreferenceTests {
    @Test("four hours is default, selection persists and reaches helper with 10 percent floor")
    func persistenceAndWire() async throws {
        let suite = "shutyourlid.tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var sent: (Int, Int)?
        let system = LidModeModel.System(serviceState: { .enabled }, register: {}, openLoginItems: {}, call: { request in
            if case .enable(let minutes, let floor) = request { sent = (minutes, floor) }
            return LidModeStatus(active: true, sleepDisabledNow: true)
        })
        let first = LidModeModel(system: system, preferences: defaults)
        #expect(first.maxMinutes == 240)
        first.setDuration(minutes: 37)
        let restored = LidModeModel(system: system, preferences: defaults)
        #expect(restored.maxMinutes == 37 && restored.usesCustomDuration)
        await restored.setEnabled(true)
        #expect(sent?.0 == 37 && sent?.1 == 10)
        restored.setDuration(minutes: 720)
        #expect(restored.maxMinutes == 37 && !restored.canChangeDuration)
    }
    @Test("invalid duration is bounded before persisting")
    func bounds() {
        let model = LidModeModel(system: .init(serviceState: { .notRegistered }, register: {}, openLoginItems: {}, call: { _ in nil }))
        model.setDuration(minutes: -100); #expect(model.maxMinutes == 1)
        model.setDuration(minutes: Int.max); #expect(model.maxMinutes == 720)
    }
}
