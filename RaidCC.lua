local Addon = Actually

Addon.RaidCC = Addon.RaidCC or {}
local RaidCC = Addon.RaidCC

local HEARTBEAT_INTERVAL = 0.30
local ARROW_TEXTURE = "Interface\\AddOns\\Actually\\Textures\\RaidCCArrow.tga"
local WARNING_INTERVAL = 30

-- TurboPlates 1.4.5 compatibility boundary (audited against its Core.lua and
-- Nameplates.lua).
--
-- This module never reads TurboPlates' private addon namespace. It only uses
-- fields attached to the original world nameplate: myPlate, liteContainer,
-- liteQuestIcon, _isLite, _unit, _turboTrackedUnit, and _turboTrackedGUID.
-- myPlate is initially created on the original plate and may then be reparented
-- to WorldFrame by C_NamePlateManager.ApplyFPSIncrease. liteContainer and
-- liteQuestIcon remain on the original plate. Only the three visual fields are
-- hidden; all classification/tracking fields are read-only. An unrecognised
-- plate is left entirely alone.
local FULL_FRAME_FIELD = "myPlate"
local LITE_FRAME_FIELD = "liteContainer"
local LITE_ICON_FIELD = "liteQuestIcon"

local CC_CYCLONE = "cyclone"
local CC_SHADOWFURY = "shadowfury"
local CC_ARROW_COLORS = {
    [CC_CYCLONE] = { 0.15, 1.00, 0.25 },
    [CC_SHADOWFURY] = { 0.72, 0.20, 1.00 },
}
local CC_PRIORITY = {
    [CC_CYCLONE] = 2,
    [CC_SHADOWFURY] = 1,
}

-- Match TurboPlates' own conflict audit. Ascension_NamePlates is represented
-- by useNewNameplates rather than a normally loaded addon.
local INCOMPATIBLE_NAMEPLATE_ADDONS = {
    "Kui_Nameplates",
    "TidyPlates_ThreatPlates",
    "PlateBuffs",
}

local trackedSpellIDs = {
    [33786] = CC_CYCLONE, -- Cyclone
    [30283] = CC_SHADOWFURY, -- Shadowfury (rank 1)
    [30413] = CC_SHADOWFURY, -- Shadowfury (rank 2)
    [30414] = CC_SHADOWFURY, -- Shadowfury (rank 3)
    [47846] = CC_SHADOWFURY, -- Shadowfury (rank 4)
    [47847] = CC_SHADOWFURY, -- Shadowfury (rank 5)
}

RaidCC.trackedSpellIDs = trackedSpellIDs
RaidCC.raidGUIDs = RaidCC.raidGUIDs or {}
RaidCC.visiblePlates = RaidCC.visiblePlates or {}
RaidCC.unitToPlate = RaidCC.unitToPlate or {}
RaidCC.trackedSpellNames = RaidCC.trackedSpellNames or {}
RaidCC.runtimeActive = false
RaidCC.initialized = false
RaidCC.cvarGuard = false
RaidCC.elapsed = 0
RaidCC.lastWarningAt = -WARNING_INTERVAL
RaidCC.lastEnvironmentWarningAt = -WARNING_INTERVAL
RaidCC.lastEnvironmentWarningCode = nil
RaidCC.debugEnabled = false

local function ClearTable(value)
    if wipe then
        wipe(value)
        return
    end
    for key in pairs(value) do
        value[key] = nil
    end
end

local function Now()
    return GetTime and GetTime() or 0
end

local function CountTable(value)
    local count = 0
    for _ in pairs(value or {}) do
        count = count + 1
    end
    return count
end

local function UnitDescription(unit)
    if not unit then return "unit=nil" end
    local name = UnitName and UnitName(unit)
    local guid = UnitGUID and UnitGUID(unit)
    return "unit=" .. tostring(unit) .. " name=" .. tostring(name)
        .. " guid=" .. tostring(guid)
end

local function IsRaid()
    if IsInRaid then
        return IsInRaid() and true or false
    end
    return GetNumRaidMembers and (GetNumRaidMembers() or 0) > 0 or false
end

local function IsNamedAddOnLoaded(name)
    if not IsAddOnLoaded then
        return false
    end
    local ok, loaded = pcall(IsAddOnLoaded, name)
    return ok and loaded and true or false
end

local function GetBooleanCVar(name)
    if C_CVar and C_CVar.GetBool then
        local ok, value = pcall(C_CVar.GetBool, name)
        if ok then
            return value == true or value == 1 or value == "1"
        end
    end
    if GetCVar then
        local ok, value = pcall(GetCVar, name)
        if ok then
            return value == true or value == 1 or value == "1"
        end
    end
    return false
end

