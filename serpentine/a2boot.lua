-- Apple II power-on intro and colour/green/white monitor filter.
-- Call apple2.boot(options) on every BOOT, even with enabled=false. The game
-- supplies palette roles and asset locations; this module has no game globals.
-- Integration and asset-copy instructions: a2boot.md in the tic80-port skill.
-- Reserve vbank(1) for mono; without it alternate displays are unavailable.

local PAL, BORDER, MAP = 0x3fc0, 0x3ff8, 0x7fe0
local PCM, BLOCK = 0x14e24, 128
local CW, CH, COLS, ROWS = 6, 8, 40, 17
local HAS_VBANK = type(vbank) == "function"
local PHOSPHOR = {
 [1] = {lit = {0x33, 0xff, 0x33}, dark = {0x07, 0x20, 0x0b}},
 [2] = {lit = {0xf4, 0xf4, 0xf4}, dark = {0x0d, 0x0e, 0x10}},
}
-- Descriptors and sequence for the standard 4,927-byte Disk II recording.
-- Alternate recordings may override drive_bank, drive_script and midpoint.
local BANK = {
 knock = {0, 2442}, cycle = {2442, 591}, hiss = {3033, 949},
 thump = {3982, 752}, short = {4734, 193},
}
local SCRIPT = {
 {"knock", 1}, {"cycle", 16}, {"hiss", 8}, {"short", 1}, {"thump", 1},
 {"short", 1}, {"thump", 1}, {"short", 2}, {"thump", 1}, {"short", 16},
 {"thump", 1}, {"short", 16}, {"thump", 4}, {"hiss", 8}, {"thump", 4},
 {"short", 32},
}

apple2 = {defaults = {
 enabled = true, mode = 0, skip = false,
 at_ms = 800, beep_ms = 100, wipe_ms = 60, title_ms = 3000,
 hold_ms = 2000, no_drive_hold_ms = 1000,
 fg = 15, bg = 0, glyph = 15, transparent = 0, title_w = 7,
 rgb = {0xf4, 0xf4, 0xf4}, bg_rgb = {0, 0, 0},
 volume = 15, bell_channel = 3,
 drive = true, drive_start_ms = 1000, drive_midpoint = 118,
 drive_bank = BANK, drive_script = SCRIPT,
}}
mono = {
 mode = 0, phosphor = PHOSPHOR, background = 0,
 solid = {15}, odd = {}, text = 15, overlay_dark = 1, overlay = true,
}
local o, t0, saved
local step, rep, pos, warmup, has_pcm, probed
local keys, gsaved, overlay
local alt_display = HAS_VBANK

local function rgb(a, c)
 for i = 0, 2 do poke(a + i, c[i + 1]) end
end

local function palette_index(i, name)
 assert(type(i) == "number" and i % 1 == 0 and i >= 0 and i <= 15,
        "a2boot: " .. name .. " must be a palette index (0..15)")
end

-- Rebuild the filter only after handing its previous palette back.
local function monitor(opts)
 mono.off()
 local m = opts.mono or {}
 mono.background = m.background or opts.bg
 mono.text = m.text or opts.glyph
 mono.solid = m.solid or {mono.text}
 mono.odd = m.odd or {}
 mono.overlay_dark = m.overlay_dark or 1
 mono.overlay = m.overlay ~= false
 alt_display = HAS_VBANK and mono.overlay
 mono.phosphor = m.phosphor or PHOSPHOR
 palette_index(mono.background, "mono.background")
 palette_index(mono.text, "mono.text")
 palette_index(mono.overlay_dark, "mono.overlay_dark")
 assert(mono.overlay_dark ~= 0, "a2boot: mono.overlay_dark must differ from overlay transparency (0)")
 local classified = {[mono.background] = true}
 local text_solid = false
 for _, i in ipairs(mono.solid) do
  palette_index(i, "mono.solid")
  assert(not classified[i], "a2boot: mono palette classes must be disjoint")
  classified[i] = true
  if i == mono.text then text_solid = true end
 end
 for _, i in ipairs(mono.odd) do
  palette_index(i, "mono.odd")
  assert(not classified[i], "a2boot: mono palette classes must be disjoint")
  classified[i] = true
 end
 assert(text_solid, "a2boot: mono.text must belong to mono.solid")
 mono.set(opts.mode)
end

-- Source ink is remapped for this draw only; transparency belongs to the asset.
local function glyph(id, x, y, w, c)
 local old = peek4(MAP + o.glyph)
 poke4(MAP + o.glyph, c)
 spr(id, x, y, o.transparent, 1, 0, 0, w, 1)
 poke4(MAP + o.glyph, old)
end

