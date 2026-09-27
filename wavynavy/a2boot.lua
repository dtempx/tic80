-- a2boot: the Apple II presentation layer -- the power-on boot sequence the
-- cart opens with, and the monochrome-monitor filter behind the three display
-- modes (colour / green / white). Wiring, in the entry stub (main.lua):
--   BOOT()  mono.load()  apple2.boot{skip = true, rgb = mono.fg(), bg_rgb = mono.bg()}
--   TIC()   if apple2.tic() then return end   ...game...   mono.apply()
-- The intro carries its own bell and borrows two palette entries, so it needs
-- nothing from the game; the filter needs the game to leave vbank(1) alone.
-- Background, the ROM maths and the measurements: README.md, section
-- "Apple II boot intro and display modes".
--
-- This module is DROP-IN PORTABLE across carts: it depends on no other module
-- and owns everything the intro needs, the Disk II drive sound included. That
-- sound is PCM, and its samples live at a FIXED address at the very top of the
-- <MAP> region (see "disk drive" below) precisely so the same bytes land in the
-- same place in every cart -- copy this file plus that block of <MAP> and the
-- intro works unchanged. A game with its own PCM bank (this port has one, in
-- pcm.lua) keeps it at the BOTTOM of the region; the two never meet. The
-- "@" and "APPLE ][" glyphs are sprites 504-511 (the last row of the sprite
-- sheet, right half) -- copy those too, or point at_spr/title_spr elsewhere.

local PAL, BORDER = 0x3fc0, 0x3ff8

-- How long after the intro starts the drive sound begins, in milliseconds.
-- A real Disk II sits quiet for a moment before the head moves, and the intro
-- is wall-clock timed, so this is measured from apple2.boot() rather than in
-- frames. The 30-frame midpoint ramp runs THROUGH the delay, so the channel is
-- already at the silence level when the first sample lands and the start does
-- not click. Set 0 to start immediately.
local PCM_START = 1000

------------------------------------------------------------------- apple2
-- Inverse-@ screen, ROM bell, top-down clear, "Apple ][" hold; wall-clock
-- timed. Borrows palette entries fg/bg and the border, restores them after.
apple2 = {defaults = {
 at_ms = 800, beep_ms = 100, wipe_ms = 60, title_ms = 3000, hold_ms = 2000, -- phases; the bell ends as the screen clears
 fg = 12, bg = 0, rgb = {0xf4, 0xf4, 0xf4},                     -- rgb: the phosphor, poked into entry fg
 bg_rgb = {0, 0, 0},                                            -- the unlit glass, poked into entry bg
 volume = 15, skip = false,                                     -- skip: any button/key ends the intro
 drive = true,                                                  -- the Disk II boot sound (needs TIC-80 1.2)
 at_spr = 504,                                                  -- the "@" glyph, dots in the cell's left 5x7
 title_spr = 505, title_w = 7,                                  -- "APPLE ][" as one 7-sprite-wide strip
}}

-- The glyphs are sprites (bottom-right corner of the sprite sheet), drawn in
-- colour 7 on colour 0 -- carry those sprites across with this file.
local GLYPH = 7
local MAP = 0x3ff0 * 2 + GLYPH                -- its nibble in the VRAM palette map

local CW, CH, COLS, ROWS = 6, 8, 40, 17   -- 6x8 cells: 40x17 fills 240x136
local o, t0, saved                        -- options, start time (nil = idle), borrowed palette

-- sprite(s) at pixel (x, y), glyph dots in colour c, everything else transparent
local function glyph(id, x, y, w, c)
 local old = peek4(MAP)
 poke4(MAP, c)
 spr(id, x, y, 0, 1, 0, 0, w, 1)
 poke4(MAP, old)
end

-- the power-on screen: one inverse "@" cell, tiled by VRAM copies across row 0
-- (3 bytes per cell per scanline) then down in 8-line bands; top rows cleared
local function at_screen(cleared)
 rect(0, 0, CW, CH, o.fg)
 glyph(o.at_spr, 0, 0, 1, o.bg)
 for ln = 0, CH - 1 do
  for c = 1, COLS - 1 do memcpy(ln * 120 + c * 3, ln * 120, 3) end
 end
 for r = 1, ROWS - 1 do memcpy(r * 960, 0, 960) end
 rect(0, 0, 240, cleared * CH, o.bg)
end

