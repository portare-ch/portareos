# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="fex-emu"
PKG_VERSION="177542e673b1f7d2179307c176ac8dd696784bed"
PKG_LICENSE="MIT"
PKG_SITE="https://github.com/FEX-Emu/FEX"
PKG_URL="https://github.com/FEX-Emu/FEX.git"
PKG_DEPENDS_TARGET="toolchain llvm:host fex-emu:host squashfs-tools zlib squashfuse alsa-lib libxcb wayland libglvnd libdrm libX11 libXrandr xorgproto"
PKG_DEPENDS_HOST="toolchain:host llvm:host openssl:host"
PKG_LONGDESC="FEX-Emu is a fast x86/x86-64 emulator for AArch64"
PKG_TOOLCHAIN="manual"

FEX_LLVM_BIN="${TOOLCHAIN}/bin"
FEX_CLANG="${FEX_LLVM_BIN}/clang"
FEX_CLANGXX="${FEX_LLVM_BIN}/clang++"
FEX_CMAKE_BASE=(
  -DCMAKE_BUILD_TYPE=Release
  -DENABLE_LTO=True
  -DBUILD_TESTING=False
  -DBUILD_THUNKS=True
  -DCMAKE_INSTALL_PREFIX=/usr
  -DCMAKE_MAKE_PROGRAM=ninja
  -DCMAKE_C_COMPILER="${FEX_CLANG}"
  -DCMAKE_CXX_COMPILER="${FEX_CLANGXX}"
  
  # Make sure we pick up teh right llvm-ar and llvm-ranlib
  -DCMAKE_AR="${FEX_LLVM_BIN}/llvm-ar"
  -DCMAKE_RANLIB="${FEX_LLVM_BIN}/llvm-ranlib"
  -DCMAKE_C_COMPILER_AR="${FEX_LLVM_BIN}/llvm-ar"
  -DCMAKE_CXX_COMPILER_AR="${FEX_LLVM_BIN}/llvm-ar"
  -DCMAKE_ASM_COMPILER_AR="${FEX_LLVM_BIN}/llvm-ar"
  -DCMAKE_C_COMPILER_RANLIB="${FEX_LLVM_BIN}/llvm-ranlib"
  -DCMAKE_CXX_COMPILER_RANLIB="${FEX_LLVM_BIN}/llvm-ranlib"
  -DCMAKE_ASM_COMPILER_RANLIB="${FEX_LLVM_BIN}/llvm-ranlib"
)

FEX_CMAKE_OPTS=(
  "${FEX_CMAKE_BASE[@]}"
  -DUSE_LINKER=lld
  -DENABLE_ASSERTIONS=False
  -DCMAKE_LINKER="${FEX_LLVM_BIN}/ld.lld"
)

make_host() {
  mkdir -p "${PKG_BUILD}/.${HOST_NAME}"
  cd "${PKG_BUILD}"

  local -a host_opts=(
    -G Ninja
    -S "${PKG_BUILD}"
    -B "${PKG_BUILD}/.${HOST_NAME}"
    "${FEX_CMAKE_BASE[@]}"
    -DUSE_LINKER="${FEX_LLVM_BIN}/ld.lld"
    -DBUILD_FEXCONFIG=False
    -DTHUNKGEN_ONLY=True
    -DCMAKE_ASM_COMPILER="${FEX_CLANG}"
    -DCMAKE_PREFIX_PATH="${TOOLCHAIN}"
    -DCLANG_EXEC_PATH="${FEX_CLANG}"
    -DENABLE_X86_HOST_DEBUG=True
  )
  cmake "${host_opts[@]}"
  cd "${PKG_BUILD}/.${HOST_NAME}"
  ninja thunkgen
}

