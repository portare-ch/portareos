# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2025-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="armsx2-lr"
PKG_VERSION="2.7.2"
PKG_SHA256="ebdffe4e3be3d509ee1ca331fcd53e0a0c257779dd38d7547b4e89103cddea5b"
PKG_LICENSE="GPLv3"
PKG_SITE="https://github.com/ARMSX2/ARMSX2"
PKG_URL="${PKG_SITE}/archive/refs/tags/${PKG_VERSION}.tar.gz"
PKG_LONGDESC="ARMSX2 is a native ARM64 PlayStation 2 (PS2) emulator, a fork of PCSX2 that ports the EE/IOP/VU JIT recompilers to ARM64."
# The libretro core, armsx2_libretro.so, and nothing else: it draws into
# RetroArch's Vulkan context and hands RetroArch its audio and input, so
# PS2 goes out through the same display, PipeWire and controller path as
# every other core. The SDL frontend it replaced is not built.
#
# SDL3 stays: the core does not use it, but CMake requires it whatever is
# being built. ffmpeg went with the frontend's video capture; nothing in
# the tree links it any more.
PKG_DEPENDS_TARGET="toolchain llvm:host SDL3 libpng zlib libjpeg-turbo zstd lz4 libwebp freetype plutosvg curl libpcap shaderc"
# ARMSX2's own Turnip build, which runemu gives this core alone (#497). It is
# an Adreno driver, so only for the device that has one.
[ "${DEVICE}" = "SM8550" ] && PKG_DEPENDS_TARGET+=" armsx2-turnip"
PKG_TOOLCHAIN="manual"
PKG_BUILD_FLAGS="speed"

PATCHES_URL="https://github.com/PCSX2/pcsx2_patches/archive/refs/tags/latest.zip"

pre_configure_target() {
  PCSX2_CMAKE_BASE=(
    # Reported version
    -DARMSX2_VERSION=${PKG_VERSION}
    -DCMAKE_BUILD_TYPE=Release
    # Full-tree IPO stays off, the recompiler/VU/EE/IOP core gets it:
    -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF
    -DLTO_PCSX2_CORE=ON
    -DCMAKE_DISABLE_PRECOMPILE_HEADERS=ON
    # Vulkan only: RetroArch runs Vulkan here, and the core renders into the
    # frontend's context, so a GL renderer would have nothing to draw into.
    -DUSE_VULKAN=ON
    -DUSE_OPENGL=OFF
    -DUSE_BACKTRACE=OFF
    -DENABLE_QT_UI=OFF
    -DENABLE_SDL_FRONTEND=OFF
    # ENABLE_LIBRETRO is defined for the whole PCSX2 library, not just the
    # core, so no frontend can be built from this configuration.
    -DENABLE_LIBRETRO=ON
    # With ENABLE_LIBRETRO, FindShaderc prefers the static shaderc_combined
    # and links it in, for a core that travels to machines without shaderc.
    # This one does not travel: the image ships libshaderc_shared.so.1, and
    # naming it makes the core dlopen that, as the standalone did, instead of
    # carrying its own glslang and SPIRV-Tools.
    -DSHADERC_LIBRARY=${SYSROOT_PREFIX}/usr/lib/libshaderc_shared.so
    -DENABLE_TESTS=OFF
    # No window system: the frontend owns the surface. WAYLAND_API=ON would
    # also make CMake require ECM, which nothing here provides.
    -DWAYLAND_API=OFF
    -DX11_API=OFF
    -DCMAKE_LINKER_TYPE=LLD
  )

  for _v in CFLAGS CXXFLAGS LDFLAGS; do
    export ${_v}="$(echo ${!_v} | sed 's/-mabi=lp64//g; s/-mtune=[^ ]*//g')"
  done

  for _f in "${SYSROOT_PREFIX}"/usr/lib/*.o "${SYSROOT_PREFIX}"/usr/lib/*.a; do
    [ -f "${_f}" ] || continue
    "${TOOLCHAIN}/bin/llvm-strip" --strip-debug "${_f}" 2>/dev/null || true
  done
}

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
  cmake --build "${PKG_BUILD}/.${TARGET_NAME}" --target pcsx2-libretro
  wget -c -t 5 -O "${PKG_BUILD}/bin/resources/patches.zip" ${PATCHES_URL}
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
  cp -a ${PKG_BUILD}/.${TARGET_NAME}/bin/armsx2_libretro.so ${INSTALL}/usr/lib/libretro
  # No info file in libretro-core-info for this core; upstream ships one.
  cp -a ${PKG_BUILD}/armsx2_libretro.info ${INSTALL}/usr/lib/libretro

  # GameDB, shaders, fonts and the patches archive. The core reads them from
  # <system>/pcsx2/resources, which is on /storage; tmpfiles.d links it here.
  #
  # A frontend's build copies these next to its binary and the core's build
  # does not, so this does the same by hand - including the part that is
  # easy to miss: armsx2_overrides.yaml, ARMSX2's GameDB tuning for tiler
  # GPUs such as the Adreno, which lives outside bin/resources so desktop
  # builds never ship it. Without it the core runs with desktop GS settings.
  mkdir -p ${INSTALL}/usr/share/armsx2
  cp -a ${PKG_BUILD}/bin/resources ${INSTALL}/usr/share/armsx2
  rm -rf ${INSTALL}/usr/share/armsx2/resources/shaders/dx11
  cp -a ${PKG_BUILD}/bin/resources-overlay/armsx2_overrides.yaml \
    ${INSTALL}/usr/share/armsx2/resources
}
