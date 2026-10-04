# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# Copyright (C) 2018-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="glibc"
PKG_VERSION="2.41"
PKG_SHA256="a5a26b22f545d6b7d7b3dd828e11e428f24f4fac43c934fb071b6a7d0828e901"
PKG_LICENSE="GPL"
PKG_SITE="https://www.gnu.org/software/libc/"
PKG_URL="https://ftp.gnu.org/pub/gnu/glibc/${PKG_NAME}-${PKG_VERSION}.tar.xz"
PKG_DEPENDS_TARGET="ccache:host autotools:host linux:host gcc:bootstrap pigz:host Python3:host"
PKG_DEPENDS_INIT="glibc"
PKG_LONGDESC="The Glibc package contains the main C library."
PKG_BUILD_FLAGS="+bfd -gold"

case "${DEVICE}" in
  RK3588)
    OPT_ENABLE_KERNEL=6.1.0
    ;;
  *)
    OPT_ENABLE_KERNEL=6.10.0
    ;;
esac

case ${TARGET_ARCH} in
  arm|aarch64)
    PKG_PATCH_DIRS="widevine-arm"
    ;;
esac

PKG_CONFIGURE_OPTS_TARGET="BASH_SHELL=/bin/sh \
                           ac_cv_path_PERL=no \
                           ac_cv_prog_MAKEINFO= \
                           --libexecdir=/usr/lib/glibc \
                           --cache-file=config.cache \
                           --disable-profile \
                           --disable-sanity-checks \
                           --enable-add-ons \
                           --enable-bind-now \
                           --with-elf \
                           --with-tls \
                           --with-__thread \
                           --with-binutils=${BUILD}/toolchain/bin \
                           --with-headers=${SYSROOT_PREFIX}/usr/include \
                           --enable-kernel=${OPT_ENABLE_KERNEL} \
                           --without-cvs \
                           --without-gd \
                           --disable-build-nscd \
                           --disable-nscd \
                           --disable-timezone-tools"

if build_with_debug; then
  PKG_CONFIGURE_OPTS_TARGET+=" --enable-debug"
else
  PKG_CONFIGURE_OPTS_TARGET+=" --disable-debug"
fi

post_unpack() {
  find "${PKG_BUILD}" -type f -name '*.py' -exec sed -e '1s,^#![[:space:]]*/usr/bin/python.*,#!/usr/bin/env python3,' -i {} \;
}

pre_configure_target() {
# Filter out some problematic *FLAGS
  export CFLAGS=$(echo ${CFLAGS} | sed -e "s|-O.|-O3|g")

  export CFLAGS=$(echo ${CFLAGS} | sed -e "s|-Wunused-but-set-variable||g")
  export CFLAGS="${CFLAGS} -Wno-unused-variable"

  if [ -n "${PROJECT_CFLAGS}" ]; then
    export CFLAGS=$(echo ${CFLAGS} | sed -e "s|${PROJECT_CFLAGS}||g")
  fi

  export LDFLAGS=$(echo ${LDFLAGS} | sed -e "s|-O.|-O3|g")

  export LDFLAGS=$(echo ${LDFLAGS} | sed -e "s|-Wl,--as-needed||")

  unset LD_LIBRARY_PATH

  # set some CFLAGS we need
  export CFLAGS="${CFLAGS} -g -fno-stack-protector"

  export BUILD_CC=${HOST_CC}
  export OBJDUMP_FOR_HOST=objdump

  cat >config.cache <<EOF
libc_cv_forced_unwind=yes
libc_cv_c_cleanup=yes
libc_cv_ssp=no
libc_cv_ssp_strong=no
libc_cv_slibdir=/usr/lib
EOF

  cat >configparms <<EOF
libdir=/usr/lib
slibdir=/usr/lib
sbindir=/usr/bin
rootsbindir=/usr/bin
build-programs=yes
EOF

  # binaries to install into target
  GLIBC_INCLUDE_BIN="getent ldd locale localedef"
}

