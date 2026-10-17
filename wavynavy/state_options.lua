-- BOOT stores apple2.boot's capability table as a2_display. Without
-- alt_display, THEME is dimmed, skipped and cannot change.
-- options: the options page, opened with B from the title (a port addition;
-- the original sets difficulty with menu keys 5/6/7). Difficulty, theme
-- (THEME_NAMES: a2boot.lua's colour / green / white Apple II monitor) and a
-- hiscore reset. Up/down picks a row, A or right steps it forward, left back
-- (both settings wrap; the on-screen help names only A), B returns to the
-- settled title. RESET HISCORE is greyed out and skipped by up/down while
-- there is no high score; while it is picked a small-font line says what it
-- clears; clearing it puts the cursor back on the first row. Every change is
-- saved to pmem at once; a difficulty change takes effect from the next game.

local ROWS = {"DIFFICULTY", "THEME", "RESET HISCORE"}
local DIFF, THEME, RESET = 1, 2, 3
local ROW_Y, ROW_DY = 48, 9 -- first row's y, px between rows (all clear of the swell)
-- labels (cursor 8 px left of them), values: cursor + widest label + 8 +
-- widest value (PRESS A TO RESET) stays inside the playfield, so nothing
-- spills into the black side rails. Both are offsets from the field's left edge
local LABEL_DX, VALUE_DX = 16, 98
local CLEARED_FRAMES = 90 -- how long "CLEARED" shows after a reset
local DISABLED_C = COLOR_SLOT_5 -- a row with nothing to do (RESET HISCORE with no hiscore): dark grey
local RESET_HINT = "CLEARS THE SAVED HISCORE"
local HINT_Y = 75 -- the hint's row, between the reset row and the help
-- the control help, one line each, centred as a block with the dashes aligned
local HELP = {{"UP/DOWN", "SELECT"}, {"A BUTTON", "CHANGE"}, {"B BUTTON", "GO BACK"}}
local HELP_Y, HELP_DY = 85, 9 -- first help line's y, px between lines (clear of the swell)

local sel, confirm, cleared = 1, false, 0

-- enter the options page on its first row, the sea still rolling
function options_init()
 sel, confirm, cleared = 1, false, 0
 sea_ph = sea_ph or 0
end

-- change the highlighted row's setting by d (+1 or -1), wrapping; persisted
local function change(d)
 if sel == THEME and not a2_display.alt_display then return end
 if sel == DIFF then
  diff = (diff + d) % #DIFF_NAMES
  pmem(1, diff)
 elseif sel == THEME then
  theme = (theme + d) % #THEME_NAMES
  mono.set(theme) -- applied from this frame's mono.apply
  pmem(2, theme)
 else
  return
 end
 psfx(SFX_BLIP)
end

-- row i can be picked: RESET HISCORE only while there is a high score to wipe
local function enabled(i)
 if i == THEME then return a2_display.alt_display end
 return i ~= RESET or hi > 0
end

-- move the highlight by d rows, wrapping and skipping disabled rows
local function step(d)
 local i = sel
 repeat i = (i - 1 + d) % #ROWS + 1 until enabled(i) or i == sel
 sel = i
end

-- B leaves; up/down moves the highlight; left/right/A change or arm/confirm the reset
function options_update()
 local dt = frame_dt()
 sea_ph = sea_ph - 0.5 * dt
 if cleared > 0 then cleared = cleared - dt end
 if bp() then goto_title_settled() return end
 if btnp(0) or btnp(1) then
  step(btnp(0) and -1 or 1)
  confirm = false
 elseif lp() or rp() then
  change(lp() and -1 or 1)
 end
 if xp() and enabled(sel) then
  if sel == RESET then
   psfx(SFX_BLIP)
   if confirm then
    hi, prev_hi = 0, 0
    pmem(0, 0)
    cleared = CLEARED_FRAMES
    sel = 1 -- the row is disabled now: back to the first one
   end
   confirm = not confirm
  else
   change(1)
  end
 end
end

-- the setting shown to the right of row i
local function value(i)
 if i == DIFF then return DIFF_NAMES[diff + 1] end
 if i == THEME then return a2_display.alt_display and THEME_NAMES[theme + 1] or "UNAVAILABLE" end
 if i == RESET then
  if confirm then return "PRESS A AGAIN" end
  if cleared > 0 then return "CLEARED" end
  if i == sel then return "PRESS A TO RESET" end
 end
 return ""
end

-- the rows with their cursor and values, the reset hint, and the key help
function options_draw()
 tbl_head("OPTIONS")
 local lx, vx = FLD_OX + LABEL_DX, FLD_OX + VALUE_DX
 for i, label in ipairs(ROWS) do
  local y = ROW_Y + (i - 1) * ROW_DY
  local c = not enabled(i) and DISABLED_C or i == sel and COLOR_SLOT_10 or COLOR_SLOT_7
  if i == sel then print(">", lx - 8, y, c) end
  print(label, lx, y, c)
  print(value(i), vx, y, c)
 end
 if sel == RESET then
  local w = print(RESET_HINT, 0, -8, COLOR_SLOT_15, false, 1, true)
  print(RESET_HINT, fld_cx(w), HINT_Y, COLOR_SLOT_5, false, 1, true)
 end
 -- keys right-aligned to a shared dash column, the block centred on the field
 local kw, aw = 0, 0
 for _, h in ipairs(HELP) do
  kw = math.max(kw, print(h[1], 0, -8, COLOR_SLOT_15))
  aw = math.max(aw, print(" - " .. h[2], 0, -8, COLOR_SLOT_15))
 end
 local dx = fld_cx(kw + aw) + kw
 for i, h in ipairs(HELP) do
  local y = HELP_Y + (i - 1) * HELP_DY
  print(h[1], dx - print(h[1], 0, -8, COLOR_SLOT_15), y, COLOR_SLOT_5)
  print(" - " .. h[2], dx, y, COLOR_SLOT_5)
 end
end
