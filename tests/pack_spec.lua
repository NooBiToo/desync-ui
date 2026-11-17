-- Headless specs for the DeSync UI pack as a whole: .toc, public defaults, no MerathilisUI traces,
-- and every module starting with nothing but ElvUI present (no Questie, no LibDBIcon).
local passed, failed = 0, 0
local defs, files

local function read(rel)
  local f = assert(io.open(ROOT .. "/ElvUI_DeSyncUI/" .. rel, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

-- the module files in .toc order
local function tocModules()
  local list = {}
  for line in read("ElvUI_DeSyncUI.toc"):gmatch("[^\r\n]+") do
    local m = line:match("^Modules\\(.+%.lua)$")
    if m then list[#list + 1] = "Modules/" .. m end
  end
  return list
end

-- a frame: unknown API methods are no-ops, fields are nil until set
local function obj()
  local o = { scripts = {} }
  local methods = {
    SetScript = function(self, k, fn) self.scripts[k] = fn end,
    GetChildren = function() end,
    GetName = function() return nil end,
  }
  return setmetatable(o, { __index = function(_, k)
    if methods[k] then return methods[k] end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end

local function stubWorld()
  CreateFrame = function() return obj() end
  UIParent, GameTooltip, Minimap, MinimapBackdrop, MinimapCluster = obj(), obj(), obj(), obj(), obj()
  C_Timer = { After = function() end }
  hooksecurefunc = function() end
  LibStub = function() return nil end
  SlashCmdList = {}
  UnitClass = function() return "Чернокнижник", "WARLOCK" end
  UnitName = function() return "Игрок" end
  GetRealmName = function() return "Сервер" end
  InCombatLockdown = function() return false end
  Enum = { BagIndex = {} }
  C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() end }
  C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() end }
  UnitExists = function() return false end
  IsInGroup = function() return false end
  QuestieLoader = nil
  ElvUI = { {
    private = { bags = { enable = true }, nameplates = { enable = true }, actionbar = { enable = true },
                general = { lootRoll = true } },
    Media = { Textures = { Tank = "t", DPS = "d" } },
    GetModule = function(_, n)
      if n == "ActionBars" then return { handledBars = {}, barDefaults = {}, db = {} } end
      if n == "Misc" then return { RollBars = {} } end
      return {}
    end,
  } }
end

local function setup()
  stubWorld()
  defs, files = {}, { "ElvUI_DeSyncUI.toc", "Core.lua" }
  local ns = { say = function() end }
  ns.NewModule = function(name, def) def.name = name; defs[name] = def; return def end
  for _, f in ipairs(tocModules()) do
    files[#files + 1] = f
    assert(loadfile(ROOT .. "/ElvUI_DeSyncUI/" .. f))("ElvUI_DeSyncUI", ns)
  end
end

local function test(name, fn)
  local ok, err = pcall(function() setup() fn() end)
  if ok then passed = passed + 1; print("PASS " .. name)
  else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end

test("toc declares the pack and its required plugins", function()
  local toc = read("ElvUI_DeSyncUI.toc")
  assert(toc:find("## Title: DeSync UI", 1, true))
  assert(toc:find("## RequiredDeps: ElvUI, ElvUI_WindTools, ElvUI_mMediaTag", 1, true))
  assert(toc:find("## OptionalDeps: Questie, LibDBIcon-1.0", 1, true))
  assert(not toc:find("Merathilis", 1, true))
  -- the pack's own logo, shipped inside the addon (128x128 32-bit TGA)
  assert(toc:find("## IconTexture: Interface\\AddOns\\ElvUI_DeSyncUI\\Media\\Logo", 1, true))
  local tga = assert(io.open(ROOT .. "/ElvUI_DeSyncUI/Media/Logo.tga", "rb")):read(18)
  assert(tga:byte(3) == 2 and tga:byte(17) == 32 and tga:byte(13) + tga:byte(14) * 256 == 128)
end)

test("toc loads the snapshot before Core and it carries version, profile, private and global", function()
  local toc = read("ElvUI_DeSyncUI.toc")
  local p, c = toc:find("\nProfile.lua", 1, true), toc:find("\nCore.lua", 1, true)
  assert(p and c and p < c, "Profile.lua must be listed before Core.lua")
  local ns = {}
  assert(loadfile(ROOT .. "/ElvUI_DeSyncUI/Profile.lua"))("ElvUI_DeSyncUI", ns)
  local s = ns.Snapshot
  assert(type(s.version) == "number" and type(s.profile) == "table" and type(s.private) == "table")
  assert(s.global.general.UIScale)
end)

test("public defaults: WandStop and MinimapTidy off, LootRoll debug off", function()
  assert(defs.WandStop.default == false and defs.MinimapTidy.default == false)
  assert(defs.LootRoll.defaults.debug == false)
  assert(defs.BankView.default ~= false and defs.TargetCount.default ~= false and defs.QuestieTipFix.default ~= false)
end)

test("no MerathilisUI traces in the addon sources", function()
  for _, f in ipairs(files) do
    local s = read(f)
    for _, w in ipairs({ "Merathilis", "keepMerOff", "%.mui", "%[\"mui\"%]" }) do
      assert(not s:find(w), f .. ": " .. w)
    end
  end
end)

test("no slash command collides with mMediaTag's /mmt (mMediaTag is required)", function()
  for _, f in ipairs(files) do
    assert(not read(f):find('"/mmt"', 1, true), f)
  end
end)

test("all modules load and enable with only ElvUI stubs (no Questie, no LibDBIcon)", function()
  for name, def in pairs(defs) do
    if def.OnEnable then
      local ok, err = pcall(def.OnEnable, { chars = {}, exclude = "", names = {}, keep = {}, log = {} })
      assert(ok, name .. ": " .. tostring(err))
    end
  end
end)

print(passed .. " passed, " .. failed .. " failed")
if failed > 0 then error("tests failed") end
