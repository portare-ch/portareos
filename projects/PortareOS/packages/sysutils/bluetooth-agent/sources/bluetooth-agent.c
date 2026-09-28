// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

/*
 * The bluez pairing agent and auto-connector.
 *
 * Registers org.bluez.Agent1 at /portareos/agent as the default
 * NoInputNoOutput agent, so pairing needs no input on the device.
 * The device named in /run/bt_device (an address, or "input" for any
 * gamepad) is paired, trusted and connected as bluez reports it.
 * /run/bt_discovery_control starts and stops discovery ("start",
 * "stop"); while /run/bt_listing exists, devices seen are appended
 * to it. Progress goes to /run/bt_status, the pid to
 * /run/bt_agent_status.
 *
 * Every call into bluez is asynchronous: Pair() calls back into this
 * agent on the same connection, and a blocking call would leave that
 * callback unanswered.
 */

#include <errno.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <systemd/sd-bus.h>
#include <systemd/sd-event.h>

#define AGENT_PATH        "/portareos/agent"
#define CONTROL_FILE      "/run/bt_discovery_control"
#define AGENT_STATUS_FILE "/run/bt_agent_status"
#define STATUS_FILE       "/run/bt_status"
#define LISTING_FILE      "/run/bt_listing"
#define DEVICE_FILE       "/run/bt_device"
#define LOG_FILE          "/var/log/bluetooth-agent.log"
#define DEVICE1           "org.bluez.Device1"
#define MAX_DEVS          128
#define CONNECT_ATTEMPTS  5

struct dev {
	char path[128];
	char addr[18];
	char name[249];
	char icon[64];
	bool has_addr, has_name, has_icon, has_paired, has_trusted, has_connected;
	bool paired, trusted, connected;
	bool listed;
	bool busy;          /* a pair, trust, connect chain is running */
	bool need_trust, need_connect;
	int attempt;
};

static struct dev devs[MAX_DEVS];
static sd_bus *bus;
static sd_event *ev;
static char adapter[128];
static const char *dev_id;
static bool discovering, listing;

static void logmsg(const char *level, const char *fmt, ...)
{
	FILE *f = fopen(LOG_FILE, "a");
	if (!f)
		return;
	char ts[32];
	time_t t = time(NULL);
	struct tm tm;
	localtime_r(&t, &tm);
	strftime(ts, sizeof(ts), "%Y-%m-%d %H:%M:%S", &tm);
	fprintf(f, "%s [%s] ", ts, level);
	va_list ap;
	va_start(ap, fmt);
	vfprintf(f, fmt, ap);
	va_end(ap);
	fputc('\n', f);
	fclose(f);
}
#define info(...) logmsg("INFO", __VA_ARGS__)
#define error(...) logmsg("ERROR", __VA_ARGS__)

static void status(const char *fmt, ...)
{
	FILE *f = fopen(STATUS_FILE, "w");
	if (!f) {
		error("Failed to write status: %s", strerror(errno));
		return;
	}
	va_list ap;
	va_start(ap, fmt);
	vfprintf(f, fmt, ap);
	va_end(ap);
	fputc('\n', f);
	fclose(f);
}

static struct dev *find_dev(const char *path, bool create)
{
	struct dev *free_slot = NULL;
	for (int i = 0; i < MAX_DEVS; i++) {
		if (!devs[i].path[0]) {
			if (!free_slot)
				free_slot = &devs[i];
		} else if (!strcmp(devs[i].path, path)) {
			return &devs[i];
		}
	}
	if (!create || !free_slot)
		return NULL;
	memset(free_slot, 0, sizeof(*free_slot));
	snprintf(free_slot->path, sizeof(free_slot->path), "%s", path);
	return free_slot;
}

static const char *short_name(const struct dev *d)
{
	return d->has_name ? d->name : d->has_addr ? d->addr : "unknown";
}

static const char *long_name(const struct dev *d, char *buf, size_t len)
{
	if (d->has_name && d->has_addr && d->has_icon)
		snprintf(buf, len, "%s (%s, %s)", d->name, d->addr, d->icon);
	else if (d->has_name && d->has_addr)
		snprintf(buf, len, "%s (%s)", d->name, d->addr);
	else
		snprintf(buf, len, "%s", short_name(d));
	return buf;
}

