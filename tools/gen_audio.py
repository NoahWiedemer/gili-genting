#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Gili Genting -- procedural audio generator (music + SFX).

Everything is synthesized from scratch with numpy/scipy:
  * a tiny tracker: note strings -> events -> instruments -> parts -> mix
  * oscillators: band-limited square (variable duty, PolyBLEP), saw, triangle, sine,
    FM / additive bells (music box, marimba, steel pan, gamelan metallophones, gongs),
    plucked strings, piano-ish, organ, formant choir, distorted saw, brass
  * noise drums: kick, snare, hats, crash, toms, shaker, clave, congas, kendang, taiko
  * ADSR, vibrato, pitch bends, feedback echo, convolution reverb from a synthetic IR
  * soft limiting + normalisation to -1 dBFS peak
Loops: everything is rendered with a long tail and then folded (wrapped) modulo the
loop length, so note releases, echoes and reverb tails continue seamlessly into the
start of the loop.  Ambient layers are generated as exactly periodic signals
(spectrally shaped FFT noise, integer-cycle LFOs, wrap-placed events).

Output: 16-bit mono PCM WAV @ 32 kHz into game/assets/audio/{music,sfx}/.

v2 additions (MUSIC2 / SFX2): five battle themes that cut into drum & bass sections (synthesized
amen-style break chopped on the 16th grid, reese/wobble bass through a time-varying resonant
filter), three DnB boss themes, area variants (beach_2, village_2, steppe_2, farm_2, cave, cellar,
shop, rest), alternate fanfares, interaction SFX and formant-synthesized enemy voices.  Each v2
item gets its own RNG seeded from its name, so the original outputs are bit-identical.

Usage:  python3 tools/gen_audio.py            (everything)
        python3 tools/gen_audio.py title boss  (only the named items)
        python3 tools/gen_audio.py battle_3 verify
