-- fx: explosions (the original's dot-pair streams, peeked from the data
-- block, plus the procedural dense fireball / heli smoke puff fitted in the
-- pico8 port -- docs/explosions-fx.md), water splashes, sky-writing smoke puffs

-- blast tables: {base addr, frame count, offsets or nil}. A nil offset table
-- means uniform 32-byte frames; otherwise frame i spans idx[i+1]..idx[i+2]-1.
xpl_p = {0, 8, nil}                      -- plane blast (addr filled in fx_init)
xpl_r = {0, 3, {0, 36, 74, 110}}         -- ram blast
xpl_h = {0, 23, {0,20,40,60,80,100,120,140,160,180,200,220,240,260,280,
                 300,320,340,360,378,398,418,438,458}}  -- heli blast

-- resolve the blast table addresses and empty the effect lists; the first
-- call also bakes the dense blast phases into the tile bank (fx_bake below)
function fx_init()
 xpl_p[1], xpl_r[1], xpl_h[1] = xplp_b, xplr_b, xplh_b
 booms = {}
 puffs = {}
 splashes = {}
 if not blast_ph then fx_bake() end
end

-- start a free-standing blast at apple (ax, ay); heli = smoke puff, else fireball
function boom(ax, ay, heli)
 table.insert(booms, {x = ax, y = ay, ph = 0, heli = heli})
end

-- start a water splash on the sea surface at apple-x ax
function splash(ax)
 table.insert(splashes, {x = ax, ph = 0})
end

-- age blasts and splashes one tick, dropping the finished ones
function fx_tick()
 prune(booms, function(b) b.ph = b.ph + 1 return b.ph < expl_of end)
 prune(splashes, function(s) s.ph = s.ph + 1 return s.ph < 8 end)
end

boom_dense = 0.54 -- fraction of a plane blast's life the dense fireball covers
-- rim colour per body colour: orange blast burns brown, green-plane blast dark blue
xpl_rim = {[9] = 4, [12] = 1}

-- deterministic per-cell speckle (quadratic: a linear mix streaks diagonally)
local function bhash(x, y)
 return (x * x * 7 + y * y * 13 + x * y * 29 + x * 53 + y * 97) % 23 / 23
end

-- The two dense-phase generators below plot through a callback, plot(dx, dy,
-- c), rather than straight to the screen: a blast's shape depends only on its
-- integer sim phase, so the pixels are generated ONCE (fx_bake) and replayed
-- from the tile bank (one spr() call) or a memoised pixel list, instead of
-- re-running the fitted maths for every cell of every blast every display
-- frame -- measured as the one draw cost that grew with a busy board (six
-- overlapping fireballs cost more than the rest of the frame put together).
-- Hot-loop hygiene, since the generators still run at boot on slow devices:
-- no `^` (Lua 5.3 routes it through C pow()), radii reciprocals and every
-- t-only threshold hoisted out of the loops, the raster test inlined.
--
-- hgr artifact: colour lights alternate column pairs; partial break, never on
-- white. Keyed off the blast-relative dx (even columns survive), not the
-- screen x as the direct-draw version was: a baked sprite cannot know where
-- it will land, and no blast in this port ever moves, so the only difference
-- is which of two adjacent columns a blast at an odd x stripes on.

-- holed mass, fill .67->.51, grows low and wide, split by a lobe seam. The
-- pico8-fitted geometry (docs/explosions-fx.md) rescaled to this port's pixel
-- space: x1.5 horizontal (scale_x/(8/15)), x1.125 vertical (scale_y/(2/3)).
-- Always generated in the orange scheme (body 9, rim 4); the green-plane
-- scheme is a pal() remap at draw time (draw_boom).
local function gen_fball(t, plot)
 local rx, ry = 6.75 + 5.7 * t, 2.6 + 5.6 * t
 local irx, iry = 1 / rx, 1 / ry
 local frx, fry = math.floor(rx), math.floor(ry)
 local yof = math.floor(ry * .18) -- mass sits low: grows downward more than up
 local hole = math.max(0, t - .78) * 3 -- centre only opens right at the handoff
 local hole2 = hole * hole
 local e1 = 1 - math.min(t / .9, 1)
 -- hash cutoff: the young mass is airier (+.11 e1^2, decaying), and -.14
 -- pays back what the raster eats
 local cut = .24 - t * .1 + .11 * e1 * e1 - .14
 for dy = -fry - 2, fry + 3 do
  local v = (dy - yof) * iry
  local v2 = v * v
  for dx = -frx - 2, frx + 2 do
   local u = dx * irx
   local q = u * u + v2
   local h = bhash(dx, dy)
   -- the seam column only thins -- the original's is a broken gap, not a clean split
   if q <= 1 + h * .3 and q >= hole2 and h > cut
    and (dx ~= 0 or h > .75) and (dx % 2 == 0 or h > .55) then
    plot(dx, dy, q > .55 + h * .25 and 4 or 9)
   end
  end
 end
 -- white core: two dots flanking the seam, gone by mid-phase
 if t < .55 then
  plot(-3, 0, 7) plot(-2, 0, 7)
  plot(2, 0, 7) plot(3, 0, 7)
 end