static const char *basic_type(const struct dev *d)
{
	if (!d->has_icon)
		return "unknown";
	if (!strcmp(d->icon, "input-gaming"))
		return "joystick";
	if (!strncmp(d->icon, "audio-", 6))
		return "audio";
	return d->icon;
}

/* The listing only ever says a device was added or removed, once each.
 * A device is written once it has an address; the name is "None" when
 * bluez has none yet, as the Python agent wrote it. */
static void listing_event(struct dev *d, bool adding)
{
	if (d->listed == adding || !d->has_addr)
		return;
	d->listed = adding;
	FILE *f = fopen(LISTING_FILE, "a");
	if (!f) {
		error("Failed to write listing event: %s", strerror(errno));
		return;
	}
	fprintf(f, "<device id=\"%s\" name=\"%s\" status=\"%s\" type=\"%s\" />\n",
	        d->addr, d->has_name ? d->name : "None",
	        adding ? "added" : "removed", basic_type(d));
	fclose(f);
}

/* The device /run/bt_device asks for: an address, "input", or none. */
static bool wanted(char *buf, size_t len)
{
	FILE *f = fopen(DEVICE_FILE, "r");
	if (!f)
		return false;
	if (!fgets(buf, (int)len, f))
		buf[0] = '\0';
	fclose(f);
	buf[strcspn(buf, " \t\r\n")] = '\0';
	return buf[0] != '\0';
}

#define CH_PAIRED_TRUE 1u
#define CH_CONNECTED   2u

/* Merge an a{sv} of Device1 properties into d. Returns the changes the
 * connect logic cares about, or a negative errno. */
static int read_props(sd_bus_message *m, struct dev *d, unsigned *changes)
{
	int r = sd_bus_message_enter_container(m, 'a', "{sv}");
	if (r < 0)
		return r;
	while ((r = sd_bus_message_enter_container(m, 'e', "sv")) > 0) {
		const char *key;
		if ((r = sd_bus_message_read(m, "s", &key)) < 0)
			return r;
		const char *s;
		int b;
		if (!strcmp(key, "Address") || !strcmp(key, "Name") || !strcmp(key, "Icon")) {
			if ((r = sd_bus_message_read(m, "v", "s", &s)) < 0)
				return r;
			if (key[0] == 'A') {
				snprintf(d->addr, sizeof(d->addr), "%s", s);
				d->has_addr = true;
			} else if (key[0] == 'N') {
				snprintf(d->name, sizeof(d->name), "%s", s);
				d->has_name = true;
			} else {
				snprintf(d->icon, sizeof(d->icon), "%s", s);
				d->has_icon = true;
			}
		} else if (!strcmp(key, "Paired") || !strcmp(key, "Trusted") || !strcmp(key, "Connected")) {
			if ((r = sd_bus_message_read(m, "v", "b", &b)) < 0)
				return r;
			if (key[0] == 'P') {
				d->paired = b;
				d->has_paired = true;
				if (b && changes)
					*changes |= CH_PAIRED_TRUE;
			} else if (key[0] == 'T') {
				d->trusted = b;
				d->has_trusted = true;
			} else {
				d->connected = b;
				d->has_connected = true;
				if (changes)
					*changes |= CH_CONNECTED;
			}
		} else if ((r = sd_bus_message_skip(m, "v")) < 0) {
			return r;
		}
		if ((r = sd_bus_message_exit_container(m)) < 0)
			return r;
	}
	if (r < 0)
		return r;
	return sd_bus_message_exit_container(m);
}

static void adapter_call(const char *method);
static void step_trust(struct dev *d);
static void step_connect(struct dev *d);
static void connect_attempt(struct dev *d);

/* Callbacks carry the device's path, not a pointer, since a device can
 * leave while a call is in flight. */
static struct dev *dev_of(void *userdata)
{
	struct dev *d = find_dev(userdata, false);
	free(userdata);
	return d;
}

static int pair_done(sd_bus_message *m, void *userdata, sd_bus_error *e)
{
	(void)e;
	struct dev *d = dev_of(userdata);
	if (!d)
		return 0;
	char n[400];
	if (sd_bus_message_is_method_error(m, NULL)) {
		error("Pairing failed (%s): %s", long_name(d, n, sizeof(n)), sd_bus_message_get_error(m)->message);
		status("Pairing failed (%s)", short_name(d));
	}
	step_trust(d);
	return 0;
}

