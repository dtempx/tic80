-- clear: wave clear - rank display, lives bonus tally, wave bonus

-- start the wave-clear screen: reset the tallies and play the wave's jingle
function clear_init()
 clear_t = 0
 sea_ph = 0 -- sea holds still during the promotion
 clear_ph = "jingle"
 tally = 0   -- reserve boats revealed so far
 tally_t = 0
 hold_t = 0
 dtally = 0  -- waves counted so far in the wave-bonus tally
 -- wave bonus: per-difficulty points (0 on beginner) x waves cleared, not
 -- counting the waves advanced/expert skip at the start
 dcleared = waves_cleared()
 dbonus = diff_bonus[diff + 1] * dcleared
 -- the jingle of the wave just cleared (wave was bumped at clear)
 clear_song = wcfg_song[math.min(wave - 1, 10)]
 play_song(clear_song)
end

-- reveal one reserve boat at a time (+50 each, tick per icon); fire skips;
-- then award the +1 ship (cap 9) and move on to the wave bonus
local function clear_tally()
 tally_t = tally_t + frame_dt()
 if tally_t > 12 and fp() then -- skip: award the rest at once
  while tally < bonus_ships do
   tally = tally + 1
   add_score(50)
  end
 elseif tally < bonus_ships and tally_t >= bonus_step then
  tally_t = 0
  tally = tally + 1
  add_score(50)
  play_song(10) -- bonus tick
 end
 if tally >= bonus_ships and tally_t > bonus_step then
  if bonus_ships < 9 then
   -- +1 ship, plus the mode's extras once late_lives_wave is cleared (wave
   -- was bumped at clear); the total still caps at 9 like the original's
   local extra = wave - 1 >= late_lives_wave and diff_wave_lives[diff + 1] or 0
   lives = math.min(lives + 1 + extra, 9)
  end
  clear_ph = dbonus > 0 and "dwait" or "hold"
  hold_t = 0
 end
end

-- the wave bonus counts up the same way the boats do: one wave per step, each
-- worth the difficulty's per-wave points, with the same blip. The step shrinks
-- as the run gets long so a deep wave's tally never outstays the screen.
local function clear_dtally()
 tally_t = tally_t + frame_dt()
 local per = diff_bonus[diff + 1]
 local step = math.max(bonus_step // math.max(wave // 6, 1), 8)
 if tally_t > 12 and fp() then -- skip: award the rest at once
  while dtally < dcleared do
   dtally = dtally + 1
   add_score(per)
  end
 elseif dtally < dcleared and tally_t >= step then
  tally_t = 0
  dtally = dtally + 1
  add_score(per)
  play_song(10) -- bonus tick
 end
 if dtally >= dcleared and tally_t > step then
  clear_ph = "hold"
  hold_t = 0
 end
end

-- step the phases: jingle -> lives bonus -> pause -> wave bonus -> hold -> get ready
function clear_update()
 clear_t = clear_t + frame_dt() -- dt: pacing holds real seconds at any fps
 if clear_ph == "jingle" then
  -- follow the song; the guard delays skip, the cap keeps silent runs moving
  if clear_t > 40 and (not music_playing() or fp()) or clear_t > 2400 then
   song_stop() -- fire-skip can land mid-jingle
   clear_ph = "bonus"
   tally_t = 0
  end
 elseif clear_ph == "bonus" then
  clear_tally()
 elseif clear_ph == "dwait" then
  -- 2s pause after the lives bonus, then the wave bonus counts up
  hold_t = hold_t + frame_dt()
  if hold_t >= 120 or fp() then
   clear_ph = "dbonus"
   tally_t = 0
  end
 elseif clear_ph == "dbonus" then
  clear_dtally()
 elseif clear_ph == "hold" then
  hold_t = hold_t + frame_dt()
  if hold_t >= 240 or fp() then goto_ready() end
 end
end

-- draw the promotion, the lives-bonus boat row and the wave-bonus block
function clear_draw()
 cls(0)
 waves_draw()
 -- rank tops out at min(wave,10), further capped by difficulty ($144C)
 local r = math.min(wave, 10, diff_rankcap[diff + 1])
 cprint(r >= 10 and "YOU HAVE BECOME" or "YOU HAVE BEEN PROMOTED TO", 30, 6)
 -- deckhand/crewchief read violet/blue (original even-column art), else
 -- green/orange - the original's two-tone rank text
 local odd = r == 4 or r == 5
 bigtext(wcfg_rank[r], 42, odd and 14 or 11, odd and 12 or 9)
 if clear_ph == "jingle" then
  -- the jingle's title in grey, centered on the screen, a note on each side
  local s = song_names[clear_song + 1]
  local w = print(s, 0, -8)
  local x = (scr_w - w - 19) // 2
  local y = (scr_h - 5) // 2
  spr(256 + spr_note, x, y, 0)
  print(s, x + 10, y, 6)
  spr(256 + spr_note, x + w + 12, y, 0)
 else
  status_draw() -- score visibly ticks up through the bonuses
  local ships = clear_ph == "bonus" and tally or bonus_ships
  print("BONUS", 70, 70, 9)
  if clear_ph ~= "bonus" or (clear_t // 8) % 2 == 0 then
   print("50 X", 106, 70, 7)
  end
  clip_field()
  for i = 1, ships do
   boat_spr(0, 130 + (i - 1) * 14, 63) -- upright hull + its code-drawn gun
  end
  clip()
 end
 -- wave bonus block, laid out as a column against the lives-bonus line above:
 -- the yellow "<DIFF> / BONUS" stack is right-aligned to x=100 where the
 -- orange "BONUS" ends, the white multiplier starts at x=106 where "50 X"
 -- does, and the white "WAVES / CLEARED" stack sits right of the count. The
 -- count itself is 2x orange and tallies up like the boat row does.
 if dbonus > 0 and (clear_ph == "dwait" or clear_ph == "dbonus" or clear_ph == "hold") then
  local y = 88
  -- print s right-aligned to x=100
  local function rprint(s, ry, c) print(s, 100 - print(s, 0, -8), ry, c) end
  rprint(diff_names[diff + 1], y, 10)
  rprint("BONUS", y + 10, 10)
  -- the multiplier blinks from the moment the line appears until the wave
  -- count stops ticking, exactly as "50 X" does over the lives bonus
  if clear_ph == "hold" or (clear_t // 8) % 2 == 0 then
   print(diff_bonus[diff + 1] .. " X", 106, y + 5, 7)
  end
  -- the count's slot is sized for the final number so the caption never
  -- shifts as the tally climbs; the number is centered within it
  local nw = print(dcleared, 0, -16, 9, false, 2)
  local x = 142
  -- the count blinks while it is tallying and settles solid on its final
  -- value once the tally is done
  if dtally > 0 and (clear_ph == "hold" or (clear_t // 8) % 2 == 0) then
   print(dtally, x + (nw - print(dtally, 0, -16, 9, false, 2)) // 2, y + 3, 9,
         false, 2)
  end
  print("WAVES", x + nw + 5, y, 7)
  print("CLEARED", x + nw + 5, y + 10, 7)
 end
end
