# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2025-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="armsx2-sa"
PKG_VERSION="2.7.2"
PKG_SHA256="ebdffe4e3be3d509ee1ca331fcd53e0a0c257779dd38d7547b4e89103cddea5b"
PKG_LICENSE="GPLv3"
PKG_SITE="https://github.com/ARMSX2/ARMSX2"
PKG_URL="${PKG_SITE}/archive/refs/tags/${PKG_VERSION}.tar.gz"
PKG_LONGDESC="ARMSX2 is a native ARM64 PlayStation 2 (PS2) emulator, a fork of PCSX2 that ports the EE/IOP/VU JIT recompilers to ARM64."
# SDL frontend only: no Qt. armsx2-sdl is the upstream handheld frontend,
# VK_KHR_display straight to the panel, FullscreenUI for the on-screen menus.
PKG_DEPENDS_TARGET="toolchain llvm:host SDL3 libpng zlib libjpeg-turbo zstd lz4 libwebp freetype plutosvg curl libpcap ffmpeg shaderc"
PKG_TOOLCHAIN="manual"
PKG_BUILD_FLAGS="speed"

PATCHES_URL="https://github.com/PCSX2/pcsx2_patches/archive/refs/tags/latest.zip"

get_graphicdrivers
  if listcontains "${GRAPHIC_DRIVERS}" "(panfrost)"; then
    GRAPHICS_DRIVER="panfrost"
  elif listcontains "${GRAPHIC_DRIVERS}" "(freedreno)"; then
    GRAPHICS_DRIVER="freedreno"
  fi