local function at_screen(cleared)
 rect(0, 0, CW, CH, o.fg)
 glyph(o.at_spr, 0, 0, 1, o.bg)
 for ln = 0, CH - 1 do
  for c = 1, COLS - 1 do memcpy(ln * 120 + c * 3, ln * 120, 3) end
 end
 for r = 1, ROWS - 1 do memcpy(r * 960, 0, 960) end
 rect(0, 0, 240, cleared * CH, o.bg)
end

-- ROM BELL1: ~935 Hz for 100 ms; no SFX or waveform asset needed.
local function bell()
 local addr = 0xff9c + o.bell_channel * 18
 poke(addr, 916 & 0xff)
 poke(addr + 1, (916 >> 8) | (o.volume << 4))
 for i = 0, 15 do poke(addr + 2 + i, i < 8 and 0xff or 0) end
end

-- 1.2+ clears the PCM buffer before TIC; older engines retain our marker.
local function drive_update(t)
 if has_pcm == nil then
  probed = probed + 1
  if probed == 1 then poke(PCM + BLOCK - 1, 0xff) return end
  has_pcm = peek(PCM + BLOCK - 1) == 0
  if not has_pcm then return end
 elseif not has_pcm then return end
 -- Ramp during the delay, so the first sample starts at its own DC midpoint.
 warmup = math.min(30, warmup + 1)
 local silence = math.floor(o.drive_midpoint * warmup / 30 + 0.5)
 for i = 0, BLOCK - 1 do
  local v = silence
  if t >= o.drive_start_ms and warmup >= 30 and step then
   local entry = o.drive_script[step]
   local blk = o.drive_bank[entry[1]]
   v = peek(o.drive_base + blk[1] + pos)
   pos = pos + 1
   if pos >= blk[2] then
    pos, rep = 0, rep + 1
    if rep > entry[2] then rep, step = 1, step + 1 end
    if step > #o.drive_script then step = nil end
   end
  end
  poke(PCM + i, v)
 end
end

