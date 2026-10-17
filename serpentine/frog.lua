-- frog.lua
-- the frog, after the original's FROGDRIVE $8D8C (one call per main-loop
-- frame from $10FD, one per go-home step from $9DC8), FROGSPAWN $8D6F and
-- the draw/erase pair FROGDRAW $905E / FROGERASE $8FAC.
--
-- There is always exactly one frog. It lives on the maze's columns 0-12 and
-- on a ring of 16 rows: rows 1-11 are the board, 12-15 run below the screen
-- and 0 above it (y = 16*row+3, a byte that wraps). It spawns below (row 14)
-- and comes onto the board from below, or from above by hopping 15 -> 0.
-- FROGDRAW draws it wherever it is, and FROGY < $B4 counts row 0 (the header
-- strip) as on the board. The port draws it off the maze too, on the same
-- ring. This layout has only 2 px above the maze and none below, so off the
-- maze it is drawn just past the edge wall, in view (draw_frogs).
-- It sits, then hops a cell (or leaps two, clean over any wall), never
-- straight back the way it faces. While sitting it eats an egg it is on.
-- A snake head that meets it at a cell centre eats it; it is then respawned
-- below the board at once.

frog={}

-- each hop's per-frame displacement in original px, read from the hop tables
-- dx D.AECF $AECF / dy D.AF0F $AF0F, stepping the index FROGANIM $DA down from
-- the start value until index&7 == 0 ($8F17-$8F30). One entry per frame.
local HOP={
 up_s={2,4,6,3,1},        -- $04 (FROGANIM start, L.8EE9)
 up_l={3,5,6,8,6,3,1},    -- $26: 2 rows
 down_s={2,4,6,3,1},      -- $0C (L.8F01)
 down_l={3,5,6,8,6,3,1},  -- $2E: 2 rows
 right_s6={2,2,4,8,4,2},  -- $15, from an x phase of 2 (L.8F64)
 right_s5={2,4,8,4,2},    -- $14, otherwise
 right_l={2,4,6,8,8,8,4,2}, -- $37: 2 columns
 left_s6={2,2,4,8,4,2},   -- $1D, from an x phase of 3 (L.8F97)
 left_s5={2,4,8,4,2},     -- $1C, otherwise
 left_l={2,4,6,8,8,8,4,2},  -- $3F: 2 columns
}

-- the frog's x is its column's odd x: 3+21k for even k, 2+21k for odd k
-- (column map D.6600 $6600 holds 2+21k and 3+21k); its x phase (D.6200) is
-- then 3 for even columns and 2 for odd
local function col_x(k) return (k%2==0) and 3+21*k or 2+21*k end

-- orig facing codes FROGFACE $C2: 0 up, 1 down, 2 right, 3 left -> port dir
local FACE_DIR={[0]=0,[1]=2,[2]=1,[3]=3}

local function sync()
 frog.cx=frog.col+1
 frog.cy=frog.row
 frog.active=16*frog.row+3<0xB4 -- FROGY < $B4 ($B0EA, $181E): rows 0-11
 frog.anim_timer=frog.hop and 1 or 0 -- FROGHOP $C6
 frog.dir=FACE_DIR[frog.face]
end

-- the random byte the steering reads (RNGENTROPY $E8)
local function roll()
 frog.rng=math.random(0,255)
 return frog.rng
end

-- FROGSPAWN $8D6F: a random column (the first whose odd x is at or past an
-- odd random x, $8D6F-$8D7B), four rows under the board ($E3 = row 14),
-- facing up, not hopping. The wait FROGDELAY $E0 is left as it was.
function spawn_frog()
 local x=roll()|1
 local col=12
 for k=0,12 do
  if col_x(k)>=x then col=k break end
 end
 frog.col,frog.row,frog.face=col,14,0
 frog.hop=nil
 sync()
end

-- the frog is eaten or cleared: FROGSPAWN + FROGERASE ($09CD, $0AA9, $9E19)
function despawn_frog() spawn_frog() end

