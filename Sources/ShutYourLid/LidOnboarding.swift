import AppKit
import CoreText
import LidModeFeature
import Observation
import SwiftUI

/// Brand splash on launch and on Dock reopen: the approved lips blow a kiss, the
/// zipper pull travels and zips the mouth, «Shut Your Lid» becomes «Shut Your
/// Lip», then the card flies into the real menu bar icon. The first time on a
/// profile it also explains where the controls are (a local UserDefaults flag).
/// It never touches the mode, the helper or any permission.
enum LidOnboardingStore {
    /// Absent on fresh installs and on installs updated from earlier versions.
    static let key = "onboarding.introShown.v1"
    static func shouldShow(_ defaults: UserDefaults) -> Bool { !defaults.bool(forKey: key) }
    static func markShown(_ defaults: UserDefaults) { defaults.set(true, forKey: key) }
}

/// Brand colors sampled from App/Assets/LogoDark.png. The artwork has no
/// color profile, so macOS draws its pixels in device RGB; the card and the
/// button use device RGB with the same raw values to match it on any display.
enum LidBrand {
    /// The logo's solid background, so the artwork blends into the card.
    static let graphite = device(0x18, 0x18, 0x1B)
    static let lipRed = device(0xF0, 0x22, 0x1C)

    static func device(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(nsColor: NSColor(deviceRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1))
    }

    /// The card color from the artwork's own corner pixel (raw components).
    @MainActor static func background(for logo: NSImage?) -> Color {
        guard let logo, let cgImage = logo.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return graphite }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard bitmap.samplesPerPixel >= 3, bitmap.bitsPerSample == 8 else { return graphite }
        var pixel = [Int](repeating: 0, count: bitmap.samplesPerPixel)
        bitmap.getPixel(&pixel, atX: 4, y: 4)
        return device(pixel[0], pixel[1], pixel[2])
    }

    /// The owner-selected logo, packaged by the build as the app icon file.
    @MainActor static func logo(bundle: Bundle = .main) -> NSImage? {
        bundle.url(forResource: "ShutYourLidLips", withExtension: "icns").flatMap(NSImage.init(contentsOf:))
    }
}

/// The splash timeline. Values are plain state so previews and tests can render
/// any frame; `play()` drives them with SwiftUI animations.
@MainActor @Observable final class LidOnboardingState {
    enum Stage: Equatable { case intro, ready }
    var stage: Stage = .intro
    /// Lips puckered for the kiss.
    var pucker = false
    /// Kiss hearts released (they rise and fade once).
    var kissed = false
    /// 0 = mouth open, pull at the first tooth; 1 = pull at rest, zipped.
    var zip: CGFloat = 0
    /// The pull has landed: the untouched artwork is shown again.
    var zipped = false
    /// «Shut Your Lid» wordmark shown.
    var wordmark = false
    /// Turn of the final «d» about its bowl, in degrees; 180 = it has become «p».
    var letterTurn: Double = 0
    /// Brief settle as the letter lands (a 1–2 pt dip, then rest).
    var landing = false
    /// The «d» has landed: the separate «p» outline is shown in its place.
    var letterSettled = false
    /// Reduce Motion: «d» cross-fades to «p» in place (0…1), no turn or fall.
    var letterFade: Double = 0
    /// The playful ending «Shut Your Lip» has been reached.
    var isLip: Bool { reduced ? letterFade >= 0.5 : letterTurn >= 90 }
    /// Reduce Motion or VoiceOver: opacity only, no travel, turn or flight.
    let reduced: Bool
    /// First run on this profile: explain where the controls are and wait for «Готово».
    let explains: Bool
    @ObservationIgnored private var timeline: Task<Void, Never>?
    /// Called once the animation has reached its end state (not after `skip()`).
    @ObservationIgnored var onPlayed: (() -> Void)?

    init(reduced: Bool, explains: Bool = true) {
        self.reduced = reduced
        self.explains = explains
    }

    /// Pauses before each beat, in milliseconds:
    /// kiss in (wordmark appears), kiss out, zip, d falls, d lands, end.
    static let fullBeats = [250, 330, 420, 800, 420, 450]
    /// Reduce Motion: zip and wordmark fade, d→p cross-fade, end.
    static let reducedBeats = [150, 350, 400]
    static func total(_ beats: [Int]) -> Duration { .milliseconds(beats.reduce(0, +)) }

