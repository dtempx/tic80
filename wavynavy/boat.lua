-- boat: steering, sea-riding, fire, death/sink/respawn, player missile

-- hull lean: steps -7..7, 5 deg apart (+ = clockwise, bow-right down) --
-- only the range the boat reaches riding the swell (steepest ~36 deg). The
-- sheet holds frames 0-7 (0..35 deg) at spr_boat+2k, turned about the block
-- centre; a left lean is the same frame x-flipped (the hull is symmetric
-- about the pivot column, so the flip is exactly the mirrored angle).
-- The cabin and gun are not on the sheet: they always stand straight up,
-- drawn in code from boat_tower. Per step (5 values): cabin centre column,
-- flat top row, then the three column heights -- each column reaches down
-- to the first solid hull pixel (capped at 4), so on a tilted deck the
-- upright cabin gets a slanted base. The 3-px gun rises from its middle.
-- Entries 0-14 are steps -7..7 (entry = step+7).
local boat_tower = {7,6,3,2,2, 7,6,3,2,2, 8,5,3,3,2, 8,5,3,3,2, 8,6,2,2,2,
 8,6,2,2,2, 8,6,2,2,2, 8,6,2,2,2, 8,6,2,2,2, 8,6,2,2,2, 8,6,2,2,2, 8,6,2,2,3,
 8,6,2,2,3, 8,6,2,2,3, 8,6,2,2,3,
 -- entries 15/16: the sink poses (steps +7 / -7) with the cabin nudged 1 px
 -- toward the raised stern, so the white submerged shape reads nose-down
 7,5,2,3,3, 8,5,3,3,2}
local tower_sink_r, tower_sink_l = 15, 16

-- cabin + gun for tower entry e at block origin (x, y); below the sea
-- surface row surf (optional) they go white, like a submerged sprite
local function draw_tower(e, x, y, surf)
 local i = 5 * e
 local cx, top = x + boat_tower[i + 1], y + boat_tower[i + 2]
 for c = 0, 2 do
  for py = top, top + boat_tower[i + 3 + c] - 1 do
   pix(cx - 1 + c, py, surf and py >= surf and 7 or 9)
  end
 end
 for py = top - 3, top - 1 do
  pix(cx, py, surf and py >= surf and 7 or 12)
 end
end

-- hull frame for lean step s (-7..7) at (x, y); the right-leaning frame
-- x-flipped for a left lean
local function boat_hull(s, x, y)
 spr(256 + spr_boat + 2 * math.abs(s), x, y, 0, 1, s < 0 and 1 or 0, 0, 2, 2)
end

local function boat_body(step, x, y)
 boat_hull(step, x, y)
 draw_tower(step + 7, x, y)
end

-- whole boat (hull + upright cabin and gun) at lean step -7..7, block origin
-- (x, y); solid, never striped, on a mono monitor
function boat_spr(step, x, y)
 mono.draw_solid(boat_body, step, x, y)
end

-- the sinking pose, bow down toward the heading, white below the surface
local function boat_sink(right, x, y, ax)
 wspr(256 + spr_boat + 14, x, y, 2, 2, right and 0 or 1, ax)
 draw_tower(right and tower_sink_r or tower_sink_l, x, y, scry(waves_dy(ax)))
end

-- lowest opaque row of the block for steps -7..7, so the keel can be
-- anchored to the swell (index step+8)
local boat_bot = {12, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 12}

-- (re)spawn the player's boat at apple-x sx (default boat_start), clearing
-- hazards, bombs and the missile, with the fleet held until the first input
function boat_init(sx)
 p_x = sx or boat_start
 p_st = 0    -- 0 alive / 1 struck / 2 sinking / 3 sunk
 p_t = 0
 hazards_clear()
 bombs = {}
 p_y = waves_y(p_x)
 p_px, p_py = p_x, p_y -- interpolation seeds (no stale lerp on respawn)
 msl = nil
 want_fire = false
 p_dir = 1   -- last steering dir; the death arc follows it
 fire_held = btn(4) or btn(5) -- a held button isn't a fresh shot
 want_skip = false
 armed = false -- enemies wait for the player's first input
end

-- respawn after a death: fresh boat at boat_start, mines parked offscreen so
-- they drift back in once the player re-arms (rather than sitting in view
-- through the get-ready)
local function respawn()
 boat_init()
 mines_offscreen()
end

function boat_input() -- every display frame: catch presses between sim ticks
 if demo then return end -- the demo arms/fires itself; a press starts the game
 local f = btn(4) or btn(5)
 if f and not fire_held then want_fire = true end
 fire_held = f
 if p_st == 0 and f then armed = true end
 if p_st >= 2 and fp() then want_skip = true end -- skip the death anim
