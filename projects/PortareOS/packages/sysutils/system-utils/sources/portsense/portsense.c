// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)
//
// portsense - the Retroid Pocket Nova's buttons.
//
// Replaces the input_sense shell script, which ran an evtest per input
// device, piped them all through grep, and matched the human-readable lines
// in a bash loop. That put a text parser and several processes in the path of
// every button press, including every press during a game.
//
// What this device actually presents, which is not what the script assumed:
//
//   InputPlumber owns the gamepad. 02-retroid-pocket-nova.yaml takes the
//   rsinput-gamepad and gpio-keys nodes, hides them under
//   /dev/inputplumber/sources, and emits a DualSense Edge instead. So the
//   pad arrives as BTN_* and ABS_HAT0* on the emulated pad's event node, and
//   the physical gamepad node does not exist to be opened.
//
//   The two volume keys arrive from different devices. Volume down is on the
//   PMIC's resin node, which InputPlumber does not manage. Volume up is on
//   gpio-keys, which it does, so it comes out of InputPlumber's keyboard
//   target as KEY_VOLUMEUP.
//
//   Home emits BTN_MODE on the pad and KEY_F1 on the keyboard target, one for
//   one. Anything acting on both fires twice.
//
// None of that is hardcoded to an event number: the nodes renumber, and
// InputPlumber's targets appear after this starts. Every event device is
// opened and dispatched on the code, which is also how hotplug stays simple.

#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/epoll.h>
#include <sys/inotify.h>
#include <sys/timerfd.h>
#include <sys/wait.h>
#include <unistd.h>

#define INPUT_DIR   "/dev/input"
#define SYSTEM_CFG  "/storage/.config/system/configs/system.cfg"
#define OSD_PIPE    "/run/portarelauncher.osd"
#define MAX_FDS     64

// Repeat cadence for a held volume key, unchanged from the script.
#define REPEAT_DELAY_MS     300
#define REPEAT_INTERVAL_MS  100

static bool debug;

static void logmsg(const char *fmt, ...)
{
	va_list ap;
	if (!debug)
		return;
	va_start(ap, fmt);
	fprintf(stderr, "portsense: ");
	vfprintf(stderr, fmt, ap);
	fputc('\n', stderr);
	va_end(ap);
}

// ---------------------------------------------------------------- settings

// get_setting's single-argument lookup, in its order: system.<name>, <name>,
// then global.<name>. Read once at startup, as the script did.
static bool setting(const char *name, char *out, size_t len)
{
	char pfx[3][160], line[512];
	FILE *f;
	size_t n[3];
	int i;

	snprintf(pfx[0], sizeof(pfx[0]), "system.%s=", name);
	snprintf(pfx[1], sizeof(pfx[1]), "%s=", name);
	snprintf(pfx[2], sizeof(pfx[2]), "global.%s=", name);
	for (i = 0; i < 3; i++)
		n[i] = strlen(pfx[i]);

	for (i = 0; i < 3; i++) {
		if (!(f = fopen(SYSTEM_CFG, "re")))
			return false;
		while (fgets(line, sizeof(line), f)) {
			if (strncmp(line, pfx[i], n[i]))
				continue;
			line[strcspn(line, "\r\n")] = '\0';
			snprintf(out, len, "%s", line + n[i]);
			fclose(f);
			return out[0] != '\0';
		}
		fclose(f);
	}
	return false;
}

static void setting_str(const char *name, char *out, size_t len, const char *dflt)
{
	if (!setting(name, out, len))
		snprintf(out, len, "%s", dflt);
}

static bool setting_bool(const char *name, bool dflt)
{
	char v[64];
	if (!setting(name, v, sizeof(v)))
		return dflt;
	return strcmp(v, "0") && strcasecmp(v, "false");
}

