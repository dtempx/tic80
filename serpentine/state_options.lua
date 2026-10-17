-- state_options.lua
-- BOOT stores apple2.boot's capability result in a2_display. Without
-- alt_display, the entire theme row is dimmed, skipped and cannot change.
-- options page, opened with B from the title (the original has none):
-- difficulty (applied from the next game: game_state.lua difficulty_level,
-- state_bonus.lua), theme (THEME_NAMES; the first three are a2boot.lua's
-- colour / green / white Apple II monitor), SNAKE_BUZZ and a high-score reset. Up/down picks a row,
-- A or right steps it forward, left back (settings wrap; the on-screen
-- help names only A), B returns to the title. RESET HISCORE is greyed out
-- and skipped by up/down while there is no record to reset; clearing it puts
-- the cursor back on the first row. Every change is saved to pmem at once
-- (records.lua set_difficulty, theme_set, set_snake_buzz).

local ROWS={"DIFFICULTY","THEME","SNAKE BUZZ","RESET HISCORE"}
local DIFF,THEME,BUZZ,RESET=1,2,3,4
local CLEARED_SECS=1.5 -- how long "CLEARED" shows after a reset
-- the control help, one line each, centred as a block with the dashes aligned
local HELP={{"UP/DOWN","SELECT"},{"A BUTTON","CHANGE"},{"B BUTTON","GO BACK"}}
local HELP_Y,HELP_DY=92,10 -- first help line's y, px between help lines

local sel=1 -- the highlighted row
local confirm=false -- the reset row is waiting for its second A
local cleared=0 -- seconds left of "CLEARED"
local march=0 -- the frame studs' march offset, as on the title

-- enter the OPTIONS state on the first row
function options_init()
 game_state="OPTIONS"
 game_update=options_update
 game_draw=options_draw
 sel,confirm,cleared=1,false,0
end

-- change the highlighted row's setting by d (+1 or -1)
local function change(d)
 if sel==THEME and not a2_display.alt_display then return end
 if sel==DIFF then set_difficulty(d)
 elseif sel==THEME then theme_set(theme+d)
 elseif sel==BUZZ then set_snake_buzz(not snake_buzz_enabled)
 else return end
 snd("blip1")
end

-- row i can be picked: RESET HISCORE only while there is a record to wipe
local function enabled(i)
 if i==THEME then return a2_display.alt_display end
 return i~=RESET or hiscore>0 or hilevel>1
end

-- move the highlight by d rows, wrapping and skipping disabled rows
local function step(d)
 local i=sel
 repeat i=(i-1+d)%#ROWS+1 until enabled(i) or i==sel
 sel=i
end

function options_update()
 march=(march+TITLE_MARCH_SPEED)%TITLE_STUD_SPACING
 if cleared>0 then cleared=cleared-1/30 end
 if back_pressed then title_init() return end
 local m=menu_pressed
 if m==0 or m==1 then
  step(m==0 and -1 or 1)
  confirm=false
 elseif m==2 or m==3 then
  change(m==2 and -1 or 1)
 end
 if start_pressed and enabled(sel) then
  if sel==RESET then
   if confirm then
    snd("devour")
    records_reset()
    cleared=CLEARED_SECS
    sel=1 -- the row is disabled now: back to the first one
   else
    snd("blip1")
   end
   confirm=not confirm
  else
   change(1)
  end
 end
end

-- the setting shown to the right of row i
local function value(i)
 if i==DIFF then return DIFFICULTY_NAMES[difficulty+1] end
 if i==THEME then return a2_display.alt_display and THEME_NAMES[theme+1] or "UNAVAILABLE" end
 if i==BUZZ then return snake_buzz_enabled and "ON" or "OFF" end
 if i==RESET then
  if confirm then return "PRESS A AGAIN" end
  if cleared>0 then return "CLEARED" end
  if i==sel then return "PRESS A TO RESET" end
 end
 return ""
end

function options_draw()
 cls(BLACK)
 draw_frame(OFFSET_X,OFFSET_Y,MAZE_COLUMNS*CELL_W,MAZE_ROWS*CELL_H,
  TITLE_STUD_SPACING,march)

 local w=print("OPTIONS",0,-40,TEXT_COLOR,false,2)
 print("OPTIONS",(240-w)//2,14,TEXT_COLOR,false,2)

 for i,label in ipairs(ROWS) do
  local y=OPTIONS_ROW_Y+(i-1)*OPTIONS_ROW_DY
  local c=not enabled(i) and OPTIONS_DISABLED_COLOR
   or (i==sel) and GREEN or TEXT_COLOR
  if i==sel then print(">",OPTIONS_LABEL_X-8,y,c) end
  print(label,OPTIONS_LABEL_X,y,c)
  print(value(i),OPTIONS_VALUE_X,y,c)
 end

 -- keys right-aligned to a shared dash column, the block centred on screen
 local kw,aw=0,0
 for _,h in ipairs(HELP) do
  kw=math.max(kw,print(h[1],0,-40,PINK))
  aw=math.max(aw,print(" - "..h[2],0,-40,PINK))
 end
 local dx=(240-kw-aw)//2+kw
 for i,h in ipairs(HELP) do
  local y=HELP_Y+(i-1)*HELP_DY
  print(h[1],dx-print(h[1],0,-40,PINK),y,DIM_WHITE)
  print(" - "..h[2],dx,y,DIM_WHITE)
 end
end
