local ADDON, ns = ...
local mod = ns.NewModule("WandStop", {
  title = "Жезл не мешает заклинаниям",
  desc = "Клавиши заклинаний на панелях ElvUI сначала сбивают выстрел жезлом (/stopcasting), потом произносят заклинание. "
      .. "Работает у мага, жреца и чернокнижника. Клик мышью по кнопке остаётся обычным. "
      .. "Нажатие сбивает и ваш текущий каст, кроме потоковых; заклинания из списка исключений этого не делают. "
      .. "Если панель перелистнулась в бою (облик, Shift+цифра), её клавиши до конца боя работают как обычно.",
  default = false,  -- changes how keys behave: opt-in for new users
  defaults = { exclude = "" },
})

local say = ns.say
local S = ns.WandStopData

local CLASSES = { MAGE = true, PRIEST = true, WARLOCK = true }
-- while one of these is up the bar shows someone else's abilities: record nothing
local GUARD = "[overridebar][vehicleui][possessbar][shapeshift][bonusbar:5] 1"
-- runs in combat on every bar page change: bind a key only while its bar shows the page it was built for
local SNIPPET = [[
  self:ClearBindings()
  for i = 1, self:GetAttribute("count") or 0 do
    local bar = self:GetAttribute("barname" .. i)
    if tostring(self:GetAttribute("state-" .. bar)) == tostring(self:GetAttribute("page" .. i)) then
      self:SetBindingClick(true, self:GetAttribute("key" .. i), self:GetAttribute("button" .. i))
    end
  end
]]
local EVENTS = {
  "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS", "ACTIONBAR_PAGE_CHANGED",
  "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM", "SPELLS_CHANGED", "CVAR_UPDATE", "PLAYER_REGEN_ENABLED",
}

local DB, AB, handler
local dirty, pending, reported = false, false, false
local macroButtons = {}
local seenState = {}  -- last value of each state-<bar> attribute, to tell real page changes from re-registration

local function safe(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok and not reported then
    reported = true
    say("WandStop: ошибка: " .. tostring(err))
  end
end

local api = {
  ActionInfo = function(slot) return GetActionInfo(slot) end,
  SpellName = function(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return (GetSpellInfo(id))
  end,
  SpellSubtext = function(id)
    if C_Spell and C_Spell.GetSpellSubtext then return C_Spell.GetSpellSubtext(id) end
    return GetSpellSubtext and GetSpellSubtext(id)
  end,
}

-- the same paging condition ElvUI drives the bar with (AB:GetPage, ActionBars.lua)
local function barCondition(barName)
  local d = AB.barDefaults and AB.barDefaults[barName]
  if d then return AB:GetPage(barName, d.page, d.conditions) end
end

-- every ElvUI action button: its keys, the slot it shows now, its bar and that bar's current page
local function barButtons()
  local list, conds = {}, {}
  for barName, bar in pairs(AB.handledBars) do
    local cond = barCondition(barName)
    local page = cond and tostring(SecureCmdOptionParse(cond))
    conds[barName] = cond
    for _, button in ipairs(bar.buttons or {}) do
      local keys = {}
      if button.keyBoundTarget then
        for _, key in ipairs({ GetBindingKey(button.keyBoundTarget) }) do
          if key ~= "" then keys[#keys + 1] = key end
        end
      end
      list[#list + 1] = {
        keys = keys, bar = barName, page = page,
        slot = button._state_type == "action" and button._state_action or nil,
      }
    end
  end
  return list, conds
end

local function macroButton(i)
  local b = macroButtons[i]
  if not b then
    b = CreateFrame("Button", "DSTWandStopButton" .. i, UIParent, "SecureActionButtonTemplate")
    b:Hide()
    b:SetAttribute("type", "macro")
    macroButtons[i] = b
  end
  return b
end

-- bindings can only change out of combat; a change in combat waits for PLAYER_REGEN_ENABLED
function mod.Rebuild()
  if not handler then return end
  if InCombatLockdown() then
    dirty = true
    return
  end
  dirty = false

  local list, conds = barButtons()
  local entries = {}
  if SecureCmdOptionParse(GUARD) ~= "1" then
    local mods = { self = AB.db and AB.db.checkSelfCast, focus = AB.db and AB.db.checkFocusCast }
    entries = S.Collect(list, api, S.ParseExclusions(DB.exclude), mods)
  end

  -- one edge only: the other one would /stopcasting the cast this press just started
  local down = GetCVarBool("ActionButtonUseKeyDown") and true or false
  for i, e in ipairs(entries) do
    local b = macroButton(i)
    b:SetAttribute("macrotext", e.text)
    b:RegisterForClicks(down and "AnyDown" or "AnyUp")
    b:SetAttribute("useOnKeyDown", down)
    handler:SetAttribute("key" .. i, e.key)
    handler:SetAttribute("button" .. i, b:GetName())
    handler:SetAttribute("barname" .. i, e.bar)
    handler:SetAttribute("page" .. i, e.page)
  end
  handler:SetAttribute("count", #entries)

  for barName, cond in pairs(conds) do
    handler:SetAttribute("_onstate-" .. barName, SNIPPET)
    -- the driver is about to set this very value: not a page change, no extra rebuild
    seenState["state-" .. barName] = tostring(SecureCmdOptionParse(cond))
    RegisterStateDriver(handler, barName, cond)
  end

  ClearOverrideBindings(handler)
  for i, e in ipairs(entries) do
    SetOverrideBindingClick(handler, true, e.key, macroButtons[i]:GetName())
  end
end

-- bars fire bursts of events: rebuild once they settle
local function schedule()
  if pending then return end
  pending = true
  C_Timer.After(0.2, function()
    pending = false
    safe(mod.Rebuild)
  end)
end

local function onEvent(_, event)
  if event == "PLAYER_REGEN_ENABLED" then
    if dirty then mod.Rebuild() end
  else
    schedule()
  end
end

-- a bar page changed (form, Shift+N, possess): rebuild for the new page once out of combat
local function onAttribute(_, name, value)
  if type(name) ~= "string" or not name:find("^state%-") then return end
  if seenState[name] == value then return end
  seenState[name] = value
  if InCombatLockdown() then dirty = true else schedule() end
end

function mod.OnEnable(db)
  DB = db
  local _, class = UnitClass("player")
  if not CLASSES[class] then return end

  local E = ElvUI and ElvUI[1]
  AB = E and E:GetModule("ActionBars", true)
  if not (AB and AB.handledBars and E.private and E.private.actionbar and E.private.actionbar.enable) then
    say("WandStop: панели ElvUI выключены, модуль не запущен")
    return
  end

  handler = CreateFrame("Frame", "DSTWandStopHandler", UIParent, "SecureHandlerStateTemplate")
  handler:HookScript("OnAttributeChanged", function(...) safe(onAttribute, ...) end)

  local f = CreateFrame("Frame")
  for _, e in ipairs(EVENTS) do pcall(f.RegisterEvent, f, e) end
  f:SetScript("OnEvent", function(...) safe(onEvent, ...) end)
  schedule()
end

function mod.options(db)
  return {
    exclude = {
      order = 2, type = "input", width = "full",
      name = "Не сбивать свой каст для заклинаний",
      desc = "Названия через запятую, например: Порча, Стрела Тьмы. Эти клавиши работают как обычно в ElvUI.",
      get = function() return db.exclude end,
      set = function(_, v)
        db.exclude = v
        safe(mod.Rebuild)
      end,
    },
  }
end
