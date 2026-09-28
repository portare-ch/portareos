# Playing at the console's sample rate on the Retroid Pocket Nova

How PortareOS makes the Nova's audio link run at 32, 44.1 or 48 kHz instead
of resampling everything to 48 kHz, and how to carry that to another
distribution. Everything here was verified on the device (kernel 7.2.5,
September 2026).

## Why the link is stuck at 48 kHz

The Nova's audio is Qualcomm AudioReach: a DSP graph, MI2S to two aw88166
speaker amps, and a codec DMA path to the WCD938x headphone codec. Four
things pin playback to 48 kHz, in the order a request meets them:

1. **The topology blob** (`qcom/sm8550/AYN-Odin2-tplg.bin`) declares the
   playback PCMs' capabilities: `rates = 0`, `rate_min = rate_max = 48000`.
   The frontend is constrained to that before any kernel code sees the
   request. A 32 kHz request is answered with the nearest allowed rate
   (`Warning: rate is not accurate (requested = 32000Hz, got = 44100Hz)`)
   and nothing in `dmesg` says why. **Without this step, the kernel patches
   below change nothing.**
2. **The DAI rate masks** in `sound/soc/qcom/qdsp6/q6dsp-lpass-ports.c`.
   The speaker port, `PRIMARY_MI2S_RX`, is written out longhand with
   `48000 | 8000 | 16000` only; the headphone port uses the CDC-DMA macro,
   which lacks 44100.
3. **The machine driver's fixup**, `sc8280xp_be_hw_params_fixup()` in
   `sound/soc/qcom/sc8280xp.c`, which pins every backend to 48000 and
   S16_LE stereo. With only the masks widened, the DSP resamples instead.
4. **The I2S bit clock**, `LPASS_CLK_ID_SEN_MI2S_IBIT`, fixed by the device
   tree (`assigned-clock-rates = <1536000>`, that is 48000 × 2 × 16) and
   enabled at startup. The link runs at a 48 kHz bit clock whatever the
   sample rate.

The headphone path (codec DMA) has no bit clock of its own and needs only
steps 1 to 3.

## The changes, in order

All paths are in this repository; the patches apply to Linux 7.2.5.

### 1. The topology blob

`projects/PortareOS/packages/linux-firmware/extra-firmware/sources/tplg-playback-rates.py`,
run by `extra-firmware`'s `package.mk` on the shipped blob.

The blob is ALSA topology: a sequence of blocks with a 36-byte header
(magic `0x41536F43`, ABI, version, type, header size, vendor type, payload
size, index, count). In each block of type 7 (PCM), every PCM record holds a
name at offset 4, `playback` and `capture` flags at offset 100, and, after
the 8 stream records of 72 bytes, a capability block whose `rates`,
`rate_min` and `rate_max` sit at offset 56. The script finds the playback
PCMs (`MultiMedia1 Playback` and `MultiMedia2 Playback`), sets
`rates = SNDRV_PCM_RATE_32000 | 44100 | 48000` (bits 5, 6 and 7),
`rate_min = 32000`, `rate_max = 48000`, and leaves capture alone. It checks
the input hash and the output hash, so a different blob is refused rather
than mis-edited.

Rebuilding the blob from the AudioReach topology source was tried first;
the available `.m4` does not reproduce the shipped binary, hence the
in-place edit.

### 2. Kernel patches (`projects/PortareOS/devices/SM8550/patches/linux/`)

| Patch | File | What it does |
| --- | --- | --- |
| `1052-…-allow-44100-on-the-rx-dais` | `q6dsp-lpass-ports.c` | Adds 44100 to the MI2S and CDC-DMA RX macros and to the longhand `Primary MI2S Playback` entry. |
| `1053-…-allow-44100-backends` | `sc8280xp.c` | In the backend fixup, keeps the frontend's rate when it is exactly 44100 on `PRIMARY_MI2S_RX` and `RX_CODEC_DMA_RX_0`; every other backend stays pinned (`DISPLAY_PORT_RX_0` offers only 48/96/192 kHz). |
| `1054-…-mi2s-bit-clock-from-stream` | `sc8280xp.c` | In the machine `prepare`, sets the MI2S bit clock to rate × channels × width. A q6dsp clock only reports its rate to the DSP when prepared, and startup has already prepared it, so on a rate change the clock is unprepared, set and prepared again; otherwise the port starts on the previous stream's clock and the DSP refuses `APM_CMD_GRAPH_START`. Done in `prepare`, before DAPM `PRE_PMU`, because the aw88166 amps check their PLL against BCLK there. |
| `1055-…-allow-32000-playback` | both | 32000 in the `Primary MI2S Playback` mask, and 32000 let through the fixup on the two playback ports. |

