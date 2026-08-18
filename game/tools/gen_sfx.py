#!/usr/bin/env python3
"""Synthesize every sound effect the game needs.

The pack ships music but no SFX. These are built from oscillators, noise and
envelopes rather than samples, so they're deterministic, tiny, tonally
consistent with each other, and regenerable.

Outputs 44.1 kHz 16-bit mono WAVs to assets/sfx/. Godot imports .wav directly.
"""
from __future__ import annotations

import math
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "sfx"
SR = 44100

rng = np.random.default_rng(20260815)


# --------------------------------------------------------------------------
# synthesis primitives
# --------------------------------------------------------------------------
def t(dur: float) -> np.ndarray:
    return np.linspace(0.0, dur, max(1, int(SR * dur)), endpoint=False)


def sweep(dur: float, f0: float, f1: float, kind="sine", curve=1.0) -> np.ndarray:
    """Oscillator with an exponential-ish pitch glide from f0 to f1."""
    tt = t(dur)
    k = (tt / dur) ** curve if dur > 0 else tt
    freq = f0 * (f1 / f0) ** k
    phase = 2 * np.pi * np.cumsum(freq) / SR
    if kind == "sine":
        return np.sin(phase)
    if kind == "saw":
        return 2.0 * ((phase / (2 * np.pi)) % 1.0) - 1.0
    if kind == "square":
        return np.sign(np.sin(phase))
    if kind == "tri":
        return 2.0 / np.pi * np.arcsin(np.sin(phase))
    raise ValueError(kind)


def tone(dur, freq, kind="sine"):
    return sweep(dur, freq, freq, kind)


def noise(dur: float) -> np.ndarray:
    return rng.uniform(-1.0, 1.0, len(t(dur)))


def env(sig: np.ndarray, a=0.005, d=0.05, s=0.0, r=0.05, sustain=0.0) -> np.ndarray:
    """ADSR. `sustain` is the sustain hold time in seconds."""
    n = len(sig)
    ai, di, si, ri = (max(1, int(x * SR)) for x in (a, d, sustain, r))
    total = ai + di + si + ri
    if total > n:  # squeeze to fit
        scale = n / total
        ai, di, si, ri = (max(1, int(x * scale)) for x in (ai, di, si, ri))
    e = np.concatenate([
        np.linspace(0, 1, ai),
        np.linspace(1, s, di),
        np.full(si, s),
        np.linspace(s, 0, ri),
    ])
    e = np.pad(e, (0, max(0, n - len(e))))[:n]
    return sig * e


def decay(sig: np.ndarray, tau: float) -> np.ndarray:
    # build the curve from the sample count, not a reconstructed duration -
    # round-tripping through seconds can be off by a sample and fail to broadcast
    return sig * np.exp(-np.arange(len(sig)) / (SR * tau))


def lowpass(sig: np.ndarray, cutoff: float) -> np.ndarray:
    """One-pole lowpass; cutoff in Hz."""
    a = math.exp(-2 * math.pi * cutoff / SR)
    out = np.empty_like(sig)
    y = 0.0
    for i, x in enumerate(sig):
        y = (1 - a) * x + a * y
        out[i] = y
    return out


def highpass(sig: np.ndarray, cutoff: float) -> np.ndarray:
    return sig - lowpass(sig, cutoff)


def drive(sig: np.ndarray, amount: float) -> np.ndarray:
    return np.tanh(sig * amount) / np.tanh(amount)


def pad(sig: np.ndarray, dur: float) -> np.ndarray:
    n = int(SR * dur)
    return np.pad(sig, (0, max(0, n - len(sig))))[:n]


def mix(*parts: np.ndarray) -> np.ndarray:
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def delay_echo(sig, time_s=0.09, feedback=0.35, taps=4):
    out = sig.copy()
    d = int(time_s * SR)
    for i in range(1, taps + 1):
        shifted = np.pad(sig, (d * i, 0))[: len(sig)] * (feedback ** i)
        out += shifted
    return out