    static var systemPrefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || NSWorkspace.shared.isVoiceOverEnabled
    }

    func play() {
        timeline?.cancel()
        timeline = Task { [weak self] in
            guard let self else { return }
            do {
                if reduced {
                    let beats = Self.reducedBeats
                    try await Task.sleep(for: .milliseconds(beats[0]))
                    withAnimation(.easeOut(duration: 0.3)) { self.zip = 1; self.zipped = true; self.wordmark = true }
                    try await Task.sleep(for: .milliseconds(beats[1]))
                    withAnimation(.easeOut(duration: 0.3)) { self.letterFade = 1 }
                    try await Task.sleep(for: .milliseconds(beats[2]))
                    self.finishPlaying()
                    return
                }
                let beats = Self.fullBeats
                try await Task.sleep(for: .milliseconds(beats[0]))
                withAnimation(.spring(duration: 0.35, bounce: 0.3)) { self.pucker = true }
                withAnimation(.easeOut(duration: 0.4)) { self.wordmark = true }
                self.kissed = true
                try await Task.sleep(for: .milliseconds(beats[1]))
                withAnimation(.spring(duration: 0.45, bounce: 0.35)) { self.pucker = false }
                try await Task.sleep(for: .milliseconds(beats[2]))
                // The pull travels along the teeth: on-screen movement, strong ease-in-out.
                withAnimation(.timingCurve(0.77, 0, 0.175, 1, duration: 0.75)) { self.zip = 1 }
                try await Task.sleep(for: .milliseconds(beats[3]))
                withAnimation(.easeOut(duration: 0.12)) { self.zipped = true }
                // The «d» tips over about its bowl and falls: gravity accelerates,
                // so this one beat eases in; it overshoots a little past «p»…
                withAnimation(.timingCurve(0.55, 0, 0.85, 0.45, duration: 0.4)) { self.letterTurn = 194 }
                try await Task.sleep(for: .milliseconds(beats[4]))
                // …and lands: a small dip and a spring back to rest as «p».
                withAnimation(.spring(duration: 0.35, bounce: 0.35)) { self.letterTurn = 180; self.landing = true }
                withAnimation(.spring(duration: 0.4, bounce: 0.3).delay(0.08)) { self.landing = false }
                try await Task.sleep(for: .milliseconds(beats[5]))
                self.letterSettled = true
                self.finishPlaying()
            } catch {}
        }
    }

    private func finishPlaying() {
        if explains { withAnimation(LidMotion.curve) { stage = .ready } } else { stage = .ready }
        onPlayed?()
    }

    /// Jump to the end state at once (Skip, Escape, a click or a second Dock click).
    func skip() {
        timeline?.cancel()
        timeline = nil
        pucker = false
        landing = false
        zip = 1
        zipped = true
        wordmark = true
        letterTurn = 180
        letterFade = 1
        letterSettled = true
        withAnimation(.easeOut(duration: 0.15)) { stage = .ready }
    }
}

/// The splash card. First run: logo, wordmark, where the controls are, «Готово».
/// Later launches: logo and wordmark only. Its size never changes while it plays.
struct LidOnboardingView: View {
    let state: LidOnboardingState
    let logo: NSImage?
    /// Pull sprite and restored lips derived from the logo (nil: zip by fading only).
    var parts: LidZipperParts? = nil
    /// The live status item image, so the card shows exactly what is in the menu bar.
    let icon: NSImage?
    /// The menu bar icon is visible on this screen (else the hint says how to reveal it).
    let iconVisible: Bool
    let onSkip: () -> Void
    let onDone: () -> Void
    /// Precomputed card color (see `LidBrand.background(for:)`).
    var cardColor: Color? = nil

    /// Window width: the 1.5× lips plus room for the pucker; everything outside
    /// the lips, the wordmark and the first-run note is transparent.
    static let width: CGFloat = 400
    static let spacing: CGFloat = 14

    /// Height of the text block; during the intro the logo sits centred over
    /// it and settles upward when the text appears (a transform, not a resize).
    @State private var detailsHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: Self.spacing) {
            VStack(spacing: 10) {
                if let logo {
                    LidKissZipLogo(state: state, logo: logo, parts: parts)
                        .accessibilityElement()
                        .accessibilityLabel(loc("onboarding.logo"))
                        .accessibilityAddTraits(.isImage)
                }
                LidWordmark(state: state)
            }
            .offset(y: state.explains && state.stage == .intro ? (detailsHeight + Self.spacing) / 2 : 0)
            .zIndex(1)
            if state.explains {
                ZStack(alignment: .bottom) {
                    // Both layers are always laid out, so the card never changes size.
                    details
                        .opacity(state.stage == .ready ? 1 : 0)
                        .offset(y: state.stage == .ready || state.reduced ? 0 : 6)
                        .allowsHitTesting(state.stage == .ready)
                        .accessibilityHidden(state.stage != .ready)
                    Button(loc("onboarding.skip"), action: onSkip)
                        .buttonStyle(.plain)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(LidBrand.graphite.opacity(0.85)))
                        .padding(.bottom, 6)
                        .opacity(state.stage == .intro ? 1 : 0)
                        .allowsHitTesting(state.stage == .intro)
                        .accessibilityHidden(state.stage != .intro)
                }
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: LidDetailsHeightKey.self, value: proxy.size.height)
                })
                .onPreferenceChange(LidDetailsHeightKey.self) { detailsHeight = $0 }
            }
        }
        .padding(.vertical, 8)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.colorScheme, .dark)
        .contentShape(Rectangle())
        .onTapGesture { if !state.explains { onSkip() } }
        .onChange(of: state.stage) { _, stage in
            if stage == .ready, state.explains { AccessibilityNotification.Announcement(loc("onboarding.message")).post() }
        }
    }

    private var details: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                if let icon {
                    Image(nsImage: icon)
                        .renderingMode(.template)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                        .accessibilityLabel(loc("onboarding.icon"))
                }
                Text(loc("onboarding.message"))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(loc(iconVisible ? "onboarding.hint" : "onboarding.hidden"))
                .font(.callout)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onDone) { Text(loc("onboarding.done")).frame(maxWidth: .infinity) }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(LidBrand.lipRed)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 4)
        }
        // A compact note of its own, below the wordmark; the lips stay frameless.
        .padding(16)
        .frame(width: 320)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(cardColor ?? LidBrand.graphite))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}

