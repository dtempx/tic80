-- constants: every tuned gameplay value (sim.py parses the name=value lines),
-- plus the original game's small data tables at the end (launch orders,
-- per-wave config, ranks, difficulty) -- see the banner down there.
-- NOTE: no comment may begin with dash-dash-space-langle: TIC-80's cart parser
-- reads that as an asset chunk tag and truncates the code (ticpak bundle
-- enforces this)

-- Citations: a trailing ($xxxx) is the address in the Apple II original's
-- disassembly (games/wavynavy/disasm/) where that value is defined or written.
-- Lines with no address are port inventions or TIC-80-side values; the ones
-- that replace original behaviour say so.

-- config
LIVES_MAX=20 -- HUD reserve-boat icons drawn at most (5 rows of 4 in the rail). PORT LIMIT: the original prints lives as a text digit and caps the award at 9 (SHIPAWARD $1FC9)
FORM_SECS=8 -- seconds per formation edge-to-edge sweep; original sweeps at FORMDX +-2 px/frame between x=$20 and x=$CA ($16E0, edges $16EF/$16FB)
EXPL_OF=40 -- blast lifetime in oframes; original walks the dot-ring streams to their end instead (BOOM.A $9B00, stepped by $5E68)
RECALL_OFS=282 -- sunk-state ticks (~20s) before snapping the fleet home. PORT INVENTION: the original has no recall watchdog (death path DEATHSEQ $1534)
ENEMY_DY=16 -- min vertical gap (px) kept between enemy planes, both climbing back and diving. PORT REFINEMENT: the original enforces no separation (REJOIN $169C)
DIVE_PUSH=2 -- px/tick a crowded diver is pushed apart to reach yoff_min. PORT REFINEMENT, see ENEMY_DY
LATE_LIVES_WAVE=6 -- first cleared wave that also awards DIFF_WAVE_LIVES (GEN-Y +1, zoomer +2). PORT ADDITION: the original awards only the +1 ship (SHIPAWARD $1FC9)
BONUS_STEP=30 -- frames between reserve-boat awards in the bonus tally. PORT PACING: the original's tally loop is ungated, one +50 and jingle per ship ($141D)
TITLE_VSPEED=0.75 -- title skywriter pace, dive ticks per 60fps frame; paths TITLEPTH1/2 ($8800/$8A00), staged by TITLEANIM ($6BC5)
DEMO_END_SECS=2 -- the attract demo ends this many seconds after its sunk boat's fleet has finished re-forming (the demo boat never respawns). PORT PACING (demo mode DEMOFLG $085D)

-- original data block in the <MAP> region (layout owned by tools/build.py;
-- addresses are peek()ed in place, hex so sim.py ignores them). The value is
-- the TIC-80 destination; the ($xxxx) is the Apple II source the bytes are
-- copied from byte-for-byte -- same pairing as the table above the <MAP> chunk.
TMPL_B=0x08000 -- formation templates (10 waves x 120 B: 40 slots x [x,y,state]) ($4B00+$80*w, TEMPLATES; ptrs WV.TMPLLO $1233)
XPLP_B=0x084b0 -- plane-blast dot frames (8 x 32 B) ($9B00, BOOM.A)
XPLR_B=0x085b0 -- ram-blast dot frames (3 frames, offsets 0/36/74, end 110) ($A900, BOOM.RAM; set by RAMKILL $58A3)
XPLH_B=0x0861e -- heli-blast dot frames (23 frames, 20 B stride to 360, then 18/20) ($AA00, BOOM.HELI; set at $1973/$198C)
MAPL_B=0x08800 -- launch quadrant map: slot (x,y) -> dive address ($9000, PATHMAP; indexed by PATHPICK $0D4E)
MAP86_B=0x08900 -- re-dive map for opcode $86 (and $88 via +hi16) ($9100, REPATH1; read by VM.HOME1 $1A71)
MAP87_B=0x08a00 -- re-dive map for opcode $87 ($9200, REPATH2; read by VM.HOME2 $1A8D)
AIM_B=0x08b00 -- dive-bomb aim table (enemy col x player col -> dx,dy nibbles) ($8F00, AUXRAMPS; index built by S.1C50, read at $0F78)
PBASE=0x08c00 -- dive bytecode base ($7000-relative offsets add this) ($7000-$8CFF, DIVEPATHS $6F27; interpreted by DIVEVM $19BD)
BANK_B=0x0a900 -- $8D00 direction -> plane-facing map ($8D00, BANKMAP; index built by BANKCALC $1C16, read at $1C46)

