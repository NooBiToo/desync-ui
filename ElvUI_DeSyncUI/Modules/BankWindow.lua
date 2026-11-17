local ADDON, ns = ...
-- Read-only window with a remembered bank. Built in Init (called by BankView once the ElvUI bag frame exists).
local D = ns.BankData
local W = {}
ns.BankWindow = W

local PAD, HEADER, SEARCH_H = 8, 24, 19
local EMPTY_TEXT = "Банк ещё не запомнен. Откройте его у банкира один раз."

local E, B, DB, frame
local viewKey

local function borderColor(quality)
  if quality and quality > 1 and B.db.qualityColors then return E:GetItemQualityColor(quality) end
  return unpack(E.media.bordercolor)
end

local function paintSearch()
  if not frame then return end
  local q = frame.search:GetText()
  for i = 1, frame.numCells do
    local c = frame.cells[i]
    local hit = D.Matches(c.item, q)
    c.icon:SetDesaturated(not hit)
    c:SetAlpha(hit and 1 or 0.3)
  end
end

local function cellEnter(self)
  if not self.item or GameTooltip:IsForbidden() then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetHyperlink(self.item.link)
  GameTooltip:Show()
end

local function cellClick(self)
  if self.item then HandleModifiedItemClick(self.item.link) end
end

local function newCell(i)
  local c = CreateFrame("Button", nil, frame.grid)
  c:SetTemplate()
  c.icon = c:CreateTexture(nil, "ARTWORK")
  c.icon:SetInside()
  c.icon:SetTexCoord(unpack(E.TexCoords))
  c.count = c:CreateFontString(nil, "OVERLAY")
  c.count:FontTemplate()
  c.count:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -1, 3)
  c:SetScript("OnEnter", cellEnter)
  c:SetScript("OnLeave", GameTooltip_Hide)
  c:SetScript("OnClick", cellClick)
  frame.cells[i] = c
  return c
end