private struct LidDetailsHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// «Shut Your Lid» in the owner-approved marker lettering (see
/// `LidWordmarkArt`): «Shut Your Li», the «d» and the «p» are separate outlines.
/// The «d» turns about the centre of its oval and falls; once it has landed the
/// separate «p» (the same shape) takes over. Brand text, English in every language.
struct LidWordmark: View {
    let state: LidOnboardingState
    static let geometry = LidWordmarkGeometry(width: 320)

    var body: some View {
        let g = Self.geometry
        let anchor = UnitPoint(x: g.bowlCenter.x / g.size.width, y: g.bowlCenter.y / g.size.height)
        ZStack(alignment: .topLeading) {
            LidStickerText(path: g.stem)
            if state.reduced {
                // No turn or fall: «d» fades into «p» in place.
                LidStickerText(path: g.d).opacity(1 - state.letterFade)
                LidStickerText(path: g.p).opacity(state.letterFade)
            } else {
                LidStickerText(path: g.d)
                    .rotationEffect(.degrees(state.letterTurn), anchor: anchor)
                    .offset(x: g.landingShift * min(max(state.letterTurn / 180, 0), 1), y: state.landing ? 3 : 0)
                    .opacity(state.letterSettled ? 0 : 1)
                LidStickerText(path: g.p)
                    .offset(y: state.landing ? 3 : 0)
                    .opacity(state.letterSettled ? 1 : 0)
            }
        }
        .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
        // Centre the lettering itself; the room kept for the «d»'s swing stays to the right.
        .offset(x: g.centring)
        .opacity(state.wordmark ? 1 : 0)
        .offset(y: state.wordmark || state.reduced ? 0 : 6)
        .accessibilityElement()
        .accessibilityLabel(state.isLip ? "Shut Your Lip" : "Shut Your Lid")
        .accessibilityAddTraits(.isHeader)
    }
}

/// White marker letters with a black outline, readable on light and dark desktops.
struct LidStickerText: View {
    let path: Path
    var body: some View {
        ZStack(alignment: .topLeading) {
            LidPathShape(path: path).stroke(Color.black, style: StrokeStyle(lineWidth: 3.5, lineJoin: .round))
            LidPathShape(path: path).fill(.white, style: FillStyle(eoFill: true))
        }
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
    }
}

struct LidPathShape: Shape {
    let path: Path
    func path(in rect: CGRect) -> Path { path }
}

/// The lettering scaled to points, in a top-left (y-down) frame with room for
/// the outline, the «d»'s swing to the right and the «p»'s descender.
struct LidWordmarkGeometry {
    let size: CGSize
    /// «Shut Your Li»
    let stem: Path
    /// The final «d» and the «p» it becomes.
    let d: Path
    let p: Path
    /// Centre of the «d»'s oval: the rotation pivot.
    let bowlCenter: CGPoint
    /// Horizontal move, applied as the «d» turns, that lands it on the «p».
    let landingShift: CGFloat
    /// Offset that centres the visible lettering within `size`.
    var centring: CGFloat { (size.width - max(stem.boundingRect.maxX, p.boundingRect.maxX) - stem.boundingRect.minX) / 2 }

