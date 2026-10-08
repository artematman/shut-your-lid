import AppKit
import LidModeFeature
import Observation
import SwiftUI

/// Which page the menu bar panel shows. Shared by the panel and its SwiftUI content.
@MainActor @Observable final class LidPanelRoute {
    enum Page { case main, settings }
    var page: Page = .main

    /// Crossfades pages; the panel's AppKit resize runs alongside with the same curve.
    func show(_ page: Page) {
        guard self.page != page else { return }
        withAnimation(LidMotion.reduced ? .easeOut(duration: 0.15) : LidMotion.curve) { self.page = page }
    }
}

/// The menu bar icon and its panel: the switch with Settings and Quit, settings on their own page.
@MainActor
final class LidModeMenuBar: NSObject {
    private let model: LidModeModel
    private let route = LidPanelRoute()
    private var item: NSStatusItem?
    private let panel = LidModeQuickPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var outsideClick: Any?
    private var localClick: Any?
    private var content: NSHostingView<LidModeQuickView>?
    private let defaults: UserDefaults
    private(set) var splash: LidOnboardingController?
    private let brandLogo: NSImage?

    init(model: LidModeModel, defaults: UserDefaults = .standard, logo: NSImage? = LidBrand.logo()) {
        self.model = model
        self.defaults = defaults
        self.brandLogo = logo
        super.init()
        panel.onClose = { [weak self] in self?.closePanel() }
        panel.onCancel = { [weak self] in
            guard let self else { return }
            // Escape steps back from Settings first, then closes.
            if self.route.page == .settings { self.route.show(.main) } else { self.closePanel() }
        }
        panel.onSettings = { [weak self] in self?.route.show(.settings) }
    }

