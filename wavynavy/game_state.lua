-- game_state: state transitions + new-game bootstrap (set_state, goto_*, start_game)

-- set the active state: label + init + 60fps handlers
local function set_state(label, init, update, draw)
 game_state = label
 draw_fraction = 1 -- interpolation fraction is per-state; never carry it across
 init()
 game_update = update
 game_draw = draw
end

-- sky-writing title screen
function goto_title()
 set_state("title", title_init, title_update, title_draw)
end

-- attract-mode demo: the game plays itself (drawn by the play renderer)
function goto_demo()
 set_state("demo", demo_init, demo_update, play_draw)
end

-- attract-mode point table
function goto_points()
 set_state("points", page_init, points_update, points_draw)
end

-- attract-mode rank table
function goto_ranks()
 set_state("ranks", page_init, ranks_update, ranks_draw)
end

-- get-ready pause before a wave
function goto_ready()
 set_state("ready", ready_init, ready_update, ready_draw)
end

-- live play, with the fleet armed at once
function goto_play()
 set_state("play", play_init, play_update, play_draw)
 armed = true -- the get-ready press already started the wave
end

-- wave-clear promotion and bonus tally
function goto_clear()
 set_state("clear", clear_init, clear_update, clear_draw)
end

-- game over: save a new hiscore, then the dirge and stats card
function go_gameover()
 if hi > prev_hi then pmem(0, hi) end
 set_state("gameover", gameover_init, gameover_update, gameover_draw)
end

-- waves cleared this run, not counting the ones advanced/expert skip at the
-- start (diff_start_wave); read by the wave bonus and the game-over recap
function waves_cleared()
 return math.max(wave - 1 - diff_start_wave[diff + 1], 0)
end

-- reset score, lives, wave and recap stats for a new run, then get ready
function start_game()
 demo = false
 score = 0
 lives = start_lives + diff_start_lives[diff + 1] -- advanced +1, expert +2
 wave = start_wave + diff_start_wave[diff + 1] -- advanced wave 2, expert wave 3
 sd_plane, sd_heli, sd_bomber, sd_cruise = 0, 0, 0, 0 -- game-over recap stats
 shots_fired, shots_hit = 0, 0
 prev_hi = hi
 goto_ready()
end
