# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# Copyright (C) 2018-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="mesa"
# 26.3.0-devel: main at the commit ARMSX2's Turnip (axfl2) is built on, so
# its a7xx feedback-loop flush (mesa-009) sits on the base it was measured
# on. Move to 26.3.0-rc1 once it is tagged.
PKG_VERSION="e3a986f0167aa7d1c5cfd62a63362c65f5339373"
PKG_SHA256="f7e82f46c257d499b1ecfe36d4126189c2e9a2f73364c99b10ad4f69ba32241b"
PKG_LICENSE="OSS"
PKG_SITE="http://www.mesa3d.org/"
PKG_URL="https://gitlab.freedesktop.org/mesa/mesa/-/archive/${PKG_VERSION}/mesa-${PKG_VERSION}.tar.gz"
PKG_DEPENDS_HOST="toolchain:host expat:host libclc:host libdrm:host llvm:host Mako:host pyyaml:host spirv-tools:host"
PKG_DEPENDS_TARGET="toolchain expat libdrm Mako:host pyyaml:host"
PKG_LONGDESC="Mesa is a 3-D graphics library with an API."
PKG_PATCH_DIRS+=" ${DEVICE}"

get_graphicdrivers

if listcontains "${GRAPHIC_DRIVERS}" "panfrost"; then
  PKG_DEPENDS_TARGET+=" mesa:host"
fi

PKG_MESON_OPTS_HOST="-Dglvnd=disabled \
                     -Dgallium-drivers= \
                     -Dplatforms= \
                     -Dglx=disabled \
                     -Dvulkan-drivers= \
                     -Dshared-llvm=disabled \
                     -Dtools=panfrost \
                     -Dvideo-codecs= \
                     -Dbuild-tests=false \
                     -Denable-glcpp-tests=false \
                     -Dmesa-clc=enabled \
                     -Dinstall-mesa-clc=true \
                     -Dprecomp-compiler=enabled \
                     -Dinstall-precomp-compiler=true"

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

if listcontains "${GRAPHIC_DRIVERS}" "panfrost"; then
  # These options require that we have built mesa host as specified above
  PKG_MESON_OPTS_TARGET+=" -Dmesa-clc=system \
                           -Dprecomp-compiler=system"
fi

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
