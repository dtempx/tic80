-- state_cleared.lua
-- the death restage (CLEARED state), and advance_level(), the maze change
-- that ends a level clear (state_bonus.lua's level_done calls it)

cleared_timer=0 -- seconds into the restage

-- freeze the board and start the pen shuffle after a death (skip_level is
-- always true: a level clear goes home instead, state_gohome.lua)
-- (death: pen shuffle $1AC3-$1AE2)
function cleared_init(skip_level)
 cleared_timer=0
 cleared_skip=skip_level -- true = respawn after a death, same maze
 level_banner.respawn=true -- the round-start box counts the snakes left (state_play.lua)

 -- freeze the board
 if not player.dead then
  player.moving=false
 end

 -- survivors keep their records and lengths on the respawn path ($8701),
 -- and the records not yet let in still wait; the pen lets them in by
 -- record number, skipping the dead (PENRELEASE $89A9)
 respawn_queue={}
 for _,e in ipairs(enemies) do
  e.moving=false
  if not e.dead then
   table.insert(respawn_queue,{slot=e.slot,len=e.length})
  end
 end
 for _,q in ipairs(enemy_queue) do table.insert(respawn_queue,q) end
 table.sort(respawn_queue,function(a,b) return a.slot<b.slot end)

 -- a respawn restages the same maze with the surviving quota
 next_target_enemies=#respawn_queue

 -- after the death beat the pen queue moves up ($1AC3-$1AE2); the restage
 -- waits for it (player_lives already counts the loss, so it is the
 -- original's LIVES $D8 at $1A71)
 snake_pen_shuffle(player_lives)
end

-- wait for the shuffle, then wipe back to the same maze and relaunch
-- (JMP BUILDMAZE $1AEE; a dropped player egg rides it out, DEATHFLG $99 = 1
-- at PLAYERDIE $19E3 skips the hatch, and round init clears it again, $8697)
function cleared_update()
 cleared_timer=cleared_timer+1/30
 snake_pen_update()
 if not snake_pen_busy() then
  local old=grid -- the maze on screen; load_maze builds a fresh table
  init_grid()
  init_doors()
  init_enemies(next_target_enemies,respawn_queue) -- survivors keep their lengths
  init_frogs()
  init_eggs(true) -- a dropped player egg survives the respawn
  wipe_enter(old,round_start) -- BUILDMAZE $1CBA: same maze back
 end
end

-- the frozen board during the shuffle
function cleared_draw()
 play_draw()
end

-- one level of the difficulty ramp (CLEARSEQ $9F14-$9F2A), for reaching
-- level l: the chase chance rises by one each level up to 7, then by one
-- every 4th level, to CHASE_CAP (13/16)
function chase_step(l)
 if chase_prob<7 or l%4==0 then
  chase_prob=math.min(chase_prob+1,CHASE_CAP)
 end
end

-- after a level clear: build the next maze and wipe to it (INC $BE at $0958,
-- CARRYLEN $9F02, then BUILDMAZE $1CBA via $1AE5/$1CB8)
function advance_level()
 local old=grid -- the maze on screen
 -- the player keeps its whole length into the next wave ($9F02);
 -- the fresh pen is always 7 long whatever the player carries ($86E5)
 carry_len=player.length
 enemy_start_len=ENEMY_LEVEL_LEN
 level=level+1
 chase_step(difficulty_level())
 current_level=(level-1)%MAZE_COUNT+1
 init_grid()
 init_doors()
 init_enemies()
 init_frogs()
 init_eggs(true) -- a dropped player egg survives (only if it did not hatch)
 wipe_enter(old,round_start)
end
