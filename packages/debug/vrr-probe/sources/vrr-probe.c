// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)
//
// vrr-probe: can the Nova's panel take a variable refresh?
//
// Static phases 0-6 set modes with the preferred mode's pixel clock and a
// longer vertical front porch, 119.88 down to 60 Hz, through ordinary mode
// setting, and flip every frame. They show whether the panel follows a
// stretched blank at all.
//
// Dynamic phases 7-14 run on the fastest mode and commit frames on a
// schedule inside 100-120 Hz, the range an integer multiple of a 50-60 Hz
// console needs: 120, 119.652 (2 x 59.826), 110 and 100 Hz, frame lengths
// alternating between 100 and 120 Hz, random lengths from 8.34 to 10 ms, a
// game whose frames take 16.7 to 20 ms shown twice in equal halves, and
// 119.652 Hz with every 20th game frame 2 ms late. On a fixed refresh a
// frame can only start on the panel's grid. With the kernel's AVR on
// (msm.dpu_avr_min_fps), each commit ends the held front porch, so frames
// should start on the schedule instead.
//
// The screen shows the phase in big digits and the target rate next to it
// (0 for a pattern), six dark grey patches, where OLED flicker shows first,
// and a bar moving 8 px per frame. Every flip completion is written out
// against CLOCK_MONOTONIC: f = read by us, F = the kernel's vblank
// timestamp, S = scheduled, C = committed, M/m = mode set start and end.
//
// Variable refresh is the CRTC's VRR_ENABLED, on a connector whose
// vrr_capable is set; "vrr" as the fourth argument sets it for the dynamic
// and idle phases, and it is cleared on the way out. The dynamic phases
// start with a real mode set: a stretched mode, then the fastest one.
// "reset" clears VRR_ENABLED and does only the mode set. "idle" sets the
// fastest mode, commits once, and then commits nothing for SECONDS, so the
// frame rate shows whether AVR holds the front porch.
//
// "fast" sets modes above the fastest one, 121 and 122 Hz (phases 15 to 17,
// the first being the fastest mode itself): its pixel clock and front porch,
// with a shorter back porch.
//
// "vrr-on" and "vrr-off" only set the CRTC's VRR_ENABLED and leave it, for
// a program started afterwards, such as a Vulkan client of the KHR display
// path, which reads it when it takes the display.
//
// "custom CLOCK,HFP,HSYNC,HBP,VFP,VSYNC,VBP RATE" sets that 1280x960 mode,
// pixel clock in kHz, porches and syncs in pixels and lines, and commits a
// frame every 1/RATE s for SECONDS, VRR_ENABLED with "vrr". "bar=PX" draws
// a full-height bar, 64 px wide, moving PX a frame, for watching a panel
// tear (tools/tear-tap); without it the usual 8 px strip moves. The timing
// the panel is given, not only the ones the kernel lists (#623).
//
// usage: vrr-probe [OUT.csv] [SECONDS] [static|dynamic|all|reset|idle|fast|vrr-on|vrr-off] [vrr]
//        vrr-probe OUT.csv SECONDS custom CLOCK,HFP,HSYNC,HBP,VFP,VSYNC,VBP RATE [vrr] [bar=PX]

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <drm/drm.h>
#include <drm/drm_mode.h>

#define W 1280
#define H 960

struct buf { uint32_t handle, pitch, fb; uint64_t size; uint32_t *map; };
struct rec { uint64_t t; uint8_t phase; char kind; };

static volatile sig_atomic_t stop;
static int drm_fd = -1;
static uint32_t crtc_id, conn_id;
static struct buf bufs[2];
static int cur, barx, bar_step;
static struct rec *recs;
static size_t nrecs;
static const size_t maxrecs = 600000;

static void on_signal(int s) { (void)s; stop = 1; }

static uint64_t now_ns(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint64_t)ts.tv_sec * 1000000000ull + ts.tv_nsec;
}

// Sleeps to 1.5 ms before t and spins the rest: waking from deep idle
// takes about 0.7 ms here, and under variable refresh a commit's lateness
// is on the panel as it is.
static void sleep_until(uint64_t t)
{
	uint64_t wake = t > 1500000 ? t - 1500000 : 0;
	struct timespec ts = { (time_t)(wake / 1000000000ull), (long)(wake % 1000000000ull) };
	while (clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &ts, NULL) == EINTR && !stop)
		;
	while (!stop && now_ns() < t)
		;
}

