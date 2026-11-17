local ADDON, ns = ...
local DB = ns.DB

function ns.RegisterOptions()
  local E = ElvUI and ElvUI[1]
  if not E then error("ElvUI не найден") end
  local EP = (E.Libs and E.Libs.EP) or LibStub("LibElvUIPlugin-1.0", true)
  if not EP then error("LibElvUIPlugin не найден") end

  local list = { order = 20, type = "group", inline = true, name = "Кнопки у миникарты", args = {} }

  local function rebuild()
    local args = list.args
    wipe(args)
    args.hint = {
      order = 0, type = "description", fontSize = "medium",
      name = "Галочка = кнопка убрана с миникарты и лежит в списке «Модификации». "
          .. "Снимите галочку, чтобы вернуть кнопку. Штатные кнопки ElvUI (почта, календарь, трекинг) лучше не трогать.\n",
    }
    for i, nm in ipairs(ns.collect()) do
      args["b" .. i] = {
        order = i, type = "toggle", width = "full", name = nm,
        get = function() return ns.handled[_G[nm]] and true or false end,
        set = function(_, v)
          local f = _G[nm]
          if not f then return end
          if DB.debug then ns.say("toggle " .. nm .. " -> " .. tostring(v)) end
          if v then
            DB.names[nm], DB.keep[nm] = true, nil
            ns.tuck(f, nm)
          else
            DB.names[nm], DB.keep[nm] = nil, true
            ns.untuck(f, nm)
          end
        end,
      }
    end
  end

  local function refresh()
    local t0 = debugprofilestop()
    rebuild()
    local t1 = debugprofilestop()
    local reg = LibStub("AceConfigRegistry-3.0", true)
    if reg then reg:NotifyChange("ElvUI") end
    if DB.debug then
      ns.say(format("refresh: rebuild %.0f мс | NotifyChange %.0f мс", t1 - t0, debugprofilestop() - t1))
    end
  end

  EP:RegisterPlugin(ADDON, function()
    ns.status.optionsCallback = "вызван"
    local ok, err = pcall(rebuild)
    if not ok then ns.status.optionsCallback = "ОШИБКА rebuild: " .. tostring(err) end
    E.Options.args.MinimapTidy = {
      order = 99, type = "group", name = "MinimapTidy",
      args = {
        header = { order = 1, type = "header", name = "MinimapTidy: кнопки аддонов в «Модификации»" },
        libdbicon = {
          order = 2, type = "toggle", width = "full",
          name = "Автоматически убирать все значки LibDBIcon (Questie, MRT, ForeverAuras и т.д.)",
          get = function() return DB.libdbicon end,
          set = function(_, v) DB.libdbicon = v; if v then ns.apply() end; refresh() end,
        },
        keepMerOff = {
          order = 3, type = "toggle", width = "full",
          name = "Держать выключенным MerathilisUI «Addon Buttons» (дубль «Модификаций»)",
          desc = "Применяется при входе в игру. Чтобы панель пропала сразу, нужен /reload.",
          get = function() return DB.keepMerOff end,
          set = function(_, v) DB.keepMerOff = v; if v then ns.apply() end end,
        },
        refresh = { order = 4, type = "execute", name = "Обновить список", func = refresh },
        list = list,
      },
    }
  end)
end