    init(width: CGFloat) {
        let art = LidWordmarkArt.self
        let scale = width / art.size.width
        let pad: CGFloat = 4
        var place = CGAffineTransform(translationX: pad, y: pad)
        stem = Path(art.path(art.stem, scale: scale).copy(using: &place)!)
        d = Path(art.path(art.d, scale: scale).copy(using: &place)!)
        p = Path(art.path(art.p, scale: scale, dx: art.pShift).copy(using: &place)!)
        let pivot = CGPoint(x: art.bowl.x * scale + pad, y: art.bowl.y * scale + pad)
        let shift = art.pShift * scale
        bowlCenter = pivot
        landingShift = shift
        // While it turns, the «d» sweeps a circle about its oval: the frame
        // holds that circle (right and below) as well as the landed «p».
        let box = d.boundingRect   // d is set above
        let radius = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                      CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY)]
            .map { hypot($0.x - pivot.x, $0.y - pivot.y) }.max() ?? 0
        size = CGSize(width: (max(stem.boundingRect.maxX, p.boundingRect.maxX, pivot.x + radius + shift) + pad).rounded(.up),
                      height: (max(stem.boundingRect.maxY, p.boundingRect.maxY, pivot.y + radius) + pad).rounded(.up))
    }
}

/// The approved artwork. While the mouth zips, it is drawn as two layers
/// derived from it — the lips without the pull, and the pull itself — so the
/// pull really travels; once it lands, the untouched artwork is shown again.
struct LidKissZipLogo: View {
    let state: LidOnboardingState
    let logo: NSImage
    var parts: LidZipperParts? = nil

    /// Logo geometry, as fractions of the square artwork.
    static let lipsCenterY: CGFloat = 0.455
    static let teeth = CGRect(x: 0.052, y: 0.408, width: 0.745, height: 0.125)
    /// 1.5× the 0.3.7 size (250 pt).
    static let side: CGFloat = 375
    /// Lips span ~0.14…0.78 of the artwork; room above for the hearts and
    /// around for the pucker, so nothing is cut off.
    static let headroom: CGFloat = 150
    static let footroom: CGFloat = 140

    var body: some View {
        let side = Self.side
        ZStack {
            Group {
                if let parts, !state.reduced {
                    travellingPull(parts, side: side)
                } else {
                    artwork(parts?.whole).resizable().interpolation(.high)
                        .frame(width: side, height: side)
                        .overlay(alignment: .topLeading) {
                            if let parts {
                                Image(decorative: parts.teethCover, scale: 1).resizable().interpolation(.high)
                                    .opacity(state.zipped ? 0 : 1 - state.zip)
                            } else {
                                fadingBand(side: side)
                            }
                        }
                }
            }
            .scaleEffect(x: state.pucker ? 0.92 : 1, y: state.pucker ? 1.07 : 1,
                         anchor: UnitPoint(x: 0.5, y: Self.lipsCenterY))
            if !state.reduced {
                ForEach(0..<3, id: \.self) { index in
                    LidKissHeart(index: index, trigger: state.kissed)
                        .scaleEffect(1.5)
                        .offset(x: CGFloat(index - 1) * 39, y: (Self.lipsCenterY - 0.5) * side - 45)
                }
            }
        }
        // Lips centre sits `headroom` below the top; the square artwork may
        // extend past this frame, but only transparent pixels do.
        .frame(width: side, height: side)
        .offset(y: Self.headroom - Self.lipsCenterY * side)
        .frame(width: side, height: Self.headroom + Self.footroom, alignment: .top)
    }

    private func artwork(_ cutout: CGImage?) -> Image {
        cutout.map { Image(decorative: $0, scale: 1) } ?? Image(nsImage: logo)
    }