-- Always initialize the monitor; enabled=false bypasses palette/audio/intro.
-- Runtime choices override defaults without changing the caller's table.
function apple2.boot(opts)
 apple2.finish()
 o = {}
 for k, v in pairs(apple2.defaults) do o[k] = v end
 for k, v in pairs(opts or {}) do o[k] = v end
 palette_index(o.fg, "fg")
 palette_index(o.bg, "bg")
 palette_index(o.glyph, "glyph")
 palette_index(o.transparent, "transparent")
 monitor(o)
 local result = {alt_display = alt_display}
 if not o.enabled then return result end
 assert(type(o.at_spr) == "number" and type(o.title_spr) == "number",
        "a2boot: enabled intro requires at_spr and title_spr")
 assert(o.fg ~= o.bg and o.glyph ~= o.transparent, "a2boot: boot ink and background must differ")
 assert(o.wipe_ms > 0, "a2boot: wipe_ms must be positive")
 assert(o.bell_channel % 1 == 0 and o.bell_channel >= 0 and o.bell_channel <= 3,
        "a2boot: bell_channel must be 0..3")
 -- No implicit sample address: omit the base or disable drive to stay silent.
 o.drive = o.drive and o.drive_base ~= nil
 if o.drive then
  assert(type(o.drive_base) == "number" and o.drive_base % 1 == 0 and o.drive_base >= 0,
         "a2boot: drive_base must be a nonnegative byte address")
  assert(o.drive_midpoint >= 0 and o.drive_midpoint <= 255 and o.drive_midpoint % 1 == 0,
         "a2boot: drive_midpoint must be an unsigned byte")
  assert(#o.drive_script > 0, "a2boot: drive_script must not be empty")
  for _, entry in ipairs(o.drive_script) do
   local block = o.drive_bank[entry[1]]
   assert(block and block[1] >= 0 and block[1] % 1 == 0 and block[2] > 0 and block[2] % 1 == 0,
          "a2boot: invalid drive block " .. tostring(entry[1]))
   assert(entry[2] > 0 and entry[2] % 1 == 0, "a2boot: drive repeats must be positive integers")
  end
 end
 local p = mono.phosphor[mono.mode]
 -- Resolve phosphor after configuration; explicit RGB always wins.
 o.rgb = (opts or {}).rgb or (p and p.lit) or o.rgb
 o.bg_rgb = (opts or {}).bg_rgb or (p and p.dark) or o.bg_rgb
 saved = {border = peek(BORDER)}
 for i = 0, 47 do saved[i] = peek(PAL + i) end
 rgb(PAL + o.bg * 3, o.bg_rgb)
 rgb(PAL + o.fg * 3, o.rgb)
 poke(BORDER, o.bg)
 step, rep, pos = o.drive and 1 or nil, 1, 0
 warmup, has_pcm, probed = 0, false, 0
 if o.drive then has_pcm = nil end
 t0 = time()
 return result
end

function apple2.finish()
 if not t0 then return end
 for i = 0, 47 do poke(PAL + i, saved[i]) end
 poke(BORDER, saved.border)
 if has_pcm then
  for i = 0, BLOCK - 1 do poke(PCM + i, o.drive_midpoint) end
 end
 step, t0 = nil, nil
end

function apple2.tic()
 if not t0 then return false end
 local t = time() - t0
 local wipe, title = o.at_ms, o.at_ms + o.wipe_ms
 if o.drive then drive_update(t) end
 local hold = has_pcm == false and o.no_drive_hold_ms or o.hold_ms
 if o.skip and (btnp() ~= 0 or keyp()) or t >= title + o.title_ms + hold then
  apple2.finish()
  return false
 end
 if t < wipe then
  at_screen(0)
  if t >= wipe - o.beep_ms then bell() end
 elseif t < title then
  at_screen((t - wipe) * ROWS // o.wipe_ms)
 else
  cls(o.bg)
  glyph(o.title_spr, (240 - o.title_w * 8) // 2, 0, o.title_w, o.fg)
 end
 return true
end

-- Palette indices are generated here: there is no PALETTE_COLORS dependency.
local function setup()
 local kind = {[mono.background] = "background"}
 for _, i in ipairs(mono.solid) do kind[i] = "solid" end
 for _, i in ipairs(mono.odd) do kind[i] = "odd" end
 keys = {{mono.background}, {mono.background}}
 for i = 0, 15 do
  if i ~= mono.background then
   if kind[i] then keys[1][#keys[1] + 1] = i end
   if kind[i] ~= "odd" then keys[2][#keys[2] + 1] = i end
  end
 end
 overlay = HAS_VBANK and mono.overlay
 gsaved = {border = peek(BORDER)}
 for i = 0, 47 do gsaved[i] = peek(PAL + i) end
 if overlay then
  vbank(1)
  poke(BORDER, 0)
  for i = 0, 15 do poke4(MAP + i, mono.overlay_dark) end
  vbank(0)
 end
end

function mono.off()
 if not gsaved then return end
 if overlay then vbank(1) memset(0, 0, 16320) vbank(0) end
 for i = 0, 47 do poke(PAL + i, gsaved[i]) end
 poke(BORDER, gsaved.border)
 gsaved = nil
end

local function strips(x0, key)
 for x = x0, 239, 2 do
  ttri(x, 0, x + 1, 0, x + .5, 272, x, 0, x + 1, 0, x + .5, 272, 2, key)
 end
end

function mono.apply()
 local p = mono.phosphor[mono.mode]
 if not p then return mono.off() end
 if not gsaved then setup() end
 for i = 0, 15 do rgb(PAL + i * 3, i == mono.background and p.dark or p.lit) end
 poke(BORDER, mono.background)
 vbank(1)
 rgb(PAL + mono.overlay_dark * 3, p.dark)
 memset(0, 0, 16320)
 strips(1, keys[1])
 if #mono.odd > 0 then strips(0, keys[2]) end
 vbank(0)
end

-- Installed once at require time, before modules that capture print. Preserve
-- TIC-80's omitted arguments in colour mode (explicit nil is not a default).
local tic_print = print
function print(...)
 if not mono.phosphor[mono.mode] then return tic_print(...) end
 local args = table.pack(...)
 args[2], args[3], args[4] = args[2] or 0, args[3] or 0, mono.text
 return tic_print(table.unpack(args, 1, math.max(4, args.n)))
end

function mono.draw_solid(f, ...)
 if not mono.phosphor[mono.mode] then return f(...) end
 local m = {}
 for i = 0, 7 do m[i] = peek(0x3ff0 + i) end
 for c = 0, 15 do
  if c ~= mono.background then poke4(MAP + c, mono.text) end
 end
 local results = table.pack(pcall(f, ...))
 for i = 0, 7 do poke(0x3ff0 + i, m[i]) end
 if not results[1] then error(results[2], 0) end
 return table.unpack(results, 2, results.n)
end

-- Changing mode retains the game configuration. Persistence belongs to game.
function mono.set(i) mono.mode = alt_display and i % 3 or 0 end
function mono.fg() return (mono.phosphor[mono.mode] or {}).lit or (o or apple2.defaults).rgb end
function mono.bg() return (mono.phosphor[mono.mode] or {}).dark or (o or apple2.defaults).bg_rgb end
