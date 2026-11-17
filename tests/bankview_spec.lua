-- Headless specs for the snapshot logic in ElvUI_DeSyncUI/Modules/BankView.lua (Lua 5.1)
local passed, failed = 0, 0
local mod, db, fire, timers, said

local function frameStub()
  local f = { scripts = {} }
  function f:RegisterEvent() end
  function f:SetScript(k, fn) self.scripts[k] = fn end
  return f
end

local function setup()
  bags = { [6] = { size = 2, items = { [1] = { hyperlink = "|Hitem:1|h[Old]|h", stackCount = 1, iconFileID = 1 } } } }
  Enum = { BagIndex = {} }
  time = function() return 1000 end
  date = os.date
  UnitName = function() return "Desync" end
  GetRealmName = function() return "Realm" end
  C_Container = {
    GetContainerNumSlots = function(id) return bags[id] and bags[id].size or 0 end,
    GetContainerItemInfo = function(id, slot) return bags[id] and bags[id].items and bags[id].items[slot] end,
  }
  timers = {}
  C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
  local eventFrame
  CreateFrame = function() local f = frameStub(); eventFrame = eventFrame or f; return f end
  said = {}
  -- ElvUI with bags enabled; BagFrame not built yet, so the button is never attached here
  ElvUI = { { private = { bags = { enable = true } }, GetModule = function() return {} end } }

  local ns = { say = function(...) said[#said + 1] = table.concat({ ... }, " ") end }
  ns.NewModule = function(name, def) def.name = name; mod = def; return def end
  assert(loadfile(ROOT .. "/ElvUI_DeSyncUI/Modules/BankData.lua"))("ElvUI_DeSyncUI", ns)
  assert(loadfile(ROOT .. "/ElvUI_DeSyncUI/Modules/BankView.lua"))("ElvUI_DeSyncUI", ns)
  db = { chars = {} }
  mod.OnEnable(db)
  fire = function(event, arg) eventFrame.scripts.OnEvent(eventFrame, event, arg) end
end

-- runs the queued C_Timer callbacks that belong to the snapshot logic
local function flush()
  local list = timers
  timers = {}
  for _, fn in ipairs(list) do fn() end
end

local function saved() local s = db.chars["Desync-Realm"]; return s and s.bags[1].slots[1].link end

local function test(name, fn)
  local ok, err = pcall(function() setup() fn() end)
  if ok then passed = passed + 1; print("PASS " .. name)
  else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end

test("opening the bank saves a snapshot after the delay", function()
  fire("BANKFRAME_OPENED")
  assert(saved() == nil)
  flush()
  assert(saved() == "|Hitem:1|h[Old]|h")
end)

test("bag updates while the bank is closed do not touch the snapshot", function()
  fire("BANKFRAME_OPENED"); flush()
  fire("BANKFRAME_CLOSED")
  bags[6].items[1] = { hyperlink = "|Hitem:2|h[New]|h", stackCount = 1, iconFileID = 2 }
  fire("BAG_UPDATE", 0)
  flush()
  assert(saved() == "|Hitem:1|h[Old]|h")
end)

test("closing the bank flushes a pending save", function()
  fire("BANKFRAME_OPENED"); flush()
  bags[6].items[1] = { hyperlink = "|Hitem:2|h[New]|h", stackCount = 1, iconFileID = 2 }
  fire("BAG_UPDATE", 6)
  fire("BANKFRAME_CLOSED")
  assert(saved() == "|Hitem:2|h[New]|h")
  bags[6] = { size = 0 }
  flush()
  assert(saved() == "|Hitem:2|h[New]|h")
end)

test("closing right after a change never wipes the snapshot with an itemless read", function()
  fire("BANKFRAME_OPENED"); flush()
  fire("BAG_UPDATE", 6)
  bags[6] = { size = 2, items = {} }  -- slots still reported, items already gone
  fire("BANKFRAME_CLOSED")
  assert(saved() == "|Hitem:1|h[Old]|h")
end)

test("a closed bank (no slots) never overwrites the snapshot", function()
  fire("BANKFRAME_OPENED"); flush()
  bags[6] = { size = 0 }
  fire("BAG_UPDATE", 6)
  flush()
  assert(saved() == "|Hitem:1|h[Old]|h")
end)

test("module stays off with a message when ElvUI bags are disabled", function()
  ElvUI[1].private.bags.enable = false
  said = {}
  mod.OnEnable({ chars = {} })
  assert(#said == 1 and said[1]:find("BankView", 1, true))
end)

print(passed .. " passed, " .. failed .. " failed")
if failed > 0 then error("tests failed") end
