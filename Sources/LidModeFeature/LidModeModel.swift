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
        case batteryLow(Int)
        case overheated
        case failed(String)
        case unavailable(String)
    }

    public enum ServiceState: Equatable, Sendable { case notRegistered, enabled, requiresApproval, notFound }
    public enum Request: Sendable { case status, enable(maxMinutes: Int, batteryFloor: Int), updateDuration(maxMinutes: Int), disable, heartbeat }

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
    public private(set) var isQuitting = false
    /// Why the mode turned itself off last time (battery, heat, limit, app gone).
    public private(set) var lastStop: LidModeStatus.StopReason?
    public static let durationPresets = [30, 60, 120, 240, 360, 480, 720]
    public private(set) var maxMinutes: Int
    public var usesCustomDuration = false
    public let batteryFloor = LidModeLimits.defaultBatteryFloor
    @ObservationIgnored private let preferences: UserDefaults?

    private let system: System
    @ObservationIgnored private var heartbeatTask: Task<Void, Never>?
    /// Lease heartbeat period (the helper's timeout is 90 s); shortened only in tests.
    @ObservationIgnored var heartbeatInterval: Duration = .seconds(30)
    @ObservationIgnored private var durationTask: Task<Void, Never>?
    @ObservationIgnored private var durationRevision = 0
    @ObservationIgnored private var operationVersion = 0
    @ObservationIgnored private var updatingDuration = false
    @ObservationIgnored private var statusRevision = 0

    public init(system: System, preferences: UserDefaults? = nil) {
        self.system = system
        self.preferences = preferences
        let saved = preferences?.object(forKey: "durationMinutes") as? Int
        self.maxMinutes = saved.map { min(max(1, $0), LidModeLimits.maxMinutesCap) } ?? LidModeLimits.defaultMaxMinutes
        self.usesCustomDuration = !Self.durationPresets.contains(self.maxMinutes)
    }

    public var canChangeDuration: Bool {
        guard !isQuitting else { return false }
        switch phase {
        case .working, .needsApproval: return false
        default: return true
        }
    }

    /// Update the preference immediately; coalesce active lease edits before sending them.
    public func setDuration(minutes: Int) {
        guard canChangeDuration else { return }
        maxMinutes = min(max(1, minutes), LidModeLimits.maxMinutesCap)
        preferences?.set(maxMinutes, forKey: "durationMinutes")
        durationRevision += 1
        guard isOn, durationTask == nil else { return }
        let version = operationVersion
        durationTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.operationVersion == version { self.durationTask = nil; self.updatingDuration = false } }
            while !Task.isCancelled && self.operationVersion == version && self.isOn {
                let revision = self.durationRevision
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                guard self.operationVersion == version, self.isOn else { return }
                if revision != self.durationRevision { continue }
                self.updatingDuration = true
                self.statusRevision += 1
                let status = await self.system.call(.updateDuration(maxMinutes: self.maxMinutes))
                guard !Task.isCancelled, self.operationVersion == version, self.isOn else { return }
                if let status, status.error == nil {
                    self.updatingDuration = false
                    self.statusRevision += 1
                    self.apply(status)
                } else {
                    // Never display an off/error switch while knowingly leaving
                    // the previous active lease running after a failed edit.
                    let reason = status?.error ?? loc("lid.helperGone")
                    self.phase = .working
                    self.stopHeartbeat()
                    _ = await self.system.call(.disable)
                    guard !Task.isCancelled, self.operationVersion == version else { return }
                    self.updatingDuration = false
                    self.statusRevision += 1
                    self.phase = .failed(reason)
                    return
                }
                if revision == self.durationRevision { return }
            }
        }
    }

    private func beginOperation() {
        operationVersion += 1
        durationTask?.cancel()
        durationTask = nil
        updatingDuration = false
    }

    public var durationTitle: String { Self.durationTitle(minutes: maxMinutes) }

    public static func durationTitle(minutes: Int) -> String {
        lidDuration(minutes: minutes)
    }

    public var isOn: Bool { if case .on = phase { return true }; return false }

    /// Re-reads the real state (on appear and on return from System Settings).
    public func refresh() async {
        guard !isQuitting, phase != .working, !updatingDuration else { return }
        let version = operationVersion
        let statusVersion = statusRevision
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
        let status = await system.call(.status)
        guard operationVersion == version, statusRevision == statusVersion, phase != .working, !updatingDuration else { return }
        guard let status else { phase = .failed(loc("lid.helperGone")); stopHeartbeat(); return }
        apply(status)
    }

    public func setEnabled(_ enabled: Bool) async {
        guard !isQuitting else { return }
        if enabled { await turnOn() } else { await turnOff() }
    }

    /// Preserve the exit status while restoring ordinary sleep before termination.
    public func prepareToQuit() async {
        guard !isQuitting else { return }
        isQuitting = true
        await turnOff()
    }

    public func openApproval() { system.openLoginItems() }

    private func turnOn() async {
        beginOperation()
        let version = operationVersion
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
        let result = await system.call(.enable(maxMinutes: maxMinutes, batteryFloor: batteryFloor))
        guard operationVersion == version else { return }
        guard let status = result else {
            phase = .failed(loc("lid.helperGone")); return
        }
        if let error = status.error { phase = .failed(error); return }
        apply(status)
    }

    private func turnOff() async {
        beginOperation()
        let version = operationVersion
        stopHeartbeat()
        guard system.serviceState() == .enabled else { phase = .off; return }
        phase = .working
        let status = await system.call(.disable)
        guard operationVersion == version else { return }
        if let status { apply(status) } else { phase = .failed(loc("lid.helperGone")) }
    }

    private func apply(_ status: LidModeStatus) {
        if let error = status.error { phase = .failed(error); stopHeartbeat(); return }
        if !status.active, status.blockedByHeat == true {
            phase = .overheated; stopHeartbeat(); return
        }
        if !status.active, let percent = status.blockedBatteryPercent, (0...100).contains(percent) {
            phase = .batteryLow(percent); stopHeartbeat(); return
        }
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
                try? await Task.sleep(for: self?.heartbeatInterval ?? .seconds(30))
                guard let self, !Task.isCancelled else { return }
                let version = self.operationVersion
                let statusVersion = self.statusRevision
                let status = await self.system.call(.heartbeat)
                guard !Task.isCancelled, self.operationVersion == version else { return }
                if self.updatingDuration || self.statusRevision != statusVersion { continue }
                // No reply is not «off»: the lease may still be active on the helper.
                if let status { self.apply(status) } else { self.phase = .failed(loc("lid.connectionLost")); self.stopHeartbeat() }
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
                    ? loc("lid.conflict")
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

    /// For tests: whether a connection is currently held (dropped on invalidation).
    var hasConnection: Bool { connection != nil }

    private func proxy(_ onError: @escaping @Sendable () -> Void) -> LidPowerControl? {
        if connection == nil {
            let new = NSXPCConnection(machServiceName: machService, options: .privileged)
            new.setCodeSigningRequirement(LidPowerHelperIdentity.clientRequirement(appBundleID: machService, team: "8XZ7Z4UR6C"))
            new.remoteObjectInterface = NSXPCInterface(with: LidPowerControl.self)
            // NSXPC calls this on its own queue: the handler is built nonisolated
            // and only hops to the main actor to drop the dead connection.
            new.invalidationHandler = Self.xpcCallback { [weak self] in Task { @MainActor in self?.connection = nil } }
            new.resume()
            connection = new
        }
        return connection?.remoteObjectProxyWithErrorHandler(Self.xpcErrorHandler(onError)) as? LidPowerControl
    }

    // XPC callbacks run on NSXPC's private queue. A closure written inside this
    // @MainActor class would inherit main-actor isolation and trap there
    // (`_dispatch_assert_queue_fail`), so they are created in nonisolated code
    // and only call @Sendable work.
    nonisolated private static func xpcCallback(_ work: @escaping @Sendable () -> Void) -> () -> Void {
        { work() }
    }

    nonisolated private static func xpcErrorHandler(_ work: @escaping @Sendable () -> Void) -> (any Error) -> Void {
        { _ in work() }
    }

    func call(_ request: LidModeModel.Request) async -> LidModeStatus? {
        await withCheckedContinuation { continuation in
            let once = Once(continuation)
            guard let proxy = proxy({ once.finish(nil) }) else { once.finish(nil); return }
            let reply: @Sendable (Data) -> Void = { once.finish(LidModeWire.decode($0)) }
            switch request {
            case .status: proxy.status(reply: reply)
            case .enable(let minutes, let floor): proxy.enable(maxMinutes: minutes, batteryFloor: floor, reply: reply)
            case .updateDuration(let minutes): proxy.updateDuration(maxMinutes: minutes, reply: reply)
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