static void add(uint8_t phase, char kind, uint64_t t)
{
	if (nrecs < maxrecs)
		recs[nrecs++] = (struct rec){ t, phase, kind };
}

static int xioctl(int fd, unsigned long req, void *arg)
{
	int r;
	do r = ioctl(fd, req, arg); while (r == -1 && errno == EINTR);
	return r;
}

static int make_buf(struct buf *b)
{
	struct drm_mode_create_dumb cd = { .width = W, .height = H, .bpp = 32 };
	if (xioctl(drm_fd, DRM_IOCTL_MODE_CREATE_DUMB, &cd)) return -1;
	b->handle = cd.handle; b->pitch = cd.pitch; b->size = cd.size;
	struct drm_mode_fb_cmd fc = { .width = W, .height = H, .pitch = cd.pitch,
				      .bpp = 32, .depth = 24, .handle = cd.handle };
	if (xioctl(drm_fd, DRM_IOCTL_MODE_ADDFB, &fc)) return -1;
	b->fb = fc.fb_id;
	struct drm_mode_map_dumb md = { .handle = cd.handle };
	if (xioctl(drm_fd, DRM_IOCTL_MODE_MAP_DUMB, &md)) return -1;
	b->map = mmap(NULL, cd.size, PROT_READ | PROT_WRITE, MAP_SHARED, drm_fd, md.offset);
	return b->map == MAP_FAILED ? -1 : 0;
}

static void rect(struct buf *b, int x, int y, int w, int h, uint32_t c)
{
	for (int j = y; j < y + h && j < H; j++) {
		uint32_t *row = (uint32_t *)((uint8_t *)b->map + (size_t)j * b->pitch);
		for (int i = x; i < x + w && i < W; i++)
			row[i] = c;
	}
}

// Seven segments: a top, b top right, c bottom right, d bottom, e bottom
// left, f top left, g middle.
static void digit(struct buf *b, int x, int y, int d, uint32_t c)
{
	static const uint8_t seg[10] = { 0x3f, 0x06, 0x5b, 0x4f, 0x66, 0x6d, 0x7d, 0x07, 0x7f, 0x6f };
	const int L = 70, T = 14;
	uint8_t s = seg[d % 10];
	if (s & 0x01) rect(b, x + T, y, L, T, c);
	if (s & 0x02) rect(b, x + T + L, y + T, T, L, c);
	if (s & 0x04) rect(b, x + T + L, y + 2 * T + L, T, L, c);
	if (s & 0x08) rect(b, x + T, y + 2 * T + 2 * L, L, T, c);
	if (s & 0x10) rect(b, x, y + 2 * T + L, T, L, c);
	if (s & 0x20) rect(b, x, y + T, T, L, c);
	if (s & 0x40) rect(b, x + T, y + T + L, L, T, c);
}

static uint32_t grey(int v) { return 0xff000000u | (v << 16) | (v << 8) | v; }

static void number(struct buf *b, int x, int y, int n, uint32_t c)
{
	char s[8];
	snprintf(s, sizeof s, "%d", n);
	for (int i = 0; s[i]; i++, x += 120)
		digit(b, x, y, s[i] - '0', c);
}

static void paint(struct buf *b, int phase, int hz)
{
	static const int levels[] = { 4, 8, 16, 32, 64, 128 };
	rect(b, 0, 0, W, H, grey(40));
	number(b, 60, 60, phase, grey(255));
	number(b, 400, 60, hz, grey(160));
	for (int i = 0; i < 6; i++)
		rect(b, 60 + i * 200, 400, 170, 300, grey(levels[i]));
}

static int set_mode(struct buf *b, struct drm_mode_modeinfo *m)
{
	struct drm_mode_crtc s = { 0 };
	s.crtc_id = crtc_id;
	s.fb_id = b->fb;
	s.set_connectors_ptr = (uintptr_t)&conn_id;
	s.count_connectors = 1;
	s.mode = *m;
	s.mode_valid = 1;
	return xioctl(drm_fd, DRM_IOCTL_MODE_SETCRTC, &s);
}

