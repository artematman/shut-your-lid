import AppKit
import Foundation
import Testing
import SwiftUI
@testable import LidModeFeature
@testable import ShutYourLid

@Suite("Lid mode menu bar and embedded helper")
struct LidModeMenuBarTests {
    @Test("heat refusal is red guidance, clears after cooling and never masks restoration failures")
    @MainActor func heatWarningRecovery() async throws {
        var hot = true
        let model = LidModeModel(system: .init(
            serviceState: { .enabled }, register: {}, openLoginItems: {},
            call: { _ in LidModeWire.decode(LidModeWire.encode(LidModeStatus(blockedByHeat: hot))) }
        ))
        await model.setEnabled(true)
        #expect(model.phase == .overheated && !model.isOn)
        #expect(LidStatus.current(for: model, pending: nil).tone == .error)
        #expect(LidStatus.current(for: model, pending: nil).text == loc("status.thermal"))
        #expect(LidDetail.current(for: model)?.text == loc("status.thermal.requirement"))
        hot = false
        await model.refresh()
        #expect(model.phase == .off && !model.isOn)
        let failed = LidModeModel(system: .init(
            serviceState: { .enabled }, register: {}, openLoginItems: {},
            call: { _ in LidModeStatus(error: "restoration failed", blockedByHeat: true) }
        ))
        await failed.setEnabled(true)
        #expect(failed.phase == .failed("restoration failed"))
    }

