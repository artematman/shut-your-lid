import Foundation
import IOKit.ps
import Testing
@testable import LidModeFeature
@testable import ShutYourLid

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
        // A running lease accepts a new duration; the model debounces the helper update.
        restored.setDuration(minutes: 720)
        #expect(restored.maxMinutes == 720 && restored.canChangeDuration)
        await restored.setEnabled(false)
    }
    @Test("status and protection texts keep the literal battery percentage in both languages")
    func percentText() {
        for language in [LidLanguage.ru, .en] {
            #expect(lidString("status.on.until %@", language: language, ["18:30"]).hasSuffix("18:30"))
            #expect(lidString("settings.protection.battery", language: language).contains("10%"))
            #expect(lidString("lid.stop.battery", language: language).contains("10%"))
        }
    }
    @Test("every Russian string has an English counterpart with the same placeholders")
    func languageParity() {
        #expect(Set(lidStringsRU.keys) == Set(lidStringsEN.keys))
        for (key, ru) in lidStringsRU {
            #expect(ru.components(separatedBy: "%@").count == lidStringsEN[key]?.components(separatedBy: "%@").count, "\(key)")
        }
    }
    @Test("status says «Включено до HH:mm» and adds «завтра» past midnight, without repeating the mode name")
    @MainActor func onUntilText() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 21, minute: 0))!
        let sameDay = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 23, minute: 5))!
        let nextDay = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 3, minute: 48))!
        #expect(LidModeStatusText.onUntil(sameDay, now: now, calendar: calendar) == loc("status.on.until %@", "23:05"))
        #expect(LidModeStatusText.onUntil(nextDay, now: now, calendar: calendar) == loc("status.on.tomorrow %@", "03:48"))
        #expect(LidModeStatusText.onUntil(nil, now: now, calendar: calendar) == loc("status.on"))
        #expect(lidString("status.on.until %@", language: .ru, ["03:48"]) == "Включено до 03:48")
        #expect(lidString("status.on.tomorrow %@", language: .ru, ["03:48"]) == "Включено до 03:48 завтра")
        #expect(lidString("status.on.tomorrow %@", language: .en, ["03:48"]) == "On until 03:48 tomorrow")
        for language in [LidLanguage.ru, .en] {
            #expect(!lidString("status.on.until %@", language: language, ["03:48"]).contains(lidString("lid.title", language: language)))
        }
    }
    @Test("interface carries no explanation that the app must stay open, and no old brand")
    func noStayOpenOrOldBrand() {
        for table in [lidStringsRU, lidStringsEN] {
            for text in table.values {
                #expect(!text.contains("открыт") || text.contains("Открыть"), "\(text)")
                #expect(!text.localizedCaseInsensitiveContains("app is open") && !text.contains("Island"), "\(text)")
            }
        }
    }
    @Test("durations use full words with correct Russian plural forms and full English units")
    func fullWordDurations() {
        let ru: [Int: String] = [1: "1 минута", 2: "2 минуты", 5: "5 минут", 11: "11 минут", 21: "21 минута", 22: "22 минуты", 30: "30 минут",
                                 45: "45 минут", 60: "1 час", 90: "1 час 30 минут", 120: "2 часа", 240: "4 часа", 300: "5 часов",
                                 360: "6 часов", 480: "8 часов", 661: "11 часов 1 минута", 720: "12 часов", 1260: "21 час", 1320: "22 часа"]
        for (minutes, text) in ru { #expect(lidDuration(minutes: minutes, language: .ru) == text) }
        let en: [Int: String] = [1: "1 minute", 30: "30 minutes", 60: "1 hour", 90: "1 hour 30 minutes", 121: "2 hours 1 minute", 360: "6 hours", 720: "12 hours"]
        for (minutes, text) in en { #expect(lidDuration(minutes: minutes, language: .en) == text) }
    }
    @Test("settings texts: no ellipsis on Custom or the login-items link, no 'turn off to change' requirement")
    func settingsTexts() {
        for language in [LidLanguage.ru, .en] {
            #expect(!lidString("settings.duration.custom", language: language).contains("…"))
            #expect(!lidString("settings.loginItems", language: language).contains("…"))
        }
        #expect(lidStringsRU["settings.duration.locked"] == nil && lidStringsEN["settings.duration.locked"] == nil)
        #expect(!lidStringsRU.values.contains { $0.contains("чтобы изменить длительность") })
    }
    @Test("model duration titles are the full-word durations")
    func durationTitles() {
        for minutes in [1, 45, 60, 90, 240, 360, 720] {
            #expect(LidModeModel.durationTitle(minutes: minutes) == lidDuration(minutes: minutes))
        }
        if LidLanguage.current == .ru {
            #expect(LidModeModel.durationTitle(minutes: 90) == "1 час 30 минут")
            #expect(LidModeModel.durationTitle(minutes: 360) == "6 часов")
        }
    }
    @Test("invalid duration is bounded before persisting")
    func bounds() {
        let model = LidModeModel(system: .init(serviceState: { .notRegistered }, register: {}, openLoginItems: {}, call: { _ in nil }))
        model.setDuration(minutes: -100); #expect(model.maxMinutes == 1)
        model.setDuration(minutes: Int.max); #expect(model.maxMinutes == 720)
    }
}
