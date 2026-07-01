//
//  WindowManager.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Owns the single floating NSPanel that hosts the notch UI. Reacts to changes
//  in NotchSettings (sizes, visibility) and AppState (expanded/collapsed) by
//  resizing/positioning/hiding the panel.
//
//  All window/AppKit concerns live here; SwiftUI rendering lives in FloatingNotchView.
//

import AppKit
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class WindowManager: NSObject {
    /// The panel is sized once to the *maximum* envelope across all states (Dynamic
    /// Island style) so state changes only animate the SwiftUI shape inside —
    /// no NSWindow resize, no NSHostingView constraint thrash, no overlapping
    /// NSAnimationContext animations to interrupt each other.
    /// Extra space around the visible notch so the SwiftUI shadow has room to render.
    static let shadowHorizontalPadding: CGFloat = 40
    static let shadowBottomPadding: CGFloat = 40

    private enum PanelLevel {
        static let interactive = NSWindow.Level.mainMenu + 3
        static let lockScreen = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
    }

    private let settings: NotchSettings
    private let appState: AppState
    private let hud: HUDController
    private let nowPlaying: NowPlayingService
    private let batteryAlerts: BatteryAlertController
    private let focusMode: FocusModeController
    private let screenLock: ScreenLockController
    private let calendar: CalendarService
    private let eventCountdown: EventCountdownController
    private let airDrop: AirDropController
    private let liveActivities: LiveActivityController
    private let notchTimer: NotchTimerController
    private let updater: UpdaterController

    private var notchPanel: NotchPanel?
    private var dragMonitors: [Any] = []
    private var statusItem: NSStatusItem?
    private var companionWindow: NSWindow?
    private var hoverTimer: Timer?
    private var localScrollMonitor: Any?
    private var globalScrollMonitor: Any?
    private var scrollAccumulator = CGPoint.zero
    private var didTriggerScrollSwipe = false
    private var lastScrollSwipeAt = Date.distantPast
    private var pendingFrameUpdate: DispatchWorkItem?
    private var pendingOnboardingFrameShrink: DispatchWorkItem?
    private var isPointerInsideNotch = false
    private var screenObserver: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []

    private enum ScrollSwipeDirection {
        case up
        case down
    }

    init(
        settings: NotchSettings,
        appState: AppState,
        hud: HUDController,
        nowPlaying: NowPlayingService,
        batteryAlerts: BatteryAlertController,
        focusMode: FocusModeController,
        screenLock: ScreenLockController,
        calendar: CalendarService,
        eventCountdown: EventCountdownController,
        airDrop: AirDropController,
        liveActivities: LiveActivityController,
        notchTimer: NotchTimerController,
        updater: UpdaterController
    ) {
        self.settings = settings
        self.appState = appState
        self.hud = hud
        self.nowPlaying = nowPlaying
        self.batteryAlerts = batteryAlerts
        self.focusMode = focusMode
        self.screenLock = screenLock
        self.calendar = calendar
        self.eventCountdown = eventCountdown
        self.airDrop = airDrop
        self.liveActivities = liveActivities
        self.notchTimer = notchTimer
        self.updater = updater
        super.init()
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let localScrollMonitor {
            NSEvent.removeMonitor(localScrollMonitor)
        }
        if let globalScrollMonitor {
            NSEvent.removeMonitor(globalScrollMonitor)
        }
        for monitor in dragMonitors {
            NSEvent.removeMonitor(monitor)
        }
        pendingOnboardingFrameShrink?.cancel()
        hoverTimer?.invalidate()
    }

    func start() {
        observeSettings()
        observeScreenChanges()
        observeScreenLock()
        applyVisibility()
        startHoverPolling()
        installScrollGestureMonitors()
        installDragMonitors()
        showStatusItem()
        if settings.hasCompletedOnboarding {
            showCompanionWindow()
        }
        // First launch: don't force-expand here. FloatingNotchView starts with
        // a locked glyph in the collapsed notch, springs it open, then expands
        // through the same Dynamic Island-style notch transition.
        applyLaunchAtLoginPreference()
    }

    // MARK: - Observation

    private func observeSettings() {
        settings.$showNotch
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.applyVisibility()
                    self?.refreshStatusMenu()
                }
            }
            .store(in: &cancellables)

        settings.$launchAtLogin
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.applyLaunchAtLoginPreference() }
            }
            .store(in: &cancellables)

        // Panel envelope only changes with user-configured sizes; state transitions
        // animate purely inside SwiftUI, leaving the panel frame untouched.
        Publishers.MergeMany(
            settings.$collapsedWidth.dropFirst().map { _ in () },
            settings.$collapsedHeight.dropFirst().map { _ in () },
            settings.$expandedWidth.dropFirst().map { _ in () },
            settings.$expandedHeight.dropFirst().map { _ in () }
        )
        .sink { [weak self] _ in
            MainActor.assumeIsolated { self?.updateNotchFrame(animated: false) }
        }
        .store(in: &cancellables)

        appState.$isExpanded
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshStatusMenu() }
            }
            .store(in: &cancellables)

        settings.$hasCompletedOnboarding
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] completed in
                MainActor.assumeIsolated {
                    if completed {
                        self?.scheduleOnboardingFrameShrink()
                        self?.showCompanionWindow()
                    } else {
                        self?.pendingOnboardingFrameShrink?.cancel()
                        self?.companionWindow?.orderOut(nil)
                        self?.eventCountdown.clearDetail()
                        self?.appState.resetToCollapsed()
                        self?.applyVisibility()
                        self?.updateNotchFrame(animated: false)
                        self?.notchPanel?.orderFrontRegardless()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func observeScreenLock() {
        screenLock.$currentPresentation
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] presentation in
                MainActor.assumeIsolated {
                    if presentation != nil {
                        self?.pendingFrameUpdate?.cancel()
                        self?.eventCountdown.clearDetail()
                        self?.appState.resetToCollapsed()
                    }
                    self?.applyVisibility()
                    self?.applyPanelLockMode(presentation != nil)
                    if presentation != nil {
                        self?.updateNotchFrame(animated: false)
                        self?.notchPanel?.orderFrontRegardless()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.updateNotchFrame(animated: false)
            }
        }
    }

    // MARK: - Show / Hide

    private func applyVisibility() {
        if settings.showNotch || screenLock.currentPresentation != nil {
            showNotchPanel()
        } else {
            hideNotchPanel()
        }
    }

    private func showNotchPanel() {
        if notchPanel == nil {
            notchPanel = makePanel()
        }
        updateNotchFrame(animated: false)
        notchPanel?.orderFrontRegardless()
    }

    private func hideNotchPanel() {
        notchPanel?.orderOut(nil)
        updatePointerInsideState(false)
    }

    // MARK: - Hover tracking

    private func startHoverPolling() {
        hoverTimer?.invalidate()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pollHoverState()
            }
        }
        hoverTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func pollHoverState() {
        guard settings.showNotch, let panel = notchPanel, panel.isVisible else {
            updatePointerInsideState(false)
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let hoverFrame = interactiveNotchFrame(in: panel).insetBy(dx: -8, dy: -8)
        updatePointerInsideState(hoverFrame.contains(mouseLocation))
    }

    private func updatePointerInsideState(_ isInside: Bool) {
        // Toggle on every poll — the panel covers a large transparent envelope,
        // so we make it ignore mouse events anywhere outside the notch shape so
        // clicks fall through to whatever app sits below. While a file drag
        // hovers the drop zone the panel must keep receiving events so the
        // NSDraggingDestination can accept the drop.
        notchPanel?.ignoresMouseEvents = !isInside && !airDrop.isDropTargetVisible

        // While the HUD is showing, don't propagate hover state to AppState —
        // volume/brightness key bursts shouldn't trigger a hover-to-expand,
        // which would replace the HUD with the expanded panel.
        let effectiveInside = isInside
            && hud.current == nil
            && batteryAlerts.currentPresentation == nil
            && focusMode.currentPresentation == nil
            && screenLock.currentPresentation == nil
            && !airDrop.isDropTargetVisible
            && settings.hasCompletedOnboarding

        guard isPointerInsideNotch != effectiveInside else { return }
        isPointerInsideNotch = effectiveInside

        if effectiveInside {
            appState.mouseEntered()
        } else {
            appState.mouseExited()
        }
    }

    // MARK: - AirDrop drag detection

    private func installDragMonitors() {
        guard dragMonitors.isEmpty else { return }
        if let moved = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { _ in
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.handleGlobalDragMoved() }
            }
        }) {
            dragMonitors.append(moved)
        }
        if let ended = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { _ in
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.handleGlobalDragEnded() }
            }
        }) {
            dragMonitors.append(ended)
        }
    }

    /// How far beyond the actual visible notch shape a drag still counts as
    /// "near" it — generous enough for a dragged Finder icon (coarser than a
    /// bare cursor) but nowhere near the whole screen.
    private static let dragProximityInset: CGFloat = -60

    private func handleGlobalDragMoved() {
        guard settings.airDropEnabled, settings.showNotch else { return }
        guard let panel = notchPanel, panel.isVisible else { return }
        // Proximity zone: a modest halo around the actual visible notch shape,
        // not the whole (much larger) panel envelope.
        let zone = interactiveNotchFrame(in: panel).insetBy(
            dx: Self.dragProximityInset,
            dy: Self.dragProximityInset
        )
        guard zone.contains(NSEvent.mouseLocation), isDraggedContentAirDroppable() else {
            if airDrop.isDropTargetVisible {
                airDrop.dragEnded()
                panel.ignoresMouseEvents = true
            }
            return
        }
        airDrop.dragApproached()
        panel.ignoresMouseEvents = false   // so the panel can receive the drop
    }

    /// Only file drags that AirDrop itself would actually accept should open
    /// the drop zone — not every file drag that merely carries a `.fileURL`.
    private func isDraggedContentAirDroppable() -> Bool {
        guard let urls = NSPasteboard(name: .drag).readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else { return false }
        return AirDropController.canShareViaAirDrop(urls)
    }

    private func handleGlobalDragEnded() {
        guard airDrop.isDropTargetVisible else { return }
        // Give the NSDraggingDestination a beat to process a drop landing on
        // the panel before the branch retracts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.airDrop.isDropTargetVisible else { return }
                self.airDrop.dragEnded()
                self.notchPanel?.ignoresMouseEvents = true
            }
        }
    }

    private func installScrollGestureMonitors() {
        guard localScrollMonitor == nil, globalScrollMonitor == nil else { return }

        localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return event }
                return self.handleScrollGesture(event) ? nil : event
            }
        }

        globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    _ = self?.handleScrollGesture(event)
                }
            }
        }
    }

    private func handleScrollGesture(_ event: NSEvent) -> Bool {
        guard settings.showNotch, let panel = notchPanel, panel.isVisible else {
            resetScrollGesture()
            return false
        }

        let gestureFrame = interactiveNotchFrame(in: panel).insetBy(dx: -10, dy: -10)
        guard gestureFrame.contains(NSEvent.mouseLocation) else {
            resetScrollGesture()
            return false
        }

        if shouldLetExpandedCalendarHandleScroll(in: gestureFrame) {
            resetScrollGesture()
            return false
        }

        guard event.momentumPhase.isEmpty else {
            if event.momentumPhase == .ended || event.momentumPhase == .cancelled {
                resetScrollGesture()
            }
            return false
        }

        if event.phase == .began || event.phase == .mayBegin {
            resetScrollGesture()
        }

        scrollAccumulator.x += normalizedScrollDeltaX(for: event)
        scrollAccumulator.y += normalizedScrollDeltaY(for: event)

        let didHandle: Bool
        if !didTriggerScrollSwipe, canTriggerScrollSwipe, isVerticalScrollSwipe(scrollAccumulator) {
            didTriggerScrollSwipe = true
            lastScrollSwipeAt = Date()
            handleTrackpadSwipe(scrollAccumulator.y < 0 ? .down : .up)
            didHandle = true
        } else {
            didHandle = false
        }

        if event.phase == .ended ||
            event.phase == .cancelled {
            resetScrollGesture()
        }

        return didHandle
    }

    private var canTriggerScrollSwipe: Bool {
        Date().timeIntervalSince(lastScrollSwipeAt) > 0.45
    }

    private func normalizedScrollDeltaX(for event: NSEvent) -> CGFloat {
        normalizedScrollDelta(for: event, value: event.scrollingDeltaX)
    }

    private func normalizedScrollDeltaY(for event: NSEvent) -> CGFloat {
        normalizedScrollDelta(for: event, value: event.scrollingDeltaY)
    }

    private func normalizedScrollDelta(for event: NSEvent, value: CGFloat) -> CGFloat {
        let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 8
        let inversion: CGFloat = event.isDirectionInvertedFromDevice ? -1 : 1
        return value * multiplier * inversion
    }

    private func isVerticalScrollSwipe(_ delta: CGPoint) -> Bool {
        let verticalDistance = abs(delta.y)
        let horizontalDistance = abs(delta.x)
        return verticalDistance >= 26 && verticalDistance > horizontalDistance * 1.2
    }

    private func shouldLetExpandedCalendarHandleScroll(in gestureFrame: NSRect) -> Bool {
        guard settings.hasCompletedOnboarding,
              appState.isExpanded,
              nowPlaying.track == nil,
              !eventCountdown.isDetailPresented,
              batteryAlerts.currentPresentation == nil,
              focusMode.currentPresentation == nil,
              hud.current == nil else {
            return false
        }

        let bodyWidth = max(CGFloat(settings.expandedWidth), CalendarNotchMetrics.expandedSize.width)
        let bodyLeft = gestureFrame.midX - bodyWidth / 2
        let agendaLeft = bodyLeft
            + 18 // CalendarNotchView horizontal padding
            + CalendarNotchMetrics.monthColumnWidth
            + 16 // HStack spacing between month and agenda

        return NSEvent.mouseLocation.x >= agendaLeft - 6
    }

    private func handleTrackpadSwipe(_ direction: ScrollSwipeDirection) {
        switch direction {
        case .up:
            handleTrackpadSwipeUp()
        case .down:
            handleTrackpadSwipeDown()
        }
    }

    private func handleTrackpadSwipeDown() {
        guard batteryAlerts.currentPresentation == nil,
              focusMode.currentPresentation == nil,
              screenLock.currentPresentation == nil,
              hud.current == nil,
              !appState.isExpanded else {
            return
        }

        if eventCountdown.presentation != nil, eventCountdown.trackedEvent != nil {
            eventCountdown.showDetail()
        }
        appState.expand()
    }

    private func handleTrackpadSwipeUp() {
        if batteryAlerts.currentPresentation != nil {
            batteryAlerts.dismissCurrentPresentation()
            return
        }

        if focusMode.currentPresentation != nil {
            focusMode.dismissCurrentPresentation()
            return
        }

        if hud.current != nil {
            hud.dismissCurrent()
            return
        }

        guard appState.isExpanded else { return }
        eventCountdown.clearDetail()
        appState.collapse()
    }

    private func resetScrollGesture() {
        scrollAccumulator = .zero
        didTriggerScrollSwipe = false
    }

    private func interactiveNotchFrame(in panel: NSPanel) -> NSRect {
        // Notch is centered horizontally at the panel's top edge. With a constant
        // panel envelope we can't derive its rect from the panel frame; we have to
        // compute the visible size from current state.
        let visible = currentVisibleSize()
        let panelFrame = panel.frame
        return NSRect(
            x: panelFrame.midX - visible.width / 2,
            y: panelFrame.maxY - visible.height,
            width: visible.width,
            height: visible.height
        )
    }

    // MARK: - Menu bar companion

    private func showStatusItem() {
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                if let image = NSImage(named: "MenuBarIcon") {
                    image.isTemplate = true
                    // Scale to the menu bar's height while preserving the notch's 2:1 aspect ratio.
                    let height: CGFloat = 18
                    image.size = NSSize(width: height * (image.size.width / image.size.height), height: height)
                    button.image = image
                    button.imagePosition = .imageOnly
                } else {
                    button.title = "NL"
                }
                button.toolTip = "NotchLand"
            }
            item.menu = NSMenu()
            statusItem = item
        }
        refreshStatusMenu()
    }

    private func refreshStatusMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()
        menu.autoenablesItems = false

        let titleItem = NSMenuItem(title: "NotchLand", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        let showItem = makeMenuItem(title: "Show Notch", action: #selector(toggleNotch), key: "n")
        showItem.state = settings.showNotch ? .on : .off
        menu.addItem(showItem)

        let expandItem = makeMenuItem(
            title: appState.isExpanded ? "Collapse Notch" : "Expand Notch",
            action: #selector(toggleExpansion),
            key: "e"
        )
        expandItem.isEnabled = settings.showNotch
        menu.addItem(expandItem)

        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "Settings", action: #selector(openCompanionWindow), key: ","))
        menu.addItem(makeMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), key: ""))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "Quit NotchLand", action: #selector(quit), key: "q"))
    }

    private func makeMenuItem(title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleNotch() {
        settings.showNotch.toggle()
        refreshStatusMenu()
    }

    @objc private func checkForUpdates() {
        updater.checkForUpdates()
    }

    @objc private func toggleExpansion() {
        appState.toggle()
        refreshStatusMenu()
    }

    @objc private func openCompanionWindow() {
        showCompanionWindow()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - System integration

    private func applyLaunchAtLoginPreference() {
        do {
            if settings.launchAtLogin {
                guard SMAppService.mainApp.status != .enabled else { return }
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("NotchLand failed to update launch-at-login: \(error.localizedDescription)")
        }
    }

    // MARK: - Companion window

    private func showCompanionWindow() {
        if companionWindow == nil {
            companionWindow = makeCompanionWindow()
        }

        guard let companionWindow else { return }
        companionWindow.center()
        companionWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeCompanionWindow() -> NSWindow {
        let hosting = NSHostingView(
            rootView: SettingsView()
                .environmentObject(settings)
                .environmentObject(appState)
                .environmentObject(hud)
                .environmentObject(batteryAlerts)
                .environmentObject(focusMode)
                .environmentObject(screenLock)
                .environmentObject(calendar)
                .environmentObject(eventCountdown)
                .environmentObject(airDrop)
                .environmentObject(liveActivities)
                .environmentObject(notchTimer)
                .environmentObject(updater)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NotchLand Settings"
        window.titleVisibility = .visible
        window.contentMinSize = NSSize(width: 720, height: 480)
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        return window
    }

    // MARK: - Panel construction

    private func makePanel() -> NotchPanel {
        let panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false   // shadow drawn by SwiftUI so intensity is configurable
        panel.isFloatingPanel = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.becomesKeyOnlyIfNeeded = true
        // The envelope panel covers a large transparent area; ignore mouse events
        // by default so clicks pass through, and only re-enable when the hover
        // poll confirms the cursor is inside the visible notch shape.
        panel.ignoresMouseEvents = true
        panel.level = panelLevel(forScreenLockPresentation: screenLock.currentPresentation)
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let hosting = NotchHostingView(
            rootView: FloatingNotchView()
                .environmentObject(settings)
                .environmentObject(appState)
                .environmentObject(hud)
                .environmentObject(nowPlaying)
                .environmentObject(batteryAlerts)
                .environmentObject(focusMode)
                .environmentObject(screenLock)
                .environmentObject(calendar)
                .environmentObject(eventCountdown)
                .environmentObject(airDrop)
                .environmentObject(liveActivities)
                .environmentObject(notchTimer)
        )
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layerContentsRedrawPolicy = .onSetNeedsDisplay
        hosting.airDrop = airDrop
        hosting.registerForDraggedTypes([.fileURL])
        panel.contentView = hosting
        applyBackingScale(to: panel)
        SkyLightWindowBridge.shared.delegateWindow(
            panel,
            to: screenLock.currentPresentation == nil ? .notchSurface : .lockScreenNotchOverlay
        )
        return panel
    }

    private func panelLevel(forScreenLockPresentation presentation: ScreenLockController.Presentation?) -> NSWindow.Level {
        presentation == nil ? PanelLevel.interactive : PanelLevel.lockScreen
    }

    private func applyPanelLockMode(_ isLockedOrUnlocking: Bool) {
        guard let panel = notchPanel else { return }
        panel.level = isLockedOrUnlocking ? PanelLevel.lockScreen : PanelLevel.interactive
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        SkyLightWindowBridge.shared.delegateWindow(
            panel,
            to: isLockedOrUnlocking ? .lockScreenNotchOverlay : .notchSurface
        )
    }

    private func applyBackingScale(to panel: NSPanel) {
        let scale = panel.screen?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2.0
        panel.contentView?.layer?.contentsScale = scale
        applyScaleRecursively(panel.contentView, scale: scale)
    }

    private func applyScaleRecursively(_ view: NSView?, scale: CGFloat) {
        guard let view else { return }
        view.layer?.contentsScale = scale
        for sub in view.subviews { applyScaleRecursively(sub, scale: scale) }
    }

    // MARK: - Frame

    /// Sets the panel to the maximum envelope across all states. The panel never
    /// resizes for state transitions — only when settings or screen change. This
    /// is the single source of "no panel-resize during animation" guarantees.
    private func updateNotchFrame(animated: Bool) {
        _ = animated  // kept for source compatibility; envelope resize is never animated.
        guard let panel = notchPanel else { return }
        guard let screen = resolvedScreen(for: panel) else { return }

        let envelope = panelEnvelopeSize()
        let panelWidth = envelope.width + Self.shadowHorizontalPadding * 2
        let panelHeight = envelope.height + Self.shadowBottomPadding
        let screenFrame = screen.frame
        let originX = screenFrame.midX - panelWidth / 2
        let originY = screenFrame.maxY - panelHeight   // panel top-edge at screen top
        let newFrame = NSRect(x: originX, y: originY, width: panelWidth, height: panelHeight)

        applyBackingScale(to: panel)
        panel.setFrame(newFrame, display: true)
    }

    /// The widest/tallest the visible notch can ever be across collapsed, peek,
    /// HUD, now-playing, and expanded states. Reserves the *largest possible*
    /// `invertedCornerRadius * 2` (the expanded value) so every state fits
    /// within a constant panel envelope.
    private func panelEnvelopeSize() -> CGSize {
        let baseWidth = CGFloat(settings.collapsedWidth)
        let baseHeight = CGFloat(settings.collapsedHeight)

        let extra = FloatingNotchView.expandedInvertedRadius * 2

        // Onboarding contributes to the envelope only when it could be shown —
        // once the user has tapped GET STARTED, the envelope shrinks back to
        // the regular feature footprint on the next frame update.
        let onboardingWidth: CGFloat = settings.hasCompletedOnboarding
            ? 0
            : max(OnboardingMetrics.expandedStepSize.width, OnboardingLockNotchMetrics.bodyWidth)
        let onboardingHeight: CGFloat = settings.hasCompletedOnboarding
            ? 0
            : max(OnboardingMetrics.expandedStepSize.height, OnboardingLockNotchMetrics.height)

        let expandedWidth = max(
            CGFloat(settings.expandedWidth),
            NowPlayingMetrics.expandedSize.width,
            CalendarNotchMetrics.expandedSize.width,
            EventDetailMetrics.eventOnlySize.width,
            onboardingWidth
        )
        let expandedHeight = max(
            CGFloat(settings.expandedHeight),
            NowPlayingMetrics.expandedSize.height,
            CalendarNotchMetrics.expandedSize.height,
            EventDetailMetrics.eventOnlySize.height,
            onboardingHeight
        )

        let collapsedFamilyWidth = max(
            baseWidth,
            HUDController.drawerMinWidth,
            NowPlayingMetrics.collapsedWidth,
            EventCountdownChipMetrics.musicComboContainerBodyWidth(baseWidth: baseWidth),
            EventCountdownChipMetrics.eventOnlyContainerBodyWidth(baseWidth: baseWidth),
            BatteryAlertMetrics.maxWidth,
            FocusModeAlertMetrics.maxWidth,
            LockScreenAlertMetrics.maxWidth
        )
        let collapsedFamilyHeight = max(
            baseHeight + max(
                HUDController.drawerHeight,
                NowPlayingMetrics.collapsedExtraHeight,
                NowPlayingMetrics.hoverExtraHeight,
                10 // bare hover-peek extra height
            ),
            BatteryAlertMetrics.maxHeight,
            FocusModeAlertMetrics.maxHeight,
            LockScreenAlertMetrics.maxHeight
        )

        return CGSize(
            width: max(expandedWidth, collapsedFamilyWidth) + extra,
            height: max(expandedHeight, collapsedFamilyHeight)
        )
    }

    private func scheduleNotchFrameUpdate(animated: Bool) {
        pendingFrameUpdate?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.pendingFrameUpdate = nil
                self?.updateNotchFrame(animated: animated)
            }
        }
        pendingFrameUpdate = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func scheduleOnboardingFrameShrink() {
        pendingOnboardingFrameShrink?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.pendingOnboardingFrameShrink = nil
                self?.updateNotchFrame(animated: false)
            }
        }
        pendingOnboardingFrameShrink = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: workItem)
    }

    private func resolvedScreen(for panel: NSPanel?) -> NSScreen? {
        panel?.screen ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Mirrors `FloatingNotchView.currentVisibleSize` so the AppKit-level hover
    /// frame matches the SwiftUI-rendered shape — including the per-state
    /// `invertedCornerRadius * 2` reserved for the NotchDrop-style ears.
    private func currentVisibleSize() -> CGSize {
        let baseWidth = CGFloat(settings.collapsedWidth)
        let baseHeight = CGFloat(settings.collapsedHeight)
        let hasMusic = nowPlaying.track != nil
        let hasEvent = eventCountdown.presentation != nil
        let batteryPresentation = batteryAlerts.currentPresentation
        let focusPresentation = focusMode.currentPresentation
        let screenLockPresentation = screenLock.currentPresentation

        let invertedR: CGFloat
        if batteryPresentation != nil || focusPresentation != nil || screenLockPresentation != nil
            || airDrop.isDropTargetVisible {
            invertedR = FloatingNotchView.musicInvertedRadius
        } else {
            invertedR = FloatingNotchView.invertedRadius(
                isExpanded: appState.isExpanded,
                hasMusic: hasMusic,
                isHovering: appState.isHovering
            )
        }
        let extra = invertedR * 2

        // Onboarding overrides every other state so the hover hit-test matches
        // the rendered welcome card.
        if !settings.hasCompletedOnboarding {
            guard appState.isExpanded else {
                return CGSize(
                    width: max(baseWidth, OnboardingLockNotchMetrics.bodyWidth)
                        + FloatingNotchView.bareInvertedRadius * 2,
                    height: OnboardingLockNotchMetrics.height
                )
            }

            // Uses the largest wizard-step size regardless of which step is
            // actually showing — SwiftUI-side wizard state isn't mirrored
            // here, and a hover hit-test that's briefly larger than the
            // rendered welcome step has no visible effect (onboarding
            // advances by explicit taps, not hover).
            return CGSize(
                width: OnboardingMetrics.expandedStepSize.width + FloatingNotchView.bareInvertedRadius * 2,
                height: OnboardingMetrics.expandedStepSize.height
            )
        }

        if screenLockPresentation != nil {
            let bodyW = max(baseWidth, LockScreenAlertMetrics.width)
            return CGSize(width: bodyW + extra, height: LockScreenAlertMetrics.fallbackHeight)
        }
        if airDrop.isDropTargetVisible {
            let bodyW = max(baseWidth, AirDropZoneMetrics.width)
            return CGSize(width: bodyW + extra, height: AirDropZoneMetrics.height)
        }
        if let batteryPresentation {
            switch batteryPresentation {
            case .charging, .lowBattery:
                let bodyW = max(baseWidth, BatteryAlertMetrics.width(for: batteryPresentation))
                return CGSize(width: bodyW + extra, height: baseHeight)
            }
        }
        if focusPresentation != nil {
            let bodyW = max(baseWidth, FocusModeAlertMetrics.width)
            return CGSize(width: bodyW + extra, height: baseHeight)
        }
        if appState.isExpanded {
            if eventCountdown.isDetailPresented, eventCountdown.trackedEvent != nil {
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
        if hud.current != nil {
            let bodyW = max(baseWidth, HUDController.drawerMinWidth)
            return CGSize(width: bodyW + extra, height: baseHeight + HUDController.drawerHeight)
        }
        if hasMusic, hasEvent {
            let bodyW = EventCountdownChipMetrics.musicComboContainerBodyWidth(baseWidth: baseWidth)
            let extraH = appState.isHovering
                ? NowPlayingMetrics.hoverExtraHeight
                : NowPlayingMetrics.collapsedExtraHeight
            return CGSize(width: bodyW + extra, height: baseHeight + extraH)
        }
        if hasMusic {
            let bodyW = max(baseWidth, NowPlayingMetrics.collapsedWidth)
            let extraH = appState.isHovering
                ? NowPlayingMetrics.hoverExtraHeight
                : NowPlayingMetrics.collapsedExtraHeight
            return CGSize(width: bodyW + extra, height: baseHeight + extraH)
        }
        if hasEvent {
            let bodyW = EventCountdownChipMetrics.eventOnlyContainerBodyWidth(baseWidth: baseWidth)
            return CGSize(width: bodyW + extra, height: baseHeight)
        }
        if appState.isHovering {
            return CGSize(width: baseWidth + extra + 25, height: baseHeight + 10)
        }
        return CGSize(width: baseWidth + extra, height: baseHeight)
    }
}

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class NotchHostingView<Content: View>: NSHostingView<Content> {
    weak var airDrop: AirDropController?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    // MARK: NSDraggingDestination — files dropped on the notch drop zone.

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.types?.contains(.fileURL) == true ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        airDrop?.setHoveringDropZone(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        airDrop?.setHoveringDropZone(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else { return false }
        airDrop?.handleDrop(urls: urls)
        return true
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
