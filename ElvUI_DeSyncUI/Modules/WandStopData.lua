local ADDON, ns = ...
-- Which keys get the "/stopcasting, then cast" macro, and its text.
-- Plain Lua on purpose: tests/wandstopdata_spec.lua runs it headless.
local S = {}
ns.WandStopData = S

-- never wrapped: wand Shoot and hunter Auto Shot (stopping them is the point, not casting them)
S.SKIP = { [5019] = true, [75] = true }

-- a subtext is a rank only when it carries a number ("Уровень 3"), not "Расовая способность".
-- mods = { self = bool, focus = bool }: mirror ElvUI's checkselfcast / checkfocuscast on its buttons
function S.MacroText(name, subtext, mods)
  local rank = (subtext and subtext:find("%d")) and ("(" .. subtext .. ")") or ""
  local cond = ""
  if mods and mods.self then cond = cond .. "[mod:SELFCAST,@player]" end
  if mods and mods.focus then cond = cond .. "[mod:FOCUSCAST,@focus,exists]" end
  if cond ~= "" then cond = cond .. "[] " end
  return "/stopcasting [nochanneling]\n/cast " .. cond .. name .. rank
end

function S.ParseExclusions(text)
  local set = {}
  for part in string.gmatch(text or "", "[^,]+") do
    local name = part:match("^%s*(.-)%s*$")
    if name ~= "" then set[ns.BankData.Lower(name)] = true end
  end
  return set
end

-- buttons: { { keys = {string}, slot = number|nil, bar = string|nil, page = string|nil } }
-- api: ActionInfo / SpellName / SpellSubtext. Returns { { key, text, bar, page } }
function S.Collect(buttons, api, exclude, mods)
  local out = {}
  for _, b in ipairs(buttons) do
    local kind, id
    if b.slot then kind, id = api.ActionInfo(b.slot) end
    local name = kind == "spell" and id and not S.SKIP[id] and api.SpellName(id)
    if name and not exclude[ns.BankData.Lower(name)] then
      local text = S.MacroText(name, api.SpellSubtext(id), mods)
      for _, key in ipairs(b.keys) do
        out[#out + 1] = { key = key, text = text, bar = b.bar, page = b.page }
      end
    end
  end
  return out
end
