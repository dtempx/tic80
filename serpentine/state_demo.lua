-- state_demo.lua
-- DEMO state: the original's attract mode, run while ATTRACTFL $D6 ~= 0. The
-- power-on zero page has the flag set, and every game over sets it again
-- ($1AB7) and restarts at $8829. That entry is past the start jingle ($8826)
-- and the score and level resets (CLEARSCORE $87C5, SETLEVEL1 $880F), so the
-- pen fills in silence and the level carries over. While the flag is set:
--   - the player is steered by the enemy navigator (ENEMYAI $17AB). The chase
--     chance is forced to 15/16 and the hunt flag LONGERFLG $E9 and the target
--     override PHEADCPYY $CE are cleared around the call ($0C73-$0C9F), so it
--     heads for the frog while one is on the board and wanders otherwise
--   - each of those player frames also spends a DELAY $30 ($0C77), which slows
--     the whole main loop, enemies included
--   - every round init moves on a maze, wrapping 6 -> 1 ($865C-$8666)
--   - sound is off: the note bank is pointed at the cassette port ($1ABD) and
--     every sequencer returns early on the flag (SFX.FROGHOP $B0D5,
--     SFX.EATCHIRP $B119, SFX.WARBLE $B181, SFX.MOVE $B1C9). The clear tune
--     still takes its time
--   - the frog's hop delay counts down before the pen is empty ($8DC9)
--   - the score and level are not drawn ($82E8, $19ED, $9EEF); the header
--     cycles two message panels instead (ATTRACTTXT $9590, ATTRACTTX2 $95A2).
--     the panels are left out; the port shows the level and nonzero HISCORE digits
--     in the top corners using the gameplay status style
--   - 'K' or joystick button 0 starts a game (STARTGAME $87B5, $091B-$0938).
--     Nothing on page 1 is cleared first: the demo board freezes where it
--     is, the frog is erased (FROGERASE $87B8), S.B237 ($8816) shuts the pen
--     doors and blanks both pens, the start jingle plays ($8826), the pen
--     fills ($8829), and the wipe clears the demo maze -- snakes and all --
--     and reveals level 1 (BUILDMAZE via COLDSTART). The port keeps that
--     frozen board in demo_board until the wipe is over (round_start)
-- The demo reuses the play states (PREGAME, WIPE, PLAY, CLEARED, GOHOME,
-- HATCH) as an inner state machine. DEMO keeps the running one in `demo`,
-- calls it under its own label so their game_state checks still hold, and
-- takes over again whenever one of them switches state.
-- a demo game over returns to the title, which starts the next demo
-- after DEMO_WAIT_SECS; the original restarts the demo at once ($1AC0).

attract=false -- ATTRACTFL $D6: read by the play modules while the demo runs
demo={} -- the inner state: update, draw and label
demo_board=nil -- the frozen demo maze a new game starts over, until its wipe ends

-- the demo's play frames are longer by one DELAY $30 ($0C77); logic ticks
-- are stretched by the same ratio (game_state.lua tick_stretch)
local DEMO_STRETCH=1+orig_delay_secs(DEMO_DELAY_A)/ORIG_FRAME_SECS

-- the autopilot, the player's navigator in the demo ($0C73-$0C9F): no hunt
-- (LONGERFLG $E9 = 0) and no target override (PHEADCPYY $CE = 0), so the
-- target is the frog while it is on the board ($182B), else a random exit
function demo_decide(p)
 if not p.is_released then return p.dir end -- the launch goes UP (INTROCLK $D7, $0C62)
 local tx,ty
 if frog.active then tx,ty=frog_orig_xy() end
 return ai_navigate(p,tx,ty,DEMO_CHASE)
end

-- the demo's round init: the next maze (INC LEVEL, wrap at 6, $865C-$8666).
-- The maze on screen was built from the old level, so the new one shows at
-- the next wipe: a death moves on one maze, a clear (INC $BE at $0958 too) two.
function demo_round_init()
 level=level+1
 if level>=DEMO_LEVEL_WRAP then level=1 end
 current_level=(level-1)%MAZE_COUNT+1
end

-- the inner state now in game_update/game_draw/game_state becomes demo's,
-- and DEMO takes the dispatch back
local function adopt()
 demo.update,demo.draw,demo.label=game_update,game_draw,game_state
 game_state="DEMO"
 game_update=demo_update
 game_draw=demo_draw
end

-- start the demo from the title (the $8829 restart: pen fill, then
-- COLDSTART $0803 and the wipe to the first maze)
function demo_init()
 attract=true
 start_game(true)
 pregame_enter() -- silent, no jingle wait, no GET READY! banner
 adopt()
end

-- leave the demo: sound and full-speed ticks back
local function demo_stop()
 attract=false
 tick_stretch=1
end

-- keep what page 1 shows of the demo: its maze and dropped eggs (the frog is
-- erased at $87B8). Its snakes go at once, the moment a game starts.
-- start_game replaces these tables, so the old ones stay frozen as they are
local function freeze_board()
 local eggs={}
 for _,e in ipairs({player_egg,enemy_egg}) do
  if e and e.active and e.dropped then
   table.insert(eggs,{x=e.x,y=e.y,is_player=(e==player_egg)})
  end
 end
 return {grid=grid,eggs=eggs}
end

-- the frozen demo board: its maze, then its eggs everywhere but
-- the two pens, which S.B237 blanked -- drawn only within the wipe's bands,
-- and right of the wipe's reveal line rx (0 = the whole screen)
function draw_demo_board(rx)
 rx=rx or 0
 draw_grid(demo_board.grid)
 wipe_bands(240,function(x,y,w,h)
  local x0=math.max(x,rx)
  if x+w<=x0 then return end
  clip(x0,y,x+w-x0,h)
  for _,e in ipairs(demo_board.eggs) do draw_egg_shape(e.x,e.y,e.is_player) end
 end)
 clip()
end

function demo_update()
 if back_pressed then -- B leaves the demo for the title
  demo_stop()
  title_init()
  return
 end
 if start_pressed then
  demo_board=freeze_board()
  demo_stop()
  start_game()   -- STARTGAME $87B5 from the attract branch
  pregame_enter()
  return
 end

 game_state=demo.label
 demo.update()
 if game_state=="GAMEOVER" then
  demo_stop()
  title_init() -- see the header
  return
 end
 if game_update~=demo_update then adopt() end

 -- the delay runs in the main loop only, not in the scripted walks, the
 -- wipe or the death sweep
 local live=demo.label=="PLAY" and not player.dead
 tick_stretch=(live and player.is_released) and DEMO_STRETCH or 1
 game_state="DEMO"
end

function demo_draw()
 game_state=demo.label
 demo.draw()
 game_state="DEMO"
end
