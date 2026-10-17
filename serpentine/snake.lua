-- snake.lua
-- shared snake physics (cell-center movement, trail-replay segments) and the
-- procedural snake renderer. positions AND movement distances are px, so
-- on-screen speed is uniform in both axes despite the rectangular cells
-- (cell traversal time is therefore axis-dependent).
--
-- A snake table stands for one of the original's 128-byte entity records
-- (player $6400, enemies $6480/$6500/$6580, layout disasm README 2.3):
--   x,y        head px                   +0,+1
--   dir        0 up/1 right/2 down/3 left +2 (orig 0 left,1 right,2 up,3 down)
--   body[]     segment {x,y,dir}         +3..+$17 triples
--   length     segments incl. head       +$1F; alive while >=2, max 7 ($09F7)
--   trail[]    past step directions      step FIFO +$20..+$57 (S.0E5F $0E5F)
--   cx,cy      cell under the head       cell index (row<<4|col) into $A3F1
--   next_dir   buffered turn             TURNDIR $EB / AICHOSEN $AD ($1914)
--   moving     false = stopped at a wall ($0E26-$0E3E skips the head advance)
--   stack      pen-spawn unfurl budget   zeroed FIFO at launch ($0868)
--   color      draw colour               hi-bit mask $E9 (SETPALETTE $10D7)
--   dead, dead_timer                     length<2; shrink countdown ESHRINK $A4-$A6
--   grow_timer tail pop-in animation (original has none)

-- cell (cx,cy) center in px; a cell's decision point is head y&$0F==3 ($17AF/$194E)
function get_center(cx,cy)
 return OFFSET_X+(cx-1)*CELL_W+CELL_W/2, OFFSET_Y+(cy-1)*CELL_H+CELL_H/2
end

-- px position to cell (cx,cy); original maps x through column table $6600 and y&$F0 ($195D-$1964)
function get_cell(px,py)
 return math.floor((px-OFFSET_X)/CELL_W)+1, math.floor((py-OFFSET_Y)/CELL_H)+1
end

-- elliptical cell-normalized collision (B: dx^2+dy^2<25 on square 9.5px cells)
-- the original tests same row, then an x window (PROXCHECK $1718, HEADCOMBAT $14E1)
function hit(ax,ay,bx,by)
 local dx,dy=(ax-bx)/CELL_W,(ay-by)/CELL_H
 return dx*dx+dy*dy < HIT_CELLS*HIT_CELLS
end

-- true once the head is on (x,y): within EAT_PX of it now, or it swept over it
-- since the last check (head_prev_x/y, set by check_collisions), so a fast
-- head can't step past a point between ticks. A jump longer than a cell
-- (respawn, pen launch) counts only the current spot.
-- tighter than hit(), which would take an egg ~half a cell early
function head_over(snake,x,y)
 local ax,ay=snake.head_prev_x or snake.x,snake.head_prev_y or snake.y
 local bx,by=snake.x,snake.y
 local sx,sy=bx-ax,by-ay
 local len2=sx*sx+sy*sy
 local t=0
 if len2>0 and len2<=CELL_W*CELL_W then
  t=math.max(0,math.min(1,((x-ax)*sx+(y-ay)*sy)/len2))
 else
  ax,ay,sx,sy=bx,by,0,0
 end
 local dx,dy=ax+sx*t-x,ay+sy*t-y
 return dx*dx+dy*dy<=EAT_PX*EAT_PX
end

-- the reverse of direction d (the original masks it out with table $1948)
function inv_dir(d)
 return (d+2)%4
end

-- point dist px from (px,py) along dir (the original steps 2 px from STEPDELTA $0E55)
function offset_by(px,py,dist,dir)
 if dir==0 then return px,py-dist end
 if dir==1 then return px+dist,py end
 if dir==2 then return px,py+dist end
 if dir==3 then return px-dist,py end
 return px,py
end

