local ADDON, ns = ...
local P = "|cff33ccffDeSync UI|r: "
function ns.say(...) print(P .. strjoin(" ", tostringall(...))) end

-- ns.DB is a stable table. The game replaces the SavedVariables global AFTER our files ran,
-- so on ADDON_LOADED we copy the saved data into ns.DB and make it the global again.
local DB = { modules = {} }
ns.DB = DB

ns.modules, ns.order = {}, {}

-- def = { title, desc, default (enabled by default), defaults = {...}, OnEnable = function(db), options = function(db) -> args }
function ns.NewModule(name, def)
  def.name = name
  ns.modules[name] = def
  ns.order[#ns.order + 1] = name
  return def
end

local function fill(t, defaults)
  for k, v in pairs(defaults or {}) do
    if t[k] == nil then
      if type(v) == "table" then t[k] = {}; fill(t[k], v) else t[k] = v end
    end
  end
end

function ns.ModuleDB(name)
  local def = ns.modules[name]
  DB.modules[name] = DB.modules[name] or {}
  local m = DB.modules[name]
  if m.enabled == nil then m.enabled = def.default ~= false end
  fill(m, def.defaults)
  return m
end

local started = {}
local function startModule(name)
  local def = ns.modules[name]
  if started[name] or not def.OnEnable then return end
  started[name] = true
  local ok, err = pcall(def.OnEnable, ns.ModuleDB(name))
  if not ok then ns.say("ошибка в модуле " .. name .. ": " .. tostring(err)) end
end

local function registerOptions()
  local E = ElvUI and ElvUI[1]
  if not E then return end
  local EP = (E.Libs and E.Libs.EP) or LibStub("LibElvUIPlugin-1.0", true)
  if not EP then return end

  EP:RegisterPlugin(ADDON, function()
    local args = {
      header = { order = 1, type = "header", name = "DeSync UI" },
      info = {
        order = 2, type = "description", fontSize = "medium",
        name = "Сборка интерфейса на ElvUI и модули DeSync. Каждый модуль включается отдельно. "
          .. "Выключение модуля вступает в силу после /reload.\n",
      },
      install = {
        order = 3, type = "execute", name = "Запустить установку",
        desc = "Окно установки DeSync UI: применить вид сборки (то же, что /desync install).",
        func = function() if ns.Installer then ns.Installer.Open() end end,
      },
    }
    for i, name in ipairs(ns.order) do
      local def = ns.modules[name]
      local mdb = ns.ModuleDB(name)
      local g = {
        order = 10 + i, type = "group", name = def.title or name, args = {},
      }
      g.args.enabled = {
        order = 1, type = "toggle", width = "full", name = "Включить модуль",
        get = function() return mdb.enabled end,
        set = function(_, v)
          mdb.enabled = v
          if v then startModule(name) else ns.say("«" .. (def.title or name) .. "» выключится после /reload") end
        end,
      }
      if def.desc then g.args.desc = { order = 2, type = "description", name = def.desc .. "\n" } end
      if def.options then
        local ok, extra = pcall(def.options, mdb)
        if ok and type(extra) == "table" then
          for k, v in pairs(extra) do
            v.order = (v.order or 0) + 10
            v.disabled = function() return not mdb.enabled end
            g.args[k] = v
          end
        elseif not ok then
          ns.say("ошибка в настройках модуля " .. name .. ": " .. tostring(extra))
        end
      end
      args[name] = g
    end
    E.Options.args.DeSyncTools = { order = 99, type = "group", name = "DeSync UI", childGroups = "tree", args = args }
  end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, loaded)
  if event == "ADDON_LOADED" then
    if loaded ~= ADDON then return end
    local saved = _G.DeSyncToolsDB
    if type(saved) == "table" and saved ~= DB then
      for k, v in pairs(saved) do DB[k] = v end
    end
    if type(DB.modules) ~= "table" then DB.modules = {} end
    DB.modules.TipLog = nil -- the temporary tooltip journal (0.6 debug build) is gone; drop its saved log
    _G.DeSyncToolsDB = DB
    return
  end
  registerOptions()
  for _, name in ipairs(ns.order) do
    if ns.ModuleDB(name).enabled then startModule(name) end
  end
end)

SLASH_DESYNCTOOLS1 = "/dst"
SlashCmdList.DESYNCTOOLS = function()
  ns.say("модули:")
  for _, name in ipairs(ns.order) do
    ns.say("  " .. name .. ": " .. (ns.ModuleDB(name).enabled and "включён" or "выключен"))
  end
  ns.say("настройки: /ec -> DeSync UI")
end
