-- state_gohome.lua
-- GOHOME state: the level clear, after the original's GOHOME $9CB0 and
-- CLEARSEQ $9E97. With every enemy dead ($093F-$0958) the enemy egg goes
-- (EGGERASE $9CB0), the clear tune plays (jingle $AF6A with JINGLE.SEL $88 =
-- 1, $9CD9-$9CDD), then the player is steered home with no input: every step
-- moves it 2 px (S.0E5F), runs the frog (FROGDRIVE $9DC8) and redraws the egg
-- (S.856A $9DCB), so a frog hopping for a laid egg races the snake home. At
-- the cell above its chute ((FF,$83), S.9E05 $9E05) the frog is taken off
-- (FROGSPAWN/FROGERASE $9E19), the chute opens ($9E22-$9E58), the snake goes
-- down into it and back up to the launch spot ($9E5B-$9E8B), its body folds
-- into the head (CLEARSEQ: (len-1)*4+1 still steps, $9E97-$9EB4) and the
-- chute shuts ($9EB6-$9EEC). Then an egg still out hatches (state_hatch.lua,
-- the $1AF1 path taken while DEATHFLG $99 = 0), else the next maze comes in.

gohome={}

-- the cell above the player's chute
local function home_cell() return PLAYER_DOOR2.cx,PLAYER_DOOR2.cy-1 end

local function at_center(s)
 local x,y=get_center(s.cx,s.cy)
 return s.x==x and s.y==y
end

local function has(t,d)
 for _,v in ipairs(t) do if v==d then return true end end
 return false
end

-- the steering rule at a decision point ($9D23-$9DB6): a single exit is
-- taken; otherwise right while FRAMECTR < $C0 (at or past it, with right
-- open, FRAMECTR is reseeded from CASSIN+KBD AND $7D and right is passed
-- over, $9D6A-$9D82), then down while above the home row ($9D8D-$9D9A),
-- then up, down, left ($9D9C-$9DB2), else carry on
local function steer()
 local ex=open_exits(player)
 local d=nil
 if #ex==1 then
  d=ex[1]
 else
  local _,hcy=home_cell()
  if has(ex,1) then
   if gohome.frame<0xC0 then d=1 else gohome.frame=math.random(0,0x7D) end
  end
  if not d and player.cy<hcy and has(ex,2) then d=2 end
  if not d and has(ex,0) then d=0 end
  if not d and has(ex,2) then d=2 end
  if not d and has(ex,3) then d=3 end
 end
 player.dir=d or player.dir
 player.next_dir=player.dir
end

-- a sitting frog on the walking head is moved off, with no score
-- ($9DD6-$9DEB: FROGHOP = 0 and the head on the frog -> FROGSPAWN/FROGERASE);
-- the frog eats the egg itself, inside frog_drive (L.8DE2 $8DE2)
local function frog_on_head()
 if not frog.hop and frog.active and player.cx==frog.cx and player.cy==frog.cy
  and at_center(player) then
  despawn_frog()
 end
end

local function set_phase(p)
 gohome.phase=p
 gohome.t=0
 gohome.n=0
 gohome.unfold=false
end

-- the clear: enemies are all dead
function gohome_enter()
 set_phase("tune")
 gohome.total=0
 gohome.js=GOHOME_JS_START -- JINGLE.SEL $88 = $64 ($9CE0)
 gohome.js_cnt=8 -- Z.0F = 8 ($9CE4)
 gohome.frame=0 -- FRAMECTR: the all-dead check fires on its wrap
 -- EGGERASE $9CB0: the enemy egg goes with the enemies
 enemy_egg.active=false
 enemy_egg.dropped=false
 enemy_egg.gestating=false
 player.bulge=nil
 player.moving=false
 game_state="GOHOME"
 game_update=gohome_update
 game_draw=gohome_draw
 if gohome_instant then gohome_done() return end
 -- the clear tune (jingle $AF6A, $88 = 1, from $9CDD); muted in the demo,
 -- where it still takes its time (DEMO_CLEAR_TUNE_SECS)
 if not attract then music(1,0,0,false) end
end

-- after CLEARSEQ: hatch an egg that is still out, else change the maze
-- ($9F2C JMP $1AE5: DEATHFLG $99 = 0 while an egg is out -> $1AF1), through
-- the harder modes' level bonus (state_bonus.lua)
function gohome_done()
 if player_egg.active and player_egg.dropped then
  hatch_enter()
 else
  level_done()
 end
end

-- one go-home step (the loop at $9D23-$9E03)
local function walk_step()
 local dist=STEP_PX
 local hcx,hcy=home_cell()
 while dist>0 do
  if at_center(player) then
   if player.cx==hcx and player.cy==hcy then -- S.9E05: home
    set_phase("door")
    despawn_frog() -- FROGSPAWN + FROGERASE $9E19
    break
   end
   steer()
  end
  dist=glide(player,dist)
  frog_on_head()
 end
 gohome.frame=(gohome.frame+1)%256 -- INC FRAMECTR $9DD4
 gohome.js_cnt=gohome.js_cnt-1 -- the walk speeds up ($9DF3-$9E03)
 if gohome.js_cnt==0 then
  gohome.js=math.max(gohome.js-1,GOHOME_JS_MIN)
  gohome.js_cnt=10
 end
 frog_drive() -- FROGDRIVE once per step ($9DC8)
 frog_on_head()
