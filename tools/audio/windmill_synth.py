import numpy as np
from scipy.io import wavfile
import os, sys

SR = 44100
OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(42)


def band_noise(n, lo, hi, tilt=0.0):
    # FFT-filtered noise, circular by construction so it loops with no seam.
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    edge = lambda x, c, w: 0.5 * (1 + np.tanh((x - c) / w))
    g = edge(f, lo, lo * 0.3 + 1) * (1 - edge(f, hi, hi * 0.3 + 1))
    g *= (np.maximum(f, 20) / 1000.0) ** tilt
    out = np.fft.irfft(spec * g, n)
    return out / (np.std(out) + 1e-12)


def circ_add(buf, sig, pos, loop):
    # Adds sig at pos; wraps around the end when building a loop.
    idx = np.arange(len(sig)) + pos
    if loop:
        np.add.at(buf, idx % len(buf), sig)
    else:
        m = (idx >= 0) & (idx < len(buf))
        buf[idx[m]] += sig[m]


def metal_hit(dur, partials, decay, amp):
    t = np.arange(int(dur * SR)) / SR
    s = np.zeros_like(t)
    for i, (fr, a) in enumerate(partials):
        fr *= 1 + rng.uniform(-0.02, 0.02)
        s += a * np.sin(2 * np.pi * fr * t + rng.uniform(0, 6.28)) * np.exp(-t / (decay / (1 + 0.4 * i)))
    click = rng.standard_normal(len(t)) * np.exp(-t / 0.004)
    return amp * (s + 0.5 * click)


def thud(dur, f0, amp):
    t = np.arange(int(dur * SR)) / SR
    return amp * np.sin(2 * np.pi * f0 * t * (1 - 0.3 * t)) * np.exp(-t / 0.05)


def resonator_squeak(rate_curve, f_res, amp, loop=False):
    # Stick-slip creak: an impulse train at a wobbling rate rung through metal resonances.
    n = len(rate_curve)
    ph = np.cumsum(rate_curve) / SR
    imp = np.zeros(n)
    hits = np.nonzero(np.diff(np.floor(ph)) > 0)[0]
    imp[hits] = rng.uniform(0.6, 1.0, len(hits))
    t = np.arange(int(0.03 * SR)) / SR
    ker = sum(np.sin(2 * np.pi * fr * t) * np.exp(-t / 0.008) for fr in f_res)
    if loop:
        # Circular convolution so ringing at the end wraps into the start.
        return amp * np.fft.irfft(np.fft.rfft(imp) * np.fft.rfft(ker, n), n)
    return amp * np.convolve(imp, ker)[:n]


