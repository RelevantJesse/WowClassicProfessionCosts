local ADDON_NAME = ... or "FrugalForge"

local function ts()
  return date("%Y-%m-%d %H:%M:%S", time())
end

local VENDOR_PRICE_BY_ID = _G.FrugalForgeVendorPrices or {}
local FALLBACK_VENDOR_IDS = {
  [2324] = true, -- Bleach
  [2325] = true, -- Black Dye
  [2604] = true, -- Red Dye
  [2605] = true, -- Green Dye
  [6260] = true, -- Blue Dye
  [6261] = true, -- Orange Dye
  [4342] = true, -- Purple Dye
  [10290] = true, -- Pink Dye
  [2320] = true, -- Coarse Thread
  [2321] = true, -- Fine Thread
  [159] = true, -- Refreshing Spring Water
  [2880] = true, -- Weak Flux
  [4399] = true, -- Wooden Stock
  [4400] = true, -- Heavy Stock
  [4291] = true, -- Silken Thread
  [8343] = true, -- Heavy Silken Thread
  [14341] = true, -- Rune Thread
  [18240] = true, -- Ogre Tannin
}
local function getVendorPrice(itemId)
  if not itemId then return nil end
  local price = VENDOR_PRICE_BY_ID[itemId]
  if price ~= nil then return price end
  if FALLBACK_VENDOR_IDS[itemId] then return 0 end
  return nil
end

local function isVendorItem(itemId)
  if not itemId then return false end
  if getVendorPrice(itemId) ~= nil then return true end
  return FALLBACK_VENDOR_IDS[itemId] == true
end

local PRODUCERS_BY_OUTPUT = nil
local NO_SCAN_REAGENT_IDS = {
  [6218] = true,  -- Runed Copper Rod
  [6339] = true,  -- Runed Silver Rod
  [11130] = true, -- Runed Golden Rod
  [11145] = true, -- Runed Truesilver Rod
  [16207] = true, -- Runed Arcanite Rod
  [22461] = true, -- Runed Fel Iron Rod
  [22462] = true, -- Runed Adamantite Rod
  [22463] = true, -- Runed Eternium Rod
}

local function shouldTrackMissingPrice(itemId)
  return itemId and not NO_SCAN_REAGENT_IDS[itemId]
end

local ENCHANT_SHARD_IDS = {
  [10978] = true, -- Small Glimmering Shard
  [11084] = true, -- Large Glimmering Shard
  [11138] = true, -- Small Glowing Shard
  [11139] = true, -- Large Glowing Shard
  [11177] = true, -- Small Radiant Shard
  [11178] = true, -- Large Radiant Shard
  [14343] = true, -- Small Brilliant Shard
  [14344] = true, -- Large Brilliant Shard
  [22448] = true, -- Small Prismatic Shard
  [22449] = true, -- Large Prismatic Shard
}

local function isEnchantShard(itemId)
  if ENCHANT_SHARD_IDS[itemId] then return true end
  local data = _G.FrugalForgeData_Anniversary
  local name = data and data.items and data.items[itemId]
  if not name and type(GetItemInfo) == "function" then
    name = GetItemInfo(itemId)
  end
  if not name then return false end
  return string.find(name, "Shard", 1, true) ~= nil
end
local function getProducersByOutput()
  if PRODUCERS_BY_OUTPUT then return PRODUCERS_BY_OUTPUT end
  local map = {}
  local data = _G.FrugalForgeProducers
  if type(data) == "table" then
    for _, p in ipairs(data) do
      if type(p) == "table" and p.outputItemId then
        map[p.outputItemId] = map[p.outputItemId] or {}
        table.insert(map[p.outputItemId], p)
      end
    end
  end
  PRODUCERS_BY_OUTPUT = map
  return map
end

local function sanitizeReagentIds(list)
  if type(list) ~= "table" then return list end
  local out = {}
  local seen = {}
  for _, itemId in ipairs(list) do
    local n = tonumber(itemId)
    if n and n > 0 and not isVendorItem(n) and not NO_SCAN_REAGENT_IDS[n] and not seen[n] then
      seen[n] = true
      table.insert(out, n)
    end
  end
  table.sort(out)
  return out
end

local buildRecipeByOutput

local function recipeUsesOgreTannin(recipe)
  if not recipe then return false end
  local regs = recipe.reagentsWithQty or recipe.reagents
  if type(regs) ~= "table" then return false end
  for _, reg in ipairs(regs) do
    local itemId = tonumber((type(reg) == "table" and (reg.itemId or reg.id or reg[1])) or reg)
    if itemId == 18240 then return true end
  end
  return false
end

local function ensureDb()
  FrugalForgeDB = FrugalForgeDB or {}
  FrugalForgeDB.settings = FrugalForgeDB.settings or {
    warnStaleHours = 12,
    priceRank = 3, -- 1=min, 2=median, 3=most recent
    showPanelOnAuctionHouse = true,
    targetSkill = nil,
    selectedProfessionId = nil,
    debug = false,
    useCraftIntermediates = true,
    ignoreOwnedSelection = false,
    currentCharOnlySelection = false,
    ownedValueFactor = 0.9,
    devMode = false,
    minimapAngle = 45,
    minimapHidden = false,
    includeNonTrainerRecipes = true,
  }
  FrugalForgeDB.lastPlan = FrugalForgeDB.lastPlan or nil

  if type(FrugalForgeDB.targets) == "table" and type(FrugalForgeDB.targets.reagentIds) == "table" then
    FrugalForgeDB.targets.reagentIds = sanitizeReagentIds(FrugalForgeDB.targets.reagentIds)
  end
  if type(FrugalForgeDB.scanTargets) == "table" and type(FrugalForgeDB.scanTargets.reagentIds) == "table" then
    FrugalForgeDB.scanTargets.reagentIds = sanitizeReagentIds(FrugalForgeDB.scanTargets.reagentIds)
  end
end