"""
import os
import re
import sys
import wave
import time
import zlib
from collections import defaultdict

import numpy as np
from scipy import signal as ss

SR = 32000
TAU = 2.0 * np.pi
HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(HERE)
MUS_DIR = os.path.join(PROJ, 'game', 'assets', 'audio', 'music')
SFX_DIR = os.path.join(PROJ, 'game', 'assets', 'audio', 'sfx')
RNG = np.random.default_rng(20261018)


# =====================================================================================
# basic DSP helpers
# =====================================================================================
def ns(sec):
    return max(1, int(round(sec * SR)))


def t_(n):
    return np.arange(n) / SR


def noise(n):
    return RNG.standard_normal(n)


def _sos(kind, fc, order):
    if kind == 'band':
        lo, hi = fc
        hi = min(hi, SR * 0.45)
        lo = max(lo, 5.0)
        return ss.butter(order, [lo, hi], 'bandpass', fs=SR, output='sos')
    fc = min(max(fc, 5.0), SR * 0.45)
    return ss.butter(order, fc, kind, fs=SR, output='sos')


def lp(x, fc, order=2):
    return ss.sosfilt(_sos('low', fc, order), x)


def hp(x, fc, order=2):
    return ss.sosfilt(_sos('high', fc, order), x)


def bp(x, lo, hi, order=2):
    return ss.sosfilt(_sos('band', (lo, hi), order), x)


def rms(x):
    return float(np.sqrt(np.mean(x ** 2) + 1e-20))


def att(n, sec):
    """Linear attack ramp (avoids clicks for oscillators with random start phase)."""
    k = min(n, ns(sec))
    e = np.ones(n)
    e[:k] = np.linspace(0, 1, k, endpoint=False)
    return e


def fin(x, sec=0.004):
    """Fade the tail to exactly zero.  The fade covers max(sec, 15% of the sound, capped at
    0.25 s) with a half-cosine, so truncated exponential decays never end in a click."""
    k = min(len(x), max(ns(sec), min(int(0.15 * len(x)), ns(0.25))))
    if k > 1:
        x = x.copy()
        x[-k:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, k))
    return x


def damp(x, dur, rel):
    """Exponential damping after `dur` seconds (key-off for ringing instruments)."""
    i = ns(dur)
    if i >= len(x):
        return x
    end = min(len(x), i + ns(rel * 7))
    g = np.exp(-np.arange(end - i) / (rel * SR))
    y = x[:end].copy()
    y[i:] *= g
    return fin(y)


def adsr(dur, a=0.01, d=0.1, s=0.8, r=0.1):
    nd = max(ns(dur), 2)
    na = max(min(ns(a), nd), 1)
    nr = max(ns(r), 2)
    e = np.empty(nd + nr)
    e[:na] = np.linspace(0, 1, na, endpoint=False)
    k = np.arange(nd - na)
    e[na:nd] = s + (1 - s) * np.exp(-k * 4.0 / max(ns(d), 1))
    last = e[nd - 1]
    kr = np.arange(nr)
    e[nd:] = last * np.exp(-kr * 5.0 / nr) * (1 - kr / nr)
    return e


def ftrack(f, n, vib=None, bend=None):
    """Frequency array with optional delayed vibrato (rate, depth_semitones, delay)
    and exponential pitch bend (semitones, tau)."""
    fr = np.full(n, float(f))
    if vib is not None and vib[1] > 0:
        rate, depth, delay = vib
        t = t_(n)
        ramp = np.clip((t - delay) / 0.25, 0, 1)
        fr *= 2 ** (depth * ramp * np.sin(TAU * rate * t) / 12)
    if bend is not None:
        semis, tau = bend
        fr *= 2 ** (semis * np.exp(-t_(n) / tau) / 12)
    return fr


def blep(t, dt):
    r = np.zeros_like(t)
    m = t < dt
    x = t[m] / dt[m]
    r[m] = x + x - x * x - 1
    m = t > 1 - dt
    x = (t[m] - 1) / dt[m]
    r[m] = x * x + x + x + 1
    return r


def o_saw(fr, ph0=None):
    ph0 = RNG.random() if ph0 is None else ph0
    t = (np.cumsum(fr) / SR + ph0) % 1.0
    dt = np.minimum(fr / SR, 0.5)
    return 2 * t - 1 - blep(t, dt)


def o_sq(fr, duty=0.5, ph0=None):
    ph0 = RNG.random() if ph0 is None else ph0
    t = (np.cumsum(fr) / SR + ph0) % 1.0
    dt = np.minimum(fr / SR, 0.5)
    v = np.where(t < duty, 1.0, -1.0)
    v += blep(t, dt)
    v -= blep((t - duty) % 1.0, dt)
    return v - (2 * duty - 1)


def o_tri(fr, ph0=0.25):
    t = (np.cumsum(fr) / SR + ph0) % 1.0
    return 4 * np.abs(t - 0.5) - 1


def o_sin(fr, ph0=0.0):
    return np.sin(TAU * (np.cumsum(fr) / SR + ph0))


def additive(fr, partials):
    """partials: (ratio, amp, decay_seconds); fr: frequency array of the fundamental."""
    n = len(fr)
    t = t_(n)
    base = np.cumsum(fr) / SR
    x = np.zeros(n)
    for ratio, amp, dec in partials:
        if fr[0] * ratio > 0.45 * SR:
            continue
        x += amp * np.sin(TAU * (ratio * base + RNG.random())) * np.exp(-t / dec)
    return x


def softclip(x, k=0.6):
    a = np.abs(x)
    return np.where(a < k, x, np.sign(x) * (k + (1 - k) * np.tanh((a - k) / (1 - k))))


def norm_peak(x, db=-1.0):
    p = np.max(np.abs(x)) + 1e-12
    return x / p * 10 ** (db / 20)


def master(y, ceil_db=-1.0, drive=1.3):
    y = y / (np.max(np.abs(y)) + 1e-12) * drive
    y = softclip(y)
    return norm_peak(y, ceil_db)


# --- formants -------------------------------------------------------------------------
VOWELS = {
    'a': [(800, 1.0, 80), (1150, 0.5, 90), (2900, 0.22, 120), (3900, 0.1, 130)],
    'o': [(450, 1.0, 70), (800, 0.35, 80), (2830, 0.08, 100)],
    'u': [(325, 1.0, 50), (700, 0.2, 60), (2530, 0.05, 170)],
    'e': [(400, 1.0, 60), (2000, 0.3, 100), (2550, 0.2, 120)],
    'i': [(270, 1.0, 60), (2300, 0.25, 100), (3000, 0.15, 120)],
    'r': [(550, 1.0, 90), (1300, 0.5, 110), (1650, 0.4, 120)],
}


def formant(x, spec, shift=1.0):
    if isinstance(spec, str):
        spec = VOWELS[spec]
    y = np.zeros_like(x)
    for fc, amp, bw in spec:
        fc *= shift
        if fc >= 0.45 * SR:
            continue
        b, a = ss.iirpeak(fc, max(fc / bw, 0.5), fs=SR)
        y += amp * ss.lfilter(b, a, x)
    return y


# --- periodic (loopable) generators ---------------------------------------------------------
def pnoise(n, lo=None, hi=None, tilt=0.0, order=2, peak=None):
    """Exactly periodic noise of length n, spectrally shaped in the FFT domain."""
    X = np.fft.rfft(RNG.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    fz = np.maximum(f, 1e-3)
    H = np.ones_like(f)
    if lo:
        H /= np.sqrt(1 + (lo / fz) ** (2 * order))
    if hi:
        H /= np.sqrt(1 + (fz / hi) ** (2 * order))
    if tilt:
        H *= (np.maximum(f, 20) / 1000.0) ** tilt
    if peak:
        fc, bw = peak
        H *= np.exp(-0.5 * ((f - fc) / bw) ** 2)
    H[0] = 0
    x = np.fft.irfft(X * H, n)
    return x / (np.std(x) + 1e-12)


def plfo(n, cycles, ph=0.0):
    return np.sin(TAU * (cycles * np.arange(n) / n + ph))


def psmooth(n, max_cycles=6, min_cycles=1):
    """Smooth random periodic envelope in [0, 1]."""
    x = np.zeros(n)
    for k in range(min_cycles, max_cycles + 1):
        x += RNG.uniform(0.3, 1.0) / k ** 0.7 * plfo(n, k, RNG.random())
    x -= x.min()
    return x / (x.max() + 1e-12)


def place_wrap(buf, sig, i):
    n = len(buf)
    i %= n
    pos = 0
    while pos < len(sig):
        take = min(len(sig) - pos, n - i)
        buf[i:i + take] += sig[pos:pos + take]
        pos += take
        i = 0


def cfilt(x, fn):
    """Apply a (linear) filter circularly so periodic signals stay periodic."""
    n = len(x)
    return fn(np.tile(x, 3))[n:2 * n]


# --- effects ---------------------------------------------------------------------------
def make_ir(t60=2.0, bright=0.5, pre=0.02):
    length = min(t60 * 1.15 + 0.2, 6.0)
    n = ns(length)
    t = t_(n)
    w = RNG.standard_normal(n)
    dark = lp(w, 1600, 1) * 2.0
    brt = hp(w, 250, 1)
    mix = np.exp(-t / (0.25 * t60 * bright + 0.04))
    ir = (brt * mix + dark * (1 - mix)) * np.exp(-6.9 * t / t60)
    ir *= np.clip(t / 0.012, 0, 1)                      # soft onset of diffuse part
    sc = np.sqrt(np.mean(ir[:ns(0.1)] ** 2)) * 6
    for d, g in [(0.009, 0.7), (0.0157, -0.55), (0.0231, 0.45), (0.0329, -0.35), (0.0447, 0.3), (0.0583, 0.2)]:
        ir[ns(d)] += g * sc
    ir = fin(ir, 0.08)
    ir = np.concatenate([np.zeros(ns(pre)), ir])
    return ir / np.sqrt(np.sum(ir ** 2))


def echo_fx(x, delay_sec, fb=0.4, cut=3200):
    """Feedback delay, wet only: y[n] = x[n-D] + fb*y[n-D] (computed block-wise)."""
    D = ns(delay_sec)
    y = np.zeros(len(x))
    y[D:] = x[:len(x) - D]
    for i in range(D, len(y), D):
        m = min(D, len(y) - i)
        y[i:i + m] += fb * y[i - D:i - D + m]
    return lp(y, cut)


def reverb(x, t60=1.5, wet=0.3, bright=0.6, pre=0.01):
    ir = make_ir(t60, bright, pre)
    w = ss.fftconvolve(x, ir)
    y = np.zeros(len(w))
    y[:len(x)] += x
    return y + wet * w


# =====================================================================================
# music theory / notation
# =====================================================================================
PC = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}
NOTE_RE = re.compile(r'^([A-G])([#b]?)(-?\d)$')


def nm(s):
    m = NOTE_RE.match(s)
    if not m:
        raise ValueError('bad note ' + s)
    acc = {'#': 1, 'b': -1, '': 0}[m.group(2)]
    return 12 * (int(m.group(3)) + 1) + PC[m.group(1)] + acc


def mhz(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def _dur(s):
    if '/' in s:
        a, b = s.split('/')
        return float(a) / float(b)
    return float(s)


def mel(s, start=0.0, vel=0.8, tr=0, bpb=None):
    """'C5:1 D5:.5 r:.5 [C4,E4]:2 | ...' -> [(beat, hz, dur_beats, vel)].
    '|' separates bars; with bpb given every bar is checked for its length."""
    ev = []
    b = start
    for bi, bar in enumerate(s.split('|')):
        tot = 0.0
        for tok in bar.split():
            p, d = (tok.split(':') + ['1'])[:2]
            d = _dur(d)
            v = vel
            if p.endswith('!'):
                v = min(1.0, vel * 1.2)
                p = p[:-1]
            if p not in ('r', '-'):
                notes = p[1:-1].split(',') if p.startswith('[') else [p]
                for q in notes:
                    ev.append((b, mhz(nm(q) + tr), d, v))
            b += d
            tot += d
        if bpb is not None and bar.strip() and abs(tot - bpb) > 1e-6:
            raise ValueError('bar %d has %.3f beats: %s' % (bi + 1, tot, bar))
    return ev


QUAL = {'': [0, 4, 7], 'm': [0, 3, 7], '7': [0, 4, 7, 10], 'm7': [0, 3, 7, 10],
        'maj7': [0, 4, 7, 11], 'm6': [0, 3, 7, 9], 'dim': [0, 3, 6], 'dim7': [0, 3, 6, 9],
        '7b9': [0, 4, 7, 10, 13], '7#11': [0, 4, 7, 10, 18], 'sus4': [0, 5, 7], 'aug': [0, 4, 8],
        'maj7#11': [0, 4, 7, 11, 18], 'maj7#5': [0, 4, 8, 11], 'm9': [0, 3, 7, 10, 14],
        'add9': [0, 4, 7, 14], 'sus2': [0, 2, 7], 'mmaj7': [0, 3, 7, 11]}
CH_RE = re.compile(r'^([A-G])([#b]?)(.*)$')


def parse_chord(name):
    m = CH_RE.match(name)
    root = (PC[m.group(1)] + {'#': 1, 'b': -1, '': 0}[m.group(2)]) % 12
    return root, QUAL[m.group(3)]


def voicing(name, low=52):
    root, ivs = parse_chord(name)
    if len(ivs) >= 5:
        ivs = ivs[1:]
    out = sorted({low + (((root + iv) % 12 - low) % 12) for iv in ivs})
    return out


def root_note(name, low=36):
    root, _ = parse_chord(name)
    return low + ((root - low) % 12)


def timeline(chords, bpb):
    """chords: list of 'Dm' (one bar) or ('Dm', beats). Returns [(name, start, dur)]."""
    out = []
    b = 0.0
    for c in chords:
        if isinstance(c, tuple):
            name, d = c
        else:
            name, d = c, bpb
        out.append((name, b, d))
        b += d
    return out


def merged(tl):
    out = []
    for name, st, d in tl:
        if out and out[-1][0] == name and abs(out[-1][1] + out[-1][2] - st) < 1e-9:
            out[-1] = (name, out[-1][1], out[-1][2] + d)
        else:
            out.append((name, st, d))
    return out


def pad_ev(tl, low=52, vel=0.6, overlap=0.15, merge=True, bass_oct=None):
    ev = []
    for name, st, d in (merged(tl) if merge else tl):
        for m in voicing(name, low):
            ev.append((st, mhz(m), d + overlap, vel))
        if bass_oct is not None:
            ev.append((st, mhz(root_note(name, bass_oct)), d + overlap, vel))
    return ev


def arp_ev(tl, pattern, step, low=55, vel=0.6, dur=None, accents=None, start=0.0, octs=3):
    ev = []
    for name, st, d in tl:
        v = voicing(name, low)
        ext = [m + 12 * o for o in range(octs) for m in v]
        k = 0
        b = st
        while b < st + d - 1e-9:
            ix = pattern[k % len(pattern)]
            if ix is not None:
                if ix == 't':
                    m = v[-1]
                elif ix == 'b':
                    m = v[0]
                else:
                    m = ext[ix % len(ext)]
                a = accents[k % len(accents)] if accents else 1.0
                ev.append((start + b, mhz(m), dur or step, vel * a))
            k += 1
            b += step
    return ev


def bass_ev(tl, pattern, low=36, period=None, vel=0.85):
    """pattern: [(offset, interval|'app'|'app+', dur, vel)] repeated every `period` beats."""
    ev = []
    for ci, (name, st, d) in enumerate(tl):
        r = root_note(name, low)
        nxt = root_note(tl[(ci + 1) % len(tl)][0], low)
        per = period or d
        b0 = st
        while b0 < st + d - 1e-9:
            for off, iv, du, vv in pattern:
                b = b0 + off
                if b >= st + d - 1e-9:
                    continue
                if iv == 'app':
                    m = nxt - 1 if nxt - 1 >= low else nxt + 1
                elif iv == 'app+':
                    m = nxt + 2
                else:
                    m = r + iv
                ev.append((b, mhz(m), du, vel * vv))
            b0 += per
    return ev


def pat(s, start=0.0, step=0.25, f=0.0, vmap=None):
    vmap = vmap or {'X': 1.0, 'x': 0.75, 'o': 0.45, 'g': 0.25}
    s = s.replace(' ', '').replace('|', '')
    return [(start + i * step, f, step, vmap.get(c, 0.7)) for i, c in enumerate(s) if c != '.']


def shift(ev, beats=0.0, semis=0, velmul=1.0):
    return [(b + beats, f * 2 ** (semis / 12), d, v * velmul) for (b, f, d, v) in ev]


# =====================================================================================
# instruments: inst(freq, dur_seconds, vel, **kw) -> np.ndarray
# =====================================================================================
def i_square(f, dur, vel, duty=0.5, a=0.004, d=0.12, s=0.65, r=0.06, vib=(5.8, 0.15, 0.18), bend=None, cut=None):
    e = adsr(dur, a, d, s, r)
    fr = ftrack(f, len(e), vib, bend)
    x = o_sq(fr, duty) * e
    if cut:
        x = lp(x, cut)
    return x * vel * 0.35


def i_tri(f, dur, vel, a=0.003, d=0.1, s=0.8, r=0.05, vib=None):
    e = adsr(dur, a, d, s, r)
    return o_tri(ftrack(f, len(e), vib)) * e * vel * 0.6


def i_clar(f, dur, vel, cut=1700):
    e = adsr(dur, 0.025, 0.12, 0.8, 0.09)
    fr = ftrack(f, len(e), (5.0, 0.08, 0.2))
    x = o_sq(fr, 0.5) + 0.15 * o_sq(fr, 0.3)
    return lp(x, cut, 2) * e * vel * 0.45


def i_strings(f, dur, vel, a=0.35, r=0.8, cut=2400, det=0.09, voices=3, trem=0.0, s=0.85):
    e = adsr(dur, a, 0.3, s, r)
    n = len(e)
    x = np.zeros(n)
    for k in range(voices):
        dt = (k - (voices - 1) / 2) * det
        x += o_saw(ftrack(f * 2 ** (dt / 12), n, (4.8 + 0.37 * k, 0.07, 0.3)))
    x = lp(x, min(cut, f * 10), 2)
    x = hp(x, 60, 1)
    if trem:
        x *= 1 - trem * (0.5 + 0.5 * np.sin(TAU * 13.0 * t_(n)))
    return x * e * vel * 0.32 / np.sqrt(voices)


def i_pad(f, dur, vel, a=1.0, r=1.5, octave=0.25):
    e = adsr(dur, a, 0.5, 0.9, r)
    n = len(e)
    x = o_tri(ftrack(f * 2 ** (0.08 / 12), n, (4.5, 0.05, 0.0))) \
        + o_tri(ftrack(f * 2 ** (-0.08 / 12), n, (5.1, 0.05, 0.0))) \
        + octave * o_sin(ftrack(2 * f, n, (3.7, 0.04, 0.0)))
    return x * e * vel * 0.25


def i_choir(f, dur, vel, vowel='a', a=0.4, r=0.9, voices=3, det=0.14, breath=0.08, s=0.9):
    e = adsr(dur, a, 0.3, s, r)
    n = len(e)
    src = np.zeros(n)
    for k in range(voices):
        dt = (k - (voices - 1) / 2) * det
        src += o_saw(ftrack(f * 2 ** (dt / 12), n, (5.0 + 0.45 * k, 0.13, 0.25)))
    src += breath * noise(n) * voices
    y = formant(src, vowel)
    y = y / (np.max(np.abs(y)) + 1e-9)
    return y * e * vel * 0.4


def i_distsaw(f, dur, vel, drive=4.0, cut=3200, a=0.005, d=0.2, s=0.8, r=0.08, vib=(5.5, 0.2, 0.2)):
    e = adsr(dur, a, d, s, r)
    n = len(e)
    fr = ftrack(f, n, vib)
    x = o_saw(fr) + o_saw(fr * 1.0045) + 0.6 * o_sq(fr * 0.5)
    x = np.tanh(drive * x * e * 0.6)
    x = lp(x, cut, 2)
    return fin(x) * vel * 0.33


def i_bass_saw(f, dur, vel, cut=700, a=0.003, d=0.15, s=0.55, r=0.05, sub=0.5):
    e = adsr(dur, a, d, s, r)
    n = len(e)
    fr = ftrack(f, n)
    raw = o_saw(fr)
    bright = lp(raw, min(cut * 4, 9000))
    dark = lp(raw, cut * 0.6 + f)
    fe = np.exp(-t_(n) / 0.07)
    x = bright * fe + dark * (1 - fe) + sub * o_sin(fr)
    return x * e * vel * 0.42


def i_softbass(f, dur, vel, a=0.02, r=0.3):
    e = adsr(dur, a, 0.4, 0.75, r)
    fr = ftrack(f, len(e))
    x = o_sin(fr) + 0.25 * o_tri(fr) + 0.12 * o_sin(2 * fr)
    return x * e * vel * 0.5


def i_fingerbass(f, dur, vel):
    n = ns(dur + 0.2)
    t = t_(n)
    ph = f * t
    e = (1 - np.exp(-t / 0.004)) * np.exp(-t / 0.7)
    x = np.sin(TAU * ph) + 0.35 * np.sin(2 * TAU * ph) * np.exp(-t / 0.15) \
        + 0.15 * np.sin(3 * TAU * ph) * np.exp(-t / 0.08)
    return damp(x * e, dur, 0.05) * vel * 0.55


def i_musicbox(f, dur, vel, decay=1.4, bright=1.0):
    dec = decay * (523.0 / f) ** 0.35
    n = ns(min(dec * 6, 8.0))
    t = t_(n)
    x = additive(np.full(n, f), [(1, 1.0, dec), (2, 0.06, dec * 0.5), (4.07, 0.22 * bright, dec * 0.12),
                                 (6.3, 0.08 * bright, 0.06), (9.6, 0.05 * bright, 0.025)])
    x += hp(noise(n), 3000) * np.exp(-t / 0.0015) * 0.04 * bright
    return fin(x * att(n, 0.0012)) * vel * 0.42


def i_marimba(f, dur, vel):
    dec = float(np.clip(0.45 * (262.0 / f) ** 0.6, 0.12, 1.2))
    n = ns(dec * 5)
    t = t_(n)
    x = additive(np.full(n, f), [(1, 1.0, dec), (3.93, 0.32, dec * 0.22), (9.2, 0.08, 0.025), (2.0, 0.04, dec * 0.4)])
    x += lp(noise(n), 2500) * np.exp(-t / 0.003) * 0.15
    return fin(x * att(n, 0.0015)) * vel * 0.45


def i_steel(f, dur, vel):
    dec = float(np.clip(0.9 * (440.0 / f) ** 0.3, 0.3, 1.5))
    n = ns(dec * 4)
    fr = ftrack(f, n, bend=(0.25, 0.025))
    x = additive(fr, [(1, 1.0, dec), (2.0, 0.55, dec * 0.55), (3.0, 0.22, dec * 0.3),
                      (4.01, 0.12, dec * 0.18), (5.03, 0.06, 0.08)])
    x = damp(x * att(n, 0.002), dur + 0.35, 0.25)
    return x * vel * 0.33


def i_bell(f, dur, vel, ratio=3.5, index=2.5, decay=2.0):
    n = ns(min(decay * 4.5, 8))
    t = t_(n)
    idx = index * min(1.0, 1500.0 / f) * np.exp(-t / (decay * 0.3))
    x = np.sin(TAU * f * t + idx * np.sin(TAU * f * ratio * t)) * np.exp(-t / decay)
    return fin(x * att(n, 0.002)) * vel * 0.35


def i_metallo(f, dur, vel, decay=1.4, ombak=3.0, bright=1.0, mute=None):
    n = ns(min(decay * 4.5, 7.0))
    t = t_(n)
    parts = [(1, 1.0, decay), (2.76, 0.3 * bright, decay * 0.3), (5.40, 0.12 * bright, decay * 0.1),
             (8.93, 0.05 * bright, 0.05)]
    x = 0.5 * additive(np.full(n, f - ombak / 2), parts) + 0.5 * additive(np.full(n, f + ombak / 2), parts)
    x += bp(noise(n), 2000, 6000) * np.exp(-t / 0.003) * 0.08 * bright
    x = fin(x * att(n, 0.001))
    if mute is not None:
        x = damp(x, dur * mute, 0.12)
    return x * vel * 0.45


def i_gong(f, dur, vel, decay=6.0, beat=0.9, thud=0.3):
    n = ns(min(decay * 5, 16))
    t = t_(n)
    fr = f * (1 + 0.015 * np.exp(-t / 0.4))
    x = additive(fr, [(1, 1.0, decay), (1.0 + beat / f, 0.7, decay), (2.0, 0.28, decay * 0.5),
                      (2.92, 0.18, decay * 0.3), (4.15, 0.08, decay * 0.15), (5.4, 0.05, decay * 0.08)])
    x += lp(noise(n), 400) * np.exp(-t / 0.05) * thud
    return fin(x * att(n, 0.012)) * vel * 0.4


def i_ketuk(f, dur, vel):
    n = ns(0.5)
    t = t_(n)
    x = np.sin(TAU * f * t) * np.exp(-t / 0.09) + lp(noise(n), 600) * np.exp(-t / 0.01) * 0.4
    return fin(x * att(n, 0.001)) * vel * 0.4


def i_pluck(f, dur, vel, decay=1.5, pos=0.2, bright=1.0, nh=30, rel=0.15, B=0.00008):
    dec0 = float(np.clip(decay * (196.0 / f) ** 0.4, 0.15, 5.0))
    n = ns(dec0 * 4)
    t = t_(n)
    x = np.zeros(n)
    for k in range(1, nh + 1):
        fk = k * f * np.sqrt(1 + B * k * k)
        if fk > 0.45 * SR:
            break
        a = abs(np.sin(np.pi * k * pos)) / k ** (1.4 - 0.4 * bright)
        dk = dec0 / (1 + 0.25 * (k - 1) ** 1.3 / bright)
        x += a * np.sin(TAU * fk * t) * np.exp(-t / dk)
    x += hp(noise(n), 1500) * np.exp(-t / 0.004) * 0.05 * bright
    x = x / (np.max(np.abs(x)) + 1e-9)
    x = damp(x * att(n, 0.0008), dur, rel)
    return x * vel * 0.45


def i_piano(f, dur, vel, decay=2.5, rel=0.35):
    dec0 = float(np.clip(decay * (262.0 / f) ** 0.5, 0.4, 6.0))
    n = ns(dec0 * 3)
    t = t_(n)
    Bc = 0.0004 * (f / 262.0) ** 0.5
    x = np.zeros(n)
    for k in range(1, 17):
        fk = k * f * np.sqrt(1 + Bc * k * k)
        if fk * 1.001 > 0.45 * SR:
            break
        a = 1.0 / k ** (1.7 - 0.6 * vel)
        dk = dec0 / (1 + 0.4 * (k - 1))
        env = 0.7 * np.exp(-t / (dk * 0.35)) + 0.3 * np.exp(-t / dk)
        x += a * 0.5 * (np.sin(TAU * fk * t) + np.sin(TAU * fk * 1.0007 * t + 0.3)) * env
    x += lp(noise(n), 3000) * np.exp(-t / 0.006) * 0.08
    x = x / (np.max(np.abs(x)) + 1e-9)
    return damp(x * att(n, 0.001), dur, rel) * vel * 0.45


def i_organ(f, dur, vel, a=0.01, r=0.08):
    bars = ((0.5, 0.6), (1, 1.0), (1.5, 0.5), (2, 0.7), (3, 0.35), (4, 0.4), (6, 0.15), (8, 0.2))
    e = adsr(dur, a, 0.05, 1.0, r)
    n = len(e)
    t = t_(n)
    warp = np.cumsum(1 + 0.0025 * np.sin(TAU * 6.2 * t)) / SR
    x = np.zeros(n)
    tot = 0.0
    for ratio, amp in bars:
        if f * ratio > 0.45 * SR:
            continue
        x += amp * np.sin(TAU * f * ratio * warp + RNG.random())
        tot += amp
    x /= tot
    x = x * (1 + 0.08 * np.sin(TAU * 6.2 * t)) + hp(noise(n), 2000) * np.exp(-t / 0.004) * 0.25
    return x * e * vel * 0.5


def i_brass(f, dur, vel, a=0.03, r=0.12):
    e = adsr(dur, a, 0.2, 0.75, r)
    n = len(e)
    fr = ftrack(f, n, (5.3, 0.12, 0.25), bend=(-0.6, 0.03))
    raw = o_saw(fr) + o_saw(fr * 1.003)
    bright = lp(raw, min(f * 7, 9000))
    dark = lp(raw, f * 2.0)
    fe = np.exp(-t_(n) / 0.25) * 0.6 + 0.4 * e
    x = bright * fe + dark * (1 - fe)
    return x * e * vel * 0.3


def i_whistle(f, dur, vel, breath=0.05):
    e = adsr(dur, 0.08, 0.2, 0.85, 0.25)
    n = len(e)
    fr = ftrack(f, n, (5.2, 0.22, 0.25), bend=(-0.5, 0.05))
    ph = np.cumsum(fr) / SR
    x = np.sin(TAU * ph) + 0.06 * np.sin(2 * TAU * ph) + breath * bp(noise(n), f * 0.8, f * 1.3) * 4
    return x * e * vel * 0.4


def i_suling(f, dur, vel):
    e = adsr(dur, 0.06, 0.25, 0.8, 0.2)
    n = len(e)
    fr = ftrack(f, n, (5.6, 0.3, 0.3), bend=(-1.0, 0.04))
    ph = np.cumsum(fr) / SR
    x = np.sin(TAU * ph) + 0.12 * np.sin(2 * TAU * ph) + 0.04 * np.sin(3 * TAU * ph)
    x += 0.35 * bp(noise(n), f * 0.7, f * 1.6) * (0.4 + 0.6 * np.exp(-t_(n) / 0.08))
    return x * e * vel * 0.4


def i_chirp(f, dur, vel, up=1.6):
    n = ns(dur)
    t = t_(n)
    fr = f * up ** (t / dur) * (1 + 0.04 * np.sin(TAU * 28 * t))
    env = np.sin(np.pi * t / dur) ** 2
    return o_sin(fr) * env * vel * 0.3


def i_cricket(f, dur, vel, pulses=4, rate=32.0):
    n = ns(pulses / rate + 0.02)
    t = t_(n)
    env = np.zeros(n)
    w = ns(0.55 / rate)
    win = np.hanning(w)
    for k in range(pulses):
        i = ns(k / rate)
        env[i:i + w] += win[:len(env[i:i + w])] * (0.8 + 0.2 * RNG.random())
    return np.sin(TAU * f * t) * env * vel * 0.3


# --- drums (inst signature kept: f, dur, vel) ----------------------------------------
def d_kick(f, dur, vel, f0=52, punch=115, dec=0.32):
    n = ns(dec * 4.5)
    t = t_(n)
    fr = f0 + punch * np.exp(-t / 0.035)
    x = np.sin(TAU * np.cumsum(fr) / SR) * np.exp(-t / dec)
    x += lp(noise(n), 3000) * np.exp(-t / 0.003) * 0.25
    return fin(np.tanh(1.6 * x)) * vel * 0.8


def d_snare(f, dur, vel, tone=185, dec=0.13, snap=1.0):
    n = ns(0.4)
    t = t_(n)
    body = np.sin(TAU * np.cumsum(tone * (1 + 0.4 * np.exp(-t / 0.01))) / SR) * np.exp(-t / 0.06) * 0.6
    nz = bp(noise(n), 1200, 9000) * np.exp(-t / dec) * snap
    return fin(body + nz) * vel * 0.5


def d_hat(f, dur, vel, dec=0.035):
    n = ns(dec * 7)
    t = t_(n)
    metal = sum(o_sq(np.full(n, fm), 0.5) for fm in (2052, 2879, 3407, 4580, 5612, 7187))
    x = hp(noise(n) + 0.5 * metal, 7000) * np.exp(-t / dec)
    return fin(x) * vel * 0.3


def d_ohat(f, dur, vel):
    return d_hat(f, dur, vel, dec=0.2) * 0.8


def d_crash(f, dur, vel, dec=1.4):
    n = ns(dec * 3)
    t = t_(n)
    metal = sum(o_sq(np.full(n, fm), 0.5) for fm in (1453, 2271, 3311, 4637, 5873, 7333))
    x = hp(noise(n), 3500) * np.exp(-t / dec) + 0.3 * hp(metal, 3000) * np.exp(-t / (dec * 0.6))
    return fin(x * att(n, 0.002)) * vel * 0.3


def d_tom(f, dur, vel, dec=0.25):
    n = ns(dec * 3)
    t = t_(n)
    fr = f * (1 + 0.5 * np.exp(-t / 0.02))
    x = np.sin(TAU * np.cumsum(fr) / SR) * np.exp(-t / dec) + lp(noise(n), 2500) * np.exp(-t / 0.01) * 0.2
    return fin(x) * vel * 0.6


def d_shaker(f, dur, vel):
    n = ns(0.1)
    t = t_(n)
    env = (1 - np.exp(-t / 0.006)) * np.exp(-t / 0.025)
    return fin(bp(noise(n), 4000, 11000) * env) * vel * 0.3


def d_clave(f, dur, vel, fc=2500):
    n = ns(0.09)
    t = t_(n)
    x = np.sin(TAU * fc * t) * np.exp(-t / 0.018) + 0.3 * np.sin(TAU * 1.62 * fc * t) * np.exp(-t / 0.01)
    return fin(x) * vel * 0.4


def d_conga(f, dur, vel):
    n = ns(0.5)
    t = t_(n)
    fr = f * (1 + 0.15 * np.exp(-t / 0.015))
    x = np.sin(TAU * np.cumsum(fr) / SR) * np.exp(-t / 0.16) + bp(noise(n), 800, 4000) * np.exp(-t / 0.008) * 0.3
    return fin(x) * vel * 0.5


def d_wood(f, dur, vel):
    n = ns(0.12)
    t = t_(n)
    x = np.sin(TAU * f * t) * np.exp(-t / 0.022) + 0.4 * np.sin(TAU * 2.7 * f * t) * np.exp(-t / 0.01)
    x += hp(noise(n), 3000) * np.exp(-t / 0.0015) * 0.3
    return fin(x) * vel * 0.45


def d_taiko(f, dur, vel, base=62, dec=0.9):
    n = ns(dec * 3)
    t = t_(n)
    fr = base * (1 + 0.6 * np.exp(-t / 0.03))
    x = np.sin(TAU * np.cumsum(fr) / SR) * np.exp(-t / dec)
    x += lp(noise(n), 800) * np.exp(-t / 0.08) * 0.5 + bp(noise(n), 400, 2000) * np.exp(-t / 0.02) * 0.3
    return fin(np.tanh(1.4 * x)) * vel * 0.9


def d_timp(f, dur, vel, dec=1.3):
    n = ns(dec * 3)
    t = t_(n)
    x = additive(np.full(n, f), [(1, 1.0, dec), (1.5, 0.5, dec * 0.6), (1.98, 0.35, dec * 0.4), (2.44, 0.2, dec * 0.3)])
    x += lp(noise(n), 1000) * np.exp(-t / 0.02) * 0.5
    return fin(x * att(n, 0.002)) * vel * 0.55


def k_dhe(f, dur, vel):
    n = ns(0.6)
    t = t_(n)
    fr = 88 + 30 * (1 - np.exp(-t / 0.05))
    x = np.sin(TAU * np.cumsum(fr) / SR) * np.exp(-t / 0.22) + lp(noise(n), 500) * np.exp(-t / 0.015) * 0.4
    return fin(x) * vel * 0.65


def k_tak(f, dur, vel):
    n = ns(0.12)
    t = t_(n)
    x = bp(noise(n), 1500, 5000) * np.exp(-t / 0.012) * 1.3 + 0.5 * np.sin(TAU * 420 * t) * np.exp(-t / 0.02)
    return fin(x) * vel * 0.45


def k_tung(f, dur, vel):
    n = ns(0.4)
    t = t_(n)
    fr = 230 * (1 + 0.1 * np.exp(-t / 0.02))
    return fin(np.sin(TAU * np.cumsum(fr) / SR) * np.exp(-t / 0.13)) * vel * 0.45


def k_ket(f, dur, vel):
    n = ns(0.06)
    t = t_(n)
    return fin(bp(noise(n), 800, 2500) * np.exp(-t / 0.008) * 1.5) * vel * 0.35


# =====================================================================================
# song container
# =====================================================================================
class Song:
    def __init__(self, bpm, beats, loop=True, tail=6.0, t60=2.0, bright=0.5, pre=0.02, max_len=None, drive=1.3):
        self.bpm = bpm
        self.spb = 60.0 / bpm
        self.beats = beats
        self.loop = loop
        self.L = int(round(beats * self.spb * SR))
        self.N = self.L + ns(tail)
        self.dry = np.zeros(self.N)
        self.wet = np.zeros(self.N)
        self.post = []
        self.t60, self.bright, self.pre = t60, bright, pre
        self.parts = []
        self.max_len = max_len
        self.drive = drive

    def sec(self, beat):
        return beat * self.spb

    @staticmethod
    def _assemble(placed, min_len):
        """placed: [(start_index, signal)] -> buffer long enough for every signal (nothing is cut)."""
        end = max([min_len] + [i + len(sg) for i, sg in placed])
        buf = np.zeros(end)
        for i, sg in placed:
            buf[i:i + len(sg)] += sg
        return buf

    def add(self, events, inst, gain=1.0, rev=0.2, echo=None, lpf=None, hpf=None, hum=0.003, vj=0.05,
            name='', **kw):
        placed = []
        for (b, f, d, v) in events:
            vv = v * (1 + vj * RNG.uniform(-1, 1))
            sig = fin(inst(f, d * self.spb, vv, **kw))
            jit = RNG.uniform(-1, 1) * hum * SR if b > 0 else 0.0
            placed.append((max(int(round(b * self.spb * SR + jit)), 0), sig))
        self._bus(self._assemble(placed, self.N), gain, rev, echo, lpf, hpf, name or getattr(inst, '__name__', '?'))

    def add_sig(self, sig, beat=0.0, gain=1.0, rev=0.2, echo=None, lpf=None, hpf=None, name='sig'):
        part = self._assemble([(int(round(beat * self.spb * SR)), sig)], self.N)
        self._bus(part, gain, rev, echo, lpf, hpf, name)

    def _bus(self, part, gain, rev, echo, lpf, hpf, name):
        if echo:   # room for the echo repeats to die away (fb^k < -60 dB)
            d, fb, mix = echo
            k = int(np.ceil(np.log(1e-3) / np.log(max(fb, 1e-3)))) + 1
            part = np.concatenate([part, np.zeros(ns(d * self.spb * k))])
        if lpf:
            part = lp(part, lpf)
        if hpf:
            part = hp(part, hpf)
        part = part * gain
        if echo:
            part = part + mix * echo_fx(part, d * self.spb, fb)
        n = len(part)
        if n > len(self.dry):
            self.dry = np.concatenate([self.dry, np.zeros(n - len(self.dry))])
            self.wet = np.concatenate([self.wet, np.zeros(n - len(self.wet))])
        self.dry[:n] += part
        self.wet[:n] += part * rev
        self.parts.append((name, rms(part)))

    def add_post(self, layer, rel_db):
        """Periodic ambient layer (length L), level relative to the music RMS."""
        assert len(layer) == self.L
        self.post.append((layer, rel_db))

    def render(self):
        ir = make_ir(self.t60, self.bright, self.pre)
        wet = ss.fftconvolve(self.wet, ir)
        out = np.zeros(len(wet))
        out[:len(self.dry)] += self.dry
        out += wet
        out = hp(out, 28)
        if self.loop:
            y = np.zeros(self.L)
            for k in range(0, len(out), self.L):
                seg = out[k:k + self.L]
                y[:len(seg)] += seg
            ref = rms(y)
            for layer, rel in self.post:
                y += layer / rms(layer) * ref * 10 ** (rel / 20)
            y -= y.mean()
            return master(y, drive=self.drive)
        y = out
        a = np.abs(y)
        idx = np.nonzero(a > a.max() * 10 ** (-60 / 20))[0]
        end = idx[-1] + 1 if len(idx) else len(y)
        y = y[:min(len(y), end + ns(0.05))]
        if self.max_len:
            y = cap(y, self.max_len, 1.2)
        y = master(y, drive=self.drive)
        k = ns(0.003)
        y[:k] *= np.linspace(0, 1, k)
        return fin(y, 0.03)


# =====================================================================================
# MUSIC
# =====================================================================================
TITLE_MEL = ("F5:1 E5:.5 D5:.5 A5:1 | Bb5:2 A5:1 | G5:1 F5:.5 E5:.5 D5:1 | E5:1 C#5:1 A4:1 | "
             "F5:1 E5:.5 D5:.5 A5:1 | C6:2 A5:1 | Bb5:1 A5:.5 G5:.5 F5:1 | E5:3 | "
             "D5:1 F5:1 Bb5:1 | C6:1.5 Bb5:.5 A5:.5 G5:.5 | A5:2 F5:1 | D6:2 A5:1 | "
             "Bb5:1 A5:.5 G5:.5 D5:1 | F5:1.5 E5:.5 D5:1 | D5:1 E5:1 F5:1 | E5:2 C#5:1")


def song_title():
    ch = ['Dm', 'Bb', 'Gm', 'A', 'Dm', 'F', 'Gm', 'A', 'Bb', 'C', 'F', 'Dm', 'Gm', 'Dm', 'Bb', 'A']
    S = Song(64, 48, tail=7, t60=2.8)
    T = timeline(ch, 3)
    S.add(mel(TITLE_MEL, bpb=3, vel=0.85), i_musicbox, gain=1.0, rev=0.35, echo=(1.5, 0.3, 0.22), name='musicbox')
    S.add(pad_ev(T, low=50, vel=0.6), i_strings, gain=0.55, rev=0.5, a=0.7, r=1.4, cut=1800, name='strings')
    S.add(bass_ev(T, [(0, 0, 2.9, 1.0)], low=38), i_softbass, gain=0.6, rev=0.15, a=0.08, r=0.6, name='bass')
    harp = arp_ev(T[:8], [0, 2, 4], 1.0, low=50, vel=0.5) + \
        arp_ev(T[8:], [0, 2, 4, 5, 4, 2], 0.5, low=50, vel=0.42, accents=[1, .7, .8, .7, .8, .7])
    S.add(harp, i_pluck, gain=0.7, rev=0.35, decay=1.3, bright=0.6, rel=0.4, name='harp')
    # soft high counter-line in the second half
    S.add(mel("r:3 | r:3 | r:3 | r:3 | r:3 | r:3 | r:3 | r:3 | F6:3 | E6:3 | C6:3 | F6:3 | "
              "D6:3 | A5:3 | Bb5:1.5 C6:1.5 | C#6:3", bpb=3, vel=0.4),
          i_strings, gain=0.35, rev=0.55, a=0.5, r=1.0, cut=3500, voices=2, name='violin')
    return S.render()


def song_ending():
    ch = ['Dm', 'Bb', 'Gm', 'A', 'Dm', 'F', 'Gm', 'A', 'Bb', 'C', 'F', 'D', 'Gm', 'F', 'Bbmaj7', 'A7']
    S = Song(60, 48, tail=8, t60=3.2)
    T = timeline(ch, 3)
    melody = mel(TITLE_MEL, bpb=3, vel=0.8)
    S.add(melody, i_musicbox, gain=1.0, rev=0.45, echo=(1.5, 0.35, 0.25), decay=1.8, name='musicbox')
    S.add(shift([e for e in melody if e[0] >= 24], semis=12, velmul=0.35), i_bell, gain=0.5, rev=0.6,
          ratio=3.0, index=0.8, decay=1.5, name='celesta')
    S.add(arp_ev(T, [0, 2, 4, 5, 4, 2], 0.5, low=50, vel=0.42, accents=[1, .6, .75, .6, .75, .6]),
          i_musicbox, gain=0.6, rev=0.45, decay=1.0, bright=0.5, name='mb-arp')
    S.add(pad_ev(T, low=50, vel=0.45), i_pad, gain=0.6, rev=0.5, a=1.2, r=2.0, name='pad')
    S.add(bass_ev(T, [(0, 0, 2.9, 1.0)], low=38), i_softbass, gain=0.5, rev=0.2, a=0.1, r=0.8, name='bass')
    return S.render()


def song_memory():
    ch = ['Fmaj7', 'Em7', 'Dm7', 'Bbmaj7', 'Fmaj7', 'Am7', 'Bbmaj7', ('Csus4', 2), ('C', 2)]
    S = Song(60, 32, tail=9, t60=4.5, bright=0.7)
    T = timeline(ch, 4)
    m = mel("A5:1 G5:.5 F5:.5 C6:2 | B5:2 G5:1 E5:1 | F5:1 E5:.5 D5:.5 A5:2 | D6:2 A5:2 | "
            "A5:1 G5:.5 F5:.5 C6:2 | E6:2 C6:1 G5:1 | F5:1 A5:1 D6:1 C6:1 | G5:3 r:1", bpb=4, vel=0.75)
    S.add(m, i_musicbox, gain=1.0, rev=0.75, echo=(0.75, 0.45, 0.35), decay=2.0, name='musicbox')
    S.add(arp_ev(T, [0, 2, 1, 3, 2, 4, 3, 5], 0.5, low=60, vel=0.35), i_musicbox, gain=0.55, rev=0.8,
          decay=1.2, bright=0.4, name='mb-arp')
    S.add(pad_ev(T, low=53, vel=0.5), i_strings, gain=0.45, rev=0.7, a=1.5, r=2.5, cut=1500, name='pad')
    S.add(pad_ev(T, low=65, vel=0.35), i_pad, gain=0.4, rev=0.8, a=2.0, r=2.5, name='glass')
    S.add(bass_ev(T, [(0, 0, 3.9, 1.0)], low=36), i_softbass, gain=0.4, rev=0.3, a=0.4, r=1.5, name='bass')
    return S.render()


def song_beach():
    intro = ['Gmaj7', 'Em7', 'Cmaj7', 'Cm6']
    A = ['Gmaj7', 'Em7', 'Cmaj7', 'D7', 'Gmaj7', 'Em7', 'Cm6', 'D7b9']
    B = ['Am7', 'Bm7', 'Cmaj7', 'Cm6', 'Bm7', 'E7b9', 'Am7', 'Ab7#11']
    ch = intro + A + B
    S = Song(100, 80, tail=5, t60=1.6)
    T = timeline(ch, 4)
    lead = mel("r:.5 D5:.5 G5:.5 A5:.5 B5:1 A5:.5 G5:.5 | E5:2 r:.5 D5:.5 E5:.5 G5:.5 | "
               "E5:1 D5:.5 B4:.5 C5:1.5 E5:.5 | F#5:1.5 E5:.5 D5:2 | "
               "r:.5 D5:.5 G5:.5 A5:.5 B5:1 D6:.5 B5:.5 | A5:2 r:.5 G5:.5 A5:.5 B5:.5 | "
               "C6:1 Bb5:.5 A5:.5 Eb5:2 | D5:1 Eb5:.5 F#5:.5 A5:1 C6:1 | "
               "C6:1.5 B5:.5 A5:1 E5:1 | D6:1.5 C6:.5 B5:1 F#5:1 | E6:2 D6:.5 B5:.5 G5:1 | "
               "Eb6:2 D6:.5 C6:.5 A5:1 | D6:1 B5:.5 A5:.5 F#5:1 D5:1 | G#5:1.5 F5:.5 E5:1 D5:1 | "
               "C5:1 E5:.5 G5:.5 A5:1 C6:1 | C6:1.5 Bb5:.5 Gb5:1 D5:1", start=16, bpb=4, vel=0.85)
    S.add(lead, i_steel, gain=0.9, rev=0.3, echo=(0.75, 0.28, 0.2), name='steel')
    acc = [1, .55, .6, .95, .55, .6, .9, .55]
    S.add(arp_ev(T, [0, 2, 1, 3, 1, 2, 0, 2], 0.5, low=55, vel=0.6, accents=acc), i_marimba, gain=0.75,
          rev=0.25, name='marimba')
    S.add(arp_ev(T[12:], [None, 4, None, 5, None, 4, 6, None], 0.5, low=55, vel=0.35), i_marimba,
          gain=0.5, rev=0.3, name='marimba-hi')
    S.add(bass_ev(T, [(0, 0, 1.0, 1.0), (1.5, 7, 0.5, 0.7), (2, 0, 1.0, 0.85), (3, 12, 0.5, 0.6),
                      (3.5, 'app', 0.5, 0.75)], low=40), i_fingerbass, gain=0.8, rev=0.08, name='bass')
    S.add(pad_ev(T[12:], low=55, vel=0.4), i_strings, gain=0.3, rev=0.5, a=0.8, r=1.2, cut=1600, name='pad')
    S.add(mel("r:2 B6:2 | r:4 | r:2 G6:1 F#6:1 | Eb6:4", bpb=4, vel=0.5), i_bell, gain=0.45, rev=0.7,
          ratio=3.5, index=1.2, decay=1.8, name='eerie-bell')
    S.add(mel("r:4 | r:4 | r:4 | r:4 | r:4 | r:4 | r:2 Eb7:2 | r:4", start=48, bpb=4, vel=0.35), i_bell,
          gain=0.45, rev=0.7, ratio=3.5, index=1.0, decay=1.6, name='eerie-bell2')
    sh, cl, kk, cg, cg2 = [], [], [], [], []
    for bar in range(20):
        st = bar * 4
        sh += pat("x.o.x.oox.o.x.oo", st)
        cl += pat("x..x..x...x.x...", st)
        if bar >= 4:
            kk += pat("x.......x.....o.", st)
            cg += pat("..o.x...o..xo.x.", st)
            cg2 += pat("......x.......x.", st)
    S.add(sh, d_shaker, gain=0.8, rev=0.1, hum=0.004, name='shaker')
    S.add(cl, d_clave, gain=0.5, rev=0.2, hum=0.002, name='clave')
    S.add(kk, d_kick, gain=0.28, rev=0.05, hum=0.001, name='kick', f0=55, dec=0.25)
    S.add([(b, 330.0, d, v) for b, f, d, v in cg], d_conga, gain=0.45, rev=0.15, name='conga-hi')
    S.add([(b, 220.0, d, v) for b, f, d, v in cg2], d_conga, gain=0.5, rev=0.15, name='conga-lo')
    return S.render()


SL_CENTS = [0, 231, 474, 717, 955]
CIP = {'1': 0, '2': 1, '3': 2, '5': 3, '6': 4}


def sl_hz(deg, base=290.0):
    o, k = divmod(deg, 5)
    return base * 2 ** o * 2 ** (SL_CENTS[k] / 1200.0)


def gtok(tok):
    return CIP[tok[0]] + 5 * tok.count("'") - 5 * tok.count(',')


def song_village():
    gongans = ["6 5 3 2 5 3 2 1 2 3 5 6 5 3 2 6",
               "1 6 1 2 3 5 3 2 6 5 3 2 1 2 1 6",
               "3 5 6 1' 6 5 6 3 5 6 1' 2' 1' 6 5 6",
               "2 3 5 6 5 3 2 1 6, 1 2 3 2 1 2 6"]
    bal = [gtok(x) for g in gongans for x in g.split()]
    S = Song(80, 64, tail=9, t60=2.2)
    saron, demung, peking, bonang, panerus = [], [], [], [], []
    for i, d in enumerate(bal):
        saron.append((i, sl_hz(d, 290), 1, 0.8 if i % 2 else 0.65))
        if i % 2 == 1:
            demung.append((i, sl_hz(d, 145), 2, 0.8))
        if i % 2 == 0:
            a, b = bal[i], bal[i + 1]
            for k, dd in enumerate([a, a, b, b]):
                peking.append((i + 0.5 * k, sl_hz(dd, 580), 0.5, 0.5 if k % 2 else 0.6))
        if i >= 16:
            tgt = bal[i | 1]
            fig_b = [tgt + 1, tgt]
            fig_p = [tgt + 2, tgt + 1]
            for k in range(2):
                bonang.append((i + 0.5 * k, sl_hz(fig_b[k], 580), 0.5, 0.5))
                panerus.append((i + 0.5 * k + 0.25, sl_hz(fig_p[k], 580), 0.25, 0.4))
    S.add(saron, i_metallo, gain=0.85, rev=0.3, decay=1.0, mute=1.1, name='saron')
    S.add(demung, i_metallo, gain=0.7, rev=0.3, decay=1.8, bright=0.6, name='demung')
    S.add(peking, i_metallo, gain=0.45, rev=0.3, decay=0.6, ombak=4.0, name='peking')
    S.add(bonang, i_metallo, gain=0.4, rev=0.3, decay=0.5, ombak=2.0, bright=0.5, name='bonang')
    S.add(panerus, i_metallo, gain=0.33, rev=0.3, decay=0.4, ombak=2.5, bright=0.5, name='panerus')
    gong, kempul, kenong, ketuk = [], [], [], []
    for g in range(4):
        st = g * 16
        gong.append((st, sl_hz(4, 290) / 8, 4, 1.0))
        kempul.append((st + 8, sl_hz(bal[st + 7], 290) / 4, 2, 0.8))
        for k in (4, 8, 12, 16):
            kenong.append(((st + k) % 64, sl_hz(bal[(st + k - 1) % 64], 290), 2, 0.6))
        for k in (2, 6, 10, 14):
            ketuk.append((st + k, 200.0, 0.5, 0.6))
    S.add(gong, i_gong, gain=0.8, rev=0.35, decay=6.0, beat=0.8, name='gong')
    S.add(kempul, i_gong, gain=0.6, rev=0.3, decay=3.0, beat=1.6, thud=0.15, name='kempul')
    S.add(kenong, i_gong, gain=0.35, rev=0.3, decay=2.0, beat=2.2, thud=0.05, name='kenong')
    S.add(ketuk, i_ketuk, gain=0.6, rev=0.2, name='ketuk')
    # kendang
    norm_p = "D...t.D.T..tD.T."
    fill_p = "D.tTD.tTDtTtD.DD"
    strokes = {'D': [], 'T': [], 't': [], 'k': []}
    for blk in range(16):
        p = fill_p if blk % 4 == 3 else norm_p
        for i, c in enumerate(p):
            if c in strokes:
                strokes[c].append((blk * 4 + i * 0.25, 0.0, 0.25, 0.85 if i % 4 == 0 else 0.65))
        strokes['k'] += pat("..x...x...x...x.", blk * 4, vmap={'x': 0.4})
    S.add(strokes['D'], k_dhe, gain=0.7, rev=0.15, name='kendang-dhe')
    S.add(strokes['T'], k_tak, gain=1.0, rev=0.15, name='kendang-tak')
    S.add(strokes['t'], k_tung, gain=0.5, rev=0.15, name='kendang-tung')
    S.add(strokes['k'], k_ket, gain=0.35, rev=0.1, name='kendang-ket')
    # suling over the second half
    sul = "5:2 6:1 1':1 6:3 5:1 3:2 5:1 3:1 2:4 3:1 5:1 6:2 1':3 2':1 1':1 6:1 5:1 3:1 5:2 6:2"
    ev = []
    b = 32.0
    for tok in sul.split():
        p, d = tok.split(':')
        ev.append((b, sl_hz(gtok(p), 580), float(d), 0.7))
        b += float(d)
    S.add(ev, i_suling, gain=0.55, rev=0.4, echo=(0.75, 0.25, 0.15), name='suling')
    return S.render()


def song_steppe():
    ch = ['Em', 'Em', 'C', 'B7', 'Am', 'Em', 'F', 'B7', 'Em', 'D', 'C', 'B7']
    S = Song(72, 48, tail=5, t60=1.1, bright=0.3)
    T = timeline(ch, 4)
    S.add(bass_ev(T, [(0, 0, 2.5, 1.0), (2.5, 7, 1.5, 0.6)], low=40), i_pluck, gain=0.6, rev=0.12,
          decay=2.2, bright=0.7, rel=0.3, name='guitar-bass')
    S.add(arp_ev(T, [None, None, 't', 1, None, 't', 0, 1], 0.5, low=55, vel=0.5,
                 accents=[1, 1, .9, .7, 1, .8, .7, .6]), i_pluck, gain=0.8, rev=0.15, decay=1.8,
          bright=1.0, rel=0.3, name='guitar')
    S.add(mel("E5:3 C5:.5 D5:.5 | B4:4 | C5:2 A4:1 F4:1 | F#4:2 D#5:1 B4:1 | "
              "G5:2 F#5:.5 E5:.5 B4:1 | A5:3 F#5:1 | G5:2 E5:1 C5:1 | B4:4", start=16, bpb=4, vel=0.75),
          i_whistle, gain=0.6, rev=0.3, echo=(1.5, 0.3, 0.25), name='whistle')
    S.add(mel("r:4 | r:2 E6:2 | r:4 | r:3 B5:1", bpb=4, vel=0.4), i_pluck, gain=0.5, rev=0.35,
          decay=2.5, bright=0.4, rel=1.0, name='harmonics')
    S.add([(0, 70.0, 1, 0.8), (16, 70.0, 1, 0.6), (32, 70.0, 1, 0.7), (44, 70.0, 1, 0.5)], d_tom,
          gain=0.35, rev=0.4, dec=0.5, name='lone-drum')
    n = S.L
    w1 = pnoise(n, 150, 900) * (0.4 + 0.6 * psmooth(n, 5))
    w2 = pnoise(n, 600, 2500) * (0.3 + 0.7 * psmooth(n, 7)) * 0.4
    wh = pnoise(n, peak=(720, 35)) * psmooth(n, 4) ** 2 * 0.5
    S.add_post(cfilt(w1 + w2 + wh, lambda v: lp(v, 3000, 2)), -14)
    return S.render()


def song_cliff():
    ch = [('Cm', 8), ('Ab', 8), ('Fm', 8), ('Db', 8), ('G', 8)]
    S = Song(60, 40, tail=9, t60=4.0, bright=0.4)
    T = timeline(ch, 4)
    S.add(pad_ev(T, low=43, vel=0.7), i_strings, gain=0.6, rev=0.5, a=1.8, r=2.5, cut=900, name='low-strings')
    S.add(bass_ev(T, [(0, 0, 8, 1.0)], low=36), i_strings, gain=0.55, rev=0.4, a=2.0, r=2.5, cut=500,
          name='contrabass')
    S.add(pad_ev(T[2:], low=55, vel=0.45), i_choir, gain=0.35, rev=0.7, vowel='u', a=2.0, r=2.5,
          name='choir')
    piano = [(1, 'G5'), (2.5, 'Eb5'), (4, 'D5'), (6, 'C5'),
             (9, 'C6'), (10.5, 'Bb5'), (12, 'G5'), (14, 'Eb5'),
             (17, 'Ab5'), (18.5, 'G5'), (20, 'F5'), (22, 'C5'),
             (25, 'F5'), (26, 'Ab5'), (27.5, 'Db6'), (30, 'C6'),
             (33, 'B5'), (34.5, 'D6'), (36, 'F5'), (37.5, 'D5')]
    S.add([(b, mhz(nm(n_)), 2.0, 0.55) for b, n_ in piano], i_piano, gain=0.75, rev=0.8,
          echo=(1.5, 0.3, 0.2), decay=3.0, rel=1.5, name='piano')
    n = S.L
    rain = pnoise(n, 300, 5000, tilt=-0.5) * (0.6 + 0.4 * psmooth(n, 5))
    wind = pnoise(n, 40, 350) * (0.3 + 0.7 * psmooth(n, 4)) * 1.6
    storm = rain * 0.5 + wind
    for st in (11.0, 31.5):
        place_wrap(storm, thunder_sig(4.5, crack=False) * 6.0, ns(st))
    S.add_post(storm, -13)
    return S.render()


def song_farm():
    intro = ['Am', 'Am', 'F', 'E']
    A = ['Am', 'Am', 'F', 'E', 'Dm', 'Am', 'Bb', 'E7']
    B = ['Dm', 'Am', 'Dm', 'E', 'F', 'Bb', 'G#dim7', 'E7']
    ch = intro + A + B
    S = Song(120, 80, tail=5, t60=1.8, bright=0.35)
    T = timeline(ch, 4)
    bass = []
    for name, st, d in T:
        r = root_note(name, 33)
        for j, iv in enumerate([0, 0, 12, 0, 7, 0, 12, 10]):
            bass.append((st + j * 0.5, mhz(r + iv), 0.35, 0.95 if j == 0 else 0.7))
    S.add(bass, i_bass_saw, gain=0.75, rev=0.08, cut=500, name='bass')
    S.add(pad_ev(T, low=48, vel=0.5), i_strings, gain=0.35, rev=0.5, a=1.0, r=1.5, cut=1200, name='pad')
    clock_hi, clock_lo, hats, kick = [], [], [], []
    for bar in range(20):
        st = bar * 4
        clock_hi += [(st, 1900.0, 0.25, 0.8), (st + 2, 1900.0, 0.25, 0.7)]
        clock_lo += [(st + 1, 1250.0, 0.25, 0.7), (st + 3, 1250.0, 0.25, 0.65)]
        hats += pat("x.o.x.o.x.o.x.o.", st, vmap={'x': 0.55, 'o': 0.3})
        if bar >= 4:
            kick += [(st, 0, 0.25, 0.8), (st + 0.5, 0, 0.25, 0.5)]
    S.add(clock_hi, d_wood, gain=0.75, rev=0.15, hum=0.0005, name='tick')
    S.add(clock_lo, d_wood, gain=0.75, rev=0.15, hum=0.0005, name='tock')
    S.add(hats, d_hat, gain=0.5, rev=0.05, hum=0.001, dec=0.02, name='hat')
    S.add(kick, d_kick, gain=0.32, rev=0.05, f0=48, punch=70, dec=0.35, name='heartbeat')
    clar = mel("A3:.5 r:.5 C4:.5 r:.5 B3:.5 Bb3:.5 A3:1 | r:1 E4:.5 r:.5 D#4:.5 E4:.5 r:1 | "
               "F4:.5 r:.5 E4:.5 r:.5 D4:.5 C4:.5 A3:1 | G#3:2 B3:1 r:1 | "
               "D4:.5 r:.5 F4:.5 r:.5 E4:.5 Eb4:.5 D4:1 | r:1 A4:.5 r:.5 G#4:.5 A4:.5 r:1 | "
               "Bb4:1 A4:.5 F4:.5 D4:1 Bb3:1 | G#3:1 B3:1 D4:1 F4:1", start=16, bpb=4, vel=0.8, tr=12)
    clar2 = mel("F4:1 E4:.5 D4:.5 C4:1 A3:1 | Bb3:1 D4:1 F4:1 Bb4:1 | B4:1 G#4:1 F4:1 D4:1 | "
                "E4:2 G#3:1 B3:1", start=64, bpb=4, vel=0.75, tr=12)
    S.add(clar + clar2, i_clar, gain=0.7, rev=0.3, echo=(0.75, 0.25, 0.15), name='clarinet')
    S.add(arp_ev(T[12:], [0, None, 2, None, 1, None, 2, 1], 0.5, low=57, vel=0.55), i_pluck, gain=0.45,
          rev=0.25, decay=0.35, bright=0.5, rel=0.05, name='pizz')
    S.add(mel("E6:16 | F6:16", start=48, vel=0.35), i_strings, gain=0.3, rev=0.6, a=2.0, r=1.0,
          cut=5000, voices=2, trem=0.6, name='hi-trem')
    return S.render()


BATTLE_MEL = ("C5:.5 D5:.5 Eb5:.5 G5:1.5 F5:.5 Eb5:.5 | Eb5:1.5 C5:.5 Ab4:2 | "
              "D5:.5 Eb5:.5 F5:.5 Bb5:1.5 Ab5:.5 G5:.5 | G5:3 r:1 | "
              "C5:.5 D5:.5 Eb5:.5 G5:1.5 F5:.5 Eb5:.5 | Ab5:1.5 G5:.5 F5:1 Eb5:1 | "
              "D5:1 F5:1 Bb5:1 D6:1 | B5:2 G5:.5 B5:.5 D6:1 | "
              "C6:1.5 Bb5:.5 Ab5:1 Eb5:1 | D6:1.5 C6:.5 Bb5:1 F5:1 | Bb5:1 D6:1 G6:1.5 F6:.5 | "
              "Eb6:2 D6:1 C6:1 | Ab5:1.5 G5:.5 F5:1 C6:1 | D6:1.5 C6:.5 Bb5:1 D6:1 | "
              "Eb6:1 D6:.5 C6:.5 Bb5:1 G5:1 | B5:.5 C6:.5 D6:.5 F6:.5 G6:2 | "
              "C6:3 Eb6:.5 D6:.5 | D6:3 F6:.5 Eb6:.5 | F6:2 D6:1 B5:1 | "
              "D6:.5 C6:.5 B5:.5 Ab5:.5 G5:.5 F5:.5 D5:.5 B4:.5")


def song_battle():
    A = ['Cm', 'Ab', 'Bb', 'Cm', 'Cm', 'Ab', 'Bb', 'G7']
    B = ['Ab', 'Bb', 'Gm', 'Cm', 'Fm', 'Bb', 'Eb', 'G7']
    C = ['Ab', 'Bb', 'Bdim7', 'G7']
    ch = A + B + C
    S = Song(150, 80, tail=4, t60=1.3)
    T = timeline(ch, 4)
    lead = mel(BATTLE_MEL, bpb=4, vel=0.9)
    S.add(lead, i_square, gain=0.8, rev=0.18, echo=(0.75, 0.22, 0.15), duty=0.25, vib=(6.0, 0.18, 0.15),
          name='lead')
    S.add(shift([e for e in lead if e[0] >= 32], semis=-12, velmul=0.6), i_square, gain=0.45, rev=0.15,
          duty=0.5, cut=3000, name='lead-low')
    bass = []
    for k, (name, st, d) in enumerate(T):
        r = root_note(name, 36)
        ivs = [0, 12, 0, 12, 10, 7, 5, 3] if k % 4 == 3 else [0, 12] * 4
        for j, iv in enumerate(ivs):
            bass.append((st + j * 0.5, mhz(r + iv), 0.45, 1.0 if j % 2 == 0 else 0.75))
    S.add(bass, i_bass_saw, gain=0.8, rev=0.05, cut=800, name='bass')
    S.add(pad_ev(T, low=53, vel=0.55), i_strings, gain=0.35, rev=0.3, a=0.08, r=0.3, cut=2500, name='strings')
    S.add(arp_ev(T[8:], [0, 1, 2, 3, 4, 5, 6, 5, 4, 3, 2, 1, 2, 3, 4, 5], 0.25, low=60, vel=0.45),
          i_square, gain=0.7, rev=0.2, duty=0.125, a=0.002, d=0.05, s=0.3, r=0.03, vib=None, name='arp')
    kick, snare, hats, ohat, crash, toms = [], [], [], [], [], []
    for bar in range(20):
        st = bar * 4
        fill = bar % 4 == 3
        kick += pat("x.....x.x.....x." if not fill else "x.....x.x.x.....", st)
        snare += pat("....x.......x..." if not fill else "....x..gx.x.xxXX", st, vmap={'x': .8, 'X': 1., 'g': .3})
        hats += pat("x.x.x.x.x.x.x..." if not fill else "x.x.x.x.x.......", st)
        if not fill:
            ohat += [(st + 3.5, 0, 0.5, 0.5)]
        if bar in (0, 8, 16):
            crash.append((st, 0, 1, 0.9))
        if fill:
            toms += [(st + 2.5, 220.0, .25, .8), (st + 3.0, 180.0, .25, .85), (st + 3.25, 150.0, .25, .9),
                     (st + 3.5, 120.0, .25, .9), (st + 3.75, 100.0, .25, 1.0)]
    S.add(kick, d_kick, gain=0.5, rev=0.05, hum=0.0, name='kick')
    S.add(snare, d_snare, gain=0.6, rev=0.15, hum=0.001, name='snare')
    S.add(hats, d_hat, gain=0.35, rev=0.05, hum=0.001, name='hat')
    S.add(ohat, d_ohat, gain=0.3, rev=0.05, name='ohat')
    S.add(crash, d_crash, gain=0.45, rev=0.2, name='crash')
    S.add(toms, d_tom, gain=0.55, rev=0.15, name='toms')
    return S.render()


def song_boss():
    intro = ['Em', 'F', 'Em', 'D#dim7']
    A = ['Em', 'C', 'Am', 'B7', 'Em', 'C', 'F', 'B7']
    B = ['Am', 'Bdim', 'C', 'D#dim7', 'Em', 'Cm', 'F', 'B7']
    C = ['Em', 'Fm', 'Em', 'Fm', 'C', 'D#dim7', 'B7', 'B7']
    ch = intro + A + B + C
    S = Song(168, 112, tail=4, t60=1.6)
    T = timeline(ch, 4)
    riff = []
    for name, st, d in T:
        r = root_note(name, 40)
        for j, iv in enumerate([0, 0, 12, 0, 1, 0, 3, 2]):
            riff.append((st + j * 0.5, mhz(r + iv), 0.42, 1.0 if j in (0, 2) else 0.8))
    S.add(riff, i_bass_saw, gain=0.75, rev=0.05, cut=900, name='bass')
    S.add(shift(riff, semis=12, velmul=0.8), i_distsaw, gain=0.4, rev=0.1, drive=6.0, cut=2500, vib=None,
          a=0.002, d=0.08, s=0.6, r=0.04, name='guitar-riff')
    lead = mel("B5:2 G5:1 E5:1 | G5:1.5 F#5:.5 E5:1 C5:1 | A5:2 C6:1 B5:1 | D#6:2 B5:1 F#5:1 | "
               "E6:2 D#6:.5 E6:.5 B5:1 | C6:1.5 B5:.5 A5:1 G5:1 | A5:1 C6:1 F6:1.5 E6:.5 | "
               "D#6:2 C6:.5 B5:.5 A5:.5 F#5:.5 | "
               "C6:1 B5:.5 A5:.5 E5:1 A5:1 | D6:1 C6:.5 B5:.5 F5:1 B5:1 | E6:1.5 D6:.5 C6:1 G5:1 | "
               "F#6:1.5 D#6:.5 C6:1 A5:1 | B5:1 E6:1 G6:2 | G6:1 Eb6:1 C6:1 G5:1 | A5:1 C6:1 F6:1 A6:1 | "
               "B6:2 A6:.5 F#6:.5 D#6:1", start=16, bpb=4, vel=0.9)
    S.add(shift(lead, semis=-12), i_distsaw, gain=0.85, rev=0.2, echo=(0.75, 0.2, 0.12), drive=4.0,
          cut=3500, name='lead-dist')
    S.add(lead, i_square, gain=0.4, rev=0.2, duty=0.25, name='lead-sq')
    runs = arp_ev(T[20:], [0, 1, 2, 3, 4, 5, 6, 7, 8, 7, 6, 5, 4, 3, 2, 1], 0.25, low=64, vel=0.75)
    S.add(runs, i_distsaw, gain=0.45, rev=0.15, drive=4.0, cut=4000, vib=None, a=0.002, d=0.05, s=0.7,
          r=0.03, name='runs')
    S.add(runs, i_square, gain=0.25, rev=0.15, duty=0.125, vib=None, a=0.002, d=0.05, s=0.5, r=0.03,
          name='runs-sq')
    stabs = []
    for name, st, d in T[:4]:
        for off in (0, 1.5, 3):
            for m in voicing(name, 55):
                stabs.append((st + off, mhz(m), 0.6, 0.9))
    S.add(stabs + pad_ev(T[4:], low=55, vel=0.6), i_organ, gain=0.45, rev=0.3, name='organ')
    kick, snare, hats, crash, toms, taiko = [], [], [], [], [], []
    for bar in range(28):
        st = bar * 4
        fill = bar % 8 == 7 or bar == 3
        if bar < 4:
            kick += pat("x.......x.......", st)
            taiko += [(st, 0, 1, 1.0), (st + 1.5, 0, 1, 0.7), (st + 3, 0, 1, 0.85)]
            hats += pat("x.x.x.x.x.x.x.x.", st, vmap={'x': 0.4})
        else:
            kick += pat("x.x.x.x.x.x.x.x." if not fill else "x.x.x.x.x.x.....", st)
            snare += pat("....x.......x..." if not fill else "....x.......xxXX", st)
            hats += pat("x.x.x.x.x.x.x.x." if not fill else "x.x.x.x.x.x.....", st)
        if bar % 4 == 0:
            crash.append((st, 0, 1, 0.9))
        if fill:
            toms += [(st + 3.0, 200.0, .25, .8), (st + 3.25, 160.0, .25, .85), (st + 3.5, 130.0, .25, .9),
                     (st + 3.75, 100.0, .25, 1.0)]
    S.add(kick, d_kick, gain=0.4, rev=0.05, hum=0.0, name='kick')
    S.add(snare, d_snare, gain=0.7, rev=0.15, hum=0.001, tone=170, name='snare')
    S.add(hats, d_hat, gain=0.3, rev=0.05, hum=0.001, name='hat')
    S.add(crash, d_crash, gain=0.45, rev=0.2, name='crash')
    S.add(toms, d_tom, gain=0.55, rev=0.15, name='toms')
    S.add(taiko, d_taiko, gain=0.6, rev=0.3, name='taiko')
    S.add([(st, 82.4, 1, 0.8) for st in range(16, 48, 4)], d_timp, gain=0.4, rev=0.3, name='timpani')
    return S.render()


def glide_voice(events, spb, N, port=0.06, vib=(5.6, 0.22), det_c=0.0, harm=0.12, gap=0.12, att_tau=0.1):
    logf = np.full(N, np.nan)
    gate = np.zeros(N)
    for b, f, d, v in events:
        i0 = int(round(b * spb * SR))
        i1 = min(N, int(round((b + d) * spb * SR)))
        logf[i0:i1] = np.log2(f)
        gate[i0:max(i0 + 1, i1 - ns(gap * spb))] = v
    idx = np.where(~np.isnan(logf), np.arange(N), 0)
    np.maximum.accumulate(idx, out=idx)
    logf = logf[idx]
    first = np.nonzero(~np.isnan(logf))[0][0]
    logf[:first] = logf[first]
    a = np.exp(-1.0 / (port * SR))
    logf = ss.lfilter([1 - a], [1, -a], logf, zi=[a * logf[0]])[0]
    a2 = np.exp(-1.0 / (att_tau * SR))
    gs = ss.lfilter([1 - a2], [1, -a2], gate)
    t = t_(N)
    depth = vib[1] * (0.6 + 0.4 * np.sin(TAU * 0.13 * t))
    lf = logf + depth / 12 * np.sin(TAU * vib[0] * t) + det_c / 1200.0
    ph = np.cumsum(2 ** lf) / SR
    x = np.sin(TAU * ph) + harm * np.sin(2 * TAU * ph)
    return x * gs


def song_void():
    S = Song(64, 32, tail=9, t60=4.5, bright=0.8)
    pads = [(0, ['C4', 'E4', 'G4', 'B4', 'F#5']), (8, ['Ab3', 'C4', 'E4', 'G4']),
            (16, ['D4', 'F#4', 'A#4', 'C5']), (24, ['C4', 'E4', 'G#4', 'B4'])]
    S.add([(b, mhz(nm(n_)), 8.2, 0.5) for b, ns_ in pads for n_ in ns_], i_pad, gain=0.5, rev=0.7,
          a=2.5, r=3.0, name='pad')
    S.add([(b, mhz(nm(n_)), 8.2, 0.4) for b, ns_ in pads for n_ in ns_[:3]], i_choir, gain=0.3, rev=0.8,
          vowel='u', a=3.0, r=3.0, name='choir')
    melody = mel("E6:2 F#6:1 G6:1 | B6:3 A6:1 | G#6:2 E6:2 | C6:4 | D6:2 E6:1 F#6:1 | A#6:3 G#6:1 | "
                 "G#6:2 F#6:1 E6:1 | E6:3 r:1", bpb=4, vel=0.8)
    v1 = glide_voice(melody, S.spb, S.N)
    v2 = glide_voice(shift(melody, semis=-5), S.spb, S.N, det_c=8, vib=(5.1, 0.25))
    v3 = glide_voice(shift(melody, semis=12), S.spb, S.N, det_c=22, vib=(6.3, 0.3), harm=0.0)
    S.add_sig(v1, gain=0.5, rev=0.6, echo=(1.5, 0.35, 0.25), name='voice')
    S.add_sig(v2, gain=0.25, rev=0.7, name='voice-4th')
    S.add_sig(v3, gain=0.08, rev=0.8, name='voice-high')
    crick = [(b, 4300.0 + 400 * RNG.random(), 0.2, 0.7) for b in
             (1.5, 3.25, 7.0, 9.5, 12.75, 15.5, 18.0, 21.25, 24.5, 27.0, 29.75)]
    S.add(crick, i_cricket, gain=1.0, rev=0.5, pulses=4, name='chirps')
    birds = [(b, f, 0.12, 0.8) for b, f in ((5.0, 2200.), (5.2, 2500.), (13.0, 2600.), (20.5, 2000.),
                                            (20.7, 2300.), (28.5, 2800.))]
    S.add(birds, i_chirp, gain=1.0, rev=0.6, up=1.7, name='birds')
    return S.render()


def song_victory():
    S = Song(132, 9, loop=False, tail=3.0, t60=1.5)
    lead = mel("G4:1/3 C5:1/3 E5:1/3 G5:1 E5:.5 G5:.5 C6:1 Ab5:1 Bb5:1 C6:3", vel=0.9)
    S.add(lead, i_square, gain=0.7, rev=0.25, duty=0.25, vib=(6, 0.2, 0.2), name='lead')
    S.add(lead, i_brass, gain=0.6, rev=0.25, name='brass-lead')
    chords = [(1, ['C4', 'E4', 'G4'], 3), (4, ['Ab3', 'C4', 'Eb4'], 1), (5, ['Bb3', 'D4', 'F4'], 1),
              (6, ['C4', 'E4', 'G4', 'C5'], 3)]
    S.add([(b, mhz(nm(n_)), d, 0.7) for b, ns_, d in chords for n_ in ns_], i_brass, gain=0.5, rev=0.3,
          name='brass')
    S.add(mel("r:1 C3:3 Ab2:1 Bb2:1 [C2,C3]:3"), i_bass_saw, gain=0.6, rev=0.1, cut=600, name='bass')
    snare = [(0, 0, 1 / 3, 0.6), (1 / 3, 0, 1 / 3, 0.7), (2 / 3, 0, 1 / 3, 0.8)]
    snare += [(4 + k * 0.25, 0, 0.25, 0.3 + 0.07 * k) for k in range(8)]
    S.add(snare, d_snare, gain=0.5, rev=0.2, hum=0, name='snare')
    S.add([(1, 0, 1, 1.0), (6, 0, 1, 1.0)], d_crash, gain=0.5, rev=0.3, name='crash')
    S.add([(1, 0, 1, 1.0), (4, 0, 1, .8), (5, 0, 1, .8), (6, 0, 1, 1.0)], d_kick, gain=0.35, rev=0.1,
          name='kick')
    S.add([(1, 65.4, 1, 0.9), (6, 65.4, 1, 1.0)], d_timp, gain=0.5, rev=0.3, name='timp')
    return S.render()


def song_gameover():
    S = Song(84, 9, loop=False, tail=2.5, t60=2.2, max_len=7.8)
    m = mel("E5:1 D5:.5 C5:.5 B4:1 A4:1 F4:1 E4:1 G#4:1 A4:2", vel=0.8)
    S.add(m, i_musicbox, gain=1.0, rev=0.45, decay=1.8, name='musicbox')
    S.add(m, i_whistle, gain=0.35, rev=0.4, breath=0.02, name='flute')
    ch = timeline([('Am', 2), ('F', 2), ('Dm', 1), ('E7', 2), ('Am', 2)], 4)
    S.add(pad_ev(ch, low=50, vel=0.55, merge=False), i_strings, gain=0.5, rev=0.5, a=0.3, r=1.2, cut=1500,
          name='strings')
    S.add(mel("A2:2 F2:2 D2:1 E2:2 A1:2"), i_softbass, gain=0.6, rev=0.2, r=0.8, name='bass')
    return S.render()


def song_revolution():
    S = Song(90, 15, loop=False, tail=4.0, t60=2.6, max_len=11.0)
    secs = [(0, 4, ['C3', 'G3', 'C4', 'Eb4', 'G4'], 0.45, 3.5),
            (4, 2, ['Ab2', 'Eb3', 'C4', 'Eb4', 'Ab4'], 0.65, 0.6),
            (6, 2, ['Bb2', 'F3', 'D4', 'F4', 'Bb4'], 0.8, 0.5),
            (8, 6, ['C3', 'G3', 'C4', 'E4', 'G4', 'C5'], 1.0, 0.05)]
    for b, d, notes, v, a in secs:
        ev = [(b, mhz(nm(n_)), d, v) for n_ in notes]
        S.add(ev, i_choir, gain=0.75, rev=0.55, vowel='a' if b >= 8 else 'o', a=a * S.spb, r=2.0, name='choir')
        S.add(ev, i_strings, gain=0.45, rev=0.5, a=a * S.spb, r=2.0, cut=3000, name='strings')
    S.add([(8, mhz(nm(n_)), 5, 0.9) for n_ in ['C4', 'E4', 'G4', 'C5', 'E5']], i_brass, gain=0.45, rev=0.4,
          a=0.05, r=1.5, name='brass')
    S.add(mel("r:8 G5:2 C6:4"), i_square, gain=0.35, rev=0.4, duty=0.25, name='lead')
    S.add(mel("C2:4 Ab1:2 Bb1:2 C2:6"), i_bass_saw, gain=0.6, rev=0.2, cut=400, s=0.9, r=1.5, name='bass')
    hits = [(0, 1.0), (2, 0.8), (4, 0.9), (5, 0.8), (6, 0.9), (6.5, 0.7), (7, 0.85), (7.25, 0.7), (7.5, 0.8),
            (7.75, 0.9)]
    S.add([(b, 0, 1, v) for b, v in hits] + [(8, 0, 1, 1.0)], d_taiko, gain=0.5, rev=0.35, name='taiko')
    S.add([(8, 0, 1, 1.0)], d_crash, gain=0.6, rev=0.4, dec=2.5, name='crash')
    S.add([(8, 65.4, 1, 1.0), (11, 65.4, 1, 0.6)], d_timp, gain=0.6, rev=0.3, dec=2.0, name='timp')
    S.add([(8, 0, 1, 1.0)], d_kick, gain=0.7, rev=0.2, dec=0.6, name='kick')
    # riser 0..8 beats
    n = ns(8 * S.spb)
    t = t_(n)
    riser = np.zeros(n)
    nzs = noise(n)
    centers = np.geomspace(200, 7000, 10)
    for k, c in enumerate(centers):
        bump = np.exp(-0.5 * ((t / t[-1] - (k + 0.5) / len(centers)) / 0.12) ** 2)
        riser += bp(nzs, c * 0.7, c * 1.4) * bump
    riser *= (t / t[-1]) ** 1.5
    fr = 110 * 2 ** (3 * (t / t[-1]) ** 1.3)
    riser = riser * 0.6 + 0.15 * lp(o_saw(fr), 3000) * (t / t[-1]) ** 2
    S.add_sig(fin(riser, 0.03), 0, gain=0.5, rev=0.3, name='riser')
    return S.render()


# =====================================================================================
# SFX
# =====================================================================================
def cap(x, max_len, fade=0.3):
    """Limit length to max_len seconds with a smooth (half-cosine) fade over the last `fade` s."""
    n = ns(max_len)
    if len(x) <= n:
        return x
    x = x[:n].copy()
    k = ns(fade)
    x[-k:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, k))
    return x


def mix(total, items):
    """Sum (start_seconds, signal) items; `total` is a minimum length -- nothing gets cut."""
    starts = [(ns(st) if st > 0 else 0) for st, _ in items]
    y = np.zeros(max([ns(total)] + [i + len(sg) for i, (_, sg) in zip(starts, items)]))
    for i, (_, sg) in zip(starts, items):
        y[i:i + len(sg)] += sg
    return y


def finish(x, db=-1.0, fade_in=0.0015, trim_db=-48, max_len=None):
    """Trim the tail below trim_db (re peak), DC-block, normalise, fade both ends."""
    x = np.asarray(x, dtype=float)
    a = np.abs(x)
    idx = np.nonzero(a > a.max() * 10 ** (trim_db / 20))[0]
    if len(idx):
        x = x[:idx[-1] + ns(0.01)]
    x = hp(x, 25, 1)
    if max_len:
        x = cap(x, max_len, min(0.4, max_len * 0.3))
    x = norm_peak(x, db)
    k = ns(fade_in)
    x[:k] *= np.linspace(0, 1, k)
    return fin(x, 0.008)


def blip(f, dur, duty=0.5, kind='sq', a=0.002, decay=None, bend=None):
    n = ns(dur)
    fr = ftrack(f, n, bend=bend)
    x = o_sq(fr, duty, 0.0) if kind == 'sq' else (o_tri(fr) if kind == 'tri' else o_sin(fr))
    env = att(n, a) * (np.exp(-t_(n) / decay) if decay else 1.0)
    return fin(x * env)


def sweep(f0, f1, dur, kind='sin', duty=0.5):
    n = ns(dur)
    t = t_(n)
    fr = f0 * (f1 / f0) ** (t / dur)
    if kind == 'sin':
        return o_sin(fr)
    if kind == 'saw':
        return o_saw(fr)
    if kind == 'tri':
        return o_tri(fr)
    return o_sq(fr, duty)


def vox(f_track, spec_a, spec_b=None, morph=None, rasp=0.0, jitter=0.01, shift_=1.0, sub=0.0):
    n = len(f_track)
    jit = 1 + jitter * lp(noise(n), 30) * 5
    fr = f_track * jit
    src = o_saw(fr) + sub * o_saw(fr * 0.5) + rasp * noise(n)
    y = formant(src, spec_a, shift_)
    if spec_b is not None:
        yb = formant(src, spec_b, shift_)
        y = y * (1 - morph) + yb * morph
    return y


CHICK_O = [(950, 1.0, 160), (1900, 0.7, 220), (3100, 0.35, 300)]
CHICK_U = [(650, 1.0, 140), (1400, 0.45, 220), (2800, 0.2, 300)]
CHICK_A = [(1200, 1.0, 180), (2300, 0.8, 250), (3500, 0.4, 350)]


def bok(dur=0.09, f0=520, rise=0.25, fall=0.15, a_spec=CHICK_O, b_spec=CHICK_U, rasp=0.15):
    n = ns(dur)
    t = t_(n)
    ftr = f0 * (1 + rise * np.exp(-t / 0.015)) * (1 - fall * t / dur)
    m = np.clip(t / dur, 0, 1)
    y = vox(ftr, a_spec, b_spec, m, rasp=rasp, jitter=0.02)
    env = att(n, 0.004) * np.exp(-t / (dur * 0.6))
    y = y / (np.max(np.abs(y)) + 1e-9) * env
    click = lp(noise(ns(0.006)), 1500) * np.exp(-t_(ns(0.006)) / 0.0015) * 0.4
    y[:len(click)] += click
    return fin(y, 0.006)


def sfx_ui_move():
    return finish(blip(1318.5, 0.045, 0.25, decay=0.02), -6)


def sfx_ui_select():
    return finish(mix(0.14, [(0, blip(1046.5, 0.05, 0.25, decay=0.04)), (0.045, blip(1568, 0.09, 0.25, decay=0.04))]), -3)


def sfx_ui_cancel():
    return finish(mix(0.14, [(0, blip(784, 0.05, 0.5, decay=0.04)), (0.045, blip(523.3, 0.09, 0.5, decay=0.035))]), -4)


def sfx_ui_error():
    def buzz():
        n = ns(0.09)
        fr = np.full(n, 140.0)
        return fin((o_sq(fr, 0.5, 0) + o_sq(fr * 1.06, 0.3, 0.3)) * att(n, 0.002))
    return finish(lp(mix(0.22, [(0, buzz()), (0.12, buzz())]), 2500), -3)


def sfx_text_blip():
    return finish(blip(880, 0.025, kind='tri', decay=0.012) + 0.3 * blip(1760, 0.025, 0.25, decay=0.006), -9)


def sfx_step():
    n = ns(0.09)
    t = t_(n)
    x = lp(noise(n), 450) * (1 - np.exp(-t / 0.002)) * np.exp(-t / 0.022) * 2
    x += bp(noise(n), 1500, 4000) * np.exp(-t / 0.006) * 0.25
    x += np.sin(TAU * 90 * t) * np.exp(-t / 0.02) * 0.4
    return finish(x, -8)


def sfx_cluck1():
    return finish(mix(0.4, [(0, bok(0.085, 540)), (0.16, bok(0.07, 480, rise=0.2) * 0.7)]), -2)


def sfx_cluck2():
    n = ns(0.3)
    t = t_(n)
    ftr = 560 * (1 + 0.5 * np.sin(np.pi * np.clip(t / 0.22, 0, 1)) ** 2) * (1 - 0.25 * t / 0.3)
    y = vox(ftr, CHICK_A, CHICK_U, np.clip((t - 0.15) / 0.15, 0, 1), rasp=0.25, jitter=0.03)
    y = y / np.max(np.abs(y)) * att(n, 0.01) * np.exp(-np.maximum(t - 0.18, 0) / 0.05)
    return finish(mix(0.75, [(0, bok(0.08, 520)), (0.14, bok(0.07, 560) * 0.8), (0.32, fin(y))]), -2)


def sfx_cluck_angry():
    n = ns(0.5)
    t = t_(n)
    ftr = 950 * (1 + 0.45 * np.sin(np.pi * np.clip(t / 0.35, 0, 1))) * (1 + 0.06 * np.sin(TAU * 75 * t))
    ftr *= 1 - 0.3 * np.clip((t - 0.3) / 0.2, 0, 1)
    y = vox(ftr, CHICK_A, CHICK_O, np.clip(t / 0.5, 0, 1), rasp=0.6, jitter=0.06, shift_=1.15)
    y = np.tanh(3 * y / np.max(np.abs(y)))
    env = att(n, 0.008) * np.where(t < 0.38, 1.0, np.exp(-(t - 0.38) / 0.04))
    pre = bok(0.06, 700, a_spec=CHICK_A)
    return finish(mix(0.62, [(0, pre * 0.7), (0.07, fin(y * env))]), -1)


def hit_core(f=120, dec=0.1, nz=0.08, bright=3000):
    n = ns(0.3)
    t = t_(n)
    x = np.sin(TAU * np.cumsum(50 + f * np.exp(-t / 0.02)) / SR) * np.exp(-t / dec)
    x += lp(noise(n), bright) * np.exp(-t / nz) * 0.8
    x += hp(noise(n), 4000) * np.exp(-t / 0.004) * 0.5
    return fin(np.tanh(2 * x))


def sfx_hit():
    return finish(hit_core(), -1)


def sfx_hit_crit():
    n = ns(0.5)
    ring = i_bell(1850, 0.4, 1.0, ratio=2.4, index=2.0, decay=0.22)
    x = mix(0.6, [(0, hit_core(160, 0.14, 0.1, 5000) * 1.2), (0.045, hit_core(110, 0.12, 0.08, 3000)),
                  (0, ring * 0.6)])
    return finish(np.tanh(1.5 * x / np.max(np.abs(x))), -1)


def sfx_slash():
    n = ns(0.18)
    t = t_(n)
    nz = noise(n)
    w = np.zeros(n)
    for k, c in enumerate(np.geomspace(700, 6000, 8)):
        bump = np.exp(-0.5 * ((t / t[-1] - k / 7) / 0.15) ** 2)
        w += bp(nz, c * 0.7, c * 1.4) * bump
    w *= att(n, 0.01)
    m = ns(0.35)
    tm = t_(m)
    shing = sum(a * np.sin(TAU * f * tm) for f, a in ((3200, 1.0), (4710, 0.6), (6130, 0.4))) * np.exp(-tm / 0.09)
    return finish(mix(0.45, [(0, fin(w)), (0.08, fin(shing * att(m, 0.002)) * 0.35)]), -1)


def sfx_peck():
    n = ns(0.1)
    t = t_(n)
    x = np.sin(TAU * np.cumsum(1800 * np.exp(-t / 0.02) + 700) / SR) * np.exp(-t / 0.018)
    x += bp(noise(n), 2000, 5000) * np.exp(-t / 0.006) * 0.8
    x += np.sin(TAU * 150 * t) * np.exp(-t / 0.02) * 0.5
    return finish(mix(0.16, [(0, fin(x)), (0.06, fin(x) * 0.5)]), -2)


def sfx_whoosh():
    n = ns(0.38)
    t = t_(n)
    nz = noise(n)
    w = np.zeros(n)
    path = [400, 800, 1500, 1100, 700]
    for k, c in enumerate(path):
        bump = np.exp(-0.5 * ((t / t[-1] - k / (len(path) - 1)) / 0.18) ** 2)
        w += bp(nz, c * 0.6, c * 1.6) * bump
    env = np.sin(np.pi * t / t[-1]) ** 1.5
    return finish(w * env, -3)


def crackles(n, count, amp=1.0, dmin=0.0008, dmax=0.004):
    y = np.zeros(n)
    for _ in range(count):
        m = ns(RNG.uniform(dmin, dmax) * 5)
        tm = t_(m)
        c = hp(noise(m), RNG.uniform(1000, 4000)) * np.exp(-tm / RNG.uniform(dmin, dmax))
        place = RNG.integers(0, max(1, n - m))
        y[place:place + m] += c * amp * min(RNG.pareto(2.5), 2.5) * 0.4
    return lp(y, 5000, 2)


def sfx_magic_fire():
    n = ns(1.9)
    t = t_(n)
    env = np.clip(t / 0.15, 0, 1) * np.exp(-np.maximum(t - 0.3, 0) / 0.35)
    roar = lp(noise(n), 900) * (1 + 0.5 * lp(noise(n), 15) * 5) * env
    whoosh = sweep(80, 300, 1.9, 'saw') * env * 0.3
    x = roar + lp(whoosh, 800) + crackles(n, 60, 1.5) * env
    x += bp(noise(n), 2000, 6000) * env * 0.2
    return finish(reverb(x, 0.8, 0.2), -1, max_len=1.5)


def sfx_magic_heal():
    notes = [72, 76, 79, 84, 88, 91]
    items = [(k * 0.08, i_bell(mhz(m), 0.5, 0.8, ratio=2.0, index=1.0, decay=0.6)) for k, m in enumerate(notes)]
    n = ns(1.2)
    t = t_(n)
    shimmer = hp(noise(n), 6000) * np.sin(np.pi * t / t[-1]) ** 2 * 0.15 * (1 + np.sin(TAU * 18 * t)) * 0.5
    pad = sum(np.sin(TAU * mhz(m) * t) for m in (72, 76, 79)) * np.sin(np.pi * t / t[-1]) ** 2 * 0.15
    x = mix(1.5, items + [(0, shimmer), (0, pad)])
    return finish(reverb(x, 1.4, 0.35, 0.8), -1, max_len=1.6)


def sfx_magic_dark():
    n = ns(1.4)
    t = t_(n)
    fr = 220 * 2 ** (-t / 1.4)
    x = sum(o_saw(fr * 2 ** (d / 12)) for d in (-0.15, 0, 0.17, -12))
    x = lp(x, 900) * np.sin(np.pi * np.clip(t / 1.4, 0, 1)) ** 0.7
    rm = x * np.sin(TAU * 37 * t) * 0.5
    swell = bp(noise(n), 200, 1200) * (t / 1.4) ** 2 * np.exp(-np.maximum(t - 1.0, 0) / 0.1)
    y = x + rm + swell * 0.8
    return finish(reverb(fin(y), 1.6, 0.3, 0.3), -1, max_len=1.6)


def sfx_magic_ice():
    items = []
    for k in range(10):
        f = RNG.uniform(2500, 6500)
        items.append((k * 0.05 + RNG.uniform(0, 0.02), i_bell(f, 0.3, RNG.uniform(0.5, 1.0), ratio=1.41,
                                                                 index=1.5, decay=0.25)))
    n = ns(1.0)
    t = t_(n)
    hiss = hp(noise(n), 5000) * np.exp(-t / 0.35) * 0.25
    crack = hp(noise(ns(0.03)), 2000) * np.exp(-t_(ns(0.03)) / 0.006)
    x = mix(1.2, items + [(0, hiss), (0, crack)])
    return finish(reverb(x, 1.2, 0.3, 0.9), -1)


def sfx_poison():
    items = []
    for k in range(9):
        f = RNG.uniform(300, 800)
        d = RNG.uniform(0.05, 0.09)
        m = ns(d)
        tm = t_(m)
        fr = f * 2 ** (tm / d * 1.2)
        b = np.sin(TAU * np.cumsum(fr) / SR) * np.sin(np.pi * tm / d)
        items.append((k * 0.1 + RNG.uniform(0, 0.04), b * RNG.uniform(0.5, 1.0)))
    n = ns(1.0)
    t = t_(n)
    wob = np.sin(TAU * np.cumsum(110 + 25 * np.sin(TAU * 6 * t)) / SR) * np.sin(np.pi * t) * 0.25
    return finish(mix(1.1, items + [(0, lp(o_sq(np.full(n, 110.0) + 25 * np.sin(TAU * 6 * t), 0.3), 600)
                                       * np.sin(np.pi * t) * 0.15 + wob)]), -2)


def sfx_shield():
    n = ns(0.9)
    t = t_(n)
    fr = 300 * 2 ** (1.0 * (1 - np.exp(-t / 0.15)))
    x = sum(np.sin(TAU * np.cumsum(fr * r) / SR + p) for r, p in ((1, 0), (1.007, 1), (2.01, 2), (3.0, 0.5)))
    x *= att(n, 0.01) * np.exp(-t / 0.3) * (1 + 0.3 * np.sin(TAU * 11 * t))
    ring = i_bell(1200, 0.5, 0.6, ratio=1.5, index=2.0, decay=0.4)
    return finish(reverb(mix(1.0, [(0, x), (0.02, ring)]), 0.9, 0.25), -1)


def sfx_buff():
    notes = [60, 64, 67, 72, 76, 79, 84]
    items = [(k * 0.06, blip(mhz(m), 0.09, 0.25, decay=0.06)) for k, m in enumerate(notes)]
    n = ns(0.55)
    items.append((0, sweep(300, 2400, 0.55, 'sin') * att(n, 0.02) * np.linspace(0.3, 0, n) * 0.6))
    return finish(reverb(mix(0.75, items), 0.6, 0.2), -2)


def sfx_debuff():
    notes = [79, 75, 72, 68, 63, 60, 56]
    items = [(k * 0.07, blip(mhz(m), 0.1, 0.5, decay=0.07, bend=(0.6, 0.03))) for k, m in enumerate(notes)]
    n = ns(0.7)
    t = t_(n)
    fr = 600 * 2 ** (-2.5 * t / 0.7) * (1 + 0.05 * np.sin(TAU * 9 * t))
    items.append((0, o_tri(fr) * att(n, 0.02) * np.linspace(0.5, 0, n)))
    return finish(reverb(mix(0.85, items), 0.6, 0.2), -2)


def sfx_enemy_die():
    n = ns(1.0)
    t = t_(n)
    ftr = np.interp(t, [0, 0.08, 0.35, 0.8, 1.0], [150, 205, 180, 105, 85])
    ftr *= 1 + 0.035 * np.sin(TAU * 7 * t) * np.clip(t / 0.3, 0, 1)
    ftr *= 1 + 0.08 * np.exp(-((t - 0.5) / 0.03) ** 2)
    m = np.clip((t - 0.2) / 0.5, 0, 1)
    y = vox(ftr, 'a', 'r', m, rasp=0.25, jitter=0.03, sub=0.35)
    y = y / np.max(np.abs(y))
    env = att(n, 0.03) * np.where(t < 0.75, 1.0, np.exp(-(t - 0.75) / 0.07))
    y = np.tanh(1.8 * y * env)
    thud = hit_core(70, 0.15, 0.05, 900) * 0.6
    return finish(mix(1.25, [(0, fin(y)), (0.95, thud)]), -1)


def sfx_chicken_ko():
    n = ns(0.95)
    t = t_(n)
    ftr = 900 * 2 ** (-1.7 * t / 0.95) * (1 + 0.05 * np.sin(TAU * 8 * t) * t)
    y = vox(ftr, CHICK_A, CHICK_U, np.clip(t / 0.95, 0, 1), rasp=0.3, jitter=0.04)
    y = y / np.max(np.abs(y)) * att(n, 0.01) * np.where(t < 0.7, 1.0, np.exp(-(t - 0.7) / 0.08))
    thud = hit_core(60, 0.18, 0.04, 700) * 0.7
    puff = lp(noise(ns(0.25)), 3000) * np.exp(-t_(ns(0.25)) / 0.06) * 0.15
    return finish(mix(1.5, [(0, bok(0.07, 650, a_spec=CHICK_A) * 0.8), (0.1, fin(y)), (1.05, thud),
                            (1.08, puff)]), -1)


def creak(dur=0.35, f0=260):
    n = ns(dur)
    t = t_(n)
    fr = f0 * (1 + 0.25 * np.sin(np.pi * t / dur)) * (1 + 0.05 * lp(noise(n), 40) * 5)
    pulses = o_saw(fr) * (0.5 + 0.5 * np.sign(np.sin(TAU * 35 * t)))
    return fin(bp(pulses, 400, 2500) * np.sin(np.pi * t / dur))


def sfx_chest_open():
    sparkle = [(0.35 + k * 0.07, i_bell(mhz(m), 0.4, 0.7, ratio=2.0, index=1.2, decay=0.5))
               for k, m in enumerate([79, 84, 88, 91])]
    click = hit_core(200, 0.03, 0.02, 4000) * 0.5
    return finish(reverb(mix(1.3, [(0, click), (0.05, creak(0.35, 230) * 0.8)] + sparkle), 0.8, 0.2), -1, max_len=1.5)


def sfx_item_get():
    seq = [(0, 79, 0.08), (0.08, 84, 0.08), (0.16, 88, 0.08), (0.24, 91, 0.45)]
    items = []
    for st, m, d in seq:
        items.append((st, blip(mhz(m), d + 0.1, 0.25, decay=0.15 if d > 0.1 else 0.06)))
        items.append((st, i_bell(mhz(m), d, 0.4, ratio=2.0, index=0.8, decay=0.4)))
    return finish(reverb(mix(0.95, items), 0.6, 0.2), -1, max_len=1.2)


def sfx_level_up():
    items = []
    for k, m in enumerate([60, 64, 67, 72, 76, 79]):
        items.append((k * 0.06, blip(mhz(m), 0.08, 0.25, decay=0.05)))
    for m in (72, 76, 79, 84):
        items.append((0.4, i_square(mhz(m), 0.6, 0.45, duty=0.5, a=0.005, s=0.7, r=0.3)))
        items.append((0.4, i_bell(mhz(m + 12), 0.6, 0.35, ratio=2.0, index=1.0, decay=0.6)))
    items += [(0.75 + k * 0.05, blip(mhz(m), 0.06, 0.125, decay=0.04) * 0.5) for k, m in enumerate([96, 91, 96, 100])]
    return finish(reverb(mix(1.6, items), 0.8, 0.25), -1, max_len=1.8)


def sfx_door():
    n = ns(0.3)
    t = t_(n)
    thud = np.sin(TAU * np.cumsum(70 + 60 * np.exp(-t / 0.02)) / SR) * np.exp(-t / 0.08)
    thud += lp(noise(n), 700) * np.exp(-t / 0.03) * 0.7
    latch = hp(noise(ns(0.02)), 2500) * np.exp(-t_(ns(0.02)) / 0.004) * 0.4
    return finish(reverb(mix(0.85, [(0, creak(0.45, 200) * 0.7), (0.42, fin(thud)), (0.44, latch)]), 0.5, 0.2), -1)


def sfx_memory_flash():
    n = ns(1.5)
    t = t_(n)
    swell = np.sin(np.pi * np.clip(t / 1.5, 0, 1)) ** 2
    nz = hp(noise(n), 2500) * swell * 0.25
    cl = np.zeros(n)
    for m in (88, 95, 102, 104, 100):
        fr = mhz(m) * (1 + 0.02 * t)
        cl += np.sin(TAU * np.cumsum(np.full(n, fr) if np.isscalar(fr) else fr) / SR + RNG.random()) * \
            (0.6 + 0.4 * np.sin(TAU * RNG.uniform(5, 12) * t))
    cl *= swell * 0.2
    rb = i_bell(mhz(84), 0.7, 0.8, ratio=2.0, index=1.5, decay=0.35)[:ns(0.7)][::-1]
    fb = i_bell(mhz(84), 0.7, 0.8, ratio=2.0, index=1.5, decay=0.5)
    x = mix(1.8, [(0, nz), (0, cl), (0.05, fin(rb)), (0.75, fb)])
    return finish(reverb(x, 1.8, 0.4, 0.9), -1, max_len=1.8)


def sfx_battle_start():
    n = ns(0.5)
    t = t_(n)
    fr = 220 * 2 ** (3.5 * t / 0.5)
    swirl = sum(np.sin(TAU * np.cumsum(fr * r) / SR + 2 * np.sin(TAU * (8 + 30 * t) * t)) for r in (1, 1.5, 2.02))
    swirl *= att(n, 0.02) * (0.4 + 0.6 * t / 0.5) * (0.6 + 0.4 * np.sin(TAU * (6 + 40 * t) * t))
    grains = []
    for _ in range(45):
        f = RNG.uniform(2000, 9000)
        grains.append((0.45 + RNG.uniform(0, 0.35), i_bell(f, 0.1, RNG.uniform(0.3, 1.0), ratio=1.37,
                                                            index=2.0, decay=RNG.uniform(0.02, 0.09))))
    m = ns(0.4)
    burst = hp(noise(m), 3000) * np.exp(-t_(m) / 0.08)
    boom = np.sin(TAU * np.cumsum(45 + 80 * np.exp(-t_(m) / 0.03)) / SR) * np.exp(-t_(m) / 0.15)
    x = mix(1.1, [(0, fin(swirl) * 0.5), (0.45, fin(burst) * 0.8), (0.45, fin(boom))] + grains)
    return finish(reverb(x, 0.9, 0.2), -1)


def sfx_flee():
    items = []
    st = 0.0
    gap = 0.12
    for k in range(6):
        items.append((st, (lp(noise(ns(0.05)), 900) * np.exp(-t_(ns(0.05)) / 0.012)) * (0.6 + 0.08 * k)))
        st += gap
        gap *= 0.82
    n = ns(0.45)
    t = t_(n)
    w = bp(noise(n), 600, 3000) * np.sin(np.pi * t / t[-1]) ** 2 * 0.6
    items.append((0.35, w))
    return finish(mix(0.9, items), -2)


def sfx_power_down():
    n = ns(2.0)
    t = t_(n)
    fr = 18 + 102 * np.exp(-t / 0.55)
    buzz = o_saw(fr) + 0.5 * o_sq(fr * 2, 0.5) + 0.3 * o_sin(fr * 3)
    bright = lp(buzz, 4000)
    dark = lp(buzz, 300)
    fx = np.exp(-t / 0.3)
    x = bright * fx + dark * (1 - fx)
    whine = np.sin(TAU * np.cumsum(2200 * np.exp(-t / 0.4) + 100) / SR) * np.exp(-t / 0.35) * 0.15
    amp = np.clip(1 - t / 2.0, 0, 1) ** 1.5 * att(n, 0.005)
    sp = crackles(ns(0.6), 18, 1.0)
    y = mix(2.0, [(0, (x + whine) * amp), (0, sp * 0.6)])
    return finish(y, -1)


def thunder_sig(dur=2.5, crack=True):
    n = ns(dur)
    t = t_(n)
    brown = hp(np.cumsum(noise(n)), 20, 1)
    rumble = lp(brown, 160, 2)
    rumble /= np.std(rumble) + 1e-9
    am = lp(np.abs(noise(n)), 6)
    am = am / am.max()
    env = (1 - np.exp(-t / 0.08)) * np.exp(-t / (dur * 0.33))
    x = rumble * (0.3 + am) * env
    mid = bp(noise(n), 200, 1500) * lp(np.abs(noise(n)), 12) * 6 * np.exp(-t / (dur * 0.2)) * 0.25
    x += mid * (1 - np.exp(-t / 0.05))
    if crack:
        c = hp(noise(n), 1200) * np.exp(-t / 0.08) * 1.5 + bp(noise(n), 400, 3000) * np.exp(-t / 0.25) * 0.6
        x += c * (1 + 0.8 * np.sign(np.sin(TAU * 23 * t)))
    return fin(x, 0.05)


def sfx_thunder():
    return finish(reverb(thunder_sig(2.5), 1.5, 0.2), -1, 0.001)


def sfx_blood_splat():
    n = ns(0.35)
    t = t_(n)
    squish = bp(noise(n), 300, 2200) * (1 - np.exp(-t / 0.003)) * np.exp(-t / 0.06) * 1.2
    squish *= 1 + 0.6 * np.sin(TAU * 40 * t)
    items = [(0, fin(squish)), (0, hit_core(80, 0.06, 0.03, 1200) * 0.6)]
    for k in range(5):
        m = ns(0.05)
        tm = t_(m)
        f = RNG.uniform(500, 1400)
        d = np.sin(TAU * np.cumsum(f * 2 ** (-tm / 0.03)) / SR) * np.sin(np.pi * tm / tm[-1])
        items.append((0.06 + k * 0.045 + RNG.uniform(0, 0.02), d * 0.35))
    return finish(mix(0.45, items), -1)


def sfx_coin():
    return finish(mix(0.4, [(0, blip(987.8, 0.07, 0.5, decay=0.2)), (0.07, blip(1318.5, 0.3, 0.5, decay=0.1))]), -2)


def sfx_quest():
    items = [(k * 0.12, i_bell(mhz(m), 0.8, 0.8, ratio=2.0, index=1.2, decay=0.8)) for k, m in enumerate([67, 74, 79])]
    items += [(k * 0.12, blip(mhz(m), 0.12, 0.25, decay=0.08) * 0.4) for k, m in enumerate([67, 74, 79])]
    n = ns(1.0)
    t = t_(n)
    pad = sum(np.sin(TAU * mhz(m) * t) for m in (67, 71, 74)) * np.sin(np.pi * t) ** 2 * 0.08
    return finish(reverb(mix(1.4, items + [(0.2, pad)]), 0.9, 0.25), -1, max_len=1.6)


def sfx_save():
    items = [(k * 0.1, i_musicbox(mhz(m), 0.5, 0.9, decay=1.0)) for k, m in enumerate([72, 76, 79, 84])]
    items.append((0.4, i_musicbox(mhz(88), 0.5, 0.6, decay=1.2)))
    return finish(reverb(mix(1.5, items), 1.0, 0.3, 0.8), -1, max_len=1.6)


# --- ambient loops (exactly periodic) --------------------------------------------------
def amb_rain():
    n = ns(10.0)
    hiss = pnoise(n, 500, 9000, tilt=-0.3) * (0.85 + 0.15 * psmooth(n, 8))
    body = pnoise(n, 150, 1200) * 0.35
    drops = np.zeros(n)
    for _ in range(2200):
        m = ns(0.012)
        tm = t_(m)
        fc = RNG.uniform(1500, 7000)
        d = np.sin(TAU * fc * tm) * np.exp(-tm / RNG.uniform(0.0008, 0.003))
        place_wrap(drops, d * min(RNG.pareto(3.0), 3.0) * 0.3, RNG.integers(0, n))
    plinks = np.zeros(n)
    for _ in range(14):
        m = ns(0.08)
        tm = t_(m)
        f = RNG.uniform(900, 2200)
        d = np.sin(TAU * np.cumsum(f * 2 ** (-tm / 0.05)) / SR) * np.exp(-tm / 0.02) * att(m, 0.001)
        place_wrap(plinks, d * RNG.uniform(0.3, 0.8), RNG.integers(0, n))
    x = hiss * 0.35 + body + drops * 1.2 + plinks * 0.5
    return norm_peak(x - x.mean(), -1)


def warp_lfo(n, cycles, ph, kappa=4.0, skew=0.6):
    p = (cycles * np.arange(n) / n + ph) % 1.0
    p = p + skew * np.sin(TAU * p) / TAU
    return np.exp(kappa * (np.cos(TAU * (p - 0.5)) - 1))


def amb_waves():
    n = ns(10.0)
    w1 = warp_lfo(n, 2, 0.0, 3.0, 0.6) * (0.85 + 0.15 * plfo(n, 1, 0.2))
    w2 = warp_lfo(n, 2, 0.06, 5.0, 0.7)
    surf = pnoise(n, 60, 1100) * (0.15 + w1)
    foam = pnoise(n, 1500, 9000, tilt=-0.2) * (0.05 + w2) * 0.6
    lap = pnoise(n, 100, 600) * warp_lfo(n, 5, 0.3, 2.0, 0.3) * 0.2
    bg = pnoise(n, 80, 3000, tilt=-0.5) * 0.15
    x = surf + foam + lap + bg
    return norm_peak(x - x.mean(), -1)


def amb_wind():
    n = ns(10.0)
    g1 = psmooth(n, 5)
    g2 = 1 - g1 * 0.8
    low = pnoise(n, 60, 500) * (0.3 + 0.7 * g1)
    mid = pnoise(n, 400, 1800) * (0.2 + 0.6 * g2) * 0.6
    wh1 = pnoise(n, peak=(640, 25)) * psmooth(n, 4) ** 2 * 0.6
    wh2 = pnoise(n, peak=(910, 30)) * psmooth(n, 6) ** 2 * 0.4
    x = low + mid + wh1 + wh2
    return norm_peak(x - x.mean(), -1)


def amb_fire():
    n = ns(8.0)
    roar = pnoise(n, 40, 600) * (0.6 + 0.4 * psmooth(n, 14, 3))
    hiss = pnoise(n, 2000, 8000) * 0.12 * (0.5 + 0.5 * psmooth(n, 10, 2))
    cr = np.zeros(n)
    for _ in range(500):
        m = ns(0.02)
        tm = t_(m)
        c = noise(m) * np.exp(-tm / RNG.uniform(0.0005, 0.003))
        c = hp(c, RNG.uniform(800, 3000))
        place_wrap(cr, fin(c) * min(RNG.pareto(2.2), 3.0) * 0.25, RNG.integers(0, n))
    for _ in range(9):
        m = ns(0.12)
        tm = t_(m)
        pop = np.sin(TAU * np.cumsum(180 * 2 ** (-tm / 0.04)) / SR) * np.exp(-tm / 0.02) + \
            hp(noise(m), 1500) * np.exp(-tm / 0.004)
        place_wrap(cr, fin(pop) * RNG.uniform(0.6, 1.2), RNG.integers(0, n))
    cr = cfilt(cr, lambda v: lp(v, 5500, 2))
    x = roar * 0.5 + hiss + cr
    return norm_peak(x - x.mean(), -1)


def amb_night():
    n = ns(10.0)
    x = pnoise(n, 100, 2000, tilt=-0.6) * 0.04
    species = [(4300.0, 16, 3, 30.0, 0.8), (5100.0, 13, 4, 36.0, 0.5), (3800.0, 21, 2, 26.0, 0.35)]
    for f, k, pulses, rate, amp in species:
        period = n // k
        off = RNG.integers(0, period)
        for j in range(k):
            c = i_cricket(f * RNG.uniform(0.995, 1.005), 0.1, amp * RNG.uniform(0.8, 1.0), pulses, rate)
            place_wrap(x, c, off + j * period + RNG.integers(-200, 200))
    # katydid trills (on/off), periodic
    tr = np.zeros(n)
    m = ns(1.2)
    tm = t_(m)
    trill = np.sin(TAU * 6200 * tm) * (0.5 + 0.5 * np.sign(np.sin(TAU * 55 * tm))) * np.sin(np.pi * tm / tm[-1])
    for st in (1.3, 6.4):
        place_wrap(tr, lp(trill, 9000) * 0.12, ns(st))
    x = x + tr + pnoise(n, 3500, 6000) * 0.01 * psmooth(n, 3)
    return norm_peak(x - x.mean(), -1)


# =====================================================================================
# EXTENSION -- more music + SFX (battle themes with drum & bass sections, DnB boss themes,
# area variants, alternate fanfares, interaction sounds, enemy voices).
# Every item below is rendered with its own RNG seeded from its name (see with_rng), so the
# original outputs above stay bit-identical and every new file can be regenerated alone.
# =====================================================================================
def beats_tl(chords, bpb=4, start=0.0):
    return [(c, st + start, d) for c, st, d in timeline(chords, bpb)]


class Arr:
    """Arrangement helper: consecutive sections (kind, chord timeline, lead string) on one beat axis."""

    def __init__(self, bpb=4):
        self.bpb = bpb
        self.pos = 0.0
        self.secs = []

    def sec(self, kind, chords, lead=None):
        T = beats_tl(chords, self.bpb, self.pos)
        n = sum(d for _, _, d in T)
        s = {'kind': kind, 'T': T, 'start': self.pos, 'beats': n, 'lead': lead}
        self.secs.append(s)
        self.pos += n
        return s

    def T(self, *kinds):
        return [c for s in self.secs if s['kind'] in kinds for c in s['T']]


def lead_ev(sec, vel=0.85, tr=0):
    return mel(sec['lead'], start=sec['start'], vel=vel, tr=tr, bpb=4)


def ctone(name, tok, low, nxt=None):
    """Chord-aware note: r=root t=third f=fifth s=seventh o=octave T/F=third/fifth up an octave,
    A=chromatic approach to the next chord's root; ints are raw semitones above the root."""
    root, ivs = parse_chord(name)
    r = low + ((root - low) % 12)
    if not isinstance(tok, str):
        return r + tok
    if tok == 'A':
        n_ = low + ((parse_chord(nxt or name)[0] - low) % 12)
        return n_ - 1 if n_ - 1 >= low - 2 else n_ + 1
    m = {'r': 0, 't': ivs[1], 'f': ivs[2], 's': ivs[3] if len(ivs) > 3 else 10, 'o': 12,
         'T': ivs[1] + 12, 'F': ivs[2] + 12}
    return r + m[tok]


