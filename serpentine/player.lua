-- player.lua
-- input, death/respawn transitions, combat scoring

player={} -- the player record $6400 (fields: snake.lua header)
player_pace={counter=0,period=0} -- PLYRGOV $90 / PLYRGOVP $91

-- Reset only at game start/respawn; a clear carries the governor ($871D-$8724).
function reset_player_pace()
 local p=(0xd0-difficulty_level())&0xff
 player_pace.counter,player_pace.period=p,p
end

-- One original frame of the player governor ($0CA2-$0CCC), bypassed in demo/launch.
function step_player_pace()
 if attract or player.launch_hold then return end
 local p=player_pace.period
 local c=player_pace.counter
 if p<0x80 then c=((c-1)&0xff)|1 end
 c=(c-1)&0xff
 if c==0 then
  p=(p-2)&0xff
  if p<0x80 then p=(p-3)&0xff end
  if p<0x10 then p=(p+3)&0xff end
  player_pace.period=p
  c=p
 end
 player_pace.counter=c
end

-- Average the original skipped moves into this port's continuous pixel motion.
function player_speed()
 if attract then return PLAYER_SPEED end
 local p=player_pace.period
 local period=p>=0x80 and p or ((p+1)&0xfe)
 if period==0 then period=256 end
 local skips=p>=0x80 and 1 or 2
 return PLAYER_SPEED*(period-skips)/period
end

-- build the player snake at (cx,cy), default the player pen (record init $0822-$08BB)
function init_player(cx,cy)
 local start_cx=cx or get_bottom_door_x("right")
 local start_cy=cy or (MAZE_ROWS+1)
 local start_x,start_y=get_center(start_cx,start_cy)

 player={
  x=start_x,
  y=start_y,
  cx=start_cx,
  cy=start_cy,
  dir=0, -- up: the launch is forced UP (INTROCLK $D7, $0C62-$0C70)
  next_dir=0,
  moving=true,
  trail={}, -- step FIFO +$20..+$57, zeroed at launch ($0868)
  length=carry_len or PLAYER_START_LEN, -- $641F: CARRYLEN $A3 after a clear, else 3 ($0877)
  body={},
  dead=false, -- DEATHFLG $99
  color=BLUE, -- player always draws with $E9=$80 ($10ED)
  dead_timer=0,
  bite_cd=0, -- ticks until the player may bite an enemy again (PENDSFX $D9, gate $12BE)
  hidden=false, -- still off screen during the pen fill
  is_released=false, -- control handed over when the launch clock $D7 runs out ($0C62)
  launch_hold=true, -- frozen at the launch spot while $D7 counts ($0C62-$0C70 skip the move); enemy_pen.lua lifts it
  stack=SEGMENT_DIST, -- body starts stacked in the pen (snake.lua)
  -- the demo steers the player with the enemy navigator ($0C73, state_demo.lua)
  decide=attract and demo_decide or nil,
 }

 -- pre-fill the trail so the tail extends cleanly backwards
 for i=1,10 do
  table.insert(player.trail,0)
 end

 calc_segments(player)
end

-- latch Z (start) and the requested turn from the d-pad
-- polled every TIC frame (60hz) so no press lands between 30hz logic ticks
-- (READINPUT $0CD1 synthesizes a stick from keys $89-$8C; KEYHANDLER $96A3)
function poll_input()
 if btnp(4) then start_pressed=true end
 if btnp(5) then back_pressed=true end -- B: the title's options entry, the options page's back
 if btnp(4) or btnp(5) then fire_pressed=true end -- either fire button (intro skip)
 for d=0,3 do -- menu steps: 0 up, 1 down, 2 left, 3 right (options page)
  if btnp(d) then menu_pressed=d end
 end
 if game_state=="PLAY" and player.is_released and not player.dead then
  if btn(0) then player.next_dir=0 end
  if btn(1) then player.next_dir=2 end
  if btn(2) then player.next_dir=3 end
  if btn(3) then player.next_dir=1 end
 end
