-- enemies: 40-slot formation + bomb pool.
-- e.st: 0 formation / 1 exploding / 2 dead / 3 diving / 4 re-descend / 5 ram

-- build this wave's 40-slot formation from its template, set the slide speed
-- and the three launch timers
function enemies_init()
 ens = {}
 bombs = {}
 local w = math.min(wave, 10)
 local h = tmpl_b + (w - 1) * 120 -- 40 slots x 3 bytes (x,y,st)
 for i = 0, 39 do
  local x, y, st = peek(h + i * 3), peek(h + i * 3 + 1), peek(h + i * 3 + 2)
  local e = {x = x, y = y, tx = x, ty = y, st = st, ph = 0, i = i,
             heli = st == 0 and y < 16, pts = 0, fdx = 1, fdy = 0}
  dive_facing(e, 1, 0)
  table.insert(ens, e)
 end
 -- slide speed: one edge-to-edge sweep takes form_secs
 local lo, hi = 300, 0
 for _, e in ipairs(ens) do
  if e.st == 0 then
   lo = math.min(lo, e.tx)
   hi = math.max(hi, e.tx)
  end
 end
 slide_mag = math.max(0.25, (170 - (hi - lo)) / (form_secs * 60 * ostep * gspeed))
 slide = slide_mag
 -- 3 launch timers: per-difficulty base, ramped per wave to a floor ($134E).
 -- RAMPDIFF runs on every wave clear with no wave cap (WAVEADV clamps only
 -- the template index), so the ramp uses the real wave number, not w
 lper, lt = {}, {}
 local base, flo = diff_base[diff + 1], diff_floor[diff + 1]
 local ram = {ramp1, ramp2, ramp3}
 for k = 1, 3 do
  lper[k] = math.max(flo[k], base[k] - (wave - 1) * ram[k])
  lt[k] = lper[k]
 end
 llists = {llist1, llist2, llist3}
end

-- yoff_min: the minimum vertical gap the port keeps between enemies. The
-- original enforces none anywhere - RESPAWN ($1AD9) plants every recycled slot
-- at ENEY=$E0 and REJOIN ($169C) bare-INCs it, while launches fire on a timer
-- with no regard for who is already airborne - so slots routinely fly up, and
-- dive, right on top of each other. Both fixes below are port refinements;
-- yoff_min=0 restores the original's behaviour exactly.

-- true if any enemy in one of `states` sits within yoff_min of y (e excluded)
local function y_crowded(e, y, states)
 for _, o in ipairs(ens) do
  if o ~= e and states[o.st] and math.abs(o.y - y) < enemy_dy then
   return o
  end
 end
 return nil
end

-- Send an enemy to state 4 (re-descend). Keeps the original's ENEY=$E0 entry
-- point but backs the newcomer down the queue until it clears every other
-- climber, so a batch recycled on one frame files up in single file.
local climbing = {[4] = true}
function redescend(e)
 local y = 224
 if enemy_dy > 0 then
  local o = y_crowded(e, y, climbing)
  while o do
   y = o.y - enemy_dy -- queue in behind the one already climbing
   o = y_crowded(e, y, climbing)
  end
 end
 e.st = 4
 e.y = y % 256
 e.ex = nil
end

-- send formation slot e into a dive, setting the points it is now worth
local function launch(e)
 e.st = 3
 e.bt = 999 -- let the first bomb string of the dive fire at once
 if e.heli then
  e.pts = 50
  psfx(sfx_helilaunch)
 else
  e.pts = 20
 end
 dive_start(e, dive_map(1, e.x, e.y, 0))
end

-- Two divers whose scripts converge end up flying overlapped: gating the
-- launch does not help, because they are launched seconds apart and only meet
-- mid-path (measured - a launch-only guard left 78 overlapping dive-ticks in a
-- 4-minute run, unchanged from the original). So the dive itself is nudged:
-- when two divers come within yoff_min in y *and* close enough in x to overlap
-- on screen (the glyph is 16 px wide), the lower one drifts down a fraction of
-- a pixel per tick until the gap opens. e.y stays the VM's own coordinate -
-- only this small bias is added, so the path keeps the original's shape and
-- collisions, wave-ditching and drawing all stay consistent with each other.
local diving = {[3] = true}
function dive_separate(e)
 if enemy_dy <= 0 then return end
 local o = y_crowded(e, e.y, diving)
 if o and math.abs(o.x - e.x) < 16 then
  -- push whichever is already lower further down; ties break on slot identity
  -- so the pair never both move the same way and chase each other
  local lower = (e.y > o.y or (e.y == o.y and e.i > o.i)) and e or o
  lower.y = (lower.y + dive_push) % 256
 end
end

-- beginner easing is in force (constants.lua beg_ease_wave; also read by the
-- $87 re-dive in dive.lua)
function beg_eased()
 return diff == 0 and wave >= beg_ease_wave