local function purgeRodScanTargets()
  ensureDb()
  local purged = 0
  if type(FrugalForgeDB.targets) == "table" and type(FrugalForgeDB.targets.reagentIds) == "table" then
    local before = #FrugalForgeDB.targets.reagentIds
    FrugalForgeDB.targets.reagentIds = sanitizeReagentIds(FrugalForgeDB.targets.reagentIds)
    purged = purged + (before - #FrugalForgeDB.targets.reagentIds)
  end
  if type(FrugalForgeDB.scanTargets) == "table" and type(FrugalForgeDB.scanTargets.reagentIds) == "table" then
    local before = #FrugalForgeDB.scanTargets.reagentIds
    FrugalForgeDB.scanTargets.reagentIds = sanitizeReagentIds(FrugalForgeDB.scanTargets.reagentIds)
    purged = purged + (before - #FrugalForgeDB.scanTargets.reagentIds)
  end
  if type(FrugalForgeDB.targets) == "table" and type(FrugalForgeDB.targets.reagentIds) == "table" then
    _G.FrugalScan_TargetItemIds = FrugalForgeDB.targets.reagentIds
  end
  DEFAULT_CHAT_FRAME:AddMessage("|cff7dd3fcFrugalForge|r: Purged " .. tostring(purged) .. " rod item(s) from scan targets.")
end


local function latestSnapshot()
  local db = _G.FrugalScanDB
  if type(db) ~= "table" then return nil end
  local snap = db.lastSnapshot
  if type(snap) ~= "table" then return nil end
  return snap
end

local function latestOwned()
  if type(FrugalForgeDB) == "table" and type(FrugalForgeDB.lastOwnedSnapshot) == "table" then
    return FrugalForgeDB.lastOwnedSnapshot
  end
  local db = _G.FrugalScanDB
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
  local status = _G.FrugalScan_ScanStatus
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
  local targetSkill = tonumber(ui.deltaBox and ui.deltaBox:GetText() or "") or FrugalForgeDB.settings.targetSkill
  FrugalForgeDB.settings.targetSkill = targetSkill
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
    return buildTargetsForProfession(selected, targetSkill)
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
  -- removed legacy ProfessionLevelerScan_* globals
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

buildTargetsForProfession = function(professionId, targetSkill)
  local prof = getProfessionById(professionId)
  if not prof then return nil, "Unknown profession" end

  local currentSkill, _ = currentSkillForProfession(prof.name)
  if not currentSkill then currentSkill = 1 end
  local maxSkill = targetSkill or (currentSkill + 100)
  if maxSkill < currentSkill then
    maxSkill = currentSkill + 1
  end
  FrugalForgeDB.settings.targetSkill = maxSkill

  local targets = {}
  local reagentIds = {}
  local seen = {}
  local recipeByOutput = buildRecipeByOutput(prof)
  local producersByOutput = getProducersByOutput()
  local visiting = {}
  local function addReagentId(itemId)
    if itemId and not seen[itemId] and not isVendorItem(itemId) and not NO_SCAN_REAGENT_IDS[itemId] then
      seen[itemId] = true
      table.insert(reagentIds, itemId)
    end
  end
  local function collectIntermediates(itemId)
    if not itemId or visiting[itemId] then return end
    visiting[itemId] = true
    addReagentId(itemId)
    local recipe = recipeByOutput[itemId]
    if recipe then
      local regs = recipe.reagentsWithQty or recipe.reagents or {}
      for _, reg in ipairs(regs) do
        local regId = tonumber((type(reg) == "table" and (reg.itemId or reg.id or reg[1])) or reg)
        if regId then collectIntermediates(regId) end
      end
    end
    local prods = producersByOutput and producersByOutput[itemId]
    if type(prods) == "table" then
      for _, p in ipairs(prods) do
        if type(p) == "table" and type(p.reagents) == "table" then
          for _, reg in ipairs(p.reagents) do
            local regId = tonumber(reg.itemId or reg.id or reg[1])
            if regId then collectIntermediates(regId) end
          end
        end
      end
    end
    visiting[itemId] = nil
  end

    local includeNonTrainer = (FrugalForgeDB.settings.includeNonTrainerRecipes ~= false)
    for _, r in ipairs(prof.recipes or {}) do
      local minSkill = r.minSkill or 0
      local grayAt = r.grayAt or 0
      if minSkill <= maxSkill and grayAt > currentSkill then
        if r.learnedByTrainer == false and not includeNonTrainer then
          -- skip recipes that require a purchased recipe item
        else
        if recipeUsesOgreTannin(r) then
          -- skip ogre tannin recipes
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
            if itemId then
              addReagentId(itemId)
              if FrugalForgeDB.settings.useCraftIntermediates ~= false then
                collectIntermediates(itemId)
              end
            end
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

buildRecipeByOutput = function(profession)
  local map = {}
  if not profession or type(profession.recipes) ~= "table" then return map end
  for _, r in ipairs(profession.recipes) do
    if r and r.createsItemId and not recipeUsesOgreTannin(r) then
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
          if not price then
            price = getVendorPrice(itemId)
          end
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

  local recipeByOutput = buildRecipeByOutput(fullTargets.profession)
  local producersByOutput = getProducersByOutput()
  local reagentIds = {}
  local seen = {}
  local visiting = {}

  local function addScanId(itemId)
    if itemId and not seen[itemId] and not isVendorItem(itemId) and isQualityAtMost(itemId, QUALITY_UNCOMMON) then
      seen[itemId] = true
      table.insert(reagentIds, itemId)
    end
  end

  local function collectIntermediates(itemId)
    if not itemId or visiting[itemId] then return end
    visiting[itemId] = true
    addScanId(itemId)
    local recipe = recipeByOutput[itemId]
    if recipe then
      local regs = recipe.reagentsWithQty or recipe.reagents or {}
      for _, reg in ipairs(regs) do
        local regId = tonumber((type(reg) == "table" and (reg.itemId or reg.id or reg[1])) or reg)
        if regId then
          collectIntermediates(regId)
        end
      end
    end
    local prods = producersByOutput and producersByOutput[itemId]
    if type(prods) == "table" then
      for _, p in ipairs(prods) do
        if type(p) == "table" and type(p.reagents) == "table" then
          for _, reg in ipairs(p.reagents) do
            local regId = tonumber(reg.itemId or reg.id or reg[1])
            if regId then
              collectIntermediates(regId)
            end
          end
        end
      end
    end
    visiting[itemId] = nil
  end

  for _, r in ipairs(selected) do
    for _, reg in ipairs(r.reagents or {}) do
      local itemId = tonumber((type(reg) == "table" and (reg.itemId or reg.id or reg[1])) or reg)
      if itemId then
        addScanId(itemId)
        if FrugalForgeDB.settings.useCraftIntermediates ~= false then
          collectIntermediates(itemId)
        end
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
  FrugalScan_TargetProfessionId = targets.profession.professionId
  FrugalScan_TargetProfessionName = targets.profession.name
  FrugalScan_TargetGameVersion = "Anniversary"
  FrugalScan_RecipeTargets = targets.targets
  FrugalScan_TargetItemIds = targets.reagentIds
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
      local recipes = (FrugalForgeDB.targets and FrugalForgeDB.targets.targets) or _G.FrugalScan_RecipeTargets
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
    -- Ensure we also include outputs and reagents from targets for owned detection
    local recipesForOwned = (FrugalForgeDB.targets and FrugalForgeDB.targets.targets) or _G.FrugalScan_RecipeTargets
    if type(recipesForOwned) == "table" or (owned and type(owned.items) == "table") then
      local seen = {}
      local merged = {}
      if type(ids) == "table" then
        for _, itemId in ipairs(ids) do
          local n = tonumber(itemId)
          if n and n > 0 and not seen[n] then
            seen[n] = true
            table.insert(merged, n)
          end
        end
      end
      if type(recipesForOwned) == "table" then
        for _, r in ipairs(recipesForOwned) do
          if type(r) == "table" then
            local outId = tonumber(r.createsItemId or r.createsItem or r.createsId)
            if outId and not seen[outId] then
              seen[outId] = true
              table.insert(merged, outId)
            end
            local regs = r.reagentsWithQty or r.reagents
            if type(regs) == "table" then
              for _, reg in ipairs(regs) do
                local n = tonumber((type(reg) == "table" and (reg.itemId or reg.id or reg[1])) or reg)
                if n and n > 0 and not seen[n] then
                  seen[n] = true
                  table.insert(merged, n)
                end
              end
            end
          end
        end
      end
      if owned and type(owned.items) == "table" then
        for _, it in ipairs(owned.items) do
          local n = tonumber(it.itemId)
          if n and n > 0 and not seen[n] then
            seen[n] = true
            table.insert(merged, n)
          end
        end
      end
      ids = merged
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
  local recipes = storedTargets and storedTargets.targets or _G.FrugalScan_RecipeTargets
  if type(recipes) ~= "table" or #recipes == 0 then
    local selected = FrugalForgeDB.settings.selectedProfessionId
    if selected then
      local built, err = buildTargetsForProfession(selected, FrugalForgeDB.settings.targetSkill)
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
  local activeTargetProfession = (storedTargets and storedTargets.professionName) or _G.FrugalScan_TargetProfessionName
  local snapProfession = snap and snap.targetProfessionName or nil
  local targetProfessionName = activeTargetProfession or snapProfession
  local known, rank, maxRank = hasProfession(targetProfessionName)
  local profWarning = nil
  if targetProfessionName and not known then
    profWarning = string.format("Targets are for %s but this character does not know it. Planning from skill 1.", targetProfessionName)
  end

  local stepLines = {}
  local materials = {}
  local recipeNeeds = {}
  local recipeNeedList = {}
  local intermediatesAll = {}
  local intermediatesFirstNeedSkill = {}
  local totalCost = 0
  local missingPriceItems = {}
  local reagentKinds = {}
  local pricedKinds = {}
  local ESSENCE_PAIRS = {
    { lesser = 10938, greater = 10939 }, -- Magic
    { lesser = 10998, greater = 11082 }, -- Astral
    { lesser = 11134, greater = 11135 }, -- Mystic
    { lesser = 11174, greater = 11175 }, -- Nether
    { lesser = 16202, greater = 16203 }, -- Eternal
    { lesser = 22447, greater = 22446 }, -- Planar
    { lesser = 34056, greater = 34055 }, -- Cosmic
  }

  local useIntermediates = (FrugalForgeDB.settings.useCraftIntermediates ~= false)
  local ignoreOwnedSelection = (FrugalForgeDB.settings.ignoreOwnedSelection == true)
  local useOwnedForSelection = not ignoreOwnedSelection
  local ownedValueFactor = tonumber(FrugalForgeDB.settings.ownedValueFactor)
  if not ownedValueFactor then ownedValueFactor = 0.9 end
  if ownedValueFactor < 0 then ownedValueFactor = 0 end
  if ownedValueFactor > 1 then ownedValueFactor = 1 end
  local nonTrainerPenalty = tonumber(FrugalForgeDB.settings.nonTrainerPenalty)
  if not nonTrainerPenalty then nonTrainerPenalty = 1.5 end
  if nonTrainerPenalty < 1 then nonTrainerPenalty = 1 end
  local vendorRecipePenalty = 1 + (nonTrainerPenalty - 1) * 0.5
  if vendorRecipePenalty < 1 then vendorRecipePenalty = 1 end
  local vendorRecipeOverrides = {
    [11225] = false,
    [16217] = true,
  }
  local professionData = targetProfessionName and getProfessionByName(targetProfessionName) or nil
  local recipeByOutput = buildRecipeByOutput(professionData)
  local producersByOutput = getProducersByOutput()
  local skillCap = nil
  if targetProfessionName then
    local okSkill, rank = hasProfession(targetProfessionName)
    if okSkill and rank then
      skillCap = FrugalForgeDB.settings.targetSkill or (rank + 100)
    end
  end

  local function addIntermediate(intermediates, itemId, crafts)
    intermediates[itemId] = (intermediates[itemId] or 0) + crafts
  end

  local liveOwnedCache = {}
  local function getLiveOwned(itemId)
    if not itemId then return 0 end
    local cached = liveOwnedCache[itemId]
    if cached ~= nil then return cached end
    local live = 0
    if GetItemCount then
      live = GetItemCount(itemId, true) or 0
    end
    liveOwnedCache[itemId] = live
    return live
  end

  local function getOwnedCount(itemId, mode)
    if not itemId then return 0 end
    if mode == "selection" and ignoreOwnedSelection then
      return 0
    end
    local live = getLiveOwned(itemId)
    if FrugalForgeDB.settings.currentCharOnlySelection then
      return live
    end
    local snapOwned = ownedMap[itemId] or 0
    if mode == "selection" or mode == "shopping" then
      return math.max(live, snapOwned)
    end
    return snapOwned
  end

  local function getRecipeReagents(recipe)
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
    return {}
  end

  local function formatQty(q)
    return string.format("%.1f", q)
  end

  local function resolveRecipeVendorPrice(recipeItemId, explicitPrice)
    if not recipeItemId then return nil end
    local override = vendorRecipeOverrides[recipeItemId]
    if override == false then
      return nil
    end
    if override == true then
      return explicitPrice or getVendorPrice(recipeItemId)
    end
    if isVendorItem(recipeItemId) then
      return explicitPrice or getVendorPrice(recipeItemId)
    end
    return nil
  end

  local function getCraftOptions(itemId)
    local options = {}
    local recipe = recipeByOutput[itemId]
    if recipe and not (skillCap and recipe.minSkill and recipe.minSkill > skillCap) then
      table.insert(options, {
        type = "recipe",
        recipe = recipe,
        outputQty = recipe.createsQuantity or 1,
        reagents = getRecipeReagents(recipe),
      })
    end
    local prods = producersByOutput and producersByOutput[itemId]
    if type(prods) == "table" then
      for _, p in ipairs(prods) do
        if type(p) == "table" then
          table.insert(options, {
            type = "producer",
            producer = p,
            outputQty = p.outputQty or 1,
            reagents = p.reagents or {},
          })
        end
      end
    end
    return options
  end

  local bestCostMemo = {}
  local function computeBestUnitCost(itemId, stack, ownedSnapshot)
    if bestCostMemo[itemId] then
      local cached = bestCostMemo[itemId]
      return cached.cost, cached.missing, cached.option
    end
    if stack[itemId] then
      return nil, 1, nil
    end
    local price = prices[itemId] or getVendorPrice(itemId)
    local bestCost = price
    local bestMissing = price and 0 or 1
    local bestOption = nil

    if useIntermediates then
      stack[itemId] = true
      for _, opt in ipairs(getCraftOptions(itemId)) do
        local outQty = opt.outputQty or 1
        if outQty <= 0 then outQty = 1 end
        local cost = 0
        local missing = 0
        for _, reg in ipairs(opt.reagents or {}) do
          local regId = tonumber(reg.itemId or reg.id or reg[1])
          local regQty = reg.qty or reg.quantity or 1
          if regId then
            local regCost, regMissing = computeBestUnitCost(regId, stack, ownedSnapshot)
            if regCost == nil or (regMissing and regMissing > 0) then
              missing = missing + (regMissing or 1)
            else
              local ownedQty = 0
              if useOwnedForSelection then
                if ownedSnapshot and ownedSnapshot[regId] ~= nil then
                  ownedQty = ownedSnapshot[regId]
                else
                  ownedQty = getOwnedCount(regId, "selection")
                end
              end
              local useOwned = math.min(regQty, ownedQty)
              local buyQty = regQty - useOwned
              cost = cost + (regCost * buyQty) + (regCost * useOwned * ownedValueFactor)
            end
          else
            missing = missing + 1
          end
        end
        if missing == 0 then
          local unitCost = cost / outQty
          if bestCost == nil or unitCost < bestCost then
            bestCost = unitCost
            bestMissing = 0
            bestOption = opt
          end
        end
      end
      stack[itemId] = nil
    end

    bestCostMemo[itemId] = { cost = bestCost, missing = bestMissing, option = bestOption }
    return bestCost, bestMissing, bestOption
  end

  -- Best craft-only unit cost (ignores the direct-buy price when choosing the option).
  -- This is useful when we want a craft option even if buying is cheaper.
  local function computeBestCraftUnitCost(itemId, stack, ownedSnapshot)
    if stack[itemId] then
      return nil, 1, nil
    end

    stack[itemId] = true
    local bestCost = nil
    local bestMissing = 1
    local bestOption = nil

    for _, opt in ipairs(getCraftOptions(itemId)) do
      local outQty = opt.outputQty or 1
      if outQty <= 0 then outQty = 1 end
      local cost = 0
      local missing = 0
      for _, reg in ipairs(opt.reagents or {}) do
        local regId = tonumber(reg.itemId or reg.id or reg[1])
        local regQty = reg.qty or reg.quantity or 1
        if regId then
          local regCost, regMissing = computeBestUnitCost(regId, stack, ownedSnapshot)
          if regCost == nil or (regMissing and regMissing > 0) then
            missing = missing + (regMissing or 1)
          else
            local ownedQty = 0
            if useOwnedForSelection then
              if ownedSnapshot and ownedSnapshot[regId] ~= nil then
                ownedQty = ownedSnapshot[regId]
              else
                ownedQty = getOwnedCount(regId, "selection")
              end
            end
            local useOwned = math.min(regQty, ownedQty)
            local buyQty = regQty - useOwned
            cost = cost + (regCost * buyQty) + (regCost * useOwned * ownedValueFactor)
          end
        else
          missing = missing + 1
        end
      end
      if missing == 0 then
        local unitCost = cost / outQty
        if bestCost == nil or unitCost < bestCost then
          bestCost = unitCost
          bestMissing = 0
          bestOption = opt
        end
      end
    end

    stack[itemId] = nil
    return bestCost, bestMissing, bestOption
  end

  local function shallowCopy(map)
    local out = {}
    for k, v in pairs(map or {}) do out[k] = v end
    return out
  end

  local function canCraftFromOwned(itemId, qty, ownedSnapshot, stack)
    if not itemId or qty <= 0 then return true end
    if not useOwnedForSelection or not ownedSnapshot then return false end
    if stack[itemId] then return false end
    local options = getCraftOptions(itemId)
    if #options == 0 then return false end
    stack[itemId] = true
    for _, opt in ipairs(options) do
      local outQty = opt.outputQty or 1
      if outQty <= 0 then outQty = 1 end
      local crafts = math.ceil(qty / outQty)
      local ok = true
      for _, reg in ipairs(opt.reagents or {}) do
        local regId = tonumber(reg.itemId or reg.id or reg[1])
        local regQty = (reg.qty or reg.quantity or 1) * crafts
        if not regId then
          ok = false
          break
        end
        local ownedBase = getOwnedCount(regId, "selection")
        if ownedBase > (ownedSnapshot[regId] or 0) then
          ownedSnapshot[regId] = ownedBase
        end
        local ownedQty = ownedSnapshot[regId] or 0
        if ownedQty >= regQty then
          ownedSnapshot[regId] = ownedQty - regQty
        else
          local need = regQty - ownedQty
          ownedSnapshot[regId] = 0
          if not canCraftFromOwned(regId, need, ownedSnapshot, stack) then
            ok = false
            break
          end
        end
      end
      if ok then
        stack[itemId] = nil
        return true
      end
    end
    stack[itemId] = nil
    return false
  end

  local function expandItem(itemId, qty, visited, leaf, intermediates)
    if not itemId or qty <= 0 then return end
    if not useIntermediates then
      leaf[itemId] = (leaf[itemId] or 0) + qty
      return
    end
    if visited[itemId] then
      leaf[itemId] = (leaf[itemId] or 0) + qty
      return
    end

    local buyPrice = prices[itemId] or getVendorPrice(itemId)
    local bestCost, bestMissing, bestOption = computeBestUnitCost(itemId, {}, nil)
    local craftCost, craftMissing, craftOption = computeBestCraftUnitCost(itemId, {}, nil)
    local craftOptions = getCraftOptions(itemId)

    -- If we can satisfy this requirement entirely from owned mats (possibly recursively),
    -- prefer crafting even if the market says buying is cheaper (minimize purchases).
    local canMakeFromOwned = false
    if useOwnedForSelection and craftOptions and #craftOptions > 0 then
      local ownedSnapshot = {}
      canMakeFromOwned = canCraftFromOwned(itemId, qty, ownedSnapshot, {})
    end

    local useCraft = false
    if canMakeFromOwned then
      useCraft = true
    elseif craftOption and craftCost and (buyPrice == nil or craftCost < buyPrice) then
      useCraft = true
    end
    -- Note: selection-time owned usage is governed by ignoreOwnedSelection via getOwnedCount/canCraftFromOwned.

    if not useCraft then
      leaf[itemId] = (leaf[itemId] or 0) + qty
      return
    end

    local chosen = craftOption or bestOption
    if not chosen and craftOptions and #craftOptions > 0 then
      -- Deterministic fallback: prefer a recipe option when costs are unknown (e.g., missing prices).
      for _, opt in ipairs(craftOptions) do
        if opt and opt.type == "recipe" then
          chosen = opt
          break
        end
      end
      if not chosen then
        chosen = craftOptions[1]
      end
    end
    if not chosen then
      leaf[itemId] = (leaf[itemId] or 0) + qty
      return
    end

    local outQty = chosen.outputQty or 1
    if outQty <= 0 then outQty = 1 end
    local crafts = math.ceil(qty / outQty)
    if chosen.type == "recipe" then
      addIntermediate(intermediates, itemId, crafts)
    end
    visited[itemId] = true
    for _, reg in ipairs(chosen.reagents or {}) do
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

  local function expandItemForceCraft(itemId, qty, visited, leaf, intermediates)
    if not itemId or qty <= 0 then return end
    if not useIntermediates then
      leaf[itemId] = (leaf[itemId] or 0) + qty
      return
    end
    if visited[itemId] then
      leaf[itemId] = (leaf[itemId] or 0) + qty
      return
    end

    local craftOption = select(3, computeBestCraftUnitCost(itemId, {}, nil))
    local craftOptions = getCraftOptions(itemId)
    local chosen = craftOption
    if not chosen and craftOptions and #craftOptions > 0 then
      for _, opt in ipairs(craftOptions) do
        if opt and opt.type == "recipe" then
          chosen = opt
          break
        end
      end
      if not chosen then
        chosen = craftOptions[1]
      end
    end
    if not chosen then
      leaf[itemId] = (leaf[itemId] or 0) + qty
      return
    end

    local outQty = chosen.outputQty or 1
    if outQty <= 0 then outQty = 1 end
    local crafts = math.ceil(qty / outQty)
    if chosen.type == "recipe" then
      addIntermediate(intermediates, itemId, crafts)
    end
    visited[itemId] = true
    for _, reg in ipairs(chosen.reagents or {}) do
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
  local targetSkill = FrugalForgeDB.settings.targetSkill or (currentSkill + 100)

  local function clamp01(x)
    if x < 0 then return 0 end
    if x > 1 then return 1 end
    return x
  end

  local function lerp(a, b, t)
    return a + (b - a) * t
  end

  local function bandChance(skill, bandStart, bandEnd, hi, lo, gamma)
    if bandEnd <= bandStart then return lo end
    local t = clamp01((skill - bandStart) / (bandEnd - bandStart))
    return lerp(hi, lo, t ^ gamma)
  end

  local function chanceForSkill(skill, r)
    local orange = r.orangeUntil or r.minSkill or 0
    local yellow = r.yellowUntil or orange
    local green = r.greenUntil or yellow
    local gray = r.grayAt or green
    if skill <= orange then return 1 end
    if skill <= yellow then return bandChance(skill, orange, yellow, 0.75, 0.35, 2.5) end
    if skill <= green then return bandChance(skill, yellow, green, 0.25, 0.10, 2.5) end
    if skill < gray then return bandChance(skill, green, gray, 0.10, 0.03, 2.5) end
    return 0
  end

  local function requiredRodForEnchantSkill(skill)
    if not skill then return nil end
    if skill >= 375 then return 22463 end -- Runed Eternium Rod
    if skill >= 350 then return 22462 end -- Runed Adamantite Rod
    if skill >= 300 then return 22461 end -- Runed Fel Iron Rod
    if skill >= 200 then return 11145 end -- Runed Truesilver Rod
    if skill >= 150 then return 11130 end -- Runed Golden Rod
    if skill >= 100 then return 6339 end -- Runed Silver Rod
    return 6218 -- Runed Copper Rod
  end


  local function recipePenaltyFactor(info)
    if not info or not info.requiresRecipe then return 1 end
    if info.recipeVendorPrice then return vendorRecipePenalty end
    return nonTrainerPenalty
  end

  local function estimateCostForCrafts(info, crafts, ownedRemaining)
    local cost = 0
    local missing = 0
    if info.requiresRecipe and not info.recipeVendorPrice then
      missing = missing + 1
    end
    for itemId, qty in pairs(info.leaf) do
      local need = qty * crafts
      if ownedRemaining[itemId] == nil then
        ownedRemaining[itemId] = getOwnedCount(itemId, "selection")
      end
      local ownedQty = (ignoreOwnedSelection and 0) or (ownedRemaining[itemId] or 0)
      local useOwned = math.min(need, ownedQty)
      local buy = need - useOwned
      local price = prices[itemId]
      if not price then
        price = getVendorPrice(itemId)
      end
      if price then
        cost = cost + (price * buy) + (price * useOwned * ownedValueFactor)
      else
        missing = missing + 1
      end
    end
    cost = cost * recipePenaltyFactor(info)
    return cost, missing
  end

  local function estimateCostForCraftsNoOwned(info, crafts)
    local cost = 0
    local missing = 0
    if info.requiresRecipe and not info.recipeVendorPrice then
      missing = missing + 1
    end
    for itemId, qty in pairs(info.leaf) do
      local need = qty * crafts
      local price = prices[itemId]
      if not price then
        price = getVendorPrice(itemId)
      end
      if price then
        cost = cost + (price * need)
      else
        missing = missing + 1
      end
    end
    cost = cost * recipePenaltyFactor(info)
    return cost, missing
  end

  local function consumeOwnedForCrafts(info, crafts, ownedRemaining)
    if ignoreOwnedSelection then return end
    for itemId, qty in pairs(info.leaf) do
      local need = qty * crafts
      if ownedRemaining[itemId] == nil then
        ownedRemaining[itemId] = getOwnedCount(itemId, "selection")
      end
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
        if info.missingPriceCount and info.missingPriceCount > 0 then
          -- skip recipes with missing price data
        else
          local p = chanceForSkill(skill, info.recipe)
          if p > 0 then
            local crafts = 1 / p
            local cost, missing = estimateCostForCrafts(info, crafts, ownedMap)
            local score = (missing > 0) and 1e18 or cost
            table.insert(candidates, { info = info, score = score, cost = cost, missing = missing, p = p, crafts = crafts })
          end
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
      if not price then
        price = getVendorPrice(itemId)
      end
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
      local missingPriceCount = 0
      for itemId, qty in pairs(leaf) do
      local price = prices[itemId]
      if not price then
        price = getVendorPrice(itemId)
      end
        local ownedQty = ownedMap[itemId] or 0
        if price then
          local ownedUse = math.min(qty, ownedQty)
          costPerCraft = costPerCraft + (price * (qty - ownedUse))
        else
          if ownedQty < qty then
            missing = missing + 1
            missingPriceCount = missingPriceCount + 1
          end
        end
      end

      local recipeItemId = tonumber(r.recipeItemId or r.recipeItem or r.recipeItemID)
      local recipeVendorPrice = resolveRecipeVendorPrice(recipeItemId, r.recipeVendorPrice)
      if r.requiresRecipe and not recipeVendorPrice then
        missing = missing + 1
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
        missingPriceCount = missingPriceCount,
        requiresRecipe = r.requiresRecipe == true,
        recipeItemId = recipeItemId,
        recipeVendorPrice = recipeVendorPrice,
      })
      end
    end
    end
  end

  local viableCount = 0
  for _, info in ipairs(recipeInfos) do
    if not (info.missingPriceCount and info.missingPriceCount > 0) then
      viableCount = viableCount + 1
    end
  end
  if #recipeInfos == 0 or viableCount == 0 then
    if FrugalForgeDB.settings and FrugalForgeDB.settings.debug then
      FrugalForgeDB.lastCandidateDebugLines = { "Top candidates unavailable (no recipes)" }
    end
    local msg = "No viable recipes found for the selected skill range. Missing prices prevent planning. Run Scan Missing or expand your scan."
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
      if not prices[itemId] and not isVendorItem(itemId) and shouldTrackMissingPrice(itemId) then
        missingForPlan[itemId] = true
      end
    end
  end
  local missingForPlanCount = 0
  for _ in pairs(missingForPlan) do missingForPlanCount = missingForPlanCount + 1 end
  local missingIds = {}
  for itemId in pairs(missingForPlan) do
    table.insert(missingIds, itemId)
  end

  if FrugalForgeDB.settings and FrugalForgeDB.settings.debug then
    logTopCandidates(currentSkill)
    if type(FrugalForgeDB.lastCandidateDebugLines) ~= "table" then
      FrugalForgeDB.lastCandidateDebugLines = { "Top candidates unavailable (no data)" }
    end
  end

  local ownedRemainingSelection = {}
  local ownedRecipes = {}
  local chosenBySkill = {}
  for skill = currentSkill, targetSkill - 1 do
    local best = nil
    for _, info in ipairs(recipeInfos) do
      if skill >= info.minSkill and skill < info.grayAt then
        if info.missingPriceCount and info.missingPriceCount > 0 then
          -- skip recipes with missing price data
        else
          local p = chanceForSkill(skill, info.recipe)
          if p > 0 then
            local crafts = 1 / p
            local cost, missing = estimateCostForCrafts(info, crafts, ownedRemainingSelection)
            local rawCost, rawMissing = estimateCostForCraftsNoOwned(info, crafts)
            local recipeKey = info.recipeItemId or (info.recipe and info.recipe.recipeId) or info.recipeId or info.name
            local recipeCost = 0
            if info.requiresRecipe and info.recipeVendorPrice and recipeKey and not ownedRecipes[recipeKey] then
              recipeCost = info.recipeVendorPrice
            end
            if recipeCost > 0 then
              cost = cost + recipeCost
              rawCost = rawCost + recipeCost
            end
            if not best
              or missing < best.missing
              or (missing == best.missing and cost < best.expectedCost)
              or (missing == best.missing and cost == best.expectedCost and rawMissing < best.rawMissing)
              or (missing == best.missing and cost == best.expectedCost and rawMissing == best.rawMissing and rawCost < best.rawCost) then
              best = {
                info = info,
                p = p,
                crafts = crafts,
                expectedCost = cost,
                missing = missing,
                rawCost = rawCost,
                rawMissing = rawMissing
              }
            end
          end
        end
      end
    end
    if not best then break end
    chosenBySkill[skill] = best
    if best.info.requiresRecipe and best.info.recipeVendorPrice then
      local recipeKey = best.info.recipeItemId or (best.info.recipe and best.info.recipe.recipeId) or best.info.recipeId or best.info.name
      if recipeKey then
        ownedRecipes[recipeKey] = true
      end
    end
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

  local requiredRods = {}
  for _, r in ipairs(ranges) do
    local recipe = r.info and r.info.recipe
    if recipe and recipe.professionId == 333 and not recipe.createsItemId then
      local rodId = requiredRodForEnchantSkill(r.info.minSkill or recipe.minSkill or 0)
      if rodId then requiredRods[rodId] = true end
    end
  end

  local rodLeaf = {}
  local rodSteps = {}
  for rodId in pairs(requiredRods) do
    local ownedRod = getOwnedCount(rodId, "shopping")
    if ownedRod < 1 then
      expandItemForceCraft(rodId, 1, {}, rodLeaf, {})
      local rodRecipe = recipeByOutput and recipeByOutput[rodId]
      local rodSkill = (rodRecipe and (rodRecipe.minSkill or 0)) or currentSkill
      local rodName = getItemName(rodId) or ("item " .. tostring(rodId))
      local p = (rodRecipe and chanceForSkill(rodSkill, rodRecipe)) or nil
      local craftNote = p and string.format(" (skill-up chance %.0f%%)", p * 100) or ""
      table.insert(rodSteps, { sortKey = rodSkill, text = string.format("- Craft required rod: %s (%d)%s", rodName, rodId, craftNote) })
    end
  end

  -- Convert expected crafts (fractional) into a deterministic whole-craft plan for
  -- reagent expansion and shopping list accounting.
  for _, r in ipairs(ranges) do
    local n = math.ceil(tonumber(r.crafts or 0) or 0)
    if n < 0 then n = 0 end
    r.craftCount = n
  end

  local craftsByOutput = {}
  for _, r in ipairs(ranges) do
    local outputId = r.info.outputItemId
    if outputId then
      craftsByOutput[outputId] = (craftsByOutput[outputId] or 0) + (r.craftCount or 0)
    end
  end

  for _, r in ipairs(ranges) do
    for itemId, crafts in pairs(r.info.inter) do
      intermediatesAll[itemId] = (intermediatesAll[itemId] or 0) + crafts * (r.craftCount or 0)
      local needAt = intermediatesFirstNeedSkill[itemId]
      if not needAt or r.startSkill < needAt then
        intermediatesFirstNeedSkill[itemId] = r.startSkill
      end
    end
  end
  local stepEntries = {}
  local ownedForSteps = {}
  for itemId, qty in pairs(ownedMap) do ownedForSteps[itemId] = qty end
  table.sort(rodSteps, function(a, b) return a.sortKey < b.sortKey end)
  for _, entry in ipairs(rodSteps) do
    table.insert(stepEntries, { startSkill = entry.sortKey, endSkill = entry.sortKey, text = entry.text })
  end
  for _, r in ipairs(ranges) do
    local displayStart = r.startSkill
    local displayEnd = r.endSkill + 1
    local skillText = string.format(" (skill %d-%d)", displayStart, displayEnd)
    local craftCount = r.craftCount or math.ceil(r.crafts or 0)
    local rangeCost = 0
    local rangeMissing = 0
    if r.info.requiresRecipe then
      recipeNeeds[r.info.recipe.recipeId or r.info.name or "recipe"] = r.info
    end
    for itemId, qty in pairs(r.info.leaf) do
      local need = qty * craftCount
      local ownedQty = ownedForSteps[itemId] or 0
      local useOwned = math.min(need, ownedQty)
      if useOwned > 0 then
        ownedForSteps[itemId] = ownedQty - useOwned
      end
      local buy = need - useOwned
      if buy > 0 then
        local price = prices[itemId]
        if not price then
          price = getVendorPrice(itemId)
        end
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

  for _, r in ipairs(ranges) do
    local craftCount = r.craftCount or math.ceil(r.crafts or 0)
    for itemId, qty in pairs(r.info.leaf) do
      local need = qty * craftCount
      if ownedRemaining[itemId] == nil then
        ownedRemaining[itemId] = getOwnedCount(itemId, "shopping")
      end
      local ownedQty = ownedRemaining[itemId] or 0
      local useOwned = math.min(need, ownedQty)
      if useOwned > 0 then
        ownedRemaining[itemId] = ownedQty - useOwned
      end
      local buy = need - useOwned
      local price = prices[itemId]
      if not price then
        price = getVendorPrice(itemId)
      end
      if price then
        pricedKinds[itemId] = true
        totalCost = totalCost + (price * buy)
      else
        if shouldTrackMissingPrice(itemId) then
          missingPriceItems[itemId] = true
        end
      end
      local vendor = isVendorItem(itemId)
      materials[itemId] = materials[itemId] or { need = 0, craft = 0, price = price, isVendor = vendor }
      materials[itemId].need = materials[itemId].need + need
      reagentKinds[itemId] = true
    end
  end
  for itemId, qty in pairs(rodLeaf) do
    local price = prices[itemId]
    if not price then
      price = getVendorPrice(itemId)
    end
    if price then
      pricedKinds[itemId] = true
      totalCost = totalCost + (price * qty)
    else
      if shouldTrackMissingPrice(itemId) then
        missingPriceItems[itemId] = true
      end
    end
    local vendor = isVendorItem(itemId)
    materials[itemId] = materials[itemId] or { need = 0, craft = 0, price = price, isVendor = vendor }
    materials[itemId].need = materials[itemId].need + qty
    reagentKinds[itemId] = true
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

  for itemId, crafts in pairs(intermediatesAll) do
    local recipe = recipeByOutput[itemId]
    local outputQty = (recipe and recipe.createsQuantity) or 1
    if outputQty <= 0 then outputQty = 1 end
    local craftQty = math.ceil(crafts * outputQty)
    materials[itemId] = materials[itemId] or { need = 0, craft = 0, price = prices[itemId] or getVendorPrice(itemId), isVendor = isVendorItem(itemId) }
    materials[itemId].craft = (materials[itemId].craft or 0) + craftQty
  end

  -- Intermediate accounting correction:
  -- We expand intermediates into base mats assuming we craft the full intermediate requirement.
  -- If the player already owns some intermediate outputs, those owned units should not be expanded
  -- into base mats. This pass subtracts the base-mat needs corresponding to the owned portion of
  -- intermediate demand and also precomputes net-craft quantities for display.
  local ownedLiveByItem = {}
  local netCraftByItem = {}

  local function chooseCraftOption(itemId)
    local craftCost, craftMissing, craftOption = computeBestCraftUnitCost(itemId, {}, nil)
    if craftMissing and craftMissing > 0 then
      craftOption = craftOption -- keep deterministic fallback below
    end
    if craftCost == nil then
      craftOption = craftOption -- may still be nil
    end

    local chosen = craftOption
    if not chosen then
      local craftOptions = getCraftOptions(itemId)
      if craftOptions and #craftOptions > 0 then
        for _, opt in ipairs(craftOptions) do
          if opt and opt.type == "recipe" then
            chosen = opt
            break
          end
        end
        if not chosen then
          chosen = craftOptions[1]
        end
      end
    end
    return chosen
  end

  local function expandCraftedUnitsToLeaf(itemId, qtyUnits, leafOut, visited)
    if not itemId or qtyUnits <= 0 then return end
    if visited[itemId] then
      -- Cycle safeguard: treat as leaf.
      leafOut[itemId] = (leafOut[itemId] or 0) + qtyUnits
      return
    end

    local chosen = chooseCraftOption(itemId)
    if not chosen then
      leafOut[itemId] = (leafOut[itemId] or 0) + qtyUnits
      return
    end

    local outQty = chosen.outputQty or 1
    if outQty <= 0 then outQty = 1 end
    local crafts = math.ceil(qtyUnits / outQty)

    visited[itemId] = true
    local dummyInter = {}
    for _, reg in ipairs(chosen.reagents or {}) do
      local regId
      local regQty = 1
      if type(reg) == "table" then
        regId = tonumber(reg.itemId or reg.id or reg[1])
        regQty = reg.qty or reg.quantity or 1
      else
        regId = tonumber(reg)
      end
      expandItem(regId, regQty * crafts, visited, leafOut, dummyInter)
    end
    visited[itemId] = nil
  end

  for itemId, entry in pairs(materials) do
    local ownedLive = getOwnedCount(itemId, "shopping")
    ownedLiveByItem[itemId] = ownedLive

    local needBuy = entry.need or 0
    local needCraft = entry.craft or 0

    local ownedForBuyNeed = math.min(needBuy, ownedLive)
    local ownedAfterBuyNeed = ownedLive - ownedForBuyNeed
    local ownedUsedForCraft = math.min(needCraft, ownedAfterBuyNeed)
    netCraftByItem[itemId] = math.max(0, needCraft - ownedUsedForCraft)

    if ownedUsedForCraft > 0 and needCraft > 0 then
      local leafDelta = {}
      expandCraftedUnitsToLeaf(itemId, ownedUsedForCraft, leafDelta, {})
      for leafId, leafQty in pairs(leafDelta) do
        if materials[leafId] then
          materials[leafId].need = math.max(0, (materials[leafId].need or 0) - leafQty)
        end
      end
    end
  end

  local shoppingLines = { "Materials list:" }
  local missingCount = 0
  local shoppingList = {}
  local used = {}
  for _, pair in ipairs(ESSENCE_PAIRS) do
    local lesserEntry = materials[pair.lesser]
    local greaterEntry = materials[pair.greater]
    if lesserEntry or greaterEntry then
      used[pair.lesser] = true
      used[pair.greater] = true
      local needGreater = (greaterEntry and (greaterEntry.need or 0)) or 0
      local needLesser = (lesserEntry and (lesserEntry.need or 0)) or 0
      local craftGreater = (greaterEntry and (greaterEntry.craft or 0)) or 0
      local craftLesser = (lesserEntry and (lesserEntry.craft or 0)) or 0
      local totalNeedGreater = needGreater + (needLesser / 3)
      local totalCraftGreater = craftGreater + (craftLesser / 3)
      local priceGreater = (greaterEntry and greaterEntry.price) or prices[pair.greater] or getVendorPrice(pair.greater)
      local priceLesser = (lesserEntry and lesserEntry.price) or prices[pair.lesser] or getVendorPrice(pair.lesser)
      local effectivePrice = nil
      if priceGreater and priceLesser then
        effectivePrice = math.min(priceGreater, priceLesser * 3)
      elseif priceGreater then
        effectivePrice = priceGreater
      elseif priceLesser then
        effectivePrice = priceLesser * 3
      end
      table.insert(shoppingList, {
        itemId = pair.greater,
        entry = {
          need = totalNeedGreater,
          craft = totalCraftGreater,
          price = effectivePrice,
          isVendor = false,
          isEssenceCombined = true,
          lesserId = pair.lesser,
          greaterId = pair.greater,
        }
      })
    end
  end
  for itemId, entry in pairs(materials) do
    if not used[itemId] then
      table.insert(shoppingList, { itemId = itemId, entry = entry })
    end
  end
  table.sort(shoppingList, function(a, b)
    return tostring(getItemName(a.itemId)) < tostring(getItemName(b.itemId))
  end)

  local recomputedTotalCost = 0
  for _, row in ipairs(shoppingList) do
    local itemId = row.itemId
    local entry = row.entry
    local ownedLive = ownedLiveByItem[itemId]
    local needBuy = entry.need or 0
    local needCraft = entry.craft or 0
    local netCraft = netCraftByItem[itemId] or 0
    if entry.isEssenceCombined then
      local greaterId = entry.greaterId
      local lesserId = entry.lesserId
      local ownedGreater = getOwnedCount(greaterId, "shopping")
      local ownedLesser = getOwnedCount(lesserId, "shopping")
      ownedLive = ownedGreater + (ownedLesser / 3)
      netCraft = needCraft
    else
      if ownedLive == nil then
        ownedLive = getOwnedCount(itemId, "shopping")
        ownedLiveByItem[itemId] = ownedLive
      end
    end

    -- Owned allocation: satisfy "buy-needed" usage first, then use remaining owned to reduce crafts.
    local ownedForBuyNeed = math.min(needBuy, ownedLive)
    local buy = math.max(0, needBuy - ownedForBuyNeed)
    local craft = netCraft
    if entry.isEssenceCombined then
      local ownedAfterBuyNeed = ownedLive - ownedForBuyNeed
      local ownedUsedForCraft = math.min(needCraft, ownedAfterBuyNeed)
      craft = math.max(0, needCraft - ownedUsedForCraft)
    end
    local totalNeed = needBuy + needCraft

    local ownedBreakdown = ""
    if not entry.isEssenceCombined then
      local chars = ownedByChar[itemId]
      if chars then
        local parts = {}
        for name, qty in pairs(chars) do
          table.insert(parts, string.format("%s:%d", name, qty))
        end
        table.sort(parts)
        ownedBreakdown = " [" .. table.concat(parts, ", ") .. "]"
      end
    end

    local priceText = entry.price and copperToText(math.floor(entry.price + 0.5)) or "missing price"
    local totalText = entry.price and copperToText(math.floor(entry.price * buy + 0.5)) or "?"
    local missingTag = entry.price and "" or " (missing price)"
    local vendorTag = entry.isVendor and " (vendor)" or ""
    local craftText = ""
    if craft > 0 then
      craftText = entry.isEssenceCombined and string.format(", craft %s", formatQty(craft)) or string.format(", craft %d", craft)
    end
    if entry.isEssenceCombined then
      local line = string.format("  - %s (%d): need %s (owned %s%s)%s, buy %s @ %s = %s%s",
        getItemName(itemId), itemId, formatQty(totalNeed), formatQty(ownedLive), ownedBreakdown, craftText, formatQty(buy), priceText, totalText, missingTag)
      table.insert(shoppingLines, line)
    else
      local line = string.format("  - %s (%d): need %d (owned %d%s)%s, buy %d @ %s = %s%s%s",
        getItemName(itemId), itemId, totalNeed, ownedLive, ownedBreakdown, craftText, buy, priceText, totalText, missingTag, vendorTag)
      table.insert(shoppingLines, line)
    end

    if entry.price then
      recomputedTotalCost = recomputedTotalCost + (entry.price * buy)
    end
  end
  totalCost = recomputedTotalCost
  for _, info in pairs(recipeNeeds) do
    table.insert(recipeNeedList, info)
  end
  table.sort(recipeNeedList, function(a, b)
    return tostring(a.name or a.recipeId) < tostring(b.name or b.recipeId)
  end)
  if #recipeNeedList > 0 then
    table.insert(shoppingLines, "Recipes needed:")
    for _, info in ipairs(recipeNeedList) do
      local recipePriceText = ""
      if info.recipeVendorPrice then
        recipePriceText = " vendor " .. copperToText(info.recipeVendorPrice)
      end
      table.insert(shoppingLines, string.format("  - Recipe: %s (not trainer learned;%s)", info.name or info.recipeId or "recipe", recipePriceText ~= "" and recipePriceText or " vendor/AH/quest"))
      if info.recipeVendorPrice then
        recomputedTotalCost = recomputedTotalCost + info.recipeVendorPrice
      elseif info.recipeItemId and shouldTrackMissingPrice(info.recipeItemId) then
        missingPriceItems[info.recipeItemId] = true
      end
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
    if FrugalForgeDB.settings and FrugalForgeDB.settings.devMode then
      local ids = {}
      for itemId in pairs(missingPriceItems) do
        table.insert(ids, itemId)
      end
      table.sort(ids)
      table.insert(summaryLines, "Missing price itemIds: " .. table.concat(ids, ", "))
    end
  end
  if missingForPlanCount > 0 then
    table.insert(summaryLines, string.format("Missing prices for %d item(s); recipes needing them were skipped.", missingForPlanCount))
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
  ui.deltaLabel:SetText("Target")

  ui.deltaBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  ui.deltaBox:SetSize(40, 20)
  ui.deltaBox:SetPoint("TOPLEFT", 375, y - 2)
  ui.deltaBox:SetAutoFocus(false)
  ui.deltaBox:SetNumeric(true)
  ui.deltaBox:SetText(tostring(FrugalForgeDB.settings.targetSkill or 350))

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
    local scanTargets = FrugalForgeDB.scanTargets or FrugalForgeDB.targets
    if scanTargets and type(scanTargets.reagentIds) == "table" then
      local ids = sanitizeReagentIds(scanTargets.reagentIds)
      FrugalScan_TargetItemIds = ids
      -- no legacy targets
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
        if n and n > 0 and not NO_SCAN_REAGENT_IDS[n] and (isQualityAtMost(n, QUALITY_UNCOMMON) or isEnchantShard(n)) then
          table.insert(ids, n)
        end
      end
    else
      local scanTargets = FrugalForgeDB.scanTargets or FrugalForgeDB.targets
      if scanTargets and type(scanTargets.reagentIds) == "table" then
        local prices = buildPriceMap()
        for _, itemId in ipairs(scanTargets.reagentIds) do
          local n = tonumber(itemId)
          if n and n > 0 and not NO_SCAN_REAGENT_IDS[n] and not prices[n] and not isVendorItem(n) and (isQualityAtMost(n, QUALITY_UNCOMMON) or isEnchantShard(n)) then
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
    -- no legacy targets
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
      "targets.prof=" .. tostring(_G.FrugalScan_TargetProfessionName or "none"),
      "targets.id=" .. tostring(_G.FrugalScan_TargetProfessionId or "none"),
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

  local purgeBtn = CreateFrame("Button", nil, overlay, "UIPanelButtonTemplate")
  purgeBtn:SetSize(160, 22)
  purgeBtn:SetPoint("TOPRIGHT", devBtn, "BOTTOMRIGHT", 0, -6)
  purgeBtn:SetText("Purge Rod Targets")
  purgeBtn:SetScript("OnClick", function()
    purgeRodScanTargets()
  end)
  overlay.purgeBtn = purgeBtn

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


