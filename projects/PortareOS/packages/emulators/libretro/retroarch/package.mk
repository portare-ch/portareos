# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-2026 ROCKNIX (https://github.com/ROCKNIX)
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="retroarch"
# bump-ignore: this tracks master, and the bumper follows /releases/latest.
# Upstream's newest tag is still v1.22.2 from November 2025, which is 2009
# commits behind the commit below, so the bumper would file a downgrade and
# call it an update. Re-pin by hand.
PKG_VERSION="9705e03a59145bc33aa79fe6b52a92005703f74e"
PKG_SHA256="bd747f84a239e72195cb5c155d1b888739853c03feedfa2e83ac8924c5b539ab"
PKG_SITE="https://github.com/libretro/RetroArch"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_LICENSE="GPL-3.0-or-later"
PKG_DEPENDS_TARGET="toolchain SDL2 alsa-lib libass openssl freetype zlib retroarch-assets core-info ffmpeg libass joyutils openal-soft libogg libvorbisidec libvorbis libvpx libpng libdrm flac xz"
PKG_LONGDESC="Reference frontend for the libretro API."

case ${ARCH} in
  arm)
    true
    ;;
  *)
    PKG_DEPENDS_TARGET+=" empty"
    ;;
esac

PKG_CONFIGURE_OPTS_TARGET="--disable-qt \
                           --disable-pulse \
                           --enable-alsa \
                           --enable-udev \
                           --disable-opengl1 \
                           --disable-x11 \
                           --enable-zlib \
                           --enable-freetype \
                           --disable-discord \
                           --disable-vg \
                           --disable-sdl \
                           --enable-sdl2 \
                           --enable-kms \
                           --enable-ffmpeg"

if [ "${PIPEWIRE_SUPPORT}" = "yes" ]; then
  PKG_DEPENDS_TARGET+=" pipewire"
  PKG_CONFIGURE_OPTS_TARGET+=" --enable-pipewire"
fi

case ${ARCH} in
  arm) PKG_CONFIGURE_OPTS_TARGET+=" --enable-neon" ;;
  aarch64) PKG_CONFIGURE_OPTS_TARGET+=" --disable-neon" ;;
esac

case ${DEVICE} in
  RK*) PKG_DEPENDS_TARGET+=" librga" ;;
esac

if [ "${DISPLAYSERVER}" = "wl" ]; then
  PKG_DEPENDS_TARGET+=" wayland"
  PKG_CONFIGURE_OPTS_TARGET+=" --enable-wayland"
  case ${ARCH} in
    arm)
      true
      ;;
    *)
      PKG_DEPENDS_TARGET+=" ${WINDOWMANAGER}"
      ;;
  esac
else
  PKG_CONFIGURE_OPTS_TARGET+=" --disable-wayland"
fi

if [ "${OPENGLES_SUPPORT}" = "yes" ] && [ "${PREFER_GLES}" = "yes" ]; then
  PKG_DEPENDS_TARGET+=" ${OPENGLES}"
  # --enable-opengles3 required for glcore, --enable-opengles3_1 doesn't auto-select it
  PKG_CONFIGURE_OPTS_TARGET+=" --enable-opengles --enable-opengles3 --enable-opengles3_1"
  PKG_CONFIGURE_OPTS_TARGET+=" --disable-opengl"
else
  # Full OpenGL
  PKG_DEPENDS_TARGET+=" ${OPENGL} glu libglvnd"
  PKG_CONFIGURE_OPTS_TARGET+=" --enable-opengl"
  PKG_CONFIGURE_OPTS_TARGET+=" --disable-opengles --disable-opengles3 --disable-opengles3_1 --disable-opengles3_2"
fi

if [ "${VULKAN_SUPPORT}" = "yes" ]; then
  PKG_DEPENDS_TARGET+=" ${VULKAN}"
  PKG_CONFIGURE_OPTS_TARGET+=" --enable-vulkan --enable-vulkan_display"
else
  PKG_CONFIGURE_OPTS_TARGET+=" --disable-vulkan"
fi

pre_configure_target() {
  CFLAGS+=" -DUDEV_TOUCH_SUPPORT"
  CXXFLAGS+=" -DUDEV_TOUCH_SUPPORT"
  TARGET_CONFIGURE_OPTS=""
  cd ${PKG_BUILD}
}

make_target() {
  make HAVE_UPDATE_ASSETS=0 HAVE_LIBRETRODB=1 HAVE_BLUETOOTH=0 HAVE_NETWORKING=1 HAVE_ZARCH=1 HAVE_QT=0 HAVE_LANGEXTRA=1
  [ $? -eq 0 ] && echo "(retroarch ok)" || { echo "(retroarch failed)" ; exit 1 ; }
  make -C gfx/video_filters compiler=$CC extra_flags="$CFLAGS"
  [ $? -eq 0 ] && echo "(video filters ok)" || { echo "(video filters failed)" ; exit 1 ; }
  make -C libretro-common/audio/dsp_filters compiler=$CC extra_flags="$CFLAGS"
  [ $? -eq 0 ] && echo "(audio filters ok)" || { echo "(audio filters failed)" ; exit 1 ; }
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_BUILD}/retroarch ${INSTALL}/usr/bin
  mkdir -p ${INSTALL}/usr/share/retroarch/filters

  mkdir -p ${INSTALL}/etc
    cp -a ${PKG_BUILD}/retroarch.cfg ${INSTALL}/etc

  mkdir -p ${INSTALL}/usr/share/retroarch/filters/64bit/video
    cp -a ${PKG_BUILD}/gfx/video_filters/*.so ${INSTALL}/usr/share/retroarch/filters/64bit/video
    cp -a ${PKG_BUILD}/gfx/video_filters/*.filt ${INSTALL}/usr/share/retroarch/filters/64bit/video

  mkdir -p ${INSTALL}/usr/share/retroarch/filters/64bit/audio
    cp -a ${PKG_BUILD}/libretro-common/audio/dsp_filters/*.so ${INSTALL}/usr/share/retroarch/filters/64bit/audio
    cp -a ${PKG_BUILD}/libretro-common/audio/dsp_filters/*.dsp ${INSTALL}/usr/share/retroarch/filters/64bit/audio

  # General configuration
  mkdir -p ${INSTALL}/usr/config/retroarch
    if [ -d "${PKG_DIR}/sources/${DEVICE}" ]; then
      cp -a ${PKG_DIR}/sources/${DEVICE}/* ${INSTALL}/usr/config/retroarch
    else
      echo "Configure retroarch for ${DEVICE}"
      exit 1
    fi

  # Make sure the shader directories exist for overlayfs.
  mkdir -p ${INSTALL}/usr/share/slang-shaders
    touch ${INSTALL}/usr/share/slang-shaders/.overlay

  mkdir -p ${INSTALL}/usr/share/libretro
    # Copy achievment sounds
    cp -a ${PKG_DIR}/sounds ${INSTALL}/usr/share/libretro
    # Copy achievements hooks script
    cp -a ${PKG_DIR}/scripts/call_achievements_hooks.sh ${INSTALL}/usr/share/libretro
}

post_install() {
  enable_service tmp-cores.mount
  enable_service tmp-database.mount
  enable_service tmp-assets.mount
  enable_service tmp-shaders.mount
}
