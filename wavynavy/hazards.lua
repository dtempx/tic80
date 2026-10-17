-- hazards: sea mines ($6055/$6060), the twin-boom bomber ($6111/$60C5) and
-- the cruise missile ($6254/$61D5)

-- set up this wave's mines and the bomber/cruise spawn timers and quotas
function hazards_init()
 -- mines: 0/1/2 per wave at fixed x and trough-level y, drifting; hidden
 -- except in troughs (the swell covers them)
 mines = {}
 local w = math.min(wave, 10)
 local mx = {48, 160}
 local my = {SEA_MID + 10, SEA_MID + 12}
 for i = 1, WCFG_MINE[w] do
  table.insert(mines, {x = mx[i], y = my[i], dir = -1}) -- drift right-to-left
 end
 -- bomber/cruise: one active at a time, respawning until `QUOTA` are shot
 bomber = nil
 cruise = nil
 bomber_t = BOMBER_RELOAD
 cruise_t = CRUISE_RELOAD
 bomber_q = WCFG_BOMBER[w] == 1 and QUOTA or 0
 cruise_q = WCFG_CRUISE[w] == 1 and QUOTA or 0
 hz_side = 0
 ck_n, ck_t = 0, 0 -- cruise-kill chirp repeats pending / otick countdown
end

-- send the crossers home on a board reset
function hazards_clear()
 if mines == nil then hazards_init() end
 bomber = nil
 cruise = nil
 ck_n = 0 -- drop any pending cruise-kill chirps with the board
end

-- park the mines past the right edge, keeping their spacing, so they drift
-- back in once play resumes (called on respawn; the get-ready hides nothing)
function mines_offscreen()
 for i, m in ipairs(mines) do
  m.x = FLD_X1 + 12 + (i - 1) * 112 -- 255: sprite fully outside the field
  m.px = m.x
 end
end

-- drift the mines (wrapping at the edges) and test them against the boat
local function mines_tick()
 for _, m in ipairs(mines) do
  m.x = m.x + MINE_DX * m.dir -- horizontal drift, wrapping
  -- wrap only at the trailing edge, so a mine queued past the leading edge
  -- (mines_offscreen) drifts in instead of teleporting across
  if m.dir < 0 and m.x < FLD_X0 - 8 then m.x = FLD_X1 + 8
  elseif m.dir > 0 and m.x > FLD_X1 + 8 then m.x = FLD_X0 - 8 end
  -- lethal only in a trough where the boat rode down onto it ($6092)
  if p_st == 0 and math.abs(m.x - p_x) < 9 and math.abs(p_y - m.y) < 7
     and waves_y(m.x) > m.y - 4 then
   boom(m.x, m.y)
   psfx(SFX_MINEHIT)
   player_hit()
  end
 end
end

-- fly the bomber across, dropping a bomb every 6 ticks; gone once off the field
local function bomber_tick()
 if not bomber then return end
 local b = bomber
 b.x = b.x + BOMBER_DX * b.dir
 b.drop = b.drop + 1
 if b.drop >= 6 and #bombs < 32 then -- steady bomb string while crossing
  b.drop = 0
  table.insert(bombs, {x = b.x, y = b.y + 4, px = b.x, py = b.y + 4,
                       dx = 0, dy = BOMB_DY, bc = COLOR_SLOT_11})
 end
 if b.x < FLD_X0 - 8 or b.x > FLD_X1 + 8 then bomber = nil end
end

-- fly the cruise missile: a high pass, then a crest-skimming pass back
local function cruise_tick()
 if not cruise then return end
 local c = cruise
 -- x-only mover, altitude fixed per pass; the low pass skims the crests
 c.x = c.x + CRUISE_DX * c.dir
 if p_st == 0 and math.abs(c.x - p_x) < 10 and math.abs(c.y - p_y) < 8 then
  boom(p_x, p_y) -- orange hazard blast at the impact, as the mine does
  psfx(SFX_RAM)
  player_hit()
  cruise = nil
 elseif c.x < FLD_X0 - 8 or c.x > FLD_X1 + 8 then
  if c.pass == 1 then -- high pass done: come back low the other way
   c.pass = 2
   c.dir = -c.dir
   c.x = c.dir > 0 and FLD_X0 or FLD_X1
   c.y = SEA_MID - SEA_AMP - 2 -- crest-skimming altitude (duckable)
  else
   cruise = nil
  end
 end
