//
//  OnboardingView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Content rendered inside the notch's "expanded-onboarding" branch on first
//  launch. The notch panel expands to fit this card; tapping GET STARTED
//  flips settings.hasCompletedOnboarding, which lets the regular branches
//  take over and the panel envelope shrink back.
//

import Lottie
import SwiftUI

enum OnboardingWizardStep: CaseIterable, Hashable {
    case welcome
    case features
    case permissions
}

enum OnboardingMetrics {
    /// Inner body width × total height of the expanded notch during the
    /// welcome step. Width excludes the inverted-corner ears; height
    /// includes the full top-to-bottom envelope.
    static let notchSize = CGSize(width: 318, height: 176)

    /// Card size for the features/permissions wizard steps — bigger than
    /// the welcome step to fit icons, copy, and navigation chrome.
    static let expandedStepSize = CGSize(width: 460, height: 260)

    static func size(for step: OnboardingWizardStep) -> CGSize {
        switch step {
        case .welcome: notchSize
        case .features, .permissions: expandedStepSize
        }
    }

    // Deprecated aliases for backwards compatibility during transition
    @available(*, deprecated, message: "use size(for:)")
    static let welcomeHeight: CGFloat = notchSize.height
    @available(*, deprecated, message: "use size(for:)")
    static let buttonHeight: CGFloat = notchSize.height
}

enum OnboardingLockNotchMetrics {
    static let bodyWidth: CGFloat = 184
    static let height: CGFloat = 32
}

struct OnboardingLockNotchView: View {
    let isUnlocked: Bool

    @State private var didOpen = false
    @State private var isPulsing = false

    var body: some View {
        Image(systemName: didOpen ? "lock.open.fill" : "lock.fill")
            .font(.system(size: 17, weight: .heavy, design: .rounded))
            .foregroundStyle(didOpen ? Color(red: 0.23, green: 0.86, blue: 0.33) : .secondary)
            .symbolEffect(.bounce, value: didOpen)
            .contentTransition(.symbolEffect(.replace.downUp))
            .scaleEffect(isPulsing ? 1.08 : 0.94)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .accessibilityLabel(didOpen ? "Unlocked" : "Locked")
            .onAppear {
                didOpen = isUnlocked
                withAnimation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
            .onChange(of: isUnlocked) { _, unlocked in
                withAnimation(.spring(response: 0.38, dampingFraction: 0.58)) {
                    didOpen = unlocked
                }
            }
    }
}

struct OnboardingView: View {
    @Binding var wizardStep: OnboardingWizardStep
    let onGetStarted: () -> Void
    let onWelcomeAnimationFinished: () -> Void
    let animateIntro: Bool

    @State private var showHero = false
    @State private var showNext = false

    init(
        wizardStep: Binding<OnboardingWizardStep>,
        onGetStarted: @escaping () -> Void,
        onWelcomeAnimationFinished: @escaping () -> Void = {},
        animateIntro: Bool = true
    ) {
        self._wizardStep = wizardStep
        self.onGetStarted = onGetStarted
        self.onWelcomeAnimationFinished = onWelcomeAnimationFinished
        self.animateIntro = animateIntro
        _showHero = State(initialValue: !animateIntro)
        _showNext = State(initialValue: !animateIntro)
    }

    var body: some View {
        VStack(spacing: 10) {
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .padding(.horizontal, wizardStep == .welcome ? 16 : 20)
        .padding(.top, wizardStep == .welcome ? 10 : 16)
        .padding(.bottom, 12)
        .task {
            guard animateIntro else {
                showHero = true
                showNext = true
                onWelcomeAnimationFinished()
                return
            }
            await runIntroSequence()
        }
        .onDisappear {
            guard animateIntro else { return }
            showHero = false
            showNext = false
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch wizardStep {
        case .welcome:
            OnboardingHeroAnimation()
                .frame(maxWidth: .infinity, maxHeight: 108)
                .revealOnboardingItem(showHero, offset: -4, scale: 0.72)
        case .features:
            OnboardingFeaturesStepView()
        case .permissions:
            OnboardingPermissionsStepView(onFinish: onGetStarted)
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 12) {
            if wizardStep != .welcome {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                ForEach(OnboardingWizardStep.allCases, id: \.self) { step in
                    Circle()
                        .fill(step == wizardStep ? Color.white : Color.white.opacity(0.25))
                        .frame(width: 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity)

            if wizardStep != .permissions {
                Button(action: goNext) {
                    Text("NEXT")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 16)
                        .frame(height: 28)
                        .background(Capsule(style: .continuous).fill(Color(red: 0.36, green: 0.86, blue: 0.45)))
                }
                .buttonStyle(.plain)
                .opacity(wizardStep == .welcome && !showNext ? 0 : 1)
                .disabled(wizardStep == .welcome && !showNext)
            }
        }
    }

    private func goNext() {
        withAnimation(.easeInOut(duration: 0.22)) {
            switch wizardStep {
            case .welcome: wizardStep = .features
            case .features: wizardStep = .permissions
            case .permissions: break
            }
        }
    }

    private func goBack() {
        withAnimation(.easeInOut(duration: 0.22)) {
            switch wizardStep {
            case .welcome: break
            case .features: wizardStep = .welcome
            case .permissions: wizardStep = .features
            }
        }
    }

    @MainActor
    private func runIntroSequence() async {
        showHero = false
        showNext = false

        try? await Task.sleep(for: .milliseconds(90))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.46, dampingFraction: 0.82, blendDuration: 0)) {
            showHero = true
        }

        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.44, dampingFraction: 0.82, blendDuration: 0)) {
            showNext = true
        }
        onWelcomeAnimationFinished()
    }
}

