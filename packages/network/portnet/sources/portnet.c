/* SPDX-License-Identifier: GPL-2.0
 * Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)
 *
 * portnet - Wi-Fi for PortareOS, straight to iwd over sd-bus.
 *
 * This replaces nmcli. NetworkManager was here to own Ethernet and to do
 * DHCP while iwd did 802.11; this device has one interface, wlan0, and iwd
 * can do the addressing itself, so the 7 MB in between was a translation
 * layer for a translation nobody needed.
 *
 * A command, not a daemon. iwd already reconnects to a known network on its
 * own, so there is nothing to sit and watch. The one thing that does need a
 * service is the passphrase: iwd asks for it through an Agent, so "join"
 * registers one for as long as the join takes and drops it after. That is
 * the same shape as portareos-bluetooth-agent, for the same reason.
 *
 * Output is plain and tab-separated, because the launcher parses it. See
 * the usage text at the bottom for the contract.
 */

#include <errno.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <systemd/sd-bus.h>

#define IWD              "net.connman.iwd"
#define IF_ADAPTER       IWD ".Adapter"
#define IF_DEVICE        IWD ".Device"
#define IF_STATION       IWD ".Station"
#define IF_NETWORK       IWD ".Network"
#define IF_KNOWN         IWD ".KnownNetwork"
#define IF_AGENT_MANAGER IWD ".AgentManager"
#define IF_AGENT         IWD ".Agent"
#define AGENT_PATH       "/net/portare/portnet/agent"

#define MAX_NETS 64

struct net {
	char path[256];   /* the Network object                      */
	char name[80];    /* SSID                                    */
	char type[24];    /* psk, open, 8021x, wep                   */
	bool known;       /* iwd has a passphrase for it             */
	bool connected;
	int  signal;      /* 0-100                                   */
};

static sd_bus *bus;
static const char *join_passphrase;   /* only set during "join" */
static int  agent_result;             /* 0 until the agent is asked */

static int fail(const char *what, int r)
{
	fprintf(stderr, "portnet: %s: %s\n", what, strerror(r < 0 ? -r : r));
	return 1;
}

/* iwd puts every object under one ObjectManager, so one call gets the
 * adapter, the station and every network at once. Everything below walks
 * that reply rather than making a call per object. */
static int managed_objects(sd_bus_message **reply)
{
	sd_bus_error err = SD_BUS_ERROR_NULL;
	int r = sd_bus_call_method(bus, IWD, "/", "org.freedesktop.DBus.ObjectManager",
	                           "GetManagedObjects", &err, reply, "");
	if (r < 0) {
		fprintf(stderr, "portnet: iwd: %s\n",
		        err.message ? err.message : strerror(-r));
		sd_bus_error_free(&err);
		return r;
	}
	sd_bus_error_free(&err);
	return 0;
}

/* Reads one a{sv} property block, picking out the handful of keys we use.
 * Unknown keys are skipped with sd_bus_message_skip, which needs the
 * variant's own signature - that is what the read of "v" with NULL does. */
