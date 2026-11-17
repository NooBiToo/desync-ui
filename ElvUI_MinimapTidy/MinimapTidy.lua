local ADDON, ns = ...
local P = "|cff33ccffMinimapTidy|r: "
local function say(...) print(P .. strjoin(" ", tostringall(...))) end
ns.say = say

MinimapTidyDB = MinimapTidyDB or {}
local DB = MinimapTidyDB
DB.names = DB.names or {}   -- frames tucked by hand (name -> true)
DB.keep  = DB.keep  or {}   -- frames that must stay on the minimap (name -> true)
if DB.libdbicon == nil then DB.libdbicon = true end   -- tuck all LibDBIcon buttons automatically
if DB.keepMerOff == nil then DB.keepMerOff = true end -- keep MerathilisUI "Addon Buttons" off
if DB.debug == nil then DB.debug = true end           -- diagnostic build: print timings
ns.DB = DB

local handled, entries = {}, {}   -- frame -> true / compartment entry
ns.handled = handled

local function iconOf(f)
  if f.icon and f.icon.GetTexture and f.icon:GetTexture() then return f.icon:GetTexture() end
  local nt = f.GetNormalTexture and f:GetNormalTexture()
  if nt and nt:GetTexture() then return nt:GetTexture() end
  for _, r in ipairs({ f:GetRegions() }) do
    if r.IsObjectType and r:IsObjectType("Texture") and r:GetTexture()
       and not tostring(r:GetTexture()):find("Border") then
      return r:GetTexture()
    end
  end
  return 134400
end

local hooked = {}
local function hookShow(f)
  if hooked[f] then return end
  hooked[f] = true
  hooksecurefunc(f, "Show", function(self) if handled[self] then self:Hide() end end)
  if f.SetShown then
    hooksecurefunc(f, "SetShown", function(self, s) if s and handled[self] then self:Hide() end end)
  end
end

-- hide a frame and add a clickable entry to the Addon Compartment
function ns.tuck(f, label)
  if not f or handled[f] then return end
  if DB.keep[label] or (f.GetName and DB.keep[f:GetName() or ""]) then return end
  handled[f] = true
  if AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon then
    local e = {
      text = label, icon = iconOf(f), notCheckable = true, registerForAnyClick = true,
      func = function(_, input)
        if f.Click then f:Click((input and input.buttonName) or "LeftButton") end
      end,
    }
    entries[f] = e
    AddonCompartmentFrame:RegisterAddon(e)
  end
  f:Hide()
  hookShow(f)
end

-- undo ns.tuck
function ns.untuck(f, label)
  if not f then return end
  local t0 = debugprofilestop()
  local function lap(what)
    local t = debugprofilestop()
    if DB.debug then say(format("untuck %s | %s: %.0f мс", tostring(label), what, t - t0)) end
    t0 = t
  end
  handled[f] = nil
  local e = entries[f]
  entries[f] = nil
  if e and AddonCompartmentFrame and AddonCompartmentFrame.registeredAddons then
    for i, v in ipairs(AddonCompartmentFrame.registeredAddons) do
      if v == e then table.remove(AddonCompartmentFrame.registeredAddons, i) break end
    end
    lap("убрал запись из списка (свой путь)")
    if AddonCompartmentFrame.UpdateDisplay then AddonCompartmentFrame:UpdateDisplay() end
    lap("UpdateDisplay (свой путь)")
  end
  -- LibDBIcon keeps its own flags in the owning addon's saved data
  local lib = LibStub and LibStub("LibDBIcon-1.0", true)
  local ldbName = label and label:match("^LibDBIcon10_(.+)$")
  if lib and ldbName and lib.objects[ldbName] then
    local o = lib.objects[ldbName]
    if o.compartmentData then pcall(lib.RemoveButtonFromCompartment, lib, ldbName) end
    if o.db then o.db.hide = false end
    lap("LibDBIcon:RemoveButtonFromCompartment")
  end
  if f.Show then f:Show() end
  lap("f:Show()")
end

local function tuckLDB(lib, name)
  local o = lib.objects and lib.objects[name]
  if not o or handled[o] then return end
  if DB.keep["LibDBIcon10_" .. name] then return end
  pcall(lib.AddButtonToCompartment, lib, name)   -- also sets db.showInCompartment
  if o.db then o.db.hide = true end
  -- the library already registered the compartment entry, only hide the button
  handled[o] = true
  o:Hide()
  hookShow(o)
end

local function doLibDBIcon()
  if not DB.libdbicon then return end
  local lib = LibStub and LibStub("LibDBIcon-1.0", true)
  if not lib then return end
  for _, n in ipairs(lib:GetButtonList()) do tuckLDB(lib, n) end
  if not lib.__mmtCB then
    lib.__mmtCB = true
    lib.RegisterCallback(DB, "LibDBIcon_IconCreated", function(_, _, name)
      C_Timer.After(0, function() tuckLDB(lib, name) end)
    end)
  end
end

local function doElvUI()
  if not DB.keepMerOff then return end
  local ok, E = pcall(function() return ElvUI and ElvUI[1] end)
  if not ok or not E or not E.db then return end
  local ab = E.db.mui and E.db.mui.minimapButtons and E.db.mui.minimapButtons.addonButtons
  if ab and ab.enable then
    ab.enable = false
    say("MerathilisUI Addon Buttons выключен (нужен /reload, чтобы пропала панель)")
  end
end

