//
//  NotchActivityCoordinator.swift
//  ClaudeIsland
//
//  Coordinates live activities and expanding views for the notch
//  Includes auto-expand on task complete, auto-collapse, and idle-hide logic
//

import Combine
import SwiftUI

// MARK: - Activity Types

/// How the notch is currently being presented
enum NotchPresentationMode: Equatable {
    case closed
    case manualOpen
    case autoOpen

    var isOpen: Bool {
        self != .closed
    }
}

/// Types of activities that can be shown in the notch
enum NotchActivityType: Equatable {
    case claude      // Claude is processing
    case none
}

// MARK: - Expanding Activity

/// An activity that expands the notch to the sides
struct ExpandingActivity: Equatable {
    var show: Bool = false
    var type: NotchActivityType = .none
    var value: CGFloat = 0

    static let empty = ExpandingActivity()
}

// MARK: - Coordinator

/// Coordinates notch activities and state
@MainActor
class NotchActivityCoordinator: ObservableObject {
    static let shared = NotchActivityCoordinator()

    // MARK: - Published State

    /// Current notch presentation mode
    @Published private(set) var presentationMode: NotchPresentationMode = .closed

    /// Current expanding activity (expands notch to sides)
    @Published var expandingActivity: ExpandingActivity = .empty {
        didSet {
            if expandingActivity.show {
                scheduleActivityHide()
            } else {
                activityTask?.cancel()
            }
        }
    }

    /// Duration before auto-hiding the activity
    var activityDuration: TimeInterval = 0 // 0 = manual control (won't auto-hide)

    /// Duration before auto-collapsing after an auto-opened presentation
    var autoCollapseDuration: TimeInterval {
        AppSettings.autoCollapseDelay
    }

    /// Delay after the mouse leaves an auto-opened panel before collapsing
    var mouseLeaveCollapseDuration: TimeInterval = 0.9

    /// Whether the pointer is currently hovering the notch panel
    @Published private(set) var isHoveringPanel: Bool = false

    /// Whether the notch is auto-expanded for a task completion notification
    @Published private(set) var isAutoExpandedForTaskComplete: Bool = false

    /// Timestamp of the last auto-expand for task completion
    private var autoExpandedAt: Date?

    // MARK: - Idle Hide State

    /// Timer for checking idle state and hiding notch
    private var idleCheckTask: Task<Void, Never>?

    /// Timestamp of last meaningful activity across all sessions
    private var lastMeaningfulActivity: Date = Date()

    // MARK: - Private

    private var activityTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?

    private init() {
        startIdleCheckIfNeeded()
    }

    // MARK: - Public API

    /// Show an expanding activity
    func showActivity(
        type: NotchActivityType,
        value: CGFloat = 0,
        duration: TimeInterval = 0
    ) {
        activityDuration = duration
        lastMeaningfulActivity = Date()

        withAnimation(.smooth) {
            expandingActivity = ExpandingActivity(
                show: true,
                type: type,
                value: value
            )
        }
    }

    /// Hide the current activity
    func hideActivity() {
        withAnimation(.smooth) {
            expandingActivity = .empty
        }
    }

    /// Mark the notch as manually opened.
    /// Manual opens should never be auto-collapsed by this coordinator.
    func didOpenManually() {
        isAutoExpandedForTaskComplete = false
        setPresentationMode(.manualOpen)
    }

    /// Mark the notch as auto-opened.
    /// Auto-opened presentations can be collapsed by hover/idle timing.
    func didOpenAutomatically() {
        setPresentationMode(.autoOpen)
    }

    /// Auto-expand the notch for a task completion notification.
    func autoExpandForTaskComplete(sessionId: String) {
        guard AppSettings.autoExpandOnTaskComplete else { return }

        isAutoExpandedForTaskComplete = true
        autoExpandedAt = Date()
        lastMeaningfulActivity = Date()
        didOpenAutomatically()
    }

