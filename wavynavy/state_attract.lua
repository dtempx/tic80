-- attract: the pregame cycle (title -> demo -> point table -> rank table).
-- On every screen of it A starts a game; B opens the options page from the
-- title (state_title.lua) and returns to the settled title from the others.
-- Difficulty, theme and the hiscore reset live on the options page
-- (state_options.lua).

local PG_HOLD = 360 -- frames each static attract screen holds (~6s)

-- point table: enemy sprite per row + score (mine omitted - unshootable).
-- Per row: kind, text, then the sprite's first opaque column within its
-- block and its opaque width (measured from the sheet). The table is laid
-- out as one block centred on the playfield by what is visible: a sprite
-- column as wide as the widest sprite (each sprite right-aligned in it),
-- PT_GAP, then the text, left-aligned on a shared x
local PT_FIRST_YPOS = 48 -- ypos of the first enemy sprite (the rest are spaced 16px apart)
local PT_GAP = 12 -- px between the sprite column and the text
local PT_STEP = 120 -- 2s between row reveals
local PT_ROWS = {
 {"plane", "10 OR 20 POINTS", 1, 13},
 {"heli", "20 OR 50 POINTS", 0, 16},
 {"bomber", "100 POINTS", 3, 17},
 {"cruise", "100 POINTS", 1, 36},
}
local PT_DONE = (#PT_ROWS - 1) * PT_STEP + 300

-- static-screen driver: swell scrolls; A starts, B goes back to the title,
-- the hold timer advances the cycle
local function pg_tick(nxt, hold)
 local dt = frame_dt()
 pg_t = pg_t + dt
 oframe = (oframe + 1) % 4 -- rotor anim cadence only; stays integer
 sea_ph = sea_ph - 0.5 * dt
 if xp() then
  start_game()
 elseif bp() then
  goto_title_settled()
 elseif pg_t > (hold or PG_HOLD) then
  nxt()
 end
end

-- reset timers and the swell for a static attract screen (point/rank tables)
function page_init()
 pg_t = 0
 sea_ph = 0
 oframe = 0
end

------ demo: the game plays itself for one wave ------

-- AI patrol ($5FE9): step +/-2, reverse near edges, per-segment dwell ($6045)
local DEMO_DWELL = {40,96,48,64,96,80,32,64,96,48,24,16,64,80,48,64}

-- move the demo boat's patrol target one sim tick
function demo_ai()
 if demo_dir > 0 and demo_tx >= 0xd0 then demo_dir = -1
 elseif demo_dir < 0 and demo_tx <= 0x14 then demo_dir = 1 end
 demo_tx = clamp(CLAMP_LO, demo_tx + demo_dir * 2, CLAMP_HI)
 demo_dt = demo_dt + 1
 if demo_dt >= DEMO_DWELL[demo_seg + 1] then
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
 lives = START_LIVES
 sd_plane, sd_heli, sd_bomber, sd_cruise = 0, 0, 0, 0
 shots_fired, shots_hit = 0, 0
 demo_tx = 120
 demo_dir = 1
 demo_seg = 0
 demo_dt = 0
 demo_end_t = 0 -- 60fps frames since the fleet re-formed after the sinking
 play_init()
 armed = true -- the demo boat opens fire immediately
end

-- run the demo game; A starts a real one, B goes back to the title
function demo_update()
 play_update()
 if bp() then
  demo = false
  sfx_stop(2)
  goto_title_settled()
  return
 end
 -- no overall timer: the demo plays until its boat has sunk and the fleet
 -- has re-formed, then holds DEMO_END_SECS and ends (the demo boat never
 -- respawns -- only player input could re-arm it), or until the wave
 -- clears; fire starts the real game
 if p_st == 3 and p_t > 25 and formation_ready() then
  demo_end_t = demo_end_t + frame_dt()
 end
 if demo_end_t >= DEMO_END_SECS * 60 or wave > 1 or xp() then
  demo = false
  sfx_stop(2)
  if xp() then start_game() else goto_points() end
 end
end

------ table screens ------

-- header + sea; hitop() last so the banner never overdraws the hiscore line
-- (also the options page's header, state_options.lua)
function tbl_head(s)
 cls(COLOR_SLOT_0)
 waves_draw()
 bigtext("WAVY NAVY", 18, COLOR_SLOT_11, COLOR_SLOT_9)
 if s then cprint(s, 36, COLOR_SLOT_14) end
 hitop()
end

-- hold the point table until every row is shown, then the rank table
function points_update()
 pg_tick(goto_ranks, PT_DONE)
end

-- draw the point table, revealing one row every PT_STEP frames
function points_draw()
 tbl_head()
 local shown = math.min(#PT_ROWS, pg_t // PT_STEP + 1)
 -- block geometry from every row, so it doesn't shift as rows reveal
 local sw, tw = 0, 0
 for _, r in ipairs(PT_ROWS) do
  sw = math.max(sw, r[4])
  tw = math.max(tw, print(r[2], 0, -8, COLOR_SLOT_15)) -- measure offscreen
 end
 local bx = fld_cx(sw + PT_GAP + tw) -- block's visible left edge
 local tx = bx + sw + PT_GAP -- shared text column
 for i = 1, shown do
  local r = PT_ROWS[i]
  local y = PT_FIRST_YPOS + (i - 1) * 16
  local sx = bx + sw - r[4] - r[3] -- right edge on the column's right edge
  if r[1] == "plane" then
   spr(SPRITE_BANK + SPRITE_PLANE, sx, y - 4, COLOR_SLOT_0, 1, 0, 0, 2, 2)
  elseif r[1] == "heli" then
   -- right-facing heli (rotor fully drawn); heli_blade_black fakes the
   -- spin, eating the blade's rear and forward tip by turns
   spr(SPRITE_BANK + SPRITE_HELI, sx, y, COLOR_SLOT_0, 1, 0, 0, 2, 1)
   heli_blade_black(sx, y)
  elseif r[1] == "bomber" then
   spr(SPRITE_BANK + SPRITE_BOMBER, sx, y, COLOR_SLOT_0, 1, 0, 0, 3, 1)
  else
   local cid, cdx = cruise_frame(1) -- nose-right, matching the other rows
   spr(cid, sx + cdx, y, COLOR_SLOT_0, 1, 0, 0, 5, 1)
  end
  print(r[2], tx, y + 1, COLOR_SLOT_7)
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
  print(WCFG_RANK[i], FLD_OX + 6 + col * 110, 56 + ((i - 1) % 5) * 12, COLOR_SLOT_7)
 end
end
