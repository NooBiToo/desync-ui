-- Turns the author's ElvUI settings into the DeSync UI snapshot (Profile.lua).
-- Plain Lua 5.1, no WoW API: used by tools/export_profile.py, tools/migrate_author.py, tools/build_release.py
-- and by tests/snapshot_spec.lua.
local S = {}

-- GUIDs and MerathilisUI leftovers that must never ship (the key "mui" is checked separately).
-- Custom text names like "MERMana" are allowed, so plain "MER" is not a stop word.
-- Personal words (realm, account) are not kept in the repository: the tools add them from the untracked
-- tools/stopwords.local.txt through S.AddStop. Character names are caught anyway: any non-ASCII text fails.
S.STOP = { "Player-", "Merathilis", "GothamNarrow", "MER:", "MER_", "mUI_" }

function S.AddStop(words)
  for _, w in ipairs(words) do S.STOP[#S.STOP + 1] = w end
end

local GOTHAM = { ["GothamNarrow-Black"] = true, ["- GothamNarrow-Black"] = true }
local NAME_FONT, OTHER_FONT = "Expressway", "PT Sans Narrow"
local MER_TAG, NAME_TAG = "[name:MER:gradient]", "[namecolor][name:medium]"

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end
S.Copy = copy

local function plainReplace(s, from, to)
  local i = 1
  local out = {}
  while true do
    local a, b = string.find(s, from, i, true)
    if not a then break end
    out[#out + 1] = s:sub(i, a - 1) .. to
    i = b + 1
  end
  out[#out + 1] = s:sub(i)
  return table.concat(out)
end

function S.Strip(t)
  for k, v in pairs(t) do
    if k == "mui" then
      t[k] = nil
    elseif type(v) == "table" then
      if k == "movers" then
        for m in pairs(v) do
          if type(m) == "string" and (m:find("^MER_") or m:find("^mUI_")) then v[m] = nil end
        end
      end
      S.Strip(v)
    end
  end
  return t
end

-- how much MerathilisUI is left: "mui" keys and MER_/mUI_ movers, at any depth
function S.CountMer(t, mui, movers)
  mui, movers = mui or 0, movers or 0
  for k, v in pairs(t) do
    if k == "mui" then
      mui = mui + 1
    elseif type(v) == "table" then
      if k == "movers" then
        for m in pairs(v) do
          if type(m) == "string" and (m:find("^MER_") or m:find("^mUI_")) then movers = movers + 1 end
        end
      end
      mui, movers = S.CountMer(v, mui, movers)
    end
  end
  return mui, movers
end

-- a font field belongs to a name text: a "name" table on its path, or a custom text showing a name tag
local function isNameFont(path, parent)
  for _, k in ipairs(path) do
    if k == "name" then return true end
  end
  local fmt = parent.text_format
  return type(fmt) == "string" and fmt:find("[name", 1, true) ~= nil
end

local function cleanKeywords(s)
  local keep = {}
  for part in string.gmatch(s, "[^,]+") do
    local w = part:match("^%s*(.-)%s*$")
    if w ~= "" and w ~= "MerathilisUI" then keep[#keep + 1] = w end
  end
  return table.concat(keep, ", ")
end

local function replaceIn(t, path)
  -- text formats first: deciding a name font looks at the parent's text_format
  for k, v in pairs(t) do
    if type(v) == "string" and v:find(MER_TAG, 1, true) then t[k] = plainReplace(v, MER_TAG, NAME_TAG) end
  end
  for k, v in pairs(t) do
    if type(v) == "string" then
      if GOTHAM[v] then
        t[k] = (k == "font" and isNameFont(path, t)) and NAME_FONT or OTHER_FONT
      elseif v == "LDB_WIM" then
        t[k] = "Friends"
      elseif k == "texture" and v == "MER_Stripes" then
        t[k] = nil
      elseif k == "keywords" and v:find("MerathilisUI", 1, true) then
        t[k] = cleanKeywords(v)
      end
    elseif type(v) == "table" then
      path[#path + 1] = k
      replaceIn(v, path)
      path[#path] = nil
    end
  end
end

function S.Replace(t)
  replaceIn(t, {})
  return t
end

-- a stop word, or any non-ASCII text: the snapshot is plain ASCII, so Cyrillic means a character name
local function stopIn(s)
  for _, w in ipairs(S.STOP) do
    if string.find(s, w, 1, true) then return w end
  end
  if string.find(s, "[\128-\255]") then return "non-ASCII" end
end

function S.FindPersonal(t, prefix, found)
  found = found or {}
  for k, v in pairs(t) do
    local path = (prefix and (prefix .. ".") or "") .. tostring(k)
    local hit = (k == "mui" and "mui") or (type(k) == "string" and stopIn(k))
    if hit then
      found[#found + 1] = path .. " (" .. hit .. ")"
    elseif type(v) == "string" then
      local w = stopIn(v)
      if w then found[#found + 1] = path .. " (" .. w .. ")" end
    elseif type(v) == "table" then
      S.FindPersonal(v, path, found)
    end
  end
  return found
end

function S.GlobalSubset(g)
  local out = { general = { UIScale = g.general and g.general.UIScale } }
  local panel = g.datatexts and g.datatexts.customPanels and g.datatexts.customPanels["minimap-top"]
  if panel then out.datatexts = { customPanels = { ["minimap-top"] = copy(panel) } } end
  if type(g.WT) == "table" then
    local wt = S.Strip(copy(g.WT))
    if #S.FindPersonal(wt) == 0 then out.WT = wt end
  end
  return out
end

local function keyOrder(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then return ta == "number" end
  if ta == "number" or ta == "string" then return a < b end
  return tostring(a) < tostring(b)
end

-- %q leaves a carriage return raw, which Lua 5.1 refuses inside a string literal
local function quote(s)
  return (string.format("%q", s):gsub("\r", "\\r"))
end

local function value(v, indent)
  local tv = type(v)
  if tv == "string" then return quote(v) end
  if tv == "number" then
    if v ~= v then return "0/0" end
    if v == 1 / 0 then return "1/0" end
    if v == -1 / 0 then return "-1/0" end
    -- %d is 32-bit in Lua 5.1 on Windows: larger integers go through %.17g
    if v == math.floor(v) and math.abs(v) < 2 ^ 31 then return string.format("%d", v) end
    return string.format("%.17g", v)
  end
  if tv == "boolean" then return tostring(v) end
  if tv == "table" then return S.Serialize(v, indent) end
  error("cannot serialize a " .. tv)
end

function S.Serialize(t, indent)
  indent = indent or ""
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, keyOrder)
  local inner = indent .. "\t"
  local lines = { "{" }
  for _, k in ipairs(keys) do
    local key = type(k) == "string" and ("[" .. quote(k) .. "]") or ("[" .. value(k) .. "]")
    lines[#lines + 1] = inner .. key .. " = " .. value(t[k], inner) .. ","
  end
  lines[#lines + 1] = indent .. "}"
  return table.concat(lines, "\n")
end

-- same settings, value by value
function S.Same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for k, v in pairs(a) do if not S.Same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

function S.Build(elvdb, privatedb, profileKey, version)
  local profile = elvdb.profiles and elvdb.profiles[profileKey]
  if type(profile) ~= "table" then error("no ElvUI profile " .. tostring(profileKey)) end
  local private = privatedb and privatedb.profiles and privatedb.profiles[profileKey] or {}
  local snap = {
    version = version,
    profile = S.Replace(S.Strip(copy(profile))),
    private = S.Replace(S.Strip(copy(private))),
    global = S.GlobalSubset(elvdb.global or {}),
  }
  local found = S.FindPersonal(snap)
  if #found > 0 then error("personal data or MerathilisUI left in the snapshot: " .. table.concat(found, "; ")) end
  local src = "-- generated by tools/export_profile.py from the author's ElvUI settings; do not edit by hand\n"
    .. "local ADDON, ns = ...\n"
    .. "ns.Snapshot = " .. S.Serialize(snap) .. "\n"
  -- the written file must load back to exactly this snapshot
  local ns = {}
  local fn = loadstring(src)
  if fn then fn("check", ns) end
  if not (fn and S.Same(snap, ns.Snapshot)) then error("snapshot does not survive the round trip to Profile.lua") end
  return src
end

return S
