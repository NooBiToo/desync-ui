-- Headless specs for tools/snapshot.lua: turning the author's ElvUI settings into the pack's snapshot.
local passed, failed = 0, 0
local S

local function setup()
  S = assert(loadfile(ROOT .. "/tools/snapshot.lua"))()
end

local function test(name, fn)
  local ok, err = pcall(function() setup() fn() end)
  if ok then passed = passed + 1; print("PASS " .. name)
  else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end

test("Strip drops mui everywhere and MerathilisUI movers", function()
  local t = S.Strip({ mui = {}, a = { mui = 1, b = 2 }, movers = { MER_X = "p", mUI_Y = "p", ElvAB_1 = "p" } })
  assert(t.mui == nil and t.a.mui == nil and t.a.b == 2)
  assert(t.movers.MER_X == nil and t.movers.mUI_Y == nil and t.movers.ElvAB_1 == "p")
end)

test("Replace: name fonts to Expressway, other fonts to PT Sans Narrow", function()
  local t = S.Replace({
    nameplates = { units = { ENEMY_NPC = { name = { font = "GothamNarrow-Black" },
                                           health = { text = { font = "- GothamNarrow-Black" } } } } },
    unitframe = { units = { raid1 = { customTexts = {
      N = { font = "GothamNarrow-Black", text_format = "[name:MER:gradient]" },
      MERMana = { font = "GothamNarrow-Black", text_format = "[power:current]" } } } } },
    general = { dmgfont = "- GothamNarrow-Black" },
  })
  assert(t.nameplates.units.ENEMY_NPC.name.font == "Expressway")
  assert(t.nameplates.units.ENEMY_NPC.health.text.font == "PT Sans Narrow")
  assert(t.unitframe.units.raid1.customTexts.N.font == "Expressway")
  assert(t.unitframe.units.raid1.customTexts.N.text_format == "[namecolor][name:medium]")
  assert(t.unitframe.units.raid1.customTexts.MERMana.font == "PT Sans Narrow")
  assert(t.general.dmgfont == "PT Sans Narrow")
end)

test("Replace: glow texture, chat keywords, WIM datatext", function()
  local t = S.Replace({
    unitframe = { colors = { frameGlow = { mouseoverGlow = { texture = "MER_Stripes", enable = true } } } },
    chat = { keywords = "%MYNAME%, ElvUI, MerathilisUI" },
    datatexts = { panels = { MinimapPanel = { [1] = "LDB_WIM", [2] = "Time" } } },
  })
  assert(t.unitframe.colors.frameGlow.mouseoverGlow.texture == nil and t.unitframe.colors.frameGlow.mouseoverGlow.enable)
  assert(t.chat.keywords == "%MYNAME%, ElvUI")
  assert(t.datatexts.panels.MinimapPanel[1] == "Friends" and t.datatexts.panels.MinimapPanel[2] == "Time")
end)