    func start() {
        guard item == nil, NSApp != nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.item = item
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.setAccessibilityLabel(loc("lid.title"))
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        let contentSize = NSSize(width: 300, height: 120)
        let glass: NSView
        let surface = NSView(frame: NSRect(origin: .zero, size: contentSize))
        surface.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *) {
            let effect = NSGlassEffectView(frame: surface.bounds)
            effect.style = .regular
            effect.cornerRadius = 18
            effect.contentView = surface
            glass = effect
        } else {
            let effect = NSVisualEffectView(frame: surface.bounds)
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = 18
            effect.layer?.masksToBounds = true
            effect.addSubview(surface)
            glass = effect
        }
        let content = NSHostingView(rootView: LidModeQuickView(model: model, route: route))
        self.content = content
        content.sizingOptions = [.intrinsicContentSize]
        content.frame = glass.bounds
        // Pinned to the top edge: while the panel grows or shrinks, rows stay put
        // and the bottom is revealed or clipped by the rounded glass.
        content.autoresizingMask = [.minYMargin]
        surface.addSubview(content)
        LidModeMenuBarGeometry.install(contentView: glass, in: panel, size: contentSize)
        resizeToContent()
        observeState()
        Task { await model.refresh() }
    }

    private func observeState() {
        withObservationTracking {
            _ = model.phase
            _ = model.lastStop
            _ = model.usesCustomDuration
            _ = route.page
            let enabled = model.isOn
            item?.button?.image = NSImage(systemSymbolName: enabled ? "laptopcomputer.and.arrow.down" : "laptopcomputer",
                                         accessibilityDescription: loc("lid.title"))
            item?.button?.image?.isTemplate = true
            item?.button?.toolTip = "Shut Your Lid · " + (enabled ? loc("status.on") : loc("status.off"))
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeState()
                // Let SwiftUI swap pages and notices first, then fit the panel.
                await Task.yield()
                self?.resizeToContent()
            }
        }
    }

    /// Fits the panel to the SwiftUI content. Visible panels animate with the
    /// SwiftUI curve, keeping the top edge under the icon; Reduce Motion or a
    /// hidden panel resizes at once.
    private func resizeToContent() {
        guard let content, let glass = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let size = LidModeMenuBarGeometry.contentSize(for: content)
        // Give SwiftUI its final size first, pinned to the top of the glass.
        content.frame = NSRect(x: 0, y: glass.bounds.height - size.height, width: size.width, height: size.height)
        guard panel.frame.size != size else { return }
        guard panel.isVisible, let button = item?.button, let window = button.window,
              let screen = window.screen ?? NSScreen.main else {
            panel.setContentSize(size)
            content.frame = NSRect(origin: .zero, size: size)
            return
        }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let target = LidModeMenuBarGeometry.frame(anchor: anchor, screen: screen.frame, size: size)
        if LidMotion.reduced {
            panel.setFrame(target, display: true)
            content.frame = NSRect(origin: .zero, size: size)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = LidMotion.duration
            context.timingFunction = LidMotion.timing
            panel.animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let content = self.content, let glass = self.panel.contentView else { return }
                content.frame = NSRect(x: 0, y: glass.bounds.height - content.frame.height,
                                       width: content.frame.width, height: content.frame.height)
            }
        }
    }

    func showPanel() {
        if !panel.isVisible { togglePopover() }
    }

    /// Launch and Dock reopen: the brand splash, then it flies into the menu bar
    /// icon. The first time on this profile it also explains where the controls
    /// are. The main panel stays closed; a click on the icon opens it as usual.
    func showBrandSplash() {
        // Launch Services can deliver reopen alongside the initial launch.
        // Keep the current animation playing when that happens or the Dock is clicked twice.
        guard splash == nil else { return }
        closePanel()
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let splash = LidOnboardingController(defaults: defaults, explains: LidOnboardingStore.shouldShow(defaults))
        splash.iconTarget = { [weak self] in self?.iconRect(on: screen) }
        splash.onArrive = { [weak self] in
            guard let button = self?.item?.button else { return }
            button.highlight(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { button.highlight(false) }
        }
        splash.onFinish = { [weak self] in self?.splash = nil }
        self.splash = splash
        splash.present(on: screen.visibleFrame, icon: item?.button?.image, iconVisible: iconRect(on: screen) != nil, logo: brandLogo)
    }

    /// The status item's rect, only when macOS shows it on `screen` (not hidden
    /// by the notch or overflow, not on another display).
    private func iconRect(on screen: NSScreen) -> NSRect? {
        guard let button = item?.button, let window = button.window, window.screen == screen,
              window.occlusionState.contains(.visible) else { return nil }
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        return screen.frame.intersects(rect) ? rect : nil
    }

    @objc private func togglePopover() {
        if NSApp.currentEvent?.type == .rightMouseUp { showContextMenu(); return }
        // Clicking the icon while the splash plays: close it and open the menu as usual.
        if let splash { splash.dismissNow(); self.splash = nil }
        guard let button = item?.button, let window = button.window else { return }
        guard let screen = window.screen ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        if panel.isVisible { closePanel(); return }
        closePanel(resettingPage: false)
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

    /// Right-click on the icon: Settings and Quit as a standard menu.
    private func showContextMenu() {
        guard let item, let button = item.button else { return }
        closePanel()
        let menu = NSMenu()
        let settings = NSMenuItem(title: loc("menu.settings"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(withTitle: loc("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        button.performClick(nil)
        item.menu = nil
    }

    @objc private func openSettings() {
        route.page = .settings
        showPanel()
    }

    /// Closing returns to the main page, so the next click opens on the switch.
    private func closePanel(resettingPage: Bool = true) {
        panel.orderOut(nil)
        if resettingPage { route.page = .main }
        if let outsideClick { NSEvent.removeMonitor(outsideClick) }
        if let localClick { NSEvent.removeMonitor(localClick) }
        outsideClick = nil
        localClick = nil
    }
}

enum LidModeMenuBarGeometry {
    /// The SwiftUI content's own fitted size; nothing wider or taller.
    @MainActor static func contentSize(for content: NSView) -> NSSize {
        let fitting = content.fittingSize
        return NSSize(width: max(120, ceil(fitting.width)), height: max(44, ceil(fitting.height)))
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
    var onCancel: (() -> Void)?
    var onSettings: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }

    /// An accessory app has no visible menu bar, so the panel handles the
    /// standard shortcuts itself: ⌘, settings, ⌘W close, ⌘Q quit.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case ",": onSettings?(); return true
        case "w": onClose?(); return true
        case "q": NSApp.terminate(nil); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
}
