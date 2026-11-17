-- Headless specs for ElvUI_DeSyncUI/Modules/WandStop.lua (Lua 5.1).
-- The restricted (in-combat) snippet is run here as plain Lua against a fake frame handle.
local passed, failed = 0, 0
local mod, db, said, binds, drivers, timers, eventFrame, made, AB
local combat, page, guard, keyDown, actions

local function obj(name)
  local o = { name = name, attrs = {}, scripts = {}, hooks = {}, clicks = {} }
  local methods = {
    GetName = function(self) return self.name end,
    SetAttribute = function(self, k, v)
      self.attrs[k] = v
      if self.hooks.OnAttributeChanged then self.hooks.OnAttributeChanged(self, k, v) end
    end,
    GetAttribute = function(self, k) return self.attrs[k] end,
    RegisterForClicks = function(self, ...) self.clicks = { ... } end,
    SetScript = function(self, k, fn) self.scripts[k] = fn end,
    HookScript = function(self, k, fn) self.hooks[k] = fn end,
    RegisterEvent = function(self) eventFrame = self end,
  }
  return setmetatable(o, { __index = function(_, k)
    if methods[k] then return methods[k] end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end

local function flush()
  local list = timers; timers = {}
  for _, fn in ipairs(list) do fn() end
end

local function setup(opts)
  opts = opts or {}
  for _, n in ipairs(made or {}) do _G[n] = nil end
  made, said, binds, drivers, timers = {}, {}, {}, {}, {}
  eventFrame, combat, page, guard, keyDown = nil, false, "1", nil, true
  -- slots: 1 Shadow Bolt, 2 macro, 3 item, 5 Shoot
  actions = { [1] = { "spell", 686 }, [2] = { "macro", 1 }, [3] = { "item", 6948 }, [5] = { "spell", 5019 } }
  local names = { [686] = "Стрела Тьмы", [172] = "Порча", [5019] = "Выстрел" }
  local keys = { ACTIONBUTTON1 = { "1" }, ACTIONBUTTON2 = { "2" }, ACTIONBUTTON3 = { "3" }, ACTIONBUTTON5 = { "5" } }

  UnitClass = function() return "Чернокнижник", opts.class or "WARLOCK" end
  InCombatLockdown = function() return combat end
  -- the module's possess/vehicle guard answers `guard`; any bar paging condition answers `page`
  SecureCmdOptionParse = function(cond)
    if cond:find("possessbar", 1, true) then return guard end
    return page
  end
  RegisterStateDriver = function(frame, name, cond)
    drivers[name] = cond
    frame:SetAttribute("state-" .. name, SecureCmdOptionParse(cond))
  end
  ClearOverrideBindings = function(owner) binds[owner] = {} end
  SetOverrideBindingClick = function(owner, prio, key, btn)
    binds[owner] = binds[owner] or {}
    binds[owner][key] = { prio = prio, btn = btn }
  end
  GetBindingKey = function(target) return unpack(keys[target] or {}) end
  GetActionInfo = function(slot) local a = actions[slot]; if a then return a[1], a[2] end end
  C_Spell = { GetSpellName = function(id) return names[id] end, GetSpellSubtext = function() return nil end }
  GetCVarBool = function(name) if name == "ActionButtonUseKeyDown" then return keyDown end end
  C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
  UIParent = obj()
  CreateFrame = function(_, name)
    local o = obj(name)
    if name then _G[name] = o; made[#made + 1] = name end
    return o
  end
  local buttons = {}
  for _, slot in ipairs({ 1, 2, 3, 5 }) do
    buttons[#buttons + 1] = { keyBoundTarget = "ACTIONBUTTON" .. slot, _state_type = "action", _state_action = slot }
  end
  AB = {
    handledBars = { bar1 = { buttons = buttons } },
    barDefaults = { bar1 = { page = 1, conditions = "[bar:2] 2;" } },
    db = { checkSelfCast = opts.selfCast or false, checkFocusCast = false, bar1 = { paging = {} } },
    GetPage = function(_, bar, defaultPage, condition) return (condition or "") .. " " .. defaultPage end,
  }
  ElvUI = { {
    private = { actionbar = { enable = opts.barsOff ~= true } },
    GetModule = function(_, n) if n == "ActionBars" then return AB end end,
  } }

  local ns = { say = function(...) said[#said + 1] = table.concat({ ... }, " ") end }
  ns.NewModule = function(name, def) def.name = name; mod = def; return def end
  for _, f in ipairs({ "BankData.lua", "WandStopData.lua", "WandStop.lua" }) do
    assert(loadfile(ROOT .. "/ElvUI_DeSyncUI/Modules/" .. f))("ElvUI_DeSyncUI", ns)
  end
  db = { exclude = "" }
  mod.OnEnable(db)
  if eventFrame then eventFrame.scripts.OnEvent(eventFrame, "PLAYER_ENTERING_WORLD") end
  flush()
end

local function fire(event, arg) eventFrame.scripts.OnEvent(eventFrame, event, arg) end
local function hb() return binds[_G.DSTWandStopHandler] or {} end

-- runs the handler's restricted snippet the way the state driver would, against a fake handle
local function runSnippet(stateName, newstate)
  local h = _G.DSTWandStopHandler
  h.attrs["state-" .. stateName] = newstate
  local fn = assert(loadstring("local self, stateid, newstate = ...\n" .. h:GetAttribute("_onstate-" .. stateName)))
  local bound, cleared = {}, false
  local handle = {
    GetAttribute = function(_, k) return h.attrs[k] end,
    ClearBindings = function() cleared = true; bound = {} end,
    SetBindingClick = function(_, prio, key, btn) bound[key] = { prio = prio, btn = btn } end,
  }
  fn(handle, stateName, newstate)
  return bound, cleared
end

local function test(name, fn)
  local ok, err = pcall(function() setup() fn() end)
  if ok then passed = passed + 1; print("PASS " .. name)
  else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end

test("binds the key of a spell button to a macro button with priority", function()
  local b = hb()["1"]
  assert(b and b.prio == true)
  local btn = _G[b.btn]
  assert(btn:GetAttribute("type") == "macro")
  assert(btn:GetAttribute("macrotext") == "/stopcasting [nochanneling]\n/cast Стрела Тьмы")
end)

test("fires on one edge only, following ActionButtonUseKeyDown", function()
  local btn = _G[hb()["1"].btn]
  assert(btn.clicks[1] == "AnyDown" and #btn.clicks == 1 and btn:GetAttribute("useOnKeyDown") == true)
  keyDown = false; fire("CVAR_UPDATE", "ActionButtonUseKeyDown"); flush()
  btn = _G[hb()["1"].btn]
  assert(btn.clicks[1] == "AnyUp" and #btn.clicks == 1 and btn:GetAttribute("useOnKeyDown") == false)
end)

test("macro, item and Shoot buttons get no binding", function()
  local h = hb()
  assert(h["2"] == nil and h["3"] == nil and h["5"] == nil)
end)

test("a driver per bar uses ElvUI's own paging condition", function()
  assert(drivers.bar1 == "[bar:2] 2; 1")
  local h = _G.DSTWandStopHandler
  assert(h:GetAttribute("count") == 1 and h:GetAttribute("key1") == "1")
  assert(h:GetAttribute("barname1") == "bar1" and h:GetAttribute("page1") == "1")
  assert(h:GetAttribute("button1") == hb()["1"].btn)
end)

test("in combat the snippet binds only keys whose bar shows the recorded page", function()
  local bound, cleared = runSnippet("bar1", "1")
  assert(cleared and bound["1"] and bound["1"].prio == true and bound["1"].btn == hb()["1"].btn)
  bound, cleared = runSnippet("bar1", "7")   -- e.g. Shadowform or Shift+2 paged the bar
  assert(cleared and next(bound) == nil)
end)

test("nothing is recorded while possessed or in a vehicle", function()
  guard = "1"; fire("UPDATE_BONUS_ACTIONBAR"); flush()
  assert(next(hb()) == nil and _G.DSTWandStopHandler:GetAttribute("count") == 0)
end)

test("a page change out of combat rebuilds for the new page; re-registering does not loop", function()
  assert(#timers == 0)
  page = "7"; actions[1] = { "spell", 172 }
  _G.DSTWandStopHandler:SetAttribute("state-bar1", "7")  -- what the state driver does
  flush()
  assert(_G.DSTWandStopHandler:GetAttribute("page1") == "7")
  assert(_G[hb()["1"].btn]:GetAttribute("macrotext"):find("Порча", 1, true))
  flush()
  assert(#timers == 0)
end)

test("self-cast setting follows ElvUI", function()
  setup({ selfCast = true })
  assert(_G[hb()["1"].btn]:GetAttribute("macrotext")
    == "/stopcasting [nochanneling]\n/cast [mod:SELFCAST,@player][] Стрела Тьмы")
end)

test("changes in combat wait for the end of combat", function()
  combat = true
  actions[1] = { "spell", 172 }
  fire("ACTIONBAR_SLOT_CHANGED", 1); flush()
  assert(_G[hb()["1"].btn]:GetAttribute("macrotext"):find("Стрела Тьмы", 1, true))
  combat = false
  fire("PLAYER_REGEN_ENABLED"); flush()
  assert(_G[hb()["1"].btn]:GetAttribute("macrotext"):find("Порча", 1, true))
end)

test("exclusions from settings release the key", function()
  local opt = mod.options(db)
  opt.exclude.set(nil, "стрела тьмы")
  flush()
  assert(db.exclude == "стрела тьмы" and opt.exclude.get() == "стрела тьмы")
  assert(hb()["1"] == nil and _G.DSTWandStopHandler:GetAttribute("count") == 0)
end)

test("other classes are left alone", function()
  setup({ class = "ROGUE" })
  assert(_G.DSTWandStopHandler == nil and next(said) == nil)
end)

test("ElvUI action bars off: message, nothing bound", function()
  setup({ barsOff = true })
  assert(_G.DSTWandStopHandler == nil and #said == 1 and said[1]:find("WandStop", 1, true))
end)

print(passed .. " passed, " .. failed .. " failed")
if failed > 0 then error("tests failed") end
