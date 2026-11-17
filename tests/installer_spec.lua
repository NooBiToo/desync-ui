-- Headless specs for ElvUI_DeSyncUI/Installer.lua: when the install window shows and what it applies.
local passed, failed = 0, 0
local I, E, D, db, snap, charKey, loginFrame
local imported, switchedTo, queued, closed, reloaded

-- ElvUI's E:CopyTable(current, default): deep-copies default into current
local function copyTable(_, current, default)
  if type(current) ~= "table" then current = {} end
  for k, v in pairs(default or {}) do
    current[k] = type(v) == "table" and copyTable(nil, current[k], v) or v
  end
  return current
end

local function fs() return { SetText = function(self, t) self.text = t end } end
local function button()
  return {
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    SetText = function(self, t) self.text = t end,
    SetScript = function(self, _, fn) self.click = fn end,
    Click = function(self) if self.click then self.click() end end,
  }
end

local function setup()
  imported, switchedTo, queued, closed, reloaded = nil, nil, nil, false, false
  snap = {
    version = 1,
    profile = { general = { font = "PT Sans Narrow" } },
    private = { general = { dmgfont = "PT Sans Narrow" } },
    global = { general = { UIScale = 0.8 }, datatexts = { customPanels = { ["minimap-top"] = { x = 1 } } } },
  }
  db = {}
  ElvDB = { profiles = {} }
  D = { SetImportedProfile = function(_, kind, key, data, force) imported = { kind = kind, key = key, data = data, force = force } end }
  local PI = {
    Queue = function(_, data) queued = data end,
    CloseInstall = function() closed = true end,
  }
  E = {
    data = { SetProfile = function(_, name) switchedTo = name end },
    CopyTable = copyTable,
    private = {},
    global = { general = {} },
    GetModule = function(_, n)
      if n == "Distributor" then return D end
      if n == "PluginInstaller" then return PI end
    end,
  }
  ElvUI = { E }
  PluginInstallFrame = { SubTitle = fs(), Desc1 = fs(), Desc2 = fs(), Desc3 = fs(), Desc4 = fs(),
                         Option1 = button(), Option2 = button(), Option3 = button(), Option4 = button(), Next = button() }
  ReloadUI = function() reloaded = true end
  UnitName = function() return "Игрок" end
  GetRealmName = function() return "Сервер" end
  charKey = "Игрок-Сервер"
  C_Timer = { After = function(_, fn) fn() end }
  SlashCmdList = {}
  CreateFrame = function()
    local f = { scripts = {} }
    function f:RegisterEvent() loginFrame = self end
    function f:SetScript(k, fn) self.scripts[k] = fn end
    return f
  end
  local ns = { DB = db, Snapshot = snap, say = function() end }
  assert(loadfile(ROOT .. "/ElvUI_DeSyncUI/Installer.lua"))("ElvUI_DeSyncUI", ns)
  I = ns.Installer
end

local function fireLogin() loginFrame.scripts.OnEvent(loginFrame, "PLAYER_LOGIN") end
local function opt(n) return PluginInstallFrame["Option" .. n] end

local function test(name, fn)
  local ok, err = pcall(function() setup() fn() end)
  if ok then passed = passed + 1; print("PASS " .. name)
  else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end

test("NeedsInstall: new character, up to date, new version once per account, skipped", function()
  local d = { profileVersion = 1, install = { ["A-R"] = { version = 1, installed = true } } }
  assert(I.NeedsInstall(d, "B-R", 1) == "install")
  assert(I.NeedsInstall(d, "A-R", 1) == nil)
  assert(I.NeedsInstall(d, "A-R", 2) == "update")
  d.profileVersion = 2  -- another character already updated the shared profile
  assert(I.NeedsInstall(d, "A-R", 2) == nil)
  I.MarkDone(d, "B-R", 1, true)
  assert(I.NeedsInstall(d, "B-R", 1) == nil)        -- skipped this version
  assert(I.NeedsInstall(d, "B-R", 2) == "install")  -- a skipped character gets the full install later
end)

test("first character creates the DeSync UI profile from the snapshot", function()
  I.ApplyProfile(E, D, snap, false)
  assert(imported.kind == "profile" and imported.key == "DeSync UI" and imported.force == true)
  assert(imported.data ~= snap.profile and imported.data.general.font == "PT Sans Narrow")
end)

