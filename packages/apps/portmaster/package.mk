# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="portmaster"
PKG_VERSION="2026.09.13-0343"
PKG_SHA256="2afda49a51b5760c14fda0a12dc543694a6b6a4b4e9ae9d4e11659996382d80a"
PKG_LICENSE="MIT"
PKG_SITE="https://github.com/PortsMaster/PortMaster-GUI"
PKG_URL="https://github.com/PortsMaster/PortMaster-GUI/releases/download/${PKG_VERSION}/PortMaster.zip"
# pugwash is a pySDL2 program: it dlopens SDL2 and its satellites by name at
# import time rather than linking them, so nothing here can be inferred from
# the binary and every one has to be declared. It imports sdl2, sdl2.ext,
# sdl2.sdlgfx and sdl2.sdlmixer, and pySDL2 resolves SDL2, SDL2_gfx,
# SDL2_mixer, SDL2_ttf and SDL2_image out of /usr/lib.
PKG_DEPENDS_TARGET="toolchain portareos-hotkey gamecontrollerdb oga_controls control-gen xmlstarlet list-guid gst-plugins-base \
                    SDL2 SDL2_mixer SDL2_gfx SDL2_ttf SDL2_image"
PKG_LONGDESC="Portmaster - a simple tool that allows you to download various game ports"
PKG_TOOLCHAIN="manual"

COMPAT_URL="https://github.com/ROCKNIX/packages/raw/main/compat.tar.gz" #f0f5e94

makeinstall_target() {
  export STRIP=true

  mkdir -p ${INSTALL}/usr/config/PortMaster
    cp -a ${PKG_DIR}/sources/* ${INSTALL}/usr/config/PortMaster

  mkdir -p ${INSTALL}/usr/bin
    cp -a ${PKG_DIR}/scripts/* ${INSTALL}/usr/bin

  mkdir -p ${INSTALL}/usr/config/PortMaster/release
    curl -Lo ${PKG_BUILD}/PortMaster.zip ${PKG_URL}

  # PortMaster knows its platforms by the OS name and PortareOS is not one
  # of them, so it would take its default platform, which never copies
  # our control.txt, mapper.txt and controller database into its folder.
  # pylibs-patches/ adds a PortareOS platform to harbourmaster. The code
  # lives in pylibs.zip inside the release archive, so both are opened,
  # patched and closed again. Not patches/: the build system applies that
  # directory to the unpacked archive itself, where the code is not.
  rm -rf ${PKG_BUILD}/release
  mkdir -p ${PKG_BUILD}/release/pylibs
    unzip -qo ${PKG_BUILD}/PortMaster.zip -d ${PKG_BUILD}/release
    unzip -qo ${PKG_BUILD}/release/PortMaster/pylibs.zip -d ${PKG_BUILD}/release/pylibs
    for p in ${PKG_DIR}/pylibs-patches/*.patch; do
      patch -d ${PKG_BUILD}/release/pylibs -p1 < ${p}
    done
    rm -f ${PKG_BUILD}/release/PortMaster/pylibs.zip
    (cd ${PKG_BUILD}/release/pylibs && zip -qr ../PortMaster/pylibs.zip .)
    (cd ${PKG_BUILD}/release && zip -qr ${INSTALL}/usr/config/PortMaster/release/PortMaster.zip PortMaster)

  mkdir -p ${INSTALL}/usr/lib/compat
    curl -Lo ${PKG_BUILD}/compat.tar.gz ${COMPAT_URL}
    tar -xvf ${PKG_BUILD}/compat.tar.gz -C ${INSTALL}/usr/lib
    # Keep the real SDL2 this tarball ships. Ports are prebuilt aarch64
    # binaries linked against real SDL2, and the system libSDL2 is now
    # sdl2-compat. ROCKNIX ran that pairing for three weeks and saw ports
    # segfault - Apotris and Aquaria confirmed - with scaling and audio
    # faults besides. control.txt exports LD_LIBRARY_PATH=/usr/lib/compat
    # for every port, so the ports find this one first and everything
    # else in the image keeps the shim.
    if [ "${PREFER_GLES}" = "yes" ]; then
      mv ${INSTALL}/usr/lib/compat/libSDL2-2.0.so.0.gles ${INSTALL}/usr/lib/compat/libSDL2-2.0.so.0
    else
      rm -rf ${INSTALL}/usr/lib/compat/libSDL2-2.0.so.0.gles
    fi
}
