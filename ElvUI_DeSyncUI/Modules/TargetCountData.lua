local ADDON, ns = ...
-- Who in the group targets which enemy nameplate. Plain Lua: tests/targetcountdata_spec.lua runs it headless.
local T = {}
ns.TargetCountData = T

-- party: the player is not in party1..4, so add it; raid: raid1..N already include the player
function T.GroupUnits(inRaid, n)
  local units = {}
  if not inRaid then units[1] = "player" end
  for i = 1, n do units[#units + 1] = (inRaid and "raid" or "party") .. i end
  return units
end

function T.IsTank(role, mainTank)
  return role == "TANK" or mainTank == true
end

-- plates: { nameplate tokens }; members: { { unit, tank } }
-- locate("<unit>target") -> plate token of that target (or nil), refused (the game hid it every way)
-- returns { [plate] = { count, tank } }, blocked
function T.Count(plates, members, locate)
  local res, blocked = {}, false
  for _, p in ipairs(plates) do res[p] = { count = 0, tank = false } end
  for _, m in ipairs(members) do
    local p, refused = locate(m.unit .. "target")
    if refused then
      blocked = true
    elseif p and res[p] then
      res[p].count = res[p].count + 1
      if m.tank then res[p].tank = true end
    end
  end
  return res, blocked
end

-- Dungeons hide every target but keep threat readable (seen in game), so there the counter works from threat.
-- threat(unit, mob) -> status 0..3 (nil when not on the mob's threat table), value (raw threat; nil when hidden).
-- In combat the game lists every group member on every mob of the pack with zero threat (seen in game),
-- so count = members with threat value > 0 on that mob (they hit or healed against it); when the value is
-- hidden, being on the table counts. tank = the tank holds it (2 or 3),
-- loose = someone else holds it; only when the group has a known tank.
-- returns { [plate] = { count, tank, loose } }
function T.CountThreat(plates, members, threat)
  local res, anyTank = {}, false
  for _, m in ipairs(members) do anyTank = anyTank or m.tank end
  for _, p in ipairs(plates) do
    local count, holder, best = 0, nil, 1
    for _, m in ipairs(members) do
      local s, value = threat(m.unit, p)
      if s then
        if value == nil or value > 0 then count = count + 1 end
        if s > best then holder, best = m, s end
      end
    end
    res[p] = {
      count = count,
      tank = holder ~= nil and holder.tank == true,
      loose = anyTank and holder ~= nil and not holder.tank or false,
    }
  end
  return res
end
