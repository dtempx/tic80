-- state_title.lua
-- standalone title screen; start builds the maze and enters the pregame wait,
-- and after DEMO_WAIT_SECS untouched the attract demo starts (state_demo.lua)
-- the original shows its title picture only while it boots, then wipes
-- straight into the demo (SCRNWIPE $1D3C with ATTRACTFL $D6 set)

-- enter the TITLE state
function title_init()
 game_state="TITLE"
 game_update=title_update
 game_draw=title_draw
 title_march=0 -- frame-stud march offset, px along the frame
 title_timer=0 -- seconds shown, toward the demo
 attract=false -- ATTRACTFL $D6 clear: no demo running
 game_difficulty=0 -- no game running, so the title runs at DIFFICULTY_GAME_SPEED[1]
 tick_stretch=1
end

-- march the frame studs; start a game on A (the original starts from attract
-- on 'K' or button 0, $96F4/$9702); B opens the options page
function title_update()
 title_march=(title_march+TITLE_MARCH_SPEED)%TITLE_STUD_SPACING
 if start_pressed then
  start_game()   -- build the maze and stage the pen lineup
  pregame_enter() -- jingle plays over the maze; snakes launch when it ends
  return
 end
 if back_pressed then
  options_init()
  return
 end
 title_timer=title_timer+1/30
 if title_timer>=DEMO_WAIT_SECS then demo_init() end
end

-- print s centred on the screen in the default font
function print_centered(s,y,c)
 local w=print(s,0,-40,c)
 print(s,(240-w)//2,y,c)
end

-- records (records.lua), two centred lines from y, shown only once a
-- game has scored. Blue in colour; on a mono monitor print() is forced to
-- solid white (a2boot.lua), so they are never striped
function draw_records(y)
 if hiscore<=0 then return end
 print_centered("HISCORE "..hiscore,y,RECORDS_COLOR)
 print_centered("HIGHEST LEVEL: "..hilevel,y+9,RECORDS_COLOR)
end

-- the original's title picture: studded frame, big serif logo, credits
-- (layout read off the original screen; the start prompt sits where it has
-- "Broderbund Software")
function title_draw()
 cls(BLACK)
 draw_frame(OFFSET_X,OFFSET_Y,MAZE_COLUMNS*CELL_W,MAZE_ROWS*CELL_H,
  TITLE_STUD_SPACING,title_march)

 local x=(240-LOGO_W)//2
 spr(SPRITE_LOGO,x,20,BLACK,1,0,0,16,3)
 spr(SPRITE_LOGO_RIGHT,x+128,20,BLACK,1,0,0,8,3)

 -- credits in the maze walls' violet (mono: forced solid white, a2boot.lua)
 print_centered("ORIGINAL BY DAVID SNIDER (1982)",57,WALL_COLOR)
 print_centered("REMAKE BY DAVE TEMPLIN",68,WALL_COLOR)

 draw_records(82)

 if time()//500%2==0 then -- real-time blink, independent of TIC() rate
  print_centered("PRESS A TO START",106,WHITE)
  print_centered("OR PRESS B FOR OPTIONS",116,WHITE)
 end
 -- the current difficulty, steady under the blinking prompt
 print_centered("DIFFICULTY: "..DIFFICULTY_NAMES[difficulty+1],126,DIM_WHITE)
end
