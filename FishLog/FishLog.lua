FishLogDB = FishLogDB or {}
local MAX = 3000
local active, stopAt = false, nil
local noisy = {
  COMBAT_LOG_EVENT_UNFILTERED = true, CURSOR_UPDATE = false,
  UPDATE_MOUSEOVER_UNIT = false, ACTIONBAR_UPDATE_COOLDOWN = true,
  SPELL_UPDATE_COOLDOWN = true, UNIT_POWER_FREQUENT = true,
  UNIT_POWER_UPDATE = true, COMBAT_LOG_EVENT = true,
}

local function add(kind, ...)
  local t = {}
  for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
  local e = FishLogDB.entries
  e[#e + 1] = string.format("%.3f %s %s", GetTime(), kind, table.concat(t, ", "))
  if #e > MAX then table.remove(e, 1) end
end

local f = CreateFrame("Frame")
f:RegisterAllEvents()
f:SetScript("OnEvent", function(_, event, ...)
  if not FishLogDB.entries then FishLogDB.entries = {} end
  if event == "UNIT_SPELLCAST_CHANNEL_START" and (...) == "player" then
    active, stopAt = true, nil
    add("==START==", event, ...)
    return
  end
  if event == "UNIT_SPELLCAST_CHANNEL_STOP" and (...) == "player" then
    stopAt = GetTime() + 3 -- keep logging 3s after (loot etc.)
  end
  if active and not noisy[event] then add("EVT", event, ...) end
end)

-- cursor / tooltip / mouseover polling while fishing
local acc = 0
f:SetScript("OnUpdate", function(_, dt)
  if not active then return end
  if stopAt and GetTime() > stopAt then
    add("==END==")
    active, stopAt = false, nil
    return
  end
  acc = acc + dt
  if acc < 0.1 then return end
  acc = 0
  local tip = GameTooltipTextLeft1 and GameTooltip:IsShown() and GameTooltipTextLeft1:GetText()
  local mo = UnitExists("mouseover") and UnitName("mouseover") or nil
  local sig = tostring(tip) .. "|" .. tostring(mo)
  if sig ~= f.lastSig then
    f.lastSig = sig
    add("POLL", "tooltip=" .. tostring(tip), "mouseover=" .. tostring(mo))
  end
end)

SLASH_FISHLOG1 = "/fishlog"
SlashCmdList.FISHLOG = function(msg)
  local e = FishLogDB.entries or {}
  if msg == "clear" then
    FishLogDB.entries = {}
    print("FishLog: cleared")
  elseif msg == "start" then
    active, stopAt = true, nil
    print("FishLog: manual start")
  elseif msg == "stop" then
    active = false
    print("FishLog: stopped")
  else
    print("FishLog: " .. #e .. " entries, recording=" .. tostring(active))
    for i = math.max(1, #e - 15), #e do print(e[i]) end
    print("/fishlog clear | start | stop. Then /reload to write file.")
  end
end
