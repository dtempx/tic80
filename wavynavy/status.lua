-- status: the HUD in the right rail (score / wave / difficulty / lives), score
-- bookkeeping, and the shared text helpers

-- add v points (4-digit wrap) and raise the hiscore to match
function add_score(v)
 if demo then return end -- the attract demo never scores or sets the hiscore
 score = (score + v) % 10000 -- the original's 4-digit BCD display wrap
 if score > hi then hi = score end
end

-- ------------------------------------------------------------------- HUD

-- The HUD sits in the right rail, as the original's own HUD was a right-hand
-- column: left-aligned on the rail's third column, HUD_DX past the field, in
-- the small font, each label over its value. HISCORE (27 px) and a row of
-- four boats (26 px) end by the screen's last column
local HUD_DX = 2          -- the HUD's column: FLD_OX + FLD_W + HUD_DX
local HUD_Y = {4, 25, 46} -- the three label rows; each value 8 px under its label
local BOAT_ROW, BOAT_PITCH = 4, 7 -- reserve boats: up to 4 a row, 7 px apart, LIVES_MAX in all

-- one line of rail text in the small font (fixed-width digits if asked)
local function hud_text(s, y, c, fixed)
 print(s, FLD_OX + FLD_W + HUD_DX, y, c, fixed, 1, true)
end

-- a label and its value (fixed-width digits) under it
local function hud_item(label, value, y)
 hud_text(label, y, COLOR_STATUS)
 hud_text(value, y + 8, COLOR_SLOT_7, true)
end

-- the hiscore at the top of the rail (all attract screens and the demo);
-- hidden until one has actually been set - a "HISCORE 0" line is noise
function hitop()
 if hi and hi > 0 then hud_item("HISCORE", string.format("%06d", hi), HUD_Y[1]) end
end

-- reveal a string array one line at a time, `step` frames apart
function reveal_lines(lines, t, step, y0, dy, c)
 for i = 1, math.min(#lines, t // step + 1) do
  cprint(lines[i], y0 + i * dy, c)
 end
end

-- print centred on the playfield (print returns the width, measured offscreen)
function cprint(s, y, c)
 local w = print(s, 0, -8, COLOR_SLOT_15)
 print(s, fld_cx(w), y, c)
end

-- 2x-scale text centred on the playfield, colored top/bottom halves (the
-- original's two-tone rank/banner look), split with clip()
function bigtext(s, y, ct, cb)
 cb = cb or ct
 local w = print(s, 0, -16, ct, false, 2)
 local x = fld_cx(w)
 clip(0, y, SCR_W, 6)
 print(s, x, y, ct, false, 2)
 clip(0, y + 6, SCR_W, 6)
 print(s, x, y, cb, false, 2)
 clip()
end

-- play: score, wave (with the difficulty badge: one + for GEN-Y, two for
-- zoomer) and the reserve boats, one icon per spare life. No hiscore, as the
-- original's play screen ($1FDA)
function status_draw()
 hud_item("SCORE", string.format("%06d", score), HUD_Y[1])
 hud_item("WAVE", wave .. string.rep("+", diff), HUD_Y[2])
 hud_text("BOATS", HUD_Y[3], COLOR_STATUS)
 local x0 = FLD_OX + FLD_W + HUD_DX
 for i = 0, math.min(math.max(lives - 1, 0), LIVES_MAX) - 1 do
  mono.draw_solid(spr, SPRITE_BANK + SPRITE_LIFE, x0 + i % BOAT_ROW * BOAT_PITCH,
                  HUD_Y[3] + 8 + i // BOAT_ROW * BOAT_PITCH, COLOR_SLOT_0)
 end
end
