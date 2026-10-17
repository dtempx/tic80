-- constants.lua
-- every tuned constant, one name=value per line (tools/sim.py parses these)
-- reference: serp/src (B); geometry rescaled per design.md section 1
-- Addresses are the original's (games/serpentine/disasm/). Where the port
-- chose a value and the original works differently, the comment cites the
-- original's site.

-- Full-height evaluation: 18x12 cells fit the entire maze on 240x136.
-- Original 21x16 cells span 273x176, exceeding the screen in both axes.
MAZE_COLUMNS=13 -- 13 cell columns, builder geometry (MAZEBUILD $A0A6-$A119)
MAZE_ROWS=11 -- 11 cell rows: block = 11 rows x 16-byte stride (MAZELOAD $A39C)
MAZE_COUNT=20 -- level reduced mod 20 by repeated SBC #$14 ($A39E-$A3A5)
MAZES_PER_ROW=10 -- <MAP> layout, maze slots filled left to right, top to bottom
MAZE_PITCH_X=15 -- 14-tile bay (13 cells + right-wall column) + 1 blank column
MAZE_PITCH_Y=13 -- 12-tile bay (11 cells + bottom-wall row) + 1 blank row

-- one-way-up passages {level={{x,y},...}}: the cell's top edge is open going
-- up and a wall coming down. The map draws them as plain top walls, as the
-- game does; maze 14's asymmetric edges (disasm README 2.1). Keep in step
-- with ONE_WAY_CELLS in tools/build.py.
ONE_WAY_UP={[14]={{4,9},{5,9},{9,9},{10,9}}}
CELL_W=18 -- rescale of the 21 px (3 HGR byte) cell ($A0A6-$A119)
CELL_H=12 -- rescale of the 16 px cell row ($A0A6-$A119)
OFFSET_X=3 -- maze's left wall line; walls are 3 px wide, so the maze covers x 2..238 (2 px free left, 1 right)
OFFSET_Y=2 -- maze's top wall line; walls are 2 px tall, so the floor lands on the screen's last rows 134..135

-- movement (px per 30hz logic tick, uniform in both axes; logic runs on even
-- TIC frames). 1.413 = 3.16 cells/s (the pico-port playtest calibration) on
-- the 13.42px geometric-mean cell -- cell-unit speeds were rejected in the
-- playtest (18x10 cells made horizontal px motion 1.8x vertical)
PLAYER_SPEED=1.413 -- calibration; original: 2 px steps (STEPDELTA $0E55) paced by governor $90/$91 ($871D)
CHASE_CAP=13 -- CHASEPROB $BD ceiling ($9F24-$9F2A); enemy speed is enemy_speed(e) in enemy.lua (EPACETHR ramp and creep)
SEGMENT_DIST=7 -- centre-to-centre spacing in pixels; original trails 4 steps = 8 px (FIFO lag $0E88-$0EA3)
SEG_R=3 -- segment ball radius: 7px balls in 12px corridors
HIT_CELLS=0.53 -- collision radius in cell units (B: 5px on 9.5px cells); original same-row + window (PROXCHECK $1718)
EAT_PX=1.5 -- egg pickup: the head's path must pass within this many px of the egg's centre (snake.lua head_over)