end

local SHUT_FRAMES={2/3,1/3,0}
local OPEN_FRAMES={1/3,2/3,1}

function gohome_update()
 gohome.t=gohome.t+1/30
 gohome.total=gohome.total+1/30
 local p=gohome.phase
 local note=SNAKE_PEN_STEP_SECS -- one S.95C2 note delay, ~50 ms

 if p=="tune" then
  local tune_done
  if attract then tune_done=gohome.t>=DEMO_CLEAR_TUNE_SECS
  else tune_done=peek(0x13FFC)==255 end
  if tune_done or gohome.t>=PREGAME_MAX_SECS then
   local hcx=home_cell()
   -- guard: a snake that never left the chute is already home
   if player.cx==hcx and player.cy>=PLAYER_DOOR2.cy then
    player.x,player.y=get_center(PLAYER_DOOR2.cx,PLAYER_DOOR2.cy)
    player.cx,player.cy=PLAYER_DOOR2.cx,PLAYER_DOOR2.cy
    player.dir=0
    set_phase("collapse")
    player.stack=(player.length-1)*SEGMENT_DIST
   else
    set_phase("walk")
   end
  end

 elseif p=="walk" then
  local step=orig_delay_secs(gohome.js,GOHOME_STEP_CYCLES)
  while gohome.phase=="walk" and gohome.t>=step do
   gohome.t=gohome.t-step
   walk_step()
   step=orig_delay_secs(gohome.js,GOHOME_STEP_CYCLES)
  end
  if gohome.phase=="walk" and gohome.total>=GOHOME_MAX_SECS then
   -- failsafe: put the snake on the home cell
   local hcx,hcy=home_cell()
   player.cx,player.cy=hcx,hcy
   player.x,player.y=get_center(hcx,hcy)
   set_phase("door")
   despawn_frog()
  end

 elseif p=="door" then -- the chute opens over three notes
  while gohome.t>=note and gohome.phase=="door" do
   gohome.t=gohome.t-note
   gohome.n=gohome.n+1
   PLAYER_DOOR2.open_amt=OPEN_FRAMES[gohome.n]
   if gohome.n==3 then
    set_phase("enter")
    player.dir=2
   end
  end

 elseif p=="enter" then
  -- the original steps 12 down and 5 back up ($9E5B-$9E8B); here the
  -- 17 notes carry the head straight down onto the launch spot
  local _,ly=get_center(PLAYER_DOOR2.cx,PLAYER_DOOR2.cy)
  local _,hy=get_center(home_cell())
  while gohome.t>=note and gohome.phase=="enter" do
   gohome.t=gohome.t-note
   gohome.n=gohome.n+1
   glide(player,(ly-hy)/17)
   if gohome.n==17 then
    glide(player,CELL_H) -- land exactly on the launch spot (float residue)
    player.dir=0 -- the last 5 steps turn it back up ($9E78)
    set_phase("collapse")
    player.stack=(player.length-1)*SEGMENT_DIST
   end
  end

 elseif p=="collapse" then -- CLEARSEQ: the tail catches up with the head
  -- the original folds (len-1)*4+1 steps (WALKCTR $9E97-$9EA1), a quarter
  -- segment per step, the whole body under the head until round init
  -- restacks it ($8676).
  -- a snake in the pen always shows head + one body segment
  -- (snake_pen.lua), so the first segment stays out while the rest fold onto
  -- it. The walk-in comes straight down, leaving that segment above the
  -- head; it then folds in under the head too and, at the same pace, slides
  -- back out below it, into the pose init_player launches from -- (len)*4
  -- steps in all
  local fold=SEGMENT_DIST/4
  while gohome.t>=note and gohome.phase=="collapse" do
   gohome.t=gohome.t-note
   gohome.n=gohome.n+1
   if not gohome.unfold then
    player.stack=math.max(0,player.stack-fold)
    if player.stack<=0 then
     -- folded into the head: re-aim the trail so it comes out below
     player.trail={}
     for _=1,10 do table.insert(player.trail,0) end
     gohome.unfold=true
    end
   else
    player.stack=math.min(SEGMENT_DIST,player.stack+fold)
    if player.stack>=SEGMENT_DIST then set_phase("close") end
   end
  end

 elseif p=="close" then -- the chute shuts over three notes ($9EB6-$9EEC)
  while gohome.t>=note and gohome.phase=="close" do
   gohome.t=gohome.t-note
   gohome.n=gohome.n+1
   PLAYER_DOOR2.open_amt=SHUT_FRAMES[gohome.n]
   if gohome.n==3 then
    PLAYER_DOOR2.state=0
    -- INC LIVES + DRAWLIVES ($9EF6): the snake home in the pen counts again
    snake_pen_hold_digit()
    gohome.phase="done"
    gohome_done()
    return
   end
  end
 end
 calc_segments(player)
end

function gohome_draw()
 play_draw()
end