static int read_props(sd_bus_message *m, const char *iface, struct net *n,
                      char *station_out, size_t station_sz,
                      char *adapter_out, size_t adapter_sz,
                      const char *path, bool *powered)
{
	int r = sd_bus_message_enter_container(m, 'a', "{sv}");
	if (r < 0)
		return r;

	while ((r = sd_bus_message_enter_container(m, 'e', "sv")) > 0) {
		const char *key = NULL;
		if ((r = sd_bus_message_read(m, "s", &key)) < 0)
			return r;

		if (!strcmp(iface, IF_NETWORK) && n) {
			if (!strcmp(key, "Name")) {
				const char *s = NULL;
				if ((r = sd_bus_message_read(m, "v", "s", &s)) < 0)
					return r;
				snprintf(n->name, sizeof(n->name), "%s", s ? s : "");
			} else if (!strcmp(key, "Type")) {
				const char *s = NULL;
				if ((r = sd_bus_message_read(m, "v", "s", &s)) < 0)
					return r;
				snprintf(n->type, sizeof(n->type), "%s", s ? s : "");
			} else if (!strcmp(key, "Connected")) {
				int b = 0;
				if ((r = sd_bus_message_read(m, "v", "b", &b)) < 0)
					return r;
				n->connected = b;
			} else if (!strcmp(key, "KnownNetwork")) {
				/* Present only when iwd has credentials. Its value is
				 * the KnownNetwork object path; that it exists at all
				 * is the answer. */
				const char *o = NULL;
				if ((r = sd_bus_message_read(m, "v", "o", &o)) < 0)
					return r;
				n->known = o && *o;
			} else if ((r = sd_bus_message_skip(m, "v")) < 0)
				return r;
		} else if (!strcmp(iface, IF_ADAPTER) && powered) {
			if (!strcmp(key, "Powered")) {
				int b = 0;
				if ((r = sd_bus_message_read(m, "v", "b", &b)) < 0)
					return r;
				*powered = b;
				if (adapter_out)
					snprintf(adapter_out, adapter_sz, "%s", path);
			} else if ((r = sd_bus_message_skip(m, "v")) < 0)
				return r;
		} else if ((r = sd_bus_message_skip(m, "v")) < 0)
			return r;

		if ((r = sd_bus_message_exit_container(m)) < 0)   /* the dict entry */
			return r;
	}
	if (r < 0)
		return r;

	if (!strcmp(iface, IF_STATION) && station_out)
		snprintf(station_out, station_sz, "%s", path);

	return sd_bus_message_exit_container(m);
}

/* One walk of the object tree: fills in the station and adapter paths, and
 * every Network object it finds. */
static int survey(struct net *nets, int *count, char *station, size_t ssz,
                  char *adapter, size_t asz, bool *powered)
{
	sd_bus_message *m = NULL;
	int r = managed_objects(&m);
	if (r < 0)
		return r;

	if (count)
		*count = 0;

	if ((r = sd_bus_message_enter_container(m, 'a', "{oa{sa{sv}}}")) < 0)
		goto done;

	while ((r = sd_bus_message_enter_container(m, 'e', "oa{sa{sv}}")) > 0) {
		const char *path = NULL;
		if ((r = sd_bus_message_read(m, "o", &path)) < 0)
			goto done;
		if ((r = sd_bus_message_enter_container(m, 'a', "{sa{sv}}")) < 0)
			goto done;

		while ((r = sd_bus_message_enter_container(m, 'e', "sa{sv}")) > 0) {
			const char *iface = NULL;
			if ((r = sd_bus_message_read(m, "s", &iface)) < 0)
				goto done;

			struct net *slot = NULL;
			if (!strcmp(iface, IF_NETWORK) && nets && count && *count < MAX_NETS) {
				slot = &nets[*count];
				memset(slot, 0, sizeof(*slot));
				snprintf(slot->path, sizeof(slot->path), "%s", path);
				slot->signal = -1;
			}

			if ((r = read_props(m, iface, slot, station, ssz,
			                    adapter, asz, path, powered)) < 0)
				goto done;

			if (slot)
				(*count)++;

			if ((r = sd_bus_message_exit_container(m)) < 0)
				goto done;
		}
		if (r < 0)
			goto done;
		if ((r = sd_bus_message_exit_container(m)) < 0)   /* a{sa{sv}} */
			goto done;
		if ((r = sd_bus_message_exit_container(m)) < 0)   /* the dict entry */
			goto done;
	}
	if (r < 0)
		goto done;
	r = sd_bus_message_exit_container(m);

done:
	sd_bus_message_unref(m);
	return r;
}

/* iwd reports signal strength in hundredths of a dBm. Map it the way a
 * person reads bars: -50 and better is full, -100 is nothing. */