Two earlier patches matter for the amps: `0036` (Primary I2S support in the
machine driver, including the `i2s_clk` handling) and `0612` (start the RX
port at `prepare`, so BCLK is up before the amps' PLL check).

### 3. PipeWire

`projects/PortareOS/packages/audio/pipewire/patches/SM8550/002-graph-quantum.patch`:
`default.clock.allowed-rates = [ 48000 44100 32000 ]`. PipeWire then switches
the graph, and the link, to the rate of the stream that opens it.

### 4. Applications

RetroArch picks the output rate from the core's when `audio_out_rate` is
`"0"` (patch `0015-audio-out-rate-from-the-core.patch`): the smallest of
32000, 44100 and 48000 the core's rate divides into within 0.5 %, else the
smallest above it, else 48000, re-picked at every audio init so a core that
changes rate mid-session (ParaLLEl N64, per game) reopens the device to
match. A non-zero `audio_out_rate` in a per-core config
(`config/<core>/<core>.cfg`) overrides the pick. mpv plays at the
file's rate, for films and for PORTAMP alike. [REFRESH_RATES.md](REFRESH_RATES.md) has the table.

## Verifying on the device

```
# What the frontend allows. Before the blob edit this printed [44100 48000].
aplay -D hw:0,0 --dump-hw-params -f S16_LE -c 2 -r 48000 -d 0 /dev/zero 2>&1 | grep ^RATE

# A request at the rate, without the "not accurate" warning:
aplay -D hw:0,0 -f S16_LE -c 2 -r 32000 -d 1 /dev/zero

# While something plays: the link rate, the bit clock, and the DSP's verdict.
grep ^rate /proc/asound/card0/pcm0p/sub0/hw_params        # rate: 32000 (32000/1)
cat /sys/kernel/debug/clk/LPASS_CLK_ID_SEN_MI2S_IBIT/clk_rate  # 1024000 = 32000 x 2 x 16
dmesg | grep -i "bit clock\|APM_CMD"                        # must stay empty
```

Then switch rates in a row (48 → 32 → 44.1 → 48) and check that each
stream starts. `aplay -D hw:0,0` bypasses PipeWire and its volume control:
the tone will be loud.

## Testing a blob without rebuilding the image

The blob is not built into the kernel (`CONFIG_EXTRA_FIRMWARE` carries only
the regulatory database), so it is loaded from `/lib/firmware` when the sound
card binds, and `/lib/firmware` is a writable tmpfs of symlinks into the
kernel overlay:

```
systemctl stop pipewire-pulse.service pipewire.service wireplumber.service pipewire.socket pipewire-pulse.socket
rm /lib/firmware/qcom/sm8550/AYN-Odin2-tplg.bin
cp /tmp/AYN-Odin2-tplg.bin /lib/firmware/qcom/sm8550/
echo sound > /sys/bus/platform/drivers/snd-sc8280xp/unbind
echo sound > /sys/bus/platform/drivers/snd-sc8280xp/bind
systemctl start pipewire.socket pipewire-pulse.socket pipewire.service wireplumber.service pipewire-pulse.service
```

The topology is loaded in the `qcom-apm` component's probe, which runs on
card bind. A reboot restores the shipped blob.

## Porting to another distribution

* Take the four kernel patches as they are; they touch only
  `q6dsp-lpass-ports.c` and `sc8280xp.c`. The bit-clock name and the
  `assigned-clock-rates` come from the board's device tree; check the sound
  node.
* Apply the topology edit to your copy of the blob. If the hash differs from
  the one in the script, the blob is a different build: read the PCM blocks
  and check the offsets before editing, and record both hashes.
* Add the rates to PipeWire's `allowed-rates`, or to whatever your sound
  server uses to pick the device rate.
* Ask for the rate per application. A global 44.1 kHz would only move the
  resampling for everything else.

Not viable: rates the hardware cannot carry, such as an exact 32040 (the
SNES's) or 32768 (the Game Boy's). The headphone codec has no rate code for
them, and the DSP's endpoints and clock table only offer the standard
rates. portare-ch/portareos#290 has the analysis.
