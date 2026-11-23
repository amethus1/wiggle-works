#!/usr/bin/env python3
"""Regenerate Wiggle Works' audio/ folder: every sound effect and the music loops.

All sounds are synthesized from scratch with the Python standard library only
(no numpy, no sample files, no network) using a fixed random seed, so the
output is identical on every run. Files written (relative to the project root):

    audio/sfx/<name>.wav         one per sound effect (see SFX below)
    audio/music/<loop>.wav       seamless 16-bar music loops (see LOOPS):
        wiggle_loop  the title menu         calm_loop    the 2D sandbox
        ready_loop   building a 3D battle   battle_loop  3D fighting
        each with its loop points in the file (see LOOP_LEAD)

Format: 16-bit mono PCM WAV at 22050 Hz. Effects are peak-normalized to about
-1 dBFS with short fades; the music loops peak at or below about -3 dBFS.

Run from anywhere:
    python3 tools/gen_audio.py              # regenerate everything, then verify
    python3 tools/gen_audio.py boom pop     # only those effects ("music" = every loop)
    python3 tools/gen_audio.py calm_loop    # only that loop
    python3 tools/gen_audio.py --verify     # only check the existing files
"""

import array
import math
import os
import random
import sys
import wave
import zlib

SR = 22050
TAU = 2.0 * math.pi
SEED = 20261119
SFX_PEAK = 0.89          # about -1 dBFS
MUSIC_PEAK = 0.708       # about -3 dBFS

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SFX_DIR = os.path.join(ROOT, "audio", "sfx")
MUSIC_PATH = os.path.join(ROOT, "audio", "music", "wiggle_loop.wav")

sin = math.sin
exp = math.exp


# =========================================================== synth toolkit
def ns(sec):
    """Seconds -> sample count (at least 1)."""
    return max(1, int(round(sec * SR)))


def buf(sec):
    return [0.0] * ns(sec)


