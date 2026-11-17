local ADDON, ns = ...
-- Questie's quest rows vanish from a mob's tooltip after the first rebuild (seen in the TipLog journal):
-- ElvUI blanks a line of the unit tooltip (text ''), Questie's CountTooltip stops at the first empty line,
-- so on each rebuild of the same mob it counts 2 rows, decides its rows are already there and skips them.
-- Every rebuild starts with a cleared tooltip, so forgetting Questie's "already added" state on clear is safe.
local mod = ns.NewModule("QuestieTipFix", {
  title = "Questie: прогресс квеста в подсказке",
  desc = "Возвращает строки Questie (прогресс квеста) в подсказку моба. Без этого они пропадают, "
      .. "когда игра перестраивает подсказку: пустая строка от ElvUI сбивает Questie со счёта строк.",
})

function mod.OnEnable()
  if not (QuestieLoader and QuestieLoader.ImportModule) then return end  -- no Questie: nothing to fix
  local ok, QT = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieTooltips")
  if not ok or type(QT) ~= "table" then return end

  GameTooltip:HookScript("OnTooltipCleared", function(tooltip)
    if tooltip:IsForbidden() then return end
    QT.lastGametooltipUnit = nil
    QT.lastGametooltipCount = 0
  end)
end