    @Test("native battery and heat warning previews render when requested")
    @MainActor func warningPreviews() async throws {
        guard let folder = ProcessInfo.processInfo.environment["LID_WARNING_PREVIEW_DIR"] else { return }
        _ = NSApplication.shared
        let out = URL(fileURLWithPath: folder)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for (name, status) in [("battery", LidModeStatus(blockedBatteryPercent: 6)), ("heat", LidModeStatus(blockedByHeat: true))] {
            let model = LidModeModel(system: .init(serviceState: { .enabled }, register: {}, openLoginItems: {}, call: { _ in status }))
            await model.setEnabled(true)
            let host = NSHostingView(rootView: LidModeQuickView(model: model))
            host.appearance = NSAppearance(named: .darkAqua)
            host.sizingOptions = [.intrinsicContentSize]
            host.layoutSubtreeIfNeeded()
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            host.wantsLayer = true
            host.layer?.backgroundColor = NSColor(white: 0.16, alpha: 1).cgColor
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: out.appendingPathComponent("\(name).png"))
        }
    }

    @Test("low battery is a localized warning, preserves the percent and never turns the mode on", arguments: [6, 10])
    @MainActor func lowBatteryWarning(percent: Int) async throws {
        let reply = LidModeStatus(blockedBatteryPercent: percent)
        let decoded = try #require(LidModeWire.decode(LidModeWire.encode(reply)))
        let model = LidModeModel(system: .init(
            serviceState: { .enabled }, register: {}, openLoginItems: {}, call: { _ in decoded }
        ))
        await model.setEnabled(true)
        #expect(!model.isOn)
        #expect(model.phase == .batteryLow(percent))
        let status = LidStatus.current(for: model, pending: nil)
        #expect(status.tone == .warning)
        #expect(status.text == loc("status.battery %@", String(percent)))
        #expect(LidDetail.current(for: model)?.text == loc("status.battery.requirement"))
        #expect(lidString("status.battery %@", language: .ru, [String(percent)]) == "Заряд аккумулятора \(percent)%")
        #expect(lidString("status.battery %@", language: .en, [String(percent)]) == "Battery charge \(percent)%")
    }

    @Test("a real helper failure takes priority over a battery warning; old replies remain compatible")
    @MainActor func batteryWarningCompatibility() async throws {
        let model = LidModeModel(system: .init(
            serviceState: { .enabled }, register: {}, openLoginItems: {},
            call: { _ in LidModeStatus(error: "restoration failed", blockedBatteryPercent: 6) }
        ))
        await model.setEnabled(true)
        #expect(model.phase == .failed("restoration failed"))
        #expect(LidStatus.current(for: model, pending: nil).tone == .error)
        let oldReply = Data(#"{"active":false,"sleepDisabledNow":false,"batteryFloor":10}"#.utf8)
        let oldStatus = try #require(LidModeWire.decode(oldReply))
        #expect(oldStatus.blockedBatteryPercent == nil)
    }

    @Test("the actual SwiftUI approval card determines the native window height without a fixed empty footer")
    @MainActor func fittedApprovalCard() async {
        _ = NSApplication.shared
        let model = LidModeModel(system: .init(
            serviceState: { .requiresApproval }, register: {}, openLoginItems: {}, call: { _ in nil }
        ))
        await model.setEnabled(true)
        let content = NSHostingView(rootView: LidModeQuickView(model: model))
        content.sizingOptions = [.intrinsicContentSize]
        content.layoutSubtreeIfNeeded()
        let size = LidModeMenuBarGeometry.contentSize(for: content)
        #expect(size.width == ceil(content.fittingSize.width) && size.width < 360)
        #expect(size.height > 80 && size.height < 260)
        #expect(size.height == ceil(content.fittingSize.height))
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        LidModeMenuBarGeometry.install(contentView: content, in: panel, size: size)
        #expect(panel.frame.height == size.height)
        #expect(content.fittingSize.height <= panel.frame.height)
    }

    @Test("installing content into an initially zero-size native panel keeps it visible")
    @MainActor func nativePanelSize() {
        _ = NSApplication.shared
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let size = NSSize(width: 360, height: 240)
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        LidModeMenuBarGeometry.install(contentView: content, in: panel, size: size)
        #expect(panel.frame.size == size)
        #expect(content.bounds.size == size)
    }

    @Test("quick control sits under its icon on either display and stays inside screen edges")
    func placement() {
        for screen in [NSRect(x: 0, y: 0, width: 1512, height: 982), NSRect(x: -1920, y: 200, width: 1920, height: 1080)] {
            for x in [screen.minX + 10, screen.midX, screen.maxX - 20] {
                let anchor = NSRect(x: x, y: screen.maxY - 28, width: 24, height: 28)
                let frame = LidModeMenuBarGeometry.frame(anchor: anchor, screen: screen, size: NSSize(width: 360, height: 240))
                #expect(frame.maxY == anchor.minY - 8)
                #expect(screen.contains(frame))
                #expect(frame.minX >= screen.minX + 8 && frame.maxX <= screen.maxX - 8)
            }
        }
    }

    @Test("helper availability is checked in the app artifact, including identity and executable, before blocking registration")
    @MainActor func embeddedHelper() throws {
        let bundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("Test.app")
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
        let id = "com.artemkharitonov.shutyourlid"
        #expect(!LidModeModel.System.hasEmbeddedHelper(bundleURL: bundle, appBundleID: id))
        let folder = bundle.appendingPathComponent("Contents/Library/LaunchDaemons")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let plist = folder.appendingPathComponent(LidPowerHelperIdentity.plistName(forApp: id))
        let info = ["Label": LidPowerHelperIdentity.label(forApp: id), "BundleProgram": "Contents/MacOS/LidPowerHelper"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: plist)
        #expect(!LidModeModel.System.hasEmbeddedHelper(bundleURL: bundle, appBundleID: id))
        let executable = bundle.appendingPathComponent("Contents/MacOS/LidPowerHelper")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        #expect(LidModeModel.System.hasEmbeddedHelper(bundleURL: bundle, appBundleID: id))
        #expect(!LidModeModel.System.hasEmbeddedHelper(bundleURL: bundle, appBundleID: "wrong.identity"))
        try Data("invalid plist".utf8).write(to: plist)
        #expect(!LidModeModel.System.hasEmbeddedHelper(bundleURL: bundle, appBundleID: id))
    }
}

