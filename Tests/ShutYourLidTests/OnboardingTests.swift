import AppKit
import CoreText
import Foundation
import SwiftUI
import Testing
@testable import LidModeFeature
@testable import ShutYourLid

@MainActor @Suite("First-run introduction")
struct OnboardingTests {
    private func defaults() throws -> UserDefaults {
        let suite = "shutyourlid.onboarding.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// The approved artwork from the repository (the app bundle carries it as the .icns).
    private var logo: NSImage? {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return NSImage(contentsOf: root.appendingPathComponent("App/Assets/LogoDark.png"))
    }

    private func fitted(_ view: LidOnboardingView) -> NSHostingView<LidOnboardingView> {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        return host
    }

    private func view(_ state: LidOnboardingState, parts: LidZipperParts? = nil, iconVisible: Bool = true) -> LidOnboardingView {
        LidOnboardingView(state: state, logo: logo, parts: parts, icon: NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: nil),
                          iconVisible: iconVisible, onSkip: {}, onDone: {})
    }

    @Test("shown once per profile; installs updated from earlier versions see it once too")
    func oncePerProfile() throws {
        let fresh = try defaults()
        #expect(LidOnboardingStore.shouldShow(fresh))
        let updated = try defaults()
        updated.set(240, forKey: "durationMinutes")   // an existing 0.3.x user
        #expect(LidOnboardingStore.shouldShow(updated))
        LidOnboardingStore.markShown(updated)
        #expect(!LidOnboardingStore.shouldShow(updated))
    }

    @Test("the first-run card marks the profile only when it leaves; the short splash never does")
    func markOnLeave() throws {
        _ = NSApplication.shared
        let store = try defaults()
        let first = LidOnboardingController(defaults: store, explains: true, reduced: true)
        var finished = 0
        first.onFinish = { finished += 1 }
        #expect(LidOnboardingStore.shouldShow(store))
        first.dismissNow()
        first.dismissNow()
        #expect(!LidOnboardingStore.shouldShow(store) && finished == 1)
        let other = try defaults()
        let repeatSplash = LidOnboardingController(defaults: other, explains: false, reduced: true)
        repeatSplash.dismissNow()
        #expect(LidOnboardingStore.shouldShow(other))
    }

    @Test("the splash is centred on the current screen and lands as a small card centred on the icon")
    func geometry() {
        let size = NSSize(width: 320, height: 260)
        for screen in [NSRect(x: 0, y: 0, width: 1512, height: 944), NSRect(x: -1920, y: 200, width: 1920, height: 1050)] {
            let frame = LidOnboardingController.centred(size, on: screen)
            #expect(screen.contains(frame) && abs(frame.midX - screen.midX) <= 1 && abs(frame.midY - screen.midY) <= 1)
            let icon = NSRect(x: screen.maxX - 300, y: screen.maxY + 4, width: 24, height: 22)
            let landing = LidOnboardingController.landing(for: frame, icon: icon)
            #expect(abs(landing.midX - icon.midX) < 0.5 && abs(landing.midY - icon.midY) < 1)
            #expect(landing.width <= 30 && abs(landing.width / landing.height - frame.width / frame.height) < 0.1)
        }
    }

