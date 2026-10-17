-- records.lua
-- persistent records and settings in pmem (slot map in constants.lua):
-- the high score and highest level reached, kept at the end of every game,
-- and the options page's difficulty, SNAKE_BUZZ and theme (the Apple II themes set
-- a2boot.lua's mono mode through mono.set). The original's hi-score table ($1A8D, initials entry
-- ENTERINIT $B614) lives on disk and is not ported.

hiscore=0 -- best score of a finished game
hilevel=1 -- highest level reached in a finished game (level 1 until one is played)
difficulty=0 -- 0 beginner, 1 advanced, 2 expert: latched by start_game as game_difficulty
theme=0 -- THEME_NAMES index - 1: 0 Apple II colour, 1 green, 2 white
snake_buzz_enabled=true -- SNAKE_BUZZ enabled; other sounds always play

-- read everything back at power-on (an unwritten slot reads 0)
function records_load()
 hiscore=pmem(PMEM_HISCORE)
 hilevel=math.max(1,pmem(PMEM_HILEVEL))
 difficulty=pmem(PMEM_DIFFICULTY)%#DIFFICULTY_NAMES
 theme_set(pmem(PMEM_THEME))
 set_snake_buzz(pmem(PMEM_SNAKE_BUZZ_OFF)==0)
end

-- a game just ended at this score and level: keep whichever beats the record;
-- true when the score set a new high score
function records_game_over(s,l)
 local new_hi=s>hiscore
 if new_hi then
  hiscore=s
  pmem(PMEM_HISCORE,s)
 end
 if l>hilevel then
  hilevel=l
  pmem(PMEM_HILEVEL,l)
 end
 return new_hi
end

-- wipe the high score and highest level (options page)
function records_reset()
 hiscore,hilevel=0,1
 pmem(PMEM_HISCORE,0)
 pmem(PMEM_HILEVEL,0)
end

-- step the difficulty by d (wraps) and remember it
function set_difficulty(d)
 difficulty=(difficulty+d)%#DIFFICULTY_NAMES
 pmem(PMEM_DIFFICULTY,difficulty)
end

-- remember the buzz preference and stop any movement burst when turned off
function set_snake_buzz(enabled)
 snake_buzz_enabled=enabled
 pmem(PMEM_SNAKE_BUZZ_OFF,enabled and 0 or 1)
 if not enabled then sfx(-1,nil,0,SNAKE_BUZZ_CHANNEL) end
end

-- the theme is an Apple II monitor, so the a2boot intro and mono filter run
function theme_a2() return theme<=THEME_A2_LAST end

-- pick a theme by number (wraps); save=false preserves the preference.
-- An Apple II theme sets the
-- matching mono mode; any other hands the mono palette back once
function theme_set(i, save)
 theme=i%#THEME_NAMES
 if save~=false then pmem(PMEM_THEME,theme) end
 if theme_a2() then
  mono.set(theme)
 elseif mono.mode~=0 then
  mono.set(0)
  mono.off()
 end
end