static int trust_done(sd_bus_message *m, void *userdata, sd_bus_error *e)
{
	(void)e;
	struct dev *d = dev_of(userdata);
	if (!d)
		return 0;
	char n[400];
	if (sd_bus_message_is_method_error(m, NULL)) {
		error("Trusting failed (%s): %s", long_name(d, n, sizeof(n)), sd_bus_message_get_error(m)->message);
		status("Trusting failed (%s)", short_name(d));
	}
	step_connect(d);
	return 0;
}

static void finish_chain(struct dev *d)
{
	if (d)
		d->busy = false;
	if (discovering) {
		info("Restarting discovery");
		adapter_call("StartDiscovery");
	}
}

static int retry_timer(sd_event_source *s, uint64_t usec, void *userdata)
{
	(void)usec;
	sd_event_source_unref(s);
	struct dev *d = dev_of(userdata);
	if (!d) {
		finish_chain(NULL);
		return 0;
	}
	d->attempt++;
	connect_attempt(d);
	return 0;
}

static int connect_done(sd_bus_message *m, void *userdata, sd_bus_error *e)
{
	(void)e;
	char *path = strdup(userdata);
	struct dev *d = dev_of(userdata);
	if (!d) {
		free(path);
		finish_chain(NULL);
		return 0;
	}
	char n[400];
	if (!sd_bus_message_is_method_error(m, NULL)) {
		info("Connected successfully (%s)", long_name(d, n, sizeof(n)));
		status("Connected successfully (%s)", short_name(d));
		free(path);
		finish_chain(d);
		return 0;
	}
	error("Connection attempt %d failed: %s", d->attempt + 1, sd_bus_message_get_error(m)->message);
	if (d->attempt < CONNECT_ATTEMPTS - 1 && path) {
		sd_event_source *t;
		if (sd_event_add_time_relative(ev, &t, CLOCK_MONOTONIC, 1000000, 0, retry_timer, path) >= 0)
			return 0;
	}
	free(path);
	status("Connection failed. Giving up. (%s)", short_name(d));
	finish_chain(d);
	return 0;
}

static int call_device(struct dev *d, const char *iface, const char *method,
                       sd_bus_message_handler_t done, const char *types, ...)
{
	sd_bus_message *m = NULL;
	char *ud = strdup(d->path);
	int r = sd_bus_message_new_method_call(bus, &m, "org.bluez", d->path, iface, method);
	if (r >= 0 && types) {
		va_list ap;
		va_start(ap, types);
		r = sd_bus_message_appendv(m, types, ap);
		va_end(ap);
	}
	/* Pairing waits on the other side; bluez gives up well before this. */
	if (r >= 0)
		r = sd_bus_call_async(bus, NULL, m, done, ud, 60 * 1000000ULL);
	sd_bus_message_unref(m);
	if (r < 0) {
		free(ud);
		error("%s on %s: %s", method, d->path, strerror(-r));
	}
	return r;
}

static void step_trust(struct dev *d)
{
	if (!d->need_trust) {
		step_connect(d);
		return;
	}
	char n[400];
	info("Trusting (%s)", long_name(d, n, sizeof(n)));
	status("Trusting %s...", short_name(d));
	if (call_device(d, "org.freedesktop.DBus.Properties", "Set", trust_done,
	                "ssv", DEVICE1, "Trusted", "b", 1) < 0)
		step_connect(d);
}

static void connect_attempt(struct dev *d)
{
	char n[400];
	info("Connecting... (%s) attempt %d", long_name(d, n, sizeof(n)), d->attempt + 1);
	status("Connecting %s...", short_name(d));
	if (call_device(d, DEVICE1, "Connect", connect_done, NULL) < 0)
		finish_chain(d);
}

static void step_connect(struct dev *d)
{
	if (!d->need_connect) {
		d->busy = false;
		return;
	}
	if (discovering) {
		info("Stopping discovery for connection");
		adapter_call("StopDiscovery");
	}
	d->attempt = 0;
	connect_attempt(d);
}

