local ADDON = ...
local P = "|cff33ccffLootRollInfo|r: "
local DB
local function isSecret(v) return issecretvalue and issecretvalue(v) end

local function log(s)
  if not DB then return end
  DB.log[#DB.log + 1] = format("%.1f %s", GetTime(), s)
  if #DB.log > 600 then table.remove(DB.log, 1) end
end

local function str(v)
  if isSecret(v) then return "<secret>" end
  local t = type(v)
  if t == "string" or t == "number" or t == "boolean" or t == "nil" then return tostring(v) end
  return "<" .. t .. ">"
end

local function dump(prefix, v, depth, budget)
  if budget.n <= 0 then return end
  if type(v) ~= "table" or isSecret(v) then
    budget.n = budget.n - 1
    log(prefix .. " = " .. str(v))
    return
  end
  if depth > 4 then log(prefix .. " = {...}") return end
  for k, x in pairs(v) do
    dump(prefix .. "." .. str(k), x, depth + 1, budget)
  end
end

local function dumpEncounter(encounterID)
  if not (C_LootHistory and C_LootHistory.GetSortedDropsForEncounter) then log("нет GetSortedDropsForEncounter") return end
  local ok, drops = pcall(C_LootHistory.GetSortedDropsForEncounter, encounterID)
  if not ok then log("ОШИБКА GetSortedDropsForEncounter: " .. tostring(drops)) return end
  if not drops then log("drops=nil для encounter " .. str(encounterID)) return end
  log("drops: " .. #drops .. " шт. для encounter " .. str(encounterID))
  dump("drop", drops, 0, { n = 300 })
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    LootRollInfoDB = LootRollInfoDB or {}
    DB = LootRollInfoDB
    DB.log = {}   -- fresh log each session
    return
  end
  if event == "PLAYER_LOGIN" then
    local names = {}
    if C_LootHistory then for k in pairs(C_LootHistory) do names[#names + 1] = k end end
    table.sort(names)
    log("C_LootHistory: " .. table.concat(names, ", "))
    for _, e in ipairs({ "START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "LOOT_HISTORY_FULL_UPDATE", "LOOT_HISTORY_UPDATE_DROP",
      "LOOT_HISTORY_UPDATE_ENCOUNTER", "LOOT_HISTORY_ROLL_CHANGED", "LOOT_HISTORY_ROLL_COMPLETE", "LOOT_ROLLS_COMPLETE",
      "LOOT_HISTORY_AUTO_SHOW", "ENCOUNTER_LOOT_RECEIVED" }) do
      pcall(self.RegisterEvent, self, e)
    end
    print(P .. "диагностика запущена. Журнал: /lri show, запись в файл при /reload")
    return
  end
  local args = {}
  for i = 1, select("#", ...) do args[i] = str((select(i, ...))) end
  local line = event .. "(" .. table.concat(args, ", ") .. ")"
  log(line)
  print(P .. line)
  if event == "START_LOOT_ROLL" then
    local rollID = ...
    if rollID and not isSecret(rollID) then
      local ok, l = pcall(GetLootRollItemLink, rollID)
      log("  rollID " .. str(rollID) .. " link=" .. (ok and str(l) or "?"))
    end
  elseif event:find("^LOOT_HISTORY_UPDATE") then
    dumpEncounter((...))
    -- an item's drop may also be asked directly
    local enc, lootListID = ...
    if enc and lootListID and C_LootHistory.GetSortedInfoForDrop then
      local ok, info = pcall(C_LootHistory.GetSortedInfoForDrop, enc, lootListID)
      log("GetSortedInfoForDrop ok=" .. tostring(ok))
      if ok then dump("info", info, 0, { n = 200 }) end
    end
  elseif event:find("^LOOT_HISTORY_ROLL") or event == "LOOT_HISTORY_FULL_UPDATE" then
    local ok, e = pcall(function() return C_LootHistory.GetLastEncounterID and C_LootHistory.GetLastEncounterID() end)
    if ok and e then dumpEncounter(e) end
  end
end)

SLASH_LOOTROLLINFO1 = "/lri"
SlashCmdList.LOOTROLLINFO = function(msg)
  if not DB then return end
  if msg == "clear" then wipe(DB.log) print(P .. "очищено") return end
  local from = math.max(1, #DB.log - 40)
  for i = from, #DB.log do print(DB.log[i]) end
end