-- ROM BELL1: a 935 Hz square for ~100 ms. Written each frame straight into
-- channel 3's sound register (0xFF9C + 54: freq lo, freq hi | volume, 32
-- 4-bit samples), which TIC-80 wipes every frame -- no SFX slot, nothing to
-- stop. Word 916 renders 932.5 Hz, the pitch-grid point nearest 935.
local function bell()
 poke(0xffd2, 916 & 0xff)
 poke(0xffd3, (916 >> 8) | (o.volume << 4))
 for i = 0, 15 do poke(0xffd4 + i, i < 8 and 0xff or 0) end
end

-- The Disk II boot sound, on TIC-80 1.2's PCM channel: 128 unsigned 8-bit
-- samples a frame at 0x14e24, 7,680 Hz. Five recorded blocks are played to a
-- schedule rather than stored as one long clip -- a seek of any length is the
-- same 77 ms cycle repeated, so the whole 5.9 s boot costs 4,927 bytes.
--
-- THE SAMPLE BYTES ARE NOT IN THIS FILE. They sit in the cart's <MAP> region
-- at BASE below -- the top of the region, chosen so a game's own data (which
-- grows up from 0x08000) never reaches them and this module stays drop-in.
-- They cost the code budget nothing and no decode runs at load. To move the
-- module to another cart, copy those <MAP> rows across with it.
--
-- This module owns the PCM channel only while the intro is on screen: the
-- last thing tic() does before returning false is hand it back at the shared
-- silence level, so a game's own PCM code (pcm.lua here) takes over cleanly.
-- Playback starts DRIVE_DELAY_MS after boot() (see the top of the file), so
-- with the default phase lengths only the opening of the sound is reached
-- before the intro ends -- lengthen title_ms to hear more of it.
local PCM, BLOCK = 0x14e24, 128
local BASE = 0x0EC00     -- the bank's fixed home at the top of <MAP>
local MID = 118          -- the one silence level every block is centred on

-- {offset from BASE, length}, laid out back to back in that order.
--   knock  318.0 ms  the drive knock plus the first 5 clicks, verbatim
--   cycle   77.0 ms  ONE head-seek period (two clicks, 35 then 42 ms apart);
--                    repeating it is what makes a seek of any length
--   hiss   123.6 ms  quiet drive background, for long gaps
--   thump   97.9 ms  one of the settling knocks in the tail
--   short   25.1 ms  the same background, for fine spacing
local bank = {
 knock = {0, 2442}, cycle = {2442, 591}, hiss = {3033, 949},
 thump = {3982, 752}, short = {4734, 193},
}

-- The boot, as {block, repeats}: {"cycle", 16} is the 77 ms seek cycle played
-- 16 times = 1.23 s of seeking, {"short", 3} three 25 ms pads of quiet.
local script = {
 {"knock", 1}, {"cycle", 16}, {"hiss", 8}, {"short", 1}, {"thump", 1},
 {"short", 1}, {"thump", 1}, {"short", 2}, {"thump", 1}, {"short", 16},
 {"thump", 1}, {"short", 16}, {"thump", 4}, {"hiss", 8}, {"thump", 4},
 {"short", 32},
}

local step        -- index into `script`; nil once the sequence has finished
local rep, pos    -- repeat count and byte offset within the current block
local warmup      -- frames of midpoint ramp-in; playback waits for 30
local has_pcm     -- nil until probed, then true/false
local probed

-- TIC-80 1.2+ clears the PCM buffer before every TIC; 1.1 and older leave that
-- reserved RAM alone. So the first update writes a marker byte and the second
-- reads it back -- which is why this only settles from the second frame on.
-- On an older engine the drive sound is simply skipped; the rest of the intro
-- (screen and bell) is unaffected.
local function drive_update(t)
 if has_pcm == nil then
  probed = probed + 1
  if probed == 1 then
   poke(PCM + BLOCK - 1, 0xff)
   return
  end
  has_pcm = peek(PCM + BLOCK - 1) == 0
  if not has_pcm then return end
 elseif has_pcm == false then
  return
 end
 -- Ramp the buffer to the midpoint over 30 frames before emitting a sample:
 -- starting at the DC level cold is what makes the opening click. This runs
 -- during DRIVE_DELAY_MS too, so a delayed start is already settled.
 warmup = math.min(30, warmup + 1)
 local silence = math.floor(MID * warmup / 30 + 0.5)
 local due = t >= PCM_START
 for i = 0, BLOCK - 1 do
  local v = silence
  if due and warmup >= 30 and step then
   local entry = script[step]
   local blk = bank[entry[1]]
   v = peek(BASE + blk[1] + pos)
   pos = pos + 1
   if pos >= blk[2] then
    pos, rep = 0, rep + 1
    if rep > entry[2] then rep, step = 1, step + 1 end
    if step > #script then step = nil end
   end
  end
  poke(PCM + i, v)
 end
