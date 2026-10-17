-- state_play.lua
-- PLAY state: update order, snake-vs-snake collisions, HUD

-- round-start box ("LEVEL n" / "GET READY!"; no such screen in the
-- original): raised by round_start once the maze has been wiped in, it stays
-- up while the pens wait to open and is removed as soon as the pens' outer
-- doors start opening (or at once if the player dies). The LEVEL status panel is hidden from the start of the wipe
-- (wipe_enter) until the box goes. The demo shows no box. After a death
-- (respawn, set by cleared_init) the second line counts the snakes left
-- instead: "2 SNAKES LEFT!", then "LAST SNAKE!".
level_banner={on=false,respawn=false}
level_hidden=false

function level_banner_show()
 level_banner.on=not attract
 level_hidden=level_banner.on
end

function level_banner_hide()
 level_banner.on=false
 level_banner.respawn=false
 level_hidden=false
end

local function level_banner_update()
 if not level_banner.on then return end
 if player.dead then
  level_banner_hide()
  return
 end
 -- the pens' outer doors start to part together (release clock 84,
 -- enemy_pen.lua): the box goes on their first frame
 if PLAYER_DOOR2.open_amt>0 or ENEMY_DOOR2.open_amt>0 then
  level_banner_hide()
 end
end

-- one 30 Hz play tick: move everything, resolve collisions, detect the clear
-- (MAINLOOP $08FD; all-dead check on the $E4 wrap, $093F-$0958 -> GOHOME $9CB0)
function play_update()
 if game_state=="GAMEOVER" then return end

 -- internal clock; freezes outside PLAY
 game_time=game_time+1/30

 if game_state=="PREGAME" then return end

 -- the release clock runs first each frame, as S.8972 does at ROUNDSTART $08C3
 if not player.dead then
  enemy_pen_update()
  update_hunger() -- FRAMECTR/GRACECTR and the player's egg (egg.lua)
 end
 update_player()
 update_dying_enemies() -- a shrivel plays out even under the player's death sweep

 if not player.dead then
  update_enemies()
  update_frogs()
  update_eggs()
  update_doors()
  check_collisions()
 end
 level_banner_update()

 -- win: pen spawn quota exhausted and every enemy on screen is dead, and
 -- the last shrivel has played out. The original only checks on the FRAMECTR
 -- $E4 wrap (every 256 frames), so its shrink always finishes before GOHOME;
 -- this port checks every tick and must wait for it
 if enemies_spawned>=target_enemies and #enemies>0 and not enemies_dying() then
  local all_dead=true
  for _,e in ipairs(enemies) do
   if not e.dead then
    all_dead=false
    break
   end
  end
  if all_dead then
   gohome_enter() -- the player goes home (state_gohome.lua, GOHOME $9CB0)
  end
 end
end

-- Port-only progression ramp: shorten the pauses, preserving the approved
-- movement instrument's stored pitch, waveform and burst duration.
function snake_buzz_tempo()
 return math.min(SNAKE_BUZZ_TEMPO_CAP,1+math.max(0,(level or 1)-1)*SNAKE_BUZZ_TEMPO_PER_LEVEL
  +(game_difficulty or 0)*SNAKE_BUZZ_TEMPO_PER_DIFFICULTY)
end

-- The previous burst/gap approximation of SFX.MOVE $B1C9, with a level ramp
-- applied only when loading the next silent gap. Stepped on the audio clock.
function step_snake_buzz()
 if snake_buzz_enabled==false then return end
 snake_buzz_state=snake_buzz_state or 0
 if snake_buzz_state>0 then
  if snake_buzz_state==SNAKE_BUZZ_BURST then
   -- one trigger for the whole burst on the tick's own channel (2): nothing
   -- else plays there, so a frog hop or bite on channel 3 can't cut it short
   sfx(SNAKE_BUZZ,nil,math.floor(SNAKE_BUZZ_BURST_FRAMES/SNAKE_BUZZ_SPEED+0.5),SNAKE_BUZZ_CHANNEL)
  end
  snake_buzz_state=snake_buzz_state-1
  if snake_buzz_state==0 then
   local sum=player.length
   for _,e in ipairs(enemies) do
    if not e.dead then sum=sum+e.length end
   end
   local gap=math.floor(sum/2+0.5)+SNAKE_BUZZ_GAP_BASE
   snake_buzz_state=-math.max(1,math.floor(gap/snake_buzz_tempo()+0.5))
  end
 else
  snake_buzz_state=snake_buzz_state+1
  if snake_buzz_state==0 then snake_buzz_state=SNAKE_BUZZ_BURST end
 end
end

