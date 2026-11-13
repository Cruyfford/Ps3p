#!/usr/bin/env python3
"""Synthesises Ps3p's original menu music and interface sounds.

Everything here is generated from scratch (sine/triangle oscillators, filtered
noise and a synthetic reverb); no samples are used.
Usage: make_audio.py <output-dir>
"""
import sys, os, subprocess
import numpy as np
from scipy.signal import butter, sosfilt, fftconvolve
from scipy.io import wavfile

SR = 44100
rng = np.random.default_rng(3141)


def note(n):  # MIDI -> Hz
    return 440.0 * 2 ** ((n - 69) / 12)


def env_adsr(n, a, d, s, r, sr=SR):
    a, d, r = int(a * sr), int(d * sr), int(r * sr)
    sus = max(n - a - d - r, 0)
    e = np.concatenate([
        np.linspace(0, 1, a, endpoint=False) if a else [],
        np.linspace(1, s, d, endpoint=False) if d else [],
        np.full(sus, s),
        np.linspace(s, 0, r) if r else [],
    ])
    return np.pad(e, (0, max(n - len(e), 0)))[:n]


def osc(freq, dur, kind="sine", detune=0.0, phase=0.0):
    t = np.arange(int(dur * SR)) / SR
    f = freq * (1 + detune)
    ph = 2 * np.pi * f * t + phase
    if kind == "sine":
        return np.sin(ph)
    if kind == "tri":
        return 2 / np.pi * np.arcsin(np.sin(ph))
    if kind == "soft":  # sine + a little 2nd/3rd harmonic
        return np.sin(ph) + 0.18 * np.sin(2 * ph) + 0.06 * np.sin(3 * ph)
    raise ValueError(kind)


def lowpass(x, fc, order=2):
    return sosfilt(butter(order, fc, "low", fs=SR, output="sos"), x)


def highpass(x, fc, order=2):
    return sosfilt(butter(order, fc, "high", fs=SR, output="sos"), x)


def make_ir(seconds=3.2, damp=2.6):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    ir = np.stack([rng.standard_normal(n), rng.standard_normal(n)])
    ir *= np.exp(-damp * t)
    ir = np.stack([lowpass(ch, 6000) for ch in ir])
    ir[:, :int(0.012 * SR)] *= np.linspace(0, 1, int(0.012 * SR))
    return ir / np.abs(ir).sum(axis=1, keepdims=True) * 18


IR = make_ir()


def reverb(stereo, wet=0.35):
    out = np.stack([fftconvolve(stereo[i], IR[i])[: stereo.shape[1]] for i in range(2)])
    return (1 - wet) * stereo + wet * out


def to_stereo(mono, pan=0.0):
    l = np.cos((pan + 1) * np.pi / 4)
    r = np.sin((pan + 1) * np.pi / 4)
    return np.stack([mono * l, mono * r])


def normalize(x, peak=0.89):
    m = np.abs(x).max()
    return x * (peak / m) if m else x


def write_wav(path, stereo):
    data = np.clip(stereo.T, -1, 1)
    wavfile.write(path, SR, (data * 32767).astype(np.int16))


# --------------------------------------------------------------------- music
def fm(freq, dur, ratio=3.5, index=2.0, idecay=3.0):
    """Glassy FM tone: carrier + decaying modulator."""
    t = np.arange(int(dur * SR)) / SR
    mod = index * np.exp(-idecay * t) * np.sin(2 * np.pi * freq * ratio * t)
    return np.sin(2 * np.pi * freq * t + mod)