def ostinato(T, toks, step=0.5, low=36, dur=0.8, vels=None, vel=0.9):
    ev = []
    for ci, (name, st, d) in enumerate(T):
        nxt = T[(ci + 1) % len(T)][0]
        k, b = 0, st
        while b < st + d - 1e-9:
            tok = toks[k % len(toks)]
            if tok is not None:
                v = vel * (vels[k % len(vels)] if vels else 1.0)
                ev.append((b, mhz(ctone(name, tok, low, nxt)), step * dur, v))
            k += 1
            b += step
    return ev


def riff(T, pattern, low=36, vel=0.9, period=4.0):
    """pattern: [(offset_beats, tok, dur_beats, vel)] repeated every `period` beats inside each chord."""
    ev = []
    for ci, (name, st, d) in enumerate(T):
        nxt = T[(ci + 1) % len(T)][0]
        b0 = st
        while b0 < st + d - 1e-9:
            for off, tok, du, vv in pattern:
                b = b0 + off
                if b >= st + d - 1e-9:
                    continue
                ev.append((b, mhz(ctone(name, tok, low, nxt)), min(du, st + d - b), vel * vv))
            b0 += period
    return ev


def swing(ev, amt=2.0 / 3):
    def sw(x):
        fl = np.floor(x + 1e-9)
        return fl + amt if abs(x - fl - 0.5) < 1e-6 else x
    return [(sw(b), f, max(sw(b + d) - sw(b), 0.12), v) for b, f, d, v in ev]


