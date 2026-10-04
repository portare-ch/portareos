#!/usr/bin/env python3
"""Fit a PortareOS color profile for the Retroid Pocket Nova: sRGB primaries, D65 white,
and either a gamma 2.2 or the piecewise sRGB tone curve.

Input: the 921 colorimeter readings that pippopapera measured on a Nova
(github.com/pippopapera/nova-display-calibration, docs/data/readings.csv, MIT)
and the IGC / PCC / GC tables of their Android profiles, which tell what the
panel was actually driven with for each reading.

Output: a profile for the pipeline mainline drm/msm exposes on this SoC - a
3x3 matrix (CRTC CTM, the DSPP's PCC block) followed by a 1024-entry gamma
table (CRTC GAMMA_LUT, the GC block). There is no de-gamma stage (IGC), so the
matrix works on gamma-encoded values; the fit chooses the matrix and the table
together to get as close to sRGB primaries, D65 and gamma 2.2 as that pipeline
can, judged by CIEDE2000 against the same targets their measurements use.

    python3 fit-profile.py /path/to/nova-display-calibration gamma22 > gamma22.profile
    python3 fit-profile.py /path/to/nova-display-calibration srgb    > srgb.profile

Needs numpy and scipy. Takes about a quarter of an hour.
"""
import csv, json, struct, sys
import numpy as np
from scipy.optimize import least_squares, minimize

R = sys.argv[1].rstrip('/') + '/'
TRANSFER = sys.argv[2] if len(sys.argv) > 2 else 'gamma22'
assert TRANSFER in ('gamma22', 'srgb'), TRANSFER

def eotf(v):
    """Display-referred code 0..1 -> linear light, the two targets their tools/color_math.py uses."""
    v = np.asarray(v, float)
    if TRANSFER == 'srgb':
        return np.where(v <= 0.04045, v / 12.92, ((v + 0.055) / 1.055) ** 2.4)
    return v ** 2.2
rows = [r for r in csv.DictReader(open(R + 'docs/data/readings.csv')) if r['android_brightness'] == '173']
man = json.load(open(R + 'sourceprofiles/profile-manifest.json'))['profiles']

def igc(name):
    v = struct.unpack('<771I', open(R + 'sourceprofiles/' + name, 'rb').read())
    return np.array([v[c * 257:(c + 1) * 257] for c in range(3)], float)

def gc(name):
    v = struct.unpack('<3075I', open(R + 'sourceprofiles/' + name, 'rb').read())
    return np.array([v[3 + c * 1024:3 + (c + 1) * 1024] for c in range(3)], float)

prof = {p: (igc(man[p]['igc_asset']), np.array(man[p]['surfaceflinger_matrix']).reshape(3, 3), gc(man[p]['gc_asset']))
        for p in ('gamma22', 'srgb')}

def drive(code, profile):
    """8-bit code -> what the panel was driven with, 0..1, through the Android pipeline of that profile."""
    code = np.asarray(code, float)
    if profile == 'original':
        return code / 255.0
    I, M, G = prof[profile]
    lin = np.array([I[c][int(code[c])] for c in range(3)])            # IGC: 12-bit linear
    out = np.clip(M @ lin, 0, 4095)                                     # PCC
    idx = np.clip(np.round(out / 4095 * 1023), 0, 1023).astype(int)     # GC: 10-bit index
    return np.array([G[c][idx[c]] for c in range(3)]) / 1023.0

D, XYZ, TAG = [], [], []
for r in rows:
    code = (int(r['R']), int(r['G']), int(r['B']))
    D.append(drive(code, r['profile'])); XYZ.append((float(r['X']), float(r['Y']), float(r['Z']))); TAG.append((r['dataset'], r['profile'], r['patch'], code))
D, XYZ = np.array(D), np.array(XYZ); n = len(D)

# ---- 1. a model of the panel: XYZ = P f(drive) / (1 + k L), an additive display with one tone curve
#         and a brightness limiter that pulls white down relative to the primaries (measured: 7 %)
knots = np.array([0, .02, .05, .1, .15, .2, .3, .4, .5, .6, .7, .8, .9, .95, 1.0])
def f_of(fp, d):
    inc = np.log1p(np.exp(fp)); cum = np.concatenate([[0], np.cumsum(inc)]); cum /= cum[-1]
    return np.interp(d, knots, cum)
def model(p, d):
    P = p[:9].reshape(3, 3); k = p[9]
    F = np.stack([f_of(p[10:], d[:, c]) for c in range(3)], 1)
    L = (F * P[1]).sum(1) / P[1].sum()
    return (F @ P.T) / (1 + k * L)[:, None]
