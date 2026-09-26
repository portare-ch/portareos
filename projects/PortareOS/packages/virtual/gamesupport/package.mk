# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2023 JELOS (https://github.com/JustEnoughLinuxOS)

PKG_NAME="gamesupport"
PKG_LICENSE="GPLv2"
PKG_SITE="https://rocknix.org"
PKG_SECTION="virtual"
PKG_LONGDESC="Game support software metapackage."

# The SDL test apps (jstest-sdl, sdljoytest, sdltouchtest) went with
# EmulationStation, whose Tools menu was the only way to start them.
# gamepad-tester covers the same ground and is in the launcher's Tools.
# sdl2text is back as the game guide reader RetroArch runs on its hotkey.
PKG_GAMESUPPORT="sixaxis portareos-hotkey gamecontrollerdb control-gen sdl2text"

case ${DEVICE} in
  RK3326|S922X|SM6115|SM8250|SM8550|SM8650|SM8750)
    PKG_GAMESUPPORT+=" mangohud"
    ;;
esac


PKG_DEPENDS_TARGET="${PKG_GAMESUPPORT}"

