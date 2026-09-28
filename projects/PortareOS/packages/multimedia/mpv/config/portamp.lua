-- PORTAMP: a Winamp-shaped face for mpv, drawn on the OSD as ASS.
--
-- The bars in the middle are not drawn here: they are the video, a
-- showfreqs chain mpv renders underneath, sized and centred so this
-- chrome frames it. Everything else - the title bar, the scrolling
-- track, the time, the transport, the playlist - is vector drawing and
-- text over the top.

local mp = require 'mp'

local W, H = 1280, 960          -- the panel, and the ASS coordinate space
local GREEN   = "30FF30"        -- ASS colours are BBGGRR
local DIM     = "1A6B1A"
local FRAME   = "3B3B3B"
local FACE    = "101410"
local SHADOW  = "000000"

-- Where the analyser video lands: 900x260, centred by mpv. The OSD is
-- composited over the video, so nothing opaque may be drawn across this
-- rectangle - the chrome goes around it, in four bands, and the well is a
-- frame rather than a filled box. Painting a full-screen background here
-- hides the bars completely, which is exactly what it did the first time.
local VIS = { x = (W - 1000) / 2, y = (H - 340) / 2, w = 1000, h = 340 }
local HOLE = { x = VIS.x - 8, y = VIS.y - 8, w = VIS.w + 16, h = VIS.h + 16 }

local ov = mp.create_osd_overlay("ass-events")
ov.res_x, ov.res_y = W, H

local function rect(x, y, w, h, colour, alpha)
    return string.format(
        "{\\an7\\pos(%d,%d)\\bord0\\shad0\\1c&H%s&\\1a&H%02X&\\p1}" ..
        "m 0 0 l %d 0 l %d %d l 0 %d{\\p0}\n",
        x, y, colour, alpha or 0, w, w, h, h)
end

-- A sunken panel, the way every 1997 skin drew one.
local function bevel(x, y, w, h)
    return rect(x, y, w, h, SHADOW)
        .. rect(x + 2, y + 2, w - 4, h - 4, FACE)
end

-- Four thin sides, so whatever is underneath stays visible.
local function frame(x, y, w, h, t, colour)
    return rect(x, y, w, t, colour)
        .. rect(x, y + h - t, w, t, colour)
        .. rect(x, y, t, h, colour)
        .. rect(x + w - t, y, t, h, colour)
end

local function text(x, y, size, colour, s, align, bold)
    return string.format(
        "{\\an%d\\pos(%d,%d)\\fnLiberation Mono\\fs%d\\b%d\\bord2\\shad0" ..
        "\\1c&H%s&\\3c&H000000&}%s\n",
        align or 7, x, y, size, bold and 1 or 0, colour, s)
end

local function clock(t)
    t = math.max(0, math.floor(t or 0))
    return string.format("%d:%02d", math.floor(t / 60), t % 60)
end

-- Winamp scrolled anything that did not fit, and so does this: the
-- string is doubled with a separator and a window slid along it.
local function marquee(s, width, phase)
    if #s <= width then return s end
    local loop = s .. "   ***   "
    local i = (phase % #loop) + 1
    return ((loop .. loop):sub(i, i + width - 1))
end

local function bar(x, y, w, h, frac, colour)
    local out = rect(x, y, w, h, SHADOW) .. rect(x + 1, y + 1, w - 2, h - 2, FACE)
    local fill = math.floor((w - 4) * math.max(0, math.min(1, frac or 0)))
    if fill > 0 then out = out .. rect(x + 2, y + 2, fill, h - 4, colour) end
    return out
end

local phase = 0

local function draw()
    local title  = mp.get_property("media-title", "") or ""
    local pos    = mp.get_property_number("time-pos", 0) or 0
    local dur    = mp.get_property_number("duration", 0) or 0
    local paused = mp.get_property_bool("pause", false)
    local idx    = (mp.get_property_number("playlist-pos", 0) or 0) + 1
    local count  = mp.get_property_number("playlist-count", 1) or 1
    local vol    = mp.get_property_number("volume", 100) or 100
    local rate   = mp.get_property_number("audio-params/samplerate", 0) or 0
    local chans  = mp.get_property_number("audio-params/channel-count", 0) or 0

    local a = {}
    local function add(s) a[#a + 1] = s end

    -- The cabinet, in four bands around the analyser so the bars show
    -- through the middle.
    add(rect(0, 0, W, HOLE.y, FACE))
    add(rect(0, HOLE.y + HOLE.h, W, H - (HOLE.y + HOLE.h), FACE))
    add(rect(0, HOLE.y, HOLE.x, HOLE.h, FACE))
    add(rect(HOLE.x + HOLE.w, HOLE.y, W - (HOLE.x + HOLE.w), HOLE.h, FACE))
    add(frame(40, 40, W - 80, H - 80, 4, FRAME))

    -- title bar
    add(rect(44, 44, W - 88, 56, FRAME))
    add(text(W / 2, 72, 30, GREEN, "P O R T A M P", 5, true))

    -- the scrolling track, the way the real one nagged at you
    phase = phase + 1
    local shown = marquee(title, 40, math.floor(phase / 4))
    add(bevel(70, 124, W - 140, 62))
    add(text(90, 155, 36, GREEN, shown, 4, true))

    -- time, big, and the state beside it
    add(bevel(70, 200, 330, 96))
    add(text(90, 248, 64, GREEN, (paused and "" or " ") .. clock(pos), 4, true))
    add(text(420, 224, 26, DIM, string.format("%-9s %d / %d",
        paused and "PAUSED" or "PLAYING", idx, count), 4))
    add(text(420, 264, 26, DIM, string.format("%d kHz  %s  %s",
        math.floor(rate / 1000), chans == 2 and "stereo" or (chans .. "ch"),
        clock(dur)), 4))

    -- the well the bars sit in, drawn as a rim
    add(frame(HOLE.x, HOLE.y, HOLE.w, HOLE.h, 4, SHADOW))
    add(frame(HOLE.x + 4, HOLE.y + 4, HOLE.w - 8, HOLE.h - 8, 2, DIM))

    -- transport, position, volume
    add(text(90, H - 250, 40, GREEN, paused and "|| PAUSED" or "|>  PLAYING", 4, true))
    add(text(W - 90, H - 250, 30, DIM, "|< D-PAD >|    Y CYCLES", 6))
    add(bar(70, H - 200, W - 140, 26, dur > 0 and pos / dur or 0, GREEN))
    add(text(90, H - 140, 26, DIM, "VOL", 4))
    add(bar(160, H - 152, 300, 22, vol / 100, DIM))
    add(text(W - 90, H - 140, 26, DIM, string.format("%d %%", math.floor(vol)), 6))

    ov.data = table.concat(a)
    ov:update()
end

mp.add_periodic_timer(0.1, draw)
mp.register_event("file-loaded", draw)