end

-- enemies currently diving (state 3)
local function n_diving()
 local n = 0
 for _, e in ipairs(ens) do
  if e.st == 3 then n = n + 1 end
 end
 return n
end

-- count down the three launch timers; each expiry launches the first slot
-- still in formation from that timer's launch list. On eased beginner waves
-- an expiry at the beg_max_dive cap is skipped (the timer still reloads, so
-- the next launch keeps its cadence rather than firing the instant one lands)
function launch_tick() -- every 4th oframe
 if not armed or p_st ~= 0 then return end
 for k = 1, 3 do
  lt[k] = lt[k] - 1
  if lt[k] <= 0 then
   lt[k] = lper[k]
   if not (beg_eased() and n_diving() >= beg_max_dive) then
    for _, i in ipairs(llists[k]) do
     local e = ens[i + 1]
     if e.st == 0 then
      launch(e)
      break
     end
    end
   end
  end
 end
end

-- one sim tick for the fleet: slide the formation, advance explosions, dives
-- and re-descents, test rams, and clear the wave once everything is gone
function enemies_tick()
 -- formation slides as one block, reversing at the field edges ($16EC)
 local lo, hi = 300, 0
 for _, e in ipairs(ens) do
  if e.st == 0 then
   lo = math.min(lo, e.tx)
   hi = math.max(hi, e.tx)
  end
 end
 if lo < 32 then
  slide = slide_mag
 elseif hi >= 202 then
  slide = -slide_mag
 end
 alive = 0 -- global: hazards_spawn stops crossers once the fleet is dead
 for _, e in ipairs(ens) do
  if e.st ~= 2 then alive = alive + 1 end
  e.tx = e.tx + slide
  if e.st == 0 then
   e.x = e.tx
   e.fdx = slide
   e.fdy = 0
   -- $16B9 sets the glyph straight off FORMDX: right -> bank 0 / face 0,
   -- left -> bank 8 / face 1. It deliberately skips BANKCALC, whose BANKMAP
   -- entry for a |dx|=1 step is 0 (nose-right) - routing the slide through it
   -- left the leftward sweep flying backwards.
   e.facing = slide > 0 and 0 or 8
   e.hface = slide > 0 and 0 or 1
  elseif e.st == 1 or e.st == 5 then -- exploding: run the blast out
   e.ph = e.ph + 1
   if e.ph >= expl_of then
    if e.st == 1 then
     e.st = 2
    else -- rammed enemies respawn via re-descend ($5E99)
     redescend(e)
    end
   end
  elseif e.st == 3 then -- diving: run the path VM, then edge/end/ram checks
   e.bt = (e.bt or 0) + 1 -- frames since last bomb (heli string spacing)
   if e.y >= waves_y(e.x) then
    e.st = 5 -- ditches into the waves: explode, then re-descend
    e.ph = 0
   else
    local live = dive_tick(e)
    dive_separate(e)
    if dive_offx(e) then
     if e.heli then redescend(e) else dive_bounce(e) end
    elseif not live then
     if e.heli or dive_offy(e) then
      redescend(e) -- off the bottom, or a heli's path ended: recycle
     else
      dive_redive(e) -- a plane's path ended in view: keep it hunting
     end
    elseif p_st == 0 and math.abs(e.x - p_x) < 12 and math.abs(e.y - p_y) < 7 then
     e.st = 5
     e.ph = 0
     psfx(sfx_ram)
     player_hit()
    end
   end
  elseif e.st == 4 then -- re-descending: drop in from the top 1 px a tick to its slot
   e.x = e.tx
   e.y = (e.y + 1) % 256
   dive_facing(e, 0, 1)
   if e.y == e.ty then e.st = 0 end
  end
 end
 -- clear only in control with no crosser/bombs left (never mid-death)
 if p_st == 0 and alive == 0 and not bomber and not cruise and #bombs == 0 then
  wave_cleared()
 end
end

