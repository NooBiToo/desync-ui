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