local function RaidCount()
    if GetNumGroupMembers then
        return GetNumGroupMembers() or 0
    end
    return GetNumRaidMembers and GetNumRaidMembers() or 0
end

local function GetPlateForUnit(unit)
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        return C_NamePlate.GetNamePlateForUnit(unit)
    end
end

local function SafeHide(frame)
    if frame and frame.Hide then
        frame:Hide()
    end
end

local function SafeShow(frame)
    if frame and frame.Show then
        frame:Show()
    end
end

function RaidCC:Print(message)
    if Addon.Print then
        Addon:Print("Raid CC: " .. tostring(message))
    end
end

function RaidCC:Debug(message)
    if self.debugEnabled or (self.db and self.db.debug == true) then
        self:Print("DEBUG " .. tostring(message))
    end
end

function RaidCC:SetDebug(enabled)
    self.debugEnabled = enabled and true or false
    if self.db then self.db.debug = self.debugEnabled end
    self:Print("debug " .. (self.debugEnabled and "enabled" or "disabled"))
    if self.debugEnabled then self:PrintStatus() end
end

function RaidCC:GetCompatibilityStatus()
    if not IsNamedAddOnLoaded("TurboPlates") then
        return false, "turboplates-not-loaded",
            "TurboPlates is not enabled for this character. Enable it and reload the UI."
    end

    if GetBooleanCVar("useNewNameplates") then
        return false, "ascension-nameplates",
            "Ascension New Nameplates is enabled. Disable it and reload the UI so TurboPlates can own the plates."
    end

    local elvEngine = ElvUI and ElvUI[1]
    if elvEngine
        and elvEngine.private
        and elvEngine.private.nameplates
        and elvEngine.private.nameplates.enable then
        return false, "elvui-nameplates",
            "ElvUI NamePlates is enabled. Disable only ElvUI's NamePlates module and reload the UI."
    end

    for _, addonName in ipairs(INCOMPATIBLE_NAMEPLATE_ADDONS) do
        if IsNamedAddOnLoaded(addonName) then
            return false, "conflict-" .. string.lower(addonName),
                addonName .. " is loaded and conflicts with TurboPlates. Disable it and reload the UI."
        end
    end

    if not C_NamePlate
        or not C_NamePlate.GetNamePlateForUnit
        or not C_NamePlateManager
        or not C_NamePlateManager.EnumerateActiveNamePlates then
        return false, "nameplate-api-missing",
            "The required Ascension nameplate-manager APIs are unavailable."
    end

    return true, "ready", "TurboPlates is loaded and ready."
end

function RaidCC:GetRuntimeStatus()
    if not self:IsEnabled() then
        return "disabled", "Disabled. Your normal nameplate settings are unchanged."
    end

    local compatible, _, message = self:GetCompatibilityStatus()
    if not compatible then
        return "blocked", "Unavailable: " .. message
    end

    if not IsRaid() then
        return "waiting", "Ready. It activates automatically in raids and battlegrounds."
    end

    if self.runtimeActive then
        return "active", "Active: raid members are name-only and tracked CC displays an arrow."
    end

    return "waiting", "Preparing the raid nameplate override."
end

function RaidCC:RefreshOptionsStatus()
    if Addon.CacheTips and Addon.CacheTips.RefreshRaidCCToggle then
        Addon.CacheTips:RefreshRaidCCToggle()
    end
end

function RaidCC:PrintStatus()
    local active, compatible, retrying = 0, 0, 0
    for nameplate in pairs(self.visiblePlates or {}) do
        local state = nameplate._actuallyRaidCCState
        if self:HasCompatibleFrames(nameplate) then compatible = compatible + 1 end
        if state and state.active then active = active + 1 end
        if state and state.retryAt then retrying = retrying + 1 end
    end
    local environmentCompatible, environmentCode = self:GetCompatibilityStatus()
    self:Print("status enabled=" .. tostring(self.db and self.db.enabled == true)
        .. " inRaid=" .. tostring(IsRaid())
        .. " runtime=" .. tostring(self.runtimeActive)
        .. " environment=" .. tostring(environmentCode)
        .. " environmentCompatible=" .. tostring(environmentCompatible)
        .. " raidGUIDs=" .. tostring(CountTable(self.raidGUIDs))
        .. " visible=" .. tostring(CountTable(self.visiblePlates))
        .. " compatible=" .. tostring(compatible)
        .. " overridden=" .. tostring(active)
        .. " retrying=" .. tostring(retrying)
        .. " friendsCVar=" .. tostring(self:GetCVarValue("nameplateShowFriends"))
        .. " enemiesCVar=" .. tostring(self:GetCVarValue("nameplateShowEnemies")))
end

