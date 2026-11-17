local ADDON, ns = ...
local mod = ns.NewModule("LootRoll", {
  title = "Кто что выбрал в розыгрыше",
  desc = "Возвращает на панель лута ElvUI счётчики на кнопках Need/Greed/Pass и список имён в подсказке кнопки. "
      .. "ElvUI не делает этого в Forever: старые события истории лута там не работают.",
  defaults = { debug = false, log = {} },  -- diagnostics only on request (/dstloot on)
})

local say = ns.say
local DB
local E, M

local function secret(v) return issecretvalue and issecretvalue(v) end

-- ElvUI roll types: 0 pass, 1 need, 2 greed, 3 disenchant, 4 transmog
local TYPE_KEY = { [0] = "pass", [1] = "need", [2] = "greed", [3] = "disenchant", [4] = "transmog" }

-- Enum.EncounterLootDropRollState -> ElvUI roll type (NoRoll = not decided yet: not counted)
local STATE_TO_TYPE = { [0] = 1, [1] = 1, [2] = 4, [3] = 2, [5] = 0 }
do
  local ES = Enum and Enum.EncounterLootDropRollState
  if ES then
    local map = {}
    if ES.NeedMainSpec then map[ES.NeedMainSpec] = 1 end
    if ES.NeedOffSpec then map[ES.NeedOffSpec] = 1 end
    if ES.Transmog then map[ES.Transmog] = 4 end
    if ES.Greed then map[ES.Greed] = 2 end
    if ES.Pass then map[ES.Pass] = 0 end
    if next(map) then STATE_TO_TYPE = map end
  end
end

