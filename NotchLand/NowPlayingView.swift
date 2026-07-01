//
//  NowPlayingView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Music UI that the FloatingNotch renders when NowPlayingService has a
//  track. Two states:
//    * Collapsed: artwork on the left of the notch, animated EQ bars on the right.
//    * Expanded:  full media controls — large artwork, title/artist, scrubber,
//                 prev/play/next, output device button. Replicates Alcove.
//

import AppKit
import SwiftUI

// MARK: - Constants for the notch sizing math (referenced by WindowManager).

enum NowPlayingMetrics {
    /// Width of the collapsed pill when music is playing. Wider than the bare
    /// notch so the artwork (left) and EQ bars (right) flank the hardware notch.
    static let collapsedWidth: CGFloat = 250
    /// Height matches the bare collapsed notch — we don't grow vertically.
    static let collapsedExtraHeight: CGFloat = 0
    /// Extra height added under the collapsed pill when the cursor is hovering,
    /// to host the scrolling song-title marquee.
    static let hoverExtraHeight: CGFloat = 24
    /// Expanded panel size. Tuned to fit the layout in the reference screenshot.
    static let expandedSize = CGSize(width: 420, height: 170)
    /// Edge inset around the artwork / bars in the collapsed pill.
    static let collapsedSidePadding: CGFloat = 10
    /// Side artwork in the collapsed pill.
    static let collapsedArtSize: CGFloat = 22
    /// EQ bars area in the collapsed pill.
    static let collapsedBarsSize = CGSize(width: 22, height: 14)
}

// MARK: - Collapsed flank (artwork left + EQ bars right)