end

-- the cruise-kill chirp's remaining repeats, one otick apart (the original
-- loops the effect for as long as the explosion animates)
local function cruise_kill_tick()
 if ck_n and ck_n > 0 then
  ck_t = ck_t - 1
  if ck_t <= 0 then
   ck_t = CRUISE_KILL_GAP
   ck_n = ck_n - 1
   psfx(SFX_CRUISEKILL)
  end
 end
end

-- one sim tick for every hazard
function hazards_tick()
 mines_tick()
 bomber_tick()
 cruise_tick()
 cruise_kill_tick()
end

-- spawn timers, ticked every 4th oframe; bombers rotate side + altitude
local BOMBER_ALT = {26, 88, 96, 120}

-- count down the bomber and cruise timers, launching one from alternating
-- sides while its quota remains
function hazards_spawn()
 if not armed or p_st ~= 0 then return end
 if alive == 0 then return end -- fleet wiped: let the crosser finish its pass
 if not bomber and bomber_q > 0 then
  bomber_t = bomber_t - 1
  if bomber_t <= 0 then
   bomber_t = BOMBER_RELOAD
   hz_side = hz_side + 1
   local r = hz_side % 2 == 0
   bomber = {x = r and FLD_X0 or FLD_X1, y = BOMBER_ALT[hz_side % 4 + 1],
             dir = r and 1 or -1, drop = 0}
  end
 end
 if not cruise and cruise_q > 0 then
  cruise_t = cruise_t - 1
  if cruise_t <= 0 then
   cruise_t = CRUISE_RELOAD
   hz_side = hz_side + 1
   local r = hz_side % 2 == 0
   cruise = {x = r and FLD_X0 or FLD_X1, y = 26, dir = r and 1 or -1, pass = 1}
   psfx(SFX_CRUISEALERT) -- entry alert: the original queues ch $0D at $6287
  end
 end
end

-- cruise airframe span in screen px from scrx(c.x), per heading: the colour
-- 7/9 pixels of the sheet glyphs over all three flicker frames, nose to tail.
-- The cyan/white exhaust trailing behind is not hittable. The original's
-- window (MSLX-CRUS.X in 0..17, $6294) likewise spans its airframe (+1..+16
-- right, 0..15 left); the drawn glyph is ~1.4x the world scale, so a
-- world-unit window like the bomber's missed the front half of the sprite.
local CRU_BODY = {[1] = {-6, 16}, [-1] = {-18, 4}}

-- missile shaft (screen cols scrx(mx), +1) overlaps the cruise airframe
local function cruise_x_hit(c, mx)
 local sx, cx, s = scrx(mx), scrx(c.x), CRU_BODY[c.dir]
 return sx + 1 >= cx + s[1] and sx <= cx + s[2]
end

-- missile vs a crosser: hit = +100, blast + kill sfx ($61C2/$62C9)
local function crosser_hit(c, mx, my, snd, xhit)
 if c and (xhit and xhit(c, mx) or not xhit and math.abs(mx - c.x) < 8)
    and math.abs(my - c.y) < 8 then
  boom(c.x, c.y)
  add_score(100)
  psfx(snd)
  return true
 end
end