def strum_ev(T, pattern, low=55, spread=0.02, vel=0.6):
    """pattern: [(offset, dur, vel, 'd'|'u')] per chord; spread = beats between strings."""
    ev = []
    for name, st, d in T:
        vs = voicing(name, low)
        vs = vs + [vs[0] + 12]
        for off, du, vv, dr in pattern:
            if off >= d - 1e-9:
                continue
            for j, m in enumerate(vs if dr == 'd' else vs[::-1]):
                ev.append((st + off + j * spread, mhz(m), du, vel * vv * (1.0 if j == 0 else 0.85)))
    return ev


def walk_ev(T, low=36, vel=0.85):
    """Walking bass: 2-beat chords root+approach, 4-beat chords root/3rd/5th/approach."""
    ev = []
    for ci, (name, st, d) in enumerate(T):
        nxt = T[(ci + 1) % len(T)][0]
        root, ivs = parse_chord(name)
        r = low + ((root - low) % 12)
        n_ = low + ((parse_chord(nxt)[0] - low) % 12)
        app = n_ - 1 if ci % 2 == 0 else n_ + 1
        tones = [r, app] if d <= 2 else [r, r + ivs[1], r + ivs[2], app]
        for j, m in enumerate(tones[:int(round(d))]):
            ev.append((st + j, mhz(m), 0.92, vel * (1.0 if j == 0 else 0.8)))
    return ev


def roll_ev(st, beats, divs=(1, 2, 4, 8), v0=0.35, v1=1.0):
    """Snare roll that doubles its rate every len(beats)/len(divs) beats (build-ups)."""
    ev = []
    seg = beats / len(divs)
    for k, dv in enumerate(divs):
        step = 1.0 / dv
        b = st + k * seg
        while b < st + (k + 1) * seg - 1e-9:
            ev.append((b, 0.0, step, v0 + (v1 - v0) * (b - st) / beats))
            b += step
    return ev


# --- analog-style mono synth (reese / wobble / filter-swept bass) --------------------------
def tvlp(x, fc, q=0.8, block=32):
    """Time-varying resonant low-pass (RBJ biquad; coefficients updated every `block` samples,
    filter state carried across blocks)."""
    n = len(x)
    fc = np.broadcast_to(np.asarray(fc, dtype=float), (n,))
    f = np.clip(fc[::block], 20.0, 0.45 * SR)
    w0 = TAU * f / SR
    cw, al = np.cos(w0), np.sin(w0) / (2 * q)
    a0 = 1 + al
    B = np.stack([(1 - cw) / 2, 1 - cw, (1 - cw) / 2], 1) / a0[:, None]
    A = np.stack([np.ones_like(cw), -2 * cw / a0, (1 - al) / a0], 1)
    y = np.empty(n)
    zi = np.zeros(2)
    for k, i in enumerate(range(0, n, block)):
        y[i:i + block], zi = ss.lfilter(B[k], A[k], x[i:i + block], zi=zi)
    return y


def line_ctrl(events, spb, N, port=0.02, gap=0.03, smooth=0.004, env_tau=0.15):
    """Monophonic control signals for a whole song: frequency (with portamento), smoothed gate,
    note-on envelope (for the filter)."""
    logf = np.full(N, np.nan)
    gate = np.zeros(N)
    env = np.zeros(N)
    for b, f, d, v in sorted(events, key=lambda e: e[0]):
        i0 = int(round(b * spb * SR))
        i1 = min(N, int(round((b + d) * spb * SR)))
        if i1 <= i0:
            continue
        logf[i0:i1] = np.log2(f)
        gate[i0:max(i0 + 1, i1 - ns(gap))] = v
        env[i0:i1] = np.exp(-t_(i1 - i0) / env_tau)
    idx = np.where(~np.isnan(logf), np.arange(N), 0)
    np.maximum.accumulate(idx, out=idx)
    logf = logf[idx]
    valid = np.nonzero(~np.isnan(logf))[0]
    logf[:valid[0]] = logf[valid[0]]
    if port > 0:
        a = np.exp(-1.0 / (port * SR))
        logf = ss.lfilter([1 - a], [1, -a], logf, zi=[a * logf[0]])[0]
    a2 = np.exp(-1.0 / (smooth * SR))
    gate = ss.lfilter([1 - a2], [1, -a2], gate)
    env = ss.lfilter([1 - a2], [1, -a2], env)
    return 2 ** logf, gate, env


def reese(events, S, det=0.2, cut=380, env_oct=1.2, env_tau=0.15, mod=None, q=1.0, drive=1.8, sub=0.8,
          port=0.03, gap=0.03, spread=(-1.0, 1.0, 0.33), top=5000, sub_oct=0):
    """Mono analog bass over the whole song: detuned saws -> time-varying resonant LP (note-on
    envelope + tempo-synced modulation in octaves) -> drive, plus a clean sine sub.
    Small detune + slow sweeps = the chiptune sections' 'analog' bass; wide detune = DnB reese;
    fast synced modulation = wobble."""
    N = S.N
    fr, g, env = line_ctrl(events, S.spb, N, port, gap, env_tau=env_tau)
    x = sum(o_saw(fr * 2 ** (k * det / 12)) for k in spread) / len(spread)
    octs = env_oct * env
    if mod is not None:
        octs = octs + mod(np.arange(N) / SR / S.spb)
    y = tvlp(x, cut * 2 ** octs, q)
    y = lp(np.tanh(drive * y), top)
    return (0.75 * y + 0.6 * sub * o_sin(fr * 2 ** sub_oct)) * g


def cmod(period, depth, ph=0.0):
    """Tempo-synced raised-cosine LFO (octaves) with a period in beats."""
    return lambda b: depth * (0.5 - 0.5 * np.cos(TAU * (b / period + ph)))


def pmod(spans, default=0.0):
    """Piecewise modulation: [(beat0, beat1, fn)]."""
    def f(b):
        out = np.full(len(b), default, dtype=float)
        for b0, b1, fn in spans:
            m = (b >= b0) & (b < b1)
            out[m] = fn(b[m])
        return out
    return f


def ramp_mod(b0, beats, depth, wob=None):
    """Filter opening over a build (optionally with a synced wobble on top)."""
    if wob is None:
        return lambda b: depth * np.clip((b - b0) / beats, 0, 1)
    return lambda b: depth * np.clip((b - b0) / beats, 0, 1) * (0.4 + 0.6 * (0.5 - 0.5 * np.cos(TAU * b / wob)))


# --- new melodic instruments -----------------------------------------------------------
def i_pwm(f, dur, vel, rate=4.0, depth=0.3, base=0.5, a=0.006, d=0.15, s=0.7, r=0.08, vib=(5.5, 0.18, 0.2),
          cut=None, bend=None):
    e = adsr(dur, a, d, s, r)
    n = len(e)
    fr = ftrack(f, n, vib, bend)
    duty = base + depth * np.sin(TAU * rate * t_(n) + TAU * RNG.random())
    x = o_sq(fr, np.clip(duty, 0.06, 0.94)) * e
    if cut:
        x = lp(x, cut)
    return x * vel * 0.33


def i_supersaw(f, dur, vel, det=0.25, voices=5, a=0.004, d=0.2, s=0.7, r=0.08, bright=7000, dark=1800, ftau=0.15,
               vib=(5.6, 0.12, 0.2)):
    e = adsr(dur, a, d, s, r)
    n = len(e)
    fr = ftrack(f, n, vib)
    x = sum(o_saw(fr * 2 ** ((k / (voices - 1) - 0.5) * 2 * det / 12)) for k in range(voices)) / np.sqrt(voices)
    fe = np.exp(-t_(n) / ftau)
    y = lp(x, bright) * fe + lp(x, dark) * (1 - fe)
    return y * e * vel * 0.3


def i_epiano(f, dur, vel, decay=1.8, rel=0.3, trem=0.0):
    dec = float(np.clip(decay * (262.0 / f) ** 0.4, 0.3, 4.0))
    n = ns(min(dur + rel * 7, dec * 4) + 0.05)
    t = t_(n)
    idx = (0.6 + 1.4 * vel) * np.exp(-t / 0.3)
    x = np.sin(TAU * f * t + idx * np.sin(TAU * f * t)) * np.exp(-t / dec)
    if f * 7 < 0.42 * SR:
        x += 0.2 * np.sin(TAU * f * 7.0 * t) * np.exp(-t / 0.025)
    if trem:
        x *= 1 + trem * np.sin(TAU * 5.0 * t)
    return damp(x * att(n, 0.001), dur, rel) * vel * 0.4


def i_squelch(f, dur, vel, cut=250, env_oct=4.0, tau=0.12, q=5.0, drive=2.5, a=0.002, s=0.8, r=0.04):
    """Acid-style resonant saw."""
    e = adsr(dur, a, 0.12, s, r)
    n = len(e)
    x = o_saw(np.full(n, f))
    fc = cut * 2 ** (env_oct * np.exp(-t_(n) / tau))
    y = np.tanh(drive * tvlp(x, fc, q, block=16))
    return y * e * vel * 0.3


def i_drip(f, dur, vel):
    n = ns(0.16)
    t = t_(n)
    fr = f * 2 ** (-1.2 * np.exp(-t / 0.008))
    x = np.sin(TAU * np.cumsum(fr) / SR) * np.exp(-t / 0.04)
    return fin(x * att(n, 0.0015)) * vel * 0.45


def i_haze(f, dur, vel, a=1.2, r=1.8):
    """Heat-shimmer pad: detuned sines with slow random pitch drift and amplitude flicker."""
    e = adsr(dur, a, 0.5, 0.9, r)
    n = len(e)
    x = np.zeros(n)
    for k in range(3):
        drift = 1 + 0.003 * lp(noise(n), 2.0) * 40
        am = 0.6 + 0.4 * np.clip(lp(noise(n), 4.0) * 30, -1, 1)
        x += np.sin(TAU * np.cumsum(f * 2 ** ((k - 1) * 0.1 / 12) * drift) / SR) * am
    return x * e * vel * 0.18


# --- new drums ---------------------------------------------------------------------------
def sh_noise(n, rate, period=None):
    """NES-style +-1 sample-and-hold noise; with `period` the sequence repeats (metallic 'short mode')."""
    k = int(n * rate / SR) + 2
    src = np.sign(RNG.standard_normal(period or k))
    if period:
        src = np.tile(src, k // period + 1)[:k]
    return src[(np.arange(n) * rate / SR).astype(int)]


def d_chipkick(f, dur, vel):
    n = ns(0.25)
    t = t_(n)
    x = o_tri(48 + 190 * np.exp(-t / 0.022))
    x = lp(np.round(x * 7.5) / 7.5 * np.exp(-t / 0.09), 6000)
    x += lp(sh_noise(n, 12000), 5000) * np.exp(-t / 0.004) * 0.35
    return fin(x * att(n, 0.0005)) * vel * 0.8


def d_chipsnare(f, dur, vel, dec=0.11):
    n = ns(0.3)
    t = t_(n)
    nz = lp(sh_noise(n, 14000), 9000) * np.exp(-t / dec)
    body = lp(o_sq(180 * (1 + 0.6 * np.exp(-t / 0.012)), 0.5, 0.0), 4000) * np.exp(-t / 0.035) * 0.45
    return fin((nz + body) * att(n, 0.0005)) * vel * 0.5


def d_chiphat(f, dur, vel, dec=0.028):
    n = ns(dec * 6)
    t = t_(n)
    x = hp(sh_noise(n, SR, period=93), 5000) * np.exp(-t / dec)
    return fin(lp(x, 12000) * att(n, 0.0005)) * vel * 0.28


def d_bkick(f, dur, vel, f0=46, punch=150, dec=0.24):
    n = ns(dec * 4)
    t = t_(n)
    fr = f0 + punch * np.exp(-t / 0.028) + 60 * np.exp(-t / 0.004)
    x = np.sin(TAU * np.cumsum(fr) / SR) * np.exp(-t / dec)
    x += bp(noise(n), 1500, 7000) * np.exp(-t / 0.0025) * 0.5
    return fin(np.tanh(2.0 * x) * att(n, 0.0004)) * vel * 0.85


def d_bsnare(f, dur, vel, tone=200, dec=0.15):
    n = ns(0.45)
    t = t_(n)
    body = np.sin(TAU * np.cumsum(tone * (1 + 0.5 * np.exp(-t / 0.008))) / SR) * np.exp(-t / 0.05) * 0.8
    body += np.sin(TAU * np.cumsum(tone * 1.72 * (1 + 0.3 * np.exp(-t / 0.006))) / SR) * np.exp(-t / 0.03) * 0.3
    nz = bp(noise(n), 1500, 11000) * (0.6 * np.exp(-t / dec) + 0.6 * np.exp(-t / 0.012))
    return fin(np.tanh(1.6 * (body + nz)) * att(n, 0.0004)) * vel * 0.55


def d_ride(f, dur, vel, dec=0.7):
    n = ns(dec * 3)
    t = t_(n)
    parts = ((2953, 1.0), (3881, 0.7), (4720, 0.6), (5577, 0.45), (6731, 0.35), (8237, 0.25))
    x = sum(a * np.sin(TAU * fq * t + TAU * RNG.random()) for fq, a in parts) * np.exp(-t / dec) * 0.25
    x += hp(noise(n), 6000) * (np.exp(-t / 0.01) * 0.8 + 0.15 * np.exp(-t / (dec * 0.5)))
    return fin(x * att(n, 0.0005)) * vel * 0.22


def d_brush(f, dur, vel):
    n = ns(0.25)
    t = t_(n)
    e = (1 - np.exp(-t / 0.025)) * np.exp(-t / 0.08)
    return fin(bp(noise(n), 2000, 9000) * e) * vel * 0.35


# --- breakbeats: synthesized 4-bar 'amen-style' break, then chopped on the 16th grid ----------
AMEN = [("x.x.......xx....", "....X..o.o..X..o"), ("x.x.......xx....", "....X..o.o..X..o"),
        ("x.x.......x.....", "....X..o.o....X."), ("..xx......x.....", ".o..X..o.o....X.")]

CHOPS = {
    'a': ' '.join(str(i) for i in range(0, 16)), 'b': ' '.join(str(i) for i in range(16, 32)),
    'c': ' '.join(str(i) for i in range(32, 48)), 'd': ' '.join(str(i) for i in range(48, 64)),
    'x': '0 1 2 3 4 5 6 7 8 9 2 3 12 13 14 15',
    'y': '0 1 2 3 4 5 38 39 40 41 10 11 12 13 30 31',
    'z': '0 1 18 19 4 5 6 7 8 9 26 27 4 5 4 5',
    'r': '0 1 2 3 4 5 6 7 4 5 4 5 4s 4s 12s 12s',            # snare roll
    's': '0 1 0 1 4 5 6 7 8 9 10 11 12 12s 12s 12s',         # stutter
    'v': '0 1 2 3 4 5 6 7 8 9 10 11 15r 14r 13r 12r',        # reversed tail into the next bar
    'f': '4s 4s 4s 4s 4 5 4 5 12s 12s 12s 12s 12 13 14 15',  # fill
    'g': '0 1 2 3 4 5 6 7 8 9 10 11 4 4s 12s 12s',
    'h': '0 1 2 3 . . . . 4 5 6 7 8 9 10 11',                # half-time
    'H': '0 1 . . . . 10 11 4 5 6 7 . 13 14 15',
}


def chops(codes):
    return ' '.join(CHOPS[c] for c in codes.split())


def make_break(spb, tone=205, room=0.4, kick_f0=50):
    items = []
    for bar, (kp, sp) in enumerate(AMEN):
        for i in range(16):
            st = (bar * 4 + i * 0.25) * spb
            if kp[i] == 'x':
                items.append((st, d_bkick(0, 0, 1.0 if i == 0 else 0.85, f0=kick_f0, punch=120, dec=0.17)))
            if sp[i] != '.':
                big = sp[i] == 'X'
                items.append((st, d_bsnare(0, 0, 1.0 if big else 0.5, tone=tone, dec=0.13 if big else 0.07)))
            if i % 2 == 0:
                items.append((st, d_ride(0, 0, 0.75 if i % 4 == 0 else 0.55, dec=0.5)))
    items.append(((3 * 4 + 2.5) * spb, d_crash(0, 0, 0.7, dec=0.9)))
    x = mix(16 * spb + 1.0, items)
    x = reverb(x, 0.5, room, 0.5, 0.004)
    x = x / (np.max(np.abs(x)) + 1e-9)
    return np.tanh(1.6 * x) / np.tanh(1.6)


def chop(brk, spb, seq):
    """Re-sequence 16th slices of a break. Tokens: N (slice N), Nr (reversed), Ns (stuttered 32nds),
    '.' (silence). Contiguous slices play through untouched; edges get micro-fades."""
    sl = 0.25 * spb * SR
    P = []
    for tok in seq.split():
        if tok in ('.', '-'):
            P.append(None)
        else:
            m = re.match(r'^(\d+)([rs]?)$', tok)
            P.append((int(m.group(1)), m.group(2)))
    out = np.zeros(int(round(len(P) * sl)) + ns(0.01))
    fi, fo = ns(0.0008), ns(0.003)
    src_ptr = None
    for i, p in enumerate(P):
        if p is None:
            src_ptr = None
            continue
        o0, o1 = int(round(i * sl)), int(round((i + 1) * sl))
        L = o1 - o0
        s, mode = p
        prev = P[i - 1] if i > 0 else None
        nxt = P[i + 1] if i + 1 < len(P) else None
        cont_prev = (mode == '' and prev is not None and prev[1] == '' and prev[0] == s - 1
                     and src_ptr is not None)
        cont_next = mode == '' and nxt is not None and nxt[1] == '' and nxt[0] == s + 1
        a0 = src_ptr if cont_prev else int(round(s * sl))
        seg = brk[a0:a0 + L]
        seg = np.pad(seg, (0, L - len(seg))) if len(seg) < L else seg.copy()
        src_ptr = a0 + L
        if mode == 'r':
            seg = seg[::-1].copy()
        elif mode == 's':
            h = L // 2
            second = seg[:L - h].copy()
            second[:fi] *= np.linspace(0, 1, fi)
            seg = np.concatenate([fin(seg[:h].copy(), 0.002), second])
        if not cont_prev:
            seg[:fi] *= np.linspace(0, 1, fi)
        if not cont_next:
            seg[-fo:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, fo))
        out[o0:o1] += seg
    return out


# --- drum kit bus ---------------------------------------------------------------------------
class Kit:
    SPEC = {
        'ck': (d_chipkick, 0.6, 0.03, {}), 'cs': (d_chipsnare, 0.5, 0.1, {}), 'ch': (d_chiphat, 0.35, 0.04, {}),
        'co': (d_chiphat, 0.28, 0.06, {'dec': 0.11}), 'ct': (d_tom, 0.45, 0.12, {}),
        'bk': (d_bkick, 0.6, 0.02, {}), 'bs': (d_bsnare, 0.42, 0.07, {}), 'bh': (d_hat, 0.25, 0.03, {'dec': 0.022}),
        'rd': (d_ride, 0.3, 0.08, {}), 'cr': (d_crash, 0.42, 0.2, {}), 'sh': (d_shaker, 0.5, 0.08, {}),
        'cl': (d_clave, 0.3, 0.15, {}), 'cg': (d_conga, 0.4, 0.12, {}), 'kd': (k_dhe, 0.55, 0.12, {}),
        'kt': (k_tak, 0.6, 0.12, {}), 'ku': (k_tung, 0.45, 0.12, {}), 'br': (d_brush, 0.5, 0.15, {}),
    }

    def __init__(self):
        self.ev = defaultdict(list)

    def clear(self, lo, hi, keys=None):
        for k in (keys or list(self.ev)):
            self.ev[k] = [e for e in self.ev[k] if not (lo - 1e-9 <= e[0] < hi - 1e-9)]

    def render(self, S, gains=None):
        gains = gains or {}
        for k, evs in self.ev.items():
            if not evs:
                continue
            fn, g, rv, kw = self.SPEC[k]
            S.add(evs, fn, gain=g * gains.get(k, 1.0), rev=rv, hum=0.0005, vj=0.04, name='kit-' + k, **kw)


CHIP_STYLES = {
    'rock':    ("x.....x.x.....x.", "....x.......x...", "x.x.x.x.x.x.x.x.", "..............x."),
    'gallop':  ("x..x..x.x..x..x.", "....x.......x...", "x.xxx.xxx.xxx.xx", ""),
    'sneak':   ("x.........x.....", "....x.......x..o", "..x...x...x...x.", ""),
    'drive':   ("x...x...x...x...", "....x.......x...", "xxo.xxo.xxo.xxo.", "......x.......x."),
    'frantic': ("x.x...x.x.x...x.", "....x..o....x..o", "xoxoxoxoxoxoxoxo", ""),
    'tropic':  ("x..x...x..x.....", "....x.......x...", "x.xox.xox.xox.xo", ""),
}


def chip_beat(D, st, nbars, style='rock', fill_every=4, toms=True):
    k, s, h, o = CHIP_STYLES[style]
    for bar in range(nbars):
        b = st + 4 * bar
        if fill_every and bar % fill_every == fill_every - 1:
            D.ev['ck'] += pat("x.....x.x.......", b)
            D.ev['cs'] += pat("....x..o", b, vmap={'x': 0.85, 'o': 0.4})
            D.ev['ch'] += pat("x.x.x.x.", b, vmap={'x': 0.6})
            if toms:
                D.ev['ct'] += [(b + 2 + 0.25 * j, 260.0 * 0.88 ** j, 0.25, 0.7 + 0.04 * j) for j in range(8)]
            else:
                D.ev['cs'] += pat("x.xxXxXX", b + 2, vmap={'x': 0.6, 'X': 0.95})
        else:
            D.ev['ck'] += pat(k, b)
            D.ev['cs'] += pat(s, b, vmap={'x': 0.85, 'o': 0.35})
            D.ev['ch'] += pat(h, b, vmap={'x': 0.6, 'o': 0.35})
            if o:
                D.ev['co'] += pat(o, b, vmap={'x': 0.5})