static struct drm_mode_modeinfo stretched(const struct drm_mode_modeinfo *base, int vtotal)
{
	struct drm_mode_modeinfo m = *base;
	int vsw = base->vsync_end - base->vsync_start;
	int vbp = base->vtotal - base->vsync_end;
	int vfp = vtotal - base->vdisplay - vsw - vbp;
	m.vsync_start = base->vdisplay + vfp;
	m.vsync_end = m.vsync_start + vsw;
	m.vtotal = vtotal;
	m.vrefresh = (uint32_t)((uint64_t)base->clock * 1000 / ((uint64_t)base->htotal * vtotal));
	m.type = DRM_MODE_TYPE_USERDEF;
	snprintf(m.name, sizeof m.name, "%ux%u-v%d", m.hdisplay, m.vdisplay, vtotal);
	return m;
}

static double mode_hz(const struct drm_mode_modeinfo *m)
{
	return m->clock * 1000.0 / ((double)m->htotal * m->vtotal);
}

// The same mode with a shorter or longer vertical back porch.
static struct drm_mode_modeinfo backporch(const struct drm_mode_modeinfo *base, int vtotal)
{
	struct drm_mode_modeinfo m = *base;
	m.vtotal = vtotal;
	m.vrefresh = (uint32_t)((uint64_t)base->clock * 1000 / ((uint64_t)base->htotal * vtotal));
	m.type = DRM_MODE_TYPE_USERDEF;
	snprintf(m.name, sizeof m.name, "%ux%u-b%d", m.hdisplay, m.vdisplay, vtotal);
	return m;
}

static int find_display(struct drm_mode_modeinfo *base, struct drm_mode_modeinfo *fast)
{
	struct drm_mode_card_res res = { 0 };
	if (xioctl(drm_fd, DRM_IOCTL_MODE_GETRESOURCES, &res)) return -1;
	uint32_t *crtcs = calloc(res.count_crtcs + 1, 4);
	uint32_t *conns = calloc(res.count_connectors + 1, 4);
	uint32_t *encs = calloc(res.count_encoders + 1, 4);
	uint32_t *fbs = calloc(res.count_fbs + 1, 4);
	res.crtc_id_ptr = (uintptr_t)crtcs;
	res.connector_id_ptr = (uintptr_t)conns;
	res.encoder_id_ptr = (uintptr_t)encs;
	res.fb_id_ptr = (uintptr_t)fbs;
	if (xioctl(drm_fd, DRM_IOCTL_MODE_GETRESOURCES, &res)) return -1;
	for (uint32_t i = 0; i < res.count_connectors; i++) {
		struct drm_mode_get_connector c = { .connector_id = conns[i] };
		if (xioctl(drm_fd, DRM_IOCTL_MODE_GETCONNECTOR, &c)) continue;
		if (c.connection != 1 || !c.count_modes) continue;
		struct drm_mode_modeinfo *modes = calloc(c.count_modes, sizeof *modes);
		struct drm_mode_get_connector c2 = { .connector_id = conns[i],
			.count_modes = c.count_modes, .modes_ptr = (uintptr_t)modes };
		if (xioctl(drm_fd, DRM_IOCTL_MODE_GETCONNECTOR, &c2)) continue;
		*base = *fast = modes[0];
		for (uint32_t k = 0; k < c2.count_modes; k++) {
			if (modes[k].type & DRM_MODE_TYPE_PREFERRED) *base = modes[k];
			if (mode_hz(&modes[k]) > mode_hz(fast)) *fast = modes[k];
		}
		conn_id = conns[i];
		struct drm_mode_get_encoder e = { .encoder_id = c2.encoder_id };
		crtc_id = (c2.encoder_id && !xioctl(drm_fd, DRM_IOCTL_MODE_GETENCODER, &e) && e.crtc_id)
			  ? e.crtc_id : crtcs[0];
		return 0;
	}
	return -1;
}