end

-- heli puff: inverted from the plane -- blue core inside solid white smoke
local function gen_puff(t, plot)
 local rx, ry = 5.25 + 4.5 * t, 3.15 + 2.7 * t -- wider than tall
 local irx, iry = 1 / rx, 1 / ry
 local frx, fry = math.floor(rx), math.floor(ry)
 local wf = math.min(1, t * 1.7 - .2) -- white front sweeps out; nothing white early
 local wlim = wf > 0 and wf * 1.3 or -1 -- white inside q < wlim (none while wf <= 0)
 local hole = math.max(0, t - .62) * 2.5 -- billow opens into a ring
 local hole2 = hole * hole
 local dcut = math.max(0, t - .72) * 2.2 - .15 -- and breaks up rather than fading out intact
 local bcut = .74 - t * .4 -- blue skeleton hash cutoff
 for dy = -fry - 2, fry + 2 do
  local v = dy * iry
  local v2 = v * v
  for dx = -frx - 3, frx + 3 do
   local u = dx * irx
   local q = u * u + v2
   local h = bhash(dx, dy)
   if q <= 1 + h * .3 and q >= hole2 and h > dcut then
    -- white smoke stays solid; only the blue takes the hgr raster break-up
    if q < wlim then
     plot(dx, dy, 7)
    elseif h > bcut and (dx % 2 == 0 or h > .55) then
     plot(dx, dy, 12)
    end
   end
  end
 end
end

-- kind 1 = fireball at t = ph / (expl_of * boom_dense), 2 = puff at t = ph / expl_of
local function gen_phase(kind, ph, plot)
 if kind == 1 then
  gen_fball(ph / (expl_of * boom_dense), plot)
 else
  gen_puff(ph / expl_of, plot)
 end
end

-- one phase as a flat pixel list {dx, dy, c, dx, dy, c, ...} and its length
local function gen_list(kind, ph)
 local list, n = {}, 0
 gen_phase(kind, ph, function(dx, dy, c)
  list[n + 1], list[n + 2], list[n + 3] = dx, dy, c
  n = n + 3
 end)
 return list, n
end

-- The tile bank (sprite ids 0-255, RAM 0x4000) holds no cart art -- every
-- sheet glyph lives in the sprite bank, 256+ -- so it is free for the baked
-- blasts. Cells are handed out by a skyline packer over the 16x16 cell grid:
-- a phase's bounding box rounds up to cw x ch cells, placed on the lowest
-- shelf that fits. Phases are baked most-expensive-first (by lit pixel
-- count), so when the bank runs out it is the cheapest, smallest early puff
-- phases that stay memoised as pixel lists (blast_ph[kind][ph].px).
local TILE_B, TILE4 = 0x4000, 0x8000 -- tile 0: byte address, nibble address
local skyline
local function tile_alloc(cw, ch)
 local best, besty
 for c = 0, 16 - cw do
  local y = 0
  for k = c, c + cw - 1 do
   if skyline[k] > y then y = skyline[k] end
  end
  if y + ch <= 16 and (not besty or y < besty) then best, besty = c, y end
 end
 if not best then return nil end
 for k = best, best + cw - 1 do skyline[k] = besty + ch end
 return besty * 16 + best
end

