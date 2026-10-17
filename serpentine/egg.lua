-- egg.lua
-- egg lifecycle: gestation on a tail, drop (severing the tail), hatch
-- (B's two-egg law). The original has ONE egg, at EGGX/EGGY $97/$98
-- ($98~=0 = exists): the longest living enemy lays it once a slot is dead
-- (EGGTRIGGER $ACC9, EGGLAY $AD5E), it gestates $92 ticks and revives the
-- first dead slot (EGGHATCH $AE2A). The player never lays.

-- reset both eggs; keep_player_egg spares a dropped player egg across a respawn
-- (the original erases its egg on death and clear, EGGERASE $AEA2 via $8E21/$9CB0)
function init_eggs(keep_player_egg)
 -- a respawn restage keeps a player egg already lying on the board
 local keep=keep_player_egg and player_egg
  and player_egg.active and player_egg.dropped

 if not keep then
  player_egg={ -- no player egg in the original
   active=false, -- anywhere at all (gestating or dropped)
   is_player=true,
   gestating=false,
   dropped=false,
   parent=nil,
   cx=0,cy=0,
   gestation_timer=0,
   hatch_timer=0,
  }
 end

 enemy_egg={ -- the original's single egg
  active=false,
  is_player=false,
  gestating=false, -- on the layer's tail: LAYERSLOT $95, pulses LAYTIMER $93 / LAYPULSES $96
  dropped=false, -- on the board: EGGX/EGGY $97/$98
  parent=nil, -- layer snake (LAYERSLOT $95, $AD00)
  cx=0,cy=0,
  gestation_timer=0, -- tail-bulge countdown (LAYTIMER $93, $AD10/$AD62)
  hatch_timer=0, -- EGGTIMER $92 ($ADA0/$ADE9)
 }
end

-- enemies still alive (the original's dead-slot test is any length < 2, $ACC9-$ACE2)
local function live_enemy_count()
 local c=0
 for _,e in ipairs(enemies) do
  if not e.dead then c=c+1 end
 end
 return c
end

-- The player's egg is the original's (S.84E6 $84E6): a hunger clock, not a
-- roll. GRACECTR $CB starts at 4 each round and drops each time the frame
-- counter FRAMECTR $E4 wraps ($093F; an enemy's death jumps it to $D0,
-- $1766). Once it is negative and no egg is out, the tail swells one stage
-- every 48 player ticks (Z.CC $CC to $30, stage Z.CA $CA, shape +4 at $8552)
-- and on the fourth the tail segment becomes the egg: length -1, the egg at
-- its spot (PHEADCPY/PHEADCPYY $CD/$CE, drawn each frame by S.856A $856A),
-- GRACECTR = 1 ($852E). A player left with one segment dies ($8537). A bite
-- resets the progress (S.170D $170D). The egg hatches only at a level clear
-- (state_hatch.lua).
hunger={frame=0,grace=GRACE_START,cc=0,ca=0,t=0}

-- a new round: L.0822 zeroes FRAMECTR, Z.CC, Z.CA ($0826-$082C) and round
-- init sets GRACECTR 4 ($86DA)
function hunger_reset_round()
 hunger.frame=0
 hunger.cc=0
 hunger.ca=0
 hunger.grace=GRACE_START
 hunger.t=0
 player.bulge=nil
end

-- an enemy bit the player (S.170D $170D, from $1589/$1644/$16FF)
function hunger_bitten()
 hunger.cc=0
 hunger.ca=0
 hunger.grace=1
 player.bulge=nil
end

-- an enemy died: FRAMECTR jumps to $D0 (S.1756 $1766)
function hunger_enemy_died() hunger.frame=0xD0 end

local function hunger_frame()
 hunger.frame=(hunger.frame+1)%256
 if hunger.frame==0 then hunger.grace=hunger.grace-1 end -- DEC GRACECTR $093F
 -- the enemies' pacing creep (S.0961): at $80, and on the wrap while a
 -- record is still alive ($0941-$095B, $097E-$0984)
 if hunger.frame==0x80 or (hunger.frame==0 and enemies_remaining()) then
  creep_enemy_pace()
 end
 -- S.84E6 only runs from the player's own tick, which the launch clock skips
 if player.launch_hold then return end
 step_player_pace()
 if hunger.grace>=0 or player_egg.active then return end -- $84E6-$84EC
 hunger.cc=hunger.cc+1
 if hunger.cc<HUNGER_TICKS then return end
 hunger.cc=0
 hunger.ca=hunger.ca+1
 if hunger.ca<4 then
  player.bulge=hunger.ca -- the tail's egg-bulge stage ($853B-$8566)
  return
 end
 -- lay: the tail segment is the egg ($8502-$851C)
 local tail=player.body[player.length]
 player.length=player.length-1
 player.bulge=nil
 hunger.ca=0
 hunger.grace=1
 player_egg.active=true
 player_egg.gestating=false
 player_egg.dropped=true
 player_egg.x,player_egg.y=tail.x,tail.y
 player_egg.cx,player_egg.cy=get_cell(tail.x,tail.y)
 if player.length<2 then kill_player() end -- $8530-$8537
end

-- one 30 Hz play tick of the hunger clock, in whole original frames
function update_hunger()
 hunger.t=hunger.t+1/30
 while hunger.t>=ORIG_FRAME_SECS do
  hunger.t=hunger.t-ORIG_FRAME_SECS
  if not player.dead then hunger_frame() end
 end
end

-- roll for a new enemy egg, then tick both eggs
-- 1-in-300 roll per tick; original picks the longest enemy (len>=3) once
-- per 256 frames at $E4==$77, only when a slot is dead (EGGTRIGGER $ACC9-$AD0C)
function update_eggs()
 -- enemy egg: never beyond the enemy quota
 if not enemy_egg.active then
  if live_enemy_count()<target_enemies then
   local valid={}
   for _,e in ipairs(enemies) do
    if not e.dead and e.length>2 and e.spawned
     and game_time-e.time_spawned>=30 then
     local can_lay=not e.time_last_egg_laid
      or game_time-e.time_last_egg_laid>=EGG_SPAWN_DELAY
     if can_lay then table.insert(valid,e) end
    end
   end
   if #valid>0 and math.random(300)==1 then
    start_gestation(enemy_egg,valid[math.random(#valid)])
   end
  end
 end

 tick_egg(player_egg)
 tick_egg(enemy_egg)
end

-- egg hatch gestation at the current difficulty level, in seconds (EGGTIMER
-- $92, set at $AD9C then $ADA0-$ADAE; see constants.lua)
function egg_hatch_secs()
 local l=difficulty_level()
 local ticks
 if l<EGG_HATCH_TICKS_MIN_LEVEL then
  ticks=(EGG_HATCH_TICKS_BASE-l*EGG_HATCH_TICKS_STEP)&0xFF
 else
  ticks=EGG_HATCH_TICKS_DEFAULT
 end
 return ticks*ORIG_FRAME_SECS
end

-- `snake` starts carrying `egg` on its tail (layer select $AD00, EGGLAY $AD5E)
function start_gestation(egg,snake)
 snake.gestating_egg=egg -- the snake renders the tail bulge (snake.lua pass 3)
 snake.time_last_egg_laid=game_time
 egg.active=true
 egg.gestating=true
 egg.dropped=false
 egg.parent=snake
 egg.gestation_timer=EGG_SPAWN_DURATION*30
end

-- one egg tick: gestate and drop (tail -1 into the egg, $AD77-$AD88), then hatch
-- (gestation countdown $ADE9, EGGHATCH $AE2A: length 2 into the first dead slot)
function tick_egg(egg)
 if not egg.active then return end

 if egg.gestating then
  -- parent died holding the egg: it dies with them
  if egg.parent.dead then
   egg.active=false
   egg.gestating=false
   egg.parent.gestating_egg=nil
   return
  end

  egg.gestation_timer=egg.gestation_timer-1
  if egg.gestation_timer<=0 then
   -- detach: the egg drops where the tail segment sits
   egg.gestating=false
   egg.dropped=true

   local tail=egg.parent.body[egg.parent.length]
   if tail then
    egg.x=tail.x
    egg.y=tail.y
    egg.cx,egg.cy=get_cell(tail.x,tail.y)
   else
    egg.x=egg.parent.x
    egg.y=egg.parent.y
    egg.cx=egg.parent.cx
    egg.cy=egg.parent.cy
   end

   -- sever the tail
   egg.parent.length=egg.parent.length-1
   egg.parent.gestating_egg=nil

   -- laying can shrink the player to a dead head
   if egg.is_player and egg.parent.length<=1 then
    kill_player()
   end

   if not egg.is_player then
    egg.hatch_timer=egg_hatch_secs()*30
   end
  end

 elseif egg.dropped then
  -- only enemy eggs hatch
  if not egg.is_player then
   egg.hatch_timer=egg.hatch_timer-1
   if egg.hatch_timer<=0 then
    snd("crunch") -- the egg crack (EGGHATCH $AE2A itself is near-silent)
    spawn_enemy(egg.cx,egg.cy,2,nil,true)
    egg.active=false
    egg.dropped=false
   end
  end
 end
end

-- Upright egg silhouette: narrow crown and broad, rounded base.
-- draw one egg centred on (x,y) (glyph EGGGLYPHS $B065; the original animates 7 phases, $ADED)
local function draw_egg_shape(x,y,is_player)
 spr(is_player and SPRITE_EGG_PLAYER or SPRITE_EGG_ENEMY,x-3,y-3,BLACK)
end

-- draw every egg lying on the board (egg redraw $ADED-$AE29)
function draw_eggs()
 if player_egg.active and player_egg.dropped then
  draw_egg_shape(player_egg.x,player_egg.y,true)
 end
 if enemy_egg.active and enemy_egg.dropped then
  draw_egg_shape(enemy_egg.x,enemy_egg.y,false)
 end
end