-- missile at (mx, my) vs the bomber and cruise; true if either was shot down
function hazards_hit(mx, my)
 if crosser_hit(bomber, mx, my, SFX_BOMBERKILL) then
  bomber_q = bomber_q - 1
  bomber = nil
  sd_bomber = sd_bomber + 1
  return true
 end
 if crosser_hit(cruise, mx, my, SFX_CRUISEKILL, cruise_x_hit) then
  cruise_q = cruise_q - 1
  cruise = nil
  sd_cruise = sd_cruise + 1
  -- the original's ch $0B is a LOOP held for the whole explosion; here the
  -- one-shot is replayed on that cadence (see CRUISE_KILL_N in constants)
  ck_n, ck_t = CRUISE_KILL_N - 1, CRUISE_KILL_GAP
  return true
 end
 return false
end

-- drawn after the sea. Unlike the boat and the aircraft (which take wspr's
-- whiten-below-the-surface path), the mine has two hand-authored glyphs: the
-- submerged one in navy/white to read against the blue sea, the airborne one
-- in sea-blue/orange to read against the black sky. A mine straddling the
-- surface draws both, each clipped to its own side of the waterline.
-- On a mono monitor a mine is solid, never striped (mono.draw_solid).
local function mine_draw(m)
 local ax = lerpd(m.px, m.x)
 local sx, sy = scrx(ax) - 8, scry(m.y) - 8
 local surf = scry(waves_dy(ax))
 if sy >= surf then -- wholly in the wave
  spr(SPRITE_BANK + SPRITE_MINE, sx, sy, COLOR_SLOT_0, 1, 0, 0, 2, 2)
 elseif sy + 16 <= surf then -- wholly clear of it
  spr(SPRITE_BANK + SPRITE_MINE_AIR, sx, sy, COLOR_SLOT_0, 1, 0, 0, 2, 2)
 else -- straddling: air glyph above the waterline, sea glyph below
  clip(FLD_OX, 0, FLD_W, surf)
  spr(SPRITE_BANK + SPRITE_MINE_AIR, sx, sy, COLOR_SLOT_0, 1, 0, 0, 2, 2)
  clip(FLD_OX, surf, FLD_W, SCR_H - surf)
  spr(SPRITE_BANK + SPRITE_MINE, sx, sy, COLOR_SLOT_0, 1, 0, 0, 2, 2)
  clip_field() -- restore the field clip, not the full screen
 end
end

-- draw every mine, split at the waterline (SHP.MINE drawn by $59EB)
function mines_draw()
 for _, m in ipairs(mines) do mono.draw_solid(mine_draw, m) end
end

-- the original authored both directions of the bomber ($545F/$547A) and the
-- cruise (frames 0-2 per direction) as separate glyphs; the port keeps only
-- the right-facing ones and x-flips them for a left heading, FLIP_DX px over
-- so the airframe sits where the original's left glyph did. The cruise's
-- three nose-right flicker frames sit at 107/123/139 (40x8 each, one per
-- sheet row); the airframe is at the same columns in all three, so only the
-- flame/trail animates, as in the original footage.
local CRU_F = {SPRITE_CRUISE, SPRITE_CRUISE + 16, SPRITE_CRUISE + 32}
-- the cruise glyph for heading dir: sprite id, draw x offset, flip
function cruise_frame(dir)
 local f = (time() // 130) % 3 -- flame flicker, ~7.5 fps
 if dir > 0 then return SPRITE_BANK + CRU_F[f + 1], 0, 0 end
 return SPRITE_BANK + CRU_F[f + 1], FLIP_DX, 1
end

-- draw the bomber and cruise missile, facing their heading
function hazards_draw()
 if bomber then
  local r = bomber.dir > 0
  spr(SPRITE_BANK + SPRITE_BOMBER, scrx(lerpd(bomber.px, bomber.x)) - 12 + (r and 0 or FLIP_DX),
      scry(bomber.y) - 4, COLOR_SLOT_0, 1, r and 0 or 1, 0, 3, 1)
 end
 if cruise then
  local id, dx, flip = cruise_frame(cruise.dir)
  spr(id, scrx(lerpd(cruise.px, cruise.x)) - 20 + dx,
      scry(lerpd(cruise.py, cruise.y)) - 4, COLOR_SLOT_0, 1, flip, 0, 5, 1)
 end
end