-- poke one phase's pixel list into freshly allocated tile cells; nil = no room
local function bake_list(list, n)
 local x0, y0, x1, y1 = 999, 999, -999, -999
 for i = 1, n, 3 do
  local dx, dy = list[i], list[i + 1]
  if dx < x0 then x0 = dx end
  if dx > x1 then x1 = dx end
  if dy < y0 then y0 = dy end
  if dy > y1 then y1 = dy end
 end
 local cw, ch = (x1 - x0 + 8) // 8, (y1 - y0 + 8) // 8
 local id = tile_alloc(cw, ch)
 if not id then return nil end
 for r = 0, ch - 1 do
  memset(TILE_B + (id + r * 16) * 32, 0, cw * 32) -- a row of cells is contiguous
 end
 for i = 1, n, 3 do
  local px, py = list[i] - x0, list[i + 1] - y0
  local cell = id + (py // 8) * 16 + px // 8
  poke4(TILE4 + cell * 64 + (py % 8) * 8 + px % 8, list[i + 2])
 end
 return {id = id, cw = cw, ch = ch, ox = x0, oy = y0}
end

-- generate every dense-phase shape once and bake as many as the tile bank
-- holds (called from the first fx_init; ~60 phases, a few ms at boot).
-- blast_ph[kind][ph] = {id, cw, ch, ox, oy} baked | {px = list, n = len} memoised
blast_ph = nil
function fx_bake()
 skyline = {}
 for c = 0, 15 do skyline[c] = 0 end
 local phases = {}
 local nfb = math.ceil(expl_of * boom_dense) -- fireball phases: ph/expl_of < boom_dense
 for ph = 0, nfb - 1 do
  if ph / expl_of < boom_dense then phases[#phases + 1] = {kind = 1, ph = ph} end
 end
 for ph = 0, expl_of - 1 do phases[#phases + 1] = {kind = 2, ph = ph} end
 for _, p in ipairs(phases) do p.px, p.n = gen_list(p.kind, p.ph) end
 table.sort(phases, function(a, b) return a.n > b.n end)
 blast_ph = {{}, {}}
 baked_cells = 0 -- for the perf/verification probes
 for _, p in ipairs(phases) do
  local b = p.n > 0 and bake_list(p.px, p.n)
  if b then
   baked_cells = baked_cells + b.cw * b.ch
  else
   b = {px = p.px, n = p.n}
  end
  blast_ph[p.kind][p.ph] = b
 end
end

-- draw one dense phase centred on screen (x, y): baked sprite, memoised
-- list, or (a phase outside the baked table) the generator straight to pix
local function draw_blast(kind, ph, x, y)
 local b = blast_ph and blast_ph[kind][ph]
 if not b then
  gen_phase(kind, ph, function(dx, dy, c) pix(x + dx, y + dy, c) end)
 elseif b.id then
  spr(b.id, x + b.ox, y + b.oy, 0, 1, 0, 0, b.cw, b.ch)
 else
  local l = b.px
  for i = 1, b.n, 3 do pix(x + l[i], y + l[i + 1], l[i + 2]) end
 end
end

-- play the original dot-pair stream over the blast's life; loops>1 recycles
-- frames (the ram burst throbs). Tight-core dots read white, the rest base.
-- One-shot blasts get the dense opening drawn on top: fireball for planes,
-- smoke puff for helis (the dot ring rides along as debris). The dense phase
-- is keyed by the integer sim phase (the title advances ph in half steps;
-- those round down to the tick's shape).
function draw_boom(ax, ay, ph, frames, base, loops, heli)
 local x, y = scrx(ax), scry(ay)
 local f = ph / expl_of
 if not loops then
  if heli then -- puff runs the whole life, dots ride along as debris
   draw_blast(2, math.floor(ph), x, y)
  elseif f < boom_dense then
   local remap = base ~= 9
   if remap then pal(9, base) pal(4, xpl_rim[base]) end
   draw_blast(1, math.floor(ph), x, y)
   if remap then pal_reset() end
   if f < boom_dense * .7 then return end -- ring joins once the mass starts opening
  end
 end
 -- pick this phase's frame and its byte span in the blast table, then plot
 -- each (dx, dy) signed-byte pair scaled into screen space
 local fb, n, idx = frames[1], frames[2], frames[3]
 local fi = math.floor(f * n * (loops or 1)) % n
 local a, b
 if idx then
  a, b = fb + idx[fi + 1], fb + idx[fi + 2]
 else
  a = fb + fi * 32
  b = a + 32
 end
 for i = a, b - 2, 2 do
  local dx, dy = sgnb(peek(i)), sgnb(peek(i + 1))
  local c = (math.abs(dx) + math.abs(dy) <= 2) and 7 or base
  pix(x + math.floor(dx * scale_x), y + math.floor(dy * scale_y), c)
 end
end

-- water spray where a bomb meets the waves
local function draw_splash(ax, ph)
 local x, y = scrx(ax), scry(waves_dy(ax))
 local hgt = 5 - math.abs(ph - 3)
 for dx = -2, 2 do
  local hh = math.floor(hgt * (3 - math.abs(dx)) / 3)
  if hh > 0 then
   line(x + dx, y - hh, x + dx, y, dx == 0 and 7 or 12)
  end
 end
end

-- integer hash of (a, b) -> 0..2^32-1; seeds each puff's own motion
local function mix(a, b)
 local h = (a * 374761393 + b * 668265263) % 4294967296
 h = (h ~ (h >> 13)) * 1274126177 % 4294967296
 return h ~ (h >> 16)
end

-- leave a sky-writing smoke puff at apple (ax, ay)
function add_puff(ax, ay)
 -- two cloud shapes, picked by position so a stroke's lumps vary
 local h = math.floor(ax) * 7 + math.floor(ay) * 13
 local s = h * 2654435761 % 4294967296
 local function u(k) return mix(s, k) % 1000 / 1000 end
 -- speed along the loop, frames/s: drift + a slow lull/flow wave + a quicker
 -- eddy. The waves outweigh the drift, so a puff stalls and now and then
 -- rocks back a frame before rolling on; periods, phases and loop position
 -- are all per puff, so neighbours never step together
 local rate, drift = 0.7 + 0.6 * u(1), 0.3 + 0.45 * u(2)
 local a1 = 0.55 + 0.25 * u(3)
 local w1, w2 = 0.35 + 0.35 * u(4), 1.1 + 0.9 * u(5)
 table.insert(puffs, {x = ax, y = ay,
  v = 1 + h // 3 % 2,      -- cloud shape (puff_grey/puff_tops row)
  r0 = rate * drift,
  c1 = rate * a1 / w1, w1 = w1, p1 = 6.2832 * u(6),
  c2 = rate * (1 - a1) / w2, w2 = w2, p2 = 6.2832 * u(7),
  off = 8 * u(8),          -- starting place in the loop
  j = h % 11 / 44})        -- 0..0.23 breeze-phase jitter
end

-- a puff's place in its 8-frame loop at t seconds: the integral of its speed
-- (add_puff), so it only ever moves one frame at a time. A breeze gust rolling
-- left to right every 2.6 s pushes the bands it catches 1-2 frames on and
-- lets them ease back, a smooth billow rather than a snap to the swell
local function puff_phase(p, now)
 local t = now / 1000
 local ph = p.off + p.r0 * t - p.c1 * math.cos(p.w1 * t + p.p1)
            - p.c2 * math.cos(p.w2 * t + p.p2)
 local w = now / 2600 - p.x / 180 + p.j
 local q = w % 1
 -- each gust sweeps about a third of the 12px bands, at its own strength
 local g = mix(math.floor(w), math.floor(p.y / 12))
 if q < 0.25 and g % 3 == 0 then
  ph = ph + (0.7 + (g >> 8) % 100 / 110) * math.sin(q * 12.566) ^ 2
 end
 return math.floor(ph) % 8 + 1
end

-- two passes: every grey under-layer, then every white top, so grey only
-- survives on a stroke's outer (mostly lower-right) edge, not between puffs.
-- PORT ADDITION: the puffs billow (puff_phase above); the grey silhouette
-- bulges while the white is within a frame of its peak swell
function draw_puffs(dy)
 local now = time()
 for _, p in ipairs(puffs) do
  p.f = puff_phase(p, now)
  local d = (p.f - puff_peak[p.v]) % 8
  local g = (d <= 1 or d == 7) and 2 or 1
  spr(256 + puff_grey[p.v][g], scrx(p.x) - 3, scry(p.y) - dy, 0)
 end
 for _, p in ipairs(puffs) do
  spr(256 + puff_tops[p.v][p.f], scrx(p.x) - 3, scry(p.y) - dy, 0)
 end
end

-- draw the smoke puffs, splashes and free-standing blasts
function fx_draw()
 draw_puffs(3)
 for _, s in ipairs(splashes) do
  draw_splash(s.x, s.ph)
 end
 for _, b in ipairs(booms) do
  draw_boom(b.x, b.y, b.ph, b.heli and xpl_h or xpl_p, b.heli and 12 or 9,
            nil, b.heli)
 end
end