-- resolve snake/snake, frog and egg contacts for this tick (HEADCOMBAT $14E1,
-- per-enemy $14E1/$159C/$1657; body scans $12CA/$1507; frog $09BF; egg $AC70)
function check_collisions()
 if player.bite_cd>0 then player.bite_cd=player.bite_cd-1 end -- PENDSFX $D9, DEC $0998
 for _,e in ipairs(enemies) do
  if e.bite_cd>0 then e.bite_cd=e.bite_cd-1 end -- every frame ($099A-$09AA)
  if not player.dead and not player.hidden and not e.dead then
   -- 1) head to head: length decides, ties go to the enemy ($14EE CMP $641F)
   if hit(player.x,player.y,e.x,e.y) then
    if player.length<=e.length then
     kill_player()
    else
     player_eat_enemy(e)
    end
   else
    -- 2) player bites the enemy's body: touching it anywhere costs the enemy
    -- its tail, then no player bite lands while PENDSFX $D9 is set (path
    -- scan $12CA-$1326, gate $12BE)
    local player_bit_enemy=false
    if player.bite_cd==0 then
     for i=2,e.length do
      if e.body[i] and hit(player.x,player.y,e.body[i].x,e.body[i].y) then
       player_bite_enemy(e)
       player_bit_enemy=true
       break
      end
     end
    end

    -- 3) enemy bites the player's body: touching anywhere along it costs the
    -- player its TAIL segment, then this enemy waits BITE_COOLDOWN (skip while
    -- BITECD $E1 ~= 0, $1502; path scan $151E-$1559; tail erased $155C-$157C;
    -- reload $157F; SFX.BITE $AF65; DEC $641F $1586; below 2 dies, $158C-$1594).
    -- S.170D resets the hunger clock ($CB=1, egg.lua hunger_bitten).
    if not player_bit_enemy and e.bite_cd==0 then
     for i=2,player.length do
      if player.body[i] and hit(e.x,e.y,player.body[i].x,player.body[i].y) then
       snd("hurt")
       e.bite_cd=BITE_COOLDOWN
       player.length=player.length-1
       hunger_bitten()
       if player.length<=1 then
        kill_player()
       end
       break
      end
     end
    end
   end
  end
 end

 -- frog vs snakes: a head that meets the sitting frog eats it, grows a
 -- segment, and the frog is respawned under the board (player +500 and grow,
 -- $09BB-$09EC; enemies $0A6A/$0B11/$0BC6 -> FROGSPAWN $0AA9 and growth $0AB3)
 if not player.dead and not player.hidden and head_on_frog(player) then
  snd("devour") -- the rising chirp, SFX.EATEN = 7 + SFX.EATCHIRP ($09E2-$09E6)
  despawn_frog()
  award(500)
  grow_snake(player)
 end
 for _,e in ipairs(enemies) do
  if not e.dead and not e.penned and head_on_frog(e) then
   snd("devour") -- SFX.EATEN = 7 ($0AAF/$0B56/$0C00), chirped from MAINLOOP $09B0
   despawn_frog()
   grow_snake(e)
   break
  end
 end

 -- dropped eggs: the player eats the enemy's, enemies eat the player's
 -- (player +150 x level, S.AC70 $AC70-$AC99; enemies $0A83-$0AA6 -> S.85AE;
 -- the frog eats either egg while sitting on it, frog.lua frog_drive)
 if enemy_egg.active and enemy_egg.dropped and not player.dead then
  if head_over(player,enemy_egg.x,enemy_egg.y) then
   snd("crunch")
   enemy_egg.active=false
   enemy_egg.dropped=false
   award(150*level)
   grow_snake(player)
  end
 end

 if player_egg.active and player_egg.dropped then
  for _,e in ipairs(enemies) do
   if not e.dead and head_over(e,player_egg.x,player_egg.y) then
    snd("crunch") -- SFX.CONSUME, as the frog's eat of this egg ($8DE9)
    player_egg.active=false
    player_egg.dropped=false
    grow_snake(e)
    break
   end
  end
 end

 -- where each head was this tick, for next tick's swept egg test (head_over)
 player.head_prev_x,player.head_prev_y=player.x,player.y
 for _,e in ipairs(enemies) do e.head_prev_x,e.head_prev_y=e.x,e.y end
end

