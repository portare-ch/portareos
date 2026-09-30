-- PORTAMP: a Linamp face - Winamp's main window as a radio display -
-- with the playlist below, drawn on the OSD as ASS.
--
-- The analyser bars are not drawn here: they are the video, a showfreqs
-- chain that portamp-filter.txt pads to the whole panel with the bars at
-- VIS. The OSD sits on top of the video, so every opaque shape here is
-- clipped around VIS with \iclip - paint over it and the bars vanish.

local mp = require 'mp'

local W, H = 1280, 960

-- Must match the pad offsets and size in portamp-filter.txt.
local VIS = { x = 64, y = 212, w = 360, h = 100 }

-- RRGGBB here; ASS wants BBGGRR.
local function c(rgb) return rgb:sub(5, 6) .. rgb:sub(3, 4) .. rgb:sub(1, 2) end

local BODY    = c("46519A")
local BODY_HI = c("7B86C9")
local BODY_LO = c("262D5E")
local LCD     = c("0B0F0B")
local LCD_RIM = c("9AA3D8")
local GREEN   = c("3CF03C")
local UNLIT   = c("0E260E")
local WHITE   = c("E8EAF6")
local DIMTXT  = c("737CB8")
local LIST_BG = c("000000")

local ICLIP = string.format("\\iclip(%d,%d,%d,%d)",
    VIS.x, VIS.y, VIS.x + VIS.w, VIS.y + VIS.h)

local ov = mp.create_osd_overlay("ass-events")
ov.res_x, ov.res_y = W, H

local function shape(x, y, colour, path)
    return string.format("{\\an7\\pos(%d,%d)\\bord0\\shad0%s\\1c&H%s&\\p1}%s{\\p0}\n",
        x, y, ICLIP, colour, path)
end

local function rect(x, y, w, h, colour)
    return shape(x, y, colour, string.format("m 0 0 l %d 0 l %d %d l 0 %d", w, w, h, h))
end

local function rrect(x, y, w, h, r, colour)
    return shape(x, y, colour, string.format(
        "m %d 0 l %d 0 b %d 0 %d 0 %d %d l %d %d b %d %d %d %d %d %d " ..
        "l %d %d b 0 %d 0 %d 0 %d l 0 %d b 0 0 0 0 %d 0",
        r, w - r, w, w, w, r, w, h - r, w, h, w, h, w - r, h,
        r, h, h, h, h - r, r, r))
end

-- A sunken well: the rim a shade lighter than the body, the inside dark.
local function well(x, y, w, h, fill)
    return rrect(x - 3, y - 3, w + 6, h + 6, 8, LCD_RIM)
        .. rrect(x, y, w, h, 6, fill or LCD)
end

local function text(x, y, an, font, size, colour, s, extra)
    return string.format("{\\an%d\\pos(%d,%d)\\fn%s\\fs%d\\bord0\\shad0\\1c&H%s&%s}%s\n",
        an, x, y, font, size, colour, extra or "", s)
end

-- Seven-segment digits, so the time reads like the display it imitates;
-- the unlit segments stay faintly visible, as on the real thing.
local SEGS = { ["0"] = "abcdef", ["1"] = "bc", ["2"] = "abged", ["3"] = "abgcd",
               ["4"] = "fgbc", ["5"] = "afgcd", ["6"] = "afgedc", ["7"] = "abc",
               ["8"] = "abcdefg", ["9"] = "abcdfg" }

local function hseg(x0, x1, yc, t)
    local h = t / 2
    return string.format("m %d %d l %d %d l %d %d l %d %d l %d %d l %d %d",
        x0, yc, x0 + h, yc - h, x1 - h, yc - h, x1, yc, x1 - h, yc + h, x0 + h, yc + h)
end

local function vseg(y0, y1, xc, t)
    local h = t / 2
    return string.format("m %d %d l %d %d l %d %d l %d %d l %d %d l %d %d",
        xc, y0, xc + h, y0 + h, xc + h, y1 - h, xc, y1, xc - h, y1 - h, xc - h, y0 + h)
end

