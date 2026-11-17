-- Headless specs for ElvUI_DeSyncUI/Modules/BankData.lua (Lua 5.1). Run: tests/run.py
local passed, failed = 0, 0
local D

-- per-test WoW API stubs; `bags[bagID] = { size = n, items = { [slot] = info } }`
local function setup()
  bags = {}
  Enum = { BagIndex = {} }
  time = function() return 1000 end
  date = os.date
  UnitName = function() return "Десинк" end
  GetRealmName = function() return "Flamegor" end
  C_Container = {
    GetContainerNumSlots = function(id) return bags[id] and bags[id].size or 0 end,
    GetContainerItemInfo = function(id, slot) return bags[id] and bags[id].items and bags[id].items[slot] end,
  }
  local ns = {}
  local chunk = assert(loadfile(ROOT .. "/ElvUI_DeSyncUI/Modules/BankData.lua"))
  chunk("ElvUI_DeSyncUI", ns)
  D = ns.BankData
end

local function test(name, fn)
  local ok, err = pcall(function() setup() fn() end)
  if ok then
    passed = passed + 1
    print("PASS " .. name)
  else
    failed = failed + 1
    print("FAIL " .. name .. ": " .. tostring(err))
  end
end

test("all addon files compile", function()
  for _, f in ipairs({ "Core.lua", "Modules/LootRoll.lua", "Modules/MinimapTidy.lua",
                       "Modules/BankData.lua", "Modules/BankWindow.lua", "Modules/BankView.lua" }) do
    local fn, err = loadfile(ROOT .. "/ElvUI_DeSyncUI/" .. f)
    -- files from later tasks may not exist yet: only "cannot open" is tolerated
    assert(fn or tostring(err):find("cannot open"), f .. ": " .. tostring(err))
  end
end)

test("BankBagIDs uses CharacterBankTab_1..9", function()
  for i = 1, 9 do Enum.BagIndex["CharacterBankTab_" .. i] = 100 + i end
  assert(table.concat(D.BankBagIDs(), ",") == "101,102,103,104,105,106,107,108,109")
end)

test("BankBagIDs falls back to 6..14", function()
  assert(table.concat(D.BankBagIDs(), ",") == "6,7,8,9,10,11,12,13,14")
  Enum = nil
  assert(table.concat(D.BankBagIDs(), ",") == "6,7,8,9,10,11,12,13,14")
end)

test("ReadBank returns nil when bank is not readable", function()
  bags = { [6] = { size = 0 }, [7] = { size = 0 } }
  assert(D.ReadBank({ 6, 7 }) == nil)
end)

test("ReadBank records items and skips empty slots and zero-size bags", function()
  bags = {
    [6] = { size = 3, items = { [2] = { hyperlink = "|cff1eff00|Hitem:2589|h[Льняная ткань]|h|r",
                                        stackCount = 5, iconFileID = 123, quality = 2 } } },
    [7] = { size = 0 },
    [8] = { size = 2 },
  }
  local s = D.ReadBank({ 6, 7, 8 })
  assert(s.time == 1000 and #s.bags == 2)
  assert(s.bags[1].id == 6 and s.bags[1].size == 3 and s.bags[2].id == 8 and s.bags[2].size == 2)
  assert(s.bags[1].slots[1] == nil and s.bags[1].slots[3] == nil)
  local it = s.bags[1].slots[2]
  assert(it.count == 5 and it.icon == 123 and it.quality == 2 and it.link:find("2589", 1, true))
end)

test("CharKey is Name-Realm", function()
  assert(D.CharKey() == "Десинк-Flamegor")
end)

test("Save/Get/Chars", function()
  local db = { chars = {} }
  D.Save(db, "B-x", { time = 1, bags = {} })
  D.Save(db, "A-x", { time = 2, bags = {} })
  assert(D.Get(db, "A-x").time == 2 and D.Get(db, "nobody") == nil)
  assert(table.concat(D.Chars(db), ",") == "A-x,B-x")
end)

test("Lower folds Latin and Cyrillic incl. Yo", function()
  assert(D.Lower("ЁЛКА Mixed") == "ёлка mixed")
  assert(D.Lower("АПРЯ") == "апря")
end)

test("Matches", function()
  local it = { link = "|cff1eff00|Hitem:2589|h[Льняная ткань]|h|r" }
  assert(D.ItemName(it) == "Льняная ткань")
  assert(D.Matches(it, "") and D.Matches(it, nil))
  assert(D.Matches(it, "ЛЬНЯН") and D.Matches(it, "ткань"))
  assert(not D.Matches(it, "шерсть"))
  assert(not D.Matches(it, "[") and not D.Matches(it, "%") and not D.Matches(it, "."))
  assert(not D.Matches(nil, "ткань") and D.Matches(nil, ""))
end)

test("Cells flattens bags in order with false for empty slots", function()
  local a, b = { link = "a" }, { link = "b" }
  local cells, n = D.Cells({ time = 1, bags = {
    { id = 6, size = 3, slots = { [2] = a } },
    { id = 8, size = 2, slots = { [1] = b } },
  } })
  assert(n == 5 and #cells == 5)
  assert(cells[1] == false and cells[2] == a and cells[3] == false and cells[4] == b and cells[5] == false)
  local none, zero = D.Cells(nil)
  assert(#none == 0 and zero == 0)
end)

test("Columns matches ElvUI floor(width / (size + spacing)), at least 1", function()
  assert(D.Columns(640, 34, 5) == 16)
  assert(D.Columns(10, 34, 5) == 1)
end)

print(passed .. " passed, " .. failed .. " failed")
if failed > 0 then error("tests failed") end