DNB_STYLES = {
    'two':  (("x.........x.....", "x.........x..x.."), "....x.......x...", "..x...x...x...x."),
    'roll': (("x.....x...x.....", "x.....x...x...x."), "....x.......x...", "xoxoxoxoxoxoxoxo"),
    'step': (("x.......x.x.....", "x.......x.x..x.."), "....x.......x..o", "..x...x...x...x."),
    'half': (("x.........x.....", "x.....x........."), "........x.......", "x.x.x.x.x.x.x.x."),
}


def dnb_layer(D, st, nbars, style='two', hats=True, snare=True, kick=True):
    ks, s, h = DNB_STYLES[style]
    for bar in range(nbars):
        b = st + 4 * bar
        if kick:
            D.ev['bk'] += pat(ks[bar % 2], b)
        if snare:
            D.ev['bs'] += pat(s, b, vmap={'x': 0.9, 'o': 0.35})
        if hats:
            D.ev['bh'] += pat(h, b, vmap={'x': 0.5, 'o': 0.3})


def riser_sig(dur, f0=150, f1=6000):
    n = ns(dur)
    t = t_(n)
    u = t / t[-1]
    nz = noise(n)
    r = np.zeros(n)
    cs = np.geomspace(f0 * 1.5, f1, 10)
    for k, c in enumerate(cs):
        r += bp(nz, c * 0.7, c * 1.4) * np.exp(-0.5 * ((u - (k + 0.5) / len(cs)) / 0.12) ** 2)
    r *= u ** 1.5
    tone = lp(o_saw(110 * 2 ** (3 * u ** 1.3)), 3000) * u ** 2
    return fin((r * 0.7 + 0.15 * tone) * att(n, 0.01), 0.02)


def subdrop(dur=1.4, f0=110, f1=32):
    n = ns(dur)
    t = t_(n)
    fr = f1 + (f0 - f1) * np.exp(-t / 0.25)
    x = np.sin(TAU * np.cumsum(fr) / SR) * np.exp(-t / 0.5)
    return fin(np.tanh(1.5 * x) * att(n, 0.003))


def clang(f=700, vel=1.0):
    """Cleaver-on-anvil metallic hit (inharmonic FM + noise)."""
    return i_bell(f, 0.5, vel, ratio=1.41, index=3.5, decay=0.6) + \
        fin(hp(noise(ns(0.05)), 3000) * np.exp(-t_(ns(0.05)) / 0.006) * att(ns(0.05), 0.0004)) * 0.3 * vel


def buzz_sig(dur):
    """Dying electrical hum with flicker."""
    n = ns(dur)
    flick = lp((sh_noise(n, 25) > 0).astype(float), 60)
    x = lp(o_saw(np.full(n, 100.0)) + 0.5 * o_sq(np.full(n, 200.0), 0.5), 1800) * flick
    return fin(x * smooth_env(n, 0.02, 0.1))


def smooth_env(n, a, r):
    t = t_(n)
    dur = n / SR
    up = np.clip(t / max(a, 1e-4), 0, 1)
    dn = np.clip((dur - t) / max(r, 1e-4), 0, 1)
    return (0.5 - 0.5 * np.cos(np.pi * up)) * (0.5 - 0.5 * np.cos(np.pi * dn))


