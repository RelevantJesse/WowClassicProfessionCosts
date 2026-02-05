local ADDON_NAME = ...
local OPTIONS_FRAME_NAME = "FrugalScanOptionsFrame"

local function EnsureDb()
  if type(FrugalScanDB) ~= "table" then
    FrugalScanDB = {}
  end
  _G.ProfessionLevelerScanDB = nil
  if type(FrugalScanDB.settings) ~= "table" then
    FrugalScanDB.settings = {}
  end
  if type(FrugalScanDB.debugLog) ~= "table" then
    FrugalScanDB.debugLog = {}
  end

  local s = FrugalScanDB.settings
  if type(s.maxSkillDelta) ~= "number" then s.maxSkillDelta = 100 end
  if type(s.expansionCapSkill) ~= "number" then s.expansionCapSkill = 350 end
  if type(s.maxPagesPerItem) ~= "number" then s.maxPagesPerItem = 10 end
  if type(s.minQueryIntervalSeconds) ~= "number" then s.minQueryIntervalSeconds = 1.5 end
  if s.minQueryIntervalSeconds > 1.5 then s.minQueryIntervalSeconds = 1.5 end
  if s.minQueryIntervalSeconds < 0.5 then s.minQueryIntervalSeconds = 0.5 end
  if type(s.queryTimeoutSeconds) ~= "number" then s.queryTimeoutSeconds = 10 end
  if type(s.maxTimeoutRetriesPerPage) ~= "number" then s.maxTimeoutRetriesPerPage = 3 end
  if type(s.priceRank) ~= "number" then s.priceRank = 3 end

  s.verboseDebug = (s.verboseDebug == true)
end

EnsureDb()

local TryRegisterOptions = nil

local function AppendLog(line)
  EnsureDb()
  local log = FrugalScanDB.debugLog
  if type(log) ~= "table" then
    FrugalScanDB.debugLog = {}
    log = FrugalScanDB.debugLog
  end

  local ts = date("%H:%M:%S", time())
  table.insert(log, ts .. " " .. tostring(line))

  local maxLines = 800
  local extra = #log - maxLines
  if extra > 0 then
    for _ = 1, extra do
      table.remove(log, 1)
    end
  end
end

local function Print(msg)
  AppendLog(tostring(msg))
  DEFAULT_CHAT_FRAME:AddMessage("|cff7dd3fcFrugalScan|r: " .. tostring(msg))
end

local function DebugPrint(msg)
  EnsureDb()
  if FrugalScanDB and FrugalScanDB.settings and FrugalScanDB.settings.verboseDebug then
    Print("[debug] " .. tostring(msg))
  end
end

local function Trim(s)
  if type(s) ~= "string" then return "" end
  s = string.gsub(s, "^%s+", "")
  s = string.gsub(s, "%s+$", "")
  return s
end

local function FirstWord(s)
  s = Trim(s or "")
  if s == "" then return "", "" end
  local a, b = string.match(s, "^(%S+)%s*(.*)$")
  return (a or ""), (b or "")
end

local function GetAuctionFrame()
  if AuctionFrame then return AuctionFrame end
  if AuctionHouseFrame then return AuctionHouseFrame end
  return nil
end

local function NormalizeProfessionName(name)
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

local function TryGetSkillLineByName(targetName)
  local targetNorm = NormalizeProfessionName(targetName)
  if not targetNorm then return nil end
  if not GetNumSkillLines or not GetSkillLineInfo then return nil end

  local num = GetNumSkillLines()
  if not num or num <= 0 then return nil end

  for i = 1, num do
    local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
    local nameNorm = NormalizeProfessionName(name)
    if not isHeader and nameNorm and nameNorm == targetNorm then
      if type(rank) == "number" and type(maxRank) == "number" then
        return rank, maxRank
      end
      return nil
    end
  end

  return nil
end

local state = {
  running = false,
  queue = {},
  total = 0,
  currentItemId = nil,
  currentQueryName = nil,
  page = 0,
  maxPages = 10,
  delaySeconds = 1.5,
  awaiting = false,
  prices = {},
  foundAnyForItem = false,
  startedAt = nil,
  lastQueryAt = nil,
  lastQueryToken = 0,
  timeoutRetries = 0,
  pendingItemInfoId = nil,
  lastSendMethod = nil, -- "ui" | "api"
}

local function UpdateStatus()
  _G.FrugalScan_ScanStatus = _G.FrugalScan_ScanStatus or {}
  local s = _G.FrugalScan_ScanStatus
  s.running = state.running
  s.remaining = #state.queue
  s.total = state.total or #state.queue
  s.currentItemId = state.currentItemId
  s.currentName = state.currentQueryName
  s.startedAt = state.startedAt
  if type(_G.FrugalForge_UpdateScanStatus) == "function" then
    pcall(_G.FrugalForge_UpdateScanStatus)
  end
end

local function GetSetting(name, defaultValue)
  local settings = FrugalScanDB and FrugalScanDB.settings or nil
  if not settings then return defaultValue end
  local value = settings[name]
  if value == nil then return defaultValue end
  return value
end

local function IsAtAuctionHouse()
  local af = GetAuctionFrame()
  return af and af.IsShown and af:IsShown() or false
end

local function EnsureBrowseTab()
  if not IsAtAuctionHouse() then return end
  if AuctionFrameBrowse and not AuctionFrameBrowse:IsShown() and AuctionFrameTab1 and AuctionFrameTab1.Click then
    DebugPrint("EnsureBrowseTab(): clicking AuctionFrameTab1")
    AuctionFrameTab1:Click()
  end
end

local function OpenOptionsUi()
  Print("FrugalScan options UI has been removed. Use /frugal for controls.")
end

local function IsBrowseTabVisible()
  if not AuctionFrameBrowse then return true end
  return AuctionFrameBrowse:IsShown() == true
end

local function ParseItemIdFromLink(link)
  if not link then return nil end
  local id = string.match(link, "item:(%d+)")
  return id and tonumber(id) or nil
end

local QUALITY_COMMON = 1
local QUALITY_UNCOMMON = 2
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
local function IsScanQualityAllowed(itemId)
  if ENCHANT_SHARD_IDS[itemId] then return true end
  local _, _, quality = GetItemInfo(itemId)
  if quality == nil then return true end
  return quality <= QUALITY_UNCOMMON
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
local EXTRA_VENDOR_ITEM_IDS = {
  [9210] = true, -- Ghost Dye (not present in vendor price table)
}
local function IsVendorItem(itemId)
  if not itemId then return false end
  if VENDOR_PRICE_BY_ID[itemId] ~= nil then return true end
  if EXTRA_VENDOR_ITEM_IDS[itemId] == true then return true end
  return FALLBACK_VENDOR_IDS[itemId] == true
end

local function SanitizeTargetIds()
  local function sanitize(list)
    if type(list) ~= "table" then return list end
    local out = {}
    local seen = {}
    for _, itemId in ipairs(list) do
      local n = tonumber(itemId)
      if n and n > 0 and not IsVendorItem(n) and IsScanQualityAllowed(n) and not seen[n] then
        seen[n] = true
        table.insert(out, n)
      end
    end
    table.sort(out)
    return out
  end

  if type(_G.FrugalScan_TargetItemIds) == "table" then
    _G.FrugalScan_TargetItemIds = sanitize(_G.FrugalScan_TargetItemIds)
  end
end

SanitizeTargetIds()