// The buttons this device has, so a remap in system.cfg can name one rather
// than give a number. Not the whole of input-event-codes.h: these are what
// the Nova's pad and keys emit.
static const struct { const char *name; int code; } CODES[] = {
	{ "KEY_VOLUMEUP", KEY_VOLUMEUP },   { "KEY_VOLUMEDOWN", KEY_VOLUMEDOWN },
	{ "KEY_POWER", KEY_POWER },         { "KEY_F1", KEY_F1 },
	{ "BTN_SOUTH", BTN_SOUTH },         { "BTN_EAST", BTN_EAST },
	{ "BTN_NORTH", BTN_NORTH },         { "BTN_WEST", BTN_WEST },
	{ "BTN_TL", BTN_TL },               { "BTN_TR", BTN_TR },
	{ "BTN_SELECT", BTN_SELECT },       { "BTN_START", BTN_START },
	{ "BTN_MODE", BTN_MODE },           { "BTN_THUMBL", BTN_THUMBL },
	{ "BTN_THUMBR", BTN_THUMBR },       { "BTN_TOUCH", BTN_TOUCH },
	{ "BTN_TRIGGER_HAPPY3", BTN_TRIGGER_HAPPY3 },
	{ "BTN_TRIGGER_HAPPY4", BTN_TRIGGER_HAPPY4 },
};

static int code_of(const char *name, int dflt)
{
	size_t i;
	char *end;
	long v;

	if (!name || !*name)
		return dflt;
	for (i = 0; i < sizeof(CODES) / sizeof(CODES[0]); i++)
		if (!strcmp(CODES[i].name, name))
			return CODES[i].code;
	v = strtol(name, &end, 0);
	if (end != name && !*end)
		return (int)v;
	logmsg("unknown button \"%s\", keeping the default", name);
	return dflt;
}

static struct {
	int fn_a, fn_b;             // held modifiers
	int hotkey_a, hotkey_b, hotkey_c;
	bool dpad_events;
	char act_a_up[128], act_a_down[128];
	char act_b_up[128], act_b_down[128];
	char act_ab_up[128], act_ab_down[128];
} cfg;

static void load_config(void)
{
	char v[128], loglevel[64];

	setting_str("loglevel", loglevel, sizeof(loglevel), "none");
	debug = !strcmp(loglevel, "verbose");

	// M1 and Start, per the Nova's 070-modifiers quirk.
	setting_str("key.function.a", v, sizeof(v), "BTN_TRIGGER_HAPPY3");
	cfg.fn_a = code_of(v, BTN_TRIGGER_HAPPY3);
	setting_str("key.function.b", v, sizeof(v), "BTN_START");
	cfg.fn_b = code_of(v, BTN_START);

	setting_str("key.hotkey.a", v, sizeof(v), "BTN_TL");
	cfg.hotkey_a = code_of(v, BTN_TL);
	setting_str("key.hotkey.b", v, sizeof(v), "BTN_SELECT");
	cfg.hotkey_b = code_of(v, BTN_SELECT);
	setting_str("key.hotkey.c", v, sizeof(v), "BTN_START");
	cfg.hotkey_c = code_of(v, BTN_START);

	cfg.dpad_events  = setting_bool("key.dpad.events", false);

	setting_str("key.function.a.up",   cfg.act_a_up,   sizeof(cfg.act_a_up),   "brightness up");
	setting_str("key.function.a.down", cfg.act_a_down, sizeof(cfg.act_a_down), "brightness down");
	setting_str("key.function.b.up",   cfg.act_b_up,   sizeof(cfg.act_b_up),   "ledcontrol");
	setting_str("key.function.b.down", cfg.act_b_down, sizeof(cfg.act_b_down), "ledcontrol poweroff");
	setting_str("key.function.ab.up",  cfg.act_ab_up,  sizeof(cfg.act_ab_up),  "wifictl enable");
	setting_str("key.function.ab.down",cfg.act_ab_down,sizeof(cfg.act_ab_down),"wifictl disable");
}

// ----------------------------------------------------------------- actions

// The helpers are all binaries in /usr/bin, so there is no shell here: the
// action string is split on spaces and exec'd. Children are reaped in the
// SIGCHLD handler.
static void run(const char *cmdline)
{
	char buf[192], *argv[16];
	int argc = 0;
	pid_t pid;

	snprintf(buf, sizeof(buf), "%s", cmdline);
	for (char *tok = strtok(buf, " "); tok && argc < 15; tok = strtok(NULL, " "))
		argv[argc++] = tok;
	argv[argc] = NULL;
	if (!argc)
		return;

	logmsg("run: %s", cmdline);
	pid = fork();
	if (pid == 0) {
		char path[160];
		if (argv[0][0] == '/')
			execv(argv[0], argv);
		else {
			snprintf(path, sizeof(path), "/usr/bin/%s", argv[0]);
			execv(path, argv);
		}
		_exit(127);
	}
	if (pid < 0)
		logmsg("fork failed: %s", strerror(errno));
}