-- lifecycle (seconds; tick timers are these x30)
MAX_ENEMIES=3 -- three enemy records $6480/$6500/$6580, recycled forever
ENEMY_START_LEN=5 -- level 1 only: game start presets 5 ($8861), kept via $8701
ENEMY_LEVEL_LEN=7 -- every later wave ($86E5); never scales with the player
PLAYER_START_LEN=3 -- also the length after any death ($0877)
MAX_LEN=7 -- no snake grows past 7 ($09F7/$0AB6/$0B5D/$0C07 CMP #$07)
BITE_COOLDOWN=6 -- logic ticks between one enemy's bites: 4 frames x ~50 ms (LDA #$04/STA $E1 $157F, DEC per frame $099A)
PLAYER_BITE_COOLDOWN=3 -- logic ticks between the player's bites: 2 frames x ~50 ms (PENDSFX $D9 = 2 at $1385, DEC per frame $0998, gate $12BE)
SNAKE_PEN_STEP_SECS=0.05 -- player-pen walk step: NOTE.SILENT $9612 (21 x NOTEDELAY $F0)
SNAKE_PEN_GAP=2 -- px between the launch snake's body and slot 1's head; original slot 1 (FF,A5) sits 20 px under launch (FF,91), a 4 px gap (S.8B3F $8B3F)
SNAKE_PEN_DIGIT_DX=-6 -- px nudge of the pen's lives digit from its computed spot (snake_pen.lua digit_x); negative moves it left
ENEMY_PEN_TICK_SECS=0.05 -- release clock tick: one original main-loop frame (RELCLOCK $AE, INC at PENDISPATCH $897A)
ORIG_FRAME_SECS=0.05 -- one original main-loop frame (FRAMECTR $E4, INC $093B), the hunger clock's tick
GRACE_START=4 -- GRACECTR $CB at round init (LDA #$04/STA $CB, $86D8); drops each FRAMECTR wrap ($093F)
HUNGER_TICKS=48 -- player ticks per tail-bulge stage: Z.CC $CC counts to $30 (S.84E6 $84F2)
APPLE_HZ=1020484 -- 6502 clock, for the step timings derived from DELAY $AF4F cycle counts
STEP_PX=1.464 -- one 2 px HGR step (STEPDELTA $0E55) x 13.42/18.33, the port/original cell ratio
GOHOME_JS_START=100 -- go-home step DELAY: JINGLE.SEL $88 = $64 at $9CE0, -1 every 10 steps ($9DF3)
GOHOME_JS_MIN=64 -- ... down to $40 ($9DFB)
GOHOME_STEP_CYCLES=6000 -- estimate of a go-home step's work besides DELAY (S.0E5F, FROGDRIVE, S.856A)
GOHOME_MAX_SECS=60 -- failsafe: the original steers home with no time limit (GOHOME $9CB0)
HATCH_JS_START=120 -- hatched-snake step DELAY: $78 at $1B03, -1 every 6 steps ($1C1F-$1C27)
HATCH_STEP_CYCLES=2500 -- estimate of a hatched-snake step's work besides DELAY (2-segment S.0E5F)
PREGAME_MAX_SECS=6.0 -- failsafe cap on the start-jingle wait (jingle $AF6A from $8826)
WIPE_CLEAR_SECS=1.19 -- maze clear, top to bottom: 174 rows x (DELAY $30 + row) ~6.8 ms (SCRNWIPE $1D3C, cycle count)
WIPE_PAUSE_SECS=0.33 -- two DELAY $FF between clear and reveal ($1DB5-$1DBC, cycle count)
WIPE_REVEAL_SECS=2.16 -- next maze, left to right: 280 pixel columns x ~7.7 ms incl. DELAY $07 ($1E02-$1F53, cycle count)
GAMEOVER_SECS=8 -- game-over freeze; original goes to hi-score check ($1A71/$1A8D)

-- attract demo (state_demo.lua; ATTRACTFL $D6)
DEMO_WAIT_SECS=8.0 -- title hold before the demo starts; the original shows its title only while booting
DEMO_BOOT_LEVEL=2 -- LEVEL $BE in the power-on zero-page snapshot, the first demo's maze
DEMO_LEVEL_WRAP=6 -- every demo round init moves on a level, back to 1 at 6 (CMP #$06, $865C-$8666)
DEMO_CHASE=15 -- the autopilot's chase chance out of 16 (LDA #$0F/STA CHASEPROB, $0C8A)
DEMO_DELAY_A=48 -- DELAY $30 spent on every demo player frame ($0C77), slowing the whole loop
DEMO_CLEAR_TUNE_SECS=0.87 -- the muted clear tune still takes its time ($9CDD): track 1 = 52 TIC frames, measured headless
EGG_SPAWN_DURATION=5.0 -- (B) tail-bulge time; original delay $93=$30 + 4x$20 pulses (EGGLAY $AD5E)
EGG_SPAWN_DELAY=60.0 -- (B) lay cooldown; original checks once per 256 frames at $E4==$77 (EGGTRIGGER $ACC9)

-- egg hatch gestation, in original 20Hz ticks (ORIG_FRAME_SECS): level<$13(19)
-- -> $A8-(level<<3) wrapped as a byte, i.e. 167-level*8 (CMP #$13/BCC $ADA4,
-- ASL x3/EOR #$FF/ADC #$A8 $ADA7-$ADAE); level>=19 leaves the default set at
-- $AD9C untouched, i.e. 16 (see egg_hatch_ticks() below)
EGG_HATCH_TICKS_BASE=167 -- $A7, the level-0 intercept of 167-level*8
EGG_HATCH_TICKS_STEP=8 -- per level
EGG_HATCH_TICKS_MIN_LEVEL=19 -- CMP #$13: at and above this level the ramp does not apply
EGG_HATCH_TICKS_DEFAULT=16 -- $10, set at $AD9C and left alone once level>=19

SCORE_ROLLOVER=1000000 -- the original's 6-digit BCD display wrap ($B8/$B9/$BA, DRAWSCORE $82E8)

-- status line in the small font (3x5 glyphs, 4 px pitch): "LEVEL n" in
-- the screen's top-left corner and 6 score digits (23 px wide) in its top-right,
-- white on a wall-coloured panel with 1 px padding all round (rows 0..6), flush with the
-- screen edges, covering the maze wall and any sprite under it
-- (state_play.lua draw_status)
LEVEL_X=1 -- "LEVEL n" from x 1; its panel starts at the screen's left edge
LEVEL_Y=1 -- rows 1..5
SCORE_X=216 -- digits on x 216..238; panel x 215..239, flush with the right edge
SCORE_Y=1 -- digits on rows 1..5

-- persistent memory, pmem() slots (the cart's saveid keeps them across edits)
PMEM_HISCORE=0 -- best score of any finished game
PMEM_DIFFICULTY=1 -- 0 beginner, 1 advanced, 2 expert (options page)
PMEM_THEME=2 -- theme (THEME_NAMES): 0 colour, 1 green, 2 white Apple II monitor
PMEM_HILEVEL=3 -- highest level reached in any finished game
PMEM_SNAKE_BUZZ_OFF=4 -- 0 SNAKE_BUZZ on (default), 1 off

-- title-screen records (state_title.lua draw_records)
RECORDS_COLOR=4 -- blue, the player snake's colour (mono forces print() to solid white, so never striped)

-- display themes, indexed by theme+1 (PMEM_THEME). Themes 0..THEME_A2_LAST
-- are the Apple II monitors (a2boot.lua: the boot intro plus mono mode 0
-- colour / 1 green / 2 white); later themes don't run any a2boot code
THEME_NAMES={"APPLE II - COLOR","APPLE II - GREEN","APPLE II - B&W"}
THEME_A2_LAST=2

-- options page (state_options.lua). The difficulty is latched at game start
-- (game_difficulty, game_state.lua); BEGINNER plays as the original. The code
-- calls the modes BEGINNER, ADVANCED and EXPERT; these are display names only
DIFFICULTY_NAMES={"BOOMER","GEN-Y","ZOOMER"}

-- level-clear bonus (state_bonus.lua): points per level cleared so far,
-- counted up BONUS_PT_INCR points per blip. Kept small next to a level's own
-- scoring (bites 100 x m, head-on kills 200 x m x length), so harder modes earn
-- a little extra without swamping BEGINNER's high scores
DIFFICULTY_BONUS={0,500,1000}

DIFFICULTY_GAME_SPEED={1.3,1.5,1.6} -- logic ticks per 30 Hz slot; scales movement and timers, not SNAKE_BUZZ (game_state.lua tic_frame)

-- Each ramp levels off at a different point, and enemy speed never stops rising:
-- Level Enemy speed (round start)  Chase chance  Egg hatch
-- 1     50%                        6/16          7.95 s
-- 8     75%                        9             5.15 s
-- 12    80%                        10            3.55 s
-- 19    83%                        11            0.80 s (floor)
-- 24    87.5%                      13 (cap)      0.80 s

-- The enemy level that level 1 plays at, indexed by game_difficulty+1
-- (BEGINNER plays at the real level), rising one per level from there. Every
-- difficulty formula reads it as difficulty_level() (enemy pacing, chase
-- chance, egg gestation, frog wait); the maze, the LEVEL display and scoring
-- keep the real level
DIFFICULTY_START_LEVEL={1,7,18} -- BEGINNER, ADVANCED, EXPERT

BONUS_WAIT_SECS=0.5 -- panel up, before the count starts
BONUS_TICK_DELAY=2 -- 30 Hz logic ticks between count blips; larger is slower
BONUS_PT_INCR=25 -- points awarded per bonus blip; positive integer
BONUS_HOLD_SECS=8 -- the final total stays up this long
BONUS_NOTE=57 -- A-4, the blip slot's stored note (SFX.BLIP2 $AF60, sfx 6)
BONUS_NOTES={0,2,4,7,9,12,14,16,19,21,24} -- semitones over BONUS_NOTE: spread this rising scale over the full count; longer bonuses repeat notes without descending or pausing
OPTIONS_ROW_Y=38 -- first menu row's y
OPTIONS_ROW_DY=14 -- px between menu rows
OPTIONS_LABEL_X=24 -- menu labels' x; the cursor sits 8 px left of it
OPTIONS_VALUE_X=132 -- values' x, clear of the widest label (RESET HISCORE)
OPTIONS_DISABLED_COLOR=11 -- a row with nothing to do (RESET HISCORE with no record): the #404040 logo grey

-- sound-effect slots in main.lua's SFX editor (README.md audio table)
SNAKE_BUZZ=0 -- movement click train (SFX.MOVE $B1C9)
SFX_DEVOUR=1 -- enemy or frog eaten chirp (SFX.EATCHIRP $B119)
SFX_CRUNCH=2 -- egg consumed or hatched warble (SFX.WARBLE $B181)
SFX_HOP=3 -- frog pre-hop click run (SFX.FROGHOP $B0D5)
SFX_HURT=4 -- enemy bites player thud (SFX.BITE $AF65)
SFX_BLIP1=5 -- second blip of a surviving player bite (SFX.BLIP1 $AF5B)
SFX_BLIP2=6 -- first player-bite blip; also the level-bonus tally (SFX.BLIP2 $AF60)
SFX_HATCH=7 -- unused port-authored egg-hatch pop; hatches use SFX_CRUNCH

-- SNAKE_BUZZ: retain the preferred port burst/gap approximation of
-- SFX.MOVE $B1C9. Progression shortens its pauses without changing the instrument.
SNAKE_BUZZ_SPEED=3 -- existing burst/gap clock and duration scale; stored SFX pitch is preserved
SNAKE_BUZZ_TEMPO_PER_LEVEL=0.04 -- added pause-speed multiplier per completed level (port-only)
SNAKE_BUZZ_TEMPO_PER_DIFFICULTY=0.15 -- ADVANCED starts at 1.15x pause speed, EXPERT at 1.30x
SNAKE_BUZZ_TEMPO_CAP=1.75 -- room for every difficulty to ramp further; bursts keep their previous sound
SNAKE_BUZZ_FRAME_TICS=3 -- TIC frames per original ~50 ms game frame (audio clock)
SNAKE_BUZZ_BURST=15 -- click frames per burst: LDA #$0F / STA $8E ($B212)
SNAKE_BUZZ_BURST_FRAMES=45 -- sfx duration, TIC frames = 15 clicks (SNAKE_BUZZ_BURST*SNAKE_BUZZ_FRAME_TICS)
SNAKE_BUZZ_GAP_BASE=5 --silent frames added to round(sum/2): ADC #$84 counts $84..$80 ($B209)
SNAKE_BUZZ_CHANNEL=2 -- dedicated sfx channel (3 = other game sfx, 0 = jingles)

-- sprite slots (SPRITES bank; art + slot map live in tools/build.py, all of it
-- transcribed from the original's shape tables $B025/$B049, $B065, $82B8)
SPRITE_BODY=256 -- +stage*4+dir: plain, then egg-bulge stages 1-3 (codes 0-3, 8-19; SHAPEPTRLO $B025)
SPRITE_HEAD=272 -- +dir, mouth closed (orig codes 4-7; SHAPEPTRLO $B025)
SPRITE_HEAD_OPEN=276 -- +dir, mouth open (orig 24-27, the EOR #$1C variant at $ABC2)
SPRITE_SHRIVEL=280 -- +0..2 death shrivel frames (orig codes 21-23, painted by DEATHSWEEP $19F4)
SPRITE_EGG_PLAYER=283 -- egg glyph (EGGGLYPHS $B065)
SPRITE_EGG_ENEMY=284 -- egg glyph, orange-spotted (EGGGLYPHS $B065, hi-bit rows)
SPRITE_FROG=288 -- 2x2 tiles, +dir*2 (right-facing bitmap $81B5; left $80B9, up/down $82B8)
SPRITE_LOGO=320 -- title logo left 128 px, 16x3 tiles (rendered by tools/logo.py; not in the cracked image)
SPRITE_LOGO_RIGHT=368 -- title logo right 64 px, 8x3 tiles
LOGO_W=192 -- title logo strip, px
LOGO_H=24

-- title screen studded frame, the maze's 234x132 outline (the original's is static)
TITLE_STUD_SPACING=12 -- px between studs along the frame; must divide the 732 px perimeter (61 studs) so the march wraps seamlessly
TITLE_MARCH_SPEED=1 -- px the studs advance per 30 Hz logic tick (counter-clockwise: up the right side)

-- palette indices (design.md section 2: measured Apple II HGR colors)
BLACK=0
WHITE=1
VIOLET=2
GREEN=3 -- the $E9=$00 colour group: frog and shorter-than-player enemies (SETPALETTE $10D7)
BLUE=4 -- the $E9=$80 group: player snake (always $80, $10ED)
ORANGE=5 -- the $E9=$80 group: enemy at least as long as the player (SETPALETTE $10D7)
DIM_WHITE=6

-- 11 (#404040) and 12 (#c0c0c0) are the title logo's antialiasing greys
YELLOW=13 -- #ffff00, not an Apple II HGR colour; unused since NEW HISCORE! went blue (RECORDS_COLOR)
SHADOW=14 -- #333333, checkered with black in the drop shadow under the round-start and level-bonus boxes (colour monitor only)
SHADOW_DROP=4 -- px a box's drop shadow is offset right and down (drop_shadow, state_play.lua)
PINK=15 -- #ff69b4, not an Apple II HGR colour; unused since the round-start box's LEVEL n line went WALL_COLOR (2026-10-02)
WALL_COLOR=2 -- maze walls, painted violet by the builder (MAZEBUILD $A09F)
TEXT_COLOR=1

-- Palette indices shared by draw calls and preview carts. Slot names stay
-- valid when a display theme changes the RGB values of a palette bank.
COLOR_SLOT_7=7 -- palette slot 7
COLOR_SLOT_8=8 -- palette slot 8
COLOR_SLOT_9=9 -- palette slot 9
COLOR_SLOT_10=10 -- palette slot 10
COLOR_SLOT_11=11 -- palette slot 11
COLOR_SLOT_12=12 -- palette slot 12
COLORKEY_NONE=-1 -- draw every palette color (no transparent key)
PALETTE_COLORS={BLACK,WHITE,VIOLET,GREEN,BLUE,ORANGE,DIM_WHITE,COLOR_SLOT_7,COLOR_SLOT_8,COLOR_SLOT_9,COLOR_SLOT_10,COLOR_SLOT_11,COLOR_SLOT_12,YELLOW,SHADOW,PINK} -- index by palette id + 1

-- Apple II intro sprite strip (shared with the asset editors).
SPRITE_BOOT_AT=504 -- inverse @ glyph
SPRITE_BOOT_TITLE=505 -- seven cells spelling APPLE ][
BOOT_DRIVE_BASE=0x0EC00 -- Disk II sample bytes in MAP; game-owned allocation
BOOT_DRIVE_LENGTH=4927 -- standard drive recording byte span
BOOT_DRIVE_MIDPOINT=118 -- silence level of the authored drive samples
