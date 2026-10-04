#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present PortareOS

"""Move the AYN-Odin2 topology's playback graphs to SH_MEM_PULL_MODE.

The playback graphs end in WR_SHARED_MEM_EP, which publishes no position
of its own, so q6apm_dai_pointer() can only report

    q6apm_get_hw_pointer(graph, stream) * runtime->period_size

- the DSP's buffer index, a whole period at a time. The kernel then
advertises SNDRV_PCM_INFO_BATCH, and PipeWire keeps one extra period
queued on top of its quantum to cover a pointer that jumps
(recalc_headroom(), spa/plugins/alsa/alsa-pcm.c). Every stream on the
device pays that period twice over: once as latency, once as jitter.

SH_MEM_PULL_MODE is the same endpoint with a position buffer. The DSP
writes a frame counter and an index into shared memory and the driver
reads the position from there, exactly. Everything needed for it is
already in the kernel - q6apm_push_pull_config(), the watermark event,
the pos_buffer read in q6apm_dai_pointer() - and the mode is selected by
nothing more than the module being present in the graph:

    iid = q6apm_graph_get_module_iid(graph, MODULE_ID_SH_MEM_PULL_MODE);
    if (iid < 0)
        iid = q6apm_graph_get_module_iid(graph, MODULE_ID_WR_SHARED_MEM_EP);
    else
        graph->info->is_push_pull_mode = true;

Both modules take the same topology configuration - audioreach.c routes
them to one audioreach_shmem_set_media_format() - so this is a change of
module id and nothing else.

The Nova's own ADSP firmware implements it. Its module registry
(adsp.mbn, 16-byte rows of {type, module_id, entry, entry}) carries
0x07001006 with real entry points, next to 0x07001007:

    0x07001006  type 0x0b  0xb054a990  0xb054ab98
    0x07001007  type 0x0b  0xb054ab6c  0xb054ac58
    0x07001000  type 0x01  0x00000000  0x00000000
    0x07001001  type 0x01  0x00000000  0x00000000

Capture is left alone. RD_SHARED_MEM_EP has the same limitation and
SH_MEM_PUSH_MODE is implemented too, but nothing here records at low
latency, so it is not worth the risk until something does.

Runs after tplg-playback-rates.py; IN_SHA256 is that script's output.
"""

import hashlib
import struct
import sys

IN_SHA256 = "82f8b0f3b8a78cbcd8aac7d23a8feb428aa3d97a7ddf184e410a0926c496d00d"
OUT_SHA256 = "b3f2327f9c5395055dee7189e984a7eac2d7ae8d513fa52b4eb3149518b39276"

# snd_soc_tplg_vendor_value_elem is {__le32 token; __le32 value}. Token 200
# is the module id, 201 the instance id.
AR_TKN_U32_MODULE_ID = 200
MODULE_ID_WR_SHARED_MEM_EP = 0x07001000
MODULE_ID_SH_MEM_PULL_MODE = 0x07001006


def patch(data):
    """Rewrite every (module id, WR_SHARED_MEM_EP) pair to pull mode."""
    find = struct.pack("<II", AR_TKN_U32_MODULE_ID, MODULE_ID_WR_SHARED_MEM_EP)
    repl = struct.pack("<II", AR_TKN_U32_MODULE_ID, MODULE_ID_SH_MEM_PULL_MODE)
    offsets = []
    off = data.find(find)
    while off != -1:
        data[off:off + len(repl)] = repl
        offsets.append(off)
        off = data.find(find, off + len(repl))
    return offsets


def main():
    if len(sys.argv) != 2:
        sys.exit(f"usage: {sys.argv[0]} AYN-Odin2-tplg.bin")
    path = sys.argv[1]
    data = bytearray(open(path, "rb").read())

    if hashlib.sha256(data).hexdigest() != IN_SHA256:
        sys.exit(f"{path}: not the topology this edit was made for")

    offsets = patch(data)
    # The two playback graphs, MultiMedia1 and MultiMedia2. The capture
    # graph's RD_SHARED_MEM_EP is a different module id and is not matched.
    if len(offsets) != 2:
        sys.exit(f"{path}: expected 2 playback endpoints, found {len(offsets)}")
    if hashlib.sha256(data).hexdigest() != OUT_SHA256:
        sys.exit(f"{path}: edit produced an unexpected file")

    open(path, "wb").write(data)
    print(f"{path}: playback endpoints at "
          f"{', '.join(hex(o) for o in offsets)} now SH_MEM_PULL_MODE")


if __name__ == "__main__":
    main()
