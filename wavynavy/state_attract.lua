-- attract: the pregame cycle (title -> demo -> point table -> rank table),
-- difficulty stepping, and the two hold combos (hiscore reset, display mode)

local pg_hold = 360 -- frames each static attract screen holds (~6s)

-- step difficulty by delta (persisted), clamped 0..2 no-wrap, blink 2s.
-- Outside the title it snaps back to the settled title so the label shows.
function set_diff(delta, to_title)
 local nd = clamp(0, diff + delta, 2)
 if nd == diff then return false end
 diff = nd
 pmem(1, diff)
 psfx(sfx_blip)
 if to_title then
  goto_title()
  title_settle()
 end
 diff_blink = 120
 return true
end

-- hiscore reset: hold fire+down 4s anywhere in the attract cycle. Returns
-- true while the combo is held so callers suppress the start action.
local hs_hold = 240

-- advance the fire+down hold; zero the hiscore once it reaches 4s
function hs_reset_tick()
 if not (btn(4) and btn(1)) then
  hs_t = 0
  return false
 end
 local before = hs_t or 0
 hs_t = before + frame_dt() -- dt: counters hold real seconds at any fps
 if before < hs_hold and hs_t >= hs_hold then -- fire once on the crossing
  hi = 0
  prev_hi = 0
  pmem(0, 0)
  psfx(sfx_blip) -- audible confirmation (same blip as a difficulty change)
 end
 return true
end