prim = {t[2]: XYZ[i] for i, t in enumerate(TAG) if t[1] == 'original' and t[2] in ('red-floor-0', 'green-floor-0', 'blue-floor-0')}
P0 = np.column_stack([prim['red-floor-0'], prim['green-floor-0'], prim['blue-floor-0']])
init = np.concatenate([P0.ravel(), [0.05], np.log(np.expm1(np.diff(knots ** 2.2) + 1e-6) + 1e-9)])
w = 1.0 / (XYZ[:, 1:2] + 3.0)
fit = least_squares(lambda p: ((model(p, D) - XYZ) * w).ravel(), init, max_nfev=6000)
p = fit.x
err = np.abs(model(p, D) - XYZ).sum(1) / (XYZ.sum(1) + 1)
print(f"# panel model: {n} readings, median error {np.median(err) * 100:.2f} %, 90th percentile {np.percentile(err, 90) * 100:.2f} %", file=sys.stderr)

# ---- 2. color science, as in their tools/color_math.py (eotf above)
def srgb_matrix(whiteY):
    u = lambda x, y: np.array([x / y, 1, (1 - x - y) / y])
    prim = np.column_stack([u(.64, .33), u(.30, .60), u(.15, .06)]); wu = u(.3127, .3290)
    s = np.linalg.solve(prim, wu); return prim * s * whiteY, wu * whiteY
def lab(xyz, white):
    r = xyz / white; e = 216 / 24389; kk = 24389 / 27
    f = np.where(r > e, np.cbrt(np.maximum(r, 0)), (kk * r + 16) / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)
def de00(l1, l2):
    L1, a1, b1 = l1[..., 0], l1[..., 1], l1[..., 2]; L2, a2, b2 = l2[..., 0], l2[..., 1], l2[..., 2]
    C1 = np.hypot(a1, b1); C2 = np.hypot(a2, b2); Cb = (C1 + C2) / 2; G = .5 * (1 - np.sqrt(Cb ** 7 / (Cb ** 7 + 25. ** 7)))
    ap1 = (1 + G) * a1; ap2 = (1 + G) * a2; Cp1 = np.hypot(ap1, b1); Cp2 = np.hypot(ap2, b2)
    hp1 = np.degrees(np.arctan2(b1, ap1)) % 360; hp2 = np.degrees(np.arctan2(b2, ap2)) % 360
    hp1 = np.where((ap1 == 0) & (b1 == 0), 0, hp1); hp2 = np.where((ap2 == 0) & (b2 == 0), 0, hp2)
    dL = L2 - L1; dC = Cp2 - Cp1; raw = hp2 - hp1
    dh = np.where(np.abs(raw) <= 180, raw, np.where(raw > 180, raw - 360, raw + 360)); dh = np.where(Cp1 * Cp2 == 0, 0, dh)
    dH = 2 * np.sqrt(Cp1 * Cp2) * np.sin(np.radians(dh / 2)); Lb = (L1 + L2) / 2; Cbp = (Cp1 + Cp2) / 2
    hs = hp1 + hp2; hb = np.where(Cp1 * Cp2 == 0, hs, np.where(np.abs(hp1 - hp2) <= 180, hs / 2, np.where(hs < 360, (hs + 360) / 2, (hs - 360) / 2)))
    T = 1 - .17 * np.cos(np.radians(hb - 30)) + .24 * np.cos(np.radians(2 * hb)) + .32 * np.cos(np.radians(3 * hb + 6)) - .20 * np.cos(np.radians(4 * hb - 63))
    th = 30 * np.exp(-((hb - 275) / 25) ** 2); Rc = 2 * np.sqrt(Cbp ** 7 / (Cbp ** 7 + 25. ** 7))
    Sl = 1 + .015 * (Lb - 50) ** 2 / np.sqrt(20 + (Lb - 50) ** 2); Sc = 1 + .045 * Cbp; Sh = 1 + .015 * Cbp * T; Rt = -np.sin(np.radians(2 * th)) * Rc
    return np.sqrt(np.maximum(0, (dL / Sl) ** 2 + (dC / Sc) ** 2 + (dH / Sh) ** 2 + Rt * (dC / Sc) * (dH / Sh)))
def errors(codes, drv, drv_white):
    """CIEDE2000 of the model's prediction against sRGB / D65 / gamma 2.2, normalised to the pipeline's own white."""
    pr = model(p, drv); wY = model(p, drv_white)[0][1]
    Mx, wh = srgb_matrix(wY); tgt = eotf(codes / 255.0) @ Mx.T
    return de00(lab(pr, wh), lab(tgt, wh))

codes_b = np.array([t[3] for t in TAG if t[1] == 'original' and t[2] not in ('white-start', 'white-end', 'black')], float)
codes_60 = np.array([t[3] for t in TAG if t[0] == 'native-gamma22-brightness-20260913/reference-173' and t[2] not in ('white-start', 'white-end', 'black', 'gray-4')], float)
g = np.linspace(0, 255, 6); codes_grid = np.array([[a, b, c] for a in g for b in g for c in g if not (a == b == c == 0)], float)
grays = np.array([[v, v, v] for v in (8, 16, 24, 32, 48, 64, 96, 128, 160, 192, 224, 240, 248, 255)], float)
sets = ((codes_b, '36 gamut-boundary colors'), (codes_60, '56 reference patches'), (codes_grid, '6x6x6 grid'), (grays, 'gray ramp'))

