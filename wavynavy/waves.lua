-- waves: sea surface model, scroll, rendering, submerged-sprite draws

-- reset the swell's scroll phase
function waves_init()
 sea_ph = 0
 prev_ph = 0
end

-- advance scroll by this wave's signed sea velocity ($1279 divisor)
function waves_tick()
 prev_ph = sea_ph
 sea_ph = sea_ph + WCFG_SEAVEL[math.min(wave, 10)]
end

-- a sim tick with the swell held still (the respawn get-ready): settle the
-- draw-time phase on the current one. Left alone, prev_ph keeps the last
-- moving tick's phase and waves_dph() swings between the two on every
-- draw_fraction cycle, so the frozen sea and the boat riding it flicker by a
-- pixel at 3-4 frame intervals
function waves_hold()
 prev_ph = sea_ph
end

-- sea surface height at apple-x (the $4A00 table's 2-crest sine).
-- SIM clock only (collision, sea-riding): uses the current tick's phase.
function waves_y(ax)
 return SEA_MID + SEA_AMP * math.sin((ax + sea_ph) / SEA_LEN * 2 * math.pi)
end

-- draw-time surface height: phase interpolated between the last two ticks so
-- the swell rolls at display rate (attract states scroll sea_ph per display
-- frame; there lerpd's teleport snap just yields the live phase)
function waves_dph() return lerpd(prev_ph, sea_ph) end
-- surface height at apple-x ax for phase ph (default: the draw-time phase)
function waves_dy(ax, ph)
 return SEA_MID + SEA_AMP * math.sin((ax + (ph or waves_dph())) / SEA_LEN * 2 * math.pi)
end

-- fill the pillarboxed playfield only: each screen column maps back to its
-- apple-x through the inverse of scrx, so the swell keeps the original's shape
function waves_draw()
 local ph = waves_dph()
 for x = FLD_OX, FLD_OX + FLD_W - 1 do
  local ay = waves_dy((x - FLD_OX) / SCALE_X + FLD_X0, ph)
  line(x, scry(ay), x, SCR_H - 1, COLOR_SLOT_12)
 end
end

-- draw a sprite block; the part below the sea surface (at apple-x ax) is
-- forced white, the original's look for anything in the water
function wspr(id, sx, sy, w, h, flip, ax)
 local surf = scry(waves_dy(ax))
 if sy >= surf then
  pal_white()
  spr(id, sx, sy, COLOR_SLOT_0, 1, flip, 0, w, h)
  pal_reset()
 elseif sy + h * 8 <= surf then
  spr(id, sx, sy, COLOR_SLOT_0, 1, flip, 0, w, h)
 else
  clip(FLD_OX, 0, FLD_W, surf)
  spr(id, sx, sy, COLOR_SLOT_0, 1, flip, 0, w, h)
  clip(FLD_OX, surf, FLD_W, SCR_H - surf)
  pal_white()
  spr(id, sx, sy, COLOR_SLOT_0, 1, flip, 0, w, h)
  pal_reset()
  clip_field() -- restore the field clip, not the full screen
 end
end