function ns.apply()
  doElvUI()
  doLibDBIcon()
  for name in pairs(DB.names) do
    local f = _G[name]
    if f then ns.tuck(f, name) end
  end
end

-- every button-like child of the minimap, for the options list and /mmt list
function ns.collect()
  local out, seen = {}, {}
  for _, parent in ipairs({ Minimap, MinimapBackdrop, MinimapCluster }) do
    if parent and parent.GetChildren then
      for _, c in ipairs({ parent:GetChildren() }) do
        local nm = c.GetName and c:GetName()
        if nm and not seen[nm] and c.IsObjectType
           and (c:IsObjectType("Button") or c:IsObjectType("CheckButton")) then
          seen[nm] = true
          -- map pins (QuestieFrame123, ...Pin45, ...) are children of the minimap too, hundreds of them,
          -- they are not buttons: only LibDBIcon buttons and names without a trailing number pass
          local isPin = nm:find("^Questie") or (nm:find("%d+$") and not nm:find("^LibDBIcon10_"))
          if not isPin then
            out[#out + 1] = nm
          end
        end
      end
    end
  end
  table.sort(out)
  -- safety net: a UI list with hundreds of toggles freezes ElvUI's options window
  for i = #out, 81, -1 do out[i] = nil end
  return out
end

-- diagnostics: every step reports its result, errors are printed instead of swallowed
ns.status = {}
function ns.step(name, fn, ...)
  local ok, err = pcall(fn, ...)
  ns.status[name] = ok and "ok" or ("ОШИБКА: " .. tostring(err))
  if not ok then say("ошибка в шаге '" .. name .. "': " .. tostring(err)) end
  return ok
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, loaded)
  if event == "ADDON_LOADED" then
    if loaded ~= ADDON then return end
    -- WoW loads SavedVariables AFTER our files ran and replaces the global MinimapTidyDB with the saved table.
    -- Our local DB still points at the table made at file load, which the game never writes out.
    -- Copy the saved data into DB and make DB the global again, so every later change is saved.
    local saved = _G.MinimapTidyDB
    if saved and saved ~= DB then
      for k, v in pairs(saved) do DB[k] = v end
      if type(DB.names) ~= "table" then DB.names = {} end
      if type(DB.keep) ~= "table" then DB.keep = {} end
    end
    _G.MinimapTidyDB = DB
    return
  end
  -- options first: a failure in apply() must not take the panel down with it
  if ns.RegisterOptions then ns.step("options", ns.RegisterOptions) end
  ns.step("apply", ns.apply)
  C_Timer.After(2, function() ns.step("apply+2s", ns.apply) end)   -- other addons create buttons late
  C_Timer.After(6, function() ns.step("apply+6s", ns.apply) end)
end)

SLASH_MINIMAPTIDY1 = "/mmt"
SlashCmdList.MINIMAPTIDY = function(msg)
  local cmd, arg = msg:match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  if cmd == "list" then
    local l = ns.collect()
    say("кнопок у миникарты: " .. #l)
    for _, nm in ipairs(l) do
      say("  " .. nm .. (handled[_G[nm]] and "  [в Модификациях]" or ""))
    end
  elseif cmd == "status" then
    local lib = LibStub and LibStub("LibDBIcon-1.0", true)
    local nl, nh = 0, 0
    if lib then
      for _, n in ipairs(lib:GetButtonList()) do
        nl = nl + 1
        if handled[lib.objects[n]] then nh = nh + 1 end
      end
    end
    local E = ElvUI and ElvUI[1]
    say("версия аддона: " .. tostring(C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version") or GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version")))
    say("ElvUI: " .. tostring(E ~= nil) .. " | LibElvUIPlugin: " .. tostring(LibStub and LibStub("LibElvUIPlugin-1.0", true) ~= nil))
    say("ElvUI_Options загружен: " .. tostring(IsAddOnLoaded and IsAddOnLoaded("ElvUI_Options")) .. " | панель в E.Options: " .. tostring(E and E.Options and E.Options.args and E.Options.args.MinimapTidy ~= nil))
    say("AddonCompartmentFrame: " .. tostring(AddonCompartmentFrame ~= nil) .. " | LibDBIcon: " .. tostring(lib ~= nil) .. " | кнопок LDB: " .. nl .. ", убрано: " .. nh)
    say("шаги: options=" .. tostring(ns.status.options) .. " | apply=" .. tostring(ns.status.apply) .. " | +2s=" .. tostring(ns.status["apply+2s"]) .. " | +6s=" .. tostring(ns.status["apply+6s"]))
    say("callback панели вызван: " .. tostring(ns.status.optionsCallback))
  elseif cmd == "ldblist" then
    local lib = LibStub and LibStub("LibDBIcon-1.0", true)
    if not lib then say("LibDBIcon не найден") return end
    for _, n in ipairs(lib:GetButtonList()) do
      local o = lib.objects[n]
      say("  " .. n .. " | frame=" .. tostring(o:GetName()) .. " | shown=" .. tostring(o:IsShown()) .. " | убран=" .. tostring(handled[o] and true or false))
    end
  elseif cmd == "hide" and arg ~= "" and _G[arg] then
    DB.names[arg], DB.keep[arg] = true, nil
    ns.tuck(_G[arg], arg)
  elseif cmd == "unhide" and arg ~= "" and _G[arg] then
    DB.names[arg], DB.keep[arg] = nil, true
    ns.untuck(_G[arg], arg)
  else
    say("Настройки: /ec -> MinimapTidy. Консоль: /mmt list | hide Имя | unhide Имя")
  end
end