post_makeinstall_target() {
  mkdir -p ${INSTALL}/.noinstall
    cp -p ${INSTALL}/usr/bin/localedef ${INSTALL}/.noinstall
    cp -a ${INSTALL}/usr/share/i18n/locales ${INSTALL}/.noinstall
    mv ${INSTALL}/usr/share/i18n/charmaps ${INSTALL}/.noinstall

  safe_remove ${INSTALL}/usr/lib/audit
  safe_remove ${INSTALL}/usr/lib/glibc
  safe_remove ${INSTALL}/usr/lib/*.o
  safe_remove ${INSTALL}/var

# add UTF-8 charmap
  mkdir -p ${INSTALL}/usr/share/i18n/charmaps
    cp -PR ${INSTALL}/.noinstall/charmaps/UTF-8.gz ${INSTALL}/usr/share/i18n/charmaps

  if [ ! "${GLIBC_LOCALES}" = yes ]; then
    safe_remove ${INSTALL}/usr/share/i18n/locales

    mkdir -p ${INSTALL}/usr/share/i18n/locales
      cp -PR ${PKG_BUILD}/localedata/locales/POSIX ${INSTALL}/usr/share/i18n/locales
  else
# 369 locale definitions is 12.1MB, and this device is asked for two of
# them: English, and Japanese because game and ROM text comes that way.
# A definition is not self-contained - en_US and ja_JP both copy i18n and
# iso14651_t1 and include the transliteration tables - so the list is the
# transitive closure of copy and include, 19 files rather than 2. Most of
# what survives is iso14651_t1_common at 3.2MB, which collation needs.
    LOCALES_KEEP="en_US ja_JP POSIX i18n i18n_ctype iso14651_t1 \
                  iso14651_t1_common translit_circle translit_cjk_compat \
                  translit_cjk_variants translit_combining translit_compat \
                  translit_emojis translit_font translit_fraction \
                  translit_narrow translit_neutral translit_small \
                  translit_wide"
    mkdir -p ${INSTALL}/.locales-keep
    for _l in ${LOCALES_KEEP}; do
      [ -f ${INSTALL}/usr/share/i18n/locales/${_l} ] &&
        cp -p ${INSTALL}/usr/share/i18n/locales/${_l} ${INSTALL}/.locales-keep/
    done
    safe_remove ${INSTALL}/usr/share/i18n/locales
    mkdir -p ${INSTALL}/usr/share/i18n/locales
      mv ${INSTALL}/.locales-keep/* ${INSTALL}/usr/share/i18n/locales/
    rmdir ${INSTALL}/.locales-keep
  fi

# gconv is 257 charset converters, 19MB, on a system that is UTF-8
# throughout - and UTF-8 is built into glibc, so it needs no module here at
# all. What is kept is Latin-1 and -15, the UTF-16/32 forms libraries
# convert through, and the Japanese encodings to go with the ja_JP locale
# above. EUC-JP links against libJIS, so that stays too; CP932 and SJIS
# carry their tables inside. The full set is still in .noinstall for the
# build. Anything asking iconv for a charset that is gone gets a failed
# iconv_open rather than wrong text.
  GCONV_KEEP="ISO8859-1.so ISO8859-15.so UNICODE.so UTF-16.so UTF-32.so \
              UTF-7.so CP932.so SJIS.so EUC-JP.so EUC-JP-MS.so \
              libJIS.so libJISX0213.so ANSI_X3.110.so"
  if [ -d ${INSTALL}/usr/lib/gconv ]; then
    mkdir -p ${INSTALL}/.gconv-keep
    for _m in ${GCONV_KEEP}; do
      [ -f ${INSTALL}/usr/lib/gconv/${_m} ] &&
        mv ${INSTALL}/usr/lib/gconv/${_m} ${INSTALL}/.gconv-keep/
    done
    cp -a ${INSTALL}/usr/lib/gconv/gconv-modules ${INSTALL}/.gconv-keep/ 2>/dev/null || :
    cp -a ${INSTALL}/usr/lib/gconv/gconv-modules.d ${INSTALL}/.gconv-keep/ 2>/dev/null || :
    safe_remove ${INSTALL}/usr/lib/gconv
    mkdir -p ${INSTALL}/usr/lib/gconv
      mv ${INSTALL}/.gconv-keep/* ${INSTALL}/usr/lib/gconv/
    rmdir ${INSTALL}/.gconv-keep
  fi

# create default configs
  mkdir -p ${INSTALL}/etc
    cp ${PKG_DIR}/config/nsswitch-target.conf ${INSTALL}/etc/nsswitch.conf
    cp ${PKG_DIR}/config/host.conf ${INSTALL}/etc
    cp ${PKG_DIR}/config/gai.conf ${INSTALL}/etc
    cp ${PKG_DIR}/config/ld.so.conf ${INSTALL}/etc

  ln -sf /storage/.cache/ld.so.cache ${INSTALL}/etc/ld.so.cache
  if [ -f ${INSTALL}/usr/bin/ldconfig ]; then
    mv ${INSTALL}/usr/bin/ldconfig ${INSTALL}/usr/bin/ldconfig.real
    cat >${INSTALL}/usr/bin/ldconfig <<'EOF'
#!/bin/sh
me=$0
case "$me" in
  /*) ;;
  *) me=$(pwd)/$me ;;
esac
me=$(readlink -f "$me" 2>/dev/null) || me=$0
REAL=${me%/*}/ldconfig.real
[ -x "$REAL" ] || REAL=/usr/bin/ldconfig.real
case " $* " in
  *" -C "*|*" -C"*) exec "$REAL" -X "$@" ;;
esac
exec "$REAL" -X -C /storage/.cache/ld.so.cache "$@"
EOF
    chmod 755 ${INSTALL}/usr/bin/ldconfig
  fi
}

configure_init() {
  cd ${PKG_BUILD}
    rm -rf ${PKG_BUILD}/.${TARGET_NAME}-init
}

make_init() {
  : # reuse make_target()
}

makeinstall_init() {
  mkdir -p ${INSTALL}/usr/lib
    cp -PR ${PKG_BUILD}/.${TARGET_NAME}/elf/ld*.so* ${INSTALL}/usr/lib
    cp -PR ${PKG_BUILD}/.${TARGET_NAME}/libc.so* ${INSTALL}/usr/lib
    cp -PR ${PKG_BUILD}/.${TARGET_NAME}/math/libm.so* ${INSTALL}/usr/lib
    cp -PR ${PKG_BUILD}/.${TARGET_NAME}/nptl/libpthread.so* ${INSTALL}/usr/lib
    cp -PR ${PKG_BUILD}/.${TARGET_NAME}/rt/librt.so* ${INSTALL}/usr/lib
    cp -PR ${PKG_BUILD}/.${TARGET_NAME}/resolv/libnss_dns.so* ${INSTALL}/usr/lib
    cp -PR ${PKG_BUILD}/.${TARGET_NAME}/resolv/libresolv.so* ${INSTALL}/usr/lib
}

post_makeinstall_init() {
# create default configs
  mkdir -p ${INSTALL}/etc
    cp ${PKG_DIR}/config/nsswitch-init.conf ${INSTALL}/etc/nsswitch.conf
}
