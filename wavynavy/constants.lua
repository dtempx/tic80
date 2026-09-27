-- constants: every tuned gameplay value (sim.py parses the name=value lines),
-- plus the original game's small data tables at the end (launch orders,
-- per-wave config, ranks, difficulty) -- see the banner down there.
-- NOTE: no comment may begin with dash-dash-space-langle: TIC-80's cart parser
-- reads that as an asset chunk tag and truncates the code (tools/ticpkg.py
-- enforces this)

-- Citations: a trailing ($xxxx) is the address in the Apple II original's
-- disassembly (games/wavynavy/disasm/) where that value is defined or written.
-- Lines with no address are port inventions or TIC-80-side values; the ones
-- that replace original behaviour say so.

-- config
lives_max=8 -- HUD reserve-boat icons drawn at most (clears the WAVE readout). PORT LIMIT: the original prints lives as a text digit and caps the award at 9 (SHIPAWARD $1FC9)
form_secs=8 -- seconds per formation edge-to-edge sweep; original sweeps at FORMDX +-2 px/frame between x=$20 and x=$CA ($16E0, edges $16EF/$16FB)
expl_of=40 -- blast lifetime in oframes; original walks the dot-ring streams to their end instead (BOOM.A $9B00, stepped by $5E68)
recall_ofs=282 -- sunk-state ticks (~20s) before snapping the fleet home. PORT INVENTION: the original has no recall watchdog (death path DEATHSEQ $1534)
enemy_dy=16 -- min vertical gap (px) kept between enemy planes, both climbing back and diving. PORT REFINEMENT: the original enforces no separation (REJOIN $169C)
dive_push=2 -- px/tick a crowded diver is pushed apart to reach yoff_min. PORT REFINEMENT, see enemy_dy
late_lives_wave=6 -- first cleared wave that also awards diff_wave_lives (advanced +1, expert +2). PORT ADDITION: the original awards only the +1 ship (SHIPAWARD $1FC9)
bonus_step=30 -- frames between reserve-boat awards in the bonus tally. PORT PACING: the original's tally loop is ungated, one +50 and jingle per ship ($141D)
title_vspeed=0.75 -- title skywriter pace, dive ticks per 60fps frame; paths TITLEPTH1/2 ($8800/$8A00), staged by TITLEANIM ($6BC5)
demo_secs=30 -- attract demo length in seconds; a death in progress defers the cutoff until the boat has sunk (hard cap +6s). PORT PACING (demo mode DEMOFLG $085D)

-- original data block in the <MAP> region (layout owned by tools/build.py;
-- addresses are peek()ed in place, hex so sim.py ignores them). The value is
-- the TIC-80 destination; the ($xxxx) is the Apple II source the bytes are
-- copied from byte-for-byte -- same pairing as the table above the <MAP> chunk.
tmpl_b=0x08000 -- formation templates (10 waves x 120 B: 40 slots x [x,y,state]) ($4B00+$80*w, TEMPLATES; ptrs WV.TMPLLO $1233)
xplp_b=0x084b0 -- plane-blast dot frames (8 x 32 B) ($9B00, BOOM.A)
xplr_b=0x085b0 -- ram-blast dot frames (3 frames, offsets 0/36/74, end 110) ($A900, BOOM.RAM; set by RAMKILL $58A3)
xplh_b=0x0861e -- heli-blast dot frames (23 frames, 20 B stride to 360, then 18/20) ($AA00, BOOM.HELI; set at $1973/$198C)
mapl_b=0x08800 -- launch quadrant map: slot (x,y) -> dive address ($9000, PATHMAP; indexed by PATHPICK $0D4E)
map86_b=0x08900 -- re-dive map for opcode $86 (and $88 via +hi16) ($9100, REPATH1; read by VM.HOME1 $1A71)
map87_b=0x08a00 -- re-dive map for opcode $87 ($9200, REPATH2; read by VM.HOME2 $1A8D)
aim_b=0x08b00 -- dive-bomb aim table (enemy col x player col -> dx,dy nibbles) ($8F00, AUXRAMPS; index built by S.1C50, read at $0F78)
pbase=0x08c00 -- dive bytecode base ($7000-relative offsets add this) ($7000-$8CFF, DIVEPATHS $6F27; interpreted by DIVEVM $19BD)
bank_b=0x0a900 -- $8D00 direction -> plane-facing map ($8D00, BANKMAP; index built by BANKCALC $1C16, read at $1C46)

