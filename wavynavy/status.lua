-- status: the top strip (score / wave / difficulty / lives), score bookkeeping,
-- and the shared text helpers

-- add v points (4-digit wrap) and raise the hiscore to match
function add_score(v)
 if demo then return end -- the attract demo never scores or sets the hiscore
 score = (score + v) % 10000 -- the original's 4-digit BCD display wrap
 if score > hi then hi = score end
end

-- hiscore centered at the top in blue (all attract screens); hidden until one
-- has actually been set - a "HISCORE 0" line is noise
function hitop()
 if not hi or hi <= 0 then return end
 cprint("HISCORE " .. hi, 1, 12)
end

-- reveal a string array one line at a time, `step` frames apart
function reveal_lines(lines, t, step, y0, dy, c)
 for i = 1, math.min(#lines, t // step + 1) do
  cprint(lines[i], y0 + i * dy, c)
 end
end

-- centered print (print returns the width, measured offscreen)
function cprint(s, y, c)
 local w = print(s, 0, -8)
 print(s, (scr_w - w) // 2, y, c)
end

-- centered 2x-scale text, colored top/bottom halves (the original's two-tone
-- rank/banner look), split with clip()
function bigtext(s, y, ct, cb)
 cb = cb or ct
 local w = print(s, 0, -16, ct, false, 2)
 local x = (scr_w - w) // 2
 clip(0, y, scr_w, 6)
 print(s, x, y, ct, false, 2)
 clip(0, y + 6, scr_w, 6)
 print(s, x, y, cb, false, 2)
 clip()
end

-- the whole strip is laid out inside the pillarboxed field [fld_ox, fld_ox+fld_w)
-- so it never spills onto the black bars beside the playing area
function status_draw()
 print(string.format("SCORE %06d", score), fld_ox + 2, 0, status_c, true)
 -- wave readout, with the difficulty badge appended: one + for advanced, two
 -- for expert (all one string so the label centers as a unit); nudged
 -- `wave_dx` px right of the field centre to sit clear of the score
 local s = "WAVE " .. wave
 if diff > 0 then s = s .. string.rep("+", diff) end
 local w = print(s, 0, -8, status_c, true)
 print(s, fld_ox + (fld_w - w) // 2 + wave_dx, 0, status_c, true)
 -- reserve boats right-aligned to the field's right edge: one icon per spare
 -- life, capped so a long row can never reach back to the WAVE readout
 for i = 1, math.min(math.max(lives - 1, 0), lives_max) do
  mono.draw_solid(spr, 256 + spr_life, fld_ox + fld_w - 2 - i * 7, 1, 0)
 end
end