function RaidCC:HandleCommand(input)
    local command = string.lower(string.gsub(tostring(input or ""), "^%s*(.-)%s*$", "%1"))
    if command == "debug" then
        self:SetDebug(not (self.debugEnabled or (self.db and self.db.debug == true)))
    elseif command == "status" then
        self:PrintStatus()
    elseif command == "scan" then
        self:RebuildRaidGUIDCache()
        self:ReevaluateVisiblePlates()
        self:PrintStatus()
    else
        self:Print("commands: /raidcc debug, /raidcc status, /raidcc scan")
    end
end

function RaidCC:WarnCompatibility()
    local current = Now()
    if current - self.lastWarningAt < WARNING_INTERVAL then
        return
    end
    self.lastWarningAt = current
    self:Print("compatible TurboPlates plate fields were not found; raid override was skipped")
end

function RaidCC:WarnEnvironment(code, message)
    local current = Now()
    if self.lastEnvironmentWarningCode == code
        and current - self.lastEnvironmentWarningAt < WARNING_INTERVAL then
        return
    end
    self.lastEnvironmentWarningCode = code
    self.lastEnvironmentWarningAt = current
    self:Print("inactive: " .. tostring(message))
end

function RaidCC:IsModeRequested()
    return self.db and self.db.enabled == true and IsRaid()
end

function RaidCC:ShouldModeBeActive()
    if not self:IsModeRequested() then
        return false
    end
    local compatible = self:GetCompatibilityStatus()
    return compatible and true or false
end

function RaidCC:IsEnabled()
    return self.db and self.db.enabled == true or false
end

function RaidCC:SetEnabled(enabled)
    if not self.db then
        return
    end
    self.db.enabled = enabled and true or false
    self:RefreshMode()
    if self.runtimeActive then
        self:ReevaluateVisiblePlates()
    elseif enabled then
        local compatible, code, message = self:GetCompatibilityStatus()
        if not compatible then
            self:WarnEnvironment(code, message)
        elseif not IsRaid() then
            self:Print("enabled; waiting for a raid or battleground")
        end
    end
    self:RefreshOptionsStatus()
end

function RaidCC:RebuildRaidGUIDCache()
    ClearTable(self.raidGUIDs)
    if not IsRaid() then
        return
    end
    for index = 1, RaidCount() do
        local guid = UnitGUID("raid" .. index)
        if guid then
            self.raidGUIDs[guid] = true
        end
    end
    self:Debug("raid GUID cache rebuilt count=" .. tostring(CountTable(self.raidGUIDs)))
end

function RaidCC:ClassifyUnit(unit)
    if not self.runtimeActive then
        return false, "runtime-inactive"
    end
    if not unit then
        return false, "missing-unit"
    end
    if not UnitExists(unit) then
        return false, "unit-does-not-exist"
    end
    if not UnitIsPlayer(unit) then
        return false, "not-player"
    end
    if UnitIsUnit(unit, "player") then
        return false, "self"
    end
    local guid = UnitGUID(unit)
    if not guid then
        return false, "missing-guid"
    end
    if self.raidGUIDs[guid] ~= true then
        return false, "not-raid-member"
    end
    return true, "raid-member"
end

function RaidCC:ShouldOverrideUnit(unit)
    local allowed = self:ClassifyUnit(unit)
    return allowed
end

function RaidCC:HasCompatibleFrames(nameplate)
    return nameplate and (
        nameplate[FULL_FRAME_FIELD]
        or nameplate[LITE_FRAME_FIELD]
    ) and true or false
end

function RaidCC:CreateOverlay(nameplate)
    local overlay = CreateFrame("Frame", nil, nameplate)
    overlay:SetAllPoints(nameplate)
    if overlay.SetFrameLevel and nameplate.GetFrameLevel then
        overlay:SetFrameLevel((nameplate:GetFrameLevel() or 0) + 10)
    end
    overlay:EnableMouse(false)

    local nameText = overlay:CreateFontString(nil, "OVERLAY")
    nameText:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    nameText:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    overlay.nameText = nameText

    local arrowShadow = overlay:CreateTexture(nil, "ARTWORK")
    arrowShadow:SetTexture(ARROW_TEXTURE)
    arrowShadow:SetSize(38, 38)
    arrowShadow:SetPoint("BOTTOM", nameText, "TOP", 2, 2)
    arrowShadow:SetVertexColor(0, 0, 0, 1)
    arrowShadow:SetAlpha(0.80)
    arrowShadow:Hide()
    overlay.arrowShadow = arrowShadow

    local arrow = overlay:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture(ARROW_TEXTURE)
    arrow:SetSize(38, 38)
    arrow:SetPoint("BOTTOM", nameText, "TOP", 0, 4)
    arrow:SetVertexColor(1, 1, 1, 1)
    arrow:Hide()
    overlay.arrow = arrow

    overlay:Hide()
    return overlay