    /// Open track over the teeth from the pull to the corner of the mouth; the
    /// pull's left edge moves from the first tooth to its place in the logo.
    private func travellingPull(_ parts: LidZipperParts, side: CGFloat) -> some View {
        let left = parts.pullLeft(at: state.zip)
        let openFrom = left + parts.bodyWidth / 2
        return ZStack(alignment: .topLeading) {
            Image(decorative: parts.base, scale: 1).resizable().interpolation(.high)   // background already transparent
            // Teeth right of the pull are still apart: covered in the mouth's dark.
            Image(decorative: parts.teethCover, scale: 1).resizable().interpolation(.high)
                .mask(alignment: .topLeading) {
                    Rectangle().frame(width: max(0, 1 - openFrom) * side, height: side).offset(x: openFrom * side)
                }
            Image(decorative: parts.sprite, scale: 1).resizable().interpolation(.high)
                .offset(x: (left - parts.restLeft) * side)
            artwork(parts.whole).resizable().interpolation(.high)
                .opacity(state.zipped ? 1 : 0)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    /// Reduce Motion (or no derived layers): the open gap simply fades.
    private func fadingBand(side: CGFloat) -> some View {
        let rect = Self.teeth
        return RoundedRectangle(cornerRadius: rect.height * side / 2, style: .continuous)
            .fill(Color(white: 0.03))
            .frame(width: rect.width * side, height: rect.height * side)
            .offset(x: rect.minX * side, y: rect.minY * side)
            .opacity(state.zipped ? 0 : 1 - state.zip)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

/// Two layers derived from the approved logo at runtime (no new artwork):
/// the zipper pull with its outline, and the lips with the pull removed —
/// the hidden area is restored from the mirror image of the left half of the
/// lips (they are near-symmetric), highlights recoloured to lip red.
struct LidZipperParts: @unchecked Sendable {
    /// The approved artwork with its square background made transparent.
    let whole: CGImage
    /// The lips without the pull (background transparent).
    let base: CGImage
    /// The teeth alone, as a dark shape: laid over them it reads as an open
    /// mouth and never spills over the lips.
    let teethCover: CGImage
    let sprite: CGImage
    /// Left edge of the pull's body: at rest (in the logo) and at the first tooth.
    let restLeft: CGFloat
    let startLeft: CGFloat
    let bodyWidth: CGFloat
    /// Teeth row and the end of the open track (corner of the mouth), as fractions.
    let teethTop: CGFloat
    let teethHeight: CGFloat
    let trackEnd: CGFloat

    /// Makes the artwork's solid square background transparent: a flood fill
    /// from the edges over background-coloured pixels (the black outline is
    /// darker, so the fill stops there and never reaches the mouth), then the
    /// anti-aliased rim between background and outline gets partial alpha.
    static func clearBackground(_ rgba: inout [UInt8], size n: Int) {
        let bg = (Int(rgba[(4 * n + 4) * 4]), Int(rgba[(4 * n + 4) * 4 + 1]), Int(rgba[(4 * n + 4) * 4 + 2]))
        let bgLum = (bg.0 + bg.1 + bg.2) / 3, outlineLum = max(0, bgLum - 16)
        func isBackground(_ i: Int) -> Bool {
            abs(Int(rgba[i * 4]) - bg.0) <= 7 && abs(Int(rgba[i * 4 + 1]) - bg.1) <= 7 && abs(Int(rgba[i * 4 + 2]) - bg.2) <= 7
        }
        var filled = [Bool](repeating: false, count: n * n)
        var stack: [Int] = []
        for k in 0..<n { for i in [k, (n - 1) * n + k, k * n, k * n + n - 1] where !filled[i] && isBackground(i) { filled[i] = true; stack.append(i) } }
        while let i = stack.popLast() {
            let x = i % n, y = i / n
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < n, ny < n else { continue }
                let j = ny * n + nx
                if !filled[j], isBackground(j) { filled[j] = true; stack.append(j) }
            }
        }
        // Two-pixel rim next to the cleared area: dark pixels fade with their distance from the background tone.
        var rim = [Bool](repeating: false, count: n * n)
        for _ in 0..<2 {
            var next = rim
            for i in 0..<(n * n) where !filled[i] && !rim[i] {
                let x = i % n, y = i / n
                let touches = [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { dx, dy in
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < n, ny < n else { return false }
                    return filled[ny * n + nx] || rim[ny * n + nx]
                }
                if touches { next[i] = true }
            }
            rim = next
        }
        for i in 0..<(n * n) {
            if filled[i] { rgba[i * 4] = 0; rgba[i * 4 + 1] = 0; rgba[i * 4 + 2] = 0; rgba[i * 4 + 3] = 0; continue }
            guard rim[i] else { continue }
            let lum = (Int(rgba[i * 4]) + Int(rgba[i * 4 + 1]) + Int(rgba[i * 4 + 2])) / 3
            guard lum <= bgLum + 7 else { continue }   // red or cream edge: keep
            let alpha = min(255, max(0, (bgLum + 4 - lum) * 255 / max(1, bgLum + 4 - outlineLum)))
            // Premultiplied black at that alpha.
            rgba[i * 4] = 0; rgba[i * 4 + 1] = 0; rgba[i * 4 + 2] = 0; rgba[i * 4 + 3] = UInt8(alpha)
        }
    }

    func pullLeft(at progress: CGFloat) -> CGFloat {
        startLeft + (restLeft - startLeft) * min(max(progress, 0), 1)
    }

    @MainActor private static var cache: (ObjectIdentifier, LidZipperParts?)?

    @MainActor static func make(from logo: NSImage) -> LidZipperParts? {
        if let cache, cache.0 == ObjectIdentifier(logo) { return cache.1 }
        let parts = extract(logo, size: 1024)
        cache = (ObjectIdentifier(logo), parts)
        return parts
    }

    static func extract(_ logo: NSImage, size n: Int) -> LidZipperParts? {
        guard let source = logo.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: space, bitmapInfo: info) else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: n, height: n))
        guard let data = context.data else { return nil }
        // Row 0 of the buffer is the top of the image.
        let original = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: n * n * 4))
        func px(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * n + x) * 4
            return (Int(original[i]), Int(original[i + 1]), Int(original[i + 2]))
        }
        func cream(_ p: (Int, Int, Int)) -> Bool { p.0 > 190 && p.1 > 180 && p.2 > 160 }
        func dark(_ p: (Int, Int, Int)) -> Bool { p.0 < 70 && p.1 < 70 && p.2 < 70 }
        func reddish(_ p: (Int, Int, Int)) -> Bool { p.0 > 120 && p.1 < 110 && p.2 < 110 }
        let f = CGFloat(n)

        // Teeth row (cream in the middle of the mouth) and the first tooth.
        var teethRows: [Int] = []
        for y in Int(0.35 * f)..<Int(0.6 * f) where (Int(0.3 * f)..<Int(0.7 * f)).contains(where: { cream(px($0, y)) }) { teethRows.append(y) }
        guard let teethTopRow = teethRows.first, let teethBottomRow = teethRows.last else { return nil }
        var firstTooth = n
        for y in teethTopRow...teethBottomRow { for x in 0..<Int(0.3 * f) where cream(px(x, y)) { firstTooth = min(firstTooth, x); break } }

        // The pull: cream parts right of the last tooth or below the teeth, plus
        // its dark sticker outline.
        let x0 = Int(0.69 * f), y0 = Int(0.39 * f), y1 = Int(0.80 * f)
        let w = n - x0, h = y1 - y0
        var core = [Bool](repeating: false, count: w * h)
        for y in 0..<h { for x in 0..<w {
            let gx = x0 + x, gy = y0 + y
            let nx = CGFloat(gx) / f, ny = CGFloat(gy) / f
            if nx > 0.70, ny > 0.40, ny < 0.78, nx > 0.787 || ny > 0.545, cream(px(gx, gy)) { core[y * w + x] = true }
        } }
        func dilate(_ m: [Bool], _ r: Int) -> [Bool] {
            var rows = [Bool](repeating: false, count: m.count), out = rows
            for y in 0..<h { var last = -r - 1
                for x in 0..<w { if m[y * w + x] { last = x } ; if x - last <= r { rows[y * w + x] = true } }
                last = w + r + 1
                for x in stride(from: w - 1, through: 0, by: -1) { if m[y * w + x] { last = x }; if last - x <= r { rows[y * w + x] = true } } }
            for x in 0..<w { var last = -r - 1
                for y in 0..<h { if rows[y * w + x] { last = y }; if y - last <= r { out[y * w + x] = true } }
                last = h + r + 1
                for y in stride(from: h - 1, through: 0, by: -1) { if rows[y * w + x] { last = y }; if last - y <= r { out[y * w + x] = true } } }
            return out
        }
        let halo = dilate(core, Int((15 * f / 1254).rounded()))
        var mask = core
        for y in 0..<h { for x in 0..<w where halo[y * w + x] {
            let p = px(x0 + x, y0 + y)
            if dark(p) || cream(p) { mask[y * w + x] = true }
        } }
        mask = dilate(mask, 2)

        // Mirror axis of the lips from the red silhouette.
        var minRed = n, maxRed = 0
        for y in stride(from: Int(0.25 * f), to: Int(0.7 * f), by: 4) { for x in 0..<n where reddish(px(x, y)) { minRed = min(minRed, x); maxRed = max(maxRed, x) } }
        guard maxRed > minRed else { return nil }
        let axis2 = minRed + maxRed   // mirrored x = axis2 - x

        var base = original, sprite = [UInt8](repeating: 0, count: n * n * 4)
        var bodyMin = n, bodyMax = 0, trackEnd = 0
        for y in 0..<h { for x in 0..<w where mask[y * w + x] {
            let gx = x0 + x, gy = y0 + y, i = (gy * n + gx) * 4
            let p = px(gx, gy)
            if !reddish(p) { for c in 0..<4 { sprite[i + c] = original[i + c] } }
            if core[y * w + x], CGFloat(gy) / f < 0.545 { bodyMin = min(bodyMin, gx); bodyMax = max(bodyMax, gx) }
            let mx = min(max(axis2 - gx, 0), n - 1)
            var m = px(mx, gy)
            if CGFloat(gy) / f > 0.55, max(m.0, m.1, m.2) > 90 { m = (251, 26, 23) }
            base[i] = UInt8(m.0); base[i + 1] = UInt8(m.1); base[i + 2] = UInt8(m.2); base[i + 3] = 255
        } }
        for y in teethTopRow...teethBottomRow { for x in stride(from: n - 1, to: Int(0.6 * f), by: -1) {
            let i = (y * n + x) * 4
            if base[i] > 190, base[i + 1] > 180, base[i + 2] > 160 { trackEnd = max(trackEnd, x); break }
        } }
        guard bodyMax > bodyMin, firstTooth < n else { return nil }

        func image(_ bytes: [UInt8]) -> CGImage? {
            var copy = bytes
            return copy.withUnsafeMutableBytes { raw in
                CGContext(data: raw.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: space, bitmapInfo: info)?.makeImage()
            }
        }
        // The logo has no teeth right of the pull's resting place; the mirror
        // brought some there. Return that part of the slot to the mouth's dark.
        for y in max(0, teethTopRow - 8)...min(n - 1, teethBottomRow + 8) { for x in bodyMax..<n {
            let i = (y * n + x) * 4
            let r = Int(base[i]), g = Int(base[i + 1]), b = Int(base[i + 2])
            if (r + g + b) / 3 > 40, !(r > 120 && g < 110 && b < 110), r - g < 60 { base[i] = 8; base[i + 1] = 8; base[i + 2] = 8 }
        } }
        // The open slot: per column, from the top to the bottom tooth (light,
        // not red) in the lips-without-pull layer, one pixel more each way —
        // but never over red, so it stays inside the mouth outline.
        var cover = [UInt8](repeating: 0, count: n * n * 4)
        let rowsFrom = max(0, teethTopRow - 6), rowsTo = min(n - 1, teethBottomRow + 6)
        func isRed(_ i: Int) -> Bool { base[i] > 120 && base[i + 1] < 110 && base[i + 2] < 110 }
        var slot = [Bool](repeating: false, count: n * n)
        for x in max(0, firstTooth - 3)..<n {
            var top = -1, bottom = -1
            for y in rowsFrom...rowsTo {
                let i = (y * n + x) * 4
                let r = Int(base[i]), g = Int(base[i + 1]), b = Int(base[i + 2])
                if (r + g + b) / 3 > 70, g > 60, !isRed(i) { if top < 0 { top = y }; bottom = y }
            }
            guard top >= 0 else { continue }
            for y in top...bottom { slot[y * n + x] = true }
        }
        // Grown by 4 px so the scaled-down cover has no soft edge on a tooth
        // (which would let it show through); never onto red.
        let grow = 4
        for y in max(0, rowsFrom - grow)...min(n - 1, rowsTo + grow) { for x in max(0, firstTooth - 3 - grow)..<n {
            let i = (y * n + x) * 4
            guard !isRed(i) else { continue }
            var near = false
            for dy in -grow...grow where !near { let yy = y + dy; guard yy >= 0, yy < n else { continue }
                for dx in -grow...grow { let xx = x + dx; if xx >= 0, xx < n, slot[yy * n + xx] { near = true; break } } }
            if near { cover[i] = 8; cover[i + 1] = 8; cover[i + 2] = 8; cover[i + 3] = 255 }
        } }
        clearBackground(&base, size: n)
        var whole = original
        clearBackground(&whole, size: n)
        guard let baseImage = image(base), let spriteImage = image(sprite), let wholeImage = image(whole),
              let coverImage = image(cover) else { return nil }
        let pad: CGFloat = 0.006
        return LidZipperParts(whole: wholeImage, base: baseImage, teethCover: coverImage, sprite: spriteImage,
                              restLeft: CGFloat(bodyMin) / f, startLeft: CGFloat(firstTooth) / f,
                              bodyWidth: CGFloat(bodyMax - bodyMin) / f,
                              teethTop: CGFloat(teethTopRow) / f - pad, teethHeight: CGFloat(teethBottomRow - teethTopRow) / f + 2 * pad,
                              trackEnd: CGFloat(trackEnd) / f + 0.012)
    }
}