// The launcher draws the on-screen display, because it holds DRM master. A
// FIFO with no reader would block a button press, so open it non-blocking and
// drop the message if nobody is listening - O_NONBLOCK gives ENXIO there
// rather than waiting, which is what the script needed a timeout for.
static void osd(const char *fmt, ...)
{
	char msg[160];
	va_list ap;
	int fd;

	va_start(ap, fmt);
	vsnprintf(msg, sizeof(msg) - 1, fmt, ap);
	va_end(ap);
	strncat(msg, "\n", sizeof(msg) - strlen(msg) - 1);

	fd = open(OSD_PIPE, O_WRONLY | O_NONBLOCK | O_CLOEXEC);
	if (fd < 0)
		return;
	if (write(fd, msg, strlen(msg)) < 0) {
		/* the launcher went away mid-write; the button still worked */
	}
	close(fd);
}

static void notify_volume(void)
{
	char v[64];
	if (setting("audio.volume", v, sizeof(v)))
		osd("Volume: %s%%", v);
}

static void notify_brightness(void)
{
	char v[64];
	if (setting("display.brightness", v, sizeof(v)))
		osd("Brightness: %s%%", v);
}

// ------------------------------------------------------------------- state

static bool fn_a_held, fn_b_held;
static bool hk_a_held, hk_b_held, hk_c_held;
static int  repeat_fd = -1;       // timerfd driving a held volume key
static int  repeat_dir;           // +1 up, -1 down

static void volume_step(int dir)
{
	run(dir > 0 ? "volume up" : "volume down");
	notify_volume();
}

// A held volume key repeats off a timerfd rather than a background subshell,
// so there is no process to race with on release and nothing to kill.
static void repeat_start(int dir)
{
	struct itimerspec its = {
		.it_value    = { .tv_sec = REPEAT_DELAY_MS / 1000,
				 .tv_nsec = (REPEAT_DELAY_MS % 1000) * 1000000L },
		.it_interval = { .tv_sec = REPEAT_INTERVAL_MS / 1000,
				 .tv_nsec = (REPEAT_INTERVAL_MS % 1000) * 1000000L },
	};
	repeat_dir = dir;
	volume_step(dir);
	timerfd_settime(repeat_fd, 0, &its, NULL);
}

static void repeat_stop(void)
{
	struct itimerspec off = { { 0, 0 }, { 0, 0 } };
	if (!repeat_dir)
		return;
	timerfd_settime(repeat_fd, 0, &off, NULL);
	repeat_dir = 0;
	// Once more on release: the last repeat and its notify are not atomic,
	// and the header has to end on the value the volume ended on.
	notify_volume();
}

// What a volume key does depends on which modifiers are down, which is the
// one piece of the script's logic worth keeping exactly.
static void volume_or_action(int dir)
{
	const char *act;

	if (fn_a_held && fn_b_held) {
		act = dir > 0 ? cfg.act_ab_up : cfg.act_ab_down;
		run(act);
	} else if (fn_a_held) {
		act = dir > 0 ? cfg.act_a_up : cfg.act_a_down;
		run(act);
		if (!strncmp(act, "brightness ", 11))
			notify_brightness();
	} else if (fn_b_held) {
		run(dir > 0 ? cfg.act_b_up : cfg.act_b_down);
	} else {
		repeat_start(dir);
	}
}

// A+B+C together kills whatever the launcher last named, the escape from a
// wedged emulator.
static void execute_kill(void)
{
	char name[128];
	FILE *f = fopen("/tmp/.process-kill-data", "re");

	if (!f)
		return;
	if (fgets(name, sizeof(name), f)) {
		name[strcspn(name, "\r\n")] = '\0';
		if (name[0]) {
			char cmd[160];
			snprintf(cmd, sizeof(cmd), "killall %s", name);
			run(cmd);
		}
	}
	fclose(f);
}

// ------------------------------------------------------------ event router

// The script got HW_DEVICE from /etc/profile. A daemon does not source it,
// and this tree builds one platform, so find the handler rather than be told:
// there is exactly one directory under platforms/.
static const char *power_handler(void)
{
	static char path[512];
	static bool looked;
	struct dirent *de;
	DIR *d;

	if (looked)
		return path[0] ? path : NULL;
	looked = true;

	d = opendir("/usr/lib/autostart/quirks/platforms");
	if (!d)
		return NULL;
	while ((de = readdir(d))) {
		if (de->d_name[0] == '.')
			continue;
		snprintf(path, sizeof(path),
			 "/usr/lib/autostart/quirks/platforms/%s/bin/power-handler", de->d_name);
		if (access(path, X_OK) == 0)
			break;
		path[0] = '\0';
	}
	closedir(d);
	return path[0] ? path : NULL;
}

