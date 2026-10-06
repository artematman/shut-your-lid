import Foundation

/// «Работать с закрытой крышкой» — the part that runs as root in
/// `LidPowerHelper` (and in tests with fakes).
///
/// Why this mechanism. On a MacBook on battery with no external display,
/// closing the lid forces clamshell sleep: `caffeinate` and IOKit
/// no-idle-sleep assertions do not survive it. The one switch that does is
/// the kernel's sleep-disabled flag, set by `pmset -a disablesleep 1`, which
/// needs root. (Same conclusion as the MIT-licensed cocaffeinate script,
/// checked on this Mac: `disablesleep` is undocumented in `man pmset`, and
/// `SleepDisabled` appears in `pmset -g` only while set.) Root comes from an
/// app-embedded LaunchDaemon registered with SMAppService, approved once by
/// the user in System Settings — no password ever passes through the app.
///
/// What protects the Mac:
/// - a lease: the flag stays set only while the app holds a live connection
///   and heartbeats; app quit, crash or SIGKILL end the lease → restore;
/// - a state file written BEFORE the flag is set: after a helper crash,
///   SIGKILL or reboot, the helper restores the previous value on launch;
/// - guards: on battery at/below the floor, macOS thermal state serious or
///   critical, or the time limit → restore (and ask the Mac to sleep if the
///   lid is closed). macOS's own thermal management is never touched.
public struct LidModeStatus: Codable, Equatable, Sendable {
    public var active: Bool
    /// What `pmset -g` reports right now (verified, not assumed).
    public var sleepDisabledNow: Bool
    public var enabledAt: Date?
    public var expiresAt: Date?
    public var batteryFloor: Int
    public var lastStopReason: StopReason?
    public var error: String?

    public init(active: Bool = false, sleepDisabledNow: Bool = false, enabledAt: Date? = nil, expiresAt: Date? = nil,
                batteryFloor: Int = LidModeLimits.defaultBatteryFloor, lastStopReason: StopReason? = nil, error: String? = nil) {
        self.active = active; self.sleepDisabledNow = sleepDisabledNow; self.enabledAt = enabledAt
        self.expiresAt = expiresAt; self.batteryFloor = batteryFloor; self.lastStopReason = lastStopReason; self.error = error
    }

    public enum StopReason: String, Codable, Sendable {
        case user, appGone, heartbeatLost, batteryFloor, telemetryUnavailable, thermal, timeLimit, recoveredAfterRestart, failed
    }
}

public enum LidModeLimits {
    public static let defaultBatteryFloor = 10
    public static let defaultMaxMinutes = 240
    public static let maxMinutesCap = 720
    public static let heartbeatTimeout: TimeInterval = 90
}

/// The machine's sleep-disabled flag.
public protocol LidPowerSettings: Sendable {
    func sleepDisabled() throws -> Bool
    func setSleepDisabled(_ value: Bool) throws
    /// Asks the Mac to sleep now (used after a guard fires with the lid closed).
    func sleepNow() throws
}

/// Battery and heat, as macOS reports them.
public struct LidPowerReading: Equatable, Sendable {
    public var onBattery: Bool?
    public var batteryPercent: Int?
    public var thermalSeriousOrWorse: Bool
    public var lidClosed: Bool
    public init(onBattery: Bool?, batteryPercent: Int?, thermalSeriousOrWorse: Bool, lidClosed: Bool) {
        self.onBattery = onBattery; self.batteryPercent = batteryPercent
        self.thermalSeriousOrWorse = thermalSeriousOrWorse; self.lidClosed = lidClosed
    }
}

extension LidPowerReading {
    /// A known AC source is safe without a charge reading. Unknown source or
    /// missing/invalid charge while on battery must never bypass the guard.
    public var hasSafeTelemetry: Bool {
        guard let onBattery else { return false }
        guard onBattery else { return true }
        guard let batteryPercent else { return false }
        return (0...100).contains(batteryPercent)
    }
}

public enum LidModeError: Error, Equatable, Sendable, CustomStringConvertible {
    case telemetryUnavailable
    case notApplied(String)
    case batteryTooLow(Int)
    case tooHot

    public var description: String {
        switch self {
        case .telemetryUnavailable: return "Не удалось определить питание или заряд аккумулятора. Режим остановлен до восстановления данных."
        case .notApplied(let message): return message
        case .batteryTooLow(let percent): return "Заряд аккумулятора \(percent)%. Подключите питание перед включением режима."
        case .tooHot: return "Mac слишком сильно нагрелся. Дождитесь охлаждения."
        }
    }
}

