-- state_bonus.lua
-- BONUS state (the original has no level bonus): in ADVANCED and EXPERT,
-- after the clear's walk home (and any hatch) and before the next maze, the
-- mode's DIFFICULTY_BONUS x levels cleared so far is counted up BONUS_PT_INCR
-- points per blip, one blip every BONUS_TICK_DELAY ticks, rising in pitch.
-- Fire skips to the total. BEGINNER and the demo change the maze at once.

bonus={}

-- the end of a level clear (state_gohome.lua / state_hatch.lua)
function level_done()
 local per=DIFFICULTY_BONUS[game_difficulty+1]
 if per==0 then
  advance_level()
  return
 end
 if gohome_instant then -- the test harness: no count, same points
  award(per*level)
  advance_level()
  return
 end
 bonus.per=per
 bonus.levels=level -- levels cleared, this one included (advance_level then counts it)
 bonus.total=per*level
 bonus.total_blips=math.ceil(bonus.total/BONUS_PT_INCR)
 bonus.pts=0 -- counted so far
 bonus.blips=0
 bonus.t=0
 bonus.phase="wait"
 game_state="BONUS"
 game_update=bonus_update
 game_draw=bonus_draw
end

-- count up to n more points (the last blip may be short of BONUS_PT_INCR)
local function count_pts(n)
 n=math.min(n,bonus.total-bonus.pts)
 bonus.pts=bonus.pts+n
 award(n)
end

function bonus_update()
 bonus.t=bonus.t+1/30
 local p=bonus.phase
 if p=="wait" then
  if bonus.t>=BONUS_WAIT_SECS then
   bonus.phase="count"
   bonus.wait=1 -- ticks to the next blip: the first comes at once
  end

 elseif p=="count" then
  if fire_pressed then
   count_pts(bonus.total)
  else
   bonus.wait=bonus.wait-1
   if bonus.wait<=0 then
    bonus.wait=BONUS_TICK_DELAY
    count_pts(BONUS_PT_INCR)
    bonus.blips=bonus.blips+1
    -- Spread the rise over the entire count: no restart at level boundaries.
    local step=math.floor((bonus.blips-1)*(#BONUS_NOTES-1)
     /math.max(1,bonus.total_blips-1))
    snd("tally",BONUS_NOTE+BONUS_NOTES[step+1])
   end
  end
  if bonus.pts>=bonus.total then
   bonus.phase="hold"
   bonus.t=0
  end

 elseif p=="hold" then
  if bonus.t>=BONUS_HOLD_SECS or fire_pressed then
   bonus.phase="done"
   advance_level()
  end
 end
end

-- the frozen board under three lines: difficulty BONUS, levels completed,
-- and the counting total at double size. Measure the final total so the
-- box stays the same width while the centred count grows.
-- The box fits the widest line with 8 px of padding each side, centred on screen
function bonus_draw()
 play_draw()
 local title=DIFFICULTY_NAMES[game_difficulty+1].." BONUS"
 local line=string.format("%d X %d LEVELS COMPLETED",bonus.per,bonus.levels)
 local total="+"..tostring(bonus.pts)
 local tw=print(title,0,-20,TEXT_COLOR,true)
 local lw=print(line,0,-20,TEXT_COLOR,true)
 local final_width=print("+"..tostring(bonus.total),0,-20,TEXT_COLOR,true,2)
 local total_width=print(total,0,-20,TEXT_COLOR,true,2)
 local w=math.max(tw,lw,final_width)+16
 local h=52 -- two small lines, one double-size total, 9 px bottom padding
 local x=(240-w)//2
 local y=(136-h)//2
 drop_shadow(x,y,w,h)
 rect(x,y,w,h,BLACK)
 rectb(x,y,w,h,WHITE)
 print(title,(240-tw)//2,y+9,WHITE,true)
 print(line,(240-lw)//2,y+19,BLUE,true)
 print(total,(240-total_width)//2,y+31,BLUE,true,2)
end