// A property of a DRM object by name: its id, and its value in *value.
static uint32_t find_prop(uint32_t obj_id, uint32_t obj_type, const char *name, uint64_t *value)
{
	struct drm_mode_obj_get_properties gp = { .obj_id = obj_id, .obj_type = obj_type };
	if (xioctl(drm_fd, DRM_IOCTL_MODE_OBJ_GETPROPERTIES, &gp) || !gp.count_props)
		return 0;
	uint32_t *ids = calloc(gp.count_props, sizeof *ids);
	uint64_t *vals = calloc(gp.count_props, sizeof *vals);
	gp.props_ptr = (uintptr_t)ids;
	gp.prop_values_ptr = (uintptr_t)vals;
	uint32_t found = 0;
	if (!xioctl(drm_fd, DRM_IOCTL_MODE_OBJ_GETPROPERTIES, &gp)) {
		for (uint32_t i = 0; i < gp.count_props && !found; i++) {
			struct drm_mode_get_property pr = { .prop_id = ids[i] };
			if (!xioctl(drm_fd, DRM_IOCTL_MODE_GETPROPERTY, &pr) && !strcmp(pr.name, name)) {
				found = ids[i];
				if (value) *value = vals[i];
			}
		}
	}
	free(ids);
	free(vals);
	return found;
}

static int set_vrr(int on)
{
	uint32_t id = find_prop(crtc_id, DRM_MODE_OBJECT_CRTC, "VRR_ENABLED", NULL);
	if (!id) {
		fprintf(stderr, "the CRTC has no VRR_ENABLED\n");
		return -1;
	}
	struct drm_mode_obj_set_property sp = { .value = (uint64_t)on, .prop_id = id,
		.obj_id = crtc_id, .obj_type = DRM_MODE_OBJECT_CRTC };
	if (xioctl(drm_fd, DRM_IOCTL_MODE_OBJ_SETPROPERTY, &sp)) {
		perror("VRR_ENABLED");
		return -1;
	}
	return 0;
}

// Wait up to timeout_ms for flip completions; returns how many arrived.
static int wait_flips(uint8_t phase, int timeout_ms)
{
	struct pollfd p = { drm_fd, POLLIN, 0 };
	if (poll(&p, 1, timeout_ms) <= 0 || !(p.revents & POLLIN))
		return 0;
	char ebuf[1024];
	uint64_t t = now_ns();
	ssize_t n = read(drm_fd, ebuf, sizeof ebuf);
	int done = 0;
	for (ssize_t off = 0; off + (ssize_t)sizeof(struct drm_event) <= n;) {
		struct drm_event *e = (struct drm_event *)(ebuf + off);
		if (e->type == DRM_EVENT_FLIP_COMPLETE) {
			struct drm_event_vblank *v = (struct drm_event_vblank *)e;
			add(phase, 'F', (uint64_t)v->tv_sec * 1000000000ull + v->tv_usec * 1000ull);
			add(phase, 'f', t);
			done++;
		}
		off += e->length;
	}
	return done;
}

static int flip(uint8_t phase)
{
	struct buf *b = &bufs[cur ^ 1];
	if (bar_step) {
		rect(b, 0, 0, W, H, grey(40));
		rect(b, barx, 0, 64, H, grey(255));
		barx = (barx + bar_step) % (W - 64);
	} else {
		rect(b, 0, 860, W, 60, grey(40));
		rect(b, barx, 860, 24, 60, grey(255));
		barx = (barx + 8) % (W - 24);
	}
	struct drm_mode_crtc_page_flip pf = { .crtc_id = crtc_id, .fb_id = b->fb,
		.flags = DRM_MODE_PAGE_FLIP_EVENT, .user_data = phase };
	if (xioctl(drm_fd, DRM_IOCTL_MODE_PAGE_FLIP, &pf))
		return -1;
	add(phase, 'C', now_ns());
	cur ^= 1;
	return 0;
}

// Static phases: flip as soon as the last flip completed.
static int run_free(uint8_t phase, double secs)
{
	uint64_t end = now_ns() + (uint64_t)(secs * 1e9);
	int flips = 0;
	while (!stop && now_ns() < end) {
		if (flip(phase)) { perror("page flip"); return -1; }
		while (!stop && !wait_flips(phase, 200))
			;
		flips++;
	}
	return flips;
}

static uint64_t rng = 0x9e3779b97f4a7c15ull;
static uint64_t next_rand(void)
{
	rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17;
	return rng;
}

