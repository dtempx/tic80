-- door.lua
-- animated pen doors: knock -> wait -> open -> hold until the tail clears -> close
-- (B's door state machine): the original has one enemy pen door, maze cell
-- PENDOORCELL $A471, opened/shut by the release script ($8ABA/$8AC5/$8AD0), and a
-- player entry door animated by S.887F $887F / S.88B9 $88B9.

ENEMY_DOOR1 ={cx=1, cy=12} -- enemy pen, bottom row
ENEMY_DOOR2 ={cx=1, cy=9}  -- enemy chute into the maze (orig chute cell (8,0), PENDOORCELL $A471)
PLAYER_DOOR1={cx=11,cy=12} -- player pen entry, bottom-left (S.887F/S.88B9; snake_pen.lua drives it)
PLAYER_DOOR2={cx=13,cy=9}  -- player chute into the maze (orig one-way-up cell (8,12), disasm README 2.1)

doors_list={ENEMY_DOOR1,ENEMY_DOOR2,PLAYER_DOOR1,PLAYER_DOOR2}

-- the player pen's LEFT-wall door, on the left edge of cell (11,11): only the
-- hatched snake uses it (HGR byte column $1E rows 178-187, parted from the
-- middle out over five frames at $1C2C-$1C60, shut again at $1C7F-$1CB3).
-- Not in doors_list: movement never consults it (state_hatch.lua walks the
-- snake through), grid.lua draws it in place of that wall
PLAYER_DOOR3={cx=11,cy=11,open_amt=0}

-- shut every door (round init writes the pen door cell 0 = shut, $86A9)
function init_doors()
 for _,d in ipairs(doors_list) do
  d.state=0 -- 0 shut, 1 knocked, 2 opening, 3 open, 4 closing
  d.timer=0
  d.open_amt=0 -- 0..1 opening; orig pen door cell $A471 is 0 shut or 8 open
  d.triggering_snake=nil
 end
 PLAYER_DOOR3.open_amt=0
end

-- column of the enemy ("left") or player pen door (helper)
function get_bottom_door_x(side)
 if side=="left" then return ENEMY_DOOR1.cx else return PLAYER_DOOR1.cx end
end

-- the door on the top edge of cell (cx,cy), or nil (door lookup)
function get_door(cx,cy)
 for _,d in ipairs(doors_list) do
  if d.cx==cx and d.cy==cy then return d end
 end
 return nil
end

-- has snake s gone wholly through door d (the 2 px bar on the top edge of
-- its cell)? True once the tail ball's bottom row is above the bar, or when
-- there is no live snake to wait for. Every door that shuts behind a snake
-- asks this, so none can close on one
function door_cleared(d,s)
 if not s or s.dead then return true end
 local tail=s.body[s.length]
 if not tail then return true end
 return tail.y+SEG_R<OFFSET_Y+(d.cy-1)*CELL_H
end

-- a snake knocks on a shut door: start the 1 s wait before it opens
-- (the original opens the enemy door from the release clock, $AE=$60 at $8ABA)
function trigger_door(cx,cy,snake)
 -- no physics triggers while the pregame queue is staged
 if game_state=="PREGAME" then return end

 local d=get_door(cx,cy)
 if d and d.state==0 and not d.scripted then -- enemy_pen.lua owns scripted doors
  d.state=1
  d.timer=30 -- 1s knock-to-open wait
  d.triggering_snake=snake
 end
end

-- advance every door's state machine one tick (original door frames PENDOOR $8ABA)
function update_doors()
 -- the in-maze chute doors also open for a snake standing on their cell;
 -- the release script's doors (enemy_pen.lua) never do
 if game_state=="PLAY" then
  for _,d in ipairs({ENEMY_DOOR2,PLAYER_DOOR2}) do
   if d.state==0 and not d.scripted then
    local s=nil
    if player.cx==d.cx and player.cy==d.cy and not player.dead then
     s=player
    else
     for _,e in ipairs(enemies) do
      if e.cx==d.cx and e.cy==d.cy and not e.dead then
       s=e
       break
      end
     end
    end
    if s then
     d.state=1
     d.timer=30
     d.triggering_snake=s
    end
   end
  end
 end

 for _,d in ipairs(doors_list) do
  if d.scripted then
   -- frames and passability come from the release script
  elseif d.state==1 then
   d.timer=d.timer-1
   if d.timer<=0 then
    d.state=2
   end

  elseif d.state==2 then
   -- opening over 1s
   d.open_amt=d.open_amt+1.0/30.0
   if d.open_amt>=1.0 then
    d.open_amt=1.0
    d.state=3
    if d.triggering_snake and not d.triggering_snake.dead then
     d.triggering_snake.moving=true
    end
   end

  elseif d.state==3 then
   -- fully open: wait for the trailing segment to clear the threshold
   if door_cleared(d,d.triggering_snake) then d.state=4 end

  elseif d.state==4 then
   -- slamming shut
   d.open_amt=d.open_amt-1.0/30.0
   if d.open_amt<=0.0 then
    d.open_amt=0.0
    d.state=0
    d.triggering_snake=nil
   end
  end
 end
end