static void connect_device(struct dev *d, bool force)
{
	char filter[64], n[400];
	if (!wanted(filter, sizeof(filter))) {
		info("skipping %s. No filter.", d->addr);
		return;
	}
	if (!d->has_trusted || !d->has_connected) {
		info("skipping %s. Missing required properties.", d->addr);
		return;
	}
	long_name(d, n, sizeof(n));
	if (!d->has_icon) {
		info("Skipping device %s (no type)", n);
		return;
	}
	if (strcmp(filter, d->addr) && !(!strcmp(filter, "input") && !strncmp(d->icon, "input", 5))) {
		info("Skipping device %s (not %s)", n, filter);
		return;
	}
	info("Event for %s (paired=%s, trusted=%s, connected=%s)", n,
	     d->paired ? "paired" : "not paired", d->trusted ? "trusted" : "untrusted",
	     d->connected ? "connected" : "disconnected");
	if (d->paired && d->trusted && d->connected) {
		info("Skipping already connected device %s", n);
		return;
	}
	if (d->busy) {
		info("Busy with %s already", n);
		return;
	}
	bool need_pair = !d->paired && !d->connected && discovering;
	d->need_trust = !d->trusted && (discovering || force);
	d->need_connect = !d->connected || force;
	if (!need_pair && !d->need_trust && !d->need_connect)
		return;
	d->busy = true;
	if (need_pair) {
		info("Pairing... (%s)", n);
		status("Pairing %s...", short_name(d));
		if (call_device(d, DEVICE1, "Pair", pair_done, NULL) >= 0)
			return;
	}
	step_trust(d);
}

static int adapter_done(sd_bus_message *m, void *userdata, sd_bus_error *e)
{
	(void)e;
	if (sd_bus_message_is_method_error(m, NULL))
		error("%s failed: %s", (const char *)userdata, sd_bus_message_get_error(m)->message);
	return 0;
}

static void adapter_call(const char *method)
{
	if (!adapter[0]) {
		error("%s: no adapter yet", method);
		return;
	}
	int r = sd_bus_call_method_async(bus, NULL, "org.bluez", adapter, "org.bluez.Adapter1",
	                                 method, adapter_done, (void *)method, "");
	if (r < 0)
		error("%s: %s", method, strerror(-r));
}

static int on_added(sd_bus_message *m, void *userdata, sd_bus_error *e)
{
	(void)userdata; (void)e;
	const char *path;
	if (sd_bus_message_read(m, "o", &path) < 0 ||
	    sd_bus_message_enter_container(m, 'a', "{sa{sv}}") < 0)
		return 0;
	while (sd_bus_message_enter_container(m, 'e', "sa{sv}") > 0) {
		const char *iface;
		if (sd_bus_message_read(m, "s", &iface) < 0)
			return 0;
		if (strcmp(iface, DEVICE1)) {
			sd_bus_message_skip(m, "a{sv}");
		} else {
			struct dev *d = find_dev(path, true);
			if (!d || read_props(m, d, NULL) < 0)
				return 0;
			info("Interface added: %s", path);
			if (listing)
				listing_event(d, true);
			if (d->has_addr)
				connect_device(d, false);
			else
				info("No address. skip.");
		}
		sd_bus_message_exit_container(m);
	}
	return 0;
}

static int on_removed(sd_bus_message *m, void *userdata, sd_bus_error *e)
{
	(void)userdata; (void)e;
	const char *path, *iface;
	if (sd_bus_message_read(m, "o", &path) < 0 ||
	    sd_bus_message_enter_container(m, 'a', "s") < 0)
		return 0;
	while (sd_bus_message_read(m, "s", &iface) > 0) {
		if (strcmp(iface, DEVICE1))
			continue;
		struct dev *d = find_dev(path, false);
		if (d) {
			listing_event(d, false);
			d->path[0] = '\0';
		}
	}
	return 0;
}

static int on_props(sd_bus_message *m, void *userdata, sd_bus_error *e)
{
	(void)userdata; (void)e;
	const char *iface;
	if (sd_bus_message_read(m, "s", &iface) < 0 || strcmp(iface, DEVICE1))
		return 0;
	struct dev *d = find_dev(sd_bus_message_get_path(m), true);
	unsigned changes = 0;
	if (!d || read_props(m, d, &changes) < 0)
		return 0;
	if (listing)
		listing_event(d, true);
	if (changes & CH_PAIRED_TRUE) {
		if (d->has_addr)
			connect_device(d, true);
		return 0;
	}
	if (changes & CH_CONNECTED)
		return 0;
	if (d->has_addr)
		connect_device(d, false);
	return 0;
}

static void start_discovery(void)
{
	if (access(LISTING_FILE, F_OK) == 0) {
		listing = true;
		info("Listing mode enabled");
		for (int i = 0; i < MAX_DEVS; i++)
			if (devs[i].path[0]) {
				devs[i].listed = false;
				listing_event(&devs[i], true);
			}
	}
	if (!discovering) {
		discovering = true;
		info("Starting discovery");
		adapter_call("StartDiscovery");
	}
}

