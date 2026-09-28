# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="winetricks"
PKG_VERSION="20260125"
PKG_SHA256="2890bd9fbbade4638e58b4999a237273192df03b58516ae7b8771e09c22d2f56"
PKG_LICENSE="LGPL-2.1"
PKG_SITE="https://github.com/Winetricks/winetricks"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain cabextract p7zip curl"
PKG_LONGDESC="Script to install runtime libraries and applications into a Wine prefix."
PKG_TOOLCHAIN="manual"

# This used to arrive as a curl of the Winetricks master branch during the
# wine package's makeinstall_target - no tag, no checksum, a different script
# in every build. It is a package now so it goes through PKG_URL and
# PKG_SHA256 like everything else.
#
# cabextract and p7zip are what the verbs actually shell out to when they
# unpack a redistributable, and curl is how it fetches them. Without those
# winetricks installs nothing.

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
    cp -a ${PKG_BUILD}/src/winetricks ${INSTALL}/usr/bin
    chmod 0755 ${INSTALL}/usr/bin/winetricks
}