private struct OnboardingHeroAnimation: View {
    var body: some View {
        if AppRuntime.isXcodePreview {
            Image(systemName: "sparkles")
                .font(.system(size: 42, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.36, green: 0.86, blue: 0.45))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LottieView(animation: .named("Welcome"))
                .playing(loopMode: .loop)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

private extension View {
    func revealOnboardingItem(_ isVisible: Bool, offset: CGFloat, scale: CGFloat) -> some View {
        self
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : scale, anchor: .top)
            .offset(y: isVisible ? 0 : offset)
            .blur(radius: isVisible ? 0 : 6)
    }
}

private struct OnboardingNotchPreview: View {
    @State private var previewStep: OnboardingWizardStep = .welcome

    private let invertedRadius = FloatingNotchView.expandedInvertedRadius

    var body: some View {
        let bodySize = OnboardingMetrics.size(for: previewStep)
        let size = CGSize(
            width: bodySize.width + invertedRadius * 2,
            height: bodySize.height
        )
        let shape = NotchDropShape(
            invertedCornerRadius: invertedRadius,
            bottomCornerRadius: 20
        )

        ZStack(alignment: .top) {
            Color(red: 0.11, green: 0.11, blue: 0.12)
                .ignoresSafeArea()

            NotchPreviewContainer {
                ZStack(alignment: .bottom) {
                    shape.fill(Color.black)
                        .frame(width: size.width, height: size.height)

                    OnboardingView(
                        wizardStep: $previewStep,
                        onGetStarted: {},
                        animateIntro: false
                    )
                    .frame(width: bodySize.width, height: bodySize.height)
                }
                .clipShape(shape)
                .shadow(color: Color.black.opacity(0.42), radius: 18, x: 0, y: 8)
                .padding(.top, 18)
            }
            .animation(.easeInOut(duration: 0.22), value: previewStep)
        }
        .frame(width: 520, height: 320)
    }
}

private struct OnboardingContentPreview: View {
    @State private var wizardStep: OnboardingWizardStep = .welcome

    var body: some View {
        NotchPreviewContainer {
            OnboardingView(wizardStep: $wizardStep, onGetStarted: {}, animateIntro: false)
                .frame(width: OnboardingMetrics.notchSize.width, height: OnboardingMetrics.notchSize.height)
                .background(Color.black)
        }
    }
}

private struct OnboardingLockPreview: View {
    let isUnlocked: Bool

    private let invertedRadius = FloatingNotchView.bareInvertedRadius
    private let bodySize = CGSize(
        width: OnboardingLockNotchMetrics.bodyWidth,
        height: OnboardingLockNotchMetrics.height
    )

    var body: some View {
        let size = CGSize(
            width: bodySize.width + invertedRadius * 2,
            height: bodySize.height
        )
        let shape = NotchDropShape(
            invertedCornerRadius: invertedRadius,
            bottomCornerRadius: bodySize.height / 2
        )

        ZStack(alignment: .top) {
            Color(red: 0.11, green: 0.11, blue: 0.12)
                .ignoresSafeArea()

            ZStack {
                shape.fill(Color.black)
                    .frame(width: size.width, height: size.height)

                OnboardingLockNotchView(isUnlocked: isUnlocked)
                    .frame(width: bodySize.width, height: bodySize.height)
            }
            .clipShape(shape)
            .shadow(color: Color.black.opacity(0.36), radius: 12, x: 0, y: 6)
            .padding(.top, 18)
        }
        .frame(width: 300, height: 92)
    }
}

#Preview("Onboarding Notch") {
    OnboardingNotchPreview()
}

#Preview("Onboarding Content") {
    OnboardingContentPreview()
}

#Preview("Onboarding Locked") {
    OnboardingLockPreview(isUnlocked: false)
}

#Preview("Onboarding Unlocked") {
    OnboardingLockPreview(isUnlocked: true)
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