// Refresh length in ns for dynamic pattern k, refresh n.
static uint64_t interval(int k, unsigned n)
{
	static uint64_t game;
	switch (k) {
	case 0: return 8333333;                           /* 120 Hz */
	case 1: return 8357510;                           /* 2 x 59.826105 Hz */
	case 2: return 9090909;                           /* 110 Hz */
	case 3: return 10000000;                          /* 100 Hz */
	case 4: return (n & 1) ? 8333333 : 10000000;      /* 100 / 120 alternating */
	case 5: return 8340000 + next_rand() % 1660001;   /* 8.34 to 10 ms */
	case 6:                                           /* game frames 16.7-20 ms, twice */
		if (!(n & 1)) game = 16680000 + next_rand() % 3320001;
		return game / 2;
	default:                                          /* 2 x 59.826, a late game frame */
		return 8357510 + (n % 40 == 39 ? 2000000 : 0);
	}
}

// Dynamic phases: commit on a schedule.
static int run_scheduled(uint8_t phase, int k, double secs)
{
	uint64_t start = now_ns() + 50000000ull, t = start;
	uint64_t end = start + (uint64_t)(secs * 1e9);
	int pending = 0, flips = 0, late = 0;
	for (unsigned n = 0; !stop && t < end; n++) {
		// Collect completions while waiting for the slot.
		while (pending && now_ns() + 1000000 < t) {
			int ms = (int)((t - now_ns()) / 1000000) - 1;
			pending -= wait_flips(phase, ms > 0 ? ms : 0);
		}
		sleep_until(t);
		if (pending) {
			late++;
			while (!stop && pending)
				pending -= wait_flips(phase, 100);
		}
		add(phase, 'S', t);
		if (flip(phase)) { perror("page flip"); return -1; }
		pending = 1;
		flips++;
		t += interval(k, n);
	}
	while (!stop && pending)
		pending -= wait_flips(phase, 100);
	if (late)
		printf("    %d commits waited for the previous frame\n", late);
	return flips;
}

// A frame every 1/rate s on the mode just set, as a game would commit.
static int run_rate(uint8_t phase, double rate, double secs)
{
	uint64_t period = (uint64_t)(1e9 / rate + 0.5);
	uint64_t t = now_ns() + 50000000ull, end = t + (uint64_t)(secs * 1e9);
	int pending = 0, flips = 0, late = 0;
	while (!stop && t < end) {
		while (pending && now_ns() + 1000000 < t) {
			int ms = (int)((t - now_ns()) / 1000000) - 1;
			pending -= wait_flips(phase, ms > 0 ? ms : 0);
		}
		sleep_until(t);
		if (pending) {
			late++;
			while (!stop && pending)
				pending -= wait_flips(phase, 100);
		}
		add(phase, 'S', t);
		if (flip(phase)) { perror("page flip"); return -1; }
		pending = 1;
		flips++;
		t += period;
	}
	while (!stop && pending)
		pending -= wait_flips(phase, 100);
	if (late)
		printf("    %d commits waited for the previous frame\n", late);
	return flips;
}