-- timing (design.md section 1)
ostep=0.3125 -- original frames per TIC frame (18.75/60); the Apple II frame loop is MAINLOOP ($089C)
gspeed=1 -- gameplay-speed scalar (1 = original speed). PORT LEVER, no original counterpart
tick_of=4 -- launch-timer tick, original frames; FRAMECNT ($9650) gates spawners/LNCHTICK every 4th frame (CMP #$04 at $08F0)
smooth=1 -- 1 = interpolate drawing between sim ticks (60fps motion); 0 = raw 18.75Hz steps. PORT RENDERING, no original counterpart

-- field geometry (apple coords; simulation runs entirely in these)
fld_x0=3 -- playfield left edge; XOR plotter rejects x<$03 (CPX #$03 at $5929, PLOT.B $590F)
fld_x1=243 -- playfield right edge; plotter rejects x>=$F3 ($5925)
fld_y0=2 -- playfield top; plotter rejects y<$02 ($5915)
fld_y1=190 -- playfield bottom; plotter rejects y>=$BE ($5911)
sea_mid=167 -- sea midline y; fitted to SEAYTBL, the 256-entry sea-surface Y table ($4A00)
sea_amp=15 -- sea amplitude; fitted to SEAYTBL ($4A00), which runs $B4 down to ~$98
sea_len=120 -- sea wavelength; fitted to SEAYTBL ($4A00), scrolled by SEAPHASE $47C5 ($5D3D)
clamp_lo=16 -- boat target min x; LDA #$10 / STA TARGETX ($17F8)
clamp_hi=225 -- boat target max x; LDA #$E1 / STA TARGETX ($1808)
boat_start=57 -- boat spawn x; LDA #$39 / STA TARGETX ($0C51)

-- movement, px per original frame
boat_dx=2 -- boat chase speed; ADC #$02 right / SBC #$02 left ($1836/$1855)
msl_dy=11 -- missile rise; SBC #$0B in MISSILE ($18F8)
bomb_dy=4 -- bomb fall; ADC #$04 in the formation-bomb mover ($0EC9)
bomber_dx=4 -- bomber crosser; ADC #$04 in BMBRMOVE ($60D6)
cruise_dx=6 -- cruise crosser; ADC #$06 in CRUSMOVE ($61E6)
mine_dx=2 -- mine drift; per-wave WV.MDRIFT alternates $FE/$02 ($1283) -> MINEDIR $47C8
slide_dx=1 -- formation slide, nominal unit: enemies.lua derives the real magnitude from form_secs. The original steps FORMDX +-2 ($4762/$4763, added at $16E0)
sink_dy=1 -- boat sink rate; INC PLAYERY in the sink path ($173C)

-- heli bomb-string spacing, in original frames between rounds. PORT INVENTION,
-- not decoded: the original ($0F36/$1B1D) fires one round per dive-op $7F with
-- no gate, and since dive_tick runs bytecode until a MOVE opcode, several $7F
-- can fire in one oframe. Rounds fall bomb_dy px/oframe, so the on-screen gap
-- is bomb_dy*heli_round_gap*scale_y = 4*2*0.75 = 6 px (2x the previous 3 px).
heli_round_gap=2 -- oframes a round must fall before the next one fires ($0F36/$1B1D)

-- difficulty: per-mode base launch periods (3 dive timers, 4-of ticks, $673C+)
t1_beg=16 -- beginner timer 1; LDA #$10 in DIFF.BEG ($673C)
t2_beg=38 -- beginner timer 2; LDA #$26 ($6741)
t3_beg=58 -- beginner timer 3; LDA #$3A ($6746)
t1_adv=10 -- advanced timer 1; LDA #$0A in DIFF.ADV ($6765)
t2_adv=33 -- advanced timer 2; LDA #$21 ($676A)
t3_adv=47 -- advanced timer 3; LDA #$2F ($676F)
t1_exp=8 -- expert timer 1; LDA #$08 in DIFF.EXP ($6789)
t2_exp=28 -- expert timer 2; LDA #$1C ($678E)
t3_exp=37 -- expert timer 3; LDA #$25 ($6793)
ramp1=2 -- per-wave period ramp, timer 1; SBC #$02 in RAMPDIFF ($1355)
ramp2=1 -- per-wave period ramp, timer 2; SBC #$01 ($136D)
ramp3=1 -- per-wave period ramp, timer 3; SBC #$01 ($1385)
floor1=3 -- period floor, timer 1; CMP #$03 ($135D)
floor2=6 -- period floor, timer 2; CMP #$06 ($1375)
floor3=10 -- period floor, timer 3; CMP #$0A ($138D)
-- beginner easing (PORT CHANGE 2026-09-25, docs/difficulty.md): the original
-- ramps every mode to the same floors, so beginner reached expert intensity
-- by wave 8. On beginner only, the ramp now stops at wave 5's periods, and
-- from beg_ease_wave on a launch is skipped while beg_max_dive enemies are
-- already diving, and the wave-gated $87 homing re-dive is not taken.
-- Advanced/expert keep the original's floors and have no cap.
beg_floor1=8 -- beginner period floor, timer 1 = wave 5's value (16-4*2). PORT CHANGE over CMP #$03 ($135D)
beg_floor2=34 -- beginner period floor, timer 2 = wave 5's value (38-4). PORT CHANGE over CMP #$06 ($1375)
beg_floor3=54 -- beginner period floor, timer 3 = wave 5's value (58-4). PORT CHANGE over CMP #$0A ($138D)
beg_ease_wave=6 -- first beginner wave with the diver cap and no $87 re-dive. PORT CHANGE
beg_heli_burst=6 -- beginner: most rounds one heli burst fires (one $82 loop of a $8C00-$8C80 burst subroutine) = the longest string waves 1-4 produce ($8C40, 6 x left). PORT CHANGE: waves 5/6/8/9/10+ also reach $8C30's 8-round right sweep; the path still flies in full, rounds 7-8 are withheld
beg_max_dive=4 -- beginner: most enemies diving at once from beg_ease_wave (launch skipped at the cap). PORT CHANGE: the original launches with no regard for who is airborne (LNCHTICK $0CF8)

-- hazards
bomber_reload=15 -- bomber spawn timer, 4-of ticks; CMP #$0F in BMBRSPWN ($6124)
cruise_reload=16 -- cruise spawn timer, 4-of ticks; CMP #$10 in CRUSSPWN ($6267)
quota=4 -- bomber/cruise kills required per wave; BMBR.QTA/CRUS.QTA seeded 4 ($0C3C/$0C3F, decremented $61C7/$62CE)

-- sound: SFX slot ids (slot order mirrors the PICO-8 bank; see README). These
-- are the actual TIC-80 SFX slot numbers, so sfx.lua's psfx/lsfx pass them to
-- the engine unchanged and its `dur` table is keyed by the same numbers.
sfx_fire=0 -- player missile launch, orig ch $00 ($64A4, fired $18E2)
sfx_chopper=1 -- rotor drone while a heli dives (looped on ch2); orig ch $05 re-queued every frame by SNDSCAN ($654E, $6310)
sfx_planekill=2 -- formation plane shot, orig ch $02 ($64E2, fired $197D)
sfx_bombsplash=3 -- bomb hits the player/sea, orig ch $03 ($6505, fired $0EF7/$0FF3)
sfx_playerhit=4 -- boat struck (played 3x, ch3), orig ch $04 ($650B, fired $1077)
sfx_helilaunch=5 -- heli starts its dive, orig ch $05 ($654E, fired $0D7A)
sfx_diveplanekill=6 -- diving plane shot, orig ch $06 ($6557, fired $1996)
sfx_ram=7 -- enemy rams the boat, orig ch $07 ($658B, fired $1BA5)
sfx_helikill=8 -- hovering heli shot, orig ch $08 ($65A4, fired $1978)
sfx_divehelikill=9 -- diving heli shot, orig ch $09 ($65C4, fired $1991)
sfx_minehit=10 -- boat strikes a sea mine, orig ch $0A ($65E3, fired $60BF)
sfx_cruisekill=11 -- cruise missile shot, orig ch $0B, script loops ($65EE, fired $62C2, stopped $5F57)
sfx_bomberkill=12 -- bomber shot, orig ch $0C ($65F7, fired $61AD)
sfx_playersink=13 -- boat sinking drone (looped on ch3), orig ch $0E, script loops ($6613, started $10A6, stopped $174F)
sfx_blip=14 -- the bonus tally tick = the original's MUSIC song $0A ($BA10, played per ship icon at $143C), traced by ../tools/songtrace.py onto the two-voice wave 6 (2026-09-20; was an authored blip). Reused as a PORT ADDITION for the difficulty change / high-score reset
sfx_helifire=15 -- heli gunfire report, one per round (ch1), orig ch $01 ($64DB, fired $0F95)
-- 16: the cruise-missile entry alert (original ch $0D, $6608). Added after
-- the bank was laid out, so it takes the first RESERVED buffer slot (16-19)
-- rather than renumbering the music instruments at 20.
sfx_cruisealert=16 -- cruise missile entry alert

-- heli gunfire spacing, in DISPLAY frames between consecutive reports. Every
-- round is queued and heard (four shots = four blips, sfx.lua hf_pull); this
-- only sets how far apart they sound. Rounds arrive 1-2 oticks apart (53 or
-- 107ms) and the report is 33ms, so a spacing under ~3 frames can merge two
-- into one blip. 5 frames = 83ms, matching the ~90ms the reference video
-- shows (the original's frame period sagged to 70-90ms during a dive).
hf_gap_f=5 -- display frames between heli-fire reports (sfx.lua hf_pull). PORT SPACING over the original's ungated per-round trigger ($0F95, ch $01 script $64DB)
sink_cut=28 -- oticks into the sunk state before the sink drone is cut (~1.5s); the original stops ch $0E when PLAYERST -> 3 ($174F)
-- cruise-kill chirp: the original LOOPS ch $0B ($65EE ends in $FE) and stops
-- it when the 9-frame explosion script at $A300 has played twice ($5F40 via
-- the $964B flag) = 18 original frames ~ 960ms, about 10 cycles of its 99ms
-- loop. The port replays the one-shot instead (TIC-80 slot 11 is 5 frames),
-- so these reproduce that cadence: an otick is 53.3ms, so a repeat every
-- 2 oticks ~ 107ms, 10 times ~ 960ms.
cruise_kill_n=10 -- cruise-kill chirp repeats; reproduces the original's looped ch $0B ($65EE, $FE terminator at $65F6) stopped at $5F57
cruise_kill_gap=2 -- oticks between them (~107ms vs the original's 99ms loop, $65EE)

-- render mapping (design.md section 2): PILLARBOXED, deliberately wider than
-- aspect-correct. The Apple II's 280x192 hi-res filled a 4:3 CRT (pixel aspect
-- 0.9143), so the shape-preserving horizontal scale would be scale_y*0.9143 =
-- 0.6857. But the port draws sprites at full original pixel size while
-- compressing positions, which crammed the 22-apple-px formation grid (a 13px
-- plane in a 15px slot vs the original's 22px slot). scale_x=0.80 trades a
-- +17% horizontal stretch for formation air (plane occupancy 86% -> 74%).
-- Vertical is the binding constraint (sea trough at apple y=182 must land on
-- the last row): scale_y = 135/180 = 0.75.
-- (all PORT RENDERING: the Apple II drew 280x192 hi-res 1:1, so none of these
-- have an original counterpart; apx_ar describes that display, not a value read
-- from the binary.)
apx_ar=0.914286 -- apple pixel aspect (w/h) on a 4:3 CRT: (4/3)/(280/192)
scale_y=0.75 -- apple px -> screen px, vertical (135/180, trough on last row)
scale_x=0.80 -- horizontal scale (aspect-correct would be scale_y*apx_ar=0.6857)
scr_h=136 -- TIC-80 screen height (verified: pix() clips at y=135)
scr_w=240 -- TIC-80 screen width
fld_w=192 -- pillarboxed playfield width, round(240*scale_x)
fld_ox=24 -- left margin, (scr_w-fld_w)//2; black bars outside [24,216)
fld_oy=1 -- top margin, in screen px: drops the playfield clear of the status text
status_c=12 -- status-bar text colour (Apple blue)
wave_dx=10 -- WAVE readout nudge, px right of the field centre (clears the score)

-- sprite bank bases (SPRITES chunk rows; draw with spr(256+id, ...)). The value
-- is the TIC-80 slot; the ($xxxx) is the Apple II pen script the art was traced
-- from -- the original has no sprite sheet, it XOR-plots these dot scripts.
spr_plane=0 -- facings 0-15: f<8 -> 2f, f>=8 -> 32+2(f-8) (16x16 blocks); SHP.PLANE ($5223, ptrs $512F/$513F indexed by ENEBANK $4490)
spr_boat=64 -- lean frames 0-7 at 64+2k (16x16 blocks, the whole sheet row): k*5 deg clockwise (bow-right down), 0..35 = the range the boat reaches on the swell (steepest ~36 deg); left leans are the same frames x-flipped (boat_spr, steps -7..7). Frame 0 is the original upright glyph; 1-7 rendered 2026-09-25 from it (dark-orange 4 edge smoothing). The frames are HULL ONLY: boat_spr draws the cabin (3 columns, flat top, reaching down to the hull) and the 3-px gun in code from the boat_tower table, so both always stand straight up, replacing the original's 5-frame tilt ladder. SHP.BOAT ($53C9; the 5 frames at $53C9/$53E4/$5402/$5424/$5441, chosen via TILTMAP $8E00)
spr_mine=224 -- 16x16 block, submerged variant (navy/white spikes, reads on the blue sea); moved from 74 to 228 on 2026-09-25 to free the boat row, then to 224; SHP.MINE ($53A4, drawn by $59EB)
spr_mine_air=226 -- 16x16 block (moved with spr_mine, 76 -> 230 -> 226), above-surface variant (sea-blue/orange, reads on the black sky). PORT ADDITION: the original has one mine script ($53A4) and no above-water variant
spr_heli=96 -- 16x8, one sprite per heading (right 96, left 98), rotor fully drawn; heli_blade_black() fakes the spin, blanking the blade's rear and forward tip by turns. Scripts $536E (right) / $5389 (left), rotor passes $5877/$588B
spr_bomber=104 -- frames a/b at 104/108 (24x8, w=3); SHP.BMBR1/2 ($545F/$547A)
spr_cruise=112 -- directions interleaved per frame: nose-right at 112/122/133, nose-left at 117/128/138 (40x8; exhaust behind the wings redrawn as a white/cyan flame 2026-09-25, airframe unchanged); frames bake body offsets, corrected in cruise_frame. SHP.CRUS ($5494; $5494/$54F0/$554A and $54C2/$551D/$5578)
spr_missile=160 -- frames 0-4 at 160/161/162/163/164 (8x16 / 8x16 / 8x32 / 8x32 / 8x32; white/cyan exhaust flame redrawn 2026-09-25, rocket rows unchanged); SHP.MSL ($55A6; frames $55A6/$55B3/$55CB/$55F0)
-- sky-writing smoke puff, 2 shapes x (grey under-layer, white top); draw_puffs
-- draws all greys then all whites. PUFFDRAW ($6D3D, stamped by dive-VM op $7C
-- at $1B53; letterforms SKYFONT $55F0). PORT ADDITION: 20 slots, one sheet
-- row per shape -- 2 greys (base, bulge) then 8 white tops forming a closed
-- billow loop, each frame 2-4 px from the next (A: rest, rise, swell, peak,
-- spill right, sink right, settle, lean left; B: rest, lean left, sink left,
-- settle, rise, peak, crest right, spill back). draw_puffs walks the loop a
-- step at a time; the grey bulges within one frame of puff_peak
puff_grey = {{165, 166}, {181, 182}}
puff_tops = {{167, 168, 169, 170, 171, 172, 173, 174},
             {183, 184, 185, 186, 187, 188, 189, 190}}
puff_peak = {4, 6}
spr_bomb=101 -- enemy bomb (finned glyph, PICO-8 sprite 24 ported); the original has no bomb script, it inlines 9 PLOT.A calls ($5B24)
spr_note=103 -- 8x8 slot, 7x5 light-grey beamed eighth notes sized to the system font's cap height; brackets the song title on the wave-clear screen (sprite #359). PORT ADDITION
spr_life=102 -- HUD reserve-boat icon (5x5, drawn at 7px pitch). PORT ADDITION: the original prints lives as a text digit ($1FDA) and the bonus tally redraws the live boat sprite ($1426)

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
-- These must stay AFTER the t1_beg..t3_exp and floor/beg_floor scalars:
-- diff_base and diff_floor read them at load time.

-- dive-launch candidate orders, one per launch timer: 40 slot ids, 0-based
-- ($0DEC+; a timer fires the first state-0 slot in its list)
llist1 = {31,24,39,23,16,32,15,8,7,0,33,25,38,30,22,17,14,9,6,1,29,26,37,34,
          21,18,13,10,5,2,28,27,36,20,19,35,12,11,4,3}
llist2 = {24,16,32,8,0,25,17,33,9,1,26,18,34,10,2,27,19,35,11,3,28,20,36,12,
          4,29,21,37,13,5,30,22,38,14,6,31,23,39,15,7}
llist3 = {31,23,39,15,7,30,22,38,14,6,29,21,37,13,5,28,20,36,12,4,27,19,35,
          11,3,26,18,34,10,2,25,17,33,9,1,24,16,32,8,0}

-- per-wave config, waves 1..10 (tables $1233-$12BE; waves 11+ reuse wave 10)
wcfg_song   = {0,1,2,3,4,5,6,7,8,0}    -- promotion jingle (song id)
wcfg_f87    = {0,0,1,0,1,1,0,1,1,0}    -- 1 = re-dive opcode $87 taken
wcfg_bomb   = {0,1,0,1,1,0,1,1,1,1}    -- 1 = plane bomb op $7d live (helis always fire)
wcfg_mine   = {0,1,0,1,0,2,1,1,0,2}    -- sea mines afloat (0-2)
wcfg_bomber = {0,0,1,0,0,0,1,0,1,0}    -- 1 = bomber crosser runs
wcfg_cruise = {0,0,0,1,1,0,0,1,0,1}    -- 1 = cruise missile runs
wcfg_seavel = {-0.5,-0.5,1,-1,1,-1,1,-1,1,-1}  -- sea scroll per otick, signed
wcfg_rank   = {"GALLEY SLAVE","BOATSWAIN","COOK","DECKHAND","CREWCHIEF",
               "GUNNER","CAPTAIN","ADMIRAL","DEFENSE CHIEF","PRESIDENT"}

-- per-difficulty base launch periods (3 timers, 4-of ticks, $673C+)
diff_base = {{t1_beg,t2_beg,t3_beg},{t1_adv,t2_adv,t3_adv},{t1_exp,t2_exp,t3_exp}}
-- per-difficulty period floors: the original's 3/6/10 for all modes; beginner's
-- raised to wave 5's periods (port change, see beg_floor1 above)
diff_floor = {{beg_floor1,beg_floor2,beg_floor3},{floor1,floor2,floor3},{floor1,floor2,floor3}}
diff_names = {"BEGINNER","ADVANCED","EXPERT"}
diff_bonus = {0, 250, 500}   -- per-wave intermission bonus (port addition)
diff_rankcap = {8, 9, 10}    -- highest rank reachable per mode ($144C)
diff_start_lives = {0, 1, 2} -- extra lives on top of start_lives per mode (port addition)
diff_start_wave = {0, 1, 2}  -- waves skipped at the start per mode: advanced opens on wave 2, expert on 3 (port addition)
diff_wave_lives = {0, 1, 2}  -- extra lives per wave cleared from late_lives_wave on, on top of the +1 ship (port addition)
