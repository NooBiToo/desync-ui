-- Headless specs for ElvUI_DeSyncUI/Modules/QuestieTipFix.lua.
-- Reproduces the in-game log: ElvUI blanks a line in a mob tooltip, Questie's CountTooltip stops at the first
-- empty line, so on every rebuild of the same mob Questie thinks its rows are already there and skips them.
local passed, failed = 0, 0
local mod, scripts, lines, QT

-- Questie's unit post-call, reduced to its dedupe rule (Questie/Modules/Tooltips/TooltipHandler.lua:18-62, 187-199)
local function countTooltip()
  local n = 0
  for _, t in ipairs(lines) do
    if t ~= "" then n = n + 1 else return n end
  end
  return n
end
local function questiePostCall(name)
  if name ~= QT.lastGametooltipUnit or not QT.lastGametooltipCount or countTooltip() < QT.lastGametooltipCount then
    QT.lastGametooltipUnit = name
    lines[#lines + 1] = "Воинство зла: 3/8"
    QT.lastGametooltipCount = countTooltip()
  end
end
local function questieOnShow() QT.lastGametooltipUnit, QT.lastGametooltipCount = nil, 0 end

-- one tooltip rebuild of a mob, as the game and ElvUI produce it (line 3 blanked by ElvUI)
local function rebuild(name)
  if scripts.OnTooltipCleared then for _, fn in ipairs(scripts.OnTooltipCleared) do fn(GameTooltip) end end
  lines = { name, "35 Гуманоид", "", "79% уровень угрозы", "ID: 2253" }
  questiePostCall(name)
end
local function hasQuestRow()
  for _, t in ipairs(lines) do if t:find("Воинство зла", 1, true) then return true end end
end

local function setup(withFix)
  scripts, lines = {}, {}
  QT = { lastGametooltipCount = 0 }
  QuestieLoader = { ImportModule = function(_, n) if n == "QuestieTooltips" then return QT end end }
  GameTooltip = {
    IsForbidden = function() return false end,
    HookScript = function(_, k, fn) scripts[k] = scripts[k] or {}; table.insert(scripts[k], fn) end,
  }
  local ns = { say = function() end }
  ns.NewModule = function(name, def) def.name = name; mod = def; return def end
  assert(loadfile(ROOT .. "/ElvUI_DeSyncUI/Modules/QuestieTipFix.lua"))("ElvUI_DeSyncUI", ns)
  if withFix then mod.OnEnable({}) end
end

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then passed = passed + 1; print("PASS " .. name)
  else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end

test("without the fix the quest row vanishes on the second rebuild (the bug, as logged in game)", function()
  setup(false)
  rebuild("Громила"); questieOnShow()
  rebuild("Громила"); assert(hasQuestRow())
  rebuild("Громила"); assert(not hasQuestRow())
end)

test("with the fix the quest row stays on every rebuild of the same mob", function()
  setup(true)
  rebuild("Громила"); questieOnShow()
  for _ = 1, 5 do
    rebuild("Громила")
    assert(hasQuestRow())
  end
end)

test("with the fix the quest row is never doubled within one build", function()
  setup(true)
  rebuild("Громила")
  questiePostCall("Громила")  -- a second post-call without a clear must not add it again
  local n = 0
  for _, t in ipairs(lines) do if t:find("Воинство зла", 1, true) then n = n + 1 end end
  assert(n == 1)
end)

test("without Questie the module does nothing and does not fail", function()
  QuestieLoader = nil
  scripts = {}
  GameTooltip = { HookScript = function(_, k, fn) scripts[k] = fn end, IsForbidden = function() return false end }
  local ns = { say = function() end }
  ns.NewModule = function(name, def) def.name = name; mod = def; return def end
  assert(loadfile(ROOT .. "/ElvUI_DeSyncUI/Modules/QuestieTipFix.lua"))("ElvUI_DeSyncUI", ns)
  mod.OnEnable({})
  assert(next(scripts) == nil)
end)

print(passed .. " passed, " .. failed .. " failed")
if failed > 0 then error("tests failed") end
