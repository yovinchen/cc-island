//
//  UsageRing.swift
//  ClaudeIsland
//
//  Circular progress ring for displaying API usage / context window percentage.
//

import SwiftUI

struct UsageRing: View {
    let progress: Double // 0.0 to 1.0
    var size: CGFloat = 16
    var lineWidth: CGFloat = 2
    var showPercentText: Bool = false

    private var color: Color {
        if progress >= 0.9 {
            return Color(red: 1.0, green: 0.4, blue: 0.4) // Red
        } else if progress >= 0.7 {
            return TerminalColors.amber // Amber/yellow
        } else {
            return TerminalColors.green // Green
        }
    }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)

            // Progress ring
            Circle()
                .trim(from: 0, to: CGFloat(min(progress, 1.0)))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Percentage text (optional, for larger rings)
            if showPercentText {
                Text("\(Int(progress * 100))")
                    .font(.system(size: size * 0.35, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.3), value: progress)
    }
}

// MARK: - Usage Display for Notch Header

struct UsageHeaderDisplay: View {
    @ObservedObject var usageManager: UsageDataManager

    var body: some View {
        if AppSettings.showUsageData, usageManager.aggregatedUsage.hasData {
            HStack(spacing: 4) {
                // Context window usage ring
                if let contextPercent = usageManager.aggregatedUsage.contextWindowPercent {
                    UsageRing(progress: contextPercent, size: 14, lineWidth: 1.5)
                        .help("Context: \(Int(contextPercent * 100))%")
                }

                // API rate limit ring
                if let primaryPercent = usageManager.aggregatedUsage.primaryUsedPercent {
                    UsageRing(progress: primaryPercent, size: 14, lineWidth: 1.5)
                        .help("API Usage: \(Int(primaryPercent * 100))%")
                }
            }
        }
    }
}