-- new round (L.0822: FROGSPAWN $0842, FROGFACE/FROGHOP = 0 $0847-$0849;
-- round init FROGDELAY = 0 $86A7, so it hops at once)
function init_frogs()
 frog.delay=0
 frog.clicked=false
 frog.t=0
 frog.rng=0
 spawn_frog()
end

-- put the frog on a cell, sitting (test and pose helper)
function frog_place(cx,cy,face)
 frog.col,frog.row=cx-1,cy
 frog.face=face or 0
 frog.hop=nil
 sync()
end

-- the frame counter the hop law reads (FRAMECTR $E4; the go-home walk
-- counts its own steps, $9DD4)
local function frame_ctr()
 if game_state=="GOHOME" then return gohome.frame end
 return hunger.frame
end

-- start a hop of `deltas` frames moving (dcol,drow) cells, facing nd
local function hop(nd,dcol,drow,deltas)
 local total=0
 for _,d in ipairs(deltas) do total=total+d end
 frog.face=nd -- FROGND -> FROGFACE at the first frame ($905A)
 frog.hop={dcol=dcol,drow=drow,deltas=deltas,total=total,n=0}
 -- PORT: the visible entry from below also sounds (the original's
 -- pre-hop click gate at $B0EA excludes the offscreen starting row).
 local dest=(frog.row+drow)%16
 if frog.row>MAZE_ROWS and dest>=1 and dest<=MAZE_ROWS
    and not frog.clicked and not frog_parked() then
  frog.clicked=true
  snd("hop")
 end
 return true
end

-- the four hop handlers; each refuses (nil) to reverse or to leave the
-- columns, and the caller then rolls a random direction instead (L.8F43).
-- RNGENTROPY bit 7 set -> a one-cell hop, clear -> a two-cell leap.
local function go_up()   -- L.8EE9
 if frog.face==1 then return nil end
 if frog.rng>=128 then return hop(0,0,-1,HOP.up_s) end
 return hop(0,0,-2,HOP.up_l)
end
local function go_down() -- L.8F01
 if frog.face==0 then return nil end
 if frog.rng>=128 then return hop(1,0,1,HOP.down_s) end
 return hop(1,0,2,HOP.down_l)
end
local function go_right() -- L.8F46: x $E9 (column 11) allows only a short hop
 if frog.face==3 or frog.col>11 then return nil end
 if frog.col==11 or frog.rng>=128 then
  return hop(2,1,0,(frog.col%2==1) and HOP.right_s6 or HOP.right_s5)
 end
 return hop(2,2,0,HOP.right_l)
end
local function go_left() -- L.8F78: x $17 (column 1) allows only a short hop
 if frog.face==2 or frog.col<1 then return nil end
 if frog.col==1 or frog.rng>=128 then
  return hop(3,-1,0,(frog.col%2==0) and HOP.left_s6 or HOP.left_s5)
 end
 return hop(3,-2,0,HOP.left_l)
end

-- L.8E38: a random direction from (RNG>>3)&3 -- 0 up, 1 down, 2 left,
-- 3 right -- rolled again until one is allowed
local function go_random()
 for _=1,64 do
  local d=(roll()>>3)&3
  local ok
  if d==0 then ok=go_up() elseif d==1 then ok=go_down()
  elseif d==2 then ok=go_left() else ok=go_right() end
  if ok then return end
 end
end

-- the frog's position in original px, mid-hop included (FROGX/FROGY $C0/$C1
-- move every hop frame, $8F1A-$8F27): what the enemy AI aims at ($182B).
-- FROGY is a byte, so a hop across the 15/0 seam wraps
function frog_orig_xy()
 local x,y=col_x(frog.col),16*frog.row+3
 local h=frog.hop
 if h then
  local done=0
  for i=1,h.n do done=done+h.deltas[i] end
  local f=done/h.total
  x=x+h.dcol*21*f
  y=y+h.drow*16*f
 end
 return x,y%256
end

