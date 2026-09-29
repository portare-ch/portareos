// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)
//
// pcm-flags - what the driver says about a PCM, rather than what we infer.
//
// SNDRV_PCM_INFO_BATCH is a kernel flag no /proc file prints. It decides
// whether PipeWire keeps an extra period queued (recalc_headroom()), which on
// this device was the largest term in the audio latency budget. q6apm-dai sets
// it unconditionally upstream; patch 1074 clears it when the graph runs in
// push-pull mode, where the DSP publishes a sample-accurate position.
//
// alsa-lib exposes it as snd_pcm_hw_params_is_batch(), so ask.
//
// The device PipeWire holds cannot be opened again, but the Nova's topology
// carries two playback graphs and PipeWire uses one, so the other answers the
// same question about the same driver.

#include <alsa/asoundlib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void flag(const char *name, int v)
{
	printf("  %-22s %s\n", name, v ? "yes" : "no");
}

int main(int argc, char **argv)
{
	const char *dev = argc > 1 ? argv[1] : "hw:0,1";
	unsigned int rate = argc > 2 ? (unsigned)atoi(argv[2]) : 32000;
	snd_pcm_t *pcm;
	snd_pcm_hw_params_t *hw;
	snd_pcm_uframes_t pmin, pmax, bmin, bmax;
	int err;

	if ((err = snd_pcm_open(&pcm, dev, SND_PCM_STREAM_PLAYBACK, 0)) < 0) {
		fprintf(stderr, "%s: %s\n", dev, snd_strerror(err));
		return 1;
	}
	snd_pcm_hw_params_alloca(&hw);
	if ((err = snd_pcm_hw_params_any(pcm, hw)) < 0) {
		fprintf(stderr, "hw_params_any: %s\n", snd_strerror(err));
		return 1;
	}

	printf("%s\n\n", dev);
	printf("info flags, as the driver reports them:\n");
	flag("BATCH", snd_pcm_hw_params_is_batch(hw));
	flag("BLOCK_TRANSFER", snd_pcm_hw_params_is_block_transfer(hw));
	flag("MONOTONIC", snd_pcm_hw_params_is_monotonic(hw));
	flag("can pause", snd_pcm_hw_params_can_pause(hw));
	flag("can resume", snd_pcm_hw_params_can_resume(hw));
	flag("no period wakeup", snd_pcm_hw_params_can_disable_period_wakeup(hw));

	snd_pcm_hw_params_set_access(pcm, hw, SND_PCM_ACCESS_MMAP_INTERLEAVED);
	snd_pcm_hw_params_set_format(pcm, hw, SND_PCM_FORMAT_S16_LE);
	snd_pcm_hw_params_set_channels(pcm, hw, 2);
	if ((err = snd_pcm_hw_params_set_rate(pcm, hw, rate, 0)) < 0) {
		printf("\nrate %u: %s\n", rate, snd_strerror(err));
		snd_pcm_close(pcm);
		return 0;
	}

	snd_pcm_hw_params_get_period_size_min(hw, &pmin, NULL);
	snd_pcm_hw_params_get_period_size_max(hw, &pmax, NULL);
	snd_pcm_hw_params_get_buffer_size_min(hw, &bmin);
	snd_pcm_hw_params_get_buffer_size_max(hw, &bmax);
	printf("\nat %u Hz:\n", rate);
	printf("  period size   %lu .. %lu frames\n", (unsigned long)pmin, (unsigned long)pmax);
	printf("  buffer size   %lu .. %lu frames\n", (unsigned long)bmin, (unsigned long)bmax);

	// Which period sizes the driver will actually take. The step is the
	// thing #422 changed, so read it rather than trust the patch.
	printf("  accepted      ");
	for (snd_pcm_uframes_t p = 32; p <= 1024; p += 32) {
		snd_pcm_hw_params_t *t;
		snd_pcm_hw_params_alloca(&t);
		snd_pcm_hw_params_copy(t, hw);
		if (snd_pcm_hw_params_test_period_size(pcm, t, p, 0) == 0)
			printf("%lu ", (unsigned long)p);
	}
	printf("\n");

	snd_pcm_close(pcm);
	return 0;
}
