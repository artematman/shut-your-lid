import AppKit
import Foundation
import Testing
import SwiftUI
@testable import LidModeFeature
@testable import ShutYourLid

@Suite("Lid mode menu bar and embedded helper")
struct LidModeMenuBarTests {
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
        #expect(size.width == 360)
        #expect(size.height > 80 && size.height < 240)
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
