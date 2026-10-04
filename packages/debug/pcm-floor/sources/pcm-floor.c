// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)
//
// pcm-floor: the lowest latency the driver will actually sustain.
//
// pcm-flags says which period sizes a PCM accepts. This streams at each of
// them and counts what goes wrong, which is the part that decides anything:
// a period the driver advertises and then underruns on is not a floor.
//
// It opens the hardware device directly, so it measures the driver and the
// DSP with nothing else in the path - no PipeWire quantum, no RetroArch ring.
// That is the number the rest of the stack sits on top of, and until #422's
// period_min_ms became a parameter it could not be probed at all: 320 frames
// at 32kHz was this fork's own floor, not the hardware's.
//
// Silence is written rather than a tone. The question is whether the DSP keeps
// up, and a buffer of zeros exercises the same path without making noise.
//
// hw:0,0, and PipeWire has to be stopped first - this needs the device to
// itself. Note that hw:0,1 is not a substitute: it answers hw_params queries
// with the same constraints, which is why pcm-flags reads it while PipeWire
// holds the other, but a write to it returns EIO. It has no route behind it.

#include <alsa/asoundlib.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct result {
	snd_pcm_uframes_t period, buffer;
	unsigned int xruns;
	double delay_ms, asked_ms;
	bool ran;
	int err;
};

// One pass: configure, stream for the requested time, count underruns.
static void try_period(const char *dev, unsigned int rate, unsigned int chans,
		       snd_pcm_uframes_t want, unsigned int periods,
		       double seconds, struct result *r)
{
	snd_pcm_t *pcm = NULL;
	snd_pcm_hw_params_t *hw;
	snd_pcm_uframes_t period = want, buffer = want * 2;
	int err;
	int16_t *silence = NULL;
	long frames_to_write;
	unsigned int stalls;

	memset(r, 0, sizeof(*r));
	r->asked_ms = want * 1000.0 / rate;

	err = snd_pcm_open(&pcm, dev, SND_PCM_STREAM_PLAYBACK, 0);
	if (err < 0) {
		r->err = err;
		return;
	}
	(void)periods;

	snd_pcm_hw_params_alloca(&hw);
	snd_pcm_hw_params_any(pcm, hw);

	// MMAP because that is what this driver and PipeWire both use; asking
	// for RW_INTERLEAVED here would measure a path nothing else takes.
	if ((err = snd_pcm_hw_params_set_access(pcm, hw,
			SND_PCM_ACCESS_MMAP_INTERLEAVED)) < 0 ||
	    (err = snd_pcm_hw_params_set_format(pcm, hw, SND_PCM_FORMAT_S16_LE)) < 0 ||
	    (err = snd_pcm_hw_params_set_channels(pcm, hw, chans)) < 0 ||
	    (err = snd_pcm_hw_params_set_rate(pcm, hw, rate, 0)) < 0) {
		r->err = err;
		goto out;
	}

	// The rate has to be a single value before the period rule can step by
	// frames, which is why it is set above and not _near'd here.
	if ((err = snd_pcm_hw_params_set_period_size_near(pcm, hw, &period, NULL)) < 0 ||
	    (err = snd_pcm_hw_params_set_buffer_size_near(pcm, hw, &buffer)) < 0 ||
	    (err = snd_pcm_hw_params(pcm, hw)) < 0) {
		r->err = err;
		goto out;
	}

	r->period = period;
	r->buffer = buffer;

	// Without these the start threshold is whatever the driver defaults to,
	// and if that is above the buffer the stream never starts: the writes
	// fill the buffer once and then block forever.
	{
		snd_pcm_sw_params_t *sw;

		snd_pcm_sw_params_alloca(&sw);
		snd_pcm_sw_params_current(pcm, sw);
		snd_pcm_sw_params_set_start_threshold(pcm, sw, buffer);
		snd_pcm_sw_params_set_avail_min(pcm, sw, period);
		if ((err = snd_pcm_sw_params(pcm, sw)) < 0) {
			r->err = err;
			goto out;
		}
	}

	silence = calloc(period * chans, sizeof(int16_t));
	if (!silence) {
		r->err = -ENOMEM;
		goto out;
	}

	frames_to_write = (long)(seconds * rate);
	// A write that makes no progress would otherwise spin here forever,
	// which is the one way a tool like this can be worse than no tool.
	stalls = 0;
	while (frames_to_write > 0) {
		snd_pcm_sframes_t wrote = snd_pcm_mmap_writei(pcm, silence, period);

		if (wrote == 0 && ++stalls > 1000) {
			r->err = -ETIMEDOUT;
			goto out;
		}
		if (wrote > 0)
			stalls = 0;

		if (wrote == -EPIPE) {
			r->xruns++;
			snd_pcm_prepare(pcm);
			continue;
		}
		if (wrote == -ESTRPIPE) {
			while (snd_pcm_resume(pcm) == -EAGAIN)
				usleep(1000);
			snd_pcm_prepare(pcm);
			continue;
		}
		if (wrote < 0) {
			r->err = wrote;
			goto out;
		}
		frames_to_write -= wrote;

		// Once, in the middle, so the reading is of a running stream
		// rather than of one still filling.
		if (!r->delay_ms && frames_to_write < (long)(seconds * rate) / 2) {
			snd_pcm_sframes_t d = 0;

			if (snd_pcm_delay(pcm, &d) == 0 && d > 0)
				r->delay_ms = d * 1000.0 / rate;
		}
	}
	r->ran = true;

out:
	free(silence);
	if (pcm) {
		snd_pcm_drop(pcm);
		snd_pcm_close(pcm);
	}
}

