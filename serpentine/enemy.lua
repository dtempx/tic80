-- enemy.lua
-- release queue, the original's navigator (ENEMYAI $17AB) and pacing

enemies={} -- live enemy records; e.slot 1..3 is the original's record $6480/$6500/$6580
enemies_spawned=0 -- releases so far; original keyframe index RELIDX $AF ($89A9, $FF = done)
enemy_queue={} -- {slot=,len=} still to release; original targets ETGTLEN $A0-$A2 ($86E5/$8701)
enemy_pace={2,2,2} -- per-record move-skip threshold, EPACETHR $B3-$B5
pace_phase=0 -- the record the next creep raises, CYCLERPH $9F (0-2)

-- reset the enemy roster for a wave (round init $8654: lengths $86E5-$86F3 or $8701)
-- queue: {slot=,len=} in release order; nil = a fresh pen, records 1..3 in
-- turn (PENRELEASE $89A9). A nil len uses enemy_start_len (a respawn passes
-- the survivors' lengths, $8701)
function init_enemies(max_target,queue)
 enemies={}
 enemies_spawned=0
 target_enemies=max_target or MAX_ENEMIES
 if not queue then
  queue={}
  for s=1,target_enemies do queue[s]={slot=s} end
 end
 enemy_queue=queue
end

-- the lowest record neither alive nor waiting in the pen: a hatchling
-- revives the first dead record (EGGHATCH $AE2A)
local function free_slot()
 local held={}
 for _,e in ipairs(enemies) do
  if not e.dead then held[e.slot]=true end
 end
 for _,q in ipairs(enemy_queue) do held[q.slot]=true end
 for s=1,MAX_ENEMIES do
  if not held[s] then return s end
 end
 return 1 -- (B) egg law can hatch a fourth snake: it shares record 1's pace
end

-- is any record still alive or waiting in the pen (a length >= 2, $0941-$0954)?
function enemies_remaining()
 if #enemy_queue>0 then return true end
 for _,e in ipairs(enemies) do
  if not e.dead then return true end
 end
 return false
end

-- every record's threshold back to (level>>2)+2 ($8710-$871B). Round init
-- runs this only with CARRYLEN $A3 = 0, at game start and on a respawn; after
-- a level clear it returns at $8700 first, so the thresholds crept up so far
-- carry into the next level until the player dies
function reset_enemy_pace()
 local t=(difficulty_level()>>2)+2
 for s=1,MAX_ENEMIES do enemy_pace[s]=t end
end

-- S.0961 $0961: one record's threshold +1, round-robin, on FRAMECTR $80 and
-- on its wrap (egg.lua hunger_frame), so each enemy speeds up every 384 frames
function creep_enemy_pace()
 local s=pace_phase+1
 -- a byte: the original's wrap to 0 skips once per 256 frames, as 255 does
 enemy_pace[s]=math.min(enemy_pace[s]+1,255)
 pace_phase=(pace_phase+1)%MAX_ENEMIES
end

-- create an enemy at (sx,sy), default the enemy pen; is_egg = an egg hatchling
-- (pen release PENRELEASE $89A9, ESTATE $D3-$D5 -> 0; hatch EGGHATCH $AE2A)
function spawn_enemy(sx,sy,len,sdir,is_egg)
 local start_cx=sx or get_bottom_door_x("left")
 local start_cy=sy or (MAZE_ROWS+1)
 local start_x,start_y=get_center(start_cx,start_cy)

 local slot
 if not len and not is_egg then
  local q=table.remove(enemy_queue,1)
  if q then len,slot=q.len,q.slot end
 end
 slot=slot or free_slot()

 local start_dir=sdir or 0 -- up
 if sx~=nil and sdir==nil then
  -- egg hatch: heading right, the original's choice on a decision row
  -- ($AE90-$AE9C); the navigator then decides at once (below)
  start_dir=1
 end

 local enemy={
  x=start_x,
  y=start_y,
  cx=start_cx,
  cy=start_cy,
  dir=start_dir,
  next_dir=start_dir,
  moving=true,
  trail={},
  slot=slot, -- which of the three records, for its pace (EPACETHR $B3-$B5)
  length=len or enemy_start_len or ENEMY_START_LEN, -- +$1F ($649F/$651F/$659F)
  body={},
  dead=false,
  color=ORANGE, -- $E9=$80 until SETPALETTE $10D7 finds it shorter than the player
  bite_cd=0, -- ticks until this enemy may bite the player again (BITECD $E1-$E3)
  -- pen spawns start stacked like the player; a hatchling is born laid out
  stack=(not is_egg) and SEGMENT_DIST or nil,
 }

 -- pre-fill the trail so the tail extends cleanly on spawn
 for i=1,10 do
  table.insert(enemy.trail,start_dir)
 end

 enemy.decide=enemy_decide -- decides at each cell centre it reaches (snake.lua)
 if is_egg then
  -- a hatchling starts on a centre: take the first decision there
  local d=enemy_decide(enemy)
  if d then enemy.dir,enemy.next_dir=d,d end
 end
 calc_segments(enemy)
 table.insert(enemies,enemy)

 if not is_egg then
  enemies_spawned=enemies_spawned+1
 end
end

-- the original's target jitter, added to the player's head for a hunting
-- enemy (D.187A $187A dx / D.188A $188A dy, original px, index RNG & $0F)
local JIT_X={0,24,-24,0,0,0,16,-16,16,-16,12,0,12,-12,0,-12}
local JIT_Y={0,0,0,18,-18,0,8,8,-8,-8,14,0,-15,14,0,-15}

-- enemy speed: an enemy steps on all but one of every EPACETHR frames (the
-- skip at $114B-$1159), its record's threshold (reset_enemy_pace, raised by
-- creep_enemy_pace), while the player steps on nearly every frame (governor
-- PLYRGOV $90, $0CA2). So half the player's speed on levels 1-3, then 2/3,
-- 3/4 ... toward it, and closer through a round.
function enemy_speed(e)
 local thr=enemy_pace[e.slot]
 return PLAYER_SPEED*(thr-1)/thr
