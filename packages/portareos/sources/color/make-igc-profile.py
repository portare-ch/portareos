#!/usr/bin/env python3
"""Turn pippopapera's measured three-stage profile into a PortareOS color profile
with a de-gamma table, for a kernel that drives the DSPP's IGC (DEGAMMA_LUT).

    python3 make-igc-profile.py /path/to/nova-display-calibration gamma22 > gamma22-igc.profile

degamma: 256 lines R G B, 16-bit (the IGC's 12-bit values << 4)
ctm:     their PCC matrix, applied to linear light
lut:     1024 lines R G B, 16-bit (the GC's 10-bit values << 6)
"""
import json, struct, sys
R = sys.argv[1].rstrip('/') + '/'; P = sys.argv[2]
man = json.load(open(R + 'sourceprofiles/profile-manifest.json'))['profiles'][P]
igc = struct.unpack('<771I', open(R + 'sourceprofiles/' + man['igc_asset'], 'rb').read())
gc = struct.unpack('<3075I', open(R + 'sourceprofiles/' + man['gc_asset'], 'rb').read())
assert gc[:3] == (0, 1024, 0)
I = [igc[c * 257:(c + 1) * 257] for c in range(3)]   # R, G, B, 257 entries of 12 bits
G = [gc[3 + c * 1024:3 + (c + 1) * 1024] for c in range(3)]   # R, G, B, 1024 entries of 10 bits
M = man['surfaceflinger_matrix']
print("# PortareOS color profile for the Retroid Pocket Nova: sRGB primaries, D65 white, %s." % ("gamma 2.2" if P == "gamma22" else "the piecewise sRGB tone curve"))
print("# The three-stage version: pippopapera's measured IGC, PCC and GC tables as they are")
print("# (github.com/pippopapera/nova-display-calibration, MIT, Copyright (c) 2026 pippopapera),")
print("# for a kernel whose CRTC has a DEGAMMA_LUT - the IGC driven through the LUTDMA. Their")
print("# measurement, gamma 2.2: 36 gamut-boundary colors at a mean dE00 of 0.63, from 5.8 stock;")
print("# sRGB measured comparably against its own curve, with too little data to rank the two.")
print("#")
print("# degamma: 256 lines R G B, 0..65535 (12-bit IGC values << 4). ctm: linear-light matrix,")
print("# out = M x in, row-major. lut: 1024 lines R G B, 0..65535 (10-bit GC values << 6).")
for i in range(256):
    print("degamma %d %d %d" % (I[0][i] << 4, I[1][i] << 4, I[2][i] << 4))
print("ctm " + " ".join("%.9f" % v for v in M))
for i in range(1024):
    print("lut %d %d %d" % (G[0][i] << 6, G[1][i] << 6, G[2][i] << 6))