-- true if the snake's cell is open toward d; is_pathing lets a probe pass shut doors
-- (WALLCHECK $194C against the cell nibble at MAZECELLS $A3F1)
function can_move(snake,d,is_pathing)
 local tcx,tcy=snake.cx,snake.cy

 -- virtual row 12: the spawning pens beneath the maze -- exit is up-only,
 -- through an open (or pathing-probed) door
 if tcy==MAZE_ROWS+1 then
  if tcx<1 or tcx>MAZE_COLUMNS then return false end
  if d==0 then
   local door=get_door(tcx,tcy)
   if door then
    if door.state==3 then return true end
    if is_pathing then return true end
   end
  end
  return false
 end

 if tcx<1 or tcx>MAZE_COLUMNS or tcy<1 or tcy>MAZE_ROWS then return false end
 local cell_val=grid[tcy][tcx]

 -- never leak off the playfield through a gap in the boundary wall data
 -- (the pen row MAZE_ROWS+1 is a legal target; anything beyond is not)
 local ntx,nty=tcx,tcy
 if d==0 then nty=nty-1
 elseif d==1 then ntx=ntx+1
 elseif d==2 then nty=nty+1
 elseif d==3 then ntx=ntx-1 end
 if ntx<1 or ntx>MAZE_COLUMNS or nty<1 or nty>MAZE_ROWS+1 then
  return false
 end

 -- doors override the wall bits on their edge
 if d==0 then
  local door=get_door(tcx,tcy)
  if door then
   if door.state==3 then return true end
   if is_pathing then return true end
   return false
  end
 end

 if d==0 and (cell_val&1)~=0 then return false end
 if d==1 and (cell_val&2)~=0 then return false end
 if d==2 and (cell_val&4)~=0 then return false end
 if d==3 and (cell_val&8)~=0 then return false end
 -- one-way passage: downward through it is a dead wall
 if d==2 and (cell_val&64)~=0 then return false end

 return true
end

-- advance the head up to dist px; snaps to cell centers, returns leftover
-- px after a center crossing (px carry exactly across a corner even when the
-- movement axis changes), 0 if still travelling, nil if blocked
-- (head advance via STEPFETCH $1931 / STEPDELTA $0E55; blocked = no advance, $0E26-$0E3E)
function move_head(snake,dist)
 local cpx,cpy=get_center(snake.cx,snake.cy)
 if snake.x==cpx and snake.y==cpy and not can_move(snake,snake.dir) then
  if snake.dir==0 then
   local door=get_door(snake.cx,snake.cy)
   if door and door.state==0 then
    trigger_door(snake.cx,snake.cy,snake)
   end
  end
  return nil
 end

 local dx,dy=0,0
 if snake.dir==0 then dy=-1 end
 if snake.dir==1 then dx=1 end
 if snake.dir==2 then dy=1 end
 if snake.dir==3 then dx=-1 end

 local tcx,tcy=snake.cx+dx,snake.cy+dy
 local tpx,tpy=get_center(tcx,tcy)
 local step=dist
 local gap

 if dx==1 then
  if tpx<=snake.x+step then gap=tpx-snake.x snake.x=tpx end
 elseif dx==-1 then
  if tpx>=snake.x-step then gap=snake.x-tpx snake.x=tpx end
 elseif dy==1 then
  if tpy<=snake.y+step then gap=tpy-snake.y snake.y=tpy end
 else
  if tpy>=snake.y-step then gap=snake.y-tpy snake.y=tpy end
 end
 if snake.stack then snake.stack=snake.stack+(gap or step) end
 if not gap then
  snake.x,snake.y=offset_by(snake.x,snake.y,step,snake.dir)
  return 0
 end

 change_cell(snake,tcx,tcy)
 return dist-gap
end

-- a port px position in the original's px (x on the 21 px column grid, y on
-- 16 px rows, row k at y = 16k+3): the unit the AI and frog laws compare in
function orig_xy(px,py)
 return (px-OFFSET_X-CELL_W/2)/CELL_W*21+2.5,
        (py-OFFSET_Y-CELL_H/2)/CELL_H*16+19
end

-- unit step for direction d (0 up, 1 right, 2 down, 3 left)
function dir_vec(d)
 if d==0 then return 0,-1 end
 if d==1 then return 1,0 end
 if d==2 then return 0,1 end
 return -1,0
end

-- seconds of one original DELAY $AF4F call with A=a (the monitor-style wait,
-- (26+27a+5a^2)/2 cycles) plus `extra` cycles of other work
function orig_delay_secs(a,extra)
 return ((26+27*a+5*a*a)/2+(extra or 0))/APPLE_HZ
end