-- diagnostics (saved in the settings file, shown with /dstloot)
local function log(s)
  if not (DB and DB.debug) then return end
  DB.log[#DB.log + 1] = format("%.1f %s", GetTime(), s)
  while #DB.log > 300 do table.remove(DB.log, 1) end
end

local function str(v)
  if secret(v) then return "<secret>" end
  local t = type(v)
  if t == "string" or t == "number" or t == "boolean" or t == "nil" then return tostring(v) end
  return "<" .. t .. ">"
end

local function dump(prefix, v, depth, budget)
  if budget.n <= 0 then return end
  if type(v) ~= "table" or secret(v) then
    budget.n = budget.n - 1
    log(prefix .. " = " .. str(v))
    return
  end
  if depth > 4 then log(prefix .. " = {...}") return end
  for k, x in pairs(v) do dump(prefix .. "." .. str(k), x, depth + 1, budget) end
end

local function itemID(link)
  if not link or secret(link) then return nil end
  return tostring(link):match("item:(%d+)")
end

local function classToken(c)
  if secret(c) then return nil end
  if type(c) == "string" then return c end
  if type(c) == "number" and C_CreatureInfo and C_CreatureInfo.GetClassInfo then
    local i = C_CreatureInfo.GetClassInfo(c)
    return i and i.classFile
  end
end

-- the list of per-player entries inside a drop record
local function rollList(info)
  if type(info.rollInfos) == "table" then return info.rollInfos end
  for k, v in pairs(info) do
    if k ~= "winner" and type(v) == "table" and type(v[1]) == "table" then return v end
  end
end

-- which of the on-screen roll bars belongs to this drop
local function findBar(info, key)
  local id = itemID(info.itemHyperlink)
  if not id then return nil end
  local free
  for _, bar in next, M.RollBars do
    if bar.rollID and bar:IsShown() and itemID(bar.button and bar.button.link) == id then
      if bar.dstRoll ~= bar.rollID then bar.dstRoll, bar.dstKey = bar.rollID, nil end
      if bar.dstKey == key then return bar end
      if bar.rollID == info.lootListID then bar.dstKey = key return bar end
      if not bar.dstKey and not free then free = bar end
    end
  end
  if free then free.dstKey = key end
  return free
end

local function syncDrop(info, encounterID)
  if type(info) ~= "table" or secret(info) then return end
  local key = str(encounterID or info.encounterID) .. ":" .. str(info.lootListID)
  local bar = findBar(info, key)
  if not bar then log("нет панели для " .. key .. " " .. str(info.itemHyperlink)) return end

  wipe(bar.rolls)
  local list = rollList(info)
  local counted = 0
  for _, r in ipairs(list or {}) do
    if type(r) == "table" then
      local name = r.playerName or r.name
      local state = r.state or r.rollState
      local t = STATE_TO_TYPE[state]
      if t and name and not secret(name) then
        bar.rolls[t] = bar.rolls[t] or {}
        tinsert(bar.rolls[t], { name, classToken(r.playerClass or r.classFile or r.classID or r.className) })
        counted = counted + 1
      end
    end
  end
  for t, k in pairs(TYPE_KEY) do
    local b = bar[k]
    if b and b.text then
      local n = bar.rolls[t] and #bar.rolls[t] or 0
      b.text:SetText(n > 0 and n or "")
    end
  end
  log("синхронизировано " .. key .. ": записей в списке " .. (list and #list or 0) .. ", учтено " .. counted)
end

local function syncEncounter(encounterID)
  if not (C_LootHistory and C_LootHistory.GetSortedDropsForEncounter) then return end
  local ok, drops = pcall(C_LootHistory.GetSortedDropsForEncounter, encounterID)
  if not ok or type(drops) ~= "table" then return end
  for _, d in ipairs(drops) do syncDrop(d, encounterID) end
end

local function anyBar()
  for _, bar in next, M.RollBars do
    if bar.rollID and bar:IsShown() then return true end
  end
end

local function syncAll()
  if not anyBar() then return end
  if not (C_LootHistory and C_LootHistory.GetAllEncounterInfos) then return end
  local ok, list = pcall(C_LootHistory.GetAllEncounterInfos)
  if not ok or type(list) ~= "table" then return end
  for _, e in ipairs(list) do
    local id = type(e) == "table" and e.encounterID or e
    if id and not secret(id) then syncEncounter(id) end
  end
end

local function onEvent(_, event, a, b)
  if DB.debug then
    log(event .. "(" .. str(a) .. ", " .. str(b) .. ")")
  end
  if event == "START_LOOT_ROLL" then
    -- ElvUI builds the bar in its own handler; history data may arrive a moment later
    C_Timer.After(0.5, syncAll)
    C_Timer.After(2, syncAll)
  elseif event == "LOOT_HISTORY_UPDATE_DROP" then
    if a and b and not secret(a) and not secret(b) and C_LootHistory.GetSortedInfoForDrop then
      local ok, info = pcall(C_LootHistory.GetSortedInfoForDrop, a, b)
      if ok and info then
        if DB.debug then dump("drop", info, 0, { n = 120 }) end
        syncDrop(info, a)
      end
    else
      syncAll()
    end
  else -- LOOT_HISTORY_UPDATE_ENCOUNTER / FULL_UPDATE
    if a and not secret(a) and event == "LOOT_HISTORY_UPDATE_ENCOUNTER" then syncEncounter(a) else syncAll() end
  end
end

function mod.OnEnable(db)
  DB = db
  E = ElvUI and ElvUI[1]
  M = E and E:GetModule("Misc", true)
  if not (E and M and M.RollBars and E.private and E.private.general and E.private.general.lootRoll) then
    say("LootRoll: панель розыгрыша ElvUI выключена или не найдена, модуль не запущен")
    return
  end
  if not (C_LootHistory and C_LootHistory.GetSortedInfoForDrop) then
    say("LootRoll: в этом клиенте нет нового API истории лута")
    return
  end

  local f = CreateFrame("Frame")
  for _, e in ipairs({ "START_LOOT_ROLL", "LOOT_HISTORY_UPDATE_DROP", "LOOT_HISTORY_UPDATE_ENCOUNTER", "LOOT_HISTORY_FULL_UPDATE" }) do
    pcall(f.RegisterEvent, f, e)
  end
  f:SetScript("OnEvent", function(...)
    local ok, err = pcall(onEvent, ...)
    if not ok then log("ОШИБКА: " .. tostring(err)) end
  end)

  SLASH_DSTLOOT1 = "/dstloot"
  SlashCmdList.DSTLOOT = function(msg)
    if msg == "clear" then wipe(DB.log) say("журнал очищен") return end
    if msg == "on" then DB.debug = true say("диагностика включена") return end
    if msg == "off" then DB.debug = false say("диагностика выключена") return end
    say("диагностика " .. (DB.debug and "включена" or "выключена") .. ", строк: " .. #DB.log .. ". /dstloot on|off|clear")
    for i = math.max(1, #DB.log - 30), #DB.log do print(DB.log[i]) end
  end
end

function mod.options(db)
  return {
    debug = {
      order = 2, type = "toggle", width = "full",
      name = "Диагностика (писать журнал розыгрышей в файл настроек)",
      desc = "Команда /dstloot показывает последние строки журнала. Включите перед розыгрышем в группе, если счётчики не появляются.",
      get = function() return db.debug end,
      set = function(_, v) db.debug = v end,
    },
  }
end