def smooth(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


# ---------------- Old farm water-pump windmill ----------------
OLD_ROT = 2.0       # wheel turns per second at full speed
OLD_BLADES = 18
OLD_GEAR = 1 / 3.3333333  # back-geared pump stroke ratio


def old_windmill(rate, loop):
    # rate is the wheel speed (0..1 of full) per sample.
    n = len(rate)
    t = np.arange(n) / SR
    rot_ph = np.cumsum(rate * OLD_ROT) / SR
    stroke_ph = rot_ph * OLD_GEAR
    out = np.zeros(n)

    # Air through the sail wheel: soft noise fluttering at blade-pass and wheel rate.
    blade = 0.75 + 0.25 * np.cos(2 * np.pi * rot_ph * OLD_BLADES)
    wobble = 0.8 + 0.2 * np.cos(2 * np.pi * rot_ph)
    air = band_noise(n, 180, 1400, tilt=-0.6)
    out += 0.16 * air * blade * wobble * rate ** 1.5

    # Background wind with slow gusting.
    gust = 0.8 + 0.2 * np.sin(2 * np.pi * 0.1 * t) + 0.1 * np.sin(2 * np.pi * 0.3 * t + 1)
    out += 0.07 * band_noise(n, 60, 900, tilt=-1.0) * gust

    # Gearbox chatter at tooth-mesh rate.
    mesh = np.maximum(0, np.cos(2 * np.pi * rot_ph * 12)) ** 8
    out += 0.05 * band_noise(n, 1500, 6000) * mesh * rate

    # Wheel shaft creak once per turn, a dry wooden-metal groan.
    groan_env = np.exp(-((np.mod(rot_ph + 0.3, 1.0) - 0.5) ** 2) / 0.01) * rate
    groan_rate = 55 + 25 * np.sin(2 * np.pi * rot_ph * 0.5) + 6 * np.sin(2 * np.pi * rot_ph * 3.5)
    out += resonator_squeak(groan_rate, [420, 980, 1650], 0.09, loop) * groan_env

    # Pump rod squeak on each upstroke, rising in pitch.
    sp = np.mod(stroke_ph, 1.0)
    up_env = np.sin(np.pi * np.clip(sp / 0.5, 0, 1)) ** 2 * (sp < 0.5) * rate
    squeak_rate = 140 + 160 * sp + 30 * np.sin(2 * np.pi * stroke_ph * 3)
    out += resonator_squeak(squeak_rate, [1150, 2380, 3700], 0.07, loop) * up_env

    # Clank at top and bottom of each stroke.
    crossings = np.nonzero(np.diff(np.floor(stroke_ph * 2)) > 0)[0]
    for c in crossings:
        top = int(np.floor(stroke_ph[c + 1] * 2)) % 2 == 1
        v = rate[c] ** 1.2
        a = (0.5 if top else 0.75) * v
        hit = metal_hit(0.6, [(510, 1), (1340, 0.6), (2230, 0.4), (3510, 0.25)], 0.12, a)
        hit[: int(0.1 * SR)] += thud(0.1, 85 if not top else 110, 0.6 * a)[: int(0.1 * SR)]
        circ_add(out, hit, c + 1, loop)
    return out


# ---------------- Modern small wind turbine ----------------
MOD_ROT = 5.0       # rotor turns per second (300 rpm)
MOD_BLADES = 3


def modern_turbine(rate, loop):
    n = len(rate)
    t = np.arange(n) / SR
    rot_ph = np.cumsum(rate * MOD_ROT) / SR
    out = np.zeros(n)

    # Blade whoosh, peaking as each blade passes the tower.
    bp = np.mod(rot_ph * MOD_BLADES, 1.0)
    pulse = np.exp(-((bp - 0.5) ** 2) / 0.02)
    whoosh = band_noise(n, 350, 3200, tilt=-0.4)
    whoosh_lo = band_noise(n, 120, 600, tilt=-0.8)
    out += (0.20 * whoosh * (0.35 + 0.65 * pulse) + 0.10 * whoosh_lo * (0.5 + 0.5 * pulse)) * rate ** 2

    # Generator hum and electrical whine, pitched by rotor speed.
    hum_ph = np.cumsum(rate * 120.0) / SR
    whine_ph = np.cumsum(rate * 840.0) / SR
    hum = (np.sin(2 * np.pi * hum_ph) + 0.5 * np.sin(4 * np.pi * hum_ph) + 0.25 * np.sin(6 * np.pi * hum_ph))
    whine = np.sin(2 * np.pi * whine_ph + 0.3 * np.sin(2 * np.pi * rot_ph))
    out += (0.06 * hum + 0.022 * whine) * rate ** 1.5

    # Bearing hiss and nacelle rumble.
    out += 0.025 * band_noise(n, 3000, 9000) * rate
    out += 0.06 * band_noise(n, 30, 140) * (0.7 + 0.3 * np.cos(2 * np.pi * rot_ph)) * rate

    # Background wind with slow gusting.
    gust = 0.8 + 0.2 * np.sin(2 * np.pi * 0.125 * t) + 0.1 * np.sin(2 * np.pi * 0.375 * t + 2)
    out += 0.06 * band_noise(n, 60, 900, tilt=-1.0) * gust
    return out


def brake_clunk(amp):
    s = metal_hit(0.35, [(300, 1), (760, 0.5), (1900, 0.3)], 0.06, amp)
    s[: int(0.12 * SR)] += thud(0.12, 70, amp)[: int(0.12 * SR)]
    return s


# ---------------- Rendering ----------------
def fade(x, fin=0.0, fout=0.0):
    x = x.copy()
    if fin:
        k = int(fin * SR); x[:k] *= np.linspace(0, 1, k)
    if fout:
        k = int(fout * SR); x[-k:] *= np.linspace(1, 0, k)
    return x


def write(name, x, peak_db=-3.0):
    x = x / np.max(np.abs(x)) * 10 ** (peak_db / 20)
    wavfile.write(os.path.join(OUT, name + ".wav"), SR, (x * 32767).astype(np.int16))
    return x


def secs(s):
    return np.ones(int(s * SR))


results = {}

# Old windmill: 10 s loop = 20 wheel turns, 6 pump strokes, all cycles whole.
loop = old_windmill(secs(10.0), True)
g = 1 / np.max(np.abs(loop))
# Rotate the seam off the clank so the loop point sits in a quiet moment.
results["DazedWindmillOld_Loop"] = np.roll(loop, -int(0.4 * SR)) * g
st = np.linspace(0, 1, int(6 * SR))
results["DazedWindmillOld_Start"] = fade(old_windmill(smooth(st) * 0.999 + 0.001, False) * g, 0.4)
sp = 1 - np.linspace(0, 1, int(7 * SR))
results["DazedWindmillOld_Stop"] = fade(old_windmill(smooth(sp) ** 1.3 * 0.999 + 0.001, False) * g, 0, 1.2)

# Modern turbine: 8 s loop = 40 rotor turns, all cycles whole.
loop = modern_turbine(secs(8.0), True)
g = 1 / np.max(np.abs(loop))
results["DazedWindmillModern_Loop"] = loop * g
st = np.linspace(0, 1, int(5 * SR))
s = modern_turbine(smooth(np.clip((st - 0.06) / 0.94, 0, 1)) * 0.999 + 0.001, False) * g
circ_add(s, brake_clunk(0.55), int(0.05 * SR), False)
results["DazedWindmillModern_Start"] = fade(s, 0.3)
sp = np.linspace(0, 1, int(7 * SR))
s = modern_turbine((1 - smooth(sp / 0.85)) ** 1.5 * 0.999 + 0.001, False) * g
circ_add(s, brake_clunk(0.5), int(0.15 * SR), False)
results["DazedWindmillModern_Stop"] = fade(s, 0, 1.0)

# One gain per windmill so start, loop and stop sit at matching levels.
for fam in ["Old", "Modern"]:
    keys = [k for k in results if fam in k]
    peak = max(np.max(np.abs(results[k])) for k in keys)
    for k in keys:
        results[k] = results[k] / peak * 10 ** (-3 / 20)
        wavfile.write(os.path.join(OUT, k + ".wav"), SR, (results[k] * 32767).astype(np.int16))
        print(k, f"{len(results[k])/SR:.1f}s")

# Seam check: jump across the loop point vs typical sample-to-sample change.
for k in ["DazedWindmillOld_Loop", "DazedWindmillModern_Loop"]:
    v = results[k]
    print(k, "seam jump", abs(v[0] - v[-1]).round(4), "typical", np.median(np.abs(np.diff(v))).round(4))
