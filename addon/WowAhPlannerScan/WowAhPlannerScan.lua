local ADDON_NAME = ...

WowAhPlannerScanDB = WowAhPlannerScanDB or {}
WowAhPlannerScanDB.settings = WowAhPlannerScanDB.settings or {}
WowAhPlannerScanDB.settings.maxSkillDelta = WowAhPlannerScanDB.settings.maxSkillDelta or 100
WowAhPlannerScanDB.settings.expansionCapSkill = WowAhPlannerScanDB.settings.expansionCapSkill or 350
WowAhPlannerScanDB.settings.maxPagesPerItem = WowAhPlannerScanDB.settings.maxPagesPerItem or 10
WowAhPlannerScanDB.settings.minQueryIntervalSeconds = WowAhPlannerScanDB.settings.minQueryIntervalSeconds or 2
WowAhPlannerScanDB.settings.queryTimeoutSeconds = WowAhPlannerScanDB.settings.queryTimeoutSeconds or 10

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff7dd3fcWowAhPlannerScan|r: " .. tostring(msg))
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
  page = 0,
  maxPages = 10,
  delaySeconds = 2.0,
  awaiting = false,
  prices = {},
  startedAt = nil,
  lastQueryAt = nil,
  lastQueryToken = 0,
}

local function GetSetting(name, defaultValue)
  local settings = WowAhPlannerScanDB and WowAhPlannerScanDB.settings or nil
  if not settings then return defaultValue end
  local value = settings[name]
  if value == nil then return defaultValue end
  return value
end

local function IsAtAuctionHouse()
  return AuctionFrame and AuctionFrame:IsShown()
end

local function ParseItemIdFromLink(link)
  if not link then return nil end
  local id = string.match(link, "item:(%d+):")
  return id and tonumber(id) or nil
end

local function CanQuery()
  if not CanSendAuctionQuery then
    return true
  end
  return CanSendAuctionQuery()
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

local function StartSnapshot()
  state.prices = {}
  state.startedAt = time()
  state.lastQueryAt = nil
  state.lastQueryToken = 0
end

local function FinishSnapshot()
  local snapshot = {
    schema = "wowahplanner-scan-v1",
    snapshotTimestampUtc = date("!%Y-%m-%dT%H:%M:%SZ", time()),
    realmName = GetRealmName(),
    faction = UnitFactionGroup("player"),
    generatedAtEpochUtc = time(),
    prices = {},
  }

  for itemId, entry in pairs(state.prices) do
    table.insert(snapshot.prices, {
      itemId = itemId,
      minUnitBuyoutCopper = entry.minUnitBuyoutCopper,
      totalQuantity = entry.totalQuantity,
    })
  end

  table.sort(snapshot.prices, function(a, b) return a.itemId < b.itemId end)

  WowAhPlannerScanDB.lastSnapshot = snapshot
  WowAhPlannerScanDB.lastGeneratedAtEpochUtc = snapshot.generatedAtEpochUtc

  state.running = false
  state.currentItemId = nil
  state.queue = {}
  state.awaiting = false

  Print("Scan complete. Use /wahpscan export to copy JSON.")
end

local function BuildExportJson()
  local snap = WowAhPlannerScanDB.lastSnapshot
  if not snap then return nil end

  local parts = {}
  table.insert(parts, '{"schema":"wowahplanner-scan-v1"')
  table.insert(parts, ',"snapshotTimestampUtc":"' .. snap.snapshotTimestampUtc .. '"')
  table.insert(parts, ',"realmName":"' .. (snap.realmName or "") .. '"')
  table.insert(parts, ',"faction":"' .. (snap.faction or "") .. '"')
  table.insert(parts, ',"prices":[')

  for i, p in ipairs(snap.prices or {}) do
    if i > 1 then table.insert(parts, ",") end
    table.insert(parts, string.format('{"itemId":%d,"minUnitBuyoutCopper":%d,"totalQuantity":%d}', p.itemId, p.minUnitBuyoutCopper or 0, p.totalQuantity or 0))
  end

  table.insert(parts, "]}")
  return table.concat(parts)
end