local function ExtractAuctionRow(listType, index)
  local fields = { GetAuctionItemInfo(listType, index) }
  local auctionName = fields[1]
  local count = tonumber(fields[3]) or 1

  -- Classic clients differ in return ordering. We want minBid and buyoutPrice.
  -- Common order:
  -- 1 name, 2 texture, 3 count, 4 quality, 5 canUse, 6 level, 7 levelColHeader, 8 minBid, 9 minIncrement, 10 buyout, ...
  -- Some clients include an extra header field, shifting minBid/buyout by +1.
  local minBidIndex = 8
  local buyoutIndex = 10
  if type(fields[minBidIndex]) == "string" and type(fields[minBidIndex + 1]) == "number" then
    minBidIndex = minBidIndex + 1
    buyoutIndex = buyoutIndex + 1
  end

  local minBid = tonumber(fields[minBidIndex]) or 0
  local buyoutPrice = tonumber(fields[buyoutIndex]) or 0
  return auctionName, count, minBid, buyoutPrice, fields
end

local function InsertSortedLimited(list, value, maxCount)
  if not list then return end
  if not value or value <= 0 then return end
  if not maxCount or maxCount < 1 then maxCount = 1 end

  local inserted = false
  for i = 1, #list do
    if value < list[i] then
      table.insert(list, i, value)
      inserted = true
      break
    end
  end
  if not inserted then
    table.insert(list, value)
  end

  while #list > maxCount do
    table.remove(list, #list)
  end
end

local function CanQuery()
  if not CanSendAuctionQuery then
    return true
  end
  local ok, res = pcall(CanSendAuctionQuery)
  if ok then return res end
  ok, res = pcall(CanSendAuctionQuery, "list")
  if ok then return res end
  return true
end

local function EnsureItemName(itemId)
  local name = GetItemInfo(itemId)
  if name then return name end
  if GameTooltip then
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    GameTooltip:SetHyperlink("item:" .. itemId)
    GameTooltip:Hide()
  end
  return GetItemInfo(itemId)
end

local function SetBrowseExactMatch(enabled)
  local want = enabled == true

  local candidates = {
    BrowseExactMatch,
    BrowseExactMatchCheckButton,
    AuctionFrameBrowse_ExactMatch,
    AuctionFrameBrowseExactMatch,
  }

  if AuctionFrameBrowse then
    if AuctionFrameBrowse.ExactMatch then table.insert(candidates, AuctionFrameBrowse.ExactMatch) end
    if AuctionFrameBrowse.ExactMatchCheckButton then table.insert(candidates, AuctionFrameBrowse.ExactMatchCheckButton) end
  end

  for _, w in ipairs(candidates) do
    if w and w.SetChecked then
      local ok = pcall(w.SetChecked, w, want)
      if ok then
        DebugPrint("Set exact-match checkbox=" .. tostring(want))
        return true
      end
    end
  end

  return false
end

local function TrySendBrowseQueryViaUi(searchText, debugItemName)
  -- Some clients/UIs behave better if we drive the built-in search box/button.
  if not searchText or searchText == "" then return false end
  if not IsAtAuctionHouse() then return false end
  EnsureBrowseTab()

  local did = false
  if BrowseName and BrowseName.SetText then
    BrowseName:SetText("")
    BrowseName:SetText(searchText)
    did = true
  end

  -- Reduce false positives from partial name matches (e.g. "Thick Leather Ammo Pouch").
  local exactOk = SetBrowseExactMatch(true)
  if (not exactOk) and FrugalScanDB and FrugalScanDB.settings and FrugalScanDB.settings.verboseDebug then
    DebugPrint("Exact-match checkbox not found; UI search may return partial name matches.")
  end

  if BrowseSearchButton and BrowseSearchButton.Click then
    BrowseSearchButton:Click()
    DebugPrint("Sent query via BrowseSearchButton: search=" .. tostring(searchText) .. ", itemName=\"" .. tostring(debugItemName) .. "\"")
    return true
  end

  if AuctionFrameBrowse_SearchButton and AuctionFrameBrowse_SearchButton.Click then
    AuctionFrameBrowse_SearchButton:Click()
    DebugPrint("Sent query via AuctionFrameBrowse_SearchButton: search=" .. tostring(searchText) .. ", itemName=\"" .. tostring(debugItemName) .. "\"")
    return true
  end

  if AuctionFrameBrowse_Search and type(AuctionFrameBrowse_Search) == "function" then
    AuctionFrameBrowse_Search()
    DebugPrint("Sent query via AuctionFrameBrowse_Search(): search=" .. tostring(searchText) .. ", itemName=\"" .. tostring(debugItemName) .. "\"")
    return true
  end

  return did and false or false
end

local function IsEnabled(btn)
  if not btn then return false end
  if btn.IsEnabled then
    local ok, res = pcall(btn.IsEnabled, btn)
    if ok then return res == true or res == 1 end
  end
  return true
end

local function TryNextPageViaUi()
  if not IsAtAuctionHouse() then return false end
  EnsureBrowseTab()

  local btn = BrowseNextPageButton
  if not btn and AuctionFrameBrowse and AuctionFrameBrowse.NextPageButton then
    btn = AuctionFrameBrowse.NextPageButton
  end

  if not btn or not btn.Click then
    DebugPrint("Next page button not found for UI pagination.")
    return false
  end

  if not IsEnabled(btn) then
    DebugPrint("Next page button is disabled.")
    return false
  end

  btn:Click()
  DebugPrint("Sent next page via UI button (page=" .. tostring(state.page) .. ")")
  return true
end

local function StartSnapshot()
  state.prices = {}
  if state.mergeWithLast == true and FrugalScanDB and type(FrugalScanDB.lastSnapshot) == "table" and type(FrugalScanDB.lastSnapshot.prices) == "table" then
    for _, p in ipairs(FrugalScanDB.lastSnapshot.prices) do
      if p and p.itemId then
        state.prices[p.itemId] = {
          bestUnits = { p.minUnitBuyoutCopper },
          minUnitBuyoutCopper = p.minUnitBuyoutCopper,
          totalQuantity = p.totalQuantity,
        }
      end
    end
  end
  state.startedAt = time()
  state.lastQueryAt = nil
  state.lastQueryToken = 0
  state.timeoutRetries = 0
  state.pendingItemInfoId = nil
  state.canQueryFalseCount = 0
end

local function NormalizeRealmSlug(realmName)
  local s = tostring(realmName or "")
  s = string.lower(s)
  s = s:gsub("'", "")
  s = s:gsub("%s+", "-")
  s = s:gsub("[^%w%-]", "")
  return s
end

local function DetectRegion()
  if GetCVar then
    local portal = GetCVar("portal")
    if portal and portal ~= "" then
      return string.upper(tostring(portal))
    end
  end

  local configured = FrugalScan_TargetRegion
  if configured and tostring(configured) ~= "" then
    return tostring(configured)
  end

  return nil
end

local function BuildExportJsonFromSnapshot(snap)
  if not snap then return nil end

  local parts = {}
  table.insert(parts, '{"schema":"wowahplanner-scan-v1"')
  table.insert(parts, ',"snapshotTimestampUtc":"' .. (snap.snapshotTimestampUtc or "") .. '"')
  table.insert(parts, ',"realmName":"' .. (snap.realmName or "") .. '"')
  table.insert(parts, ',"faction":"' .. (snap.faction or "") .. '"')
  if snap.region then
    table.insert(parts, ',"region":"' .. tostring(snap.region) .. '"')
  end
  if snap.gameVersion then
    table.insert(parts, ',"gameVersion":"' .. tostring(snap.gameVersion) .. '"')
  end
  if snap.realmSlug then
    table.insert(parts, ',"realmSlug":"' .. tostring(snap.realmSlug) .. '"')
  end
  if snap.targetProfessionId then
    table.insert(parts, ',"targetProfessionId":' .. tostring(snap.targetProfessionId))
  end
  if snap.targetProfessionName then
    table.insert(parts, ',"targetProfessionName":"' .. tostring(snap.targetProfessionName) .. '"')
  end
  table.insert(parts, ',"prices":[')

  for i, p in ipairs(snap.prices or {}) do
    if i > 1 then table.insert(parts, ",") end
    table.insert(parts, string.format('{"itemId":%d,"minUnitBuyoutCopper":%d,"totalQuantity":%d}', p.itemId, p.minUnitBuyoutCopper or 0, p.totalQuantity or 0))
  end

  table.insert(parts, "]}")
  return table.concat(parts)
end

local function FinishSnapshot()
  local rank = 3

  local realmName = GetRealmName()
  local realmSlug = NormalizeRealmSlug(realmName)
  local region = DetectRegion()

  local snapshot = {
    schema = "wowahplanner-scan-v1",
    snapshotTimestampUtc = date("!%Y-%m-%dT%H:%M:%SZ", time()),
    realmName = realmName,
    faction = UnitFactionGroup("player"),
    region = region,
    realmSlug = realmSlug,
    gameVersion = FrugalScan_TargetGameVersion,
    targetProfessionId = FrugalScan_TargetProfessionId,
    targetProfessionName = FrugalScan_TargetProfessionName,
    generatedAtEpochUtc = time(),
    priceRank = rank,
    prices = {},
  }

  for itemId, entry in pairs(state.prices) do
    if entry and type(entry.bestUnits) == "table" and #entry.bestUnits > 0 then
      local idx = rank
      if idx > #entry.bestUnits then idx = #entry.bestUnits end
      entry.minUnitBuyoutCopper = entry.bestUnits[idx]
    end

    table.insert(snapshot.prices, {
      itemId = itemId,
      minUnitBuyoutCopper = entry.minUnitBuyoutCopper,
      totalQuantity = entry.totalQuantity,
    })
  end

  table.sort(snapshot.prices, function(a, b) return a.itemId < b.itemId end)

  if state.mergeWithLast == true then
  local base = (FrugalScanDB and FrugalScanDB.lastSnapshot) or nil
    if base and type(base.prices) == "table" then
      local merged = {}
      for _, p in ipairs(base.prices) do
        if p and p.itemId then
          merged[p.itemId] = p
        end
      end
      for _, p in ipairs(snapshot.prices) do
        if p and p.itemId then
          merged[p.itemId] = p
        end
      end
      snapshot.prices = {}
      for _, p in pairs(merged) do
        table.insert(snapshot.prices, p)
      end
      table.sort(snapshot.prices, function(a, b) return a.itemId < b.itemId end)
    end
  end
  state.mergeWithLast = true

  FrugalScanDB.lastSnapshot = snapshot
  FrugalScanDB.lastSnapshotJson = BuildExportJsonFromSnapshot(snapshot)
  FrugalScanDB.lastGeneratedAtEpochUtc = snapshot.generatedAtEpochUtc

  state.running = false
  state.currentItemId = nil
  state.queue = {}
  state.awaiting = false
  state.total = 0
  UpdateStatus()

  Print("Scan complete. Items priced: " .. tostring(#(snapshot.prices or {})) .. ".")
end

local function BuildExportJson()
  local snap = FrugalScanDB.lastSnapshot
  if not snap then return nil end
  local json = BuildExportJsonFromSnapshot(snap)
  FrugalScanDB.lastSnapshotJson = json
  return json
end

local function ParseItemRef(v)
  if v == nil then return nil, nil end

  local t = type(v)
  if t == "number" then
    local itemId = tonumber(v)
    if itemId and itemId > 0 then return itemId, 1 end
    return nil, nil
  end

  if t == "table" then
    local itemId = tonumber(v.itemId or v.id or v.ItemId or v.ID)
    local qty = tonumber(v.qty or v.count or v.Quantity or v.Count)
    if itemId and itemId > 0 then
      if not qty or qty < 1 then qty = 1 end
      return itemId, qty
    end
    return nil, nil
  end

  if t ~= "string" then return nil, nil end

  local s = tostring(v)
  local itemId = tonumber(string.match(s, "item:(%d+)")) or tonumber(string.match(s, "^(%d+)"))
  if not itemId or itemId <= 0 then return nil, nil end

  local qty = tonumber(string.match(s, ";(%d+)$"))
  if not qty or qty < 1 then qty = 1 end
  return itemId, qty
end

local function BuildWantedItemIdSet()
  local wanted = {}
  local count = 0

  if type(FrugalScan_TargetItemIds) == "table" then
    for _, itemId in ipairs(FrugalScan_TargetItemIds) do
      local n = tonumber(itemId)
      if n and n > 0 and not wanted[n] then
        wanted[n] = true
        count = count + 1
      end
    end
  end


  if type(FrugalScan_OwnedItemIds) == "table" then
    for _, itemId in ipairs(FrugalScan_OwnedItemIds) do
      local n = tonumber(itemId)
      if n and n > 0 and not wanted[n] then
        wanted[n] = true
        count = count + 1
      end
    end
  end

  if count == 0 and type(_G.FrugalForgeDB) == "table" and type(_G.FrugalForgeDB.targets) == "table" then
    local t = _G.FrugalForgeDB.targets
    if type(t.reagentIds) == "table" then
      for _, itemId in ipairs(t.reagentIds) do
        local n = tonumber(itemId)
        if n and n > 0 and not wanted[n] then
          wanted[n] = true
          count = count + 1
        end
      end
    end
  end

  if count == 0 and type(FrugalScan_RecipeTargets) == "table" then
    for _, r in ipairs(FrugalScan_RecipeTargets) do
      if type(r) == "table" and type(r.reagents) == "table" then
        for _, itemId in ipairs(r.reagents) do
          local n = tonumber(itemId)
          if n and n > 0 and not wanted[n] then
            wanted[n] = true
            count = count + 1
          end
        end
      end
    end
  end

  return wanted, count
end

local function BuildOwnedCountsByCharacterFromBagBrother(wantedSet)
  local function IsAddOnLoadedSafe(addonName)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
      return C_AddOns.IsAddOnLoaded(addonName)
    end
    if IsAddOnLoaded then
      return IsAddOnLoaded(addonName)
    end
    return nil
  end

  local function LoadAddOnSafe(addonName)
    if C_AddOns and C_AddOns.LoadAddOn then
      return C_AddOns.LoadAddOn(addonName)
    end
    if LoadAddOn then
      return LoadAddOn(addonName)
    end
    return false, "LoadAddOn not available"
  end

  local function DetectBagDb()
    local candidates = {
      { name = "BrotherBags", value = _G and _G.BrotherBags or nil },
      { name = "BagBrother", value = _G and _G.BagBrother or nil },
      { name = "BagnonDB", value = _G and _G.BagnonDB or nil },
      { name = "BagnonDB2", value = _G and _G.BagnonDB2 or nil },
      { name = "BagnonDB3", value = _G and _G.BagnonDB3 or nil },
    }
    for _, c in ipairs(candidates) do
      if type(c.value) == "table" then
        return c.value, c.name
      end
    end
    return nil, nil
  end

  local function IsGuildLikeKey(k)
    if type(k) ~= "string" then return false end
    local key = string.lower(k)
    return string.find(key, "guild", 1, true) or string.find(key, "vault", 1, true)
  end

  local function ExtractCharacterName(k)
    if type(k) ~= "string" then return nil end
    local name = string.match(k, "^(.-)%s%-%s")
    if name and name ~= "" then return name end
    return k
  end

  local bb, source = DetectBagDb()
  if type(bb) ~= "table" then
    local bbLoaded = IsAddOnLoadedSafe("BagBrother")
    local bagnonLoaded = IsAddOnLoadedSafe("Bagnon")
    DebugPrint("Owned export: bag DB not found (BagBrother loaded=" .. tostring(bbLoaded) .. ", Bagnon loaded=" .. tostring(bagnonLoaded) .. "). Attempting LoadAddOn(BagBrother)...")
    LoadAddOnSafe("BagBrother")
    bb, source = DetectBagDb()
  end

  if type(bb) ~= "table" then
    return nil, nil, "BagBrother/Bagnon data not found. Expected global BrotherBags (preferred) or BagBrother/BagnonDB. If you have Bagnon/BagBrother installed, enable BagBrother and /reload. Use /frugalscan owneddebug for diagnostics."
  end

  local realmName = GetRealmName()
  local charRoots = {}

  if source == "BrotherBags" or source == "BagBrother" then
    local realmTable = bb[realmName] or bb[string.lower(realmName)] or bb[NormalizeRealmSlug(realmName)]
    if type(realmTable) == "table" then
      for k, v in pairs(realmTable) do
        if type(v) == "table" and (not IsGuildLikeKey(k)) then
          table.insert(charRoots, { name = ExtractCharacterName(k), node = v })
        end
      end
    end
  elseif source == "BagnonDB" or source == "BagnonDB2" or source == "BagnonDB3" then
    if type(bb.characters) == "table" then
      local suffix = " - " .. tostring(realmName)
      for k, v in pairs(bb.characters) do
        if type(k) == "string" and type(v) == "table" and string.sub(k, -string.len(suffix)) == suffix and (not IsGuildLikeKey(k)) then
          table.insert(charRoots, { name = ExtractCharacterName(k), node = v })
        end
      end
    end
  end

  if #charRoots == 0 then
    return nil, nil, "Owned export: could not find realm-specific section in " .. tostring(source) .. ". Refusing to scan entire DB to avoid counting guild bank/other realms. Use /frugalscan owneddebug for diagnostics."
  else
    DebugPrint("Owned export: using " .. tostring(source) .. " realm=\"" .. tostring(realmName) .. "\" characters=" .. tostring(#charRoots))
  end

  local function WalkCounts(node, counts, visited)
    local tt = type(node)
    if tt == "table" then
      if visited[node] then return end
      visited[node] = true
      for k, v in pairs(node) do
        if not IsGuildLikeKey(k) then
          WalkCounts(v, counts, visited)
        end
      end
      return
    end

    if tt == "string" then
      local itemId, qty = ParseItemRef(node)
      if itemId and qty and wantedSet[itemId] then
        counts[itemId] = (counts[itemId] or 0) + qty
      end
    end
  end

  local totals = {}
  local byCharacter = {}

  for _, c in ipairs(charRoots) do
    local counts = {}
    WalkCounts(c.node, counts, {})
    if next(counts) ~= nil then
      byCharacter[c.name or "Unknown"] = counts
      for itemId, qty in pairs(counts) do
        totals[itemId] = (totals[itemId] or 0) + qty
      end
    end
  end

  return totals, byCharacter, nil
end

local function BuildOwnedCountsFromBagBrother(wantedSet)
  local totals, _, err = BuildOwnedCountsByCharacterFromBagBrother(wantedSet)
  return totals, err
end

local function OwnedDebug()
  local realmName = GetRealmName()
  Print("Owned debug: realm=\"" .. tostring(realmName) .. "\" slug=\"" .. tostring(NormalizeRealmSlug(realmName)) .. "\"")
  local function IsAddOnLoadedSafe(addonName)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
      return C_AddOns.IsAddOnLoaded(addonName)
    end
    if IsAddOnLoaded then
      return IsAddOnLoaded(addonName)
    end
    return nil
  end

  Print("AddOns: Bagnon loaded=" .. tostring(IsAddOnLoadedSafe("Bagnon")) .. ", BagBrother loaded=" .. tostring(IsAddOnLoadedSafe("BagBrother")))
  Print("Globals: BrotherBags=" .. tostring(type(_G and _G.BrotherBags)) .. ", BagBrother=" .. tostring(type(_G and _G.BagBrother)) .. ", BagnonDB=" .. tostring(type(_G and _G.BagnonDB)))

  local function DumpTableKeys(label, t)
    if type(t) ~= "table" then
      Print(label .. ": (not a table)")
      return
    end
    local n = 0
    local sample = {}
    for k, _ in pairs(t) do
      n = n + 1
      if #sample < 8 then
        table.insert(sample, tostring(k))
      end
    end
    Print(label .. ": keys=" .. tostring(n) .. " sample=[" .. table.concat(sample, ", ") .. "]")
  end

  DumpTableKeys("BrotherBags", _G and _G.BrotherBags or nil)
  DumpTableKeys("BagBrother", _G and _G.BagBrother or nil)
  DumpTableKeys("BagnonDB.characters", (_G and _G.BagnonDB and _G.BagnonDB.characters) or nil)
end

local function BuildOwnedExportJsonFromCounts(snapshot, items, characters)
  local parts = {}
  table.insert(parts, '{"schema":"wowahplanner-owned-v1"')
  table.insert(parts, ',"snapshotTimestampUtc":"' .. (snapshot.snapshotTimestampUtc or "") .. '"')
  table.insert(parts, ',"realmName":"' .. (snapshot.realmName or "") .. '"')
  if snapshot.region then
    table.insert(parts, ',"region":"' .. tostring(snapshot.region) .. '"')
  end
  if snapshot.gameVersion then
    table.insert(parts, ',"gameVersion":"' .. tostring(snapshot.gameVersion) .. '"')
  end
  if snapshot.realmSlug then
    table.insert(parts, ',"realmSlug":"' .. tostring(snapshot.realmSlug) .. '"')
  end
  if type(characters) == "table" then
    table.insert(parts, ',"characters":[')
    for cIdx, ch in ipairs(characters) do
      if cIdx > 1 then table.insert(parts, ",") end
      table.insert(parts, '{"name":"' .. tostring(ch.name or "") .. '","items":[')
      for i, it in ipairs(ch.items or {}) do
        if i > 1 then table.insert(parts, ",") end
        table.insert(parts, string.format('{"itemId":%d,"qty":%d}', it.itemId, it.qty or 0))
      end
      table.insert(parts, "]}")
    end
    table.insert(parts, "]")
  end
  table.insert(parts, ',"items":[')

  for i, it in ipairs(items or {}) do
    if i > 1 then table.insert(parts, ",") end
    table.insert(parts, string.format('{"itemId":%d,"qty":%d}', it.itemId, it.qty or 0))
  end

  table.insert(parts, "]}")
  return table.concat(parts)
end

local exportFrame
local ShowExportFrame

local function ExportOwned()
  EnsureDb()

  local wantedSet, wantedCount = BuildWantedItemIdSet()
  if wantedCount == 0 then
    Print("No target itemIds loaded. Open /frugal, choose a profession, and Build Targets.")
    return
  end

  local counts, byCharacter, err = BuildOwnedCountsByCharacterFromBagBrother(wantedSet)
  if not counts then
    Print("Owned export failed: " .. tostring(err))
    return
  end

  local realmName = GetRealmName()
  local realmSlug = NormalizeRealmSlug(realmName)
  local region = DetectRegion()

  local items = {}
  for itemId, qty in pairs(counts) do
    if qty and qty > 0 then
      table.insert(items, { itemId = itemId, qty = qty })
    end
  end
  table.sort(items, function(a, b) return a.itemId < b.itemId end)

  local snapshot = {
    schema = "wowahplanner-owned-v1",
    snapshotTimestampUtc = date("!%Y-%m-%dT%H:%M:%SZ", time()),
    realmName = realmName,
    realmSlug = realmSlug,
    region = region,
    gameVersion = FrugalScan_TargetGameVersion,
    itemCount = #(items or {}),
    items = items,
  }

  local characters = {}
  if type(byCharacter) == "table" then
    local names = {}
    for name, _ in pairs(byCharacter) do table.insert(names, name) end
    table.sort(names, function(a, b) return tostring(a) < tostring(b) end)
    for _, name in ipairs(names) do
      local cItems = {}
      for itemId, qty in pairs(byCharacter[name] or {}) do
        if qty and qty > 0 then
          table.insert(cItems, { itemId = itemId, qty = qty })
        end
      end
      table.sort(cItems, function(a, b) return a.itemId < b.itemId end)
      table.insert(characters, { name = name, items = cItems })
    end
  end

  local json = BuildOwnedExportJsonFromCounts(snapshot, items, characters)
  FrugalScanDB.lastOwnedSnapshot = snapshot
  if type(FrugalForgeDB) == "table" then
    FrugalForgeDB.lastOwnedSnapshot = snapshot
  end
  FrugalScanDB.lastOwnedJson = json
  Print("Owned items imported (" .. tostring(snapshot.itemCount or 0) .. " items).")
end

ShowExportFrame = function(textOverride, titleOverride)
  local text = textOverride
  local titleText = titleOverride
  if not text then
    text = BuildExportJson()
    titleText = titleText or "FrugalScan Export"
    if not text then
      Print("No snapshot found yet. Run /frugalscan start (or /frugal scan) first.")
      return
    end
  else
    titleText = titleText or "FrugalScan Log"
  end

  if not exportFrame then
    exportFrame = CreateFrame("Frame", "FrugalScanExportFrame", UIParent, "BackdropTemplate")
    exportFrame:SetSize(700, 450)
    exportFrame:SetPoint("CENTER")
    exportFrame:SetMovable(true)
    exportFrame:EnableMouse(true)
    exportFrame:RegisterForDrag("LeftButton")
    exportFrame:SetScript("OnDragStart", exportFrame.StartMoving)
    exportFrame:SetScript("OnDragStop", exportFrame.StopMovingOrSizing)

    exportFrame:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })

    local title = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    exportFrame.title = title

    local close = CreateFrame("Button", nil, exportFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -8, -8)

    local scroll = CreateFrame("ScrollFrame", nil, exportFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -48)
    scroll:SetPoint("BOTTOMRIGHT", -36, 16)

    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(640)
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEscapePressed", function() exportFrame:Hide() end)
    scroll:SetScrollChild(editBox)

    exportFrame.editBox = editBox
  end

  if exportFrame.title then
    exportFrame.title:SetText(titleText)
  end

  exportFrame.editBox:SetText(text)
  exportFrame.editBox:HighlightText()
  exportFrame:Show()
end

local function QueueItems()
  state.queue = {}
  local function FilterQueue()
    if #state.queue == 0 then return end
    local filtered = {}
    local seen = {}
    for _, itemId in ipairs(state.queue) do
      if type(itemId) == "number" and itemId > 0 and IsScanQualityAllowed(itemId) and not IsVendorItem(itemId) and not seen[itemId] then
        seen[itemId] = true
        table.insert(filtered, itemId)
      end
    end
    state.queue = filtered
  end
  local function TryQueue(itemId)
    if type(itemId) == "number" and itemId > 0 and IsScanQualityAllowed(itemId) and not IsVendorItem(itemId) then
      table.insert(state.queue, itemId)
    end
  end

  if FrugalScan_ForceTargetItemIds == true then
    FrugalScan_ForceTargetItemIds = nil
    state.mergeWithLast = true
    local targets = _G.FrugalScan_TargetItemIds or {}
    if type(targets) ~= "table" then targets = {} end
    for _, itemId in ipairs(targets) do
      TryQueue(itemId)
    end
    if #state.queue == 0 then
      Print("Queued 0 items. Missing-price list was empty.")
    else
      table.sort(state.queue, function(a, b) return a < b end)
      FilterQueue()
      Print("Queued " .. tostring(#state.queue) .. " missing-price items.")
    end
    state.total = #state.queue
    UpdateStatus()
    return
  end

  state.mergeWithLast = false

  local recipeTargets = FrugalScan_RecipeTargets
  local professionId = FrugalScan_TargetProfessionId
  local professionName = FrugalScan_TargetProfessionName
  if type(_G.FrugalForgeDB) == "table" and (type(_G.FrugalForgeDB.scanTargets) == "table" or type(_G.FrugalForgeDB.targets) == "table") then
    local t = _G.FrugalForgeDB.scanTargets or _G.FrugalForgeDB.targets
    if type(t.targets) == "table" and #t.targets > 0 then
      recipeTargets = t.targets
    end
    if t.professionId then professionId = t.professionId end
    if t.professionName then professionName = t.professionName end
  end
  local maxSkillDelta = tonumber(GetSetting("maxSkillDelta", 100)) or 100
  DebugPrint("targets profId=" .. tostring(professionId) .. ", name=" .. tostring(professionName) .. ", recipes=" .. tostring(type(recipeTargets) == "table" and #recipeTargets or 0))
  if maxSkillDelta < 0 then maxSkillDelta = 0 end

  local wantById = type(professionId) == "number"
  local wantByName = type(professionName) == "string" and professionName ~= ""
  local targetNameNorm = NormalizeProfessionName(professionName)

  if type(recipeTargets) == "table" and (wantById or wantByName) then
    local skillLevel = nil
    local maxSkillLevel = nil

    if GetProfessions and GetProfessionInfo then
      local primary1, primary2, archaeology, fishing, cooking, firstAid = GetProfessions()
      local profs = { primary1, primary2, archaeology, fishing, cooking, firstAid }

      for _, idx in ipairs(profs) do
        if idx then
          local name, _, sLevel, mLevel, _, _, skillLine = GetProfessionInfo(idx)
          local nameNorm = NormalizeProfessionName(name)
          local nameMatch = wantByName and nameNorm and targetNameNorm and nameNorm == targetNameNorm
          local idMatch = wantById and skillLine == professionId
          if nameMatch or idMatch then
            skillLevel = sLevel
            maxSkillLevel = mLevel
            break
          end
        end
      end
    end

    if (not skillLevel or not maxSkillLevel) and wantByName then
      -- Some clients return nil from GetProfessions() unless profession UI is opened/loaded.
      local rank, maxRank = TryGetSkillLineByName(professionName)
      if rank and maxRank then
        skillLevel = rank
        maxSkillLevel = maxRank
      end
    end

    if not skillLevel or not maxSkillLevel then
      Print("You do not have the target profession (id=" .. tostring(professionId) .. ", name=" .. tostring(professionName) .. "). Queueing all target reagents.")

      local itemSet = {}
      for _, r in ipairs(recipeTargets) do
        if type(r) == "table" then
          local reagents = r.reagents
          if type(reagents) == "table" then
            for _, itemId in ipairs(reagents) do
              if type(itemId) == "number" and itemId > 0 and IsScanQualityAllowed(itemId) and not IsVendorItem(itemId) then
                itemSet[itemId] = true
              end
            end
          end
        end
      end

      for itemId, _ in pairs(itemSet) do
        table.insert(state.queue, itemId)
      end

      table.sort(state.queue, function(a, b) return a < b end)
      FilterQueue()
      if #state.queue > 0 then
        Print("Queued " .. tostring(#state.queue) .. " items from full target list.")
        state.total = #state.queue
        UpdateStatus()
        return
      end

      Print("No reagent itemIds found in targets. Falling back to legacy target list if present.")
    else
      local cap = tonumber(GetSetting("expansionCapSkill", 350)) or 350
      if cap < skillLevel then cap = skillLevel end

      local targetSkill = nil
      if FrugalForgeDB and FrugalForgeDB.settings and tonumber(FrugalForgeDB.settings.targetSkill) then
        targetSkill = tonumber(FrugalForgeDB.settings.targetSkill)
      elseif FrugalScanDB and FrugalScanDB.settings and tonumber(FrugalScanDB.settings.targetSkill) then
        targetSkill = tonumber(FrugalScanDB.settings.targetSkill)
      end

      local upper = targetSkill or (skillLevel + maxSkillDelta)
      if upper < skillLevel then upper = skillLevel end
      if upper > cap then upper = cap end

      local itemSet = {}
      local recipesInWindow = 0
      for _, r in ipairs(recipeTargets) do
        if type(r) == "table" then
          local minSkill = tonumber(r.minSkill) or 0
          local grayAt = tonumber(r.grayAt) or 0
          if minSkill <= upper and grayAt > skillLevel then
            recipesInWindow = recipesInWindow + 1
            local reagents = r.reagents
            if type(reagents) == "table" then
              for _, itemId in ipairs(reagents) do
                if type(itemId) == "number" and itemId > 0 and IsScanQualityAllowed(itemId) and not IsVendorItem(itemId) then
                  itemSet[itemId] = true
                end
              end
            end
          end
        end
      end

      for itemId, _ in pairs(itemSet) do
        table.insert(state.queue, itemId)
      end

      table.sort(state.queue, function(a, b) return a < b end)
      FilterQueue()
      if #state.queue > 0 then
        Print("Queued " .. tostring(#state.queue) .. " items for skill " .. tostring(skillLevel) .. " -> " .. tostring(upper) .. " (target=" .. tostring(targetSkill or "delta " .. tostring(maxSkillDelta)) .. ", cap=" .. tostring(cap) .. ").")
        state.total = #state.queue
        UpdateStatus()
        return
      end

      Print("No recipe reagents found in your skill window (recipesInWindow=" .. tostring(recipesInWindow) .. "). Falling back to full pack reagents (if available).")
    end
  end

  local targets = _G.FrugalScan_TargetItemIds or {}
  if type(targets) ~= "table" then targets = {} end

  for _, itemId in ipairs(targets) do
    TryQueue(itemId)
  end

  FilterQueue()
  state.total = #state.queue
  UpdateStatus()

  if #state.queue == 0 then
    Print("Queued 0 items. Targets not loaded or empty. Use /frugal to build targets, then scan again.")
  else
    Print("Queued " .. tostring(#state.queue) .. " items.")
  end
end

local function QueryCurrentPage()
  if not state.currentItemId then return end
  if not IsAtAuctionHouse() then
    Print("Auction House is not open.")
    state.running = false
    return
  end

  EnsureBrowseTab()
  if not IsBrowseTabVisible() then
    DebugPrint("Browse tab not visible after EnsureBrowseTab()")
  end

  state.maxPages = tonumber(GetSetting("maxPagesPerItem", 10)) or state.maxPages
  state.delaySeconds = tonumber(GetSetting("minQueryIntervalSeconds", 3)) or state.delaySeconds

  if not CanQuery() then
    state.canQueryFalseCount = (state.canQueryFalseCount or 0) + 1
    local wait = state.delaySeconds
    if state.canQueryFalseCount > 1 then
      wait = math.min(15, state.delaySeconds + (state.canQueryFalseCount - 1))
    end
    DebugPrint("CanSendAuctionQuery=false; waiting " .. tostring(wait) .. "s (count=" .. tostring(state.canQueryFalseCount) .. ")")
    C_Timer.After(wait, QueryCurrentPage)
    return
  end
  state.canQueryFalseCount = 0

  if state.lastQueryAt then
    local elapsed = GetTime() - state.lastQueryAt
    if elapsed < state.delaySeconds then
      C_Timer.After(state.delaySeconds - elapsed, QueryCurrentPage)
      return
    end
  end

  local itemName = EnsureItemName(state.currentItemId)
  if not itemName then
    state.pendingItemInfoId = state.currentItemId
    DebugPrint("Item name not cached yet for itemId=" .. tostring(state.currentItemId))
    C_Timer.After(math.max(1, state.delaySeconds), QueryCurrentPage)
    return
  end

  state.currentQueryName = itemName
  local searchText = "\"" .. tostring(itemName) .. "\""
  DebugPrint("PreQuery: atAH=" .. tostring(IsAtAuctionHouse()) ..
    ", browseVisible=" .. tostring(IsBrowseTabVisible()) ..
    ", canQuery=" .. tostring(CanQuery()) ..
    ", lastQueryAt=" .. tostring(state.lastQueryAt) ..
    ", timeoutRetries=" .. tostring(state.timeoutRetries or 0))

  state.awaiting = true
  state.lastQueryAt = GetTime()
  state.lastQueryToken = (state.lastQueryToken or 0) + 1
  local thisToken = state.lastQueryToken
  DebugPrint("QueryAuctionItems(itemId=" .. tostring(state.currentItemId) ..
    ", itemName=\"" .. tostring(itemName) ..
    "\", search=" .. tostring(searchText) ..
    ", page=" .. tostring(state.page) .. ")")

  local sent = false

  -- Prefer UI search with quoted term: the built-in AH search treats quotes as exact and behaves better than QueryAuctionItems on some clients.
  if state.page == 0 then
    sent = TrySendBrowseQueryViaUi(searchText, itemName)
    if sent then state.lastSendMethod = "ui" end
  elseif state.lastSendMethod == "ui" then
    sent = TryNextPageViaUi()
  end

  if not sent then
    -- Fallback to QueryAuctionItems if UI controls are missing.
    if QueryAuctionItems then
      -- Use explicit numeric defaults for legacy Classic clients.
      local ok, err = pcall(QueryAuctionItems, searchText, 0, 0, 0, 0, 0, state.page, false, 0, false, true) -- exactMatch=true
      if ok then
        sent = true
        state.lastSendMethod = "api"
        DebugPrint("Sent query via QueryAuctionItems(): search=" .. tostring(searchText) .. ", page=" .. tostring(state.page) .. ", exactMatch=true")
      else
        DebugPrint("QueryAuctionItems error: " .. tostring(err))
      end
    end
  end

  if not sent then
    Print("Unable to send auction query (no supported API/UI found).")
    state.running = false
    state.awaiting = false
    return
  end

  local timeout = tonumber(GetSetting("queryTimeoutSeconds", 10)) or 10
  if timeout < 3 then timeout = 3 end
  C_Timer.After(timeout, function()
    if state.running and state.awaiting and state.lastQueryToken == thisToken then
      state.awaiting = false
      state.timeoutRetries = (state.timeoutRetries or 0) + 1
      local maxRetries = tonumber(GetSetting("maxTimeoutRetriesPerPage", 3)) or 3
      if maxRetries < 0 then maxRetries = 0 end

      if state.timeoutRetries > maxRetries then
        Print("Query timeout (itemId=" .. tostring(state.currentItemId) ..
          ", name=\"" .. tostring(state.currentQueryName) ..
          "\", page=" .. tostring(state.page) ..
          "). Skipping item after " .. tostring(maxRetries) .. " retries.")
        state.currentItemId = nil
        state.page = 0
        C_Timer.After(state.delaySeconds, NextItem)
        return
      end

      Print("Query timeout (itemId=" .. tostring(state.currentItemId) ..
        ", name=\"" .. tostring(state.currentQueryName) ..
        "\", page=" .. tostring(state.page) ..
        "). Retrying (" .. tostring(state.timeoutRetries) .. "/" .. tostring(maxRetries) .. ")...")
      C_Timer.After(state.delaySeconds * 2, QueryCurrentPage)
    end
  end)
end

local function NextItem()
  if not state.running then return end

  if #state.queue == 0 then
    FinishSnapshot()
    return
  end

  state.currentItemId = table.remove(state.queue, 1)
  state.currentQueryName = nil
  state.lastSendMethod = nil
  state.foundAnyForItem = false
  state.page = 0
  state.awaiting = false
  state.timeoutRetries = 0
  UpdateStatus()
  QueryCurrentPage()
end

local function ProcessCurrentPage()
  if not state.currentItemId then return end

  local shown, total = GetNumAuctionItems("list")
  local itemId = state.currentItemId
  local matched = 0
  local idMatches = 0
  local nameMatches = 0
  local buyoutMissing = 0
  local rank = 3

  for i = 1, shown do
    local auctionName, count, minBid, buyoutPrice, _ = ExtractAuctionRow("list", i)
    local link = GetAuctionItemLink("list", i)
    local id = ParseItemIdFromLink(link)

    local isExactNameMatch = (auctionName and state.currentQueryName and auctionName == state.currentQueryName)
    local isExactIdMatch = (id == itemId)

    -- Prefer ID match; fall back to exact name match if links aren't available / parsable on this client.
    if isExactIdMatch then idMatches = idMatches + 1 end
    if isExactNameMatch then nameMatches = nameMatches + 1 end
    if (isExactIdMatch or (not id and isExactNameMatch)) and (not buyoutPrice or buyoutPrice <= 0) then
      buyoutMissing = buyoutMissing + 1
    end

    if (isExactIdMatch or (not id and isExactNameMatch)) and count and count > 0 then
      -- Always use buyout for pricing. Bid-only auctions are ignored to avoid underpricing.
      local price = buyoutPrice
      if price and price > 0 then
        local unit = math.floor(price / count)
      local entry = state.prices[itemId]
      if not entry then
        entry = { minUnitBuyoutCopper = unit, totalQuantity = 0, bestUnits = {}, minSeen = unit }
        state.prices[itemId] = entry
      end
      if unit < entry.minSeen then entry.minSeen = unit end
      InsertSortedLimited(entry.bestUnits, unit, rank)
      entry.totalQuantity = entry.totalQuantity + count
      matched = matched + 1
      elseif FrugalScanDB and FrugalScanDB.settings and FrugalScanDB.settings.verboseDebug and (isExactIdMatch or (not id and isExactNameMatch)) then
        DebugPrint("No buyout for match: name=\"" .. tostring(auctionName) .. "\", count=" .. tostring(count) ..
          ", minBid=" .. tostring(minBid) .. ", buyout=" .. tostring(buyoutPrice) .. ", linkId=" .. tostring(id))
      end
    end
  end

  if matched == 0 then
    DebugPrint("No matches found in results for itemId=" .. tostring(itemId) ..
      " on page=" .. tostring(state.page) ..
      " (shown=" .. tostring(shown) ..
      ", idMatches=" .. tostring(idMatches) ..
      ", nameMatches=" .. tostring(nameMatches) ..
      ", buyoutMissing=" .. tostring(buyoutMissing) ..
      ", queryName=\"" .. tostring(state.currentQueryName) .. "\")")

    if FrugalScanDB and FrugalScanDB.settings and FrugalScanDB.settings.verboseDebug and shown > 0 then
      local n, c, mb, bo, fields = ExtractAuctionRow("list", 1)
      local l = GetAuctionItemLink("list", 1)
      local pid = ParseItemIdFromLink(l)
      DebugPrint("First row: name=\"" .. tostring(n) .. "\", count=" .. tostring(c) .. ", minBid=" .. tostring(mb) .. ", buyout=" .. tostring(bo) ..
        ", linkId=" .. tostring(pid) .. ", fieldsLen=" .. tostring(#fields))
    end
  else
    DebugPrint("Matched " .. tostring(matched) .. " auctions for itemId=" .. tostring(itemId) .. " on page=" .. tostring(state.page))
    state.foundAnyForItem = true
  end

  local nextPageExists = total and total > (state.page + 1) * 50
  if nextPageExists and (state.lastSendMethod == "ui") then
    -- UI-driven searches reliably populate page 0. Some items may not appear on the first page (e.g. query matches many names).
    -- Page forward only until we find at least one match, then stop to avoid long scans and throttling.
    if (not state.foundAnyForItem) and state.page < state.maxPages then
      state.page = state.page + 1
      state.timeoutRetries = 0
      C_Timer.After(state.delaySeconds, QueryCurrentPage)
      return
    end

    if not state.foundAnyForItem then
      DebugPrint("UI pagination exhausted without finding itemId=" .. tostring(itemId) .. " (maxPages=" .. tostring(state.maxPages) .. ").")
    end

    state.currentItemId = nil
    C_Timer.After(state.delaySeconds, NextItem)
    return
  end

  if nextPageExists and state.page < state.maxPages then
    state.page = state.page + 1
    state.timeoutRetries = 0
    C_Timer.After(state.delaySeconds, QueryCurrentPage)
  else
    state.currentItemId = nil
    C_Timer.After(state.delaySeconds, NextItem)
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
frame:RegisterEvent("UI_ERROR_MESSAGE")
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "AUCTION_ITEM_LIST_UPDATE" and state.running and state.awaiting then
    state.awaiting = false
    state.timeoutRetries = 0
    local shown, total = GetNumAuctionItems("list")
    DebugPrint("AUCTION_ITEM_LIST_UPDATE: shown=" .. tostring(shown) .. ", total=" .. tostring(total) .. ", itemId=" .. tostring(state.currentItemId) .. ", page=" .. tostring(state.page))
    ProcessCurrentPage()
    return
  end

  if event == "GET_ITEM_INFO_RECEIVED" and state.running and state.pendingItemInfoId then
    local receivedItemId = ...
    if not receivedItemId or receivedItemId == state.pendingItemInfoId then
      local name = GetItemInfo(state.pendingItemInfoId)
      if name then
        DebugPrint("GET_ITEM_INFO_RECEIVED: itemId=" .. tostring(state.pendingItemInfoId) .. " name=\"" .. tostring(name) .. "\"")
        state.pendingItemInfoId = nil
        C_Timer.After(0.1, QueryCurrentPage)
      end
    end
    return
  end

  if event == "UI_ERROR_MESSAGE" and state.running and state.awaiting then
    local _, msg = ...
    if not msg then
      msg = ...
    end
    if msg then
      DebugPrint("UI_ERROR_MESSAGE while awaiting query: " .. tostring(msg))
    end
    return
  end
end)

local function StartScan(queueOverride)
  if not IsAtAuctionHouse() then
    Print("Open the Auction House first.")
    return
  end

  EnsureBrowseTab()
  if type(queueOverride) == "table" then
    state.queue = {}
    for _, itemId in ipairs(queueOverride) do
      if type(itemId) == "number" and itemId > 0 and IsScanQualityAllowed(itemId) then
        table.insert(state.queue, itemId)
      end
    end
    state.total = #state.queue
    UpdateStatus()

    if #state.queue == 0 then
      Print("No valid itemIds provided.")
      return
    end

    Print("Queued " .. tostring(#state.queue) .. " manual item(s).")
  else
    QueueItems()
  end

  if #state.queue == 0 then
    Print("No targets loaded. Use /frugal to build targets, then scan again.")
    return
  end

  StartSnapshot()
  state.running = true
  UpdateStatus()
  Print("Starting scan...")
  NextItem()
end

local function StopScan()
  state.running = false
  state.awaiting = false
  state.queue = {}
  state.currentItemId = nil
  state.total = 0
  UpdateStatus()
  Print("Stopped.")
end

SLASH_FRUGALSCAN1 = "/frugalscan"
SlashCmdList["FRUGALSCAN"] = function(msg)
  EnsureDb()
  local cmd, rest = FirstWord(msg)
  cmd = string.lower(cmd or "")
  rest = Trim(rest or "")

  if cmd == "start" then
    StartScan()
    return
  end

  if cmd == "item" or cmd == "scanitem" then
    if rest == "" then
      Print("Usage: /frugalscan item <itemId|itemLink>")
      return
    end

    local itemId = ParseItemIdFromLink(rest)
    if not itemId then
      local n = tonumber(rest)
      if n and n > 0 then itemId = n end
    end

    if not itemId or itemId <= 0 then
      Print("Could not parse itemId from: " .. tostring(rest))
      return
    end

    Print("Manual scan queued: itemId=" .. tostring(itemId) .. " (name=\"" .. tostring(EnsureItemName(itemId) or "") .. "\")")
    StartScan({ itemId })
    return
  end

  if cmd == "stop" then
    StopScan()
    return
  end

  if cmd == "status" then
    Print("running=" .. tostring(state.running) ..
      ", remaining=" .. tostring(#state.queue) ..
      ", current=" .. tostring(state.currentItemId) ..
      ", verboseDebug=" .. tostring(GetSetting("verboseDebug", false)))
    return
  end

  if cmd == "options" then
    OpenOptionsUi()
    return
  end

  if cmd == "panel" then
    Print("Scan panel removed. Use /frugal for controls.")
    return
  end

  if cmd == "log" then
    local log = FrugalScanDB.debugLog or {}
    local text = table.concat(log, "\n")
    if text == "" then
      Print("Log is empty.")
      return
    end
    ShowExportFrame(text, "FrugalScan Log")
    return
  end

  if cmd == "clearlog" then
    FrugalScanDB.debugLog = {}
    Print("Log cleared.")
    return
  end

  if cmd == "verbose" or cmd == "v" then
    FrugalScanDB.settings.verboseDebug = not (FrugalScanDB.settings.verboseDebug == true)
    Print("Verbose debug = " .. tostring(FrugalScanDB.settings.verboseDebug))
    return
  end

  if cmd == "debug" then
    Print("Target id=" .. tostring(FrugalScan_TargetProfessionId) .. ", name=" .. tostring(FrugalScan_TargetProfessionName))
    Print("Settings: maxSkillDelta=" .. tostring(GetSetting("maxSkillDelta", 100)) ..
      ", expansionCapSkill=" .. tostring(GetSetting("expansionCapSkill", 350)) ..
      ", maxPagesPerItem=" .. tostring(GetSetting("maxPagesPerItem", 10)) ..
      ", minQueryIntervalSeconds=" .. tostring(GetSetting("minQueryIntervalSeconds", 3)) ..
      ", queryTimeoutSeconds=" .. tostring(GetSetting("queryTimeoutSeconds", 10)) ..
      ", maxTimeoutRetriesPerPage=" .. tostring(GetSetting("maxTimeoutRetriesPerPage", 3)) ..
      ", verboseDebug=" .. tostring(GetSetting("verboseDebug", false)))
    Print("APIs: QueryAuctionItems=" .. tostring(QueryAuctionItems ~= nil) ..
      ", CanSendAuctionQuery=" .. tostring(CanSendAuctionQuery ~= nil) ..
      ", InterfaceOptions_AddCategory=" .. tostring(InterfaceOptions_AddCategory ~= nil) ..
      ", Settings=" .. tostring(Settings ~= nil) ..
      ", AuctionFrame=" .. tostring(AuctionFrame ~= nil) ..
      ", AuctionFrameBrowse=" .. tostring(AuctionFrameBrowse ~= nil) ..
      ", BrowseName=" .. tostring(BrowseName ~= nil) ..
      ", BrowseSearchButton=" .. tostring(BrowseSearchButton ~= nil) ..
      ", AuctionFrameBrowse_SearchButton=" .. tostring(AuctionFrameBrowse_SearchButton ~= nil) ..
      ", BrowseNextPageButton=" .. tostring(BrowseNextPageButton ~= nil))
    if GetProfessions and GetProfessionInfo then
      local primary1, primary2, archaeology, fishing, cooking, firstAid = GetProfessions()
      local profs = { primary1, primary2, archaeology, fishing, cooking, firstAid }
      Print("GetProfessions() => " .. tostring(primary1) .. ", " .. tostring(primary2) .. ", " .. tostring(archaeology) .. ", " .. tostring(fishing) .. ", " .. tostring(cooking) .. ", " .. tostring(firstAid))
      for _, idx in ipairs(profs) do
        if idx then
          local name, _, sLevel, mLevel, _, _, skillLine = GetProfessionInfo(idx)
          Print("Have (profession slots): name=" .. tostring(name) .. ", skillLine=" .. tostring(skillLine) .. ", skill=" .. tostring(sLevel) .. "/" .. tostring(mLevel))
        end
      end
    else
      Print("GetProfessions/GetProfessionInfo not available.")
    end

    if GetNumSkillLines and GetSkillLineInfo then
      local num = GetNumSkillLines() or 0
      Print("GetNumSkillLines() => " .. tostring(num))
      for i = 1, num do
        local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
        if not isHeader then
          Print("Have (skill lines): name=" .. tostring(name) .. ", skill=" .. tostring(rank) .. "/" .. tostring(maxRank))
        end
      end
    else
      Print("GetNumSkillLines/GetSkillLineInfo not available.")
    end
    return
  end

  if cmd == "export" then
    ShowExportFrame()
    return
  end

  if cmd == "owned" then
    ExportOwned()
    return
  end

  if cmd == "owneddebug" then
    OwnedDebug()
    return
  end

  Print("Commands: /frugalscan start | item <id|link> | stop | status | export | owned | owneddebug | options | log | clearlog | debug | verbose")
end

TryRegisterOptions = function() end
-- Options UI removed; FrugalScan no longer registers settings panels.
