#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024 ROCKNIX (https://github.com/ROCKNIX)

source /etc/profile

set_kill set "gamepad-tester"

# How to get out used to be flashed by sdl2notify before the tester started.
# It is in this tool's gamelist.xml description now, which the launcher
# shows beside the entry - before it is launched, when it can still be read.
/usr/bin/gamepad-tester
