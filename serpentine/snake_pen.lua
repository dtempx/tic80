-- snake_pen.lua
-- the player's reserve pen, after the original's queue walks. Every reserve
-- snake is drawn with two segments whatever its length (each walk routine
-- sets DRAWLEN $E7 and the length $641F to 2), walks one fixed route in
-- ~50 ms steps, and faces the way it last moved (S.0E5F $0E5F re-derives each
-- segment's shape direction from its own step, $0EB1-$0ED4).
--
-- The route, in the original's 2-px steps (each routine's start record is
-- the D.xxxx table it copies into the player record $6400):
--   S.8C15 $8C15  off screen (D3,C1) up 7 ($8C35), right 4 ($8C4B) -> entry
--   S.8BDA $8BDA  entry (DB,B3) right 11 ($8BEB)                    -> slot 2
--   S.8B89 $8B89  slot 2 (F1,B3) right 7 ($8B9A), up 7 ($8BB3)      -> slot 1
--   S.8B3F $8B3F  slot 1 (FF,A5) up 10 ($8B5F)       -> launch (FF,91), which
--                 is where round init stacks the rest of the body ($8676)
-- The body trails the head by one segment along that path (the trail FIFO's
-- 4-step lag, $0E88-$0EA3). S.8C15 starts with an empty FIFO (D.8C8A), so a
-- snake enters with its body stacked under its head.

SNAKE_PEN_ENTRY=11  -- route step where S.8C15 ends
SNAKE_PEN_SLOT2=22  -- S.8BDA ends
SNAKE_PEN_SLOT1=36  -- S.8B89 ends
SNAKE_PEN_LAUNCH=46 -- S.8B3F ends

-- route legs: steps, port direction (0 up, 1 right)
-- ($8C35, $8C4B, $8BEB, $8B9A, $8BB3, $8B5F: the step counts in the walk routines above)
local LEGS={{7,0},{4,1},{11,1},{7,1},{7,0},{10,0}}

-- snakes: reserves as {s=route step}; ops: queued walk/door/digit steps; t: step clock
snake_pen={snakes={},ops={},t=0}

-- route_point: the point and facing d px along the route.
-- route_dist: px of path covered by the first s steps.
-- Each leg keeps the original's step count; its px per step (snake_pen.step[i],
-- set in snake_pen_reset) makes the route's corners and stops land on the port's
-- pen cells. The direction returned is the leg the point was reached by, so
-- a snake standing on a corner still faces the way it came.
local function route_point(d)
 local x,y,dir=snake_pen.x0,snake_pen.y0,LEGS[1][2]
 for i,leg in ipairs(LEGS) do
  if d<=1e-6 then break end
  local run=math.min(d,leg[1]*snake_pen.step[i])
  dir=leg[2]
  if leg[2]==0 then y=y-run else x=x+run end
  d=d-run
 end
 return x,y,dir
end

-- px of route covered after s steps (see route_point)
local function route_dist(s)
 local d=0
 for i,leg in ipairs(LEGS) do
  local n=math.min(s,leg[1])
  d=d+n*snake_pen.step[i]
  s=s-n
  if s<=0 then break end
 end
 return d
end

