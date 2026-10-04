# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="libdecor"
PKG_VERSION="0.2.5"
PKG_SHA256="1d0e9b3d2711dfc4edc21db3c87752a76cd62079cfad447699acda5d49b23536"
PKG_LICENSE="MIT"
PKG_SITE="https://gitlab.freedesktop.org/libdecor/libdecor"
PKG_URL="${PKG_SITE}/-/archive/${PKG_VERSION}/${PKG_NAME}-${PKG_VERSION}.tar.bz2"
# Without the GTK plugin: it draws decorations for Wayland windows, and there
# is no compositor here to put a window in. The cairo plugin is always built
# and needs pangocairo.
PKG_DEPENDS_TARGET="toolchain wayland wayland-protocols cairo pango"
PKG_LONGDESC="libdecor - A client-side decorations library for Wayland clients"
PKG_TOOLCHAIN="meson"

# dbus would fetch the cursor size from a desktop settings portal; there is none.
PKG_MESON_OPTS_TARGET="-Dgtk=disabled -Ddbus=disabled -Ddemo=false"
