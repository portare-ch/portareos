# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="ymir-lr"
PKG_VERSION="92000a51cb2b18ebb0ecde0803a4764b92cd5538"
PKG_LICENSE="GPL-3.0-only"
PKG_SITE="https://github.com/ymir-emu/Ymir"
PKG_URL="${PKG_SITE}.git"
PKG_DEPENDS_TARGET="toolchain llvm:host"
PKG_LONGDESC="Ymir - cycle-accurate Sega Saturn emulator with the VDPs and the SCSP on their own threads, as a libretro core"
PKG_TOOLCHAIN="manual"
PKG_BUILD_FLAGS="speed"

# The libretro core is not upstream's: Ymir declined one (ymir-emu/Ymir#746),
# so patch 001 carries libretro's own wrapper (git.libretro.com/libretro/emir,
# branch libretro), rebased onto the pinned upstream commit. A bump is a pin
# move and a rebase of that patch.
#
# clang, as upstream builds it: the NEON renderer leans on clang's implicit
# vector conversions, which GCC rejects, and upstream's CI notes GCC also
# produces much slower code for it. The same clang ARMSX2 uses.

make_target() {
  # The toolchain's flags are GCC's: clang has no -mabi=lp64 ("unknown
  # target ABI", the nightly's failure) and ARMSX2 drops -mtune with it.
  local _v
  for _v in CFLAGS CXXFLAGS LDFLAGS; do
    export ${_v}="$(echo ${!_v} | sed 's/-mabi=lp64//g; s/-mtune=[^ ]*//g')"
  done
  # As ARMSX2 does before linking with lld.
  local _f
  for _f in "${SYSROOT_PREFIX}"/usr/lib/*.o "${SYSROOT_PREFIX}"/usr/lib/*.a; do
    [ -f "${_f}" ] || continue
    "${TOOLCHAIN}/bin/llvm-strip" --strip-debug "${_f}" 2>/dev/null || true
  done

  mkdir -p "${PKG_BUILD}/.${TARGET_NAME}"
  cmake -G Ninja -S "${PKG_BUILD}" -B "${PKG_BUILD}/.${TARGET_NAME}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_MAKE_PROGRAM=ninja \
    -DCMAKE_C_COMPILER="${TOOLCHAIN}/bin/clang" \
    -DCMAKE_CXX_COMPILER="${TOOLCHAIN}/bin/clang++" \
    -DCMAKE_C_COMPILER_AR="${TOOLCHAIN}/bin/llvm-ar" \
    -DCMAKE_CXX_COMPILER_AR="${TOOLCHAIN}/bin/llvm-ar" \
    -DCMAKE_C_COMPILER_RANLIB="${TOOLCHAIN}/bin/llvm-ranlib" \
    -DCMAKE_CXX_COMPILER_RANLIB="${TOOLCHAIN}/bin/llvm-ranlib" \
    -DCMAKE_AR="${TOOLCHAIN}/bin/llvm-ar" \
    -DCMAKE_RANLIB="${TOOLCHAIN}/bin/llvm-ranlib" \
    -DCMAKE_SHARED_LINKER_FLAGS_INIT="-fuse-ld=lld -Wl,--strip-debug -Wl,--exclude-libs,ALL" \
    -DCMAKE_SYSTEM_NAME=Linux \
    -DCMAKE_SYSTEM_PROCESSOR=${TARGET_ARCH} \
    -DCMAKE_C_COMPILER_TARGET=${TARGET_NAME} \
    -DCMAKE_CXX_COMPILER_TARGET=${TARGET_NAME} \
    -DCMAKE_SYSROOT="${SYSROOT_PREFIX}" \
    -DCMAKE_FIND_ROOT_PATH="${SYSROOT_PREFIX}" \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
    -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
    -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
    -DYmir_ENABLE_LIBRETRO=ON \
    -DYmir_DEV_BUILD=OFF \
    -DYmir_ENABLE_IPO=ON \
    -DYmir_ENABLE_TESTS=OFF \
    -DYmir_ENABLE_SANDBOX=OFF \
    -DYmir_ENABLE_YMDASM=OFF
  cmake --build "${PKG_BUILD}/.${TARGET_NAME}" --target ymir_libretro
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
    cp -a ${PKG_BUILD}/.${TARGET_NAME}/apps/ymir-libretro/ymir_libretro.so ${INSTALL}/usr/lib/libretro
}