/// One kiss heart: rises, grows a little and fades out, once per trigger.
struct LidKissHeart: View {
    let index: Int
    let trigger: Bool

    struct Values { var y: CGFloat = 0; var scale: CGFloat = 0.5; var opacity: Double = 0 }

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: index == 1 ? 20 : 14, weight: .bold))
            .foregroundStyle(LidBrand.lipRed)
            .keyframeAnimator(initialValue: Values(), trigger: trigger) { content, value in
                content
                    .offset(y: value.y)
                    .scaleEffect(value.scale)
                    .opacity(value.opacity)
            } keyframes: { _ in
                let delay = Double(index == 1 ? 0 : index) * 0.06
                KeyframeTrack(\.y) {
                    LinearKeyframe(0, duration: delay)
                    CubicKeyframe(index == 1 ? -58 : -42, duration: 0.85)
                }
                KeyframeTrack(\.scale) {
                    LinearKeyframe(0.5, duration: delay)
                    SpringKeyframe(1, duration: 0.35, spring: .bouncy)
                    LinearKeyframe(1, duration: 0.5)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0, duration: delay)
                    LinearKeyframe(1, duration: 0.12)
                    LinearKeyframe(1, duration: 0.38)
                    LinearKeyframe(0, duration: 0.35)
                }
            }
            .accessibilityHidden(true)
    }
}