-- one pixel of an 8x8 sprite-bank cell (SPRITES RAM 0x6000, 32 bytes/cell,
-- 4 bytes/row, low nibble = even column)
local function cellpx(id, c, r)
 local v = peek(0x6000 + id * 32 + r * 4 + c // 2)
 return c % 2 == 0 and v & 15 or v >> 4
end

-- is screen point (sx,sy) an opaque pixel of e's drawn glyph? Anchor and
-- glyph choice mirror enemies_draw exactly (colorkey 0 = transparent), incl.
-- whichever rotor-blade tip heli_blade_black blanks this oframe
local function glyph_px(e, sx, sy)
 local base, col, row, w, h
 if e.heli then
  base = spr_heli + 2 * (e.hface or 0)
  col, row, w, h = sx - scrx(e.x) + 8, sy - scry(e.y) + 4, 16, 8
 else
  local f = e.facing or 0
  base = spr_plane + (f < 8 and 2 * f or 32 + 2 * (f - 8))
  col, row, w, h = sx - scrx(e.x) + 8, sy - scry(e.y) + 8, 16, 16
 end
 if col < 0 or col >= w or row < 0 or row >= h then return false end
 if e.heli and row == 0 then
  local tx, tw = heli_blade_span(e.hface)
  if col >= tx and col < tx + tw then return false end
 end
 return cellpx(base + col // 8 + row // 8 * 16, col % 8, row % 8) ~= 0
end

-- missile hit = the original 13x20 window ($1936) OR a swept pixel test.
-- The window alone is narrower than the drawn glyph (13 apple px vs a
-- 16-screen-px canvas ~ 20 apple px at scale_x), so shots visibly crossing
-- a wingtip sailed on. The sweep walks the warhead down every screen row
-- it covered this tick (nothing tunnels past the 11-px step) and checks
-- the shaft's two screen columns against the glyph's opaque pixels.
local function msl_hit(e, mx, my, my0)
 if mx > e.x - 7 and mx <= e.x + 6
   and my - 14 >= e.y - 20 and my - 14 < e.y then
  return true
 end
 if math.abs(mx - e.x) > 13 then return false end -- beyond any glyph reach
 local bx = scrx(mx) -- shaft columns: glyph cols 3-4 drawn at scrx(mx)-3
 for sy = scry(my) - 2, scry(my0) do -- -2: the long frames' nose offset
  if glyph_px(e, bx, sy) or glyph_px(e, bx + 1, sy) then return true end
 end
 return false
end

-- missile at (mx, my), swept from my0: destroy and score the first enemy hit
function enemies_hit(mx, my, my0)
 for _, e in ipairs(ens) do
  if (e.st == 0 or e.st == 3 or e.st == 4)
    and msl_hit(e, mx, my, my0 or my) then
   e.st = 1
   e.ph = 0
   local v = e.pts
   if v == 0 then v = e.heli and 20 or 10 end -- not diving: heli 20, plane 10
   add_score(v)
   if e.heli then
    sd_heli = sd_heli + 1
    psfx(v > 20 and sfx_divehelikill or sfx_helikill)
   else
    sd_plane = sd_plane + 1
    psfx(v > 10 and sfx_diveplanekill or sfx_planekill)
   end
   return true
  end
 end
 return false
end

-- wave 5+ recolors the lower plane rows green; row split by formation home y
local function is_green(e, w)
 return w >= 5 and not e.heli and e.ty > 0x2a
end

-- per-rank palette shifts (docs/enemy-colors.md): base art is scheme A.
-- Returns true when it remapped, so the caller resets the map only then
-- (waves 1-3 draw the whole fleet with no remap at all)
local function enemy_pal(e, w)
 if w == 4 then
  pal(14, 12) -- planes violet -> blue
  pal(11, 9)  -- helis green -> orange
  return true
 elseif is_green(e, w) then
  pal(14, 11)
  return true
 end
 return false
end

-- draw every enemy (explosion, heli or banked plane) and then the bombs
function enemies_draw()
 local w = math.min(wave, 10)
 for _, e in ipairs(ens) do
  if e.st == 1 then -- shot: plane fireball / heli smoke puff
   draw_boom(e.x, e.y, e.ph, e.heli and xpl_h or xpl_p,
             (e.heli or is_green(e, w)) and 12 or 9, nil, e.heli)
  elseif e.st == 5 then -- rammed: ram burst (throbs)
   draw_boom(e.x, e.y, e.ph, xpl_r, is_green(e, w) and 12 or 9, 3)
  elseif e.st ~= 2 then
   local ax
   if e.ex then
    ax = lerpd(e.pex, e.ex)
   else
    ax = lerpw(e.px, e.x)
   end
   local x, y = scrx(ax), scry(lerpw(e.py, e.y))
   local remapped = enemy_pal(e, w)
   if e.heli then
    -- body faces the sticky HELIFACE bit, which only turns over on a nonzero
    -- dx (see dive_facing). One sprite per heading, rotor fully drawn (96
    -- right, 98 left); heli_blade_black fakes the spin the original got from
    -- its E-0A/0B phase pair, eating the blade's rear and forward tip by turns
    wspr(256 + spr_heli + 2 * (e.hface or 0), x - 8, y - 4, 2, 1, 0, ax)
    heli_blade_black(x - 8, y - 4, e.hface)
   else
    local f = e.facing or 0
    local base = f < 8 and 2 * f or 32 + 2 * (f - 8)
    wspr(256 + spr_plane + base, x - 8, y - 8, 2, 2, 0, ax)
   end
   if remapped then pal_reset() end -- wspr's whiten path already reset it
  end
 end
 bombs_draw()
end
