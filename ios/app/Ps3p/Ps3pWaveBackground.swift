// SPDX-License-Identifier: GPL-2.0-only
// Ps3p: the animated menu background ("Flow"). Original design: a slowly shifting
// colour field, layered translucent light ribbons and drifting glow particles,
// with a gentle tilt parallax.

import SwiftUI
import CoreMotion

/// Colour themes the user can pick in Settings › Ps3p.
enum Ps3pPalette: String, CaseIterable, Identifiable {
    case auto, ocean, aurora, ember, violet, graphite
    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Time of day"
        case .ocean: "Ocean"
        case .aurora: "Aurora"
        case .ember: "Ember"
        case .violet: "Violet"
        case .graphite: "Graphite"
        }
    }

    /// Top and bottom colours of the field.
    func colours(at date: Date) -> (Color, Color, Color) {
        switch self {
        case .ocean: return (Color(red: 0.02, green: 0.10, blue: 0.28), Color(red: 0.00, green: 0.32, blue: 0.55), Color(red: 0.35, green: 0.85, blue: 1.0))
        case .aurora: return (Color(red: 0.01, green: 0.12, blue: 0.14), Color(red: 0.02, green: 0.38, blue: 0.32), Color(red: 0.45, green: 1.0, blue: 0.75))
        case .ember: return (Color(red: 0.16, green: 0.03, blue: 0.03), Color(red: 0.55, green: 0.16, blue: 0.05), Color(red: 1.0, green: 0.68, blue: 0.35))
        case .violet: return (Color(red: 0.08, green: 0.02, blue: 0.20), Color(red: 0.34, green: 0.10, blue: 0.55), Color(red: 0.85, green: 0.55, blue: 1.0))
        case .graphite: return (Color(red: 0.04, green: 0.04, blue: 0.05), Color(red: 0.20, green: 0.21, blue: 0.24), Color(red: 0.85, green: 0.88, blue: 0.95))
        case .auto:
            let hour = Calendar.current.component(.hour, from: date)
            switch hour {
            case 5..<9: return Ps3pPalette.ember.colours(at: date)
            case 9..<16: return Ps3pPalette.ocean.colours(at: date)
            case 16..<19: return Ps3pPalette.violet.colours(at: date)
            case 19..<23: return Ps3pPalette.aurora.colours(at: date)
            default: return Ps3pPalette.graphite.colours(at: date)
            }
        }
    }

    static let storageKey = "ps3p.background.palette"
}

@MainActor
final class Ps3pTilt: ObservableObject {
    static let shared = Ps3pTilt()
    @Published var x: Double = 0
    @Published var y: Double = 0
    private let manager = CMMotionManager()
    private var users = 0

    func start() {
        users += 1
        guard users == 1, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let g = motion?.gravity else { return }
            // Smoothed so the field drifts rather than jitters.
            self.x += (g.x - self.x) * 0.08
            self.y += (g.y + 0.6 - self.y) * 0.08
        }
    }

    func stop() {
        users = max(users - 1, 0)
        if users == 0 { manager.stopDeviceMotionUpdates() }
    }
}

struct Ps3pWaveBackground: View {
    @AppStorage(Ps3pPalette.storageKey) private var paletteRaw = Ps3pPalette.auto.rawValue
    @AppStorage("ps3p.background.particles") private var particlesOn = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var tilt = Ps3pTilt.shared
    private let start = Date()

    private struct Particle {
        let x: Double, speed: Double, size: Double, phase: Double, drift: Double
    }

