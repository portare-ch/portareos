# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

# libdrm's headers are under a subdirectory, so the include path has to come
# from pkg-config rather than the sysroot default.
DRM_CFLAGS ?= $(shell pkg-config --cflags libdrm)
DRM_LIBS ?= $(shell pkg-config --libs libdrm)

BINARY = tear-test

all:
	$(CC) $(CFLAGS) $(DRM_CFLAGS) -Wall -Wextra -O2 tear-test.c -o $(BINARY) $(LDFLAGS) $(DRM_LIBS)