end

function RaidCC:GetState(nameplate)
    local state = nameplate._actuallyRaidCCState
    if not state then
        state = {
            active = false,
            unit = nil,
            guid = nil,
            overlay = self:CreateOverlay(nameplate),
            retryAt = nil,
            retryCount = 0,
            retryScheduled = false,
            debugDecision = nil,
            arrowShown = false,
            arrowKind = nil,
        }
        nameplate._actuallyRaidCCState = state
    end
    return state
end

function RaidCC:ScheduleGuardedRetry(nameplate, state)
    if state.retryScheduled or not C_Timer or not C_Timer.After then
        return
    end
    state.retryScheduled = true
    local expectedUnit = state.unit
    local expectedGUID = state.guid
    C_Timer.After(0, function()
        state.retryScheduled = false
        if state.unit ~= expectedUnit
            or state.guid ~= expectedGUID
            or not expectedUnit
            or not UnitExists(expectedUnit)
            or UnitGUID(expectedUnit) ~= expectedGUID then
            return
        end
        RaidCC:SafeEvaluatePlate(nameplate, expectedUnit)
    end)
end

local function FindNameText(nameplate)
    local lite = nameplate[LITE_FRAME_FIELD]
    local full = nameplate[FULL_FRAME_FIELD]
    if nameplate._isLite and lite then
        return lite.liteNameText
    end
    if full then
        return full.nameText
    end
    if lite then
        return lite.liteNameText
    end
end

function RaidCC:CopyNameAppearance(nameplate, unit, overlay)
    local source = FindNameText(nameplate)
    local target = overlay.nameText
    local displayed = source and source.GetText and source:GetText()
    target:SetText(displayed and displayed ~= "" and displayed or (UnitName(unit) or ""))

    if source and source.GetFont then
        local path, size, flags = source:GetFont()
        if path and size then
            target:SetFont(path, size, flags)
        end
    end
    if source and source.GetTextColor then
        target:SetTextColor(source:GetTextColor())
    else
        target:SetTextColor(1, 1, 1, 1)
    end
    if source and source.GetShadowColor and target.SetShadowColor then
        target:SetShadowColor(source:GetShadowColor())
    end
    if source and source.GetShadowOffset and target.SetShadowOffset then
        target:SetShadowOffset(source:GetShadowOffset())
    end
end

function RaidCC:InstallShowSuppression(frame, nameplate)
    if not frame or frame._actuallyRaidCCShowHooked or not hooksecurefunc then
        return
    end
    frame._actuallyRaidCCShowHooked = true
    hooksecurefunc(frame, "Show", function(self)
        local state = nameplate._actuallyRaidCCState
        if state and state.active then
            self:Hide()
        end
    end)
end

function RaidCC:InstallHooks(nameplate)
    self:InstallShowSuppression(nameplate[FULL_FRAME_FIELD], nameplate)
    self:InstallShowSuppression(nameplate[LITE_FRAME_FIELD], nameplate)
    self:InstallShowSuppression(nameplate[LITE_ICON_FIELD], nameplate)
end

function RaidCC:SuppressTurboPlates(nameplate)
    SafeHide(nameplate[FULL_FRAME_FIELD])
    SafeHide(nameplate[LITE_FRAME_FIELD])
    SafeHide(nameplate[LITE_ICON_FIELD])
end

function RaidCC:RemoveOverride(nameplate, plateIsBeingRemoved, reason)
    local state = nameplate and nameplate._actuallyRaidCCState
    if not state then
        return
    end

    local wasActive = state.active
    state.active = false
    state.retryAt = nil
    state.retryScheduled = false
    state.arrowShown = false
    state.arrowKind = nil
    if state.overlay then
        state.overlay.arrow:Hide()
        state.overlay.arrowShadow:Hide()
        state.overlay:Hide()
    end
    if wasActive then
        self:Debug("override removed reason=" .. tostring(reason or "reevaluated")
            .. " " .. UnitDescription(state.unit))
    end
    if plateIsBeingRemoved or not wasActive then
        return
    end

    -- _isLite is TurboPlates' display-mode decision and is never changed here.
    if nameplate._isLite then
        SafeHide(nameplate[FULL_FRAME_FIELD])
        SafeShow(nameplate[LITE_FRAME_FIELD])
    else
        SafeHide(nameplate[LITE_FRAME_FIELD])
        SafeHide(nameplate[LITE_ICON_FIELD])
        SafeShow(nameplate[FULL_FRAME_FIELD])
    end
end

