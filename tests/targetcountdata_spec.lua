-- Headless specs for ElvUI_DeSyncUI/Modules/TargetCountData.lua (Lua 5.1). Run: tests/run.py
local passed, failed = 0, 0
local T

local function setup()
  local ns = {}
  assert(loadfile(ROOT .. "/ElvUI_DeSyncUI/Modules/TargetCountData.lua"))("ElvUI_DeSyncUI", ns)
  T = ns.TargetCountData
end

local function test(name, fn)
  local ok, err = pcall(function() setup() fn() end)
  if ok then passed = passed + 1; print("PASS " .. name)
  else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end

-- targets[unit] = the nameplate token it targets; locate("<unit>target") -> plate token, refused
local function locateFrom(targets, refused)
  return function(target)
    if refused then return nil, true end
    return targets[(target:gsub("target$", ""))], false
  end
end

test("GroupUnits: party includes the player, raid uses raid tokens", function()
  assert(table.concat(T.GroupUnits(false, 2), ",") == "player,party1,party2")
  assert(table.concat(T.GroupUnits(true, 3), ",") == "raid1,raid2,raid3")
  assert(table.concat(T.GroupUnits(false, 0), ",") == "player")
end)

test("IsTank: assigned role or raid main tank", function()
  assert(T.IsTank("TANK", false) and T.IsTank("NONE", true) and T.IsTank(nil, true))
  assert(not T.IsTank("DAMAGER", false) and not T.IsTank(nil, nil))
end)

test("Count: members on each plate, tank flag on the tank's target", function()
  local members = { { unit = "player" }, { unit = "party1", tank = true }, { unit = "party2" }, { unit = "party3" } }
  local targets = { player = "nameplate1", party1 = "nameplate1", party2 = "nameplate2" }
  local res, blocked = T.Count({ "nameplate1", "nameplate2", "nameplate3" }, members, locateFrom(targets))
  assert(not blocked)
  assert(res.nameplate1.count == 2 and res.nameplate1.tank == true)
  assert(res.nameplate2.count == 1 and not res.nameplate2.tank)
  assert(res.nameplate3.count == 0 and not res.nameplate3.tank)
end)

test("Count: two tanks mark both their targets", function()
  local members = { { unit = "raid1", tank = true }, { unit = "raid2", tank = true } }
  local res = T.Count({ "nameplate1", "nameplate2" }, members,
    locateFrom({ raid1 = "nameplate1", raid2 = "nameplate2" }))
  assert(res.nameplate1.tank and res.nameplate2.tank and res.nameplate1.count == 1)
end)

test("Count: a refused lookup is reported and counts nothing", function()
  local res, blocked = T.Count({ "nameplate1" }, { { unit = "party1", tank = true } }, locateFrom({}, true))
  assert(blocked == true and res.nameplate1.count == 0 and not res.nameplate1.tank)
end)

test("Count: a target that is not one of the enemy plates counts nothing", function()
  local res = T.Count({ "nameplate1" }, { { unit = "party1" } }, locateFrom({ party1 = "nameplate9" }))
  assert(res.nameplate1.count == 0 and res.nameplate9 == nil)
end)

print(passed .. " passed, " .. failed .. " failed")
if failed > 0 then error("tests failed") end
