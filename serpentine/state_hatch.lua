-- state_hatch.lua
-- HATCH state: a laid egg still out when the level is cleared hatches into
-- a 2-segment snake that walks home and joins the player pen -- the $1AF1
-- path, taken from $1AE5 while DEATHFLG $99 = 0 (an egg is out, $8528/$8697).
--   $1AF1-$1B01  consume warble x5 (SFX.CONSUME = 5, DELAY $78 each)
--   $1B03-$1B42  the snake is built on the egg: head and body both there,
--                heading right (codes 5/1), 2 segments; S.85AE erases the egg
--   $1B44-$1B7F  it first steps down onto a decision row, then right onto a
--                cell column
--   $1B82-$1C29  then steers down and right to the pen's outside cell,
--                (BF,B3) on the bottom row, one 2 px step per DELAY
--                JINGLE.SEL (from $78, -1 every 6 steps)
--   $1C2C-$1C63  the pen's left-wall door parts over five notes (+1)
--   $1C66-$1C7A  14 steps right, through it to the entry spot (DB,B3)
--   $1C7C        S.8C92: queue behind the snakes already there, or out
--                through the bottom door if the pen is full (snake_pen.lua)
--   $1C7F-$1CB3  the side door shuts over five notes; PHEADCPYY = 0 ($1CB8)
--                and the maze changes (BUILDMAZE $1CBA)

hatch={}

local function has(t,d)
 for _,v in ipairs(t) do if v==d then return true end end
 return false
end

-- the cell just outside the pen's left-wall door
local function target_cell() return PLAYER_DOOR3.cx-1,PLAYER_DOOR3.cy end

-- the steering rule at a decision point ($1B93-$1C08): a single exit is
-- taken; otherwise down ($1BD7), right while left of the target ($1BDF-$1BEC),
-- then left, right, up ($1BEE-$1C04), else carry on
local function steer(b)
 local ex=open_exits(b)
 local d=nil
 if #ex==1 then
  d=ex[1]
 else
  local tcx=target_cell()
  if has(ex,2) then d=2
  elseif b.cx<tcx and has(ex,1) then d=1
  elseif has(ex,3) then d=3
  elseif has(ex,1) then d=1
  elseif has(ex,0) then d=0 end
 end
 b.dir=d or b.dir
 b.next_dir=b.dir
end

local function set_phase(p)
 hatch.phase=p
 hatch.t=0
 hatch.n=0
end

function hatch_enter()
 local egg=player_egg
 local cx,cy=get_cell(egg.x,egg.y)
 -- $1B0B-$1B42: both segments on the egg, heading right
 hatch.baby={
  x=egg.x,y=egg.y,cx=cx,cy=cy,
  dir=1,next_dir=1,
  trail={},
  length=2,
  body={},
  color=BLUE,
  stack=0, -- empty trail FIFO: the body starts on the head (snake.lua)
 }
 calc_segments(hatch.baby)
 -- S.85AE $1B3C: the egg is gone, the snake stands in its place
 player_egg.active=false
 player_egg.dropped=false
 hatch.js=HATCH_JS_START -- JINGLE.SEL $88 = $78 ($1B03)
 hatch.js_cnt=8 -- Z.0F = 8 ($1B07)
 hatch.total=0
 hatch.aligned=false
 set_phase("warble")
 snd("crunch") -- the consume warble, SFX.CONSUME = 5 ($1AF1)
 game_state="HATCH"
 game_update=hatch_update
 game_draw=hatch_draw
 if gohome_instant then
  hatch.baby=nil
  snake_pen_admit(player_lives)
  set_phase("queue")
 end
end

-- one step of the walk to the pen ($1B44-$1C29)
local function walk_step()
 local b=hatch.baby
 local dist=STEP_PX
 local tcx,tcy=target_cell()
 while dist>0 do
  local cxp,cyp=get_center(b.cx,b.cy)
  if not hatch.aligned then
   -- once, from the egg: onto a decision row, then onto a cell column
   -- ($1B44-$1B7F); after that it only steers at cell centres ($1B82)
   if b.y~=cyp then
    b.dir=2
   elseif b.x~=cxp then
    b.dir=1
   else
    hatch.aligned=true
   end
  end
  if hatch.aligned and b.x==cxp and b.y==cyp then
   if b.cx==tcx and b.cy==tcy then -- (BF,B3): at the pen ($1B82-$1B90)
    set_phase("door")
    break
   end
   steer(b)
  end
  dist=glide(b,dist)
 end
 hatch.js_cnt=hatch.js_cnt-1 -- DEC Z.0F / DEC JINGLE.SEL ($1C1F-$1C27)
 if hatch.js_cnt==0 then
  hatch.js=math.max(hatch.js-1,1)
  hatch.js_cnt=6
 end
end

function hatch_update()
 hatch.t=hatch.t+1/30
 hatch.total=hatch.total+1/30
 local b=hatch.baby
 local p=hatch.phase
 local note=SNAKE_PEN_STEP_SECS -- one S.95C5 note delay, ~50 ms

 if p=="warble" then
  if hatch.t>=5*orig_delay_secs(0x78) then set_phase("walk") end

 elseif p=="walk" then
  local step=orig_delay_secs(hatch.js,HATCH_STEP_CYCLES)
  while hatch.phase=="walk" and hatch.t>=step do
   hatch.t=hatch.t-step
   walk_step()
   step=orig_delay_secs(hatch.js,HATCH_STEP_CYCLES)
  end
  if hatch.phase=="walk" and hatch.total>=GOHOME_MAX_SECS then
   -- failsafe: put the snake at the pen door
   b.cx,b.cy=target_cell()
   b.x,b.y=get_center(b.cx,b.cy)
   set_phase("door")
  end

 elseif p=="door" then -- five frames of the door, then one more note
  while hatch.t>=note and hatch.phase=="door" do
   hatch.t=hatch.t-note
   hatch.n=hatch.n+1
   PLAYER_DOOR3.open_amt=math.min(hatch.n,5)/5
   if hatch.n==6 then
    set_phase("enter")
    b.dir=1
    hatch.enter_px=(snake_pen_entry_point()-b.x)/14
   end
  end

 elseif p=="enter" then -- 14 steps right, into the pen ($1C66-$1C7A)
  while hatch.t>=note and hatch.phase=="enter" do
   hatch.t=hatch.t-note
   hatch.n=hatch.n+1
   local dist=hatch.enter_px
   while dist>0 do dist=glide(b,dist) end
   if hatch.n==14 then
    -- the pen takes over from here (S.8C92 $8C92): it draws the snake
    hatch.baby=nil
    snake_pen_admit(player_lives)
    set_phase("queue")
   end
  end

 elseif p=="queue" then
  snake_pen_update()
  if not snake_pen_busy() then set_phase("close") end

 elseif p=="close" then -- the side door shuts over five notes ($1C7F-$1CB3)
  while hatch.t>=note and hatch.phase=="close" do
   hatch.t=hatch.t-note
   hatch.n=hatch.n+1
   PLAYER_DOOR3.open_amt=(5-hatch.n)/5
   if hatch.n==5 or gohome_instant then
    PLAYER_DOOR3.open_amt=0
    hatch.phase="done"
    level_done() -- the harder modes' level bonus, then the maze (state_bonus.lua)
    return
   end
  end
 end
 if hatch.baby then calc_segments(hatch.baby) end
end

function hatch_draw()
 play_draw()
 if hatch.baby then draw_snake(hatch.baby) end
 draw_status() -- back on top of the snakes (state_play.lua)
end