/// What is persisted before the flag is touched, so a restart can undo it.
struct LidModeRecord: Codable, Equatable {
    var previousSleepDisabled: Bool
    var enabledAt: Date
    var expiresAt: Date
    var batteryFloor: Int
}

public final class LidModeController: @unchecked Sendable {
    private let settings: LidPowerSettings
    private let stateURL: URL
    private let now: () -> Date
    private let elapsed: () -> TimeInterval
    private let lock = NSLock()
    private var record: LidModeRecord?
    private var lastHeartbeat: TimeInterval?
    private var deadline: TimeInterval?
    private var lastStop: LidModeStatus.StopReason?
    private var restorationError: String?
    private var sleepAfterRestore = false

    public init(settings: LidPowerSettings, stateURL: URL, now: @escaping () -> Date = Date.init,
                elapsed: @escaping () -> TimeInterval = LidMonotonicTime.now) {
        self.settings = settings; self.stateURL = stateURL; self.now = now; self.elapsed = elapsed
    }

    // MARK: Launch recovery

    /// On helper launch: a record means the flag was set by a previous run
    /// that did not finish (crash, SIGKILL, reboot) — no app holds a lease
    /// yet, so the previous value is restored.
    @discardableResult
    public func recoverOnLaunch() -> LidModeStatus {
        lock.lock(); defer { lock.unlock() }
        if FileManager.default.fileExists(atPath: stateURL.path) {
            guard readRecord() != nil else {
                restorationError = "Файл восстановления повреждён; включение заблокировано."
                return statusLocked()
            }
            restoreLocked(reason: .recoveredAfterRestart)
        }
        return statusLocked()
    }

    // MARK: Requests from the app

    public func enable(maxMinutes: Int, batteryFloor: Int, power: LidPowerReading) throws -> LidModeStatus {
        lock.lock(); defer { lock.unlock() }
        let floor = max(LidModeLimits.defaultBatteryFloor, min(batteryFloor, 90))
        if power.thermalSeriousOrWorse { throw LidModeError.tooHot }
        guard power.hasSafeTelemetry else { throw LidModeError.telemetryUnavailable }
        if let restorationError { throw LidModeError.notApplied(restorationError) }
        if power.onBattery == true, let percent = power.batteryPercent, percent <= floor { throw LidModeError.batteryTooLow(percent) }
        if record != nil && restorationError == nil { lastHeartbeat = elapsed(); return statusLocked() }
        if FileManager.default.fileExists(atPath: stateURL.path) {
            restoreLocked(reason: .recoveredAfterRestart)
            guard restorationError == nil else { throw LidModeError.notApplied(restorationError!) }
        }
        let previous = try settings.sleepDisabled()
        guard !previous else { throw LidModeError.notApplied("Режим сна уже изменён другим приложением. Сначала выключите его режим.") }
        restorationError = nil
        let start = now()
        let minutes = max(1, min(maxMinutes, LidModeLimits.maxMinutesCap))
        let newRecord = LidModeRecord(previousSleepDisabled: previous, enabledAt: start,
                                      expiresAt: start.addingTimeInterval(TimeInterval(minutes * 60)), batteryFloor: floor)
        // Written first: if anything dies after the flag is set, launch recovery undoes it.
        try writeRecord(newRecord)
        do {
            try settings.setSleepDisabled(true)
            guard try settings.sleepDisabled() else { throw LidModeError.notApplied("pmset reported sleep still enabled") }
        } catch {
            restoreLocked(reason: .failed)
            throw (error as? LidModeError) ?? LidModeError.notApplied(String(describing: error))
        }
        record = newRecord
        let startElapsed = elapsed()
        lastHeartbeat = startElapsed
        deadline = startElapsed + TimeInterval(minutes * 60)
        lastStop = nil
        return statusLocked()
    }

    public func disable(reason: LidModeStatus.StopReason) -> LidModeStatus {
        lock.lock(); defer { lock.unlock() }
        restoreLocked(reason: reason)
        return statusLocked()
    }

    public func heartbeat() -> LidModeStatus {
        lock.lock(); defer { lock.unlock() }
        if record != nil && restorationError == nil { lastHeartbeat = elapsed() }
        return statusLocked()
    }