local setMinimapButtonHidden
local function createMinimapButton()
  if ui.minimapBtn or not Minimap then return end
  ensureDb()

  local btn = CreateFrame("Button", "FrugalForgeMinimapButton", Minimap)
  btn:SetSize(24, 24)
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
    local settings = FrugalForgeDB.settings or {}
    if settings.minimapOffsetX ~= nil and settings.minimapOffsetY ~= nil then
      btn:ClearAllPoints()
      btn:SetPoint("CENTER", Minimap, "CENTER", settings.minimapOffsetX, settings.minimapOffsetY)
      return
    end
    local angle = settings.minimapAngle or 45
    local rad = (math.rad and math.rad(angle)) or (angle * math.pi / 180)
    local radius = 80
    local x = math.cos(rad) * radius
    local y = math.sin(rad) * radius
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
  end

  btn:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      return
    end
    if IsAltKeyDown and IsAltKeyDown() then
      setMinimapButtonHidden(true)
      DEFAULT_CHAT_FRAME:AddMessage("|cff7dd3fcFrugalForge|r: Minimap button hidden. Use /frugal minimap to show.")
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
    GameTooltip:AddLine("Alt click:", 0.7, 0.7, 0.7, false)
    GameTooltip:AddLine("Hide minimap button (/frugal minimap to show)", 1, 1, 1, false)
    GameTooltip:AddLine("Drag:", 0.7, 0.7, 0.7, false)
    GameTooltip:AddLine("Move minimap button", 1, 1, 1, false)
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
      FrugalForgeDB.settings.minimapOffsetX = dx
      FrugalForgeDB.settings.minimapOffsetY = dy
      position()
    end)
  end)

  btn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)

  position()
  ui.minimapBtn = btn
  if FrugalForgeDB.settings and FrugalForgeDB.settings.minimapHidden then
    btn:Hide()
  end
end

setMinimapButtonHidden = function(hidden)
  ensureDb()
  FrugalForgeDB.settings.minimapHidden = hidden and true or false
  if hidden then
    if ui.minimapBtn then ui.minimapBtn:Hide() end
  else
    if not ui.minimapBtn then
      createMinimapButton()
    else
      ui.minimapBtn:Show()
    end
  end
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
      "targets.prof=" .. tostring(_G.FrugalScan_TargetProfessionName or "none"),
      "targets.id=" .. tostring(_G.FrugalScan_TargetProfessionId or "none"),
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
  if cmd == "minimap" or cmd == "minimapbutton" then
    ensureDb()
    local hidden = not (FrugalForgeDB.settings and FrugalForgeDB.settings.minimapHidden)
    setMinimapButtonHidden(hidden)
    if hidden then
      DEFAULT_CHAT_FRAME:AddMessage("|cff7dd3fcFrugalForge|r: Minimap button hidden. Use /frugal minimap to show.")
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cff7dd3fcFrugalForge|r: Minimap button shown.")
    end
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
