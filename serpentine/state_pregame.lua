-- state_pregame.lua
-- game-start intro, in the original's order: the pens are emptied and their
-- doors shut (S.B237 $B237, from $8816) over the maze on screen -- a blank one
-- from the title, the frozen demo board from the demo -- the start jingle
-- plays (jingle $AF6A from $8826), the player pen fills (snake_pen.lua
-- snake_pen_fill, $8829-$8857), then the maze wipe reveals level 1
-- (state_wipe.lua, BUILDMAZE $1CBA via COLDSTART $0803) and round_start hands
-- over to PLAY, where the release clock lets the first enemy in
-- (enemy_pen.lua). Later levels and respawns skip straight to the wipe.

pregame_timer=0 -- seconds in PREGAME
pregame_fill=false -- set by start_game: the pen is empty until snake_pen_fill
pregame_intro=false -- a new game's intro (jingle, pen fill, level-1 wipe) is running; fire skips it

-- stage the player at the launch spot and restart the release clock; the
-- enemy pen starts empty (round init ROUNDINIT $8654: every enemy record back
-- under the bottom door (02,C3) at $0895, launch clock SETINTROCLK $8699)
function pregame_init()
 enemy_pen_reset()
 init_player(PLAYER_DOOR2.cx,PLAYER_DOOR2.cy)
 -- on a new game the active snake is still off screen: it walks in with
 -- the pen fill and takes over at the launch spot
 player.hidden=pregame_fill
 hunger_reset_round() -- FRAMECTR, Z.CC/Z.CA and GRACECTR restart (egg.lua)
 -- the enemies' pace resets only on round init's CARRYLEN $A3 = 0 path
 -- (game start, respawn; $86DC-$8710); the creep's round-robin restarts
 -- with FRAMECTR every round (CYCLERPH $9F = 0 at $0840)
 if not carry_len then
  reset_enemy_pace()
  reset_player_pace()
 end
 pace_phase=0
 -- the carry is used once ($08C1 clears $A3), so a death respawns at 3
 carry_len=nil
end

-- after any wipe: restage the round and play (round init via JMP L.0822 at
-- $1F83, then ROUNDSTART $08C3)
function round_start()
 if attract then demo_round_init() end -- the demo's next maze (ROUNDINIT $8654)
 demo_board=nil -- the wipe has cleared the frozen demo maze (state_demo.lua)
 pregame_intro=false
 pregame_init()
 snake_pen_launch() -- the pen's snake at the launch spot is the player now
 level_banner_show() -- LEVEL n / WRANGLING SNAKES until the snakes are out (state_play.lua)
 game_state="PLAY"
 game_update=play_update
 game_draw=play_draw
end

-- switch to PREGAME and start the level-1 jingle (jingle $AF6A, $88=0, from $8826)
function pregame_enter()
 pregame_timer=0
 pregame_ready=false -- jingle finished
 level_banner_hide() -- nothing left over from a previous game
 game_state="PREGAME"
 game_update=pregame_update
 game_draw=pregame_draw
 -- level-start jingle; gates the pen fill below. The demo enters past it
 -- ($8829), so its pen fills at once
 if not attract then music(0,0,0,false) end
 pregame_intro=not attract
end

-- (the original has no skip): fire cuts a wipe short -- the new game's
-- intro, a death's or a level clear's (state_wipe.lua). The next maze is
-- shown, on_done (round_start) restages the round, and its release script is
-- run ahead, with the first enemy climbing as it would in play, to the tick
-- before its keyframe $54 (84), where the enemy pen's outer door and the
-- player's chute open together (enemy_pen.lua)
function round_skip_start(on_done)
 maze_blank=false
 on_done()
 -- the release clock ticks at most once per play tick, so this stops on 83;
 -- the guard bounds it at twice the ~125 ticks that takes
 local guard=250
 while enemy_pen.clock<83 and not enemy_pen.done and guard>0 do
  enemy_pen_update()
  update_enemies()
  guard=guard-1
 end
end

-- fire during a new game's intro also cuts the jingle and the pen fill
-- short: the pen ops finish at once, then as round_skip_start
function pregame_skip()
 music() -- stop the jingle
 if pregame_fill then
  pregame_fill=false
  snake_pen_fill(player_lives)
 end
 local instant=snake_pen_instant
 snake_pen_instant=true
 snake_pen_update()
 snake_pen_instant=instant
 snake_pen_launch()
 round_skip_start(round_start)
end

-- wait for the jingle, fill the pen, then wipe to level 1 (game start $8826-$887C)
function pregame_update()
 if pregame_intro and fire_pressed then
  pregame_skip()
  return
 end
 pregame_timer=pregame_timer+1/30
 if not pregame_ready then
  -- 0x13FFC is the music-state track byte: music(0) sets it synchronously,
  -- and the engine writes -1 (255) there when the non-looping jingle ends.
  -- The timer is a failsafe so a stuck tune can never wedge the game here.
  pregame_ready=attract or peek(0x13FFC)==255 or pregame_timer>=PREGAME_MAX_SECS
  if pregame_ready and pregame_fill then
   pregame_fill=false
   snake_pen_fill(player_lives)
  end
 end
 snake_pen_update()
 if pregame_ready and not snake_pen_busy() then
  snake_pen_launch()
  player.hidden=false
  -- clear the frozen demo maze if the game started from the demo, else
  -- the blank maze on screen is only revealed: level 1 either way
  wipe_enter(demo_board and demo_board.grid,round_start)
 end
end

-- the board with a WRANGLING SNAKES banner (no such string located in the
-- original). A game started from the demo shows none: the frozen demo board
-- stays as it is, as in the original ($8816-$887C)
function pregame_draw()
 play_draw()
 if attract or demo_board then return end
 local s="WRANGLING SNAKES..."
 local w=print(s,0,-20,TEXT_COLOR,true)
 local x=(240-w)//2
 rect(x-3,54,w+6,11,BLACK)
 print(s,x,56,TEXT_COLOR,true)
end
