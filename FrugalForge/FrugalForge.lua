local ADDON_NAME = ... or "FrugalForge"

local function ts()
  return date("%Y-%m-%d %H:%M:%S", time())
end

local function ensureDb()
  FrugalForgeDB = FrugalForgeDB or {}
  FrugalForgeDB.settings = FrugalForgeDB.settings or {
    warnStaleHours = 12,
    priceRank = 3, -- 1=min, 2=median, 3=most recent
    showPanelOnAuctionHouse = true,
    maxSkillDelta = 100,
    selectedProfessionId = nil,
    debug = false,
    useCraftIntermediates = true,
    ignoreOwnedSelection = false,
    currentCharOnlySelection = false,
    ownedValueFactor = 0.9,
    devMode = false,
    minimapAngle = 45,
    includeNonTrainerRecipes = true,
  }
  FrugalForgeDB.lastPlan = FrugalForgeDB.lastPlan or nil
end

local function latestSnapshot()
  local db = _G.FrugalScanDB or _G.ProfessionLevelerScanDB
  if type(db) ~= "table" then return nil end
  local snap = db.lastSnapshot
  if type(snap) ~= "table" then return nil end
  return snap
end

local function latestOwned()
  if type(FrugalForgeDB) == "table" and type(FrugalForgeDB.lastOwnedSnapshot) == "table" then
    return FrugalForgeDB.lastOwnedSnapshot
  end
  local db = _G.FrugalScanDB or _G.ProfessionLevelerScanDB
  if type(db) ~= "table" then return nil end
  local owned = db.lastOwnedSnapshot
  if type(owned) ~= "table" then return nil end
  return owned
end

local function parseIsoTimestampToEpoch(ts)
  if type(ts) ~= "string" then return nil end
  local y, m, d, hh, mm, ss = string.match(ts, "^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)Z$")
  if not y then return nil end
  return time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = tonumber(hh), min = tonumber(mm), sec = tonumber(ss) })
end

local function getSnapshotEpoch(snap)
  if type(snap) ~= "table" then return nil end
  if type(snap.generatedAtEpochUtc) == "number" then return snap.generatedAtEpochUtc end
  if type(snap.snapshotTimestampUtc) == "string" then
    return parseIsoTimestampToEpoch(snap.snapshotTimestampUtc)
  end
  return nil
end

local function fmtAge(epochUtc)
  if type(epochUtc) ~= "number" then return "unknown" end
  local delta = time() - epochUtc
  if delta < 0 then delta = 0 end
  local hours = math.floor(delta / 3600)
  local mins = math.floor((delta % 3600) / 60)
  return string.format("%dh %dm ago", hours, mins)
end

local function hoursSince(epochUtc)
  if type(epochUtc) ~= "number" then return nil end
  local delta = time() - epochUtc
  if delta < 0 then delta = 0 end
  return delta / 3600
end

local function colorize(text, color)
  return color .. text .. "|r"
end

local function getItemName(itemId)
  local data = FrugalForgeData_Anniversary
  if data and type(data.items) == "table" then
    local name = data.items[itemId]
    if name then return name end
  end
  return "item " .. tostring(itemId)
end

local QUALITY_COMMON = 1
local QUALITY_UNCOMMON = 2

local function getItemQuality(itemId)
  if not itemId then return nil end
  local _, _, quality = GetItemInfo(itemId)
  return quality
end

local function isQualityAtMost(itemId, maxQuality)
  local quality = getItemQuality(itemId)
  if quality == nil then return true end
  return quality <= maxQuality
end

local function log(msg)
  if not msg then return end
  DEFAULT_CHAT_FRAME:AddMessage("|cff7dd3fcFrugalForge|r: " .. tostring(msg))
  FrugalForgeDB.debugLog = FrugalForgeDB.debugLog or {}
  table.insert(FrugalForgeDB.debugLog, tostring(msg))
  if #FrugalForgeDB.debugLog > 200 then
    table.remove(FrugalForgeDB.debugLog, 1)
  end
end

local ui = {}
local buildTargetsForProfession
local buildPriceMap
local buildScanTargets
local getProfessionByName
local applyTargetsSafe
local debugLog
local showTextFrame

local function updateScanStatus()
  if not ui.scanValue then return end
  local status = _G.FrugalScan_ScanStatus or _G.ProfessionLevelerScan_ScanStatus
  if status and status.running then
    local total = tonumber(status.total) or 0
    local remaining = tonumber(status.remaining) or 0
    local done = total - remaining
    if total > 0 then
      ui.scanValue:SetText(string.format("Scan: %d/%d (%d remaining)", done, total, remaining))
    else
      ui.scanValue:SetText("Scan: running...")
    end
  else
    ui.scanValue:SetText("Scan: idle")
  end
end

