-- bombs: the shared pool every dropper feeds - dive-op bombs ($7D/$7E),
-- aimed dive-bombs ($7F), heli bomb strings, and the bomber's string

-- enemy e drops a bomb for dive op $7D-$7F (straight down, or $7F aimed at the player)
function drop_bomb(e, op)
 if op == 0x7d and (wcfg_bomb[math.min(wave, 10)] == 0 or e.heli) then return end
 -- helis fire strings of rounds. NOT original behaviour: the disassembly fires
 -- one round per dive-op $7F ungated, and because dive_tick runs the bytecode
 -- until a MOVE opcode, several $7F can fire in a single oframe - so e.bt is 0
 -- for all of them and a frame-count gate cannot space them. Gate on how far
 -- the previous round has actually fallen instead (see constants.lua)
 if e.heli then
  -- e.bt = oframes since this heli last fired (enemies.lua). The previous
  -- round has fallen bomb_dy*e.bt apple px in that time, so requiring
  -- heli_round_gap ticks spaces the string by bomb_dy*heli_round_gap px
  if (e.bt or 999) < heli_round_gap then return end
  -- beginner: cap each burst (e.burst counts rounds since the burst loop's
  -- $82, reset in dive.lua) at the early waves' longest string
  if diff == 0 and (e.burst or 0) >= beg_heli_burst then return end
  e.burst = (e.burst or 0) + 1
  e.bt = 0
  heli_fire_round() -- one ch1 report per round, as the original's $0F99 (sfx.lua)
 end
 if #bombs >= 32 then return end -- original: two 16-slot pools
 local dx, dy = 0, bomb_dy
 if op == 0x7f then
  -- dive-bomb aimed at the player's column via the $8F00 table ($0F78/$1C50)
  -- indexed by (dropper column, player column); the byte packs signed dx
  -- in the high nibble and dy in the low
  local v = peek(aim_b + math.floor(e.x / 16) * 16 + math.floor(p_x / 16))
  dy = v % 16
  dx = v >> 4
  if dx >= 8 then dx = dx - 16 end
 end
 -- aimed dive-bombs draw green, chopper rounds as bare pixels. px/py seed
 -- the draw interpolation: bombs_tick moves the bomb later this same otick,
 -- so an unseeded bomb hangs frozen under the dropper for its first tick
 local w = math.min(wave, 10)
 local bc = e.heli and 14
          or w == 4 and 9
          or (w >= 5 and not e.heli and e.ty > 0x2a) and 14
          or 11
 table.insert(bombs, {x = e.x, y = e.y + 4, px = e.x, py = e.y + 4,
                      dx = dx, dy = dy,
                      grn = op == 0x7f and not e.heli, heli = e.heli,
                      bc = bc})
end

-- move every bomb one tick; remove it when it hits the boat or splashes into the sea
function bombs_tick()
 prune(bombs, function(b)
  b.x = b.x + b.dx
  b.y = b.y + b.dy
  if p_st == 0 and math.abs(b.x - p_x) < 8 and math.abs(b.y - p_y) < 5 then
   boom(p_x, p_y) -- orange hazard blast at the impact, as the mine does
   psfx(sfx_bombsplash)
   player_hit()
   return false
  elseif b.y >= waves_y(b.x) then
   splash(b.x)
   psfx(sfx_bombsplash)
   return false
  end
  return true
 end)
end

-- draw every bomb: finned sprites (recoloured per dropper) or 2x2 heli rounds;
-- the finned sprite is solid, never striped, on a mono monitor (the heli
-- rounds already are: white)
function bombs_draw()
 for _, b in ipairs(bombs) do
  local x, y = scrx(lerpd(b.px, b.x)), scry(lerpd(b.py, b.y))
  if b.heli then -- chopper rounds are 2x2 blocks, not finned bombs
   -- S.5B74 ($5B74) plots four pixels around the bomb's stored position:
   -- (x,y), (x+1,y), (x+1,y-1), (x,y-1) -- a 2x2 square whose origin is its
   -- BOTTOM-left. Two apple px scale to 1.6 wide / 1.5 tall, so 2x2 screen
   -- px is the honest render; rect keeps the pair square as the original reads
   rect(x, y - 1, 2, 2, 7)
  else
   if b.bc and b.bc ~= 14 then pal(14, b.bc) end
   if b.grn then pal(7, 11) end
   mono.draw_solid(spr, 256 + spr_bomb, x - 3, y - 2, 0)
   if (b.bc and b.bc ~= 14) or b.grn then pal_reset() end
  end
 end
end