-- scripted walks (go-home, hatch): move up to dist px toward the next cell
-- centre along snake.dir WITHOUT a wall check -- the original's scripted
-- steps push a STEPDELTA $0E55 delta through S.0E5F and only consult the maze
-- at decision points. Returns the leftover px and whether a centre was reached.
function glide(snake,dist)
 local dx,dy=dir_vec(snake.dir)
 local ccx,ccy=get_center(snake.cx,snake.cy)
 -- the centre ahead: this cell's if short of it, else the neighbour's
 local tcx,tcy=snake.cx,snake.cy
 if (snake.x-ccx)*dx+(snake.y-ccy)*dy>=0 then tcx,tcy=snake.cx+dx,snake.cy+dy end
 local tx,ty=get_center(tcx,tcy)
 local rem=math.abs(tx-snake.x)+math.abs(ty-snake.y)
 if snake.stack then snake.stack=snake.stack+math.min(dist,rem) end
 if dist<rem then
  snake.x,snake.y=snake.x+dx*dist,snake.y+dy*dist
  return 0,false
 end
 snake.x,snake.y=tx,ty
 if tcx~=snake.cx or tcy~=snake.cy then
  table.insert(snake.trail,snake.dir)
  if #snake.trail>100 then table.remove(snake.trail,1) end
  snake.cx,snake.cy=tcx,tcy
 end
 return dist-rem,true
end

