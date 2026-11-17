-- Headless smoke/behaviour specs for ElvUI_DeSyncUI/Modules/BankWindow.lua (Lua 5.1).
-- Frames are universal stubs: unknown API methods are no-ops; scripts, shown state, text and alpha are recorded.
local passed, failed = 0, 0
local W, B, db, f, clicked
local OWN = "Desync-Realm"

local function obj(name)
  local o = { scripts = {}, shown = true, alpha = 1, name = name }
  local methods = {
    SetScript = function(self, k, fn) self.scripts[k] = fn end,
    HookScript = function(self, k, fn)
      local old = self.scripts[k]
      self.scripts[k] = function(...) if old then old(...) end fn(...) end
    end,
    Show = function(self) self.shown = true end,
    Hide = function(self)
      if self.shown then
        self.shown = false
        if self.scripts.OnHide then self.scripts.OnHide(self) end
      end
    end,
    IsShown = function(self) return self.shown end,
    SetShown = function(self, v) if v then self:Show() else self:Hide() end end,
    SetText = function(self, t)
      self.text = t
      if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, true) end
    end,
    GetText = function(self) return self.text end,
    SetAlpha = function(self, a) self.alpha = a end,
    SetClampedToScreen = function(self, v) self.clamped = v end,
    CreateTexture = function() return obj() end,
    CreateFontString = function() return obj() end,
    IsForbidden = function() return false end,
  }
  -- like a real widget: capitalized names are API methods (no-op here), plain fields are nil until set
  return setmetatable(o, { __index = function(_, k)
    if methods[k] then return methods[k] end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end

local function item(id, name, count)
  return { link = "|cffffffff|Hitem:" .. id .. "|h[" .. name .. "]|h|r", count = count or 1, icon = id, quality = 1 }
end

local function snap(...) return { time = 1000, bags = { ... } } end

local function setup()
  time = function() return 1000 end
  date = os.date
  UnitName = function() return "Desync" end
  GetRealmName = function() return "Realm" end
  CreateFrame = function(_, name, _, template)
    local o = obj(name)
    if name then _G[name] = o end
    if template == "SearchBoxTemplate" then o.Left, o.Middle, o.Right = obj(), obj(), obj() end
    return o
  end
  UIParent, GameTooltip = obj(), obj()
  UISpecialFrames = {}
  GameTooltip_Hide = function() end
  clicked = nil
  HandleModifiedItemClick = function(link) clicked = link end
  MenuUtil = nil
  ElvUI = { {
    media = { bordercolor = { 0, 0, 0 } }, TexCoords = { 0, 1, 0, 1 },
    Scale = function(_, v) return v end,
    GetItemQualityColor = function() return 1, 1, 1 end,
    GetModule = function() return nil end,
  } }
  B = { db = { bankSize = 34, bankButtonSpacing = 5, bankWidth = 200, qualityColors = true }, BagFrame = obj() }

  local ns = {}
  assert(loadfile(ROOT .. "/ElvUI_DeSyncUI/Modules/BankData.lua"))("ElvUI_DeSyncUI", ns)
  assert(loadfile(ROOT .. "/ElvUI_DeSyncUI/Modules/BankWindow.lua"))("ElvUI_DeSyncUI", ns)
  W = ns.BankWindow
  db = { chars = {} }
  W.Init(db, B)
  f = _G.DeSyncBankViewFrame
end

local function shownCells()
  local n = 0
  for _, c in ipairs(f.cells) do if c.shown then n = n + 1 end end
  return n
end

local function test(name, fn)
  local ok, err = pcall(function() setup() fn() end)
  if ok then passed = passed + 1; print("PASS " .. name)
  else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end

test("Toggle shows the own bank with one cell per slot", function()
  db.chars[OWN] = snap({ id = 6, size = 3, slots = { [2] = item(1, "Old") } }, { id = 7, size = 2, slots = {} })
  assert(not f.shown)
  W.Toggle()
  assert(f.shown and shownCells() == 5)
  assert(f.title.text:find(OWN, 1, true))
  assert(f.grid.shown and not f.empty.shown)
  assert(UISpecialFrames[1] == "DeSyncBankViewFrame")
  W.Toggle()
  assert(not f.shown)
end)

test("a smaller bank after a new snapshot hides leftover cells", function()
  db.chars[OWN] = snap({ id = 6, size = 5, slots = {} })
  W.Toggle()
  db.chars[OWN] = snap({ id = 6, size = 2, slots = {} })
  W.Refresh(OWN)
  assert(shownCells() == 2)
end)

test("no snapshot shows the empty text", function()
  W.Toggle()
  assert(f.shown and f.empty.shown and not f.grid.shown)
end)

test("viewing an alt survives a refresh of the own bank; reopening returns to own", function()
  db.chars[OWN] = snap({ id = 6, size = 1, slots = {} })
  db.chars["Alt-Realm"] = snap({ id = 6, size = 1, slots = {} })
  W.Toggle()
  assert(f.charButton.shown)
  f.charButton.scripts.OnClick(f.charButton)  -- no MenuUtil: cycles to the next character
  assert(f.title.text:find("Alt-Realm", 1, true))
  W.Refresh(OWN)
  assert(f.title.text:find("Alt-Realm", 1, true))
  W.Toggle(); W.Toggle()
  assert(f.title.text:find(OWN, 1, true))
end)

test("character switch is hidden with a single saved bank", function()
  db.chars[OWN] = snap({ id = 6, size = 1, slots = {} })
  W.Toggle()
  assert(not f.charButton.shown)
end)

test("an alt with no saved bank can still switch to another character's bank", function()
  db.chars["Main-Realm"] = snap({ id = 6, size = 2, slots = {} })
  W.Toggle()
  assert(f.empty.shown and f.charButton.shown)
  f.charButton.scripts.OnClick(f.charButton)
  assert(f.title.text:find("Main-Realm", 1, true) and f.grid.shown and shownCells() == 2)
end)

test("the window is kept on screen", function()
  assert(f.clamped == true)
end)

test("search dims cells that do not match, case-insensitive Cyrillic", function()
  db.chars[OWN] = snap({ id = 6, size = 3, slots = { [1] = item(2589, "Льняная ткань", 5), [2] = item(2592, "Шерсть") } })
  W.Toggle()
  f.search:SetText("ТКАН")
  assert(f.cells[1].alpha == 1 and f.cells[2].alpha < 1 and f.cells[3].alpha < 1)
  f.search:SetText("")
  assert(f.cells[1].alpha == 1 and f.cells[2].alpha == 1 and f.cells[3].alpha == 1)
end)

test("Shift-click hands the item link to the game", function()
  local it = item(2589, "Льняная ткань")
  db.chars[OWN] = snap({ id = 6, size = 1, slots = { [1] = it } })
  W.Toggle()
  f.cells[1].scripts.OnClick(f.cells[1])
  assert(clicked == it.link)
end)

test("closing the bags closes the window", function()
  db.chars[OWN] = snap({ id = 6, size = 1, slots = {} })
  W.Toggle()
  B.BagFrame:Hide()
  assert(not f.shown)
end)

print(passed .. " passed, " .. failed .. " failed")
if failed > 0 then error("tests failed") end
