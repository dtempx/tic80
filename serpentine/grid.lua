-- grid.lua
-- maze wall bits decoded from the map (20 mazes in 14x12 bays, 10 per row,
-- one blank tile column and row between bays)

grid={} -- wall bits per cell; the original's working buffer is MAZECELLS $A3F1+(row<<4|col)
current_level=1 -- maze slot 1..20 = LEVEL $BE mod 20 ($A39E-$A3A5)

-- map tiles 0-3 draw the walls on their own left/top edge, so a bay in the map
-- editor is the maze outline: 0 open, 1 left, 2 top, 3 both
-- does a legend tile have a left wall? (original cell nibble bit 0 = left open, $A127)
local function has_left(c) return c==1 or c==3 end
-- legend tile has a top wall (original nibble bit 3 = top open, $A288)
local function has_top(c) return c==2 or c==3 end

-- decode maze `lvl` from its <MAP> bay into grid[] wall bits (MAZELOAD $A39C, table MAZEPTRTBL $A3DD)
function load_maze(lvl)
 local slot=(lvl-1)%MAZE_COUNT
 local mx=slot%MAZES_PER_ROW*MAZE_PITCH_X
 local my=slot//MAZES_PER_ROW*MAZE_PITCH_Y
 -- one-way secret passages (ONE_WAY_UP): the map shows a top wall there
 local one_way={}
 for _,c in ipairs(ONE_WAY_UP[slot+1] or {}) do one_way[c[2]*16+c[1]]=true end

 grid={}
 for y=1,MAZE_ROWS do
  grid[y]={}
  for x=1,MAZE_COLUMNS do
   local cell=mget(mx+x-1,my+y-1)
   local right=mget(mx+x,my+y-1)
   local below=mget(mx+x-1,my+y)
   local up_one_way=one_way[y*16+x]
   local down_one_way=one_way[(y+1)*16+x]
   local v=0
   -- one-way secret passages: passable up, solid coming down
   if up_one_way then v=v+16
   elseif has_top(cell) then v=v+1 end    -- wall up
   if has_left(right) then v=v+2 end      -- wall right
   if down_one_way then v=v+64
   elseif has_top(below) then v=v+4 end   -- wall down
   if has_left(cell) then v=v+8 end       -- wall left
   grid[y][x]=v
  end
 end
end