static void stop_discovery(void)
{
	if (listing)
		info("Listing mode disabled");
	listing = false;
	if (discovering) {
		discovering = false;
		info("Stopping discovery");
		adapter_call("StopDiscovery");
	}
}

static int control_tick(sd_event_source *s, uint64_t usec, void *userdata)
{
	(void)userdata;
	FILE *f = fopen(CONTROL_FILE, "r");
	if (f) {
		char cmd[32] = "";
		if (!fgets(cmd, sizeof(cmd), f))
			cmd[0] = '\0';
		fclose(f);
		if (unlink(CONTROL_FILE) < 0)
			error("Failed to remove control file: %s", strerror(errno));
		cmd[strcspn(cmd, " \t\r\n")] = '\0';
		if (!strcmp(cmd, "start"))
			start_discovery();
		else if (!strcmp(cmd, "stop"))
			stop_discovery();
	}
	sd_event_source_set_time(s, usec + 500000);
	return 0;
}

static int find_adapter(void)
{
	if (dev_id) {
		snprintf(adapter, sizeof(adapter), "/org/bluez/%s", dev_id);
		return 0;
	}
	sd_bus_error e = SD_BUS_ERROR_NULL;
	sd_bus_message *reply = NULL;
	int r = sd_bus_call_method(bus, "org.bluez", "/", "org.freedesktop.DBus.ObjectManager",
	                           "GetManagedObjects", &e, &reply, "");
	if (r < 0) {
		error("Failed to find adapter via ObjectManager: %s", e.message ? e.message : strerror(-r));
		sd_bus_error_free(&e);
		return r;
	}
	r = sd_bus_message_enter_container(reply, 'a', "{oa{sa{sv}}}");
	while (r >= 0 && !adapter[0] && sd_bus_message_enter_container(reply, 'e', "oa{sa{sv}}") > 0) {
		const char *path, *iface;
		sd_bus_message_read(reply, "o", &path);
		sd_bus_message_enter_container(reply, 'a', "{sa{sv}}");
		while (sd_bus_message_enter_container(reply, 'e', "sa{sv}") > 0) {
			sd_bus_message_read(reply, "s", &iface);
			if (!strcmp(iface, "org.bluez.Adapter1"))
				snprintf(adapter, sizeof(adapter), "%s", path);
			sd_bus_message_skip(reply, "a{sv}");
			sd_bus_message_exit_container(reply);
		}
		sd_bus_message_exit_container(reply);
		sd_bus_message_exit_container(reply);
	}
	sd_bus_message_unref(reply);
	return adapter[0] ? 0 : -ENODEV;
}

/* bluez needs a moment after it starts before the adapter is there. */
static int adapter_timer(sd_event_source *s, uint64_t usec, void *userdata)
{
	(void)usec; (void)userdata;
	sd_event_source_unref(s);
	if (find_adapter() < 0) {
		error("No bluetooth adapter found");
		sd_event_exit(ev, 1);
		return 0;
	}
	info("Using adapter at %s", adapter);
	info("Adapter initialized");
	sd_event_source *t;
	if (sd_event_add_time_relative(ev, &t, CLOCK_MONOTONIC, 500000, 0, control_tick, NULL) >= 0)
		sd_event_source_set_enabled(t, SD_EVENT_ON);
	return 0;
}

static int m_release(sd_bus_message *m, void *userdata, sd_bus_error *e)
{
	(void)userdata; (void)e;
	info("Agent Release");
	sd_event_exit(ev, 0);
	return sd_bus_reply_method_return(m, "");
}

static int m_accept(sd_bus_message *m, void *userdata, sd_bus_error *e)
{
	(void)userdata; (void)e;
	info("Agent %s", sd_bus_message_get_member(m));
	return sd_bus_reply_method_return(m, "");
}

static int m_pin(sd_bus_message *m, void *userdata, sd_bus_error *e)
{
	(void)userdata; (void)e;
	const char *dev = "";
	sd_bus_message_read(m, "o", &dev);
	info("RequestPinCode (%s)", dev);
	return sd_bus_reply_method_return(m, "s", "0000");
}

