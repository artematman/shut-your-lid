import AppKit
import Foundation
import Observation
import ServiceManagement

/// The switch «Работать с закрытой крышкой» as the app sees it. It shows
/// «on» only when the helper confirms the flag is really set (`pmset`
/// verified); anything else — approval pending, refused, failed, helper
/// gone — leaves it off with the reason in plain words.
@MainActor @Observable public final class LidModeModel {
    public enum Phase: Equatable, Sendable {
        case off
        /// Registered, waiting for the user's approval in System Settings.
        case needsApproval
        case working
        case on(until: Date?)
        case failed(String)
        case unavailable(String)
    }

    public enum ServiceState: Equatable, Sendable { case notRegistered, enabled, requiresApproval, notFound }
    public enum Request: Sendable { case status, enable(maxMinutes: Int, batteryFloor: Int), disable, heartbeat }

    /// Seams for tests; production values use SMAppService and XPC.
    public struct System {
        public var preflight: @MainActor () -> String?
        public var serviceState: @MainActor () -> ServiceState
        public var register: @MainActor () throws -> Void
        public var openLoginItems: @MainActor () -> Void
        public var call: @MainActor (Request) async -> LidModeStatus?
        public init(preflight: @escaping @MainActor () -> String? = { nil }, serviceState: @escaping @MainActor () -> ServiceState, register: @escaping @MainActor () throws -> Void,
                    openLoginItems: @escaping @MainActor () -> Void, call: @escaping @MainActor (Request) async -> LidModeStatus?) {
            self.preflight = preflight
            self.serviceState = serviceState; self.register = register; self.openLoginItems = openLoginItems; self.call = call
        }
    }

    public private(set) var phase: Phase = .off
    /// Why the mode turned itself off last time (battery, heat, limit, app gone).
    public private(set) var lastStop: LidModeStatus.StopReason?
    public static let durationPresets = [30, 60, 120, 240, 480, 720]
    public private(set) var maxMinutes: Int
    public var usesCustomDuration = false
    public let batteryFloor = LidModeLimits.defaultBatteryFloor
    @ObservationIgnored private let preferences: UserDefaults?

    private let system: System
    @ObservationIgnored private var heartbeatTask: Task<Void, Never>?

    public init(system: System, preferences: UserDefaults? = nil) {
        self.system = system
        self.preferences = preferences
        let saved = preferences?.object(forKey: "durationMinutes") as? Int
        self.maxMinutes = saved.map { min(max(1, $0), LidModeLimits.maxMinutesCap) } ?? LidModeLimits.defaultMaxMinutes
        self.usesCustomDuration = !Self.durationPresets.contains(self.maxMinutes)
    }

    public var canChangeDuration: Bool {
        switch phase {
        case .on, .working, .needsApproval: return false
        default: return true
        }
    }

    /// A running lease is immutable; the chosen duration applies to the next start.
    public func setDuration(minutes: Int) {
        guard canChangeDuration else { return }
        maxMinutes = min(max(1, minutes), LidModeLimits.maxMinutesCap)
        preferences?.set(maxMinutes, forKey: "durationMinutes")
    }

    public var durationTitle: String { Self.durationTitle(minutes: maxMinutes) }

    public static func durationTitle(minutes: Int) -> String {
        if minutes % 60 == 0 { return "\(minutes / 60) ч" }
        return "\(minutes) мин"
    }

    public var isOn: Bool { if case .on = phase { return true }; return false }

    /// Re-reads the real state (on appear and on return from System Settings).
    public func refresh() async {
        switch system.serviceState() {
        case .notFound: phase = .unavailable(loc("lid.unavailable")); stopHeartbeat(); return
        case .requiresApproval:
            stopHeartbeat()
            if phase == .needsApproval || phase == .working { phase = .needsApproval } else { phase = .off }
            return
        case .notRegistered: phase = .off; stopHeartbeat(); return
        case .enabled: break
        }
        if phase == .needsApproval {
            // Approved meanwhile: finish what the user asked for.
            await turnOn()
            return
        }
        guard let status = await system.call(.status) else { phase = .failed(loc("lid.helperGone")); stopHeartbeat(); return }
        apply(status)
    }

    public func setEnabled(_ enabled: Bool) async {
        if enabled { await turnOn() } else { await turnOff() }
    }

    public func openApproval() { system.openLoginItems() }

    private func turnOn() async {
        if let reason = system.preflight() { phase = .failed(reason); stopHeartbeat(); return }
        phase = .working
        switch system.serviceState() {
        case .notFound: phase = .unavailable(loc("lid.unavailable")); stopHeartbeat(); return
        case .notRegistered:
            do { try system.register() } catch {
                // SMAppService reports «needs approval» as an error on first register.
                if system.serviceState() != .requiresApproval {
                    phase = .failed(String(describing: error)); return
                }
            }
            if system.serviceState() == .requiresApproval { phase = .needsApproval; system.openLoginItems(); return }
        case .requiresApproval:
            phase = .needsApproval; system.openLoginItems(); return
        case .enabled: break
        }
        guard let status = await system.call(.enable(maxMinutes: maxMinutes, batteryFloor: batteryFloor)) else {
            phase = .failed(loc("lid.helperGone")); return
        }
        if let error = status.error { phase = .failed(error); return }
        apply(status)
    }