def menu_music(path_m4a, tmp_wav):
    bar = 9.0
    # Original progression in F (lydian colour), slower and darker than Psxp.
    chords = [
        [41, 53, 60, 64, 67, 71],   # Fmaj7#11 colour
        [38, 50, 57, 60, 64, 69],   # Dm9
        [46, 53, 58, 62, 65, 69],   # Bbmaj9
        [36, 48, 55, 58, 62, 67],   # C7sus-ish
        [41, 53, 57, 64, 67, 72],
        [45, 52, 57, 60, 64, 67],   # Am7
        [43, 50, 58, 62, 65, 70],   # Gm9
        [36, 48, 55, 60, 62, 67],   # Csus2
    ]
    loop = bar * len(chords)        # 72 s
    total = loop + bar
    N = int(total * SR)
    mix = np.zeros((2, N))
    t_all = np.arange(N) / SR

    # sub drone that breathes slowly
    drone = np.sin(2 * np.pi * note(29) * t_all) * (0.07 + 0.03 * np.sin(2 * np.pi * t_all / 18))
    mix += to_stereo(lowpass(drone, 120))

    # wide, slowly filtered pads (sine stacks, no triangle) for an airy, spacious bed
    for i, ch in enumerate(chords + chords[:1]):
        start = int(i * bar * SR)
        dur = bar + 5.0
        n = int(dur * SR)
        e = env_adsr(n, 3.5, 1.5, 0.75, 4.0)
        for j, m in enumerate(ch[1:]):
            for k, det in enumerate((-0.006, 0.006)):
                w = osc(note(m), dur, "sine", det, rng.uniform(0, 6.28)) * e * 0.06
                st = to_stereo(w, (-0.85, 0.85)[k])
                end = min(start + n, N)
                mix[:, start:end] += st[:, : end - start]

    # gentle FM-glass arpeggio, a fixed pattern per chord (not random)
    pattern = [0, 2, 4, 3, 5, 3, 4, 2]
    step = bar / 16
    for i, ch in enumerate(chords):
        tones = sorted(ch[2:]) + [ch[3] + 12, ch[4] + 12]
        for s in range(16):
            if s % 2 and rng.random() < 0.5:
                continue
            m = tones[pattern[s % 8] % len(tones)] + 12
            d = 1.8
            w = fm(note(m), d, ratio=3.5, index=1.6, idecay=5) * np.exp(-3.0 * np.arange(int(d * SR)) / SR)
            w *= np.minimum(np.arange(len(w)) / (0.003 * SR), 1) * 0.045
            st = int((i * bar + s * step) * SR)
            seg = to_stereo(w, 0.5 * np.sin(s * 0.8))
            k = min(seg.shape[1], N - st)
            mix[:, st:st + k] += seg[:, :k]

    # high shimmer: very quiet filtered noise with slow pan
    noise = highpass(rng.standard_normal(N), 4000) * 0.006 * (1 + np.sin(2 * np.pi * t_all / 24))
    mix += np.stack([noise * (1 + np.sin(t_all / 5)) / 2, noise * (1 - np.sin(t_all / 5)) / 2])

    mix = reverb(mix, 0.55)
    L = int(loop * SR)
    xf = N - L
    fade = np.linspace(0, 1, xf)
    out = mix[:, :L].copy()
    out[:, :xf] = out[:, :xf] * fade + mix[:, L:] * (1 - fade)
    write_wav(tmp_wav, normalize(out, 0.6))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp_wav, "-c:a", "aac", "-b:a", "160k",
                    path_m4a], check=True)
    os.remove(tmp_wav)


# --------------------------------------------------------------------- sounds
def boot_sound(path):
    """Deep rising sweep that blooms into a wide, bright chord, then settles."""
    dur = 7.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    mix = np.zeros((2, n))
    # rising pitch sweep (glide from F1 up an octave) under everything
    f = note(29) * 2 ** (np.clip(t / 2.2, 0, 1))
    ph = 2 * np.pi * np.cumsum(f) / SR
    sweep = np.sin(ph) * env_adsr(n, 1.8, 0.8, 0.5, 3.0) * 0.25
    mix += to_stereo(lowpass(sweep, 400))
    # air rush
    rush = lowpass(highpass(rng.standard_normal(n), 1500), 9000) * np.exp(-((t - 2.0) / 0.7) ** 2) * 0.09
    mix += np.stack([rush, np.roll(rush, 613)])
    # bloom chord at ~2.2s: Fmaj9(#11) spread wide, FM glass + sine
    for i, m in enumerate((53, 60, 64, 67, 71, 76, 79)):
        st = 2.1 + i * 0.03
        d = dur - st
        nn = int(d * SR)
        w = (0.6 * fm(note(m), d, ratio=2.0, index=1.2, idecay=1.5) + 0.4 * osc(note(m), d)) \
            * env_adsr(nn, 0.08, 1.8, 0.4, 2.8) * 0.09
        s = int(st * SR)
        seg = to_stereo(w, -0.9 + i * 0.3)
        k = min(seg.shape[1], n - s)
        mix[:, s:s + k] += seg[:, :k]
    mix = reverb(mix, 0.55)
    mix[:, -int(0.6 * SR):] *= np.linspace(1, 0, int(0.6 * SR))
    write_wav(path, normalize(mix, 0.85))