static int signal_pct(int16_t dbm100)
{
	int dbm = dbm100 / 100;
	if (dbm >= -50)
		return 100;
	if (dbm <= -100)
		return 0;
	return 2 * (dbm + 100);
}

/* GetOrderedNetworks is the only place the signal strength lives, and it
 * only lists what the last scan saw. Networks known but out of range are
 * in the object tree without an entry here, which is exactly the
 * difference between "saved" and "in range". */
static int merge_signals(const char *station, struct net *nets, int count)
{
	sd_bus_error err = SD_BUS_ERROR_NULL;
	sd_bus_message *m = NULL;
	int r = sd_bus_call_method(bus, IWD, station, IF_STATION,
	                           "GetOrderedNetworks", &err, &m, "");
	if (r < 0) {
		sd_bus_error_free(&err);
		return r;
	}
	sd_bus_error_free(&err);

	if ((r = sd_bus_message_enter_container(m, 'a', "(on)")) < 0)
		goto done;
	while ((r = sd_bus_message_enter_container(m, 'r', "on")) > 0) {
		const char *path = NULL;
		int16_t strength = 0;
		if ((r = sd_bus_message_read(m, "on", &path, &strength)) < 0)
			goto done;
		for (int i = 0; i < count; i++)
			if (!strcmp(nets[i].path, path))
				nets[i].signal = signal_pct(strength);
		if ((r = sd_bus_message_exit_container(m)) < 0)
			goto done;
	}
	if (r < 0)
		goto done;
	r = sd_bus_message_exit_container(m);

done:
	sd_bus_message_unref(m);
	return r;
}

static int cmd_list(bool rescan)
{
	char station[256] = "", adapter[256] = "";
	bool powered = false;
	struct net nets[MAX_NETS];
	int count = 0, r;

	if ((r = survey(nets, &count, station, sizeof(station),
	                adapter, sizeof(adapter), &powered)) < 0)
		return fail("survey", r);
	if (!station[0]) {
		fprintf(stderr, "portnet: no station - is the radio off?\n");
		return 1;
	}

	if (rescan) {
		sd_bus_error err = SD_BUS_ERROR_NULL;
		/* Already-scanning is not an error worth failing on: somebody
		 * else asked first and the results land either way. */
		sd_bus_call_method(bus, IWD, station, IF_STATION, "Scan", &err, NULL, "");
		sd_bus_error_free(&err);

		/* Wait for the scan rather than guessing at it. A fixed sleep
		 * returned fewer networks than not rescanning at all: the
		 * results replace the cached list the moment the scan starts,
		 * so reading it early shows a half-filled one. */
		for (int i = 0; i < 100; i++) {          /* 10 s ceiling */
			int scanning = 0;
			sd_bus_error e2 = SD_BUS_ERROR_NULL;
			r = sd_bus_get_property_trivial(bus, IWD, station, IF_STATION,
			                                "Scanning", &e2, 'b', &scanning);
			sd_bus_error_free(&e2);
			if (r < 0 || !scanning)
				break;
			usleep(100 * 1000);
		}
		count = 0;
		if ((r = survey(nets, &count, station, sizeof(station),
		                adapter, sizeof(adapter), &powered)) < 0)
			return fail("survey", r);
	}

	merge_signals(station, nets, count);

	for (int i = 0; i < count; i++)
		printf("%s\t%d\t%d\t%d\t%s\n", nets[i].name, nets[i].known ? 1 : 0,
		       nets[i].connected ? 1 : 0, nets[i].signal, nets[i].type);
	return 0;
}

static int find_by_name(const char *ssid, struct net *out)
{
	struct net nets[MAX_NETS];
	char station[256] = "";
	int count = 0;
	if (survey(nets, &count, station, sizeof(station), NULL, 0, NULL) < 0)
		return -EIO;
	for (int i = 0; i < count; i++)
		if (!strcmp(nets[i].name, ssid)) {
			*out = nets[i];
			return 0;
		}
	return -ENOENT;
}