-- draw the board: maze, frog, eggs, snakes, then the reserve pen
-- (full redraw; the original erases and redraws only what moved, $0FD1/$1056)
function play_draw()
 cls(BLACK)
 if demo_board then
  draw_demo_board() -- a game started from the demo, before its wipe (state_demo.lua)
 elseif maze_blank then
  draw_grid()
  wipe_mask(240) -- blank maze before the first reveal (state_wipe.lua)
 else
  draw_grid()
  draw_frogs()
  draw_eggs()
 end

 -- mask the pen area during play so queued spawns pop in unseen;
 -- pregame shows it so the lineup is visible
 if game_state~="PREGAME" then
  clip(0,0,240,OFFSET_Y+MAZE_ROWS*CELL_H+1)
 end
 draw_snake(player)
 draw_enemies()
 clip()

 --[[ Top status temporarily disabled for the full-height maze evaluation.
 (original header: DRAWSCORE $82E8, DRAWLEVEL $8727, digits DIGITFONT $7DF2)
 print("SERPENTINE",OFFSET_X,3,TEXT_COLOR,true)
 ]]

 draw_player_reserves() -- snake_pen.lua: reserve snakes + lives digit
 draw_status()
 if level_banner.on and game_state=="PLAY" then draw_level_banner() end
end

-- the round-start box: "LEVEL", a double-size number, then "GET READY!",
-- centred, with 8 px of padding either side of the wider line, in the
-- level-bonus box's frame and drop shadow (state_bonus.lua)
function draw_level_banner()
 local title="LEVEL"
 local number=tostring(level)
 local ready="GET READY!"
 -- player_lives already counts the death, so it is the snakes still to play
 if level_banner.respawn then
  ready=player_lives>1 and player_lives.." SNAKES LEFT!" or "LAST SNAKE!"
 end
 local tw=print(title,0,-20,TEXT_COLOR,true)
 local nw=print(number,0,-20,TEXT_COLOR,true,2)
 local rw=print(ready,0,-20,TEXT_COLOR,true)
 local w=math.max(tw,nw,rw)+16
 local h=52 -- small heading, double-size number, small prompt, 9 px padding
 local x=(240-w)//2
 local y=(136-h)//2
 drop_shadow(x,y,w,h)
 rect(x,y,w,h,BLACK)
 rectb(x,y,w,h,WHITE)
 print(title,(240-tw)//2,y+9,WALL_COLOR,true)
 print(number,(240-nw)//2,y+19,WALL_COLOR,true,2)
 -- LAST SNAKE! blinks like the title prompt: real time, 500 ms on / 500 ms off
 if ready~="LAST SNAKE!" or time()//500%2==0 then
  print(ready,(240-rw)//2,y+37,WHITE,true)
 end
end

-- the status line in the small font across the top corners (placed here because
-- the original's header line has no room on the full-height screen): "LEVEL n"
-- (DRAWLEVEL $8727) top-left, and the 6-digit score top-right, zero-padded as
-- DRAWSCORE $82E8 prints all six BCD digits. Each is white text on a
-- wall-coloured panel with 1 px of padding all round (text 4n-1 px wide at the fixed 4 px pitch,
-- so the panel is 4n+1 by 7, rows 0..6), wiping the maze wall and any sprite
-- under it. Call it after every snake so it stays on top. The demo shows
-- the level and a nonzero saved high score, with a HISCORE prefix (PORT).
-- On a green or white monitor (a2boot.lua mono) the panel is black instead:
-- a violet one would come out as stripes behind the text, and so would the
-- maze wall it covers
local function draw_status_text(text,x,y)
 local bg=mono.phosphor[mono.mode] and BLACK or WALL_COLOR
 rect(x-1,y-1,4*#text+1,7,bg)
 print(text,x,y,WHITE,true,1,true)
end

-- fill a rect with a black/SHADOW checkerboard, parity fixed to the screen so
-- adjoining fills line up
local function checker(x,y,w,h)
 rect(x,y,w,h,BLACK)
 for py=y,y+h-1 do
  for px=x+(x+py)%2,x+w-1,2 do pix(px,py,SHADOW) end
 end
end

-- the dithered drop shadow of the box at x,y,w,h, SHADOW_DROP px right
-- and down: only the L the box itself leaves showing, so draw it first or
-- after. A mono monitor has no grey (the dots would stripe), so colour only
function drop_shadow(x,y,w,h)
 if mono.phosphor[mono.mode] then return end
 local d=SHADOW_DROP
 checker(x+w,y+d,d,h) -- right edge, down to the corner
 checker(x+d,y+h,w-d,d) -- bottom edge
end

-- the level carries a "+" per difficulty step above BEGINNER ("LEVEL 1+")
-- (hidden while level_hidden: from a wipe's start until the round-start box goes)
function draw_status()
 if not level_hidden then
  draw_status_text("LEVEL "..level..string.rep("+",game_difficulty),LEVEL_X,LEVEL_Y)
 end
 if attract and (hiscore or 0)==0 then return end
 local text=string.format("%06d",attract and hiscore or score)
 if attract then text="HISCORE "..text end
 draw_status_text(text,SCORE_X-4*(#text-6),SCORE_Y)
end