end

-- ENEMYAI $17AB at a decision point (a cell centre). Returns the direction to
-- take, or nil when the only way is back: the original then skips the move
-- ($17FA pops past the caller's JSR S.0E5F), so the snake waits there.
--   one exit  -> take it ($17E7-$17F7)
--   several   -> a target: the player's head plus a random jitter when this
--                enemy is at least as long as the player (LONGERFLG $E9 = $80,
--                SETPALETTE $10D7; $183C-$185A), else the player's egg
--                ($181E), else the frog while it is on the board ($182B);
--                no target -> random ($1877)
--   then the chase gate: a 4-bit roll below CHASEPROB $BD ($185C-$1875) takes
--   a greedy step -- the axis with the larger gap first (compared at half
--   resolution, $189A-$18E3), then the other -- if open; else, or on the
--   roll's failure, a random open exit (D.B171 $B171 is 1,2,4,8 x4: uniform,
--   $1903-$1912). The every-8th-decision random branch ($180F, AIRANDCTR
--   $94&7 = 7) is dead code: $94 is only ever written 0 ($1926) or 1 ($AD60).
function enemy_decide(e)
 if e.penned then
  -- climbing the pen (enemy_pen.lua); the cell above the outer door is its
  -- first decision point in the maze
  if e.cy>=ENEMY_DOOR2.cy then return 0 end
  e.penned=false
 end

 local tx,ty
 if e.length>=player.length then
  local j=math.random(1,16)
  local px,py=orig_xy(player.x,player.y)
  tx,ty=px+JIT_X[j],py+JIT_Y[j]
 elseif player_egg.active and player_egg.dropped then
  tx,ty=orig_xy(player_egg.x,player_egg.y)
 elseif frog.active then
  tx,ty=frog_orig_xy()
 end
 return ai_navigate(e,tx,ty,chase_prob)
