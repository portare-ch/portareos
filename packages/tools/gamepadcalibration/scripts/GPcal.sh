#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024 ROCKNIX (https://github.com/ROCKNIX)
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

# Calibrates the sticks and triggers through rsinput's module parameters.
# Save writes /storage/.config/autostart/GPcal.sh, which the boot runner
# executes, so a calibration survives a reboot.

GPCAL_PATH="/usr/local/share/gpcal"

source /etc/profile

set_kill set "python3"

# The launcher has dropped DRM master; pyxel's SDL draws straight to it.
export SDL_VIDEODRIVER=kmsdrm

# pyxel comes from the system site-packages, not the venv the upstream
# bundle carried.
cd "$GPCAL_PATH"

# PYTHONDONTWRITEBYTECODE: the mount is read-only, so no .pyc files.
PYTHONDONTWRITEBYTECODE=1 python3 main.py