make_target() {
  local _v
  for _v in CFLAGS CXXFLAGS LDFLAGS; do
    export ${_v}="$(echo ${!_v} | sed 's/-mabi=lp64//g; s/-mtune=[^ ]*//g')"
  done
  export USER="${USER:-$(whoami)}"
  export HOME=${PKG_BUILD}/nix
  curl -L https://nixos.org/nix/install | sh -s -- --no-daemon
  . "${HOME}/.nix-profile/etc/profile.d/nix.sh"

  # FEX's Data/nix/LibraryForwarding/shell.nix opens with
  #
  #   { pkgs ? import <nixpkgs> { } }:
  #
  # so the i686 and x86_64 cross toolchains it builds the thunks with come
  # from whatever <nixpkgs> resolves to. A fresh install points that at an
  # unstable channel, which makes this recipe's output depend on the day it
  # runs. Pin it.
  #
  # nixos-25.11 is pinned rather than a channel because unstable moved
  # default-gcc-version to 16, and the thunks are compiled by clang against
  # that GCC's libstdc++: GCC 16's <limits> defines
  # numeric_limits<__float128>::signaling_NaN() as
  #
  #   __builtin_bit_cast(__float128, __builtin_nansf128(""))
  #
  # and on i686 clang's __builtin_nansf128 gives a 12-byte long double where
  # __float128 is 16, so the cast is rejected and ThunkLibs fails to build.
  # 25.11 is on GCC 14, which predates that definition.
  export NIX_PATH="nixpkgs=https://github.com/NixOS/nixpkgs/archive/b6018f87da91d19d0ab4cf979885689b469cdd41.tar.gz"

  mkdir -p "${PKG_BUILD}/.${TARGET_NAME}"
  cd "${PKG_BUILD}/.${TARGET_NAME}"

  case ${TARGET_CPU} in
    cortex-x3|cortex-x4)
      TUNE_CPU="cortex-a78"
      ;;
    *)
      TUNE_CPU="${TARGET_CPU##*.}"
      ;;
  esac

  local -a tgt_opts=(
    -G Ninja
    -S "${PKG_BUILD}"
    -B "${PKG_BUILD}/.${TARGET_NAME}"
    -DCMAKE_SYSTEM_NAME=Linux
    -DCMAKE_SYSTEM_PROCESSOR=aarch64
    -DCMAKE_C_COMPILER_TARGET=aarch64-portareos-linux-gnu
    -DCMAKE_CXX_COMPILER_TARGET=aarch64-portareos-linux-gnu
    -DCMAKE_SYSROOT="${SYSROOT_PREFIX}"
    -DCMAKE_FIND_ROOT_PATH="${SYSROOT_PREFIX}"
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY
    -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY
    # FEXConfig is a Qt desktop dialog; FEX is configured from files here.
    -DBUILD_FEXCONFIG=False
    # FEX takes a system fmt when find_package sees one and its bundled copy
    # otherwise. A shared libfmt left in an incremental build's sysroot, from
    # the standalone Dolphin that is gone, made FEXRootFSFetcher need a
    # libfmt.so.12 the image does not ship. Always the bundled one.
    -DCMAKE_DISABLE_FIND_PACKAGE_fmt=TRUE
    "${FEX_CMAKE_OPTS[@]}"
    -DGENERATOR_EXE="${TOOLCHAIN}/usr/bin/thunkgen"
    -DCMAKE_INSTALL_LIBDIR=lib
    -DTUNE_CPU="${TUNE_CPU}"
  )
  cmake "${tgt_opts[@]}"
  bash "${PKG_BUILD}/Data/nix/cmake_enable_libfwd.sh"
  ninja
}

makeinstall_target() {
  cd "${PKG_BUILD}/.${TARGET_NAME}"
  DESTDIR="${INSTALL}" ninja install
  mkdir -p "${INSTALL}/usr/config/fex-emu"
  cp -rf "${PKG_DIR}/config/fex-emu/." "${INSTALL}/usr/config/fex-emu"
  cp -rf "${PKG_DIR}/config/gptk" "${INSTALL}/usr/config/fex-emu"

}

makeinstall_host() {
  mkdir -p "${TOOLCHAIN}/usr/bin"
  cp -av "${PKG_BUILD}/.${HOST_NAME}/Bin/thunkgen" "${TOOLCHAIN}/usr/bin"
}
