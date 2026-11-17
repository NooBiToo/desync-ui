local ADDON, ns = ...
-- Bank snapshots: reading the bank while it is open, storing per character, searching.
-- Plain Lua on purpose (no WoW helpers like strlower/tinsert): tests/bankdata_spec.lua runs it headless.
local D = {}
ns.BankData = D

-- Forever bank: CharacterBankTab_1..9, tab 1 is the base bank (same list ElvUI uses)
function D.BankBagIDs()
  local idx = Enum and Enum.BagIndex or {}
  local ids = {}
  for i = 1, 9 do ids[i] = idx["CharacterBankTab_" .. i] or (5 + i) end
  return ids
end

-- nil when no bank bag reports slots: the bank is closed, keep the previous snapshot
function D.ReadBank(bagIDs)
  local out = {}
  for _, id in ipairs(bagIDs) do
    local size = C_Container.GetContainerNumSlots(id) or 0
    if size > 0 then
      local slots = {}
      for slot = 1, size do
        local info = C_Container.GetContainerItemInfo(id, slot)
        if info and info.hyperlink then
          slots[slot] = { link = info.hyperlink, count = info.stackCount or 1, icon = info.iconFileID, quality = info.quality }
        end
      end
      out[#out + 1] = { id = id, size = size, slots = slots }
    end
  end
  if #out == 0 then return nil end
  return { time = time(), bags = out }
end

function D.CharKey()
  return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

function D.Save(db, key, snap) db.chars[key] = snap end
function D.Get(db, key) return db.chars[key] end

function D.Chars(db)
  local keys = {}
  for k in pairs(db.chars) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

-- string.lower depends on the C locale (it can mangle UTF-8 bytes) and never folds Cyrillic,
-- so fold Latin and the UTF-8 Cyrillic capitals by explicit byte ranges
function D.Lower(s)
  s = s:gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end)
  s = s:gsub("\208([\144-\159])", function(c) return "\208" .. string.char(c:byte() + 32) end) -- А-П -> а-п
  s = s:gsub("\208([\160-\175])", function(c) return "\209" .. string.char(c:byte() - 32) end) -- Р-Я -> р-я
  s = s:gsub("\208\129", "\209\145")                                                          -- Ё -> ё
  return s
end

function D.ItemName(item)
  return item.link:match("%[(.-)%]") or item.link
end

function D.Matches(item, query)
  if not query or query == "" then return true end
  if not item then return false end
  return string.find(D.Lower(D.ItemName(item)), D.Lower(query), 1, true) ~= nil
end

-- one cell per bank slot, bags in order; false marks an empty slot
function D.Cells(snap)
  local cells = {}
  for _, bag in ipairs(snap and snap.bags or {}) do
    for slot = 1, bag.size do cells[#cells + 1] = bag.slots[slot] or false end
  end
  return cells, #cells
end

-- same column count ElvUI uses for its bank (Bags.lua, B:Layout)
function D.Columns(width, size, spacing)
  return math.max(1, math.floor(width / (size + spacing)))
end

function D.FormatTime(t)
  return date("%d.%m %H:%M", t)
end