test("FindPersonal catches names, realm, GUIDs and leftovers; allows MERMana", function()
  S.AddStop({ "MYREALM" })  -- a realm name from the local, untracked stop list
  local found = S.FindPersonal({ a = "Персонаж Сервер", b = { MYREALM = 1 }, c = "Player-1-0000000A",
                                 d = "[name:MER:gradient]", mui = {}, ok = { MERMana = { x = 1 } } })
  assert(#found == 5, "found " .. #found .. ": " .. table.concat(found, ", "))
  assert(#S.FindPersonal({ ok = { MERMana = { font = "PT Sans Narrow" } } }) == 0)
end)

test("GlobalSubset keeps only UIScale, the minimap-top panel and clean WT", function()
  local g = S.GlobalSubset({ general = { UIScale = 0.8, AceGUI = {} }, serverID = { [1] = 1 },
    datatexts = { customPanels = { ["minimap-top"] = { x = 1 }, other = {} } }, WT = { a = 1 }, mui = {} })
  assert(g.general.UIScale == 0.8 and g.general.AceGUI == nil and g.serverID == nil and g.mui == nil)
  assert(g.datatexts.customPanels["minimap-top"].x == 1 and g.datatexts.customPanels.other == nil and g.WT.a == 1)
  assert(S.GlobalSubset({ general = { UIScale = 1 }, WT = { note = "Персонаж" } }).WT == nil)
end)

test("the shipped stop list is generic; personal words come only from AddStop", function()
  for _, w in ipairs(S.STOP) do assert(not w:find("[\128-\255]"), w) end
  assert(#S.STOP == 6)
  assert(#S.FindPersonal({ a = "ZZTOP" }) == 0)
  S.AddStop({ "ZZTOP" })
  assert(#S.FindPersonal({ a = "ZZTOP" }) == 1)
end)

test("CountMer counts mui keys and MerathilisUI movers anywhere", function()
  local t = { mui = {}, profiles = { K = { mui = { x = 1 }, movers = { MER_A = "p", mUI_B = "p", ElvAB_1 = "p" } } } }
  local mui, movers = S.CountMer(t)
  assert(mui == 2 and movers == 2)
  S.Strip(t)
  mui, movers = S.CountMer(t)
  assert(mui == 0 and movers == 0)
end)

test("Serialize is deterministic and loads back", function()
  local src = S.Serialize({ b = 1, a = { 2, 3 }, ["x y"] = "q\"\n", t = true })
  assert(src == S.Serialize({ t = true, ["x y"] = "q\"\n", a = { 2, 3 }, b = 1 }))
  local back = loadstring("return " .. src)()
  assert(back.b == 1 and back.a[2] == 3 and back["x y"] == "q\"\n" and back.t == true)
end)

test("Serialize keeps big integers, infinities and control characters intact", function()
  local t = { a = 3e9, b = -3e9, c = 1 / 0, d = -1 / 0, e = "x\ry\0z\t", f = 2 ^ 40 + 1, g = 0.1 }
  local back = loadstring("return " .. S.Serialize(t))()
  for k, v in pairs(t) do assert(back[k] == v, k .. ": " .. tostring(back[k])) end
end)

test("FindPersonal rejects any non-ASCII text (character names of any alt)", function()
  assert(#S.FindPersonal({ note = "Эрл" }) == 1)
  assert(#S.FindPersonal({ ["Ключ"] = 1 }) == 1)
  assert(#S.FindPersonal({ font = "PT Sans Narrow" }) == 0)
end)

test("Build refuses a value that does not survive the round trip", function()
  local ok, err = pcall(S.Build, { profiles = { K = { x = 0 / 0 } }, global = {} }, { profiles = { K = {} } }, "K", 1)
  assert(not ok and tostring(err):find("round trip", 1, true))
end)

test("Build refuses a snapshot that still carries personal data", function()
  S.AddStop({ "MYREALM" })
  local ok, err = pcall(S.Build, { profiles = { K = { note = "MYREALM" } }, global = {} }, { profiles = { K = {} } }, "K", 1)
  assert(not ok and tostring(err):find("MYREALM", 1, true))
end)

test("Build writes a loadable Profile.lua with version, profile, private and global", function()
  local src = S.Build(
    { profiles = { K = { general = { font = "GothamNarrow-Black" }, mui = {} } }, global = { general = { UIScale = 0.8 } } },
    { profiles = { K = { general = { dmgfont = "- GothamNarrow-Black" } } } }, "K", 3)
  local ns = {}
  assert(loadstring(src))("ElvUI_DeSyncUI", ns)
  assert(ns.Snapshot.version == 3 and ns.Snapshot.profile.general.font == "PT Sans Narrow")
  assert(ns.Snapshot.profile.mui == nil and ns.Snapshot.private.general.dmgfont == "PT Sans Narrow")
  assert(ns.Snapshot.global.general.UIScale == 0.8)
end)

print(passed .. " passed, " .. failed .. " failed")
if failed > 0 then error("tests failed") end