pre_configure_target() {
  PCSX2_CMAKE_BASE=(
    # Reported version
    -DARMSX2_VERSION=${PKG_VERSION}
    -DCMAKE_BUILD_TYPE=Release
    # Full-tree IPO stays off, the recompiler/VU/EE/IOP core gets it:
    -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF
    -DLTO_PCSX2_CORE=ON
    -DCMAKE_DISABLE_PRECOMPILE_HEADERS=ON
    -DUSE_VULKAN=ON
    # No OpenGL and no X11: the SDL frontend reaches the panel through
    # VK_KHR_display alone. A GL renderer would need an EGL surface, which
    # takes a compositor, and X11 was only there for the GL context.
    -DUSE_OPENGL=OFF
    -DUSE_BACKTRACE=OFF
    -DENABLE_QT_UI=OFF
    -DENABLE_SDL_FRONTEND=ON
    -DENABLE_TESTS=OFF
    # No Wayland: ARMSX2 draws straight to the panel through VK_KHR_display,
    # with no compositor to be a client of. ON also made its CMake require
    # ECM (extra-cmake-modules), which nothing here provides.
    -DWAYLAND_API=OFF
    -DX11_API=OFF
    -DCMAKE_LINKER_TYPE=LLD
  )

  for _v in CFLAGS CXXFLAGS LDFLAGS; do
    export ${_v}="$(echo ${!_v} | sed 's/-mabi=lp64//g; s/-mtune=[^ ]*//g')"
  done
}

  for _f in "${SYSROOT_PREFIX}"/usr/lib/*.o "${SYSROOT_PREFIX}"/usr/lib/*.a; do
    [ -f "${_f}" ] || continue
    "${TOOLCHAIN}/bin/llvm-strip" --strip-debug "${_f}" 2>/dev/null || true
  done

make_target() {
  mkdir -p "${PKG_BUILD}/.${TARGET_NAME}"
  cd "${PKG_BUILD}/.${TARGET_NAME}"

  local -a tgt_opts=(
    -G Ninja
    -S "${PKG_BUILD}"
    -B "${PKG_BUILD}/.${TARGET_NAME}"
    -DCMAKE_INSTALL_PREFIX=/usr
    -DCMAKE_MAKE_PROGRAM=ninja
    -DCMAKE_C_COMPILER="${TOOLCHAIN}/bin/clang"
    -DCMAKE_CXX_COMPILER="${TOOLCHAIN}/bin/clang++"
    -DCMAKE_C_COMPILER_AR="${TOOLCHAIN}/bin/llvm-ar"
    -DCMAKE_CXX_COMPILER_AR="${TOOLCHAIN}/bin/llvm-ar"
    -DCMAKE_C_COMPILER_RANLIB="${TOOLCHAIN}/bin/llvm-ranlib"
    -DCMAKE_CXX_COMPILER_RANLIB="${TOOLCHAIN}/bin/llvm-ranlib"
    -DCMAKE_EXE_LINKER_FLAGS_INIT="-fuse-ld=lld -Wl,--strip-debug"
    -DCMAKE_MODULE_LINKER_FLAGS_INIT="-fuse-ld=lld -Wl,--strip-debug"
    -DCMAKE_SHARED_LINKER_FLAGS_INIT="-fuse-ld=lld -Wl,--strip-debug"
    -DCMAKE_SYSTEM_NAME=Linux
    -DCMAKE_SYSTEM_PROCESSOR=${TARGET_ARCH}
    -DCMAKE_C_COMPILER_TARGET=${TARGET_NAME}
    -DCMAKE_CXX_COMPILER_TARGET=${TARGET_NAME}
    -DCMAKE_SYSROOT="${SYSROOT_PREFIX}"
    -DCMAKE_FIND_ROOT_PATH="${SYSROOT_PREFIX}"
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY
    -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY
    -DLLVM_DIR="${TOOLCHAIN}/lib/cmake/llvm"
    -DCMAKE_AR="${TOOLCHAIN}/bin/llvm-ar"
    -DCMAKE_RANLIB="${TOOLCHAIN}/bin/llvm-ranlib"
    -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER
    "${PCSX2_CMAKE_BASE[@]}"
  )
  cmake "${tgt_opts[@]}"
  cmake --build "${PKG_BUILD}/.${TARGET_NAME}" --target pcsx2-sdl
  wget -c -t 5 -O "bin/resources/patches.zip" ${PATCHES_URL}
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp -rf ${PKG_DIR}/scripts/* ${INSTALL}/usr/bin
  chmod 755 ${INSTALL}/usr/bin/*

  mkdir -p ${INSTALL}/usr/share/armsx2-sa
  cp -rf ${PKG_BUILD}/.${TARGET_NAME}/bin/* ${INSTALL}/usr/share/armsx2-sa

  mkdir -p ${INSTALL}/usr/config
  cp -rf ${PKG_DIR}/config/common/ARMSX2 ${INSTALL}/usr/config
  cp -f ${PKG_DIR}/config/common/armsx2.gptk ${INSTALL}/usr/config/ARMSX2

  # The generic config is the Nova's (#15), checked against its panel:
  # nothing in PCSX2.ini names a resolution, AspectRatio "Auto 4:3/3:2" fills
  # the 4:3 panel, the launcher passes -fullscreen so StartFullscreen=false is
  # moot, widescreen patches are off, and IntegerScaling stays off: PCSX2
  # scales the internal framebuffer in whole multiples, which on a 1280x960
  # window means 1024x896 for a 512x448 game and no gain in a 3D title.
  # upscale_multiplier is 2: 512x448 renders at 1024x896 and the output
  # scaler takes it the last step to the panel, where native resolution
  # was being stretched 2.1x.
  case ${DEVICE} in
    S922X)
      cp -rf ${PKG_DIR}/config/S922X/ARMSX2 ${INSTALL}/usr/config
    ;;
    *)
      cp -rf ${PKG_DIR}/config/inputplumber/ARMSX2 ${INSTALL}/usr/config
    ;;
  esac
}

post_install() {
  case ${GRAPHICS_DRIVER} in
    panfrost)
      GRAPHICS="export MESA_GL_VERSION_OVERRIDE=3.3 MESA_GLSL_VERSION_OVERRIDE=330"
    ;;
    *)
      GRAPHICS=""
    ;;
  esac

  sed -e "s/@GRAPHICS@/${GRAPHICS}/g" \
        -i ${INSTALL}/usr/bin/start_armsx2.sh
}
