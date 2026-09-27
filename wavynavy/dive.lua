-- dive: the enemy flight-path bytecode VM. Paths are little programs stored
-- byte-exact in the data block ($7000-relative); one dive_tick advances one
-- enemy by one original frame. See docs/dive-path-bytecode.md.

-- quadrant-map lookup: mi 1..4 -> mapl/map86/map87 (the $88 map is
-- byte-identical to $9100, asserted at extraction, so mi 4 folds onto map86).
-- Index is the original's ((x & $f0) | (y >> 4)); coords are masked to a
-- byte so a wrapped position can't index off the page.
function dive_map(mi, ex, oy, hi16)
 local page = (mi == 4 and 1 or mi - 1)
 local v = peek(mapl_b + page * 256
   + (math.floor(ex) & 0xf0) + ((math.floor(oy) & 0xf0) >> 4))
 return (v % 16 + hi16) * 256 + (v >> 4) * 16
end

-- e.pc is a real RAM address: pbase is added at every assignment site so the
-- hot fetch stays a bare peek
function dive_start(e, off)
 e.pc = pbase + off - 1
 e.stk = {}
 e.lp = {}
 e.seg = nil
 e.mir = nil
 e.burst = 0 -- heli rounds in the current burst (bombs.lua)
 -- planes track an unwrapped x for the edge-bounce; helis keep the original's
 -- wrap-and-recycle rule and never get one
 if not e.heli then e.ex = e.ex or e.x end
end

-- the VM's own re-dive jumps ($86-$88) pick a path for the plane's real
-- column, so any edge-bounce mirror is dropped along with the old path
local function jump(e, off)
 e.pc = pbase + off - 1
 e.mir = nil
end

-- read the next bytecode byte of e's path, advancing its pc
local function fetch(e)
 e.pc = e.pc + 1
 return peek(e.pc)
end

-- the original's direction -> bank-facing map ($8D00 via $1C30/$1C3F):
-- Y = (dx CLC-ROR x5 & $F0) | (dy & $0F); a negative map value keeps the
-- current facing (BMI at $1C49)
local function ror5(a)
 local c = 0
 for _ = 1, 5 do
  local nc = a & 1
  a = (a >> 1) | (c << 7)
  c = nc
 end
 return a & 0xf0
end

function dive_facing(e, dx, dy) -- global: formation/re-descend use it too
 -- BANKCALC ($1C16): helis carry a sticky 1-bit facing, not a bank angle. A
 -- zero dx falls through at $1C1E leaving HELIFACE untouched, so the heli
 -- keeps its heading through vertical steps instead of flipping every tick.
 if e.heli then
  if dx ~= 0 then e.hface = dx < 0 and 1 or 0 end
  return
 end
 local v = peek(bank_b + (ror5(dx & 0xff) | (dy & 0x0f)))
 if v < 0x80 then e.facing = v end
end

-- step e by (dx, dy) with byte wrap, recording the step and updating its facing
local function dive_move(e, dx, dy)
 dx = dx * (e.mir or 1) -- edge-bounce mirror, see dive_bounce
 e.x = (e.x + dx) % 256
 e.y = (e.y + dy) % 256
 if e.ex then e.ex = e.ex + dx end
 e.fdx = dx
 e.fdy = dy
 dive_facing(e, dx, dy)
end

-- horizontally offscreen. Planes: the whole 16-px glyph (drawn at scrx(x)-8)
-- has cleared the field, judged on the unwrapped ex so a left exit isn't
-- misread as the right side. Helis: the original's rule - x wraps at 256, so
-- an exit on either side lands in 246..255.
local offx_lo = fld_x0 - 10  -- half-glyph in world coords (~8/scale_x)
local offx_hi = fld_x1 + 10
function dive_offx(e)
 if not e.ex then return e.x >= 246 end
 return e.ex < offx_lo or e.ex > offx_hi
end

-- reverse a diving plane's horizontal direction once it is fully offscreen.
-- A persistent mirror rather than a one-off flip: the VM re-reads inline
-- steps from bytecode every tick, so only a factor applied inside dive_move
-- turns the *rest* of the path around too (a segment-only flip left planes
-- drifting outward, unseen, through runs of raw moves).
function dive_bounce(e)
 e.mir = -(e.mir or 1)
end

-- a bounced plane's path was written to end offscreen, so its $80 can now
-- arrive with the plane in full view: instead of vanishing it re-dives from
-- the $86 map - the original's own mid-flight "re-read the player" jump
function dive_redive(e)
 dive_start(e, dive_map(2, e.x, p_x, 0))
end

-- true once e has dropped off the bottom of the field (y in 192..207)
function dive_offy(e)
 return e.y >= 192 and e.y < 208
end

-- run one original frame of dive; false = dive over (end op or off bottom).
-- ops $80-$88 move/loop/call/re-dive; $7c-$7f puff/bomb; else raw dx,dy.
-- horizontal offscreen is handled by the caller (dive_bounce), not here.
function dive_tick(e)
 for _ = 1, 48 do
  -- a repeated segment ($81) in progress takes this frame's move
  if e.seg then
   local s = e.seg
   dive_move(e, s[1], s[2])
   s[3] = s[3] - 1
   if s[3] <= 0 then e.seg = nil end
   return not dive_offy(e)
  end
  local b = fetch(e)
  if b == 0x80 then -- end of path
   return false
  elseif b == 0x81 then -- segment: dx, dy, repeat count
   local dx, dy = sgnb(fetch(e)), sgnb(fetch(e))
   e.seg = {dx, dy, math.max(1, fetch(e))}
  elseif b == 0x82 then -- loop start: n passes
   local n = fetch(e)
   table.insert(e.lp, {e.pc, n}) -- pc points at n: loop-end resumes after it
   e.burst = 0 -- each $8C00-$8C80 burst is one loop: a new loop, a new burst
  elseif b == 0x83 then -- loop end: jump back until the count runs out
   local l = e.lp[#e.lp]
   if l then
    l[2] = l[2] - 1
    if l[2] > 0 then
     e.pc = l[1]
    else
     table.remove(e.lp)
    end
   end
  elseif b == 0x84 then -- call subpath at $hilo (a $7000-relative address)
   local hi, lo = fetch(e), fetch(e)
   table.insert(e.stk, e.pc)
   e.pc = pbase + (hi - 0x70) * 256 + lo - 1
  elseif b == 0x85 then -- return from subpath
   if #e.stk > 0 then
    e.pc = table.remove(e.stk)
   end
  elseif b == 0x86 then -- re-dive at the player's column
   jump(e, dive_map(2, e.x, p_x, 0))
  elseif b == 0x87 then -- re-dive, only on waves that enable it (never on eased beginner waves)
   if wcfg_f87[math.min(wave, 10)] == 1 and not beg_eased() then
    jump(e, dive_map(3, e.x, p_x, 0))
   end
  elseif b == 0x88 then -- re-dive via the $88 map (paths 16 pages higher)
   jump(e, dive_map(4, e.x, p_x, 16))
  elseif b == 0x7c then -- sky-writing smoke puff
   add_puff(e.x, e.y)
   e.pf = title_t -- last-puff frame; the title finds the final dive with it
  elseif b >= 0x7d and b <= 0x7f then -- bomb drop
   drop_bomb(e, b)
  else -- raw move: this byte is dx, the next is dy
   dive_move(e, sgnb(b), sgnb(fetch(e)))
   return not dive_offy(e)
  end
 end
 return false -- runaway guard, never hit on valid data
end
