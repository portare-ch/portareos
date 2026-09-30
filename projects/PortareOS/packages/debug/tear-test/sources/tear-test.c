// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)
//
// tear-test: count torn frames, rather than looking for them.
//
// Shows two frames that differ - A light on top, B light on the bottom -
// flips between them once per vblank, and reads the DPU's per-frame CRC back
// out of debugfs. A pipeline that never tears produces a CRC equal to A's or
// to B's and nothing else. A frame assembled from part of one and part of the
// other hashes to a third value, and that is what this counts.
//
// The CRC is taken where the DPU hands pixels to the DSI, which is the useful
// limitation: a tear this tool cannot see is downstream of that point, in the
// link or in the panel controller, and a clean count next to a tear somebody
// can see localises the fault to there and nowhere else.
//
// --async flips without waiting for vblank, to tear on purpose. A run that
// reports torn frames there and none without it is a detector known to work;
// if the driver refuses async flips the count still means what it says, but
// its sensitivity is untested and the tool says so.

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#include <xf86drm.h>
#include <xf86drmMode.h>
#include <drm_mode.h>

#define MAX_CRC_LINE 128

struct fb {
	uint32_t handle, fb_id, pitch;
	uint64_t size;
	uint8_t *map;
};

static int dumb_fb(int fd, uint32_t w, uint32_t h, struct fb *out)
{
	struct drm_mode_create_dumb creq = { .width = w, .height = h, .bpp = 32 };
	struct drm_mode_map_dumb mreq = { 0 };

	if (drmIoctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &creq))
		return -errno;
	out->handle = creq.handle;
	out->pitch = creq.pitch;
	out->size = creq.size;

	if (drmModeAddFB(fd, w, h, 24, 32, creq.pitch, creq.handle, &out->fb_id))
		return -errno;

	mreq.handle = creq.handle;
	if (drmIoctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &mreq))
		return -errno;
	out->map = mmap(NULL, creq.size, PROT_READ | PROT_WRITE, MAP_SHARED,
			fd, mreq.offset);
	if (out->map == MAP_FAILED)
		return -errno;
	return 0;
}

// stripes == 0 splits the screen in half, which is enough: a tear at any
// scanline but the very first or last leaves a frame that matches neither
// source. Finer stripes make a tear near an edge visible to the CRC too.
static void paint(struct fb *f, uint32_t w, uint32_t h, int stripes, bool invert)
{
	for (uint32_t y = 0; y < h; y++) {
		bool light = stripes > 0 ? ((y / stripes) & 1) : (y < h / 2);
		if (invert)
			light = !light;
		uint32_t px = light ? 0x00ffffff : 0x00000000;
		uint32_t *row = (uint32_t *)(f->map + (uint64_t)y * f->pitch);
		for (uint32_t x = 0; x < w; x++)
			row[x] = px;
	}
}

// The CRC directory is per CRTC and named by index, not by id, so find the
// one whose status names the CRTC being driven.
static int open_crc(int card, uint32_t crtc_id, char *ctl_out, size_t n)
{
	for (int i = 0; i < 8; i++) {
		char p[256];
		FILE *s;
		unsigned id = 0;

		snprintf(p, sizeof(p), "/sys/kernel/debug/dri/%d/crtc-%d/status", card, i);
		s = fopen(p, "r");
		if (!s)
			continue;
		if (fscanf(s, "crtc:%u", &id) != 1)
			id = 0;
		fclose(s);
		if (id != crtc_id)
			continue;

		snprintf(ctl_out, n, "/sys/kernel/debug/dri/%d/crtc-%d/crc/control", card, i);
		snprintf(p, sizeof(p), "/sys/kernel/debug/dri/%d/crtc-%d/crc/data", card, i);
		return open(p, O_RDONLY);
	}
	return -ENOENT;
}

// One entry per read. debugfs pads with a NUL, so trim on anything unprintable.
static int read_crc(int fd, unsigned long *seq, char *key, size_t keylen)
{
	char buf[MAX_CRC_LINE];
	ssize_t n = read(fd, buf, sizeof(buf) - 1);
	char *p;

	if (n <= 0)
		return -1;
	buf[n] = 0;
	for (p = buf; *p; p++)
		if (*p < 0x20)
			*p = 0;
	p = buf;
	while (*p == ' ')
		p++;
	if (sscanf(p, "%lx", seq) != 1)
		return -1;
	p = strchr(p, ' ');
	if (!p)
		return -1;
	while (*p == ' ')
		p++;
	snprintf(key, keylen, "%s", p);
	return 0;
}

static void flip_done(int fd, unsigned f, unsigned s, unsigned u, void *d)
{
	(void)fd; (void)f; (void)s; (void)u;
	*(int *)d = 0;
}