-- display mode: the same 4s hold on fire+up steps the monitor colour ->
-- green -> white (a2boot.lua's mono, persisted in pmem slot 2). Unlike the
-- one-shot reset above the timer re-arms on each crossing, so a continued hold
-- keeps cycling every 4s -- the change is on screen, so the player stops at the
-- monitor they want instead of re-holding for each step.
function disp_mode_tick()
 if not (btn(4) and btn(0)) then
  disp_t = 0
  return false
 end
 disp_t = (disp_t or 0) + frame_dt()
 if disp_t >= hs_hold then
  disp_t = disp_t - hs_hold
  mono.cycle()
  psfx(sfx_blip)
 end
 return true
end

-- both attract combos, ticked every frame (never short-circuited, or holding
-- one would freeze the other's timer); true while either is held
function combo_tick()
 local hs = hs_reset_tick()
 local dm = disp_mode_tick()
 return hs or dm
end

-- static-screen driver: swell scrolls; fire starts, left/right step
-- difficulty, the hold timer advances the cycle
local function pg_tick(nxt, hold)
 local dt = frame_dt()
 pg_t = pg_t + dt
 oframe = (oframe + 1) % 4 -- rotor anim cadence only; stays integer
 sea_ph = sea_ph - 0.5 * dt
 if combo_tick() then return end
 if xp() then
  start_game()
 elseif lp() or rp() then
  set_diff(lp() and -1 or 1, true)
 elseif pg_t > (hold or pg_hold) then
  nxt()
 end
end

-- reset timers and the swell for a static attract screen (point/rank tables)
function page_init()
 pg_t = 0
 sea_ph = 0
 oframe = 0
 hs_t = 0
 disp_t = 0
end

------ demo: the game plays itself for one wave ------

-- AI patrol ($5FE9): step +/-2, reverse near edges, per-segment dwell ($6045)
local demo_dwell = {40,96,48,64,96,80,32,64,96,48,24,16,64,80,48,64}

-- move the demo boat's patrol target one sim tick
function demo_ai()
 if demo_dir > 0 and demo_tx >= 0xd0 then demo_dir = -1
 elseif demo_dir < 0 and demo_tx <= 0x14 then demo_dir = 1 end
 demo_tx = clamp(clamp_lo, demo_tx + demo_dir * 2, clamp_hi)
 demo_dt = demo_dt + 1
 if demo_dt >= demo_dwell[demo_seg + 1] then
  demo_dt = 0
  demo_dir = -demo_dir
  demo_seg = (demo_seg + 1) % 16
 end
end

-- set up a silent, unscored wave-1 game driven by the patrol AI
function demo_init()
 demo = true
 wave = 1
 score = 0
 lives = start_lives
 sd_plane, sd_heli, sd_bomber, sd_cruise = 0, 0, 0, 0
 shots_fired, shots_hit = 0, 0
 demo_tx = 120
 demo_dir = 1
 demo_seg = 0
 demo_dt = 0
 demo_t = 0
 hs_t = 0
 disp_t = 0
 play_init()
 armed = true -- the demo boat opens fire immediately
end

-- run the demo game; fire starts a real one, left/right change difficulty
function demo_update()
 demo_t = demo_t + frame_dt()
 play_update()
 if combo_tick() then return end
 if lp() or rp() then
  demo = false
  sfx_stop(2)
  set_diff(lp() and -1 or 1, true)
  return
 end
 -- runs one wave then bows out; fire starts the real game. The timeout
 -- waits out a death in progress (struck arc / sinking) so the demo never
 -- cuts away mid-sink, with a hard cap in case the sequence wedges.
 local dying = p_st == 1 or p_st == 2 or (p_st == 3 and p_t < 25)
 local len = demo_secs * 60 -- demo_t counts 60 fps frames (dt-scaled)
 local timeout = demo_t > len and not dying or demo_t > len + pg_hold
 if timeout or wave > 1 or xp() then
  demo = false
  sfx_stop(2)
  if xp() then start_game() else goto_points() end
 end
end

------ table screens ------

-- header + sea; hitop() last so the banner never overdraws the hiscore line
local function tbl_head(s)
 cls(0)
 waves_draw()
 bigtext("WAVY NAVY", 18, 11, 9)
 if s then cprint(s, 36, 14) end
 hitop()
end

-- point table: enemy sprite per row + score (mine omitted - unshootable)
local pt_rows = {
 {"plane", "10 OR 20 POINTS"},
 {"heli", "20 OR 50 POINTS"},
 {"bomber", "100 POINTS"},
 {"cruise", "100 POINTS"},
}
local pt_step = 120 -- 2s between row reveals
local pt_done = (#pt_rows - 1) * pt_step + 300

-- hold the point table until every row is shown, then the rank table
function points_update()
 pg_tick(goto_ranks, pt_done)
end

-- draw the point table, revealing one row every pt_step frames
function points_draw()
 tbl_head()
 local shown = math.min(#pt_rows, pg_t // pt_step + 1)
 local y = 48
 for i = 1, shown do
  local r = pt_rows[i]
  if r[1] == "plane" then
   spr(256 + spr_plane, 46, y - 4, 0, 1, 0, 0, 2, 2)
  elseif r[1] == "heli" then
   -- right-facing heli (single sprite, rotor fully drawn); heli_blade_black
   -- fakes the spin, eating the blade's rear and forward tip by turns
   spr(256 + spr_heli, 46, y, 0, 1, 0, 0, 2, 1)
   heli_blade_black(46, y)
  elseif r[1] == "bomber" then
   spr(256 + spr_bomber, 42, y, 0, 1, 0, 0, 3, 1)
  else
   local cid, cdx = cruise_frame(1) -- nose-right, matching the other rows
   spr(cid, 32 + cdx, y, 0, 1, 0, 0, 5, 1)
  end
  print(r[2], 80, y + 1, 7)
  y = y + 16
 end
end

-- rank table: the ten promotion ranks in two columns
function ranks_update()
 pg_tick(goto_title)
end

-- draw the ten ranks, five per column
function ranks_draw()
 tbl_head("RANK TABLE")
 for i = 1, 10 do
  local col = (i - 1) // 5
  print(wcfg_rank[i], 30 + col * 110, 56 + ((i - 1) % 5) * 12, 7)
 end
end