# --- periodic ambience layers (length n, exactly loopable) ---------------------------------
def _waves(n):
    c = max(1, int(round(n / ns(5.0))))
    w1 = warp_lfo(n, c, 0.0, 3.0, 0.6) * (0.85 + 0.15 * plfo(n, max(1, c // 2), 0.2))
    w2 = warp_lfo(n, c, 0.06, 5.0, 0.7)
    surf = pnoise(n, 60, 1100) * (0.15 + w1)
    foam = pnoise(n, 1500, 9000, tilt=-0.2) * (0.05 + w2) * 0.6
    lap = pnoise(n, 100, 600) * warp_lfo(n, int(round(c * 2.5)), 0.3, 2.0, 0.3) * 0.2
    x = surf + foam + lap + pnoise(n, 80, 3000, tilt=-0.5) * 0.15
    return x - x.mean()


def _night(n, frogs=True):
    x = pnoise(n, 100, 2000, tilt=-0.6) * 0.04
    scale = n / ns(10.0)
    for f, k, pulses, rate, amp in [(4300.0, 16, 3, 30.0, 0.8), (5100.0, 13, 4, 36.0, 0.5), (3800.0, 21, 2, 26.0, 0.35)]:
        k = max(1, int(round(k * scale)))
        period = n // k
        off = RNG.integers(0, period)
        for j in range(k):
            c = i_cricket(f * RNG.uniform(0.995, 1.005), 0.1, amp * RNG.uniform(0.8, 1.0), pulses, rate)
            place_wrap(x, c, off + j * period + RNG.integers(-200, 200))
    if frogs:
        m = ns(0.14)
        tm = t_(m)
        for _ in range(int(round(5 * scale))):
            f = RNG.uniform(320, 460)
            cr = np.sin(TAU * f * tm) * (0.5 + 0.5 * np.sin(TAU * 38 * tm)) ** 3 * np.sin(np.pi * tm / tm[-1])
            cr = lp(cr + 0.3 * np.sin(TAU * 2 * f * tm) * np.sin(np.pi * tm / tm[-1]), 2500) * 0.35
            i = RNG.integers(0, n)
            place_wrap(x, cr, i)
            place_wrap(x, cr * 0.8, i + ns(0.2))
    return x - x.mean()


def _bubbles(n, count):
    x = pnoise(n, 40, 300) * 0.05
    m = ns(0.09)
    tm = t_(m)
    for _ in range(count):
        f = RNG.uniform(120, 320)
        b = np.sin(TAU * np.cumsum(f * (1 + 1.6 * tm / 0.09)) / SR) * np.sin(np.pi * tm / tm[-1]) ** 2
        place_wrap(x, b * RNG.uniform(0.3, 1.0), RNG.integers(0, n))
    return x - x.mean()


def _crackle_loop(n, count):
    y = np.zeros(n)
    for _ in range(count):
        d = RNG.uniform(0.0008, 0.004)
        m = ns(d * 5)
        tm = t_(m)
        c = hp(noise(m), RNG.uniform(1000, 4000)) * np.exp(-tm / d) * att(m, 0.0003)
        place_wrap(y, c * min(RNG.pareto(2.5), 2.5) * 0.4, RNG.integers(0, n))
    y = cfilt(y, lambda v: lp(v, 5000, 2))
    return y + pnoise(n, 300, 4000) * 0.02


# =====================================================================================
# MUSIC v2 -- battle themes (chiptune with drum & bass sections), DnB boss themes
# =====================================================================================
B1_A = ("D5:1 A4:.5 D5:.5 F#5:1 A5:1 | G5:1.5 F#5:.5 E5:1 D5:1 | F#5:1.5 E5:.5 D5:1 B4:1 | C#5:1 E5:1 A5:2 | "
        "D5:1 A4:.5 D5:.5 F#5:1 A5:1 | B5:1.5 A5:.5 G5:1 B5:1 | A5:1 G5:.5 F#5:.5 E5:1 G5:1 | "
        "A5:2 G5:.5 F#5:.5 E5:.5 C#5:.5")
B1_B = ("D5:1.5 C#5:.5 D5:1 F#5:1 | G5:1.5 F#5:.5 G5:1 B5:1 | A5:1.5 G5:.5 F#5:1 D5:1 | E5:2 C#5:1 E5:1 | "
        "D6:1.5 B5:.5 G5:1 D6:1 | C#6:1.5 A5:.5 E5:1 C#6:1 | D6:1 Bb5:1 E6:1 C6:1 | F#6:3 r:1")
B1_D = ("B5:.75 B5:.75 F#5:.5 A5:1 B5:1 | r:.5 D6:.5 B5:.5 G5:.5 A5:1 B5:1 | F#5:.75 F#5:.75 D5:.5 E5:1 F#5:1 | "
        "r:.5 A5:.5 E5:.5 C#5:.5 E5:2 | B5:.75 B5:.75 F#5:.5 A5:1 B5:1 | r:.5 D6:.5 B5:.5 G5:.5 E6:1 D6:1 | "
        "B5:.75 G5:.75 E5:.5 G5:1 B5:1 | C#6:1 E6:1 A5:2")


def song_battle_1():
    """Heroic chip battle (D major, 172 bpm): square lead + brass, filter-swept analog bass;
    DnB pop-ups at the section seams and an 8-bar amen/reese section."""
    A = Arr()
    a = A.sec('chip', ['D', 'G', 'Bm', 'A', 'D', 'G', 'Em', 'A'], B1_A)
    b = A.sec('chip', ['Bm', 'G', 'D', 'A', 'G', 'A', ('Bb', 2), ('C', 2), 'D'], B1_B)
    d = A.sec('dnb', ['Bm', 'G', 'D', 'A', 'Bm', 'G', 'Em', 'A'], B1_D)
    S = Song(172, A.pos, tail=4, t60=1.2, bright=0.5, drive=1.6)
    la, lb, ld = lead_ev(a, 0.9), lead_ev(b, 0.9), lead_ev(d, 0.85)
    S.add(la + lb, i_square, gain=0.7, rev=0.16, echo=(0.75, 0.2, 0.12), duty=0.25, vib=(6.0, 0.18, 0.15), name='lead')
    S.add(shift(lb, semis=-12, velmul=0.7), i_brass, gain=0.4, rev=0.2, name='brass')
    S.add(ld, i_supersaw, gain=0.5, rev=0.18, echo=(0.75, 0.25, 0.16), name='dnb-saw')
    S.add(ld, i_square, gain=0.3, rev=0.12, duty=0.125, vib=None, a=0.002, d=0.08, s=0.5, r=0.04, name='dnb-sq')
    cb = ostinato(a['T'], ['r', 'o'], 0.5, 38, 0.75) + \
        ostinato(b['T'], ['r', 'r', 'o', 'r', 'f', 'r', 'o', 'A'], 0.5, 38, 0.75)
    S.add_sig(reese(cb, S, det=0.08, cut=240, env_oct=2.6, env_tau=0.07, q=1.8, drive=1.4, sub=0.45,
                    mod=cmod(32, 1.4)), gain=0.7, rev=0.03, name='chip-bass')
    rz = riff(d['T'], [(0, 'r', 1.4, 1.0), (1.5, 'r', 0.5, 0.8), (2.5, 'o', 0.7, 0.9), (3.25, 'f', 0.7, 0.85)], low=35)
    S.add_sig(reese(rz, S, det=0.22, cut=280, env_oct=1.3, env_tau=0.2, q=1.3, drive=2.4, sub=1.0, mod=cmod(2, 1.0)),
              gain=0.8, rev=0.02, name='reese')
    S.add(arp_ev(b['T'] + d['T'], [0, 1, 2, 3, 4, 5, 4, 3], 0.25, low=62, vel=0.4), i_square, gain=0.4, rev=0.2,
          duty=0.125, a=0.002, d=0.04, s=0.3, r=0.02, vib=None, name='arp')
    S.add(pad_ev(A.T('chip'), low=54, vel=0.45), i_strings, gain=0.28, rev=0.35, a=0.1, r=0.4, cut=2200, name='pad')
    S.add(pad_ev(d['T'], low=52, vel=0.5), i_pad, gain=0.3, rev=0.45, a=0.4, r=1.0, name='dnb-pad')
    D = Kit()
    chip_beat(D, a['start'], 8, 'rock')
    chip_beat(D, b['start'], 8, 'gallop')
    D.clear(a['start'] + 30, a['start'] + 32)
    D.clear(b['start'] + 28, b['start'] + 32)
    dnb_layer(D, d['start'], 8, 'two', snare=False)
    D.ev['cr'] += [(a['start'], 0, 1, 0.9), (b['start'], 0, 1, 0.8), (d['start'], 0, 1, 1.0), (d['start'] + 16, 0, 1, 0.7)]
    D.render(S)
    brk = make_break(S.spb)
    S.add_sig(chop(brk, S.spb, '4 5 4 5 12s 12s 12 13'), a['start'] + 30, gain=0.85, rev=0.04, name='pop-1')
    S.add_sig(chop(brk, S.spb, CHOPS['f']), b['start'] + 28, gain=0.85, rev=0.04, name='pop-2')
    S.add_sig(chop(brk, S.spb, chops('a b x c a b z v')), d['start'], gain=1.0, rev=0.04, name='break')
    S.add_sig(riser_sig(4 * S.spb), b['start'] + 28, gain=0.3, rev=0.2, name='riser')
    S.add_sig(subdrop(), d['start'], gain=0.5, rev=0.0, name='subdrop')
    return S.render()


B2_A = ("F5:.25 r:.25 Ab5:.25 r:.25 C6:.5 B5:.5 C6:.5 r:.5 Ab5:.5 F5:.5 | G5:.5 Ab5:.5 G5:.5 F5:.5 E5:1 C5:1 | "
        "F5:.25 r:.25 Ab5:.25 r:.25 Db6:.5 C6:.5 Db6:.5 r:.5 Ab5:.5 F5:.5 | E5:.5 G5:.5 Bb5:.5 Db6:.5 C6:2 | "
        "F5:.25 r:.25 Ab5:.25 r:.25 C6:.5 B5:.5 C6:.5 r:.5 Ab5:.5 F5:.5 | "
        "Ab5:.5 G5:.5 F5:.5 E5:.5 F5:.5 G5:.5 Ab5:.5 B5:.5 | Bb5:1 Gb5:.5 Db6:1 Bb5:.5 Gb5:1 | "
        "G5:.5 E5:.5 C5:.5 Db5:.5 C5:2")
B2_B = ("Db6:1.5 C6:.5 Bb5:1 F5:1 | Ab5:1.5 G5:.5 F5:1 C5:1 | Db6:1.5 Eb6:.5 F6:1 Db6:1 | C6:3 r:1 | "
        "F6:1 Eb6:.5 Db6:.5 C6:1 Ab5:1 | Bb5:1 Db6:1 Gb6:1.5 F6:.5 | E6:1 Db6:1 Bb5:1 G5:1 | "
        "C6:.5 B5:.5 Bb5:.5 A5:.5 Ab5:.5 G5:.5 Gb5:.5 E5:.5")
B2_D = ("F5:.75 Ab5:.75 C6:.5 r:.5 B5:.5 C6:1 | r:1 Db6:.5 C6:.5 Ab5:1 F5:1 | F5:.75 Bb5:.75 Db6:.5 r:.5 C6:.5 Db6:1 | "
        "r:1 E6:.5 Db6:.5 C6:1 G5:1 | F5:.75 Ab5:.75 C6:.5 r:.5 B5:.5 C6:1 | r:1 F6:.5 Eb6:.5 Db6:1 Ab5:1 | "
        "Gb5:.75 Bb5:.75 Db6:.5 r:.5 F6:.5 Gb6:1 | E6:1 C6:1 G5:.5 E5:.5 C5:1")


def song_battle_2():
    """Sneaky / sinister (F minor, 168 bpm): tiptoe 12.5% pulse with echo, Neapolitan chords,
    resonant staccato bass; half-time-into-rolling DnB with acid squelch and a dark reese."""
    A = Arr()
    a = A.sec('chip', ['Fm', 'Fm', 'Db', 'C7', 'Fm', 'Fm', 'Gb', 'C7'], B2_A)
    b = A.sec('chip', ['Bbm', 'Fm', 'Bbm', 'Fm', 'Db', 'Gb', 'Edim7', 'C7'], B2_B)
    d = A.sec('dnb', ['Fm', 'Db', 'Bbm', 'C', 'Fm', 'Db', 'Gb', 'C7'], B2_D)
    S = Song(168, A.pos, tail=4, t60=1.5, bright=0.4, drive=1.6)
    la, lb, ld = lead_ev(a, 0.85), lead_ev(b, 0.85), lead_ev(d, 0.9)
    S.add(la, i_square, gain=0.7, rev=0.2, echo=(0.75, 0.32, 0.25), duty=0.125, a=0.002, d=0.07, s=0.45, r=0.03,
          vib=None, name='tiptoe')
    S.add(lb, i_square, gain=0.6, rev=0.25, echo=(1.5, 0.25, 0.18), duty=0.125, vib=(5.0, 0.25, 0.2), name='lead-b')
    S.add(shift(lb, semis=-12, velmul=0.6), i_strings, gain=0.35, rev=0.3, a=0.05, r=0.3, cut=1800, voices=2,
          name='lead-b-low')
    S.add(shift(ld, semis=-12), i_squelch, gain=0.5, rev=0.12, echo=(0.75, 0.3, 0.2), cut=220, env_oct=4.2, q=5.5,
          name='acid')
    S.add(ld, i_square, gain=0.3, rev=0.2, duty=0.25, vib=None, a=0.002, d=0.1, s=0.5, r=0.03, name='dnb-sq')
    cb = ostinato(a['T'], ['r', None, 'o', None, 'r', 't', None, 'A'], 0.5, 41, 0.5) + \
        ostinato(b['T'], ['r', None, 'r', 'o', None, 'r', 'f', 'A'], 0.5, 41, 0.5)
    S.add_sig(reese(cb, S, det=0.05, cut=200, env_oct=2.8, env_tau=0.05, q=2.6, drive=1.6, sub=0.5, gap=0.02,
                    mod=cmod(16, 0.8)), gain=0.7, rev=0.04, name='sneak-bass')
    rz = riff(d['T'], [(0, 'r', 0.75, 1.0), (0.75, 'r', 0.75, 0.85), (1.5, 'o', 0.5, 0.8), (2.5, 'r', 1.5, 0.9)], low=29)
    S.add_sig(reese(rz, S, det=0.3, cut=170, env_oct=1.6, env_tau=0.25, q=1.4, drive=2.8, sub=1.0, mod=cmod(4, 1.6)),
              gain=0.85, rev=0.02, name='reese')
    S.add(arp_ev(a['T'], [None, None, 6, None, None, 5, None, 4], 0.5, low=72, vel=0.35), i_bell, gain=0.35, rev=0.5,
          ratio=3.5, index=1.0, decay=0.8, name='celesta')
    S.add(pad_ev(b['T'], low=53, vel=0.45), i_strings, gain=0.3, rev=0.4, a=0.3, r=0.6, cut=1500, trem=0.5, name='trem')
    S.add(pad_ev(d['T'], low=48, vel=0.45), i_choir, gain=0.25, rev=0.5, vowel='o', a=0.6, r=1.0, name='choir')
    D = Kit()
    chip_beat(D, a['start'], 8, 'sneak', toms=False)
    chip_beat(D, b['start'], 8, 'sneak')
    for bar in range(16):
        D.ev['cl'] += pat("......x.......x.", 4 * bar, vmap={'x': 0.5})
    D.clear(a['start'] + 14, a['start'] + 16)
    D.clear(b['start'] + 28, b['start'] + 32)
    dnb_layer(D, d['start'], 4, 'half', snare=False)
    dnb_layer(D, d['start'] + 16, 4, 'step', snare=False)
    D.ev['cr'] += [(a['start'], 0, 1, 0.7), (d['start'], 0, 1, 1.0), (d['start'] + 16, 0, 1, 0.8)]
    D.render(S)
    brk = make_break(S.spb, tone=185)
    S.add_sig(chop(brk, S.spb, '4 5 4 5 4s 4s 12s 12s'), a['start'] + 14, gain=0.75, rev=0.05, name='pop-1')
    S.add_sig(chop(brk, S.spb, CHOPS['f']), b['start'] + 28, gain=0.8, rev=0.05, name='pop-2')
    S.add_sig(chop(brk, S.spb, chops('h H h g a y z v')), d['start'], gain=1.0, rev=0.05, name='break')
    S.add_sig(subdrop(), d['start'], gain=0.5, rev=0.0, name='subdrop')
    return S.render()


B3_A = ("E5:.5 F#5:.5 A5:1 C#6:.5 B5:.5 A5:1 | F#5:1.5 E5:.5 C#5:1 E5:1 | F#5:.5 A5:.5 B5:1 A5:.5 F#5:.5 E5:1 | "
        "E5:1 B4:1 E5:.5 F#5:.5 G#5:1 | E5:.5 F#5:.5 A5:1 C#6:.5 E6:.5 C#6:1 | B5:.5 A5:.5 F#5:1 A5:1 C#6:1 | "
        "D6:1.5 C#6:.5 B5:1 F#5:1 | G#5:1 B5:1 E6:2")
B3_B = ("r:.5 A5:.5 F#5:.5 A5:1 B5:.5 A5:1 | r:.5 B5:.5 G#5:.5 B5:1 C#6:.5 B5:1 | E6:1.5 C#6:.5 B5:1 G#5:1 | "
        "A5:1.5 F#5:.5 E5:1 C#5:1 | D5:.5 F#5:.5 A5:.5 D6:1 C#6:.5 A5:1 | B5:.5 G#5:.5 E5:.5 B5:1 C#6:.5 B5:1 | "
        "A5:1 C#6:1 F#6:1 E6:1 | E6:2 B5:.5 C#6:.5 E6:1")
B3_D = ("F#5:.75 A5:.75 C#6:.5 B5:1 A5:1 | r:.5 F#5:.5 A5:.5 D6:.5 C#6:1 A5:1 | E5:.75 A5:.75 C#6:.5 E6:1 C#6:1 | "
        "r:.5 B5:.5 G#5:.5 E5:.5 B5:2 | F#5:.75 A5:.75 C#6:.5 B5:1 A5:1 | r:.5 F#5:.5 A5:.5 D6:.5 E6:1 F#6:1 | "
        "D6:.75 B5:.75 F#5:.5 A5:1 B5:1 | G#5:1 B5:1 E6:1 r:1")


def song_battle_3():
    """Tropical-percussive (A major pentatonic, 170 bpm): steel pan + marimba lead, interlocking
    gamelan kotekan, kendang/congas/shaker; breaks + reese under the metallophones."""
    A = Arr()
    a = A.sec('chip', ['A', 'F#m', 'D', 'E', 'A', 'F#m', 'Bm', 'E'], B3_A)
    b = A.sec('chip', ['D', 'E', 'C#m', 'F#m', 'D', 'E', 'F#m', 'E'], B3_B)
    d = A.sec('dnb', ['F#m', 'D', 'A', 'E', 'F#m', 'D', 'Bm', 'E'], B3_D)
    S = Song(170, A.pos, tail=5, t60=1.4, bright=0.6, drive=1.55)
    la, lb, ld = lead_ev(a, 0.85), lead_ev(b, 0.85), lead_ev(d, 0.85)
    S.add(la + lb + ld, i_steel, gain=0.8, rev=0.22, echo=(0.75, 0.22, 0.15), name='steel')
    S.add(shift(la + lb, semis=-12, velmul=0.55), i_marimba, gain=0.5, rev=0.2, name='marimba-dbl')
    S.add(ld, i_square, gain=0.3, rev=0.15, duty=0.25, vib=(6.0, 0.15, 0.15), name='dnb-sq')
    kot = b['T'] + d['T']
    S.add(arp_ev(kot, [0, None, 1, None, 2, None, 1, None], 0.25, low=64, vel=0.5), i_metallo, gain=0.38, rev=0.25,
          decay=0.35, ombak=5.0, mute=1.4, name='polos')
    S.add(arp_ev(kot, [None, 2, None, 3, None, 4, None, 3], 0.25, low=64, vel=0.45), i_metallo, gain=0.34, rev=0.25,
          decay=0.35, ombak=5.0, mute=1.4, name='sangsih')
    S.add(arp_ev(a['T'], [0, 2, 1, 3, 1, 2, 0, 2], 0.5, low=55, vel=0.5, accents=[1, .6, .7, .9, .6, .7, .9, .6]),
          i_marimba, gain=0.5, rev=0.2, name='marimba-arp')
    S.add([(s['start'] + 16 * k, mhz(nm('A1')), 4, 0.9) for s in (a, b, d) for k in range(2)], i_gong, gain=0.45,
          rev=0.3, decay=4.0, beat=1.2, name='gong')
    cb = ostinato(a['T'] + b['T'], ['r', None, None, 'f', None, None, 'o', None], 0.5, 33, 0.9)
    S.add_sig(reese(cb, S, det=0.1, cut=300, env_oct=2.2, env_tau=0.09, q=1.5, drive=1.5, sub=0.6, mod=cmod(32, 1.2)),
              gain=0.75, rev=0.03, name='bass')
    rz = riff(d['T'], [(0, 'r', 1.0, 1.0), (1.5, 'f', 0.5, 0.8), (2.0, 'r', 0.75, 0.85), (3.0, 'o', 1.0, 0.85)], low=30)
    S.add_sig(reese(rz, S, det=0.2, cut=320, env_oct=1.2, env_tau=0.18, q=1.2, drive=2.0, sub=1.0, mod=cmod(1, 1.0)),
              gain=0.8, rev=0.02, name='reese')
    D = Kit()
    chip_beat(D, a['start'], 8, 'tropic', toms=False)
    chip_beat(D, b['start'], 8, 'tropic')
    for bar in range(int(A.pos // 4)):
        st = 4 * bar
        D.ev['kd'] += pat("x......x..x.....", st, vmap={'x': 0.7})
        D.ev['kt'] += pat("...x.......x.x..", st, vmap={'x': 0.55})
        D.ev['sh'] += pat("x.xox.xox.xox.xo", st, vmap={'x': 0.5, 'o': 0.3})
        D.ev['cg'] += [(bb, 330.0, dd, v) for bb, _, dd, v in pat("..x...x...xx..x.", st, vmap={'x': 0.55})]
        D.ev['cg'] += [(bb, 220.0, dd, v) for bb, _, dd, v in pat("......x.......x.", st, vmap={'x': 0.6})]
    D.clear(a['start'] + 30, a['start'] + 32, ['ck', 'cs', 'ch', 'co', 'ct'])
    D.clear(b['start'] + 28, b['start'] + 32, ['ck', 'cs', 'ch', 'co', 'ct'])
    dnb_layer(D, d['start'], 8, 'roll', snare=False, hats=False)
    D.ev['cr'] += [(a['start'], 0, 1, 0.7), (d['start'], 0, 1, 1.0)]
    D.render(S, gains={'sh': 0.8})
    brk = make_break(S.spb, tone=220)
    S.add_sig(chop(brk, S.spb, '0 1 4 5 12s 12s 12 13'), a['start'] + 30, gain=0.8, rev=0.05, name='pop-1')
    S.add_sig(chop(brk, S.spb, CHOPS['f']), b['start'] + 28, gain=0.8, rev=0.05, name='pop-2')
    S.add_sig(chop(brk, S.spb, chops('a b a c x b z v')), d['start'], gain=0.95, rev=0.05, name='break')
    S.add_sig(subdrop(), d['start'], gain=0.45, rev=0.0, name='subdrop')
    return S.render()


B4_A = ("C#5:.25 E5:.25 G#5:.25 C#6:.25 B5:.25 G#5:.25 E5:.25 G#5:.25 C#6:.5 D#6:.5 E6:1 | "
        "E6:.25 C#6:.25 A5:.25 E5:.25 A5:.25 C#6:.25 E6:.25 A6:.25 G#6:1 E6:1 | "
        "F#6:.5 E6:.25 D#6:.25 E6:.5 C#6:.5 A5:.5 C#6:.5 F#5:1 | "
        "D#6:.25 C#6:.25 B#5:.25 C#6:.25 D#6:.25 E6:.25 D#6:.25 B#5:.25 G#5:2 | "
        "C#5:.25 E5:.25 G#5:.25 C#6:.25 B5:.25 G#5:.25 E5:.25 G#5:.25 C#6:.5 D#6:.5 E6:1 | "
        "E6:.25 C#6:.25 A5:.25 E5:.25 A5:.25 C#6:.25 E6:.25 F#6:.25 G#6:.5 A6:.5 E6:1 | "
        "F#6:.5 D6:.5 A5:.5 F#5:.5 A5:.5 D6:.5 F#6:1 | G#6:.5 F#6:.25 E6:.25 D#6:.5 B#5:.5 G#5:.5 B#5:.5 D#6:1")
B4_D1 = ("C#6:.75 C#6:.75 G#5:.5 B5:1 C#6:1 | A5:.75 A5:.75 E5:.5 G#5:1 A5:1 | B5:.75 B5:.75 F#5:.5 A5:1 B5:1 | "
         "G#5:.5 B#5:.5 D#6:.5 G#6:.5 F#6:1 D#6:1")
B4_B = ("E6:1.5 C#6:.5 A5:1 C#6:1 | D#6:1.5 B5:.5 F#5:1 D#6:1 | E6:1 G#6:1 E6:1 C#6:1 | "
        "B5:.5 C#6:.5 D#6:.5 E6:.5 G#6:2 | A6:1.5 G#6:.5 F#6:1 C#6:1 | B#5:1.5 D#6:.5 G#6:1 F#6:1 | "
        "E6:1 C#6:1 D#6:1 F#6:1 | G#6:2 F#6:.5 E6:.5 D#6:.5 B#5:.5")
B4_D2 = B4_D1 + (" | C#6:.75 E6:.75 G#6:.5 F#6:1 E6:1 | C#6:.75 E6:.75 A6:.5 G#6:1 E6:1 | "
                 "F#6:.75 D6:.75 A5:.5 D6:1 F#6:1 | G#6:.5 F#6:.5 D#6:.5 B#5:.5 G#5:2")


def song_battle_4():
    """Frantic (C# minor, 176 bpm): detuned supersaw 16th runs, pulse arps, gallop bass;
    two DnB bursts (4 + 8 bars) with 1/4 -> 1/8 wobbles."""
    A = Arr()
    a = A.sec('chip', ['C#m', 'A', 'F#m', 'G#', 'C#m', 'A', 'D', 'G#7'], B4_A)
    d1 = A.sec('dnb', ['C#m', 'A', 'B', 'G#'], B4_D1)
    b = A.sec('chip', ['A', 'B', 'C#m', 'C#m', 'F#m', 'G#', ('A', 2), ('B', 2), 'G#7'], B4_B)
    d2 = A.sec('dnb', ['C#m', 'A', 'B', 'G#', 'C#m', 'A', 'D', 'G#7'], B4_D2)
    S = Song(176, A.pos, tail=4, t60=1.1, bright=0.55, drive=1.7)
    la, l1, lb, l2 = lead_ev(a, 0.85), lead_ev(d1, 0.9), lead_ev(b, 0.85), lead_ev(d2, 0.9)
    S.add(la + lb, i_supersaw, gain=0.55, rev=0.15, echo=(0.75, 0.2, 0.12), name='saw-lead')
    S.add(shift(la + lb, semis=-12, velmul=0.5), i_square, gain=0.25, rev=0.12, duty=0.5, vib=None, a=0.002, d=0.08,
          s=0.6, r=0.03, name='sq-low')
    S.add(l1 + l2, i_distsaw, gain=0.45, rev=0.15, drive=3.0, cut=3800, vib=None, name='dnb-dist')
    S.add(l1 + l2, i_square, gain=0.3, rev=0.15, duty=0.25, vib=None, name='dnb-sq')
    S.add(arp_ev(a['T'] + b['T'], [0, 1, 2, 3, 4, 3, 2, 1], 0.25, low=61, vel=0.4), i_square, gain=0.35, rev=0.15,
          duty=0.125, a=0.002, d=0.04, s=0.3, r=0.02, vib=None, name='arp')
    S.add(pad_ev(a['T'] + b['T'], low=52, vel=0.45), i_strings, gain=0.25, rev=0.3, a=0.05, r=0.3, cut=2500,
          trem=0.4, name='strings')
    cb = ostinato(a['T'], ['r', 'o', 'r', 'o', 'r', 'o', 'f', 'o'], 0.5, 37, 0.7) + \
        riff(b['T'], [(0, 'r', 0.4, 1.0), (0.5, 'r', 0.2, 0.75), (0.75, 'o', 0.2, 0.8)], low=37, period=1.0)
    S.add_sig(reese(cb, S, det=0.1, cut=260, env_oct=2.4, env_tau=0.06, q=1.7, drive=1.6, sub=0.45, gap=0.02,
                    mod=cmod(16, 1.2)), gain=0.7, rev=0.03, name='chip-bass')
    rz = riff(d1['T'] + d2['T'], [(0, 'r', 2.5, 1.0), (2.5, 'o', 0.5, 0.8), (3, 'f', 1, 0.85)], low=32)
    mod = pmod([(d1['start'], d1['start'] + 16, cmod(1, 1.6)), (d2['start'], d2['start'] + 16, cmod(1, 2.2)),
                (d2['start'] + 16, d2['start'] + 32, cmod(0.5, 2.4))])
    S.add_sig(reese(rz, S, det=0.25, cut=200, env_oct=1.0, env_tau=0.2, q=1.6, drive=2.6, sub=1.0, mod=mod),
              gain=0.8, rev=0.02, name='reese')
    D = Kit()
    chip_beat(D, a['start'], 8, 'frantic')
    chip_beat(D, b['start'], 8, 'frantic')
    dnb_layer(D, d1['start'], 4, 'roll', snare=False)
    dnb_layer(D, d2['start'], 8, 'roll', snare=False)
    D.ev['cr'] += [(s['start'], 0, 1, 1.0) for s in (a, d1, b, d2)] + [(d2['start'] + 16, 0, 1, 0.8)]
    D.render(S)
    brk = make_break(S.spb, tone=200)
    S.add_sig(chop(brk, S.spb, chops('a x r f')), d1['start'], gain=0.95, rev=0.04, name='break-1')
    S.add_sig(chop(brk, S.spb, chops('a b c d a z s v')), d2['start'], gain=1.0, rev=0.04, name='break-2')
    S.add_sig(riser_sig(4 * S.spb), d2['start'] - 4, gain=0.3, rev=0.2, name='riser')
    S.add_sig(subdrop(), d1['start'], gain=0.45, name='subdrop-1')
    S.add_sig(subdrop(), d2['start'], gain=0.5, name='subdrop-2')
    return S.render()


B5_A = ("D5:1.5 G5:.5 Bb5:1 A5:1 | G5:2 Bb4:1 Eb5:1 | F5:1.5 D5:.5 Bb4:1 C5:1 | D5:1 C5:1 A4:2 | "
        "D5:1.5 G5:.5 Bb5:1 D6:1 | C6:1.5 Bb5:.5 G5:1 Eb5:1 | Eb5:1 G5:1 C6:1 Bb5:1 | A5:2 F#5:1 D5:1")
B5_B = ("G5:1.5 Bb5:.5 Eb6:1 D6:1 | C6:1.5 A5:.5 F5:1 C6:1 | D6:1.5 C6:.5 A5:1 F5:1 | G5:3 r:1 | "
        "Eb6:1.5 D6:.5 C6:1 G5:1 | A5:1 C6:1 F6:1.5 Eb6:.5 | D6:1.5 C6:.5 Bb5:1 F5:1 | F#5:1 A5:1 C6:1 D6:1")
B5_D = ("Bb5:2 A5:1 G5:1 | G5:1.5 F5:.5 Eb5:1 G5:1 | F5:2 D5:1 F5:1 | A5:1.5 C6:.5 A5:1 F5:1 | "
        "G5:1 C6:1 Eb6:1.5 D6:.5 | D6:1.5 Bb5:.5 G5:1 D5:1 | Eb5:1 G5:1 Bb5:1 C6:1 | F#5:1 A5:1 D6:2")


def song_battle_5():
    """Melancholic but driving (G minor, 164 bpm): PWM lead + triangle counter-line over driving
    8th-note analog bass; liquid DnB section with e-piano, soft reese and a sad triangle lead."""
    A = Arr()
    a = A.sec('chip', ['Gm', 'Eb', 'Bb', 'F', 'Gm', 'Eb', 'Cm', 'D'], B5_A)
    b = A.sec('chip', ['Eb', 'F', 'Dm', 'Gm', 'Cm', 'F', 'Bb', 'D7'], B5_B)
    d = A.sec('dnb', ['Gm', 'Eb', 'Bb', 'F', 'Cm', 'Gm', 'Eb', 'D'], B5_D)
    S = Song(164, A.pos, tail=5, t60=1.8, bright=0.45, drive=1.5)
    la, lb, ld = lead_ev(a, 0.85), lead_ev(b, 0.85), lead_ev(d, 0.8)
    S.add(la + lb, i_pwm, gain=0.65, rev=0.25, echo=(0.75, 0.25, 0.18), rate=3.0, depth=0.3, vib=(5.2, 0.22, 0.25),
          name='pwm-lead')
    S.add(shift(lb, semis=-12, velmul=0.5), i_tri, gain=0.45, rev=0.25, vib=(5.0, 0.1, 0.3), name='tri-counter')
    S.add(ld, i_tri, gain=0.55, rev=0.35, echo=(1.5, 0.3, 0.25), a=0.02, d=0.2, s=0.8, r=0.15,
          vib=(5.3, 0.2, 0.2), name='dnb-tri')
    S.add(shift(ld, semis=12, velmul=0.4), i_bell, gain=0.25, rev=0.5, ratio=2.0, index=0.8, decay=0.8, name='dnb-bell')
    S.add(pad_ev(A.T('chip'), low=55, vel=0.5), i_strings, gain=0.32, rev=0.4, a=0.3, r=0.8, cut=2000, name='strings')
    ep = []
    for name, st, dd in d['T']:
        for off, du in ((0, 1.4), (1.5, 0.4), (2.5, 1.4)):
            ep += [(st + off, mhz(m), du, 0.55) for m in voicing(name, 55)]
    S.add(ep, i_epiano, gain=0.4, rev=0.35, trem=0.15, name='epiano')
    cb = ostinato(a['T'] + b['T'], ['r'] * 7 + ['o'], 0.5, 31, 0.8, vels=[1, .7, .85, .7, .95, .7, .85, .8])
    S.add_sig(reese(cb, S, det=0.09, cut=280, env_oct=2.0, env_tau=0.08, q=1.4, drive=1.5, sub=0.6, mod=cmod(16, 1.0)),
              gain=0.75, rev=0.03, name='drive-bass')
    rz = riff(d['T'], [(0, 'r', 3.0, 1.0), (3, 'f', 1.0, 0.8)], low=31)
    S.add_sig(reese(rz, S, det=0.16, cut=260, env_oct=0.8, env_tau=0.3, q=1.0, drive=1.6, sub=1.1, port=0.06,
                    mod=cmod(4, 0.9)), gain=0.8, rev=0.02, name='reese')
    D = Kit()
    chip_beat(D, a['start'], 8, 'drive')
    chip_beat(D, b['start'], 8, 'drive')
    D.clear(a['start'] + 30, a['start'] + 32)
    D.clear(b['start'] + 28, b['start'] + 32)
    dnb_layer(D, d['start'], 8, 'two', snare=False)
    D.ev['cr'] += [(a['start'], 0, 1, 0.8), (b['start'], 0, 1, 0.7), (d['start'], 0, 1, 1.0)]
    D.render(S)
    brk = make_break(S.spb, tone=195)
    S.add_sig(chop(brk, S.spb, '12 13 14 15 4s 4s 12s 12s'), a['start'] + 30, gain=0.8, rev=0.05, name='pop-1')
    S.add_sig(chop(brk, S.spb, CHOPS['f']), b['start'] + 28, gain=0.8, rev=0.05, name='pop-2')
    S.add_sig(chop(brk, S.spb, chops('a b a c a b x v')), d['start'], gain=0.95, rev=0.05, name='break')
    S.add_sig(subdrop(), d['start'], gain=0.45, name='subdrop')
    return S.render()


BD1_A = ("D6:.5 r:.25 D6:.25 r:.5 A5:.5 F5:.5 r:.5 E5:.5 F5:.5 | Bb5:.5 r:.25 Bb5:.25 r:.5 F5:.5 D5:.5 r:.5 C#5:.5 D5:.5 | "
         "G5:.5 r:.25 G5:.25 r:.5 Bb5:.5 D6:.5 r:.5 C#6:.5 D6:.5 | E6:.5 r:.25 E6:.25 r:.5 C#6:.5 A5:.5 G5:.5 F5:.5 E5:.5 | "
         "D6:.5 r:.25 D6:.25 r:.5 A5:.5 F5:.5 r:.5 E5:.5 F5:.5 | D6:.5 r:.25 D6:.25 r:.5 Bb5:.5 F6:.5 r:.5 E6:.5 D6:.5 | "
         "Bb5:.5 r:.25 Bb5:.25 r:.5 D6:.5 G6:.5 r:.5 F6:.5 E6:.5 | C#6:.5 E6:.5 G6:.5 A6:.5 G6:.25 F6:.25 E6:.25 D6:.25 C#6:1")
BD1_W = ("G5:1.5 Bb5:.5 D6:1 Bb5:1 | A5:1.5 F5:.5 D5:1 F5:1 | D6:1.5 C6:.5 Bb5:1 F5:1 | E5:1 G5:1 C#6:1 E6:1 | "
         "D6:1.5 F6:.5 E6:1 D6:1 | C#6:.5 D6:.5 E6:.5 F6:.5 A6:2 | G#6:1.5 E6:.5 B5:1 D6:1 | C#6:2 E6:1 A6:1")
BD1_K = "F5:2 D5:1 Bb4:1 | G5:2 Bb5:1 D6:1 | E6:2 Bb5:1 G5:1 | A5:2 C#6:1 E6:1"
_BD1_1 = "D6:.25 F6:.25 A6:.25 F6:.25 D6:.5 r:.5 C#6:.25 D6:.25 E6:.25 F6:.25 E6:.5 C#6:.5"
_BD1_2 = "D6:.25 F6:.25 Bb6:.25 F6:.25 D6:.5 r:.5 C6:.25 D6:.25 F6:.25 D6:.25 Bb5:1"
BD1_B = (_BD1_1 + " | " + _BD1_2 + " | G5:.25 Bb5:.25 D6:.25 G6:.25 F6:.5 r:.5 E6:.25 F6:.25 G6:.25 F6:.25 D6:1 | "
         "C#6:.25 E6:.25 A6:.25 E6:.25 C#6:.5 r:.5 Bb5:.5 A5:.5 G5:.5 E5:.5 | " + _BD1_1 + " | " + _BD1_2 + " | "
         "C#6:.25 E6:.25 G6:.25 Bb6:.25 G6:.25 E6:.25 C#6:.25 Bb5:.25 G5:.5 Bb5:.5 C#6:.5 E6:.5 | "
         "A6:2 G6:.5 F6:.5 E6:.5 C#6:.5")


def song_boss_dnb_1():
    """DnB boss (D harmonic minor, 174 bpm). Starts straight on the drop: stabbing pulse +
    distorted saw over amen chops and a growling reese; wobble section (1/4, 1/8, 1/4T, 1/16);
    choir breakdown; 4-bar build (snare roll, riser, opening filter); second drop with runs."""
    A = Arr()
    da = A.sec('drop', ['Dm', 'Bb', 'Gm', 'A', 'Dm', 'Bb', 'Gm', 'A7'], BD1_A)
    wb = A.sec('wob', ['Gm', 'Dm', 'Bb', 'A', 'Gm', 'Dm', 'E', 'A'], BD1_W)
    bk = A.sec('brk', ['Bb', 'Gm', 'Edim', 'A'], BD1_K)
    bu = A.sec('build', ['Dm', 'Bb', 'Gm', 'A'])
    db = A.sec('drop', ['Dm', 'Bb', 'Gm', 'A', 'Dm', 'Bb', 'C#dim7', 'A'], BD1_B)
    S = Song(174, A.pos, tail=4, t60=1.2, bright=0.45, drive=1.8)
    lA, lW, lK, lB = lead_ev(da, 0.9), lead_ev(wb, 0.8), lead_ev(bk, 0.75), lead_ev(db, 0.9)
    S.add(lA + lB, i_square, gain=0.5, rev=0.15, echo=(0.75, 0.2, 0.12), duty=0.25, vib=(6.0, 0.15, 0.2), name='stab-sq')
    S.add(shift(lA + lB, semis=-12), i_distsaw, gain=0.45, rev=0.15, drive=4.0, cut=3500, vib=None, a=0.002, d=0.1,
          s=0.6, r=0.04, name='stab-dist')
    S.add(lW, i_pwm, gain=0.5, rev=0.25, echo=(0.75, 0.3, 0.2), rate=5.0, depth=0.25, name='wob-lead')
    S.add(lK, i_square, gain=0.5, rev=0.4, echo=(1.5, 0.35, 0.3), duty=0.5, vib=(5.0, 0.2, 0.3), name='brk-lead')
    S.add(arp_ev(bu['T'], [0, 1, 2, 3, 4, 5, 6, 7, 8, 7, 6, 5, 4, 3, 2, 1], 0.25, low=62, vel=0.45), i_square,
          gain=0.4, rev=0.2, duty=0.125, a=0.002, d=0.04, s=0.3, r=0.02, vib=None, name='build-arp')
    stabs = [(st + off, mhz(m), 0.3, 0.7) for name, st, d in da['T'] + db['T'] for off in (0, 1.5)
             for m in voicing(name, 55)]
    S.add(stabs, i_supersaw, gain=0.22, rev=0.2, det=0.35, d=0.1, s=0.5, name='chord-stabs')
    S.add(pad_ev(bk['T'] + bu['T'], low=50, vel=0.55), i_choir, gain=0.35, rev=0.6, vowel='a', a=0.5, r=1.2,
          name='choir')
    S.add(pad_ev(da['T'] + wb['T'] + db['T'], low=50, vel=0.4), i_pad, gain=0.22, rev=0.4, a=0.3, r=0.8, name='pad')
    w0, u0 = wb['start'], bu['start']
    mod = pmod([(w0, w0 + 8, cmod(1, 2.6)), (w0 + 8, w0 + 16, cmod(0.5, 2.6)), (w0 + 16, w0 + 24, cmod(2 / 3, 2.8)),
                (w0 + 24, w0 + 32, cmod(0.25, 2.4)), (u0, u0 + 16, ramp_mod(u0, 16, 2.5)),
                (da['start'], da['start'] + 32, cmod(4, 0.8)), (db['start'], db['start'] + 32, cmod(4, 0.8))])
    rz = riff(da['T'] + db['T'], [(0, 'r', 1.5, 1.0), (1.5, 'r', 0.5, 0.8), (2, 'o', 0.5, 0.85), (2.5, 'r', 1.0, 0.9),
                                  (3.5, 't', 0.5, 0.8)], low=33) + \
        riff(wb['T'], [(0, 'r', 2.0, 1.0), (2, 'r', 1.5, 0.9), (3.5, 'o', 0.5, 0.8)], low=33) + \
        riff(bu['T'], [(0, 'r', 4, 0.9)], low=33)
    S.add_sig(reese(rz, S, det=0.26, cut=180, env_oct=1.4, env_tau=0.18, q=1.5, drive=3.0, sub=1.0, mod=mod),
              gain=0.85, rev=0.02, name='reese')
    S.add_sig(reese(riff(bk['T'], [(0, 'r', 4, 0.7)], low=33), S, det=0.1, cut=120, env_oct=0.3, q=0.8, drive=1.0,
                    sub=1.0), gain=0.5, rev=0.05, name='brk-sub')
    D = Kit()
    dnb_layer(D, da['start'], 8, 'two')
    dnb_layer(D, wb['start'], 8, 'step')
    dnb_layer(D, db['start'], 8, 'two')
    D.ev['rd'] += pat("x.x.x.x.x.x.x.x.", bk['start'], vmap={'x': 0.35}) + pat("x.x.x.x.x.x.x.x.", bk['start'] + 8,
                                                                             vmap={'x': 0.35})
    D.ev['bs'] += roll_ev(u0, 16, divs=(1, 2, 4, 8))
    D.ev['bk'] += pat("x...x...x...x...", u0 + 8) + pat("x...x...x...x...", u0 + 12)
    D.ev['cr'] += [(da['start'], 0, 1, 1.0), (wb['start'], 0, 1, 0.9), (bk['start'], 0, 1, 0.7), (db['start'], 0, 1, 1.0)]
    D.render(S)
    brk = make_break(S.spb, tone=195)
    S.add_sig(chop(brk, S.spb, chops('a b x c a y z v')), da['start'], gain=1.0, rev=0.04, name='break-A')
    S.add_sig(chop(brk, S.spb, chops('a x b z c y s f')), wb['start'], gain=1.0, rev=0.04, name='break-W')
    S.add_sig(chop(brk, S.spb, chops('a b c d a z r v')), db['start'], gain=1.0, rev=0.04, name='break-B')
    S.add_sig(riser_sig(16 * S.spb), u0, gain=0.4, rev=0.25, name='riser')
    for s in (da, db):
        S.add_sig(subdrop(), s['start'], gain=0.6, rev=0.0, name='subdrop')
    return S.render()


_BD2_1 = "F#5:.75 F#5:.75 A5:.5 C#6:.75 C#6:.75 B5:.5"
_BD2_2 = "A5:.75 A5:.75 F#5:.5 D6:1 C#6:1"
_BD2_3 = "B5:.75 B5:.75 D6:.5 F#6:.75 E6:.75 D6:.5"
_BD2_4 = "E#5:.5 G#5:.5 C#6:.5 E#6:.5 C#6:2"
_BD2_6 = "A5:.75 A5:.75 F#5:.5 D6:.5 E6:.5 F#6:1"
_BD2_8 = "C#6:.5 E#6:.5 G#6:.5 B6:.5 G#6:.25 E#6:.25 C#6:.25 B5:.25 G#5:1"
BD2_A = ' | '.join([_BD2_1, _BD2_2, _BD2_3, _BD2_4, _BD2_1, _BD2_6, "G#6:.75 E6:.75 B5:.5 E6:.75 D6:.75 B5:.5", _BD2_8])
BD2_B = ' | '.join([_BD2_1, _BD2_2, _BD2_3, _BD2_4, _BD2_1, _BD2_6, "B6:.75 G6:.75 D6:.5 G6:.75 F#6:.75 D6:.5", _BD2_8])
BD2_W = ("D6:2 r:1 C#6:.5 D6:.5 | C#6:2 r:1 A5:.5 C#6:.5 | F#6:2 r:1 E6:.5 D6:.5 | E#6:2 G#6:2 | "
         "B6:1 F#6:1 D6:1 B5:1 | A6:1 F#6:1 C#6:1 A5:1 | B6:1 G6:1 D6:1 B5:1 | G#6:1 E#6:1 C#6:.5 G#5:.5 E#5:1")
BD2_H = "F#5:2 A5:1 G#5:1 | B5:2 E6:1 D6:1 | C#6:1.5 D6:.5 C#6:1 A5:1 | F#5:3 r:1"
BD2_U = "F#5:1 A5:1 D6:1 F#6:1 | B5:1 D6:1 F#6:1 B6:1 | G5:1 B5:1 D6:1 G6:1 | C#6:.5 E#6:.5 G#6:.5 C#7:.5 r:2"


def song_boss_dnb_2():
    """Wobble boss (F# harmonic minor, 172 bpm): laser-zap chip stabs doubled by supersaw;
    wobble section stepping 1/4 -> 1/8 -> triplets -> 1/16; half-time break; build with a 2-beat
    silence before the second drop."""
    A = Arr()
    da = A.sec('drop', ['F#m', 'D', 'Bm', 'C#', 'F#m', 'D', 'E', 'C#7'], BD2_A)
    wb = A.sec('wob', ['Bm', 'F#m', 'D', 'C#', 'Bm', 'F#m', 'G', 'C#'], BD2_W)
    hf = A.sec('half', ['D', 'E', 'F#m', 'F#m'], BD2_H)
    bu = A.sec('build', ['D', 'Bm', 'G', 'C#'], BD2_U)
    db = A.sec('drop', ['F#m', 'D', 'Bm', 'C#', 'F#m', 'D', 'G', 'C#7'], BD2_B)
    S = Song(172, A.pos, tail=4, t60=1.3, bright=0.45, drive=1.8)
    lA, lW, lH, lU, lB = (lead_ev(s, v) for s, v in ((da, 0.9), (wb, 0.75), (hf, 0.75), (bu, 0.8), (db, 0.95)))
    S.add(lA + lB, i_square, gain=0.5, rev=0.15, echo=(0.75, 0.22, 0.14), duty=0.5, vib=None, bend=(7, 0.012),
          a=0.002, d=0.12, s=0.6, r=0.04, name='laser')
    S.add(lA + lB, i_supersaw, gain=0.4, rev=0.15, det=0.3, name='saw-dbl')
    S.add(lW, i_bell, gain=0.4, rev=0.4, echo=(0.75, 0.35, 0.25), ratio=3.5, index=1.6, decay=1.0, name='wob-bell')
    S.add(lW, i_square, gain=0.3, rev=0.25, duty=0.25, vib=(6.0, 0.2, 0.2), name='wob-sq')
    S.add(lH, i_pwm, gain=0.55, rev=0.4, echo=(1.0, 0.35, 0.3), rate=2.5, depth=0.35, vib=(5.0, 0.25, 0.25),
          name='half-lead')
    S.add(lU, i_square, gain=0.45, rev=0.25, duty=0.125, vib=None, name='build-lead')
    S.add(arp_ev(bu['T'], [0, 1, 2, 3, 4, 5, 6, 7, 8, 7, 6, 5, 4, 3, 2, 1], 0.25, low=61, vel=0.4)[:56], i_square,
          gain=0.35, rev=0.2, duty=0.125, a=0.002, d=0.04, s=0.3, r=0.02, vib=None, name='build-arp')
    stabs = [(st + off, mhz(m), 0.3, 0.7) for name, st, d in da['T'] + db['T'] for off in (0, 1.5)
             for m in voicing(name, 54)]
    S.add(stabs, i_supersaw, gain=0.22, rev=0.2, det=0.35, d=0.1, s=0.5, name='chord-stabs')
    S.add(pad_ev(hf['T'] + bu['T'], low=50, vel=0.5), i_choir, gain=0.3, rev=0.6, vowel='o', a=0.6, r=1.2, name='choir')
    w0, u0 = wb['start'], bu['start']
    mod = pmod([(da['start'], da['start'] + 32, cmod(2, 1.2)), (w0, w0 + 8, cmod(1, 2.8)),
                (w0 + 8, w0 + 16, cmod(0.5, 2.8)), (w0 + 16, w0 + 24, cmod(1 / 3, 2.8)),
                (w0 + 24, w0 + 32, cmod(0.25, 2.6)), (u0, u0 + 16, ramp_mod(u0, 14, 2.4, wob=0.5)),
                (db['start'], db['start'] + 32, cmod(1, 1.8))])
    rz = riff(da['T'] + db['T'], [(0, 'r', 0.75, 1.0), (0.75, 'r', 0.75, 0.9), (1.5, 'o', 0.5, 0.85),
                                  (2.5, 'r', 1.0, 0.95), (3.5, 'f', 0.5, 0.85)], low=30) + \
        riff(wb['T'], [(0, 'r', 4, 1.0)], low=30) + \
        riff(bu['T'][:3], [(0, 'r', 2, 0.9), (2, 'r', 2, 0.9)], low=30) + \
        riff(bu['T'][3:], [(0, 'r', 2, 0.9)], low=30)
    S.add_sig(reese(rz, S, det=0.24, cut=150, env_oct=1.0, env_tau=0.2, q=2.0, drive=3.2, sub=1.0, mod=mod),
              gain=0.85, rev=0.02, name='wobble')
    rzH = riff(hf['T'], [(0, 'r', 2.5, 1.0), (3, 'r', 1, 0.8)], low=30)
    S.add_sig(reese(rzH, S, det=0.3, cut=120, env_oct=1.5, env_tau=0.4, q=1.0, drive=2.0, sub=1.1), gain=0.75,
              rev=0.03, name='half-reese')
    D = Kit()
    dnb_layer(D, da['start'], 8, 'two')
    dnb_layer(D, wb['start'], 8, 'roll')
    dnb_layer(D, hf['start'], 4, 'half')
    D.ev['bs'] += roll_ev(u0 + 4, 10, divs=(2, 4, 8))
    D.ev['bk'] += pat("x...x...x...x...", u0 + 8) + pat("x...x...", u0 + 12)
    dnb_layer(D, db['start'], 8, 'step')
    D.ev['cr'] += [(s['start'], 0, 1, 1.0) for s in (da, wb, db)] + [(hf['start'], 0, 1, 0.7)]
    D.render(S)
    brk = make_break(S.spb, tone=210)
    S.add_sig(chop(brk, S.spb, chops('a b x c a y z v')), da['start'], gain=1.0, rev=0.04, name='break-A')
    S.add_sig(chop(brk, S.spb, chops('a x b z a y c s')), wb['start'], gain=0.9, rev=0.04, name='break-W')
    S.add_sig(chop(brk, S.spb, chops('h H h g')), hf['start'], gain=0.9, rev=0.05, name='break-H')
    S.add_sig(chop(brk, S.spb, chops('a b c d a z r f')), db['start'], gain=1.0, rev=0.04, name='break-B')
    S.add_sig(riser_sig(14 * S.spb), u0, gain=0.4, rev=0.25, name='riser')
    for s in (da, db):
        S.add_sig(subdrop(), s['start'], gain=0.6, rev=0.0, name='subdrop')
    return S.render()


BD3_M = "G#5:2 A5:1 G#5:1 | E5:1.5 C#5:.5 A4:2 | B5:1 A5:1 G#5:1 G5:1 | D#5:2 G5:1 A#5:1"
_BD3_1 = "G#5:.25 G#5:.25 r:.5 B5:.25 B5:.25 r:.5 D#6:.5 D6:.5 C#6:.5 B5:.5"
_BD3_2 = "G#5:.25 G#5:.25 r:.5 B5:.25 B5:.25 r:.5 E6:.5 D#6:.5 B5:.5 G#5:.5"
BD3_A = ' | '.join([_BD3_1, _BD3_2, "A5:.25 A5:.25 r:.5 C#6:.25 C#6:.25 r:.5 E6:.5 F6:.5 E6:.5 C#6:.5",
                    "D#6:.25 D#6:.25 r:.5 G6:.25 G6:.25 r:.5 A#6:.5 G6:.5 D#6:.5 A#5:.5", _BD3_1, _BD3_2,
                    "C#6:.25 C#6:.25 r:.5 E6:.25 E6:.25 r:.5 G#6:.5 F#6:.5 E6:.5 C#6:.5",
                    "D#6:.5 G6:.5 A#6:.5 C#7:.5 A#6:.25 G6:.25 D#6:.25 C#6:.25 G5:1"])
BD3_C = ("E5:2 D#5:1 C#5:1 | D#5:2 B4:1 G#4:1 | C#5:2 E5:1 A5:1 | G5:3 r:1 | E5:2 F#5:1 G#5:1 | "
         "B5:2 A#5:1 G#5:1 | G#5:1.5 B5:.5 E6:2 | D#6:2 A#5:1 G5:1")
_BD3_B1 = "G#6:.5 r:.25 G#6:.25 D#6:.5 B5:.5 G#5:.5 B5:.5 D#6:.5 F#6:.5"
_BD3_B2 = "G#6:.5 r:.25 G#6:.25 E6:.5 B5:.5 G#5:.5 B5:.5 E6:.5 G#6:.5"
BD3_B = ' | '.join([_BD3_B1, _BD3_B2, "A6:.5 r:.25 A6:.25 E6:.5 C#6:.5 A5:.5 C#6:.5 E6:.5 F6:.5",
                    "G6:.5 r:.25 G6:.25 D#6:.5 A#5:.5 G5:.5 A#5:.5 D#6:.5 G6:.5", _BD3_B1, _BD3_B2,
                    "A6:.5 G#6:.5 E6:.5 C#6:.5 A5:.5 C#6:.5 E6:.5 F6:.5",
                    "G6:1 A#6:.5 G6:.5 D#6:.5 C#6:.5 A#5:1"])


def song_boss_dnb_3():
    """Final boss, The Butcher (G# harmonic minor, 176 bpm): sinister organ + choir motif
    (b2 / leading-tone menace) over a half-time stomp, then the most brutal drop -- 4x-driven
    reese, distorted growl, chopped amen, cleaver clangs; choir/wobble section; build; drop 2."""
    A = Arr()
    it = A.sec('intro', ['G#m', 'A', 'G#m', 'D#7'], BD3_M)
    da = A.sec('drop', ['G#m', 'E', 'A', 'D#', 'G#m', 'E', 'C#m', 'D#7'], BD3_A)
    ch = A.sec('choir', ['C#m', 'G#m', 'A', 'D#', 'C#m', 'G#m', 'E', 'D#7'], BD3_C)
    bu = A.sec('build', ['G#m', 'A', 'G#m', 'D#7'], BD3_M)
    db = A.sec('drop', ['G#m', 'E', 'A', 'D#', 'G#m', 'E', 'A', 'D#7'], BD3_B)
    S = Song(176, A.pos, tail=5, t60=1.6, bright=0.35, drive=1.9)
    motif_i, motif_b = lead_ev(it, 0.8, tr=-12), lead_ev(bu, 0.85)
    S.add(motif_i, i_organ, gain=0.55, rev=0.4, name='organ-motif')
    S.add(shift(motif_i, semis=-12, velmul=0.6), i_organ, gain=0.35, rev=0.4, name='organ-low')
    S.add(pad_ev(it['T'] + ch['T'], low=50, vel=0.6), i_choir, gain=0.4, rev=0.6, vowel='a', a=0.4, r=1.0, name='choir')
    S.add(lead_ev(ch, 0.75), i_choir, gain=0.35, rev=0.5, vowel='o', a=0.1, r=0.4, voices=4, name='choir-motif')
    S.add(lead_ev(ch, 0.6, tr=-12), i_organ, gain=0.3, rev=0.4, name='organ-motif-2')
    S.add(motif_b, i_distsaw, gain=0.5, rev=0.2, drive=5.0, cut=3000, name='build-dist')
    S.add(motif_b, i_square, gain=0.3, rev=0.2, duty=0.25, name='build-sq')
    lA, lB = lead_ev(da, 0.9), lead_ev(db, 0.95)
    S.add(lA + lB, i_square, gain=0.45, rev=0.15, echo=(0.75, 0.2, 0.12), duty=0.25, vib=(6.0, 0.15, 0.2),
          name='stab-sq')
    S.add(shift(lA + lB, semis=-12), i_distsaw, gain=0.45, rev=0.15, drive=5.0, cut=3200, vib=None, a=0.002, d=0.1,
          s=0.6, r=0.04, name='stab-dist')
    S.add([(st + off, mhz(m), 0.4, 0.8) for name, st, d in da['T'] + db['T'] for off in (0, 1.5)
           for m in voicing(name, 55)], i_organ, gain=0.3, rev=0.3, name='organ-stabs')
    rI = riff(it['T'], [(0, 'r', 1.5, 1.0), (2, 'r', 0.5, 0.8), (2.5, 'r', 1.5, 0.9)], low=32)
    rD = riff(da['T'] + db['T'], [(0, 'r', 0.5, 1.0), (0.5, 'r', 0.5, 0.85), (1, 'o', 0.5, 0.8), (1.5, 'r', 1, 0.95),
                                  (2.5, 'r', 0.5, 0.85), (3, 't', 0.5, 0.85), (3.5, 'f', 0.5, 0.9)], low=32)
    rC = riff(ch['T'], [(0, 'r', 3, 1.0), (3, 'o', 1, 0.85)], low=32)
    rU = riff(bu['T'], [(0, 'r', 4, 0.9)], low=32)
    mod = pmod([(it['start'], it['start'] + 16, cmod(4, 1.0)), (da['start'], da['start'] + 32, cmod(1, 1.6)),
                (ch['start'], ch['start'] + 16, cmod(2 / 3, 2.6)), (ch['start'] + 16, ch['start'] + 32, cmod(1 / 3, 2.6)),
                (bu['start'], bu['start'] + 16, ramp_mod(bu['start'], 16, 2.6)),
                (db['start'], db['start'] + 32, cmod(0.5, 2.0))])
    S.add_sig(reese(rI + rD + rC + rU, S, det=0.32, cut=160, env_oct=1.5, env_tau=0.15, q=1.8, drive=4.0, sub=1.0,
                    mod=mod), gain=0.9, rev=0.02, name='reese')
    S.add(shift(rD, semis=12, velmul=0.6), i_distsaw, gain=0.25, rev=0.05, drive=6.0, cut=1500, vib=None, a=0.002,
          d=0.1, s=0.7, r=0.03, name='growl')
    D = Kit()
    dnb_layer(D, it['start'], 4, 'half')
    dnb_layer(D, da['start'], 8, 'two')
    dnb_layer(D, ch['start'], 8, 'step')
    D.ev['bs'] += roll_ev(bu['start'], 16, divs=(1, 2, 4, 8))
    D.ev['bk'] += pat("x...x...x...x...", bu['start'] + 8) + pat("x...x...x...x...", bu['start'] + 12)
    dnb_layer(D, db['start'], 8, 'roll')
    D.ev['cr'] += [(s['start'], 0, 1, 1.0) for s in (it, da, ch, db)]
    D.render(S)
    brk = make_break(S.spb, tone=180, kick_f0=46)
    S.add_sig(chop(brk, S.spb, chops('h H h g')), it['start'], gain=0.9, rev=0.05, name='break-I')
    S.add_sig(chop(brk, S.spb, chops('a b x c a y z v')), da['start'], gain=1.0, rev=0.04, name='break-A')
    S.add_sig(chop(brk, S.spb, chops('a z b x c y a s')), ch['start'], gain=1.0, rev=0.04, name='break-C')
    S.add_sig(chop(brk, S.spb, chops('a b c d a z r f')), db['start'], gain=1.0, rev=0.04, name='break-B')
    clangs = [(it['start'] + 4 * k, 0) for k in range(4)] + [(da['start'], 0), (da['start'] + 16, 0), (db['start'], 0),
                                                            (db['start'] + 16, 0)]
    for k, (b0, _) in enumerate(clangs):
        S.add_sig(clang(660 + 40 * (k % 3), 1.0), b0, gain=0.3, rev=0.35, name='clang')
    S.add_sig(riser_sig(16 * S.spb), bu['start'], gain=0.4, rev=0.25, name='riser')
    for s in (da, db):
        S.add_sig(subdrop(), s['start'], gain=0.6, rev=0.0, name='subdrop')
    return S.render()


# =====================================================================================
# MUSIC v2 -- area variants
# =====================================================================================
BEACH2_MEL = ("A4:1 C5:1 E5:1.5 F5:.5 | D5:2 Bb4:1 F5:1 | E5:1.5 C5:.5 A4:1 G4:1 | A4:3 r:1 | "
              "A4:1 C5:1 F5:1.5 G5:.5 | A5:2 F5:1 D5:1 | F5:1.5 D5:.5 Bb4:1 D5:1 | E5:3 r:1 | "
              "F5:1 D5:.5 F5:.5 A5:2 | G5:1.5 E5:.5 C5:2 | E5:1 G5:1 C6:1.5 A5:.5 | F5:2 D5:1 A4:1 | "
              "Bb4:1 D5:1 F5:1 A5:1 | A5:1.5 F5:.5 D5:2 | C5:1 F5:1 G5:2 | E5:3 r:1")


def song_beach_2():
    """Calm alternate beach (F major, 84 bpm): ukulele strums, soft steel pan then flute + marimba,
    gentle shaker/rim, surf in the background."""
    ch = ['Fmaj7', 'Gm7', 'Am7', 'Bbmaj7', 'Fmaj7', 'Dm7', 'Gm7', 'C7',
          'Bbmaj7', 'C', 'Am7', 'Dm7', 'Gm7', 'Bbmaj7', 'Csus4', 'C']
    S = Song(84, 64, tail=6, t60=1.8, bright=0.55)
    T = timeline(ch, 4)
    m = mel(BEACH2_MEL, bpb=4, vel=0.75)
    S.add([e for e in m if e[0] < 32], i_steel, gain=0.75, rev=0.3, echo=(0.75, 0.25, 0.2), name='steel')
    S.add([e for e in m if e[0] >= 32], i_whistle, gain=0.5, rev=0.35, echo=(0.75, 0.25, 0.2), breath=0.04,
          name='flute')
    S.add(shift([e for e in m if e[0] >= 32], semis=-12, velmul=0.5), i_marimba, gain=0.4, rev=0.25, name='marimba')
    S.add(strum_ev(T, [(0, 1.0, 1.0, 'd'), (1.5, 0.5, 0.6, 'u'), (2.0, 1.0, 0.85, 'd'), (3.5, 0.5, 0.6, 'u')],
                   low=60, spread=0.025, vel=0.45), i_pluck, gain=0.45, rev=0.25, decay=0.7, bright=0.8, rel=0.1,
          name='uke')
    S.add(bass_ev(T, [(0, 0, 1.4, 1.0), (1.5, 7, 0.5, 0.6), (2, 0, 1.0, 0.8), (3.5, 'app', 0.5, 0.6)], low=36),
          i_softbass, gain=0.55, rev=0.1, name='bass')
    sh, rim, cg = [], [], []
    for bar in range(16):
        st = bar * 4
        sh += pat("x.o.x.o.x.o.x.o.", st, vmap={'x': 0.45, 'o': 0.25})
        rim += pat("....x.......x...", st, vmap={'x': 0.35})
        if bar >= 8:
            cg += [(b, 300.0, d, v) for b, _, d, v in pat("......x.......x.", st, vmap={'x': 0.4})]
    S.add(sh, d_shaker, gain=0.6, rev=0.1, hum=0.004, name='shaker')
    S.add(rim, d_clave, gain=0.25, rev=0.2, fc=1700, name='rim')
    S.add(cg, d_conga, gain=0.35, rev=0.15, name='conga')
    S.add_post(cfilt(_waves(S.L), lambda v: lp(v, 4000)), -15)
    return S.render()


def song_village_2():
    """Village at night (slendro, 54 bpm): slower, sparser gamelan -- soft saron, gender
    figuration, gong/kempul/kenong, a lonely suling -- with crickets and frogs."""
    gongans = ["3 5 6 1' 6 5 3 2 5 6 5 3 2 1 2 6", "1 2 3 5 3 2 1 6 2 3 2 1 6 5 6 1",
               "6 1 2 3 2 1 6 5 3 5 6 1' 6 5 3 2"]
    bal = [gtok(x) for g in gongans for x in g.split()]
    S = Song(54, 48, tail=10, t60=3.0, bright=0.45)
    S.add([(i, sl_hz(d, 290), 1, 0.55) for i, d in enumerate(bal) if i % 2 == 1], i_metallo, gain=0.6, rev=0.35,
          decay=1.4, bright=0.6, name='saron')
    gender = []
    for i, d in enumerate(bal):
        fig = [d, d + 2] if i % 2 == 0 else [d + 1, d]
        for k, dd in enumerate(fig):
            gender.append((i + 0.5 * k, sl_hz(dd, 290), 0.5, 0.45 if k else 0.5))
    S.add(gender, i_metallo, gain=0.45, rev=0.4, decay=2.2, bright=0.35, ombak=2.0, name='gender')
    S.add([(i, sl_hz(d, 145), 2, 0.6) for i, d in enumerate(bal) if i % 4 == 3], i_metallo, gain=0.45, rev=0.35,
          decay=2.5, bright=0.4, name='slenthem')
    gong, kempul, kenong = [], [], []
    for g in range(3):
        st = g * 16
        gong.append((st, sl_hz(4, 290) / 8, 4, 0.9))
        kempul.append((st + 8, sl_hz(bal[st + 7], 290) / 4, 2, 0.6))
        for k in (4, 12):
            kenong.append((st + k, sl_hz(bal[st + k - 1], 290), 2, 0.4))
    S.add(gong, i_gong, gain=0.75, rev=0.4, decay=7.0, beat=0.7, name='gong')
    S.add(kempul, i_gong, gain=0.5, rev=0.35, decay=3.5, beat=1.4, thud=0.1, name='kempul')
    S.add(kenong, i_gong, gain=0.3, rev=0.35, decay=2.2, beat=2.0, thud=0.05, name='kenong')
    S.add([(st, 0, 1, 0.6) for st in range(0, 48, 16)], k_dhe, gain=0.4, rev=0.2, name='kendang-dhe')
    S.add([(st + o, 0, 1, 0.4) for st in range(0, 48, 16) for o in (6, 10.5, 14)], k_tung, gain=0.35, rev=0.2,
          name='kendang-tung')
    sul = "6:2 1':2 2':3 1':1 6:4 5:2 3:2 5:4 6:2 5:1 3:1 2:4 3:2 5:2 6:4"
    ev, b = [], 8.0
    for tok in sul.split():
        p, d = tok.split(':')
        ev.append((b, sl_hz(gtok(p), 580), float(d), 0.6))
        b += float(d)
    S.add(ev, i_suling, gain=0.45, rev=0.5, echo=(1.0, 0.3, 0.2), name='suling')
    S.add_post(_night(S.L), -11)
    return S.render()


STEPPE2_SLIDE = ("A4:3 C5:.5 D5:.5 | F5:4 | D5:2 Bb4:1 G4:1 | E4:2 G4:1 C5:1 | D5:3 F5:.5 E5:.5 | C5:4 | "
                 "D5:2 F5:1 G5:1 | E5:2 C#5:2 | D5:2 G5:2 | F5:2 A5:2 | G5:2 F5:1 D5:1 | E5:2 C#5:1 A4:1")


def song_steppe_2():
    """Steppe in the heat (D minor, 66 bpm): gliding slide lead, shimmering haze pad, sparse
    guitar, hot wind + cicadas."""
    ch = ['Dm', 'Dm', 'Bb', 'C', 'Dm', 'Am', 'Bb', 'A', 'Gm', 'Dm', 'Bb', 'A']
    S = Song(66, 48, tail=7, t60=2.6, bright=0.4)
    T = timeline(ch, 4)
    m = mel(STEPPE2_SLIDE, bpb=4, vel=0.8)
    v = glide_voice(m, S.spb, S.N, port=0.08, vib=(4.6, 0.3), harm=0.3, gap=0.08, att_tau=0.05)
    v = lp(np.tanh(1.8 * v), 3500)
    S.add_sig(v, gain=0.45, rev=0.35, echo=(1.5, 0.35, 0.3), name='slide')
    S.add(pad_ev(T, low=67, vel=0.5), i_haze, gain=0.5, rev=0.6, a=1.5, r=2.0, name='haze')
    S.add(arp_ev(T, [0, None, 2, 1, None, 3, None, 2], 0.5, low=50, vel=0.45), i_pluck, gain=0.55, rev=0.25,
          decay=2.0, bright=0.6, rel=0.5, name='guitar')
    S.add(bass_ev(T, [(0, 0, 3.5, 1.0)], low=38), i_softbass, gain=0.5, rev=0.15, a=0.05, r=0.8, name='bass')
    S.add([(b, 70.0, 1, v_) for b, v_ in ((0, .7), (2.5, .4), (16, .6), (18.5, .35), (32, .65), (34.5, .4))], d_tom,
          gain=0.3, rev=0.45, dec=0.5, name='lone-drum')
    n = S.L
    wind = pnoise(n, 120, 900) * (0.4 + 0.6 * psmooth(n, 5)) + pnoise(n, peak=(780, 30)) * psmooth(n, 4) ** 2 * 0.5
    S.add_post(cfilt(wind, lambda x: lp(x, 3000, 2)), -16)
    pulses = (0.5 + 0.5 * plfo(n, int(round(n / SR * 46)))) ** 4
    cic = pnoise(n, 4200, 7500) * pulses * (0.2 + 0.8 * psmooth(n, 3) ** 2)
    S.add_post(cic, -24)
    return S.render()


FARM2_PIZZ = ("Bb2:.5 r:1 Db3:.5 r:1 C3:.5 r:.5 | A2:.5 r:3.5 | Bb2:.5 r:1 Db3:.5 r:1 E3:.5 r:.5 | "
              "F3:.5 r:1.5 E3:.5 r:1.5 | Bb2:.5 r:1 Db3:.5 r:1 C3:.5 r:.5 | A2:.5 r:1.5 Gb2:.5 r:1.5 | "
              "F2:.5 r:1 Ab2:.5 r:1 A2:.5 r:.5 | Bb2:.5 r:3.5 | r:4 | Db4:.5 r:1 C4:.5 r:2 | r:4 | "
              "E3:.5 r:.5 F3:.5 r:2.5")


def song_farm_2():
    """Farm after the power cut -- stealth (Bb minor, 70 bpm): almost nothing. Low drone, creeping
    pizzicato, heartbeat, tritone swell, dying electrical buzz, dark air."""
    S = Song(70, 48, tail=8, t60=3.0, bright=0.25)
    p = mel(FARM2_PIZZ, bpb=4, vel=0.75)
    S.add(p, i_pluck, gain=0.7, rev=0.3, decay=0.5, bright=0.35, rel=0.08, nh=12, name='pizz')
    S.add([(0, mhz(nm('Bb1')), 48, 0.7), (0, mhz(nm('F2')), 48, 0.45)], i_strings, gain=0.5, rev=0.4, a=4.0, r=4.0,
          cut=400, name='drone')
    S.add([(16, mhz(nm('E2')), 14, 0.45)], i_strings, gain=0.4, rev=0.5, a=3.0, r=3.0, cut=600, name='tritone')
    S.add([(26, mhz(nm('A5')), 14, 0.25), (30, mhz(nm('Bb5')), 10, 0.2)], i_strings, gain=0.25, rev=0.6, a=4.0,
          r=3.0, cut=4000, voices=2, trem=0.6, name='hi-cluster')
    hb = [(b + o, 0, 0.25, v) for b in range(0, 32, 2) for o, v in ((0, 0.7), (0.35, 0.45))]
    S.add(hb, d_kick, gain=0.35, rev=0.1, f0=42, punch=50, dec=0.3, hum=0.0, name='heartbeat')
    S.add_sig(buzz_sig(0.7), 10.5, gain=0.12, rev=0.3, name='buzz-1')
    S.add_sig(buzz_sig(0.5), 37.0, gain=0.1, rev=0.3, name='buzz-2')
    n = S.L
    air = pnoise(n, 50, 400) * (0.4 + 0.6 * psmooth(n, 4))
    S.add_post(air, -20)
    return S.render()


CAVE_MEL = ("B5:3 G#5:1 | E6:4 | C#6:2 E6:1 G#5:1 | F#5:4 | B5:2 D#6:1 E6:1 | F#6:3 D#6:1 | E6:2 C#6:1 A5:1 | "
            "B5:2 E6:2 | G#5:2 B5:1 E6:1 | C#6:2 G#6:2 | G#6:2 F#6:1 E6:1 | D#6:4 | C#6:2 E6:1 A6:1 | "
            "G#6:2 F#6:1 D#6:1 | E6:2 C#6:1 B5:1 | B5:4")


def song_cave():
    """Secret grotto (E major/lydian, 90 bpm): crystal FM arpeggios, glassy music-box melody,
    pitched water drips, long reverb."""
    ch = ['Emaj7', 'C#m7', 'Amaj7', 'B', 'Emaj7', 'G#m7', 'Amaj7', 'Bsus4',
          'C#m7', 'Amaj7', 'Emaj7', 'B', 'Amaj7', 'G#m7', 'C#m7', 'Bsus4']
    S = Song(90, 64, tail=10, t60=4.5, bright=0.85, pre=0.035)
    T = timeline(ch, 4)
    S.add(mel(CAVE_MEL, bpb=4, vel=0.6), i_musicbox, gain=0.7, rev=0.75, echo=(1.5, 0.4, 0.3), decay=2.2, name='glass')
    S.add(arp_ev(T, [0, 2, 4, 6, 5, 3, 1, 4], 0.5, low=64, vel=0.4, accents=[1, .7, .8, .7, .9, .7, .8, .7]),
          i_bell, gain=0.4, rev=0.7, echo=(0.75, 0.35, 0.25), ratio=2.0, index=0.9, decay=1.2, name='crystal')
    S.add(pad_ev(T, low=52, vel=0.45), i_pad, gain=0.45, rev=0.7, a=1.5, r=2.5, name='pad')
    S.add(pad_ev(T[8:], low=59, vel=0.3), i_choir, gain=0.2, rev=0.8, vowel='u', a=2.0, r=2.5, name='choir')
    S.add(bass_ev(T, [(0, 0, 3.8, 1.0)], low=40), i_softbass, gain=0.4, rev=0.4, a=0.3, r=1.5, name='bass')
    pent = [88, 90, 92, 95, 97, 100]
    beats = np.sort(RNG.choice(np.arange(0, 64, 0.5), 22, replace=False))
    drips = [(float(b), mhz(int(RNG.choice(pent))), 0.2, float(RNG.uniform(0.4, 0.9))) for b in beats]
    S.add(drips, i_drip, gain=0.6, rev=0.8, echo=(1.0, 0.4, 0.35), hum=0.0, name='drips')
    n = S.L
    S.add_post(pnoise(n, 30, 250) * (0.5 + 0.5 * psmooth(n, 3)), -22)
    return S.render()


CELLAR_MB = ("E5:1 A5:1 C6:1 | B5:2 G#5:1 | A5:1 E5:1 C5:1 | D5:2 F5:1 | E5:1 A5:1 C6:1 | D6:1.5 C6:.5 A5:1 | "
             "D#5:1 F#5:1 A5:1 | G#5:3 | C6:1 B5:1 A5:1 | G#5:2 E5:1 | A5:1 C6:1 E6:1 | F6:2 D6:1 | "
             "E6:1 C6:1 A5:1 | F5:1.5 E5:.5 D5:1 | E5:1 G#5:1 B5:1 | A5:3")


def song_cellar():
    """Witch's cellar (A minor waltz, 76 bpm): detuned music box + ghostly lower box, low string
    and organ drone, creaks, bubbling cauldron."""
    ch = ['Am', 'E7', 'Am', 'Dm', 'Am', 'Dm', 'B7', 'E', 'Am', 'E', 'Am', 'Dm', 'Am', 'Dm', 'E', 'Am']
    S = Song(76, 48, tail=8, t60=2.6, bright=0.4)
    T = timeline(ch, 3)
    m = [(b, f * 2 ** (RNG.normal(0, 0.1) / 12), d, v) for b, f, d, v in mel(CELLAR_MB, bpb=3, vel=0.75)]
    S.add(m, i_musicbox, gain=0.9, rev=0.45, echo=(1.5, 0.3, 0.2), decay=1.6, name='musicbox')
    ghost = [(b, f * 2 ** (RNG.normal(-0.15, 0.1) / 12), d, v) for b, f, d, v in shift(m, semis=-12, velmul=0.4)]
    S.add(ghost, i_musicbox, gain=0.45, rev=0.6, decay=2.0, bright=0.4, name='ghost-box')
    pah = [(st + o, mhz(mm), 0.8, 0.35) for name, st, d in T for o in (1, 2) for mm in voicing(name, 57)]
    S.add(pah, i_musicbox, gain=0.35, rev=0.4, decay=0.6, bright=0.5, name='pah')
    S.add(bass_ev(T, [(0, 0, 1.0, 1.0)], low=45), i_musicbox, gain=0.5, rev=0.35, decay=1.2, bright=0.3, name='oom')
    S.add([(0, mhz(nm('A1')), 48, 0.8)], i_strings, gain=0.45, rev=0.4, a=4.0, r=4.0, cut=300, name='drone')
    S.add([(0, mhz(nm('A2')), 48, 0.5), (0, mhz(nm('E3')), 48, 0.4)], i_organ, gain=0.12, rev=0.5, a=3.0, r=3.0,
          name='organ-drone')
    for st, f in ((7.5, 170), (29.0, 210)):
        S.add_sig(creak(0.6, f) * 0.5, st, gain=0.4, rev=0.5, name='creak')
    S.add_post(_bubbles(S.L, 34), -19)
    return S.render()


SHOP_CH = [('Gm7', 2), ('C7', 2), ('Fmaj7', 2), ('D7', 2), ('Gm7', 2), ('C7', 2), ('Am7', 2), ('D7b9', 2),
           ('Gm7', 2), ('C7', 2), ('Fmaj7', 2), ('Dm7', 2), ('Bbm6', 2), ('Eb7', 2), ('Am7', 2), ('D7b9', 2),
           'Gm7', 'C7', 'Am7', 'D7b9', 'Gm7', ('Bbm6', 2), ('Eb7', 2), ('Fmaj7', 2), ('Dm7', 2), ('Gm7', 2), ('C7', 2)]
SHOP_MEL = ("r:.5 D5:.5 F5:.5 G5:.5 Bb5:1 A5:.5 G5:.5 | A5:1.5 E5:.5 F#5:1 A5:1 | "
            "G5:.5 F5:.5 D5:.5 Bb4:.5 Db5:.5 C5:.5 Bb4:1 | C5:1 E5:.5 G5:.5 F#5:.5 Eb5:.5 C5:1 | "
            "r:.5 D5:.5 F5:.5 G5:.5 Bb5:.5 B5:.5 C6:1 | A5:1.5 G5:.5 F5:1 D5:1 | "
            "Db5:.5 F5:.5 G5:.5 Bb5:.5 Db6:1 C6:.5 Bb5:.5 | A5:1.5 G5:.5 F#5:.5 Eb5:.5 D5:1 | "
            "Bb5:1.5 A5:.5 G5:.5 F5:.5 D5:1 | E5:.5 G5:.5 Bb5:.5 Db6:.5 C6:2 | C6:1.5 B5:.5 A5:.5 G5:.5 E5:1 | "
            "F#5:.5 A5:.5 C6:.5 Eb6:.5 D6:2 | D6:1 Bb5:.5 G5:.5 F5:1 D5:1 | Db6:1 Bb5:.5 G5:.5 Db6:.5 C6:.5 Bb5:1 | "
            "A5:1.5 E5:.5 F5:1 A5:1 | G5:1 r:.5 F5:.5 E5:.5 Db5:.5 C5:1")


def song_shop():
    """Toke's black market (F major ii-V lounge, 112 bpm swing): chip 'sax' with scoops, rhodes
    comping, walking upright bass, brushes + ride, vinyl crackle."""
    S = Song(112, 64, tail=5, t60=1.4, bright=0.45)
    T = timeline(SHOP_CH, 4)
    lead = swing(mel(SHOP_MEL, bpb=4, vel=0.8))
    S.add(lead, i_square, gain=0.55, rev=0.25, echo=(0.75, 0.2, 0.12), duty=0.5, cut=2600, vib=(5.0, 0.3, 0.15),
          bend=(-1.0, 0.035), a=0.01, d=0.2, s=0.7, r=0.08, name='chip-sax')
    S.add(walk_ev(T, low=33), i_fingerbass, gain=0.75, rev=0.08, name='walk')
    comp = []
    for name, st, d in T:
        hits = [(0, 0.5), (1 + 2 / 3, 0.3)] if d <= 2 else [(0, 0.5), (1 + 2 / 3, 0.3), (2 + 2 / 3, 0.5)]
        for off, du in hits:
            comp += [(st + off, mhz(mm), du, 0.5) for mm in voicing(name, 55)]
    S.add(comp, i_epiano, gain=0.4, rev=0.25, trem=0.2, name='rhodes')
    ride, brush, kick = [], [], []
    for bar in range(16):
        st = 4 * bar
        ride += [(st + o, 0, 0.5, v) for o, v in ((0, .6), (1, .5), (1 + 2 / 3, .35), (2, .6), (3, .5), (3 + 2 / 3, .35))]
        brush += [(st + 1, 0, 0.5, 0.6), (st + 3, 0, 0.5, 0.6)]
        kick += [(st, 0, 0.5, 0.5), (st + 2, 0, 0.5, 0.4)]
    S.add(ride, d_ride, gain=0.35, rev=0.15, dec=0.9, hum=0.002, name='ride')
    S.add(brush, d_brush, gain=0.55, rev=0.15, name='brush')
    S.add(kick, d_kick, gain=0.18, rev=0.05, f0=50, dec=0.25, name='kick')
    S.add_post(_crackle_loop(S.L, 260), -27)
    return S.render()


REST_MEL = ("E5:2 G5:1 | E5:1.5 D5:.5 C5:1 | A4:2 C5:1 | B4:3 | E5:2 G5:1 | B5:1.5 A5:.5 G5:1 | A5:2 F5:1 | D5:3 | "
            "C5:2 E5:1 | F5:1.5 E5:.5 D5:1 | E5:1 D5:1 C5:1 | D5:3")


def song_rest():
    """Campfire rest (C major 3/4, 72 bpm, exactly 30 s): fingerpicked guitar and a soft plucked melody."""
    ch = ['C', 'Am', 'F', 'G', 'C', 'Em', 'F', 'G', 'Am', 'F', 'C', 'G']
    S = Song(72, 36, tail=7, t60=2.0, bright=0.4)
    T = timeline(ch, 3)
    S.add(bass_ev(T, [(0, 0, 2.0, 1.0)], low=40), i_pluck, gain=0.55, rev=0.2, decay=2.5, bright=0.5, rel=0.6,
          name='guitar-bass')
    S.add(arp_ev(T, [None, 1, 2, 3, 2, 1], 0.5, low=55, vel=0.45, accents=[1, 1, .8, .9, .75, .7]), i_pluck, gain=0.6,
          rev=0.25, decay=1.6, bright=0.7, rel=0.4, name='guitar')
    S.add(mel(REST_MEL, bpb=3, vel=0.6), i_pluck, gain=0.6, rev=0.3, echo=(1.5, 0.25, 0.15), decay=2.2, bright=0.9,
          rel=0.6, name='melody')
    S.add(pad_ev(T, low=52, vel=0.3), i_pad, gain=0.18, rev=0.5, a=1.5, r=2.0, name='hum')
    return S.render()


# --- alternate fanfares (non-loop) -------------------------------------------------------
def song_victory_2():
    S = Song(140, 12, loop=False, tail=2.5, t60=1.3, max_len=7.0)
    lead = mel("G5:.5 G5:.25 G5:.25 D6:1 C6:.5 B5:.5 A5:1 | D5:.5 D5:.25 D5:.25 A5:1 G5:.5 F#5:.5 E5:.5 F#5:.5 | "
               "G5:4", bpb=4, vel=0.9)
    S.add(lead, i_square, gain=0.6, rev=0.2, duty=0.25, vib=(6.0, 0.2, 0.25), name='lead')
    S.add(shift(lead, semis=-12, velmul=0.5), i_pwm, gain=0.35, rev=0.2, rate=5.0, depth=0.25, name='lead-low')
    T = timeline([('G', 2), ('C', 2), 'D'], 4)
    S.add(arp_ev(T, [0, 1, 2, 3, 4, 3, 2, 1], 0.25, low=67, vel=0.35), i_square, gain=0.3, rev=0.15, duty=0.125,
          a=0.002, d=0.04, s=0.3, r=0.02, vib=None, name='arp')
    S.add(mel("G2:.5 G3:.5 G2:.5 G3:.5 C3:.5 C4:.5 C3:.5 C4:.5 | D3:.5 D4:.5 D3:.5 D4:.5 D3:.5 D4:.5 D3:.5 D4:.5 | "
              "G2:4", bpb=4, vel=0.85), i_tri, gain=0.55, rev=0.1, name='tri-bass')
    S.add([(8, mhz(nm(n_)), 4, 0.7) for n_ in ('G4', 'B4', 'D5', 'G5')], i_brass, gain=0.45, rev=0.3, name='brass')
    D = Kit()
    D.ev['ck'] += pat("x...x...x...x...", 0) + pat("x...x...x.x.x.x.", 4) + [(8, 0, 1, 1.0)]
    D.ev['cs'] += pat("....x.......x...", 0) + pat("....x.......xxXX", 4)
    D.ev['ch'] += pat("x.x.x.x.x.x.x.x.", 0) + pat("x.x.x.x.x.x.....", 4)
    D.ev['cr'] += [(0, 0, 1, 0.7), (8, 0, 1, 1.0)]
    D.render(S)
    return S.render()


def song_victory_3():
    S = Song(126, 12, loop=False, tail=2.5, t60=1.5, max_len=7.0)
    lead = mel("C5:.5 F5:.5 A5:.5 C6:.5 r:.5 A5:.5 C6:1 | Bb5:.5 G5:.5 E5:.5 G5:.5 C6:1 Bb5:.5 G5:.5 | A5:4",
               bpb=4, vel=0.85)
    S.add(lead, i_steel, gain=0.85, rev=0.25, name='steel')
    S.add(shift(lead, semis=-12, velmul=0.6), i_marimba, gain=0.55, rev=0.2, name='marimba')
    T = timeline(['F', 'C7', 'F'], 4)
    S.add(arp_ev(T[:2], [0, 2, 1, 3, 1, 2, 0, 2], 0.5, low=55, vel=0.45), i_marimba, gain=0.45, rev=0.2, name='arp')
    S.add([(8, mhz(nm(n_)), 4, 0.6) for n_ in ('F4', 'A4', 'C5', 'F5')], i_steel, gain=0.5, rev=0.3, name='chord')
    S.add(mel("F2:1.5 C3:.5 F2:1 A2:1 | C3:1.5 G2:.5 C3:1 E2:1 | F2:4", bpb=4, vel=0.85), i_fingerbass, gain=0.7,
          rev=0.1, name='bass')
    S.add([(8, mhz(nm('F2')), 4, 0.8)], i_gong, gain=0.4, rev=0.3, decay=2.5, beat=1.5, name='gong')
    D = Kit()
    for st in (0, 4):
        D.ev['sh'] += pat("x.xox.xox.xox.xo", st, vmap={'x': 0.5, 'o': 0.3})
        D.ev['cg'] += [(b, 330.0, d, v) for b, _, d, v in pat("..x...x...xx..x.", st, vmap={'x': 0.55})]
        D.ev['kd'] += pat("x......x..x.....", st, vmap={'x': 0.6})
    D.ev['kt'] += pat("....x..x.xxxXXXX", 4, vmap={'x': 0.5, 'X': 0.8})
    D.ev['kd'] += [(8, 0, 1, 0.9)]
    D.render(S)
    return S.render()


def song_boss_victory():
    S = Song(116, 16, loop=False, tail=3.0, t60=1.8, max_len=9.6)
    hit = 8 + 8 / 3                        # one bar of 174-bpm DnB fill = 8/3 beats at 116 bpm
    lead = mel("A4:1/3 D5:1/3 F#5:1/3 A5:1.5 F#5:.5 A5:1 | D6:1 Bb5:.5 D6:.5 E6:1 C6:.5 E6:.5", bpb=4, vel=0.95)
    S.add(lead, i_square, gain=0.5, rev=0.25, duty=0.25, vib=(6.0, 0.2, 0.25), name='lead')
    S.add(lead, i_brass, gain=0.55, rev=0.25, name='brass-lead')
    chords = [(1, ['D4', 'F#4', 'A4'], 3), (4, ['Bb3', 'D4', 'F4'], 2), (6, ['C4', 'E4', 'G4'], 2),
              (hit, ['D4', 'F#4', 'A4', 'D5'], 4)]
    S.add([(b, mhz(nm(n_)), d, 0.7) for b, ns_, d in chords for n_ in ns_], i_brass, gain=0.5, rev=0.3, name='brass')
    S.add([(b, mhz(nm(n_)), d, 0.6) for b, ns_, d in chords for n_ in ns_], i_choir, gain=0.4, rev=0.5, vowel='a',
          a=0.08, r=1.2, name='choir')
    S.add([(hit, mhz(nm(n_)), 4, 0.95) for n_ in ('D6', 'A5')], i_square, gain=0.4, rev=0.3, duty=0.25,
          vib=(6.0, 0.25, 0.3), name='final-sq')
    S.add(mel("r:1 D3:3 Bb2:2 C3:2"), i_bass_saw, gain=0.6, rev=0.1, cut=600, name='bass')
    fspb = 60.0 / 174
    brk = make_break(fspb, tone=200)
    S.add_sig(chop(brk, fspb, CHOPS['f']), 8, gain=0.9, rev=0.05, name='dnb-fill')
    S.add_sig(reese([(8, mhz(nm('D2')), 8 / 3, 0.9)], S, det=0.25, cut=200, env_oct=0.0, q=1.5, drive=2.5, sub=0.8,
                    mod=lambda b: 2.5 * np.clip((b - 8) / (8 / 3), 0, 1)), gain=0.5, rev=0.03, name='reese-swell')
    D = Kit()
    D.ev['cs'] += [(0, 0, 1 / 3, 0.6), (1 / 3, 0, 1 / 3, 0.7), (2 / 3, 0, 1 / 3, 0.8)]
    D.ev['cr'] += [(1, 0, 1, 1.0), (hit, 0, 1, 1.0)]
    D.ev['bk'] += [(1, 0, 1, 1.0), (4, 0, 1, 0.8), (6, 0, 1, 0.8), (hit, 0, 1, 1.0)]
    D.render(S)
    S.add([(1, 73.4, 1, 0.9), (hit, 73.4, 1, 1.0), (hit + 1.5, 73.4, 1, 0.6)], d_timp, gain=0.5, rev=0.3, name='timp')
    S.add_sig(subdrop(1.6), hit, gain=0.5, rev=0.0, name='subdrop')
    return S.render()


# =====================================================================================
# SFX v2 -- interaction sounds
# =====================================================================================
def burst(dur, lo, hi, dec, a=0.0005):
    n = ns(dur)
    t = t_(n)
    return fin(bp(noise(n), lo, hi) * np.exp(-t / dec) * att(n, a), 0.002)


def swish(dur, f0, f1):
    n = ns(dur)
    u = t_(n) / (dur)
    nz = noise(n)
    y = np.zeros(n)
    for k, c in enumerate(np.geomspace(f0, f1, 6)):
        y += bp(nz, c * 0.7, c * 1.4) * np.exp(-0.5 * ((u - k / 5) / 0.2) ** 2)
    return fin(y * np.sin(np.pi * np.clip(u, 0, 1)) ** 1.5)


def coin_clink(f):
    n = ns(0.18)
    t = t_(n)
    x = sum(a * np.sin(TAU * f * r * t + TAU * RNG.random()) * np.exp(-t / dd)
            for r, a, dd in ((1, 1.0, 0.06), (1.51, 0.6, 0.04), (2.37, 0.45, 0.03), (3.12, 0.3, 0.02))
            if f * r < 0.45 * SR)
    x += hp(noise(n), 5000) * np.exp(-t / 0.002) * 0.5
    return fin(x * att(n, 0.0004))


def clank(f, dec=0.12):
    n = ns(dec * 5)
    t = t_(n)
    x = sum(a * np.sin(TAU * f * r * t + TAU * RNG.random()) * np.exp(-t / (dec * dd))
            for r, a, dd in ((1, 1.0, 1.0), (2.43, 0.7, 0.6), (3.97, 0.5, 0.4), (5.81, 0.3, 0.25))
            if f * r < 0.45 * SR)
    x += bp(noise(n), 2000, 9000) * np.exp(-t / 0.003) * 0.8
    return fin(x * att(n, 0.0004))


def sparkle(count, t0, spread, lo=4000, hi=9000, amp=(0.2, 0.6)):
    return [(t0 + RNG.uniform(0, spread), i_bell(RNG.uniform(lo, hi), 0.1, RNG.uniform(*amp), ratio=1.41, index=1.5,
                                                 decay=RNG.uniform(0.02, 0.07))) for _ in range(count)]


def sfx_interact():
    n = ns(0.12)
    t = t_(n)
    pop = np.sin(TAU * np.cumsum(260 + 520 * (1 - np.exp(-t / 0.012))) / SR) * np.exp(-t / 0.03) * att(n, 0.001)
    thump = np.sin(TAU * 140 * t) * np.exp(-t / 0.025) * att(n, 0.001)
    return finish(mix(0.2, [(0, d_wood(480.0, 0, 1.0)), (0, fin(pop) * 0.45), (0, fin(thump) * 0.5)]), -4)


def sfx_talk_start():
    a = blip(660, 0.05, 0.25, decay=0.035, bend=(-4, 0.015))
    b = blip(990, 0.09, 0.25, decay=0.05, bend=(-3, 0.02))
    return finish(mix(0.16, [(0, a), (0.05, b), (0.05, blip(1980, 0.05, kind='tri', decay=0.02) * 0.25)]), -6)


def sfx_sign_read():
    n = ns(0.5)
    t = t_(n)
    y = np.zeros(n)
    swell = np.exp(-0.5 * ((t - 0.12) / 0.06) ** 2) + 0.8 * np.exp(-0.5 * ((t - 0.32) / 0.07) ** 2)
    for _ in range(160):
        pos = RNG.uniform(0.02, 0.44)
        if RNG.random() > np.interp(pos, t, swell):
            continue
        m = ns(RNG.uniform(0.003, 0.018))
        tm = t_(m)
        fc = RNG.uniform(1500, 6500)
        g = bp(noise(m), fc * 0.6, fc * 1.6) * np.sin(np.pi * tm / tm[-1]) ** 2
        i = ns(pos)
        y[i:i + m] += g[:len(y[i:i + m])] * RNG.uniform(0.3, 1.0)
    y += bp(noise(n), 800, 5000) * swell * 0.08
    return finish(y, -6)


def sfx_switch_on():
    notes = [88, 95, 100, 104]
    items = [(k * 0.055, i_bell(mhz(m), 0.6, 0.85, ratio=2.0, index=1.4, decay=0.7)) for k, m in enumerate(notes)]
    items += [(k * 0.055, blip(mhz(m), 0.07, 0.25, decay=0.04) * 0.25) for k, m in enumerate(notes)]
    items += sparkle(14, 0.15, 0.4, amp=(0.2, 0.5))
    n = ns(0.9)
    items.append((0.05, hp(noise(n), 7000) * np.exp(-t_(n) / 0.25) * att(n, 0.02) * 0.08))
    return finish(reverb(mix(1.2, items), 1.2, 0.3, 0.9), -1, max_len=1.4)


def sfx_switch_fail():
    items = []
    for k, (m, d) in enumerate([(67, 0.17), (66, 0.17), (65, 0.17), (64, 0.5)]):
        n = ns(d)
        t = t_(n)
        fr = np.full(n, mhz(m))
        if d > 0.3:
            fr *= 1 + 0.012 * np.sin(TAU * 6 * t) * np.clip(t / 0.15, 0, 1)
        src = o_saw(fr) + 0.4 * o_sq(fr, 0.3)
        wah = np.clip(t / (d * 0.6), 0, 1)
        y = formant(src, 'u') * (1 - wah) + formant(src, 'a') * wah
        y = y / (np.max(np.abs(y)) + 1e-9) * smooth_env(n, 0.02, 0.05 if d < 0.3 else 0.15)
        items.append((k * 0.19, y))
    return finish(reverb(mix(1.1, items), 0.5, 0.15), -3)


def sfx_puzzle_solved():
    seq = [(0.0, 72), (0.08, 76), (0.16, 79), (0.24, 84)]
    items = [(st, blip(mhz(m), 0.12, 0.25, decay=0.06)) for st, m in seq]
    items += [(st, i_bell(mhz(m + 12), 0.2, 0.4, ratio=2.0, index=0.8, decay=0.35)) for st, m in seq]
    for m in (84, 88, 91, 86):
        items.append((0.36, i_square(mhz(m), 0.7, 0.35, duty=0.25, a=0.005, d=0.2, s=0.6, r=0.35)))
        items.append((0.36, i_bell(mhz(m + 12), 0.9, 0.3, ratio=2.0, index=1.0, decay=0.8)))
    items += [(0.36 + k * 0.06, blip(mhz(m), 0.06, 0.125, decay=0.04) * 0.35) for k, m in enumerate([96, 100, 103, 108])]
    return finish(reverb(mix(1.5, items), 0.9, 0.25, 0.8), -1, max_len=1.6)


def sfx_secret_found():
    run = [74, 81, 78, 85, 81, 88, 85, 92]          # zig-zag climb D5 A5 F#5 C#6 A5 E6 C#6 G#6 (original)
    items = []
    for k, m in enumerate(run):
        items.append((k * 0.09, i_square(mhz(m), 0.08, 0.6, duty=0.5, a=0.003, d=0.05, s=0.7, r=0.04, vib=None)))
        items.append((k * 0.09, i_bell(mhz(m + 12), 0.1, 0.25, ratio=2.0, index=0.8, decay=0.25)))
    st = len(run) * 0.09
    for m in (81, 85, 88, 93):
        items.append((st, i_square(mhz(m), 0.6, 0.3, duty=0.25, a=0.01, d=0.2, s=0.7, r=0.4)))
        items.append((st, i_bell(mhz(m + 12), 0.8, 0.3, ratio=2.0, index=1.2, decay=0.9)))
    n = ns(0.9)
    items.append((st, hp(noise(n), 6000) * np.exp(-t_(n) / 0.3) * att(n, 0.05) * 0.1))
    return finish(reverb(mix(1.6, items), 1.0, 0.3, 0.85), -1, max_len=1.6)


def sfx_pickup():
    items = [(0, blip(1568, 0.05, 0.25, decay=0.03)), (0.045, blip(2093, 0.12, 0.25, decay=0.05))]
    items += sparkle(8, 0.03, 0.25, 4500, 9000)
    return finish(reverb(mix(0.45, items), 0.5, 0.15, 0.9), -3)


def sfx_dig():
    def stroke():
        n = ns(0.22)
        e = smooth_env(n, 0.03, 0.08)
        scr = bp(noise(n), 900, 4500) * e * (0.6 + 0.4 * lp(np.abs(noise(n)), 60) * 3)
        y = scr * 0.6 + crackles(n, 25, 1.2) * e
        m = ns(0.12)
        tm = t_(m)
        chuff = (lp(noise(m), 350) * 1.5 + np.sin(TAU * 85 * tm) * 0.5) * np.exp(-tm / 0.03) * att(m, 0.002)
        return mix(0.35, [(0, y), (0.18, fin(chuff))])
    return finish(mix(0.7, [(0, stroke()), (0.33, stroke() * 0.85)]), -2)


def sfx_well():
    m = ns(0.12)
    tm = t_(m)
    plop = np.sin(TAU * np.cumsum(350 + 900 * (1 - np.exp(-tm / 0.02))) / SR) * np.exp(-tm / 0.035) * att(m, 0.002)
    bub = lp(noise(m), 1200) * np.exp(-tm / 0.02) * att(m, 0.002) * 0.3
    dry = mix(2.0, [(0, d_wood(1900.0, 0, 0.6) * 0.5), (0.5, fin(plop)), (0.5, fin(bub))])
    x = dry + 0.8 * echo_fx(dry, 0.17, 0.55, 1400)
    return finish(reverb(x, 1.8, 0.45, 0.2), -1, max_len=1.9)


def sfx_shop_open():
    ding = i_bell(2093, 0.9, 1.0, ratio=2.0, index=0.6, decay=0.55) + \
        0.5 * i_bell(2637, 0.9, 0.6, ratio=2.0, index=0.6, decay=0.45)
    n = ns(0.25)
    drawer = bp(noise(n), 300, 2500) * smooth_env(n, 0.05, 0.08) * 0.5 + crackles(n, 20, 1.0) * 0.6
    coins = [(0.42 + k * 0.035, coin_clink(RNG.uniform(3000, 5000)) * 0.25) for k in range(3)]
    items = [(0, burst(0.025, 1200, 7000, 0.004)), (0.04, burst(0.03, 600, 4000, 0.006)), (0.08, ding),
             (0.12, drawer), (0.38, hit_core(90, 0.06, 0.03, 1500) * 0.5)] + coins
    return finish(reverb(mix(1.1, items), 0.6, 0.2), -1, max_len=1.2)


def sfx_sell():
    items = [(st, coin_clink(f) * a) for st, f, a in ((0, 3800, 1), (0.06, 4600, .8), (0.1, 3300, .7),
                                                       (0.17, 5200, .6), (0.24, 4100, .5))]
    items.append((0.0, blip(1318.5, 0.05, 0.5, decay=0.04) * 0.2))
    return finish(reverb(mix(0.55, items), 0.4, 0.15, 0.8), -2)


def sfx_menu_open():
    return finish(mix(0.22, [(0, swish(0.14, 700, 4000) * 0.5), (0.03, blip(880, 0.05, 0.25, decay=0.03)),
                             (0.08, blip(1318.5, 0.08, 0.25, decay=0.04))]), -5)


def sfx_menu_close():
    return finish(mix(0.22, [(0, swish(0.14, 4000, 700) * 0.5), (0.03, blip(1318.5, 0.05, 0.25, decay=0.03)),
                             (0.08, blip(880, 0.08, 0.25, decay=0.04))]), -5)


def sfx_skill_unlock():
    items = [(k * 0.045, blip(mhz(m), 0.07, 0.25, decay=0.04)) for k, m in enumerate([72, 76, 79, 84, 88, 91, 96])]
    items.append((0, swish(0.35, 500, 7000) * 0.4))
    st = 0.34
    for m in (84, 88, 91, 95):
        items.append((st, i_bell(mhz(m), 0.8, 0.5, ratio=2.0, index=1.3, decay=0.8)))
        items.append((st, i_square(mhz(m - 12), 0.5, 0.25, duty=0.25, a=0.005, s=0.6, r=0.35)))
    items += sparkle(16, st, 0.6, amp=(0.15, 0.45))
    return finish(reverb(mix(1.4, items), 1.1, 0.3, 0.9), -1, max_len=1.5)


def sfx_equip():
    return finish(reverb(mix(0.45, [(0, clank(1150, 0.12)), (0.075, clank(1720, 0.08) * 0.6),
                                    (0, hit_core(140, 0.03, 0.02, 3000) * 0.4)]), 0.4, 0.15), -2)


def sfx_heal_small():
    items = [(0, i_bell(mhz(79), 0.5, 0.7, ratio=2.0, index=0.7, decay=0.5)),
             (0.1, i_bell(mhz(86), 0.5, 0.6, ratio=2.0, index=0.7, decay=0.55))]
    n = ns(0.6)
    t = t_(n)
    w = np.sin(np.pi * t / t[-1]) ** 2
    items += [(0, (np.sin(TAU * mhz(79) * t) + np.sin(TAU * mhz(83) * t)) * w * 0.08), (0, hp(noise(n), 6500) * w * 0.05)]
    return finish(reverb(mix(0.8, items), 1.0, 0.3, 0.8), -3, max_len=1.0)


# =====================================================================================
# SFX v2 -- enemy / creature voices (formant synthesis)
# =====================================================================================
NASAL = [(260, 1.0, 60), (1000, 0.12, 120), (2300, 0.06, 160)]


def voc(dur, f_pts, vowels, rasp=0.1, jitter=0.02, sub=0.0, breath=0.0, shift_=1.0, vib=None, am=None):
    """Formant voice. f_pts: [(time_fraction, hz)] contour or a frequency array; vowels:
    [(time_fraction, vowel name | formant spec)] crossfaded in order. Returns peak-normalised."""
    if isinstance(f_pts, np.ndarray):
        fr = f_pts.astype(float)
        n = len(fr)
    else:
        n = ns(dur)
        fr = np.interp(np.linspace(0, 1, n), [p[0] for p in f_pts], [p[1] for p in f_pts])
    t = t_(n)
    if vib:
        fr = fr * 2 ** (vib[1] * np.sin(TAU * vib[0] * t) / 12)
    fr = fr * (1 + jitter * lp(noise(n), 30) * 5)
    s = o_saw(fr)
    src = s + sub * o_saw(fr * 0.5) + rasp * noise(n) * (0.5 + 0.5 * (s > 0))
    if am is not None:
        src = src * am(t)
    if breath:
        src = src + breath * noise(n) * 2.0
    ts = [p[0] for p in vowels]
    y = np.zeros(n)
    for k, (_, v) in enumerate(vowels):
        w = np.interp(t / (n / SR), ts, [1.0 if j == k else 0.0 for j in range(len(vowels))])
        y += formant(src, v, shift_) * w
    return y / (np.max(np.abs(y)) + 1e-9)


def sfx_tourist_1():                 # grumpy fat man: "hrrrm-pf"
    h = burst(0.07, 400, 2500, 0.03) * 0.25
    y = voc(0.34, [(0, 105), (0.3, 122), (1, 92)], [(0, 'u'), (0.4, NASAL), (1, NASAL)], rasp=0.35, jitter=0.04,
            sub=0.4, am=lambda t: 1 + 0.35 * np.sin(TAU * 31 * t))
    y = np.tanh(1.8 * y) * smooth_env(len(y), 0.03, 0.06)
    p = burst(0.03, 200, 1500, 0.01) * 0.8
    f = burst(0.18, 1200, 6000, 0.06) * 0.35
    return finish(mix(0.7, [(0, h), (0.04, y), (0.38, p), (0.4, f)]), -1, max_len=1.2)


def sfx_tourist_2():                 # long creaky burp + satisfied "mm"
    y = voc(0.62, [(0, 80), (0.15, 102), (0.6, 88), (1, 66)], [(0, 'o'), (0.3, 'a'), (1, 'o')], rasp=0.5,
            jitter=0.09, sub=0.6, shift_=0.8,
            am=lambda t: 0.45 + 0.55 * np.clip(lp(noise(len(t)), 45) * 25 + 0.5, 0, 1))
    y = np.tanh(2.0 * y) * smooth_env(len(y), 0.025, 0.12)
    tail = voc(0.18, [(0, 120), (1, 95)], [(0, 'u'), (1, NASAL)], rasp=0.2, jitter=0.03)
    tail = tail * smooth_env(len(tail), 0.02, 0.08) * 0.35
    return finish(mix(0.95, [(0, y), (0.66, tail)]), -1, max_len=1.2)


def shutter(amp=1.0):
    def clk(lo, hi, dec, a):
        m = ns(0.03)
        tm = t_(m)
        c = bp(noise(m), lo, hi) * np.exp(-tm / dec) + np.sin(TAU * lo * 0.6 * tm) * np.exp(-tm / 0.003) * 0.4
        return fin(c * att(m, 0.0004)) * a
    return mix(0.1, [(0, clk(2500, 9000, 0.002, 1.0)), (0.05, clk(1200, 6000, 0.0035, 0.75))]) * amp


def sfx_influencer_1():              # shutter + breathy "oooh"
    ooh = voc(0.5, [(0, 300), (0.3, 430), (1, 360)], [(0, 'u'), (0.5, 'o'), (1, 'u')], rasp=0.04, jitter=0.015,
              breath=0.25, shift_=1.18, vib=(5.5, 0.35))
    ooh = ooh * smooth_env(len(ooh), 0.06, 0.15)
    return finish(mix(0.8, [(0, shutter()), (0.17, ooh * 0.8)]), -1, max_len=1.2)


def sfx_influencer_2():              # burst-mode shutter + "wooow"
    wow = voc(0.55, [(0, 340), (0.45, 560), (1, 430)], [(0, 'u'), (0.45, 'a'), (1, 'u')], rasp=0.04, jitter=0.015,
              breath=0.2, shift_=1.2, vib=(6.0, 0.3))
    wow = wow * smooth_env(len(wow), 0.05, 0.15)
    return finish(mix(1.0, [(0, shutter()), (0.11, shutter(0.85)), (0.22, shutter(0.9)), (0.36, wow * 0.8)]), -1,
                  max_len=1.2)


def screech(d, f0, f1, f2):
    y = voc(d, [(0, f0), (0.35, f1), (1, f2)], [(0, 'i'), (0.5, 'a'), (1, 'e')], rasp=0.6, jitter=0.05, shift_=1.7,
            vib=(19, 1.0))
    return np.tanh(3.0 * y) * smooth_env(len(y), 0.015, 0.06)


def sfx_macaque_1():
    return finish(mix(0.85, [(0, screech(0.3, 1300, 1900, 1500)), (0.36, screech(0.38, 1500, 2200, 1350))]), -1,
                  max_len=1.2)


def sfx_macaque_2():                 # "ak-ak-ak-ak" chatter + short screech
    items = []
    st = 0.0
    for _ in range(7):
        d = RNG.uniform(0.05, 0.075)
        f = RNG.uniform(950, 1350)
        y = voc(d, [(0, f), (0.5, f * 1.15), (1, f * 0.9)], [(0, 'a'), (1, 'e')], rasp=0.4, jitter=0.03, shift_=1.6)
        items.append((st, np.tanh(2.5 * y) * smooth_env(len(y), 0.004, 0.015)))
        items.append((st + d - 0.004, burst(0.008, 2500, 8000, 0.0015) * 0.3))
        st += d + RNG.uniform(0.025, 0.045)
    items.append((st + 0.03, screech(0.22, 1400, 1800, 1200) * 0.8))
    return finish(mix(0.9, items), -1, max_len=1.2)


def snap(f=2400, a=1.0):
    m = ns(0.06)
    tm = t_(m)
    x = hp(noise(m), 3000) * np.exp(-tm / 0.0009) + np.sin(TAU * f * tm) * np.exp(-tm / 0.006) * 0.5 + \
        np.sin(TAU * 420 * tm) * np.exp(-tm / 0.01) * 0.4
    return fin(x * att(m, 0.0003)) * a


def sfx_crab_1():
    return finish(mix(0.35, [(0, snap(2300)), (0.15, snap(2700, 0.9))]), -2)


def sfx_crab_2():
    items = [(k * 0.045 + RNG.uniform(0, 0.01), snap(RNG.uniform(2000, 3200), RNG.uniform(0.5, 0.9))) for k in range(6)]
    m = ns(0.04)
    tm = t_(m)
    for st in (0.3, 0.38):
        items.append((st, np.sin(TAU * np.cumsum(300 + 900 * tm / 0.04) / SR) * np.sin(np.pi * tm / tm[-1]) * 0.4))
    return finish(mix(0.5, items), -2)


def sfx_fox_1():                     # yip-yip
    def yip(f):
        y = voc(0.12, [(0, f), (0.3, f * 1.6), (1, f * 1.05)], [(0, 'a'), (1, 'e')], rasp=0.2, jitter=0.02,
                shift_=1.35)
        return np.tanh(2 * y) * smooth_env(len(y), 0.006, 0.04)
    return finish(mix(0.45, [(0, yip(680)), (0.2, yip(720))]), -1)


def sfx_fox_2():                     # howl
    y = voc(1.15, [(0, 470), (0.25, 860), (0.6, 820), (1, 600)], [(0, 'u'), (0.3, 'o'), (0.8, 'o'), (1, 'u')],
            rasp=0.08, jitter=0.012, breath=0.08, shift_=1.25, vib=(5.0, 0.35))
    y = y * smooth_env(len(y), 0.12, 0.3)
    return finish(reverb(y, 1.2, 0.25, 0.5), -1, max_len=1.2)


def sfx_dog_1():                     # woof woof
    def woof(f, a):
        y = voc(0.17, [(0, f), (0.2, f * 1.15), (1, f * 0.7)], [(0, 'a'), (0.6, 'u'), (1, 'u')], rasp=0.55,
                jitter=0.04, sub=0.4)
        return np.tanh(2.5 * y) * smooth_env(len(y), 0.008, 0.06) * a
    return finish(mix(0.6, [(0, woof(330, 1.0)), (0.24, woof(300, 0.85))]), -1)


def sfx_dog_2():                     # growl
    y = voc(0.9, [(0, 90), (0.5, 100), (1, 85)], [(0, 'r'), (0.5, 'o'), (1, 'r')], rasp=0.7, jitter=0.06, sub=0.6,
            shift_=0.9, am=lambda t: 0.4 + 0.6 * (0.5 + 0.5 * np.sin(TAU * 27 * t + 3 * lp(noise(len(t)), 8) * 30)))
    n = len(y)
    y = np.tanh(2.2 * y) * smooth_env(n, 0.15, 0.15) * (0.6 + 0.4 * np.clip(t_(n) / 0.6, 0, 1))
    return finish(y, -1)


def sfx_guard_1():                   # pea whistle: short tweet + long blast
    def blast(d, f0):
        n = ns(d)
        t = t_(n)
        trill = 0.5 + 0.5 * np.sin(TAU * 34 * t + 2.0 * lp(noise(n), 20) * 3)
        fr = f0 * (1 + 0.025 * trill) * (1 + 0.01 * np.exp(-t / 0.02))
        ph = np.cumsum(fr) / SR
        x = (np.sin(TAU * ph) + 0.25 * np.sin(2 * TAU * ph)) * (0.6 + 0.4 * trill)
        x += bp(noise(n), f0 * 0.7, f0 * 1.4) * 0.25
        return x * smooth_env(n, 0.012, 0.05)
    return finish(mix(0.85, [(0, blast(0.13, 2850)), (0.2, blast(0.6, 2850))]), -2)


def sfx_guard_2():                   # stern "Hey!"
    h = burst(0.05, 500, 3000, 0.03) * 0.3
    y = voc(0.28, [(0, 175), (0.3, 165), (1, 120)], [(0, 'e'), (0.7, 'e'), (1, 'i')], rasp=0.25, jitter=0.03, sub=0.2)
    y = np.tanh(1.8 * y) * smooth_env(len(y), 0.015, 0.08)
    return finish(mix(0.4, [(0, h), (0.035, y)]), -1)


def sfx_farmer_1():                  # strained grunt
    y = voc(0.42, [(0, 125), (0.3, 115), (1, 95)], [(0, NASAL), (0.3, 'a'), (1, 'r')], rasp=0.5, jitter=0.05, sub=0.4,
            am=lambda t: 1 + 0.3 * np.sin(TAU * 24 * t))
    return finish(np.tanh(2.5 * y) * smooth_env(len(y), 0.03, 0.1), -1)


def sfx_farmer_2():                  # "ptoo" + spit splat
    too = voc(0.13, [(0, 170), (1, 150)], [(0, 'u'), (1, 'u')], rasp=0.2)
    too = too * smooth_env(len(too), 0.01, 0.05)
    n = ns(0.2)
    fly = bp(noise(n), 2000, 7000) * smooth_env(n, 0.03, 0.12) * 0.15
    m = ns(0.15)
    tm = t_(m)
    splat = bp(noise(m), 300, 2200) * (1 - np.exp(-tm / 0.002)) * np.exp(-tm / 0.03) * (1 + 0.6 * np.sin(TAU * 45 * tm))
    k = ns(0.04)
    tk = t_(k)
    drops = [(0.5 + j * 0.03 + RNG.uniform(0, 0.01),
              np.sin(TAU * np.cumsum(RNG.uniform(600, 1300) * 2 ** (-tk / 0.03)) / SR) * np.sin(np.pi * tk / 0.04) * 0.25)
             for j in range(3)]
    items = [(0, burst(0.02, 150, 1500, 0.006) * 0.8), (0.02, burst(0.015, 2000, 7000, 0.004) * 0.5), (0.03, too),
             (0.15, fly), (0.45, fin(splat))] + drops
    return finish(mix(0.7, items), -1, max_len=1.2)


def sfx_fisher_1():                  # hummed sea-shanty fragment (original tune)
    notes = [(0.0, 'D3', 0.16), (0.17, 'G3', 0.21), (0.4, 'G3', 0.09), (0.5, 'A3', 0.12), (0.63, 'B3', 0.21),
             (0.86, 'A3', 0.3)]
    dur = 1.18
    n = ns(dur)
    f = np.full(n, mhz(nm('D3')))
    gate = np.zeros(n)
    for st, nn, d in notes:
        f[ns(st):] = mhz(nm(nn))
        gate[ns(st):ns(st + d)] = 1.0
    a = np.exp(-1.0 / (0.015 * SR))
    f = ss.lfilter([1 - a], [1, -a], f, zi=[a * f[0]])[0]
    a2 = np.exp(-1.0 / (0.012 * SR))
    gate = 0.25 + 0.75 * ss.lfilter([1 - a2], [1, -a2], gate)
    y = voc(dur, f, [(0, NASAL), (0.5, 'u'), (1, NASAL)], rasp=0.06, jitter=0.012, sub=0.2, vib=(5.0, 0.15))
    return finish(reverb(y * gate * smooth_env(n, 0.03, 0.12), 0.8, 0.15), -2, max_len=1.2)


def sfx_bookie_1():                  # sleazy "heh-heh-heh" + wheeze
    items = []
    for k in range(5):
        f = 200 - 12 * k
        y = voc(0.1, [(0, f), (1, f * 0.92)], [(0, 'e'), (1, NASAL)], rasp=0.3, jitter=0.03, breath=0.15, shift_=1.05)
        items += [(k * 0.155, burst(0.035, 600, 3500, 0.02) * 0.35),
                  (k * 0.155 + 0.025, y * smooth_env(len(y), 0.008, 0.04))]
    wz = voc(0.22, [(0, 260), (1, 300)], [(0, 'i'), (1, 'i')], rasp=0.1, breath=0.8, shift_=1.1)
    items.append((0.8, wz * smooth_env(len(wz), 0.05, 0.08) * 0.25))
    return finish(mix(1.05, items), -1, max_len=1.2)


def sfx_wolf_1():                    # teeth grinding "knirsch"
    n = ns(0.75)
    t = t_(n)
    strokes = sum(np.exp(-0.5 * ((t - c) / 0.07) ** 2) for c in (0.12, 0.36, 0.6))
    y = np.zeros(n)
    for _ in range(480):
        pos = RNG.uniform(0, 0.72)
        if RNG.random() > np.interp(pos, t, strokes):
            continue
        d = RNG.uniform(0.0006, 0.002)
        m = ns(d * 6)
        tm = t_(m)
        g = fin(hp(noise(m), RNG.uniform(1500, 5000)) * np.exp(-tm / d) * att(m, 0.0003))
        i = ns(pos)
        y[i:i + m] += g[:len(y[i:i + m])] * RNG.uniform(0.3, 1.0)
    grind = bp(o_saw(70.0 * (1 + 0.1 * lp(noise(n), 20) * 5)), 300, 1600) * strokes * 0.25
    return finish(y + grind, -1)


def sfx_butcher_1():                 # deep menacing "HO HO HO hooo"
    items = []
    for k, (f, d) in enumerate([(84, 0.2), (80, 0.2), (76, 0.2), (72, 0.38)]):
        y = voc(d, [(0, f * 1.08), (0.3, f), (1, f * 0.85)], [(0, 'o'), (1, 'o' if k < 3 else 'u')], rasp=0.4,
                jitter=0.04, sub=0.8, shift_=0.82)
        y = np.tanh(2.0 * y) * smooth_env(len(y), 0.02, 0.07 if k < 3 else 0.2)
        items += [(k * 0.24, burst(0.05, 300, 2000, 0.03) * 0.3), (k * 0.24 + 0.03, y)]
    return finish(reverb(mix(1.2, items), 1.4, 0.3, 0.35), -1, max_len=1.2)


def sfx_butcher_2():                 # cleaver scraped along steel, ending in a ring
    d = 0.7
    n = ns(d)
    t = t_(n)
    fric = tvlp(hp(noise(n), 800), 1800 * 2 ** (1.4 * t / d), 1.5)
    chatter = lp(0.6 + 0.4 * np.sign(np.sin(TAU * np.cumsum(60 + 40 * t) / SR)), 400)
    src = fric * chatter * smooth_env(n, 0.08, 0.1)
    steel = [(1230, 1.0, 25), (2570, 0.8, 35), (3940, 0.6, 45), (5380, 0.45, 60), (7100, 0.3, 80)]
    y = formant(src, steel) + 0.3 * src
    rn = ns(0.6)
    tr = t_(rn)
    ring = sum(a * np.sin(TAU * f * 1.03 * tr + TAU * RNG.random()) * np.exp(-tr / (0.35 / (1 + k * 0.4)))
               for k, (f, a, _) in enumerate(steel))
    ring = fin(ring * att(rn, 0.002)) * 0.4
    return finish(reverb(mix(1.2, [(0, y), (d - 0.05, ring)]), 0.7, 0.2, 0.6), -1, max_len=1.2)


def sfx_cow_1():
    y = voc(1.15, [(0, 118), (0.3, 142), (0.7, 128), (1, 100)], [(0, NASAL), (0.2, 'u'), (0.55, 'o'), (1, 'u')],
            rasp=0.18, jitter=0.02, sub=0.35, shift_=0.85, vib=(4.5, 0.2))
    return finish(np.tanh(1.5 * y) * smooth_env(len(y), 0.12, 0.25), -1, max_len=1.2)


def sfx_turtle_1():                  # slow breathy sigh
    y = voc(1.1, [(0, 95), (0.4, 88), (1, 70)], [(0, 'a'), (0.6, 'o'), (1, 'u')], rasp=0.3, jitter=0.03, breath=1.2,
            shift_=0.9)
    return finish(y * smooth_env(len(y), 0.25, 0.45), -3, max_len=1.2)


def sfx_gecko_1():                   # "to-KAY"
    croak = lambda r: (lambda t: 0.6 + 0.4 * np.sin(TAU * r * t))
    to = voc(0.17, [(0, 430), (1, 380)], [(0, 'o'), (1, 'u')], rasp=0.35, jitter=0.03, am=croak(42))
    to = np.tanh(2 * to) * smooth_env(len(to), 0.008, 0.05)
    kay = voc(0.27, [(0, 410), (0.3, 430), (1, 330)], [(0, 'a'), (0.5, 'e'), (1, 'e')], rasp=0.35, jitter=0.03,
              am=croak(40))
    kay = np.tanh(2 * kay) * smooth_env(len(kay), 0.01, 0.08)
    return finish(mix(0.8, [(0, burst(0.006, 2500, 8000, 0.0015) * 0.6), (0.005, to),
                            (0.3, burst(0.01, 1500, 6000, 0.002) * 0.6), (0.31, kay)]), -1)


def sfx_chicken_1():                 # three quick boks
    return finish(mix(0.45, [(0, bok(0.08, 560)), (0.13, bok(0.07, 600) * 0.85), (0.25, bok(0.09, 520) * 0.9)]), -2)


def sfx_chicken_2():                 # "bok bok ba-GAWK"
    gawk = voc(0.25, [(0, 800), (0.3, 1050), (1, 700)], [(0, CHICK_A), (1, CHICK_O)], rasp=0.5, jitter=0.04)
    gawk = np.tanh(2 * gawk) * smooth_env(len(gawk), 0.01, 0.06)
    return finish(mix(0.7, [(0, bok(0.07, 540)), (0.12, bok(0.07, 540) * 0.9), (0.26, bok(0.06, 620, a_spec=CHICK_A)),
                            (0.33, gawk)]), -2)


def sfx_chicken_3():                 # contented murmur "brrrk"
    m = voc(0.4, [(0, 430), (1, 380)], [(0, CHICK_U), (1, CHICK_O)], rasp=0.2, jitter=0.03,
            am=lambda t: 0.55 + 0.45 * np.sin(TAU * 24 * t))
    m = m * smooth_env(len(m), 0.04, 0.1) * 0.7
    return finish(mix(0.62, [(0, m), (0.46, bok(0.07, 500) * 0.8)]), -2)


def sfx_rooster_1():                 # cock-a-doodle-doo
    syl = [(0.0, 0.11, [(0, 560), (1, 640)], CHICK_O), (0.13, 0.09, [(0, 700), (1, 760)], CHICK_A),
           (0.25, 0.16, [(0, 820), (0.5, 900), (1, 840)], CHICK_A),
           (0.44, 0.66, [(0, 880), (0.2, 960), (0.7, 900), (1, 700)], CHICK_A)]
    parts = []
    for k, (st, d, fp, sp) in enumerate(syl):
        last = k == len(syl) - 1
        y = voc(d, fp, [(0, sp), (1, CHICK_U if last else sp)], rasp=0.45, jitter=0.03,
                vib=(9, 0.4) if last else None)
        parts.append((st, np.tanh(2.2 * y) * smooth_env(len(y), 0.008, d * 0.3 if last else 0.025)))
    return finish(mix(1.15, parts), -1, max_len=1.2)


# =====================================================================================
# v2 registry (rendered after the originals, each with its own name-seeded RNG)
# =====================================================================================
MUSIC2 = {
    'battle_1': (song_battle_1, True), 'battle_2': (song_battle_2, True), 'battle_3': (song_battle_3, True),
    'battle_4': (song_battle_4, True), 'battle_5': (song_battle_5, True),
    'boss_dnb_1': (song_boss_dnb_1, True), 'boss_dnb_2': (song_boss_dnb_2, True), 'boss_dnb_3': (song_boss_dnb_3, True),
    'beach_2': (song_beach_2, True), 'village_2': (song_village_2, True), 'steppe_2': (song_steppe_2, True),
    'farm_2': (song_farm_2, True), 'cave': (song_cave, True), 'cellar': (song_cellar, True), 'shop': (song_shop, True),
    'rest': (song_rest, True),
    'victory_2': (song_victory_2, False), 'victory_3': (song_victory_3, False),
    'boss_victory': (song_boss_victory, False),
}
SFX2 = {
    'interact': sfx_interact, 'talk_start': sfx_talk_start, 'sign_read': sfx_sign_read, 'switch_on': sfx_switch_on,
    'switch_fail': sfx_switch_fail, 'puzzle_solved': sfx_puzzle_solved, 'secret_found': sfx_secret_found,
    'pickup': sfx_pickup, 'dig': sfx_dig, 'well': sfx_well, 'shop_open': sfx_shop_open, 'sell': sfx_sell,
    'menu_open': sfx_menu_open, 'menu_close': sfx_menu_close, 'skill_unlock': sfx_skill_unlock, 'equip': sfx_equip,
    'heal_small': sfx_heal_small,
    'tourist_1': sfx_tourist_1, 'tourist_2': sfx_tourist_2, 'influencer_1': sfx_influencer_1,
    'influencer_2': sfx_influencer_2, 'macaque_1': sfx_macaque_1, 'macaque_2': sfx_macaque_2, 'crab_1': sfx_crab_1,
    'crab_2': sfx_crab_2, 'fox_1': sfx_fox_1, 'fox_2': sfx_fox_2, 'dog_1': sfx_dog_1, 'dog_2': sfx_dog_2,
    'guard_1': sfx_guard_1, 'guard_2': sfx_guard_2, 'farmer_1': sfx_farmer_1, 'farmer_2': sfx_farmer_2,
    'fisher_1': sfx_fisher_1, 'bookie_1': sfx_bookie_1, 'wolf_1': sfx_wolf_1, 'butcher_1': sfx_butcher_1,
    'butcher_2': sfx_butcher_2, 'cow_1': sfx_cow_1, 'turtle_1': sfx_turtle_1, 'gecko_1': sfx_gecko_1,
    'chicken_1': sfx_chicken_1, 'chicken_2': sfx_chicken_2, 'chicken_3': sfx_chicken_3, 'rooster_1': sfx_rooster_1,
}


def with_rng(name, fn):
    """Run fn with a fresh RNG seeded from `name` (keeps the original items' RNG stream untouched)."""
    global RNG
    saved = RNG
    RNG = np.random.default_rng([20261018, zlib.crc32(name.encode())])
    try:
        return fn()
    finally:
        RNG = saved


# =====================================================================================
# I/O + verification
# =====================================================================================
def write_wav(path, x):
    x = np.clip(x, -1, 1)
    data = np.round(x * 32767).astype('<i2')
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def read_wav(path):
    with wave.open(path, 'rb') as w:
        p = (w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getcomptype())
        d = np.frombuffer(w.readframes(w.getnframes()), dtype='<i2').astype(float) / 32767
    return p, d


MUSIC = {
    'title': (song_title, True), 'beach': (song_beach, True), 'village': (song_village, True),
    'steppe': (song_steppe, True), 'cliff': (song_cliff, True), 'farm': (song_farm, True),
    'battle': (song_battle, True), 'boss': (song_boss, True), 'memory': (song_memory, True),
    'void': (song_void, True), 'ending': (song_ending, True), 'victory': (song_victory, False),
    'gameover': (song_gameover, False), 'revolution': (song_revolution, False),
}
SFX = {
    'ui_move': sfx_ui_move, 'ui_select': sfx_ui_select, 'ui_cancel': sfx_ui_cancel, 'ui_error': sfx_ui_error,
    'text_blip': sfx_text_blip, 'step': sfx_step, 'cluck1': sfx_cluck1, 'cluck2': sfx_cluck2,
    'cluck_angry': sfx_cluck_angry, 'hit': sfx_hit, 'hit_crit': sfx_hit_crit, 'slash': sfx_slash,
    'peck': sfx_peck, 'whoosh': sfx_whoosh, 'magic_fire': sfx_magic_fire, 'magic_heal': sfx_magic_heal,
    'magic_dark': sfx_magic_dark, 'magic_ice': sfx_magic_ice, 'poison': sfx_poison, 'shield': sfx_shield,
    'buff': sfx_buff, 'debuff': sfx_debuff, 'enemy_die': sfx_enemy_die, 'chicken_ko': sfx_chicken_ko,
    'chest_open': sfx_chest_open, 'item_get': sfx_item_get, 'level_up': sfx_level_up, 'door': sfx_door,
    'memory_flash': sfx_memory_flash, 'battle_start': sfx_battle_start, 'flee': sfx_flee,
    'power_down': sfx_power_down, 'thunder': sfx_thunder, 'blood_splat': sfx_blood_splat, 'coin': sfx_coin,
    'quest': sfx_quest, 'save': sfx_save,
}
AMB = {'rain_loop': amb_rain, 'waves_loop': amb_waves, 'wind_loop': amb_wind, 'fire_loop': amb_fire,
       'night_loop': amb_night}


def seam_report(d):
    """Loop-seam check.
    1) continuity: the wrap jump |x[0]-x[-1]| compared with the largest sample step in the
       64 samples on either side of the seam (a click shows up as an outlier step).
    2) click energy: high-passed (>6 kHz) energy in a 6 ms window centred on the seam,
       relative to the 99th percentile of the same measure over the whole file played as a loop
       (the seam sits on beat 1, so it must not be louder in HF than the file's normal onsets)."""
    jump = abs(d[0] - d[-1])
    near = np.concatenate([d[-65:], d[:65]])
    steps = np.abs(np.diff(near))
    steps = np.delete(steps, 64)            # drop the seam step itself
    local = float(steps.max())
    w = ns(0.006)
    ring = np.concatenate([d[-4096:], d, d[:4096]])
    h = hp(ring, 6000, 4)[4096:-4096] if len(d) > 9000 else hp(ring, 6000, 4)
    hd = np.concatenate([h[-w:], h[:w]])
    seam_e = float(np.mean(hd ** 2))
    frames = h[:len(h) // w * w].reshape(-1, w)
    ref_e = float(np.percentile(np.mean(frames ** 2, axis=1), 99)) + 1e-12
    ok = jump <= 1.5 * local + 2e-3 and seam_e <= 1.5 * ref_e
    return jump, local, seam_e / ref_e, ok


def click_scan(d, loop):
    """Count audible discontinuities: second-difference spikes > 12x the local (25 ms) level
    and > 0.02 absolute. For loops the file is scanned as wrapped (end -> start)."""
    pad = min(2000, len(d))
    x = np.concatenate([d[-pad:], d, d[:pad]]) if loop else np.concatenate([np.zeros(400), d, np.zeros(400)])
    dd = np.abs(np.diff(x, 2))
    env = np.sqrt(np.maximum(np.convolve(dd ** 2, np.ones(801) / 801, mode='same'), 0))
    return int(np.sum((dd / (env + 1e-4) > 12) & (dd > 0.02)))


def verify():
    rows = []
    ok = True
    for name, (fn, loop) in list(MUSIC.items()) + list(MUSIC2.items()):
        rows.append(('music', name, loop))
    for name in list(SFX) + list(SFX2):
        rows.append(('sfx', name, False))
    for name in AMB:
        rows.append(('sfx', name, True))
    print('\n%-6s %-14s %8s  %-5s  %s' % ('kind', 'name', 'dur(s)', 'loop', 'checks'))
    for kind, name, loop in rows:
        path = os.path.join(MUS_DIR if kind == 'music' else SFX_DIR, name + '.wav')
        if not os.path.exists(path):
            print('%-6s %-14s MISSING' % (kind, name))
            ok = False
            continue
        p, d = read_wav(path)
        fmt_ok = p == (1, 2, SR, 'NONE')
        peak_db = 20 * np.log10(np.max(np.abs(d)) + 1e-12)
        info = 'fmt=%s peak=%.1fdB' % ('ok' if fmt_ok else 'BAD' + str(p), peak_db)
        if loop:
            jump, local, hf, seam_ok = seam_report(d)
            info += ' seam jump=%.4f (local max step %.4f) hf/p99=%.2f %s' % (
                jump, local, hf, 'OK' if seam_ok else 'CLICK?')
            ok &= seam_ok
        else:
            info += ' start=%.4f end=%.4f' % (abs(d[0]), abs(d[-1]))
        clicks = click_scan(d, loop)
        info += ' clicks=%d' % clicks
        ok &= fmt_ok and clicks == 0
        print('%-6s %-14s %8.2f  %-5s  %s' % (kind, name, len(d) / SR, 'yes' if loop else 'no', info))
    print('\nALL OK' if ok else '\nSOME CHECKS FAILED')
    return ok


def main(argv):
    os.makedirs(MUS_DIR, exist_ok=True)
    os.makedirs(SFX_DIR, exist_ok=True)
    only = set(argv)
    t0 = time.time()
    for name, (fn, loop) in MUSIC.items():
        if only and name not in only:
            continue
        t1 = time.time()
        y = fn()
        write_wav(os.path.join(MUS_DIR, name + '.wav'), y)
        print('music %-12s %6.2fs  (%.1fs)' % (name, len(y) / SR, time.time() - t1), flush=True)
    for name, fn in list(SFX.items()) + list(AMB.items()):
        if only and name not in only:
            continue
        y = fn()
        write_wav(os.path.join(SFX_DIR, name + '.wav'), y)
        print('sfx   %-12s %6.2fs' % (name, len(y) / SR), flush=True)
    # v2 items: rendered after the originals, each with its own name-seeded RNG
    for name, (fn, loop) in MUSIC2.items():
        if only and name not in only:
            continue
        t1 = time.time()
        y = with_rng(name, fn)
        write_wav(os.path.join(MUS_DIR, name + '.wav'), y)
        print('music %-12s %6.2fs  (%.1fs)' % (name, len(y) / SR, time.time() - t1), flush=True)
    for name, fn in SFX2.items():
        if only and name not in only:
            continue
        y = with_rng(name, fn)
        write_wav(os.path.join(SFX_DIR, name + '.wav'), y)
        print('sfx   %-12s %6.2fs' % (name, len(y) / SR), flush=True)
    print('total %.1fs' % (time.time() - t0))
    if not only or 'verify' in only:
        verify()


if __name__ == '__main__':
    main(sys.argv[1:])