-- empty pen; geometry from the live cell constants
function snake_pen_reset()
 local dx,by=get_center(PLAYER_DOOR1.cx,MAZE_ROWS) -- door column, pen floor
 local lx,ly=get_center(PLAYER_DOOR2.cx,PLAYER_DOOR2.cy) -- launch spot
 local hs=(lx-dx)/22 -- px per horizontal step (entry leg 4 + 11 + 7)
 local vs=(by-ly)/17 -- px per vertical step, entry leg (S.8C15's 7 up)
 -- slot 1 sits two segments plus SNAKE_PEN_GAP under the launch spot, so its head
 -- clears the launch snake's stacked body; its own body stays above the
 -- floor corner, so it still faces up the chute as in the original
 local y1=ly+2*SEGMENT_DIST+SNAKE_PEN_GAP
 snake_pen.step={vs,hs,hs,hs,(by-y1)/7,(y1-ly)/10}
 snake_pen.hs=hs
 snake_pen.x0,snake_pen.y0=dx,by+7*vs -- S.8C15's start, under the door
 -- lives digit between the entry spot and slot 2, where DRAWLIVES $9F2F
 -- repaints it (byte column 32, the bottom-row band)
 snake_pen.digit_x=dx+6.5*snake_pen.hs
 snake_pen.snakes={}
 snake_pen.ops={}
 snake_pen.t=0
 -- no digit until the first DRAWLIVES of the fill ($8B71 etc.); the door
 -- opening (S.887F) draws none
 snake_pen.digit=false
 PLAYER_DOOR1.open_amt=0
end

-- true while queued pen steps remain
function snake_pen_busy() return #snake_pen.ops>0 end

-- queue one pen op (sequencer; the original calls its walk routines in turn)
local function push(op) table.insert(snake_pen.ops,op) end

-- S.887F $887F: the entry door parts over three steps (frames $0A54, $0250,
-- $0040 at HGR $3BEF/$3FEF); S.88B9 $88B9 closes it the same way
local function door(open)
 local amts=open and {1/3,2/3,1} or {2/3,1/3,0}
 for _,a in ipairs(amts) do push({op="door",amt=a}) end
end

-- a new snake comes in under the door (S.8C15) and walks on to step `to`
local function enter(to)
 local p={s=0}
 push({op="add",snake=p})
 push({op="walk",snake=p,to=to})
end

-- game start ($8829-$8857): open the door, walk in the active snake to the
-- launch spot and up to two reserves to slots 1 and 2, raising the lives
-- digit as each one enters (LIVES $D8 = 1, 2, 3 stored at $8832/$8842/$884F),
-- then close the door. More lives than three stay off screen. The digit keeps
-- the last count until the release tick (snake_pen_hold_digit).
function snake_pen_fill(lives)
 snake_pen_reset()
 door(true)
 local targets={SNAKE_PEN_LAUNCH,SNAKE_PEN_SLOT1,SNAKE_PEN_SLOT2}
 for i=1,math.min(lives,3) do
  push({op="digit",n=i})
  enter(targets[i])
 end
 door(false)
end

-- the lives digit as the original draws it. LIVES $D8 counts the snake at
-- the launch spot until round init's DEC LIVES ($868F), which is not drawn:
-- the next DRAWLIVES is PENDOOR's ($8AC8), when the release clock opens the
-- chute cell at $60, the tick the player and the first enemy go out. Until
-- then the digit holds the whole count, the port's player_lives, which counts
-- the active snake; the clear sequence's INC LIVES + DRAWLIVES ($9EF6) holds it
-- the same way. snake_pen_release_digit hands it back to the reserves count.
function snake_pen_hold_digit() snake_pen.digit=player_lives end
function snake_pen_release_digit() snake_pen.digit=nil end

-- after a death ($1AC3-$1AE2), with lives = snakes left incl. the next one:
-- slot 1 walks up to the launch spot (S.8B3F), then slot 2 moves up to slot 1
-- (S.8B89); a third snake, if there is one, comes in through the door and
-- takes slot 2 (S.887F, S.8C15, S.8BDA, S.88B9). Each waits for the last.
-- The original assumes slots 1 and 2 are full whenever lives allow; here each
-- queued snake simply moves up to the next free place, front first, which is
-- the same sequence in that case and closes any gap otherwise.
function snake_pen_shuffle(lives)
 local targets={SNAKE_PEN_LAUNCH,SNAKE_PEN_SLOT1,SNAKE_PEN_SLOT2}
 local q={}
 for _,p in ipairs(snake_pen.snakes) do table.insert(q,p) end
 table.sort(q,function(a,b) return a.s>b.s end)
 local n=0
 for _,p in ipairs(q) do
  if n<math.min(lives,3) then
   n=n+1
   if p.s<targets[n] then push({op="walk",snake=p,to=targets[n]}) end
  end
 end
 if n<math.min(lives,3) then
  door(true)
  for k=n+1,math.min(lives,3) do enter(targets[k]) end
  door(false)
 end
end

-- a snake standing at the entry spot (the hatched snake, state_hatch.lua)
-- joins the queue (S.8C92 $8C92, with lives = LIVES $D8 counting the active
-- snake, as after CLEARSEQ's INC $9EF6): with three or more it walks back out
-- through the bottom door and waits off screen (S.887F, 3 steps left and 10
-- down at $8CA1-$8CCD, S.88B9); with two it stops in slot 2 (S.8BDA), with
-- one it goes on to slot 1 (S.8B89), with none up to the launch spot
-- (S.8B3F). Either way it is an extra life: LIVES +1 as it heads out for the
-- off-screen queue ($8C98), or once it has walked into its slot ($8CEA).
function snake_pen_admit(lives)
 local p={s=SNAKE_PEN_ENTRY}
 push({op="add",snake=p})
 if lives>=3 then
  push({op="life"})
  door(true)
  -- back along the entry route (11 steps) for the original's 3+10
  push({op="walk",snake=p,to=0})
  push({op="remove",snake=p})
  door(false)
 else
  local to=(lives==2) and SNAKE_PEN_SLOT2 or (lives==1) and SNAKE_PEN_SLOT1
   or SNAKE_PEN_LAUNCH
  push({op="walk",snake=p,to=to})
  push({op="life"})
 end
end

-- the route point of the pen's entry spot (where S.8C15 stops, (DB,B3))
function snake_pen_entry_point()
 return route_point(route_dist(SNAKE_PEN_ENTRY))
end

-- the snake at the launch spot becomes the live player (init_player stacks
-- its body there, $8676); drop the pen's copy. This is round init, whose
-- DEC LIVES the digit does not show yet (snake_pen_hold_digit)
function snake_pen_launch()
 for i=#snake_pen.snakes,1,-1 do
  if snake_pen.snakes[i].s==SNAKE_PEN_LAUNCH then table.remove(snake_pen.snakes,i) end
 end
 snake_pen_hold_digit()
end

-- test harnesses: place reserves instantly (slot 1, then slot 2)
function snake_pen_set(reserves)
 snake_pen_reset()
 if reserves>=1 then table.insert(snake_pen.snakes,{s=SNAKE_PEN_SLOT1}) end
 if reserves>=2 then table.insert(snake_pen.snakes,{s=SNAKE_PEN_SLOT2}) end
 snake_pen.digit=nil
end

-- one op per step; a step is one original note delay (NOTE.SILENT $9612:
-- 21 x NOTEDELAY $9698 at Y=$F0, ~50 ms) called through S.95C2/S.95C5
local function run_op()
 local op=snake_pen.ops[1]
 if op.op=="door" then
  PLAYER_DOOR1.open_amt=op.amt
  table.remove(snake_pen.ops,1)
 elseif op.op=="walk" then
  local p=op.snake
  p.back=op.to<p.s -- walking the route backwards (the exit, S.8C92)
  if p.s<op.to then p.s=p.s+1 elseif p.s>op.to then p.s=p.s-1 end
  if p.s==op.to then table.remove(snake_pen.ops,1) end
 end
end

-- run due pen ops: bookkeeping at once, walk/door ops one per SNAKE_PEN_STEP_SECS
function snake_pen_update()
 snake_pen.t=snake_pen.t+1/30
 while #snake_pen.ops>0 do
  local op=snake_pen.ops[1]
  -- instant ops (bookkeeping) never cost a step
  if op.op=="add" then
   table.insert(snake_pen.snakes,op.snake)
   table.remove(snake_pen.ops,1)
  elseif op.op=="digit" then
   snake_pen.digit=op.n
   table.remove(snake_pen.ops,1)
  elseif op.op=="life" then
   player_lives=player_lives+1 -- INC LIVES ($8C98/$8CEA); the digit follows
   -- (DRAWLIVES $8CAF/$8CC8/$8CEC), held or not
   if snake_pen.digit then snake_pen_hold_digit() end
   table.remove(snake_pen.ops,1)
  elseif op.op=="remove" then
   for i=#snake_pen.snakes,1,-1 do
    if snake_pen.snakes[i]==op.snake then table.remove(snake_pen.snakes,i) end
   end
   table.remove(snake_pen.ops,1)
  elseif snake_pen_instant then
   run_op()
  elseif snake_pen.t>=SNAKE_PEN_STEP_SECS then
   snake_pen.t=snake_pen.t-SNAKE_PEN_STEP_SECS
   run_op()
  else
   break
  end
 end
 if #snake_pen.ops==0 then snake_pen.t=0 end
end

-- two segments per snake, clipped at the pen floor so a snake below the door
-- is off screen; lives digit last, on top, as DRAWLIVES overwrites the bytes
-- (a held digit counts the active snake too, snake_pen_hold_digit)
function draw_player_reserves()
 clip(0,0,240,OFFSET_Y+MAZE_ROWS*CELL_H)
 pal(ORANGE,BLUE)
 for _,p in ipairs(snake_pen.snakes) do
  local d=route_dist(p.s)
  local hx,hy,hd=route_point(d)
  local bx,by,bd
  if p.back then
   -- heading back down the route: the body trails on the far side, and both
   -- face the way they now move
   bx,by,bd=route_point(math.min(d+SEGMENT_DIST,route_dist(SNAKE_PEN_LAUNCH)))
   hd,bd=inv_dir(hd),inv_dir(bd)
  else
   bx,by,bd=route_point(math.max(0,d-SEGMENT_DIST))
  end
  spr(SPRITE_BODY+bd,math.floor(bx+0.5)-3,math.floor(by+0.5)-3,BLACK)
  spr(SPRITE_HEAD+hd,math.floor(hx+0.5)-3,math.floor(hy+0.5)-3,BLACK)
 end
 pal(ORANGE,ORANGE)
 clip()
 if snake_pen.digit==false then return end
 local n=snake_pen.digit or math.max(0,player_lives-(player.dead and 0 or 1))
 local _,ly=get_center(PLAYER_DOOR1.cx,MAZE_ROWS)
 -- right-align: digit_x is the left edge of a single digit, so a wider
 -- (e.g. two-digit) count is shifted left to keep its right edge fixed
 local x0=math.floor(snake_pen.digit_x)+SNAKE_PEN_DIGIT_DX
 local w1=print("0",0,-20,BLUE,true,1,true)
 local w=print(n,0,-20,BLUE,true,1,true)
 print(n,x0+w1-w,ly-2,BLUE,true,1,true)
end
