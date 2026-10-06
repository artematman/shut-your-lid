import LidModeFeature
import SwiftUI

/// «Работать с закрытой крышкой» — one switch in Shut Your Lid's style. It reads
/// «on» only when the helper has verified the system flag; approval,
/// refusal and failures keep it off with the reason and the one next step.
@MainActor struct LidModeSettingsView {
    @Bindable var model: LidModeModel

    var detail: String {
        switch model.phase {
        case .off:
            if let stop = model.lastStop, let note = Self.stopNote(stop) { return note + " " + loc("lid.detail.off %@", model.durationTitle) }
            return loc("lid.detail.off %@", model.durationTitle)
        case .needsApproval: return loc("lid.detail.needsApproval")
        case .working: return loc("lid.detail.working")
        case .on(let until):
            let time = until.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—"
            return loc("lid.detail.on %@", time)
        case .failed(let reason): return loc("lid.detail.failed %@", reason)
        case .unavailable(let reason): return reason
        }
    }

    static func stopNote(_ reason: LidModeStatus.StopReason) -> String? {
        switch reason {
        case .user: return nil
        case .appGone, .heartbeatLost: return loc("lid.stop.appGone")
        case .batteryFloor: return loc("lid.stop.battery")
        case .thermal: return loc("lid.stop.thermal")
        case .telemetryUnavailable: return loc("lid.stop.telemetry")
        case .timeLimit: return loc("lid.stop.time")
        case .recoveredAfterRestart: return loc("lid.stop.recovered")
        case .failed: return loc("lid.stop.failed")
        }
    }
}
