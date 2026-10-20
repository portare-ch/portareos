# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# Copyright (C) 2018-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="mesa"
PKG_VERSION="26.3.0-rc1"
PKG_SHA256="63327d58a51d189c1d1600746c505609bba5c495123b4e51de4e0c038b745542"
PKG_LICENSE="OSS"
PKG_SITE="http://www.mesa3d.org/"
# Release candidates come from mesa's own archive. The gitlab tag a
# candidate is cut from can go away again - mesa-26.3.0-rc1 did on
# 2026-10-20 and took the nightly with it - while archive.mesa3d.org
# keeps every tarball it has published.
PKG_URL="https://archive.mesa3d.org/mesa-${PKG_VERSION}.tar.xz"
PKG_DEPENDS_TARGET="toolchain expat libdrm Mako:host pyyaml:host"
PKG_LONGDESC="Mesa is a 3-D graphics library with an API."
PKG_PATCH_DIRS+=" ${DEVICE}"

# The shader caches - Mesa's own, and every emulator's pipeline cache
# checked against the driver's UUID - are keyed on the driver's build-id.
# freedreno's isa and register generators walk Python sets, so a random
# hash seed reorders isa/encode.h and the driver comes out different from
# the same source: every nightly threw every cache away (#623).
export PYTHONHASHSEED=0

get_graphicdrivers

PKG_MESON_OPTS_TARGET="-Dc_link_args=-lgcc \
                       -Dcpp_link_args=-lgcc \
                       -Dgallium-drivers=${GALLIUM_DRIVERS// /,} \
                       -Dgallium-extra-hud=false \
                       -Dgallium-rusticl=false \
                       -Dshader-cache=enabled \
                       -Dopengl=true \
                       -Dgbm=enabled \
                       -Degl=enabled \
                       -Dvalgrind=disabled \
                       -Dlibunwind=disabled \
                       -Dlmsensors=disabled \
                       -Dbuild-tests=false \
                       -Dmicrosoft-clc=disabled"

if [ "${DISPLAYSERVER}" = "x11" ]; then
  PKG_DEPENDS_TARGET+=" xorgproto libXext libXdamage libXfixes libXxf86vm libxcb libX11 libxshmfence libXrandr libglvnd glfw"
  export X11_INCLUDES=
  PKG_MESON_OPTS_TARGET+="	-Dplatforms=x11 \
				-Dglx=dri \
				-Dglvnd=enabled"
elif [ "${DISPLAYSERVER}" = "wl" ]; then
  PKG_DEPENDS_TARGET+=" wayland wayland-protocols libglvnd glfw"
  PKG_MESON_OPTS_TARGET+=" 	-Dplatforms=wayland,x11 \
				-Dglx=dri \
				-Dglvnd=enabled"
  PKG_DEPENDS_TARGET+=" xorgproto libXext libXdamage libXfixes libXxf86vm libxcb libX11 libxshmfence libXrandr libglvnd"
  export X11_INCLUDES=
else
  PKG_MESON_OPTS_TARGET+="	-Dplatforms="" \
				-Dglx=disabled \
				-Dglvnd=disabled"
fi

if [ "${LLVM_SUPPORT}" = "yes" ]; then
  PKG_DEPENDS_TARGET+=" elfutils llvm"
  PKG_MESON_OPTS_TARGET+=" -Dllvm=enabled"
else
  PKG_MESON_OPTS_TARGET+=" -Dllvm=disabled"
fi

# Gallium VA-API is for AMD; the libva package is gone with the x86 drivers.
PKG_MESON_OPTS_TARGET+=" -Dgallium-va=disabled"

if [ "${OPENGLES_SUPPORT}" = "yes" ]; then
  PKG_MESON_OPTS_TARGET+=" -Dgles1=enabled -Dgles2=enabled"
else
  PKG_MESON_OPTS_TARGET+=" -Dgles1=disabled -Dgles2=disabled"
fi

if [ "${VULKAN_SUPPORT}" = "yes" ]; then
  PKG_DEPENDS_TARGET+=" ${VULKAN} vulkan-tools"
  PKG_MESON_OPTS_TARGET+=" -Dvulkan-drivers=${VULKAN_DRIVERS_MESA// /,}"
else
  PKG_MESON_OPTS_TARGET+=" -Dvulkan-drivers="
fi