function RaidCC:HasTrackedCC(unit)
    if not unit or not UnitExists(unit) then
        return false
    end
    local bestKind
    local bestName
    local bestSpellID
    local bestPriority = 0
    for index = 1, 40 do
        local name, _, _, _, _, _, _, _, _, _, spellID = UnitDebuff(unit, index)
        if not name then
            break
        end
        local kind = (spellID and trackedSpellIDs[spellID]) or self.trackedSpellNames[name]
        local priority = kind and CC_PRIORITY[kind] or 0
        if priority > bestPriority then
            bestKind = kind
            bestName = name
            bestSpellID = spellID
            bestPriority = priority
        end
    end
    if bestKind then
        return true, bestKind, bestName, bestSpellID
    end
    return false, nil, nil, nil
end

function RaidCC:UpdateArrow(state)
    local valid = state.active
        and state.unit
        and UnitExists(state.unit)
        and UnitGUID(state.unit) == state.guid
        and self.raidGUIDs[state.guid] == true
    local hasCC, kind, spellName, spellID = valid and self:HasTrackedCC(state.unit)
    if hasCC then
        local color = CC_ARROW_COLORS[kind] or { 1, 1, 1 }
        state.overlay.arrow:SetVertexColor(color[1], color[2], color[3], 1)
        state.overlay.arrowShadow:Show()
        state.overlay.arrow:Show()
    else
        state.overlay.arrow:Hide()
        state.overlay.arrowShadow:Hide()
    end
    local shown = hasCC and true or false
    if state.arrowShown ~= shown or state.arrowKind ~= kind then
        state.arrowShown = shown
        state.arrowKind = kind
        self:Debug("CC arrow " .. (shown and ("shown:" .. tostring(kind)) or "hidden")
            .. " " .. UnitDescription(state.unit)
            .. (shown and (" spell=" .. tostring(spellName)
                .. " spellID=" .. tostring(spellID)) or ""))
    end
end

function RaidCC:ApplyOverride(nameplate, unit, state)
    state.active = true
    state.retryAt = nil
    self:InstallHooks(nameplate)
    self:CopyNameAppearance(nameplate, unit, state.overlay)
    self:SuppressTurboPlates(nameplate)
    state.overlay:Show()
    self:UpdateArrow(state)
end

function RaidCC:EvaluatePlate(nameplate, unit)
    if not nameplate then
        return
    end
    local state = self:GetState(nameplate)
    unit = unit or state.unit or nameplate._unit or nameplate._turboTrackedUnit
    local guid = unit and UnitExists(unit) and UnitGUID(unit) or nil

    if state.unit and self.unitToPlate[state.unit] == nameplate and state.unit ~= unit then
        self.unitToPlate[state.unit] = nil
    end
    state.unit = unit
    state.guid = guid
    if unit then
        self.unitToPlate[unit] = nameplate
    end

    local shouldOverride, decision = self:ClassifyUnit(unit)
    if not shouldOverride then
        if state.debugDecision ~= decision then
            state.debugDecision = decision
            self:Debug("plate decision=" .. tostring(decision) .. " "
                .. UnitDescription(unit))
        end
        self:RemoveOverride(nameplate, false, decision)
        return
    end

    if not self:HasCompatibleFrames(nameplate) then
        state.active = false
        state.overlay:Hide()
        state.retryCount = (state.retryCount or 0) + 1
        state.retryAt = Now()
        local retryDecision = "waiting-compatible-frames:" .. tostring(state.retryCount)
        if state.debugDecision ~= retryDecision then
            state.debugDecision = retryDecision
            self:Debug("plate decision=waiting-compatible-frames retry="
                .. tostring(state.retryCount) .. " " .. UnitDescription(unit)
                .. " full=" .. tostring(nameplate[FULL_FRAME_FIELD] ~= nil)
                .. " lite=" .. tostring(nameplate[LITE_FRAME_FIELD] ~= nil)
                .. " liteIcon=" .. tostring(nameplate[LITE_ICON_FIELD] ~= nil))
        end
        if state.retryCount <= 2 then
            self:ScheduleGuardedRetry(nameplate, state)
        else
            self:WarnCompatibility()
        end
        return
    end

    state.retryCount = 0
    state.retryScheduled = false
    if state.debugDecision ~= "override-active" then
        state.debugDecision = "override-active"
        self:Debug("plate decision=override-active " .. UnitDescription(unit)
            .. " isLite=" .. tostring(nameplate._isLite and true or false))
    end
    self:ApplyOverride(nameplate, unit, state)
end

function RaidCC:SafeEvaluatePlate(nameplate, unit)
    local ok, reason = pcall(self.EvaluatePlate, self, nameplate, unit)
    if not ok then
        self:RemoveOverride(nameplate, false)
        self:Print("plate evaluation failed safely: " .. tostring(reason))
    end