local function digit(x, y, w, h, t, ch)
    local lit = SEGS[ch] or ""
    local g, m = 3, h / 2
    local p = {
        a = hseg(g, w - g, t / 2, t), g = hseg(g, w - g, m, t), d = hseg(g, w - g, h - t / 2, t),
        f = vseg(t / 2 + g, m - g, t / 2, t), b = vseg(t / 2 + g, m - g, w - t / 2, t),
        e = vseg(m + g, h - t / 2 - g, t / 2, t), c = vseg(m + g, h - t / 2 - g, w - t / 2, t),
    }
    local on, off = {}, {}
    for s, path in pairs(p) do
        if lit:find(s, 1, true) then on[#on + 1] = path else off[#off + 1] = path end
    end
    return shape(x, y, UNLIT, table.concat(off, " "))
        .. (#on > 0 and shape(x, y, GREEN, table.concat(on, " ")) or "")
end

-- Right-aligned at x1: "m:ss", or "mm:ss" past ten minutes.
local function sevenseg_time(x1, y, secs)
    secs = math.max(0, math.floor(secs or 0))
    local s = string.format("%d:%02d", math.floor(secs / 60), secs % 60)
    local DW, DH, T, GAP, COLON = 58, 108, 12, 14, 26
    local out, x = {}, x1
    for i = #s, 1, -1 do
        local ch = s:sub(i, i)
        if ch == ":" then
            x = x - COLON
            out[#out + 1] = rect(x + 7, y + DH * 0.28, 12, 12, GREEN)
                .. rect(x + 7, y + DH * 0.64, 12, 12, GREEN)
        else
            x = x - DW
            out[#out + 1] = digit(x, y, DW, DH, T, ch)
            x = x - GAP
        end
    end
    return table.concat(out)
end

local function clock(t)
    t = math.max(0, math.floor(t or 0))
    return string.format("%d:%02d", math.floor(t / 60), t % 60)
end

-- Anything longer than the window scrolls a character at a time, the
-- string doubled with a separator and a window slid along it.
local function marquee(s, width, phase)
    if #s <= width then return s end
    local loop = s .. "  ***  "
    local i = (phase % #loop) + 1
    return ((loop .. loop):sub(i, i + width - 1))
end

-- Playlist names and lengths. mpv only knows the playing file's tags and
-- duration, so each entry is probed once, one at a time, by a second
-- mpv that plays a hundredth of a second into nothing.
local info, probing, queue = {}, false, {}

local function label_for(path)
    local e = info[path]
    if e and e.title ~= "" then
        return (e.artist ~= "" and (e.artist .. " - ") or "") .. e.title
    end
    return (path:match("([^/]+)$") or path):gsub("%.[^.]+$", "")
end

local function probe_next()
    if probing or #queue == 0 then return end
    local path = table.remove(queue, 1)
    probing = true
    mp.command_native_async({
        name = "subprocess", playback_only = false,
        capture_stdout = true, capture_stderr = true,
        args = { "mpv", "--no-config", "--vo=null", "--ao=null", "--end=0.01",
                 "--term-playing-msg=PORTAMP|${=duration:}|${metadata/by-key/artist:}|${metadata/by-key/title:}",
                 "--", path },
    }, function(_, res)
        local out = res and ((res.stdout or "") .. (res.stderr or "")) or ""
        local d, a, t = out:match("PORTAMP|([^|\n]*)|([^|\n]*)|([^|\n]*)")
        info[path] = { duration = tonumber(d), artist = a or "", title = t or "" }
        probing = false
        probe_next()
    end)
end

local function sync_playlist()
    for _, e in ipairs(mp.get_property_native("playlist", {})) do
        if not info[e.filename] then
            info[e.filename] = { artist = "", title = "" }
            queue[#queue + 1] = e.filename
        end
    end
    probe_next()
end

local phase = 0

local function draw()
    local pos    = mp.get_property_number("time-pos", 0) or 0
    local dur    = mp.get_property_number("duration", 0) or 0
    local paused = mp.get_property_bool("pause", false)
    local rate   = mp.get_property_number("audio-params/samplerate", 0) or 0
    local chans  = mp.get_property_number("audio-params/channel-count", 0) or 0
    local kbps   = math.floor((mp.get_property_number("audio-bitrate", 0) or 0) / 1000 + 0.5)
    local list   = mp.get_property_native("playlist", {})
    local cur    = (mp.get_property_number("playlist-pos", 0) or 0) + 1
    local path   = mp.get_property("path", "") or ""

    local a = {}
    local function add(s) a[#a + 1] = s end

    -- the cabinet
    add(rect(0, 0, W, H, BODY))
    add(rect(24, 28, W - 48, 2, BODY_HI))

    -- the name plate: rails either side, the way the Linamp carries its own
    for _, y in ipairs({ 14, 22 }) do
        add(rect(40, y, 500, 4, WHITE))
        add(rect(W - 540, y, 500, 4, WHITE))
    end
    add(text(W / 2, 20, 5, "Liberation Sans", 34, WHITE, "PORTAMP",
        "\\b1\\fsp6\\bord2\\3c&H" .. BODY_LO .. "&"))

    -- left display: play state, the time, the analyser under it
    add(well(40, 64, 408, 268))
    if paused then
        add(rect(70, 96, 10, 34, GREEN) .. rect(88, 96, 10, 34, GREEN))
    else
        add(shape(70, 94, GREEN, "m 0 0 l 30 19 l 0 38"))
    end
    add(sevenseg_time(424, 84, pos))

    -- right column: the title, then the stream
    phase = phase + 1
    local e = info[path]
    local name = label_for(path)
    if e == nil or e.title == "" then
        local t = mp.get_property("media-title", "") or ""
        if t ~= "" then name = t end
    end
    local line = string.format("%d. %s (%s)", cur, name, clock(dur)):upper()
    add(well(476, 64, 764, 72))
    add(text(496, 100, 4, "Liberation Mono", 46, GREEN, marquee(line, 28, math.floor(phase / 3)),
        string.format("\\b1\\clip(%d,%d,%d,%d)", 480, 66, 1236, 134)))

    add(well(476, 164, 128, 60))
    add(text(590, 194, 6, "Liberation Mono", 44, GREEN, kbps > 0 and tostring(kbps) or "", "\\b1"))
    add(text(616, 194, 4, "Liberation Sans", 30, WHITE, "kbps", "\\b1"))
    add(well(712, 164, 88, 60))
    add(text(786, 194, 6, "Liberation Mono", 44, GREEN, rate > 0 and tostring(math.floor(rate / 1000)) or "", "\\b1"))
    add(text(812, 194, 4, "Liberation Sans", 30, WHITE, "kHz", "\\b1"))
    add(text(1100, 194, 6, "Liberation Sans", 28, chans == 1 and GREEN or DIMTXT, "mono", "\\b1"))
    add(text(1120, 194, 4, "Liberation Sans", 28, chans >= 2 and GREEN or DIMTXT, "stereo", "\\b1"))

    -- position, where the Linamp keeps its sliders
    add(well(476, 296, 764, 20, BODY_LO))
    local x = 480 + math.floor((764 - 72) * (dur > 0 and math.min(1, pos / dur) or 0))
    add(rrect(x, 290, 64, 32, 4, WHITE))
    for i = 0, 3 do add(rect(x + 20 + i * 7, 298, 3, 16, DIMTXT)) end

    -- playlist
    add(rect(24, 352, W - 48, 2, BODY_HI))
    add(text(W / 2, 374, 5, "Liberation Sans", 22, WHITE, "PLAYLIST", "\\b1\\fsp8"))
    local ROWS, RH, TOP = 13, 40, 394
    add(well(40, TOP, W - 80, ROWS * RH + 16, LIST_BG))
    local first = math.max(1, math.min(cur - 3, #list - ROWS + 1))
    for r = 0, ROWS - 1 do
        local i = first + r
        local entry = list[i]
        if not entry then break end
        local y = TOP + 8 + r * RH + RH / 2
        local colour = (i == cur) and WHITE or GREEN
        local d = (i == cur and dur > 0) and dur or (info[entry.filename] or {}).duration
        add(text(60, y, 4, "Liberation Sans", 32, colour,
            string.format("%d. %s", i, label_for(entry.filename)),
            string.format("\\clip(%d,%d,%d,%d)", 56, TOP, W - 190, TOP + ROWS * RH + 16)))
        if d then add(text(W - 80, y, 6, "Liberation Sans", 32, colour, clock(d))) end
    end
    if #list > ROWS then
        local track = ROWS * RH
        local th = math.max(40, math.floor(track * ROWS / #list))
        local ty = TOP + 8 + math.floor((track - th) * (first - 1) / (#list - ROWS))
        add(rrect(W - 64, ty, 10, th, 4, DIMTXT))
    end

    ov.data = table.concat(a)
    ov:update()
end

mp.add_periodic_timer(0.1, draw)
mp.register_event("file-loaded", function() sync_playlist(); draw() end)
mp.observe_property("playlist-count", "number", sync_playlist)