@MainActor @Suite("Panel layout")
struct DurationPanelLayoutTests {
    private func fitted(_ view: LidModeQuickView) -> (NSHostingView<LidModeQuickView>, NSSize) {
        let content = NSHostingView(rootView: view)
        content.sizingOptions = [.intrinsicContentSize]
        content.layoutSubtreeIfNeeded()
        return (content, LidModeMenuBarGeometry.contentSize(for: content))
    }

    private func model(_ state: LidModeModel.ServiceState = .notRegistered,
                       _ reply: @escaping @MainActor (LidModeModel.Request) async -> LidModeStatus? = { _ in nil }) -> LidModeModel {
        LidModeModel(system: .init(serviceState: { state }, register: {}, openLoginItems: {}, call: reply))
    }

    private func width(_ text: String, _ font: NSFont) -> CGFloat {
        ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width)
    }

    @Test("slider track stays in place as localized duration changes width")
    func stableSliderTrack() throws {
        _ = NSApplication.shared
        func slider(in view: NSView) -> NSSlider? {
            if let found = view as? NSSlider { return found }
            for child in view.subviews { if let found = slider(in: child) { return found } }
            return nil
        }
        var baseline: NSRect?
        for minutes in [1, 59, 60, 61, 90, 282, 659, 720] {
            let m = model()
            m.usesCustomDuration = true
            m.setDuration(minutes: minutes)
            let route = LidPanelRoute(); route.page = .settings
            let (content, size) = fitted(LidModeQuickView(model: m, route: route))
            content.frame = NSRect(origin: .zero, size: size)
            content.layoutSubtreeIfNeeded()
            let control = try #require(slider(in: content))
            let rect = control.convert(control.bounds, to: content)
            #expect(rect.width > 60)
            if let baseline { #expect(abs(rect.minX - baseline.minX) < 1 && abs(rect.width - baseline.width) < 1) }
            else { baseline = rect }
        }
    }

    @Test("main page fits the full switch label and two buttons, nothing more")
    func compactMain() {
        _ = NSApplication.shared
        let (_, main) = fitted(LidModeQuickView(model: model()))
        let label = width(loc("lid.title"), .systemFont(ofSize: NSFont.systemFontSize, weight: .medium))
        // Label + 12 pt gap + switch + 14 pt side paddings: never clipped, never padded out.
        #expect(main.width >= label + 28 + 40)
        #expect(main.width <= max(240 + 28, label + 28 + 80))
        #expect(main.height < 110)
    }

    @Test("off, working, on and an automatic stop share one geometry; no spinner width jump")
    func stableGeometry() async {
        _ = NSApplication.shared
        let (_, off) = fitted(LidModeQuickView(model: model()))

        var release: CheckedContinuation<Void, Never>?
        var confirmed = false
        let slow = model(.enabled) { request in
            if case .enable = request {
                await withCheckedContinuation { release = $0 }
                confirmed = true
            }
            // Status refreshes from the view report the helper's real state.
            return LidModeStatus(active: confirmed, sleepDisabledNow: confirmed,
                                 expiresAt: confirmed ? Date().addingTimeInterval(3 * 3600) : nil)
        }
        let task = Task { await slow.setEnabled(true) }
        while slow.phase != .working || release == nil { await Task.yield() }
        let (_, working) = fitted(LidModeQuickView(model: slow))
        #expect(!slow.isOn)
        release?.resume()
        await task.value
        let (_, on) = fitted(LidModeQuickView(model: slow))
        #expect(slow.isOn)

        let stopped = model(.enabled) { _ in LidModeStatus(active: false, sleepDisabledNow: false, lastStopReason: .batteryFloor) }
        await stopped.refresh()
        let (_, stop) = fitted(LidModeQuickView(model: stopped))
        #expect(working == off && on == off && stop == off)
    }

    @Test("status texts: in-flight direction, confirmed end time, short stop reasons")
    func statusTexts() async {
        _ = NSApplication.shared
        let off = model()
        #expect(LidStatus.current(for: off, pending: nil).text == loc("status.off"))
        let pending = model(.enabled) { _ in nil }
        let task = Task { await pending.setEnabled(true) }
        await task.value
        #expect(LidStatus.current(for: pending, pending: nil).tone == .error)
        let stopped = model(.enabled) { _ in LidModeStatus(active: false, sleepDisabledNow: false, lastStopReason: .batteryFloor) }
        await stopped.refresh()
        #expect(LidStatus.current(for: stopped, pending: nil).text == loc("lid.stop.battery"))
        for quiet in [LidModeStatus.StopReason.user, .appGone, .heartbeatLost, .recoveredAfterRestart] {
            let m = model(.enabled) { _ in LidModeStatus(active: false, sleepDisabledNow: false, lastStopReason: quiet) }
            await m.refresh()
            #expect(LidStatus.current(for: m, pending: nil).text == loc("status.off"))
        }
    }

    @Test("detail rows appear only for approval and errors, and grow height but not width")
    func details() async {
        _ = NSApplication.shared
        let plain = model()
        #expect(LidDetail.current(for: plain) == nil)
        let approval = model(.requiresApproval)
        await approval.setEnabled(true)
        #expect(LidDetail.current(for: approval) == LidDetail(text: nil, offersApproval: true))
        let failing = model(.enabled)
        await failing.setEnabled(true)
        #expect(LidDetail.current(for: failing)?.text == loc("lid.helperGone"))
        let (_, base) = fitted(LidModeQuickView(model: plain))
        for grown in [approval, failing] {
            let (_, size) = fitted(LidModeQuickView(model: grown))
            #expect(size.width == base.width && size.height > base.height)
        }
        // A very long helper error wraps (bounded) instead of widening the panel.
        let verbose = model(.enabled) { _ in LidModeStatus(active: false, sleepDisabledNow: false, error: String(repeating: "очень длинная причина ошибки ", count: 20)) }
        await verbose.refresh()
        let (_, long) = fitted(LidModeQuickView(model: verbose))
        #expect(long.width == base.width && long.height < base.height + 120)
    }

    @Test("pending or unconfirmed enabling never shows the switch on")
    func neverFakeOn() async {
        _ = NSApplication.shared
        let unconfirmed = model(.enabled) { _ in LidModeStatus(active: true, sleepDisabledNow: false) }
        await unconfirmed.setEnabled(true)
        #expect(!unconfirmed.isOn && LidStatus.current(for: unconfirmed, pending: true).tone != .active)
        let approval = model(.requiresApproval)
        await approval.setEnabled(true)
        #expect(!approval.isOn && LidStatus.current(for: approval, pending: true).tone == .warning)
    }

    @Test("a lost heartbeat shows a connection error, never «Выключено»; a later confirmed status recovers")
    func lostHeartbeat() async throws {
        _ = NSApplication.shared
        var answering = true
        let m = model(.enabled) { request in
            if case .heartbeat = request, !answering { return nil }
            return LidModeStatus(active: true, sleepDisabledNow: true, expiresAt: Date().addingTimeInterval(3600))
        }
        m.heartbeatInterval = .milliseconds(30)
        await m.setEnabled(true)
        #expect(m.isOn)
        answering = false
        let deadline = ContinuousClock.now + .seconds(10)
        while m.isOn, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(m.phase == .failed(loc("lid.connectionLost")))
        let status = LidStatus.current(for: m, pending: nil)
        #expect(status.tone == .error && status.text != loc("status.off"))
        #expect(LidDetail.current(for: m)?.text == loc("lid.connectionLost"))
        answering = true
        await m.refresh()
        #expect(m.isOn)
        await m.setEnabled(false)
    }

    @Test("rapid on/off requests settle on the helper-confirmed state")
    func rapidToggles() async {
        _ = NSApplication.shared
        var active = false
        let m = model(.enabled) { request in
            switch request {
            case .enable: active = true
            case .disable: active = false
            default: break
            }
            return LidModeStatus(active: active, sleepDisabledNow: active, expiresAt: active ? Date().addingTimeInterval(600) : nil)
        }
        for index in 0..<10 { await m.setEnabled(index % 2 == 0) }
        #expect(!m.isOn && LidStatus.current(for: m, pending: nil).text == loc("status.off"))
        await m.setEnabled(true)
        #expect(m.isOn && LidStatus.current(for: m, pending: nil).tone == .active)
    }

    @Test("settings and back keep the width and return to the same height")
    func pageRoundTrip() {
        _ = NSApplication.shared
        let m = model()
        let route = LidPanelRoute()
        let (_, before) = fitted(LidModeQuickView(model: m, route: route))
        route.show(.settings)
        let (_, settings) = fitted(LidModeQuickView(model: m, route: route))
        route.show(.main)
        let (_, after) = fitted(LidModeQuickView(model: m, route: route))
        #expect(settings.width == before.width && settings.height > before.height)
        #expect(after == before)
    }

    @Test("custom duration adds an unclipped row in settings while keeping the width")
    func customRow() throws {
        _ = NSApplication.shared
        let m = model()
        let route = LidPanelRoute(); route.page = .settings
        let (_, presetSize) = fitted(LidModeQuickView(model: m, route: route))
        m.usesCustomDuration = true
        m.setDuration(minutes: 45)
        let (custom, size) = fitted(LidModeQuickView(model: m, route: route))
        #expect(size.width == presetSize.width && size.height > presetSize.height && size.height < 480)
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        LidModeMenuBarGeometry.install(contentView: custom, in: panel, size: size)
        custom.layoutSubtreeIfNeeded()
        #expect(custom.fittingSize.height <= panel.frame.height)
    }

    @Test("duration presets include six hours; the native pop-up and slider fill the group width")
    func durationControls() {
        _ = NSApplication.shared
        #expect(LidDurationPicker.presets == [30, 60, 120, 240, 360, 480, 720])
        let m = model()
        m.setDuration(minutes: 360)
        m.usesCustomDuration = false
        #expect(!LidDurationPicker.showsCustom(m))
        m.usesCustomDuration = true
        m.setDuration(minutes: 90)
        let route = LidPanelRoute(); route.page = .settings
        let (content, size) = fitted(LidModeQuickView(model: m, route: route))
        content.frame = NSRect(origin: .zero, size: size)
        content.layoutSubtreeIfNeeded()
        func find<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
            (view as? T).map { [$0] } ?? [] + view.subviews.flatMap { find(type, in: $0) }
        }
        let popUps = find(NSPopUpButton.self, in: content)
        let sliders = find(NSSlider.self, in: content)
        #expect(popUps.count == 1 && sliders.count == 1)
        if let popUp = popUps.first {
            // Group inset 10 pt each side, page inset 14 pt each side.
            #expect(popUp.frame.width >= size.width - 28 - 20 - 2)
            #expect(popUp.titleOfSelectedItem == loc("settings.duration.custom"))
            #expect(popUp.itemTitles.contains(lidDuration(minutes: 360)))
        }
        if let slider = sliders.first {
            #expect(slider.numberOfTickMarks == 0 && slider.isContinuous)
            #expect(slider.minValue == 1 && slider.maxValue == 720 && Int(slider.doubleValue) == 90)
            #expect(slider.frame.width > 100)
        }
    }

    @Test("slider and pop-up edits go straight to the model while changes are allowed")
    func durationEditsReachModel() {
        _ = NSApplication.shared
        let m = model()
        let slider = LidSlider(value: 90, range: 1...720, label: "", valueDescription: "") { m.setDuration(minutes: $0) }
        let coordinator = slider.makeCoordinator()
        coordinator.onChange = { m.setDuration(minutes: $0) }
        coordinator.current = 90
        let native = NSSlider(value: 136.6, minValue: 1, maxValue: 720, target: nil, action: nil)
        coordinator.changed(native)
        #expect(m.maxMinutes == 137)
        let popUp = LidPopUpButton(items: [(360, "6")], selection: 0, label: "") { m.setDuration(minutes: $0) }
        let popUpCoordinator = popUp.makeCoordinator()
        popUpCoordinator.onSelect = { m.setDuration(minutes: $0) }
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        let item = NSMenuItem(title: "6", action: nil, keyEquivalent: ""); item.tag = 360
        button.menu?.addItem(item); button.selectItem(withTag: 360)
        popUpCoordinator.changed(button)
        #expect(m.maxMinutes == 360)
    }

    @Test("every one-line status and both button pairs fit the panel width in RU and EN")
    func longStringsFit() {
        let medium = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        let callout = NSFont.preferredFont(forTextStyle: .callout)
        let statusKeys = ["status.off", "status.enabling", "status.disabling", "status.working", "status.on",
                          "status.needsApproval", "status.failed", "status.unavailable",
                          "lid.stop.battery", "lid.stop.thermal", "lid.stop.time", "lid.stop.telemetry", "lid.stop.failed"]
        for language in [LidLanguage.ru, .en] {
            let inner = max(240, width(lidString("lid.title", language: language), medium) + 12 + 40)
            for key in statusKeys + ["status.on.tomorrow %@"] {
                let text = lidString(key, language: language, key.contains("%@") ? ["23:59"] : [])
                #expect(width(text, callout) + 18 <= inner, "\(language) \(key)")
            }
            for pair in [("settings.title", "menu.quit.short"), ("settings.back", "menu.quit.short")] {
                let buttons = [pair.0, pair.1].map { width(lidString($0, language: language), callout) + 20 + 20 }
                #expect(buttons.max()! * 2 + 8 <= inner, "\(language) \(pair)")
            }
        }
    }

    /// Renders every state to PNGs for visual review: LID_PREVIEW_DIR=/some/dir swift test --filter previews
    @Test("preview renders when requested")
    func previews() async throws {
        guard let folder = ProcessInfo.processInfo.environment["LID_PREVIEW_DIR"] else { return }
        let app = NSApplication.shared
        app.appearance = NSAppearance(named: .darkAqua)
        let off = model()
        let on = model(.enabled) { _ in LidModeStatus(active: true, sleepDisabledNow: true, expiresAt: Date().addingTimeInterval(9 * 3600)) }
        await on.refresh()
        let approval = model(.requiresApproval); await approval.setEnabled(true)
        let battery = model(.enabled) { _ in LidModeStatus(active: false, sleepDisabledNow: false, lastStopReason: .batteryFloor) }
        await battery.refresh()
        let failed = model(.enabled); await failed.setEnabled(true)
        let settings = LidPanelRoute(); settings.page = .settings
        let custom = model()
        custom.usesCustomDuration = true; custom.setDuration(minutes: 90)
        for (name, view) in [("off", LidModeQuickView(model: off)), ("on", LidModeQuickView(model: on)),
                             ("approval", LidModeQuickView(model: approval)), ("battery-stop", LidModeQuickView(model: battery)),
                             ("failed", LidModeQuickView(model: failed)),
                             ("settings", LidModeQuickView(model: off, route: settings)),
                             ("settings-custom", LidModeQuickView(model: custom, route: settings))] {
            let (content, size) = fitted(view)
            let backdrop = NSView(frame: NSRect(origin: .zero, size: size))
            backdrop.wantsLayer = true
            backdrop.layer?.backgroundColor = NSColor(white: 0.16, alpha: 1).cgColor
            content.frame = backdrop.bounds
            backdrop.addSubview(content)
            backdrop.layoutSubtreeIfNeeded()
            guard let bitmap = backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds) else { continue }
            backdrop.cacheDisplay(in: backdrop.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png"))
        }
    }
}
