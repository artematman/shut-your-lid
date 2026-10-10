import AppKit
import LidModeFeature
import SwiftUI

/// Motion shared by SwiftUI and the AppKit panel resize: a strong ease-out,
/// short enough for a utility. With Reduce Motion only opacity changes remain.
enum LidMotion {
    static let duration = 0.2
    static let controlPoints: (Float, Float, Float, Float) = (0.23, 1, 0.32, 1)
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static var curve: Animation {
        let p = controlPoints
        return .timingCurve(Double(p.0), Double(p.1), Double(p.2), Double(p.3), duration: duration)
    }
    static var timing: CAMediaTimingFunction {
        let p = controlPoints
        return CAMediaTimingFunction(controlPoints: p.0, p.1, p.2, p.3)
    }
}

/// The panel content. Both pages stay mounted so they share one width (set by
/// the main page) and can crossfade; only the active one is visible, focusable
/// and exposed to VoiceOver.
struct LidModeQuickView: View {
    @Bindable var model: LidModeModel
    var route = LidPanelRoute()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LidPageLayout(settingsActive: route.page == .settings) {
            page(LidModeMainPage(model: model, route: route), active: route.page == .main, edge: -1)
            page(LidModeSettingsPage(model: model, route: route), active: route.page == .settings, edge: 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .fixedSize()
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refresh() }
        }
    }

    private func page(_ content: some View, active: Bool, edge: CGFloat) -> some View {
        content
            .opacity(active ? 1 : 0)
            .offset(x: active || reduceMotion ? 0 : edge * 10)
            .disabled(!active)
            .allowsHitTesting(active)
            .accessibilityHidden(!active)
    }
}

/// Width always comes from the main page, so switching pages never changes
/// the panel's width; height follows the active page.
struct LidPageLayout: Layout {
    var settingsActive: Bool

    private func width(_ subviews: Subviews) -> CGFloat {
        guard let main = subviews.first else { return 0 }
        return max(240, ceil(main.sizeThatFits(.unspecified).width))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = width(subviews)
        let index = settingsActive && subviews.count > 1 ? 1 : 0
        guard subviews.indices.contains(index) else { return .zero }
        return CGSize(width: width, height: ceil(subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil)).height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }
}

struct LidModeMainPage: View {
    @Bindable var model: LidModeModel
    let route: LidPanelRoute
    /// Direction of the request in flight, for «Включаем…» / «Выключаем…».
    @State private var pending: Bool?

    var body: some View {
        LidFitStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 12) {
                    Text(loc("lid.title"))
                        .font(.body.weight(.medium))
                        .fixedSize()
                        .onTapGesture { if canToggle { toggle(!model.isOn) } }
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                    Toggle(loc("lid.title"), isOn: Binding(get: { model.isOn }, set: { enabled in toggle(enabled) }))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(!canToggle)
                }
                LidStatusLine(status: LidStatus.current(for: model, pending: pending))
            }
            .lidDefinesWidth()

            // Rare, actionable detail: approval button or the error reason. The
            // panel grows for it; everyday states keep a fixed geometry.
            if let detail = LidDetail.current(for: model) {
                LidDetailView(detail: detail) { model.openApproval() }
                    .padding(.top, 10)
                    .transition(.opacity)
            }

            HStack(spacing: 8) {
                LidFooterButton(title: loc("settings.title"), symbol: "gearshape", help: loc("menu.settings")) {
                    route.show(.settings)
                }
                LidFooterButton(title: loc("menu.quit.short"), symbol: "power", help: loc("menu.quit")) {
                    NSApp.terminate(nil)
                }
                .accessibilityLabel(loc("menu.quit"))
            }
            .padding(.top, 12)
            .lidDefinesWidth()
        }
        .animation(LidMotion.curve, value: LidDetail.current(for: model))
        .onChange(of: model.phase) { _, phase in if phase != .working { pending = nil } }
    }

    private var canToggle: Bool {
        switch model.phase {
        case .working, .unavailable: return false
        default: return true
        }
    }

    private func toggle(_ enabled: Bool) {
        pending = enabled
        Task { await model.setEnabled(enabled) }
    }
}

/// One line of state under the switch. The row is always present and one line
/// tall, so off → working → on never moves or resizes anything.
struct LidStatus: Equatable {
    enum Tone: Equatable { case neutral, working, active, warning, error }
    let tone: Tone
    let text: String
    /// End of a confirmed lease; the text is recomputed from it as the clock moves.
    let until: Date?