/* --- the passphrase agent ------------------------------------------------
 *
 * iwd will not take a passphrase as an argument to Connect; it calls back
 * for one. So "join" puts an agent on the bus, answers exactly one
 * RequestPassphrase with what was on the command line, and takes it off
 * again. Nothing is written anywhere by us - iwd stores the credentials
 * itself under /var/lib/iwd once the association succeeds, which is also
 * why a wrong passphrase leaves nothing behind.
 */
static int agent_request_passphrase(sd_bus_message *m, void *userdata,
                                    sd_bus_error *err)
{
	(void)userdata; (void)err;
	if (!join_passphrase)
		return sd_bus_reply_method_errorf(m, IWD ".Agent.Error.Canceled",
		                                  "no passphrase offered");
	agent_result = 1;
	return sd_bus_reply_method_return(m, "s", join_passphrase);
}

static int agent_cancel(sd_bus_message *m, void *userdata, sd_bus_error *err)
{
	(void)userdata; (void)err;
	return sd_bus_reply_method_return(m, "");
}

static const sd_bus_vtable agent_vtable[] = {
	SD_BUS_VTABLE_START(0),
	SD_BUS_METHOD("RequestPassphrase", "o", "s", agent_request_passphrase,
	              SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_METHOD("Cancel", "s", "", agent_cancel, SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_METHOD("Release", "", "", agent_cancel, SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_VTABLE_END
};

static int cmd_connect(const char *ssid, const char *passphrase)
{
	struct net n;
	sd_bus_slot *slot = NULL;
	sd_bus_error err = SD_BUS_ERROR_NULL;
	int r;

	if ((r = find_by_name(ssid, &n)) < 0) {
		fprintf(stderr, "portnet: %s: not in range\n", ssid);
		return 10;      /* the launcher reads 10 as "gone" */
	}

	if (passphrase && *passphrase) {
		join_passphrase = passphrase;
		if ((r = sd_bus_add_object_vtable(bus, &slot, AGENT_PATH, IF_AGENT,
		                                  agent_vtable, NULL)) < 0)
			return fail("agent", r);
		r = sd_bus_call_method(bus, IWD, "/net/connman/iwd", IF_AGENT_MANAGER,
		                       "RegisterAgent", &err, NULL, "o", AGENT_PATH);
		if (r < 0) {
			fprintf(stderr, "portnet: RegisterAgent: %s\n",
			        err.message ? err.message : strerror(-r));
			sd_bus_error_free(&err);
			sd_bus_slot_unref(slot);
			return 1;
		}
		sd_bus_error_free(&err);
	}

	/* Connect blocks until the association resolves, and the agent
	 * callback has to be served while it does - so this drives the bus
	 * by hand rather than using the synchronous call. */
	sd_bus_message *call = NULL;
	r = sd_bus_message_new_method_call(bus, &call, IWD, n.path, IF_NETWORK, "Connect");
	if (r >= 0)
		r = sd_bus_call_async(bus, NULL, call, NULL, NULL, 0);
	sd_bus_message_unref(call);
	if (r < 0) {
		sd_bus_slot_unref(slot);
		return fail("Connect", r);
	}

	int rc = 4;   /* the launcher reads 4 as "the password was wrong" */
	for (int i = 0; i < 300; i++) {          /* 30 s, in 100 ms steps */
		sd_bus_process(bus, NULL);
		struct net now;
		if (find_by_name(ssid, &now) == 0 && now.connected) {
			rc = 0;
			break;
		}
		sd_bus_wait(bus, 100 * 1000);
	}

	if (slot) {
		sd_bus_error e2 = SD_BUS_ERROR_NULL;
		sd_bus_call_method(bus, IWD, "/net/connman/iwd", IF_AGENT_MANAGER,
		                   "UnregisterAgent", &e2, NULL, "o", AGENT_PATH);
		sd_bus_error_free(&e2);
		sd_bus_slot_unref(slot);
		/* Asked for the passphrase and still not connected: it was wrong.
		 * Never asked: the failure was something else. */
		if (rc != 0 && !agent_result)
			rc = 1;
	}
	return rc;
}

static int cmd_disconnect(void)
{
	char station[256] = "";
	sd_bus_error err = SD_BUS_ERROR_NULL;
	int r;

	if ((r = survey(NULL, NULL, station, sizeof(station), NULL, 0, NULL)) < 0)
		return fail("survey", r);
	if (!station[0])
		return 0;

	r = sd_bus_call_method(bus, IWD, station, IF_STATION, "Disconnect", &err, NULL, "");
	if (r < 0) {
		fprintf(stderr, "portnet: Disconnect: %s\n",
		        err.message ? err.message : strerror(-r));
		sd_bus_error_free(&err);
		return 1;
	}
	sd_bus_error_free(&err);
	return 0;
}

static int cmd_radio(const char *arg)
{
	char adapter[256] = "";
	bool powered = false;
	int r;

	if ((r = survey(NULL, NULL, NULL, 0, adapter, sizeof(adapter), &powered)) < 0)
		return fail("survey", r);
	if (!adapter[0]) {
		fprintf(stderr, "portnet: no adapter\n");
		return 1;
	}

	if (!arg) {
		puts(powered ? "on" : "off");
		return 0;
	}

	int want = !strcmp(arg, "on");
	sd_bus_error err = SD_BUS_ERROR_NULL;
	r = sd_bus_set_property(bus, IWD, adapter, IF_ADAPTER, "Powered", &err, "b", want);
	if (r < 0) {
		fprintf(stderr, "portnet: Powered: %s\n",
		        err.message ? err.message : strerror(-r));
		sd_bus_error_free(&err);
		return 1;
	}
	sd_bus_error_free(&err);
	return 0;
}

static int cmd_status(void)
{
	struct net nets[MAX_NETS];
	char station[256] = "";
	int count = 0;

	if (survey(nets, &count, station, sizeof(station), NULL, 0, NULL) < 0)
		return 1;
	for (int i = 0; i < count; i++)
		if (nets[i].connected) {
			printf("%s\n", nets[i].name);
			return 0;
		}
	return 1;
}

static void usage(void)
{
	fputs("portnet - Wi-Fi through iwd\n\n"
	      "  portnet list [--rescan]   SSID\\tknown\\tconnected\\tsignal\\ttype\n"
	      "  portnet connect <ssid>    a network iwd already has a key for\n"
	      "  portnet join <ssid> <pw>  0 ok, 4 wrong passphrase, 10 not in range\n"
	      "  portnet disconnect\n"
	      "  portnet radio [on|off]    with no argument, prints the state\n"
	      "  portnet status            prints the connected SSID, or exits 1\n",
	      stderr);
}

int main(int argc, char **argv)
{
	int r = sd_bus_open_system(&bus);
	if (r < 0)
		return fail("system bus", r);

	int rc = 1;
	if (argc < 2)
		usage();
	else if (!strcmp(argv[1], "list"))
		rc = cmd_list(argc > 2 && !strcmp(argv[2], "--rescan"));
	else if (!strcmp(argv[1], "connect") && argc > 2)
		rc = cmd_connect(argv[2], NULL);
	else if (!strcmp(argv[1], "join") && argc > 3)
		rc = cmd_connect(argv[2], argv[3]);
	else if (!strcmp(argv[1], "disconnect"))
		rc = cmd_disconnect();
	else if (!strcmp(argv[1], "radio"))
		rc = cmd_radio(argc > 2 ? argv[2] : NULL);
	else if (!strcmp(argv[1], "status"))
		rc = cmd_status();
	else
		usage();

	sd_bus_flush_close_unref(bus);
	return rc;
}
