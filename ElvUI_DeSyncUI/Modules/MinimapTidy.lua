local ADDON, ns = ...
local mod = ns.NewModule("MinimapTidy", {
  title = "Кнопки у миникарты",
  desc = "Прячет значки аддонов у миникарты и кладёт их в штатный список «Модификации» "
      .. "(включите его показ в ElvUI, если он скрыт).",
  default = false,  -- the pack's profile hides the compartment: off unless chosen
  defaults = { names = {}, keep = {}, libdbicon = true },
})

local say = ns.say
local DB                          -- module settings, set in OnEnable / options
local handled, entries = {}, {}   -- frame -> true / compartment entry
local owner = {}                  -- callback owner for LibDBIcon

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

local function tuck(f, label)
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

local function untuck(f, label)
  if not f then return end
  handled[f] = nil
  local e = entries[f]
  entries[f] = nil
  if e and AddonCompartmentFrame and AddonCompartmentFrame.registeredAddons then
    for i, v in ipairs(AddonCompartmentFrame.registeredAddons) do
      if v == e then table.remove(AddonCompartmentFrame.registeredAddons, i) break end
    end
    if AddonCompartmentFrame.UpdateDisplay then AddonCompartmentFrame:UpdateDisplay() end
  end
  local lib = LibStub and LibStub("LibDBIcon-1.0", true)
  local ldbName = label and label:match("^LibDBIcon10_(.+)$")
  if lib and ldbName and lib.objects[ldbName] then
    local o = lib.objects[ldbName]
    if o.compartmentData then pcall(lib.RemoveButtonFromCompartment, lib, ldbName) end
    if o.db then o.db.hide = false end
  end
  if f.Show then f:Show() end
end

local function tuckLDB(lib, name)
  local o = lib.objects and lib.objects[name]
  if not o or handled[o] then return end
  if DB.keep["LibDBIcon10_" .. name] then return end
  pcall(lib.AddButtonToCompartment, lib, name)
  if o.db then o.db.hide = true end
  handled[o] = true
  o:Hide()
  hookShow(o)
end

local function doLibDBIcon()
  if not DB.libdbicon then return end
  local lib = LibStub and LibStub("LibDBIcon-1.0", true)
  if not lib then return end
  for _, n in ipairs(lib:GetButtonList()) do tuckLDB(lib, n) end
  if not lib.__dstCB then
    lib.__dstCB = true
    lib.RegisterCallback(owner, "LibDBIcon_IconCreated", function(_, _, name)
      C_Timer.After(0, function() if DB.libdbicon then tuckLDB(lib, name) end end)
    end)
  end
end

local function apply()
  doLibDBIcon()
  for name in pairs(DB.names) do
    local f = _G[name]
    if f then tuck(f, name) end
  end
end

-- button-like children of the minimap; map pins (QuestieFrame123 ...) are skipped,
-- a list with hundreds of toggles freezes ElvUI's options window
local function collect()
  local out, seen = {}, {}
  for _, parent in ipairs({ Minimap, MinimapBackdrop, MinimapCluster }) do
    if parent and parent.GetChildren then
      for _, c in ipairs({ parent:GetChildren() }) do
        local nm = c.GetName and c:GetName()
        if nm and not seen[nm] and c.IsObjectType
           and (c:IsObjectType("Button") or c:IsObjectType("CheckButton")) then
          seen[nm] = true
          local isPin = nm:find("^Questie") or (nm:find("%d+$") and not nm:find("^LibDBIcon10_"))
          if not isPin then out[#out + 1] = nm end
        end
      end
    end
  end
  table.sort(out)
  for i = #out, 81, -1 do out[i] = nil end
  return out
end

function mod.OnEnable(db)
  DB = db
  apply()
  C_Timer.After(2, apply)   -- other addons create buttons late
  C_Timer.After(6, apply)

  SLASH_DSTMINIMAP1 = "/dstmm"
  SlashCmdList.DSTMINIMAP = function(msg)
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    if cmd == "list" then
      local l = collect()
      say("кнопок у миникарты: " .. #l)
      for _, nm in ipairs(l) do say("  " .. nm .. (handled[_G[nm]] and "  [в Модификациях]" or "")) end
    elseif cmd == "hide" and arg ~= "" and _G[arg] then
      DB.names[arg], DB.keep[arg] = true, nil
      tuck(_G[arg], arg)
    elseif cmd == "unhide" and arg ~= "" and _G[arg] then
      DB.names[arg], DB.keep[arg] = nil, true
      untuck(_G[arg], arg)
    else
      say("/dstmm list | hide Имя | unhide Имя")
    end
  end
end

function mod.options(db)
  local list = { order = 20, type = "group", inline = true, name = "Кнопки у миникарты", args = {} }

  local function rebuild()
    local args = list.args
    wipe(args)
    args.hint = {
      order = 0, type = "description", fontSize = "medium",
      name = "Галочка = кнопка убрана с миникарты и лежит в списке «Модификации». "
          .. "Снимите галочку, чтобы вернуть кнопку. Штатные кнопки ElvUI (почта, календарь, трекинг) лучше не трогать.\n",
    }
    for i, nm in ipairs(collect()) do
      args["b" .. i] = {
        order = i, type = "toggle", width = "full", name = nm,
        get = function() return handled[_G[nm]] and true or false end,
        set = function(_, v)
          local f = _G[nm]
          if not f then return end
          DB = DB or db
          if v then
            db.names[nm], db.keep[nm] = true, nil
            tuck(f, nm)
          else
            db.names[nm], db.keep[nm] = nil, true
            untuck(f, nm)
          end
        end,
      }
    end
  end

  local function refresh()
    rebuild()
    local reg = LibStub("AceConfigRegistry-3.0", true)
    if reg then reg:NotifyChange("ElvUI") end
  end

  rebuild()
  return {
    libdbicon = {
      order = 2, type = "toggle", width = "full",
      name = "Автоматически убирать все значки LibDBIcon (Questie, MRT, ForeverAuras и т.д.)",
      get = function() return db.libdbicon end,
      set = function(_, v) db.libdbicon = v; if v then DB = db; apply() end; refresh() end,
    },
    refresh = { order = 4, type = "execute", name = "Обновить список", func = refresh },
    list = list,
  }
end