    private static let particles: [Particle] = {
        var g = SystemRandomNumberGenerator()
        return (0..<46).map { _ in
            Particle(x: .random(in: 0...1, using: &g), speed: .random(in: 0.006...0.022, using: &g),
                     size: .random(in: 1.2...3.6, using: &g), phase: .random(in: 0...1, using: &g),
                     drift: .random(in: 0.01...0.05, using: &g))
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSince(start)
            let palette = Ps3pPalette(rawValue: paletteRaw) ?? .auto
            let (top, bottom, glow) = palette.colours(at: context.date)
            Canvas { gc, size in
                draw(gc: &gc, size: size, t: t, top: top, bottom: bottom, glow: glow)
            }
        }
        .ignoresSafeArea()
        .onAppear { tilt.start() }
        .onDisappear { tilt.stop() }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func draw(gc: inout GraphicsContext, size: CGSize, t: Double, top: Color, bottom: Color, glow: Color) {
        let w = size.width, h = size.height
        let rect = CGRect(origin: .zero, size: size)
        let px = tilt.x * 28, py = tilt.y * 18

        // 1. Base field with a slowly orbiting light pool.
        gc.fill(Path(rect), with: .linearGradient(Gradient(colors: [top, bottom, top]),
                                                   startPoint: CGPoint(x: w * 0.5, y: 0),
                                                   endPoint: CGPoint(x: w * 0.5, y: h)))
        let pool = CGPoint(x: w * (0.5 + 0.28 * sin(t * 0.05)) + px, y: h * (0.45 + 0.15 * cos(t * 0.04)) + py)
        gc.fill(Path(rect), with: .radialGradient(Gradient(colors: [glow.opacity(0.28), .clear]),
                                                   center: pool, startRadius: 0, endRadius: max(w, h) * 0.75))

        // 2. Light ribbons: each is a band between two sine curves, softly lit.
        var ribbons = gc
        ribbons.blendMode = .plusLighter
        for i in 0..<6 {
            let fi = Double(i)
            let baseY = h * (0.48 + 0.04 * fi) + py * (0.4 + fi * 0.15)
            let amp = h * (0.06 + 0.012 * fi)
            let freq = 1.2 + 0.35 * fi
            let speed = 0.12 + 0.05 * fi
            let thickness = h * (0.025 + 0.018 * Double((i * 7) % 4))
            var upper: [CGPoint] = [], lower: [CGPoint] = []
            let steps = 64
            for s in 0...steps {
                let u = Double(s) / Double(steps)
                let x = u * (w + 80) - 40 + px * (0.6 + fi * 0.1)
                let phase = u * .pi * 2 * freq + t * speed + fi * 1.3
                let y = baseY + sin(phase) * amp + sin(phase * 0.47 + t * 0.07) * amp * 0.6
                let thick = thickness * (0.55 + 0.45 * sin(u * .pi * 3 + t * 0.2 + fi))
                upper.append(CGPoint(x: x, y: y - thick))
                lower.append(CGPoint(x: x, y: y + thick))
            }
            var band = Path()
            band.addLines(upper)
            band.addLines(lower.reversed())
            band.closeSubpath()
            let alpha = 0.05 + 0.025 * Double(i % 3)
            ribbons.fill(band, with: .linearGradient(
                Gradient(colors: [glow.opacity(0), glow.opacity(alpha), .white.opacity(alpha * 0.9), glow.opacity(0)]),
                startPoint: CGPoint(x: 0, y: baseY), endPoint: CGPoint(x: w, y: baseY)))
            // A thin bright crest line on every other ribbon.
            if i % 2 == 0 {
                var crest = Path()
                crest.addLines(upper)
                ribbons.stroke(crest, with: .linearGradient(
                    Gradient(colors: [.clear, .white.opacity(0.22), .clear]),
                    startPoint: CGPoint(x: 0, y: baseY), endPoint: CGPoint(x: w, y: baseY)), lineWidth: 0.8)
            }
        }

        // 3. Drifting glow particles that rise and twinkle.
        if particlesOn {
            var dots = gc
            dots.blendMode = .plusLighter
            for p in Self.particles {
                let life = (p.phase + t * p.speed).truncatingRemainder(dividingBy: 1)
                let y = h * (1.05 - life * 1.1) + py * 0.5
                let x = w * p.x + sin(t * 0.3 + p.phase * 10) * w * p.drift + px * 1.4
                let twinkle = 0.5 + 0.5 * sin(t * 2 + p.phase * 30)
                let a = sin(life * .pi) * (0.25 + 0.5 * twinkle)
                let r = p.size * (0.8 + 0.4 * twinkle)
                let dot = CGRect(x: x - r * 3, y: y - r * 3, width: r * 6, height: r * 6)
                dots.fill(Path(ellipseIn: dot), with: .radialGradient(
                    Gradient(colors: [.white.opacity(a), glow.opacity(a * 0.4), .clear]),
                    center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r * 3))
            }
        }

        // 4. Vignette keeps text readable at the edges.
        gc.fill(Path(rect), with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.45)]),
                                                   center: CGPoint(x: w / 2, y: h / 2),
                                                   startRadius: min(w, h) * 0.35, endRadius: max(w, h) * 0.8))
    }
}