-- timing (design.md section 1)
OSTEP=0.3125 -- original frames per TIC frame (18.75/60); the Apple II frame loop is MAINLOOP ($089C)
GSPEED=1 -- gameplay-speed scalar (1 = original speed). PORT LEVER, no original counterpart
TICK_OF=4 -- launch-timer tick, original frames; FRAMECNT ($9650) gates spawners/LNCHTICK every 4th frame (CMP #$04 at $08F0)
SMOOTH=1 -- 1 = interpolate drawing between sim ticks (60fps motion); 0 = raw 18.75Hz steps. PORT RENDERING, no original counterpart

-- field geometry (apple coords; simulation runs entirely in these)
FLD_X0=3 -- playfield left edge; XOR plotter rejects x<$03 (CPX #$03 at $5929, PLOT.B $590F)
FLD_X1=243 -- playfield right edge; plotter rejects x>=$F3 ($5925)
FLD_Y0=2 -- playfield top; plotter rejects y<$02 ($5915)
FLD_Y1=190 -- playfield bottom; plotter rejects y>=$BE ($5911)
SEA_MID=167 -- sea midline y; fitted to SEAYTBL, the 256-entry sea-surface Y table ($4A00)
SEA_AMP=15 -- sea amplitude; fitted to SEAYTBL ($4A00), which runs $B4 down to ~$98
SEA_LEN=120 -- sea wavelength; fitted to SEAYTBL ($4A00), scrolled by SEAPHASE $47C5 ($5D3D)
CLAMP_LO=16 -- boat target min x; LDA #$10 / STA TARGETX ($17F8)
CLAMP_HI=225 -- boat target max x; LDA #$E1 / STA TARGETX ($1808)
BOAT_START=57 -- boat spawn x; LDA #$39 / STA TARGETX ($0C51)

-- movement, px per original frame
BOAT_DX=2 -- boat chase speed; ADC #$02 right / SBC #$02 left ($1836/$1855)
MSL_DY=11 -- missile rise; SBC #$0B in MISSILE ($18F8)
BOMB_DY=4 -- bomb fall; ADC #$04 in the formation-bomb mover ($0EC9)
BOMBER_DX=4 -- bomber crosser; ADC #$04 in BMBRMOVE ($60D6)
CRUISE_DX=6 -- cruise crosser; ADC #$06 in CRUSMOVE ($61E6)
MINE_DX=2 -- mine drift; per-wave WV.MDRIFT alternates $FE/$02 ($1283) -> MINEDIR $47C8
SLIDE_DX=1 -- formation slide, nominal unit: enemies.lua derives the real magnitude from FORM_SECS. The original steps FORMDX +-2 ($4762/$4763, added at $16E0)
SINK_DY=1 -- boat sink rate; INC PLAYERY in the sink path ($173C)

-- heli bomb-string spacing, in original frames between rounds. PORT INVENTION,
-- not decoded: the original ($0F36/$1B1D) fires one round per dive-op $7F with
-- no gate, and since dive_tick runs bytecode until a MOVE opcode, several $7F
-- can fire in one oframe. Rounds fall BOMB_DY px/oframe, so the on-screen gap
-- is BOMB_DY*HELI_ROUND_GAP*SCALE_Y = 4*2*0.75 = 6 px (2x the previous 3 px).
HELI_ROUND_GAP=2 -- oframes a round must fall before the next one fires ($0F36/$1B1D)

-- difficulty: per-mode base launch periods (3 dive timers, 4-of ticks, $673C+)
T1_BEG=16 -- boomer timer 1; LDA #$10 in DIFF.BEG ($673C)
T2_BEG=38 -- boomer timer 2; LDA #$26 ($6741)
T3_BEG=58 -- boomer timer 3; LDA #$3A ($6746)
T1_ADV=10 -- GEN-Y timer 1; LDA #$0A in DIFF.ADV ($6765)
T2_ADV=33 -- GEN-Y timer 2; LDA #$21 ($676A)
T3_ADV=47 -- GEN-Y timer 3; LDA #$2F ($676F)
T1_EXP=8 -- zoomer timer 1; LDA #$08 in DIFF.EXP ($6789)
T2_EXP=28 -- zoomer timer 2; LDA #$1C ($678E)
T3_EXP=37 -- zoomer timer 3; LDA #$25 ($6793)
RAMP1=2 -- per-wave period ramp, timer 1; SBC #$02 in RAMPDIFF ($1355)
RAMP2=1 -- per-wave period ramp, timer 2; SBC #$01 ($136D)
RAMP3=1 -- per-wave period ramp, timer 3; SBC #$01 ($1385)
FLOOR1=3 -- period floor, timer 1; CMP #$03 ($135D)
FLOOR2=6 -- period floor, timer 2; CMP #$06 ($1375)
FLOOR3=10 -- period floor, timer 3; CMP #$0A ($138D)

-- boomer easing (PORT CHANGE 2026-09-25, docs/difficulty.md): the original
-- ramps every mode to the same floors, so boomer reached zoomer intensity
-- by wave 8. On boomer only, the ramp now stops at wave 5's periods, and
-- from BEG_EASE_WAVE on a launch is skipped while BEG_MAX_DIVE enemies are
-- already diving, and the wave-gated $87 homing re-dive is not taken.
-- GEN-Y/zoomer keep the original's floors and have no cap.
BEG_FLOOR1=8 -- boomer period floor, timer 1 = wave 5's value (16-4*2). PORT CHANGE over CMP #$03 ($135D)
BEG_FLOOR2=34 -- boomer period floor, timer 2 = wave 5's value (38-4). PORT CHANGE over CMP #$06 ($1375)
BEG_FLOOR3=54 -- boomer period floor, timer 3 = wave 5's value (58-4). PORT CHANGE over CMP #$0A ($138D)
BEG_EASE_WAVE=6 -- first boomer wave with the diver cap and no $87 re-dive. PORT CHANGE
BEG_HELI_BURST=6 -- boomer: most rounds one heli burst fires (one $82 loop of a $8C00-$8C80 burst subroutine) = the longest string waves 1-4 produce ($8C40, 6 x left). PORT CHANGE: waves 5/6/8/9/10+ also reach $8C30's 8-round right sweep; the path still flies in full, rounds 7-8 are withheld
BEG_MAX_DIVE=4 -- boomer: most enemies diving at once from BEG_EASE_WAVE (launch skipped at the cap). PORT CHANGE: the original launches with no regard for who is airborne (LNCHTICK $0CF8)

-- hazards
BOMBER_RELOAD=15 -- bomber spawn timer, 4-of ticks; CMP #$0F in BMBRSPWN ($6124)
CRUISE_RELOAD=16 -- cruise spawn timer, 4-of ticks; CMP #$10 in CRUSSPWN ($6267)
QUOTA=4 -- bomber/cruise kills required per wave; BMBR.QTA/CRUS.QTA seeded 4 ($0C3C/$0C3F, decremented $61C7/$62CE)

-- sound: SFX slot ids (slot order mirrors the PICO-8 bank; see README). These
-- are the actual TIC-80 SFX slot numbers, so sfx.lua's psfx/lsfx pass them to
-- the engine unchanged and its `DUR` table is keyed by the same numbers.
SFX_FIRE=0 -- player missile launch, orig ch $00 ($64A4, fired $18E2)
SFX_CHOPPER=1 -- rotor drone while a heli dives (looped on ch2); orig ch $05 re-queued every frame by SNDSCAN ($654E, $6310)
SFX_PLANEKILL=2 -- formation plane shot, orig ch $02 ($64E2, fired $197D)
SFX_BOMBSPLASH=3 -- bomb hits the player/sea, orig ch $03 ($6505, fired $0EF7/$0FF3)
SFX_PLAYERHIT=4 -- boat struck (played 3x, ch3), orig ch $04 ($650B, fired $1077)
SFX_HELILAUNCH=5 -- heli starts its dive, orig ch $05 ($654E, fired $0D7A)
SFX_DIVEPLANEKILL=6 -- diving plane shot, orig ch $06 ($6557, fired $1996)
SFX_RAM=7 -- enemy rams the boat, orig ch $07 ($658B, fired $1BA5)
SFX_HELIKILL=8 -- hovering heli shot, orig ch $08 ($65A4, fired $1978)
SFX_DIVEHELIKILL=9 -- diving heli shot, orig ch $09 ($65C4, fired $1991)
SFX_MINEHIT=10 -- boat strikes a sea mine, orig ch $0A ($65E3, fired $60BF)
SFX_CRUISEKILL=11 -- cruise missile shot, orig ch $0B, script loops ($65EE, fired $62C2, stopped $5F57)
SFX_BOMBERKILL=12 -- bomber shot, orig ch $0C ($65F7, fired $61AD)
SFX_PLAYERSINK=13 -- boat sinking drone (looped on ch3), orig ch $0E, script loops ($6613, started $10A6, stopped $174F)
SFX_BLIP=14 -- the bonus tally tick = the original's MUSIC song $0A ($BA10, played per ship icon at $143C), traced by ../tools/songtrace.py onto the two-voice wave 6 (2026-09-20; was an authored blip). Reused as a PORT ADDITION for the difficulty change / high-score reset
SFX_HELIFIRE=15 -- heli gunfire report, one per round (ch1), orig ch $01 ($64DB, fired $0F95)

-- 16: the cruise-missile entry alert (original ch $0D, $6608). Added after
-- the bank was laid out, so it takes the first RESERVED buffer slot (16-19)
-- rather than renumbering the music instruments at 20.
SFX_CRUISEALERT=16 -- cruise missile entry alert

-- heli gunfire spacing, in DISPLAY frames between consecutive reports. Every
-- round is queued and heard (four shots = four blips, sfx.lua hf_pull); this
-- only sets how far apart they sound. Rounds arrive 1-2 oticks apart (53 or
-- 107ms) and the report is 33ms, so a spacing under ~3 frames can merge two
-- into one blip. 5 frames = 83ms, matching the ~90ms the reference video
-- shows (the original's frame period sagged to 70-90ms during a dive).
HF_GAP_F=5 -- display frames between heli-fire reports (sfx.lua hf_pull). PORT SPACING over the original's ungated per-round trigger ($0F95, ch $01 script $64DB)
SINK_CUT=28 -- oticks into the sunk state before the sink drone is cut (~1.5s); the original stops ch $0E when PLAYERST -> 3 ($174F)

-- cruise-kill chirp: the original LOOPS ch $0B ($65EE ends in $FE) and stops
-- it when the 9-frame explosion script at $A300 has played twice ($5F40 via
-- the $964B flag) = 18 original frames ~ 960ms, about 10 cycles of its 99ms
-- loop. The port replays the one-shot instead (TIC-80 slot 11 is 5 frames),
-- so these reproduce that cadence: an otick is 53.3ms, so a repeat every
-- 2 oticks ~ 107ms, 10 times ~ 960ms.
CRUISE_KILL_N=10 -- cruise-kill chirp repeats; reproduces the original's looped ch $0B ($65EE, $FE terminator at $65F6) stopped at $5F57
CRUISE_KILL_GAP=2 -- oticks between them (~107ms vs the original's 99ms loop, $65EE)

-- render mapping (design.md section 2): PILLARBOXED, deliberately wider than
-- aspect-correct. The Apple II's 280x192 hi-res filled a 4:3 CRT (pixel aspect
-- 0.9143), so the shape-preserving horizontal scale would be SCALE_Y*0.9143 =
-- 0.6857. But the port draws sprites at full original pixel size while
-- compressing positions, which crammed the 22-apple-px formation grid (a 13px
-- plane in a 15px slot vs the original's 22px slot). SCALE_X=0.80 trades a
-- +17% horizontal stretch for formation air (plane occupancy 86% -> 74%).
-- Vertical is the binding constraint (sea trough at apple y=182 must land on
-- the last row): SCALE_Y = 135/180 = 0.75.
-- (all PORT RENDERING: the Apple II drew 280x192 hi-res 1:1, so none of these
-- have an original counterpart; APX_AR describes that display, not a value read
-- from the binary.)
APX_AR=0.914286 -- apple pixel aspect (w/h) on a 4:3 CRT: (4/3)/(280/192)
SCALE_Y=0.75 -- apple px -> screen px, vertical (135/180, trough on last row)
SCALE_X=0.80 -- horizontal scale (aspect-correct would be SCALE_Y*APX_AR=0.6857)
SCR_H=136 -- TIC-80 screen height (verified: pix() clips at y=135)
SCR_W=240 -- TIC-80 screen width
FLD_W=192 -- pillarboxed playfield width, round(240*SCALE_X)

-- the field's left margin: 6 px left of centre, so the side rails are 18 and
-- 30 px and the right one holds the whole HUD in the small font (HISCORE is
-- 27 px of ink), as the original's own HUD was a right-hand column
FLD_OX=18 -- left rail width; the playfield spans x 18..209, the HUD rail 210..239

FLD_OY=-3 -- top margin, in screen px (from the old top status line; kept so every screen row maps as before)
COLOR_STATUS=12 -- status labels (Apple blue), in the right rail

-- sprite bank bases (SPRITES chunk rows; draw with spr(256+id, ...)). The value
-- is the TIC-80 slot; the ($xxxx) is the Apple II pen script the art was traced
-- from -- the original has no sprite sheet, it XOR-plots these dot scripts.
SPRITE_PLANE=0 -- facings 0-15: f<8 -> 2f, f>=8 -> 32+2(f-8) (16x16 blocks); SHP.PLANE ($5223, ptrs $512F/$513F indexed by ENEBANK $4490)
SPRITE_BOAT=64 -- lean frames 0-7 at 64+2k (16x16 blocks, the whole sheet row): k*5 deg clockwise (bow-right down), 0..35 = the range the boat reaches on the swell (steepest ~36 deg); left leans are the same frames x-flipped (boat_spr, steps -7..7). Frame 0 is the original upright glyph; 1-7 rendered 2026-09-25 from it (dark-orange 4 edge smoothing). The frames are HULL ONLY: boat_spr draws the cabin (3 columns, flat top, reaching down to the hull) and the 3-px gun in code from the boat_tower table, so both always stand straight up, replacing the original's 5-frame tilt ladder. SHP.BOAT ($53C9; the 5 frames at $53C9/$53E4/$5402/$5424/$5441, chosen via TILTMAP $8E00)
SPRITE_MINE_AIR=224 -- 16x16 block, above-surface variant (sea-blue/orange, reads on the black sky); 226 holds an identical second frame. PORT ADDITION: the original has one mine script ($53A4) and no above-water variant
SPRITE_MINE=228 -- 16x16 block, submerged variant (navy/white spikes, reads on the blue sea); 230 holds an identical second frame. SHP.MINE ($53A4, drawn by $59EB)
SPRITE_HELI=96 -- 16x8, right-facing (98 holds an identical second frame); left = x-flipped (FLIP_DX). Rotor fully drawn; heli_blade_black() fakes the spin, blanking the blade's rear and forward tip by turns. Scripts $536E (right) / $5389 (left, now a flip), rotor passes $5877/$588B
SPRITE_BOMBER=112 -- 24x8 (w=3), right-facing (115 holds an identical second frame); left = x-flipped (FLIP_DX). Moved from 104 (right) / 108 (left) 2026-10-04; SHP.BMBR1/2 ($545F right / $547A left, now a flip)
SPRITE_CRUISE=107 -- 40x8 (w=5), nose-right flicker frames 0/1/2 at 107/123/139 (rows 6-8, cols 11-15); nose-left = x-flipped (FLIP_DX). Moved from 112/122/133 (+ left 117/128/138) 2026-10-04; exhaust redrawn as a white/cyan flame 2026-09-25, airframe unchanged. SHP.CRUS ($5494; $5494/$54F0/$554A and left $54C2/$551D/$5578, now a flip)
FLIP_DX=-1 -- screen px added to a left-facing heli/bomber/cruise drawn as the x-flipped right glyph, so the airframe lands where the original's separately authored left glyph sat (best fit: the mirrors then differ by 4/16/7 px, mostly the original's hand-drawn asymmetries). PORT CHANGE 2026-10-04
SPRITE_MISSILE=160 -- frames 0-4 at 160/161/162/163/164 (8x16 / 8x16 / 8x32 / 8x32 / 8x32; white/cyan exhaust flame redrawn 2026-09-25, rocket rows unchanged); SHP.MSL ($55A6; frames $55A6/$55B3/$55CB/$55F0)

-- sky-writing smoke puff, 2 shapes x (grey under-layer, white top); draw_puffs
-- draws all greys then all whites. PUFFDRAW ($6D3D, stamped by dive-VM op $7C
-- at $1B53; letterforms SKYFONT $55F0). PORT ADDITION: 16 slots, the whole
-- sheet row 144-159, 8 per shape -- 2 greys (base, bulge) then 6 white tops
-- forming a closed billow loop, each frame 2-4 px from the next (A: rest,
-- rise, swell, peak, spill right, settle; B: rest, lean left, rise, peak,
-- crest right, spill back). Cut from 8-frame loops on 2026-10-04 to fit one
-- row (dropped A's sink right/lean left, B's sink left/settle). draw_puffs
-- walks the loop a step at a time; the grey bulges within one frame of PUFF_PEAK
SPRITE_PUFF_GREY = {{144, 145}, {152, 153}}
SPRITE_PUFF_TOPS = {{146, 147, 148, 149, 150, 151},
             {154, 155, 156, 157, 158, 159}}
PUFF_PEAK = {4, 5}
SPRITE_BOMB=128 -- enemy bomb (moved from 101 on 2026-10-04) (finned glyph, PICO-8 sprite 24 ported); the original has no bomb script, it inlines 9 PLOT.A calls ($5B24)
SPRITE_NOTE=130 -- 8x8 slot, 7x5 light-grey beamed eighth notes sized to the system font's cap height; brackets the song title on the wave-clear screen (sprite #386, moved from 103 on 2026-10-04). PORT ADDITION
SPRITE_LIFE=129 -- (moved from 102 on 2026-10-04) HUD reserve-boat icon (5x5, drawn at 7px pitch). PORT ADDITION: the original prints lives as a text digit ($1FDA) and the bonus tally redraws the live boat sprite ($1426)

-- ---------------------------------------------------------------------------
-- original-game TABLES (merged from the former data.lua, 2026-09-20)
--
-- Everything above is a scalar `name=value` line, which is the shape sim.py's
-- parser looks for; everything below is a Lua table constructor. sim.py ignores
-- these because a `{` never matches its numeric value pattern -- so when adding
-- a table here, keep the values INSIDE the braces and never start a
-- continuation line with `name = <number>`, or sim.py will read it as a
-- constant. The bulk binary data is not here: it lives in the <MAP> region,
-- addressed by the *_b offsets above.
--
-- These must stay AFTER the T1_BEG..T3_EXP and floor/beg_floor scalars:
-- DIFF_BASE and DIFF_FLOOR read them at load time.

-- dive-launch candidate orders, one per launch timer: 40 slot ids, 0-based
-- ($0DEC+; a timer fires the first state-0 slot in its list)
LLIST1 = {31,24,39,23,16,32,15,8,7,0,33,25,38,30,22,17,14,9,6,1,29,26,37,34,
          21,18,13,10,5,2,28,27,36,20,19,35,12,11,4,3}
LLIST2 = {24,16,32,8,0,25,17,33,9,1,26,18,34,10,2,27,19,35,11,3,28,20,36,12,
          4,29,21,37,13,5,30,22,38,14,6,31,23,39,15,7}
LLIST3 = {31,23,39,15,7,30,22,38,14,6,29,21,37,13,5,28,20,36,12,4,27,19,35,
          11,3,26,18,34,10,2,25,17,33,9,1,24,16,32,8,0}

-- per-wave config, waves 1..10 (tables $1233-$12BE; waves 11+ reuse wave 10)
WCFG_SONG   = {0,1,2,3,4,5,6,7,8,0}    -- promotion jingle (song id)
WCFG_F87    = {0,0,1,0,1,1,0,1,1,0}    -- 1 = re-dive opcode $87 taken
WCFG_BOMB   = {0,1,0,1,1,0,1,1,1,1}    -- 1 = plane bomb op $7d live (helis always fire)
WCFG_MINE   = {0,1,0,1,0,2,1,1,0,2}    -- sea mines afloat (0-2)
WCFG_BOMBER = {0,0,1,0,0,0,1,0,1,0}    -- 1 = bomber crosser runs
WCFG_CRUISE = {0,0,0,1,1,0,0,1,0,1}    -- 1 = cruise missile runs
WCFG_SEAVEL = {-0.5,-0.5,1,-1,1,-1,1,-1,1,-1}  -- sea scroll per otick, signed
WCFG_RANK   = {"GALLEY SLAVE","BOATSWAIN","COOK","DECKHAND","CREWCHIEF",
               "GUNNER","CAPTAIN","ADMIRAL","DEFENSE CHIEF","PRESIDENT"}

-- per-difficulty base launch periods (3 timers, 4-of ticks, $673C+)
DIFF_BASE = {{T1_BEG,T2_BEG,T3_BEG},{T1_ADV,T2_ADV,T3_ADV},{T1_EXP,T2_EXP,T3_EXP}}
-- per-difficulty period floors: the original's 3/6/10 for all modes; boomer's
-- raised to wave 5's periods (port change, see BEG_FLOOR1 above)
DIFF_FLOOR = {{BEG_FLOOR1,BEG_FLOOR2,BEG_FLOOR3},{FLOOR1,FLOOR2,FLOOR3},{FLOOR1,FLOOR2,FLOOR3}}
DIFF_NAMES = {"BOOMER","GEN-Y","ZOOMER"}
DIFF_BONUS = {0, 500, 1000}  -- per-wave intermission bonus (port addition)
DIFF_RANKCAP = {8, 9, 10}    -- highest rank reachable per mode ($144C)
DIFF_START_LIVES = {0, 1, 2} -- extra lives on top of START_LIVES per mode (port addition)
DIFF_START_WAVE = {0, 1, 2}  -- waves skipped at the start per mode: GEN-Y opens on wave 2, zoomer on 3 (port addition)
DIFF_WAVE_LIVES = {0, 1, 2}  -- extra lives per wave cleared from LATE_LIVES_WAVE on, on top of the +1 ship (port addition)

-- display themes, indexed by theme + 1 (pmem slot 2): the Apple II monitors,
-- a2boot.lua's mono mode 0 colour / 1 green / 2 white. PORT ADDITION
THEME_NAMES = {
  "APPLE II - COLOR",
  "APPLE II - GREEN",
  "APPLE II - B&W"}

-- Palette indices used by every draw call. Slot names stay valid when a
-- mono monitor theme repaints the palette (a2boot.lua mono.apply).
COLOR_SLOT_0=0 -- palette slot 0
COLOR_SLOT_1=1 -- palette slot 1
COLOR_SLOT_2=2 -- palette slot 2
COLOR_SLOT_3=3 -- palette slot 3
COLOR_SLOT_4=4 -- palette slot 4
COLOR_SLOT_5=5 -- palette slot 5
COLOR_SLOT_6=6 -- palette slot 6
COLOR_SLOT_7=7 -- palette slot 7
COLOR_SLOT_8=8 -- palette slot 8
COLOR_SLOT_9=9 -- palette slot 9
COLOR_SLOT_10=10 -- palette slot 10
COLOR_SLOT_11=11 -- palette slot 11
COLOR_SLOT_12=12 -- palette slot 12
COLOR_SLOT_13=13 -- palette slot 13
COLOR_SLOT_14=14 -- palette slot 14
COLOR_SLOT_15=15 -- palette slot 15

-- Apple II intro sprite strip (shared with the asset editors).
SPRITE_BOOT_AT=504 -- inverse @ glyph
SPRITE_BOOT_TITLE=505 -- seven cells spelling APPLE ][
BOOT_DRIVE_BASE=0x0EC00 -- Disk II sample bytes in MAP; game-owned allocation
BOOT_DRIVE_LENGTH=4927 -- standard drive recording byte span
BOOT_DRIVE_MIDPOINT=118 -- silence level of the authored drive samples

SPRITE_BANK=256 -- first cell of the SPRITES bank