end

-- Leave the channel at the shared silence level rather than wherever the last
-- sample happened to sit, so handing it to the game's PCM code does not step
-- the DC level and thump.
local function drive_release()
 if has_pcm then for i = 0, BLOCK - 1 do poke(PCM + i, MID) end end
end

-- start (or restart) the intro; opts override apple2.defaults
function apple2.boot(opts)
 apple2.finish()
 o = setmetatable(opts or {}, {__index = apple2.defaults})
 saved = {border = peek(BORDER)}
 for i = 0, 47 do saved[i] = peek(PAL + i) end
 for i = 0, 2 do
  poke(PAL + o.bg * 3 + i, o.bg_rgb[i + 1])
  poke(PAL + o.fg * 3 + i, o.rgb[i + 1])
 end
 poke(BORDER, o.bg)
 step, rep, pos = o.drive and 1 or nil, 1, 0
 warmup, has_pcm, probed = 0, nil, 0
 t0 = time()
end

-- end the intro now, hand the borrowed palette back and release the PCM channel
function apple2.finish()
 if not t0 then return end
 for i = 0, 47 do poke(PAL + i, saved[i]) end
 poke(BORDER, saved.border)
 drive_release()
 step, t0 = nil, nil
end

-- draw this frame of the intro; true while it runs, false once it is over
function apple2.tic()
 if not t0 then return false end
 local t = time() - t0
 local wipe, title = o.at_ms, o.at_ms + o.wipe_ms
 if o.drive then drive_update(t) end  -- every frame we own: the engine clears
                                      -- the buffer each TIC, so even silence
                                      -- has to be written back
 -- no PCM channel means no drive sound to wait for, so cut the final hold short
 local hold = (has_pcm == false) and 1000 or o.hold_ms
 if o.skip and (btnp() ~= 0 or keyp()) or t >= title + o.title_ms + hold then
  apple2.finish()
  return false
 end
 -- phases: "@" screen (bell at its end), top-down wipe, then the title hold
 if t < wipe then
  at_screen(0)
  if t >= wipe - o.beep_ms then bell() end
 elseif t < title then
  at_screen((t - wipe) * ROWS // o.wipe_ms)
 else
  cls(o.bg)
  glyph(o.title_spr, (240 - o.title_w * 8) // 2, 0, o.title_w, o.fg)   -- centred, as HTAB 17 is on the real page
 end
 return true
end

--------------------------------------------------------------------- mono
-- The monitor the game is watched on: a colour set, or a green- or
-- white-phosphor monochrome one as a post-process (mono.apply() last in TIC()).
-- An Apple II "colour" is alternate hi-res dots, so a mono monitor shows
-- colours as 1-px vertical stripes, white and black solid. Bank 0 keeps the
-- frame with its palette forced to dark/lit; bank 1 (index 0 transparent) gets
-- the unlit dots: one 1-px ttri() strip per column sampling bank 0 through a
-- palette map (everything -> DARK) with a chroma list that skips all but the
-- coloured pixels of that column's parity. ~4 ms a frame per pass on the Pi.
-- The game must not use vbank(1); mono.off() restores bank 0's palette.
mono = {
 modes = {"color", "green", "white"},   -- fire+up steps through these
 slot = 2,                              -- pmem: 0 hiscore, 1 difficulty, 2 display
 index = 0, mode = "color",
 -- lit dot / unlit glass per phosphor (the P1 green and P4 white tubes)
 phosphor = {
  green = {lit = {0x33, 0xff, 0x33}, dark = {0x07, 0x20, 0x0b}},
  white = {lit = {0xf4, 0xf4, 0xf4}, dark = {0x0d, 0x0e, 0x10}},
 },
 -- how a mono monitor reads this port's palette (design.md section 6): solid
 -- indices are white dots, odd ones are the Apple green/orange parity; every
 -- other index falls in with the blue/violet parity and lights even columns.
 solid = {6, 7, 10},   -- light grey, Apple white, yellow
 odd = {9, 11},        -- Apple orange, Apple green
}

local DARK, keys, gsaved = 1
local has_vbank = type(vbank) == "function"

-- poke an {r, g, b} triple into the palette entry at address a
local function rgb(a, c) for i = 0, 2 do poke(a + i, c[i + 1]) end end

-- first mono frame: build the per-parity chroma-key lists, save the colour
-- palette for mono.off(), and point every entry of bank 1's map at DARK
local function setup()
 local kind = {}
 for _, i in ipairs(mono.solid) do kind[i] = "solid" end
 for _, i in ipairs(mono.odd) do kind[i] = "odd" end
 keys = {{0}, {0}}   -- indices the strips skip: [1] on odd columns, [2] on even columns
 for i = 1, 15 do
  if kind[i] then keys[1][#keys[1] + 1] = i end
  if kind[i] ~= "odd" then keys[2][#keys[2] + 1] = i end
 end
 gsaved = {border = peek(BORDER)}
 for i = 0, 47 do gsaved[i] = peek(PAL + i) end
 if has_vbank then
  vbank(1)
  poke(BORDER, 0)
  for i = 0, 15 do poke4(0x7fe0 + i, DARK) end   -- bank 1's palette map
  vbank(0)
 end
end

-- hand the borrowed palette back and clear the overlay (colour mode)
function mono.off()
 if not gsaved then return end
 if has_vbank then
  vbank(1) memset(0, 0, 16320) vbank(0)   -- raw clear: cls() would go through the map
 end
 for i = 0, 47 do poke(PAL + i, gsaved[i]) end
 poke(BORDER, gsaved.border)
 gsaved = nil
end

-- a strip per column: a triangle with its apex below the screen covers exactly
-- the pixel centres of column x
local function strips(x0, key)
 for x = x0, 239, 2 do
  ttri(x, 0, x + 1, 0, x + .5, 272, x, 0, x + 1, 0, x + .5, 272, 2, key)
 end
end

-- post-process the finished frame: force bank 0 to dark/lit, then lay the
-- unlit-dot strips over it on bank 1 (hands off to mono.off() in colour mode)
function mono.apply()
 if not has_vbank then return end
 local p = mono.phosphor[mono.mode]
 if not p then return mono.off() end
 if not gsaved then setup() end
 rgb(PAL, p.dark)
 for i = 1, 15 do rgb(PAL + i * 3, p.lit) end
 poke(BORDER, 0)
 vbank(1)
 rgb(PAL + DARK * 3, p.dark)   -- the unlit dots the strips lay down
 memset(0, 0, 16320)
 strips(1, keys[1])
 if #mono.odd > 0 then strips(0, keys[2]) end
 vbank(0)
end

-- text is never striped on a mono monitor: while a phosphor mode is on, every
-- print() draws in Apple white (a mono.solid index) whatever colour it asked for
local SOLID = 7
local tic_print = print
function print(s, x, y, c, ...)
 if mono.phosphor[mono.mode] then c = SOLID end
 return tic_print(s, x, y, c, ...)
end

-- f(...) drawn unstriped on a mono monitor: the VRAM palette map (0x3ff0, 8
-- bytes) sends every opaque index to SOLID for the call, then is put back as
-- it was. The map covers spr() and the primitives alike. Colour mode: f(...) as is.
function mono.draw_solid(f, ...)
 if not mono.phosphor[mono.mode] then return f(...) end
 local m = {}
 for i = 0, 7 do m[i] = peek(0x3ff0 + i) end
 for c = 1, 15 do poke4(0x7fe0 + c, SOLID) end
 f(...)
 for i = 0, 7 do poke(0x3ff0 + i, m[i]) end
end

-- pick a mode by index (wraps), remembering it across runs in pmem
function mono.set(i)
 mono.index = i % #mono.modes
 mono.mode = mono.modes[mono.index + 1]
 pmem(mono.slot, mono.index)
end

-- step to the next display mode (colour -> green -> white -> colour)
function mono.cycle() mono.set(mono.index + 1) end

-- restore the stored mode at BOOT; an unwritten slot reads 0 = colour
function mono.load() mono.set(pmem(mono.slot)) end

-- the boot screen's phosphor and glass: white on black on a colour set
function mono.fg() return (mono.phosphor[mono.mode] or {}).lit or apple2.defaults.rgb end
function mono.bg() return (mono.phosphor[mono.mode] or {}).dark or apple2.defaults.bg_rgb end