    @Test("a returning user gets the launch animation; duplicate reopen does not skip it")
    func repeatLaunch() throws {
        _ = NSApplication.shared
        let store = try defaults()
        LidOnboardingStore.markShown(store)
        let model = LidModeModel(system: .init(
            serviceState: { .notRegistered }, register: {}, openLoginItems: {}, call: { _ in nil }
        ))
        let menu = LidModeMenuBar(model: model, defaults: store, logo: try #require(logo))
        menu.showBrandSplash()
        let first = try #require(menu.splash)
        defer { menu.splash?.dismissNow() }
        #expect(first.isVisible && !first.explains && first.state.stage == .intro)
        menu.showBrandSplash()
        #expect(menu.splash === first && first.state.stage == .intro && first.state.zip == 0)
        first.dismissNow()
        #expect(menu.splash == nil)
        menu.showBrandSplash()
        let next = try #require(menu.splash)
        #expect(next !== first && next.isVisible && next.state.stage == .intro)
    }

    @Test("pull and restored lips come from the approved logo; at rest they rebuild it, and the pull really travels")
    func zipperParts() throws {
        _ = NSApplication.shared
        let logo = try #require(logo)
        let parts = try #require(LidZipperParts.extract(logo, size: 512))
        #expect(parts.startLeft < 0.1)                        // first tooth, left side
        #expect(parts.restLeft > 0.74 && parts.restLeft < 0.82) // the pull's place in the logo
        #expect(parts.restLeft - parts.startLeft > 0.6)       // a real journey
        #expect(parts.bodyWidth > 0.04 && parts.bodyWidth < 0.15)
        #expect(parts.trackEnd > parts.restLeft && parts.trackEnd < 1)
        #expect(parts.teethCover.width == parts.base.width)
        #expect(parts.pullLeft(at: 0) == parts.startLeft && parts.pullLeft(at: 1) == parts.restLeft)
        // Compose base + sprite at rest and compare with the logo.
        func pixels(_ draw: (CGContext) -> Void) -> [UInt8] {
            let ctx = CGContext(data: nil, width: 512, height: 512, bitsPerComponent: 8, bytesPerRow: 2048,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            draw(ctx)
            return Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: 512 * 512 * 4))
        }
        let rect = CGRect(x: 0, y: 0, width: 512, height: 512)
        let original = pixels { $0.draw(parts.whole, in: rect) }
        let rebuilt = pixels { $0.draw(parts.base, in: rect); $0.draw(parts.sprite, in: rect) }
        let base = pixels { $0.draw(parts.base, in: rect) }
        var close = 0, changed = 0
        for i in stride(from: 0, to: original.count, by: 4) {
            if (0..<3).allSatisfy({ abs(Int(original[i + $0]) - Int(rebuilt[i + $0])) < 40 }) { close += 1 }
            if (0..<3).contains(where: { abs(Int(original[i + $0]) - Int(base[i + $0])) > 60 }) { changed += 1 }
        }
        #expect(Double(close) / Double(512 * 512) > 0.995)    // only the anti-aliased rim may differ
        #expect(changed > 3000)                                // the pull is really gone from the base
    }

    @Test("the artwork's square background is transparent; outline, mouth, teeth and pull stay opaque")
    func transparentArtwork() throws {
        _ = NSApplication.shared
        let logo = try #require(logo)
        let parts = try #require(LidZipperParts.extract(logo, size: 512))
        let ctx = CGContext(data: nil, width: 512, height: 512, bitsPerComponent: 8, bytesPerRow: 2048,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(parts.whole, in: CGRect(x: 0, y: 0, width: 512, height: 512))
        let px = UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: 512 * 512 * 4)
        // Buffer row 0 is the top of the image; sample by fractions of the artwork.
        func alpha(_ x: CGFloat, _ y: CGFloat) -> UInt8 { px[(Int(y * 511) * 512 + Int(x * 511)) * 4 + 3] }
        func rgb(_ x: CGFloat, _ y: CGFloat) -> (UInt8, UInt8, UInt8) { let i = (Int(y * 511) * 512 + Int(x * 511)) * 4; return (px[i], px[i + 1], px[i + 2]) }
        for corner in [(0.01, 0.01), (0.99, 0.01), (0.01, 0.99), (0.99, 0.99), (0.5, 0.05), (0.5, 0.95)] as [(CGFloat, CGFloat)] {
            #expect(alpha(corner.0, corner.1) == 0, "\(corner)")
        }
        #expect(alpha(0.3, 0.3) == 255 && rgb(0.3, 0.3).0 > 200)          // red upper lip
        #expect(alpha(0.5, 0.465) == 255)                                 // mouth / teeth row
        #expect(alpha(0.86, 0.66) == 255 && rgb(0.86, 0.66).1 > 180)      // cream laptop pull
        // The black outline survives: scanning in from the left at mid-height, the first opaque pixel is dark.
        let row = 0.47 as CGFloat
        let first = stride(from: 0.0 as CGFloat, to: 0.3, by: 1 / 511).first { alpha($0, row) > 200 }
        #expect(first != nil && rgb(first!, row).0 < 60)
        // Same for the base layer used while the pull travels.
        ctx.clear(CGRect(x: 0, y: 0, width: 512, height: 512))
        ctx.draw(parts.base, in: CGRect(x: 0, y: 0, width: 512, height: 512))
        #expect(alpha(0.99, 0.99) == 0 && alpha(0.01, 0.01) == 0 && alpha(0.3, 0.3) == 255)
    }

    @Test("skip jumps to the zipped, ready state with «Shut Your Lip»")
    func skip() {
        let state = LidOnboardingState(reduced: false)
        state.play()
        state.skip()
        #expect(state.stage == .ready && state.zip == 1 && !state.pucker && state.wordmark && state.isLip)
    }