def midi(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def ramp(n, a, b, curve="lin", power=1.0):
    """n values from a to b; 'exp' interpolates geometrically (a, b > 0)."""
    if n <= 1:
        return [float(a)] * n
    inv = 1.0 / (n - 1)
    if curve == "exp":
        la = math.log(a)
        d = math.log(b) - la
        return [exp(la + d * (i * inv) ** power) for i in range(n)]
    d = b - a
    return [a + d * (i * inv) ** power for i in range(n)]


def env(n, points):
    """Piecewise-linear curve through [(time_sec, value), ...]."""
    out = [0.0] * n
    pts = [(int(round(t * SR)), float(v)) for t, v in points]
    fi, fv = pts[0]
    for i in range(0, min(n, max(0, fi))):
        out[i] = fv
    for (i0, a), (i1, b) in zip(pts, pts[1:]):
        if i1 <= i0:
            continue
        step = (b - a) / (i1 - i0)
        for i in range(max(0, i0), min(n, i1)):
            out[i] = a + step * (i - i0)
    li, lv = pts[-1]
    for i in range(max(0, li), n):
        out[i] = lv
    return out


def fpath(n, points):
    """Frequency glide through [(time_sec, hz), ...], interpolated in log space."""
    return [exp(v) for v in env(n, [(t, math.log(f)) for t, f in points])]


def decay(n, tau, attack=0.002):
    """Linear attack then exponential decay with time constant tau (s)."""
    out = [0.0] * n
    a = max(1, int(attack * SR))
    for i in range(min(a, n)):
        out[i] = i / a
    d = exp(-1.0 / (tau * SR))
    g = 1.0
    for i in range(a, n):
        out[i] = g
        g *= d
    return out


def _attack(x, sec):
    a = max(1, int(sec * SR))
    for i in range(min(a, len(x))):
        x[i] *= i / a
    return x


def fade_tail(x, sec):
    f = min(len(x), ns(sec))
    L = len(x)
    for i in range(f):
        x[L - 1 - i] *= i / f
    return x


def mul(x, y):
    if isinstance(y, (int, float)):
        return [v * y for v in x]
    return [a * b for a, b in zip(x, y)]


def add(*items):
    """add((list, gain), ...) -> new list as long as the longest input."""
    n = max(len(x) for x, _ in items)
    out = [0.0] * n
    for x, g in items:
        mix(out, x, 0, g, samples=True)
    return out


def mix(dst, src, at=0.0, gain=1.0, samples=False):
    """Add src*gain into dst (in place) starting at `at` seconds (or samples)."""
    i0 = at if samples else int(round(at * SR))
    if i0 < 0:
        src = src[-i0:]
        i0 = 0
    end = min(len(dst), i0 + len(src))
    if end > i0:
        dst[i0:end] = [a + gain * b for a, b in zip(dst[i0:end], src)]
    return dst


def norm(x, peak=1.0):
    m = max(abs(v) for v in x) if x else 0.0
    if m <= 0.0:
        return x[:]
    g = peak / m
    return [v * g for v in x]


def sat(x, drive):
    """Soft saturation (adds warm harmonics, tames peaks)."""
    t = math.tanh
    return [t(drive * v) for v in x]


def noise(n, rng):
    r = rng.random
    return [2.0 * r() - 1.0 for _ in range(n)]


def smooth_rand(n, rng, rate_hz, lo=0.0, hi=1.0):
    """Smoothly wandering random control curve (cosine-interpolated)."""
    step = max(1, int(SR / rate_hz))
    pts = [rng.uniform(lo, hi) for _ in range(n // step + 3)]
    out = [0.0] * n
    cos = math.cos
    for i in range(n):
        j, r = divmod(i, step)
        t = 0.5 - 0.5 * cos(math.pi * r / step)
        out[i] = pts[j] + (pts[j + 1] - pts[j]) * t
    return out


# ---- oscillators
def _sh_sine(p):
    return sin(TAU * p)


def _sh_tri(p):
    p += 0.25
    p -= int(p)
    return 1.0 - 4.0 * abs(p - 0.5)


def _sh_cute(p):
    a = TAU * p
    return sin(a) + 0.32 * sin(2 * a) + 0.1 * sin(3 * a)


def _sh_soft(p):
    return math.tanh(2.2 * sin(TAU * p))


def _sh_reed(p):
    a = TAU * p
    return (sin(a) + 0.62 * sin(2 * a) + 0.48 * sin(3 * a) + 0.33 * sin(4 * a)
            + 0.22 * sin(5 * a) + 0.14 * sin(6 * a) + 0.08 * sin(7 * a))


SHAPES = {"sine": _sh_sine, "tri": _sh_tri, "cute": _sh_cute,
          "soft": _sh_soft, "reed": _sh_reed}


def osc(freq, n=None, shape="sine", vib=0.0, vib_rate=6.0, vib_delay=0.0):
    """Phase-accumulating oscillator. freq: Hz or per-sample list of Hz.
    vib: vibrato depth (fraction of pitch), optionally faded in over vib_delay."""
    fl = freq if isinstance(freq, list) else None
    if n is None:
        n = len(fl)
    f0 = 0.0 if fl is not None else float(freq)
    fn = SHAPES[shape]
    out = [0.0] * n
    p = 0.0
    inv = 1.0 / SR
    vw = TAU * vib_rate / SR
    vd = int(vib_delay * SR)
    for i in range(n):
        f = fl[i] if fl is not None else f0
        if vib:
            depth = vib if (vd <= 0 or i >= vd) else vib * i / vd
            f *= 1.0 + depth * sin(vw * i)
        p += f * inv
        p -= int(p)
        out[i] = fn(p)
    return out


def partials_tone(f, dur, parts, attack=0.002):
    """Fixed-pitch additive tone. parts: [(ratio, amp, tau_sec or 0)]."""
    n = ns(dur)
    out = [0.0] * n
    for ratio, amp, tau in parts:
        fr = f * ratio
        if fr >= 0.47 * SR:
            continue
        w = TAU * fr / SR
        d = exp(-1.0 / (tau * SR)) if tau else 1.0
        g = amp
        for i in range(n):
            out[i] += g * sin(w * i)
            g *= d
    return _attack(out, attack)


def harmonic_tone(freqs, parts, attack=0.003):
    """Additive tone following a per-sample pitch list.
    parts: [(multiple, amp, tau_sec or 0)], each partial decays on its own."""
    n = len(freqs)
    out = [0.0] * n
    inv = 1.0 / SR
    nyq = 0.47 * SR
    for k, amp, tau in parts:
        d = exp(-1.0 / (tau * SR)) if tau else 1.0
        g = amp
        p = 0.0
        for i in range(n):
            f = freqs[i] * k
            p += f * inv
            if f < nyq:
                out[i] += g * sin(TAU * p)
            g *= d
    return _attack(out, attack)


def thump(dur, f0, f1, tau, sweep_tau, attack=0.002):
    """Sine with a fast pitch drop f0 -> f1: kick drums, cartoon thumps."""
    n = ns(dur)
    out = [0.0] * n
    a = max(1, int(attack * SR))
    d = exp(-1.0 / (tau * SR))
    ks = exp(-1.0 / (sweep_tau * SR))
    s = 1.0
    g = 1.0
    p = 0.0
    inv = 1.0 / SR
    for i in range(n):
        p += (f1 + (f0 - f1) * s) * inv
        s *= ks
        v = sin(TAU * p) * g
        if i < a:
            v *= i / a
        else:
            g *= d
        out[i] = v
    return out


# ---- filters
def lowpass(x, fc):
    """One-pole lowpass; fc in Hz (number or per-sample list)."""
    out = [0.0] * len(x)
    y = 0.0
    if isinstance(fc, list):
        k = -TAU / SR
        for i, v in enumerate(x):
            y += (1.0 - exp(k * fc[i])) * (v - y)
            out[i] = y
    else:
        a = 1.0 - exp(-TAU * fc / SR)
        for i, v in enumerate(x):
            y += a * (v - y)
            out[i] = y
    return out


def highpass(x, fc):
    return [a - b for a, b in zip(x, lowpass(x, fc))]


def svf(x, fc, q=0.707, mode="bp"):
    """Topology-preserving state-variable filter (stable for any cutoff).
    mode 'bp' is scaled to unity gain at the centre frequency."""
    n = len(x)
    out = [0.0] * n
    k = 1.0 / q
    lim = 0.45 * SR
    var = isinstance(fc, list)
    tan = math.tan
    if not var:
        g = tan(math.pi * min(fc, lim) / SR)
        a1 = 1.0 / (1.0 + g * (g + k))
        a2 = g * a1
        a3 = g * a2
    ic1 = ic2 = 0.0
    m = 0 if mode == "lp" else (1 if mode == "bp" else 2)
    for i in range(n):
        if var:
            f = fc[i]
            g = tan(math.pi * (f if f < lim else lim) / SR)
            a1 = 1.0 / (1.0 + g * (g + k))
            a2 = g * a1
            a3 = g * a2
        v0 = x[i]
        v3 = v0 - ic2
        v1 = a1 * ic1 + a2 * v3
        v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2.0 * v1 - ic1
        ic2 = 2.0 * v2 - ic2
        if m == 0:
            out[i] = v2
        elif m == 1:
            out[i] = k * v1
        else:
            out[i] = v0 - k * v1 - v2
    return out


def echo(x, delay_sec, fb, wet, lp=3000.0):
    """Feedback echo with a darkening lowpass in the loop (in place, no tail)."""
    d = ns(delay_sec)
    a = 1.0 - exp(-TAU * lp / SR)
    line = [0.0] * len(x)
    s = 0.0
    for i in range(d, len(x)):
        s += a * (x[i - d] + fb * line[i - d] - s)
        line[i] = s
    return [v + wet * e for v, e in zip(x, line)]


# ---- building blocks
def chirp(dur, f0, f1=None, shape="sine", vib=0.0, vib_rate=7.0,
          attack=0.006, release=0.03, power=1.0):
    n = ns(dur)
    fr = ramp(n, f0, f1 if f1 else f0, "exp", power)
    x = osc(fr, n, shape, vib, vib_rate)
    return mul(x, env(n, [(0, 0), (attack, 1), (max(attack, dur - release), 0.85), (dur, 0)]))


def blip(dur, path, shape="cute", vib=0.03, vib_rate=10.0, attack=0.008,
         release=0.03, vib_delay=0.0, hold=0.85):
    """Creature-voice syllable: pitch glides through path [(t, hz), ...]."""
    n = ns(dur)
    x = osc(fpath(n, path), n, shape, vib, vib_rate, vib_delay)
    return mul(x, env(n, [(0, 0), (attack, 1), (max(attack, dur - release), hold), (dur, 0)]))


def bell(f, dur, tau=0.4, bright=1.0):
    return partials_tone(f, dur, [(1, 1.0, tau), (2, 0.35 * bright, tau * 0.5),
                                  (2.76, 0.2 * bright, tau * 0.3), (5.4, 0.07 * bright, tau * 0.12)])


def marimba(f, dur=0.7, tau=0.25):
    return partials_tone(f, dur, [(1, 1.0, tau), (2, 0.12, tau * 0.4), (3.93, 0.16, 0.03)])


def ping(f, tau=0.05):
    parts = [(1, 1.0, tau)]
    if f * 2.32 < 6500:
        parts.append((2.32, 0.2, tau * 0.5))
    return partials_tone(f, tau * 6, parts, attack=0.0015)


def grain(rng, dur, fc, q=1.5):
    """Tiny Hann-windowed band of noise (rustles, crackles, rain ticks)."""
    n = ns(dur)
    g = svf(noise(n, rng), fc, q, "bp")
    w = [0.5 - 0.5 * math.cos(TAU * i / n) for i in range(n)]
    return norm(mul(g, w))


def drip(f, tau=0.035, rise=1.9, dur=0.12):
    """Water drop plink: sine with a fast upward glide."""
    n = ns(dur)
    return harmonic_tone(fpath(n, [(0, f * 0.7), (0.025, f * rise * 0.95), (dur, f * rise)]),
                         [(1, 1.0, tau)], attack=0.0015)


def sparkles(dst, rng, t0, t1, count, fmin, fmax, amp, tau=0.04):
    for _ in range(count):
        mix(dst, ping(rng.uniform(fmin, fmax), tau), rng.uniform(t0, t1),
            amp * rng.uniform(0.6, 1.0))
    return dst


def noise_lp(n, rng, fc, passes=2):
    x = noise(n, rng)
    for _ in range(passes):
        x = lowpass(x, fc)
    return norm(x)


# ---- output
def finish(x, peak=SFX_PEAK, fade_in=0.005, fade_out=0.010, min_len=0.05):
    """DC-block, trim trailing silence, fade both ends, normalize the peak."""
    x = highpass(x, 18.0)
    m = max(abs(v) for v in x) or 1.0
    thr = m * 0.0015
    end = len(x)
    while end > 1 and abs(x[end - 1]) < thr:
        end -= 1
    end = min(len(x), max(end + ns(0.01), ns(min_len)))
    x = x[:end]
    fi = min(ns(fade_in), len(x) // 4)
    fo = min(ns(fade_out), len(x) // 4)
    cos = math.cos
    for i in range(fi):
        x[i] *= 0.5 - 0.5 * cos(math.pi * i / fi)
    L = len(x)
    for i in range(fo):
        x[L - 1 - i] *= 0.5 - 0.5 * cos(math.pi * i / fo)
    x[-1] = 0.0
    return norm(x, peak)


def write_wav(path, x):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = array.array("h", [32767 if v >= 1.0 else (-32767 if v <= -1.0 else int(round(v * 32767.0)))
                             for v in x])
    if sys.byteorder == "big":
        data.byteswap()
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


# ============================================================ sound effects
SFX = {}


def sfx(name):
    def deco(fn):
        SFX[name] = fn
        return fn
    return deco


@sfx("spawn")
def _spawn(rng):
    x = buf(0.75)
    mix(x, chirp(0.06, 320, 950, attack=0.003, release=0.04), 0.0, 0.55)
    for k, m in enumerate((76, 79, 84, 88)):          # E5 G5 C6 E6
        mix(x, bell(midi(m), 0.62 - 0.05 * k, tau=0.16 + 0.03 * k, bright=0.5),
            0.03 + 0.055 * k, 0.5)
    sparkles(x, rng, 0.1, 0.5, 7, 2300, 3600, 0.14, tau=0.035)
    return x


@sfx("poof")
def _poof(rng):
    n = ns(0.5)
    fc = ramp(n, 2600, 300, "exp")
    air = norm(lowpass(lowpass(noise(n, rng), fc), fc))
    air = mul(air, decay(n, 0.1, attack=0.018))
    body = thump(0.25, 160, 70, 0.07, 0.05)
    return add((air, 1.0), (body, 0.35))


@sfx("hop")
def _hop(rng):
    n = ns(0.28)
    x = osc(fpath(n, [(0, 230), (0.09, 560), (0.28, 500)]), n, "tri", 0.05, 22)
    x = lowpass(mul(x, decay(n, 0.08, attack=0.004)), 3000)
    return add((x, 1.0), (thump(0.08, 180, 90, 0.03, 0.02), 0.4))


@sfx("giggle1")
def _giggle1(rng):        # "hee-hee-hee-hee", tumbling down
    x = buf(0.52)
    t = 0.0
    for k, base in enumerate((1150, 1040, 950, 860)):
        d = 0.075 if k < 3 else 0.1
        mix(x, blip(d, [(0, base * 0.95), (d * 0.35, base * 1.12), (d, base * 0.88)],
                    vib=0.03, vib_rate=12), t, 1.0 - 0.1 * k)
        t += d + 0.035
    return x


@sfx("giggle2")
def _giggle2(rng):        # quick rising "hihihihi!"
    x = buf(0.5)
    t = 0.0
    for k, base in enumerate((720, 800, 880, 980, 1150)):
        d = 0.05 if k < 4 else 0.12
        mix(x, blip(d, [(0, base * 0.9), (d, base * 1.15)], vib=0.03 if k < 4 else 0.05,
                    vib_rate=10, attack=0.006, release=0.02 if k < 4 else 0.05), t, 0.85 + 0.04 * k)
        t += d + 0.025
    return x


@sfx("giggle3")
def _giggle3(rng):        # "tee-HEE!" plus a little hiccup
    x = buf(0.52)
    mix(x, blip(0.09, [(0, 950), (0.05, 1250), (0.09, 1100)], vib=0.02), 0.0, 0.8)
    mix(x, blip(0.2, [(0, 1150), (0.06, 1450), (0.2, 980)], vib=0.045, vib_rate=9,
                release=0.06), 0.14, 1.0)
    mix(x, blip(0.05, [(0, 1500), (0.03, 1700), (0.05, 1600)], vib=0.0, attack=0.005,
                release=0.02), 0.41, 0.45)
    return x


@sfx("squish")
def _squish(rng):
    n = ns(0.36)
    wet = norm(svf(noise(n, rng), ramp(n, 1400, 260, "exp"), 3.5, "bp"))
    wet = mul(wet, env(n, [(0, 0), (0.01, 1), (0.05, 0.35), (0.08, 0.9), (0.14, 0.3),
                           (0.18, 0.6), (0.36, 0)]))
    nb = ns(0.25)
    bloop = osc(fpath(nb, [(0, 420), (0.08, 170), (0.25, 140)]), nb, "sine", 0.06, 28)
    bloop = mul(bloop, decay(nb, 0.07, attack=0.006))
    return lowpass(add((wet, 0.6), (bloop, 0.7)), 3000)


@sfx("thud")
def _thud(rng):
    body = thump(0.22, 190, 105, 0.045, 0.02)
    wood = partials_tone(420, 0.22, [(1, 0.5, 0.03), (2.3, 0.2, 0.015)])
    knock = lowpass(mul(noise(ns(0.02), rng), decay(ns(0.02), 0.004, 0.0008)), 1800)
    return add((body, 1.0), (wood, 0.6), (norm(knock), 0.3))


@sfx("clink")
def _clink(rng):
    ring = partials_tone(1760, 0.4, [(1, 1.0, 0.11), (1.51, 0.45, 0.08),
                                     (2.44, 0.28, 0.05), (3.6, 0.08, 0.025)], attack=0.001)
    tick = norm(highpass(mul(noise(ns(0.01), rng), decay(ns(0.01), 0.0015, 0.0005)), 2000))
    return add((ring, 1.0), (tick, 0.15))


@sfx("boing")
def _boing(rng):
    n = ns(0.5)
    f = [0.0] * n
    for i in range(n):
        t = i / SR
        f[i] = 200 * (1 + 0.7 * (1 - exp(-t / 0.025))) * (1 + 0.16 * sin(TAU * 15 * t) * exp(-t / 0.18))
    x = mul(osc(f, n, "cute"), decay(n, 0.16, attack=0.003))
    return lowpass(x, 2500)


@sfx("boing_big")
def _boing_big(rng):
    n = ns(1.1)
    f = [0.0] * n
    for i in range(n):
        t = i / SR
        f[i] = 110 * (1 + 0.75 * (1 - exp(-t / 0.04))) * (1 + 0.22 * sin(TAU * 8.5 * t) * exp(-t / 0.5))
    tone = harmonic_tone(f, [(1, 1.0, 0), (2, 0.5, 0), (3, 0.25, 0.6), (4, 0.12, 0.3)])
    tone = lowpass(mul(tone, decay(n, 0.35, attack=0.004)), 2200)
    return add((tone, 1.0), (thump(0.2, 150, 60, 0.05, 0.03), 0.5))


@sfx("tink")
def _tink(rng):
    ring = partials_tone(2350, 0.3, [(1, 1.0, 0.07), (2.32, 0.2, 0.03)], attack=0.001)
    tick = norm(highpass(mul(noise(ns(0.006), rng), decay(ns(0.006), 0.001, 0.0005)), 3000))
    return add((ring, 1.0), (tick, 0.08))


@sfx("ding")
def _ding(rng):
    return partials_tone(1046.5, 1.0, [(1, 1.0, 0.42), (2, 0.3, 0.22), (2.76, 0.14, 0.12),
                                       (5.4, 0.04, 0.05), (0.5, 0.12, 0.5)])


@sfx("click")
def _click(rng):
    x = buf(0.06)
    c = mul(norm(svf(noise(ns(0.012), rng), 2600, 1.2, "bp")), decay(ns(0.012), 0.0025, 0.0005))
    t = partials_tone(1400, 0.03, [(1, 0.5, 0.006), (2.2, 0.2, 0.003)], attack=0.0005)
    mix(x, c, 0.005, 1.0)
    mix(x, t, 0.005, 1.0)
    mix(x, c, 0.022, 0.45)
    return x


@sfx("tick")
def _tick(rng):
    x = buf(0.06)
    c = mul(norm(svf(noise(ns(0.01), rng), 3200, 2.0, "bp")), decay(ns(0.01), 0.002, 0.0005))
    t = partials_tone(2000, 0.04, [(1, 0.35, 0.005)], attack=0.0005)
    w = partials_tone(900, 0.05, [(1, 0.4, 0.008)], attack=0.0008)
    mix(x, c, 0.005, 0.6)
    mix(x, t, 0.005, 1.0)
    mix(x, w, 0.005, 1.0)
    return x


@sfx("grab")
def _grab(rng):
    return chirp(0.09, 480, 720, "sine", attack=0.012, release=0.05)


@sfx("link")
def _link(rng):
    x = buf(0.42)
    c = mul(norm(svf(noise(ns(0.015), rng), 2200, 1.5, "bp")), decay(ns(0.015), 0.003, 0.0005))
    knock = partials_tone(900, 0.06, [(1, 0.6, 0.012), (1.7, 0.3, 0.008)], attack=0.0008)
    mix(x, c, 0.005, 0.7)
    mix(x, knock, 0.005, 1.0)
    mix(x, c, 0.027, 0.5)
    mix(x, partials_tone(1200, 0.05, [(1, 0.4, 0.01)], attack=0.0008), 0.027, 1.0)
    mix(x, ping(midi(96), 0.08), 0.055, 0.35)         # C7
    mix(x, ping(midi(100), 0.1), 0.1, 0.3)            # E7
    return lowpass(x, 7000)


@sfx("snap")
def _snap(rng):
    x = buf(0.45)
    crack = norm(lowpass(highpass(mul(noise(ns(0.015), rng), decay(ns(0.015), 0.003, 0.0005)), 1200), 6000))
    n = ns(0.42)
    f = [0.0] * n
    for i in range(n):
        t = i / SR
        f[i] = 290 * (1 - 0.18 * (1 - exp(-t / 0.08))) * (1 + 0.025 * sin(TAU * 13 * t))
    twang = harmonic_tone(f, [(k, 1.0 / k, 0.22 / k ** 0.7) for k in range(1, 7)], attack=0.002)
    mix(x, crack, 0.0, 0.5)
    mix(x, twang, 0.006, 0.8)
    return x


@sfx("paint")
def _paint(rng):
    n = ns(0.28)
    wet = mul(norm(svf(noise(n, rng), ramp(n, 1800, 450, "exp"), 1.8, "bp")), decay(n, 0.06, 0.006))
    nb = ns(0.1)
    blop = harmonic_tone(fpath(nb, [(0, 330), (0.06, 150), (0.1, 140)]), [(1, 1.0, 0.04)])
    return lowpass(add((wet, 1.0), (blop, 0.5)), 4500)


@sfx("fuse")
def _fuse(rng):
    n = ns(0.55)
    hiss = norm(lowpass(highpass(noise(n, rng), 2200), 6500))
    hiss = mul(hiss, smooth_rand(n, rng, 60, 0.35, 1.0))
    x = mul(hiss, env(n, [(0, 0), (0.03, 1), (0.45, 0.85), (0.55, 0)]))
    x = mul(x, 0.55)
    for _ in range(14):
        t = rng.uniform(0.02, 0.48)
        mix(x, grain(rng, rng.uniform(0.002, 0.005), rng.uniform(2500, 4500), 1.2), t,
            rng.uniform(0.4, 0.9))
    return lowpass(x, 6500)


@sfx("zap")
def _zap(rng):
    n = ns(0.4)
    jitter = smooth_rand(n, rng, 40, -1.0, 1.0)
    fb = [ramp_v * (1 + 0.04 * j) for ramp_v, j in zip(ramp(n, 135, 100, "exp"), jitter)]
    buzz = lowpass(lowpass(osc(fb, n, "soft"), 2800), 2800)
    trem = [0.65 + 0.35 * sin(TAU * 28 * i / SR) for i in range(n)]
    buzz = mul(norm(buzz), trem)
    zip_ = harmonic_tone(fpath(n, [(0, 1400), (0.4, 350)]), [(1, 0.5, 0.15), (2, 0.15, 0.08)])
    x = add((buzz, 0.6), (zip_, 0.6))
    return mul(x, env(n, [(0, 0), (0.01, 1), (0.3, 0.7), (0.4, 0)]))


@sfx("flame")
def _flame(rng):
    n = ns(0.8)
    fc = env(n, [(0, 400), (0.2, 1600), (0.8, 500)])
    w = noise(n, rng)
    whoosh = norm(lowpass(lowpass(w, fc), fc))
    roar = noise_lp(n, rng, 180)
    flick = smooth_rand(n, rng, 18, 0.55, 1.0)
    x = mul(add((whoosh, 1.0), (roar, 0.6)), flick)
    x = mul(x, env(n, [(0, 0), (0.18, 1), (0.5, 0.7), (0.8, 0)]))
    for _ in range(6):
        mix(x, grain(rng, rng.uniform(0.003, 0.006), rng.uniform(1500, 3000), 1.0),
            rng.uniform(0.1, 0.6), rng.uniform(0.15, 0.3))
    return x


@sfx("freeze")
def _freeze(rng):
    x = buf(1.0)
    scale = (84, 86, 88, 91, 93, 96, 98, 100)          # C6..E7 pentatonic
    count = 18
    for k in range(count):
        t = 0.02 + k * 0.045 + rng.uniform(-0.01, 0.01)
        idx = min(len(scale) - 1, max(0, int(k * len(scale) / count) + rng.choice((-1, 0, 1))))
        mix(x, ping(midi(scale[idx]), 0.12), t, rng.uniform(0.25, 0.45))
    n = len(x)
    shimmer = mul(norm(svf(noise(n, rng), 3800, 4.0, "bp")), env(n, [(0, 0), (0.3, 1), (1.0, 0)]))
    pad = add((partials_tone(1568, 1.0, [(1, 1.0, 0)]), 0.5), (partials_tone(1576, 1.0, [(1, 1.0, 0)]), 0.5))
    pad = mul(pad, env(n, [(0, 0), (0.2, 0.6), (0.7, 1.0), (1.0, 0)]))
    mix(x, shimmer, 0, 0.12)
    mix(x, pad, 0, 0.18)
    return lowpass(x, 7000)


@sfx("thaw")
def _thaw(rng):
    x = buf(0.9)
    for t, f, a in ((0.0, 900, 1.0), (0.17, 760, 0.8), (0.3, 1000, 0.9),
                    (0.5, 680, 0.75), (0.68, 820, 0.65)):
        mix(x, drip(f * rng.uniform(0.97, 1.03), tau=0.03), t + rng.uniform(-0.01, 0.01), a)
    return x


@sfx("pound")
def _pound(rng):
    n = ns(0.75)
    low = thump(0.75, 130, 42, 0.18, 0.05)
    dirt = mul(noise_lp(n, rng, 350), decay(n, 0.08, 0.003))
    bonk = partials_tone(210, 0.15, [(1, 0.5, 0.04), (1.6, 0.2, 0.02)])
    x = sat(add((low, 1.0), (dirt, 0.5), (bonk, 0.6)), 1.8)
    return lowpass(x, 3000)


@sfx("warp")
def _warp(rng):
    n = ns(0.75)
    f = ramp(n, 180, 1900, "exp", 1.6)
    a = osc(f, n, "tri", 0.05, 14)
    b = osc([v * 1.504 for v in f], n, "sine", 0.04, 11)
    x = mul(add((a, 0.6), (b, 0.35)), env(n, [(0, 0), (0.05, 0.6), (0.5, 1), (0.75, 0)]))
    sparkles(x, rng, 0.45, 0.68, 5, 2400, 3400, 0.12, tau=0.04)
    return lowpass(x, 4500)


@sfx("split")
def _split(rng):
    x = buf(0.5)
    mix(x, thump(0.06, 700, 250, 0.015, 0.01), 0.0, 0.7)
    mix(x, mul(norm(svf(noise(ns(0.03), rng), 1500, 1.0, "bp")), decay(ns(0.03), 0.006, 0.0008)), 0.0, 0.4)
    mix(x, blip(0.3, [(0, 700), (0.25, 1600), (0.3, 1550)], vib=0.04, vib_rate=9,
                attack=0.02, release=0.06, vib_delay=0.1), 0.07, 0.8)
    return x


@sfx("merge")
def _merge(rng):
    x = buf(0.8)
    mix(x, marimba(midi(79), 0.65, 0.28), 0.0, 0.8)     # G5
    mix(x, marimba(midi(84), 0.65, 0.3), 0.13, 0.9)     # C6
    mix(x, marimba(midi(88), 0.6, 0.25), 0.13, 0.3)     # E6 harmony
    return x


@sfx("boom")
def _boom(rng):
    n = ns(1.4)
    low = thump(1.4, 120, 45, 0.32, 0.07)
    fc = ramp(n, 1400, 180, "exp", 0.6)
    body = mul(norm(lowpass(lowpass(noise(n, rng), fc), fc)), decay(n, 0.28, 0.006))
    pomf = mul(norm(svf(noise(n, rng), 260, 1.2, "bp")), decay(n, 0.12, 0.004))
    x = sat(add((low, 0.9), (body, 0.55), (pomf, 0.45)), 1.5)
    return lowpass(x, 3800)


@sfx("mega_boom")
def _mega_boom(rng):
    n = ns(2.2)
    low = thump(2.2, 100, 34, 0.5, 0.1)
    low2 = thump(1.0, 85, 40, 0.35, 0.08)
    fc = ramp(n, 1100, 120, "exp", 0.6)
    body = mul(norm(lowpass(lowpass(noise(n, rng), fc), fc)), decay(n, 0.45, 0.008))
    rumble = mul(noise_lp(n, rng, 140, 3), smooth_rand(n, rng, 7, 0.4, 1.0))
    rumble = mul(rumble, env(n, [(0, 0), (0.15, 1), (0.8, 0.7), (2.2, 0)]))
    x = add((low, 1.0), (body, 0.5), (rumble, 0.45))
    mix(x, low2, 0.11, 0.6)
    return lowpass(sat(x, 1.6), 3000)


@sfx("confetti")
def _confetti(rng):
    x = buf(0.95)
    mix(x, mul(norm(svf(noise(ns(0.05), rng), 1400, 0.9, "bp")), decay(ns(0.05), 0.008, 0.001)), 0.0, 0.8)
    mix(x, thump(0.08, 380, 140, 0.025, 0.015), 0.0, 0.6)
    for _ in range(70):
        r = rng.random()
        t = 0.04 + 0.86 * r ** 1.8
        mix(x, grain(rng, rng.uniform(0.004, 0.012), rng.uniform(2500, 5000), 2.0), t,
            0.35 * (1.0 - 0.6 * r) * rng.uniform(0.5, 1.0))
    return lowpass(x, 7000)


@sfx("firework_launch")
def _firework_launch(rng):
    n = ns(1.0)
    f = ramp(n, 520, 2100, "exp", 0.8)
    whistle = osc(f, n, "sine", 0.012, 9)
    breath = norm(svf(noise(n, rng), f, 6.0, "bp"))
    hiss = norm(lowpass(highpass(noise(n, rng), 1500), 5000))
    x = mul(add((whistle, 0.6), (breath, 0.35), (hiss, 0.06)),
            env(n, [(0, 0), (0.08, 0.8), (0.75, 1), (1.0, 0)]))
    nl = ns(0.12)
    mix(x, mul(noise_lp(nl, rng, 600), decay(nl, 0.03, 0.003)), 0.0, 0.5)
    return x


@sfx("firework_burst")
def _firework_burst(rng):
    x = buf(1.6)
    nb = ns(0.4)
    bang = add((thump(0.4, 150, 55, 0.1, 0.03), 1.0),
               (mul(noise_lp(nb, rng, 1500), decay(nb, 0.06, 0.003)), 0.6))
    mix(x, sat(bang, 1.4), 0.0, 1.0)
    for _ in range(110):
        r = rng.random()
        t = 0.12 + 1.38 * r ** 1.6
        a = (1.0 - 0.6 * r)
        if rng.random() < 0.6:
            mix(x, grain(rng, rng.uniform(0.002, 0.005), rng.uniform(2000, 4000), 1.2), t,
                0.3 * a * rng.uniform(0.5, 1.0))
        else:
            mix(x, ping(rng.uniform(2000, 3400), 0.025), t, 0.2 * a * rng.uniform(0.5, 1.0))
    n = len(x)
    fizz = mul(norm(lowpass(highpass(noise(n, rng), 3000), 6000)),
               env(n, [(0.1, 0), (0.25, 1), (1.5, 0)]))
    mix(x, fizz, 0, 0.05)
    return lowpass(x, 7000)


@sfx("splat")
def _splat(rng):
    x = buf(0.55)
    n = len(x)
    mix(x, thump(0.2, 220, 80, 0.05, 0.02), 0.0, 0.7)
    wet = mul(norm(svf(noise(n, rng), ramp(n, 2200, 350, "exp", 0.5), 2.2, "bp")),
              env(n, [(0, 0), (0.006, 1), (0.06, 0.5), (0.3, 0)]))
    mix(x, wet, 0.0, 0.8)
    for _ in range(5):
        mix(x, drip(rng.uniform(500, 900), tau=0.02), rng.uniform(0.12, 0.45), rng.uniform(0.15, 0.3))
    return lowpass(x, 5000)


@sfx("bubble")
def _bubble(rng):
    x = buf(0.55)
    for t, f0, a in ((0.0, 260, 1.0), (0.11, 340, 0.8), (0.2, 420, 0.7), (0.34, 300, 0.85)):
        nb = ns(0.12)
        b = harmonic_tone(fpath(nb, [(0, f0), (0.06, f0 * 2.2), (0.12, f0 * 2.4)]),
                          [(1, 1.0, 0.03)], attack=0.002)
        mix(x, b, t + rng.uniform(-0.01, 0.01), a)
    return x


@sfx("bubble_pop")
def _bubble_pop(rng):
    x = buf(0.1)
    nb = ns(0.08)
    mix(x, harmonic_tone(fpath(nb, [(0, 900), (0.03, 1900), (0.08, 2000)]), [(1, 1.0, 0.012)],
                         attack=0.001), 0.003, 1.0)
    mix(x, grain(rng, 0.002, 3000, 1.0), 0.003, 0.3)
    return x


@sfx("glue")
def _glue(rng):
    n = ns(0.5)
    sticky = norm(svf(noise(n, rng), env(n, [(0, 700), (0.25, 260), (0.5, 200)]), 6.0, "bp"))
    sticky = mul(sticky, env(n, [(0, 0), (0.02, 1), (0.12, 0.6), (0.2, 0.9), (0.5, 0)]))
    f = fpath(n, [(0, 260), (0.2, 140), (0.5, 120)])
    f = [v * (1 + 0.08 * sin(TAU * 25 * i / SR)) for i, v in enumerate(f)]
    gloop = mul(harmonic_tone(f, [(1, 1.0, 0.2), (2, 0.3, 0.1)]), env(n, [(0, 1), (0.4, 1), (0.5, 0)]))
    return lowpass(add((sticky, 0.5), (gloop, 0.6)), 2500)


@sfx("glass")
def _glass(rng):
    x = buf(1.0)
    crack = norm(lowpass(highpass(mul(noise(ns(0.05), rng), decay(ns(0.05), 0.012, 0.001)), 1500), 6000))
    mix(x, crack, 0.0, 0.5)
    for _ in range(26):
        r = rng.random()
        t = 0.005 + 0.85 * r ** 1.7
        f = rng.uniform(1700, 3800)
        tau = rng.uniform(0.04, 0.1)
        parts = [(1, 1.0, tau)]
        if f * 2.7 < 7000:
            parts.append((2.7, 0.3, tau * 0.4))
        mix(x, partials_tone(f, tau * 5, parts, attack=0.001), t,
            rng.uniform(0.5, 0.9) * (1.0 - 0.6 * r) * 0.5)
    return lowpass(x, 6500)


@sfx("steam")
def _steam(rng):
    n = ns(0.6)
    x = norm(lowpass(highpass(noise(n, rng), 1800), 6000))
    x = mul(x, smooth_rand(n, rng, 25, 0.75, 1.0))
    return mul(x, env(n, [(0, 0), (0.04, 1), (0.35, 0.8), (0.6, 0)]))


@sfx("splash")
def _splash(rng):
    x = buf(0.85)
    n = len(x)
    nb = ns(0.1)
    mix(x, harmonic_tone(fpath(nb, [(0, 450), (0.04, 180), (0.1, 170)]), [(1, 1.0, 0.04)]), 0.0, 0.6)
    wash = norm(svf(noise(n, rng), env(n, [(0, 1600), (0.1, 1100), (0.85, 500)]), 0.9, "bp"))
    wash = mul(wash, env(n, [(0, 0), (0.012, 1), (0.12, 0.6), (0.4, 0.25), (0.85, 0)]))
    mix(x, wash, 0.0, 0.7)
    for _ in range(8):
        mix(x, drip(rng.uniform(700, 1400), tau=0.02), rng.uniform(0.15, 0.7), rng.uniform(0.12, 0.25))
    return lowpass(x, 5500)


@sfx("cannon")
def _cannon(rng):
    n = ns(0.9)
    low = thump(0.9, 95, 45, 0.22, 0.06)
    fc = env(n, [(0, 250), (0.06, 1400), (0.9, 300)])
    fwoo = mul(norm(lowpass(lowpass(noise(n, rng), fc), fc)),
               env(n, [(0, 0), (0.01, 1), (0.15, 0.5), (0.9, 0)]))
    pomf = mul(norm(svf(noise(n, rng), 300, 1.0, "bp")), decay(n, 0.07, 0.003))
    oomp = harmonic_tone(fpath(ns(0.25), [(0, 180), (0.25, 90)]), [(1, 1.0, 0.08)])
    x = add((low, 0.8), (fwoo, 0.45), (pomf, 0.4), (oomp, 0.3))
    return lowpass(sat(x, 1.4), 3500)


@sfx("pop")
def _pop(rng):
    x = buf(0.25)
    burst = mul(norm(svf(noise(ns(0.05), rng), 1300, 0.8, "bp")), decay(ns(0.05), 0.01, 0.0008))
    tail = mul(noise_lp(ns(0.2), rng, 900), decay(ns(0.2), 0.05, 0.002))
    mix(x, burst, 0.004, 1.0)
    mix(x, thump(0.1, 320, 110, 0.025, 0.012), 0.004, 0.6)
    mix(x, tail, 0.004, 0.2)
    return x


@sfx("puff")
def _puff(rng):
    n = ns(0.45)
    breath = norm(svf(noise(n, rng), ramp(n, 450, 1300, "exp"), 1.4, "bp"))
    breath = mul(breath, env(n, [(0, 0), (0.28, 1), (0.45, 0)]))
    stretch = mul(osc(ramp(n, 180, 280, "exp"), n, "sine"), env(n, [(0, 0), (0.25, 1), (0.45, 0)]))
    return add((breath, 1.0), (stretch, 0.15))


@sfx("whoosh")
def _whoosh(rng):
    n = ns(0.5)
    fc = env(n, [(0, 350), (0.22, 2400), (0.5, 500)])
    x = norm(svf(noise(n, rng), fc, 1.3, "bp"))
    return mul(x, env(n, [(0, 0), (0.18, 1), (0.26, 0.85), (0.5, 0)]))


@sfx("party")
def _party(rng):
    x = buf(1.55)
    n = ns(1.2)
    # kazoo "ta-da-da-DAAA" (C4 E4 G4 C5) with tiny glides between notes
    f = fpath(n, [(0, 262), (0.11, 262), (0.125, 330), (0.235, 330), (0.25, 392),
                  (0.355, 392), (0.37, 523), (1.05, 523), (1.2, 540)])
    kazoo = osc(f, n, "reed", 0.018, 6.0, vib_delay=0.55)
    kazoo = add((kazoo, 1.0), (norm(svf(kazoo, 1100, 2.0, "bp")), 0.6))
    art = env(n, [(0, 0), (0.015, 1), (0.1, 0.8), (0.12, 0.35), (0.135, 1), (0.22, 0.8),
                  (0.24, 0.35), (0.255, 1), (0.34, 0.8), (0.36, 0.35), (0.38, 1),
                  (0.9, 0.85), (1.2, 0)])
    mix(x, lowpass(mul(kazoo, art), 3500), 0.0, 0.5)
    # bells doubling two octaves up
    for t, m in ((0.0, 84), (0.12, 88), (0.24, 91), (0.37, 96)):
        mix(x, bell(midi(m), 0.9, 0.3, 0.4), t, 0.2)
    mix(x, thump(0.25, 160, 90, 0.08, 0.03), 0.37, 0.4)
    sparkles(x, rng, 0.4, 1.3, 9, 2300, 3500, 0.1, tau=0.05)
    return x


@sfx("wind")
def _wind(rng):
    n = ns(2.3)
    w = noise(n, rng)
    gust = smooth_rand(n, rng, 1.6, 0.25, 1.0)
    whistle = norm(svf(w, [300 + 700 * g for g in gust], 2.2, "bp"))
    body = norm(lowpass(lowpass(w, 500), 500))
    x = mul(add((whistle, 0.7), (body, 0.4)), gust)
    return mul(x, env(n, [(0, 0), (0.35, 1), (1.8, 1), (2.3, 0)]))


@sfx("rain")
def _rain(rng):
    n = ns(2.3)
    x = mul(norm(lowpass(highpass(noise(n, rng), 600), 3500)), 0.12)
    for _ in range(320):
        t = rng.uniform(0.0, 2.25)
        if rng.random() < 0.7:
            mix(x, grain(rng, rng.uniform(0.003, 0.008), rng.uniform(1500, 4500), 1.5), t,
                rng.uniform(0.1, 0.4))
        else:
            mix(x, drip(rng.uniform(700, 1600), tau=0.01, dur=0.05), t, rng.uniform(0.05, 0.15))
    x = mul(x, env(n, [(0, 0), (0.3, 1), (1.9, 1), (2.3, 0)]))
    return lowpass(x, 6000)


@sfx("magic")
def _magic(rng):
    x = buf(1.15)
    for k, m in enumerate((72, 74, 76, 79, 81, 84, 86, 88, 91, 93, 96)):   # C5..C7 pentatonic
        harp = partials_tone(midi(m), 0.6, [(1, 1.0, 0.25), (2, 0.3, 0.1), (3, 0.08, 0.05)])
        mix(x, harp, k * 0.055, 0.45 * (1 - 0.03 * k))
    sparkles(x, rng, 0.4, 0.95, 6, 2500, 3500, 0.1, tau=0.05)
    return lowpass(echo(x, 0.09, 0.3, 0.35, 4000), 7000)


@sfx("rumble")
def _rumble(rng):
    n = ns(2.3)
    w = noise(n, rng)
    lo = norm(lowpass(lowpass(lowpass(w, 110), 110), 110))
    lo = mul(lo, smooth_rand(n, rng, 9, 0.35, 1.0))
    rattle_amt = [v * v for v in smooth_rand(n, rng, 14, 0.0, 1.0)]
    rattle = mul(norm(svf(w, 380, 2.0, "bp")), rattle_amt)
    x = mul(add((lo, 0.9), (rattle, 0.15)), env(n, [(0, 0), (0.25, 1), (1.6, 0.8), (2.3, 0)]))
    for _ in range(6):
        t = rng.uniform(0.15, 1.6)
        mix(x, thump(0.25, 110, 55, 0.07, 0.03), t, rng.uniform(0.3, 0.6))
    return lowpass(sat(x, 1.8), 1500)


@sfx("undo")
def _undo(rng):
    n = ns(0.28)
    fwd = harmonic_tone(fpath(n, [(0, 450), (0.28, 800)]), [(1, 1.0, 0), (2, 0.25, 0)])
    fwd = mul(fwd, mul(decay(n, 0.07, attack=0.025), env(n, [(0, 1), (0.26, 1), (0.28, 0)])))
    return fwd[::-1]                     # played backwards: soft swell, pitch sliding down


@sfx("honk")
def _honk(rng):          # cartoon car horn: two notes together, "beep-beeeep"
    x = buf(0.62)
    for t0, dur in ((0.0, 0.13), (0.2, 0.34)):
        n = ns(dur)
        tone = add((osc(410.0, n, "reed", 0.004, 7.0), 0.6), (osc(515.0, n, "reed", 0.004, 7.0), 0.5))
        tone = mul(tone, env(n, [(0, 0), (0.012, 1), (dur - 0.03, 0.9), (dur, 0)]))
        mix(x, lowpass(tone, 3200), t0, 1.0)
    return sat(x, 1.6)


@sfx("nope")
def _nope(rng):
    x = buf(0.48)
    n1 = ns(0.15)
    b1 = harmonic_tone(fpath(n1, [(0, 300), (0.05, 330), (0.15, 310)]),
                       [(1, 1.0, 0), (2, 0.35, 0), (3, 0.15, 0)])
    b1 = mul(b1, env(n1, [(0, 0), (0.015, 1), (0.11, 0.9), (0.15, 0)]))
    n2 = ns(0.25)
    b2 = harmonic_tone(fpath(n2, [(0, 250), (0.06, 262), (0.25, 215)]),
                       [(1, 1.0, 0), (2, 0.35, 0), (3, 0.15, 0)])
    b2 = mul(b2, env(n2, [(0, 0), (0.015, 1), (0.18, 0.85), (0.25, 0)]))
    mix(x, b1, 0.0, 1.0)
    mix(x, b2, 0.2, 1.0)
    return lowpass(x, 2500)


@sfx("sticker")
def _sticker(rng):
    x = buf(1.05)
    for t, m in ((0.0, 79), (0.08, 84), (0.16, 88), (0.26, 91)):    # G5 C6 E6 G6
        mix(x, marimba(midi(m), 0.7, 0.25), t, 0.6)
    for m in (84, 88):                                               # soft C6+E6 bloom
        mix(x, bell(midi(m), 0.75, 0.35, 0.3), 0.26, 0.25)
    sparkles(x, rng, 0.3, 0.8, 5, 2400, 3400, 0.12, tau=0.05)
    return x


@sfx("wee")
def _wee(rng):
    n = ns(0.65)
    x = osc(fpath(n, [(0, 480), (0.1, 620), (0.5, 1500), (0.65, 1450)]), n, "cute",
            0.045, 8, vib_delay=0.15)
    x = mul(x, env(n, [(0, 0), (0.03, 0.9), (0.45, 1), (0.65, 0)]))
    breath = mul(norm(svf(noise(n, rng), 1200, 1.5, "bp")), env(n, [(0, 0), (0.02, 1), (0.08, 0)]))
    return add((x, 1.0), (breath, 0.12))


@sfx("eek")
def _eek(rng):
    n = ns(0.26)
    x = osc(fpath(n, [(0, 900), (0.03, 1750), (0.18, 1700), (0.26, 1450)]), n, "cute", 0.03, 16)
    return mul(x, env(n, [(0, 0), (0.008, 1), (0.2, 0.85), (0.26, 0)]))


@sfx("yay")
def _yay(rng):
    x = buf(0.68)
    mix(x, blip(0.09, [(0, 620), (0.09, 900)], vib=0.0, attack=0.01, release=0.02), 0.0, 0.8)
    mix(x, blip(0.5, [(0, 880), (0.12, 1180), (0.5, 1000)], vib=0.04, vib_rate=7,
                attack=0.015, release=0.12, vib_delay=0.1, hold=0.9), 0.1, 1.0)
    sparkles(x, rng, 0.2, 0.55, 3, 2400, 3200, 0.08, tau=0.04)
    return x


@sfx("dizzy")
def _dizzy(rng):
    n = ns(1.05)
    base = ramp(n, 900, 330, "exp")
    f = [b * (1 + 0.09 * sin(TAU * 6.5 * i / SR)) for i, b in enumerate(base)]
    x = osc(f, n, "cute")
    trem = [0.8 + 0.2 * sin(TAU * 3.25 * i / SR) for i in range(n)]
    return mul(mul(x, trem), env(n, [(0, 0), (0.03, 1), (0.8, 0.8), (1.05, 0)]))


# ===================================================== combat sound effects
# Battle-mode sounds: toy guns, cartoon melee, creature voices and big (but
# friendly) booms. Every effect still gets its own seed from its name, so
# adding these never changes any file above. Each one ends in tame() so very
# little energy is left above ~7 kHz.
COMBAT_SFX = []


def combat_sfx(name):
    COMBAT_SFX.append(name)
    return sfx(name)


# ---- combat building blocks
def tame(x, fc=6000.0):
    """4-pole Butterworth-style lowpass: steep top-end roll-off, nothing harsh."""
    return svf(svf(x, fc, 0.541, "lp"), fc, 1.307, "lp")


def nburst(rng, dur, fc, q=1.0, tau=0.01, attack=0.0008):
    """Short decaying band of noise: gun pops, smacks, knocks."""
    n = ns(dur)
    return mul(norm(svf(noise(n, rng), fc, q, "bp")), decay(n, tau, attack))


def snap_noise(rng, dur, tau, lo=1000.0, hi=5500.0):
    """Broadband shot snap, band-limited so it pops without getting piercing."""
    n = ns(dur)
    x = highpass(mul(noise(n, rng), decay(n, tau, 0.0004)), lo)
    return norm(lowpass(lowpass(x, hi), hi))


def sweep_noise(rng, dur, path, q=1.5, shape=None):
    """Band of noise whose centre glides through path [(t, hz), ...] (swishes)."""
    n = ns(dur)
    x = norm(svf(noise(n, rng), fpath(n, path), q, "bp"))
    return mul(x, env(n, shape)) if shape else x


def vibrato(freqs, depth, rate, delay=0.0):
    """Pitch list with vibrato (depth = fraction of pitch), faded in over delay."""
    vd = int(delay * SR)
    w = TAU * rate / SR
    return [f * (1.0 + (depth if i >= vd else depth * i / vd) * sin(w * i))
            for i, f in enumerate(freqs)]


def jitter(freqs, rng, amount, rate=25.0):
    """Pitch list with a smooth random wobble (rough, organic voices)."""
    j = smooth_rand(len(freqs), rng, rate, -amount, amount)
    return [f * (1.0 + d) for f, d in zip(freqs, j)]


def buzz(freqs, nharm=16, tilt=1.0, attack=0.004, top=6500.0):
    """Band-limited sawtooth-like source following a pitch list (voices, horns).
    Harmonics that would ever rise above `top` Hz are left out."""
    hi = max(freqs)
    parts = [(k, 1.0 / k ** tilt, 0) for k in range(1, nharm + 1) if k == 1 or k * hi < top]
    return harmonic_tone(freqs, parts, attack)


def subharm(freqs, depth=0.35):
    """Amplitude curve pulsing at half the pitch: growly throat roughness."""
    out = [0.0] * len(freqs)
    p = 0.0
    k = 0.5 / SR
    for i, f in enumerate(freqs):
        p += f * k
        p -= int(p)
        out[i] = 1.0 - depth + depth * sin(TAU * p)
    return out


def vowel(x, bands):
    """Parallel band-pass formant filter. bands: [(hz or per-sample list, q, gain), ...]."""
    out = [0.0] * len(x)
    for fc, q, g in bands:
        mix(out, svf(x, fc, q, "bp"), 0, g, samples=True)
    return out


def grunt(rng, dur, path, f1, f2, wobble=0.03, breath=0.12):
    """Cartoon hurt grunt: a buzzy pitch drop through two gliding formants
    (paths of (t, hz)), ending in a little puff of breath ("oo-f")."""
    n = ns(dur)
    f = jitter(vibrato(fpath(n, path), wobble, 11.0), rng, 0.015, 30)
    src = buzz(f, 14, 1.0)
    x = add((vowel(src, [(fpath(n, f1), 3.5, 1.0), (fpath(n, f2), 5.0, 0.45)]), 1.0), (src, 0.08))
    x = norm(mul(x, env(n, [(0, 0), (0.008, 1), (dur * 0.45, 0.8), (dur, 0)])))
    if breath:
        nb = ns(dur * 0.6)
        huff = mul(norm(svf(noise(nb, rng), 1700, 1.0, "bp")),
                   env(nb, [(0, 0), (dur * 0.3, 1), (dur * 0.6, 0)]))
        mix(x, huff, dur * 0.4, breath)
    return x


def horn(f, dur, attack=0.025, release=0.08, scoop=0.0, vib=0.0, vib_delay=0.15,
         bright=2600.0, tilt=0.8):
    """Brassy note: buzzy partials through a lowpass that opens as it swells."""
    n = ns(dur)
    fr = fpath(n, [(0, f * (1.0 - scoop)), (min(0.06, dur * 0.3), f), (dur, f)])
    if vib:
        fr = vibrato(fr, vib, 5.5, vib_delay)
    a = env(n, [(0, 0), (attack, 1), (max(attack, dur - release), 0.85), (dur, 0)])
    src = buzz(fr, 12, tilt)
    return mul(svf(src, [350.0 + bright * v for v in a], 0.9, "lp"), a)


def drum(rng, dur=0.7, f0=120.0, f1=50.0, tau=0.2):
    """Big round war drum: pitch-dropping thump plus a soft skin slap."""
    x = thump(dur, f0, f1, tau, 0.03)
    mix(x, nburst(rng, 0.18, 350, 0.8, 0.03, 0.001), 0.0, 0.45)
    mix(x, nburst(rng, 0.04, 1200, 0.7, 0.006), 0.0, 0.15)
    return fade_tail(x, dur * 0.4)


# ---- guns (toy-like: a round pitched pop carries each shot, the noise stays soft)
@combat_sfx("gun_pistol")
def _gun_pistol(rng):
    x = buf(0.32)
    n = len(x)
    mix(x, thump(0.22, 460, 120, 0.035, 0.01), 0.0, 0.85)
    mix(x, nburst(rng, 0.08, 1500, 0.8, 0.012), 0.0, 0.7)
    mix(x, snap_noise(rng, 0.03, 0.004, 900, 5000), 0.0, 0.4)
    mix(x, mul(noise_lp(n, rng, 800), decay(n, 0.05, 0.002)), 0.0, 0.25)
    return tame(sat(x, 1.6), 5500)


@combat_sfx("gun_rifle")
def _gun_rifle(rng):
    x = buf(0.45)
    n = len(x)
    mix(x, snap_noise(rng, 0.05, 0.006, 1500, 6000), 0.0, 1.0)
    mix(x, nburst(rng, 0.1, 2300, 1.0, 0.015), 0.0, 0.6)
    mix(x, thump(0.22, 400, 120, 0.03, 0.01), 0.0, 0.55)
    mix(x, mul(noise_lp(n, rng, 1200), decay(n, 0.05, 0.002)), 0.0, 0.25)
    x = echo(sat(x, 1.5), 0.055, 0.2, 0.22, 2500)
    return tame(x, 6000)


@combat_sfx("gun_shotgun")
def _gun_shotgun(rng):
    x = buf(0.65)
    n = len(x)
    fc = ramp(n, 3200, 250, "exp", 0.5)
    blast = mul(norm(lowpass(lowpass(noise(n, rng), fc), fc)), decay(n, 0.09, 0.0015))
    mix(x, fade_tail(thump(0.6, 180, 62, 0.1, 0.025), 0.15), 0.0, 0.9)
    mix(x, blast, 0.0, 0.9)
    mix(x, nburst(rng, 0.3, 450, 0.9, 0.045), 0.0, 0.5)
    for t, g in ((0.0, 0.35), (0.004, 0.3), (0.009, 0.2)):        # a spread of pellets
        mix(x, snap_noise(rng, 0.04, 0.005, 800, 4500), t, g)
    return tame(sat(x, 1.7), 4500)


@combat_sfx("gun_mg")
def _gun_mg(rng):           # one tight shot, meant to be retriggered rapidly
    x = buf(0.09)
    mix(x, thump(0.09, 420, 150, 0.018, 0.006), 0.0, 0.9)
    mix(x, nburst(rng, 0.05, 1700, 0.9, 0.006), 0.0, 0.7)
    mix(x, snap_noise(rng, 0.02, 0.002, 1200, 5000), 0.0, 0.3)
    return tame(sat(x, 1.5), 5500)


@combat_sfx("gun_sniper")
def _gun_sniper(rng):
    x = buf(0.95)
    nt = ns(0.4)
    mix(x, snap_noise(rng, 0.06, 0.007, 1200, 6000), 0.0, 1.0)
    mix(x, nburst(rng, 0.12, 2000, 0.9, 0.018), 0.0, 0.6)
    mix(x, thump(0.45, 300, 80, 0.07, 0.015), 0.0, 0.7)
    mix(x, mul(noise_lp(nt, rng, 1000), decay(nt, 0.07, 0.002)), 0.0, 0.35)
    x = echo(sat(x, 1.5), 0.14, 0.38, 0.5, 1800)                  # canyon slap-back
    return tame(x, 6000)


@combat_sfx("gun_laser")
def _gun_laser(rng):        # "pew!"
    n = ns(0.26)
    f = vibrato(ramp(n, 2200, 300, "exp", 0.7), 0.025, 45)
    pew = harmonic_tone(f, [(1, 1.0, 0), (2, 0.3, 0)], attack=0.001)
    sub = osc([v * 0.5 for v in f], n, "soft")
    x = add((pew, 0.75), (sub, 0.3))
    x = mul(x, env(n, [(0, 0), (0.004, 1), (0.08, 0.8), (0.26, 0)]))
    return tame(x, 5500)


# ---- launchers and bows
@combat_sfx("bazooka")
def _bazooka(rng):          # "thoomp" + rocket whoosh trailing away
    x = buf(0.85)
    n = len(x)
    mix(x, thump(0.45, 150, 55, 0.08, 0.025), 0.0, 0.9)
    mix(x, nburst(rng, 0.3, 320, 0.9, 0.05), 0.0, 0.5)
    mix(x, snap_noise(rng, 0.03, 0.005, 700, 3500), 0.0, 0.25)
    fc = env(n, [(0, 600), (0.08, 2600), (0.85, 700)])
    whoosh = mul(norm(svf(noise(n, rng), fc, 1.2, "bp")), smooth_rand(n, rng, 30, 0.6, 1.0))
    mix(x, mul(whoosh, env(n, [(0, 0), (0.03, 1), (0.25, 0.6), (0.85, 0)])), 0.0, 0.55)
    return tame(sat(x, 1.5), 5000)


@combat_sfx("rocket")
def _rocket(rng):           # short rocket hiss
    n = ns(0.65)
    fc = env(n, [(0, 700), (0.12, 2200), (0.65, 1100)])
    hiss = mul(norm(svf(noise(n, rng), fc, 0.8, "bp")), smooth_rand(n, rng, 35, 0.55, 1.0))
    roar = mul(noise_lp(n, rng, 300), smooth_rand(n, rng, 20, 0.5, 1.0))
    x = mul(add((hiss, 0.8), (roar, 0.5)), env(n, [(0, 0), (0.06, 1), (0.4, 0.75), (0.65, 0)]))
    for _ in range(6):
        mix(x, grain(rng, rng.uniform(0.003, 0.006), rng.uniform(1500, 3000), 1.0),
            rng.uniform(0.03, 0.45), rng.uniform(0.1, 0.2))
    return tame(x, 5500)


@combat_sfx("bow")
def _bow(rng):              # bowstring "twang" + arrow "fwip"
    x = buf(0.45)
    n = ns(0.42)
    f = [0.0] * n
    for i in range(n):
        t = i / SR
        f[i] = 175 * (1 + 0.1 * exp(-t / 0.015)) * (1 + 0.03 * sin(TAU * 12 * t) * exp(-t / 0.15))
    twang = harmonic_tone(f, [(k, 1.0 / k, 0.12 / k ** 0.7) for k in range(1, 9)], attack=0.001)
    mix(x, fade_tail(twang, 0.15), 0.004, 0.9)
    mix(x, sweep_noise(rng, 0.09, [(0, 1200), (0.09, 3200)], 1.5,
                       [(0, 0), (0.01, 1), (0.09, 0)]), 0.0, 0.3)
    mix(x, nburst(rng, 0.01, 2500, 1.0, 0.002), 0.0, 0.25)
    return tame(x, 5000)


@combat_sfx("arrow_hit")
def _arrow_hit(rng):        # wooden "thunk" + the shaft wobbling "brrm"
    x = buf(0.4)
    mix(x, thump(0.18, 300, 140, 0.03, 0.008), 0.0, 0.8)
    mix(x, partials_tone(560, 0.15, [(1, 0.6, 0.03), (2.45, 0.3, 0.015), (4.1, 0.1, 0.008)],
                         attack=0.001), 0.0, 0.7)
    mix(x, nburst(rng, 0.02, 1400, 0.9, 0.004), 0.0, 0.5)
    n = ns(0.36)
    quiver = mul(partials_tone(380, 0.36, [(1, 1.0, 0.1), (2, 0.25, 0.05)]),
                 [0.5 + 0.5 * sin(TAU * 24 * i / SR) for i in range(n)])
    mix(x, fade_tail(quiver, 0.15), 0.008, 0.25)
    return tame(x, 4500)


# ---- melee
@combat_sfx("swing")
def _swing(rng):            # blade "vwip"
    n = ns(0.3)
    x = norm(svf(noise(n, rng), env(n, [(0, 500), (0.13, 2800), (0.3, 700)]), 2.3, "bp"))
    x = mul(x, env(n, [(0, 0), (0.11, 1), (0.17, 0.7), (0.3, 0)]))
    return tame(x, 6000)


@combat_sfx("clang")
def _clang(rng):            # sword on shield: bright inharmonic ring with a slow shimmer
    ring = partials_tone(880, 0.75, [(1, 1.0, 0.22), (1.48, 0.7, 0.16), (2.03, 0.5, 0.12),
                                     (2.71, 0.4, 0.08), (3.53, 0.25, 0.05), (4.6, 0.12, 0.035)],
                         attack=0.001)
    shimmer = partials_tone(884, 0.75, [(1, 0.5, 0.22), (1.48, 0.35, 0.16)], attack=0.001)
    x = fade_tail(add((ring, 1.0), (shimmer, 0.6)), 0.3)
    mix(x, snap_noise(rng, 0.03, 0.004, 1500, 6000), 0.0, 0.5)
    mix(x, thump(0.08, 500, 250, 0.02, 0.008), 0.0, 0.3)
    return tame(x, 6000)


@combat_sfx("slash")
def _slash(rng):            # quick "swish-tching"
    x = buf(0.36)
    mix(x, sweep_noise(rng, 0.11, [(0, 900), (0.11, 3600)], 2.0,
                       [(0, 0), (0.09, 1), (0.11, 0.3)]), 0.0, 0.6)
    mix(x, nburst(rng, 0.17, 3000, 2.0, 0.03), 0.1, 0.5)
    mix(x, partials_tone(2500, 0.25, [(1, 0.6, 0.05), (1.37, 0.4, 0.035)], attack=0.001), 0.1, 0.45)
    mix(x, thump(0.16, 220, 110, 0.03, 0.01), 0.1, 0.5)
    return tame(x, 6000)


@combat_sfx("punch")
def _punch(rng):            # cartoon "POW"
    x = buf(0.28)
    nt = ns(0.2)
    mix(x, fade_tail(thump(0.28, 240, 70, 0.05, 0.012), 0.08), 0.0, 1.0)
    mix(x, nburst(rng, 0.06, 1100, 0.7, 0.012), 0.0, 0.8)
    mix(x, mul(noise_lp(nt, rng, 600), decay(nt, 0.035, 0.002)), 0.0, 0.4)
    return tame(sat(x, 1.6), 4000)


@combat_sfx("bonk")
def _bonk(rng):             # hollow coconut "BONK" with a quick pitch drop
    n = ns(0.45)
    tone = harmonic_tone(fpath(n, [(0, 1000), (0.02, 640), (0.45, 600)]),
                         [(1, 1.0, 0.1), (2.7, 0.25, 0.025), (4.1, 0.08, 0.012)], attack=0.0008)
    x = fade_tail(add((tone, 1.0), (thump(0.25, 320, 130, 0.035, 0.01), 0.7)), 0.15)
    mix(x, nburst(rng, 0.02, 1800, 0.8, 0.004), 0.0, 0.4)
    return tame(x, 4500)


# ---- voices (cartoon blips, not speech)
@combat_sfx("oof1")
def _oof1(rng):             # "oof!"
    return grunt(rng, 0.24, [(0, 290), (0.04, 320), (0.24, 175)],
                 [(0, 600), (0.24, 380)], [(0, 1100), (0.24, 850)])


@combat_sfx("oof2")
def _oof2(rng):             # higher, startled "ow!"
    return grunt(rng, 0.28, [(0, 420), (0.05, 470), (0.28, 240)],
                 [(0, 800), (0.1, 750), (0.28, 400)], [(0, 1300), (0.28, 900)], wobble=0.04)


@combat_sfx("oof3")
def _oof3(rng):             # low two-part "uh-oof"
    x = buf(0.42)
    mix(x, grunt(rng, 0.08, [(0, 250), (0.08, 230)], [(0, 650), (0.08, 600)],
                 [(0, 1150), (0.08, 1100)], breath=0.0), 0.0, 0.6)
    mix(x, grunt(rng, 0.3, [(0, 260), (0.04, 285), (0.3, 150)], [(0, 550), (0.3, 360)],
                 [(0, 1000), (0.3, 800)], wobble=0.05), 0.11, 1.0)
    return x


@combat_sfx("ko")
def _ko(rng):               # dizzy "wheee-oooo" warble, circling birdie bells, little flop
    x = buf(1.05)
    n = ns(0.95)
    base = ramp(n, 1100, 260, "exp", 1.6)
    f = [b * (1 + 0.12 * sin(TAU * 9 * i / SR)) for i, b in enumerate(base)]
    warble = lowpass(osc(f, n, "tri"), 3000)
    mix(x, mul(warble, env(n, [(0, 0), (0.02, 1), (0.7, 0.8), (0.95, 0)])), 0.0, 0.7)
    for t, m in ((0.06, 91), (0.3, 88), (0.54, 91), (0.78, 88)):          # G6 E6 G6 E6
        mix(x, ping(midi(m), 0.07), t, 0.3)
    mix(x, thump(0.15, 180, 90, 0.028, 0.015), 0.9, 0.35)
    return tame(x, 6000)


@combat_sfx("charge")
def _charge(rng):           # bugle-ish "da-da-da-DAAA!" (G4 C5 E5 G5)
    x = buf(0.8)
    for t, m in ((0.0, 67), (0.1, 72), (0.2, 76)):
        mix(x, horn(midi(m), 0.09, attack=0.012, release=0.03, bright=3000, tilt=0.7), t, 0.8)
    mix(x, horn(midi(79), 0.48, attack=0.02, release=0.14, scoop=0.06, vib=0.02,
                vib_delay=0.12, bright=3200, tilt=0.7), 0.3, 1.0)
    x = add((x, 1.0), (vowel(x, [(1150, 2.0, 1.0)]), 0.5))       # kazoo-ish nasal edge
    return tame(x, 4500)


@combat_sfx("heal")
def _heal(rng):             # warm rising swell + climbing bells + sparkles
    x = buf(0.95)
    n = ns(0.75)
    swell = osc(ramp(n, 520, 1560, "exp", 0.8), n, "sine", 0.01, 6)
    mix(x, mul(swell, env(n, [(0, 0), (0.25, 1), (0.5, 0.6), (0.75, 0)])), 0.0, 0.25)
    for k, m in enumerate((72, 76, 79, 84, 88, 91)):              # C5 E5 G5 C6 E6 G6
        mix(x, fade_tail(bell(midi(m), 0.6, 0.22, 0.4), 0.2), 0.02 + 0.06 * k, 0.4)
    sparkles(x, rng, 0.2, 0.75, 9, 2400, 3600, 0.12, tau=0.04)
    return tame(echo(x, 0.08, 0.25, 0.3, 4000), 6500)


# ---- animals
@combat_sfx("roar")
def _roar(rng):             # big friendly T-rex: rising growl opening into "RAAWR", throat rasp
    n = ns(1.55)
    f = jitter(fpath(n, [(0, 70), (0.22, 125), (0.55, 140), (1.1, 110), (1.55, 62)]), rng, 0.04, 18)
    src = mul(buzz(f, 32, 0.9), subharm(f, 0.3))
    f1 = env(n, [(0, 350), (0.3, 680), (1.0, 560), (1.55, 360)])
    f2 = env(n, [(0, 950), (0.3, 1250), (1.0, 1100), (1.55, 800)])
    voice = vowel(src, [(f1, 2.5, 1.0), (f2, 4.0, 0.55), (2300, 5.0, 0.15)])
    chest = lowpass(lowpass(src, 260), 260)
    rasp = norm(svf(noise(n, rng), f1, 1.2, "bp"))
    rasp = mul(rasp, mul(smooth_rand(n, rng, 45, 0.2, 1.0), subharm(f, 0.4)))
    x = add((norm(voice), 1.0), (norm(chest), 0.55), (rasp, 0.3))
    x = mul(x, env(n, [(0, 0), (0.12, 0.6), (0.35, 1), (1.0, 0.85), (1.55, 0)]))
    return tame(sat(x, 1.5), 3500)


@combat_sfx("screech")
def _screech(rng):          # raptor / pterodactyl "skreee"
    n = ns(0.5)
    f = fpath(n, [(0, 650), (0.05, 1200), (0.28, 1100), (0.5, 720)])
    f = jitter(vibrato(f, 0.025, 15), rng, 0.03, 40)
    src = mul(buzz(f, 6, 1.1), smooth_rand(n, rng, 70, 0.6, 1.0))
    voice = vowel(src, [(1700, 2.5, 1.0), (2700, 3.0, 0.35)])
    rasp = mul(norm(svf(noise(n, rng), 2200, 2.0, "bp")), smooth_rand(n, rng, 60, 0.0, 1.0))
    x = add((norm(voice), 1.0), (norm(src), 0.3), (rasp, 0.2))
    x = mul(x, env(n, [(0, 0), (0.015, 1), (0.25, 0.85), (0.5, 0)]))
    return tame(x, 5000)


@combat_sfx("growl")
def _growl(rng):            # bear / wolf "grrrr"
    n = ns(0.85)
    f = jitter(fpath(n, [(0, 78), (0.3, 96), (0.85, 70)]), rng, 0.06, 12)
    src = mul(buzz(f, 40, 1.0), subharm(f, 0.35))
    rr = [0.6 + 0.4 * sin(TAU * 23 * i / SR) for i in range(n)]      # rolling "rrr"
    f1 = env(n, [(0, 320), (0.3, 520), (0.85, 300)])
    voice = vowel(src, [(f1, 2.5, 1.0), (900, 4.0, 0.4)])
    rasp = mul(norm(svf(noise(n, rng), f1, 1.4, "bp")), rr)
    x = add((norm(voice), 1.0), (norm(lowpass(src, 220)), 0.5), (rasp, 0.25))
    x = mul(mul(x, rr), env(n, [(0, 0), (0.15, 1), (0.6, 0.8), (0.85, 0)]))
    return tame(sat(x, 1.6), 2500)


@combat_sfx("bark")
def _bark(rng):             # friendly "woof!"
    n = ns(0.24)
    src = buzz(fpath(n, [(0, 330), (0.025, 560), (0.08, 500), (0.24, 300)]), 12, 0.9)
    f1 = fpath(n, [(0, 450), (0.04, 800), (0.24, 450)])
    f2 = fpath(n, [(0, 1000), (0.04, 1500), (0.24, 1000)])
    x = norm(vowel(src, [(f1, 3.0, 1.0), (f2, 4.0, 0.5)]))
    x = mul(x, env(n, [(0, 0), (0.006, 1), (0.07, 0.75), (0.24, 0)]))
    mix(x, nburst(rng, 0.1, 1500, 0.8, 0.02, 0.002), 0.0, 0.25)
    return tame(sat(x, 1.4), 4500)


@combat_sfx("moo")
def _moo(rng):              # "mmMOOOooo"
    n = ns(1.05)
    f = vibrato(fpath(n, [(0, 112), (0.2, 135), (0.7, 128), (1.05, 92)]), 0.015, 5.0, 0.3)
    src = buzz(f, 30, 1.0)
    mouth = svf(src, env(n, [(0, 300), (0.3, 1000), (0.75, 850), (1.05, 380)]), 1.2, "lp")
    x = add((norm(mouth), 1.0), (norm(vowel(src, [(700, 3.0, 1.0)])), 0.25))
    x = mul(x, env(n, [(0, 0), (0.12, 0.6), (0.35, 1), (0.8, 0.85), (1.05, 0)]))
    return tame(x, 3000)


@combat_sfx("cluck")
def _cluck(rng):            # "buk-buk-bKAWK"
    x = buf(0.42)
    for t, path, d, g in ((0.0, [(0, 700), (0.05, 540)], 0.05, 0.6),
                          (0.085, [(0, 680), (0.05, 520)], 0.05, 0.55),
                          (0.18, [(0, 640), (0.035, 980), (0.16, 700)], 0.16, 1.0)):
        n = ns(d)
        v = norm(vowel(buzz(fpath(n, path), 8, 1.0), [(1100, 3.0, 1.0), (2100, 4.0, 0.4)]))
        mix(x, mul(v, env(n, [(0, 0), (0.004, 1), (d * 0.5, 0.7), (d, 0)])), t, g)
        mix(x, grain(rng, 0.004, 2600, 1.2), t, 0.15 * g)                 # beak tick
    return tame(x, 5000)


@combat_sfx("trumpet")
def _trumpet(rng):          # elephant "PAWOOO"
    n = ns(1.0)
    f = fpath(n, [(0, 330), (0.07, 520), (0.25, 560), (0.7, 540), (1.0, 440)])
    f = jitter(vibrato(f, 0.02, 8.0, 0.2), rng, 0.015, 30)
    src = mul(buzz(f, 11, 0.7), smooth_rand(n, rng, 50, 0.8, 1.0))
    a = env(n, [(0, 0), (0.05, 1), (0.7, 0.9), (1.0, 0)])
    brass = svf(src, [500 + 2600 * v for v in a], 1.0, "lp")
    nasal = vowel(src, [(1300, 2.0, 1.0)])
    rasp = mul(norm(svf(noise(n, rng), 1500, 1.5, "bp")), smooth_rand(n, rng, 40, 0.2, 1.0))
    x = mul(add((norm(brass), 1.0), (norm(nasal), 0.35), (rasp, 0.08)), a)
    return tame(sat(x, 1.5), 4500)


@combat_sfx("stomp")
def _stomp(rng):            # giant footstep: deep BOOM, a little dirt and a few pebbles
    x = buf(0.65)
    n = len(x)
    mix(x, thump(0.65, 115, 48, 0.13, 0.035), 0.0, 1.0)
    mix(x, mul(noise_lp(n, rng, 400), decay(n, 0.07, 0.004)), 0.0, 0.6)
    mix(x, nburst(rng, 0.1, 550, 0.8, 0.018), 0.0, 0.5)
    x = sat(x, 2.0)
    for _ in range(7):
        mix(x, grain(rng, rng.uniform(0.006, 0.015), rng.uniform(400, 1200), 1.2),
            rng.uniform(0.05, 0.35), rng.uniform(0.04, 0.1))
    return tame(x, 2200)


# ---- big booms and hazards
@combat_sfx("nuke")
def _nuke(rng):             # the biggest cartoon KA-BOOM: flash, shockwave whoosh, long rumble
    n = ns(3.9)
    x = thump(3.9, 85, 38, 0.7, 0.14)
    mix(x, thump(2.0, 70, 40, 0.4, 0.1), 0.09, 0.5)
    fc = ramp(n, 1300, 100, "exp", 0.5)
    mix(x, mul(norm(lowpass(lowpass(noise(n, rng), fc), fc)), decay(n, 0.7, 0.006)), 0.0, 0.8)
    mix(x, nburst(rng, 0.3, 900, 0.7, 0.05, 0.002), 0.0, 0.35)
    nw = ns(1.6)
    shock = norm(svf(noise(nw, rng), env(nw, [(0, 250), (0.45, 1500), (1.6, 350)]), 1.0, "bp"))
    mix(x, mul(shock, env(nw, [(0, 0), (0.4, 1), (0.6, 0.8), (1.6, 0)])), 0.15, 0.4)
    rumble = mul(noise_lp(n, rng, 110, 3), smooth_rand(n, rng, 5, 0.35, 1.0))
    mix(x, mul(rumble, env(n, [(0, 0), (0.3, 1), (1.6, 0.8), (3.9, 0)])), 0.0, 0.5)
    for _ in range(30):                                            # falling debris patter
        mix(x, grain(rng, rng.uniform(0.008, 0.02), rng.uniform(300, 1200), 1.5),
            rng.uniform(0.6, 2.6), rng.uniform(0.03, 0.08))
    return tame(sat(x, 1.7), 2600)


@combat_sfx("whistle")
def _whistle(rng):          # falling bomb "pheeeeooooo"
    n = ns(1.25)
    f = vibrato(ramp(n, 1750, 600, "exp", 1.3), 0.006, 7.0)
    x = add((osc(f, n, "sine"), 0.7), (norm(svf(noise(n, rng), f, 8.0, "bp")), 0.3))
    x = mul(x, env(n, [(0, 0), (0.15, 0.5), (1.0, 0.9), (1.18, 1.0), (1.25, 0)]))
    return tame(x, 5000)


@combat_sfx("plane")
def _plane(rng):            # propeller plane zooming past, pitch dropping as it passes
    n = ns(2.5)
    tc = 1.25
    t = [i / SR for i in range(n)]
    dop = [1.0 - 0.1 * math.tanh((s - tc) / 0.3) for s in t]
    near = [1.0 / (1.0 + ((s - tc) / 0.5) ** 2) for s in t]
    f0 = [92.0 * d for d in dop]
    eng = mul(buzz(f0, 40, 0.9), subharm([v * 0.5 for v in f0], 0.25))     # engine putter
    air = norm(svf(noise(n, rng), [700.0 * d for d in dop], 0.8, "bp"))
    x = lowpass(add((norm(eng), 0.8), (air, 0.3)), [500.0 + 3000.0 * v for v in near])
    x = mul(mul(x, near), env(n, [(0, 0), (0.3, 1), (2.2, 1), (2.5, 0)]))
    return tame(x, 5000)


@combat_sfx("alarm")
def _alarm(rng):            # air-raid style warning: two short rising-falling (toy) wails
    n = ns(1.5)
    f = fpath(n, [(0, 340), (0.33, 780), (0.48, 770), (0.75, 470), (1.08, 780),
                  (1.23, 770), (1.5, 400)])
    x = add((osc(f, n, "soft"), 0.7), (osc([v * 2.0 for v in f], n, "sine"), 0.2))
    x = lowpass(lowpass(x, 3000), 3000)
    x = mul(x, env(n, [(0, 0), (0.2, 0.9), (0.48, 1), (0.75, 0.6), (0.95, 0.9), (1.23, 1),
                       (1.5, 0)]))
    return tame(x, 4500)


@combat_sfx("sizzle")
def _sizzle(rng):           # lava burn "TSSSS" with crackles and slow lava blorps
    n = ns(0.85)
    hiss = mul(norm(lowpass(highpass(noise(n, rng), 2500), 6000)), smooth_rand(n, rng, 45, 0.4, 1.0))
    x = mul(hiss, env(n, [(0, 0), (0.015, 0.5), (0.25, 0.35), (0.85, 0)]))
    mix(x, nburst(rng, 0.18, 3000, 0.8, 0.03), 0.0, 0.4)
    for _ in range(22):
        mix(x, grain(rng, rng.uniform(0.002, 0.005), rng.uniform(2500, 5000), 1.2),
            rng.uniform(0.01, 0.6), rng.uniform(0.3, 0.8))
    for _ in range(4):
        nb = ns(0.15)
        f = rng.uniform(170, 260)
        blorp = harmonic_tone(fpath(nb, [(0, f), (0.05, f * 2.0), (0.15, f * 2.15)]), [(1, 1.0, 0.03)])
        mix(x, blorp, rng.uniform(0.05, 0.6), rng.uniform(0.25, 0.4))
    return tame(x, 6000)


@combat_sfx("fizz")
def _fizz(rng):             # acid dissolving: dense fizz, popping bubbles, a sinking gloop
    x = buf(0.95)
    n = len(x)
    bed = mul(norm(svf(noise(n, rng), 4000, 1.0, "bp")),
              env(n, [(0, 0), (0.03, 1), (0.4, 0.6), (0.95, 0)]))
    mix(x, bed, 0.0, 0.12)
    for _ in range(150):
        r = rng.random()
        mix(x, grain(rng, rng.uniform(0.002, 0.004), rng.uniform(2500, 5000), 2.0),
            0.01 + 0.85 * r ** 1.5, 0.3 * (1.0 - 0.7 * r) * rng.uniform(0.4, 1.0))
    for _ in range(10):
        f = rng.uniform(450, 1100)
        nb = ns(0.08)
        b = harmonic_tone(fpath(nb, [(0, f), (0.025, f * 1.8), (0.08, f * 1.9)]), [(1, 1.0, 0.015)],
                          attack=0.001)
        mix(x, b, rng.uniform(0.03, 0.75), rng.uniform(0.15, 0.35))
    ng = ns(0.6)
    gf = [v * (1 + 0.1 * sin(TAU * 18 * i / SR)) for i, v in enumerate(ramp(ng, 300, 120, "exp"))]
    gloop = mul(harmonic_tone(gf, [(1, 1.0, 0), (2, 0.3, 0)]), env(ng, [(0, 0), (0.08, 1), (0.6, 0)]))
    mix(x, gloop, 0.05, 0.25)
    return tame(x, 6000)


@combat_sfx("crumble")
def _crumble(rng):          # stone / wood structure breaking apart
    x = buf(1.0)
    n = len(x)
    mix(x, thump(0.45, 150, 55, 0.08, 0.025), 0.0, 0.8)
    mix(x, snap_noise(rng, 0.05, 0.01, 600, 4000), 0.0, 0.5)
    mix(x, mul(noise_lp(n, rng, 250), env(n, [(0, 0), (0.02, 1), (0.3, 0.5), (1.0, 0)])), 0.0, 0.4)
    for _ in range(45):
        r = rng.random()
        t = 0.02 + 0.75 * r ** 1.4
        a = rng.uniform(0.25, 0.6) * (1.0 - 0.5 * r)
        if rng.random() < 0.6:                                     # stone chunks
            mix(x, grain(rng, rng.uniform(0.01, 0.03), rng.uniform(300, 1600), 1.2), t, a)
        else:                                                      # wooden knocks
            f = rng.uniform(250, 650)
            tau = rng.uniform(0.02, 0.04)
            mix(x, partials_tone(f, tau * 5, [(1, 1.0, tau), (2.3, 0.3, tau * 0.5)], attack=0.001),
                t, a * 0.8)
    return tame(sat(x, 1.3), 4500)


@combat_sfx("metal_hit")
def _metal_hit(rng):        # hollow crate / barrel "BWONG"
    ring = partials_tone(240, 0.7, [(1, 1.0, 0.22), (1.59, 0.6, 0.16), (2.14, 0.45, 0.12),
                                    (2.92, 0.3, 0.08), (3.67, 0.2, 0.05), (5.1, 0.1, 0.03)],
                         attack=0.001)
    beat = partials_tone(241.7, 0.7, [(1, 0.5, 0.2)], attack=0.001)
    x = fade_tail(add((ring, 1.0), (beat, 1.0), (thump(0.25, 200, 110, 0.05, 0.015), 0.6)), 0.25)
    mix(x, nburst(rng, 0.03, 1500, 0.8, 0.005), 0.0, 0.4)
    return tame(x, 5000)


# ---- misc
@combat_sfx("reload")
def _reload(rng):           # "click ... shhk-CLACK"
    x = buf(0.5)
    mix(x, nburst(rng, 0.015, 2300, 1.4, 0.003), 0.0, 0.6)
    mix(x, partials_tone(900, 0.04, [(1, 0.5, 0.008), (2.3, 0.2, 0.004)], attack=0.0005), 0.0, 1.0)
    mix(x, sweep_noise(rng, 0.08, [(0, 1200), (0.08, 2600)], 1.5,
                       [(0, 0), (0.06, 1), (0.08, 0)]), 0.2, 0.3)
    mix(x, nburst(rng, 0.02, 1800, 1.2, 0.004), 0.28, 0.9)
    mix(x, partials_tone(650, 0.06, [(1, 0.6, 0.012), (2.2, 0.25, 0.006)], attack=0.0005), 0.28, 1.0)
    mix(x, thump(0.06, 400, 200, 0.012, 0.006), 0.28, 0.4)
    return tame(x, 6000)


@combat_sfx("pin")
def _pin(rng):              # grenade pin pulled: tiny click + bright "ping!"
    x = buf(0.4)
    mix(x, nburst(rng, 0.012, 3000, 1.5, 0.002), 0.0, 0.4)
    mix(x, sweep_noise(rng, 0.04, [(0, 2000), (0.04, 3800)], 2.0,
                       [(0, 0), (0.01, 1), (0.04, 0)]), 0.01, 0.2)
    nb = ns(0.35)
    ring = harmonic_tone(fpath(nb, [(0, 2050), (0.02, 2350), (0.35, 2380)]),
                         [(1, 1.0, 0.07), (1.52, 0.25, 0.035)], attack=0.001)
    mix(x, ring, 0.03, 0.8)
    return tame(x, 6000)


@combat_sfx("victory")
def _victory(rng):          # brassy "da-da-da-DAA-da-DAAAA!" (C C C E D G) over a C chord
    x = buf(1.9)
    for t, m, d in ((0.0, 72, 0.12), (0.13, 72, 0.12), (0.26, 72, 0.12), (0.39, 76, 0.3),
                    (0.72, 74, 0.12)):
        mix(x, horn(midi(m), d, attack=0.015, release=0.04), t, 0.7)
    for m, g in ((79, 0.75), (76, 0.4), (72, 0.4)):               # final chord, G5 on top
        mix(x, horn(midi(m), 0.95, attack=0.03, release=0.3, scoop=0.03 if m == 79 else 0.0,
                    vib=0.015, vib_delay=0.25), 0.85, g)
    mix(x, drum(rng, 0.5, 130, 60, 0.12), 0.0, 0.5)
    mix(x, drum(rng, 0.7, 120, 55, 0.18), 0.85, 0.6)
    nc = ns(0.8)
    cym = mul(norm(svf(noise(nc, rng), 4500, 0.8, "bp")), decay(nc, 0.2, 0.004))   # soft cymbal wash
    mix(x, cym, 0.85, 0.08)
    sparkles(x, rng, 0.9, 1.6, 8, 2400, 3600, 0.1, tau=0.05)
    return tame(x, 6500)


@combat_sfx("battle_start")
def _battle_start(rng):     # "BOOM-boom" war drum, then a heroic horn call "doo-DAAAA"
    x = buf(1.85)
    mix(x, drum(rng, 0.8, 115, 48, 0.22), 0.0, 1.0)
    mix(x, drum(rng, 0.6, 125, 55, 0.15), 0.17, 0.6)
    mix(x, horn(midi(60), 0.22, attack=0.02, release=0.05, bright=2200), 0.34, 0.75)       # C4
    for m, g in ((67, 0.8), (60, 0.4)):                                                  # G4 over C4
        mix(x, horn(midi(m), 1.1, attack=0.04, release=0.35, scoop=0.05 if m == 67 else 0.0,
                    vib=0.018, vib_delay=0.35, bright=2400), 0.58, g)
    mix(x, drum(rng, 0.6, 120, 50, 0.18), 0.58, 0.55)
    return tame(x, 6000)


@combat_sfx("defeat")
def _defeat(rng):           # gentle "aww" trombone: "wah, wah, wah, waaah" (D4 C#4 C4 B3), soft and round
    x = buf(2.3)
    notes = ((0.0, 62, 0.36), (0.38, 61, 0.36), (0.76, 60, 0.36), (1.14, 59, 1.05))
    for t, m, d in notes:
        n = ns(d)
        f0 = midi(m)
        last = m == 59
        # each note leans in from a touch sharp; the last one sags and wobbles ("waaah")
        fr = fpath(n, [(0, f0 * 1.025), (0.06, f0), (d, f0 * (0.965 if last else 0.995))])
        if last:
            fr = vibrato(fr, 0.03, 4.8, 0.25)
        src = buzz(fr, 12, 1.1)
        # the "wah": the mouth opens from "oo" to "aww" on every note
        f1 = env(n, [(0, 360), (0.13, 700), (d, 560 if last else 640)])
        f2 = env(n, [(0, 780), (0.13, 1080), (d, 920 if last else 1000)])
        v = add((vowel(src, [(f1, 3.0, 1.0), (f2, 4.5, 0.45)]), 1.0), (lowpass(src, 500), 0.25))
        rel = 0.45 if last else 0.08
        a = env(n, [(0, 0), (0.035, 1), (max(0.04, d - rel), 0.75 if last else 0.85), (d, 0)])
        mix(x, mul(norm(v), a), t, 0.9 if last else 0.75)
    mix(x, ping(midi(83), 0.09), 1.95, 0.12)          # a tiny "plink" to keep it cute
    return tame(lowpass(x, 2600), 3800)


# ---- 3D: parachutes, ejecting, wood
@combat_sfx("chute_open")
def _chute_open(rng):       # a parachute catching the air: a soft cloth "fwump" with a flutter
    x = buf(0.55)
    n = ns(0.5)
    cloth = norm(svf(noise(n, rng), env(n, [(0, 280), (0.06, 900), (0.5, 380)]), 1.1, "bp"))
    flutter = [0.6 + 0.4 * sin(TAU * env_f * i / SR) for i, env_f in enumerate(ramp(n, 32, 14))]
    cloth = mul(mul(cloth, flutter), env(n, [(0, 0), (0.035, 1), (0.12, 0.55), (0.5, 0)]))
    mix(x, cloth, 0.0, 0.8)
    mix(x, thump(0.3, 150, 70, 0.07, 0.03, attack=0.012), 0.02, 0.7)          # the "wump" as it fills
    return tame(x, 4500)


@combat_sfx("eject")
def _eject(rng):            # cartoony ejector seat: a cork "POP!" and a little rising "fweee"
    x = buf(0.55)
    mix(x, thump(0.12, 700, 220, 0.03, 0.01), 0.0, 0.9)
    mix(x, nburst(rng, 0.05, 1500, 0.9, 0.01), 0.0, 0.5)
    mix(x, chirp(0.32, 520, 1500, "cute", 0.0, attack=0.01, release=0.12, power=0.7), 0.05, 0.4)
    n = ns(0.4)
    hiss = mul(norm(svf(noise(n, rng), ramp(n, 900, 2600, "exp"), 1.2, "bp")), env(n, [(0, 0), (0.03, 1), (0.4, 0)]))
    mix(x, hiss, 0.03, 0.25)
    return tame(x, 6000)


@combat_sfx("wood_crunch")
def _wood_crunch(rng):      # a tank rolling over a crate, a fence or a tree: splintery "CRRUNCH"
    x = buf(0.6)
    mix(x, thump(0.25, 200, 80, 0.05, 0.02), 0.0, 0.7)
    for _ in range(18):          # splinters: short dry cracks, thickest at the start
        r = rng.random()
        t = 0.24 * r ** 1.6
        mix(x, nburst(rng, 0.03, rng.uniform(900, 2600), 1.3, rng.uniform(0.004, 0.01)), t,
            rng.uniform(0.3, 0.7) * (1.0 - 0.5 * r))
    for _ in range(6):           # hollow wooden knocks
        f = rng.uniform(220, 480)
        tau = rng.uniform(0.02, 0.035)
        mix(x, partials_tone(f, tau * 5, [(1, 1.0, tau), (2.4, 0.35, tau * 0.5)], attack=0.001),
            rng.uniform(0.0, 0.3), rng.uniform(0.3, 0.55))
    return tame(sat(x, 1.4), 4500)


@combat_sfx("crackle")
def _crackle(rng):          # dry wood catching fire: a soft whoosh and a few crackles (one go, no loop)
    x = buf(0.75)
    n = ns(0.7)
    bed = mul(noise_lp(n, rng, 500), env(n, [(0, 0), (0.12, 1), (0.4, 0.6), (0.7, 0)]))
    mix(x, bed, 0.0, 0.35)
    for _ in range(14):
        t = rng.uniform(0.02, 0.62)
        mix(x, grain(rng, rng.uniform(0.004, 0.012), rng.uniform(1500, 3800), 1.5), t, rng.uniform(0.35, 0.9))
    for _ in range(3):           # a couple of fatter pops
        mix(x, nburst(rng, 0.03, rng.uniform(600, 1100), 1.0, 0.008), rng.uniform(0.05, 0.55), 0.6)
    return tame(x, 5500)


@combat_sfx("chop")
def _chop(rng):             # an axe biting into a wooden post: a hollow "THOCK"
    x = buf(0.3)
    mix(x, partials_tone(310, 0.25, [(1, 1.0, 0.045), (2.37, 0.45, 0.02), (3.9, 0.2, 0.01)], attack=0.0008),
        0.0, 0.8)
    mix(x, thump(0.18, 260, 120, 0.04, 0.012), 0.0, 0.6)
    mix(x, nburst(rng, 0.02, 2200, 1.0, 0.003), 0.0, 0.35)                     # the blade's bite
    return tame(x, 5000)


@combat_sfx("land_puff")
def _land_puff(rng):        # landing softly under a parachute: a gentle thud and a puff of dust
    x = buf(0.5)
    mix(x, thump(0.25, 130, 60, 0.06, 0.02, attack=0.004), 0.0, 0.7)
    n = ns(0.4)
    dust = mul(norm(svf(noise(n, rng), ramp(n, 1100, 450, "exp"), 0.9, "bp")), env(n, [(0, 0), (0.02, 1), (0.4, 0)]))
    mix(x, dust, 0.0, 0.45)
    nf = ns(0.3)
    flop = mul(norm(svf(noise(nf, rng), 500, 1.2, "bp")), env(nf, [(0, 0), (0.08, 1), (0.3, 0)]))
    mix(x, flop, 0.12, 0.3)                                                   # the canopy settling
    return tame(x, 4000)


# ---- 2D: toys and creatures against fighters
@combat_sfx("laser_ping")
def _laser_ping(rng):       # a laser sword bats a bullet away: "pew-PING!"
    x = buf(0.5)
    mix(x, chirp(0.06, 2200, 900, "tri", attack=0.002, release=0.02), 0.0, 0.45)
    mix(x, partials_tone(2350, 0.45, [(1, 1.0, 0.11), (1.51, 0.3, 0.06), (2.1, 0.12, 0.03)], attack=0.001),
        0.03, 0.75)
    mix(x, harmonic_tone(vibrato([1175.0] * ns(0.4), 0.02, 18), [(1, 0.4, 0.12)], attack=0.002), 0.03, 0.4)
    return tame(x, 6000)


@combat_sfx("ice_crunch")
def _ice_crunch(rng):       # a frozen fighter's ice block smashed: "KRSSH" with tinkling bits
    x = buf(0.8)
    mix(x, thump(0.2, 240, 90, 0.04, 0.015), 0.0, 0.6)
    for _ in range(22):          # the crunch: dense bright cracks
        r = rng.random()
        mix(x, nburst(rng, 0.025, rng.uniform(1800, 4200), 1.6, rng.uniform(0.003, 0.008)),
            0.12 * r ** 1.5, rng.uniform(0.3, 0.8))
    for _ in range(14):          # the bits tinkling down
        r = rng.random()
        f = rng.uniform(2000, 3800)
        tau = rng.uniform(0.03, 0.07)
        mix(x, partials_tone(f, tau * 5, [(1, 1.0, tau)], attack=0.001), 0.05 + 0.6 * r ** 1.3,
            rng.uniform(0.15, 0.35) * (1.0 - 0.5 * r))
    return tame(x, 6000)


@combat_sfx("plat_crash")
def _plat_crash(rng):       # a built platform blown to bits: "CRASH!" and the pieces clattering down
    x = buf(1.0)
    mix(x, thump(0.4, 170, 55, 0.08, 0.025), 0.0, 0.8)
    mix(x, snap_noise(rng, 0.06, 0.012, 600, 4200), 0.0, 0.6)
    n = ns(0.6)
    mix(x, mul(noise_lp(n, rng, 700), env(n, [(0, 0), (0.01, 1), (0.25, 0.4), (0.6, 0)])), 0.0, 0.4)
    for _ in range(16):          # the pieces landing: wood and stone knocks, spreading out
        r = rng.random()
        t = 0.12 + 0.75 * r ** 1.2
        f = rng.uniform(260, 900)
        tau = rng.uniform(0.015, 0.035)
        mix(x, partials_tone(f, tau * 5, [(1, 1.0, tau), (2.6, 0.3, tau * 0.5)], attack=0.001), t,
            rng.uniform(0.25, 0.5) * (1.0 - 0.6 * r))
    return tame(sat(x, 1.3), 4500)


@combat_sfx("zap_buzz")
def _zap_buzz(rng):         # electricity running through water or metal: a buzzing "BZZZT!"
    n = ns(0.55)
    f = jitter(fpath(n, [(0, 120), (0.5, 110)]), rng, 0.03, 30)
    hum = buzz(f, 30, 0.9, top=5000.0)
    hum = mul(hum, [0.55 + 0.45 * sin(TAU * 32 * i / SR) for i in range(n)])     # the "zzz" flutter
    hum = mul(hum, smooth_rand(n, rng, 90, 0.5, 1.0))
    crack = [0.0] * n
    for _ in range(12):
        mix(crack, nburst(rng, 0.012, rng.uniform(2500, 4500), 1.5, 0.002), rng.randrange(n), rng.uniform(0.4, 1.0),
            samples=True)
    x = add((norm(svf(hum, 1600, 0.8, "bp")), 0.7), (norm(lowpass(hum, 900)), 0.4), (crack, 0.35))
    return tame(mul(x, env(n, [(0, 0), (0.01, 1), (0.4, 0.8), (0.55, 0)])), 5500)


@combat_sfx("swoop")
def _swoop(rng):            # a pterodactyl diving down to grab someone: "fwoosh" and a "kree!"
    x = buf(0.8)
    n = ns(0.75)
    fc = env(n, [(0, 350), (0.3, 1500), (0.75, 450)])
    wind = mul(norm(svf(noise(n, rng), fc, 1.4, "bp")), env(n, [(0, 0), (0.28, 1), (0.75, 0)]))
    mix(x, wind, 0.0, 0.6)
    m = ns(0.3)
    f = jitter(vibrato(fpath(m, [(0, 1100), (0.06, 1700), (0.3, 1350)]), 0.02, 14), rng, 0.02, 30)
    kree = mul(vowel(buzz(f, 5, 1.2), [(1800, 2.5, 1.0), (2900, 3.0, 0.3)]), env(m, [(0, 0), (0.02, 1), (0.2, 0.8), (0.3, 0)]))
    mix(x, norm(kree), 0.25, 0.55)
    return tame(x, 5000)


@combat_sfx("grumble")
def _grumble(rng):          # a gentle giant (a Brachiosaurus) losing its temper: a low, rumbly "hrrMMPH"
    n = ns(0.9)
    f = jitter(fpath(n, [(0, 62), (0.25, 80), (0.6, 74), (0.9, 58)]), rng, 0.05, 14)
    src = mul(buzz(f, 36, 1.0, top=3000.0), subharm(f, 0.3))
    f1 = env(n, [(0, 280), (0.3, 480), (0.65, 330), (0.9, 250)])                     # "hrr" opening to "MM"
    voice = vowel(src, [(f1, 2.5, 1.0), (850, 4.0, 0.35)])
    chest = lowpass(lowpass(src, 220), 220)
    x = add((norm(voice), 1.0), (norm(chest), 0.6))
    x = mul(x, env(n, [(0, 0), (0.08, 0.7), (0.3, 1), (0.7, 0.75), (0.9, 0)]))
    return tame(sat(x, 1.1), 3000)


@combat_sfx("thwack")
def _thwack(rng):           # the beat of stillness after a big hit: a short, punchy "THWACK!"
    x = buf(0.28)
    mix(x, thump(0.2, 220, 85, 0.045, 0.012), 0.0, 0.6)
    mix(x, nburst(rng, 0.04, 1500, 0.9, 0.008), 0.0, 1.0)
    mix(x, snap_noise(rng, 0.02, 0.004, 1200, 5000), 0.0, 0.6)
    return tame(sat(x, 1.5), 5500)


# ================================================================== music
BPM = 108                       # 60/108 s per beat = exactly 12250 samples
BEAT = SR * 60.0 / BPM
BAR = int(round(BEAT * 4))      # 49000 samples
BARS = 16                       # loop = 784000 samples = 35.56 s

NOTE = {"G4": 67, "A4": 69, "B4": 71, "C5": 72, "D5": 74, "E5": 76, "F5": 77,
        "G5": 79, "A5": 81, "B5": 83, "C6": 84}

CHORDS = ["C", "Am", "F", "G", "C", "Am", "F", "G",
          "F", "G", "Em", "Am", "F", "G", "C", "G7"]
ARP_TONES = {"C": (60, 64, 67, 72), "Am": (57, 60, 64, 69), "F": (53, 57, 60, 65),
             "G": (55, 59, 62, 67), "Em": (52, 55, 59, 64), "G7": (55, 59, 62, 65)}
BASS_ROOT = {"C": 48, "Am": 45, "F": 41, "G": 43, "Em": 40, "G7": 43}

# (beat, note) per bar; marimba lead in C major
MELODY = [
    [(0, "E5"), (0.5, "G5"), (1, "A5"), (1.5, "G5"), (2, "E5"), (3, "C5"), (3.5, "D5")],
    [(0, "E5"), (0.5, "C5"), (1, "A4"), (2, "C5"), (2.5, "E5"), (3, "A5")],
    [(0, "A5"), (0.5, "G5"), (1, "F5"), (1.5, "A5"), (2, "G5"), (3, "F5"), (3.5, "E5")],
    [(0, "D5"), (1, "G4"), (1.5, "B4"), (2, "D5")],
    [(0, "E5"), (0.5, "G5"), (1, "A5"), (1.5, "G5"), (2, "E5"), (2.5, "G5"), (3, "C6")],
    [(0, "B5"), (0.5, "A5"), (1, "E5"), (2, "A5"), (2.5, "G5"), (3, "E5")],
    [(0, "F5"), (0.5, "A5"), (1, "C6"), (1.5, "A5"), (2, "F5"), (2.5, "G5"), (3, "A5")],
    [(0, "G5"), (1.5, "F5"), (2, "D5"), (2.5, "B4"), (3, "D5")],
    [(0, "C5"), (1, "F5"), (2, "A5"), (3.5, "G5")],
    [(0, "G5"), (0.5, "F5"), (1, "D5"), (2, "B4"), (2.5, "D5"), (3, "G5")],
    [(0, "E5"), (1, "G5"), (2, "B5"), (3.5, "A5")],
    [(0, "A5"), (0.5, "G5"), (1, "E5"), (1.5, "C5"), (2, "A4"), (3, "C5"), (3.5, "D5")],
    [(0, "F5"), (0.5, "A5"), (1, "C6"), (2, "A5"), (2.5, "F5"), (3, "A5")],
    [(0, "G5"), (0.5, "B5"), (1, "G5"), (2, "F5"), (2.5, "D5"), (3, "B4")],
    [(0, "C5"), (0.5, "E5"), (1, "G5"), (1.5, "C6"), (2, "G5"), (2.5, "E5"), (3, "C5")],
    [(0, "D5"), (0.5, "F5"), (1, "G5"), (2, "F5"), (2.5, "D5"), (3, "B4"), (3.5, "D5")],
]


def render_music():
    rng = random.Random(SEED * 7 + 11)
    L = BAR * BARS
    total = L + ns(6.0)                       # extra room for ringing tails, wrapped later
    mel, arp, bass, kick, perc, glk = ([0.0] * total for _ in range(6))
    cache = {}

    def note(kind, key, make):
        if (kind, key) not in cache:
            cache[(kind, key)] = make()
        return cache[(kind, key)]

    def mallet(m):
        f = midi(m)
        tau = 0.34 * (523.0 / f) ** 0.3
        x = partials_tone(f, 1.3, [(1, 1.0, tau), (3.93, 0.2, 0.04), (2, 0.06, tau * 0.3)])
        click = mul(lowpass(noise(ns(0.01), random.Random(m)), 2500), decay(ns(0.01), 0.002, 0.0005))
        mix(x, click, 0, 0.08)
        return fade_tail(x, 0.05)

    def pluck(m):
        x = partials_tone(midi(m), 0.75, [(1, 1.0, 0.3), (2, 0.4, 0.12), (3, 0.15, 0.06), (4, 0.05, 0.03)],
                          attack=0.004)
        return fade_tail(x, 0.04)

    def bassnote(m, beats):
        dur = beats * BEAT / SR
        n = ns(dur)
        x = partials_tone(midi(m), dur, [(1, 1.0, 0), (2, 0.3, 0.25), (3, 0.1, 0.12)], attack=0.008)
        return mul(x, env(n, [(0, 1), (0.12, 0.8), (max(0.13, dur - 0.06), 0.65), (dur, 0)]))

    def glock(m):
        return fade_tail(partials_tone(midi(m), 1.0, [(1, 1.0, 0.35), (3, 0.06, 0.04)], attack=0.0015), 0.05)

    kick_s = thump(0.3, 140, 50, 0.11, 0.025, attack=0.003)
    tok_s = add((partials_tone(780, 0.12, [(1, 1.0, 0.025), (1.58, 0.4, 0.015)], attack=0.001), 1.0),
                (mul(norm(svf(noise(ns(0.02), rng), 1800, 1.0, "bp")), decay(ns(0.02), 0.004, 0.0008)), 0.2))
    shk_n = ns(0.08)
    shk_s = mul(norm(svf(noise(shk_n, rng), 4200, 0.9, "bp")), decay(shk_n, 0.02, 0.004))

    def pos(bar, beat):
        return int(round(bar * BAR + beat * BEAT))

    for bar in range(BARS):
        chord = CHORDS[bar]
        bsec = 8 <= bar < 12                 # calmer middle section
        # --- lead marimba (+ glockenspiel sparkle on the on-beat notes in bars 5-8 / 13-16)
        for b, nm in MELODY[bar]:
            m = NOTE[nm]
            vel = rng.uniform(0.82, 0.95) + (0.06 if b == int(b) else 0.0)
            i = pos(bar, b) + rng.randint(-60, 60)
            mix(mel, note("mal", m, lambda m=m: mallet(m)), max(0, i), vel, samples=True)
            if bar in (4, 5, 6, 7, 12, 13, 14, 15) and b == int(b):
                mix(glk, note("glk", m + 12, lambda m=m: glock(m + 12)), max(0, i), vel, samples=True)
        # --- plucked arpeggio
        tones = ARP_TONES[chord]
        steps = ([(k, (0, 2, 3, 2)[k]) for k in range(4)] if bsec
                 else [(k * 0.5, (0, 1, 2, 1, 3, 2, 1, 2)[k]) for k in range(8)])
        for b, idx in steps:
            m = tones[idx]
            vel = (0.9 if b == int(b) else 0.7) * rng.uniform(0.9, 1.0)
            mix(arp, note("plk", m, lambda m=m: pluck(m)), pos(bar, b), vel, samples=True)
        # --- bass
        r = BASS_ROOT[chord]
        if bsec:
            line = [(0, r, 1.8), (2, r + 7, 1.8)]
        elif bar == BARS - 1:
            line = [(0, r, 0.9), (1.5, r, 0.4), (2, r + 2, 0.9), (3, r + 4, 0.9)]   # walk G-A-B -> C
        else:
            line = [(0, r, 0.9), (1.5, r, 0.4), (2, r + 7, 0.9), (3, r + 12, 0.4), (3.5, r + 7, 0.4)]
        for b, m, beats in line:
            mix(bass, note("bass", (m, beats), lambda m=m, beats=beats: bassnote(m, beats)),
                pos(bar, b), 1.0 if b in (0, 2) else 0.8, samples=True)
        # --- gentle percussion
        for b in ((0,) if bsec else (0, 2)):
            mix(kick, kick_s, pos(bar, b), 1.0, samples=True)
        toks = (1, 3, 3.5) if bar == BARS - 1 else (1, 3)
        for b in toks:
            mix(perc, tok_s, pos(bar, b), 0.7 if b == 3.5 else 1.0, samples=True)
        for k in range(8):
            mix(perc, shk_s, pos(bar, k * 0.5), (0.35 if k % 2 == 0 else 0.55) * 0.35, samples=True)

    send = add((mel, 1.0), (arp, 0.4), (glk, 0.6))
    wet = echo(send, 3 * BEAT / SR, 0.28, 1.0, 2500)            # dotted-quarter echo
    wet = [w - s for w, s in zip(wet, send)]                     # echo returns only
    master = add((mel, 0.55), (arp, 0.24), (bass, 0.5), (kick, 0.42), (perc, 0.16),
                 (glk, 0.1), (wet, 0.2))
    master = lowpass(highpass(master, 30.0), 7000)
    # wrap everything past the loop end back onto the start -> seamless loop
    out = master[:L]
    for i in range(L, total):
        out[i - L] += master[i]
    return norm(out, MUSIC_PEAK)


# ------------------------------------------------------- more music loops
# One loop per mood (autoload/sfx.gd MOODS): wiggle_loop above on the title
# menu, calm_loop in the 2D sandbox, ready_loop while a 3D battle is set up
# (and between 🌊 waves), battle_loop while it's fought. Each is a whole
# number of bars, and every ringing tail past the end is wrapped back onto
# the start, so it loops with no click. Each has its own seed, so changing
# one never changes another.

def _wrap(master, L):
    """Folds everything past sample L back onto the start: a seamless loop."""
    out = master[:L]
    for i in range(L, len(master)):
        out[(i - L) % L] += master[i]
    return out


def _level(x, rms, peak=MUSIC_PEAK):
    """Scales a loop to loudness `rms`. The few drum hits that would then go
    past 60% of `peak` are rounded off smoothly so they never reach it. That
    goes sample by sample, so a seamless loop stays seamless."""
    r = math.sqrt(sum(v * v for v in x) / len(x)) or 1.0
    k = 0.6 * peak
    tanh = math.tanh

    def soft(v):
        a = abs(v)
        if a <= k:
            return v
        return math.copysign(k + (peak - k) * tanh((a - k) / (peak - k)), v)
    return [soft(v * rms / r) for v in x]


def _m_kalimba(m):
    x = partials_tone(midi(m), 1.5, [(1, 1.0, 0.45), (2, 0.04, 0.12), (5.9, 0.09, 0.03)], attack=0.0025)
    return fade_tail(x, 0.1)


def _m_glock(m, tau=0.32):
    return fade_tail(partials_tone(midi(m), 1.0, [(1, 1.0, tau), (2.76, 0.1, tau * 0.25)], attack=0.0015), 0.06)


def _m_pizz(m, tau=0.1, dur=0.5):
    x = partials_tone(midi(m), dur, [(1, 1.0, tau), (2, 0.45, tau * 0.6), (3, 0.25, tau * 0.4),
                                     (4, 0.12, tau * 0.3), (5, 0.06, tau * 0.2)], attack=0.003)
    return fade_tail(x, 0.06)


def _m_pad(midis, dur, rng, attack=0.6, release=0.9, fc=1400.0):
    """Soft, slightly chorused chord: pairs of triangle waves, gently lowpassed."""
    n = ns(dur + release)
    out = [0.0] * n
    for m in midis:
        f = midi(m)
        for det in (-0.0035, 0.0035):
            mix(out, osc(f * (1.0 + det), n, "tri", 0.003, rng.uniform(4.0, 5.5)), 0, 0.5, samples=True)
    out = lowpass(lowpass(out, fc), fc)
    return mul(out, env(n, [(0, 0), (attack, 1), (dur, 0.85), (dur + release, 0)]))


def _m_softbass(m, dur):
    n = ns(dur)
    x = partials_tone(midi(m), dur, [(1, 1.0, 0), (2, 0.3, 0.3), (3, 0.08, 0.12)], attack=0.02)
    return mul(x, env(n, [(0, 0), (0.05, 1), (max(0.06, dur - 0.15), 0.7), (dur, 0)]))


def _m_bass(m, dur, fc=700.0):
    """Round, punchy bass: a buzzy tone through a lowpass, plucked envelope."""
    n = ns(dur)
    src = buzz([midi(m)] * n, 10, 1.3)
    a = env(n, [(0, 0), (0.005, 1), (dur * 0.5, 0.75), (max(0.006, dur - 0.02), 0.6), (dur, 0)])
    return mul(lowpass(lowpass(src, fc), fc), a)


def _m_kick(rng, f0=150.0):
    x = thump(0.3, f0, 48, 0.11, 0.022, attack=0.0015)
    mix(x, nburst(rng, 0.02, 2500, 0.8, 0.004), 0, 0.12)
    return fade_tail(x, 0.08)


def _m_snare(rng, tone=185.0, tau=0.065, bright=3000.0, dur=0.25):
    n = ns(dur)
    body = partials_tone(tone, dur, [(1, 1.0, 0.045), (1.62, 0.5, 0.03)], attack=0.001)
    wires = mul(norm(svf(noise(n, rng), bright, 0.6, "bp")), decay(n, tau, 0.0008))
    return fade_tail(add((body, 0.55), (wires, 0.85)), 0.05)


def _m_hat(rng, tau=0.016, fc=5200.0):
    n = ns(0.09)
    return mul(norm(svf(noise(n, rng), fc, 1.1, "bp")), decay(n, tau, 0.0005))


def _m_tom(rng, f):
    x = thump(0.4, f * 1.5, f, 0.13, 0.04, attack=0.0015)
    mix(x, nburst(rng, 0.05, 900, 0.8, 0.012), 0, 0.15)
    return fade_tail(x, 0.1)


def _m_crash(rng, dur=1.8):
    n = ns(dur)
    x = norm(add((svf(noise(n, rng), 4300, 0.5, "bp"), 1.0), (svf(noise(n, rng), 2500, 0.8, "bp"), 0.45)))
    return mul(x, decay(n, 0.5, 0.002))


def _m_block(f):
    """Woodblock "tok" (the tick-tock of a clock)."""
    return fade_tail(partials_tone(f, 0.12, [(1, 1.0, 0.028), (2.71, 0.25, 0.01)], attack=0.0008), 0.02)


def _m_shaker(rng, tau=0.025):
    n = ns(0.09)
    return mul(norm(svf(noise(n, rng), 4300, 0.9, "bp")), decay(n, tau, 0.006))


def _cache():
    store = {}

    def note(key, make):
        if key not in store:
            store[key] = make()
        return store[key]
    return note


# ---- calm_loop: the 2D sandbox. Slow and dreamy: kalimba over a soft pad.
CALM_BPM = 100                  # 13230 samples a beat
CALM_BARS = 16                  # 38.4 s
CALM_CHORDS = ["F", "Dm", "Bb", "C6", "F", "Am", "Bb", "Csus",
               "Dm", "Am", "Bb", "F", "Gm", "Bb", "Csus", "C7"]
CALM_PAD = {"F": (53, 57, 60, 64), "Dm": (53, 57, 60, 62), "Bb": (53, 57, 58, 62), "C6": (55, 57, 60, 64),
            "Am": (52, 57, 60, 64), "Csus": (53, 55, 60, 62), "Gm": (53, 55, 58, 62), "C7": (52, 55, 58, 60)}
CALM_ROOT = {"F": 41, "Dm": 38, "Bb": 46, "C6": 48, "Am": 45, "Csus": 48, "Gm": 43, "C7": 48}
CALM_MELODY = [                 # (beat, note) per bar, F major pentatonic-ish
    [(0, 81), (1.5, 79), (2, 77), (3, 72)],
    [(0, 74), (0.5, 77), (1, 81), (3, 79)],
    [(0, 77), (1, 74), (1.5, 77), (2, 81), (3.5, 79)],
    [(0, 79), (1.5, 81), (2, 79), (3, 76)],
    [(0, 81), (0.5, 84), (1, 81), (2, 79), (3, 77)],
    [(0, 76), (1, 79), (2, 84), (3, 81)],
    [(0, 86), (1, 84), (1.5, 81), (2, 77), (3, 79)],
    [(0, 77), (2, 76), (3, 72)],
    [(0, 74), (1, 77), (2, 81), (2.5, 84), (3, 81)],
    [(0, 79), (1, 76), (2, 72), (3, 76)],
    [(0, 77), (0.5, 81), (1, 86), (2, 84), (3, 81)],
    [(0, 84), (2, 81), (3, 77)],
    [(0, 79), (1, 82), (2, 86), (3, 84)],
    [(0, 81), (1, 77), (2, 74), (3, 77)],
    [(0, 79), (1, 77), (2, 79), (3, 84)],
    [(0, 82), (1, 81), (2, 79), (3, 76)],
]


def render_calm():
    rng = random.Random(SEED * 7 + 101)
    beat = SR * 60.0 / CALM_BPM
    L = int(round(beat * 4 * CALM_BARS))
    total = L + ns(6.0)
    kal, box, pad, bass, kick, perc = ([0.0] * total for _ in range(6))
    note = _cache()

    def pos(bar, b):
        return int(round((bar * 4 + b) * beat))

    tok = _m_block(1050.0)
    kick_s = mul(_m_kick(rng, 120.0), 0.8)
    shk = _m_shaker(rng)
    for bar in range(CALM_BARS):
        chord = CALM_CHORDS[bar]
        for b, m in CALM_MELODY[bar]:
            vel = rng.uniform(0.75, 0.9) + (0.08 if b == int(b) else 0.0)
            i = max(0, pos(bar, b) + rng.randint(-80, 80))
            mix(kal, note(("kal", m), lambda m=m: _m_kalimba(m)), i, vel, samples=True)
        if bar % 8 >= 4:              # a music box twinkles along in the second half of each phrase
            top = CALM_PAD[chord][-1] + 24
            for b in (0, 2.5):
                mix(box, note(("box", top), lambda top=top: _m_glock(top, 0.45)), pos(bar, b), 0.6, samples=True)
        mix(pad, note(("pad", chord), lambda c=chord: _m_pad(CALM_PAD[c], 4 * beat / SR, rng)),
            pos(bar, 0), 1.0, samples=True)
        r = CALM_ROOT[chord]
        for b, m, beats, g in ((0, r, 2.6, 1.0), (3, r + 7, 0.9, 0.6)):
            mix(bass, note(("bass", m, beats), lambda m=m, beats=beats: _m_softbass(m, beats * beat / SR)),
                pos(bar, b), g, samples=True)
        mix(kick, kick_s, pos(bar, 0), 1.0, samples=True)
        if bar >= 8:
            mix(kick, kick_s, pos(bar, 2.5), 0.5, samples=True)
        for b in (1, 3):
            mix(perc, tok, pos(bar, b), 0.6, samples=True)
        for k in range(8):           # lazily swung shaker
            mix(perc, shk, pos(bar, k * 0.5 + (0.08 if k % 2 else 0.0)), 0.25 if k % 2 else 0.15, samples=True)

    send = add((kal, 1.0), (box, 0.7))
    wet = echo(send, 0.75 * beat / SR, 0.32, 1.0, 2200)          # dotted-eighth echo
    wet = [w - s for w, s in zip(wet, send)]
    master = add((kal, 0.5), (box, 0.12), (pad, 0.16), (bass, 0.42), (kick, 0.3), (perc, 0.1), (wet, 0.25))
    master = lowpass(highpass(master, 30.0), 6500)
    return _level(_wrap(master, L), 0.105)


# ---- ready_loop: building a 3D battle. A toy-soldier march getting ready:
# tiptoeing pizzicato, a ticking clock, a snare and soft horns.
READY_BPM = 120                 # 11025 samples a beat
READY_BARS = 16                 # 32 s
READY_CHORDS = ["G", "C", "G", "D", "G", "C", "Am", "D",
                "Em", "C", "G", "D", "Em", "Am", "C", "D7"]
READY_HORN = {"G": (55, 59, 62), "C": (55, 60, 64), "D": (54, 57, 62), "Am": (57, 60, 64),
              "Em": (55, 59, 64), "D7": (54, 60, 62)}
READY_ROOT = {"G": 43, "C": 48, "D": 50, "Am": 45, "Em": 40, "D7": 50}
READY_MELODY = [                # (beat, note) per bar, G major
    [(0, 67), (0.5, 71), (1, 74), (2, 79), (3, 74)],
    [(0, 76), (0.5, 74), (1, 72), (2, 76), (3, 79)],
    [(0, 74), (1, 71), (1.5, 74), (2, 79), (3, 78)],
    [(0, 76), (1, 74), (2, 69), (3, 72)],
    [(0, 71), (0.5, 74), (1, 79), (2, 83), (3, 81)],
    [(0, 79), (1, 76), (1.5, 79), (2, 84), (3, 79)],
    [(0, 81), (1, 76), (2, 72), (3, 74)],
    [(0, 78), (1, 81), (2, 78), (3, 74)],
    [(0, 79), (1, 83), (2, 79), (3, 76)],
    [(0, 76), (1, 79), (2, 84), (3, 79)],
    [(0, 83), (1, 79), (2, 74), (3, 71)],
    [(0, 74), (1, 78), (2, 81), (3, 78)],
    [(0, 76), (0.5, 79), (1, 83), (2, 81), (3, 79)],
    [(0, 76), (1, 72), (2, 76), (3, 81)],
    [(0, 79), (1, 76), (2, 72), (3, 76)],
    [(0, 74), (1, 78), (2, 81), (3, 84)],
]


def render_ready():
    rng = random.Random(SEED * 7 + 202)
    beat = SR * 60.0 / READY_BPM
    L = int(round(beat * 4 * READY_BARS))
    total = L + ns(5.0)
    mel, pz, horns, kick, snare, clock = ([0.0] * total for _ in range(6))
    note = _cache()

    def pos(bar, b):
        return int(round((bar * 4 + b) * beat))

    kick_s = _m_kick(rng, 110.0)
    snares = [_m_snare(rng, 200.0, 0.05, 3400.0) for _ in range(3)]
    tick = _m_block(1500.0)
    tock = _m_block(1120.0)
    for bar in range(READY_BARS):
        chord = READY_CHORDS[bar]
        for b, m in READY_MELODY[bar]:
            vel = rng.uniform(0.8, 0.92) + (0.06 if b == int(b) else 0.0)
            i = max(0, pos(bar, b) + rng.randint(-50, 50))
            mix(mel, note(("glk", m), lambda m=m: _m_glock(m + 12, 0.28)), i, vel * 0.45, samples=True)
            mix(mel, note(("pzm", m), lambda m=m: _m_pizz(m, 0.12)), i, vel, samples=True)
        r = READY_ROOT[chord]
        for b, m in ((0, r), (1, r + 7), (2, r + 12), (3, r + 7)):
            mix(pz, note(("pz", m), lambda m=m: _m_pizz(m, 0.09)), pos(bar, b), 1.0 if b in (0, 2) else 0.8,
                samples=True)
        for m in READY_HORN[chord]:
            mix(horns, note(("hn", m), lambda m=m: horn(midi(m), 4 * beat / SR + 0.1, attack=0.25, release=0.35,
                                                         bright=700, tilt=1.1)), pos(bar, 0), 0.35, samples=True)
        for b in (0, 2):
            mix(kick, kick_s, pos(bar, b), 1.0 if b == 0 else 0.7, samples=True)
        hits = [(0, 0.45), (0.5, 0.2), (0.75, 0.22), (1, 0.85), (2, 0.45), (2.5, 0.2), (2.75, 0.22), (3, 0.85)]
        if bar % 4 == 3 and bar != READY_BARS - 1:
            hits += [(3.5, 0.35), (3.75, 0.45)]
        if bar == READY_BARS - 1:                # a snare roll back to the top
            hits = [(0, 0.45), (0.5, 0.2), (0.75, 0.22), (1, 0.85)]
            hits += [(2 + k * 0.25, 0.3 + 0.07 * k) for k in range(8)]
        for k, (b, g) in enumerate(hits):
            mix(snare, snares[k % 3], pos(bar, b), g, samples=True)
        for b in range(4):
            mix(clock, tick if b % 2 == 0 else tock, pos(bar, b + 0.5), 0.5, samples=True)

    wet = echo(mel, 0.5 * beat / SR, 0.25, 1.0, 2500)
    wet = [w - s for w, s in zip(wet, mel)]
    master = add((mel, 0.42), (pz, 0.36), (horns, 0.2), (kick, 0.3), (snare, 0.2), (clock, 0.07), (wet, 0.18))
    master = lowpass(highpass(master, 30.0), 7000)
    return _level(_wrap(master, L), 0.12)


# ---- battle_loop: the fighting. Bouncy and heroic, never scary: drums,
# a driving bass, brass stabs and a brass tune.
BATTLE_BPM = 140                # 9450 samples a beat
BATTLE_BARS = 16                # 27.4 s
BATTLE_CHORDS = ["C", "Bb", "F", "C", "C", "Bb", "Ab", "G",
                 "Am", "F", "C", "G", "Ab", "Bb", "C", "G"]
BATTLE_STAB = {"C": (60, 64, 67), "Bb": (58, 62, 65), "F": (57, 60, 65), "Ab": (56, 60, 63),
               "G": (59, 62, 67), "Am": (57, 60, 64)}
BATTLE_ROOT = {"C": 48, "Bb": 46, "F": 41, "Ab": 44, "G": 43, "Am": 45}
BATTLE_MELODY = [               # (beat, note, beats) per bar
    [(0, 67, 0.5), (0.5, 72, 0.5), (1, 76, 1.0), (2.5, 74, 0.5), (3, 72, 1.0)],
    [(0, 74, 1.5), (1.5, 70, 0.5), (2, 74, 1.0), (3, 77, 1.0)],
    [(0, 77, 1.0), (1, 76, 0.5), (1.5, 74, 0.5), (2, 72, 1.5), (3.5, 69, 0.5)],
    [(0, 72, 2.0), (2.5, 67, 0.5), (3, 72, 0.5), (3.5, 76, 0.5)],
    [(0, 79, 1.0), (1, 76, 0.5), (1.5, 79, 0.5), (2, 84, 1.0), (3, 79, 1.0)],
    [(0, 77, 1.0), (1, 74, 0.5), (1.5, 77, 0.5), (2, 82, 1.5), (3.5, 79, 0.5)],
    [(0, 80, 1.0), (1, 79, 0.5), (1.5, 77, 0.5), (2, 75, 1.0), (3, 72, 1.0)],
    [(0, 74, 1.5), (1.5, 71, 0.5), (2, 74, 1.0), (3, 79, 1.0)],
    [(0, 76, 1.5), (1.5, 72, 0.5), (2, 69, 1.0), (3, 72, 1.0)],
    [(0, 77, 1.0), (1, 81, 1.0), (2, 79, 1.0), (3, 77, 1.0)],
    [(0, 76, 1.0), (1, 79, 1.0), (2, 84, 2.0)],
    [(0, 83, 1.0), (1, 79, 0.5), (1.5, 74, 0.5), (2, 79, 2.0)],
    [(0, 72, 1.0), (1, 75, 1.0), (2, 80, 1.5), (3.5, 79, 0.5)],
    [(0, 77, 1.0), (1, 74, 1.0), (2, 82, 1.5), (3.5, 77, 0.5)],
    [(0, 79, 0.5), (0.5, 84, 1.5), (2, 79, 0.5), (2.5, 76, 0.5), (3, 72, 1.0)],
    [(0, 74, 0.5), (0.5, 79, 0.5), (1, 83, 1.0), (2, 86, 1.5), (3.5, 79, 0.5)],
]


def render_battle():
    rng = random.Random(SEED * 7 + 303)
    beat = SR * 60.0 / BATTLE_BPM
    L = int(round(beat * 4 * BATTLE_BARS))
    total = L + ns(5.0)
    lead, stabs, bass, kick, snare, hats, toms, crash = ([0.0] * total for _ in range(8))
    note = _cache()

    def pos(bar, b):
        return int(round((bar * 4 + b) * beat))

    kick_s = _m_kick(rng, 160.0)
    snare_s = _m_snare(rng, 190.0, 0.08, 2800.0, 0.3)
    hat_s = [_m_hat(rng) for _ in range(2)]
    tom_s = {f: _m_tom(rng, f) for f in (190.0, 150.0, 115.0, 90.0)}
    crash_s = _m_crash(rng)
    for bar in range(BATTLE_BARS):
        chord = BATTLE_CHORDS[bar]
        for b, m, beats in BATTLE_MELODY[bar]:
            d = beats * beat / SR * 0.92
            long_note = beats >= 1.5
            make = (lambda m=m, d=d, v=long_note: horn(midi(m), d, attack=0.02, release=0.06, scoop=0.03,
                                                         vib=0.012 if v else 0.0, vib_delay=0.2,
                                                         bright=3000, tilt=0.75))
            vel = rng.uniform(0.85, 0.95) + (0.06 if b == int(b) else 0.0)
            mix(lead, note(("lead", m, beats), make), pos(bar, b), vel, samples=True)
        for b, g in ((0, 1.0), (1.5, 0.7), (2.5, 0.75)):
            for m in BATTLE_STAB[chord]:
                mix(stabs, note(("stab", m), lambda m=m: horn(midi(m), 0.17, attack=0.012, release=0.06,
                                                              bright=2200, tilt=0.8)),
                    pos(bar, b), g, samples=True)
        r = BATTLE_ROOT[chord]
        for k, up in enumerate((0, 0, 12, 0, 0, 0, 7, 12)):
            m = r + up
            mix(bass, note(("bass", m), lambda m=m: _m_bass(m, 0.45 * beat / SR)), pos(bar, k * 0.5),
                1.0 if k % 2 == 0 else 0.8, samples=True)
        fill = bar in (7, 15)
        for b in ((0, 2, 2.5) if not fill else (0, 2)):
            mix(kick, kick_s, pos(bar, b), 1.0 if b != 2.5 else 0.7, samples=True)
        for b in ((1, 3) if not fill else (1,)):
            mix(snare, snare_s, pos(bar, b), 1.0, samples=True)
        for k in range(8 if not fill else 6):
            mix(hats, hat_s[k % 2], pos(bar, k * 0.5), 1.0 if k % 2 == 0 else 0.6, samples=True)
        if bar == 7:            # a quick tom fill
            for k, f in enumerate((190.0, 150.0, 115.0, 90.0)):
                mix(toms, tom_s[f], pos(bar, 3 + k * 0.25), 0.8 + 0.05 * k, samples=True)
        if bar == 15:           # a bigger one, back to the top
            seq = (190.0, 190.0, 150.0, 150.0, 115.0, 115.0, 90.0, 90.0)
            for k, f in enumerate(seq):
                mix(toms, tom_s[f], pos(bar, 2 + k * 0.25), 0.7 + 0.04 * k, samples=True)
            mix(snare, snare_s, pos(bar, 3.75), 0.6, samples=True)
        if bar in (0, 8):
            mix(crash, crash_s, pos(bar, 0), 1.0, samples=True)

    wet = echo(lead, 0.75 * beat / SR, 0.2, 1.0, 2500)
    wet = [w - s for w, s in zip(wet, lead)]
    master = add((lead, 0.34), (stabs, 0.12), (bass, 0.3), (kick, 0.55), (snare, 0.32), (hats, 0.05),
                 (toms, 0.4), (crash, 0.06), (wet, 0.12))
    master = lowpass(highpass(master, 30.0), 7000)
    return _level(_wrap(master, L), 0.13)


# name -> (render, bars, bpm); wiggle_loop is at MUSIC_PATH
LOOPS = {
    "wiggle_loop": (render_music, BARS, BPM),
    "calm_loop": (render_calm, CALM_BARS, CALM_BPM),
    "ready_loop": (render_ready, READY_BARS, READY_BPM),
    "battle_loop": (render_battle, BATTLE_BARS, BATTLE_BPM),
}


def loop_path(name):
    return os.path.join(os.path.dirname(MUSIC_PATH), name + ".wav")


# Godot's mixer reads a little past both ends of a loop: it interpolates
# towards the sample after the loop's last one, and its QOA decoder (the
# compressed import) stumbles on the first few samples of a file. With the
# loop running from the file's first sample to its last, both made a click
# at the seam. So each loop file has a copy of the loop's last LOOP_LEAD
# samples before it and of its first LOOP_GUARD samples after it, and a
# 'smpl' chunk saying where the loop is, which Godot's importer reads
# (edit/loop_mode "Detect From WAV").
LOOP_LEAD = 1024
LOOP_GUARD = 1024


def write_loop(path, x):
    """Writes loop `x` with its lead-in, guard and loop points (see LOOP_LEAD)."""
    write_wav(path, x[-LOOP_LEAD:] + x + x[:LOOP_GUARD])
    begin = LOOP_LEAD
    end = LOOP_LEAD + len(x)          # Godot's loop_end: the first sample after the loop
    head = [0, 0, int(round(1e9 / SR)), 60, 0, 0, 0, 1, 0]      # maker, product, period, note, ..., 1 loop
    loop = [0, 0, begin, end, 0, 0]                              # id, forward, start, end, fraction, forever
    chunk = b"smpl" + (4 * (len(head) + len(loop))).to_bytes(4, "little") + b"".join(
        v.to_bytes(4, "little") for v in head + loop)
    with open(path, "r+b") as f:
        f.seek(0, 2)
        f.write(chunk)
        size = f.tell()
        f.seek(4)
        f.write((size - 8).to_bytes(4, "little"))


def loop_points(path):
    """(begin, end) from a WAV file's 'smpl' chunk, or None."""
    with open(path, "rb") as f:
        b = f.read()
    off = 12
    while off + 8 <= len(b):
        cid = b[off:off + 4]
        size = int.from_bytes(b[off + 4:off + 8], "little")
        if cid == b"smpl" and size >= 60:
            at = off + 8 + 36 + 8
            return (int.from_bytes(b[at:at + 4], "little"), int.from_bytes(b[at + 4:at + 8], "little"))
        off += 8 + size + (size & 1)
    return None


# ============================================================ verification
SFX_MAX_SEC = {"boom": 1.6, "mega_boom": 2.3, "firework_burst": 1.7, "party": 1.6,
               "wind": 2.5, "rain": 2.5, "rumble": 2.5,
               "roar": 1.7, "nuke": 4.2, "whistle": 1.4, "plane": 2.7, "alarm": 1.7,
               "victory": 2.1, "battle_start": 2.1, "defeat": 2.4, "gun_mg": 0.1}


def _read(path):
    with wave.open(path, "rb") as w:
        params = (w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getcomptype())
        nf = w.getnframes()
        data = array.array("h")
        data.frombytes(w.readframes(nf))
    if sys.byteorder == "big":
        data.byteswap()
    return params, nf, data


def verify():
    ok = True
    problems = []
    print("\n%-16s %7s %8s %7s %7s" % ("file", "sec", "bytes", "peak", "rms"))
    total = 0
    combat_total = 0
    durs = []
    for name in SFX:
        path = os.path.join(SFX_DIR, name + ".wav")
        if not os.path.isfile(path):
            problems.append("missing " + path)
            continue
        try:
            params, nf, data = _read(path)
        except Exception as e:                              # noqa: BLE001
            problems.append("%s: not a valid WAV (%s)" % (name, e))
            continue
        size = os.path.getsize(path)
        total += size
        if name in COMBAT_SFX:
            combat_total += size
        sec = nf / float(SR)
        durs.append(sec)
        peak = max(abs(v) for v in data) / 32767.0 if nf else 0.0
        rms = math.sqrt(sum(v * v for v in data) / max(1, nf)) / 32767.0
        print("%-16s %7.3f %8d %7.3f %7.3f" % (name, sec, size, peak, rms))
        if params != (1, 2, SR, "NONE"):
            problems.append("%s: wrong format %r" % (name, params))
        if nf == 0 or peak < 0.5 or rms < 0.01:
            problems.append("%s: silent or too quiet (peak %.3f)" % (name, peak))
        if peak > 0.9:
            problems.append("%s: peak %.3f above -1 dBFS" % (name, peak))
        if sec > SFX_MAX_SEC.get(name, 1.2):
            problems.append("%s: too long (%.2f s)" % (name, sec))
        if abs(data[0]) > 200 or abs(data[-1]) > 200:
            problems.append("%s: does not start/end near zero" % name)
    print("-- %d sfx files, %.1f KB total, %.2f-%.2f s (avg %.2f s)" % (
        len(durs), total / 1024.0, min(durs or [0]), max(durs or [0]), sum(durs) / max(1, len(durs))))
    print("-- of which %d combat sfx, %.1f KB" % (len(COMBAT_SFX), combat_total / 1024.0))
    if total - combat_total > 3 * 1024 * 1024:
        problems.append("sfx total %.2f MB exceeds 3 MB" % ((total - combat_total) / 1048576.0))
    if combat_total > 4 * 1024 * 1024:
        problems.append("combat sfx total %.2f MB exceeds 4 MB" % (combat_total / 1048576.0))

    music_total = 0
    for name, (_, bars, bpm) in LOOPS.items():
        path = loop_path(name)
        if not os.path.isfile(path):
            problems.append("missing " + path)
            continue
        params, nf, data = _read(path)
        size = os.path.getsize(path)
        music_total += size
        pts = loop_points(path)
        if pts is None:
            problems.append("%s: no loop points ('smpl' chunk)" % name)
            continue
        begin, end = pts
        L = end - begin
        if begin != LOOP_LEAD or end + LOOP_GUARD != nf or \
                list(data[:begin]) != list(data[end - begin:end]) or \
                list(data[end:nf]) != list(data[begin:begin + nf - end]):
            problems.append("%s: the lead-in and guard aren't copies of the loop's ends" % name)
        loop = data[begin:end]
        sec = L / float(SR)
        peak = max(abs(v) for v in loop) / 32767.0
        rms = math.sqrt(sum(v * v for v in loop) / L) / 32767.0
        diffs = sorted(abs(loop[i + 1] - loop[i]) for i in range(0, L - 1, 7))
        typical = diffs[int(len(diffs) * 0.999)]
        bends = sorted(abs(loop[i + 1] - 2 * loop[i] + loop[i - 1]) for i in range(1, L - 1, 7))
        typical_bend = bends[int(len(bends) * 0.999)]
        # the seam: the step from the loop's last sample back to its first, and
        # how much the slope changes there (a click would show up in both)
        seam = abs(loop[0] - loop[-1])
        bend = abs(loop[0] - 2 * loop[-1] + loop[-2])
        print("-- %s: %.3f s loop (%d bars @ %d BPM, samples %d-%d of %d), %d bytes (%.2f MB), "
              "peak %.3f (%.1f dBFS), rms %.3f (%.1f dBFS)"
              % (name, sec, bars, bpm, begin, end, nf, size, size / 1048576.0, peak, 20 * math.log10(peak), rms,
                 20 * math.log10(rms)))
        print("   loop seam: step %d (99.9th pct step %d), slope change %d (99.9th pct %d), "
              "ends %d %d %d | starts %d %d" % (seam, typical, bend, typical_bend,
                                                loop[-3], loop[-2], loop[-1], loop[0], loop[1]))
        if params != (1, 2, SR, "NONE"):
            problems.append("%s: wrong format %r" % (name, params))
        if not 24.0 <= sec <= 40.0:
            problems.append("%s: duration %.2f s outside 24-40 s" % (name, sec))
        if L != int(round(SR * 60.0 / bpm * 4 * bars)):
            problems.append("%s: the loop is not a whole number of bars" % name)
        if peak < 0.3 or peak > 0.75:
            problems.append("%s: peak %.3f not near -3 dBFS" % (name, peak))
        if seam > typical or bend > typical_bend:
            problems.append("%s: the loop seam jumps more than normal steps" % name)
        if size > 2.5 * 1024 * 1024:
            problems.append("%s: file over 2.5 MB" % name)
    print("-- %d music loops, %.2f MB" % (len(LOOPS), music_total / 1048576.0))
    if music_total > 7 * 1024 * 1024:
        problems.append("music total %.2f MB exceeds 7 MB" % (music_total / 1048576.0))
    for p in problems:
        print("FAIL:", p)
        ok = False
    print("verification", "PASSED" if ok else "FAILED")
    return ok


# =================================================================== main
def main(argv):
    if "--verify" in argv:
        return 0 if verify() else 1
    wanted = [a for a in argv if not a.startswith("-")]
    unknown = [a for a in wanted if a not in SFX and a not in LOOPS and a != "music"]
    if unknown:
        print("unknown sound(s): %s\nknown: %s music (all the loops) %s" % (
            ", ".join(unknown), " ".join(SFX), " ".join(LOOPS)))
        return 2
    os.makedirs(SFX_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(MUSIC_PATH), exist_ok=True)
    for name, fn in SFX.items():
        if wanted and name not in wanted:
            continue
        rng = random.Random(SEED * 1000003 + zlib.crc32(name.encode("utf-8")))
        write_wav(os.path.join(SFX_DIR, name + ".wav"), finish(fn(rng)))
        print("sfx  ", name)
    for name, (render, _, _) in LOOPS.items():
        if not wanted or "music" in wanted or name in wanted:
            print("music ", name, "(takes a little while)...")
            write_loop(loop_path(name), render())
    return 0 if verify() else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