end

function RaidCC:OnPlateAdded(unit, suppliedNameplate)
    local nameplate = suppliedNameplate or GetPlateForUnit(unit)
    if not nameplate then
        self:Debug("plate added but no frame was resolved " .. UnitDescription(unit))
        return
    end
    self:Debug("plate added source=" .. (suppliedNameplate and "manager" or "event")
        .. " " .. UnitDescription(unit))
    self.visiblePlates[nameplate] = true
    local state = self:GetState(nameplate)
    state.unit = unit
    state.guid = UnitGUID(unit)
    state.retryCount = 0
    self:SafeEvaluatePlate(nameplate, unit)
end

function RaidCC:OnPlateRemoved(unit, suppliedNameplate)
    local nameplate = suppliedNameplate or self.unitToPlate[unit] or GetPlateForUnit(unit)
    if not nameplate then
        self:Debug("plate removed but no tracked frame was resolved " .. UnitDescription(unit))
        return
    end
    self:Debug("plate removed source=" .. (suppliedNameplate and "manager" or "event")
        .. " " .. UnitDescription(unit))
    local state = nameplate._actuallyRaidCCState
    if state then
        self:RemoveOverride(nameplate, true, "plate-removed")
        state.unit = nil
        state.guid = nil
        state.retryCount = 0
        state.retryScheduled = false
    end
    self.unitToPlate[unit] = nil
    self.visiblePlates[nameplate] = nil
end

function RaidCC:DiscoverVisiblePlates()
    if not C_NamePlateManager or not C_NamePlateManager.EnumerateActiveNamePlates then
        return
    end
    local discovered = 0
    for nameplate in C_NamePlateManager.EnumerateActiveNamePlates() do
        discovered = discovered + 1
        self.visiblePlates[nameplate] = true
        local unit = nameplate._unit or nameplate._turboTrackedUnit
        if unit then
            local state = self:GetState(nameplate)
            state.unit = unit
            state.guid = UnitGUID(unit)
            self.unitToPlate[unit] = nameplate
        end
    end
    self:Debug("active plate discovery enumerated=" .. tostring(discovered)
        .. " tracked=" .. tostring(CountTable(self.visiblePlates)))
end

function RaidCC:ReevaluateVisiblePlates()
    self:DiscoverVisiblePlates()
    for nameplate in pairs(self.visiblePlates) do
        local state = nameplate._actuallyRaidCCState
        self:SafeEvaluatePlate(nameplate, state and state.unit)
    end
end

function RaidCC:GetCVarValue(name)
    local value = GetCVar and GetCVar(name)
    return value ~= nil and tostring(value) or "0"
end

function RaidCC:ForceRequiredCVars()
    if not SetCVar then
        return
    end
    self.cvarGuard = true
    local changed = {}
    local ok, reason = pcall(function()
        if self:GetCVarValue("nameplateShowFriends") ~= "1" then
            SetCVar("nameplateShowFriends", "1")
            table.insert(changed, "friends")
        end
        if self:GetCVarValue("nameplateShowEnemies") ~= "1" then
            SetCVar("nameplateShowEnemies", "1")
            table.insert(changed, "enemies")
        end
    end)
    self.cvarGuard = false
    if not ok then
        self:Print("could not enable required nameplate settings: " .. tostring(reason))
        return false
    end
    if #changed > 0 then
        self:Debug("forced nameplate CVars: " .. table.concat(changed, ","))
    end
    return true
end

function RaidCC:SaveCVarSnapshot()
    local snapshot = self.db.cvarSnapshot
    if type(snapshot) == "table" and snapshot.valid then
        return
    end
    self.db.cvarSnapshot = {
        valid = true,
        friends = self:GetCVarValue("nameplateShowFriends"),
        enemies = self:GetCVarValue("nameplateShowEnemies"),
    }
    self:Debug("saved CVar snapshot friends=" .. tostring(self.db.cvarSnapshot.friends)
        .. " enemies=" .. tostring(self.db.cvarSnapshot.enemies))
end

function RaidCC:RestoreCVars(clearSnapshot)
    local snapshot = self.db and self.db.cvarSnapshot
    if type(snapshot) == "table" and snapshot.valid and SetCVar then
        self.cvarGuard = true
        local ok, reason = pcall(function()
            SetCVar("nameplateShowFriends", snapshot.friends or "0")
            SetCVar("nameplateShowEnemies", snapshot.enemies or "0")
        end)
        self.cvarGuard = false
        if not ok then
            self:Print("could not restore previous nameplate settings: " .. tostring(reason))
            return false
        end
        self:Debug("restored CVar snapshot friends=" .. tostring(snapshot.friends)
            .. " enemies=" .. tostring(snapshot.enemies)
            .. " clear=" .. tostring(clearSnapshot and true or false))
    end
    if clearSnapshot and self.db then
        self.db.cvarSnapshot = nil
    end
    return true