static int m_passkey(sd_bus_message *m, void *userdata, sd_bus_error *e)
{
	(void)userdata; (void)e;
	const char *dev = "";
	sd_bus_message_read(m, "o", &dev);
	info("RequestPasskey (%s)", dev);
	return sd_bus_reply_method_return(m, "u", (uint32_t)0);
}

static const sd_bus_vtable agent_vtable[] = {
	SD_BUS_VTABLE_START(0),
	SD_BUS_METHOD("Release", "", "", m_release, SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_METHOD("AuthorizeService", "os", "", m_accept, SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_METHOD("RequestPinCode", "o", "s", m_pin, SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_METHOD("RequestPasskey", "o", "u", m_passkey, SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_METHOD("DisplayPasskey", "ouq", "", m_accept, SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_METHOD("DisplayPinCode", "os", "", m_accept, SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_METHOD("RequestConfirmation", "ou", "", m_accept, SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_METHOD("RequestAuthorization", "o", "", m_accept, SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_METHOD("Cancel", "", "", m_accept, SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_VTABLE_END
};

static int on_signal(sd_event_source *s, const struct signalfd_siginfo *si, void *userdata)
{
	(void)s; (void)si; (void)userdata;
	sd_event_exit(ev, 0);
	return 0;
}

int main(int argc, char **argv)
{
	int opt;
	while ((opt = getopt(argc, argv, "i:")) != -1)
		if (opt == 'i')
			dev_id = optarg;

	sigset_t ss;
	sigemptyset(&ss);
	sigaddset(&ss, SIGTERM);
	sigaddset(&ss, SIGINT);
	sigprocmask(SIG_BLOCK, &ss, NULL);

	int r = sd_event_default(&ev);
	if (r >= 0) r = sd_event_add_signal(ev, NULL, SIGTERM, on_signal, NULL);
	if (r >= 0) r = sd_event_add_signal(ev, NULL, SIGINT, on_signal, NULL);
	if (r >= 0) r = sd_bus_open_system(&bus);
	if (r >= 0) r = sd_bus_attach_event(bus, ev, SD_EVENT_PRIORITY_NORMAL);
	if (r >= 0) r = sd_bus_match_signal(bus, NULL, "org.bluez", "/", "org.freedesktop.DBus.ObjectManager",
	                                    "InterfacesAdded", on_added, NULL);
	if (r >= 0) r = sd_bus_match_signal(bus, NULL, "org.bluez", "/", "org.freedesktop.DBus.ObjectManager",
	                                    "InterfacesRemoved", on_removed, NULL);
	if (r >= 0) r = sd_bus_add_match(bus, NULL,
	                                 "type='signal',sender='org.bluez',interface='org.freedesktop.DBus.Properties',"
	                                 "member='PropertiesChanged',arg0='" DEVICE1 "'", on_props, NULL);
	if (r >= 0) r = sd_bus_add_object_vtable(bus, NULL, AGENT_PATH, "org.bluez.Agent1", agent_vtable, NULL);
	if (r < 0) {
		error("Setup failed: %s", strerror(-r));
		return 1;
	}

	sd_bus_error e = SD_BUS_ERROR_NULL;
	r = sd_bus_call_method(bus, "org.bluez", "/org/bluez", "org.bluez.AgentManager1", "RegisterAgent",
	                       &e, NULL, "os", AGENT_PATH, "NoInputNoOutput");
	if (r >= 0)
		r = sd_bus_call_method(bus, "org.bluez", "/org/bluez", "org.bluez.AgentManager1",
		                       "RequestDefaultAgent", &e, NULL, "o", AGENT_PATH);
	if (r < 0) {
		error("Failed to register agent: %s", e.message ? e.message : strerror(-r));
		sd_bus_error_free(&e);
		return 1;
	}
	info("Agent registered");

	FILE *f = fopen(AGENT_STATUS_FILE, "w");
	if (!f) {
		error("Failed to write status file: %s", strerror(errno));
		return 1;
	}
	fprintf(f, "%d", (int)getpid());
	fclose(f);

	info("Waiting for Bluetooth adapter...");
	sd_event_source *t;
	sd_event_add_time_relative(ev, &t, CLOCK_MONOTONIC, 5000000, 0, adapter_timer, NULL);

	r = sd_event_loop(ev);

	unlink(AGENT_STATUS_FILE);
	error("Agent terminated");
	sd_bus_flush_close_unref(bus);
	sd_event_unref(ev);
	return r < 0 ? 1 : r;
}
