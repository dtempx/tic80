-- game_state: frame pacer, sound dispatch and new-game bootstrap

-- Real-time pacer: pins the 30 Hz sim to the wall clock so game speed stays
-- constant even when the engine calls TIC() slower or faster than the nominal
-- 60 Hz (TIC-80's cadence follows display/system load — see README timing
-- note). dt is measured in 1/60 s display frames, EMA-smoothed (frames present
-- on the refresh grid, not at call instants) and clamped to 4 frames so a
-- stall never fast-forwards the game. fixed_dt=true restores exact
-- one-call-one-frame stepping for the deterministic headless test probes.
local last_ms,dt_ema,acc=nil,nil,0
local blip1_wait=0 -- TIC() frames until the bite pair's BLIP1 plays (0 = none pending)
tick_stretch=1 -- logic-tick length multiplier: the demo's longer frames (state_demo.lua)

-- logic ticks per 30 Hz slot from constants.lua, indexed by difficulty;
-- the title, options and demo run at difficulty 0
function game_speed()
 return DIFFICULTY_GAME_SPEED[game_difficulty+1]
end

-- display frames elapsed since the last TIC(), smoothed and clamped (port-only pacer)
local function frame_dt()
 if fixed_dt then return 1 end
 local now=time()
 local dt=1
 if last_ms then
  local raw=(now-last_ms)/(1000/60)
  if raw>4 then raw=4 end
  dt_ema=dt_ema and (dt_ema+0.2*(raw-dt_ema)) or raw
  dt=dt_ema
 end
 last_ms=now
 return dt
end