end

function RaidCC:EnterActiveMode()
    local compatible, code, message = self:GetCompatibilityStatus()
    if not compatible then
        self:WarnEnvironment(code, message)
        return
    end
    if self.runtimeActive then
        if not self:ForceRequiredCVars() then
            self:LeaveActiveMode()
            return
        end
        self:RebuildRaidGUIDCache()
        self:ReevaluateVisiblePlates()
        return
    end
    self:SaveCVarSnapshot()
    self.runtimeActive = true
    self:Debug("entering active raid mode")
    if not self:ForceRequiredCVars() then
        self.runtimeActive = false
        self:RestoreCVars(true)
        return
    end
    self:RebuildRaidGUIDCache()
    self:ReevaluateVisiblePlates()
end

function RaidCC:LeaveActiveMode()
    for nameplate in pairs(self.visiblePlates) do
        self:RemoveOverride(nameplate, false, "mode-disabled")
    end
    self.runtimeActive = false
    self:Debug("leaving active raid mode")
    self:RestoreCVars(true)
    ClearTable(self.raidGUIDs)
end

function RaidCC:RefreshMode()
    local requested = self:IsModeRequested()
    local compatible, code, message = self:GetCompatibilityStatus()
    if requested and compatible then
        self:EnterActiveMode()
    else
        if self.runtimeActive then
            self:LeaveActiveMode()
        elseif self.db and self.db.cvarSnapshot and self.db.cvarSnapshot.valid then
            -- Recover a snapshot left by a reload/logout that came back disabled,
            -- outside a raid, or without a usable TurboPlates environment.
            self:RestoreCVars(true)
        end
        if requested and not compatible then
            self:WarnEnvironment(code, message)
        end
    end
    self:RefreshOptionsStatus()
end

function RaidCC:OnHeartbeat(elapsed)
    if not self.runtimeActive then
        return
    end
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < HEARTBEAT_INTERVAL then
        return
    end
    self.elapsed = 0

    local compatible = self:GetCompatibilityStatus()
    if not compatible then
        self:RefreshMode()
        return
    end

    for nameplate in pairs(self.visiblePlates) do
        local state = nameplate._actuallyRaidCCState
        if state then
            if state.retryAt then
                local currentGUID = state.unit and UnitExists(state.unit) and UnitGUID(state.unit)
                if currentGUID == state.guid then
                    self:SafeEvaluatePlate(nameplate, state.unit)
                else
                    self:RemoveOverride(nameplate, false)
                end
            elseif state.active then
                local valid = state.unit
                    and UnitExists(state.unit)
                    and UnitGUID(state.unit) == state.guid
                    and self.raidGUIDs[state.guid] == true
                if not valid then
                    self:SafeEvaluatePlate(nameplate, state.unit)
                else
                    self:InstallHooks(nameplate)
                    self:SuppressTurboPlates(nameplate)
                    self:CopyNameAppearance(nameplate, state.unit, state.overlay)
                    self:UpdateArrow(state)
                end
            end
        end
    end
end

function RaidCC:OnRosterChanged()
    local shouldBeActive = self:ShouldModeBeActive()
    self:Debug("roster changed shouldBeActive=" .. tostring(shouldBeActive)
        .. " runtime=" .. tostring(self.runtimeActive)
        .. " raidCount=" .. tostring(RaidCount()))
    self:RefreshMode()
end

function RaidCC:OnUnitChanged(unit, auraOnly)
    local nameplate = unit and self.unitToPlate[unit]
    local state = nameplate and nameplate._actuallyRaidCCState
    if not state or not state.active or state.unit ~= unit or UnitGUID(unit) ~= state.guid then
        return
    end
    if auraOnly then
        self:UpdateArrow(state)
    else
        self:CopyNameAppearance(nameplate, unit, state.overlay)
    end
end

function RaidCC:BuildTrackedSpellNames()
    ClearTable(self.trackedSpellNames)
    for spellID, kind in pairs(trackedSpellIDs) do
        local name = GetSpellInfo and GetSpellInfo(spellID)
        if name then
            self.trackedSpellNames[name] = kind
        end
    end
    -- Ascension may remap IDs, but stable English names still qualify.
    self.trackedSpellNames.Cyclone = CC_CYCLONE
    self.trackedSpellNames.Shadowfury = CC_SHADOWFURY
end