    private func turnOff() async {
        stopHeartbeat()
        guard system.serviceState() == .enabled else { phase = .off; return }
        phase = .working
        let status = await system.call(.disable)
        if let status { apply(status) } else { phase = .failed(loc("lid.helperGone")) }
    }

    private func apply(_ status: LidModeStatus) {
        if let error = status.error { phase = .failed(error); stopHeartbeat(); return }
        if status.active, status.sleepDisabledNow {
            phase = .on(until: status.expiresAt)
            startHeartbeat()
        } else {
            phase = .off
            lastStop = status.lastStopReason
            stopHeartbeat()
        }
    }

    private func startHeartbeat() {
        guard heartbeatTask == nil else { return }
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, !Task.isCancelled else { return }
                if let status = await self.system.call(.heartbeat) { self.apply(status) } else { self.phase = .off; self.stopHeartbeat() }
            }
        }
    }

    private func stopHeartbeat() { heartbeatTask?.cancel(); heartbeatTask = nil }
}

// MARK: - Production system

public extension LidModeModel.System {
    /// SMAppService for the daemon embedded in this app, XPC to its Mach service.
    @MainActor static func live(appBundleID: String = Bundle.main.bundleIdentifier ?? "com.artemkharitonov.shutyourlid") -> Self {
        let service = SMAppService.daemon(plistName: LidPowerHelperIdentity.plistName(forApp: appBundleID))
        let client = LidPowerClient(machService: LidPowerHelperIdentity.label(forApp: appBundleID))
        return Self(
            preflight: {
                LegacyModeConflict.isPresent()
                    ? "Сначала выключите режим крышки в Island Pro, завершите Island Pro и отключите его фоновый помощник в настройках macOS."
                    : nil
            },
            serviceState: {
                switch service.status {
                case .enabled: return .enabled
                case .requiresApproval: return .requiresApproval
                case .notRegistered: return .notRegistered
                // A not-yet-registered embedded service can be reported as
                // notFound. Only call it missing after checking the artifact;
                // registration still reports any actual system error.
                case .notFound:
                    return Self.hasEmbeddedHelper(bundleURL: Bundle.main.bundleURL, appBundleID: appBundleID)
                        ? .notRegistered : .notFound
                @unknown default: return .notFound
                }
            },
            register: { try service.register() },
            openLoginItems: { SMAppService.openSystemSettingsLoginItems() },
            call: { await client.call($0) }
        )
    }

    static func hasEmbeddedHelper(bundleURL: URL, appBundleID: String) -> Bool {
        let contents = bundleURL.appendingPathComponent("Contents")
        let plist = contents.appendingPathComponent("Library/LaunchDaemons")
            .appendingPathComponent(LidPowerHelperIdentity.plistName(forApp: appBundleID))
        guard let data = try? Data(contentsOf: plist),
              let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              info["Label"] as? String == LidPowerHelperIdentity.label(forApp: appBundleID),
              info["BundleProgram"] as? String == "Contents/MacOS/LidPowerHelper" else { return false }
        return FileManager.default.isExecutableFile(atPath: contents.appendingPathComponent("MacOS/LidPowerHelper").path)
    }
}

/// XPC client to the privileged helper (a global Mach service).
@MainActor final class LidPowerClient {
    private let machService: String
    private var connection: NSXPCConnection?

    init(machService: String) { self.machService = machService }

    private func proxy(_ onError: @escaping @Sendable () -> Void) -> LidPowerControl? {
        if connection == nil {
            let new = NSXPCConnection(machServiceName: machService, options: .privileged)
            new.setCodeSigningRequirement(LidPowerHelperIdentity.clientRequirement(appBundleID: machService, team: "8XZ7Z4UR6C"))
            new.remoteObjectInterface = NSXPCInterface(with: LidPowerControl.self)
            new.invalidationHandler = { [weak self] in Task { @MainActor in self?.connection = nil } }
            new.resume()
            connection = new
        }
        return connection?.remoteObjectProxyWithErrorHandler { _ in onError() } as? LidPowerControl
    }

    func call(_ request: LidModeModel.Request) async -> LidModeStatus? {
        await withCheckedContinuation { continuation in
            let once = Once(continuation)
            guard let proxy = proxy({ once.finish(nil) }) else { once.finish(nil); return }
            let reply: @Sendable (Data) -> Void = { once.finish(LidModeWire.decode($0)) }
            switch request {
            case .status: proxy.status(reply: reply)
            case .enable(let minutes, let floor): proxy.enable(maxMinutes: minutes, batteryFloor: floor, reply: reply)
            case .disable: proxy.disable(reply: reply)
            case .heartbeat: proxy.heartbeat(reply: reply)
            }
            Task { try? await Task.sleep(for: .seconds(15)); once.finish(nil) }
        }
    }
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<LidModeStatus?, Never>?
    init(_ continuation: CheckedContinuation<LidModeStatus?, Never>) { self.continuation = continuation }
    func finish(_ value: LidModeStatus?) {
        lock.lock(); let pending = continuation; continuation = nil; lock.unlock()
        pending?.resume(returning: value)
    }
}
