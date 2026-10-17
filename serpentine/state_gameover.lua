-- state_gameover.lua
-- freeze, wipe the maze, GAME OVER on the cleared screen, then back to the title

gameover_timer=0 -- seconds shown
gameover_new_hi=false -- this game set a new high score (never in a demo)

-- freeze every snake for the GAME OVER hold (entered when lives run out, $1A71);
-- a real game's score and level go to the records (records.lua; the
-- original's hi-score check is $1A8D), a demo's do not
function gameover_init()
 gameover_timer=0
 gameover_new_hi=not attract and records_game_over(score,level)
 -- every pen door shut for the wipe, whatever the release script had open
 init_doors()

 if not player.dead then
  player.moving=false
 end
 for _,e in ipairs(enemies) do
  e.moving=false
 end
end

-- hold, then back to the title (the original runs initials entry
-- ENTERINIT $B614, cut). Not BOOT(): that would replay the Apple II intro
function gameover_update()
 gameover_timer=gameover_timer+1/30

 if gameover_timer>=GAMEOVER_SECS then
  title_init()
 end
end

-- (string not located in the original): the frozen maze, its snakes
-- already gone, is wiped clear inside its outer walls, top to bottom, exactly
-- as between levels (wipe_mask, SCRNWIPE $1D3C, at WIPE_CLEAR_SECS; the
-- outline and both pens stay), then GAME OVER in the maze walls' colour,
-- centred on the screen, and after a new high score NEW HISCORE! in the records' blue on
-- the next line
function gameover_draw()
 -- play_draw without the snakes
 cls(BLACK)
 draw_grid()
 draw_frogs()
 draw_eggs()
 draw_player_reserves()
 local bot=OFFSET_Y+MAZE_ROWS*CELL_H
 wipe_mask(OFFSET_Y+(bot-OFFSET_Y)*math.min(gameover_timer/WIPE_CLEAR_SECS,1))
 draw_status() -- back on top of the wiped maze
 if gameover_timer<WIPE_CLEAR_SECS then return end
 -- 6 px lines at a 10 px pitch (as the round-start box), centred as a block
 local y=gameover_new_hi and 60 or 65
 print_centered("GAME OVER",y,WALL_COLOR)
 -- blinks like the title prompt: real time, 500 ms on / 500 ms off
 if gameover_new_hi and time()//500%2==0 then print_centered("NEW HISCORE!",y+10,RECORDS_COLOR) end
end