/// The splash window: centred on the current screen, then it shrinks into the
/// menu bar icon — or fades where it is when the icon can't be located on that
/// screen, or with Reduce Motion / VoiceOver. It never opens the main panel.
@MainActor final class LidOnboardingController {
    private let defaults: UserDefaults
    let state: LidOnboardingState
    private let panel = LidOnboardingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var departing = false
    private var finished = false
    private var cardColor: Color?
    /// The icon's current screen rect, asked at departure (nil: not visible on this screen).
    var iconTarget: () -> NSRect? = { nil }
    /// The card has reached the icon (a short highlight there reads as «it went in»).
    var onArrive: (() -> Void)?
    var onFinish: (() -> Void)?
    var isVisible: Bool { panel.isVisible }
    var explains: Bool { state.explains }

    static let flightDuration = 0.6

    init(defaults: UserDefaults, explains: Bool, reduced: Bool = LidOnboardingState.systemPrefersReducedMotion) {
        self.defaults = defaults
        self.state = LidOnboardingState(reduced: reduced, explains: explains)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Transparent window: only the lips, the wordmark and (first run) the note.
        panel.hasShadow = false
        panel.onCancel = { [weak self] in self?.skipOrLeave() }
        state.onPlayed = { [weak self] in
            guard let self, !self.state.explains else { return }
            self.depart()
        }
    }

