-- Headless specs for ElvUI_DeSyncUI/Modules/WandStopData.lua (Lua 5.1). Run: tests/run.py
local passed, failed = 0, 0
local S, api

-- action slots: 1 Shadow Bolt, 2 macro, 3 item, 4 empty, 5 Shoot, 6 Auto Shot, 8 Corruption, 9 spell without a name
local actions = {
  [1] = { "spell", 686 }, [2] = { "macro", 1 }, [3] = { "item", 6948 },
  [5] = { "spell", 5019 }, [6] = { "spell", 75 }, [8] = { "spell", 172 }, [9] = { "spell", 99999 },
}
local names = { [686] = "Стрела Тьмы", [5019] = "Выстрел", [75] = "Автоматическая стрельба", [172] = "Порча" }

local function setup()
  local ns = {}
  assert(loadfile(ROOT .. "/ElvUI_DeSyncUI/Modules/BankData.lua"))("ElvUI_DeSyncUI", ns)
  assert(loadfile(ROOT .. "/ElvUI_DeSyncUI/Modules/WandStopData.lua"))("ElvUI_DeSyncUI", ns)
  S = ns.WandStopData
  api = {
    ActionInfo = function(slot) local a = actions[slot]; if a then return a[1], a[2] end end,
    SpellName = function(id) return names[id] end,
    SpellSubtext = function() return nil end,
  }
end

local function test(name, fn)
  local ok, err = pcall(function() setup() fn() end)
  if ok then passed = passed + 1; print("PASS " .. name)
  else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end

test("MacroText plain and with rank", function()
  assert(S.MacroText("Стрела Тьмы") == "/stopcasting [nochanneling]\n/cast Стрела Тьмы")
  assert(S.MacroText("Стрела Тьмы", "Уровень 3") == "/stopcasting [nochanneling]\n/cast Стрела Тьмы(Уровень 3)")
  assert(S.MacroText("Каменная кожа", "Расовая способность") == "/stopcasting [nochanneling]\n/cast Каменная кожа")
  assert(S.MacroText("Порча", "") == "/stopcasting [nochanneling]\n/cast Порча")
end)

test("ParseExclusions trims, lowercases, skips empties", function()
  local ex = S.ParseExclusions(" порча , Стрела тьмы,, ")
  assert(ex["порча"] and ex["стрела тьмы"])
  local n = 0
  for _ in pairs(ex) do n = n + 1 end
  assert(n == 2)
  assert(next(S.ParseExclusions(nil)) == nil and next(S.ParseExclusions("")) == nil)
end)

test("Collect maps every key of a spell button", function()
  local out = S.Collect({ { keys = { "1", "SHIFT-1" }, slot = 1 } }, api, {})
  assert(#out == 2 and out[1].key == "1" and out[2].key == "SHIFT-1")
  assert(out[1].text == "/stopcasting [nochanneling]\n/cast Стрела Тьмы" and out[2].text == out[1].text)
end)

test("Collect uses the rank from the spell subtext", function()
  api.SpellSubtext = function(id) if id == 686 then return "Уровень 3" end end
  local out = S.Collect({ { keys = { "1" }, slot = 1 } }, api, {})
  assert(out[1].text == "/stopcasting [nochanneling]\n/cast Стрела Тьмы(Уровень 3)")
end)

test("Collect skips macros, items, empty slots, no keys, Shoot and Auto Shot", function()
  local out = S.Collect({
    { keys = { "2" }, slot = 2 }, { keys = { "3" }, slot = 3 }, { keys = { "4" }, slot = 4 },
    { keys = { "5" }, slot = 5 }, { keys = { "6" }, slot = 6 }, { keys = {}, slot = 1 },
    { keys = { "7" }, slot = nil },
  }, api, {})
  assert(#out == 0)
  assert(S.SKIP[5019] and S.SKIP[75])
end)

test("Collect honours exclusions case-insensitively", function()
  local out = S.Collect({ { keys = { "1" }, slot = 1 }, { keys = { "8" }, slot = 8 } }, api,
    S.ParseExclusions("СТРЕЛА ТЬМЫ"))
  assert(#out == 1 and out[1].key == "8" and out[1].text:find("Порча", 1, true))
end)

test("MacroText adds self- and focus-cast clauses like ElvUI buttons", function()
  assert(S.MacroText("Щит", nil, { self = true, focus = true })
    == "/stopcasting [nochanneling]\n/cast [mod:SELFCAST,@player][mod:FOCUSCAST,@focus,exists][] Щит")
  assert(S.MacroText("Щит", "Уровень 2", { self = true })
    == "/stopcasting [nochanneling]\n/cast [mod:SELFCAST,@player][] Щит(Уровень 2)")
  assert(S.MacroText("Щит", nil, {}) == "/stopcasting [nochanneling]\n/cast Щит")
end)

test("Collect carries the bar and its page, and passes cast modifiers", function()
  local out = S.Collect({ { keys = { "1" }, slot = 1, bar = "bar1", page = "7" } }, api, {}, { focus = true })
  assert(out[1].bar == "bar1" and out[1].page == "7")
  assert(out[1].text == "/stopcasting [nochanneling]\n/cast [mod:FOCUSCAST,@focus,exists][] Стрела Тьмы")
end)

test("Collect skips a spell whose name is unknown", function()
  local out = S.Collect({ { keys = { "9" }, slot = 9 } }, api, {})
  assert(#out == 0)
end)

print(passed .. " passed, " .. failed .. " failed")
if failed > 0 then error("tests failed") end
