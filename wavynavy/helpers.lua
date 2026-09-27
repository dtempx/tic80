-- helpers: shared micro-utilities and the world->screen mapping

-- sign of v as -1 or 1 (zero counts as positive)
function sgn(v) return v < 0 and -1 or 1 end

function sgnb(v) -- two's-complement byte -> signed (dive steps, blast dots)
 return v >= 128 and v - 256 or v
end

-- v limited to the range lo..hi
function clamp(lo, v, hi) return math.max(lo, math.min(v, hi)) end

-- world (apple hi-res) -> screen. Both axes scale to preserve the original's
-- 4:3 shape (see constants.lua); X is additionally offset by fld_ox to centre
-- the pillarboxed playfield between the black side margins, and Y by fld_oy to
-- keep the top heli row clear of the status line text.
function scrx(ax) return math.floor((ax - fld_x0) * scale_x + fld_ox) end
function scry(ay) return math.floor((ay - fld_y0) * scale_y + fld_oy) end

-- confine drawing to the pillarboxed playfield, so sprites straddling the edge
-- are cut at the margin instead of bleeding into the black bars
function clip_field() clip(fld_ox, 0, fld_w, scr_h) end

-- the rotor-blade tip blanked this oframe, as a glyph-local x span on the top
-- row. The port draws one fully-drawn heli glyph per heading (see spr_heli)
-- and fakes the spin by alternately eating the blade's rear and forward end,
-- the way the original alternated its extra rotor pass left/right ($5877 vs
-- $588B, toggled per slot through $9600,X). Tips are keyed by heading because
-- the blade sits at cols 4-15 facing right but 0-10 facing left.
local heli_tip = {[0] = {4, 12}, [1] = {7, 0}} -- {rear, forward} x per hface
function heli_blade_span(hface)
 return heli_tip[hface or 0][1 + oframe % 2], 4
end

-- blank that tip on the drawn glyph; sx,sy is its top-left (wspr/spr call)
function heli_blade_black(sx, sy, hface)
 local tx, tw = heli_blade_span(hface)
 rect(sx + tx, sy, tw, 1, 0)
end

-- draw-time tick interpolation: the sim steps at 18.75Hz but the screen runs
-- at 60, and 60/18.75 = 3.2 means a tick lands every 3 OR 4 display frames --
-- raw positions stutter on that uneven beat. Each otick snapshots previous
-- positions; draw_fraction is how far the current display frame sits between that
-- tick and the next (play_update sets it from its accumulator). lerpd blends
-- prev->cur, snapping on teleport-sized jumps (respawn, edge wrap, recall);
-- lerpw is the wrap-aware variant for enemy coords, which live mod 256.
draw_fraction = 1

-- smoothed real elapsed display-frames since the last call, for the sim
-- accumulators. TIC() is nominally 1/60s apart, but measured call spacing on
-- this box swings 3..48ms (non-60Hz panel vsync, engine catch-up bursts) --
-- treating each call as exactly 1/60s turns that wobble into game-speed
-- surges. Raw per-call gaps are the wrong unit too: frames are PRESENTED on
-- the display's regular refresh grid, not at the chaotic call instants, so
-- stepping motion by raw gaps judders on screen. The EMA gives near-uniform
-- per-frame steps (matching presentation) whose average tracks the wall
-- clock (correct game speed). Probes that drive updates in a tight loop set
-- fixed_dt=true to get the old exact fixed-step behavior.
local last_ms, dt_ema, g_dt
function frame_dt()
 if fixed_dt then return 1 end
 local now = time()
 if last_ms and now - last_ms < 2 then
  return g_dt or 1 -- second caller within the same display frame
 end
 local dt = 1
 if last_ms then
  local raw = (now - last_ms) / (1000 / 60)
  if raw > 4 then raw = 4 end
  dt_ema = dt_ema and (dt_ema + 0.2 * (raw - dt_ema)) or 1
  dt = dt_ema
 end
 last_ms = now
 g_dt = dt
 return dt
end

-- draw-time blend from last-tick a to current b (see draw_fraction above)
function lerpd(a, b)
 if smooth == 0 or a == nil then return b end
 local d = b - a
 if d > 24 or d < -24 then return b end
 return a + d * draw_fraction
end
-- lerpd for mod-256 enemy coords: blends the short way across the wrap
function lerpw(a, b)
 if smooth == 0 or a == nil then return b end
 local d = (b - a + 128) % 256 - 128
 if d > 24 or d < -24 then return b end
 return (a + d * draw_fraction) % 256
end

-- palette-map remap: TIC-80's pal(). c -> d for subsequent draws this frame.
function pal(c, d) poke4(0x7FE0 + c, d) end
-- The map is 8 bytes at 0x3FF0, two 4-bit entries per byte (index 2i in the
-- low nibble, 2i+1 in the high), so whole-map writes go as 8 byte pokes
-- rather than 16 nibble pokes -- pal_reset used to run after every one of
-- the 40 formation sprites, 640 poke4 calls a frame; callers now also skip
-- it when nothing was remapped.
local pal_ident = {}
for i = 0, 7 do pal_ident[i] = (2 * i + 1) * 16 + 2 * i end -- 0x10, 0x32, .. 0xFE
-- undo every pal() remap (identity palette map)
function pal_reset()
 for i = 0, 7 do poke(0x3FF0 + i, pal_ident[i]) end
end
-- every colour but 0 -> 7: the whiten-below-the-surface look (waves.lua wspr)
function pal_white()
 poke(0x3FF0, 0x70) -- index 0 stays 0 (transparent), index 1 -> 7
 for i = 1, 7 do poke(0x3FF0 + i, 0x77) end
end

function fp() return btnp(4) or btnp(5) end -- fire pressed (A or B)

-- fire starts the game, but not while up or down is held: fire+down is the
-- hiscore-reset combo and fire+up the display-mode combo, and neither may ever
-- read as a start press
function xp() return (btnp(4) or btnp(5)) and not (btn(0) or btn(1)) end

function lp() return btnp(2) end -- left: decrease difficulty (attract screens)
function rp() return btnp(3) end -- right: increase difficulty

-- remove list entries failing keep(e), preserving order (reverse sweep)
function prune(list, keep)
 for i = #list, 1, -1 do
  if not keep(list[i]) then table.remove(list, i) end
 end
end