local exportFrame
local function ShowExportFrame()
  local json = BuildExportJson()
  if not json then
    Print("No snapshot found yet. Run /wahpscan start first.")
    return
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
    title:SetText("WowAhPlannerScan Export")

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

  exportFrame.editBox:SetText(json)
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

  state.maxPages = tonumber(GetSetting("maxPagesPerItem", 10)) or state.maxPages
  state.delaySeconds = tonumber(GetSetting("minQueryIntervalSeconds", 2)) or state.delaySeconds

  if not CanQuery() then
    C_Timer.After(state.delaySeconds, QueryCurrentPage)
    return
  end

  if state.lastQueryAt then
    local elapsed = GetTime() - state.lastQueryAt
    if elapsed < state.delaySeconds then
      C_Timer.After(state.delaySeconds - elapsed, QueryCurrentPage)
      return
    end
  end

  local name = EnsureItemName(state.currentItemId)
  if not name then
    table.insert(state.queue, state.currentItemId)
    state.currentItemId = nil
    C_Timer.After(state.delaySeconds, NextItem)
    return
  end

  state.awaiting = true
  state.lastQueryAt = GetTime()
  state.lastQueryToken = (state.lastQueryToken or 0) + 1
  local thisToken = state.lastQueryToken
  QueryAuctionItems(name, nil, nil, 0, 0, 0, state.page, false, nil, false, true)

  local timeout = tonumber(GetSetting("queryTimeoutSeconds", 10)) or 10
  if timeout < 3 then timeout = 3 end
  C_Timer.After(timeout, function()
    if state.running and state.awaiting and state.lastQueryToken == thisToken then
      state.awaiting = false
      Print("Query timeout (itemId=" .. tostring(state.currentItemId) .. ", page=" .. tostring(state.page) .. "). Retrying...")
      C_Timer.After(state.delaySeconds, QueryCurrentPage)
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
  state.page = 0
  state.awaiting = false
  QueryCurrentPage()
end

local function ProcessCurrentPage()
  if not state.currentItemId then return end

  local shown, total = GetNumAuctionItems("list")
  local itemId = state.currentItemId

  for i = 1, shown do
    local _, _, count, _, _, _, _, _, buyoutPrice = GetAuctionItemInfo("list", i)
    local link = GetAuctionItemLink("list", i)
    local id = ParseItemIdFromLink(link)

    if id == itemId and buyoutPrice and buyoutPrice > 0 and count and count > 0 then
      local unit = math.floor(buyoutPrice / count)
      local entry = state.prices[itemId]
      if not entry then
        entry = { minUnitBuyoutCopper = unit, totalQuantity = 0 }
        state.prices[itemId] = entry
      end
      if unit < entry.minUnitBuyoutCopper then
        entry.minUnitBuyoutCopper = unit
      end
      entry.totalQuantity = entry.totalQuantity + count
    end
  end

  local nextPageExists = total and total > (state.page + 1) * 50
  if nextPageExists and state.page < state.maxPages then
    state.page = state.page + 1
    C_Timer.After(state.delaySeconds, QueryCurrentPage)
  else
    state.currentItemId = nil
    C_Timer.After(state.delaySeconds, NextItem)
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
frame:SetScript("OnEvent", function(_, event)
  if event == "AUCTION_ITEM_LIST_UPDATE" and state.running and state.awaiting then
    state.awaiting = false
    ProcessCurrentPage()
  end
end)

SLASH_WOWAHPLANNERSCAN1 = "/wahpscan"
SlashCmdList["WOWAHPLANNERSCAN"] = function(msg)
  msg = string.lower(msg or "")

  if msg == "start" then
    if not IsAtAuctionHouse() then
      Print("Open the Auction House first.")
      return
    end
    QueueItems()
    if #state.queue == 0 then
      Print("No targets loaded. Use the web app Targets page to download WowAhPlannerScan_Targets.lua, install it, then /reload.")
      return
    end
    StartSnapshot()
    state.running = true
    Print("Starting scan...")
    NextItem()
    return
  end

  if msg == "stop" then
    state.running = false
    state.awaiting = false
    state.queue = {}
    state.currentItemId = nil
    Print("Stopped.")
    return
  end

  if msg == "status" then
    Print("running=" .. tostring(state.running) .. ", remaining=" .. tostring(#state.queue) .. ", current=" .. tostring(state.currentItemId))
    return
  end

  if msg == "options" then
    InterfaceOptionsFrame_OpenToCategory("WowAhPlannerScan")
    InterfaceOptionsFrame_OpenToCategory("WowAhPlannerScan")
    return
  end

  if msg == "debug" then
    Print("Target id=" .. tostring(WowAhPlannerScan_TargetProfessionId) .. ", name=" .. tostring(WowAhPlannerScan_TargetProfessionName))
    Print("Settings: maxSkillDelta=" .. tostring(GetSetting("maxSkillDelta", 100)) ..
      ", expansionCapSkill=" .. tostring(GetSetting("expansionCapSkill", 350)) ..
      ", maxPagesPerItem=" .. tostring(GetSetting("maxPagesPerItem", 10)) ..
      ", minQueryIntervalSeconds=" .. tostring(GetSetting("minQueryIntervalSeconds", 2)) ..
      ", queryTimeoutSeconds=" .. tostring(GetSetting("queryTimeoutSeconds", 10)))
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

  if msg == "export" then
    ShowExportFrame()
    return
  end

  Print("Commands: /wahpscan start | stop | status | export | options | debug")
end

-- Options UI (legacy Interface Options)
local optionsParent = InterfaceOptionsFramePanelContainer or UIParent
local optionsFrame = CreateFrame("Frame", "WowAhPlannerScanOptionsFrame", optionsParent)
optionsFrame.name = "WowAhPlannerScan"

optionsFrame:SetScript("OnShow", function(self)
  if self.initialized then return end
  self.initialized = true

  local title = self:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("WowAhPlannerScan")

  local subtitle = self:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT", 16, -40)
  subtitle:SetText("Configure the scan window used when WowAhPlannerScan_RecipeTargets is loaded.")

  local slider = CreateFrame("Slider", "WowAhPlannerScanMaxSkillDeltaSlider", self, "OptionsSliderTemplate")
  slider:SetPoint("TOPLEFT", 16, -80)
  slider:SetMinMaxValues(0, 200)
  slider:SetValueStep(5)
  slider:SetObeyStepOnDrag(true)
  slider:SetWidth(300)
  slider:SetValue(GetSetting("maxSkillDelta", 100))

  _G[slider:GetName() .. "Low"]:SetText("0")
  _G[slider:GetName() .. "High"]:SetText("200")
  _G[slider:GetName() .. "Text"]:SetText("Max skill delta (levels above current)")

  slider:SetScript("OnValueChanged", function(_, value)
    value = math.floor((value or 0) + 0.5)
    WowAhPlannerScanDB.settings.maxSkillDelta = value
  end)

  local hint = self:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", 16, -130)
  hint:SetText("Default is 100. Upper bound is clamped to Expansion cap.")

  local capSlider = CreateFrame("Slider", "WowAhPlannerScanExpansionCapSlider", self, "OptionsSliderTemplate")
  capSlider:SetPoint("TOPLEFT", 16, -170)
  capSlider:SetMinMaxValues(75, 450)
  capSlider:SetValueStep(25)
  capSlider:SetObeyStepOnDrag(true)
  capSlider:SetWidth(300)
  capSlider:SetValue(GetSetting("expansionCapSkill", 350))

  _G[capSlider:GetName() .. "Low"]:SetText("75")
  _G[capSlider:GetName() .. "High"]:SetText("450")
  _G[capSlider:GetName() .. "Text"]:SetText("Expansion cap skill")

  capSlider:SetScript("OnValueChanged", function(_, value)
    value = math.floor((value or 0) + 0.5)
    WowAhPlannerScanDB.settings.expansionCapSkill = value
  end)

  local pagesSlider = CreateFrame("Slider", "WowAhPlannerScanMaxPagesSlider", self, "OptionsSliderTemplate")
  pagesSlider:SetPoint("TOPLEFT", 16, -260)
  pagesSlider:SetMinMaxValues(0, 50)
  pagesSlider:SetValueStep(1)
  pagesSlider:SetObeyStepOnDrag(true)
  pagesSlider:SetWidth(300)
  pagesSlider:SetValue(GetSetting("maxPagesPerItem", 10))

  _G[pagesSlider:GetName() .. "Low"]:SetText("0")
  _G[pagesSlider:GetName() .. "High"]:SetText("50")
  _G[pagesSlider:GetName() .. "Text"]:SetText("Max pages per item")

  pagesSlider:SetScript("OnValueChanged", function(_, value)
    value = math.floor((value or 0) + 0.5)
    WowAhPlannerScanDB.settings.maxPagesPerItem = value
  end)

  local intervalSlider = CreateFrame("Slider", "WowAhPlannerScanQueryIntervalSlider", self, "OptionsSliderTemplate")
  intervalSlider:SetPoint("TOPLEFT", 16, -350)
  intervalSlider:SetMinMaxValues(1, 5)
  intervalSlider:SetValueStep(1)
  intervalSlider:SetObeyStepOnDrag(true)
  intervalSlider:SetWidth(300)
  intervalSlider:SetValue(GetSetting("minQueryIntervalSeconds", 2))

  _G[intervalSlider:GetName() .. "Low"]:SetText("1s")
  _G[intervalSlider:GetName() .. "High"]:SetText("5s")
  _G[intervalSlider:GetName() .. "Text"]:SetText("Min query interval (seconds)")

  intervalSlider:SetScript("OnValueChanged", function(_, value)
    value = math.floor((value or 0) + 0.5)
    WowAhPlannerScanDB.settings.minQueryIntervalSeconds = value
  end)

  local timeoutSlider = CreateFrame("Slider", "WowAhPlannerScanQueryTimeoutSlider", self, "OptionsSliderTemplate")
  timeoutSlider:SetPoint("TOPLEFT", 16, -440)
  timeoutSlider:SetMinMaxValues(5, 30)
  timeoutSlider:SetValueStep(1)
  timeoutSlider:SetObeyStepOnDrag(true)
  timeoutSlider:SetWidth(300)
  timeoutSlider:SetValue(GetSetting("queryTimeoutSeconds", 10))

  _G[timeoutSlider:GetName() .. "Low"]:SetText("5s")
  _G[timeoutSlider:GetName() .. "High"]:SetText("30s")
  _G[timeoutSlider:GetName() .. "Text"]:SetText("Query timeout (seconds)")

  timeoutSlider:SetScript("OnValueChanged", function(_, value)
    value = math.floor((value or 0) + 0.5)
    WowAhPlannerScanDB.settings.queryTimeoutSeconds = value
  end)
end)

if InterfaceOptions_AddCategory then
  InterfaceOptions_AddCategory(optionsFrame)
end