    @MainActor static func current(for model: LidModeModel, pending: Bool?, now: Date = .now) -> LidStatus {
        switch model.phase {
        case .off:
            if let stop = model.lastStop, let note = LidModeStatusText.stopNote(stop) {
                return LidStatus(tone: .warning, text: note, until: nil)
            }
            return LidStatus(tone: .neutral, text: loc("status.off"), until: nil)
        case .working:
            let text = pending.map { $0 ? loc("status.enabling") : loc("status.disabling") } ?? loc("status.working")
            return LidStatus(tone: .working, text: text, until: nil)
        case .on(let until):
            return LidStatus(tone: .active, text: LidModeStatusText.onUntil(until, now: now), until: until)
        case .needsApproval:
            return LidStatus(tone: .warning, text: loc("status.needsApproval"), until: nil)
        case .batteryLow(let percent):
            return LidStatus(tone: .warning, text: loc("status.battery %@", String(percent)), until: nil)
        case .failed:
            return LidStatus(tone: .error, text: loc("status.failed"), until: nil)
        case .unavailable:
            return LidStatus(tone: .error, text: loc("status.unavailable"), until: nil)
        }
    }
}

struct LidStatusLine: View {
    let status: LidStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.everyMinute) { context in
            // Re-evaluated each minute so «завтра» disappears after midnight.
            let text = status.until == nil ? status.text : LidModeStatusText.onUntil(status.until, now: context.date)
            ZStack(alignment: .leading) {
                HStack(spacing: 6) {
                    indicator
                    Text(text)
                        .font(.callout)
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .monospacedDigit()
                }
                .id(text)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 3)))
            }
            .frame(height: 18, alignment: .leading)
            .animation(.easeOut(duration: 0.18), value: text)
            .help(text)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .onChange(of: text) { _, new in
                AccessibilityNotification.Announcement(new).post()
            }
        }
    }

    @ViewBuilder private var indicator: some View {
        Group {
            if status.tone == .working {
                ProgressView().controlSize(.mini)
            } else {
                Circle().fill(dotColor).frame(width: 7, height: 7)
            }
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
    }

    private var dotColor: Color {
        switch status.tone {
        case .neutral, .working: return Color.secondary.opacity(0.6)
        case .active: return .green
        case .warning: return .yellow
        case .error: return .red
        }
    }

    private var textColor: Color {
        switch status.tone {
        case .warning: return .yellow
        case .error: return .red
        default: return .secondary
        }
    }
}

/// The approval action or an error's reason. The status line already names the state.
struct LidDetail: Equatable {
    let text: String?
    let offersApproval: Bool

    @MainActor static func current(for model: LidModeModel) -> LidDetail? {
        switch model.phase {
        case .needsApproval: return LidDetail(text: nil, offersApproval: true)
        case .batteryLow: return LidDetail(text: loc("status.battery.requirement"), offersApproval: false)
        case .failed(let reason), .unavailable(let reason): return LidDetail(text: reason, offersApproval: false)
        case .off, .working, .on: return nil
        }
    }
}

struct LidDetailView: View {
    let detail: LidDetail
    let openApproval: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let text = detail.text {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if detail.offersApproval {
                Button(loc("lid.openApproval"), action: openApproval)
                    .controlSize(.small)
                    .help(loc("lid.openApproval.help"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Two equal, quiet buttons: icon + label, rounded fill that brightens on hover
/// and darkens on press; keyboard focus shows the system ring around the same shape.
struct LidFooterButton: View {
    let title: String
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(LidFooterButtonStyle())
        .help(help)
    }
}

struct LidFooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LidFooterButtonBody(configuration: configuration)
    }
}

private struct LidFooterButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.callout)
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : hovering ? 0.11 : 0.06))
            )
            // The Button keeps its own keyboard focus and the system focus ring.
            .contentShape(.focusEffect, RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(isEnabled ? 1 : 0.5)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// A vertical stack as wide as its marked rows. Unmarked rows (details,
/// footnotes) wrap to that width and add only height.
struct LidFitStack: Layout {
    var spacing: CGFloat = 10

    private func width(_ proposal: ProposedViewSize, _ subviews: Subviews) -> CGFloat {
        if let width = proposal.width, width.isFinite { return width }
        return subviews.filter { $0[LidDefinesWidth.self] }.map { ceil($0.sizeThatFits(.unspecified).width) }.max() ?? 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = width(proposal, subviews)
        let heights = subviews.map { ceil($0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height) }
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(0, subviews.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for subview in subviews {
            let size = ProposedViewSize(width: bounds.width, height: nil)
            subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: size)
            y += ceil(subview.sizeThatFits(size).height) + spacing
        }
    }
}

struct LidDefinesWidth: LayoutValueKey { static let defaultValue = false }

extension View {
    func lidDefinesWidth() -> some View { layoutValue(key: LidDefinesWidth.self, value: true) }
}
