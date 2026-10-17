-- state_wipe.lua
-- WIPE state: the original's maze change, BUILDMAZE $1CBA. It runs after the
-- player pen fills at game start ($887C JMP COLDSTART -> $081F), after the
-- death shuffle ($1AEE) and after a level clear ($1CB8 falling into $1CBA).
--   MAZEBUILD $A09F  builds the next maze on hidden HGR page 2
--   S.1CC0   $1CC0  copies the player pen (rows $91-$BD) from page 1 into it,
--                   so the queued snakes carry over
--   SCRNWIPE $1D3C  clears page 1 top to bottom, one HGR row per DELAY $30,
--                   skipping both pens: rows $10-$8D bytes 1-$26, rows
--                   $8E-$AD bytes 4-$23 (clear of the enemy pen and the
--                   player's chute), rows $AE-$BD bytes 4-$1D (clear of the
--                   player pen floor too)
--   $1DB5-$1DBC     two DELAY $FF
--   $1E02-$1F53     reveals page 2 left to right, one pixel column at a time
--                   (bit mask Z.F8 grows $81,$83,..., DELAY $07 per column)
--   $1F56           then round init (JMP L.0822)
-- The old maze's frog, eggs and snakes go with it (FROGERASE $19EA/$9E1C,
-- EGGERASE $8E21/$9CB0). A dropped player egg stays up and survives.

wipe={t=0,phase="clear"}

-- call fn(x,y,w,h) for each band of the maze SCRNWIPE clears, down to row y_to
function wipe_bands(y_to,fn)
 local top=OFFSET_Y+2 -- below the top border
 local bot=OFFSET_Y+MAZE_ROWS*CELL_H -- the bottom border row stays
 local xl=OFFSET_X+2 -- inside the left border stroke
 local xr=OFFSET_X+MAZE_COLUMNS*CELL_W-1 -- inside the right border stroke
 local pen_top=OFFSET_Y+(ENEMY_DOOR2.cy-1)*CELL_H -- outer-door row ($8E)
 local floor_top=OFFSET_Y+(MAZE_ROWS-1)*CELL_H -- player pen floor ($AE)
 local enemy_x=OFFSET_X+ENEMY_DOOR2.cx*CELL_W+2 -- right of the enemy pen wall
 local chute_x=OFFSET_X+(PLAYER_DOOR2.cx-1)*CELL_W-1 -- left of the player chute wall
 local floor_x=OFFSET_X+(PLAYER_DOOR1.cx-1)*CELL_W-1 -- left of the pen floor wall
 local function band(y0,y1,x0,x1)
  y1=math.min(y1,y_to)
  if y1>y0 then fn(x0,y0,x1-x0,y1-y0) end
 end
 band(top,pen_top,xl,xr)
 band(pen_top,floor_top,enemy_x,chute_x)
 band(floor_top,bot,enemy_x,floor_x)
end

-- paint black over the part of the maze SCRNWIPE clears, down to row y_to
function wipe_mask(y_to)
 wipe_bands(y_to,function(x,y,w,h) rect(x,y,w,h,BLACK) end)
end

-- start the change: old = the cell table on screen now (nil = a blank maze,
-- just the outline and pens); the live `grid` already holds the next maze
function wipe_enter(old,on_done)
 wipe.old=old
 wipe.t=0
 wipe.phase=old and "clear" or "pause" -- nothing to clear on a blank maze
 wipe.on_done=on_done
 level_hidden=true -- the LEVEL panel goes with the old maze (state_play.lua level_banner)
 game_state="WIPE"
 game_update=wipe_update
 game_draw=wipe_draw
 if wipe_instant then wipe.phase="done" end
end

function wipe_update()
 -- fire skips any wipe outside the demo, straight to the round start
 if fire_pressed and not attract then
  round_skip_start(wipe.on_done)
  return
 end
 wipe.t=wipe.t+1/30
 local p=wipe.phase
 if p=="clear" and wipe.t>=WIPE_CLEAR_SECS then
  wipe.phase,wipe.t="pause",0
 elseif p=="pause" and wipe.t>=WIPE_PAUSE_SECS then
  wipe.phase,wipe.t="reveal",0
 elseif p=="reveal" and wipe.t>=WIPE_REVEAL_SECS then
  wipe.phase="done"
 end
 if wipe.phase=="done" then
  maze_blank=false
  wipe.on_done()
 end
end

-- the player drawn only where the original's page copy keeps it: at the
-- launch spot, inside the pen (S.1CC0). On the old maze too, so no
-- snake out in the maze is ever wiped away
local function player_in_pen()
 return not player.dead and not player.hidden
  and player.cx==PLAYER_DOOR2.cx and player.cy>=PLAYER_DOOR2.cy
end

function wipe_draw()
 cls(BLACK)
 local bot=OFFSET_Y+MAZE_ROWS*CELL_H
 local y_to,rx=0,0
 if wipe.phase=="clear" then
  y_to=OFFSET_Y+(bot-OFFSET_Y)*wipe.t/WIPE_CLEAR_SECS
 else
  y_to=240
 end
 if wipe.phase=="reveal" then rx=math.floor(240*wipe.t/WIPE_REVEAL_SECS) end

 -- right of the reveal line: page 1, the old maze being cleared
 clip(rx,0,240-rx,136)
 if demo_board then
  -- a game started from the demo clears the frozen demo board (state_demo.lua)
  draw_demo_board(rx)
  clip(rx,0,240-rx,136)
 else
  draw_grid(wipe.old or grid)
 end
 if player_in_pen() then draw_snake(player) end
 wipe_mask(y_to)
 clip()

 -- left of it: page 2, the next maze with the pen copied in
 if rx>0 then
  clip(0,0,rx,136)
  rect(0,0,rx,136,BLACK)
  draw_grid()
  if player_in_pen() then draw_snake(player) end
  clip()
 end

 draw_player_reserves()
 draw_status() -- state_play.lua
 -- a dropped player egg rides out the change on top
 if player_egg and player_egg.active and player_egg.dropped then
  spr(SPRITE_EGG_PLAYER,player_egg.x-3,player_egg.y-3,BLACK) -- as egg.lua draws it
 end
end