def save(name: str, sig: np.ndarray, peak: float = 0.85):
    sig = np.nan_to_num(sig)
    m = np.max(np.abs(sig))
    if m > 0:
        sig = sig / m * peak
    # 3 ms fade in/out so nothing clicks at the boundaries
    f = min(int(0.003 * SR), len(sig) // 2)
    if f > 0:
        sig[:f] *= np.linspace(0, 1, f)
        sig[-f:] *= np.linspace(1, 0, f)
    data = (sig * 32767).astype("<i2")
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


# --------------------------------------------------------------------------
# the sounds
# --------------------------------------------------------------------------
def gun():
    # primary shot: body thump + bright transient
    body = decay(sweep(0.14, 620, 90, "square"), 0.030)
    crack = decay(highpass(noise(0.09), 2400), 0.014)
    save("shoot", drive(mix(body * 0.9, crack * 0.55), 2.2))

    # heavy shot (after big damage upgrades)
    body = decay(sweep(0.22, 380, 52, "saw"), 0.055)
    sub = decay(sweep(0.22, 150, 40, "sine"), 0.075)
    crack = decay(highpass(noise(0.12), 1600), 0.022)
    save("shoot_heavy", drive(mix(body * 0.8, sub * 0.7, crack * 0.5), 2.6))

    save("reload_start", decay(mix(
        lowpass(noise(0.05), 3200) * 0.7,
        decay(tone(0.05, 300, "square"), 0.012) * 0.4), 0.018))

    click = decay(highpass(noise(0.04), 1800), 0.010)
    clack = np.pad(decay(mix(highpass(noise(0.06), 1200) * 0.9,
                             decay(tone(0.06, 190, "square"), 0.02) * 0.5), 0.020),
                   (int(0.07 * SR), 0))
    save("reload_end", mix(click * 0.7, clack))

    save("dryfire", decay(highpass(noise(0.035), 3000), 0.008) * 0.6)


def impacts():
    # bullet hits flesh
    save("hit", drive(mix(
        decay(lowpass(noise(0.07), 1400), 0.018) * 0.9,
        decay(sweep(0.07, 260, 120, "sine"), 0.020) * 0.5), 1.8))

    # crit: same shape, brighter and with a ping on top
    save("crit", drive(mix(
        decay(lowpass(noise(0.08), 2600), 0.020) * 0.8,
        decay(tone(0.16, 1560), 0.045) * 0.45,
        decay(tone(0.16, 2340), 0.032) * 0.28), 2.0))

    # squelchy slime death
    save("enemy_death", mix(
        decay(lowpass(noise(0.20), 900), 0.055) * 0.9,
        decay(sweep(0.24, 420, 60, "tri"), 0.070) * 0.7,
        decay(sweep(0.18, 900, 180, "sine"), 0.035) * 0.3))

    save("enemy_shoot", drive(mix(
        decay(sweep(0.16, 900, 260, "tri"), 0.038) * 0.8,
        decay(highpass(noise(0.06), 3000), 0.012) * 0.3), 1.6))

    # explosion: orange enemy, grenade, boss slam
    n = lowpass(noise(0.75), 700)
    save("explosion", drive(mix(
        decay(n, 0.20) * 1.0,
        decay(sweep(0.75, 180, 26, "sine"), 0.22) * 0.9,
        decay(highpass(noise(0.12), 2000), 0.03) * 0.4), 2.4))

    save("player_hurt", drive(mix(
        decay(sweep(0.30, 300, 70, "saw"), 0.075) * 0.9,
        decay(lowpass(noise(0.18), 1100), 0.040) * 0.5), 2.0))


def pickups():
    # coin: two-tone bright blip
    a = decay(tone(0.09, 1318.5), 0.030)             # E6
    b = np.pad(decay(tone(0.14, 1975.5), 0.045), (int(0.05 * SR), 0))  # B6
    save("coin", mix(a * 0.7, b * 0.7))

    # potion: rising chime
    save("potion", mix(
        decay(sweep(0.40, 520, 1040, "sine"), 0.13) * 0.7,
        decay(sweep(0.40, 780, 1560, "sine"), 0.10) * 0.4))

    save("essence", delay_echo(mix(
        decay(tone(0.5, 880), 0.16) * 0.6,
        decay(tone(0.5, 1320), 0.12) * 0.4), 0.11, 0.30, 3))

    # gun upgrade: ascending major arpeggio, feels like a reward
    parts = []
    for i, f in enumerate((523.25, 659.25, 783.99, 1046.5)):
        seg = decay(mix(tone(0.36, f), tone(0.36, f * 2) * 0.3), 0.10)
        parts.append(np.pad(seg, (int(0.055 * i * SR), 0)))
    save("upgrade", mix(*parts))

    save("heal", mix(
        decay(sweep(0.55, 392, 784, "sine"), 0.18) * 0.6,
        decay(sweep(0.55, 587, 1175, "sine"), 0.14) * 0.35))


def abilities():
    # dash: short filtered whoosh
    w = noise(0.28)
    sw = np.array([lowpass(w, 400 + 3400 * (i / 8)) for i in range(1)])[0]
    save("dash", env(highpass(sw, 300), a=0.012, d=0.10, s=0.25, r=0.16) * 1.0)

    save("ability", mix(
        decay(sweep(0.45, 220, 880, "saw"), 0.13) * 0.5,
        decay(highpass(noise(0.30), 900), 0.09) * 0.5))

    save("shield", mix(
        decay(sweep(0.7, 180, 520, "sine"), 0.26) * 0.6,
        decay(sweep(0.7, 360, 1040, "tri"), 0.20) * 0.3))

    save("timeslow", mix(
        decay(sweep(1.0, 900, 120, "sine"), 0.34) * 0.6,
        decay(sweep(1.0, 1350, 180, "tri"), 0.28) * 0.3))

    crackle = highpass(noise(0.45), 3500) * (rng.random(len(t(0.45))) > 0.55)
    save("lightning", drive(mix(
        decay(crackle, 0.09) * 1.0,
        decay(sweep(0.45, 3000, 300, "saw"), 0.06) * 0.5,
        decay(sweep(0.5, 120, 40, "sine"), 0.14) * 0.6), 2.2))

    save("nova", drive(mix(
        decay(sweep(0.9, 900, 60, "saw"), 0.24) * 0.8,
        decay(lowpass(noise(0.9), 1400), 0.26) * 0.7,
        decay(sweep(0.9, 200, 30, "sine"), 0.30) * 0.8), 2.0))

    save("orbital", delay_echo(
        decay(sweep(0.6, 660, 1320, "tri"), 0.18) * 0.7, 0.075, 0.42, 4))

    save("decoy", mix(
        decay(sweep(0.35, 700, 350, "square"), 0.10) * 0.4,
        decay(highpass(noise(0.25), 1500), 0.07) * 0.4))

    save("lifesteal", mix(
        decay(sweep(0.5, 160, 640, "sine"), 0.17) * 0.6,
        decay(lowpass(noise(0.35), 800), 0.11) * 0.35))

    save("rapidfire", mix(
        decay(sweep(0.4, 300, 1200, "square"), 0.12) * 0.35,
        decay(highpass(noise(0.3), 2000), 0.08) * 0.35))


def bosses():
    # entrance horn: deep, slow, dread
    save("boss_spawn", drive(mix(
        decay(sweep(2.2, 55, 82, "saw"), 0.85) * 0.9,
        decay(sweep(2.2, 110, 164, "saw"), 0.70) * 0.45,
        decay(sweep(2.2, 27, 41, "sine"), 1.00) * 0.9,
        decay(lowpass(noise(2.2), 300), 0.9) * 0.3), 1.8))

    save("boss_attack", drive(mix(
        decay(sweep(0.6, 220, 44, "saw"), 0.18) * 0.9,
        decay(lowpass(noise(0.6), 800), 0.16) * 0.6), 2.2))

    save("boss_hit", drive(mix(
        decay(lowpass(noise(0.14), 1000), 0.035) * 0.9,
        decay(sweep(0.14, 180, 80, "square"), 0.040) * 0.6), 2.0))

    # death: rumble, then a bright collapse
    rumble = decay(lowpass(noise(1.8), 260), 0.55) * 0.9
    fall = decay(sweep(1.8, 400, 30, "saw"), 0.40) * 0.7
    crash = np.pad(decay(highpass(noise(0.9), 1200), 0.22) * 0.6, (int(0.25 * SR), 0))
    save("boss_death", drive(mix(rumble, fall, crash), 2.0))

    # pre-attack warning tick
    save("telegraph", mix(
        decay(tone(0.18, 1480, "tri"), 0.045) * 0.6,
        decay(tone(0.18, 2220, "sine"), 0.030) * 0.3))

    save("boss_phase", drive(mix(
        decay(sweep(1.2, 300, 90, "saw"), 0.35) * 0.7,
        decay(sweep(1.2, 60, 45, "sine"), 0.50) * 0.9,
        decay(highpass(noise(0.5), 2000), 0.12) * 0.4), 2.0))


def ui_and_flow():
    save("ui_click", decay(mix(
        tone(0.06, 880, "tri") * 0.6,
        highpass(noise(0.03), 4000) * 0.25), 0.016))
    save("ui_hover", decay(tone(0.05, 1320, "sine"), 0.012) * 0.4)
    save("ui_confirm", mix(
        decay(tone(0.16, 784), 0.05) * 0.6,
        np.pad(decay(tone(0.22, 1174.7), 0.07) * 0.6, (int(0.06 * SR), 0))))
    save("ui_deny", mix(
        decay(tone(0.16, 220, "square"), 0.05) * 0.5,
        np.pad(decay(tone(0.20, 165, "square"), 0.06) * 0.5, (int(0.07 * SR), 0))))

    # wave start: drum hit plus a rising call
    save("wave_start", drive(mix(
        decay(sweep(0.5, 160, 50, "sine"), 0.13) * 0.9,
        decay(lowpass(noise(0.3), 900), 0.07) * 0.5,
        np.pad(decay(sweep(0.6, 440, 660, "tri"), 0.20) * 0.5, (int(0.10 * SR), 0))),
        1.6))

    save("wave_clear", mix(*[
        np.pad(decay(mix(tone(0.4, f), tone(0.4, f * 2) * 0.25), 0.13) * 0.6,
               (int(0.07 * i * SR), 0))
        for i, f in enumerate((659.25, 830.6, 987.77, 1318.5))]))

    save("shop_enter", mix(
        decay(sweep(0.7, 330, 660, "tri"), 0.24) * 0.5,
        decay(tone(0.7, 990), 0.18) * 0.25))

    save("purchase", mix(
        decay(tone(0.12, 1046.5), 0.035) * 0.6,
        np.pad(decay(tone(0.3, 1568), 0.10) * 0.6, (int(0.055 * SR), 0)),
        decay(lowpass(noise(0.08), 5000), 0.02) * 0.25))

    # low-health warning pulse
    save("low_health", mix(
        decay(tone(0.28, 196, "tri"), 0.09) * 0.7,
        decay(tone(0.28, 98, "sine"), 0.11) * 0.5))

    save("death", drive(mix(
        decay(sweep(2.0, 300, 34, "saw"), 0.62) * 0.8,
        decay(sweep(2.0, 150, 20, "sine"), 0.75) * 0.8,
        decay(lowpass(noise(1.2), 500), 0.35) * 0.4), 1.7))

    save("unlock", mix(*[
        np.pad(decay(mix(tone(0.6, f), tone(0.6, f * 2) * 0.3,
                         tone(0.6, f * 3) * 0.12), 0.20) * 0.55,
               (int(0.09 * i * SR), 0))
        for i, f in enumerate((523.25, 659.25, 783.99, 1046.5, 1318.5))]))


# --------------------------------------------------------------------------
# music layers - looping percussion stacked under the user's tracks
# --------------------------------------------------------------------------
# "Normal Music.mp3" is 19.1475 s, which is 8 bars of 4/4 at ~100.3 BPM. The
# other three tracks land near whole bar counts at the same tempo, so layers
# generated at 100 BPM sit under all of them. They're mixed low on purpose:
# MP3 encoder padding makes perfectly gapless alignment impossible, and a
# quiet layer stays musical even if it drifts a few milliseconds.
BPM = 100.0
BEAT = 60.0 / BPM          # 0.6 s
BAR = BEAT * 4             # 2.4 s


def _place(buf: np.ndarray, sig: np.ndarray, at: float):
    i = int(at * SR)
    end = min(len(buf), i + len(sig))
    if i < len(buf):
        buf[i:end] += sig[: end - i]


def _kick():
    return drive(decay(sweep(0.32, 150, 42, "sine"), 0.075) * 1.0, 1.6)


def _snare():
    return mix(decay(highpass(noise(0.20), 1200), 0.055) * 0.8,
               decay(tone(0.20, 190, "tri"), 0.030) * 0.4)


def _hat(open_=False):
    d = 0.14 if open_ else 0.05
    return decay(highpass(noise(d), 7000), d * 0.30) * 0.35


def _tom(f):
    return decay(sweep(0.30, f, f * 0.5, "sine"), 0.070) * 0.7


def music_layers():
    bars = 2
    dur = BAR * bars
    n = int(dur * SR)

    # mini-boss: driving four-on-the-floor with backbeat
    buf = np.zeros(n)
    for b in range(bars):
        o = b * BAR
        for beat in range(4):
            _place(buf, _kick() * (1.0 if beat % 2 == 0 else 0.55), o + beat * BEAT)
            if beat % 2 == 1:
                _place(buf, _snare(), o + beat * BEAT)
            for eighth in (0.0, 0.5):
                _place(buf, _hat(eighth == 0.0), o + (beat + eighth) * BEAT)
    save("layer_mini", buf, peak=0.72)

    # major boss: heavier, with tom fills at the end of the phrase
    buf = np.zeros(n)
    for b in range(bars):
        o = b * BAR
        for beat in range(4):
            _place(buf, _kick(), o + beat * BEAT)
            _place(buf, _kick() * 0.5, o + (beat + 0.75) * BEAT)
            if beat % 2 == 1:
                _place(buf, _snare() * 1.1, o + beat * BEAT)
            for s in (0.0, 0.25, 0.5, 0.75):
                _place(buf, _hat(s == 0.0) * 0.8, o + (beat + s) * BEAT)
        _place(buf, decay(sweep(BAR, 46, 34, "sine"), 0.9) * 0.8, o)
    for i, f in enumerate((260, 200, 150, 110)):
        _place(buf, _tom(f), BAR * bars - BEAT * (1.0 - i * 0.25) - 0.0)
    save("layer_major", buf, peak=0.80)

    # wave escalation: sparse driving pulse, no backbeat
    buf = np.zeros(n)
    for b in range(bars):
        o = b * BAR
        for beat in range(4):
            _place(buf, decay(sweep(0.5, 70, 44, "sine"), 0.14) * 0.9, o + beat * BEAT)
            _place(buf, _hat(), o + (beat + 0.5) * BEAT)
    save("layer_escalation", buf, peak=0.62)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for label, fn in (
        ("gun", gun), ("impacts", impacts), ("pickups", pickups),
        ("abilities", abilities), ("bosses", bosses), ("ui/flow", ui_and_flow),
        ("music layers", music_layers),
    ):
        fn()
        print(f"  {label}")
    files = sorted(OUT.glob("*.wav"))
    total = sum(f.stat().st_size for f in files) / 1024
    print(f"{len(files)} sfx, {total:.0f} KB -> {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
