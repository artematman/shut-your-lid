import Foundation
import Darwin

/// Continuous monotonic time includes sleep and cannot be moved by wall-clock
/// adjustments. Values stay in memory; daemon restart always restores the flag.
public enum LidMonotonicTime {
    public static func now() -> TimeInterval {
        var scale = mach_timebase_info_data_t()
        mach_timebase_info(&scale)
        return Double(mach_continuous_time()) * Double(scale.numer) / Double(scale.denom) / 1_000_000_000
    }
}
