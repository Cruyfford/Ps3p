// SPDX-License-Identifier: GPL-2.0-only
// Ps3p: the top category bar. A floating glass strip: the chosen category expands to
// show its name, the others stay as icons; a sliding light pill follows the
// selection, icons bounce, and the bar carries a live clock.

import SwiftUI

struct Ps3pCategory: Identifiable, Equatable {
    let id: Int
    let title: String
    let symbol: String
}

struct Ps3pCrossBar: View {
    @Binding var selection: Int
    let categories: [Ps3pCategory]
    var onReselect: (Int) -> Void = { _ in }

    @Namespace private var pill
    @State private var bounce: [Int: Int] = [:]
    @Environment(\.verticalSizeClass) private var vSize

    private var compact: Bool { vSize == .compact }

    var body: some View {
        HStack(spacing: 14) {
            strip
            Spacer(minLength: 8)
            Ps3pStatusCluster()
        }
        .padding(.horizontal, compact ? 28 : 18)
        .padding(.top, compact ? 6 : 4)
        .padding(.bottom, 6)
        .onChange(of: selection) { old, new in
            guard old != new else { return }
            Ps3pAudio.shared.play(.cursor)
            bounce[new, default: 0] += 1
        }
    }

    private var strip: some View {
        HStack(spacing: 4) {
            ForEach(categories) { cat in
                let on = cat.id == selection
                Button {
                    if on {
                        Ps3pAudio.shared.play(.decide)
                        onReselect(cat.id)
                    } else {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { selection = cat.id }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: cat.symbol)
                            .font(.system(size: compact ? 17 : 19, weight: .semibold))
                            .symbolEffect(.bounce, value: bounce[cat.id, default: 0])
                            .frame(width: 24)
                        if on {
                            Text(cat.title)
                                .font(.system(size: compact ? 15 : 16, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                                .fixedSize()
                                .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .leading)),
                                                        removal: .opacity))
                        }
                    }
                    .foregroundStyle(on ? Color.white : Color.white.opacity(0.62))
                    .padding(.horizontal, on ? 16 : 12)
                    .frame(height: compact ? 38 : 42)
                    .background {
                        if on {
                            Capsule()
                                .fill(LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.12)],
                                                     startPoint: .top, endPoint: .bottom))
                                .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.7))
                                .shadow(color: .white.opacity(0.25), radius: 10)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(Ps3pPressStyle())
                .accessibilityLabel(cat.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background {
            Capsule().fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.8))
                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        }
        .environment(\.colorScheme, .dark)
    }
}

/// Clock and battery, like a console home screen.
struct Ps3pStatusCluster: View {
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            HStack(spacing: 10) {
                Text(ctx.date, format: .dateTime.hour().minute())
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(ctx.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
        }
        .accessibilityHidden(true)
    }
}

/// Springy press feedback for every Ps3p control.
struct Ps3pPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