static void handle_key(int code, int value)
{
	// value 2 is autorepeat from the kernel; the volume repeat is ours.
	if (value == 2)
		return;

	if (code == cfg.fn_a) { fn_a_held = value; logmsg("FN_A %d", value); }
	if (code == cfg.fn_b) { fn_b_held = value; logmsg("FN_B %d", value); }
	if (code == cfg.hotkey_a) hk_a_held = value;
	if (code == cfg.hotkey_b) hk_b_held = value;
	if (code == cfg.hotkey_c) hk_c_held = value;

	// The kill combo is checked when the second and third of the three
	// arrive, so the order they are pressed in does not matter.
	if (value && (code == cfg.hotkey_b || code == cfg.hotkey_c) &&
	    hk_a_held && hk_b_held && hk_c_held)
		execute_kill();

	switch (code) {
	case KEY_VOLUMEUP:
		if (value) volume_or_action(+1);
		else repeat_stop();
		return;
	case KEY_VOLUMEDOWN:
		if (value) volume_or_action(-1);
		else repeat_stop();
		return;
	case KEY_POWER: {
		const char *h = power_handler();
		if (value && h) {
			char cmd[600];
			snprintf(cmd, sizeof(cmd), "%s power", h);
			run(cmd);
		}
		return;
	}
	}

	if (!value)
		return;

	// Hotkeys that only do something while a modifier is down.
	// Two hotkeys from the script are gone with the tools they called:
	// FN_A + East closed the focused window through swaymsg, and
	// hotkey + East took a screenshot with portareos-screenshot. Neither
	// binary exists here, and neither could work while the launcher holds
	// DRM master with no compositor to ask.
	if (code == BTN_WEST && hk_a_held)
		run("mangohud_set toggle");
}

// The D-pad on this device is only ever a hat: the emulated pad reports
// ABS_HAT0X/Y and never BTN_DPAD_*. Left and right are brightness, up and
// down are volume, while M1 is held.
static void handle_hat(int code, int value)
{
	if (!fn_a_held || !cfg.dpad_events || value == 0)
		return;

	if (code == ABS_HAT0Y) {
		volume_step(value < 0 ? +1 : -1);
	} else if (code == ABS_HAT0X) {
		run(value > 0 ? "brightness up" : "brightness down");
		notify_brightness();
	}
}

static void handle_switch(int code, int value)
{
	const char *h = power_handler();
	char cmd[600];

	if (code != SW_LID || !h)
		return;
	snprintf(cmd, sizeof(cmd), "%s lid %s", h, value ? "close" : "open");
	run(cmd);
}

// ---------------------------------------------------------------- devices

static int epfd = -1;
static int dev_fd[MAX_FDS];
static int dev_count;

static bool has_bit(const unsigned long *bits, int bit)
{
	return bits[bit / (8 * sizeof(long))] & (1UL << (bit % (8 * sizeof(long))));
}

static bool already_open(const char *path)
{
	char link[64], target[256];
	for (int i = 0; i < dev_count; i++) {
		snprintf(link, sizeof(link), "/proc/self/fd/%d", dev_fd[i]);
		ssize_t n = readlink(link, target, sizeof(target) - 1);
		if (n > 0) {
			target[n] = '\0';
			if (!strcmp(target, path))
				return true;
		}
	}
	return false;
}

// Open every event device that can produce a key, a switch or a hat. Which
// node carries which button is InputPlumber's business and changes as it
// starts and as controllers come and go, so nothing here is pinned to a
// number; the router dispatches on the code.
static void scan_devices(void)
{
	struct dirent *de;
	DIR *d = opendir(INPUT_DIR);

	if (!d)
		return;
	while ((de = readdir(d))) {
		char path[300];
		unsigned long evs[EV_MAX / (8 * sizeof(long)) + 1] = { 0 };
		struct epoll_event ev;
		int fd;

		if (strncmp(de->d_name, "event", 5))
			continue;
		snprintf(path, sizeof(path), INPUT_DIR "/%s", de->d_name);
		if (already_open(path) || dev_count >= MAX_FDS)
			continue;
		if ((fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)) < 0)
			continue;
		if (ioctl(fd, EVIOCGBIT(0, sizeof(evs)), evs) < 0 ||
		    (!has_bit(evs, EV_KEY) && !has_bit(evs, EV_SW) && !has_bit(evs, EV_ABS))) {
			close(fd);
			continue;
		}
		ev.events = EPOLLIN;
		ev.data.fd = fd;
		if (epoll_ctl(epfd, EPOLL_CTL_ADD, fd, &ev) < 0) {
			close(fd);
			continue;
		}
		dev_fd[dev_count++] = fd;
		logmsg("watching %s", path);
	}
	closedir(d);
}