end

-- one PLAYERUPD pass ($1817): chase the target x and ride the swell. The
-- original runs this TWICE per oframe ($08BD/$08CC), so the boat's real pace
-- is 2*boat_dx per oframe -- boat_move below makes both calls.
local function player_upd()
 local tx = p_x
 if demo then
  tx = demo_tx           -- chase the AI patrol target
 else
  if btn(2) then tx = clamp_lo end
  if btn(3) then tx = clamp_hi end
 end
 local d = tx - p_x
 -- 2x steering while waiting to respawn (get-ready), else chase speed
 local spd = boat_dx * (armed and 1 or 2)
 if math.abs(d) > 1 then
  p_x = p_x + spd * sgn(d)
  p_dir = sgn(d)
 end
 p_y = waves_y(p_x)
end

-- once per sim tick (called from otick): two steering passes then one fire
-- check, matching MAINLOOP's 2x PLAYERUPD + 1x FIRECTL ordering
function boat_move()
 if p_st == 0 then
  player_upd()
  player_upd()
  if demo then want_fire = not msl end -- autofire ($186F)
  if want_fire and not msl then        -- FIRECTL: once per oframe
   -- px/py seed the draw interpolation: msl_tick moves it 11px later THIS
   -- same otick (snap_prev already ran), so without a seed the missile is
   -- drawn frozen at the muzzle for its whole first tick
   msl = {x = p_x, y = p_y - 4, px = p_x, py = p_y - 4}
   shots_fired = shots_fired + 1
   fire_sound() -- PCM sample on 1.2+, the slot-0 SFX fit otherwise
  end
 end
 want_fire = false
end

-- resolve the death: lose a life once, game-over if out, else recall the
-- fleet. Returns true if the run ended (caller bails out of boat_tick).
function lose_life()
 if not died then
  died = true
  if not demo then lives = lives - 1 end -- the demo boat is unsinkable
  if lives <= 0 then
   go_gameover()
   return true
  end
  recall_enemies()
  form_t = 0
 end
end

-- skip the death anim/regroup: settle the life loss, snap the fleet home
function skip_death()
 want_skip = false
 sfx_stop(3)
 if lose_life() then return end
 force_formation()
 respawn()
end

-- once per sim tick: run the death sequence (struck arc -> sinking -> sunk
-- and respawn); does nothing while the boat is alive
function boat_tick()
 if p_st ~= 0 and want_skip then skip_death() return end
 if p_st == 1 then -- struck: pitch up, arc, hull spins ($10AC/$10CE)
  local dy = math.floor(p_t / 3) - 5
  p_y = p_y + dy
  p_x = p_x + 2 * p_dir
  wrap_x()
  p_t = p_t + 1
  if p_t % 11 == 0 and p_t < 33 then psfx(sfx_playerhit, 3) end
  if dy > 0 and p_y >= waves_y(p_x) then -- falling + meets swell
   p_st = 2
   lsfx(sfx_playersink, 3)
  end
 elseif p_st == 2 then -- in water: sinks ~45deg toward its heading
  p_x = p_x + 1.25 * p_dir
  wrap_x()
  p_y = p_y + sink_dy
  if p_y >= 216 then
   p_st = 3
   p_t = 0
  end
 elseif p_st == 3 then -- sunk: recall the fleet, respawn once re-formed
  p_t = p_t + 1
  if p_t == sink_cut then sfx_stop(3) end -- the sink drone runs into recall
  if p_t == 25 then
   if lose_life() then return end
  elseif p_t > 25 and formation_ready() then
   form_t = form_t + 1 -- fleet home: hold ~2s then get-ready
   if form_t >= 28 then respawn() end
  elseif p_t >= 25 + recall_ofs then
   force_formation() -- hard cutoff: snap home vs a wedged enemy
   respawn()
  end
 end
end

-- wrap the dead boat off one field edge and back in the other
function wrap_x()
 if p_x > fld_x1 then p_x = fld_x0
 elseif p_x < fld_x0 then p_x = fld_x1 end
end

-- the boat has been hit: start the struck arc and freeze the assault
function player_hit()
 p_st = 1
 p_t = 0
 died = false -- this death's life-loss hasn't been resolved yet
 armed = false -- freeze the assault when struck
 hf_clear() -- the shots that queued these reports are over (sfx.lua)
 psfx(sfx_playerhit, 3)
end

