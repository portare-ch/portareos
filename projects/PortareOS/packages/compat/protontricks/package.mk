# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="protontricks"
PKG_VERSION="1.14.1"
PKG_SHA256="db242c0249948d3595dd33ffbd0f6850461fbd43665aff40e11ec6ea94e11bc4"
PKG_LICENSE="GPL-3.0-or-later"
PKG_SITE="https://github.com/Matoking/protontricks"
PKG_URL="https://files.pythonhosted.org/packages/source/${PKG_NAME:0:1}/${PKG_NAME}/${PKG_NAME}-${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain Python3 setuptools:host setuptools-scm:host vdf Pillow winetricks"
PKG_LONGDESC="Wrapper for running Winetricks commands against Proton prefixes."
PKG_TOOLCHAIN="python"

# Steam games run under Proton, not under a plain wine prefix, so winetricks
# on its own cannot find them: the prefix lives under
# steamapps/compatdata/<appid>/pfx and needs Proton's own runtime on the way
# in. protontricks resolves the appid, sets that up and calls winetricks.
#
# Pillow is not optional even for the command line. protontricks/__init__.py
# does "from .gui import *", and gui.py imports PIL at module level, so the
# import fails without it however the tool is invoked.
#
# setuptools-scm is a setup_requires. The sdist ships a generated _version.py,
# but scm still runs, and with no git metadata in an unpacked tarball it has
# nothing to derive a version from - hence the pretend version below, the same
# way packages/python/devel/pluggy does it.

pre_configure_target() {
  export SETUPTOOLS_SCM_PRETEND_VERSION=${PKG_VERSION}
}