function RaidCC:Initialize()
    if self.initialized then
        return
    end
    ActuallyDB = ActuallyDB or {}
    ActuallyDB.raidCC = type(ActuallyDB.raidCC) == "table" and ActuallyDB.raidCC or {}
    if ActuallyDB.raidCC.enabled == nil then
        ActuallyDB.raidCC.enabled = false
    end
    self.db = ActuallyDB.raidCC
    if self.db.debug == nil then self.db.debug = false end
    self.debugEnabled = self.db.debug == true
    self:BuildTrackedSpellNames()
    self:DiscoverVisiblePlates()
    self.initialized = true
    self:RefreshMode()
    self:Debug("initialized")
    if Addon.CacheTips and Addon.CacheTips.RefreshRaidCCToggle then
        Addon.CacheTips:RefreshRaidCCToggle()
    end
end

local Events = {}

function Events.ADDON_LOADED(addonName)
    if addonName == "TurboPlates"
        or addonName == "ElvUI"
        or addonName == "Kui_Nameplates"
        or addonName == "TidyPlates_ThreatPlates"
        or addonName == "PlateBuffs" then
        RaidCC:RefreshMode()
    end
end

function Events.PLAYER_LOGIN()
    RaidCC:RefreshMode()
end

function Events.PLAYER_ENTERING_WORLD()
    RaidCC:RefreshMode()
    if RaidCC.runtimeActive then
        RaidCC:RebuildRaidGUIDCache()
        RaidCC:ReevaluateVisiblePlates()
    end
end

function Events.GROUP_ROSTER_UPDATE()
    RaidCC:OnRosterChanged()
end

Events.RAID_ROSTER_UPDATE = Events.GROUP_ROSTER_UPDATE

function Events.ZONE_CHANGED_NEW_AREA()
    RaidCC:OnRosterChanged()
end

function Events.NAME_PLATE_UNIT_ADDED(unit)
    RaidCC:OnPlateAdded(unit)
end

function Events.NAME_PLATE_UNIT_REMOVED(unit)
    RaidCC:OnPlateRemoved(unit)
end

function Events.UNIT_AURA(unit)
    RaidCC:OnUnitChanged(unit, true)
end

function Events.UNIT_NAME_UPDATE(unit)
    RaidCC:OnUnitChanged(unit, false)
end

function Events.CVAR_UPDATE(cvarName)
    if RaidCC.cvarGuard then
        return
    end
    if not RaidCC.runtimeActive then
        if RaidCC:IsModeRequested() then
            RaidCC:RefreshMode()
        end
        return
    end
    local compatible = RaidCC:GetCompatibilityStatus()
    if not compatible then
        RaidCC:RefreshMode()
        return
    end
    -- Wrath and Ascension builds report different CVAR_UPDATE names. Checking
    -- the two required values on any CVar event avoids depending on that label.
    if not RaidCC:ForceRequiredCVars() then
        RaidCC:LeaveActiveMode()
    end
end

function Events.PLAYER_LOGOUT()
    if RaidCC.runtimeActive then
        -- Keep the valid snapshot so a reload cannot mistake the temporary
        -- both-on state for the player's original preference.
        -- Clear runtime first so a delayed CVAR_UPDATE cannot force both on again.
        RaidCC.runtimeActive = false
        RaidCC:RestoreCVars(false)
    end
end

RaidCC.eventFrame = CreateFrame("Frame")
for event in pairs(Events) do
    pcall(RaidCC.eventFrame.RegisterEvent, RaidCC.eventFrame, event)
end
RaidCC.eventFrame:SetScript("OnEvent", function(_, event, ...)
    if not RaidCC.initialized then
        return
    end
    local handler = Events[event]
    if handler then
        handler(...)
    end
end)

-- TurboPlates 1.4.5 uses these manager callbacks for its authoritative plate
-- lifecycle. OptionalDeps guarantees its callback registration happens first.
-- The traditional NAME_PLATE events above remain as a harmless fallback.
if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("NamePlateManager.UnitAdded", function(_, unit, nameplate)
        RaidCC:OnPlateAdded(unit, nameplate)
    end)
    EventRegistry:RegisterCallback("NamePlateManager.UnitRemoved", function(_, unit, nameplate)
        RaidCC:OnPlateRemoved(unit, nameplate)
    end)
end

RaidCC.heartbeatFrame = CreateFrame("Frame")
RaidCC.heartbeatFrame:SetScript("OnUpdate", function(_, elapsed)
    RaidCC:OnHeartbeat(elapsed)
end)

if SlashCmdList then
    SLASH_ACTUALLYRAIDCC1 = "/raidcc"
    SLASH_ACTUALLYRAIDCC2 = "/rcc"
    SlashCmdList.ACTUALLYRAIDCC = function(input)
        RaidCC:HandleCommand(input)
    end
end
