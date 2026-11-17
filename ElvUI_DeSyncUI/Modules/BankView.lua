local ADDON, ns = ...
local mod = ns.NewModule("BankView", {
  title = "Банк в сумке",
  desc = "Кнопка с сундуком в сумке ElvUI показывает содержимое банка в любом месте. "
      .. "Банк запоминается при каждом визите к банкиру.",
  defaults = { chars = {} },
})

local say = ns.say
local D = ns.BankData
local ICON = "Interface\\ICONS\\INV_Box_02"

local DB, B, bankIDs
local bankOpen, pending, reported = false, false, false

local function hasItems(s)
  for _, bag in ipairs(s.bags) do
    if next(bag.slots) then return true end
  end
end

-- the bank can only be read while it is open: remember it then.
-- requireItems: at closing time the client may already report slots without items; never wipe the snapshot then
local function save(requireItems)
  local s = D.ReadBank(bankIDs)
  if not s or (requireItems and not hasItems(s)) then return end
  local key = D.CharKey()
  D.Save(DB, key, s)
  if ns.BankWindow then ns.BankWindow.Refresh(key) end
end

-- moving items fires many BAG_UPDATEs: save once they settle
local function schedule()
  if pending then return end
  pending = true
  C_Timer.After(0.5, function()
    if not pending then return end  -- BANKFRAME_CLOSED already saved it
    pending = false
    if bankOpen then save() end
  end)
end

local function onEvent(_, event)
  if event == "BANKFRAME_OPENED" then
    bankOpen = true
    schedule()
  elseif event == "BANKFRAME_CLOSED" then
    if pending then
      pending = false
      save(true)
    end
    bankOpen = false
  elseif bankOpen then  -- BAG_UPDATE / PLAYERBANKSLOTS_CHANGED
    schedule()
  end
end

local function showTooltip(self)
  if GameTooltip:IsForbidden() then return end
  GameTooltip:SetOwner(self)
  GameTooltip:ClearLines()
  GameTooltip:AddLine("Банк")
  local s = D.Get(DB, D.CharKey())
  GameTooltip:AddLine(s and ("Снимок: " .. D.FormatTime(s.time)) or "Банк ещё не запомнен: откройте его у банкира", 1, 1, 1)
  GameTooltip:Show()
end

local function onClick()
  if ns.BankWindow then
    ns.BankWindow.Toggle()
    return
  end
  local s = D.Get(DB, D.CharKey())
  say(s and ("банк: снимок от " .. D.FormatTime(s.time)) or "банк ещё не запомнен: откройте его у банкира")
end

-- the bag frame is built by ElvUI at login, possibly after us: retry for a few seconds
local function attach(tries)
  local f = B.BagFrame
  if not (f and f.vendorGraysButton and f.editBox) then
    if tries < 10 then
      C_Timer.After(1, function() attach(tries + 1) end)
    else
      say("BankView: окно сумок ElvUI не найдено")
    end
    return
  end
  if f.dstBankButton then return end

  local btn = CreateFrame("Button", "ElvUI_ContainerFrameDSTBankButton", f)
  btn:Size(20)
  btn:SetTemplate()
  B:SetButtonTexture(btn, ICON)
  btn:StyleButton(nil, true)
  btn:SetScript("OnEnter", showTooltip)
  btn:SetScript("OnLeave", GameTooltip_Hide)
  btn:SetScript("OnClick", onClick)
  -- relative anchors: the button follows "Vendor Grays" when B:PositionButtons moves it
  btn:Point("RIGHT", f.vendorGraysButton, "LEFT", -5, 0)
  f.editBox:Point("RIGHT", btn, "LEFT", -5, 0)
  f.dstBankButton = btn

  if ns.BankWindow then ns.BankWindow.Init(DB, B) end
end

function mod.OnEnable(db)
  DB = db
  local E = ElvUI and ElvUI[1]
  B = E and E:GetModule("Bags", true)
  if not (B and E.private and E.private.bags and E.private.bags.enable) then
    say("BankView: сумки ElvUI выключены, модуль не запущен")
    return
  end
  bankIDs = D.BankBagIDs()

  local f = CreateFrame("Frame")
  for _, e in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "BAG_UPDATE", "PLAYERBANKSLOTS_CHANGED" }) do
    pcall(f.RegisterEvent, f, e)
  end
  f:SetScript("OnEvent", function(...)
    local ok, err = pcall(onEvent, ...)
    if not ok and not reported then
      reported = true
      say("BankView: ошибка: " .. tostring(err))
    end
  end)

  attach(0)
end