struct NowPlayingCollapsedView: View {
    let track: NowPlayingService.Track
    var isHovering: Bool = false
    var morphNamespace: Namespace.ID? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                artwork
                    .padding(.leading, NowPlayingMetrics.collapsedSidePadding)
                    .padding(.top, 4)
                Spacer(minLength: 0)
//                EQBarsView(isAnimating: track.isPlaying)
//                    .frame(
//                        width: NowPlayingMetrics.collapsedBarsSize.width,
//                        height: NowPlayingMetrics.collapsedBarsSize.height
//                    )
//                    .matchedGeometry(id: "music-eq", in: morphNamespace)
//                    .padding(.trailing, NowPlayingMetrics.collapsedSidePadding + 2)
                EQBarsView(
                    isAnimating: track.isPlaying,
                    primaryColor: track.artwork?.waveAccentColor() ?? .white
                )
                .frame(
                    width: NowPlayingMetrics.collapsedBarsSize.width,
                    height: NowPlayingMetrics.collapsedBarsSize.height
                )
                .matchedGeometry(id: "music-eq", in: morphNamespace)
                .padding(.trailing, NowPlayingMetrics.collapsedSidePadding + 2)
            }
            .frame(maxWidth: .infinity)

            if isHovering {
                MarqueeText(text: marqueeText)
                    .frame(height: NowPlayingMetrics.hoverExtraHeight - 4)
                    .padding(.top, 5)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var marqueeText: String {
        let trimmedTitle = track.title.trimmingCharacters(in: .whitespaces)
        let trimmedArtist = track.artist.trimmingCharacters(in: .whitespaces)
        if trimmedArtist.isEmpty { return trimmedTitle }
        return "\(trimmedTitle) - \(trimmedArtist)"
    }
    
    @ViewBuilder
    private var artwork: some View {
        let size = NowPlayingMetrics.collapsedArtSize
        Group {
            if let image = track.artwork {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .matchedGeometry(id: "music-art", in: morphNamespace)
    }
}

// MARK: - Expanded controls panel

struct NowPlayingExpandedView: View {
    @EnvironmentObject var nowPlaying: NowPlayingService
    let track: NowPlayingService.Track
    var morphNamespace: Namespace.ID? = nil
    @State private var scrubbedProgress: Double?
    @State private var scrubClearTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Spacer(minLength: 0)
                    Text(track.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.top, 10)
                Spacer(minLength: 8)
                EQBarsView(
                    isAnimating: track.isPlaying,
                    primaryColor: track.artwork?.waveAccentColor() ?? .white
                )
                .frame(width: 22, height: 22)
                .matchedGeometry(id: "music-eq", in: morphNamespace)
                .padding(.top, 30)
                .opacity(track.isPlaying ? 1 : 0.45)
            }

            scrubber

            controlsRow
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onDisappear {
            scrubClearTask?.cancel()
            scrubClearTask = nil
        }
    }

    @ViewBuilder
    private var artwork: some View {
        let size: CGFloat = 76
        Group {
            if let image = track.artwork {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color.white.opacity(0.18), Color.white.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .matchedGeometry(id: "music-art", in: morphNamespace)
    }

    private var scrubber: some View {
        let primaryColor = track.artwork?.dominantColor() ?? .white

        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !track.isPlaying)) { ctx in
            let elapsed = track.elapsed(at: ctx.date)
            let progress = track.progress(at: ctx.date)
            let displayedProgress = scrubbedProgress ?? progress
            let displayedElapsed = track.duration > 0
                ? displayedProgress * track.duration
                : elapsed
            let remaining = max(0, track.duration - displayedElapsed)
            HStack(spacing: 10) {
                Text(format(displayedElapsed))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .monospacedDigit()
                ProgressBar(
                    progress: displayedProgress,
                    primaryColor: primaryColor,
                    isEnabled: track.duration > 0,
                    onScrubChanged: { progress in
                        scrubClearTask?.cancel()
                        scrubClearTask = nil
                        scrubbedProgress = progress
                    },
                    onScrubEnded: { progress in
                        scrubClearTask?.cancel()
                        scrubbedProgress = progress
                        nowPlaying.seek(to: progress * track.duration)
                        scrubClearTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 450_000_000)
                            guard !Task.isCancelled else { return }
                            scrubbedProgress = nil
                            scrubClearTask = nil
                        }
                    }
                )
                .frame(height: 14)
                Text(track.duration > 0 ? "-\(format(remaining))" : "--:--")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .monospacedDigit()
            }
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 2) {
            ControlButton(symbol: "backward.fill", size: 16, prominent: false) {
                nowPlaying.previousTrack()
            }
            ControlButton(
                symbol: track.isPlaying ? "pause.fill" : "play.fill",
                size: 26,
                prominent: true
            ) {
                nowPlaying.togglePlayPause()
            }
            ControlButton(symbol: "forward.fill", size: 16, prominent: false) {
                nowPlaying.nextTrack()
            }
//            outputDeviceButton
        }
        .frame(maxWidth: .infinity)
        .padding(.top, -12)
    }

    private var outputDeviceButton: some View {
        Image(systemName: "airpods.gen3")
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(Color.white.opacity(0.85))
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Sub-components

private struct ProgressBar: View {
    let progress: Double
    let primaryColor: Color
    let isEnabled: Bool
    let onScrubChanged: (Double) -> Void
    let onScrubEnded: (Double) -> Void

    @State private var isHovering = false
    @State private var isDragging = false

    private var clampedProgress: CGFloat {
        CGFloat(min(1, max(0, progress)))
    }

    var body: some View {
        GeometryReader { geo in
            let fillWidth = geo.size.width * clampedProgress
            let thumbSize: CGFloat = (isDragging || isHovering) && isEnabled ? 11 : 7
            let gradient = Gradient(stops: [
                .init(color: primaryColor, location: 0.0),
                .init(color: primaryColor.opacity(0.55), location: 1.0)
            ])

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(primaryColor.opacity(0.18))
                    .frame(height: 5)
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            gradient: gradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, fillWidth))
                    .frame(height: 5)
                    .shadow(color: primaryColor.opacity(0.22), radius: 3, x: 0, y: 0)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: Color.black.opacity(0.24), radius: 2, x: 0, y: 1)
                    .offset(x: min(max(fillWidth - thumbSize / 2, 0), max(0, geo.size.width - thumbSize)))
                    .opacity(isEnabled ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled else { return }
                        isDragging = true
                        onScrubChanged(progress(for: value.location.x, width: geo.size.width))
                    }
                    .onEnded { value in
                        guard isEnabled else { return }
                        isDragging = false
                        onScrubEnded(progress(for: value.location.x, width: geo.size.width))
                    }
            )
        }
    }

    private func progress(for locationX: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(1, max(0, locationX / width)))
    }
}

private struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let prominent: Bool
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(background) // Expand hit area
                    .frame(width: 46, height: 48)
                Image(systemName: symbol)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var background: Color {
        if prominent {
            return Color.black.opacity(isHovering ? 0.18 : 0.13)
        }
        return Color.black.opacity(isHovering ? 0.10 : 0.06)
    }
}

// MARK: - Optional matchedGeometryEffect helper

extension View {
    /// Apply `matchedGeometryEffect` only when a namespace is supplied. Lets the
    /// music views accept an *optional* namespace so they still work standalone
    /// (e.g. in previews) without forcing every callsite to provide one.
    @ViewBuilder
    func matchedGeometry(id: String, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            self.matchedGeometryEffect(id: id, in: namespace)
        } else {
            self
        }
    }
}

// MARK: - Marquee (continuously scrolling song title)

struct MarqueeText: View {
    let text: String
    var font: Font = .system(size: 11, weight: .medium, design: .rounded)
    var color: Color = .white.opacity(0.85)
    var pointsPerSecond: Double = 28
    /// Gap between the end of one repetition and the start of the next.
    var gap: CGFloat = 48

    @State private var textWidth: CGFloat = 0
    @State private var startDate = Date()

    var body: some View {
        GeometryReader { geo in
            let viewportWidth = geo.size.width
            let needsScroll = textWidth > viewportWidth - 1
            ZStack(alignment: .leading) {
                if needsScroll {
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { ctx in
                        let cycle = textWidth + gap
                        let elapsed = max(0, ctx.date.timeIntervalSince(startDate))
                        let phase = CGFloat(elapsed * pointsPerSecond)
                            .truncatingRemainder(dividingBy: cycle)
                        HStack(spacing: gap) {
                            label
                            label
                        }
                        .offset(x: -phase)
                    }
                } else {
                    label
                        .frame(width: viewportWidth, alignment: .center)
                }
            }
            .frame(width: viewportWidth, height: geo.size.height, alignment: .leading)
            .clipped()
        }
        .background(measurement)
        .onAppear {
            startDate = Date()
        }
        .onChange(of: text) { _, _ in
            startDate = Date()
        }
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// Hidden, full-size copy used purely to read the rendered width of `text`.
    private var measurement: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .opacity(0)
            .allowsHitTesting(false)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { textWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, new in textWidth = new }
                }
            )
    }
}

