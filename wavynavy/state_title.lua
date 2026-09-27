-- title: two planes sky-write WAVY NAVY through the dive VM (the original's
-- $8800/$8A00 paths stamping $7C puffs), then the credits reveal

local orig_txt = "ORIGINAL BY RODNEY MCAULEY"

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
 diff_blink = 0
 hs_t = 0
 disp_t = 0
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

-- skip the intro to the settled title (difficulty changes bounce back here):
-- run each plane's writing to its end so the name cloud is fully formed
function title_settle()
 for _, e in ipairs(tplanes) do
  for _ = 1, 4000 do
   if e.done or (e.run or 0) >= 20 and e.pf then break end
   title_step(e)
  end
 end
 tdone = true
 tdone_t = expl_of + 24 -- past the "original by" fade so it shows fully lit
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
 if diff_blink > 0 then diff_blink = diff_blink - dt end
 sea_ph = sea_ph - 0.5 * dt -- title swell scrolls right at the fast wave speed
 if not tdone then
  title_acc = title_acc + title_vspeed * dt
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
  if tdone_t >= expl_of then
   show_orig = true
   -- hold 1.5s after "original by" before launching the flyby
   if not rplane_x and tdone_t >= expl_of + 90 then rplane_x = -8 end
  end
  if rplane_x and not show_remake then
   rplane_x = rplane_x + 2 * dt -- fly l->r, wiping in the "remake by" line
   if rplane_x > 250 then
    show_remake = true
    remake_t = title_t
   end
  end
 end
 prune(tbooms, function(b) b.ph = b.ph + 0.5 * dt return b.ph < expl_of end)
 -- either button starts; left/right step difficulty; hold advances to demo
 if title_t > 20 and not combo_tick() then
  if xp() then
   start_game()
  elseif lp() or rp() then
   set_diff(lp() and -1 or 1)
   if not show_remake then title_settle() end
   remake_t = title_t -- restart the pre-demo hold
  elseif show_remake and title_t >= remake_t + 300 then
   goto_demo()
  end
 end
end

-- difficulty readout: name (blinks 2s after a change) + hint
local function diff_draw()
 if diff_blink <= 0 or time() % 500 < 300 then
  cprint("DIFFICULTY: " .. diff_names[diff + 1], 95, 10)
 end
 cprint("<- / -> TO CHANGE DIFFICULTY", 103, 5)
end

-- draw the sea, the smoke lettering, the planes or the credits and prompts
function title_draw()
 cls(0)
 clip_field()
 waves_draw()
 clip()
 hitop()
 clip_field() -- the skywriting is world space; the text below is not
 draw_puffs(6) -- nudged above the sea
 for _, b in ipairs(tbooms) do
  draw_boom(b.x, b.y, b.ph, xpl_p, 9)
 end
 clip()
 if tdone then
  if show_orig then
   -- fade the credit up out of the smoke: dark -> grey -> brown -> orange
   local ramp = {1, 5, 4, 9}
   cprint(orig_txt, 68, ramp[math.min((tdone_t - expl_of) // 8 + 1, 4)])
  end
  if show_remake then
   cprint("REMAKE BY DAVE TEMPLIN", 78, 14)
   if diff_blink > 0 or time() % 1000 < 600 then
    cprint("PRESS FIRE TO START", 87, 7)
   end
   diff_draw()
  elseif rplane_x then
   -- reveal the remake line left of the flyby, then the plane
   clip(0, 78, math.max(rplane_x, 0), 8)
   cprint("REMAKE BY DAVE TEMPLIN", 78, 14)
   clip_field()
   spr(256 + spr_plane, rplane_x - 8, 72, 0, 1, 0, 0, 2, 2)
   clip()
  end
 else
  for _, e in ipairs(tplanes) do
   if not e.done then
    local f = e.facing or 0
    local base = f < 8 and 2 * f or 32 + 2 * (f - 8)
    spr(256 + spr_plane + base, scrx(e.x) - 6, scry(e.y) - 11, 0, 1, 0, 0, 2, 2)
   end
  end
 end
end
