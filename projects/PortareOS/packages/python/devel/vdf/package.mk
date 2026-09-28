# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="vdf"
PKG_VERSION="3.4"
PKG_SHA256="fd5419f41e07a1009e5ffd027c7dcbe43d1f7e8ef453aeaa90d9d04b807de2af"
PKG_LICENSE="MIT"
PKG_SITE="https://github.com/ValvePython/vdf"
PKG_URL="https://files.pythonhosted.org/packages/source/${PKG_NAME:0:1}/${PKG_NAME}/${PKG_NAME}-${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain Python3 setuptools:host"
PKG_LONGDESC="Library for working with Valve's KeyValues (VDF) format."
PKG_TOOLCHAIN="python"

# protontricks reads Steam's config.vdf, libraryfolders.vdf and shortcuts.vdf
# through this. It vendors a copy as protontricks._vdf, but only for a patched
# binary_loads; steam.py still does a plain "import vdf" at module level, so
# the real package has to be here.
