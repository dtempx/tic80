-- waves: sea surface model, scroll, rendering, submerged-sprite draws

-- reset the swell's scroll phase
function waves_init()
 sea_ph = 0
 prev_ph = 0
end

-- advance scroll by this wave's signed sea velocity ($1279 divisor)
function waves_tick()
 prev_ph = sea_ph
 sea_ph = sea_ph + wcfg_seavel[math.min(wave, 10)]
end

-- sea surface height at apple-x (the $4A00 table's 2-crest sine).
-- SIM clock only (collision, sea-riding): uses the current tick's phase.
function waves_y(ax)
 return sea_mid + sea_amp * math.sin((ax + sea_ph) / sea_len * 2 * math.pi)
end

-- draw-time surface height: phase interpolated between the last two ticks so
-- the swell rolls at display rate (attract states scroll sea_ph per display
-- frame; there lerpd's teleport snap just yields the live phase)
function waves_dph() return lerpd(prev_ph, sea_ph) end
-- surface height at apple-x ax for phase ph (default: the draw-time phase)
function waves_dy(ax, ph)
 return sea_mid + sea_amp * math.sin((ax + (ph or waves_dph())) / sea_len * 2 * math.pi)
end

-- fill the pillarboxed playfield only: each screen column maps back to its
-- apple-x through the inverse of scrx, so the swell keeps the original's shape
function waves_draw()
 local ph = waves_dph()
 for x = fld_ox, fld_ox + fld_w - 1 do
  local ay = waves_dy((x - fld_ox) / scale_x + fld_x0, ph)
  line(x, scry(ay), x, scr_h - 1, 12)
 end
end

-- draw a sprite block; the part below the sea surface (at apple-x ax) is
-- forced white, the original's look for anything in the water
function wspr(id, sx, sy, w, h, flip, ax)
 local surf = scry(waves_dy(ax))
 if sy >= surf then
  pal_white()
  spr(id, sx, sy, 0, 1, flip, 0, w, h)
  pal_reset()
 elseif sy + h * 8 <= surf then
  spr(id, sx, sy, 0, 1, flip, 0, w, h)
 else
  clip(fld_ox, 0, fld_w, surf)
  spr(id, sx, sy, 0, 1, flip, 0, w, h)
  clip(fld_ox, surf, fld_w, scr_h - surf)
  pal_white()
  spr(id, sx, sy, 0, 1, flip, 0, w, h)
  pal_reset()
  clip_field() -- restore the field clip, not the full screen
 end
end