static void usage(const char *me)
{
	fprintf(stderr,
		"usage: %s [--card N] [--rate HZ] [--frames N] [--stripes N] [--async]\n"
		"  --rate     pick the mode with this refresh, else the current one\n"
		"  --frames   how many flips to measure (default 1200, ~10s at 120Hz)\n"
		"  --stripes  stripe height in lines, 0 = split in half (default 0)\n"
		"  --async    flip without waiting for vblank, to tear on purpose\n",
		me);
}

int main(int argc, char **argv)
{
	int card = 0, frames = 1200, stripes = 0;
	double want_rate = 0;
	bool async = false;
	char path[64], ctl[256];
	int fd, crcfd;
	drmModeRes *res = NULL;
	drmModeConnector *conn = NULL;
	drmModeCrtc *saved = NULL;
	drmModeModeInfo mode;
	bool have_mode = false;
	struct fb fb[2] = { 0 };
	unsigned long torn = 0, gaps = 0, matched[2] = { 0, 0 }, counted = 0;
	unsigned long first_seq = 0, last_seq = 0;
	char key_a[MAX_CRC_LINE] = "", key_b[MAX_CRC_LINE] = "";

	for (int i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--card") && i + 1 < argc)
			card = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--rate") && i + 1 < argc)
			want_rate = atof(argv[++i]);
		else if (!strcmp(argv[i], "--frames") && i + 1 < argc)
			frames = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--stripes") && i + 1 < argc)
			stripes = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--async"))
			async = true;
		else if (!strcmp(argv[i], "--help") || !strcmp(argv[i], "-h")) {
			usage(argv[0]);
			return 0;
		} else {
			usage(argv[0]);
			return 2;
		}
	}

	snprintf(path, sizeof(path), "/dev/dri/card%d", card);
	fd = open(path, O_RDWR | O_CLOEXEC);
	if (fd < 0) {
		fprintf(stderr, "%s: %s\n", path, strerror(errno));
		return 1;
	}

	res = drmModeGetResources(fd);
	if (!res) {
		fprintf(stderr, "drmModeGetResources: %s\n", strerror(errno));
		return 1;
	}
	for (int i = 0; i < res->count_connectors && !conn; i++) {
		drmModeConnector *c = drmModeGetConnector(fd, res->connectors[i]);
		if (c && c->connection == DRM_MODE_CONNECTED && c->count_modes)
			conn = c;
		else if (c)
			drmModeFreeConnector(c);
	}
	if (!conn) {
		fprintf(stderr, "no connected connector with modes\n");
		return 1;
	}

	for (int i = 0; i < conn->count_modes; i++) {
		drmModeModeInfo *m = &conn->modes[i];
		double hz = m->clock * 1000.0 / ((double)m->htotal * m->vtotal);
		if (want_rate ? (hz > want_rate - 0.01 && hz < want_rate + 0.01)
			      : (m->type & DRM_MODE_TYPE_PREFERRED)) {
			mode = *m;
			have_mode = true;
			break;
		}
	}
	if (!have_mode) {
		fprintf(stderr, "no mode matching %.4f Hz; modetest -M msm -c lists them\n",
			want_rate);
		return 1;
	}

	if (drmSetMaster(fd)) {
		fprintf(stderr, "drmSetMaster: %s\n"
			"  something else owns the display. Stop the frontend first:\n"
			"    systemctl stop portarelauncher\n", strerror(errno));
		return 1;
	}

	saved = drmModeGetCrtc(fd, res->crtcs[0]);
	for (int i = 0; i < 2; i++) {
		int err = dumb_fb(fd, mode.hdisplay, mode.vdisplay, &fb[i]);
		if (err) {
			fprintf(stderr, "dumb buffer: %s\n", strerror(-err));
			return 1;
		}
		paint(&fb[i], mode.hdisplay, mode.vdisplay, stripes, i == 1);
	}

	printf("%s %ux%u @ %.6f Hz  (htotal %u, vtotal %u, %u kHz)\n",
	       conn->connector_type == DRM_MODE_CONNECTOR_DSI ? "DSI" : "connector",
	       mode.hdisplay, mode.vdisplay,
	       mode.clock * 1000.0 / ((double)mode.htotal * mode.vtotal),
	       mode.htotal, mode.vtotal, mode.clock);

	if (drmModeSetCrtc(fd, res->crtcs[0], fb[0].fb_id, 0, 0,
			   &conn->connector_id, 1, &mode)) {
		fprintf(stderr, "drmModeSetCrtc: %s\n", strerror(errno));
		return 1;
	}

	crcfd = open_crc(card, res->crtcs[0], ctl, sizeof(ctl));
	if (crcfd < 0) {
		fprintf(stderr, "no CRC interface for this CRTC: %s\n"
			"  needs debugfs mounted and CONFIG_DEBUG_FS\n",
			strerror(-crcfd));
		return 1;
	}
	{
		int c = open(ctl, O_WRONLY);
		if (c < 0 || write(c, "auto", 4) != 4) {
			fprintf(stderr, "enabling CRC capture: %s\n", strerror(errno));
			return 1;
		}
		close(c);
	}

	// Learn each frame's CRC from the hardware rather than computing it:
	// whatever the DPU hashes, including any fixed transform in the path,
	// is then the reference.
	for (int which = 0; which < 2; which++) {
		unsigned long seq;
		char key[MAX_CRC_LINE];
		int settle = 4;

		if (drmModeSetCrtc(fd, res->crtcs[0], fb[which].fb_id, 0, 0,
				   &conn->connector_id, 1, &mode)) {
			fprintf(stderr, "drmModeSetCrtc: %s\n", strerror(errno));
			return 1;
		}
		while (settle-- > 0) {
			struct pollfd p = { crcfd, POLLIN, 0 };

			if (poll(&p, 1, 2000) <= 0) {
				fprintf(stderr, "no CRC arrived in 2s; is the pipe on?\n");
				return 1;
			}
			if (read_crc(crcfd, &seq, key, sizeof(key)))
				break;
		}
		snprintf(which ? key_b : key_a, MAX_CRC_LINE, "%s", key);
	}
	if (!*key_a || !*key_b || !strcmp(key_a, key_b)) {
		fprintf(stderr, "the two frames hash the same (%s); nothing to measure\n",
			key_a);
		return 1;
	}
	printf("frame A %s\nframe B %s\n\n", key_a, key_b);

	for (int i = 0; i < frames; i++) {
		int pending = 1;
		int which = i & 1;
		unsigned flags = DRM_MODE_PAGE_FLIP_EVENT |
				 (async ? DRM_MODE_PAGE_FLIP_ASYNC : 0);

		if (drmModePageFlip(fd, res->crtcs[0], fb[which].fb_id, flags, &pending)) {
			if (async && errno == EINVAL) {
				fprintf(stderr,
					"this driver refuses async page flips, so the "
					"detector cannot be proven here.\n");
				return 3;
			}
			fprintf(stderr, "page flip: %s\n", strerror(errno));
			return 1;
		}

		while (pending) {
			struct pollfd p[2] = { { fd, POLLIN, 0 }, { crcfd, POLLIN, 0 } };
			if (poll(p, 2, 1000) <= 0)
				break;
			if (p[1].revents & POLLIN) {
				unsigned long seq;
				char key[MAX_CRC_LINE];

				if (!read_crc(crcfd, &seq, key, sizeof(key))) {
					if (counted && seq != last_seq + 1)
						gaps++;
					if (!counted)
						first_seq = seq;
					last_seq = seq;
					counted++;
					if (!strcmp(key, key_a))
						matched[0]++;
					else if (!strcmp(key, key_b))
						matched[1]++;
					else
						torn++;
				}
			}
			if (p[0].revents & POLLIN) {
				drmEventContext ev = {
					.version = 2,
					.page_flip_handler = flip_done,
				};
				drmHandleEvent(fd, &ev);
			}
		}
	}

	printf("%s, %d flips\n", async ? "async flips, tearing on purpose"
					: "one flip a vblank", frames);
	printf("  frames hashed      %lu   (seq %#lx..%#lx)\n", counted, first_seq, last_seq);
	printf("  matched frame A    %lu\n", matched[0]);
	printf("  matched frame B    %lu\n", matched[1]);
	printf("  matched neither    %lu   <- torn, or a frame this tool did not draw\n", torn);
	printf("  sequence gaps      %lu   <- a frame the CRC reader missed\n", gaps);
	if (!async && !torn)
		printf("\nNo torn frame reached the DSI. A tear seen on the panel\n"
		       "after this is downstream of the DPU: the link or the panel.\n");

	if (saved)
		drmModeSetCrtc(fd, saved->crtc_id, saved->buffer_id, saved->x, saved->y,
			       &conn->connector_id, 1, &saved->mode);
	for (int i = 0; i < 2; i++) {
		struct drm_mode_destroy_dumb d = { .handle = fb[i].handle };
		if (fb[i].map)
			munmap(fb[i].map, fb[i].size);
		if (fb[i].fb_id)
			drmModeRmFB(fd, fb[i].fb_id);
		drmIoctl(fd, DRM_IOCTL_MODE_DESTROY_DUMB, &d);
	}
	close(crcfd);
	drmDropMaster(fd);
	return torn ? 1 : 0;
}