    /// Centred on `screen`'s visible area.
    static func centred(_ size: NSSize, on screen: NSRect) -> NSRect {
        NSRect(x: (screen.midX - size.width / 2).rounded(), y: (screen.midY - size.height / 2).rounded(), width: size.width, height: size.height)
    }

    /// Where the card ends: a small rect centred on the icon, keeping its aspect.
    static func landing(for card: NSRect, icon: NSRect) -> NSRect {
        let width: CGFloat = 26, height = (width * card.height / max(card.width, 1)).rounded()
        return NSRect(x: icon.midX - width / 2, y: icon.midY - height / 2, width: width, height: height)
    }

    func present(on screen: NSRect, icon: NSImage?, iconVisible: Bool, logo: NSImage?) {
        cardColor = LidBrand.background(for: logo)
        // Always derived: the transparent artwork is needed in every mode; the
        // travelling pull is used only without Reduce Motion.
        let parts = logo.flatMap(LidZipperParts.make(from:))
        let content = NSHostingView(rootView: LidOnboardingView(
            state: state, logo: logo, parts: parts, icon: icon, iconVisible: iconVisible,
            // Skip button / a tap on the short splash: same as Escape.
            onSkip: { [weak self] in self?.skipOrLeave() },
            onDone: { [weak self] in self?.depart() }, cardColor: cardColor))
        let size = content.fittingSize
        content.frame = NSRect(origin: .zero, size: size)
        panel.contentView = content
        panel.setFrame(Self.centred(size, on: screen), display: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = state.reduced ? 0.15 : LidMotion.duration
            context.timingFunction = LidMotion.timing
            panel.animator().alphaValue = 1
        }
        if logo == nil { state.skip(); if !state.explains { depart() } } else { state.play() }
    }

    /// Escape: first stop the animation; a second press (or the short splash) leaves.
    func skipOrLeave() {
        if state.stage == .intro {
            state.skip()
            if !state.explains { depart() }
        } else {
            depart()
        }
    }

    /// Leave toward the icon. The first-run flag is set here, once the hint was offered.
    func depart() {
        guard !departing, !finished else { return }
        departing = true
        if state.explains { LidOnboardingStore.markShown(defaults) }
        let start = panel.frame
        let target = state.reduced ? nil : iconTarget()
        guard let target, let snapshot = snapshot() else {
            // Calm fade in place.
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in MainActor.assumeIsolated { self?.finish() } })
            return
        }
        // Fly a picture of the card so it scales smoothly instead of re-laying out.
        let image = NSImageView(frame: NSRect(origin: .zero, size: start.size))
        image.image = snapshot
        image.imageScaling = .scaleProportionallyUpOrDown
        image.autoresizingMask = [.width, .height]
        panel.contentView = image
        panel.hasShadow = false
        let landing = Self.landing(for: start, icon: target)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.flightDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.77, 0, 0.175, 1)
            panel.animator().setFrame(landing, display: true)
        }, completionHandler: { [weak self] in MainActor.assumeIsolated {
            self?.onArrive?()
            self?.finish()
        } })
        // Dissolve into the icon over the second half of the flight.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flightDuration * 0.45) { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.flightDuration * 0.55
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.panel.animator().alphaValue = 0
            }
        }
    }

    /// Close at once (the status item was clicked while the splash played).
    func dismissNow() {
        if state.explains, !departing { LidOnboardingStore.markShown(defaults) }
        departing = true
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        panel.orderOut(nil)
        onFinish?()
    }

    private func snapshot() -> NSImage? {
        guard let view = panel.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(bitmap)
        return image
    }
}

final class LidOnboardingPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
