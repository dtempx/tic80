-- ready: get-ready pause before each wave (start_game, and after the clear
-- intermission); frozen swell, steerable boat. NOT used after a respawn: that
-- get-ready stays in the play state (boat.lua respawn -> boat_init sets
-- armed=false, play_draw shows the prompt, mines_offscreen parks the mines)

-- freeze the swell and centre the boat for the get-ready pause
function ready_init()
 waves_init() -- sea_ph=0 and no waves_tick: the swell holds still
 ready_t = 0
 racc = 0 -- sim-tick accumulator for the steering glide
 p_x = 120 -- waves start centered; respawns keep the default via boat_init
 p_st = 0
 p_y = waves_y(p_x)
 p_px, p_py = p_x, p_y
 msl = nil
end

-- let the boat steer until fire starts the wave
function ready_update()
 local dt = frame_dt()
 ready_t = ready_t + dt
 -- glide at the normal boat pace over the frozen swell; no firing. Steering
 -- steps on the sim clock (as in play) so the pace matches the live game.
 -- 2*BOAT_DX per tick: the original's two PLAYERUPD passes (see boat.lua)
 racc = (racc or 0) + OSTEP * GSPEED * dt
 while racc >= 1 do
  racc = racc - 1
  p_px = p_x -- last-tick x for the draw interpolation
  if btn(2) then p_x = math.max(p_x - 2 * BOAT_DX, CLAMP_LO) end
  if btn(3) then p_x = math.min(p_x + 2 * BOAT_DX, CLAMP_HI) end
 end
 draw_fraction = racc
 p_y = waves_y(p_x)
 if ready_t > 20 and fp() then goto_play() end -- grace vs the opening press
end

-- draw the sea, the boat, the HUD (right rail) and the blinking prompt
function ready_draw()
 cls(COLOR_SLOT_0)
 clip_field()
 waves_draw()
 boat_draw()
 clip()
 status_draw()
 if time() % 1000 < 600 then cprint("GET READY! PRESS FIRE", 70, COLOR_SLOT_7) end
end