int main(int argc, char **argv)
{
	const char *out = argc > 1 ? argv[1] : "/storage/vrr-probe.csv";
	double secs = argc > 2 ? atof(argv[2]) : 6.0;
	const char *which = argc > 3 ? argv[3] : "all";
	int do_reset = strcmp(which, "reset") == 0;
	int do_idle = strcmp(which, "idle") == 0;
	int do_fast = strcmp(which, "fast") == 0;
	int do_static = !do_reset && !do_idle && !do_fast && strcmp(which, "dynamic") != 0;
	int do_dynamic = !do_reset && !do_idle && !do_fast && strcmp(which, "static") != 0;
	int vrr = argc > 4 && !strcmp(argv[4], "vrr");
	static const int targets[] = { 0, 110, 100, 90, 80, 72, 60 };
	static const int dyn_hz[] = { 120, 119, 110, 100, 0, 0, 0, 119 };

	signal(SIGINT, on_signal);
	signal(SIGTERM, on_signal);
	recs = calloc(maxrecs, sizeof *recs);

	drm_fd = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
	if (drm_fd < 0) { perror("card0"); return 1; }
	struct drm_mode_modeinfo base, fast;
	if (find_display(&base, &fast)) { fprintf(stderr, "no connected display\n"); return 1; }
	int base_hz = (int)(base.clock * 1000.0 / (base.htotal * base.vtotal) + 0.5);
	printf("base mode %s: clock %u htotal %u vtotal %u, connector %u crtc %u\n",
	       base.name, base.clock, base.htotal, base.vtotal, conn_id, crtc_id);
	if (make_buf(&bufs[0]) || make_buf(&bufs[1])) { perror("dumb buffer"); return 1; }
	uint64_t capable = 0;
	if (find_prop(conn_id, DRM_MODE_OBJECT_CONNECTOR, "vrr_capable", &capable))
		printf("connector vrr_capable %llu\n", (unsigned long long)capable);
	else
		printf("connector has no vrr_capable\n");
	if (!strcmp(which, "vrr-on") || !strcmp(which, "vrr-off")) {
		uint64_t v = 0;
		if (set_vrr(!strcmp(which, "vrr-on")))
			return 1;
		find_prop(crtc_id, DRM_MODE_OBJECT_CRTC, "VRR_ENABLED", &v);
		printf("VRR_ENABLED %llu\n", (unsigned long long)v);
		return 0;
	}
	if (!strcmp(which, "custom")) {
		struct drm_mode_modeinfo m = base;
		unsigned clock, hfp, hsw, hbp, vfp, vsw, vbp;
		double rate = argc > 5 ? atof(argv[5]) : 0;
		int cvrr = 0;
		for (int i = 6; i < argc; i++) {
			if (!strcmp(argv[i], "vrr")) cvrr = 1;
			else if (!strncmp(argv[i], "bar=", 4)) bar_step = atoi(argv[i] + 4);
		}
		if (argc < 6 || rate <= 0 || sscanf(argv[4], "%u,%u,%u,%u,%u,%u,%u",
				&clock, &hfp, &hsw, &hbp, &vfp, &vsw, &vbp) != 7) {
			fprintf(stderr, "custom CLOCK,HFP,HSYNC,HBP,VFP,VSYNC,VBP RATE [vrr] [bar=PX]\n");
			return 2;
		}
		m.clock = clock;
		m.hsync_start = W + hfp; m.hsync_end = m.hsync_start + hsw; m.htotal = m.hsync_end + hbp;
		m.vsync_start = H + vfp; m.vsync_end = m.vsync_start + vsw; m.vtotal = m.vsync_end + vbp;
		m.vrefresh = (uint32_t)(mode_hz(&m) + 0.5);
		m.type = DRM_MODE_TYPE_USERDEF;
		snprintf(m.name, sizeof m.name, "%ux%u-%u-%u", m.hdisplay, m.vdisplay, m.htotal, m.vtotal);
		set_vrr(0);
		paint(&bufs[0], 20, (int)(rate + 0.5));
		paint(&bufs[1], 20, (int)(rate + 0.5));
		add(20, 'M', now_ns());
		if (set_mode(&bufs[cur], &m)) {
			printf("custom: %.4f Hz, %ux%u: mode set FAILED: %s\n", mode_hz(&m), m.htotal, m.vtotal, strerror(errno));
			return 1;
		}
		add(20, 'm', now_ns());
		if (cvrr && set_vrr(1) == 0)
			printf("VRR_ENABLED 1\n");
		printf("custom: %.4f Hz, clock %u, htotal %u, vtotal %u (vfp %u vsync %u vbp %u), frames at %.4f Hz%s\n",
		       mode_hz(&m), m.clock, m.htotal, m.vtotal, vfp, vsw, vbp, rate, cvrr ? ", variable refresh" : "");
		fflush(stdout);
		usleep(300000);
		int n = run_rate(20, rate, secs);
		printf("custom: %d frames in %.1f s\n", n, secs);
		do_static = do_dynamic = do_fast = 0;
		vrr = cvrr;
		do_idle = do_reset = 0;
	}
	if (!vrr || do_reset)
		set_vrr(0);

	for (size_t i = 0; do_static && i < sizeof targets / sizeof targets[0] && !stop; i++) {
		struct drm_mode_modeinfo m = base;
		int hz = base_hz;
		if (targets[i]) {
			m = stretched(&base, (int)(base.clock * 1000.0 / (base.htotal * (double)targets[i]) + 0.5));
			hz = targets[i];
		}
		paint(&bufs[0], (int)i, hz);
		paint(&bufs[1], (int)i, hz);
		add((uint8_t)i, 'M', now_ns());
		if (set_mode(&bufs[cur], &m)) {
			printf("phase %zu: %d Hz, vtotal %u: mode set FAILED: %s\n", i, hz, m.vtotal, strerror(errno));
			continue;
		}
		add((uint8_t)i, 'm', now_ns());
		usleep(300000);
		int n = run_free((uint8_t)i, secs);
		printf("phase %zu: %d Hz, vtotal %u, vfp %u: %d flips in %.1f s\n",
		       i, hz, m.vtotal, m.vsync_start - m.vdisplay, n, secs);
		fflush(stdout);
	}

	static const double fast_targets[] = { 0, 121.0, 122.0 };
	for (size_t i = 0; do_fast && i < sizeof fast_targets / sizeof fast_targets[0] && !stop; i++) {
		struct drm_mode_modeinfo m = fast;
		if (fast_targets[i] > 0)
			m = backporch(&fast, (int)(fast.clock * 1000.0 / (fast.htotal * fast_targets[i]) + 0.5));
		uint8_t phase = (uint8_t)(15 + i);
		int hz = (int)(mode_hz(&m) + 0.5);
		paint(&bufs[0], phase, hz);
		paint(&bufs[1], phase, hz);
		add(phase, 'M', now_ns());
		if (set_mode(&bufs[cur], &m)) {
			printf("phase %u: %.3f Hz, vtotal %u: mode set FAILED: %s\n", phase, mode_hz(&m), m.vtotal, strerror(errno));
			continue;
		}
		add(phase, 'm', now_ns());
		usleep(300000);
		int n = run_free(phase, secs);
		printf("phase %u: %.3f Hz, clock %u, vtotal %u, vfp %u, vbp %u: %d flips in %.1f s\n",
		       phase, mode_hz(&m), m.clock, m.vtotal, m.vsync_start - m.vdisplay,
		       m.vtotal - m.vsync_end, n, secs);
		fflush(stdout);
	}

	if ((do_dynamic || do_reset || do_idle) && !stop) {
		struct drm_mode_modeinfo other = stretched(&base, base.vtotal + 90);
		struct drm_mode_modeinfo *dyn = do_reset ? &base : &fast;
		paint(&bufs[0], 7, dyn_hz[0]);
		paint(&bufs[1], 7, dyn_hz[0]);
		if (set_mode(&bufs[cur], &other) || set_mode(&bufs[cur], dyn)) {
			perror("mode set"); return 1;
		}
		if (do_reset) { printf("mode set again, VRR_ENABLED 0\n"); return 0; }
		if (vrr && set_vrr(1) == 0)
			printf("VRR_ENABLED 1\n");
		usleep(300000);
		if (do_idle) {
			if (flip(7)) { perror("page flip"); return 1; }
			while (!stop && !wait_flips(7, 200))
				;
			printf("%s, %.3f Hz: one commit, then idle for %.0f s\n", fast.name, mode_hz(&fast), secs);
			fflush(stdout);
			uint64_t end = now_ns() + (uint64_t)(secs * 1e9);
			while (!stop && now_ns() < end)
				usleep(100000);
			do_dynamic = 0;
		}
		if (do_dynamic)
			printf("dynamic phases on %s, %.3f Hz, vtotal %u\n", fast.name, mode_hz(&fast), fast.vtotal);
		static const char *names[] = { "120 Hz", "119.652 Hz", "110 Hz", "100 Hz",
					       "100/120 alternating", "random 8.34-10 ms",
					       "game 16.7-20 ms, each frame twice",
					       "119.652 Hz, every 20th game frame 2 ms late" };
		for (int k = 0; do_dynamic && k < 8 && !stop; k++) {
			uint8_t phase = (uint8_t)(7 + k);
			paint(&bufs[0], phase, dyn_hz[k]);
			paint(&bufs[1], phase, dyn_hz[k]);
			int n = run_scheduled(phase, k, secs);
			printf("phase %u: %s: %d frames in %.1f s\n", phase, names[k], n, secs);
			fflush(stdout);
		}
	}

	if (vrr)
		set_vrr(0);
	paint(&bufs[cur], 0, base_hz);
	if (set_mode(&bufs[cur], &base)) perror("restoring the base mode");

	FILE *f = fopen(out, "w");
	if (!f) { perror(out); return 1; }
	fprintf(f, "phase,kind,t_ns\n");
	for (size_t i = 0; i < nrecs; i++)
		fprintf(f, "%u,%c,%llu\n", recs[i].phase, recs[i].kind, (unsigned long long)recs[i].t);
	fclose(f);
	printf("%zu records to %s\n", nrecs, out);
	return 0;
}
