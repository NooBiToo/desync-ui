-- Headless specs for ElvUI_DeSyncUI/Modules/TargetCount.lua (Lua 5.1) with widget stubs.
local passed, failed = 0, 0
local mod, said, timers, eventFrame, plates, targets, roles, inGroup, inRaid, canCompare, markPos
local plateLookup, guidOpen
local registered, moddb = {}, nil
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })

local function obj(parent)
  local o = { shown = true, scripts = {}, parent = parent }
  local methods = {
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    SetShown = function(self, v) self.shown = v and true or false end,
    IsShown = function(self) return self.shown end,
    IsVisible = function(self) return self.shown end,
    SetText = function(self, t) self.text = t end,
    SetTexture = function(self, t) self.texture = t end,
    SetPoint = function(self, _, rel) self.anchor = rel end,
    ClearAllPoints = function(self) self.anchor = nil end,
    SetScript = function(self, k, fn) self.scripts[k] = fn end,
    -- the module's main frame; the combat-log probe has a frame of its own
    RegisterEvent = function(self, e)
      if e ~= "COMBAT_LOG_EVENT_UNFILTERED" then eventFrame = self end
      registered[e] = true
    end,
    CreateTexture = function() return obj() end,
    CreateFontString = function() return obj() end,
  }
  -- Forever forbids measuring nameplate regions (seen in game: "Can't measure restricted regions")
  for _, m in ipairs({ "GetLeft", "GetRight", "GetTop", "GetBottom", "GetCenter", "GetRect",
                       "GetWidth", "GetHeight", "GetSize", "GetBoundsRect" }) do
    methods[m] = function() error("Action[FrameMeasurement] failed because[Can't measure restricted regions]") end
  end
  return setmetatable(o, { __index = function(_, k)
    if methods[k] then return methods[k] end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end

local function flush()
  local list = timers; timers = {}
  for _, fn in ipairs(list) do fn() end
end

local function plate(token, hostile)
  local uf = obj()
  uf.Health = obj()  -- ElvUI's frame has no .unit in Forever (diag: ufUnit = nil)
  uf.RaidTargetIndicator = false  -- fields, not methods: nothing until a test adds one
  uf.TargetIndicator = false
  return { unitToken = token, unitFrame = uf, hostile = hostile ~= false }  -- Forever field name
end

local function setup(opts)
  opts = opts or {}
  said, timers, eventFrame, registered = {}, {}, nil, {}
  inGroup, inRaid, canCompare, markPos = true, false, true, "LEFT"  -- ElvUI default mark position
  plateLookup, guidOpen = true, true  -- each way of finding a target's plate can be refused separately
  plates = { plate("nameplate1"), plate("nameplate2"), plate("nameplate3", false) }
  -- player and party2 on nameplate1, party1 (tank) on nameplate2
  targets = { player = "nameplate1", party1 = "nameplate2", party2 = "nameplate1" }
  roles = opts.roles or { party1 = "TANK" }

  IsInGroup = function() return inGroup end
  IsInRaid = function() return inRaid end
  GetNumSubgroupMembers = function() return 2 end
  GetNumGroupMembers = function() return 3 end
  UnitGroupRolesAssigned = function(u) return roles[u] or "NONE" end
  GetPartyAssignment = function() return false end
  C_Secrets = { CanCompareUnitTokens = function() return canCompare end }
  IsInInstance = function() return false end
  UnitThreatSituation = function() return nil end
  UnitDetailedThreatSituation = nil
  issecretvalue = function(v) return v == SECRET end
  UnitExists = function(u)
    if u:find("^nameplate%d+$") then
      for _, p in ipairs(plates) do if p.unitToken == u then return true end end
      return false
    end
    return targets[u:gsub("target$", "")] ~= nil
  end
  UnitIsUnit = function(a, b) return targets[a:gsub("target$", "")] == b end
  UnitGUID = function(u)
    if not guidOpen then return SECRET end
    local member = u:match("^(.+)target$")
    if member then u = targets[member] end
    return u and ("Creature-0-" .. u) or nil
  end
  UnitCanAttack = function(_, u)
    for _, p in ipairs(plates) do if p.unitToken == u then return p.hostile end end
  end
  -- like Forever: plates carry unitToken, not namePlateUnitToken
  C_NamePlate = {
    GetNamePlates = function() return plates end,
    GetNamePlateForUnit = function(u)
      local member = u:match("^(.+)target$")
      if member then
        if not plateLookup then return nil end
        u = targets[member]
      end
      for _, p in ipairs(plates) do if p.unitToken == u then return p end end
    end,
  }
  C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
  SlashCmdList = {}
  CreateFrame = function(_, _, parent) return obj(parent) end
  ElvUI = { {
    private = { nameplates = { enable = opts.platesOff ~= true } },
    Media = { Textures = { Tank = "TankTex", DPS = "DpsTex" } },
    GetModule = function(_, n)
      if n == "NamePlates" then
        return { PlateDB = function() return { raidTargetIndicator = { position = markPos } } end }
      end
    end,
  } }

  local ns = { say = function(...) said[#said + 1] = table.concat({ ... }, " ") end }
  ns.NewModule = function(name, def) def.name = name; mod = def; return def end
  for _, f in ipairs({ "TargetCountData.lua", "TargetCount.lua" }) do
    assert(loadfile(ROOT .. "/ElvUI_DeSyncUI/Modules/" .. f))("ElvUI_DeSyncUI", ns)
  end
  moddb = {}
  mod.OnEnable(moddb)
  if eventFrame then eventFrame.scripts.OnEvent(eventFrame, "PLAYER_ENTERING_WORLD") end
  flush()
end

local function fire(event, arg) eventFrame.scripts.OnEvent(eventFrame, event, arg) end
local function w(i) return plates[i].unitFrame.dstTC end
local function visible(i) local x = w(i); return x ~= nil and x.shown end
local function saidHas(text)
  for _, s in ipairs(said) do if s:find(text, 1, true) then return true end end
end

local function test(name, fn)
  local ok, err = pcall(function() setup() fn() end)
  if ok then passed = passed + 1; print("PASS " .. name)
  else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end

test("in a party: sword with the member count, shield on the tank's target", function()
  assert(visible(1) and w(1).sword.shown and w(1).count.text == 2 and not w(1).tank.shown)
  assert(visible(2) and w(2).sword.shown and w(2).count.text == 1 and w(2).tank.shown)
  assert(w(1).sword.texture == "DpsTex" and w(2).tank.texture == "TankTex")
  assert(#said == 0)
end)

test("icons live on the health bar, so they hide whenever ElvUI hides the bar", function()
  assert(w(1).parent == plates[1].unitFrame.Health)
end)

test("friendly plates get no icons", function()
  assert(not visible(3))
end)

test("a plate that stops being attackable loses its icons", function()
  assert(visible(1))
  plates[1].hostile = false
  fire("UNIT_FACTION", "nameplate1"); flush()
  assert(not visible(1))
end)

test("an enemy becoming attackable or leaving combat triggers a redraw", function()
  assert(registered.UNIT_FLAGS and registered.UNIT_FACTION and registered.PLAYER_REGEN_ENABLED)
  fire("UNIT_FLAGS", "nameplate2"); assert(#timers == 1); flush()
  fire("PLAYER_REGEN_ENABLED"); assert(#timers == 1); flush()
end)

test("a member switching target moves the count", function()
  targets.party2 = "nameplate2"
  fire("UNIT_TARGET", "party2"); flush()
  assert(w(1).count.text == 1 and w(2).count.text == 2)
  targets.player, targets.party2 = nil, nil
  fire("PLAYER_TARGET_CHANGED"); flush()
  assert(not visible(1))
end)

test("a mob changing target does not trigger work", function()
  fire("UNIT_TARGET", "nameplate1")
  assert(#timers == 0)
end)

test("leaving the group hides everything", function()
  inGroup = false
  fire("GROUP_ROSTER_UPDATE"); flush()
  assert(not visible(1) and not visible(2))
end)

test("raid: raid tokens and the main tank assignment", function()
  inRaid = true
  roles = {}
  targets = { raid1 = "nameplate2", raid2 = "nameplate2", raid3 = "nameplate1" }
  GetPartyAssignment = function(kind, u) return kind == "MAINTANK" and u == "raid3" end
  fire("GROUP_ROSTER_UPDATE"); flush()
  assert(w(2).count.text == 2 and not w(2).tank.shown)
  assert(w(1).count.text == 1 and w(1).tank.shown)
end)

test("when the game refuses every way, it is reported once and icons stay hidden", function()
  canCompare, plateLookup, guidOpen = false, false, false
  fire("UNIT_TARGET", "party1"); flush()
  fire("UNIT_TARGET", "party2"); flush()
  assert(#said == 1 and saidHas("скрывает"))
  assert(not visible(1) and not visible(2))
end)

test("a member's target is found through its nameplate when comparison is refused (Forever)", function()
  canCompare, guidOpen = false, false
  fire("UNIT_TARGET", "party2"); flush()
  assert(w(1).count.text == 2 and w(2).tank.shown and not saidHas("скрывает"))
end)

test("a member's target is found by GUID when plate lookup and comparison are refused", function()
  canCompare, plateLookup = false, false
  fire("UNIT_TARGET", "party2"); flush()
  assert(w(1).count.text == 2 and w(2).tank.shown and not saidHas("скрывает"))
end)

test("/dstwho names the way each target was found", function()
  canCompare = false
  SlashCmdList.DSTWHO("")
  local r = table.concat(moddb.lastReport, "\n")
  assert(r:find("party2", 1, true) and r:find("по индикатору", 1, true))
end)

test("a member without a target is not a refused comparison", function()
  targets = {}         -- nobody has a target
  canCompare = false   -- would be refused, but there is nothing to compare
  fire("UNIT_TARGET", "party2"); flush()
  assert(not saidHas("скрывает") and not visible(1))
end)

test("secret answers from the game hide icons instead of breaking", function()
  plateLookup, guidOpen = false, false
  UnitIsUnit = function() return SECRET end
  fire("UNIT_TARGET", "party1"); flush()
  assert(not visible(1) and saidHas("скрывает") and not saidHas("ошибка"))
  UnitCanAttack = function() return SECRET end
  fire("UNIT_TARGET", "party1"); flush()
  assert(not visible(1) and not saidHas("ошибка"))
end)

test("a group without a tank says once why there is no shield", function()
  setup({ roles = {} })
  assert(saidHas("танк"))
  fire("UNIT_TARGET", "party1"); flush()
  local n = 0
  for _, s in ipairs(said) do if s:find("танк", 1, true) then n = n + 1 end end
  assert(n == 1)
end)

test("icons step left of a raid mark that ElvUI puts on the left (by setting, not by measuring)", function()
  local uf = plates[1].unitFrame
  assert(w(1).anchor == uf.Health)
  local mark = obj()
  uf.RaidTargetIndicator = mark
  fire("RAID_TARGET_UPDATE"); flush()
  assert(w(1).anchor == mark)
  markPos = "RIGHT"   -- mark moved to the right side in ElvUI settings
  fire("RAID_TARGET_UPDATE"); flush()
  assert(w(1).anchor == uf.Health)
  markPos = "LEFT"
  mark:Hide()
  fire("RAID_TARGET_UPDATE"); flush()
  assert(w(1).anchor == uf.Health)
  assert(#said == 0)  -- nothing tried to measure a nameplate
end)

test("icons step left of ElvUI's left target arrow on the current target", function()
  local uf = plates[1].unitFrame
  local arrow = obj()
  uf.TargetIndicator = obj()
  uf.TargetIndicator.RightIndicator = arrow  -- ElvUI names the arrow left of the bar RightIndicator
  fire("PLAYER_TARGET_CHANGED"); flush()
  assert(w(1).anchor == arrow)
  arrow:Hide()
  fire("PLAYER_TARGET_CHANGED"); flush()
  assert(w(1).anchor == uf.Health)
end)

test("/dstwho test shows icons on enemy plates even when solo, and turns off again", function()
  inGroup = false
  fire("GROUP_ROSTER_UPDATE"); flush()
  assert(not visible(1))
  SlashCmdList.DSTWHO("test"); flush()
  assert(visible(1) and w(1).sword.shown and w(1).tank.shown and not visible(3))
  SlashCmdList.DSTWHO("test"); flush()
  assert(not visible(1))
end)

test("/dstwho reports each step of the chain", function()
  said = {}
  SlashCmdList.DSTWHO("")
  assert(saidHas("в группе: да") and saidHas("индикаторов: 3") and saidHas("вражеских: 2"))
  assert(saidHas("party1") and saidHas("nameplate2") and saidHas("иконки показаны: 2"))
end)

test("inside a dungeon the counter works from threat: members in combat, shield on the tank, alert when loose", function()
  IsInInstance = function() return true, "party" end
  canCompare, plateLookup, guidOpen = false, false, false  -- the game hides every target there
  -- party1 is the tank (setup roles); nameplate1 is on the tank, nameplate2 broke loose onto the player
  local threat = { nameplate1 = { player = 0, party1 = 3, party2 = 1 }, nameplate2 = { player = 3, party1 = 1 } }
  UnitThreatSituation = function(u, mob) return threat[mob] and threat[mob][u] end
  fire("UNIT_THREAT_LIST_UPDATE", "nameplate1"); flush()
  assert(w(1).count.text == 3 and w(1).tank.shown and not w(1).alert.shown)
  assert(w(2).count.text == 2 and not w(2).tank.shown and w(2).alert.shown)
  assert(w(2).alert.texture == "Interface\\RaidFrame\\ReadyCheck-NotReady")
  assert(not saidHas("скрывает цели участников"))  -- no "hidden targets" warning in threat mode
  local n = 0
  for _, s in ipairs(said) do if s:find("угроз", 1, true) then n = n + 1 end end
  fire("UNIT_THREAT_SITUATION_UPDATE", "party2"); flush()
  for _, s in ipairs(said) do if s:find("угроз", 1, true) then n = n - 1 end end
  assert(n == 0 and saidHas("угроз"), "the threat-mode note is said once")
  -- a secret threat value counts as not on the table, without errors
  UnitThreatSituation = function() return SECRET end
  fire("UNIT_THREAT_LIST_UPDATE", "nameplate1"); flush()
  assert(not visible(1) and not saidHas("ошибка"))
  -- back in the open world: targets again
  IsInInstance = function() return false end
  canCompare, plateLookup, guidOpen = true, true, true
  fire("PLAYER_ENTERING_WORLD"); flush()
  assert(visible(1) and w(1).count.text == 2 and not w(1).alert.shown)
end)

test("in a dungeon pack the number sits only on the mob the group actually hits", function()
  IsInInstance = function() return true, "party" end
  canCompare, plateLookup, guidOpen = false, false, false
  -- everyone is listed on both mobs; only nameplate1 gets real threat (single-target)
  local value = { nameplate1 = { player = 700, party1 = 5000, party2 = 900 }, nameplate2 = { party1 = 0, player = 0, party2 = 0 } }
  UnitThreatSituation = function(u, mob)
    if mob == "nameplate1" then return u == "party1" and 3 or 0 end
    if mob == "nameplate2" then return u == "party1" and 3 or 0 end
  end
  UnitDetailedThreatSituation = function(u, mob)
    local v = value[mob] and value[mob][u]
    return u == "party1", UnitThreatSituation(u, mob), 0, 0, v
  end
  fire("UNIT_THREAT_LIST_UPDATE", "nameplate1"); flush()
  assert(w(1).count.text == 3, "hit mob: " .. tostring(w(1).count.text))
  assert(not w(2).sword.shown, "untouched mob must show no number")
  assert(w(2).tank.shown)  -- still on the tank (it pulled the pack)
end)

test("threat changes on mobs and group members trigger a redraw; other units do not", function()
  assert(registered.UNIT_THREAT_LIST_UPDATE and registered.UNIT_THREAT_SITUATION_UPDATE)
  fire("UNIT_THREAT_LIST_UPDATE", "nameplate2"); assert(#timers == 1); flush()
  fire("UNIT_THREAT_SITUATION_UPDATE", "party1"); assert(#timers == 1); flush()
  fire("UNIT_THREAT_SITUATION_UPDATE", "target"); assert(#timers == 0)
end)

test("/dstwho shows each way of finding a target separately, and whether we are in an instance", function()
  IsInInstance = function() return true, "party" end
  C_Secrets.ShouldUnitIdentityBeSecret = function() return true end
  plateLookup, guidOpen = false, false
  SlashCmdList.DSTWHO("")
  local r = table.concat(moddb.lastReport, "\n")
  assert(r:find("подземелье: да (party)", 1, true), r)
  assert(r:find("индикатор цели: нет", 1, true) and r:find("GUID: скрыт", 1, true))
  assert(r:find("сравнение: да", 1, true) and r:find("личность скрыта: да", 1, true))
end)

test("/dstwho shows whom each enemy targets (the mob's target) and the tank's threat on it", function()
  local mobTargets = { nameplate1 = "party1", nameplate2 = "party2" }
  local base = UnitIsUnit
  UnitIsUnit = function(a, b)
    local mob = a:match("^(nameplate%d+)target$")
    if mob then return mobTargets[mob] == b end
    return base(a, b)
  end
  local exists = UnitExists
  UnitExists = function(u)
    local mob = u:match("^(nameplate%d+)target$")
    if mob then return mobTargets[mob] ~= nil end
    return exists(u)
  end
  UnitThreatSituation = function(u, mob) if u == "party1" and mob == "nameplate1" then return 3 end return 0 end
  -- isTanking, status, scaledPercent, rawPercent, threatValue
  UnitDetailedThreatSituation = function(u, mob)
    if mob == "nameplate1" and u == "party1" then return true, 3, 100, 100, 5000 end
    if mob == "nameplate1" and u == "player" then return false, 0, 0, 0, 0 end
    if mob == "nameplate2" and u == "party2" then return false, 0, 40, 40, SECRET end
  end
  SlashCmdList.DSTWHO("")
  local r = table.concat(moddb.lastReport, "\n")
  assert(r:find("party1 s=3 v=5000", 1, true) and r:find("player s=0 v=0", 1, true), r)
  assert(r:find("party2 s=0 v=скрыто", 1, true), r)
  assert(r:find("nameplate1: цель моба есть: да, на ком: party1 (танк)", 1, true), r)
  assert(r:find("угроза танка: 3", 1, true), r)
  assert(r:find("nameplate2: цель моба есть: да, на ком: party2", 1, true), r)
end)

test("/dstwho also saves its report with the settings", function()
  SlashCmdList.DSTWHO("")
  local r = moddb.lastReport
  assert(type(r) == "table" and #r >= 4)
  assert(r[1]:find("в группе: да", 1, true) and table.concat(r, "\n"):find("party1", 1, true))
end)

test("/dstwho probes the other dungeon signals without breaking when the game hides them", function()
  UnitDetailedThreatSituation = function() return false, 0, SECRET, SECRET, SECRET end
  SlashCmdList.DSTWHO("")
  local all = table.concat(moddb.lastReport, "\n")
  assert(all:find("подробно (танкует/статус/%/сырой %/угроза): player false/0/?/?/?", 1, true), all)
  assert(all:find("моб: GUID", 1, true) and all:find("цель: имя", 1, true))
  assert(all:find("журнал боя в подземелье: подписка есть, событий 0", 1, true))
  assert(moddb.lastError == nil, tostring(moddb.lastError))
end)

test("errors are kept with the settings for diagnosis; no per-update record is written", function()
  assert(moddb.diag == nil and moddb.lastError == nil)
  UnitCanAttack = function() error("boom") end
  fire("UNIT_TARGET", "party1"); flush()
  assert(moddb.lastError and moddb.lastError:find("boom", 1, true))
end)

test("plates are found by unit token although frames carry no namePlateUnitToken / .unit", function()
  assert(plates[1].namePlateUnitToken == nil and plates[1].unitFrame.unit == nil)
  assert(visible(1) and visible(2))
end)

test("a plate appearing later gets icons; a removed plate drops them at once", function()
  local p = plate("nameplate5")
  plates[#plates + 1] = p
  targets.party1 = "nameplate5"
  fire("NAME_PLATE_UNIT_ADDED", "nameplate5"); flush()
  assert(p.unitFrame.dstTC and p.unitFrame.dstTC.shown and p.unitFrame.dstTC.tank.shown)
  fire("NAME_PLATE_UNIT_REMOVED", "nameplate5")
  assert(not p.unitFrame.dstTC.shown)
end)

test("a plate without an ElvUI frame is skipped", function()
  plates[#plates + 1] = { unitToken = "nameplate4", hostile = true }
  fire("NAME_PLATE_UNIT_ADDED", "nameplate4"); flush()
  assert(visible(1) and #said == 0)
end)

test("ElvUI nameplates off: message, module off", function()
  setup({ platesOff = true })
  assert(eventFrame == nil and #said == 1 and said[1]:find("TargetCount", 1, true))
end)

print(passed .. " passed, " .. failed .. " failed")
if failed > 0 then error("tests failed") end
