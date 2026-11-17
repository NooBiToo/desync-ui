local ADDON, ns = ...
local mod = ns.NewModule("TargetCount", {
  title = "Кто кого бьёт",
  desc = "В группе и рейде на индикаторах здоровья врагов (ElvUI) слева от полоски видно: "
      .. "меч с числом — сколько участников держат этого врага в цели (вы тоже считаетесь), "
      .. "щит — этого врага держит в цели танк. Танк — участник с ролью «Танк» или главный танк рейда. "
      .. "Работает в открытом мире: в подземельях Forever игра скрывает от аддонов, кто кого выбрал в цель.",
})

local say = ns.say
local T = ns.TargetCountData
local SIZE = 16

local E, DB
local pending, reported, warnedHidden, warnedNoTank = false, false, false, false
local closedHere, warnedInstance = false, false  -- inside a dungeon that hides targets
local testMode, lastError = false, nil

local function safe(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    lastError = tostring(err)
    if DB then DB.lastError = lastError end
    if not reported then
      reported = true
      say("TargetCount: ошибка: " .. lastError)
    end
  end
end

local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function notSecret(v)
  if isSecret(v) then return nil end
  return v
end

-- true / false, or nil when the game refuses to compare these units (secret unit identity)
local function same(a, b)
  local exists = UnitExists(a)
  if not isSecret(exists) and not exists then return false end  -- no target: nothing to compare
  local canCompare = C_Secrets and C_Secrets.CanCompareUnitTokens
  if canCompare and not canCompare(a, b) then return nil end
  local r = UnitIsUnit(a, b)
  if isSecret(r) then return nil end
  return r and true or false
end

-- icons hang off the health bar: whenever ElvUI hides the bar (name-only, disabled plates) they go too
local function widget(uf)
  if uf.dstTC then return uf.dstTC end
  local w = CreateFrame("Frame", nil, uf.Health)
  w:SetSize(SIZE, SIZE)
  w:SetFrameLevel((uf.Health:GetFrameLevel() or 0) + 5)

  w.sword = w:CreateTexture(nil, "OVERLAY")
  w.sword:SetTexture(E.Media.Textures.DPS)
  w.sword:SetSize(SIZE, SIZE)
  w.sword:SetPoint("RIGHT", w, "RIGHT")

  w.count = w:CreateFontString(nil, "OVERLAY")
  w.count:FontTemplate(nil, 12, "OUTLINE")
  w.count:SetPoint("BOTTOMRIGHT", w.sword, "BOTTOMRIGHT", 3, -2)

  w.tank = w:CreateTexture(nil, "OVERLAY")
  w.tank:SetTexture(E.Media.Textures.Tank)
  w.tank:SetTexCoord(2 / 64, 56 / 64, 2 / 64, 56 / 64)  -- same crop ElvUI uses for this icon
  w.tank:SetSize(SIZE, SIZE)

  uf.dstTC = w
  return w
end

local function hide(uf)
  if uf.dstTC then uf.dstTC:Hide() end
end

-- where ElvUI puts this plate's raid mark (its own setting): Forever forbids measuring nameplates,
-- GetLeft/GetRight there fail with "Can't measure restricted regions"
local function markPosition(uf)
  local NP = E:GetModule("NamePlates", true)
  local db = NP and NP.PlateDB and NP:PlateDB(uf)
  return db and db.raidTargetIndicator and db.raidTargetIndicator.position
end

-- left of the bar ElvUI may already show the raid mark (default) and, on the current target,
-- the left side arrow (target indicator styles 4/7/8, named RightIndicator): step past them
local function anchor(w, uf)
  local health = uf.Health
  local mark = uf.RaidTargetIndicator
  local arrow = uf.TargetIndicator and uf.TargetIndicator.RightIndicator
  w:ClearAllPoints()
  if mark and mark:IsShown() and markPosition(uf) == "LEFT" then
    w:SetPoint("RIGHT", mark, "LEFT", -2, 0)
  elseif arrow and arrow:IsVisible() then
    w:SetPoint("RIGHT", arrow, "LEFT", -2, 0)
  else
    w:SetPoint("RIGHT", health, "LEFT", -4, 0)
  end
end

local function paint(uf, r)
  local w = widget(uf)
  anchor(w, uf)
  local hasCount = r.count > 0
  w.sword:SetShown(hasCount)
  w.count:SetShown(hasCount)
  w.count:SetText(hasCount and r.count or "")
  w.tank:ClearAllPoints()
  if hasCount then
    w.tank:SetPoint("RIGHT", w.sword, "LEFT", -2, 0)
  else
    w.tank:SetPoint("RIGHT", w, "RIGHT")
  end
  w.tank:SetShown(r.tank)
  w:SetShown(hasCount or r.tank)
end

local function members()
  local inRaid = IsInRaid()
  local list, anyTank = {}, false
  for _, u in ipairs(T.GroupUnits(inRaid, inRaid and GetNumGroupMembers() or GetNumSubgroupMembers())) do
    local role = notSecret(UnitGroupRolesAssigned and UnitGroupRolesAssigned(u))
    local mainTank = notSecret(GetPartyAssignment and GetPartyAssignment("MAINTANK", u))
    local tank = T.IsTank(role, mainTank and true or false)
    anyTank = anyTank or tank
    list[#list + 1] = { unit = u, tank = tank }
  end
  return list, anyTank
end

-- Forever plate frames carry no namePlateUnitToken (it is unitToken) and ElvUI frames no .unit (seen in game).
-- Track plate tokens the way ElvUI does: NAME_PLATE_UNIT_ADDED / REMOVED + C_NamePlate.GetNamePlateForUnit
local active = {}

local function plateFor(unit)
  local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
  if ok then return plate end
end

-- plates already on screen when we start (login, /reload)
local function seed()
  for i = 1, 40 do
    local u = "nameplate" .. i
    if notSecret(UnitExists(u)) then active[u] = true end
  end
end

-- { { unit, plate } } on screen now, in a stable order
local function currentPlates()
  local list = {}
  for unit in pairs(active) do
    local plate = plateFor(unit)
    if plate then list[#list + 1] = { unit = unit, plate = plate } else active[unit] = nil end
  end
  table.sort(list, function(a, b) return a.unit < b.unit end)
  return list
end

-- which enemy plate a member's target is. Forever refuses comparing "partyNtarget" with "nameplateN"
-- (seen in game), so first ask for the target's own plate, then compare GUIDs, then compare units.
-- locate(target) -> plate token or nil, refused (every way hidden), how (for /dstwho)
local function makeLocate(tokens)
  local byPlate = {}
  for _, u in ipairs(tokens) do
    local p = plateFor(u)
    if p then byPlate[p] = u end
  end
  return function(target)
    local exists = UnitExists(target)
    if not isSecret(exists) and not exists then return nil, false, "нет цели" end
    local plate = plateFor(target)
    if plate then return byPlate[plate], false, "по индикатору" end
    local guid = UnitGUID and UnitGUID(target)
    if guid ~= nil and not isSecret(guid) then
      for _, u in ipairs(tokens) do
        local g = UnitGUID(u)
        if g ~= nil and not isSecret(g) and g == guid then return u, false, "по GUID" end
      end
      return nil, false, "по GUID, не на экране"
    end
    local refused = false
    for _, u in ipairs(tokens) do
      local r = same(target, u)
      if r == nil then refused = true elseif r then return u, false, "сравнением" end
    end
    if refused then return nil, true, "запрещено игрой" end
    return nil, false, "не на экране"
  end
end

local function inInstance()
  if not IsInInstance then return false end
  local inside = IsInInstance()
  return notSecret(inside) and inside and true or false
end

function mod.Update()
  if closedHere and not testMode then return end  -- this dungeon hides every target: nothing to count
  local inGroup = IsInGroup() or testMode
  local tokens, frames = {}, {}
  for _, e in ipairs(currentPlates()) do
    local plate, unit = e.plate, e.unit
    local uf = plate.unitFrame
    if uf and uf.Health and unit then
      if inGroup and notSecret(UnitCanAttack("player", unit)) then
        tokens[#tokens + 1] = unit
        frames[unit] = uf
      else
        hide(uf)
      end
    end
  end
  if #tokens == 0 then return end
  if testMode then  -- /dstwho test: draw on every enemy, no group needed
    for _, uf in pairs(frames) do paint(uf, { count = 3, tank = true }) end
    return
  end

  local list, anyTank = members()
  if not anyTank and not warnedNoTank then
    warnedNoTank = true
    say("TargetCount: в группе никто не отмечен танком (роль «Танк» или главный танк рейда), щит не показывается")
  end
  local res, blocked = T.Count(tokens, list, makeLocate(tokens))
  if blocked and inInstance() then
    -- seen in game: inside Forever dungeons every member's target is secret (plate lookup, GUID and
    -- comparison all refused), so stop until the next zone change instead of recounting on every event
    closedHere = true
    for _, uf in pairs(frames) do hide(uf) end
    if not warnedInstance then
      warnedInstance = true
      say("TargetCount: в подземельях Forever игра скрывает от аддонов, кто кого выбрал в цель, — "
        .. "здесь счётчик не работает (в открытом мире работает)")
    end
    return
  end
  if blocked and not warnedHidden then
    warnedHidden = true
    say("TargetCount: игра скрывает цели участников группы, часть иконок не показывается")
  end
  for unit, uf in pairs(frames) do paint(uf, res[unit]) end
end

-- targets change in bursts (pulls, swaps): redraw once they settle
local function schedule()
  if pending then return end
  pending = true
  C_Timer.After(0.1, function()
    pending = false
    safe(mod.Update)
  end)
end

local function groupUnit(u)
  return type(u) == "string" and (u == "player" or u:find("^party%d") or u:find("^raid%d")) and true or false
end

local function onEvent(_, event, unit)
  if event == "NAME_PLATE_UNIT_ADDED" and type(unit) == "string" then
    active[unit] = true
  elseif event == "NAME_PLATE_UNIT_REMOVED" and type(unit) == "string" then
    active[unit] = nil
    local plate = plateFor(unit)  -- the frame gets reused for another unit: drop our icons now
    if plate and plate.unitFrame then hide(plate.unitFrame) end
  elseif event == "PLAYER_ENTERING_WORLD" then
    closedHere = false  -- a new zone: maybe the open world again
    seed()
  end
  if event == "UNIT_TARGET" and not groupUnit(unit) then return end  -- mobs retarget all the time
  if (event == "UNIT_FLAGS" or event == "UNIT_FACTION")
     and not (groupUnit(unit) or (type(unit) == "string" and unit:find("^nameplate%d"))) then
    return
  end
  schedule()
end

local function yn(v)
  if isSecret(v) then return "скрыто игрой" end
  return v and "да" or "нет"
end

-- /dstwho: walk the chain plate -> group -> targets and say where it stops
local function report()
  local lines = {}
  if DB then DB.lastReport = lines end  -- also saved with the settings: readable after /reload
  local function say(s)
    lines[#lines + 1] = s
    ns.say(s)
  end
  local inRaid = IsInRaid()
  local list, anyTank = members()
  local inInstance, instanceType = false, nil
  if IsInInstance then inInstance, instanceType = IsInInstance() end
  say(string.format("в группе: %s, рейд: %s, участников: %d, танк найден: %s, тест: %s, подземелье: %s%s",
    yn(IsInGroup()), yn(inRaid), #list, yn(anyTank), yn(testMode), yn(inInstance),
    instanceType and not isSecret(instanceType) and (" (" .. instanceType .. ")") or ""))
  local secrets = C_Secrets or {}
  local all, hostile, noFrame, shown, hiddenFoe, tokens = 0, 0, 0, 0, 0, {}
  for _, e in ipairs(currentPlates()) do
    all = all + 1
    local uf, unit = e.plate.unitFrame, e.unit
    if not (uf and uf.Health) then
      noFrame = noFrame + 1
    else
      local foe = UnitCanAttack("player", unit)
      if isSecret(foe) then hiddenFoe = hiddenFoe + 1 end
      if notSecret(foe) then hostile = hostile + 1; tokens[#tokens + 1] = unit end
      if uf.dstTC and uf.dstTC:IsShown() then shown = shown + 1 end
    end
  end
  say(string.format("индикаторов: %d (вражеских: %d, «враг ли» скрыто игрой: %d, без рамки ElvUI: %d)",
    all, hostile, hiddenFoe, noFrame))
  local locate = makeLocate(tokens)
  for i, m in ipairs(list) do
    if i > 5 then break end
    local target = m.unit .. "target"
    local p, refused, how = locate(target)
    say(string.format("  %s%s: цель есть: %s, найдена: %s, совпадает с: %s", m.unit, m.tank and " (танк)" or "",
      yn(UnitExists(target)), how, refused and "—" or (p or "нет")))
    -- each way on its own: which one the game closes here
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, target)
    local guid = UnitGUID and UnitGUID(target)
    local cmp = secrets.CanCompareUnitTokens and tokens[1] and secrets.CanCompareUnitTokens(target, tokens[1])
    local hidden = secrets.ShouldUnitIdentityBeSecret and secrets.ShouldUnitIdentityBeSecret(target)
    say(string.format("    индикатор цели: %s, GUID: %s, сравнение: %s, личность скрыта: %s",
      not ok and "ошибка" or (plate and "есть" or "нет"),
      isSecret(guid) and "скрыт" or (guid and "есть" or "нет"),
      tokens[1] and yn(cmp) or "нет врагов", yn(hidden)))
  end
  say(string.format("иконки показаны: %d%s", shown, lastError and (", последняя ошибка: " .. lastError) or ""))
end

function mod.OnEnable(db)
  DB = db
  if DB then DB.diag, DB.lastError = nil, nil end  -- drop records left by older debug builds
  E = ElvUI and ElvUI[1]
  local NP = E and E:GetModule("NamePlates", true)
  if not (NP and E.private and E.private.nameplates and E.private.nameplates.enable) then
    say("TargetCount: индикаторы здоровья ElvUI выключены, модуль не запущен")
    return
  end

  local f = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PLAYER_TARGET_CHANGED",
                       "UNIT_TARGET", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "RAID_TARGET_UPDATE",
                       "UNIT_FLAGS", "UNIT_FACTION", "PLAYER_REGEN_ENABLED" }) do
    pcall(f.RegisterEvent, f, e)
  end
  f:SetScript("OnEvent", function(...) safe(onEvent, ...) end)
  seed()
  schedule()

  SLASH_DSTWHO1 = "/dstwho"
  SlashCmdList.DSTWHO = function(msg)
    if msg == "test" then
      testMode = not testMode
      say("TargetCount: тестовый режим " .. (testMode and "включён (иконки на всех врагах)" or "выключен"))
      schedule()
      return
    end
    safe(report)
  end
end