-- L.8E60-$8EE6: steer for the player's egg. Off the board or with no egg,
-- random. Within 40 px ($28, sum of |dx| and |dy|) it takes short hops
-- (RNGENTROPY |= $80). The larger gap is closed first; a reversal falls
-- through to the other axis, and a refused hop to a random one.
local function go_steer()
 local egg=player_egg
 if frog.row>=12 or not (egg.active and egg.dropped) then return go_random() end
 local fx,fy=col_x(frog.col),16*frog.row+3
 local ex,ey=orig_xy(egg.x,egg.y)
 local ady,adx=math.abs(ey-fy),math.abs(ex-fx)
 if adx+ady<40 then frog.rng=frog.rng|0x80 end
 local function vert() if ey>=fy then return go_down() end return go_up() end
 local function horiz() if ex>=fx then return go_right() end return go_left() end
 local ok
 if adx>=ady then
  if ex>=fx then
   if frog.face==3 then ok=vert() else ok=go_right() end
  else
   if frog.face==2 then ok=vert() else ok=go_left() end
  end
 else
  if ey>=fy then
   if frog.face==0 then ok=horiz() else ok=go_down() end
  else
   if frog.face==1 then ok=horiz() else ok=go_up() end
  end
 end
 if not ok then go_random() end
end

-- one hop frame (L.8F17): move by this frame's delta; on the last frame
-- (index&7 == 0) land and roll the next wait: ($E8 & $1F) + $28 - level
-- frames ($8F32-$8F3B), at the difficulty level
local function step_hop()
 local h=frog.hop
 h.n=h.n+1
 if h.n>=#h.deltas then
  frog.col=frog.col+h.dcol
  frog.row=(frog.row+h.drow)%16
  frog.hop=nil
  frog.delay=math.max(1,(roll()&0x1F)+0x28-difficulty_level())
  frog.clicked=false -- a new wait, a new click run
 end
 sync()
end

