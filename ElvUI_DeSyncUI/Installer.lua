local ADDON, ns = ...
-- The DeSync UI install window (ElvUI's PluginInstaller): puts the author's look (ns.Snapshot, Profile.lua)
-- into an ElvUI profile "DeSync UI". Per character: shown once per snapshot version, or on /desync install.
local I = {}
ns.Installer = I

local PROFILE = "DeSync UI"
local mode     -- "install" | "update" | "reinstall" while the window is open
local applied  -- the player pressed Apply / Update in this window

local function say(s) if ns.say then ns.say(s) end end

function I.CharKey()
  return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

-- per character: installed (got private settings) and the last version it skipped or finished;
-- per account: db.profileVersion = snapshot version in the shared "DeSync UI" profile
function I.NeedsInstall(db, charKey, version)
  local rec = db.install and db.install[charKey]
  if not rec then return "install" end
  if rec.skipped and (rec.version or 0) >= version then return nil end
  if not rec.installed then return "install" end
  if (db.profileVersion or 0) < version then return "update" end
end

function I.MarkDone(db, charKey, version, skipped)
  db.install = db.install or {}
  local rec = db.install[charKey] or {}
  rec.version = version
  if skipped then
    rec.skipped = true
  else
    rec.skipped, rec.installed = nil, true
  end
  db.install[charKey] = rec
end

-- the shared profile exists and already carries this snapshot: an alt just switches to it
local function profileCurrent(db, version)
  return ElvDB and ElvDB.profiles and ElvDB.profiles[PROFILE] ~= nil and (db.profileVersion or 0) >= version
end

-- an alt reuses the existing profile (keeps the player's tweaks); force overwrites it from the snapshot
function I.ApplyProfile(E, D, snap, force)
  if ElvDB and ElvDB.profiles and ElvDB.profiles[PROFILE] and not force then
    E.data:SetProfile(PROFILE)
  else
    D:SetImportedProfile("profile", PROFILE, E:CopyTable({}, snap.profile), true)
  end
end

function I.ApplyPrivate(E, snap)
  E:CopyTable(E.private, E:CopyTable({}, snap.private))
end

-- ElvUI's own global import skips UIScale (Distributor blacklist), so it is set directly.
-- The scale is account-wide: only on install, an update leaves the player's scale alone.
function I.ApplyGlobal(E, snap, withScale)
  local g = snap.global or {}
  if withScale and g.general and g.general.UIScale then
    E.global.general = E.global.general or {}
    E.global.general.UIScale = g.general.UIScale
  end
  if g.datatexts then E.global.datatexts = E:CopyTable(E.global.datatexts, g.datatexts) end
  if g.WT then E.global.WT = E:CopyTable(E.global.WT, g.WT) end
end

local function elv()
  local E = ElvUI and ElvUI[1]
  return E, E and E:GetModule("Distributor"), E and E:GetModule("PluginInstaller")
end

local function show(f, n, text, onClick)
  local b = f["Option" .. n]
  b:Show()
  b:SetText(text)
  b:SetScript("OnClick", onClick)
end

local pages = {}

pages[1] = function()
  local f, E, _, PI = PluginInstallFrame, elv()
  f.SubTitle:SetText("Добро пожаловать в DeSync UI")
  f.Desc1:SetText("Сборка ставит вид ElvUI (вместе с WindTools и mMediaTag) и модули DeSync.")
  f.Desc2:SetText(mode == "update" and "Вышла новая версия вида DeSync UI." or "Это займёт пару кликов.")
  f.Desc3:SetText("Запустить установку позже: /desync install")
  show(f, 1, mode == "update" and "Дальше" or "Установить", function() f.Next:Click() end)
  show(f, 2, "Пропустить", function()
    I.MarkDone(ns.DB, I.CharKey(), ns.Snapshot.version, true)
    PI:CloseInstall()
  end)
end

local WIPES = "Ваши правки профиля ElvUI «DeSync UI» пропадут (на всех персонажах)."

pages[2] = function()
  local f, E, D = PluginInstallFrame, elv()
  local snap, db = ns.Snapshot, ns.DB
  local function done(force, private, scale)
    I.ApplyProfile(E, D, snap, force)
    if private then I.ApplyPrivate(E, snap) end
    I.ApplyGlobal(E, snap, scale)
    db.profileVersion = snap.version
    applied = true
  end
  f.SubTitle:SetText("Вид ElvUI")
  if mode == "update" then
    f.Desc1:SetText("Вышла новая версия вида DeSync UI.")
    f.Desc2:SetText(WIPES)
    f.Desc3:SetText("Личные настройки персонажа и масштаб интерфейса не меняются.")
    show(f, 1, "Обновить вид", function()
      done(true, false, false)
      say("вид обновлён, перезагрузите интерфейс на последнем шаге")
    end)
    return
  end
  local overwrite = mode == "reinstall" or not profileCurrent(db, snap.version)
  local exists = ElvDB and ElvDB.profiles and ElvDB.profiles[PROFILE] ~= nil
  f.Desc1:SetText(exists and (overwrite and "Профиль ElvUI «DeSync UI» будет записан заново из сборки."
                                          or "Будет включён профиль ElvUI «DeSync UI».")
                         or "Будет создан профиль ElvUI «DeSync UI».")
  f.Desc2:SetText(exists and overwrite and WIPES or "Другие ваши профили ElvUI не трогаются.")
  f.Desc3:SetText("Личные настройки ElvUI этого персонажа и масштаб интерфейса (для всех персонажей) будут заменены.")
  show(f, 1, "Применить", function()
    done(overwrite, true, true)
    say("вид применён, перезагрузите интерфейс на последнем шаге")
  end)
end

pages[3] = function()
  local f = PluginInstallFrame
  f.SubTitle:SetText("Модули DeSync")
  f.Desc1:SetText("Уже включены: банк в сумке, «кто кого бьёт» на индикаторах, прогресс Questie в подсказках, "
    .. "кто что выбрал в розыгрыше.")
  f.Desc2:SetText("По желанию: «Жезл не мешает заклинаниям» и «Кнопки у миникарты».")
  f.Desc3:SetText("Все модули включаются и настраиваются в /ec → DeSync UI.")
end

pages[4] = function()
  local f = PluginInstallFrame
  f.SubTitle:SetText("Готово")
  f.Desc1:SetText("Чтобы всё применилось, перезагрузите интерфейс.")
  f.Desc2:SetText("")
  f.Desc3:SetText("")
  show(f, 1, "Перезагрузить интерфейс", function()
    -- reaching the end without Apply is a skip: nothing was installed
    I.MarkDone(ns.DB, I.CharKey(), ns.Snapshot.version, not applied)
    ReloadUI()
  end)
end

function I.Open(forceMode)
  local E, _, PI = elv()
  if not (E and PI and ns.Snapshot) then
    say("установка недоступна: нет ElvUI или снимка настроек")
    return
  end
  mode = forceMode or I.NeedsInstall(ns.DB, I.CharKey(), ns.Snapshot.version) or "reinstall"
  applied = false
  PI:Queue({
    Title = "Установка DeSync UI",
    Name = "DeSync UI",
    tutorialImage = "Interface\\AddOns\\ElvUI_DeSyncUI\\Media\\Logo",
    tutorialImageSize = { 128, 128 },
    Pages = pages,
    StepTitles = { "Добро пожаловать", "Вид ElvUI", "Модули DeSync", "Готово" },
    StepTitleWidth = 200,
    StepTitleButtonWidth = 180,
  })
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
  -- a second later: after ElvUI's own first-run window has been queued
  C_Timer.After(1, function()
    if ns.Snapshot and I.NeedsInstall(ns.DB, I.CharKey(), ns.Snapshot.version) then I.Open() end
  end)
end)

SLASH_DESYNCUI1 = "/desync"
SlashCmdList.DESYNCUI = function(msg)
  if msg == "install" then
    I.Open()
  else
    say("/desync install — окно установки DeSync UI")
  end
end
