import Foundation
import IOKit.ps

public enum LidPowerTelemetry {
    /// Only the internal battery describes a MacBook. Ignore UPS/peripherals,
    /// reject absent/ambiguous/incomplete source data instead of assuming AC.
    public static func decode(_ sources: [[String: Any]]?) -> (onBattery: Bool?, percent: Int?) {
        guard let sources else { return (nil, nil) }
        let batteries = sources.filter { $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType }
        guard batteries.count == 1, let battery = batteries.first,
              let state = battery[kIOPSPowerSourceStateKey] as? String else { return (nil, nil) }
        let onBattery: Bool
        switch state {
        case kIOPSBatteryPowerValue: onBattery = true
        case kIOPSACPowerValue: onBattery = false
        default: return (nil, nil)
        }
        guard let current = battery[kIOPSCurrentCapacityKey] as? Int,
              let maximum = battery[kIOPSMaxCapacityKey] as? Int,
              maximum > 0, current >= 0, current <= maximum else { return (onBattery, nil) }
        // Avoid integer multiplication overflow even if the system returns bad data.
        return (onBattery, Int(Double(current) / Double(maximum) * 100))
    }
}