test("an alt switches to the existing profile without overwriting it", function()
  ElvDB.profiles["DeSync UI"] = { tweaked = true }
  I.ApplyProfile(E, D, snap, false)
  assert(imported == nil and switchedTo == "DeSync UI" and ElvDB.profiles["DeSync UI"].tweaked)
end)

test("an update overwrites the profile when forced", function()
  ElvDB.profiles["DeSync UI"] = { tweaked = true }
  I.ApplyProfile(E, D, snap, true)
  assert(imported and imported.force == true)
end)

test("private and global are applied; UIScale set directly on install", function()
  I.ApplyPrivate(E, snap)
  I.ApplyGlobal(E, snap, true)
  assert(E.private.general.dmgfont == "PT Sans Narrow" and E.global.general.UIScale == 0.8)
  assert(E.global.datatexts.customPanels["minimap-top"].x == 1)
  assert(E.private.general ~= snap.private.general)  -- a copy, the snapshot stays untouched
end)

test("an update does not touch the account-wide UI scale", function()
  E.global.general.UIScale = 1
  I.ApplyGlobal(E, snap, false)
  assert(E.global.general.UIScale == 1)
end)

test("login queues the installer once for a new character; skip remembers it", function()
  fireLogin()
  assert(queued and queued.Name == "DeSync UI" and #queued.Pages == 4 and #queued.StepTitles == 4)
  assert(queued.tutorialImage == "Interface\\AddOns\\ElvUI_DeSyncUI\\Media\\Logo")
  queued.Pages[1]()
  opt(2):Click()  -- «Пропустить»
  assert(db.install[charKey].skipped == true and closed)
  queued = nil
  fireLogin()
  assert(queued == nil)
end)

test("install path: apply sets profile, private and global; the last page marks installed and reloads", function()
  fireLogin()
  queued.Pages[2]()
  opt(1):Click()  -- «Применить»
  assert(imported and imported.key == "DeSync UI" and E.private.general.dmgfont and E.global.general.UIScale == 0.8)
  queued.Pages[4]()
  opt(1):Click()  -- «Перезагрузить интерфейс»
  assert(reloaded and db.install[charKey].installed and not db.install[charKey].skipped and db.profileVersion == 1)
end)

test("clicking through to the end without Apply counts as a skip, not an install", function()
  fireLogin()
  queued.Pages[4]()
  opt(1):Click()
  assert(reloaded and db.install[charKey].skipped == true and not db.install[charKey].installed)
end)

test("the update page applies the profile but leaves private and the scale alone", function()
  db.install = { [charKey] = { version = 0, installed = true } }
  db.profileVersion = 0
  E.global.general.UIScale = 1
  fireLogin()
  queued.Pages[2]()
  opt(1):Click()  -- «Обновить вид»
  assert(imported and imported.force == true and E.private.general == nil)
  assert(E.global.general.UIScale == 1 and db.profileVersion == 1)
end)

test("an alt installing onto an older shared profile is warned and overwrites it", function()
  ElvDB.profiles["DeSync UI"] = { tweaked = true }
  db.profileVersion = 0
  fireLogin()
  queued.Pages[2]()
  assert(PluginInstallFrame.Desc2.text:find("пропадут", 1, true))
  opt(1):Click()
  assert(imported and imported.force == true)
end)

test("an alt installing onto an up-to-date shared profile only switches to it", function()
  ElvDB.profiles["DeSync UI"] = { tweaked = true }
  db.profileVersion = 1
  fireLogin()
  queued.Pages[2]()
  opt(1):Click()
  assert(imported == nil and switchedTo == "DeSync UI" and E.private.general.dmgfont)
end)

test("/desync install on an installed character warns before overwriting the shared profile", function()
  db.install = { [charKey] = { version = 1, installed = true } }
  db.profileVersion = 1
  ElvDB.profiles["DeSync UI"] = { tweaked = true }
  fireLogin()
  assert(queued == nil)
  SlashCmdList.DESYNCUI("install")
  assert(queued and queued.Name == "DeSync UI")
  queued.Pages[2]()
  assert(PluginInstallFrame.Desc2.text:find("пропадут", 1, true))
  opt(1):Click()
  assert(imported and imported.force == true)
end)

print(passed .. " passed, " .. failed .. " failed")
if failed > 0 then error("tests failed") end