local function render()
  local snap = D.Get(DB, viewKey)
  local cells, n = D.Cells(snap)
  local size, sp = E:Scale(B.db.bankSize), E:Scale(B.db.bankButtonSpacing)
  local cols = D.Columns(B.db.bankWidth, size, sp)
  local rows = math.max(1, math.ceil(n / cols))
  local gridW = cols * (size + sp) - sp
  local gridH = snap and (rows * (size + sp) - sp) or 40

  for i = 1, n do
    local c = frame.cells[i] or newCell(i)
    local it = cells[i] or nil
    c.item = it
    c:SetSize(size, size)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", frame.grid, "TOPLEFT", ((i - 1) % cols) * (size + sp), -math.floor((i - 1) / cols) * (size + sp))
    c.icon:SetTexture(it and it.icon or nil)
    c.count:SetText(it and it.count and it.count > 1 and it.count or "")
    c:SetBackdropBorderColor(borderColor(it and it.quality))
    c:Show()
  end
  -- the bank may have shrunk since the last render
  for i = n + 1, #frame.cells do
    frame.cells[i].item = nil
    frame.cells[i]:Hide()
  end
  frame.numCells = n

  frame.grid:SetSize(gridW, gridH)
  frame.grid:SetShown(snap ~= nil)
  frame.empty:SetShown(snap == nil)
  frame.title:SetText("Банк: " .. viewKey .. (snap and (" — снимок " .. D.FormatTime(snap.time)) or ""))
  -- shown whenever there is a bank other than the one on screen (an alt without its own snapshot needs it too)
  local chars = D.Chars(DB)
  frame.charButton:SetShown(#chars > 1 or (#chars == 1 and chars[1] ~= viewKey))
  frame:SetSize(gridW + PAD * 2, PAD + HEADER + SEARCH_H + PAD + gridH + PAD)
  paintSearch()
end

local function pick(key)
  viewKey = key
  render()
end

local function chooseChar(self)
  local chars = D.Chars(DB)
  if MenuUtil and MenuUtil.CreateContextMenu then
    MenuUtil.CreateContextMenu(self, function(_, root)
      for _, key in ipairs(chars) do
        root:CreateRadio(key, function() return key == viewKey end, function() pick(key) end)
      end
    end)
    return
  end
  local nextKey = chars[1]
  for i, key in ipairs(chars) do
    if key == viewKey then nextKey = chars[i % #chars + 1] end
  end
  pick(nextKey)
end

local function charTooltip(self)
  if GameTooltip:IsForbidden() then return end
  GameTooltip:SetOwner(self)
  GameTooltip:ClearLines()
  GameTooltip:AddLine("Банк другого персонажа")
  GameTooltip:Show()
end

function W.Init(db, bags)
  if frame then return end
  DB, B = db, bags
  E = ElvUI[1]

  frame = CreateFrame("Frame", "DeSyncBankViewFrame", UIParent)
  frame:SetTemplate("Transparent")
  frame:SetFrameStrata(B.BagFrame:GetFrameStrata())
  frame:SetToplevel(true)
  frame:EnableMouse(true)
  frame:SetClampedToScreen(true)  -- bags moved to the left edge would push it off screen
  frame:SetPoint("BOTTOMRIGHT", B.BagFrame, "BOTTOMLEFT", -5, 0)
  frame:Hide()
  frame.cells, frame.numCells = {}, 0
  table.insert(UISpecialFrames, "DeSyncBankViewFrame")  -- Esc closes it
  B.BagFrame:HookScript("OnHide", function() frame:Hide() end)

  frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
  local S = E:GetModule("Skins", true)
  if S and S.HandleCloseButton then pcall(S.HandleCloseButton, S, frame.close) end

  frame.charButton = CreateFrame("Button", nil, frame)
  frame.charButton:SetTemplate()
  frame.charButton:SetSize(70, 18)
  frame.charButton:SetPoint("RIGHT", frame.close, "LEFT", -2, 0)
  frame.charButton.text = frame.charButton:CreateFontString(nil, "OVERLAY")
  frame.charButton.text:FontTemplate()
  frame.charButton.text:SetPoint("CENTER")
  frame.charButton.text:SetText("Персонаж")
  frame.charButton:SetScript("OnClick", chooseChar)
  frame.charButton:SetScript("OnEnter", charTooltip)
  frame.charButton:SetScript("OnLeave", GameTooltip_Hide)

  frame.title = frame:CreateFontString(nil, "OVERLAY")
  frame.title:FontTemplate()
  frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD - 3)
  frame.title:SetPoint("RIGHT", frame.charButton, "LEFT", -5, 0)
  frame.title:SetJustifyH("LEFT")
  frame.title:SetWordWrap(false)

  -- styled like the ElvUI bag search (Bags.lua, ConstructContainerFrame)
  frame.search = CreateFrame("EditBox", "DeSyncBankViewSearch", frame, "SearchBoxTemplate")
  frame.search:CreateBackdrop()
  frame.search:FontTemplate()
  frame.search:SetHeight(SEARCH_H)
  for _, k in ipairs({ "Left", "Middle", "Right" }) do
    if frame.search[k] then frame.search[k]:SetTexture() end
  end
  frame.search:SetAutoFocus(false)
  frame.search:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 2, -(PAD + HEADER))
  frame.search:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(PAD + HEADER))
  frame.search:HookScript("OnTextChanged", paintSearch)
  frame.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

  frame.grid = CreateFrame("Frame", nil, frame)
  frame.grid:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(PAD + HEADER + SEARCH_H + PAD))

  frame.empty = frame:CreateFontString(nil, "OVERLAY")
  frame.empty:FontTemplate()
  frame.empty:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(PAD + HEADER + SEARCH_H + PAD + 10))
  frame.empty:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(PAD + HEADER + SEARCH_H + PAD + 10))
  frame.empty:SetJustifyH("CENTER")
  frame.empty:SetText(EMPTY_TEXT)
end

-- opening always starts on the current character with an empty search
function W.Toggle()
  if not frame then return end
  if frame:IsShown() then
    frame:Hide()
    return
  end
  viewKey = D.CharKey()
  frame.search:SetText("")
  frame.search:ClearFocus()
  render()
  frame:Show()
end

-- a new snapshot for `key`: redraw only if that bank is on screen
function W.Refresh(key)
  if frame and frame:IsShown() and (key == nil or key == viewKey) then render() end
end