-- load the maze for current_level (the builder's JSR to MAZELOAD, MAZEBUILD $A09F)
function init_grid()
 load_maze(current_level)
end

-- Collect visible edge directions so cap tips can be drawn last, without
-- neighbouring wall segments erasing the one-pixel point at a corner.
local wall_nodes={}
-- record that a wall arm leaves point (x,y) in direction bit `dir` (draw helper)
local function wall_node(x,y,dir)
 local key=x..","..y
 local node=wall_nodes[key]
 if node then node.dirs=node.dirs|dir
 else wall_nodes[key]={x=x,y=y,dirs=dir} end
end

-- draw one wall edge with white studs at both ends (builder passes $A127/$A1EF, corner dots)
function wall_seg(x1,y1,x2,y2)
 -- HGR walls are wider vertically: three pixels across, two scanlines high.
 -- White studs repeat at every cell boundary, including straight wall runs.
 if x1==x2 then
  wall_node(x1,y1,4)
  wall_node(x2,y2,1)
  rect(x1-1,y1,3,y2-y1+1,WALL_COLOR)
  rect(x1-1,y1,3,1,WHITE)
  rect(x2-1,y2,3,1,WHITE)
 else
  wall_node(x1,y1,2)
  wall_node(x2,y2,8)
  rect(x1,y1, x2-x1+1,2,WALL_COLOR)
  rect(x1,y1,2,2,WHITE)
  rect(x2-1,y2,2,2,WHITE)
 end
end

-- pen door: a horizontal wall that parts from the center as it opens
-- (door object; the original blits door keyframes, $8A81/$8A94/$8AA7/$8AD6)
function door_seg(px,py,d)
 wall_node(px,py,2)
 wall_node(px+CELL_W,py,8)
 local center=px+CELL_W/2
 local gap=(CELL_W/2)*d.open_amt
 rect(px,py,math.max(0,math.floor(center-gap)-px+1),2,WALL_COLOR)
 if center+gap<px+CELL_W then
  local right=math.ceil(center+gap)
  rect(right,py,px+CELL_W-right+1,2,WALL_COLOR)
 end
 rect(px,py,2,2,WHITE)
 rect(px+CELL_W-1,py,2,2,WHITE)
end

-- paint the whole maze each frame: walls, doors, then corner caps (MAZEBUILD $A09F)
-- g: the cell table to draw (default the live grid; the wipe draws the old one)
function draw_grid(g)
 g=g or grid
 wall_nodes={}
 for y=1,MAZE_ROWS do
  for x=1,MAZE_COLUMNS do
   local v=g[y][x]
   local px=OFFSET_X+(x-1)*CELL_W
   local py=OFFSET_Y+(y-1)*CELL_H

   -- top edge; one-way passages (bit 16) draw as a normal wall
   local top_door=get_door(x,y)
   if top_door then
    door_seg(px,py,top_door)
   elseif (v&1)~=0 or (v&16)~=0 then
    wall_seg(px,py,px+CELL_W,py)
   end

   -- left edge; the pen's side door parts from the middle (door.lua PLAYER_DOOR3)
   if (v&8)~=0 then
    local sd=PLAYER_DOOR3
    if x==sd.cx and y==sd.cy and sd.open_amt>0 then
     local mid=py+CELL_H/2
     local gap=CELL_H*10/16*sd.open_amt/2 -- the original's door is 10 of 16 rows
     wall_seg(px,py,px,math.floor(mid-gap))
     wall_seg(px,math.ceil(mid+gap),px,py+CELL_H)
    else
     wall_seg(px,py,px,py+CELL_H)
    end
   end

   -- bottom border (final row only; other rows share the edge below)
   if y==MAZE_ROWS then
    local bottom_door=get_door(x,y+1)
    if bottom_door then
     door_seg(px,py+CELL_H,bottom_door)
    elseif (v&4)~=0 then
     wall_seg(px,py+CELL_H,px+CELL_W,py+CELL_H)
    end
   end

   -- right border (final column only)
   if x==MAZE_COLUMNS and (v&2)~=0 then
    wall_seg(px+CELL_W,py,px+CELL_W,py+CELL_H)
   end
  end
 end
 draw_wall_caps()
end

-- corner stubs and tips for every node wall_seg recorded ($A288/$A342 corner-stub logic)
function draw_wall_caps()
 for _,n in pairs(wall_nodes) do
  local x,y,d=n.x,n.y,n.dirs
  if d==4 then pix(x,y-1,WHITE)
  elseif d==1 then pix(x,y+1,WHITE)
  elseif d==2 then pix(x-1,y,WHITE)
  elseif d==8 then pix(x+1,y,WHITE)
  elseif d==6 or d==9 or d==3 or d==12 then
   -- L corner: a white mitre from the outer to the inner corner over
   -- the 3x2 corner block, replacing the two arms' end studs
   rect(x-1,y,3,2,WALL_COLOR)
   if d==6 or d==9 then -- right+down / left+up: "\"
    rect(x-1,y,2,1,WHITE)
    rect(x,y+1,2,1,WHITE)
   else -- left+down / right+up: "/"
    rect(x,y,2,1,WHITE)
    rect(x-1,y+1,2,1,WHITE)
   end
  elseif (d&5)~=0 and (d&10)~=0 then
   rect(x-1,y,3,2,WHITE)
   pix(x,y-1,WHITE)
  end
 end
 -- lattice points no wall reaches still get a stud (keeps the dot grid)
 for y=0,MAZE_ROWS do
  for x=0,MAZE_COLUMNS do
   local px=OFFSET_X+x*CELL_W
   local py=OFFSET_Y+y*CELL_H
   if not wall_nodes[px..","..py] then rect(px-1,py,3,2,WHITE) end
  end
 end
end

-- studded wall rectangle w x h from (x0,y0) in the maze's wall style (2 px
-- rows, 3 px columns), studs every `spacing` px along one counter-clockwise
-- path from the top-right corner (left along the top, down the left, right
-- along the bottom, up the right), shifted `phase` px along it -- advancing
-- phase marches them like ants (the original title frame is static)
function draw_frame(x0,y0,w,h,spacing,phase)
 local x1,y1=x0+w,y0+h
 rect(x0-1,y0,w+3,2,WALL_COLOR)
 rect(x0-1,y1,w+3,2,WALL_COLOR)
 rect(x0-1,y0,3,h+2,WALL_COLOR)
 rect(x1-1,y0,3,h+2,WALL_COLOR)
 local s=phase//1%spacing
 while s<2*(w+h) do
  local px,py
  if s<w then px,py=x1-s,y0
  elseif s<w+h then px,py=x0,y0+s-w
  elseif s<2*w+h then px,py=x0+s-w-h,y1
  else px,py=x1,y1-(s-2*w-h) end
  rect(px-1,py,3,2,WHITE)
  s=s+spacing
 end
end
