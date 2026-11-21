# Platzhalter-Geräusche (werden später durch ElevenLabs-Sounds ersetzt)
import numpy as np, wave, os
SR = 44100
OUT = os.path.join(os.path.dirname(__file__), '..', 'sfx')
rng = np.random.default_rng(7)

def save(name, x, gain=0.9):
    x = np.asarray(x, float)
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    d = (np.clip(x, -1, 1) * 32767).astype('<i2')
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(d.tobytes())

def t(sec): return np.arange(int(SR * sec)) / SR
def noise(sec): return rng.standard_normal(int(SR * sec))
def lp(x, a):
    y = np.zeros_like(x); s = 0.0
    for i, v in enumerate(x): s += a * (v - s); y[i] = s
    return y
def hp(x, a): return x - lp(x, a)
def env(sec, att, dec):
    tt = t(sec); return np.minimum(1, tt / max(att, 1e-4)) * np.exp(-tt / dec)

# eigener Schuss: harter Knall + tiefer Wumms + kurzer Hall
s = 0.9; tt = t(s)
crack = hp(noise(s), 0.5) * env(s, 0.0005, 0.012)
body = lp(noise(s), 0.08) * env(s, 0.001, 0.06) * 3
thump = np.sin(2 * np.pi * (90 * np.exp(-tt * 18)) * tt) * env(s, 0.001, 0.08) * 1.2
tail = lp(noise(s), 0.03) * env(s, 0.05, 0.25) * 0.6
save('shot_player', crack + body + thump + tail)

# Gegner-Schuss: entfernter, dumpfer, mit Echo
s = 1.2; x = lp(noise(s), 0.15) * env(s, 0.001, 0.03) * 2 + lp(noise(s), 0.04) * env(s, 0.002, 0.12)
echo = np.zeros_like(x); d = int(0.18 * SR); echo[d:] = x[:-d] * 0.35
save('shot_enemy', x + echo, 0.7)

# Einschlag in Backstein + Querschläger
s = 0.9; tt = t(s)
hit = hp(noise(s), 0.3) * env(s, 0.0003, 0.02) + lp(noise(s), 0.2) * env(s, 0.001, 0.05)
crumble = np.zeros(len(tt))
for k in range(14):
    p = int(rng.uniform(0.02, 0.35) * SR); n = int(0.012 * SR)
    crumble[p:p + n] += hp(noise(n / SR), 0.4) * np.exp(-np.arange(n) / (0.003 * SR)) * rng.uniform(0.1, 0.4)
f = 3200 * np.exp(-tt * 2.2) + 900
ric = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(s, 0.02, 0.25) * 0.35 * (tt > 0.03)
save('impact_brick', hit + crumble + ric, 0.8)
save('impact_brick2', hit * 1.2 + crumble * 1.4, 0.8)

# Einschlag in Metall
s = 1.0; tt = t(s)
ring = sum(np.sin(2 * np.pi * fr * tt) * np.exp(-tt * dd) for fr, dd in [(780, 7), (1430, 9), (2210, 12), (3150, 15)])
save('impact_metal', ring * 0.4 + hp(noise(s), 0.3) * env(s, 0.0003, 0.01), 0.8)

# Treffer in Pappe
s = 0.35
save('impact_card', lp(noise(s), 0.25) * env(s, 0.0005, 0.03) + hp(noise(s), 0.6) * env(s, 0.0003, 0.008), 0.8)

def click(sec, tone, dec, nz=0.6):
    tt = t(sec)
    return (np.sin(2 * np.pi * tone * tt) * 0.5 + hp(noise(sec), 0.5) * nz) * env(sec, 0.0002, dec)

# Pappaufsteller klappt hoch: Holz-Klack mit Federn
s = 0.5; tt = t(s)
clack = click(s, 520, 0.012) + lp(noise(s), 0.3) * env(s, 0.0003, 0.01)
spring = np.sin(2 * np.pi * 180 * tt) * np.exp(-tt * 9) * np.sin(2 * np.pi * 14 * tt) * 0.25
save('target_up', clack + spring, 0.8)

# Pappaufsteller kippt um
s = 0.6; x = np.zeros(int(SR * s))
whoosh = lp(noise(0.2), 0.05) * np.sin(np.linspace(0, np.pi, int(SR * 0.2))) * 0.4
x[:len(whoosh)] += whoosh
p = int(0.2 * SR); slap = lp(noise(0.3), 0.35) * env(0.3, 0.0003, 0.03) * 1.5
x[p:p + len(slap)] += slap
save('target_down', x, 0.8)

# Nachladen: Magazin raus, rein, Schlitten
s = 0.9; x = np.zeros(int(SR * s))
for at, tone, dec, g in [(0.02, 900, 0.01, 0.6), (0.38, 600, 0.015, 1.0), (0.42, 1300, 0.006, 0.5), (0.66, 700, 0.02, 0.9), (0.72, 1800, 0.008, 0.7)]:
    c = click(0.12, tone, dec) * g; p = int(at * SR); x[p:p + len(c)] += c
save('reload', x, 0.7)

# leeres Magazin
s = 0.4; x = np.zeros(int(SR * s))
for at in (0.0, 0.18):
    c = click(0.08, 1500, 0.005, 0.9); p = int(at * SR); x[p:p + len(c)] += c
save('empty', x, 0.6)

# Treffer am Spieler: dumpfer Schlag
s = 0.4; tt = t(s)
save('player_hit', np.sin(2 * np.pi * 70 * tt) * env(s, 0.002, 0.08) + lp(noise(s), 0.1) * env(s, 0.001, 0.04), 0.8)

# Abend-Atmosphäre: Wind, ferner Verkehr (nahtlos, 8 s)
s = 8.0; n = int(SR * s)
wind = lp(lp(noise(s), 0.004), 0.01)
traffic = lp(noise(s), 0.02) * (0.6 + 0.4 * np.sin(2 * np.pi * t(s) / s))
x = wind * 6 + traffic * 0.8
fade = int(SR * 0.5); x[-fade:] = x[-fade:] * np.linspace(1, 0, fade) + x[:fade] * np.linspace(0, 1, fade)
x = x[:-fade]
save('ambience', x, 0.35)
print('ok')