end

-- add points with the 6-digit display wrap (SED/ADC onto BCD $B8/$B9/$BA)
function award(points)
 score=(score+points)%SCORE_ROLLOVER
end

-- one player tick: count down a death, else move the head and rebuild the body
-- (main-loop player move $0CD1-$0E41; death flow PLAYERDIE $19E0 -> ROUNDINIT $8654)
function update_player()
 if player.dead then
  if player.dead_timer and player.dead_timer>0 then
   player.dead_timer=player.dead_timer-1
   if player.dead_timer<=0 then
    if player_lives>0 then
     game_state="CLEARED"
     cleared_init(true)
     game_update=cleared_update
     game_draw=cleared_draw
    else
     game_state="GAMEOVER"
     gameover_init()
     game_update=gameover_update
     game_draw=gameover_draw
    end
   end
  end
  return
 end

 -- the launch clock only redraws the snake: no move until it runs out
 if player.launch_hold then
  calc_segments(player)
  return
 end

 player.arrived=false -- set again if the head reaches a cell centre (snake.lua)
 if player.moving then
  local dist=player_speed()
  while dist>0 do
    local next_dist=move_head(player,dist)
    if next_dist==nil then
      player.moving=false
      break
    end
    dist=next_dist
  end
 else
  -- the demo's navigator decides again while stopped, as the enemies' does
  if player.decide then
   player.next_dir=player.decide(player) or player.next_dir
  end
  -- try to resume when a path opens
  if can_move(player,player.next_dir) then
   player.dir=player.next_dir
   player.moving=true
  elseif can_move(player,player.dir) then
   player.moving=true
  end
 end

 calc_segments(player)
end

-- the player dies: death sweep, then lose a life (PLAYERDIE $19E0, DEATHSWEEP $19F4;
-- the original takes the life at the next round init, DEC $D8 at $868F)
function kill_player()
 snd("death")
 player.dead=true
 player.dead_timer=30
 player_lives=player_lives-1
end

-- the player's head touched an enemy's body: wherever it touched, the enemy
-- loses its TAIL segment ($1329-$1349 erase the last triple), +100 x m
-- (S.1352 $1352; m=(level+1)>>1 as at $1352-$1358), length -1 ($1379), and
-- below 2 it dies (KILLENEMY $1388). A surviving enemy sets PENDSFX $D9 = 2
-- ($1385), which holds off every player bite for the next two frames while
-- BLIP2 then BLIP1 play ($0987-$0998, gate $12BE; snd "bite").
function player_bite_enemy(e)
 local m=(level-1)//2+1
 award(100*m)
 -- a bite on the layer calls the lay off: the bulging tail is gone and the
 -- egg is not passed to the next segment (LAYERSLOT $95 = 0 at $136F/$1418/$14BF)
 local egg=e.gestating_egg
 if egg then
  egg.active=false
  egg.gestating=false
  e.gestating_egg=nil
 end
 e.length=e.length-1
 if e.length<=1 then
  -- KILLENEMY starts the same shrink as a head-on kill, which chirps each
  -- frame (ESHRINK0 $A4 = 7, SFX.EATCHIRP at $1117/$1181/$11EE)
  snd("devour")
  e.dead=true
  e.dead_timer=30
  hunger_enemy_died()
 else
  snd("bite")
  player.bite_cd=PLAYER_BITE_COOLDOWN
 end
end

-- head-on win: score the kill, kill the enemy, grow +1 (L.14F9 $14F9: SCOREKILL
-- $91C6, grow $09F4, KILLENEMY $1751). 200 x len x m: A=$649F (enemy length),
-- ASL into $F6, added to hundreds byte $B9 m=(level+1)>>1 times ($91C6-$91E0)
function player_eat_enemy(e)
 snd("devour")
 local m=(level-1)//2+1
 award(200*m*e.length)
 e.dead=true
 e.dead_timer=30
 hunger_enemy_died()
 grow_snake(player)
end