-- one TIC(): input, fixed 30 Hz logic ticks, SNAKE_BUZZ, then draw
-- (the original's MAINLOOP $08FD runs one game frame per pass, frame count FRAMECTR $E4)
function tic_frame()
 poll_input()
 frame=frame+1
 acc=acc+frame_dt()*game_speed()
 while acc>=2*tick_stretch do
  acc=acc-2*tick_stretch
  game_update()
  start_pressed=false
  fire_pressed=false
  back_pressed=false
  menu_pressed=nil
 end
 -- the bite pair's second blip, counted on the audio clock like the SNAKE_BUZZ below
 if blip1_wait>0 then
  blip1_wait=blip1_wait-1
  if blip1_wait==0 then snd("blip1") end
 end
 -- SNAKE_BUZZ: one original ~50 ms sound frame every SNAKE_BUZZ_FRAME_TICS
 -- TIC() calls. TIC-80 advances sfx durations/envelopes and music once per
 -- TIC() (tic_core_sound_tick_start) and the audio thread only plays back
 -- those per-frame snapshots, so the frame count IS the audio clock: counting
 -- it here keeps the gap in lockstep with the 45-frame burst even when the
 -- frame rate dips (a wall-clock or 30 Hz-logic stepper drifts against it).
 if game_state=="PLAY" and not player.dead and snake_buzz_enabled~=false then
  -- audio-frame divider for SFX.MOVE $B1C9, sped up by SNAKE_BUZZ_SPEED
  snake_buzz_tics=(snake_buzz_tics or 0)+SNAKE_BUZZ_SPEED
  while snake_buzz_tics>=SNAKE_BUZZ_FRAME_TICS do
   snake_buzz_tics=snake_buzz_tics-SNAKE_BUZZ_FRAME_TICS
   step_snake_buzz()
  end
 end
 game_draw()
end

-- game sound effects: slot, duration in 60hz frames; all on channel 3
-- (the tracker jingles use channel 0 only). "death" is a music track.
local SND={
 devour={SFX_DEVOUR,20}, -- rising 20 Hz burst chirp (~320 ms): enemy eaten head-on or killed by a bite, frog eaten by any snake (SFX.EATEN = 7) (SFX.EATCHIRP $B119, PER $B169)
 crunch={SFX_CRUNCH,14}, -- two-tone consume warble (~210 ms): every egg eaten (by a snake or the frog) or hatched; burst table, wave 3 (SFX.WARBLE $B181, PER $B1C3; tools/egg_crack.md)
 hop={SFX_HOP,24},    -- frog-hop click run, 7 cracks over ~350 ms ending on the hop; burst table, waves 4/5 (SFX.FROGHOP $B0D5, PER $B111; tools/frog_hop.md)
 hurt={SFX_HURT,2},    -- enemy-bites-player thud (single ~15 ms note) (SFX.BITE $AF65)
 blip1={SFX_BLIP1,2},   -- second half of the player-bite pair (single ~15 ms note) (SFX.BLIP1 $AF5B, PENDSFX $D9=1)
 blip2={SFX_BLIP2,2},   -- first half of the player-bite pair (single ~15 ms note) (SFX.BLIP2 $AF60, PENDSFX $D9=2)
 tally={SFX_BLIP2,2},   -- level-bonus count blip, BLIP2's slot on the rising scale (state_bonus.lua)
}

-- play a named game sound on channel 3; "death" starts the death-sweep track
-- (DEATHSWEEP $19F4 runs through the note bank $9612-$9697); "bite" is the
-- pair a surviving player bite queues with PENDSFX $D9 = 2: BLIP2 on the next
-- frame, BLIP1 the frame after ($0987-$0998). The demo is silent (speaker
-- port patched away at $1ABD, sequencers gated on ATTRACTFL $D6). note
-- (optional) replaces the slot's stored pitch
function snd(name,note)
 if attract then return end
 if name=="death" then
  music(2,0,0,false)
  return
 end
 if name=="bite" then
  name="blip2"
  blip1_wait=SNAKE_BUZZ_FRAME_TICS -- one original ~50 ms frame later
 end
 local s=SND[name]
 if s then
  -- note=nil plays the slot's stored note; -1 would override it with
  -- ~16 Hz sub-audio (TIC-80 treats any integer as a real note index)
  sfx(s[1],note,s[2],3)
 end
end

game_difficulty=0 -- the difficulty this game plays at (records.lua's, latched; the demo plays BEGINNER)

-- the enemy level every difficulty formula reads: the real level,
-- shifted so level 1 plays at DIFFICULTY_START_LEVEL[game_difficulty+1]
function difficulty_level()
 return level-1+DIFFICULTY_START_LEVEL[game_difficulty+1]
end

-- reset score, level and lives and stage level 1 (STARTGAME $87B5); a demo
-- run (state_demo.lua) enters at $8829 instead, past the score and level
-- resets, so it keeps the level of the game before it
function start_game(demo_run)
 if demo_run then
  score=score or 0
  level=level or DEMO_BOOT_LEVEL
  game_difficulty=0
 else
  score=0 -- packed BCD SCORE.HI/MD/LO $B8/$B9/$BA, cleared at CLEARSCORE $87C5
  level=1 -- LEVEL $BE, LDA #$01 at SETLEVEL1 $880F
  game_difficulty=difficulty
 end
 current_level=(level-1)%MAZE_COUNT+1
 player_lives=PLAYER_LIVES -- LIVES $D8
 -- carry_len: player length saved at a wave clear ($A3), consumed by the
 -- next pregame_init; enemy_start_len: pen length for this wave
 carry_len=nil -- CARRYLEN $A3, zeroed at game start ($8878)
 enemy_start_len=ENEMY_START_LEN -- 5 preset at $885F-$886E
 -- the enemies' chase chance out of 16, CHASEPROB $BD: COLDSTART $0803 keeps
 -- a 4-bit roll of 4 or 5, else 6 ($0803-$0811)
 local r=math.random(0,15)
 chase_prob=(r==4 or r==5) and r or 6
 -- a harder mode starts with the ramp already run up to its start level
 for l=level+1,difficulty_level() do chase_step(l) end
 game_time=0 -- seconds of play (drives egg/frog timers and the mouth flicker)
 init_grid()
 init_doors() -- every pen door shut (S.B237 $B237 at $8816)
 snake_pen_reset() -- the pen starts empty; pregame fills it after the jingle
 pregame_fill=true
 -- the title has no maze behind it, so pregame shows a blank one --
 -- the outline and both pens, what SCRNWIPE leaves -- until the wipe reveals
 -- level 1 (the original empties the pens over the attract maze, S.B237)
 maze_blank=true
 init_enemies()
 init_frogs()
 init_eggs()
 pregame_init()
end