    @Test("marker lettering: the «d» turned about its oval lands exactly on the separate «p», clear of the «i»")
    func letterBecomesP() {
        let g = LidWordmark.geometry
        func mask(_ path: CGPath) -> [Bool] {
            let w = Int(g.size.width) + 20, h = Int(g.size.height) + 20
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
            ctx.translateBy(x: 10, y: 10); ctx.setFillColor(gray: 1, alpha: 1); ctx.addPath(path); ctx.fillPath(using: .evenOdd)
            return UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: w * h).map { $0 > 127 }
        }
        // The animation's end transform: turn 180° about the oval, then the landing shift.
        var turn = CGAffineTransform(translationX: g.bowlCenter.x + g.landingShift, y: g.bowlCenter.y)
            .rotated(by: .pi).translatedBy(x: -g.bowlCenter.x, y: -g.bowlCenter.y)
        let landed = g.d.cgPath.copy(using: &turn)!
        let a = mask(landed), b = mask(g.p.cgPath)
        let inter = zip(a, b).filter { $0 && $1 }.count, union = zip(a, b).filter { $0 || $1 }.count
        #expect(Double(inter) / Double(union) > 0.97)           // same shape: a seamless hand-over
        #expect(!zip(mask(g.p.cgPath), mask(g.stem.cgPath)).contains { $0 && $1 })   // never touches the «i»
        // «d» rises above the oval, «p» hangs below it; both stay inside the frame.
        #expect(g.d.boundingRect.minY < g.bowlCenter.y - 20 && g.p.boundingRect.maxY > g.bowlCenter.y + 20)
        #expect(g.p.boundingRect.maxY <= g.size.height && g.p.boundingRect.maxX <= g.size.width)
        #expect(g.size.width > 280 && g.size.width < 380)
        // Pivot is inside the «d»'s counter (the centre of its oval), not on the stroke.
        #expect(g.d.boundingRect.contains(g.bowlCenter) && !g.d.contains(g.bowlCenter, eoFill: true))
    }

    @Test("interface language follows macOS: Russian first → RU, any other language → English; brand stays English")
    func languages() {
        #expect(LidLanguage.resolve(["ru-RU", "en-US"]) == .ru)
        #expect(LidLanguage.resolve(["ru"]) == .ru)
        #expect(LidLanguage.resolve(["en-GB"]) == .en)
        #expect(LidLanguage.resolve(["de-DE", "ru-RU"]) == .en)
        #expect(LidLanguage.resolve(["ja"]) == .en)
        #expect(LidLanguage.resolve([]) == .en)
        for key in ["onboarding.message", "onboarding.hint", "onboarding.done"] {
            #expect(lidString(key, language: .ru) != lidString(key, language: .en))
        }
        for table in [lidStringsRU, lidStringsEN] {
            #expect(!table.values.contains { $0.contains("Shut Your Lip") })   // the pun lives only in the wordmark
        }
    }

    @Test("the intro is about two seconds (reduced motion about half a second) and ends zipped and ready")
    func timeline() async throws {
        #expect(LidOnboardingState.total(LidOnboardingState.fullBeats) >= .milliseconds(2200))
        #expect(LidOnboardingState.total(LidOnboardingState.fullBeats) <= .milliseconds(3000))
        #expect(LidOnboardingState.total(LidOnboardingState.reducedBeats) <= .milliseconds(1000))
        for reduced in [true, false] {
            let state = LidOnboardingState(reduced: reduced)
            state.play()
            #expect(state.stage == .intro)
            // Generous bound: the MainActor is shared with parallel UI tests.
            let deadline = ContinuousClock.now + .seconds(15)
            while state.stage != .ready, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
            #expect(state.stage == .ready && state.zip == 1 && !state.pucker && !state.landing)
            #expect(state.kissed == !reduced && state.wordmark && state.isLip && state.letterSettled == !reduced || reduced)
            // Reduce Motion: no turn or fall, only the cross-fade.
            #expect(reduced ? state.letterTurn == 0 && state.letterFade == 1 : state.letterTurn == 180)
        }
    }

    @Test("the card keeps one size while it plays; the short splash has no text and is smaller")
    func stableCard() throws {
        _ = NSApplication.shared
        #expect(logo != nil)
        let parts = logo.flatMap { LidZipperParts.extract($0, size: 512) }
        let state = LidOnboardingState(reduced: false, explains: true)
        let start = fitted(view(state, parts: parts)).fittingSize
        state.pucker = true; state.zip = 0.5; state.letterTurn = 120
        let middle = fitted(view(state, parts: parts)).fittingSize
        state.skip()
        let ready = fitted(view(state, parts: parts)).fittingSize
        #expect(start == middle && middle == ready && ready.width == LidOnboardingView.width)
        #expect(ready.height > 400 && ready.height < 760)
        #expect(fitted(view(state, parts: parts, iconVisible: false)).fittingSize.width == ready.width)
        let short = LidOnboardingState(reduced: false, explains: false)
        let shortStart = fitted(view(short, parts: parts)).fittingSize
        short.skip()
        let shortEnd = fitted(view(short, parts: parts)).fittingSize
        #expect(shortStart == shortEnd && shortEnd.height < ready.height - 80)
        for key in ["onboarding.message", "onboarding.hint", "onboarding.hidden", "onboarding.done", "onboarding.skip", "onboarding.logo"] {
            #expect(!(lidStringsRU[key] ?? "").isEmpty && !(lidStringsEN[key] ?? "").isEmpty, "\(key)")
        }
        #expect(lidStringsRU["onboarding.openMenu"] == nil)   // the splash never opens the panel
    }

    @Test("the short splash finishes by itself; the first-run card waits for «Готово»")
    func endings() async throws {
        for explains in [false, true] {
            let state = LidOnboardingState(reduced: true, explains: explains)
            var played = false
            state.onPlayed = { played = true }
            state.play()
            let deadline = ContinuousClock.now + .seconds(15)
            while !played, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
            #expect(played && state.stage == .ready && state.zipped)
        }
    }

    /// Key frames and a flight diagram: LID_PREVIEW_DIR=/some/dir swift test --filter onboardingPreviews
    @Test("onboarding preview renders when requested")
    func onboardingPreviews() throws {
        guard let folder = ProcessInfo.processInfo.environment["LID_PREVIEW_DIR"] else { return }
        _ = NSApplication.shared
        let parts = logo.flatMap { LidZipperParts.extract($0, size: 1024) }
        func render(_ v: LidOnboardingView, backdrop color: NSColor = NSColor(white: 0.55, alpha: 1)) -> NSBitmapImageRep? {
            let host = fitted(v)
            let backdrop = NSView(frame: NSRect(x: 0, y: 0, width: host.frame.width + 40, height: host.frame.height + 40))
            backdrop.wantsLayer = true
            backdrop.layer?.backgroundColor = color.cgColor
            host.frame.origin = NSPoint(x: 20, y: 20)
            backdrop.addSubview(host)
            backdrop.layoutSubtreeIfNeeded()
            guard let bitmap = backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds) else { return nil }
            backdrop.cacheDisplay(in: backdrop.bounds, to: bitmap)
            return bitmap
        }
        let frames: [(String, Bool, Bool, (LidOnboardingState) -> Void)] = [
            ("01 open, pull at first tooth", false, false, { _ in }),
            ("02 kiss + wordmark", false, false, { $0.pucker = true; $0.wordmark = true }),
            ("03 pull travels 35%", false, false, { $0.wordmark = true; $0.zip = 0.35 }),
            ("04 pull travels 70%", false, false, { $0.wordmark = true; $0.zip = 0.7 }),
            ("05 pull lands, logo", false, false, { $0.wordmark = true; $0.zip = 1; $0.zipped = true }),
            ("06 d falls 130°", false, false, { $0.wordmark = true; $0.zip = 1; $0.zipped = true; $0.letterTurn = 130 }),
            ("07 Lip (short splash end)", false, false, { $0.skip() }),
            ("08 first run: hint + Готово", true, false, { $0.skip() }),
            ("09 first run, icon hidden", true, false, { $0.skip() }),
            ("10 reduced motion", false, true, { $0.wordmark = true; $0.zip = 0.5; $0.letterFade = 0.5 }),
        ]
        var images: [(String, NSBitmapImageRep)] = []
        let desktops: [NSColor] = [NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.96, alpha: 1), NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.22, alpha: 1)]
        for (index, (name, explains, reduced, configure)) in frames.enumerated() {
            let state = LidOnboardingState(reduced: reduced, explains: explains)
            configure(state)
            // Alternate light and dark desktops; the window itself is transparent.
            guard let bitmap = render(view(state, parts: parts, iconVisible: !name.contains("hidden")), backdrop: desktops[index % 2]) else { continue }
            images.append((name + (index % 2 == 0 ? " · light" : " · dark"), bitmap))
            let file = "splash-" + name.prefix(2) + ".png"
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: folder).appendingPathComponent(String(file)))
        }
        // The window content alone, with real transparency (alpha PNG).
        let lipEnd = LidOnboardingState(reduced: false, explains: false); lipEnd.skip()
        let alphaHost = fitted(view(lipEnd, parts: parts))
        if let bitmap = alphaHost.bitmapImageRepForCachingDisplay(in: alphaHost.bounds) {
            alphaHost.cacheDisplay(in: alphaHost.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: folder).appendingPathComponent("splash-transparent.png"))
        }
        // Flight diagram: a mock 1440×900 screen with the menu bar icon; the card
        // at the centre, then at 35/65/90% of the flight (frame and alpha as in code).
        let short = LidOnboardingState(reduced: false, explains: false); short.skip()
        for (desktopName, desktop, menuBar) in [("light", NSColor(calibratedRed: 0.86, green: 0.89, blue: 0.93, alpha: 1), NSColor(white: 0.97, alpha: 0.92)),
                                                ("dark", NSColor(calibratedRed: 0.14, green: 0.17, blue: 0.24, alpha: 1), NSColor(white: 0.12, alpha: 0.9))] {
        if let card = render(view(short, parts: parts), backdrop: .clear) {
            let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
            let icon = NSRect(x: 1180, y: 900 - 24 + 1, width: 24, height: 22)
            let start = LidOnboardingController.centred(NSSize(width: card.size.width - 40, height: card.size.height - 40), on: NSRect(x: 0, y: 0, width: 1440, height: 876))
            let end = LidOnboardingController.landing(for: start, icon: icon)
            let sheet = NSImage(size: screen.size)
            sheet.lockFocus()
            desktop.setFill(); screen.fill()
            menuBar.setFill(); NSRect(x: 0, y: 876, width: 1440, height: 24).fill()
            NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 15, weight: .regular))?
                .tinted(desktopName == "light" ? .black : .white).draw(in: icon.insetBy(dx: 2, dy: 3))
            func ease(_ t: CGFloat) -> CGFloat { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
            for t in [0.0, 0.35, 0.65, 0.9] as [CGFloat] {
                let e = ease(t)
                let frame = NSRect(x: start.minX + (end.minX - start.minX) * e, y: start.minY + (end.minY - start.minY) * e,
                                   width: start.width + (end.width - start.width) * e, height: start.height + (end.height - start.height) * e)
                let fade = t < 0.45 ? 1 : max(0, 1 - pow((t - 0.45) / 0.55, 2))
                card.draw(in: frame, from: NSRect(x: 20, y: 20, width: card.size.width - 40, height: card.size.height - 40),
                          operation: .sourceOver, fraction: fade, respectFlipped: false, hints: nil)
            }
            ("flight: centre → icon, shrinking and dissolving (t = 0, .35, .65, .9)" as NSString)
                .draw(at: NSPoint(x: 24, y: 24), withAttributes: [.font: NSFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: desktopName == "light" ? NSColor.black : NSColor.white])
            sheet.unlockFocus()
            if let tiff = sheet.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: folder).appendingPathComponent("splash-flight-\(desktopName).png"))
            }
        }
        }
        // Contact sheet of the key frames.
        guard let first = images.first?.1 else { return }
        let cellW = first.size.width, cellH = images.map { $0.1.size.height }.max()! + 28, columns = 5
        let rows = (images.count + columns - 1) / columns
        let sheet = NSImage(size: NSSize(width: cellW * CGFloat(columns), height: cellH * CGFloat(rows)))
        sheet.lockFocus()
        NSColor(white: 0.55, alpha: 1).setFill(); NSRect(origin: .zero, size: sheet.size).fill()
        for (i, (name, bitmap)) in images.enumerated() {
            let x = CGFloat(i % columns) * cellW, top = sheet.size.height - CGFloat(i / columns) * cellH
            bitmap.draw(in: NSRect(x: x, y: top - bitmap.size.height, width: bitmap.size.width, height: bitmap.size.height))
            (name as NSString).draw(at: NSPoint(x: x + 22, y: top - cellH + 6), withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.black])
        }
        sheet.unlockFocus()
        if let tiff = sheet.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: folder).appendingPathComponent("splash-sheet.png"))
        }
    }
}

private extension NSImage {
    func tinted(_ color: NSColor) -> NSImage {
        let image = copy() as! NSImage
        image.lockFocus(); color.set(); NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop); image.unlockFocus()
        return image
    }
}
