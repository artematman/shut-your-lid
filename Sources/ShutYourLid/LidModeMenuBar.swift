import AppKit
import LidModeFeature
import Observation
import SwiftUI

/// A quick control for the same verified state used by General settings.
@MainActor
final class LidModeMenuBar: NSObject {
    private let model: LidModeModel
    private var item: NSStatusItem?
    private let panel = LidModeQuickPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var outsideClick: Any?
    private var localClick: Any?
    private var content: NSHostingView<LidModeQuickView>?

    init(model: LidModeModel) {
        self.model = model
        super.init()
        panel.onClose = { [weak self] in self?.closePanel() }
    }

    func start() {
        guard item == nil, NSApp != nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.item = item
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.setAccessibilityLabel(loc("lid.title"))
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        let contentSize = NSSize(width: 360, height: 240)
        let glass = NSVisualEffectView(frame: NSRect(origin: .zero, size: contentSize))
        glass.material = .popover
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 18
        glass.layer?.masksToBounds = true
        let content = NSHostingView(rootView: LidModeQuickView(model: model))
        self.content = content
        content.sizingOptions = [.intrinsicContentSize]
        content.frame = glass.bounds
        content.autoresizingMask = [.width, .height]
        glass.addSubview(content)
        LidModeMenuBarGeometry.install(contentView: glass, in: panel, size: contentSize)
        resizeToContent()
        observeState()
        Task { await model.refresh() }
    }

    private func observeState() {
        withObservationTracking {
            _ = model.phase
            _ = model.lastStop
            let enabled = model.isOn
            item?.button?.image = NSImage(systemSymbolName: enabled ? "laptopcomputer.and.arrow.down" : "laptopcomputer",
                                         accessibilityDescription: loc("lid.title"))
            item?.button?.image?.isTemplate = true
            item?.button?.toolTip = loc("lid.title") + " · " + (enabled ? "●" : "○")
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeState()
                // Let SwiftUI update the conditional approval button first.
                await Task.yield()
                self?.resizeToContent()
            }
        }
    }

    private func resizeToContent() {
        guard let content else { return }
        content.layoutSubtreeIfNeeded()
        let size = LidModeMenuBarGeometry.contentSize(for: content)
        guard panel.frame.size != size else { return }
        panel.setContentSize(size)
        if panel.isVisible, let button = item?.button, let window = button.window,
           let screen = window.screen ?? NSScreen.main {
            let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
            panel.setFrame(LidModeMenuBarGeometry.frame(anchor: anchor, screen: screen.frame, size: size), display: true)
        }
    }

    @objc private func togglePopover() {
        guard let button = item?.button, let window = button.window else { return }
        guard let screen = window.screen ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        if panel.isVisible { closePanel(); return }
        closePanel()
        resizeToContent()
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        panel.setFrame(LidModeMenuBarGeometry.frame(anchor: anchor, screen: screen.frame, size: panel.frame.size), display: true)
        panel.makeKeyAndOrderFront(nil)
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
        localClick = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak window] event in
            if let self, event.window !== self.panel, event.window !== window { self.closePanel() }
            return event
        }
        Task { await model.refresh() }
    }

    private func closePanel() {
        panel.orderOut(nil)
        if let outsideClick { NSEvent.removeMonitor(outsideClick) }
        if let localClick { NSEvent.removeMonitor(localClick) }
        outsideClick = nil
        localClick = nil
    }
}

enum LidModeMenuBarGeometry {
    @MainActor static func contentSize(for content: NSView) -> NSSize {
        NSSize(width: 360, height: max(80, ceil(content.fittingSize.height)))
    }
    @MainActor static func install(contentView: NSView, in panel: NSPanel, size: NSSize) {
        // Assigning contentView to a zero-size panel can resize that view to
        // zero. Never read its bounds back as the desired window size.
        panel.contentView = contentView
        panel.setContentSize(size)
    }

    static func frame(anchor: NSRect, screen: NSRect, size: NSSize) -> NSRect {
        let width = min(size.width, screen.width - 16)
        let height = min(size.height, screen.height - 16)
        let x = min(max(anchor.midX - width / 2, screen.minX + 8), screen.maxX - width - 8)
        let y = max(screen.minY + 8, min(anchor.minY - height - 8, screen.maxY - height - 8))
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

private final class LidModeQuickPanel: NSPanel {
    var onClose: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onClose?() }
}

struct LidModeQuickView: View {
    @Bindable var model: LidModeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Shut Your Lid").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Выйти") { NSApp.terminate(nil) }.buttonStyle(.plain).font(.caption) }
            Toggle(loc("lid.title"), isOn: Binding(
                get: { model.isOn },
                set: { enabled in Task { await model.setEnabled(enabled) } }
            ))
            .toggleStyle(.switch)
            .font(.headline)
            .disabled(model.phase == .working || unavailable)

            Text(LidModeSettingsView(model: model).detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.phase == .needsApproval {
                Button(loc("lid.openApproval")) { model.openApproval() }
            }
        }
        .padding(20)
        .frame(width: 360, alignment: .leading)
        .fixedSize(horizontal: true, vertical: true)
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refresh() }
        }
    }

    private var unavailable: Bool {
        if case .unavailable = model.phase { return true }
        return false
    }
}