int main(int argc, char **argv)
{
	const char *dev = "hw:0,0";
	unsigned int rate = 32000, chans = 2;
	double seconds = 3.0;
	struct result r;
	snd_pcm_uframes_t tested[16];
	size_t ntested = 0;
	snd_pcm_uframes_t cand[] = { 32, 64, 96, 128, 160, 192, 256, 320,
				     384, 448, 480, 640, 960 };
	bool any = false;

	for (int i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--device") && i + 1 < argc)
			dev = argv[++i];
		else if (!strcmp(argv[i], "--rate") && i + 1 < argc)
			rate = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--channels") && i + 1 < argc)
			chans = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--seconds") && i + 1 < argc)
			seconds = atof(argv[++i]);
		else {
			fprintf(stderr,
				"usage: %s [--device hw:0,0] [--rate 32000]"
				" [--channels 2] [--seconds 3]\n"
				"  streams silence at each period size the driver"
				" accepts and counts underruns\n", argv[0]);
			return 2;
		}
	}

	// Each step opens and tears down a DSP graph, so this takes a while.
	// Line-buffered or the output arrives only at the end, over ssh.
	setvbuf(stdout, NULL, _IOLBF, 0);

	printf("%s, %u Hz, %u channels, %.1fs a step\n\n", dev, rate, chans, seconds);
	printf("  asked   granted   buffer   latency   xruns\n");

	for (size_t i = 0; i < sizeof(cand) / sizeof(cand[0]); i++) {
		bool seen = false;

		printf("  %5.2fms  ", cand[i] * 1000.0 / rate);
		fflush(stdout);   /* no newline yet, so line buffering will not */
		try_period(dev, rate, chans, cand[i], 2, seconds, &r);

		// The driver rounds a period up to its own step, so most of the
		// candidate list lands on the same few values. Streaming each
		// of them again costs seconds and says nothing.
		for (size_t j = 0; j < ntested; j++)
			if (tested[j] == r.period)
				seen = true;
		if (!r.err && seen) {
			printf("%5lu     (same as above, skipped)\n", r.period);
			continue;
		}
		if (!r.err && ntested < sizeof(tested) / sizeof(tested[0]))
			tested[ntested++] = r.period;

		if (r.err) {
			// A period the driver refuses outright is not a failure
			// of the driver, it is the answer to the question.
			printf("refused             %s\n", snd_strerror(r.err));
			continue;
		}
		// The rule rounds up, so several candidates land on one period.
		// Only report the first that reaches each.
		printf("%5lu     %5lu    %6.2fms   %u%s\n",
		       r.period, r.buffer, r.delay_ms, r.xruns,
		       r.xruns ? "  <- not sustained" : "");
		if (!r.xruns && !any) {
			any = true;
			printf("           ^ lowest period streamed without an underrun\n");
		}
	}

	printf("\nGranted may exceed asked: the driver rounds a period up to its\n"
	       "own floor, which on this fork is period_min_ms of frames at the\n"
	       "stream's rate, rounded to period_align. Both are module\n"
	       "parameters on q6apm_dai; a floor this tool cannot get under is\n"
	       "the driver's, not the DSP's, until that is lowered too.\n");
	return 0;
}
