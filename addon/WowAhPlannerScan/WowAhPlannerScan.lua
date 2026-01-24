local ADDON_NAME = ...
local OPTIONS_FRAME_NAME = "WowAhPlannerScanOptionsFrame"

local function EnsureDb()
  if type(WowAhPlannerScanDB) ~= "table" then
    WowAhPlannerScanDB = {}
  end
  if type(WowAhPlannerScanDB.settings) ~= "table" then
    WowAhPlannerScanDB.settings = {}
  end
  if type(WowAhPlannerScanDB.debugLog) ~= "table" then
    WowAhPlannerScanDB.debugLog = {}
  end

  local s = WowAhPlannerScanDB.settings
  if type(s.maxSkillDelta) ~= "number" then s.maxSkillDelta = 100 end
  if type(s.expansionCapSkill) ~= "number" then s.expansionCapSkill = 350 end
  if type(s.maxPagesPerItem) ~= "number" then s.maxPagesPerItem = 10 end
  if type(s.minQueryIntervalSeconds) ~= "number" then s.minQueryIntervalSeconds = 3 end
  if type(s.queryTimeoutSeconds) ~= "number" then s.queryTimeoutSeconds = 10 end
  if type(s.maxTimeoutRetriesPerPage) ~= "number" then s.maxTimeoutRetriesPerPage = 3 end
  if type(s.priceRank) ~= "number" then s.priceRank = 3 end

  s.showPanelOnAuctionHouse = (s.showPanelOnAuctionHouse ~= false)
  s.verboseDebug = (s.verboseDebug == true)
end

EnsureDb()

local TryRegisterOptions = nil

local function AppendLog(line)
  EnsureDb()
  local log = WowAhPlannerScanDB.debugLog
  if type(log) ~= "table" then
    WowAhPlannerScanDB.debugLog = {}
    log = WowAhPlannerScanDB.debugLog
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
  DEFAULT_CHAT_FRAME:AddMessage("|cff7dd3fcWowAhPlannerScan|r: " .. tostring(msg))
end

local function DebugPrint(msg)
  EnsureDb()
  if WowAhPlannerScanDB and WowAhPlannerScanDB.settings and WowAhPlannerScanDB.settings.verboseDebug then
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
  currentItemId = nil,
  currentQueryName = nil,
  page = 0,
  maxPages = 10,
  delaySeconds = 2.0,
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

