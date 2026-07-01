//
//  FloatingNotchView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  The SwiftUI surface hosted inside the floating NSPanel. Renders the visible
//  notch (capsule when collapsed, rounded panel when expanded) inside a slightly
//  larger transparent canvas so the SwiftUI shadow has room to render.
//

import AppKit
import SwiftUI

/// A notch silhouette: rectangular top of width `topWidth`, widening with
/// concave shoulders into a body of width `rect.width`, with rounded bottom corners.
///
/// When `topWidth == rect.width` and `shoulderRadius == 0`, this degenerates to
/// a plain rectangle with rounded bottom corners (the non-notched fallback).
struct NotchShape: Shape {
    var topWidth: CGFloat
    var bottomCornerRadius: CGFloat
    var shoulderRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(topWidth, AnimatablePair(bottomCornerRadius, shoulderRadius))
        }
        set {
            topWidth = newValue.first
            bottomCornerRadius = newValue.second.first
            shoulderRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let bodyWidth = rect.width
        let height = rect.height
        let clampedTop = min(max(topWidth, 0), bodyWidth)
        let sideInset = (bodyWidth - clampedTop) / 2

        let maxShoulder = max(0, min(sideInset, height / 2))
        let shoulder = min(max(shoulderRadius, 0), maxShoulder)
        let hasShoulder = sideInset > 0 && shoulder > 0

        let maxBottom = max(0, min(bodyWidth / 2, height - shoulder))
        let bottom = min(max(bottomCornerRadius, 0), maxBottom)

        path.move(to: CGPoint(x: sideInset, y: 0))
        path.addLine(to: CGPoint(x: bodyWidth - sideInset, y: 0))

        // Right shoulder: smooth concave Bézier with control at the bounding corner.
        // Start tangent is horizontal (continues top edge); end tangent is vertical
        // (continues right wall).
        if hasShoulder {
            path.addQuadCurve(
                to: CGPoint(x: bodyWidth, y: shoulder),
                control: CGPoint(x: bodyWidth, y: 0)
            )
        }

        path.addLine(to: CGPoint(x: bodyWidth, y: height - bottom))

        if bottom > 0 {
            path.addArc(
                center: CGPoint(x: bodyWidth - bottom, y: height - bottom),
                radius: bottom,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
        }

        path.addLine(to: CGPoint(x: bottom, y: height))

        if bottom > 0 {
            path.addArc(
                center: CGPoint(x: bottom, y: height - bottom),
                radius: bottom,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
        }

        path.addLine(to: CGPoint(x: 0, y: shoulder))

        // Left shoulder: mirror of the right one.
        if hasShoulder {
            path.addQuadCurve(
                to: CGPoint(x: sideInset, y: 0),
                control: CGPoint(x: 0, y: 0)
            )
        }

        path.closeSubpath()
        return path
    }
}

struct FloatingNotchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var settings: NotchSettings
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var hud: HUDController
    @EnvironmentObject var nowPlaying: NowPlayingService
    @EnvironmentObject var batteryAlerts: BatteryAlertController
    @EnvironmentObject var focusMode: FocusModeController
    @EnvironmentObject var screenLock: ScreenLockController
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var countdown: EventCountdownController
    @EnvironmentObject var airDrop: AirDropController
    @EnvironmentObject var liveActivities: LiveActivityController
    @EnvironmentObject var notchTimer: NotchTimerController

    /// Used to morph shared elements (artwork, EQ bars) between the collapsed
    /// and expanded music states. Without this, SwiftUI cross-fades the small
    /// view out and the big one in, which reads as two layers stacking.
    /// `matchedGeometryEffect` makes them the *same* element at different sizes.
    @Namespace private var morph
    @State private var notchTransitionScale: CGFloat = 1
    @State private var notchTransitionBlur: CGFloat = 0
    @State private var notchTransitionTask: Task<Void, Never>?
    @State private var renderedBranchKey: String?
    @State private var renderedBatteryPresentation: BatteryAlertController.Presentation?
    @State private var renderedFocusPresentation: FocusModeController.Presentation?
    @State private var renderedScreenLockPresentation: ScreenLockController.Presentation?
    @State private var isNotchPhaseAnimating = false
    @State private var notchBlendMotion: FeatureBlendMotion = .return
    @State private var suppressCollapsedMusicMarquee = false
    @State private var calendarCountdownShapeReveal: CGFloat = 1
    /// True for the lifetime of a transition whose source or destination is a
    /// calendar-countdown branch. Keeps `notchBody` on `calendarCountdownNotchBody`
    /// across the intermediate hardware-notch pivot, so SwiftUI preserves one
    /// view identity and the split shape morphs via `animatableData` instead of
    /// hard-cutting when the phase ends.
    @State private var calendarTransitionActive = false
    @State private var onboardingStage: OnboardingStage = .locked
    @State private var borderReveal: CGFloat = 0
    /// First-launch choreography: notch starts collapsed, then drives the same
    /// expanded state used by normal interactions so onboarding grows out of
    /// the collapsed notch instead of appearing at full size.
    @State private var didRevealOnboarding = false
    private static let onboardingRevealDelay: Duration = .seconds(1)

    var body: some View {
        let displayKey = visualBranchKey
        let size = currentVisibleSize(for: displayKey)

        ZStack(alignment: .top) {
            notchBody(size: size, branchKey: displayKey)
                .frame(width: size.width, height: size.height, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            renderedBranchKey = branchKey
            renderedBatteryPresentation = batteryAlerts.currentPresentation
            renderedFocusPresentation = focusMode.currentPresentation
            renderedScreenLockPresentation = screenLock.currentPresentation
            playBorderEntrance()
            resetOnboardingStateIfNeeded()
        }
        .task(id: settings.hasCompletedOnboarding) {
            // First launch starts as a locked hardware-style notch, springs the
            // glyph open, then expands through the Dynamic Island transition.
            guard !settings.hasCompletedOnboarding else { return }
            resetOnboardingStateIfNeeded()
            try? await Task.sleep(for: Self.onboardingRevealDelay)
            guard !Task.isCancelled, !settings.hasCompletedOnboarding else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.58, blendDuration: 0)) {
                onboardingStage = .unlocking
            }
            try? await Task.sleep(for: .milliseconds(720))
            guard !Task.isCancelled, !settings.hasCompletedOnboarding else { return }
            withAnimation(OnboardingNotchMotion.openAnimation) {
                onboardingStage = .welcome
                didRevealOnboarding = true
                appState.isExpanded = true
            }
        }
        .onChange(of: batteryAlerts.currentPresentation) { _, presentation in
            if let presentation {
                renderedBatteryPresentation = presentation
            }
        }
        .onChange(of: focusMode.currentPresentation) { _, presentation in
            if let presentation {
                renderedFocusPresentation = presentation
            }
        }
        .onChange(of: screenLock.currentPresentation) { _, presentation in
            if let presentation {
                renderedScreenLockPresentation = presentation
            }
        }
        .onChange(of: branchKey) { oldBranch, newBranch in
            handleBranchChange(from: oldBranch, to: newBranch)
            playBorderEntrance()
        }
        .onChange(of: appState.isHovering) { _, isHovering in
            if !isHovering {
                suppressCollapsedMusicMarquee = false
            }
        }
        .onChange(of: appState.isExpanded) { _, isExpanded in
            if !isExpanded {
                countdown.clearDetail()
            }
        }
        .onChange(of: settings.hasCompletedOnboarding) { _, completed in
            if !completed {
                resetOnboardingStateIfNeeded()
            }
        }
        .onDisappear {
            notchTransitionTask?.cancel()
        }
    }

    private func resetOnboardingStateIfNeeded() {
        guard !settings.hasCompletedOnboarding else { return }
        notchTransitionTask?.cancel()
        withTransaction(Transaction(animation: nil)) {
            renderedBranchKey = "onboarding-lock"
            renderedBatteryPresentation = nil
            renderedFocusPresentation = nil
            renderedScreenLockPresentation = nil
            onboardingStage = .locked
            appState.resetToCollapsed()
            didRevealOnboarding = false
            isNotchPhaseAnimating = false
            notchTransitionScale = 1
            notchTransitionBlur = 0
            calendarTransitionActive = false
            calendarCountdownShapeReveal = 1
            suppressCollapsedMusicMarquee = false
        }
    }

    /// Radius of the body's bottom-left/right corners.
    private func bottomCornerRadius(for key: String) -> CGFloat {
        if key == "expanded-onboarding" {
            return Self.collapsedCornerRadius
        }
        return isExpandedBranch(key) ? CGFloat(settings.cornerRadius) : Self.collapsedCornerRadius
    }

    /// Radius of the inverted (concave) top-outer corners. `0` collapses into
    /// a plain rounded-bottom rectangle; non-zero produces the NotchDrop-style
    /// curves. The value animates on the expansion spring along with the
    /// rest of the path.
    private func invertedCornerRadius(for key: String) -> CGFloat {
        if key == Self.hardwareNotchBranchKey {
            return Self.bareInvertedRadius
        }
        if key == "expanded-onboarding" {
            return Self.bareInvertedRadius
        }
        if isCompactAlertBranch(key) {
            return Self.musicInvertedRadius
        }

        return Self.invertedRadius(
            isExpanded: isExpandedBranch(key),
            hasMusic: isMusicBranch(key),
            isHovering: appState.isHovering
        )
    }

    static let collapsedCornerRadius: CGFloat = 10
    static let expandedInvertedRadius: CGFloat = 12
    static let musicInvertedRadius: CGFloat = 5
    static let hoverInvertedRadius: CGFloat = 7
    static let alertInvertedRadius: CGFloat = 8
    static let bareInvertedRadius: CGFloat = 5
    private static let hardwareNotchBranchKey = "hardware-notch"

    /// Per-state inverted-corner radius. Exposed as a static so `WindowManager`
    /// computes the same envelope dimensions as the rendered shape. Hover on the
    /// bare collapsed pill grows ears too — gives the "peek" a consistent shape
    /// with the music pill instead of staying a plain capsule.
    static func invertedRadius(isExpanded: Bool, hasMusic: Bool, isHovering: Bool) -> CGFloat {
        if isExpanded { return expandedInvertedRadius }
        if hasMusic { return musicInvertedRadius }
        if isHovering { return hoverInvertedRadius }
        return bareInvertedRadius
    }

    @ViewBuilder
    private func notchBody(size: CGSize, branchKey key: String) -> some View {
        if usesCalendarCountdownBody(for: key) {
            calendarCountdownNotchBody(size: size, branchKey: key)
        } else {
            standardNotchBody(size: size, branchKey: key)
        }
    }

    /// Whether `key` should render with the split calendar-countdown body.
    /// Includes the intermediate hardware-notch pivot while a calendar
    /// transition is in flight, so the body builder (and therefore the view
    /// identity) stays stable and the shape morphs continuously rather than
    /// swapping bodies — the swap is what made the split pop in.
    private func usesCalendarCountdownBody(for key: String) -> Bool {
        isCalendarCountdownBranch(key)
            || (key == Self.hardwareNotchBranchKey && calendarTransitionActive)
    }

    private func standardNotchBody(size: CGSize, branchKey key: String) -> some View {
        let bottomR = bottomCornerRadius(for: key)
        let invertedR = invertedCornerRadius(for: key)
        let isExpanded = isExpandedBranch(key)
        // let showsSoftBorder = !settings.useBlurMaterial || isCalendarSurfaceBranch(key)
        // The shape's inverted ears occupy `invertedR` of width on each side.
        // Keep this identical to the original transition path: one full-size
        // clipped shape whose body width morphs with the visible size.
        let bodyWidth = max(size.width - invertedR * 2, 0)
        let shape = NotchDropShape(
            invertedCornerRadius: invertedR,
            bottomCornerRadius: bottomR
        )

        return ZStack(alignment: .bottom) {
            notchDropBackground(shape: shape, forceBlack: isCalendarSurfaceBranch(key))
                .frame(width: size.width, height: size.height)

            content
                .frame(width: bodyWidth, height: size.height)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .frame(maxWidth: .infinity, alignment: .center)
        .shadow(
            color: Color.black.opacity(settings.shadowIntensity),
            radius: isExpanded ? 18 : 10,
            x: 0,
            y: isExpanded ? 8 : 4
        )
        .compositingGroup()
        .scaleEffect(notchTransitionScale, anchor: .top)
        .blur(radius: (1 - notchTransitionScale) * NotchFeatureMotion.containerBlurRadius + notchTransitionBlur)
        .opacity(Double(notchTransitionScale))
        .contentShape(shape)
        // Blue border is not needed for this version.
        /*
        .overlay {
            if showsSoftBorder {
                softBlueBorder(
                    invertedCornerRadius: invertedR,
                    bottomCornerRadius: bottomR
                )
            }
        }
        */
        .overlay {
            // Expanded content owns its own controls. Keep the overlay only for
            // collapsed click-to-open behavior so buttons can receive clicks.
            if !isExpandedBranch(key) {
                NotchInteractionSurface(
                    onTap: { location in handleNotchTap(at: location, size: size) }
                )
                .clipShape(shape)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86, blendDuration: 0),
                   value: appState.isHovering)
    }

    private func calendarCountdownNotchBody(size: CGSize, branchKey key: String) -> some View {
        let bottomR = bottomCornerRadius(for: key)
        let invertedR = invertedCornerRadius(for: key)
        let isExpanded = isExpandedBranch(key)
        let baseWidth = CGFloat(settings.collapsedWidth)
        let targetBodyWidth: CGFloat
        let leftAnchorWidth: CGFloat

        if key == Self.hardwareNotchBranchKey {
            targetBodyWidth = max(size.width - invertedR * 2, 0)
            leftAnchorWidth = targetBodyWidth
        } else if key == "collapsed-music-event" {
            targetBodyWidth = EventCountdownChipMetrics.musicComboBodyWidth(baseWidth: baseWidth)
            leftAnchorWidth = EventCountdownChipMetrics.musicComboLeftAnchorWidth
        } else {
            targetBodyWidth = EventCountdownChipMetrics.eventOnlyBodyWidth(baseWidth: baseWidth)
            leftAnchorWidth = EventCountdownChipMetrics.eventOnlyLeftAnchorWidth
        }

        let containerBodyWidth = max(size.width - invertedR * 2, 0)
        let reveal = min(max(calendarCountdownShapeReveal, 0), 1)
        let symmetricBodyWidth = containerBodyWidth / 2
        let targetLeftBodyWidth = leftAnchorWidth / 2
        let targetRightBodyWidth = max(targetLeftBodyWidth, targetBodyWidth - targetLeftBodyWidth)
        let leftBodyWidth = symmetricBodyWidth + (targetLeftBodyWidth - symmetricBodyWidth) * reveal
        let rightBodyWidth = symmetricBodyWidth + (targetRightBodyWidth - symmetricBodyWidth) * reveal
        let contentWidth = containerBodyWidth + (targetBodyWidth - containerBodyWidth) * reveal
        let contentOffset = ((targetRightBodyWidth - targetLeftBodyWidth) / 2) * reveal
        let shape = CalendarCountdownNotchShape(
            leftBodyWidth: leftBodyWidth,
            rightBodyWidth: rightBodyWidth,
            invertedCornerRadius: invertedR,
            bottomCornerRadius: bottomR
        )

        return ZStack(alignment: .bottom) {
            calendarCountdownBackground(shape: shape)
                .frame(width: size.width, height: size.height)

            content
                .frame(width: contentWidth, height: size.height)
                .offset(x: contentOffset)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .frame(maxWidth: .infinity, alignment: .center)
        .shadow(
            color: Color.black.opacity(settings.shadowIntensity),
            radius: isExpanded ? 18 : 10,
            x: 0,
            y: isExpanded ? 8 : 4
        )
        .compositingGroup()
        .scaleEffect(notchTransitionScale, anchor: .top)
        .blur(radius: (1 - notchTransitionScale) * NotchFeatureMotion.containerBlurRadius + notchTransitionBlur)
        .opacity(Double(notchTransitionScale))
        .contentShape(shape)
        .overlay {
            if !isExpandedBranch(key) {
                NotchInteractionSurface(
                    onTap: { location in handleNotchTap(at: location, size: size) }
                )
                .clipShape(shape)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86, blendDuration: 0),
                   value: appState.isHovering)
    }

    /// Fills the single-path notch shape with the configured style — solid
    /// black or the layered material (vibrancy + black overlay).
    @ViewBuilder
    private func notchDropBackground(shape: NotchDropShape, forceBlack: Bool = false) -> some View {
        if settings.useBlurMaterial && !forceBlack {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color.black.opacity(0.45))
            }
        } else {
            shape.fill(Color.black)
        }
    }

    @ViewBuilder
    private func calendarCountdownBackground(shape: CalendarCountdownNotchShape) -> some View {
        shape.fill(Color.black)
    }

    private func softBlueBorder(
        invertedCornerRadius: CGFloat,
        bottomCornerRadius: CGFloat
    ) -> some View {
        NotchDropBorderShape(
            invertedCornerRadius: invertedCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        )
            .stroke(
                Color(red: 0.22, green: 0.58, blue: 1.0).opacity(0.32 * borderReveal),
                lineWidth: 0.75
            )
            .shadow(
                color: Color(red: 0.16, green: 0.48, blue: 1.0).opacity(0.22 * borderReveal),
                radius: 5,
                x: 0,
                y: 0
            )
            .allowsHitTesting(false)
    }

    private func playBorderEntrance() {
        guard !reduceMotion else {
            borderReveal = 1
            return
        }

        borderReveal = 0
        withAnimation(.easeOut(duration: 0.55)) {
            borderReveal = 1
        }
    }

    private func handleNotchTap(at location: CGPoint, size: CGSize) {
        let key = branchKey
        if isExpandedBranch(key) {
            return
        }

        switch key {
        case "event-collapsed":
            openEventDetail()
        case "collapsed-music-event":
            if location.x >= size.width / 2 {
                openEventDetail()
            } else {
                openDefaultExpansion()
            }
        case "expanded-event-detail":
            return
        default:
            guard settings.openOnClick else { return }
            toggleDefaultExpansion()
        }
    }

    private func dismissTransientBranch(_ key: String) {
        switch key {
        case "battery-low", "battery-charging":
            batteryAlerts.dismissCurrentPresentation()
        case "focus-mode":
            focusMode.dismissCurrentPresentation()
        case "hud":
            hud.dismissCurrent()
        default:
            break
        }
    }

    private func openEventDetail() {
        guard countdown.trackedEvent != nil else {
            openDefaultExpansion()
            return
        }

        countdown.showDetail()
        appState.expand()
    }

    private func openDefaultExpansion() {
        countdown.clearDetail()
        appState.expand()
    }

    private func toggleDefaultExpansion() {
        countdown.clearDetail()
        appState.toggle()
    }

    /// Branches are inside one `ZStack`, with a soft emergence transition for
    /// the non-shared chrome (titles, scrubber, controls). Shared elements use
    /// `matchedGeometryEffect` (via the `morph` namespace passed into the music
    /// views) so the artwork & EQ bars don't fade — they literally morph their
    /// frame from the collapsed size/position to the expanded one along with
    /// the rectangle's spring. That's what makes the small notch *grow* into
    /// the big one instead of looking like two stacked layers.
    ///
    /// Every feature branch uses the same blurred content blend. The outer
    /// notch body handles the hardware-notch bridge, so branch content should
    /// feel like it is emerging from that shape instead of sitting above it.
    private var content: some View {
        let displayKey = visualBranchKey

        // Bottom alignment matters for the HUD: `HUDBarView` is a fixed-height
        // (28 pt) view that should sit in the drawer at the *bottom* of the
        // grown notch. The music/expanded branches override this with their own
        // `alignment: .top`/`.topLeading` frames, so they're unaffected.
        return ZStack(alignment: .bottom) {
            branchView(for: displayKey)
                .id(displayKey)
                .transition(branchTransition(for: displayKey))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func branchTransition(for _: String) -> AnyTransition {
        if isOnboardingBranch(visualBranchKey) || isOnboardingBranch(branchKey) {
            return .opacity.animation(OnboardingHeightMotion.contentAnimation)
        }
        return .featureBlend(notchBlendMotion)
    }

    private func handleBranchChange(from oldBranch: String, to newBranch: String) {
        notchTransitionTask?.cancel()
        renderedBranchKey = renderedBranchKey ?? oldBranch
        calendarTransitionActive = isCalendarCountdownBranch(oldBranch)
            || isCalendarCountdownBranch(newBranch)

        guard shouldUseGlobalFeatureMotion(from: oldBranch, to: newBranch) else {
            notchBlendMotion = .return
            renderedBranchKey = newBranch
            resetNotchTransition()
            return
        }

        if isCompactAlertBranch(oldBranch) || isCompactAlertBranch(newBranch) {
            handleCompactAlertBranchChange(from: oldBranch, to: newBranch)
            return
        }

        if isOnboardingBranch(oldBranch) || isOnboardingBranch(newBranch) {
            startOnboardingFeatureMotion(from: oldBranch, to: newBranch)
            return
        }

        startGlobalFeatureMotion(from: oldBranch, to: newBranch)
    }

    private func startOnboardingHeightMotion(to newBranch: String) {
        notchBlendMotion = .open
        isNotchPhaseAnimating = false
        notchTransitionScale = 1
        notchTransitionBlur = 0
        withAnimation(OnboardingHeightMotion.expandAnimation) {
            renderedBranchKey = newBranch
        }
    }

    private func startOnboardingFeatureMotion(from oldBranch: String, to newBranch: String) {
        if isGrowingTransition(from: oldBranch, to: newBranch) {
            notchBlendMotion = .open
            withAnimation(OnboardingNotchMotion.openCompressAnimation) {
                isNotchPhaseAnimating = true
                renderedBranchKey = Self.hardwareNotchBranchKey
                notchTransitionScale = 1
                notchTransitionBlur = 0
            }

            notchTransitionTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: OnboardingNotchMotion.openCompressDelayNanoseconds)
                guard !Task.isCancelled else { return }
                withTransaction(Transaction(animation: nil)) {
                    notchTransitionScale = OnboardingNotchMotion.openingScale
                    notchTransitionBlur = OnboardingNotchMotion.openingBlurRadius
                }
                try? await Task.sleep(nanoseconds: OnboardingNotchMotion.openKickDelayNanoseconds)
                guard !Task.isCancelled else { return }
                withAnimation(OnboardingNotchMotion.openAnimation) {
                    renderedBranchKey = newBranch
                    notchTransitionScale = 1
                    notchTransitionBlur = 0
                }
                try? await Task.sleep(nanoseconds: OnboardingNotchMotion.openSettleDelayNanoseconds)
                guard !Task.isCancelled else { return }
                finishNotchPhase(targetBranch: newBranch)
            }
            return
        }

        notchBlendMotion = .return
        withAnimation(OnboardingNotchMotion.collapseAnimation) {
            isNotchPhaseAnimating = true
            renderedBranchKey = Self.hardwareNotchBranchKey
            notchTransitionScale = 1
            notchTransitionBlur = 0
        }

        notchTransitionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: OnboardingNotchMotion.returnDelayNanoseconds)
            guard !Task.isCancelled else { return }
            withAnimation(OnboardingNotchMotion.returnAnimation) {
                renderedBranchKey = newBranch
                notchTransitionScale = 1
                notchTransitionBlur = 0
            }
            try? await Task.sleep(nanoseconds: OnboardingNotchMotion.returnSettleDelayNanoseconds)
            guard !Task.isCancelled else { return }
            finishNotchPhase(targetBranch: newBranch)
        }
    }

    private func startGlobalFeatureMotion(from oldBranch: String, to newBranch: String) {
        if isGrowingTransition(from: oldBranch, to: newBranch) {
            notchBlendMotion = .open
            withAnimation(NotchFeatureMotion.openCompressAnimation) {
                isNotchPhaseAnimating = true
                renderedBranchKey = Self.hardwareNotchBranchKey
                notchTransitionScale = 1
                notchTransitionBlur = 0
            }

            notchTransitionTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: NotchFeatureMotion.openCompressDelayNanoseconds)
                guard !Task.isCancelled else { return }
                withTransaction(Transaction(animation: nil)) {
                    notchTransitionScale = NotchFeatureMotion.openingScale
                    notchTransitionBlur = NotchFeatureMotion.openingBlurRadius
                }
                try? await Task.sleep(nanoseconds: NotchFeatureMotion.openKickDelayNanoseconds)
                guard !Task.isCancelled else { return }
                withAnimation(NotchFeatureMotion.openAnimation) {
                    renderedBranchKey = newBranch
                    notchTransitionScale = 1
                    notchTransitionBlur = 0
                }
                try? await Task.sleep(nanoseconds: NotchFeatureMotion.openSettleDelayNanoseconds)
                guard !Task.isCancelled else { return }
                finishNotchPhase(targetBranch: newBranch)
            }
            return
        }

        notchBlendMotion = .return
        withAnimation(NotchFeatureMotion.collapseAnimation) {
            isNotchPhaseAnimating = true
            renderedBranchKey = Self.hardwareNotchBranchKey
            notchTransitionScale = 1
            notchTransitionBlur = 0
        }

        notchTransitionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: NotchFeatureMotion.returnDelayNanoseconds)
            guard !Task.isCancelled else { return }
            withAnimation(NotchFeatureMotion.returnAnimation) {
                renderedBranchKey = newBranch
                notchTransitionScale = 1
                notchTransitionBlur = 0
            }
            try? await Task.sleep(nanoseconds: NotchFeatureMotion.returnSettleDelayNanoseconds)
            guard !Task.isCancelled else { return }
            finishNotchPhase(targetBranch: newBranch)
        }
    }

    private func handleCompactAlertBranchChange(from oldBranch: String, to newBranch: String) {
        if isCompactAlertBranch(newBranch) {
            notchBlendMotion = .open
            withAnimation(BatteryNotchMotion.expandAnimation) {
                isNotchPhaseAnimating = true
                renderedBranchKey = newBranch
                notchTransitionScale = 1
                notchTransitionBlur = 0
            }

            notchTransitionTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: BatteryNotchMotion.expandDelayNanoseconds)
                guard !Task.isCancelled else { return }
                finishNotchPhase(targetBranch: newBranch)
            }
            return
        }

        notchBlendMotion = .return
        withAnimation(BatteryNotchMotion.collapseAnimation) {
            isNotchPhaseAnimating = true
            renderedBranchKey = Self.hardwareNotchBranchKey
            notchTransitionScale = 1
            notchTransitionBlur = 0
        }

        notchTransitionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: BatteryNotchMotion.collapseDelayNanoseconds)
            guard !Task.isCancelled else { return }
            withAnimation(NotchFeatureMotion.returnAnimation) {
                renderedBranchKey = newBranch
                notchTransitionScale = 1
                notchTransitionBlur = 0
            }
            try? await Task.sleep(nanoseconds: NotchFeatureMotion.returnSettleDelayNanoseconds)
            guard !Task.isCancelled else { return }
            finishNotchPhase(targetBranch: newBranch)
        }
    }

    private func shouldUseGlobalFeatureMotion(from oldBranch: String, to newBranch: String) -> Bool {
        oldBranch != newBranch
            && oldBranch != Self.hardwareNotchBranchKey
            && newBranch != Self.hardwareNotchBranchKey
    }

    private func isGrowingTransition(from oldBranch: String, to newBranch: String) -> Bool {
        visualArea(for: newBranch) >= visualArea(for: oldBranch)
    }

    private func visualArea(for key: String) -> CGFloat {
        let size = currentVisibleSize(for: key)
        return size.width * size.height
    }

    private func resetNotchTransition() {
        isNotchPhaseAnimating = false
        suppressCollapsedMusicMarquee = false
        calendarTransitionActive = false
        guard notchTransitionScale != 1 || notchTransitionBlur != 0 else { return }

        withAnimation(NotchFeatureMotion.returnAnimation) {
            notchTransitionScale = 1
            notchTransitionBlur = 0
        }
    }

    private func finishNotchPhase(targetBranch: String) {
        suppressCollapsedMusicMarquee = isCollapsedMusicMarqueeBranch(targetBranch) && appState.isHovering
        if !isBatteryAlertBranch(targetBranch), batteryAlerts.currentPresentation == nil {
            renderedBatteryPresentation = nil
        }
        if !isFocusModeBranch(targetBranch), focusMode.currentPresentation == nil {
            renderedFocusPresentation = nil
        }
        if !isScreenLockBranch(targetBranch), screenLock.currentPresentation == nil {
            renderedScreenLockPresentation = nil
        }
        withTransaction(Transaction(animation: nil)) {
            calendarCountdownShapeReveal = 1
            isNotchPhaseAnimating = false
            calendarTransitionActive = false
        }
    }

    @ViewBuilder
    private func branchView(for key: String) -> some View {
        switch key {
        case "battery-low", "battery-charging":
            if let presentation = batteryAlerts.currentPresentation ?? renderedBatteryPresentation {
                BatteryAlertView(presentation: presentation)
            } else {
                CollapsedNotchContent(isHovering: appState.isHovering)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
        case "focus-mode":
            if let presentation = focusMode.currentPresentation ?? renderedFocusPresentation {
                FocusModeAlertView(presentation: presentation)
            } else {
                CollapsedNotchContent(isHovering: appState.isHovering)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
        case "screen-lock":
            if let presentation = screenLock.currentPresentation ?? renderedScreenLockPresentation {
                LockScreenAlertView(presentation: presentation)
            } else {
                CollapsedNotchContent(isHovering: appState.isHovering)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
        case "airdrop-drop-target":
            AirDropZoneView()
        case "expanded-music":
            if let track = nowPlaying.track {
                NowPlayingExpandedView(track: track, morphNamespace: morph)
            } else {
                CalendarNotchView()
            }
        case "expanded-event-detail":
            if let event = countdown.trackedEvent {
                FocusedEventDetailView(event: event)
            } else {
                CalendarNotchView()
            }
        case "expanded-bare":
            CalendarNotchView()
        case "expanded-onboarding":
            OnboardingView {
                settings.hasCompletedOnboarding = true
                appState.collapse()
            } onWelcomeAnimationFinished: {
                guard onboardingStage == .welcome else { return }
                withAnimation(OnboardingHeightMotion.expandAnimation) {
                    onboardingStage = .button
                }
            }
        case "onboarding-lock":
            OnboardingLockNotchView(isUnlocked: onboardingStage == .unlocking)
        case "hud":
            if let kind = hud.current {
                HUDBarView(kind: kind)
                    .padding(.bottom, 2)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                CollapsedNotchContent(isHovering: appState.isHovering)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
        case Self.hardwareNotchBranchKey:
            Color.clear
        case "collapsed-music":
            if let track = nowPlaying.track {
                NowPlayingCollapsedView(
                    track: track,
                    isHovering: shouldShowCollapsedMusicMarquee(for: key),
                    morphNamespace: morph
                )
            } else {
                CollapsedNotchContent(isHovering: appState.isHovering)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
        case "event-collapsed":
            if let presentation = countdown.presentation,
               let event = countdown.trackedEvent {
                EventCountdownCollapsedView(
                    presentation: presentation,
                    event: event,
                    side: .left
                )
            } else {
                CollapsedNotchContent(isHovering: appState.isHovering)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
        case "collapsed-music-event":
            if let track = nowPlaying.track,
               let presentation = countdown.presentation,
               let event = countdown.trackedEvent {
                CollapsedMusicEventView(
                    track: track,
                    presentation: presentation,
                    event: event,
                    isHovering: shouldShowCollapsedMusicMarquee(for: key),
                    morphNamespace: morph
                )
            } else if let track = nowPlaying.track {
                NowPlayingCollapsedView(
                    track: track,
                    isHovering: shouldShowCollapsedMusicMarquee(for: key),
                    morphNamespace: morph
                )
            } else {
                CollapsedNotchContent(isHovering: appState.isHovering)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
        default:
            CollapsedNotchContent(isHovering: appState.isHovering)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
        }
    }

    /// A stable identifier for "which content is showing right now."
    /// Hover doesn't change the branch — only state transitions do — so the
    /// marquee fading in/out under music is handled inside the branch itself.
    private var branchKey: String {
        // First-launch onboarding takes precedence over everything else.
        // We stay collapsed until the launch task explicitly expands AppState,
        // then the branch change triggers the standard growing spring.
        if !settings.hasCompletedOnboarding {
            return didRevealOnboarding && appState.isExpanded
                ? "expanded-onboarding"
                : "onboarding-lock"
        }
        if let presentation = screenLock.currentPresentation {
            return presentation.branchKey
        }
        if airDrop.isDropTargetVisible {
            return "airdrop-drop-target"
        }
        if let presentation = batteryAlerts.currentPresentation {
            return presentation.branchKey
        }
        if let presentation = focusMode.currentPresentation {
            return presentation.branchKey
        }
        if appState.isExpanded {
            if countdown.isDetailPresented, countdown.trackedEvent != nil {
                return "expanded-event-detail"
            }
            return nowPlaying.track != nil ? "expanded-music" : "expanded-bare"
        }
        if hud.current != nil { return "hud" }
        let hasEvent = countdown.presentation != nil
        if nowPlaying.track != nil {
            return hasEvent ? "collapsed-music-event" : "collapsed-music"
        }
        if hasEvent { return "event-collapsed" }
        return "collapsed-bare"
    }

    private var visualBranchKey: String {
        renderedBranchKey ?? branchKey
    }

    private func isExpandedBranch(_ key: String) -> Bool {
        key.hasPrefix("expanded")
    }

    private func isOnboardingBranch(_ key: String) -> Bool {
        key == "expanded-onboarding" || key == "onboarding-lock"
    }

    private func isMusicBranch(_ key: String) -> Bool {
        key.contains("music")
    }

    private func isBatteryAlertBranch(_ key: String) -> Bool {
        key.hasPrefix("battery-")
    }

    private func isFocusModeBranch(_ key: String) -> Bool {
        key == "focus-mode"
    }

    private func isScreenLockBranch(_ key: String) -> Bool {
        key == "screen-lock"
    }

    private func isCalendarCountdownBranch(_ key: String) -> Bool {
        key == "event-collapsed" || key == "collapsed-music-event"
    }

    private func isCalendarSurfaceBranch(_ key: String) -> Bool {
        isCalendarCountdownBranch(key)
            || key == "expanded-event-detail"
            || key == "expanded-bare"
    }

    private func isAirDropDropBranch(_ key: String) -> Bool {
        key == "airdrop-drop-target"
    }

    private func isCompactAlertBranch(_ key: String) -> Bool {
        isBatteryAlertBranch(key) || isFocusModeBranch(key) || isScreenLockBranch(key)
            || isAirDropDropBranch(key)
    }

    private func isCollapsedMusicMarqueeBranch(_ key: String) -> Bool {
        key == "collapsed-music" || key == "collapsed-music-event"
    }

    private func shouldShowCollapsedMusicMarquee(for key: String) -> Bool {
        isCollapsedMusicMarqueeBranch(key)
            && branchKey == key
            && appState.isHovering
            && !isNotchPhaseAnimating
            && !suppressCollapsedMusicMarquee
    }

    private func currentCornerRadius(size: CGSize) -> CGFloat {
        isExpandedBranch(visualBranchKey) ? settings.cornerRadius : size.height / 2
    }

    private func currentVisibleSize(for key: String) -> CGSize {
        let baseWidth = CGFloat(settings.collapsedWidth)
        let baseHeight = CGFloat(settings.collapsedHeight)
        let hasMusic = isMusicBranch(key)

        // Outer width adds `invertedCornerRadius * 2` for the ears. Per-state
        // values interpolate via the expansion spring, so the outer width
        // morphs smoothly across transitions instead of stepping.
        let extra = invertedCornerRadius(for: key) * 2

        if isExpandedBranch(key) {
            if key == "expanded-onboarding" {
                return CGSize(
                    width: baseWidth + extra,
                    height: onboardingStage == .button
                        ? OnboardingMetrics.buttonHeight
                        : OnboardingMetrics.welcomeHeight
                )
            }
            if key == "expanded-event-detail" {
                return CGSize(
                    width: EventDetailMetrics.eventOnlySize.width + extra,
                    height: EventDetailMetrics.eventOnlySize.height
                )
            }
            if hasMusic {
                return CGSize(
                    width: NowPlayingMetrics.expandedSize.width + extra,
                    height: NowPlayingMetrics.expandedSize.height
                )
            }
            return CGSize(
                width: max(CGFloat(settings.expandedWidth), CalendarNotchMetrics.expandedSize.width) + extra,
                height: CalendarNotchMetrics.expandedSize.height
            )
        }
        if key == "hud" {
            let bodyW = max(baseWidth, HUDController.drawerMinWidth)
            return CGSize(width: bodyW + extra, height: baseHeight + HUDController.drawerHeight)
        }
        if key == "onboarding-lock" {
            let bodyW = max(baseWidth, OnboardingLockNotchMetrics.bodyWidth)
            return CGSize(width: bodyW + extra, height: OnboardingLockNotchMetrics.height)
        }
        if isBatteryAlertBranch(key) {
            let batteryWidth = (batteryAlerts.currentPresentation ?? renderedBatteryPresentation)
                .map(BatteryAlertMetrics.width(for:)) ?? BatteryAlertMetrics.chargingWidth
            let bodyW = max(baseWidth, batteryWidth)
            return CGSize(width: bodyW + extra, height: baseHeight)
        }
        if isFocusModeBranch(key) {
            let bodyW = max(baseWidth, FocusModeAlertMetrics.width)
            return CGSize(width: bodyW + extra, height: baseHeight)
        }
        if isScreenLockBranch(key) {
            let bodyW = max(baseWidth, LockScreenAlertMetrics.width)
            return CGSize(width: bodyW + extra, height: LockScreenAlertMetrics.fallbackHeight)
        }
        if isAirDropDropBranch(key) {
            let bodyW = max(baseWidth, AirDropZoneMetrics.width)
            return CGSize(width: bodyW + extra, height: AirDropZoneMetrics.height)
        }
        if key == Self.hardwareNotchBranchKey {
            return CGSize(width: baseWidth + extra, height: baseHeight)
        }
        if key == "collapsed-music-event" {
            let bodyW = EventCountdownChipMetrics.musicComboContainerBodyWidth(baseWidth: baseWidth)
            let extraH = shouldShowCollapsedMusicMarquee(for: key)
                ? NowPlayingMetrics.hoverExtraHeight
                : NowPlayingMetrics.collapsedExtraHeight
            return CGSize(width: bodyW + extra, height: baseHeight + extraH)
        }
        if hasMusic {
            let bodyW = max(baseWidth, NowPlayingMetrics.collapsedWidth)
            let extraH = shouldShowCollapsedMusicMarquee(for: key)
                ? NowPlayingMetrics.hoverExtraHeight
                : NowPlayingMetrics.collapsedExtraHeight
            return CGSize(width: bodyW + extra, height: baseHeight + extraH)
        }
        if key == "event-collapsed" {
            let bodyW = EventCountdownChipMetrics.eventOnlyContainerBodyWidth(baseWidth: baseWidth)
            return CGSize(width: bodyW + extra, height: baseHeight)
        }
        if appState.isHovering {
            return CGSize(width: baseWidth + extra + 25, height: baseHeight + 10)
        }
        return CGSize(width: baseWidth + extra, height: baseHeight)
    }
}

private enum OnboardingStage {
    case locked
    case unlocking
    case welcome
    case button
}

private enum OnboardingHeightMotion {
    static let expandAnimation: Animation = .easeInOut(duration: 0.82)
    static let contentAnimation: Animation = .easeInOut(duration: 0.22)
}

private enum NotchFeatureMotion {
    static let openingScale: CGFloat = 0.72
    static let openingBlurRadius: CGFloat = 8
    static let containerBlurRadius: CGFloat = 12
    static let contentBlurRadius: CGFloat = 11
    static let collapseDuration: TimeInterval = 0.31
    static let openCompressDuration: TimeInterval = 0.18
    static let returnDelay: TimeInterval = collapseDuration
    static let openCompressDelay: TimeInterval = openCompressDuration
    static let openSettleDelay: TimeInterval = 0.34
    static let returnSettleDelay: TimeInterval = 0.48
    static let returnDelayNanoseconds = UInt64(returnDelay * 1_000_000_000)
    static let openCompressDelayNanoseconds = UInt64(openCompressDelay * 1_000_000_000)
    static let openSettleDelayNanoseconds = UInt64(openSettleDelay * 1_000_000_000)
    static let returnSettleDelayNanoseconds = UInt64(returnSettleDelay * 1_000_000_000)
    static let openKickDelayNanoseconds: UInt64 = 12_000_000

    static let collapseAnimation: Animation = .easeInOut(duration: collapseDuration)
    static let openCompressAnimation: Animation = .easeInOut(duration: openCompressDuration)
    static let openAnimation: Animation = .spring(
        response: 0.39,
        dampingFraction: 0.86,
        blendDuration: 0
    )
    static let returnAnimation: Animation = .spring(
        response: 0.49,
        dampingFraction: 0.86,
        blendDuration: 0
    )
}

private enum OnboardingNotchMotion {
    static let openingScale: CGFloat = 0.78
    static let openingBlurRadius: CGFloat = 8
    static let collapseDuration: TimeInterval = 0.52
    static let openCompressDuration: TimeInterval = 0.28
    static let returnDelay: TimeInterval = collapseDuration
    static let openSettleDelay: TimeInterval = 0.58
    static let returnSettleDelay: TimeInterval = 0.72
    static let openCompressDelayNanoseconds = UInt64(openCompressDuration * 1_000_000_000)
    static let returnDelayNanoseconds = UInt64(returnDelay * 1_000_000_000)
    static let openSettleDelayNanoseconds = UInt64(openSettleDelay * 1_000_000_000)
    static let returnSettleDelayNanoseconds = UInt64(returnSettleDelay * 1_000_000_000)
    static let openKickDelayNanoseconds: UInt64 = 12_000_000

    static let collapseAnimation: Animation = .easeInOut(duration: collapseDuration)
    static let openCompressAnimation: Animation = .easeInOut(duration: openCompressDuration)
    static let openAnimation: Animation = .spring(
        response: 0.62,
        dampingFraction: 0.9,
        blendDuration: 0
    )
    static let returnAnimation: Animation = .spring(
        response: 0.74,
        dampingFraction: 0.9,
        blendDuration: 0
    )
}

private enum BatteryNotchMotion {
    static let expandDelayNanoseconds = UInt64(
        BatteryPresentationTiming.expandDuration * 1_000_000_000
    )
    static let collapseDelayNanoseconds = UInt64(
        BatteryPresentationTiming.collapseDuration * 1_000_000_000
    )

    static let expandAnimation: Animation = .spring(
        response: BatteryPresentationTiming.expandDuration,
        dampingFraction: 0.86,
        blendDuration: 0
    )
    static let collapseAnimation: Animation = .easeInOut(
        duration: BatteryPresentationTiming.collapseDuration
    )
}

private struct FeatureContentBlendTransitionModifier: ViewModifier, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let hiddenProgress = 1 - progress

        content
            .scaleEffect(0.66 + progress * 0.34, anchor: .top)
            .blur(radius: hiddenProgress * NotchFeatureMotion.contentBlurRadius)
            .opacity(Double(progress))
            .offset(y: -hiddenProgress * 10)
            .compositingGroup()
    }
}

private enum FeatureBlendMotion {
    case open
    case `return`
}

private extension AnyTransition {
    static func featureBlend(_ motion: FeatureBlendMotion) -> AnyTransition {
        switch motion {
        case .open:
            return .asymmetric(
                insertion: .featureContentBlend.animation(NotchFeatureMotion.openAnimation),
                removal: .featureContentBlend.animation(NotchFeatureMotion.openCompressAnimation)
            )
        case .return:
            return .asymmetric(
                insertion: .featureContentBlend.animation(NotchFeatureMotion.returnAnimation),
                removal: .featureContentBlend.animation(NotchFeatureMotion.collapseAnimation)
            )
        }
    }

    private static var featureContentBlend: AnyTransition {
        .modifier(
            active: FeatureContentBlendTransitionModifier(progress: 0),
            identity: FeatureContentBlendTransitionModifier(progress: 1)
        )
    }
}

// MARK: - NotchDrop-style notch shape (single Path)

/// A single `Shape` for the entire NotchDrop-style outline: rounded bottom
/// corners + flat top edge + concave (inverted) curves at the top-outer
/// corners. Renders in one pass with no compositing groups, no overlays, no
/// destination-out blend modes — that's what eliminates the "ears attach a
/// frame later" glitch the layered mask exhibited. `animatableData`
/// interpolates both radii together so every transition is one continuous
/// path tween.
struct NotchDropShape: Shape {
    /// Radius of the inverted top-outer corners (the "ears"). When `0`, the
    /// shape degenerates to a plain rounded-bottom rectangle (collapsed
    /// capsule look). When `> 0`, the body's top edge is shorter than its
    /// bottom edge by `2 * invertedCornerRadius`, with a concave quarter-arc
    /// at each top corner.
    var invertedCornerRadius: CGFloat
    /// Radius of the body's bottom-left and bottom-right corners.
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(invertedCornerRadius, bottomCornerRadius) }
        set {
            invertedCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        guard w > 0, h > 0 else { return path }

        let ir = max(0, min(invertedCornerRadius, min(w / 2, h)))
        let br = max(0, min(bottomCornerRadius, min((w - ir * 2) / 2, h - ir)))

        // Outline traced clockwise on screen, starting at the top-left
        // (top-outer corner of the left ear).
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: w, y: 0))

        // Right inverted (concave) top-outer corner: arc from (w, 0) curving
        // inward to (w - ir, ir). Arc center is at (w, ir) so the curve
        // bulges *into* the body's interior — a concave bite from outside.
        if ir > 0 {
            path.addArc(
                center: CGPoint(x: w, y: ir),
                radius: ir,
                startAngle: .degrees(270),  // direction: up
                endAngle: .degrees(180),    // direction: left
                clockwise: true             // math CW = short way
            )
        }

        // Body's right edge.
        path.addLine(to: CGPoint(x: w - ir, y: h - br))

        // Bottom-right rounded corner.
        if br > 0 {
            path.addArc(
                center: CGPoint(x: w - ir - br, y: h - br),
                radius: br,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
        }

        // Bottom edge.
        path.addLine(to: CGPoint(x: ir + br, y: h))

        // Bottom-left rounded corner.
        if br > 0 {
            path.addArc(
                center: CGPoint(x: ir + br, y: h - br),
                radius: br,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
        }

        // Body's left edge.
        path.addLine(to: CGPoint(x: ir, y: ir))

        // Left inverted (concave) top-outer corner: mirror of the right.
        if ir > 0 {
            path.addArc(
                center: CGPoint(x: 0, y: ir),
                radius: ir,
                startAngle: .degrees(0),    // direction: right
                endAngle: .degrees(270),    // direction: up (= -90°)
                clockwise: true
            )
        }

        path.closeSubpath()
        return path
    }
}

private struct NotchDropBorderShape: Shape {
    var invertedCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(invertedCornerRadius, bottomCornerRadius) }
        set {
            invertedCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        guard w > 0, h > 0 else { return path }

        let ir = max(0, min(invertedCornerRadius, min(w / 2, h)))
        let br = max(0, min(bottomCornerRadius, min((w - ir * 2) / 2, h - ir)))

        path.move(to: CGPoint(x: w, y: 0))

        if ir > 0 {
            path.addArc(
                center: CGPoint(x: w, y: ir),
                radius: ir,
                startAngle: .degrees(270),
                endAngle: .degrees(180),
                clockwise: true
            )
        }

        path.addLine(to: CGPoint(x: w - ir, y: h - br))

        if br > 0 {
            path.addArc(
                center: CGPoint(x: w - ir - br, y: h - br),
                radius: br,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
        }

        path.addLine(to: CGPoint(x: ir + br, y: h))

        if br > 0 {
            path.addArc(
                center: CGPoint(x: ir + br, y: h - br),
                radius: br,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
        }

        path.addLine(to: CGPoint(x: ir, y: ir))

        if ir > 0 {
            path.addArc(
                center: CGPoint(x: 0, y: ir),
                radius: ir,
                startAngle: .degrees(0),
                endAngle: .degrees(270),
                clockwise: true
            )
        }

        return path
    }
}

struct CalendarCountdownNotchShape: Shape {
    var leftBodyWidth: CGFloat
    var rightBodyWidth: CGFloat
    var invertedCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>> {
        get {
            AnimatablePair(
                leftBodyWidth,
                AnimatablePair(
                    rightBodyWidth,
                    AnimatablePair(invertedCornerRadius, bottomCornerRadius)
                )
            )
        }
        set {
            leftBodyWidth = newValue.first
            rightBodyWidth = newValue.second.first
            invertedCornerRadius = newValue.second.second.first
            bottomCornerRadius = newValue.second.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        guard w > 0, h > 0 else { return path }

        let leftBody = max(0, leftBodyWidth)
        let rightBody = max(0, rightBodyWidth)
        let ir = max(0, min(invertedCornerRadius, min(w / 2, h)))
        let bodyWidth = max(0, leftBody + rightBody)
        let br = max(0, min(bottomCornerRadius, min(bodyWidth / 2, h - ir)))

        let centerX = w / 2
        let x0 = max(0, centerX - leftBody - ir)
        let x1 = min(w, centerX + rightBody + ir)
        guard x1 > x0 else { return path }

        path.move(to: CGPoint(x: x0, y: 0))
        path.addLine(to: CGPoint(x: x1, y: 0))

        if ir > 0 {
            path.addArc(
                center: CGPoint(x: x1, y: ir),
                radius: ir,
                startAngle: .degrees(270),
                endAngle: .degrees(180),
                clockwise: true
            )
        }

        path.addLine(to: CGPoint(x: x1 - ir, y: h - br))

        if br > 0 {
            path.addArc(
                center: CGPoint(x: x1 - ir - br, y: h - br),
                radius: br,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
        }

        path.addLine(to: CGPoint(x: x0 + ir + br, y: h))

        if br > 0 {
            path.addArc(
                center: CGPoint(x: x0 + ir + br, y: h - br),
                radius: br,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
        }

        path.addLine(to: CGPoint(x: x0 + ir, y: ir))

        if ir > 0 {
            path.addArc(
                center: CGPoint(x: x0, y: ir),
                radius: ir,
                startAngle: .degrees(0),
                endAngle: .degrees(270),
                clockwise: true
            )
        }

        path.closeSubpath()
        return path
    }
}

private struct CollapsedNotchContent: View {
    let isHovering: Bool

    var body: some View {
        HStack(spacing: 8) {
//            Text("NotchLand")
//                .font(.system(size: 12, weight: .semibold, design: .rounded))
//                .foregroundStyle(Color.white.opacity(isHovering ? 1.0 : 0.85))
        }
    }
}

private struct NotchInteractionSurface: NSViewRepresentable {
    let onTap: (CGPoint) -> Void

    func makeNSView(context: Context) -> TrackingView {
        TrackingView(onTap: onTap)
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onTap = onTap
    }

    final class TrackingView: NSView {
        var onTap: (CGPoint) -> Void

        private var mouseDownLocation: CGPoint?

        override var isFlipped: Bool { true }

        init(onTap: @escaping (CGPoint) -> Void) {
            self.onTap = onTap
            super.init(frame: .zero)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) not used")
        }

        override var acceptsFirstResponder: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            window?.ignoresMouseEvents = false
            mouseDownLocation = convert(event.locationInWindow, from: nil)
        }

        override func mouseUp(with event: NSEvent) {
            guard let start = mouseDownLocation else { return }
            let current = convert(event.locationInWindow, from: nil)
            let delta = CGPoint(
                x: current.x - start.x,
                y: current.y - start.y
            )

            if hypot(delta.x, delta.y) < 8 {
                onTap(current)
            }

            mouseDownLocation = nil
        }
    }
}

struct FloatingNotchViewPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            NotchShape(topWidth: 189, bottomCornerRadius: 10, shoulderRadius: 0)
                .fill(Color.black)
                .frame(width: 189, height: 32)
                .padding()
                .background(Color.gray.opacity(0.3))
                .previewDisplayName("NotchShape - collapsed")

            NotchShape(topWidth: 189, bottomCornerRadius: 18, shoulderRadius: 18)
                .fill(Color.black)
                .frame(width: 520, height: 140)
                .padding()
                .background(Color.gray.opacity(0.3))
                .previewDisplayName("NotchShape - expanded")
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
