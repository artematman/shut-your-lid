import AppKit
import LidModeFeature
import SwiftUI

/// Short state texts. The switch reads «on» only when the helper has verified
/// the system flag; approval, refusal and failures keep it off.
@MainActor enum LidModeStatusText {
    /// «Включено до HH:mm», plus «завтра» when the end is past midnight.
    static func onUntil(_ until: Date?, now: Date, calendar: Calendar = .current) -> String {
        guard let until else { return loc("status.on") }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: until)
        if calendar.isDate(until, inSameDayAs: now) { return loc("status.on.until %@", time) }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(until, inSameDayAs: tomorrow) {
            return loc("status.on.tomorrow %@", time)
        }
        formatter.dateFormat = "dd.MM HH:mm"
        return loc("status.on.until %@", formatter.string(from: until))
    }

    static func stopNote(_ reason: LidModeStatus.StopReason) -> String? {
        switch reason {
        case .user, .appGone, .heartbeatLost, .recoveredAfterRestart: return nil
        case .batteryFloor: return loc("lid.stop.battery")
        case .thermal: return loc("lid.stop.thermal")
        case .telemetryUnavailable: return loc("lid.stop.telemetry")
        case .timeLimit: return loc("lid.stop.time")
        case .failed: return loc("lid.stop.failed")
        }
    }
}

/// Settings: duration, the 10% protection in brief, secondary actions. It takes
/// the main page's width and ends with the same pair of buttons (Back, Quit).
struct LidModeSettingsPage: View {
    @Bindable var model: LidModeModel
    let route: LidPanelRoute

    var body: some View {
        LidFitStack(spacing: 12) {
            Text(loc("settings.title"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 8) {
                Text(loc("settings.duration"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                LidDurationPicker(model: model)
            }

            VStack(alignment: .leading, spacing: 8) {
                LidProtectionRow(symbol: "battery.25", color: .yellow, text: loc("settings.protection.battery"))
                LidProtectionRow(symbol: "thermometer.medium", color: .red, text: loc("settings.protection.thermal"))
            }
            .padding(.vertical, 4)

            Button(loc("settings.loginItems")) { model.openApproval() }
                .buttonStyle(.link)
                .font(.callout)
                .help(loc("lid.openApproval.help"))

            HStack(spacing: 8) {
                LidFooterButton(title: loc("settings.back"), symbol: "chevron.left", help: loc("settings.back")) {
                    route.show(.main)
                }
                LidFooterButton(title: loc("menu.quit.short"), symbol: "power", help: loc("menu.quit")) {
                    NSApp.terminate(nil)
                }
                .accessibilityLabel(loc("menu.quit"))
            }
        }
    }

}

struct LidProtectionRow: View {
    let symbol: String
    let color: Color
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Duration: a full-width native pop-up of presets plus «Своё значение», which
/// reveals a native slider. Every change goes straight to `model.setDuration`.
struct LidDurationPicker: View {
    @Bindable var model: LidModeModel

    static var presets: [Int] { LidModeModel.durationPresets }
    static let customTag = 0

    // Reserve the widest localized value so the track never shifts under the pointer.
    static let durationLabelWidth: CGFloat = {
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.preferredFont(forTextStyle: .callout).pointSize, weight: .medium)
        return ceil((1...LidModeLimits.maxMinutesCap).map {
            (lidDuration(minutes: $0) as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 0) + 2
    }()

    @MainActor static func showsCustom(_ model: LidModeModel) -> Bool {
        model.usesCustomDuration || !presets.contains(model.maxMinutes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LidPopUpButton(
                items: Self.presets.map { ($0, lidDuration(minutes: $0)) } + [(Self.customTag, loc("settings.duration.custom"))],
                separatorBeforeLast: true,
                selection: Self.showsCustom(model) ? Self.customTag : model.maxMinutes,
                label: loc("settings.duration")
            ) { tag in
                model.usesCustomDuration = tag == Self.customTag
                if tag != Self.customTag { model.setDuration(minutes: tag) }
            }
            if Self.showsCustom(model) {
                HStack(spacing: 10) {
                    LidSlider(
                        value: model.maxMinutes,
                        range: 1...LidModeLimits.maxMinutesCap,
                        label: loc("settings.duration"),
                        valueDescription: lidDuration(minutes: model.maxMinutes)
                    ) { model.setDuration(minutes: $0) }
                    Text(lidDuration(minutes: model.maxMinutes))
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: Self.durationLabelWidth, alignment: .trailing)
                        .accessibilityHidden(true)
                }
            }
        }
        .disabled(!model.canChangeDuration)
    }
}

/// NSPopUpButton that fills the width SwiftUI proposes (the SwiftUI menu
/// picker keeps its intrinsic width and truncates longer titles).
struct LidPopUpButton: NSViewRepresentable {
    let items: [(tag: Int, title: String)]
    var separatorBeforeLast = false
    let selection: Int
    let label: String
    let onSelect: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.changed(_:))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.onSelect = onSelect
        let current = button.itemArray.filter { !$0.isSeparatorItem }.map { "\($0.tag)|\($0.title)" }
        if current != items.map({ "\($0.tag)|\($0.title)" }) {
            button.removeAllItems()
            for (index, item) in items.enumerated() {
                if separatorBeforeLast, index == items.count - 1 {
                    // Separators default to tag 0; keep them out of tag lookups.
                    let separator = NSMenuItem.separator()
                    separator.tag = Int.min
                    button.menu?.addItem(separator)
                }
                let menuItem = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
                menuItem.tag = item.tag
                button.menu?.addItem(menuItem)
            }
        }
        if button.selectedTag() != selection { button.selectItem(withTag: selection) }
        button.isEnabled = context.environment.isEnabled
        button.setAccessibilityLabel(label)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        let intrinsic = nsView.intrinsicContentSize
        return CGSize(width: proposal.width.map { $0.isFinite ? $0 : intrinsic.width } ?? intrinsic.width, height: intrinsic.height)
    }

    @MainActor final class Coordinator: NSObject {
        var onSelect: (Int) -> Void = { _ in }
        @objc func changed(_ sender: NSPopUpButton) { onSelect(sender.selectedTag()) }
    }
}

/// Plain NSSlider without tick marks; continuous, whole minutes.
struct LidSlider: NSViewRepresentable {
    let value: Int
    let range: ClosedRange<Int>
    let label: String
    let valueDescription: String
    let onChange: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: Double(value), minValue: Double(range.lowerBound), maxValue: Double(range.upperBound),
                              target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        slider.numberOfTickMarks = 0
        slider.allowsTickMarkValuesOnly = false
        slider.isContinuous = true
        slider.altIncrementValue = 1
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        slider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.current = value
        if Int(slider.doubleValue.rounded()) != value { slider.doubleValue = Double(value) }
        slider.isEnabled = context.environment.isEnabled
        slider.setAccessibilityLabel(label)
        slider.setAccessibilityValueDescription(valueDescription)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSlider, context: Context) -> CGSize? {
        let height = nsView.intrinsicContentSize.height
        return CGSize(width: proposal.width.map { $0.isFinite ? $0 : 160 } ?? 160, height: height)
    }

    @MainActor final class Coordinator: NSObject {
        var onChange: (Int) -> Void = { _ in }
        var current: Int?
        /// Whole minutes only; the value updates live while dragging.
        @objc func changed(_ sender: NSSlider) {
            let minutes = Int(sender.doubleValue.rounded())
            guard minutes != current else { return }
            current = minutes
            onChange(minutes)
        }
    }
}
