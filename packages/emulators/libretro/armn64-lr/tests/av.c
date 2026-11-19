/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Exercise the real core with a generated idle ROM and a headless frontend. */
#include "libretro/libretro.c"
#include <assert.h>

static unsigned avChanges;
static size_t samplesReceived;
static int16_t lastSamples[16];
static struct retro_system_av_info announced;

static bool frontend(unsigned cmd, void* data) {
	if (cmd == RETRO_ENVIRONMENT_SET_PIXEL_FORMAT) return true;
	if (cmd == RETRO_ENVIRONMENT_GET_VARIABLE) {
		struct retro_variable* v = data;
		v->value = !strcmp(v->key, "armn64_renderer") ? "cpu" : NULL;
		return v->value != NULL;
	}
	if (cmd == RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE) {
		*(bool*) data = false;
		return true;
	}
	if (cmd == RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO) {
		announced = *(struct retro_system_av_info*) data;
		++avChanges;
		return true;
	}
	return false;
}

static void video(const void* data, unsigned w, unsigned h, size_t pitch) { }
static void poll(void) { }
static int16_t input(unsigned port, unsigned device, unsigned index, unsigned id) { return 0; }
static size_t audio(const int16_t* data, size_t frames) {
	size_t copy = frames * 2 < 16 ? frames * 2 : 16;
	memcpy(lastSamples, data, copy * sizeof(*data));
	samplesReceived += frames;
	return frames;
}

static void closeTo(double got, double want) {
	if (fabs(got - want) > 0.000001) {
		fprintf(stderr, "got %.9f, expected %.9f\n", got, want);
		abort();
	}
}

int main(void) {
	uint8_t rom[0x1000] = { 0 };
	put32(rom, 0x80371240);
	rom[0x3E] = 'E';
	put32(rom + 0x40, 0x1000FFFF); /* Branch to itself, with a NOP delay slot. */
	retro_set_environment(frontend);
	retro_set_video_refresh(video);
	retro_set_audio_sample_batch(audio);
	retro_set_input_poll(poll);
	retro_set_input_state(input);
	struct retro_game_info gameInfo = { "idle.z64", rom, sizeof(rom), NULL };
	assert(retro_load_game(&gameInfo));
	struct retro_system_av_info info;
	retro_get_system_av_info(&info);
	closeTo(info.timing.fps, 48681812.0 / 813722);
	closeTo(info.timing.sample_rate, 32040);

	/* The real retro_run path must notify once, then keep quiet until a change. */
	uint32_t const dividers[] = { 2209, 1520, 1104 };
	for (unsigned i = 0; i < sizeof(dividers) / sizeof(*dividers); ++i) {
		busWrite32(machine, 0x04500010, dividers[i] - 1);
		busWrite32(machine, 0x04500000, 0);
		busWrite32(machine, 0x04500004, 8);
		assert(machine->ai.endsAt - machine->ai.startedAt == (uint64_t) 2 * CPU_HZ * dividers[i] / 48681812);
		machine->ai.queued = 0;
		unsigned before = avChanges;
		retro_run();
		assert(avChanges == before + 1);
		closeTo(announced.timing.sample_rate, 48681812.0 / dividers[i]);
		retro_run();
		assert(avChanges == before + 1);
	}

	/* Native stereo frames arrive byte-for-byte, without a second resampler. */
	int16_t const expected[] = { -32768, 32767, -1234, 2345, 0, 1, 5678, -6789 };
	memcpy(captured, expected, sizeof(expected));
	machine->audioCount = sizeof(expected) / sizeof(*expected);
	machine->audioRate = 22037;
	samplesReceived = 0;
	playAudio();
	assert(samplesReceived == 4);
	assert(!memcmp(lastSamples, expected, sizeof(expected)));

	/* Keep the existing ParaLLEl cartridge-save layout, including byte order. */
	assert(SAVE_SIZE == 0x48800);
	for (size_t i = FILE_SRAM; i < SAVE_SIZE; ++i) saveMemory[i] = (uint8_t) (i ^ (i >> 8));
	uint8_t saved[SAVE_SIZE];
	memcpy(saved, saveMemory, sizeof(saved));
	saveImport();
	saveExport();
	assert(!memcmp(saved, saveMemory, sizeof(saved)));

	/* NTSC interlace, PAL and MPAL; H_SYNC changes independently of V_SYNC. */
	struct { uint32_t tv, v, h, clock; } modes[] = {
		{ 1, 0x20C, 0xC15, 48681812 },
		{ 0, 0x271, 0xC69, 49656530 },
		{ 2, 0x20D, 0xC15, 48628316 },
		{ 1, 0x20D, 0xC16, 48681812 },
	};
	for (unsigned i = 0; i < sizeof(modes) / sizeof(*modes); ++i) {
		machine->tvType = modes[i].tv;
		busWrite32(machine, 0x04400018, modes[i].v);
		busWrite32(machine, 0x0440001C, modes[i].h);
		unsigned before = avChanges;
		retro_run();
		assert(avChanges == before + 1);
		double fps = (double) modes[i].clock * 2 / ((modes[i].v + 1) * (modes[i].h + 1));
		closeTo(announced.timing.fps, fps);
		closeTo(announced.timing.sample_rate, (double) modes[i].clock / 1104);
		assert(llabs((long long) machine->fieldCycles - llround(CPU_HZ / fps)) <= 1);
	}

	/* CPU overclocking changes cycles, never the VI or AI clocks. */
	machine->stats.siDmas = 1;
	machine->ocWantNum = 2;
	machine->ocWantDen = 1;
	unsigned before = avChanges;
	retro_run();
	assert(avChanges == before);
	assert(machine->ocNum == 2);
	assert(machine->fieldCycles == 2 * (uint64_t) llround(CPU_HZ / announced.timing.fps));
	retro_reset();
	retro_run();
	closeTo(announced.timing.fps, 48681812.0 / 813722);
	closeTo(announced.timing.sample_rate, 32040);
	retro_unload_game();
	puts("PASS: native audio, dynamic AV updates, VI periods, regions, overclock and reset");
	return 0;
}