private func makeArtworkGradient(from artwork: NSImage?) -> LinearGradient {
    let baseColor: Color = artwork?.dominantColor() ?? Color.white.opacity(0.18)
    return LinearGradient(
        colors: [
            baseColor.opacity(0.38),
            baseColor.opacity(0.18),
            Color.black.opacity(0.0)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Artwork Color Extraction

extension NSImage {
    /// Picks a lively artwork color that remains readable against the black
    /// notch. Light colors from the artwork are preferred; dark-only palettes
    /// are gently lifted instead of being replaced with an unrelated color.
    func waveAccentColor() -> Color {
        guard let cgImage = self.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            return .white
        }

        let width = 40
        let height = 40
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var rawData = [UInt8](
            repeating: 0,
            count: width * height * bytesPerPixel
        )

        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return .white
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var buckets: [String: (count: Int, r: CGFloat, g: CGFloat, b: CGFloat)] = [:]

        for pixel in stride(from: 0, to: rawData.count, by: bytesPerPixel) {
            let alpha = CGFloat(rawData[pixel + 3]) / 255
            guard alpha > 0.8 else { continue }

            let r = CGFloat(rawData[pixel]) / 255
            let g = CGFloat(rawData[pixel + 1]) / 255
            let b = CGFloat(rawData[pixel + 2]) / 255
            let maximum = max(r, g, b)
            let minimum = min(r, g, b)
            let saturation = maximum > 0 ? (maximum - minimum) / maximum : 0

            // Keep pale artwork tones, but discard near-black and flat mid-grey
            // pixels that do not make useful music-player accents.
            guard maximum > 0.08 else { continue }
            guard saturation > 0.08 || maximum > 0.72 else { continue }

            let key = "\(Int(r * 7))-\(Int(g * 7))-\(Int(b * 7))"
            if let existing = buckets[key] {
                buckets[key] = (
                    count: existing.count + 1,
                    r: existing.r + r,
                    g: existing.g + g,
                    b: existing.b + b
                )
            } else {
                buckets[key] = (count: 1, r: r, g: g, b: b)
            }
        }

        let candidates = buckets.values.map { bucket -> ArtworkColorCandidate in
            let count = CGFloat(bucket.count)
            return ArtworkColorCandidate(
                count: bucket.count,
                r: bucket.r / count,
                g: bucket.g / count,
                b: bucket.b / count
            )
        }

        guard !candidates.isEmpty else { return .white }

        let minimumWaveLuminance: CGFloat = 0.18
        if let dominant = candidates.max(by: { $0.count < $1.count }) {
            let originalAccent = dominant.brightened(by: 1.15)
            if originalAccent.luminance >= minimumWaveLuminance {
                return originalAccent.color
            }
        }

        // The artwork's normal dominant color was too dark. Prefer a naturally
        // light tone when one exists, without changing already-readable colors.
        let lightCandidates = candidates.filter {
            $0.luminance >= minimumWaveLuminance
        }
        let pool = lightCandidates.isEmpty ? candidates : lightCandidates
        guard let selected = pool.max(by: { $0.waveScore < $1.waveScore }) else {
            return .white
        }

        var r = selected.r
        var g = selected.g
        var b = selected.b

        // On dark-only covers, preserve the selected hue and progressively mix
        // in white until it has enough luminance to read cleanly on the notch.
        while relativeLuminance(r: r, g: g, b: b) < minimumWaveLuminance {
            r += (1 - r) * 0.08
            g += (1 - g) * 0.08
            b += (1 - b) * 0.08
        }

        return Color(red: r, green: g, blue: b)
    }

    /// Extracts a clean dominant color from the artwork.
    /// Good for dynamic gradients behind music UI.
    func dominantColor() -> Color {
        guard let cgImage = self.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            return Color.white.opacity(0.18)
        }

        let width = 40
        let height = 40

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8

        var rawData = [UInt8](
            repeating: 0,
            count: width * height * bytesPerPixel
        )

        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return Color.white.opacity(0.18)
        }

        context.interpolationQuality = .medium
        context.draw(
            cgImage,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )

        var colorCounts: [String: (count: Int, r: CGFloat, g: CGFloat, b: CGFloat)] = [:]

        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * bytesPerPixel

                let r = CGFloat(rawData[index]) / 255.0
                let g = CGFloat(rawData[index + 1]) / 255.0
                let b = CGFloat(rawData[index + 2]) / 255.0
                let a = CGFloat(rawData[index + 3]) / 255.0

                guard a > 0.8 else { continue }

                let brightness = (r + g + b) / 3.0
                let saturation = max(r, g, b) - min(r, g, b)

                // Ignore boring blacks, whites, and greys.
                guard brightness > 0.12, brightness < 0.88 else { continue }
                guard saturation > 0.12 else { continue }

                // Quantize colors so nearby colors group together.
                let qr = Int(r * 8)
                let qg = Int(g * 8)
                let qb = Int(b * 8)
                let key = "\(qr)-\(qg)-\(qb)"

                if let existing = colorCounts[key] {
                    colorCounts[key] = (
                        count: existing.count + 1,
                        r: existing.r + r,
                        g: existing.g + g,
                        b: existing.b + b
                    )
                } else {
                    colorCounts[key] = (
                        count: 1,
                        r: r,
                        g: g,
                        b: b
                    )
                }
            }
        }

        guard let best = colorCounts.values.max(by: { $0.count < $1.count }) else {
            return Color.white.opacity(0.18)
        }

        let count = CGFloat(best.count)

        let r = min(best.r / count * 1.15, 1.0)
        let g = min(best.g / count * 1.15, 1.0)
        let b = min(best.b / count * 1.15, 1.0)

        return Color(red: r, green: g, blue: b)
    }
}

private struct ArtworkColorCandidate {
    let count: Int
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat

    var luminance: CGFloat {
        relativeLuminance(r: r, g: g, b: b)
    }

    var saturation: CGFloat {
        let maximum = max(r, g, b)
        guard maximum > 0 else { return 0 }
        return (maximum - min(r, g, b)) / maximum
    }

    var waveScore: CGFloat {
        sqrt(CGFloat(count)) * (0.75 + saturation * 1.4) * (0.8 + luminance)
    }

    var color: Color {
        Color(red: r, green: g, blue: b)
    }