    /// Mark the notch as closed.
    func didClose() {
        collapseTask?.cancel()
        collapseTask = nil
        isHoveringPanel = false
        isAutoExpandedForTaskComplete = false
        setPresentationMode(.closed)
    }

    /// Update whether the pointer is hovering the visible panel.
    /// When an auto-opened notch loses hover, it should collapse after a delay.
    func setPanelHovering(_ hovering: Bool) {
        isHoveringPanel = hovering

        guard presentationMode == .autoOpen else {
            if hovering {
                collapseTask?.cancel()
                collapseTask = nil
            }
            return
        }

        if hovering {
            collapseTask?.cancel()
            collapseTask = nil
        } else {
            scheduleAutoCollapse(after: mouseLeaveCollapseDuration)
        }
    }

    /// Convert an auto-opened presentation into a manual one after user interaction.
    func promoteAutoOpenToManualIfNeeded() {
        guard presentationMode == .autoOpen else { return }
        collapseTask?.cancel()
        collapseTask = nil
        isAutoExpandedForTaskComplete = false
        setPresentationMode(.manualOpen)
    }

    /// Toggle activity visibility
    func toggleActivity(type: NotchActivityType, value: CGFloat = 0) {
        if expandingActivity.show && expandingActivity.type == type {
            hideActivity()
        } else {
            showActivity(type: type, value: value)
        }
    }

    /// Record meaningful activity (prevents idle-hide)
    func recordActivity() {
        lastMeaningfulActivity = Date()
    }

    /// Check if all sessions are idle and enough time has passed for idle-hide
    func shouldHideForIdle() -> Bool {
        guard AppSettings.autoHideWhenIdle else { return false }
        let elapsed = Date().timeIntervalSince(lastMeaningfulActivity)
        return elapsed >= AppSettings.idleHideDelay
    }

    /// Cancel all timers (cleanup)
    func cancelAllTimers() {
        activityTask?.cancel()
        activityTask = nil
        collapseTask?.cancel()
        collapseTask = nil
        idleCheckTask?.cancel()
        idleCheckTask = nil
    }

    // MARK: - Idle Check

    /// Start periodic idle checking if the setting is enabled
    func startIdleCheckIfNeeded() {
        idleCheckTask?.cancel()

        guard AppSettings.autoHideWhenIdle else { return }

        idleCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self = self, !Task.isCancelled else { return }
                // The actual idle-hide logic is driven by NotchView observing this state
                self.objectWillChange.send()
            }
        }
    }

    // MARK: - Private

    private func scheduleActivityHide() {
        activityTask?.cancel()

        // Duration of 0 means manual control - don't auto-hide
        guard activityDuration > 0 else { return }

        let currentType = expandingActivity.type
        activityTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.activityDuration ?? 3))
            guard let self = self, !Task.isCancelled else { return }

            // Only hide if still showing the same type
            if self.expandingActivity.type == currentType {
                self.hideActivity()
            }
        }
    }

    private func setPresentationMode(_ mode: NotchPresentationMode) {
        presentationMode = mode

        switch mode {
        case .closed, .manualOpen:
            collapseTask?.cancel()
            collapseTask = nil
        case .autoOpen:
            if !isHoveringPanel {
                scheduleAutoCollapse(after: autoCollapseDuration)
            }
        }
    }

    private func scheduleAutoCollapse(after delay: TimeInterval) {
        collapseTask?.cancel()
        guard delay > 0 else {
            collapseAutoOpenIfNeeded()
            return
        }

        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self = self, !Task.isCancelled else { return }
            await MainActor.run {
                self.collapseAutoOpenIfNeeded()
            }
        }
    }

    private func collapseAutoOpenIfNeeded() {
        guard presentationMode == .autoOpen else { return }
        presentationMode = .closed
        isHoveringPanel = false
        isAutoExpandedForTaskComplete = false
        collapseTask = nil
    }
}
