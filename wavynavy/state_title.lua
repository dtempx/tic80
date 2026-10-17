-- title: two planes sky-write WAVY NAVY through the dive VM (the original's
-- $8800/$8A00 paths stamping $7C puffs), then the credits reveal

local ORIG_TXT = "ORIGINAL BY RODNEY MCAULEY (1983)"

-- start the two sky-writing planes on their paths and reset the credit reveal
function title_init()
 title_t = 0
 fx_init() -- resolves the blast base addrs: the title draws booms before play does
 tbooms = {}
 title_acc = 0
 sea_ph = 0
 p_x = 0x70 -- VM re-dive safety (title dives don't home)
 tplanes = {{x = 0x10, y = 0xe1, facing = 0}, {x = 0xb0, y = 0xe1, facing = 0}}
 dive_start(tplanes[1], 0x1800)
 dive_start(tplanes[2], 0x1a00)
 tdone = false
 tdone_t = 0
 converge = false -- finale: both planes converge to centre
 cx = 0
 lfast_t = nil -- frame the left plane latched to 2x (cues the right)
 show_orig = false
 show_remake = false
 remake_t = 0
 rplane_x = nil -- flyby that wipes in the "remake by" line
end

-- run one plane's dive ticks, latching 2x once its lettering ends: a >=20-run
-- of same-direction top-level moves past the first puff is the pull-away
local function title_step(e)
 if not dive_tick(e) then e.done = true end
 if #e.stk == 0 and e.fdx == e.ldx and e.fdy == e.ldy then
  e.run = (e.run or 0) + 1
 else
  e.run = 0
  e.ldx = e.fdx
  e.ldy = e.fdy
 end
 if e.run >= 20 and e.pf then
  e.fast = true
  lfast_t = lfast_t or title_t -- the left plane finishes writing first
 end
end

-- skip the intro to the settled title (B and the options page land here):
-- run each plane's writing to its end so the name cloud is fully formed
function title_settle()
 for _, e in ipairs(tplanes) do
  for _ = 1, 4000 do
   if e.done or (e.run or 0) >= 20 and e.pf then break end
   title_step(e)
  end
 end
 tdone = true
 tdone_t = EXPL_OF + 24 -- past the "original by" fade so it shows fully lit
 show_orig = true
 show_remake = true
 remake_t = title_t
 tbooms = {}
 tplanes = {}
end

-- run the sky-writing, the finale and credit reveal, and the title's inputs
function title_update()
 local dt = frame_dt() -- dt: intro pacing holds real seconds at any fps
 title_t = title_t + dt
 sea_ph = sea_ph - 0.5 * dt -- title swell scrolls right at the fast wave speed
 if not tdone then
  title_acc = title_acc + TITLE_VSPEED * dt
  local steps = math.floor(title_acc)
  title_acc = title_acc - steps
  local fin = false
  if converge then
   -- half-gap cx -> 0: the planes meet nose-to-nose at apple x=123
   cx = math.max(0, cx - 4 * steps)
   tplanes[1].x = 123 - cx
   tplanes[2].x = 123 + cx
   if cx <= 0 then fin = true end
  else
   -- cue the right plane to 2x 22f after the left latches
   if lfast_t and title_t >= lfast_t + 22 then tplanes[2].fast = true end
   for _, e in ipairs(tplanes) do
    if not e.done and not converge then
     for _ = 1, steps * (e.fast and 2 or 1) do
      if not e.done then title_step(e) end
      -- dive bottomed out: snap both symmetric about centre and converge
      if e.fast and e.fdy == 0 and e.y > 100 then
       tplanes[1].x = 24
       tplanes[1].y = 110
       tplanes[1].fdx = 2
       tplanes[1].facing = 0
       tplanes[2].x = 222
       tplanes[2].y = 110
       tplanes[2].fdx = -2
       tplanes[2].facing = 8
       converge = true
       cx = 99
      end
     end
    end
   end
  end
  if fin then
   tdone = true
   -- combust across the credit line (screen y 72 -> apple space)
   for i = 0, 5 do
    table.insert(tbooms, {x = 45 + i * 31, y = 98, ph = 0})
   end
  end
 else
  tdone_t = tdone_t + dt
  if tdone_t >= EXPL_OF then
   show_orig = true
   -- hold 1.5s after "original by" before launching the flyby
   if not rplane_x and tdone_t >= EXPL_OF + 90 then rplane_x = -8 end
  end
  if rplane_x and not show_remake then
   rplane_x = rplane_x + 2 * dt -- fly l->r, wiping in the "remake by" line
   if rplane_x > 250 then
    show_remake = true
    remake_t = title_t
   end
  end
 end
 prune(tbooms, function(b) b.ph = b.ph + 0.5 * dt return b.ph < EXPL_OF end)
 -- A starts, B opens the options page; the hold advances to the demo. The
 -- 20-frame grace keeps a press carried in from game over from acting here
 if title_t > 20 then
  if xp() then
   start_game()
  elseif bp() then
   goto_options()
  elseif show_remake and title_t >= remake_t + 300 then
   goto_demo()
  end
 end
end

-- draw the sea, the smoke lettering, the planes or the credits and prompts
function title_draw()
 cls(COLOR_SLOT_0)
 clip_field()
 waves_draw()
 clip()
 hitop()
 clip_field() -- the skywriting is world space; the text below is not
 draw_puffs(6) -- nudged above the sea
 for _, b in ipairs(tbooms) do
  draw_boom(b.x, b.y, b.ph, xpl_p, COLOR_SLOT_9)
 end
 clip()
 if tdone then
  if show_orig then
   -- fade the credit up out of the smoke: dark -> grey -> brown -> orange
   local ramp = {COLOR_SLOT_1, COLOR_SLOT_5, COLOR_SLOT_4, COLOR_SLOT_9}
   cprint(ORIG_TXT, 69, ramp[math.min((tdone_t - EXPL_OF) // 8 + 1, 4)])
  end
  if show_remake then
   cprint("REMAKE BY DAVE TEMPLIN", 78, COLOR_SLOT_14)
   -- three 9 px lines ending at y=109, clear of the swell's highest crest
   -- (screen y 113)
   if time() % 1000 < 600 then
    cprint("PRESS A TO START", 87, COLOR_SLOT_7)
    cprint("OR PRESS B FOR OPTIONS", 96, COLOR_SLOT_7)
   end
   -- the current difficulty, steady under the blinking prompts
   cprint("DIFFICULTY: " .. DIFF_NAMES[diff + 1], 105, COLOR_SLOT_6)
  elseif rplane_x then
   -- reveal the remake line left of the flyby, then the plane
   clip(0, 78, math.max(rplane_x, 0), 8)
   cprint("REMAKE BY DAVE TEMPLIN", 78, COLOR_SLOT_14)
   clip_field()
   spr(SPRITE_BANK + SPRITE_PLANE, rplane_x - 8, 72, COLOR_SLOT_0, 1, 0, 0, 2, 2)
   clip()
  end
 else
  for _, e in ipairs(tplanes) do
   if not e.done then
    local f = e.facing or 0
    local base = f < 8 and 2 * f or 32 + 2 * (f - 8)
    spr(SPRITE_BANK + SPRITE_PLANE + base, scrx(e.x) - 6, scry(e.y) - 11, COLOR_SLOT_0, 1, 0, 0, 2, 2)
   end
  end
 end
end