local function GetSetting(name, defaultValue)
  local settings = WowAhPlannerScanDB and WowAhPlannerScanDB.settings or nil
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
  if TryRegisterOptions then
    TryRegisterOptions()
  end
  DebugPrint("OpenOptionsUi()")

  if Settings and Settings.OpenToCategory then
    local id = WowAhPlannerScanDB and WowAhPlannerScanDB._settingsCategoryId or nil

    local function TryOpen()
      pcall(Settings.OpenToCategory, "AddOns")
      if state and state.settingsCategory then
        pcall(Settings.OpenToCategory, state.settingsCategory)
        return
      end
      if id then
        pcall(Settings.OpenToCategory, id)
        return
      end
      pcall(Settings.OpenToCategory, "WowAhPlannerScan")
    end

    TryOpen()
    if C_Timer and C_Timer.After then
      C_Timer.After(0, TryOpen)
      C_Timer.After(0.05, TryOpen)
      C_Timer.After(0.15, TryOpen)
    end
    return
  end

  if InterfaceOptionsFrame_OpenToCategory then
    local frame = _G[OPTIONS_FRAME_NAME]
    if InterfaceOptionsFrame and InterfaceOptionsFrame.Show then
      InterfaceOptionsFrame:Show()
    end
    pcall(InterfaceOptionsFrame_OpenToCategory, frame or "WowAhPlannerScan")
    pcall(InterfaceOptionsFrame_OpenToCategory, frame or "WowAhPlannerScan")
    return
  end

  Print("Could not open options UI. Open it via the game settings AddOns list.")
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
  if (not exactOk) and WowAhPlannerScanDB and WowAhPlannerScanDB.settings and WowAhPlannerScanDB.settings.verboseDebug then
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

  local configured = WowAhPlannerScan_TargetRegion
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
  local rank = tonumber(GetSetting("priceRank", 3)) or 3
  if rank < 1 then rank = 1 end

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
    gameVersion = WowAhPlannerScan_TargetGameVersion,
    targetProfessionId = WowAhPlannerScan_TargetProfessionId,
    targetProfessionName = WowAhPlannerScan_TargetProfessionName,
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

  WowAhPlannerScanDB.lastSnapshot = snapshot
  WowAhPlannerScanDB.lastSnapshotJson = BuildExportJsonFromSnapshot(snapshot)
  WowAhPlannerScanDB.lastGeneratedAtEpochUtc = snapshot.generatedAtEpochUtc

  state.running = false
  state.currentItemId = nil
  state.queue = {}
  state.awaiting = false

  Print("Scan complete. Items priced: " .. tostring(#(snapshot.prices or {})) .. ". Use /wahpscan export to copy JSON (or /reload to save SavedVariables for the web app).")
end

local function BuildExportJson()
  local snap = WowAhPlannerScanDB.lastSnapshot
  if not snap then return nil end
  local json = BuildExportJsonFromSnapshot(snap)
  WowAhPlannerScanDB.lastSnapshotJson = json
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

  if type(WowAhPlannerScan_TargetItemIds) == "table" then
    for _, itemId in ipairs(WowAhPlannerScan_TargetItemIds) do
      local n = tonumber(itemId)
      if n and n > 0 and not wanted[n] then
        wanted[n] = true
        count = count + 1
      end
    end
  end

  if count == 0 and type(WowAhPlannerScan_RecipeTargets) == "table" then
    for _, r in ipairs(WowAhPlannerScan_RecipeTargets) do
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

  if type(WowAhPlannerScan_VendorItemIds) == "table" then
    for _, itemId in ipairs(WowAhPlannerScan_VendorItemIds) do
      local n = tonumber(itemId)
      if n and n > 0 and not wanted[n] then
        wanted[n] = true
        count = count + 1
      end
    end
  end

  return wanted, count
end

local function BuildOwnedCountsFromBagBrother(wantedSet)
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

  local bb, source = DetectBagDb()
  if type(bb) ~= "table" then
    local bbLoaded = IsAddOnLoadedSafe("BagBrother")
    local bagnonLoaded = IsAddOnLoadedSafe("Bagnon")
    DebugPrint("Owned export: bag DB not found (BagBrother loaded=" .. tostring(bbLoaded) .. ", Bagnon loaded=" .. tostring(bagnonLoaded) .. "). Attempting LoadAddOn(BagBrother)...")
    LoadAddOnSafe("BagBrother")
    bb, source = DetectBagDb()
  end

  if type(bb) ~= "table" then
    return nil, "BagBrother/Bagnon data not found. Expected global BrotherBags (preferred) or BagBrother/BagnonDB. If you have Bagnon/BagBrother installed, enable BagBrother and /reload. Use /wahpscan owneddebug for diagnostics."
  end

  local realmName = GetRealmName()

  local nodes = {}
  if source == "BrotherBags" or source == "BagBrother" then
    local realmTable = bb[realmName] or bb[string.lower(realmName)] or bb[NormalizeRealmSlug(realmName)]
    if type(realmTable) == "table" then
      table.insert(nodes, realmTable)
    end
  elseif source == "BagnonDB" or source == "BagnonDB2" or source == "BagnonDB3" then
    if type(bb.characters) == "table" then
      local suffix = " - " .. tostring(realmName)
      for k, v in pairs(bb.characters) do
        if type(k) == "string" and string.sub(k, -string.len(suffix)) == suffix then
          table.insert(nodes, v)
        end
      end
    end
  end

  if #nodes == 0 then
    DebugPrint("Owned export: could not find realm-specific section in " .. tostring(source) .. "; scanning entire DB (may include other realms).")
    table.insert(nodes, bb)
  else
    DebugPrint("Owned export: using " .. tostring(source) .. " realm=\"" .. tostring(realmName) .. "\" nodes=" .. tostring(#nodes))
  end

  local counts = {}
  local visited = {}

  local function Walk(node)
    local tt = type(node)
    if tt == "table" then
      if visited[node] then return end
      visited[node] = true
      for _, v in pairs(node) do
        Walk(v)
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

  for _, root in ipairs(nodes) do
    Walk(root)
  end

  return counts, nil
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

local function BuildOwnedExportJsonFromCounts(snapshot, items)
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
    Print("No target itemIds loaded. Install targets from the web app first.")
    return
  end

  local counts, err = BuildOwnedCountsFromBagBrother(wantedSet)
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
    gameVersion = WowAhPlannerScan_TargetGameVersion,
    itemCount = #(items or {}),
    items = items,
  }

  local json = BuildOwnedExportJsonFromCounts(snapshot, items)
  WowAhPlannerScanDB.lastOwnedSnapshot = snapshot
  WowAhPlannerScanDB.lastOwnedJson = json

  ShowExportFrame(json, "WowAhPlanner Owned Items")
  Print("Owned export ready (" .. tostring(snapshot.itemCount or 0) .. " items). /reload to save SavedVariables for the web app.")
end

ShowExportFrame = function(textOverride, titleOverride)
  local text = textOverride
  local titleText = titleOverride
  if not text then
    text = BuildExportJson()
    titleText = titleText or "WowAhPlannerScan Export"
    if not text then
      Print("No snapshot found yet. Run /wahpscan start first.")
      return
    end
  else
    titleText = titleText or "WowAhPlannerScan Log"
  end

  if not exportFrame then
    exportFrame = CreateFrame("Frame", "WowAhPlannerScanExportFrame", UIParent, "BackdropTemplate")
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

  local recipeTargets = WowAhPlannerScan_RecipeTargets
  local professionId = WowAhPlannerScan_TargetProfessionId
  local professionName = WowAhPlannerScan_TargetProfessionName
  local maxSkillDelta = tonumber(GetSetting("maxSkillDelta", 100)) or 100
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
      Print("You do not have the target profession (id=" .. tostring(professionId) .. ", name=" .. tostring(professionName) .. ").")
      -- Fall back to WowAhPlannerScan_TargetItemIds if present.
    else
      local cap = tonumber(GetSetting("expansionCapSkill", 350)) or 350
      if cap < skillLevel then cap = skillLevel end

      local upper = skillLevel + maxSkillDelta
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
                if type(itemId) == "number" and itemId > 0 then
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
      if #state.queue > 0 then
        Print("Queued " .. tostring(#state.queue) .. " items for skill " .. tostring(skillLevel) .. " -> " .. tostring(upper) .. " (delta=" .. tostring(maxSkillDelta) .. ", cap=" .. tostring(cap) .. ").")
        return
      end

      Print("No recipe reagents found in your skill window (recipesInWindow=" .. tostring(recipesInWindow) .. "). Falling back to full pack reagents (if available).")
    end
  end

  local targets = WowAhPlannerScan_TargetItemIds or {}
  if type(targets) ~= "table" then targets = {} end

  for _, itemId in ipairs(targets) do
    if type(itemId) == "number" and itemId > 0 then
      table.insert(state.queue, itemId)
    end
  end

  if #state.queue == 0 then
    Print("Queued 0 items. Targets not loaded or empty. Ensure WowAhPlannerScan_Targets.lua is installed and /reload after updating it.")
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
  local rank = tonumber(GetSetting("priceRank", 3)) or 3
  if rank < 1 then rank = 1 end

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
      elseif WowAhPlannerScanDB and WowAhPlannerScanDB.settings and WowAhPlannerScanDB.settings.verboseDebug and (isExactIdMatch or (not id and isExactNameMatch)) then
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

    if WowAhPlannerScanDB and WowAhPlannerScanDB.settings and WowAhPlannerScanDB.settings.verboseDebug and shown > 0 then
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
      if type(itemId) == "number" and itemId > 0 then
        table.insert(state.queue, itemId)
      end
    end

    if #state.queue == 0 then
      Print("No valid itemIds provided.")
      return
    end

    Print("Queued " .. tostring(#state.queue) .. " manual item(s).")
  else
    QueueItems()
  end

  if #state.queue == 0 then
    Print("No targets loaded. Use the web app Targets page to download WowAhPlannerScan_Targets.lua, install it, then /reload.")
    return
  end

  StartSnapshot()
  state.running = true
  Print("Starting scan...")
  NextItem()
end

local function StopScan()
  state.running = false
  state.awaiting = false
  state.queue = {}
  state.currentItemId = nil
  Print("Stopped.")
end

SLASH_WOWAHPLANNERSCAN1 = "/wahpscan"
SlashCmdList["WOWAHPLANNERSCAN"] = function(msg)
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
      Print("Usage: /wahpscan item <itemId|itemLink>")
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
      ", showPanelOnAuctionHouse=" .. tostring(GetSetting("showPanelOnAuctionHouse", true)) ..
      ", verboseDebug=" .. tostring(GetSetting("verboseDebug", false)))
    return
  end

  if cmd == "options" then
    OpenOptionsUi()
    return
  end

  if cmd == "panel" then
    if WowAhPlannerScanPanel and WowAhPlannerScanPanel:IsShown() then
      WowAhPlannerScanPanel:Hide()
      Print("Panel hidden.")
    else
      if WowAhPlannerScanPanel then
        WowAhPlannerScanPanel:ClearAllPoints()
        local af = GetAuctionFrame()
        if af then
          WowAhPlannerScanPanel:SetPoint("TOPLEFT", af, "TOPRIGHT", 12, -80)
        else
          WowAhPlannerScanPanel:SetPoint("CENTER")
        end
        WowAhPlannerScanPanel:Show()
      end
      Print("Panel shown.")
    end
    return
  end

  if cmd == "log" then
    local log = WowAhPlannerScanDB.debugLog or {}
    local text = table.concat(log, "\n")
    if text == "" then
      Print("Log is empty.")
      return
    end
    ShowExportFrame(text, "WowAhPlannerScan Log")
    return
  end

  if cmd == "clearlog" then
    WowAhPlannerScanDB.debugLog = {}
    Print("Log cleared.")
    return
  end

  if cmd == "verbose" or cmd == "v" then
    WowAhPlannerScanDB.settings.verboseDebug = not (WowAhPlannerScanDB.settings.verboseDebug == true)
    Print("Verbose debug = " .. tostring(WowAhPlannerScanDB.settings.verboseDebug))
    return
  end

  if cmd == "debug" then
    Print("Target id=" .. tostring(WowAhPlannerScan_TargetProfessionId) .. ", name=" .. tostring(WowAhPlannerScan_TargetProfessionName))
    Print("Settings: maxSkillDelta=" .. tostring(GetSetting("maxSkillDelta", 100)) ..
      ", expansionCapSkill=" .. tostring(GetSetting("expansionCapSkill", 350)) ..
      ", maxPagesPerItem=" .. tostring(GetSetting("maxPagesPerItem", 10)) ..
      ", minQueryIntervalSeconds=" .. tostring(GetSetting("minQueryIntervalSeconds", 3)) ..
      ", queryTimeoutSeconds=" .. tostring(GetSetting("queryTimeoutSeconds", 10)) ..
      ", maxTimeoutRetriesPerPage=" .. tostring(GetSetting("maxTimeoutRetriesPerPage", 3)) ..
      ", showPanelOnAuctionHouse=" .. tostring(GetSetting("showPanelOnAuctionHouse", true)) ..
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

  Print("Commands: /wahpscan start | item <id|link> | stop | status | export | owned | owneddebug | options | panel | log | clearlog | debug | verbose")
end

-- Auction House panel UI
local backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
local panel = CreateFrame("Frame", "WowAhPlannerScanPanel", UIParent, backdropTemplate)
panel:SetSize(240, 198)
panel:SetFrameStrata("DIALOG")
panel:SetFrameLevel(1000)
panel:SetClampedToScreen(true)
panel:Hide()

if panel.SetBackdrop then
  panel:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
  })
end

panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", panel.StopMovingOrSizing)

local panelTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
panelTitle:SetPoint("TOPLEFT", 12, -12)
panelTitle:SetText("WowAhPlannerScan")

local panelClose = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
panelClose:SetPoint("TOPRIGHT", -4, -4)

local statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
statusText:SetPoint("TOPLEFT", 12, -36)
statusText:SetWidth(216)
statusText:SetJustifyH("LEFT")
statusText:SetText("Ready.")

local startBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
startBtn:SetPoint("TOPLEFT", 12, -62)
startBtn:SetSize(68, 22)
startBtn:SetText("Scan")
startBtn:SetScript("OnClick", function() StartScan() end)

local stopBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
stopBtn:SetPoint("LEFT", startBtn, "RIGHT", 8, 0)
stopBtn:SetSize(68, 22)
stopBtn:SetText("Stop")
stopBtn:SetScript("OnClick", function() StopScan() end)

local exportBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
exportBtn:SetPoint("LEFT", stopBtn, "RIGHT", 8, 0)
exportBtn:SetSize(68, 22)
exportBtn:SetText("Export")
exportBtn:SetScript("OnClick", function() ShowExportFrame() end)

local optionsBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
optionsBtn:SetPoint("TOPLEFT", 12, -92)
optionsBtn:SetSize(102, 22)
optionsBtn:SetText("Options")
optionsBtn:SetScript("OnClick", function() OpenOptionsUi() end)

local logBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
logBtn:SetPoint("LEFT", optionsBtn, "RIGHT", 8, 0)
logBtn:SetSize(102, 22)
logBtn:SetText("Log")
logBtn:SetScript("OnClick", function()
  local log = WowAhPlannerScanDB and WowAhPlannerScanDB.debugLog or {}
  ShowExportFrame(table.concat(log or {}, "\n"), "WowAhPlannerScan Log")
end)

local ownedBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
ownedBtn:SetPoint("TOPLEFT", 12, -122)
ownedBtn:SetSize(102, 22)
ownedBtn:SetText("Owned")
ownedBtn:SetScript("OnClick", function() ExportOwned() end)

local function UpdatePanelStatus()
  local current = state.currentItemId
  local remaining = #state.queue
  if state.running then
    local canQuery = CanQuery()
    local suffix = ""
    if canQuery == false then
      suffix = "\nWaiting: CanSendAuctionQuery=false"
    end
    statusText:SetText("Scanning...\nCurrent itemId: " .. tostring(current) .. "\nRemaining: " .. tostring(remaining) .. suffix)
  else
    local last = WowAhPlannerScanDB.lastSnapshot and WowAhPlannerScanDB.lastSnapshot.snapshotTimestampUtc or nil
    local lastOwned = WowAhPlannerScanDB.lastOwnedSnapshot and WowAhPlannerScanDB.lastOwnedSnapshot.snapshotTimestampUtc or nil
    if last then
      local ownedLine = lastOwned and ("\nOwned: " .. tostring(lastOwned)) or ""
      statusText:SetText("Ready.\nLast snapshot: " .. tostring(last) .. ownedLine)
    else
      statusText:SetText("Ready.\nNo snapshot yet.")
    end
  end

  if state.running then
    startBtn:Disable()
    stopBtn:Enable()
  else
    startBtn:Enable()
    stopBtn:Disable()
  end
end

local elapsed = 0
panel:SetScript("OnUpdate", function(_, dt)
  elapsed = elapsed + (dt or 0)
  if elapsed >= 0.5 then
    elapsed = 0
    UpdatePanelStatus()
  end
end)

local function ShowPanelNearAuctionHouse()
  if not panel then return end
  panel:ClearAllPoints()
  local af = GetAuctionFrame()
  if af then
    -- Keep away from the draggable header area to avoid interfering with moving the AH window.
    panel:SetPoint("TOPLEFT", af, "TOPRIGHT", 12, -80)
  else
    panel:SetPoint("CENTER")
  end
  UpdatePanelStatus()
  panel:Show()
  DebugPrint("Panel shown.")
end

local function HidePanel()
  if not panel then return end
  panel:Hide()
  DebugPrint("Panel hidden.")
end

local ahEventFrame = CreateFrame("Frame")
ahEventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
ahEventFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
ahEventFrame:RegisterEvent("PLAYER_LOGIN")
ahEventFrame:SetScript("OnEvent", function(_, event)
  EnsureDb()
  if event == "AUCTION_HOUSE_SHOW" then
    if WowAhPlannerScanDB.settings.showPanelOnAuctionHouse then
      C_Timer.After(0.1, ShowPanelNearAuctionHouse)
    end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    HidePanel()
  elseif event == "PLAYER_LOGIN" then
    TryRegisterOptions()
    -- Fallback: if the AH is already open when the player logs in/reloads.
    if WowAhPlannerScanDB.settings.showPanelOnAuctionHouse and IsAtAuctionHouse() then
      C_Timer.After(0.1, ShowPanelNearAuctionHouse)
    end
  end
end)

-- Options UI (legacy Interface Options)
local optionsParent = InterfaceOptionsFramePanelContainer or UIParent
local optionsFrame = CreateFrame("Frame", OPTIONS_FRAME_NAME, optionsParent)
optionsFrame.name = "WowAhPlannerScan"

local optionsLegacyRegistered = false
local optionsSettingsRegistered = false
TryRegisterOptions = function()
  if (not optionsLegacyRegistered) and InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(optionsFrame)
    optionsLegacyRegistered = true
    DebugPrint("Options registered via InterfaceOptions_AddCategory")
  end
  if (not optionsSettingsRegistered) and Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local category = Settings.RegisterCanvasLayoutCategory(optionsFrame, "WowAhPlannerScan")
    Settings.RegisterAddOnCategory(category)
    state.settingsCategory = category
    if category and category.GetID then
      WowAhPlannerScanDB._settingsCategoryId = category:GetID()
    elseif category and category.ID then
      WowAhPlannerScanDB._settingsCategoryId = category.ID
    end
    optionsSettingsRegistered = true
    DebugPrint("Options registered via Settings.RegisterAddOnCategory")
  end
end

optionsFrame:SetScript("OnShow", function(self)
  if self.initialized then return end
  self.initialized = true

  local function CreateValueLabelForSlider(slider, initialText)
    local v = self:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    v:SetPoint("LEFT", slider, "RIGHT", 12, 0)
    v:SetText(initialText or "")
    return v
  end

  local title = self:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("WowAhPlannerScan")

  local subtitle = self:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT", 16, -40)
  subtitle:SetText("Configure the scan window used when WowAhPlannerScan_RecipeTargets is loaded.")

  local showPanel = CreateFrame("CheckButton", "WowAhPlannerScanShowPanelCheckbox", self, "UICheckButtonTemplate")
  showPanel:SetPoint("TOPLEFT", 16, -60)
  showPanel.text:SetText("Show scan panel when Auction House opens")
  showPanel:SetChecked(WowAhPlannerScanDB.settings.showPanelOnAuctionHouse)
  showPanel:SetScript("OnClick", function(btn)
    WowAhPlannerScanDB.settings.showPanelOnAuctionHouse = btn:GetChecked() and true or false
  end)

  local verbose = CreateFrame("CheckButton", "WowAhPlannerScanVerboseCheckbox", self, "UICheckButtonTemplate")
  verbose:SetPoint("TOPLEFT", 16, -82)
  verbose.text:SetText("Verbose debug output")
  verbose:SetChecked(WowAhPlannerScanDB.settings.verboseDebug)
  verbose:SetScript("OnClick", function(btn)
    WowAhPlannerScanDB.settings.verboseDebug = btn:GetChecked() and true or false
  end)

  local rankSlider = CreateFrame("Slider", "WowAhPlannerScanPriceRankSlider", self, "OptionsSliderTemplate")
  rankSlider:SetPoint("TOPLEFT", 16, -118)
  rankSlider:SetMinMaxValues(1, 5)
  rankSlider:SetValueStep(1)
  rankSlider:SetObeyStepOnDrag(true)
  rankSlider:SetWidth(300)
  rankSlider:SetValue(GetSetting("priceRank", 3))
  local rankValue = CreateValueLabelForSlider(rankSlider, tostring(GetSetting("priceRank", 3)))

  _G[rankSlider:GetName() .. "Low"]:SetText("1")
  _G[rankSlider:GetName() .. "High"]:SetText("5")
  _G[rankSlider:GetName() .. "Text"]:SetText("Listing rank used for price (1=cheapest, 3=more stable)")

  rankSlider:SetScript("OnValueChanged", function(_, value)
    value = math.floor((value or 1) + 0.5)
    if value < 1 then value = 1 end
    WowAhPlannerScanDB.settings.priceRank = value
    rankValue:SetText(tostring(value))
  end)

  local slider = CreateFrame("Slider", "WowAhPlannerScanMaxSkillDeltaSlider", self, "OptionsSliderTemplate")
  slider:SetPoint("TOPLEFT", 16, -170)
  slider:SetMinMaxValues(0, 200)
  slider:SetValueStep(5)
  slider:SetObeyStepOnDrag(true)
  slider:SetWidth(300)
  slider:SetValue(GetSetting("maxSkillDelta", 100))
  local sliderValue = CreateValueLabelForSlider(slider, tostring(GetSetting("maxSkillDelta", 100)))

  _G[slider:GetName() .. "Low"]:SetText("0")
  _G[slider:GetName() .. "High"]:SetText("200")
  _G[slider:GetName() .. "Text"]:SetText("Max skill delta (levels above current)")

  slider:SetScript("OnValueChanged", function(_, value)
    value = math.floor((value or 0) + 0.5)
    WowAhPlannerScanDB.settings.maxSkillDelta = value
    sliderValue:SetText(tostring(value))
  end)

  local hint = self:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", 16, -220)
  hint:SetText("Default is 100. Upper bound is clamped to Expansion cap.")

  local capSlider = CreateFrame("Slider", "WowAhPlannerScanExpansionCapSlider", self, "OptionsSliderTemplate")
  capSlider:SetPoint("TOPLEFT", 16, -260)
  capSlider:SetMinMaxValues(75, 450)
  capSlider:SetValueStep(25)
  capSlider:SetObeyStepOnDrag(true)
  capSlider:SetWidth(300)
  capSlider:SetValue(GetSetting("expansionCapSkill", 350))
  local capValue = CreateValueLabelForSlider(capSlider, tostring(GetSetting("expansionCapSkill", 350)))

  _G[capSlider:GetName() .. "Low"]:SetText("75")
  _G[capSlider:GetName() .. "High"]:SetText("450")
  _G[capSlider:GetName() .. "Text"]:SetText("Expansion cap skill")

  capSlider:SetScript("OnValueChanged", function(_, value)
    value = math.floor((value or 0) + 0.5)
    WowAhPlannerScanDB.settings.expansionCapSkill = value
    capValue:SetText(tostring(value))
  end)

  local pagesSlider = CreateFrame("Slider", "WowAhPlannerScanMaxPagesSlider", self, "OptionsSliderTemplate")
  pagesSlider:SetPoint("TOPLEFT", 16, -350)
  pagesSlider:SetMinMaxValues(0, 50)
  pagesSlider:SetValueStep(1)
  pagesSlider:SetObeyStepOnDrag(true)
  pagesSlider:SetWidth(300)
  pagesSlider:SetValue(GetSetting("maxPagesPerItem", 10))
  local pagesValue = CreateValueLabelForSlider(pagesSlider, tostring(GetSetting("maxPagesPerItem", 10)))

  _G[pagesSlider:GetName() .. "Low"]:SetText("0")
  _G[pagesSlider:GetName() .. "High"]:SetText("50")
  _G[pagesSlider:GetName() .. "Text"]:SetText("Max pages per item")

  pagesSlider:SetScript("OnValueChanged", function(_, value)
    value = math.floor((value or 0) + 0.5)
    WowAhPlannerScanDB.settings.maxPagesPerItem = value
    pagesValue:SetText(tostring(value))
  end)

  local intervalSlider = CreateFrame("Slider", "WowAhPlannerScanQueryIntervalSlider", self, "OptionsSliderTemplate")
  intervalSlider:SetPoint("TOPLEFT", 16, -440)
  intervalSlider:SetMinMaxValues(1, 5)
  intervalSlider:SetValueStep(1)
  intervalSlider:SetObeyStepOnDrag(true)
  intervalSlider:SetWidth(300)
  intervalSlider:SetValue(GetSetting("minQueryIntervalSeconds", 3))
  local intervalValue = CreateValueLabelForSlider(intervalSlider, tostring(GetSetting("minQueryIntervalSeconds", 3)) .. "s")

  _G[intervalSlider:GetName() .. "Low"]:SetText("1s")
  _G[intervalSlider:GetName() .. "High"]:SetText("5s")
  _G[intervalSlider:GetName() .. "Text"]:SetText("Min query interval (seconds)")

  intervalSlider:SetScript("OnValueChanged", function(_, value)
    value = math.floor((value or 0) + 0.5)
    WowAhPlannerScanDB.settings.minQueryIntervalSeconds = value
    intervalValue:SetText(tostring(value) .. "s")
  end)

  local retriesSlider = CreateFrame("Slider", "WowAhPlannerScanTimeoutRetriesSlider", self, "OptionsSliderTemplate")
  retriesSlider:SetPoint("TOPLEFT", 16, -530)
  retriesSlider:SetMinMaxValues(0, 10)
  retriesSlider:SetValueStep(1)
  retriesSlider:SetObeyStepOnDrag(true)
  retriesSlider:SetWidth(300)
  retriesSlider:SetValue(GetSetting("maxTimeoutRetriesPerPage", 3))
  local retriesValue = CreateValueLabelForSlider(retriesSlider, tostring(GetSetting("maxTimeoutRetriesPerPage", 3)))

  _G[retriesSlider:GetName() .. "Low"]:SetText("0")
  _G[retriesSlider:GetName() .. "High"]:SetText("10")
  _G[retriesSlider:GetName() .. "Text"]:SetText("Max timeout retries (per page)")

  retriesSlider:SetScript("OnValueChanged", function(_, value)
    value = math.floor((value or 0) + 0.5)
    WowAhPlannerScanDB.settings.maxTimeoutRetriesPerPage = value
    retriesValue:SetText(tostring(value))
  end)

  local timeoutSlider = CreateFrame("Slider", "WowAhPlannerScanQueryTimeoutSlider", self, "OptionsSliderTemplate")
  timeoutSlider:SetPoint("TOPLEFT", 16, -620)
  timeoutSlider:SetMinMaxValues(5, 30)
  timeoutSlider:SetValueStep(1)
  timeoutSlider:SetObeyStepOnDrag(true)
  timeoutSlider:SetWidth(300)
  timeoutSlider:SetValue(GetSetting("queryTimeoutSeconds", 10))
  local timeoutValue = CreateValueLabelForSlider(timeoutSlider, tostring(GetSetting("queryTimeoutSeconds", 10)) .. "s")

  _G[timeoutSlider:GetName() .. "Low"]:SetText("5s")
  _G[timeoutSlider:GetName() .. "High"]:SetText("30s")
  _G[timeoutSlider:GetName() .. "Text"]:SetText("Query timeout (seconds)")

  timeoutSlider:SetScript("OnValueChanged", function(_, value)
    value = math.floor((value or 0) + 0.5)
    WowAhPlannerScanDB.settings.queryTimeoutSeconds = value
    timeoutValue:SetText(tostring(value) .. "s")
  end)
end)

TryRegisterOptions()
