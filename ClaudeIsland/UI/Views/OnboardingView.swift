//
//  OnboardingView.swift
//  ClaudeIsland
//
//  Lightweight 3-step onboarding flow for first-time users.
//  Step 1: Welcome   — App name and brief introduction
//  Step 2: Tools     — Auto-detect installed AI tools (reuses HookSetupView logic)
//  Step 3: Complete  — Show shortcut hints and finish
//

import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var currentStep = 0
    @State private var detectedTools: [SessionSource] = []
    @State private var selectedTools: Set<SessionSource> = []
    @State private var autoRepairEnabled = false
    @State private var isInstalling = false

    private let allTools: [SessionSource] = [
        .claude, .cline, .codexCLI, .gemini, .cursor, .windsurf, .kimiCLI, .kiroCLI,
        .ampCLI, .opencode, .copilot,
        .qoder, .droid, .codebuddy
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { step in
                    Circle()
                        .fill(step <= currentStep ? TerminalColors.green : Color.white.opacity(0.2))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 12)

            switch currentStep {
            case 0:
                welcomeStep
            case 1:
                toolDetectionStep
            default:
                completeStep
            }
        }
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundColor(TerminalColors.green)

            Text(String(localized: "onboarding.welcome.title"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)

            Text(String(localized: "onboarding.welcome.desc"))
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 24)

            Spacer()

            Button {
                withAnimation { currentStep = 1 }
            } label: {
                Text(String(localized: "onboarding.welcome.button"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Step 2: Tool Detection

    private var toolDetectionStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(String(localized: "onboarding.tools.title"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                Text(String(localized: "onboarding.tools.desc"))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.bottom, 10)

            Divider().background(Color.white.opacity(0.1))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(allTools, id: \.rawValue) { source in
                        ToolSetupRow(
                            source: source,
                            isDetected: detectedTools.contains(source),
                            isSelected: selectedTools.contains(source)
                        ) {
                            if selectedTools.contains(source) {
                                selectedTools.remove(source)
                            } else {
                                selectedTools.insert(source)
                            }
                        }
                    }

                    Divider().background(Color.white.opacity(0.1)).padding(.vertical, 4)

                    Button {
                        autoRepairEnabled.toggle()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.6))
                                .frame(width: 16)
                            Text(String(localized: "onboarding.auto_repair"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                            Circle()
                                .fill(autoRepairEnabled ? TerminalColors.green : Color.white.opacity(0.3))
                                .frame(width: 6, height: 6)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 6)
            }

            Divider().background(Color.white.opacity(0.1))

            HStack(spacing: 12) {
                Button {
                    skipAndFinish()
                } label: {
                    Text(String(localized: "onboarding.skip"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                Button {
                    installAndContinue()
                } label: {
                    HStack(spacing: 4) {
                        if isInstalling {
                            ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                        }
                        Text(selectedTools.isEmpty ? String(localized: "onboarding.continue") : (selectedTools.count == 1 ? String(localized: "onboarding.install_hook_single") : String(format: String(localized: "onboarding.install_hooks %lld"), selectedTools.count)))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(selectedTools.isEmpty ? .white.opacity(0.7) : .black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedTools.isEmpty ? Color.white.opacity(0.15) : Color.white)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isInstalling)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .onAppear {
            detectedTools = HookInstaller.detectInstalledTools()
            selectedTools = Set(detectedTools)
        }
    }

    // MARK: - Step 3: Complete

    private var completeStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(TerminalColors.green)

            Text(String(localized: "onboarding.complete.title"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            VStack(spacing: 8) {
                shortcutHint(key: "\u{2318}\u{21E7}I", label: String(localized: "onboarding.shortcut.toggle"))
                shortcutHint(key: "Hover", label: String(localized: "onboarding.shortcut.hover"))
                shortcutHint(key: "Click", label: String(localized: "onboarding.shortcut.click"))
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                AppSettings.onboardingCompleted = true
                onComplete()
            } label: {
                Text(String(localized: "onboarding.complete.button"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Helpers

    private func shortcutHint(key: String, label: String) -> some View {
        HStack(spacing: 10) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(TerminalColors.green)
                .frame(width: 60, alignment: .trailing)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.7))
            Spacer()
        }
    }

    private func installAndContinue() {
        isInstalling = true
        DispatchQueue.global(qos: .userInitiated).async {
            for source in allTools {
                AppSettings.setHookEnabled(selectedTools.contains(source), for: source)
            }
            AppSettings.autoRepairHooks = autoRepairEnabled
            HookInstaller.installEnabledOnly()
            if autoRepairEnabled {
                DispatchQueue.main.async { HookRepairManager.shared.start() }
            }
            DispatchQueue.main.async {
                AppSettings.hookSetupCompleted = true
                isInstalling = false
                withAnimation { currentStep = 2 }
            }
        }
    }

    private func skipAndFinish() {
        AppSettings.hookSetupCompleted = true
        withAnimation { currentStep = 2 }
    }
}