static void drop_device(int fd)
{
	epoll_ctl(epfd, EPOLL_CTL_DEL, fd, NULL);
	close(fd);
	for (int i = 0; i < dev_count; i++)
		if (dev_fd[i] == fd) {
			dev_fd[i] = dev_fd[--dev_count];
			return;
		}
}

// ------------------------------------------------------------------- main

static void reap(int sig)
{
	(void)sig;
	while (waitpid(-1, NULL, WNOHANG) > 0)
		;
}

int main(void)
{
	struct sigaction sa = { .sa_handler = reap, .sa_flags = SA_RESTART | SA_NOCLDSTOP };
	int inotify_fd;
	struct epoll_event ev;

	setvbuf(stderr, NULL, _IOLBF, 0);
	sigemptyset(&sa.sa_mask);
	sigaction(SIGCHLD, &sa, NULL);
	signal(SIGPIPE, SIG_IGN);

	load_config();

	epfd = epoll_create1(EPOLL_CLOEXEC);
	if (epfd < 0) {
		perror("epoll_create1");
		return 1;
	}

	// Hotplug: a controller connecting, and InputPlumber's own targets
	// appearing after this starts. The shell version was restarted by a
	// udev rule that killed it on every input event; watching the
	// directory does the same job without the round trip through systemd.
	inotify_fd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
	if (inotify_fd >= 0) {
		inotify_add_watch(inotify_fd, INPUT_DIR, IN_CREATE | IN_DELETE);
		ev.events = EPOLLIN;
		ev.data.fd = inotify_fd;
		epoll_ctl(epfd, EPOLL_CTL_ADD, inotify_fd, &ev);
	}

	repeat_fd = timerfd_create(CLOCK_MONOTONIC, TFD_NONBLOCK | TFD_CLOEXEC);
	if (repeat_fd >= 0) {
		ev.events = EPOLLIN;
		ev.data.fd = repeat_fd;
		epoll_ctl(epfd, EPOLL_CTL_ADD, repeat_fd, &ev);
	}

	scan_devices();

	for (;;) {
		struct epoll_event out[MAX_FDS + 4];
		int n = epoll_wait(epfd, out, MAX_FDS + 4, -1);

		if (n < 0) {
			if (errno == EINTR)
				continue;
			perror("epoll_wait");
			return 1;
		}

		for (int i = 0; i < n; i++) {
			int fd = out[i].data.fd;

			if (fd == inotify_fd) {
				char buf[4096];
				while (read(inotify_fd, buf, sizeof(buf)) > 0)
					;
				scan_devices();
				continue;
			}

			if (fd == repeat_fd) {
				uint64_t ticks;
				if (read(repeat_fd, &ticks, sizeof(ticks)) == sizeof(ticks) && repeat_dir)
					volume_step(repeat_dir);
				continue;
			}

			struct input_event evs[32];
			ssize_t got = read(fd, evs, sizeof(evs));

			if (got < 0) {
				// ENODEV is the node going away under us, which
				// inotify will also tell us about; drop it here
				// so a dead fd cannot spin epoll.
				if (errno != EAGAIN && errno != EINTR)
					drop_device(fd);
				continue;
			}
			for (size_t k = 0; k < (size_t)got / sizeof(evs[0]); k++) {
				switch (evs[k].type) {
				case EV_KEY:
					handle_key(evs[k].code, evs[k].value);
					break;
				case EV_ABS:
					if (evs[k].code == ABS_HAT0X || evs[k].code == ABS_HAT0Y)
						handle_hat(evs[k].code, evs[k].value);
					break;
				case EV_SW:
					handle_switch(evs[k].code, evs[k].value);
					break;
				}
			}
		}
	}
}