_G.FrugalForge_UpdateScanStatus = updateScanStatus
local function buildTargetsFromUi()
  local selected = FrugalForgeDB.settings.selectedProfessionId
  if ui.profDrop then
    local dropdownText = UIDropDownMenu_GetText(ui.profDrop)
    if dropdownText and dropdownText ~= "" and dropdownText ~= "Select..." then
      local byName = nil
      if type(getProfessionByName) == "function" then
        byName = getProfessionByName(dropdownText)
      else
        local data = FrugalForgeData_Anniversary
        if data and type(data.professions) == "table" then
          local target = tostring(dropdownText or ""):lower()
          for _, p in ipairs(data.professions) do
            local name = tostring(p.name or ""):lower()
            if name == target then
              byName = p
              break
            end
          end
        end
      end
      if byName and byName.professionId ~= selected then
        selected = byName.professionId
        FrugalForgeDB.settings.selectedProfessionId = selected
      end
    end
  end
  if not selected then
    local msg = "Select a profession first."
    FrugalForgeDB.lastBuildError = msg
    DEFAULT_CHAT_FRAME:AddMessage("|cff7dd3fcFrugalForge|r: " .. msg)
    showTextFrame(msg, "FrugalForge Build Targets Error")
    return
  end
  local delta = tonumber(ui.deltaBox and ui.deltaBox:GetText() or "") or (FrugalForgeDB.settings.maxSkillDelta or 100)
  FrugalForgeDB.settings.maxSkillDelta = delta
  if FrugalScanDB and FrugalScanDB.settings then
    FrugalScanDB.settings.maxSkillDelta = delta
  end
  FrugalForgeDB.lastBuildError = nil
  FrugalForgeDB.lastBuildMessage = "Build Targets clicked for id=" .. tostring(selected)
  log(FrugalForgeDB.lastBuildMessage)
  local function onErr(err)
    local stack = nil
    if type(debugstack) == "function" then
      stack = debugstack()
    elseif debug and type(debug.traceback) == "function" then
      stack = debug.traceback()
    end
    return tostring(err) .. (stack and ("\n" .. stack) or "")
  end
  local ok, built, err = xpcall(function()
    return buildTargetsForProfession(selected, delta)
  end, onErr)
  if not ok then
    local msg = "Build targets error: " .. tostring(built)
    FrugalForgeDB.lastBuildError = msg
    showTextFrame(msg, "FrugalForge Build Targets Error")
    DEFAULT_CHAT_FRAME:AddMessage("|cff7dd3fcFrugalForge|r: " .. msg)
    return
  end
  if not built then
    local msg = tostring(err or "Failed to build targets")
    FrugalForgeDB.lastBuildError = msg
    showTextFrame(msg, "FrugalForge Build Targets Error")
    DEFAULT_CHAT_FRAME:AddMessage("|cff7dd3fcFrugalForge|r: " .. msg)
    return
  end
  FrugalForgeDB.targets = {
    professionId = built.profession.professionId,
    professionName = built.profession.name,
    targets = built.targets,
    reagentIds = built.reagentIds,
  }
  FrugalForgeDB.targetsBuiltAt = ts()
  FrugalForgeDB.targetsBuiltAtEpoch = time()
  FrugalScan_OwnedItemIds = built.reagentIds
  ProfessionLevelerScan_OwnedItemIds = built.reagentIds
  local prices = buildPriceMap()
  local scanTargets = buildScanTargets(built, prices)
  FrugalForgeDB.scanTargets = {
    professionId = scanTargets.profession.professionId,
    professionName = scanTargets.profession.name,
    targets = scanTargets.targets,
    reagentIds = scanTargets.reagentIds,
  }
  local okApply, applyErr = applyTargetsSafe(scanTargets)
  if not okApply then
    local msg = "Targets built, but failed to apply globals: " .. tostring(applyErr)
    FrugalForgeDB.lastBuildError = msg
    showTextFrame(msg, "FrugalForge Build Targets Error")
    DEFAULT_CHAT_FRAME:AddMessage("|cff7dd3fcFrugalForge|r: " .. msg)
    return
  end
  FrugalForgeDB.lastBuildMessage = "Targets built for " .. tostring(built.profession.name) .. " (id=" .. tostring(built.profession.professionId) .. ")"
  log(FrugalForgeDB.lastBuildMessage)
  debugLog("applyTargets: prof=" .. tostring(built.profession.name) .. ", recipes=" .. tostring(#(built.targets or {})) .. ", reagents=" .. tostring(#(built.reagentIds or {})))
  -- No success popup; keep UI quiet when auto-building
end

debugLog = function(msg)
  if FrugalForgeDB and FrugalForgeDB.settings and FrugalForgeDB.settings.debug == true then
    FrugalForgeDB.debugLog = FrugalForgeDB.debugLog or {}
    table.insert(FrugalForgeDB.debugLog, "DEBUG: " .. tostring(msg))
    if #FrugalForgeDB.debugLog > 200 then
      table.remove(FrugalForgeDB.debugLog, 1)
    end
  end
end

showTextFrame = function(text, title)
  if not ui.debugFrame then
    local frame = CreateFrame("Frame", "FrugalForgeDebugFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(520, 420)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", 0, -8)
    frame.title:SetText("FrugalForge Debug")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", -32, 12)

    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetFontObject(GameFontHighlightSmall)
    box:SetWidth(450)
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", function() box:ClearFocus() end)
    scroll:SetScrollChild(box)

    frame.scroll = scroll
    frame.box = box
    ui.debugFrame = frame
  end

  ui.debugFrame.title:SetText(title or "FrugalForge Debug")
  ui.debugFrame.box:SetText(text or "")
  ui.debugFrame.box:HighlightText()
  ui.debugFrame:Show()
end

local function normalizeProfessionName(name)
  if type(name) ~= "string" then return nil end
  local s = string.lower(name)
  local idx = string.find(s, "%(")
  if idx and idx > 1 then
    s = string.sub(s, 1, idx - 1)
  end
  s = string.gsub(s, "^%s+", "")
  s = string.gsub(s, "%s+$", "")
  return s
end

local function getProfessionSkillByName(targetName)
  local targetNorm = normalizeProfessionName(targetName)
  if not targetNorm then return nil, nil end

  if GetNumSkillLines and GetSkillLineInfo then
    local num = GetNumSkillLines()
    if num and num > 0 then
      for i = 1, num do
        local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
        if not isHeader then
          local norm = normalizeProfessionName(name)
          if norm and norm == targetNorm then
            return rank, maxRank
          end
        end
      end
    end
  end

  if GetProfessions and GetProfessionInfo then
    local primary1, primary2, archaeology, fishing, cooking, firstAid = GetProfessions()
    local profs = { primary1, primary2, archaeology, fishing, cooking, firstAid }
    for _, idx in ipairs(profs) do
      if idx then
        local name, _, sLevel, mLevel = GetProfessionInfo(idx)
        local nameNorm = normalizeProfessionName(name)
        if nameNorm and nameNorm == targetNorm then
          return sLevel, mLevel
        end
      end
    end
  end

  return nil, nil
end

local function hasProfession(targetName)
  local rank, maxRank = getProfessionSkillByName(targetName)
  if rank then return true, rank, maxRank end
  return false
end

local function getProfessionList()
  local data = FrugalForgeData_Anniversary
  if not data or type(data.professions) ~= "table" then return {} end
  return data.professions
end

local function getProfessionById(profId)
  for _, p in ipairs(getProfessionList()) do
    if p.professionId == profId then return p end
  end
  return nil
end

local function getProfessionByName(name)
  local target = normalizeProfessionName(name or "")
  for _, p in ipairs(getProfessionList()) do
    if normalizeProfessionName(p.name) == target then return p end
  end
  return nil
end

local function currentSkillForProfession(professionName)
  local rank, maxRank = getProfessionSkillByName(professionName)
  if rank then return rank, maxRank end
  return nil, nil
end

buildTargetsForProfession = function(professionId, maxSkillDelta)
  local prof = getProfessionById(professionId)
  if not prof then return nil, "Unknown profession" end

  local currentSkill, _ = currentSkillForProfession(prof.name)
  if not currentSkill then currentSkill = 1 end
  local maxSkill = currentSkill + (maxSkillDelta or 100)

  local targets = {}
  local reagentIds = {}
  local seen = {}

    local includeNonTrainer = (FrugalForgeDB.settings.includeNonTrainerRecipes ~= false)
    for _, r in ipairs(prof.recipes or {}) do
      local minSkill = r.minSkill or 0
      local grayAt = r.grayAt or 0
      if minSkill <= maxSkill and grayAt > currentSkill then
        if r.learnedByTrainer == false and not includeNonTrainer then
          -- skip recipes that require a purchased recipe item
        else
        local outputItemId = tonumber(r.createsItemId or r.createsItem or r.createsId)
        local allowRecipe = true
        if outputItemId and not isQualityAtMost(outputItemId, QUALITY_UNCOMMON) then
          allowRecipe = false
        end
        if allowRecipe then
          if r.learnedByTrainer == false then
            r.requiresRecipe = true
          else
            r.requiresRecipe = nil
          end
          if type(r.reagents) == "table" and #r.reagents > 0 and type(r.reagents[1]) == "table" then
            r.reagentsWithQty = r.reagents
            local ids = {}
            for _, reg in ipairs(r.reagents) do
              local itemId = tonumber((type(reg) == "table" and (reg.itemId or reg.id or reg[1])) or reg)
              if itemId then table.insert(ids, itemId) end
            end
            r.reagents = ids
          end
          table.insert(targets, r)
          for _, reg in ipairs(r.reagents or {}) do
            local itemId = tonumber((type(reg) == "table" and (reg.itemId or reg.id or reg[1])) or reg)
            if itemId and not seen[itemId] then
              seen[itemId] = true
              table.insert(reagentIds, itemId)
            end
          end
        end
        end
      end
    end

  table.sort(targets, function(a, b)
    if a.minSkill == b.minSkill then return tostring(a.recipeId) < tostring(b.recipeId) end
    return a.minSkill < b.minSkill
  end)
  table.sort(reagentIds)

  return {
    profession = prof,
    targets = targets,
    reagentIds = reagentIds,
    currentSkill = currentSkill,
    maxSkill = maxSkill,
  }, nil
end

local function buildRecipeByOutput(profession)
  local map = {}
  if not profession or type(profession.recipes) ~= "table" then return map end
  for _, r in ipairs(profession.recipes) do
    if r and r.createsItemId then
      local existing = map[r.createsItemId]
      if not existing or (r.minSkill or 0) < (existing.minSkill or 9999) then
        map[r.createsItemId] = r
      end
    end
  end
  return map
end

buildPriceMap = function()
  local snap = latestSnapshot()
  local prices = {}
  if snap and type(snap.prices) == "table" then
    for _, p in ipairs(snap.prices) do
      local itemId = tonumber(p.itemId)
        local price = tonumber(p.minUnitBuyoutCopper)
        if itemId and price and price > 0 then
          prices[itemId] = price
        end
      end
    end
  return prices
end

buildScanTargets = function(fullTargets, prices)
  if not fullTargets or type(fullTargets.targets) ~= "table" then return fullTargets end
  if not prices or next(prices) == nil then return fullTargets end

  local perBand = FrugalForgeDB.settings.scanCheapestPerBand or 3
  local bandSize = FrugalForgeDB.settings.scanBandSize or 5
  local buckets = {}

  local function getReagents(recipe)
    if type(recipe.reagentsWithQty) == "table" and #recipe.reagentsWithQty > 0 then
      return recipe.reagentsWithQty
    end
    if type(recipe.reagents) == "table" and #recipe.reagents > 0 and type(recipe.reagents[1]) == "table" then
      return recipe.reagents
    end
    if type(recipe.reagents) == "table" then
      local r = {}
      for _, itemId in ipairs(recipe.reagents) do
        table.insert(r, { itemId = itemId, qty = 1 })
      end
      return r
    end
    return nil
  end

  for _, r in ipairs(fullTargets.targets) do
    if type(r) == "table" then
      local reagents = getReagents(r)
      if reagents then
        local cost = 0
        local missing = 0
        for _, entry in ipairs(reagents) do
          local itemId = tonumber(entry.itemId or entry.id or entry[1])
          local qty = entry.qty or entry.quantity or 1
          local price = prices[itemId]
          if price then
            cost = cost + price * qty
          else
            missing = missing + 1
          end
        end
        local minSkill = r.minSkill or 0
        local band = math.floor(minSkill / bandSize)
        buckets[band] = buckets[band] or {}
        table.insert(buckets[band], { recipe = r, cost = cost, missing = missing })
      end
    end
  end

  local selected = {}
  for _, list in pairs(buckets) do
    table.sort(list, function(a, b)
      if a.missing == b.missing then return a.cost < b.cost end
      return a.missing < b.missing
    end)
    for i = 1, math.min(perBand, #list) do
      table.insert(selected, list[i].recipe)
    end
  end

  if #selected < 5 then
    return fullTargets
  end

  local reagentIds = {}
  local seen = {}
    for _, r in ipairs(selected) do
      for _, reg in ipairs(r.reagents or {}) do
        local itemId = tonumber((type(reg) == "table" and (reg.itemId or reg.id or reg[1])) or reg)
        if itemId and not seen[itemId] and isQualityAtMost(itemId, QUALITY_UNCOMMON) then
          seen[itemId] = true
          table.insert(reagentIds, itemId)
        end
      end
    end
  table.sort(reagentIds)

  return {
    profession = fullTargets.profession,
    targets = selected,
    reagentIds = reagentIds,
    currentSkill = fullTargets.currentSkill,
    maxSkill = fullTargets.maxSkill,
  }
end


local function applyTargets(targets)
  ProfessionLevelerScan_TargetProfessionId = targets.profession.professionId
  ProfessionLevelerScan_TargetProfessionName = targets.profession.name
  ProfessionLevelerScan_TargetGameVersion = "Anniversary"
  ProfessionLevelerScan_RecipeTargets = targets.targets
  ProfessionLevelerScan_TargetItemIds = targets.reagentIds

  FrugalScan_TargetProfessionId = ProfessionLevelerScan_TargetProfessionId
  FrugalScan_TargetProfessionName = ProfessionLevelerScan_TargetProfessionName
  FrugalScan_TargetGameVersion = ProfessionLevelerScan_TargetGameVersion
  FrugalScan_RecipeTargets = ProfessionLevelerScan_RecipeTargets
  FrugalScan_TargetItemIds = ProfessionLevelerScan_TargetItemIds
end

applyTargetsSafe = function(targets)
  local ok, err = pcall(applyTargets, targets)
  if not ok then
    return false, tostring(err)
  end
  return true, nil
end

local function updateUi()
  if not ui.frame then return end
  ensureDb()

  local snap = latestSnapshot()
  if snap and (snap.snapshotTimestampUtc or snap.generatedAtEpochUtc) then
    local epoch = getSnapshotEpoch(snap)
    local tsText = snap.snapshotTimestampUtc or "unknown"
    ui.snapshotValue:SetText(string.format("Snapshot: %s (%s)", tsText, fmtAge(epoch)))
  else
    ui.snapshotValue:SetText("Snapshot: none found (run scan)")
  end

  local owned = latestOwned()
  if owned and (owned.snapshotTimestampUtc or owned.generatedAtEpochUtc) then
    local epoch = getSnapshotEpoch(owned)
    local tsText = owned.snapshotTimestampUtc or "unknown"
    ui.ownedValue:SetText(string.format("Owned: %s (%s)", tsText, fmtAge(epoch)))
  else
    ui.ownedValue:SetText("Owned: none found (run /frugal owned)")
  end

  local plan = FrugalForgeDB.lastPlan
  if plan and plan.generatedAt then
    ui.planValue:SetText(string.format("Plan: %s (%s)", plan.generatedAt, fmtAge(plan.generatedAtEpochUtc or time())))
    ui.stepsBox:SetText(plan.stepsText or "")
    ui.shoppingBox:SetText(plan.shoppingText or "")
    if plan.summaryText then
      local lines = {}
      for line in string.gmatch(plan.summaryText, "[^\r\n]+") do
        if not string.match(line, "^%s*DEBUG") and
           not string.match(line, "^%s*Debug:") and
           not string.match(line, "^%s*Targets profession:") and
           not string.match(line, "^%s*Your skill:") then
          table.insert(lines, line)
        end
      end
      ui.summaryBox:SetText(table.concat(lines, "\n"))
    else
      ui.summaryBox:SetText("")
    end
    ui.coverageValue:SetText(colorize(string.format("Coverage: %d%% (%d/%d priced)", plan.coveragePercent or 0, plan.pricedKinds or 0, plan.reagentKinds or 0), "|cffc0ffc0"))
    ui.missingValue:SetText(colorize(string.format("Missing prices: %d", plan.missingPriceItemCount or 0), (plan.missingPriceItemCount or 0) > 0 and "|cffffa0a0" or "|cffc0ffc0"))
    if plan.staleWarning then
      ui.staleValue:SetText(colorize(plan.staleWarning, "|cffffa0a0"))
    else
      ui.staleValue:SetText(colorize("Snapshot fresh", "|cffc0ffc0"))
    end
  else
    ui.planValue:SetText("Plan: not generated yet")
    ui.stepsBox:SetText("")
    ui.shoppingBox:SetText("")
    if FrugalForgeDB.settings.debug == true then
      ui.summaryBox:SetText("Debug enabled. Click Generate Plan to populate debug output.")
    else
      ui.summaryBox:SetText("")
    end
    ui.coverageValue:SetText("Coverage: n/a")
    ui.missingValue:SetText("")
    ui.staleValue:SetText("")
  end

  updateScanStatus()
end

local function buildMaps()
  local snap = latestSnapshot()
  local owned = latestOwned()
  local prices = {}
  local priceCount = 0
  if snap and type(snap.prices) == "table" then
    for _, p in ipairs(snap.prices) do
      local itemId = tonumber(p.itemId)
      local price = tonumber(p.minUnitBuyoutCopper)
      if itemId and price and price > 0 then
        prices[itemId] = price
        priceCount = priceCount + 1
      end
    end
  end

  local ownedMap = {}
  local ownedCount = 0
  if not (FrugalForgeDB.settings and FrugalForgeDB.settings.currentCharOnlySelection) then
  if owned and type(owned.items) == "table" then
    for _, it in ipairs(owned.items) do
      local itemId = tonumber(it.itemId)
      if itemId and it.qty and it.qty > 0 then
        ownedMap[itemId] = (ownedMap[itemId] or 0) + it.qty
        ownedCount = ownedCount + 1
      end
    end
  end
  end

  -- Augment owned counts with current character inventory/bank for target reagents
  if GetItemCount then
    local ids = nil
    if type(FrugalForgeDB) == "table" and type(FrugalForgeDB.targets) == "table" then
      ids = FrugalForgeDB.targets.reagentIds
    end
    if type(ids) ~= "table" or #ids == 0 then
      local recipes = (FrugalForgeDB.targets and FrugalForgeDB.targets.targets) or _G.FrugalScan_RecipeTargets or _G.ProfessionLevelerScan_RecipeTargets
      if type(recipes) == "table" then
        ids = {}
        local seen = {}
        for _, r in ipairs(recipes) do
          if type(r) == "table" and type(r.reagents) == "table" then
            for _, reg in ipairs(r.reagents) do
              local n = tonumber((type(reg) == "table" and (reg.itemId or reg.id or reg[1])) or reg)
              if n and n > 0 and not seen[n] then
                seen[n] = true
                table.insert(ids, n)
              end
            end
          end
        end
      end
    end
    if type(ids) == "table" then
      for _, itemId in ipairs(ids) do
        local n = tonumber(itemId)
        if n and n > 0 then
          local count = GetItemCount(n, true) or 0
          if count > 0 then
            ownedMap[n] = math.max(ownedMap[n] or 0, count)
          end
        end
      end
    end
  end

  local ownedByChar = {}
  if not (FrugalForgeDB.settings and FrugalForgeDB.settings.currentCharOnlySelection) then
  if owned and type(owned.characters) == "table" then
    for _, c in ipairs(owned.characters) do
      if type(c) == "table" and c.name and type(c.items) == "table" then
        for _, it in ipairs(c.items) do
          local itemId = tonumber(it.itemId)
          if itemId and it.qty and it.qty > 0 then
            local charMap = ownedByChar[itemId] or {}
            charMap[c.name] = (charMap[c.name] or 0) + it.qty
            ownedByChar[itemId] = charMap
          end
        end
      end
    end
  end
  end

  debugLog("snapshot prices=" .. tostring(priceCount) .. ", owned items=" .. tostring(ownedCount))
  return prices, priceCount, ownedMap, ownedCount, ownedByChar, snap, owned
end

local function copperToText(c)
  if not c then return "?" end
  local gold = math.floor(c / 10000)
  local silver = math.floor((c % 10000) / 100)
  local copper = c % 100
  if gold > 0 then
    return string.format("%dg %ds %dc", gold, silver, copper)
  elseif silver > 0 then
    return string.format("%ds %dc", silver, copper)
  else
    return string.format("%dc", copper)
  end
end

local function generatePlan()
  ensureDb()
  local prices, priceCount, ownedMap, ownedCount, ownedByChar, snap, owned = buildMaps()

  local storedTargets = (FrugalForgeDB.targets and type(FrugalForgeDB.targets.targets) == "table" and #FrugalForgeDB.targets.targets > 0) and FrugalForgeDB.targets or nil
  local recipes = storedTargets and storedTargets.targets or _G.FrugalScan_RecipeTargets or _G.ProfessionLevelerScan_RecipeTargets
  if type(recipes) ~= "table" or #recipes == 0 then
    local selected = FrugalForgeDB.settings.selectedProfessionId
    if selected then
      local built, err = buildTargetsForProfession(selected, FrugalForgeDB.settings.maxSkillDelta or 100)
      if not built then
        log(tostring(err or "Failed to build targets"))
        return
      end
      FrugalForgeDB.targets = {
        professionId = built.profession.professionId,
        professionName = built.profession.name,
        targets = built.targets,
        reagentIds = built.reagentIds,
      }
      applyTargetsSafe(built)
      recipes = built.targets
    else
      log("No recipe targets found. Choose a profession and build targets.")
      return
    end
  end

  debugLog("recipes loaded=" .. tostring(type(recipes) == "table" and #recipes or 0))
  local activeTargetProfession = (storedTargets and storedTargets.professionName) or _G.FrugalScan_TargetProfessionName or _G.ProfessionLevelerScan_TargetProfessionName
  local snapProfession = snap and snap.targetProfessionName or nil
  local targetProfessionName = activeTargetProfession or snapProfession
  local known, rank, maxRank = hasProfession(targetProfessionName)
  local profWarning = nil
  if targetProfessionName and not known then
    profWarning = string.format("Targets are for %s but this character does not know it. Planning from skill 1.", targetProfessionName)
  end

  local stepLines = {}
  local shopping = {}
  local recipeNeeds = {}
  local recipeNeedList = {}
  local intermediatesAll = {}
  local intermediatesFirstNeedSkill = {}
  local totalCost = 0
  local missingPriceItems = {}
  local reagentKinds = {}
  local pricedKinds = {}

  local useIntermediates = (FrugalForgeDB.settings.useCraftIntermediates ~= false)
  local ignoreOwnedSelection = (FrugalForgeDB.settings.ignoreOwnedSelection == true)
  local ownedValueFactor = tonumber(FrugalForgeDB.settings.ownedValueFactor)
  if not ownedValueFactor then ownedValueFactor = 0.9 end
  if ownedValueFactor < 0 then ownedValueFactor = 0 end
  if ownedValueFactor > 1 then ownedValueFactor = 1 end
  local nonTrainerPenalty = tonumber(FrugalForgeDB.settings.nonTrainerPenalty)
  if not nonTrainerPenalty then nonTrainerPenalty = 1.5 end
  if nonTrainerPenalty < 1 then nonTrainerPenalty = 1 end
  local professionData = targetProfessionName and getProfessionByName(targetProfessionName) or nil
  local recipeByOutput = buildRecipeByOutput(professionData)
  local skillCap = nil
  if targetProfessionName then
    local okSkill, rank = hasProfession(targetProfessionName)
    if okSkill and rank then
      skillCap = rank + (FrugalForgeDB.settings.maxSkillDelta or 100)
    end
  end

  local function addIntermediate(intermediates, itemId, crafts)
    intermediates[itemId] = (intermediates[itemId] or 0) + crafts
  end

  local function expandItem(itemId, qty, visited, leaf, intermediates)
    if not itemId or qty <= 0 then return end
    if not useIntermediates then
      leaf[itemId] = (leaf[itemId] or 0) + qty
      return
    end
    local recipe = recipeByOutput[itemId]
    if not recipe or (skillCap and recipe.minSkill and recipe.minSkill > skillCap) then
      leaf[itemId] = (leaf[itemId] or 0) + qty
      return
    end
    if visited[itemId] then
      leaf[itemId] = (leaf[itemId] or 0) + qty
      return
    end
    local outputQty = recipe.createsQuantity or 1
    if outputQty <= 0 then outputQty = 1 end
    local crafts = math.ceil(qty / outputQty)
    addIntermediate(intermediates, itemId, crafts)
    visited[itemId] = true
    local regs = recipe.reagentsWithQty or recipe.reagents or {}
    for _, reg in ipairs(regs) do
      local regId
      local regQty = 1
      if type(reg) == "table" then
        regId = tonumber(reg.itemId or reg.id or reg[1])
        regQty = reg.qty or reg.quantity or 1
      else
        regId = tonumber(reg)
      end
      expandItem(regId, regQty * crafts, visited, leaf, intermediates)
    end
    visited[itemId] = nil
  end

  local currentSkill = nil
  if targetProfessionName and not profWarning then
    currentSkill = select(1, getProfessionSkillByName(targetProfessionName))
  end
  if not currentSkill then currentSkill = 1 end
  local targetSkill = currentSkill + (FrugalForgeDB.settings.maxSkillDelta or 100)

  local function chanceForSkill(skill, r)
    local orange = r.orangeUntil or r.minSkill or 0
    local yellow = r.yellowUntil or orange
    local green = r.greenUntil or yellow
    local gray = r.grayAt or green
    if skill < orange then return 1 end
    if skill < yellow then return 0.75 end
    if skill < green then return 0.25 end
    if skill < gray then return 0.1 end
    return 0
  end

  local function estimateCostForCrafts(info, crafts, ownedRemaining)
    local cost = 0
    local missing = 0
    if info.requiresRecipe then
      missing = missing + 1
    end
    for itemId, qty in pairs(info.leaf) do
      local need = qty * crafts
      local ownedQty = (ignoreOwnedSelection and 0) or (ownedRemaining[itemId] or 0)
      local useOwned = math.min(need, ownedQty)
      local buy = need - useOwned
      local price = prices[itemId]
      if price then
        cost = cost + (price * buy) + (price * useOwned * ownedValueFactor)
      else
        missing = missing + 1
      end
    end
    if info.requiresRecipe then
      cost = cost * nonTrainerPenalty
    end
    return cost, missing
  end

  local function consumeOwnedForCrafts(info, crafts, ownedRemaining)
    if ignoreOwnedSelection then return end
    for itemId, qty in pairs(info.leaf) do
      local need = qty * crafts
      local ownedQty = ownedRemaining[itemId] or 0
      local useOwned = math.min(need, ownedQty)
      if useOwned > 0 then
        ownedRemaining[itemId] = ownedQty - useOwned
      end
    end
  end

  local recipeInfos = {}

  local function logTopCandidates(skill)
    if not (FrugalForgeDB.settings and FrugalForgeDB.settings.debug) then return end
    local candidates = {}
    for _, info in ipairs(recipeInfos) do
      if skill >= info.minSkill and skill < info.grayAt then
        local p = chanceForSkill(skill, info.recipe)
        if p > 0 then
          local crafts = 1 / p
          local cost, missing = estimateCostForCrafts(info, crafts, ownedMap)
          local score = (missing > 0) and 1e18 or cost
          table.insert(candidates, { info = info, score = score, cost = cost, missing = missing, p = p, crafts = crafts })
        end
      end
    end
    table.sort(candidates, function(a, b)
      if a.missing == b.missing then return a.score < b.score end
      return a.missing < b.missing
    end)
    local lines = {}
    table.insert(lines, "Top candidates for skill " .. tostring(skill) .. ":")
    for i = 1, math.min(5, #candidates) do
      local c = candidates[i]
      table.insert(lines, string.format("  #%d %s (p=%.2f, crafts~%.1f, cost=%s, missing=%d)",
        i,
        c.info.name or c.info.recipeId or "recipe",
        c.p,
        c.crafts,
        copperToText(math.floor(c.cost + 0.5)),
        c.missing))
    end
    if #candidates > 0 then
      local top = candidates[1]
      table.insert(lines, "  Top reagents:")
      for itemId, qty in pairs(top.info.leaf or {}) do
        local ownedQty = ownedMap[itemId] or 0
        local price = prices[itemId]
        table.insert(lines, string.format("    - %s (%d): qty %s, owned %s, price %s",
          getItemName(itemId), itemId, tostring(qty), tostring(ownedQty), tostring(price)))
      end
    end
    if #candidates == 0 then
      table.insert(lines, "  (no candidates in current skill window)")
    end
    FrugalForgeDB.lastCandidateDebugLines = lines
  end

  for _, r in ipairs(recipes) do
    if type(r) == "table" then
      if r.cooldownSeconds and r.cooldownSeconds > 0 then
        -- skip cooldown recipes
      else
      local reagents = nil
      if type(r.reagentsWithQty) == "table" and #r.reagentsWithQty > 0 then
        reagents = r.reagentsWithQty
      elseif type(r.reagents) == "table" and #r.reagents > 0 and type(r.reagents[1]) == "table" then
        reagents = r.reagents
      elseif type(r.reagents) == "table" then
        reagents = {}
        for _, itemId in ipairs(r.reagents) do
          table.insert(reagents, { itemId = itemId, qty = 1 })
        end
      end
      if not reagents then
        -- skip
      else

      local leaf = {}
      local inter = {}
      local visited = {}
      for _, entry in ipairs(reagents) do
        local itemId = tonumber(entry.itemId or entry.id or entry[1])
        local qty = entry.qty or entry.quantity or 1
        if itemId and qty and qty > 0 then
          expandItem(itemId, qty, visited, leaf, inter)
        end
      end

      local costPerCraft = 0
      local missing = 0
      if r.requiresRecipe then
        missing = missing + 1
      end
      for itemId, qty in pairs(leaf) do
        local price = prices[itemId]
        local ownedQty = ownedMap[itemId] or 0
        if price then
          local ownedUse = math.min(qty, ownedQty)
          costPerCraft = costPerCraft + (price * (qty - ownedUse))
        else
          if ownedQty < qty then
            missing = missing + 1
          end
        end
      end

      table.insert(recipeInfos, {
        recipe = r,
        minSkill = r.minSkill or 0,
        grayAt = r.grayAt or (r.greenUntil or r.yellowUntil or r.minSkill or 0),
        name = r.name or r.recipeId or "recipe",
        outputItemId = r.createsItemId,
        leaf = leaf,
        inter = inter,
        costPerCraft = costPerCraft,
        missing = missing,
        requiresRecipe = r.requiresRecipe == true,
      })
      end
    end
    end
  end

  if #recipeInfos == 0 then
    if FrugalForgeDB.settings and FrugalForgeDB.settings.debug then
      FrugalForgeDB.lastCandidateDebugLines = { "Top candidates unavailable (no recipes)" }
    end
    local msg = "No viable recipes found for the selected skill range. Try increasing Skill + or building targets."
    FrugalForgeDB.lastPlan = {
      generatedAt = ts(),
      generatedAtEpochUtc = time(),
      snapshotTimestampUtc = snap and snap.snapshotTimestampUtc or nil,
      ownedTimestampUtc = owned and owned.snapshotTimestampUtc or nil,
      staleWarning = msg,
      stepsText = "",
      shoppingText = "",
      summaryText = msg,
    }
    updateUi()
    return
  end

  local missingForPlan = {}
  for _, info in ipairs(recipeInfos) do
    for itemId in pairs(info.leaf or {}) do
      if not prices[itemId] then
        missingForPlan[itemId] = true
      end
    end
  end
  local missingForPlanCount = 0
  for _ in pairs(missingForPlan) do missingForPlanCount = missingForPlanCount + 1 end
  if missingForPlanCount > 0 then
    local missingIds = {}
    for itemId in pairs(missingForPlan) do
      table.insert(missingIds, itemId)
    end
    local msg = string.format("Pricing data missing for %d item(s). Run an AH scan (or Scan Missing) before generating a plan.", missingForPlanCount)
    FrugalForgeDB.lastPlan = {
      generatedAt = ts(),
      generatedAtEpochUtc = time(),
      snapshotTimestampUtc = snap and snap.snapshotTimestampUtc or nil,
      ownedTimestampUtc = owned and owned.snapshotTimestampUtc or nil,
      staleWarning = msg,
      stepsText = "",
      shoppingText = "",
      summaryText = msg,
      missingPriceItemIds = missingIds,
    }
    updateUi()
    return
  end

  if FrugalForgeDB.settings and FrugalForgeDB.settings.debug then
    logTopCandidates(currentSkill)
    if type(FrugalForgeDB.lastCandidateDebugLines) ~= "table" then
      FrugalForgeDB.lastCandidateDebugLines = { "Top candidates unavailable (no data)" }
    end
  end

  local ownedRemainingSelection = {}
  for itemId, qty in pairs(ownedMap) do ownedRemainingSelection[itemId] = qty end
  local chosenBySkill = {}
  for skill = currentSkill, targetSkill - 1 do
    local best = nil
    for _, info in ipairs(recipeInfos) do
      if skill >= info.minSkill and skill < info.grayAt then
        local p = chanceForSkill(skill, info.recipe)
        if p > 0 then
          local crafts = 1 / p
          local cost, missing = estimateCostForCrafts(info, crafts, ownedRemainingSelection)
          if not best or missing < best.missing or (missing == best.missing and cost < best.expectedCost) then
            best = { info = info, p = p, crafts = crafts, expectedCost = cost, missing = missing }
          end
        end
      end
    end
    if not best then break end
    chosenBySkill[skill] = best
    consumeOwnedForCrafts(best.info, best.crafts, ownedRemainingSelection)
  end

  local ranges = {}
  local current = nil
  for skill = currentSkill, targetSkill - 1 do
    local choice = chosenBySkill[skill]
    if not choice then break end
    if not current or current.info ~= choice.info then
      if current then table.insert(ranges, current) end
      current = { info = choice.info, startSkill = skill, endSkill = skill, crafts = 0, expectedCost = 0 }
    else
      current.endSkill = skill
    end
    current.crafts = current.crafts + (choice.crafts or (1 / choice.p))
    current.expectedCost = current.expectedCost + (choice.expectedCost or (choice.info.costPerCraft / choice.p))
  end
  if current then table.insert(ranges, current) end

  local craftsByOutput = {}
  for _, r in ipairs(ranges) do
    local outputId = r.info.outputItemId
    if outputId then
      craftsByOutput[outputId] = (craftsByOutput[outputId] or 0) + r.crafts
    end
  end

  for _, r in ipairs(ranges) do
    for itemId, crafts in pairs(r.info.inter) do
      intermediatesAll[itemId] = (intermediatesAll[itemId] or 0) + crafts * r.crafts
      local needAt = intermediatesFirstNeedSkill[itemId]
      if not needAt or r.startSkill < needAt then
        intermediatesFirstNeedSkill[itemId] = r.startSkill
      end
    end
  end

  local stepEntries = {}
  local ownedForSteps = {}
  for itemId, qty in pairs(ownedMap) do ownedForSteps[itemId] = qty end
  for _, r in ipairs(ranges) do
    local displayStart = r.startSkill
    local displayEnd = r.endSkill + 1
    local skillText = string.format(" (skill %d-%d)", displayStart, displayEnd)
    local craftCount = math.ceil(r.crafts or 0)
    local rangeCost = 0
    local rangeMissing = 0
    if r.info.requiresRecipe then
      recipeNeeds[r.info.recipe.recipeId or r.info.name or "recipe"] = r.info
    end
    for itemId, qty in pairs(r.info.leaf) do
      local need = qty * r.crafts
      local ownedQty = ownedForSteps[itemId] or 0
      local useOwned = math.min(need, ownedQty)
      if useOwned > 0 then
        ownedForSteps[itemId] = ownedQty - useOwned
      end
      local buy = need - useOwned
      if buy > 0 then
        local price = prices[itemId]
        if price then
          rangeCost = rangeCost + (price * buy)
        else
          rangeMissing = rangeMissing + 1
        end
      end
    end
    local costText = copperToText(math.floor(rangeCost + 0.5))
    if rangeMissing > 0 then
      costText = costText .. " (missing prices)"
    end
    local recipeTag = r.info.requiresRecipe and " (recipe required)" or ""
    table.insert(stepEntries, { startSkill = displayStart, endSkill = displayEnd, text = string.format("- %s%s%s: cost %s (craft ~%d)",
      r.info.name,
      skillText,
      recipeTag,
      costText,
      craftCount) })
  end

  local ownedRemaining = {}
  for itemId, qty in pairs(ownedMap) do ownedRemaining[itemId] = qty end

  for _, r in ipairs(ranges) do
    for itemId, qty in pairs(r.info.leaf) do
      local need = qty * r.crafts
      local ownedQty = ownedRemaining[itemId] or 0
      local useOwned = math.min(need, ownedQty)
      if useOwned > 0 then
        ownedRemaining[itemId] = ownedQty - useOwned
      end
      local buy = need - useOwned
      if buy > 0 then
        local price = prices[itemId]
        if price then
          pricedKinds[itemId] = true
          totalCost = totalCost + (price * buy)
        else
          missingPriceItems[itemId] = true
        end
        shopping[itemId] = shopping[itemId] or { need = 0, owned = 0, price = price }
        shopping[itemId].need = shopping[itemId].need + need
        shopping[itemId].owned = shopping[itemId].owned + useOwned
      end
      reagentKinds[itemId] = true
    end
  end

  local extraLines = {}
  for itemId, crafts in pairs(intermediatesAll) do
    local skillCrafts = craftsByOutput[itemId] or 0
    local extra = crafts - skillCrafts
    if extra > 0.01 then
      local recipe = recipeByOutput[itemId]
      local outputQty = (recipe and recipe.createsQuantity) or 1
      if outputQty <= 0 then outputQty = 1 end
      local qtyNeeded = math.ceil(extra * outputQty)
      local ownedQty = ownedMap[itemId] or 0
      if qtyNeeded > ownedQty then
        local totalNeeded = qtyNeeded
        local needSkill = intermediatesFirstNeedSkill[itemId] or (recipe and recipe.minSkill) or 0
        table.insert(extraLines, {
          sortKey = needSkill,
          text = string.format("- Craft until you have %d %s (%d) (have %d)", totalNeeded, getItemName(itemId), itemId, ownedQty)
        })
      end
    end
  end
  table.sort(extraLines, function(a, b)
    if a.sortKey == b.sortKey then return a.text < b.text end
    return a.sortKey < b.sortKey
  end)

  local mergedSteps = {}
  local iExtra = 1
  for _, step in ipairs(stepEntries) do
    while iExtra <= #extraLines and extraLines[iExtra].sortKey <= step.endSkill do
      table.insert(mergedSteps, extraLines[iExtra].text)
      iExtra = iExtra + 1
    end
    table.insert(mergedSteps, step.text)
  end
  while iExtra <= #extraLines do
    table.insert(mergedSteps, extraLines[iExtra].text)
    iExtra = iExtra + 1
  end
  stepLines = mergedSteps

  local shoppingLines = { "Shopping list:" }
  local missingCount = 0
  local shoppingList = {}
  for itemId, entry in pairs(shopping) do
    table.insert(shoppingList, { itemId = itemId, entry = entry })
  end
  table.sort(shoppingList, function(a, b)
    return tostring(getItemName(a.itemId)) < tostring(getItemName(b.itemId))
  end)
  for _, row in ipairs(shoppingList) do
    local itemId = row.itemId
    local entry = row.entry
    local buy = math.max(0, entry.need - entry.owned)
    local ownedBreakdown = ""
    local chars = ownedByChar[itemId]
    if chars then
      local parts = {}
      for name, qty in pairs(chars) do
        table.insert(parts, string.format("%s:%d", name, qty))
      end
      table.sort(parts)
      ownedBreakdown = " [" .. table.concat(parts, ", ") .. "]"
    end

    local priceText = entry.price and copperToText(entry.price) or "missing price"
    local totalText = entry.price and copperToText(entry.price * buy) or "?"
    local missingTag = entry.price and "" or " (missing price)"
    local line = string.format("  - %s (%d): need %d (owned %d%s), buy %d @ %s = %s%s",
      getItemName(itemId), itemId, entry.need, entry.owned, ownedBreakdown, buy, priceText, totalText, missingTag)
    table.insert(shoppingLines, line)
  end
  for _, info in pairs(recipeNeeds) do
    table.insert(recipeNeedList, info)
  end
  table.sort(recipeNeedList, function(a, b)
    return tostring(a.name or a.recipeId) < tostring(b.name or b.recipeId)
  end)
  if #recipeNeedList > 0 then
    table.insert(shoppingLines, "Recipes needed:")
    for _, info in ipairs(recipeNeedList) do
      table.insert(shoppingLines, string.format("  - Recipe: %s (not trainer learned; vendor/AH/quest)", info.name or info.recipeId or "recipe"))
    end
  end
  for _ in pairs(missingPriceItems) do missingCount = missingCount + 1 end

  local summaryLines = {}
  local snapCount = 0
  if snap and type(snap.prices) == "table" then snapCount = #snap.prices end
  local reagentCount = 0
  for _ in pairs(reagentKinds) do reagentCount = reagentCount + 1 end
  local pricedOverlap = 0
  for itemId in pairs(reagentKinds) do
    if prices[itemId] then pricedOverlap = pricedOverlap + 1 end
  end
  table.insert(summaryLines, string.format("Snapshot priced items: %d", snapCount))
  table.insert(summaryLines, string.format("Targets: %d recipes, %d reagents", #recipes, reagentCount))
  table.insert(summaryLines, string.format("Targets with prices: %d", pricedOverlap))
  local targetIdsCount = type(_G.FrugalScan_TargetItemIds) == "table" and #_G.FrugalScan_TargetItemIds or 0
  table.insert(summaryLines, string.format("Target itemIds: %d", targetIdsCount))
  table.insert(summaryLines, string.format("Total cost (priced items): %s", copperToText(totalCost)))
  local totalKinds = 0
  for _ in pairs(reagentKinds) do totalKinds = totalKinds + 1 end
  local pricedKindCount = 0
  for _ in pairs(pricedKinds) do pricedKindCount = pricedKindCount + 1 end
  local coverage = totalKinds > 0 and math.floor((pricedKindCount / totalKinds) * 100) or 0
  table.insert(summaryLines, string.format("Price coverage: %d%% (%d/%d reagents with prices)", coverage, pricedKindCount, totalKinds))
  table.insert(summaryLines, string.format("Owned items counted: %d unique", ownedCount or 0))
  if missingCount > 0 then
    table.insert(summaryLines, string.format("Missing prices for %d item(s); those steps are marked accordingly.", missingCount))
  end
  if #recipeNeedList > 0 then
    table.insert(summaryLines, string.format("Recipes needed: %d (see shopping list)", #recipeNeedList))
  end
  if snapCount == 0 then
    table.insert(summaryLines, "No prices found in snapshot. Run a scan at the AH.")
  end
  if targetProfessionName then
    table.insert(summaryLines, "Targets profession: " .. tostring(targetProfessionName))
    if known and rank and maxRank then
      table.insert(summaryLines, string.format("Your skill: %d/%d", rank, maxRank))
    end
    if profWarning then
      table.insert(summaryLines, profWarning)
    end
  end
  local warnStaleHours = FrugalForgeDB.settings.warnStaleHours or 12
  local ageHours = hoursSince(getSnapshotEpoch(snap))
  local staleWarn = (ageHours and warnStaleHours and ageHours > warnStaleHours) and
    string.format("Snapshot is stale: %.1f hours old (threshold %d).", ageHours, warnStaleHours) or nil
  if staleWarn then table.insert(summaryLines, staleWarn) end

  local ownedEpoch = owned and getSnapshotEpoch(owned) or nil
  if ownedEpoch and FrugalForgeDB.targetsBuiltAtEpoch and ownedEpoch < FrugalForgeDB.targetsBuiltAtEpoch then
    table.insert(summaryLines, "Owned snapshot is older than current targets. Run /frugal owned to refresh.")
  end

  FrugalForgeDB.lastPlan = {
    generatedAt = ts(),
    generatedAtEpochUtc = time(),
    snapshotTimestampUtc = snap and snap.snapshotTimestampUtc or nil,
    ownedTimestampUtc = owned and owned.snapshotTimestampUtc or nil,
    totalCostCopper = totalCost,
    missingPriceItemCount = missingCount,
    coveragePercent = coverage,
    reagentKinds = totalKinds,
    pricedKinds = pricedKindCount,
    staleWarning = staleWarn,
    stepsText = table.concat(stepLines, "\n"),
    shoppingText = table.concat(shoppingLines, "\n"),
    summaryText = table.concat(summaryLines, "\n"),
    missingPriceItemIds = (function()
      local ids = {}
      for itemId in pairs(missingPriceItems) do table.insert(ids, itemId) end
      table.sort(ids)
      return ids
    end)(),
  }

  -- keep quiet; no chat spam on plan updates
  updateUi()
end

local function createUi()
  if ui.frame then return end

  local f = CreateFrame("Frame", "FrugalForgeFrame", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(740, 720)
  f:SetPoint("CENTER")
  f:Hide()
  f:SetMovable(true)
  f:EnableMouse(true)
  f:EnableKeyboard(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then
      self:Hide()
      self:SetPropagateKeyboardInput(false)
    else
      self:SetPropagateKeyboardInput(true)
    end
  end)

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.title:SetPoint("TOP", 0, -8)
  local version = "?"
  local function readVersion()
    local name = ADDON_NAME or "FrugalForge"
    if C_AddOns and C_AddOns.GetAddOnMetadata then
      return C_AddOns.GetAddOnMetadata(name, "Version") or C_AddOns.GetAddOnMetadata("FrugalForge", "Version")
    end
    if GetAddOnMetadata then
      return GetAddOnMetadata(name, "Version") or GetAddOnMetadata("FrugalForge", "Version")
    end
    if GetAddOnInfo then
      local _, _, _, ver = GetAddOnInfo(name)
      if not ver or ver == "" then
        _, _, _, ver = GetAddOnInfo("FrugalForge")
      end
      return ver
    end
    return nil
  end
  version = readVersion() or "?"
  f.title:SetText("FrugalForge v" .. tostring(version))

  local y = -32
  local labels = {
    { "snapshotLabel", "Snapshot", "snapshotValue" },
    { "ownedLabel", "Owned", "ownedValue" },
    { "planLabel", "Plan", "planValue" },
    { "scanLabel", "Scan", "scanValue" },
  }

  for _, row in ipairs(labels) do
    local lblName, lblText, valName = row[1], row[2], row[3]
    ui[lblName] = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui[lblName]:SetPoint("TOPLEFT", 16, y)
    ui[lblName]:SetText(lblText .. ":")

    ui[valName] = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui[valName]:SetPoint("TOPLEFT", 140, y)
    ui[valName]:SetText("...")

    y = y - 20
  end

  ui.profLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ui.profLabel:SetPoint("TOPLEFT", 16, y - 4)
  ui.profLabel:SetText("Profession:")

  ui.profDrop = CreateFrame("Frame", "FrugalForgeProfessionDropDown", f, "UIDropDownMenuTemplate")
  ui.profDrop:SetPoint("TOPLEFT", 110, y - 4)

  ui.deltaLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ui.deltaLabel:SetPoint("TOPLEFT", 320, y - 4)
  ui.deltaLabel:SetText("Skill +")

  ui.deltaBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  ui.deltaBox:SetSize(40, 20)
  ui.deltaBox:SetPoint("TOPLEFT", 375, y - 2)
  ui.deltaBox:SetAutoFocus(false)
  ui.deltaBox:SetNumeric(true)
  ui.deltaBox:SetText(tostring(FrugalForgeDB.settings.maxSkillDelta or 100))

  ui.buildTargetsBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  ui.buildTargetsBtn:SetSize(120, 22)
  ui.buildTargetsBtn:SetPoint("TOPLEFT", 430, y - 10)
  ui.buildTargetsBtn:SetText("Build Targets")
  ui.buildTargetsBtn:SetScript("OnClick", function()
    buildTargetsFromUi()
  end)

  ui.scanBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  ui.scanBtn:SetSize(80, 22)
  ui.scanBtn:SetPoint("TOPLEFT", 16, y - 32)
  ui.scanBtn:SetText("Scan AH")
  ui.scanBtn:SetScript("OnClick", function()
    if FrugalScanDB and FrugalScanDB.settings then
      FrugalScanDB.settings.maxSkillDelta = FrugalForgeDB.settings.maxSkillDelta or 100
    end
    local scanTargets = FrugalForgeDB.scanTargets or FrugalForgeDB.targets
    if scanTargets and type(scanTargets.reagentIds) == "table" then
      FrugalScan_TargetItemIds = scanTargets.reagentIds
      ProfessionLevelerScan_TargetItemIds = scanTargets.reagentIds
    end
    if type(SlashCmdList) == "table" and SlashCmdList["FRUGALSCAN"] then
      SlashCmdList["FRUGALSCAN"]("start")
    else
      log("Scanner not loaded.")
    end
  end)

  ui.scanMissingBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  ui.scanMissingBtn:SetSize(100, 22)
  ui.scanMissingBtn:SetPoint("LEFT", ui.scanBtn, "RIGHT", 8, 0)
  ui.scanMissingBtn:SetText("Scan Missing")
  ui.scanMissingBtn:SetScript("OnClick", function()
    local ids = {}
    local missing = FrugalForgeDB.lastPlan and FrugalForgeDB.lastPlan.missingPriceItemIds or nil
    if type(missing) == "table" and #missing > 0 then
      for _, itemId in ipairs(missing) do
        local n = tonumber(itemId)
        if n and n > 0 and isQualityAtMost(n, QUALITY_UNCOMMON) then
          table.insert(ids, n)
        end
      end
    else
      local scanTargets = FrugalForgeDB.scanTargets or FrugalForgeDB.targets
      if scanTargets and type(scanTargets.reagentIds) == "table" then
        local prices = buildPriceMap()
        for _, itemId in ipairs(scanTargets.reagentIds) do
          local n = tonumber(itemId)
          if n and n > 0 and not prices[n] and isQualityAtMost(n, QUALITY_UNCOMMON) then
            table.insert(ids, n)
          end
        end
      end
    end
    if #ids == 0 then
      log("No missing-price items to scan (filtered by rarity).")
      return
    end
    FrugalScan_TargetItemIds = ids
    ProfessionLevelerScan_TargetItemIds = ids
    FrugalScan_ForceTargetItemIds = true
    log("Scanning missing prices (" .. tostring(#ids) .. " items)...")
    if type(SlashCmdList) == "table" and SlashCmdList["FRUGALSCAN"] then
      SlashCmdList["FRUGALSCAN"]("start")
    else
      log("Scanner not loaded.")
    end
  end)

  ui.ownedBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  ui.ownedBtn:SetSize(80, 22)
  ui.ownedBtn:SetPoint("LEFT", ui.scanMissingBtn, "RIGHT", 8, 0)
  ui.ownedBtn:SetText("Owned")
  ui.ownedBtn:SetScript("OnClick", function()
    if type(SlashCmdList) == "table" and SlashCmdList["FRUGALSCAN"] then
      SlashCmdList["FRUGALSCAN"]("owned")
      updateUi()
    else
      log("Scanner not loaded.")
    end
  end)

  ui.generateBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  ui.generateBtn:SetSize(140, 22)
  ui.generateBtn:SetPoint("LEFT", ui.ownedBtn, "RIGHT", 8, 0)
  ui.generateBtn:SetText("Generate Plan")
  ui.generateBtn:SetScript("OnClick", generatePlan)

  ui.ignoreOwnedCheck = CreateFrame("CheckButton", "FrugalForgeIgnoreOwnedCheck", f, "UICheckButtonTemplate")
  ui.ignoreOwnedCheck:ClearAllPoints()
  ui.ignoreOwnedCheck:SetPoint("TOPLEFT", 500, -40)
  ui.ignoreOwnedCheck.text:SetText("Ignore owned mats for selection")
  ui.ignoreOwnedCheck:SetChecked(FrugalForgeDB.settings.ignoreOwnedSelection == true)
  ui.ignoreOwnedCheck:SetScript("OnClick", function(btn)
    FrugalForgeDB.settings.ignoreOwnedSelection = btn:GetChecked() and true or false
    generatePlan()
  end)

  ui.currentCharOnlyCheck = CreateFrame("CheckButton", "FrugalForgeCurrentCharOnlyCheck", f, "UICheckButtonTemplate")
  ui.currentCharOnlyCheck:ClearAllPoints()
  ui.currentCharOnlyCheck:SetPoint("TOPLEFT", ui.ignoreOwnedCheck, "BOTTOMLEFT", 0, -4)
  ui.currentCharOnlyCheck.text:SetText("Use current character only")
  ui.currentCharOnlyCheck:SetChecked(FrugalForgeDB.settings.currentCharOnlySelection == true)
  ui.currentCharOnlyCheck:SetScript("OnClick", function(btn)
    FrugalForgeDB.settings.currentCharOnlySelection = btn:GetChecked() and true or false
    generatePlan()
  end)

  ui.ownedFactorLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ui.ownedFactorLabel:ClearAllPoints()
  ui.ownedFactorLabel:SetPoint("TOPLEFT", 450, -150)
  ui.ownedFactorLabel:SetText("Owned value factor")

  ui.ownedFactorBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  ui.ownedFactorBox:SetSize(40, 20)
  ui.ownedFactorBox:SetPoint("LEFT", ui.ownedFactorLabel, "RIGHT", 8, 0)
  ui.ownedFactorBox:SetAutoFocus(false)
  ui.ownedFactorBox:SetText(tostring(FrugalForgeDB.settings.ownedValueFactor or 0.9))
  ui.ownedFactorBox:SetScript("OnEnterPressed", function(box)
    local v = tonumber(box:GetText())
    if not v then v = 0.9 end
    if v < 0 then v = 0 end
    if v > 1 then v = 1 end
    FrugalForgeDB.settings.ownedValueFactor = v
    box:SetText(tostring(v))
    generatePlan()
  end)

  ui.closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  ui.closeBtn:SetSize(80, 24)
  ui.closeBtn:SetPoint("TOPRIGHT", -16, y - 32)
  ui.closeBtn:SetText("Close")
  ui.closeBtn:SetScript("OnClick", function() f:Hide() end)

  y = y - 68

  ui.coverageValue = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ui.coverageValue:SetPoint("TOPLEFT", 16, y)
  ui.coverageValue:SetText("Coverage: n/a")

  ui.missingValue = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ui.missingValue:SetPoint("TOPLEFT", 16, y - 16)
  ui.missingValue:SetText("")

  ui.staleValue = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ui.staleValue:SetPoint("TOPLEFT", 16, y - 32)
  ui.staleValue:SetText("")

  ui.summaryLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ui.summaryLabel:SetPoint("TOPLEFT", 16, y - 54)
  ui.summaryLabel:SetText("Summary")

  UIDropDownMenu_Initialize(ui.profDrop, function(self, level)
    local info = UIDropDownMenu_CreateInfo()
    for _, p in ipairs(getProfessionList()) do
      info.text = p.name
      info.checked = (FrugalForgeDB.settings.selectedProfessionId == p.professionId)
      info.func = function()
        FrugalForgeDB.settings.selectedProfessionId = p.professionId
        UIDropDownMenu_SetSelectedID(ui.profDrop, nil)
        UIDropDownMenu_SetText(ui.profDrop, p.name)
        FrugalForgeDB.lastPlan = nil
        updateUi()
        local function regen()
          buildTargetsFromUi()
          generatePlan()
        end
        if C_Timer and C_Timer.After then
          C_Timer.After(0.05, regen)
        else
          regen()
        end
      end
      UIDropDownMenu_AddButton(info, level)
    end
  end)

  local selected = getProfessionById(FrugalForgeDB.settings.selectedProfessionId)
  if selected then
    UIDropDownMenu_SetText(ui.profDrop, selected.name)
  else
    UIDropDownMenu_SetText(ui.profDrop, "Select...")
  end

  -- Steps box
  local stepsScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  stepsScroll:SetPoint("TOPLEFT", 16, y - 74)
  stepsScroll:SetPoint("RIGHT", -36, -8)
  stepsScroll:SetHeight(180)

  local stepsBox = CreateFrame("EditBox", nil, stepsScroll)
  stepsBox:SetMultiLine(true)
  stepsBox:SetFontObject(GameFontHighlightSmall)
  stepsBox:SetWidth(660)
  stepsBox:SetAutoFocus(false)
  stepsBox:SetScript("OnEscapePressed", function() stepsBox:ClearFocus() end)
  stepsScroll:SetScrollChild(stepsBox)
  ui.stepsBox = stepsBox

  -- Shopping box
  local shopScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  shopScroll:SetPoint("TOPLEFT", stepsScroll, "BOTTOMLEFT", 0, -8)
  shopScroll:SetPoint("RIGHT", -36, -8)
  shopScroll:SetHeight(180)

  local shopBox = CreateFrame("EditBox", nil, shopScroll)
  shopBox:SetMultiLine(true)
  shopBox:SetFontObject(GameFontHighlightSmall)
  shopBox:SetWidth(660)
  shopBox:SetAutoFocus(false)
  shopBox:SetScript("OnEscapePressed", function() shopBox:ClearFocus() end)
  shopScroll:SetScrollChild(shopBox)
  ui.shoppingBox = shopBox

  -- Summary box
  local summaryScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  summaryScroll:SetPoint("TOPLEFT", shopScroll, "BOTTOMLEFT", 0, -8)
  summaryScroll:SetPoint("BOTTOMRIGHT", -36, 8)

  local summaryBox = CreateFrame("EditBox", nil, summaryScroll)
  summaryBox:SetMultiLine(true)
  summaryBox:SetFontObject(GameFontHighlightSmall)
  summaryBox:SetWidth(660)
  summaryBox:SetAutoFocus(false)
  summaryBox:SetScript("OnEscapePressed", function() summaryBox:ClearFocus() end)
  summaryScroll:SetScrollChild(summaryBox)
  ui.summaryBox = summaryBox

  ui.frame = f

  -- Dev overlay (grid + cursor coords)
  local overlay = CreateFrame("Frame", nil, f)
  overlay:SetAllPoints(f)
  overlay:SetFrameStrata("TOOLTIP")
  overlay:EnableMouse(false)

  local gridColor = { 0.2, 0.8, 0.9, 0.15 }
  local gridStep = 50
  local w, h = 740, 720
  overlay.lines = {}
  for x = 0, w, gridStep do
    local line = overlay:CreateTexture(nil, "OVERLAY")
    line:SetColorTexture(gridColor[1], gridColor[2], gridColor[3], gridColor[4])
    line:SetPoint("TOPLEFT", f, "TOPLEFT", x, -32)
    line:SetSize(1, h - 40)
    table.insert(overlay.lines, line)
  end
  for yLine = 0, h, gridStep do
    local line = overlay:CreateTexture(nil, "OVERLAY")
    line:SetColorTexture(gridColor[1], gridColor[2], gridColor[3], gridColor[4])
    line:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -32 - yLine)
    line:SetSize(w, 1)
    table.insert(overlay.lines, line)
  end

  local coordText = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  coordText:SetPoint("TOPLEFT", 8, -8)
  coordText:SetText("Dev mode")
  overlay.coordText = coordText

  local devBtn = CreateFrame("Button", nil, overlay, "UIPanelButtonTemplate")
  devBtn:SetSize(120, 22)
  devBtn:SetPoint("TOPRIGHT", -8, -8)
  devBtn:SetText("Show Debug")
  devBtn:SetScript("OnClick", function()
    if type(FrugalForgeDB) ~= "table" then return end
    FrugalForgeDB.settings.debug = true
    FrugalForgeDB.debugLog = {}
    FrugalForgeDB.lastCandidateDebugLines = nil
    generatePlan()
    local snap = latestSnapshot()
    local snapCount = snap and type(snap.prices) == "table" and #snap.prices or 0
    local owned = latestOwned()
    local ownedCount = owned and type(owned.items) == "table" and #owned.items or 0
    local prices, _, ownedMap = buildMaps()
    local essenceOwned = ownedMap and ownedMap[11175] or 0
    local essenceCount = (GetItemCount and GetItemCount(11175, true)) or 0
    local selectedId = FrugalForgeDB.settings.selectedProfessionId
    local selectedProf = selectedId and getProfessionById(selectedId) or nil
    local debugLines = {
      "DEBUG ENABLED",
      "snap.prof=" .. tostring(snap and snap.targetProfessionName or "none"),
      "targets.prof=" .. tostring(_G.FrugalScan_TargetProfessionName or _G.ProfessionLevelerScan_TargetProfessionName or "none"),
      "targets.id=" .. tostring(_G.FrugalScan_TargetProfessionId or _G.ProfessionLevelerScan_TargetProfessionId or "none"),
      "snapshot prices=" .. tostring(snapCount),
      "targetItemIds=" .. tostring(type(_G.FrugalScan_TargetItemIds) == "table" and #_G.FrugalScan_TargetItemIds or 0),
      "owned items=" .. tostring(ownedCount),
      "ownedMap.essence11175=" .. tostring(essenceOwned),
      "GetItemCount(11175)=" .. tostring(essenceCount),
      "selected.profId=" .. tostring(selectedId or "none"),
      "selected.profName=" .. tostring(selectedProf and selectedProf.name or "none"),
      "builtAt=" .. tostring(FrugalForgeDB.targetsBuiltAt or "none"),
      "lastBuildMessage=" .. tostring(FrugalForgeDB.lastBuildMessage or "none"),
      "lastBuildError=" .. tostring(FrugalForgeDB.lastBuildError or "none"),
      "stored.targets.profName=" .. tostring(FrugalForgeDB.targets and FrugalForgeDB.targets.professionName or "none"),
      "stored.targets.profId=" .. tostring(FrugalForgeDB.targets and FrugalForgeDB.targets.professionId or "none"),
      "stored.targets.recipes=" .. tostring(FrugalForgeDB.targets and type(FrugalForgeDB.targets.targets) == "table" and #FrugalForgeDB.targets.targets or 0),
    }
    local log = FrugalForgeDB.debugLog or {}
    if #log > 0 then
      table.insert(debugLines, "")
      table.insert(debugLines, "Debug Log:")
      for _, line in ipairs(log) do
        table.insert(debugLines, line)
      end
    end
    local cand = FrugalForgeDB.lastCandidateDebugLines
    if type(cand) == "table" and #cand > 0 then
      table.insert(debugLines, "")
      for _, line in ipairs(cand) do
        table.insert(debugLines, line)
      end
    end
    showTextFrame(table.concat(debugLines, "\n"), "FrugalForge Debug")
  end)
  overlay.devBtn = devBtn

  overlay:SetScript("OnUpdate", function(self)
    local mx, my = GetCursorPosition()
    local scale = UIParent:GetScale()
    mx, my = mx / scale, my / scale
    local left, top = f:GetLeft() or 0, f:GetTop() or 0
    local relX = math.floor(mx - left)
    local relY = math.floor(top - my)
    local ww, hh = f:GetWidth() or 0, f:GetHeight() or 0
    self.coordText:SetText(string.format("UI: %.0f,%.0f  Frame: %d,%d  Size: %dx%d",
      mx, my, relX, relY, ww, hh))
  end)

  overlay:Hide()
  ui.devOverlay = overlay
end

local function toggleUi()
  createUi()
  if ui.frame:IsShown() then
    ui.frame:Hide()
  else
    updateUi()
    if ui.devOverlay then
      if FrugalForgeDB.settings and FrugalForgeDB.settings.devMode then
        ui.devOverlay:Show()
      else
        ui.devOverlay:Hide()
      end
    end
    ui.frame:Show()
  end
end


local function createMinimapButton()
  if ui.minimapBtn or not Minimap then return end
  ensureDb()

  local btn = CreateFrame("Button", "FrugalForgeMinimapButton", Minimap)
  btn:SetSize(32, 32)
  btn:SetFrameStrata("MEDIUM")
  btn:SetFrameLevel(8)
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:RegisterForDrag("LeftButton")

  local icon = btn:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Gem_01")
  icon:SetAllPoints()
  btn.icon = icon

  btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local function position()
    local angle = (FrugalForgeDB.settings and FrugalForgeDB.settings.minimapAngle) or 45
    local rad = (math.rad and math.rad(angle)) or (angle * math.pi / 180)
    local radius = 80
    local x = math.cos(rad) * radius
    local y = math.sin(rad) * radius
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
  end

  btn:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      return
    end
    if IsControlKeyDown and IsControlKeyDown() then
      if type(SlashCmdList) == "table" and SlashCmdList["FRUGALSCAN"] then
        SlashCmdList["FRUGALSCAN"]("start")
      else
        DEFAULT_CHAT_FRAME:AddMessage("|cff7dd3fcFrugalForge|r: Scanner not loaded.")
      end
      return
    end
    toggleUi()
  end)

  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("FrugalForge", 1, 0.82, 0)
    GameTooltip:AddLine("Left click:", 0.7, 0.7, 0.7, false)
    GameTooltip:AddLine("Open FrugalForge window", 1, 1, 1, false)
    GameTooltip:AddLine("Ctrl click:", 0.7, 0.7, 0.7, false)
    GameTooltip:AddLine("Start AH scan for current targets", 1, 1, 1, false)
    GameTooltip:Show()
  end)

  btn:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  btn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local cx, cy = Minimap:GetCenter()
      local mx, my = GetCursorPosition()
      local scale = UIParent:GetScale()
      mx, my = mx / scale, my / scale
      local dx, dy = mx - cx, my - cy
      local angle = (math.atan2 and math.atan2(dy, dx)) or math.atan(dy, dx)
      local deg = angle * (180 / math.pi)
      FrugalForgeDB.settings.minimapAngle = deg
      position()
    end)
  end)

  btn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)

  position()
  ui.minimapBtn = btn
end

SLASH_FRUGALFORGE1 = "/frugal"
SLASH_FRUGALFORGE2 = "/frugalforge"
SlashCmdList["FRUGALFORGE"] = function(msg)
  local cmd = string.lower(tostring(msg or "")):gsub("^%s+", ""):gsub("%s+$", "")
  if cmd == "debug" then
    FrugalForgeDB.settings.debug = true
    FrugalForgeDB.debugLog = {}
    FrugalForgeDB.lastCandidateDebugLines = nil
    generatePlan()
    local snap = latestSnapshot()
    local snapCount = snap and type(snap.prices) == "table" and #snap.prices or 0
    local owned = latestOwned()
    local ownedCount = owned and type(owned.items) == "table" and #owned.items or 0
    local prices, priceCount, ownedMap = buildMaps()
    local essenceOwned = ownedMap and ownedMap[11175] or 0
    local essenceCount = (GetItemCount and GetItemCount(11175, true)) or 0
    local selectedId = FrugalForgeDB.settings.selectedProfessionId
    local selectedProf = selectedId and getProfessionById(selectedId) or nil
    local debugLines = {
      "DEBUG ENABLED",
      "snap.prof=" .. tostring(snap and snap.targetProfessionName or "none"),
      "targets.prof=" .. tostring(_G.FrugalScan_TargetProfessionName or _G.ProfessionLevelerScan_TargetProfessionName or "none"),
      "targets.id=" .. tostring(_G.FrugalScan_TargetProfessionId or _G.ProfessionLevelerScan_TargetProfessionId or "none"),
      "snapshot prices=" .. tostring(snapCount),
      "targetItemIds=" .. tostring(type(_G.FrugalScan_TargetItemIds) == "table" and #_G.FrugalScan_TargetItemIds or 0),
      "owned items=" .. tostring(ownedCount),
      "ownedMap.essence11175=" .. tostring(essenceOwned),
      "GetItemCount(11175)=" .. tostring(essenceCount),
      "selected.profId=" .. tostring(selectedId or "none"),
      "selected.profName=" .. tostring(selectedProf and selectedProf.name or "none"),
      "builtAt=" .. tostring(FrugalForgeDB.targetsBuiltAt or "none"),
      "lastBuildMessage=" .. tostring(FrugalForgeDB.lastBuildMessage or "none"),
      "lastBuildError=" .. tostring(FrugalForgeDB.lastBuildError or "none"),
      "stored.targets.profName=" .. tostring(FrugalForgeDB.targets and FrugalForgeDB.targets.professionName or "none"),
      "stored.targets.profId=" .. tostring(FrugalForgeDB.targets and FrugalForgeDB.targets.professionId or "none"),
      "stored.targets.recipes=" .. tostring(FrugalForgeDB.targets and type(FrugalForgeDB.targets.targets) == "table" and #FrugalForgeDB.targets.targets or 0),
    }
    local log = FrugalForgeDB.debugLog or {}
    if #log > 0 then
      table.insert(debugLines, "")
      table.insert(debugLines, "Debug Log:")
      for _, line in ipairs(log) do
        table.insert(debugLines, line)
      end
    end
    local cand = FrugalForgeDB.lastCandidateDebugLines
    if type(cand) == "table" and #cand > 0 then
      table.insert(debugLines, "")
      for _, line in ipairs(cand) do
        table.insert(debugLines, line)
      end
    end
    local text = table.concat(debugLines, "\n")
    showTextFrame(text, "FrugalForge Debug")
    updateUi()
    return
  end
  if cmd == "dev" or cmd == "devmode" then
    FrugalForgeDB.settings.devMode = not (FrugalForgeDB.settings.devMode == true)
    if ui.devOverlay then
      if FrugalForgeDB.settings.devMode then
        ui.devOverlay:Show()
      else
        ui.devOverlay:Hide()
      end
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff7dd3fcFrugalForge|r: Dev mode = " .. tostring(FrugalForgeDB.settings.devMode))
    return
  end
  if cmd == "build" then
    buildTargetsFromUi()
    return
  end
  if cmd == "scan" or cmd == "start" then
    if type(SlashCmdList) == "table" and SlashCmdList["FRUGALSCAN"] then
      SlashCmdList["FRUGALSCAN"]("start")
      return
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cff7dd3fcFrugalForge|r: Scanner not loaded.")
      return
    end
  elseif cmd == "owned" then
    if type(SlashCmdList) == "table" and SlashCmdList["FRUGALSCAN"] then
      SlashCmdList["FRUGALSCAN"]("owned")
      updateUi()
      return
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cff7dd3fcFrugalForge|r: Scanner not loaded.")
      return
    end
  end
  toggleUi()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, event, addon)
  if event == "ADDON_LOADED" and addon == ADDON_NAME then
    ensureDb()
    createMinimapButton()
    createUi()
    if FrugalForgeDB.targets then
      local t = FrugalForgeDB.targets
      applyTargets({
        profession = { professionId = t.professionId, name = t.professionName },
        targets = t.targets or {},
        reagentIds = t.reagentIds or {},
      })
    end
    updateUi()
    print("|cff7dd3fcFrugalForge|r loaded. Use /frugal to open.")
  end
end)
