-- enemy_pen.lua
-- the round's release script, after the original's PENDISPATCH ($897A). One
-- clock, RELCLOCK $AE, ticks once per original main-loop frame (ROUNDSTART
-- $08C3 calls S.8972 $8972 every frame). It drives the enemy pen's two doors
-- and lets the enemies in one at a time (RELIDX $AF); on its first cycle the
-- same ticks run the player's launch (INTROCLK $D7, $60 at SETINTROCLK $8699,
-- counted down at $0C62; chute-door frames in S.88F3 $88F3). So the enemy
-- pen starts empty, the first enemy comes up through the bottom door and
-- waits at the outer door, and both outer doors open and both snakes go on
-- the same tick.
--
-- Keyframes (clock values, each handler's CMPs):
--   $04/$08/$0C  bottom door opens   S.8996 $89BE/$89D1/$89E4 (HGR $3BD1/$3FD1)
--   $10          enemy goes live     $89F7 (ESTATE $D3+X = 0); length -> ETGTLEN0
--   $44/$48/$4C  bottom door closes  S.8A16 $8A36/$8A49/$8A5C (len < 6)
--   $68/$6C/$70                      (len >= 6)
--   $54/$58/$5C  outer door opens    S.8A74 $8A81/$8A94/$8AA7 (HGR $38D1/$3CD1)
--   $60          door cell passable  PENDOOR $8AC3 (PENDOORCELL $A471 = 8)
--   $63          door cell shut      PENDOOR $8ACE (= 0)
--   $86/$8A/$8E  outer door closes   S.8AD6 $8AF6/$8B09/$8B1C (len < 5)
--   $96/$9A/$9E                      (len >= 5); the last frame starts the
--                                    next enemy's cycle: RELIDX+1, clock 0 ($8B2C)
--   player launch (first cycle): chute opens at $D7 = $0C/$08/$04 (ticks
--   $54/$58/$5C, $892A/$893B/$894C), control at $D7 = 0 (tick $60, $0C62),
--   chute closes at $D7 = $FC/$F8/$F4 (ticks $64/$68/$6C, $893B/$892A/$895D)
-- every close above starts at its keyframe or once the snake has
-- cleared that door, whichever is later (shut_behind)

-- door frame bytes as opening fractions: opening $0A54, $0250, $0040;
-- closing $0250, $0A54, $2A55 (fully shut)
local OPEN={1/3,2/3,1}
local SHUT={2/3,1/3,0}

enemy_pen={clock=0,t=0,cycle=0,len=0,intro=false,shut_pending=false}

local function frame(d,list,k) d.open_amt=list[k] end

-- the one shut sequence for every door this script closes behind a snake:
-- the SHUT frames 4 ticks apart from tick `from`, the original's keyframes.
-- the first frame waits until `s` has cleared the door (door_cleared),
-- because the port's snakes need longer than the original's to get through
-- (7 px segments on 12 px cells, and the player's length is not what the
-- fixed launch schedule assumed), and a keyframe that falls while a snake is
-- still in the doorway would shut it across the body. Returns the SHUT frame
-- just drawn (1..3), or nil.
local function shut_behind(d,s,from,c)
 if not d.shut_at then
  if c<from or d.open_amt==0 or not door_cleared(d,s) then return nil end
  d.shut_at=c
 end
 local k=c-d.shut_at
 if k%4~=0 or k>8 then return nil end
 frame(d,SHUT,k//4+1)
 if k==8 then d.shut_at=nil end
 return k//4+1
end

-- a new round: empty enemy pen, clock at 0, the player held at the launch
-- spot until its countdown ends (round init $86B2/$86B4: RELCLOCK = RELIDX = 0)
function enemy_pen_reset()
 enemy_pen.clock=0
 enemy_pen.t=0
 enemy_pen.cycle=1 -- which release cycle; the player launches on the first
 enemy_pen.len=0 -- ETGTLEN0: length of the enemy this cycle lets in
 enemy_pen.intro=true
 enemy_pen.shut_pending=false
 enemy_pen.done=false
 enemy_pen.enemy=nil -- the enemy this cycle lets in (the doors shut behind it)
 ENEMY_DOOR1.shut_at=nil
 ENEMY_DOOR2.shut_at=nil
 PLAYER_DOOR2.shut_at=nil
 -- the enemy pen's doors belong to this script; the player's chute does
 -- until its launch is over
 ENEMY_DOOR1.scripted=true
 ENEMY_DOOR2.scripted=true
 PLAYER_DOOR2.scripted=true
end

-- is any enemy still inside the pen (below the outer door)?
local function penned_enemy()
 for _,e in ipairs(enemies) do
  if e.penned and not e.dead then return e end
 end
end

local function tick()
 local c=enemy_pen.clock+1 -- INC RELCLOCK comes first ($897A)
 enemy_pen.clock=c
 local d1,d2=ENEMY_DOOR1,ENEMY_DOOR2

 -- the player's launch runs on the round's first cycle only
 if enemy_pen.intro then
  local p=PLAYER_DOOR2
  if c==84 or c==88 or c==92 then frame(p,OPEN,(c-80)//4) end
  if c==96 then
   p.state=3 -- the chute cell passes upward (one-way-up cell, disasm README 2.1)
   player.launch_hold=false -- $D7 reached 0: control from here ($0C62)
   player.is_released=true
   player.dir=0
   player.next_dir=0 -- CURDIR preset UP ($869D)
   player.moving=true
  end
  if shut_behind(p,player,100,c)==3 then
   p.state=0
   p.scripted=false -- back to the port's door logic (door.lua)
   enemy_pen.intro=false
  end
 end

 if enemy_pen.done then return end
 -- nobody left to let in: the script stops (RELIDX = $FF, $89B9/$8B34)
 if c==1 and enemies_spawned>=target_enemies then
  enemy_pen.done=true
  return
 end

 if c==4 or c==8 or c==12 then
  frame(d1,OPEN,c//4)
  if c==12 then d1.state=3 end
 elseif c==16 then
  -- ESTATE -> 0: the next queued enemy comes up from under the bottom door
  spawn_enemy()
  local e=enemies[#enemies]
  e.penned=true
  enemy_pen.enemy=e
  enemy_pen.len=e.length
 end
 if c<16 then return end
 local e=enemy_pen.enemy

 local close1=(enemy_pen.len<6) and 68 or 104 -- S.8A16 $8A18 CPX #$06
 if shut_behind(d1,e,close1,c)==1 then d1.state=0 end

 if c==84 or c==88 or c==92 then frame(d2,OPEN,(c-80)//4) end
 if c==96 then
  d2.state=3 -- PENDOOR $8AC3: the chute cell opens
  snake_pen_release_digit() -- and DRAWLIVES ($8AC8) shows round init's DEC LIVES
 end
 if c==99 then enemy_pen.shut_pending=true end -- $8ACE shuts it again

 local close2=(enemy_pen.len<5) and 134 or 150 -- S.8AD6 $8AD8 CPX #$05
 if shut_behind(d2,e,close2,c)==3 then
  -- $8B2C: next enemy's cycle, or stop once all three have been let in
  enemy_pen.clock=0
  enemy_pen.cycle=enemy_pen.cycle+1
  enemy_pen.done=(enemies_spawned>=target_enemies)
 end
end

-- one 30 Hz play tick: advance the release clock by whole original frames
function enemy_pen_update()
 enemy_pen.t=enemy_pen.t+1/30
 while enemy_pen.t>=ENEMY_PEN_TICK_SECS do
  enemy_pen.t=enemy_pen.t-ENEMY_PEN_TICK_SECS
  tick()
 end
 -- the cell shuts at $63, but not on a snake still waiting under it
 -- (the original's enemy always arrives long before $60)
 if enemy_pen.shut_pending and not penned_enemy() then
  ENEMY_DOOR2.state=0
  enemy_pen.shut_pending=false
 end
end

-- a released enemy climbs straight up the pen until its head reaches the
-- cell above the outer door, where the navigator takes over (enemy_decide
-- clears `penned` there); the pen cells only lead up
function update_penned_enemy(e)
 if e.penned then
  e.dir=0
  e.next_dir=0
 end
 if not e.moving and can_move(e,e.dir) then e.moving=true end
 if e.moving then
  local dist=enemy_speed(e)
  while dist>0 do
   dist=move_head(e,dist)
   if dist==nil then
    e.moving=false
    break
   end
  end
 end
 calc_segments(e)
end