end

-- the navigator's steering half, shared with the demo's autopilot
-- (state_demo.lua): the exits, the chase gate against `chance` (out of 16)
-- and the greedy step toward (tx,ty) in original px; tx=nil = no target
function ai_navigate(e,tx,ty,chance)
 local ex={}
 for d=0,3 do
  if d~=inv_dir(e.dir) and can_move(e,d) then ex[#ex+1]=d end
 end
 if #ex==0 then return nil end
 if #ex==1 then return ex[1] end
 local function open(d)
  for _,v in ipairs(ex) do if v==d then return true end end
  return false
 end

 if tx and math.random(0,15)<chance then
  local sx,sy=orig_xy(e.x,e.y)
  local hx,hy=math.floor(tx/2),math.floor(ty/2)
  local mx,my=math.floor(sx/2),math.floor(sy/2)
  local hdir=(hx<mx) and 3 or 1 -- left ($18AF) / right ($18BB)
  local vdir=(hy<my) and 0 or 2 -- up ($18D3) / down ($18DF)
  local first,second=hdir,vdir
  if math.abs(hx-mx)<math.abs(hy-my) then first,second=vdir,hdir end
  if open(first) then return first end
  if open(second) then return second end
 end
 return ex[math.random(#ex)]
end

-- one enemy tick: colour by length, move and steer each snake; releases come
-- from the pen script (enemy_pen.lua, PENDISPATCH $897A)
-- (per-enemy pacing and draw $114B/$11B5/$1222)
function update_enemies()
 for _,enemy in ipairs(enemies) do
  enemy.arrived=false -- set again if the head reaches a cell centre (snake.lua)
  if enemy.dead then
   -- shrivel countdown: update_dying_enemies (it runs even while the board is frozen)
  elseif enemy.penned then
   update_penned_enemy(enemy) -- climbing the pen to the outer door
  else
   -- shorter than the player = prey: drawn green ($10D7 law)
   if enemy.length<(player.length or 0) then
    enemy.color=GREEN
   else
    enemy.color=ORANGE
   end

   if enemy.moving then
    local dist=enemy_speed(enemy)
    while dist>0 do
     dist=move_head(enemy,dist) -- turns come from enemy_decide at centres
     if dist==nil then
      enemy.moving=false
      break
     end
    end
   end

   -- stopped on a centre: decide again each tick, as ENEMYAI runs every
   -- frame; with no way on (a dead end) it keeps waiting, as the original does
   if not enemy.moving then
    local d=enemy_decide(enemy)
    if d and can_move(enemy,d) then
     enemy.dir,enemy.next_dir=d,d
     enemy.moving=true
    end
   end

   calc_segments(enemy)
  end
 end
end

-- run the death shrivel of every dead enemy (ESHRINK $A4-$A6). Called every
-- play tick, even during the player's death sweep, so a shrivel always plays
-- out instead of freezing on screen until the next state ends
function update_dying_enemies()
 for _,enemy in ipairs(enemies) do
  if enemy.dead and enemy.dead_timer and enemy.dead_timer>0 then
   enemy.dead_timer=enemy.dead_timer-1
  end
 end
end

-- true while any dead enemy is still shrivelling
function enemies_dying()
 for _,enemy in ipairs(enemies) do
  if enemy.dead and enemy.dead_timer and enemy.dead_timer>0 then return true end
 end
 return false
end

-- draw every live or still-shrivelling enemy (SNAKEDRAW $0FD1 at $115B/$11C5/$1232)
function draw_enemies()
 for _,enemy in ipairs(enemies) do
  if not enemy.dead or (enemy.dead_timer and enemy.dead_timer>0) then
   draw_snake(enemy)
  end
 end
end
