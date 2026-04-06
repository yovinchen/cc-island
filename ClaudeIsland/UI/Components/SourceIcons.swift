//
//  SourceIcons.swift
//  ClaudeIsland
//
//  Pixel-art brand icons for each SessionSource, 3-color palette each.
//  Each icon is designed to resemble the tool's actual logo/brand mark.
//
//  Logo references:
//  - Claude: Starburst/sunburst radiating lines (terra cotta #D97757)
//  - Codex/OpenAI: Blossom — 3 interlocking triangles (purple-blue gradient)
//  - Cursor: Isometric 3D cube (dark with gradient faces)
//  - Gemini: Four-pointed sparkle star (blue + Google 4-color tips)
//  - Copilot: Aviator goggles / visor (purple-pink)
//  - OpenCode: Pixel-art ">_" terminal (gray pixel style — their brand IS pixel art)
//  - CodeBuddy: Tencent "C" code bracket (Tencent blue)
//  - Qoder: Stylized "Q" letter (Alibaba blue-purple)
//  - Droid/Factory: Geometric pinwheel / 8-petal asterisk (warm neutral)
//  - Trae: Rectangle frame with bottom-left notch + two diamonds (bright green #32f08c)
//  - Unknown: Question mark
//

import SwiftUI

// MARK: - Source Icon Router

struct SourceIcon: View {
    let source: SessionSource
    let size: CGFloat
    var animateLegs: Bool = false
    var dimmed: Bool = false

    var body: some View {
        iconView
            .opacity(dimmed ? 0.35 : 1.0)
    }

    @ViewBuilder
    private var iconView: some View {
        switch source {
        case .claude:
            ClaudeCrabIcon(size: size, animateLegs: animateLegs)
        case .cline:
            OpenCodePixelIcon(size: size)
        case .codexCLI, .codexDesktop:
            CodexPixelIcon(size: size)
        case .cursor:
            CursorPixelIcon(size: size)
        case .gemini:
            GeminiPixelIcon(size: size)
        case .copilot:
            CopilotPixelIcon(size: size)
        case .opencode:
            OpenCodePixelIcon(size: size)
        case .codebuddy:
            CodeBuddyPixelIcon(size: size)
        case .qoder:
            QoderPixelIcon(size: size)
        case .droid:
            DroidPixelIcon(size: size)
        case .windsurf:
            CursorPixelIcon(size: size)
        case .kimiCLI:
            CodexPixelIcon(size: size)
        case .kiroCLI:
            GeminiPixelIcon(size: size)
        case .ampCLI:
            OpenCodePixelIcon(size: size)
        case .trae:
            TraePixelIcon(size: size)
        case .unknown:
            UnknownPixelIcon(size: size)
        }
    }
}

// MARK: - Pixel Drawing Helper

/// Draws pixel blocks on a canvas. `ps` = pixel block size in canvas units.
private func drawPixels(
    _ pixels: [(CGFloat, CGFloat)],
    color: Color,
    in context: inout GraphicsContext,
    scale: CGFloat,
    ps: CGFloat = 4
) {
    let actualPS = ps * scale
    for (x, y) in pixels {
        let rect = CGRect(
            x: x * scale - actualPS / 2,
            y: y * scale - actualPS / 2,
            width: actualPS,
            height: actualPS
        )
        context.fill(Path(rect), with: .color(color))
    }
}

// MARK: - Codex / OpenAI (Blossom — 3 interlocking petal pairs)
// Real logo: flower/blossom with 3 pairs of curved triangular petals
// Colors: purple #b1a7ff → blue #7a9dff → deep blue #3941ff

struct CodexPixelIcon: View {
    let size: CGFloat
    private let petal1 = Color(red: 0.69, green: 0.65, blue: 1.0)   // #b1a7ff light purple
    private let petal2 = Color(red: 0.48, green: 0.62, blue: 1.0)   // #7a9dff medium blue
    private let core   = Color(red: 0.22, green: 0.25, blue: 1.0)   // #3941ff deep blue