def glass(path, freqs, gap=0.0, decay=20.0, vol=0.5, ratio=3.5, index=1.4, wet=0.2, tail=0.4):
    m = int(tail * SR)
    n = int((gap * len(freqs)) * SR) + m
    mix = np.zeros((2, n))
    for i, f in enumerate(freqs):
        tt = np.arange(m) / SR
        w = fm(f, tail, ratio, index, idecay=decay * 0.6) * np.exp(-decay * tt) * np.minimum(tt / 0.0015, 1)
        s = int(i * gap * SR)
        k = min(m, n - s)
        mix[:, s:s + k] += to_stereo(w[:k] * vol, (i - (len(freqs) - 1) / 2) * 0.3)
    mix = reverb(mix, wet)
    a = np.abs(mix).max(axis=0)
    last = np.nonzero(a > 1e-3)[0]
    mix = mix[:, : (last[-1] + 1 if len(last) else n)]
    mix[:, -int(0.02 * SR):] *= np.linspace(1, 0, int(0.02 * SR))
    write_wav(path, normalize(mix, 0.8 * vol / 0.5))


def launch_sound(path):
    """Reverse-swell into a low impact and a fading wide chord."""
    dur = 3.4
    n = int(dur * SR)
    t = np.arange(n) / SR
    mix = np.zeros((2, n))
    # reversed swell (rises to 1.0 s)
    sw_n = int(1.0 * SR)
    tt = np.arange(sw_n) / SR
    swell = (fm(note(65), 1.0, 2.0, 2.5, 0.5) + 0.5 * highpass(rng.standard_normal(sw_n), 2000) * 0.2) \
        * (tt / 1.0) ** 3 * 0.25
    mix[:, :sw_n] += to_stereo(swell)
    # low impact
    hit_n = n - sw_n
    th = np.arange(hit_n) / SR
    hit = np.sin(2 * np.pi * (55 * np.exp(-th * 3)) * th) * np.exp(-th * 4) * 0.5
    mix[:, sw_n:] += to_stereo(hit)
    for i, m in enumerate((41, 53, 60, 65, 72)):
        w = osc(note(m), hit_n / SR, "sine") * np.exp(-th * 1.4) * (0.15 if i < 2 else 0.06)
        mix[:, sw_n:] += to_stereo(w, -0.5 + 0.25 * i)
    mix = reverb(mix, 0.45)
    mix[:, -int(0.3 * SR):] *= np.linspace(1, 0, int(0.3 * SR))
    write_wav(path, normalize(mix, 0.85))


def main(out):
    os.makedirs(out, exist_ok=True)
    menu_music(os.path.join(out, "ps3p_menu_music.m4a"), os.path.join(out, "_music.wav"))
    boot_sound(os.path.join(out, "ps3p_boot.wav"))
    launch_sound(os.path.join(out, "ps3p_launch.wav"))
    glass(os.path.join(out, "snd_cursor.wav"), [2093], decay=45, vol=0.3, ratio=4.0, index=0.8, wet=0.15, tail=0.15)
    glass(os.path.join(out, "snd_decide.wav"), [1397, 2093], gap=0.05, decay=14, vol=0.45)
    glass(os.path.join(out, "snd_cancel.wav"), [1568, 1047], gap=0.05, decay=16, vol=0.4, ratio=2.0)
    glass(os.path.join(out, "snd_oskenter.wav"), [1760], decay=40, vol=0.3, tail=0.15)
    glass(os.path.join(out, "snd_oskcancel.wav"), [1175], decay=40, vol=0.3, tail=0.15)
    glass(os.path.join(out, "snd_system_ok.wav"), [1047, 1397, 1760, 2093], gap=0.06, decay=8, vol=0.45, tail=0.8)
    glass(os.path.join(out, "snd_system_ng.wav"), [587, 554], gap=0.1, decay=7, vol=0.45, ratio=1.41, index=2.0, tail=0.6)
    glass(os.path.join(out, "snd_trophy.wav"), [1397, 1760, 2093, 2794], gap=0.08, decay=4, vol=0.45, wet=0.4, tail=1.4)


if __name__ == "__main__":
    main(sys.argv[1])