    func brightened(by factor: CGFloat) -> ArtworkColorCandidate {
        ArtworkColorCandidate(
            count: count,
            r: min(r * factor, 1),
            g: min(g * factor, 1),
            b: min(b * factor, 1)
        )
    }
}

private func relativeLuminance(r: CGFloat, g: CGFloat, b: CGFloat) -> CGFloat {
    func linearize(_ component: CGFloat) -> CGFloat {
        component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }

    return 0.2126 * linearize(r)
        + 0.7152 * linearize(g)
        + 0.0722 * linearize(b)
}


// MARK: - EQ bars (animated audio indicator)

struct EQBarsView: View {
    let isAnimating: Bool
    var primaryColor: Color = .white
    let barCount: Int = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating)) { ctx in
            Canvas { context, size in
                let barGradient = Gradient(stops: [
                    .init(color: primaryColor, location: 0.0),
                    .init(color: primaryColor.opacity(0.72), location: 1.0)
                ])

                let barWidth: CGFloat = 2.2
                let spacing: CGFloat = 2.4
                let usedWidth = CGFloat(barCount) * barWidth
                    + CGFloat(barCount - 1) * spacing
                let leadingX = (size.width - usedWidth) / 2
                let centerY = size.height / 2
                let maxBarHeight = size.height * 0.85
                let minBarHeight: CGFloat = 2
                let now = ctx.date.timeIntervalSinceReferenceDate

                for i in 0..<barCount {
                    let phase = Double(i) * 0.85
                    let frequency = 1.6 + Double(i) * 0.22

                    let normalized: Double
                    if isAnimating {
                        let raw = sin(now * frequency + phase)
                        normalized = (abs(raw) * 0.6) + 0.25
                    } else {
                        normalized = 0.32
                    }

                    let barHeight = max(
                        minBarHeight,
                        maxBarHeight * CGFloat(normalized)
                    )

                    let x = leadingX + CGFloat(i) * (barWidth + spacing)
                    let y = centerY - barHeight / 2

                    let rect = CGRect(
                        x: x,
                        y: y,
                        width: barWidth,
                        height: barHeight
                    )

                    let path = Path(
                        roundedRect: rect,
                        cornerRadius: barWidth / 2
                    )

                    context.fill(
                        path,
                        with: .linearGradient(
                            barGradient,
                            startPoint: CGPoint(x: rect.midX, y: rect.minY),
                            endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                        )
                    )
                }
            }
        }
        .shadow(color: primaryColor.opacity(0.42), radius: 3)
    }
}

#if DEBUG
@MainActor
private struct NowPlayingCanvasPreview: View {
    @StateObject private var nowPlaying = NowPlayingService()
    let isExpanded: Bool

    var body: some View {
        Group {
            if isExpanded {
                NowPlayingExpandedView(track: NowPlayingPreviewFixtures.track)
                    .frame(
                        width: NowPlayingMetrics.expandedSize.width,
                        height: NowPlayingMetrics.expandedSize.height
                    )
            } else {
                NowPlayingCollapsedView(
                    track: NowPlayingPreviewFixtures.track,
                    isHovering: true
                )
                .frame(width: NowPlayingMetrics.collapsedWidth, height: 56)
            }
        }
        .environmentObject(nowPlaying)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(24)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
    }
}

@MainActor
private enum NowPlayingPreviewFixtures {
    static let artwork = NSImage(
        size: NSSize(width: 160, height: 160),
        flipped: false
    ) { rect in
        NSGradient(colors: [
            NSColor(red: 0.04, green: 0.08, blue: 0.20, alpha: 1),
            NSColor(red: 0.20, green: 0.44, blue: 0.92, alpha: 1),
            NSColor(red: 0.91, green: 0.50, blue: 0.72, alpha: 1)
        ])?.draw(in: rect, angle: -45)
        return true
    }

    static let track = NowPlayingService.Track(
        title: "Midnight City",
        artist: "M83",
        album: "Hurry Up, We're Dreaming",
        artwork: artwork,
        duration: 244,
        elapsedAtTimestamp: 86,
        timestamp: Date(),
        playbackRate: 1
    )
}

#Preview("Now Playing - Collapsed") {
    NowPlayingCanvasPreview(isExpanded: false)
}

#Preview("Now Playing - Expanded") {
    NowPlayingCanvasPreview(isExpanded: true)
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
