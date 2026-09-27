-- gameover: phase 1 holds "fleet was sunk" under the dirge, phase 2 is the
-- two-tone stats card with the shootdown recap

-- empty the board, stop the drones and start the dirge
function gameover_init()
 gameover_t = 0
 gameover_ph = 1
 oacc = oacc or 0 -- sea ticker; play normally seeds these
 if not booms then fx_init() end
 gameover_dirgeend = nil
 gameover_newhigh = hi > (prev_hi or 0)
 -- the board empties the instant the run ends: no frozen hull, no enemies,
 -- hazards or ordnance left hanging over the sea behind the message
 clear_board()
 sfx_stop(2)
 sfx_stop(3)
 hf_clear() -- drop gunfire rounds still queued (sfx.lua)
 play_song(9) -- fleet-sunk dirge
end

-- keep the sea rolling; hold the message through the dirge, then the stats card
function gameover_update()
 local dt = frame_dt() -- dt: pacing holds real seconds at any fps
 gameover_t = gameover_t + dt
 oacc = oacc + ostep * gspeed * dt -- the sea keeps rolling
 while oacc >= 1 do
  oacc = oacc - 1
  waves_tick()
  fx_tick()
 end
 draw_fraction = oacc -- keep the swell rolling smoothly behind the stats card
 if gameover_ph == 1 then
  -- hold until the dirge ends +2s; the cap keeps silent runs moving
  if gameover_t > 40 and (not music_playing() or gameover_t > 2400) then
   gameover_dirgeend = gameover_dirgeend or gameover_t
   if gameover_t >= gameover_dirgeend + 120 then
    gameover_ph = 2
    gameover_t = 0
   end
  end
 else
  -- lines reveal one per 2s; press skips, then press or 30s -> title
  if gameover_t < 960 then
   if gameover_t > 40 and fp() then gameover_t = 960 end
  elseif gameover_t > 960 + 1800 or fp() then
   goto_title()
  end
 end
end

-- 2x2 shootdown grid: count + sprite per enemy type
local function breakdown_draw(y)
 local numw = 0
 for _, n in ipairs({sd_plane, sd_heli, sd_bomber, sd_cruise}) do
  numw = math.max(numw, #tostring(n) * 6)
 end
 local x0 = 80
 -- count n right-aligned in a numw-wide slot at (cx, cy)
 local function cell(n, cx, cy)
  local s = tostring(n)
  print(s, cx + numw - #s * 6, cy + 1, 7, true)
 end
 cell(sd_plane, x0, y)
 spr(256 + spr_plane, x0 + numw + 6, y - 4, 0, 1, 0, 0, 2, 2)
 cell(sd_heli, x0, y + 12)
 -- right-facing heli (single sprite, rotor fully drawn); heli_blade_black
 -- fakes the spin, eating the blade's rear and forward tip by turns
 spr(256 + spr_heli, x0 + numw + 6, y + 12, 0, 1, 0, 0, 2, 1)
 heli_blade_black(x0 + numw + 6, y + 12)
 local x1 = 126
 cell(sd_bomber, x1, y)
 spr(256 + spr_bomber, x1 + numw + 6, y, 0, 1, 0, 0, 3, 1)
 cell(sd_cruise, x1, y + 12)
 local cid, cdx = cruise_frame(-1)
 spr(cid, x1 + numw + 6 + cdx, y + 12, 0, 1, 0, 0, 5, 1)
end

-- phase 1: "fleet was sunk" over the empty sea; phase 2: rank, stats and recap
function gameover_draw()
 if gameover_ph == 1 then
  play_draw() -- message over the emptied board (clear_board ran at init)
  cprint("YOUR ENTIRE FLEET WAS SUNK", 62, 8)
  return
 end
 cls(0)
 waves_draw()
 oframe = (time() // 130) % 4 -- rotor/flame anim on a screen with no sim
 cprint("YOU REACHED THE RANK OF", 16, 6)
 local r = math.min(wave, 10, diff_rankcap[diff + 1])
 local odd = r == 4 or r == 5
 bigtext(wcfg_rank[r], 26, odd and 14 or 11, odd and 12 or 9)
 hitop()
 local total = sd_plane + sd_heli + sd_bomber + sd_cruise
 local acc = shots_fired > 0 and math.floor(shots_hit * 100 / shots_fired) or 0
 local lines = {
  "SCORE " .. score,
  "DIFFICULTY: " .. diff_names[diff + 1],
  waves_cleared() .. " WAVES CLEARED",
  shots_fired .. " SHOTS FIRED",
  "ACCURACY " .. acc .. "%",
  total .. " ENEMIES SHOT DOWN",
 }
 reveal_lines(lines, math.max(gameover_t - 120, 0), 120, 34, 9, 7)
 if gameover_t >= #lines * 120 then breakdown_draw(100) end
 if gameover_newhigh and time() % 1000 < 600 then cprint("NEW HIGH SCORE!", 8, 10) end
end