-- open exits from the snake's cell, never straight back (maze nibble
-- MAZECELLS $A3F1 AND D.1948 $1948, the reverse-direction mask); a dead end
-- allows the way back (guard: the original would keep its heading)
function open_exits(snake)
 local t={}
 for d=0,3 do
  if d~=inv_dir(snake.dir) and can_move(snake,d) then t[#t+1]=d end
 end
 if #t==0 and can_move(snake,inv_dir(snake.dir)) then t[1]=inv_dir(snake.dir) end
 return t
end

-- frog, egg or kill: one more segment, never past MAX_LEN (the original's
-- grow routines RTS at 7 without growing; player S.09F4 $09F4, enemies $0AB3/$0B5A/$0C04)
function grow_snake(snake)
 if snake.length<MAX_LEN then
  snake.length=snake.length+1
  snake.grow_timer=15
 end
end

-- head arrives on a new cell: log the step, then take the buffered turn or stop at
-- a wall (cell decision point $17AF/$194E, turn wall-checked via TURNDIR $EB at $194C)
function change_cell(snake,cx,cy)
 snake.arrived=true -- the head is on a cell centre this tick (frog.lua head_on_frog)
 table.insert(snake.trail,snake.dir)
 if #snake.trail>100 then table.remove(snake.trail,1) end

 snake.cx=cx
 snake.cy=cy

 -- a snake with a navigator decides at the centre it has just reached, as
 -- ENEMYAI $17AB does at its decision points ($17AF-$17C1); nil = no way on
 if snake.decide then snake.next_dir=snake.decide(snake) or snake.dir end

 if snake.next_dir~=snake.dir and can_move(snake,snake.next_dir) then
  snake.dir=snake.next_dir
 elseif not can_move(snake,snake.dir) then
  -- blocked: knock on a door if that is what stopped us
  if snake.dir==0 then
   local door=get_door(snake.cx,snake.cy)
   if door and door.state==0 then
    trigger_door(snake.cx,snake.cy,snake)
   end
  end
  snake.moving=false
 end
end

-- rebuild body segment positions by replaying the trail backwards from the
-- head, SEGMENT_DIST px apart (px space keeps the spacing visually uniform).
-- snake.stack (pen spawns only): the most px of path any segment may lie
-- behind the head. A spawned snake's body starts stacked on one spot a
-- segment behind the head and unfurls one segment per SEGMENT_DIST of head
-- travel, as the original's zeroed trail FIFO does ($0868: every segment
-- triple starts on the pen spot, $6404-$6413 y=$99 under the head's $91).
-- The original shifts the FIFO per step instead (S.0E5F $0E5F).
function calc_segments(snake)
 if snake.cy<=MAZE_ROWS-1 and not snake.spawned then
  snake.spawned=true
  snake.time_spawned=game_time
 end

 if snake.grow_timer and snake.grow_timer>0 then
  snake.grow_timer=snake.grow_timer-1
 end

 snake.body[1]={x=snake.x,y=snake.y,dir=snake.dir}

 local trail_idx=#snake.trail
 local c_dir=inv_dir(snake.dir)
 local cx,cy=snake.cx,snake.cy
 local px,py=snake.x,snake.y

 local stack=snake.stack
 if stack and stack>=MAX_LEN*SEGMENT_DIST then
  snake.stack=nil -- fully unfurled at any length it can reach
  stack=nil
 end
 local walked=0
 for i=2,snake.length do
  local dist=SEGMENT_DIST
  if stack then dist=math.max(0,math.min(dist,stack-walked)) end
  walked=walked+dist
  while dist>0 do
   local cell_px,cell_py=get_center(cx,cy)
   local offset=math.max(math.abs(cell_px-px),math.abs(cell_py-py))

   if offset>=dist then
    px,py=offset_by(px,py,dist,c_dir)
    dist=0
   else
    dist=dist-offset
    px,py=cell_px,cell_py
    if trail_idx>0 then
     c_dir=inv_dir(snake.trail[trail_idx])
     trail_idx=trail_idx-1
    end
    if c_dir==0 then cy=cy-1 end
    if c_dir==1 then cx=cx+1 end
    if c_dir==2 then cy=cy+1 end
    if c_dir==3 then cx=cx-1 end
   end
  end
  snake.body[i]={x=px,y=py,dir=inv_dir(c_dir)}
 end
end

-- TIC-80 has no pal(): colour remapping is a poke into the VRAM palette map.
-- All snake art is authored in ORANGE and recoloured per snake at draw time,
-- so one authored set covers player blue / enemy orange / prey green.
-- shim standing in for the original's $E9 colour OR-mask (SETPALETTE $10D7).
-- remap palette index c to d for subsequent draws (TIC-80 VRAM palette map)
function pal(c,d) poke4(0x7FE0+c,d) end

-- draw a snake: shrivel frames when dead, else tail-first body then head
-- sprite art is 7x7 in an 8x8 cell, so (x-3,y-3) puts its centre on the entity
-- (SNAKEDRAW $0FD1 over DRAWGLYPH $0FF4; mouth toggle = tongue flicker, PLAYERTICK $ABA1)
function draw_snake(snake)
 if snake.hidden then return end

 pal(ORANGE,snake.color)

 if snake.dead then
  -- death: the original's three shrivel frames, one step per 10 ticks
  if snake.dead_timer and snake.dead_timer>0 then
   local f=2-math.min((snake.dead_timer-1)//10,2)
   for i=snake.length,1,-1 do
    local s=snake.body[i]
    if s then spr(SPRITE_SHRIVEL+f,s.x-3,s.y-3,BLACK) end
   end
  end
  pal(ORANGE,ORANGE)
  return
 end

 -- a gestating egg swells the tail through the original's three bulge stages
 -- (orig codes 8-11/12-15/16-19), so the bulge is part of the body sprite
 local stage=0
 local egg=snake.gestating_egg
 if egg and egg.active and egg.gestating then
  local progress=1.0-(egg.gestation_timer/(EGG_SPAWN_DURATION*30.0))
  stage=math.min(math.floor(progress*4),3)
 end
 if snake.bulge then stage=snake.bulge end -- the player's hunger bulge (egg.lua)

 -- tail-first so the head paints over the neck
 for i=snake.length,2,-1 do
  local s=snake.body[i]
  if s then
   if i==snake.length and snake.grow_timer and snake.grow_timer>0 then
    -- fresh tail segment still popping in: no sprite small enough
    local r=SEG_R*(1-snake.grow_timer/15)
    if r>=0.5 then circ(s.x,s.y,r,snake.color) end
   else
    spr(SPRITE_BODY+(i==snake.length and stage or 0)*4+s.dir,s.x-3,s.y-3,BLACK)
   end
  end
 end

 local h=snake.body[1]
 if h then
  local base=SPRITE_HEAD
  -- fixed 4 Hz toggle; original EOR #$1C flips it every 2*length+4 moves ($ABA5-$ABC2)
  if math.floor(game_time*4)%2==0 then base=SPRITE_HEAD_OPEN end
  spr(base+h.dir,h.x-3,h.y-3,BLACK)
 end

 pal(ORANGE,ORANGE)
end