    var body: some View {
        Canvas { context, _ in
            let s = size / 30.0
            // Outer petal tips (6 directions)
            drawPixels([
                (15,1),(9,5),(21,5),
                (1,15),(29,15),
                (9,25),(21,25),(15,29),
            ], color: petal1, in: &context, scale: s)
            // Inner petal body
            drawPixels([
                (15,5),(11,9),(19,9),
                (5,11),(9,13),(21,13),(25,11),
                (5,19),(9,17),(21,17),(25,19),
                (11,21),(19,21),(15,25),
            ], color: petal2, in: &context, scale: s)
            // Center hub
            drawPixels([
                (13,13),(17,13),
                (11,15),(15,15),(19,15),
                (13,17),(17,17),
            ], color: core, in: &context, scale: s)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Cursor (Isometric 3D Cube)
// Real logo: isometric cube with 3 visible faces + gradient
// Colors: light top face, medium left face, dark right face

struct CursorPixelIcon: View {
    let size: CGFloat
    private let topFace  = Color(red: 0.65, green: 0.75, blue: 1.0)  // light blue
    private let leftFace = Color(red: 0.35, green: 0.45, blue: 0.85) // medium blue
    private let rightFace = Color(red: 0.18, green: 0.22, blue: 0.55) // dark blue

    var body: some View {
        Canvas { context, _ in
            let s = size / 30.0
            // Top face (brightest)
            drawPixels([
                (15,3),
                (11,7),(15,7),(19,7),
                (7,11),(11,11),(15,11),(19,11),(23,11),
            ], color: topFace, in: &context, scale: s)
            // Left face (medium)
            drawPixels([
                (3,15),(7,15),(11,15),
                (3,19),(7,19),(11,19),
                (7,23),(11,23),
                (11,27),
            ], color: leftFace, in: &context, scale: s)
            // Right face (darkest)
            drawPixels([
                (19,15),(23,15),(27,15),
                (19,19),(23,19),(27,19),
                (19,23),(23,23),
                (19,27),
            ], color: rightFace, in: &context, scale: s)
            // Center dividing edge
            drawPixels([
                (15,15),(15,19),(15,23),(15,27),
            ], color: topFace.opacity(0.7), in: &context, scale: s)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Gemini (Four-Pointed Sparkle with Google colors at tips)
// Real logo: rounded four-pointed star, blue body, 4-color tips (2025)
// Colors: blue body + multi-color tips + white center glow

struct GeminiPixelIcon: View {
    let size: CGFloat
    private let blue   = Color(red: 0.26, green: 0.52, blue: 0.96)  // Google blue
    private let red    = Color(red: 0.92, green: 0.26, blue: 0.21)  // Google red
    private let yellow = Color(red: 0.98, green: 0.74, blue: 0.02)  // Google yellow
    private let green  = Color(red: 0.20, green: 0.66, blue: 0.33)  // Google green

    var body: some View {
        Canvas { context, _ in
            let s = size / 30.0
            // Vertical arm (blue) — top tip
            drawPixels([
                (15,1),(15,5),(15,9),
            ], color: blue, in: &context, scale: s)
            // Right arm tip (red)
            drawPixels([
                (29,15),(25,15),(21,15),
            ], color: red, in: &context, scale: s)
            // Bottom arm tip (yellow)
            drawPixels([
                (15,29),(15,25),(15,21),
            ], color: yellow, in: &context, scale: s)
            // Left arm tip (green)
            drawPixels([
                (1,15),(5,15),(9,15),
            ], color: green, in: &context, scale: s)
            // Center glow (white core)
            drawPixels([
                (15,13),(13,15),(15,15),(17,15),(15,17),
            ], color: .white, in: &context, scale: s)
            // Diagonal fill (blue, connecting arms)
            drawPixels([
                (13,11),(17,11),
                (11,13),(19,13),
                (11,17),(19,17),
                (13,19),(17,19),
            ], color: blue.opacity(0.5), in: &context, scale: s)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Copilot (Aviator Goggles / Visor)
// Real logo: two round lens shapes connected by bridge, visor curve on top
// Colors: purple frame + pink lenses + dark pupils

struct CopilotPixelIcon: View {
    let size: CGFloat
    private let frame  = Color(red: 0.45, green: 0.20, blue: 0.75) // purple frame
    private let lens   = Color(red: 0.72, green: 0.40, blue: 0.90) // pink-purple lens
    private let pupil  = Color(red: 0.15, green: 0.05, blue: 0.30) // dark pupil

    var body: some View {
        Canvas { context, _ in
            let s = size / 30.0
            // Top visor curve
            drawPixels([
                (7,5),(11,3),(15,3),(19,3),(23,5),
            ], color: frame, in: &context, scale: s)
            // Left goggle frame
            drawPixels([
                (3,7),(3,11),(3,15),(3,19),
                (7,7),(7,19),
                (11,7),(11,19),
            ], color: frame, in: &context, scale: s)
            // Bridge
            drawPixels([
                (15,9),(15,11),
            ], color: frame, in: &context, scale: s)
            // Right goggle frame
            drawPixels([
                (19,7),(19,19),
                (23,7),(23,19),
                (27,7),(27,11),(27,15),(27,19),
            ], color: frame, in: &context, scale: s)
            // Left lens fill
            drawPixels([
                (7,11),(7,15),
                (11,11),(11,15),
            ], color: lens, in: &context, scale: s)
            // Right lens fill
            drawPixels([
                (19,11),(19,15),
                (23,11),(23,15),
            ], color: lens, in: &context, scale: s)
            // Pupils
            drawPixels([
                (7,13),(23,13),
            ], color: pupil, in: &context, scale: s)
            // Bottom chin curve
            drawPixels([
                (7,23),(11,23),(15,23),(19,23),(23,23),
            ], color: frame.opacity(0.5), in: &context, scale: s)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - OpenCode (Pixel-Art Terminal ">_")
// Real logo: pixel-art block letters — their brand IS pixel art
// Colors: light gray #CFCECD + medium gray #656363 + white cursor

struct OpenCodePixelIcon: View {
    let size: CGFloat
    private let light  = Color(red: 0.81, green: 0.81, blue: 0.80) // #CFCECD
    private let medium = Color(red: 0.72, green: 0.69, blue: 0.69) // #B7B1B1
    private let cursor = Color.white

    var body: some View {
        Canvas { context, _ in
            let s = size / 30.0
            // ">" chevron bracket (bold, 2px wide feel)
            drawPixels([
                (3,5),(5,5),
                (7,9),(9,9),
                (11,13),(13,13),
                (7,17),(9,17),
                (3,21),(5,21),
            ], color: light, in: &context, scale: s, ps: 3)
            // "_" underscore
            drawPixels([
                (17,21),(19,21),(21,21),(23,21),(25,21),
            ], color: medium, in: &context, scale: s, ps: 3)
            // Blinking cursor block
            drawPixels([
                (27,19),(27,21),
            ], color: cursor, in: &context, scale: s, ps: 3)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - CodeBuddy / Tencent (Stylized "C" with code bracket)
// Real logo: Tencent Cloud AI assistant, blue theme
// Colors: Tencent blue #0052D9 + light blue + white accent

struct CodeBuddyPixelIcon: View {
    let size: CGFloat
    private let primary = Color(red: 0.0, green: 0.32, blue: 0.85)  // Tencent blue
    private let light   = Color(red: 0.35, green: 0.58, blue: 1.0)  // light blue
    private let accent  = Color.white

    var body: some View {
        Canvas { context, _ in
            let s = size / 30.0
            // "C" outer shape (code bracket style)
            drawPixels([
                (11,3),(15,3),(19,3),(23,3),
                (7,7),
                (3,11),(3,15),(3,19),
                (7,23),
                (11,27),(15,27),(19,27),(23,27),
            ], color: primary, in: &context, scale: s)
            // Inner bracket detail
            drawPixels([
                (11,7),(15,7),
                (7,11),(7,15),(7,19),
                (11,23),(15,23),
            ], color: light, in: &context, scale: s)
            // Code dot / cursor accent
            drawPixels([
                (19,13),(23,13),
                (19,17),(23,17),
            ], color: accent, in: &context, scale: s)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Qoder / Alibaba (Stylized "Q" with tail)
// Real logo: distinctive Q letterform with diagonal tail
// Colors: blue-purple from their UI theme

struct QoderPixelIcon: View {
    let size: CGFloat
    private let ring = Color(red: 0.35, green: 0.30, blue: 0.85)  // blue-purple
    private let tail = Color(red: 0.55, green: 0.45, blue: 1.0)   // lighter purple
    private let dot  = Color.white

    var body: some View {
        Canvas { context, _ in
            let s = size / 30.0
            // "Q" circle outline
            drawPixels([
                (11,3),(15,3),(19,3),
                (7,7),(23,7),
                (3,11),(27,11),
                (3,15),(27,15),
                (3,19),(27,19),
                (7,23),(23,23),
                (11,27),(15,27),
            ], color: ring, in: &context, scale: s)
            // Q tail (diagonal, extending bottom-right)
            drawPixels([
                (19,23),(23,27),(27,27),
            ], color: tail, in: &context, scale: s)
            // Inner dot
            drawPixels([
                (15,15),
            ], color: dot, in: &context, scale: s)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Droid / Factory AI (Geometric Pinwheel / 8-petal asterisk)
// Real logo: 8 curved leaf-shaped petals radiating from center, rotational symmetry
// Colors: warm neutral palette

struct DroidPixelIcon: View {
    let size: CGFloat
    private let petal1 = Color(red: 0.85, green: 0.75, blue: 0.60) // warm light
    private let petal2 = Color(red: 0.65, green: 0.55, blue: 0.42) // warm medium
    private let center = Color.white

    var body: some View {
        Canvas { context, _ in
            let s = size / 30.0
            // 8 petal tips (N, NE, E, SE, S, SW, W, NW)
            drawPixels([
                (15,1),         // N
                (25,5),         // NE
                (29,15),        // E
                (25,25),        // SE
                (15,29),        // S
                (5,25),         // SW
                (1,15),         // W
                (5,5),          // NW
            ], color: petal1, in: &context, scale: s)
            // Inner petal arms (connecting tips to center, pinwheel rotation)
            drawPixels([
                (13,5),(17,9),   // N arm curves right
                (21,9),(23,13),  // NE arm curves down
                (25,17),(21,19), // E arm curves down
                (19,23),(17,25), // SE arm curves left
                (13,25),(11,21), // S arm curves left
                (7,21),(5,17),   // SW arm curves up
                (3,13),(7,11),   // W arm curves up
                (9,7),(11,5),    // NW arm curves right
            ], color: petal2, in: &context, scale: s)
            // Center hub
            drawPixels([
                (13,13),(17,13),
                (13,17),(17,17),
                (15,15),
            ], color: center, in: &context, scale: s)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Trae / ByteDance (Rectangle frame + notch + two diamonds)
// Real logo: outer rectangle with bottom-left step/notch, two diamond shapes inside
// Color: bright green #32f08c

struct TraePixelIcon: View {
    let size: CGFloat
    private let frame   = Color(red: 0.20, green: 0.94, blue: 0.55) // #32f08c
    private let diamond = Color(red: 0.10, green: 0.75, blue: 0.40) // darker green
    private let glow    = Color.white

    var body: some View {
        Canvas { context, _ in
            let s = size / 30.0
            // Outer frame (rectangle with bottom-left notch)
            drawPixels([
                // Top edge
                (3,3),(7,3),(11,3),(15,3),(19,3),(23,3),(27,3),
                // Right edge
                (27,7),(27,11),(27,15),(27,19),(27,23),
                // Bottom edge (shifted right, notch at left)
                (11,23),(15,23),(19,23),(23,23),
                // Left edge (shorter due to notch)
                (3,7),(3,11),(3,15),(3,19),
                // Notch step
                (7,19),(7,23),(11,27),(7,27),(3,27),(3,23),
            ], color: frame, in: &context, scale: s)
            // Left diamond (rotated square)
            drawPixels([
                (11,11),
                (9,13),(13,13),
                (11,15),
            ], color: diamond, in: &context, scale: s)
            // Right diamond (rotated square)
            drawPixels([
                (21,11),
                (19,13),(23,13),
                (21,15),
            ], color: diamond, in: &context, scale: s)
            // Diamond center glow
            drawPixels([
                (11,13),(21,13),
            ], color: glow, in: &context, scale: s)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Unknown (Question Mark in circle)

struct UnknownPixelIcon: View {
    let size: CGFloat
    private let ring = Color(red: 0.50, green: 0.52, blue: 0.56)
    private let mark = Color(red: 0.72, green: 0.74, blue: 0.78)
    private let dot  = Color.white

    var body: some View {
        Canvas { context, _ in
            let s = size / 30.0
            // Circle outline
            drawPixels([
                (11,3),(15,3),(19,3),
                (7,7),(23,7),
                (3,11),(27,11),
                (3,15),(27,15),
                (3,19),(27,19),
                (7,23),(23,23),
                (11,27),(15,27),(19,27),
            ], color: ring, in: &context, scale: s)
            // "?" mark
            drawPixels([
                (11,7),(15,7),(19,7),
                (19,11),
                (15,15),
                (15,19),
            ], color: mark, in: &context, scale: s)
            // Bottom dot
            drawPixels([
                (15,23),
            ], color: dot, in: &context, scale: s)
        }
        .frame(width: size, height: size)
    }
}