    public func status() -> LidModeStatus {
        lock.lock(); defer { lock.unlock() }
        return statusLocked()
    }

    // MARK: Guards (called every few seconds while active)

    /// Returns the reason the mode was stopped, if a guard fired.
    @discardableResult
    public func tick(power: LidPowerReading) -> LidModeStatus.StopReason? {
        lock.lock(); defer { lock.unlock() }
        if restorationError != nil { restoreLocked(reason: .failed); return .failed }
        guard let current = record else { return nil }
        let reason: LidModeStatus.StopReason?
        if power.thermalSeriousOrWorse { reason = .thermal }
        else if !power.hasSafeTelemetry { reason = .telemetryUnavailable }
        else if power.onBattery == true, let percent = power.batteryPercent, percent <= current.batteryFloor { reason = .batteryFloor }
        else if let deadline, elapsed() >= deadline { reason = .timeLimit }
        else if let beat = lastHeartbeat, elapsed() - beat > LidModeLimits.heartbeatTimeout { reason = .heartbeatLost }
        else { reason = nil }
        guard let reason else { return nil }
        // Keep this intent through a failed restore so the retry also sleeps.
        sleepAfterRestore = power.lidClosed || reason == .batteryFloor
        restoreLocked(reason: reason)
        return reason
    }

    // MARK: Private

    private func restoreLocked(reason: LidModeStatus.StopReason) {
        if let saved = record ?? readRecord() {
            do {
                try settings.setSleepDisabled(saved.previousSleepDisabled)
                guard try settings.sleepDisabled() == saved.previousSleepDisabled else {
                    throw LidModeError.notApplied("Не удалось восстановить обычный сон.")
                }
                try FileManager.default.removeItem(at: stateURL)
                restorationError = nil
            } catch {
                record = saved
                restorationError = "Ошибка восстановления: \(error)"
                lastStop = .failed
                return
            }
        } else if FileManager.default.fileExists(atPath: stateURL.path) {
            restorationError = "Файл восстановления повреждён; включение заблокировано."
            lastStop = .failed
            return
        }
        restorationError = nil
        record = nil
        lastHeartbeat = nil
        deadline = nil
        lastStop = reason
        if sleepAfterRestore {
            do {
                try settings.sleepNow()
                sleepAfterRestore = false
            } catch {
                restorationError = "Обычный сон восстановлен, но Mac не подтвердил команду сна: \(error)"
                lastStop = .failed
            }
        }
    }

    private func statusLocked() -> LidModeStatus {
        let flag: Bool
        do { flag = try settings.sleepDisabled() }
        catch { return LidModeStatus(error: "Не удалось прочитать состояние сна: \(error)") }
        return LidModeStatus(active: record != nil && restorationError == nil, sleepDisabledNow: flag,
                      enabledAt: record?.enabledAt, expiresAt: deadline.map { now().addingTimeInterval(max(0, $0 - elapsed())) },
                      batteryFloor: record?.batteryFloor ?? LidModeLimits.defaultBatteryFloor, lastStopReason: lastStop, error: restorationError)
    }

    private func readRecord() -> LidModeRecord? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(LidModeRecord.self, from: data)
    }

    private func writeRecord(_ value: LidModeRecord) throws {
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: stateURL, options: .atomic)
    }
}

/// The real flag, through the system's own `pmset` (run as root by the helper).
public struct PmsetPowerSettings: LidPowerSettings {
    public init() {}

    public func sleepDisabled() throws -> Bool {
        let output = try Self.run(["-g"])
        return Self.parseSleepDisabled(output)
    }

    public func setSleepDisabled(_ value: Bool) throws {
        if value, LegacyModeConflict.isPresent() {
            throw LidModeError.notApplied("Выключите режим крышки и завершите Island Pro. Отключите его помощник в настройках macOS перед переходом.")
        }
        _ = try Self.run(["-a", "disablesleep", value ? "1" : "0"])
    }

    public func sleepNow() throws { _ = try Self.run(["sleepnow"]) }

    /// `pmset -g` lists `SleepDisabled  1` only while the flag is set.
    public static func parseSleepDisabled(_ output: String) -> Bool {
        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.count >= 2, parts[0] == "SleepDisabled" { return parts[1] == "1" }
        }
        return false
    }

    static func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else { throw LidModeError.notApplied(output.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return output
    }
}
