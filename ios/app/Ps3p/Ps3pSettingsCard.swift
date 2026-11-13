// SPDX-License-Identifier: GPL-2.0-only
// Ps3p: look and sound options, shown first on the Settings tab.

import SwiftUI

struct Ps3pSettingsCard: View {
    @AppStorage(Ps3pPalette.storageKey) private var paletteRaw = Ps3pPalette.auto.rawValue
    @AppStorage("ps3p.background.particles") private var particles = true
    @State private var musicOn = Ps3pAudio.shared.musicEnabled
    @State private var musicVolume = Double(Ps3pAudio.shared.musicVolume)
    @State private var effectsOn = Ps3pAudio.shared.effectsEnabled

    var body: some View {
        OverlaySectionCard(title: "Ps3p") {
            VStack(alignment: .leading, spacing: 10) {
                Label("Background colour", systemImage: "paintpalette.fill")
                    .font(.subheadline.weight(.semibold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Ps3pPalette.allCases) { palette in
                            swatch(palette)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .overlayRowLabelInset()

            OverlayToggleRow(controllerNavigationID: "ps3p.particles", label: "Floating lights",
                             systemImage: "sparkles", isOn: $particles)
            OverlayToggleRow(controllerNavigationID: "ps3p.music", label: "Menu music",
                             systemImage: "music.note", isOn: $musicOn)
                .onChange(of: musicOn) { _, on in Ps3pAudio.shared.musicEnabled = on }
            if musicOn {
                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill").foregroundStyle(OverlayTheme.textSecondary)
                    Slider(value: $musicVolume, in: 0...1)
                        .onChange(of: musicVolume) { _, v in Ps3pAudio.shared.musicVolume = Float(v) }
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(OverlayTheme.textSecondary)
                }
                .overlayRowLabelInset()
            }
            OverlayToggleRow(controllerNavigationID: "ps3p.effects", label: "Menu sounds",
                             systemImage: "speaker.wave.2.fill", isOn: $effectsOn)
                .onChange(of: effectsOn) { _, on in
                    Ps3pAudio.shared.effectsEnabled = on
                    if on { Ps3pAudio.shared.play(.decide) }
                }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: musicOn)
    }

    private func swatch(_ palette: Ps3pPalette) -> some View {
        let (top, bottom, glow) = palette.colours(at: Date())
        let on = palette.rawValue == paletteRaw
        return Button {
            withAnimation(.easeInOut(duration: 0.6)) { paletteRaw = palette.rawValue }
            Ps3pAudio.shared.play(.cursor)
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [top, bottom, glow.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 64, height: 44)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(on ? Color.white : .white.opacity(0.2), lineWidth: on ? 2 : 0.8)
                    }
                    .shadow(color: on ? glow.opacity(0.6) : .clear, radius: 8)
                Text(palette.title)
                    .font(.caption2.weight(on ? .semibold : .regular))
                    .foregroundStyle(on ? OverlayTheme.textPrimary : OverlayTheme.textSecondary)
            }
        }
        .buttonStyle(Ps3pPressStyle())
        .accessibilityLabel(palette.title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
