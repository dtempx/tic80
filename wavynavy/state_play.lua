-- play: 60fps update accumulating 18.75Hz sim ticks; drawing interpolates
-- between ticks (helpers.lua lerpd/lerpw) so motion is smooth at display rate

-- set up a wave: sea, effects, fleet, hazards and the boat
function play_init()
 waves_init()
 fx_init()
 enemies_init()
 hazards_init()
 boat_init(p_x) -- keep the get-ready x
 oacc = 0
 oframe = 0
end

-- record every mover's last-tick position for the draw-time interpolation
local function snap_prev()
 p_px, p_py = p_x, p_y
 if msl then msl.px, msl.py = msl.x, msl.y end
 for _, e in ipairs(ens) do
  e.px = e.x
  e.py = e.y
  e.pex = e.ex
 end
 for _, b in ipairs(bombs) do
  b.px = b.x
  b.py = b.y
 end
 for _, m in ipairs(mines) do m.px = m.x end
 if bomber then bomber.px = bomber.x end
 if cruise then cruise.px, cruise.py = cruise.x, cruise.y end
end

-- one 18.75Hz sim tick (an original frame) of the whole game
function otick() -- global: the headless test harness drives it directly
 snap_prev()
 oframe = (oframe + 1) % 4
 boat_move() -- boat steps on the sim clock (2 steering passes, see boat.lua)
 if demo then demo_ai() end -- advance the AI patrol target
 -- swell + hazards move through the death sequence; halt at respawn
 if armed or p_st ~= 0 then
  waves_tick()
  hazards_tick()
 end
 boat_tick()
 msl_tick()
 enemies_tick()
 bombs_tick()
 if oframe == 0 then
  launch_tick()
  hazards_spawn()
 end
 fx_tick()
end

-- per display frame: poll input, then run however many sim ticks are due
function play_update()
 boat_input() -- polled every display frame so no press is missed between ticks
 chopper_sound()
 oacc = oacc + ostep * gspeed * frame_dt()
 while oacc >= 1 do
  oacc = oacc - 1
  otick()
 end
 draw_fraction = oacc -- how far this display frame sits toward the next sim tick
end

-- empty the board: every enemy, hazard and piece of ordnance goes, and the
-- boat is parked in the gone state (p_st 3, what boat_draw treats as "no
-- hull"). Called when the run ends so the game-over message sits over bare
-- sea instead of a frozen ship and a frozen fleet.
function clear_board()
 ens = {}
 bombs = {}
 mines = {}
 bomber = nil
 cruise = nil
 msl = nil
 p_st = 3
 armed = false
end

-- wave clear -> promotion intermission (bonus counts every surviving ship)
function wave_cleared()
 sfx_stop(2)
 hf_clear() -- drop gunfire rounds still queued (sfx.lua)
 wave = wave + 1
 if demo then return end -- the demo bows out once wave>1 (demo_update sees it)
 bonus_ships = math.max(lives, 0)
 goto_clear()
end

-- draw the playfield, the status line and the get-ready prompt
function play_draw()
 cls(0)
 clip_field() -- world space is pillarboxed; the HUD below is not
 waves_draw()
 mines_draw()
 fx_draw()
 -- fleet shown through death/fly-home; hidden at get-ready. At gameover the
 -- lists are already empty (clear_board), so no state test is needed here.
 if armed or p_st ~= 0 then
  enemies_draw()
  hazards_draw()
 end
 boat_draw() -- p_st 3 draws nothing, which is the gameover case
 clip()
 if demo then hitop() else status_draw() end -- demo: hiscore line only
 if not armed and p_st == 0 and time() % 1000 < 600 then
  cprint("GET READY! PRESS FIRE", 70, 7)
 end
end