# ---- 3. our pipeline: drive = G_c(clip(M v)), a matrix on encoded values then one table per channel
gk = np.array([0, .004, .008, .016, .024, .032, .048, .064, .09, .125, .16, .2, .25, .3, .4, .5, .6, .7, .8, .9, .95, 1.0]); NK = len(gk)
def G_of(gp, x):
    inc = np.log1p(np.exp(gp[1:])); cum = np.concatenate([[0], np.cumsum(inc)]); cum = cum / cum[-1] * (1 / (1 + np.exp(-gp[0])))
    return np.interp(x, gk, cum)
def our_drive(q, v):
    M = q[:9].reshape(3, 3); u = np.clip(v @ M.T, 0, 1)
    return np.stack([G_of(q[9 + c * NK:9 + (c + 1) * NK], u[:, c]) for c in range(3)], 1)
train = np.vstack([codes_b, codes_60, codes_grid, grays]) / 255.0
wts = np.concatenate([np.ones(len(codes_b)), np.ones(len(codes_60)), np.ones(len(codes_grid)), np.full(len(grays), 8.0)])
def obj(q, weighted):
    e = errors(train * 255, our_drive(q, train), our_drive(q, np.array([[1., 1, 1]])))
    return ((e * wts).sum() / wts.sum() + 0.05 * e.max()) if weighted else e.mean()
rng = np.random.default_rng(7); best = None
base_g = np.concatenate([[4.0], np.log(np.expm1(np.diff(gk) + 1e-9))])
for trial in range(8):
    M0 = np.eye(3) * rng.uniform(0.75, 0.95) + rng.uniform(0, 0.12, (3, 3)) * (1 - np.eye(3))
    q0 = np.concatenate([M0.ravel(), np.tile(base_g, 3)]) + rng.normal(0, 0.05, 9 + 3 * NK)
    res = minimize(obj, q0, args=(False,), method='L-BFGS-B', options={'maxiter': 4000, 'maxfun': 400000})
    if best is None or res.fun < best.fun: best = res
q = best.x
q = minimize(obj, q, args=(True,), method='L-BFGS-B', options={'maxiter': 4000, 'maxfun': 400000}).x
q = minimize(obj, q, args=(True,), method='Powell', options={'maxiter': 30000, 'maxfev': 300000, 'xtol': 1e-5, 'ftol': 1e-7}).x
M = q[:9].reshape(3, 3); white = our_drive(q, np.array([[1., 1, 1]]))

# ---- 4. the profile, with what it is expected to do
print("# PortareOS color profile for the Retroid Pocket Nova: sRGB primaries, D65 white, %s." % ("gamma 2.2" if TRANSFER == "gamma22" else "the piecewise sRGB tone curve"))
print("#")
print("# Fitted by fit-profile.py %s to the colorimeter readings pippopapera published for this" % TRANSFER)
print("# panel (github.com/pippopapera/nova-display-calibration, MIT, Copyright (c) 2026")
print("# pippopapera), for the two-stage pipeline mainline drm/msm exposes: a 3x3 matrix (CTM) on")
print("# gamma-encoded values, then a 1024-entry gamma table (GAMMA_LUT). Predicted CIEDE2000")
print("# against this target, normalised to each pipeline's white (model, not measured):")
print("#")
print("#   %-28s %10s %10s" % ("", "stock", "this file"))
for cs, lbl in sets:
    e0 = errors(cs, cs / 255.0, np.array([[1., 1, 1]])); e1 = errors(cs, our_drive(q, cs / 255.0), white)
    print("#   %-28s %5.2f mean %5.2f mean   (max %.2f / %.2f)" % (lbl, e0.mean(), e1.mean(), e0.max(), e1.max()))
print("#")
print("# White is driven at %.3f %.3f %.3f: %.1f %% of the stock luminance." % (white[0][0], white[0][1], white[0][2], 100 * model(p, white)[0][1] / model(p, np.array([[1., 1, 1]]))[0][1]))
print("#")
print("# ctm: out = M x in, row-major. lut: 1024 lines of R G B, 0..65535, indexed by the matrix's output.")
print("ctm " + " ".join("%.6f" % v for v in M.ravel()))
x = np.linspace(0, 1, 1024)
tab = np.stack([G_of(q[9 + c * NK:9 + (c + 1) * NK], x) for c in range(3)], 1)
for row in np.clip(np.round(tab * 65535), 0, 65535).astype(int):
    print("lut %d %d %d" % tuple(row))
