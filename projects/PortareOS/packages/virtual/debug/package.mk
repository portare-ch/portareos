# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="debug"
PKG_VERSION=""
PKG_LICENSE="GPL"
PKG_SITE="https://libreelec.tv"
PKG_URL=""
PKG_SECTION="virtual"
PKG_LONGDESC="What a problem on the device gets debugged with: gdb and strace"

# The base set added memtester, kmsxx, libva-utils, valgrind, and ours
# apitrace, renderdoc and nvtop on top. apitrace traces GL and the image
# renders through Vulkan; renderdoc needs a desktop client; nvtop is a
# desktop GPU monitor. gdb and strace are what a problem on the device
# gets debugged with. vblank-rate measures the panel's real refresh
# rate, which REFRESH_RATES.md's procedure for adding a mode needs and
# nothing else on the image can do. pcm-flags reads a PCM's info flags and
# period steps straight from the driver; SNDRV_PCM_INFO_BATCH decides how
# much PipeWire queues ahead and no /proc file prints it.
PKG_DEPENDS_TARGET="toolchain gdb strace vblank-rate pcm-flags"