-- is an egg under the sitting frog? |dy| < 9 and |dx| < 12 original px
-- (S.8DF0 $8DF0 for the enemy egg, $8D93-$8DB5 for the player's)
local function on_egg(egg)
 if not (egg and egg.active and egg.dropped) then return false end
 local fx,fy=col_x(frog.col),16*frog.row+3
 local ex,ey=orig_xy(egg.x,egg.y)
 return math.abs(ey-fy)<9 and math.abs(ex-fx)<12
end

-- does the sitting frog's wait count down this frame? Only once every enemy
-- is out of the pen (RELIDX $AF < 0, $8DCD) or in the demo (ATTRACTFL $D6,
-- $8DC9); until then it is parked wherever it sits
local function wait_counts() return enemy_pen.done or attract end

-- the frog is PARKED while that gate is shut -- every round's release
-- phase, where it waits under the board (the round-start hop at FROGDELAY 0
-- also falls in it). Parked, it is neither drawn nor heard. Unparked it is
-- drawn and heard on rows 0-11, as in the original (FROGY < $B4 $B0EA). Below
-- the board (rows 12-15, off the original's screen) it scrambles through
-- short waits ($8DD3-$8DDD) unseen and unheard. A hop onto the board is
-- drawn and sounds at takeoff; a hop off it stays drawn until landing.
function frog_parked() return not wait_counts() end

-- one FROGDRIVE call: a hop in progress takes its next frame; a sitting
-- frog eats an egg under it, clicks through the last 8 frames of its wait
-- (SFX.FROGHOP $B0D5, on the board only), counts the wait down -- only once
-- every enemy is out of the pen (RELIDX $AF < 0, $8DCD) or in the demo
-- (ATTRACTFL $D6, $8DC9), and at most 15
-- frames while below the board ($8DD3-$8DDD) -- and hops when it runs out
-- (L.8E29: pure random on every 8th frame, $E4&7 = 7, else steering)
function frog_drive()
 if frog.hop then step_hop() return end

 if on_egg(enemy_egg) then -- EGGERASE $8E21
  enemy_egg.active=false
  enemy_egg.dropped=false
  snd("crunch") -- SFX.CONSUME = 5 ($8E24)
 end
 if on_egg(player_egg) then -- S.85AE $8DE6
  player_egg.active=false
  player_egg.dropped=false
  snd("crunch") -- SFX.CONSUME = 5 ($8DE9)
 end

 -- the pre-hop click run, once per wait, at the first frame it is under 8
 -- (7: on the board the wait counts down one at a time), on rows 0-11 only
 -- (FROGY < $B4) and never parked
 if not frog.clicked and frog.delay>=1 and frog.delay<=7 and frog.row<=MAZE_ROWS
    and not frog_parked() then
  frog.clicked=true
  snd("hop")
 end

 if frog.delay==0 then
  if (frame_ctr()&7)==7 then go_random() else go_steer() end
  if frog.hop then step_hop() end -- the first frame is this call's
  return
 end
 if wait_counts() then
  frog.delay=frog.delay-1
  if frog.row>=12 then frog.delay=frog.delay&0x0F end
 end
 sync()
end

-- one 30 Hz play tick: FROGDRIVE once per original frame
function update_frogs()
 frog.t=(frog.t or 0)+1/30
 while frog.t>=ORIG_FRAME_SECS do
  frog.t=frog.t-ORIG_FRAME_SECS
  frog_drive()
 end
end

-- is this snake's head on the sitting frog? The original compares exact
-- positions each frame (player $09BF-$09CB; enemies one px apart,
-- $0A6A/$0B11/$0BC6), which happens as the head reaches the frog's cell
-- centre: `arrived` is set by change_cell (snake.lua) for that tick
function head_on_frog(s)
 if frog.hop or not frog.active then return false end
 if s.cx~=frog.cx or s.cy~=frog.cy then return false end
 local x,y=get_center(s.cx,s.cy)
 return s.arrived or (s.x==x and s.y==y)
end

-- screen y of the frog's centre at (fractional) ring row r = (FROGY-3)/16.
-- Rows 1-11 are the board. Off it the frog sits in a virtual lane past the
-- edge: row 0 in the lane above row 1, moved 3 px down so more of it
-- shows over the top wall (only 2 px of screen are above the maze), and
-- 12-15 all in the lane below row 11, just off screen, so a hop between the
-- board and either lane slides
local function frog_screen_y(r)
 local function lane_y(row) return OFFSET_Y+(row-1)*CELL_H+CELL_H/2 end
 local above=lane_y(0)
 local below=lane_y(MAZE_ROWS+1)
 if r>=MAZE_ROWS+1 then return below end
 if r>MAZE_ROWS then return lane_y(MAZE_ROWS)+(below-lane_y(MAZE_ROWS))*(r-MAZE_ROWS) end
 if r<1 then return above+(lane_y(1)-above)*r end
 return lane_y(r)
end

-- draw the frog where its hop has got to, on or off the maze (FROGDRAW
-- $905E draws at any FROGY; one image per facing, $81B5/$80B9/$82B8). Its
-- wrapped FROGY picks the row: 0 is just above the maze, 12-15 below it
function draw_frogs()
 if frog_parked() then return end -- see frog_parked()
 local px=get_center(frog.cx,1)
 local _,oy=frog_orig_xy()
 local h=frog.hop
 if h then
  local done=0
  for i=1,h.n do done=done+h.deltas[i] end
  px=px+h.dcol*CELL_W*done/h.total
 end
 local r=(oy-3)/16
 -- below the board, draw hops entering or leaving it so the frog slides
 -- through the bottom edge; the scramble below stays hidden
 if r>MAZE_ROWS then
  local dest=h and (frog.row+h.drow)%16
  local leaving=h and frog.row>=1 and frog.row<=MAZE_ROWS
  if not (leaving or (dest and dest>=1 and dest<=MAZE_ROWS)) then return end
 end
 local py=frog_screen_y(r)
 -- 11x11 art centred in a 16x16 composite
 spr(SPRITE_FROG+frog.dir*2,px-8,py-8,BLACK,1,0,0,2,2)
end