-- on death the board persists: in-flight slots fly home, no new attacks
function recall_enemies()
 armed = false
 for _, e in ipairs(ens) do
  if e.st == 3 then -- diving: re-enter from the top and descend to its slot
   redescend(e) -- yoff_min keeps the recalled divers from stacking up
  end
 end
 booms = {}
 msl = nil
end

-- hard-cutoff fallback: snap every survivor home with no animation
function force_formation()
 armed = false
 for _, e in ipairs(ens) do
  if e.st == 1 then
   e.st = 2
  elseif e.st ~= 2 then
   e.st = 0
   e.x = e.tx
   e.y = e.ty
   e.ph = 0
   e.fdx = slide
   e.fdy = 0
  end
 end
 bombs = {}
 booms = {}
 hazards_clear()
 msl = nil
end

-- true once no slot is still exploding, diving or re-descending
function formation_ready()
 for _, e in ipairs(ens) do
  if e.st == 1 or e.st == 3 or e.st == 4 or e.st == 5 then return false end
 end
 return true
end

-- advance the player's missile one tick; retire it on a hit or off the top
function msl_tick()
 if not msl then return end
 local y0 = msl.y -- pre-move y: enemies_hit sweeps the rows crossed this tick
 msl.y = msl.y - msl_dy
 if enemies_hit(msl.x, msl.y, y0) or hazards_hit(msl.x, msl.y) then
  shots_hit = shots_hit + 1
  msl = nil
 elseif msl.y < fld_y0 then
  msl = nil
 end
end

-- hit-arc "spin": the original never turns the hull over -- it rocks through
-- its tilt glyphs 0,1,2,4,3 (upright, right-down, steeper right-down, steep
-- left-down, left-down), 2 sim ticks (~0.11 s) each, the same order whatever
-- the heading, cabin and gun always up (BOATFRM from table $10CE, stepped
-- once per tick by PLAYRMOVE $107D). Like the original, the spin reuses the
-- sea-riding leans: moderate, the steepest, then both mirrored -- steps
-- 0, 4, 7, -7, -4 (0 / 20 / 35 deg). (The reference capture,
-- games/wavynavy/video/deathspin, measures the original's glyphs steeper,
-- ~42/65 deg; the port keeps the spin inside its own riding range.)
local spin_s = {0, 4, 7, -7, -4}

-- draw the player's missile, its trail frame chosen by distance flown
local function draw_missile()
 if not msl then return end
 -- original trail ladder: launch frame, short trail, then the long pair
 -- flickering ($5B1C); nose offsets match the authored canvases
 local age = p_y - 4 - msl.y
 local f = age < 12 and 0 or age < 24 and 1 or 2 + oframe % 3
 local hgt, nose = ({2, 2, 4, 4, 4})[f + 1], ({0, 0, 2, 2, 2})[f + 1]
 spr(256 + spr_missile + f, scrx(lerpd(msl.px, msl.x)) - 3,
     scry(lerpd(msl.py, msl.y)) - nose, 0, 1, 0, 0, 1, hgt)
end

-- sea slope under the hull -> lean step -7..7 (+ = bow-right down): the
-- swell's on-screen angle across the 14-px hull, to the nearest 5 deg
-- (the steepest swell is ~36 deg, so the whole range is used)
local function sea_tilt(ax)
 local sl = waves_dy(ax + 7) - waves_dy(ax - 7)
 local s = math.floor(math.atan(sl * scale_y, 14 * scale_x) / (math.pi / 36) + .5)
 return math.max(-7, math.min(7, s))
end

-- draw the boat for its state (tumbling, sinking or riding the swell) and its missile
function boat_draw()
 if p_st == 3 then return end
 local ax = lerpd(p_px, p_x)
 local x, y = scrx(ax), scry(lerpd(p_py, p_y))
 if p_st == 1 then -- tumbling: hull rocks through the 5-pose cycle
  boat_spr(spin_s[p_t // 2 % 5 + 1], x - 8, y - 8)
  return
 end
 if p_st == 2 then -- sinking: steepest lean (35 deg), bow down toward the
  -- direction of travel (frame 7, x-flipped heading left).
  -- DELIBERATE DEVIATION (owner's call, 2026-09-25): the original ends table
  -- $10CE on glyph 1 and sinks right-down whatever the heading, which reads
  -- as bow-up when the boat sinks toward the left.
  mono.draw_solid(boat_sink, p_dir >= 0, x - 8, y - 8, ax)
  return
 end
 -- hull rides the swell, keel anchored just below the DRAWN (interpolated)
 -- surface so it never floats off or digs into the rolling sea
 y = scry(waves_dy(ax))
 local s = sea_tilt(ax)
 boat_spr(s, x - 8, y - boat_bot[s + 8] + 1)
 draw_missile()
end
