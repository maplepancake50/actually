local Addon = Actually

Addon.Modules = Addon.Modules or {}
Addon.Modules.RaidCC = Addon.Modules.RaidCC or {}

local RaidCC = Addon.Modules.RaidCC

local HEARTBEAT_INTERVAL = 0.30
local ARROW_TEXTURE = "Interface\\AddOns\\Actually\\Modules\\RaidCC\\Textures\\arrow.tga"
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

local trackedSpellIDs = {
    [33786] = true, -- Cyclone
    [30283] = true, -- Shadowfury (rank 1)
    [30413] = true, -- Shadowfury (rank 2)
    [30414] = true, -- Shadowfury (rank 3)
    [47846] = true, -- Shadowfury (rank 4)
    [47847] = true, -- Shadowfury (rank 5)
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

local function IsRaid()
    if IsInRaid then
        return IsInRaid() and true or false
    end
    return GetNumRaidMembers and (GetNumRaidMembers() or 0) > 0 or false
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

function RaidCC:WarnCompatibility()
    local current = Now()
    if current - self.lastWarningAt < WARNING_INTERVAL then
        return
    end
    self.lastWarningAt = current
    self:Print("compatible TurboPlates plate fields were not found; raid override was skipped")
end

function RaidCC:ShouldModeBeActive()
    return self.db and self.db.enabled == true and IsRaid()
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
end

function RaidCC:ShouldOverrideUnit(unit)
    if not self.runtimeActive or not unit or not UnitExists(unit) then
        return false
    end
    if not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then
        return false
    end
    local guid = UnitGUID(unit)
    return guid and self.raidGUIDs[guid] == true or false
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

    local arrow = overlay:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture(ARROW_TEXTURE)
    arrow:SetSize(36, 36)
    arrow:SetPoint("BOTTOM", nameText, "TOP", 0, 4)
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

function RaidCC:RemoveOverride(nameplate, plateIsBeingRemoved)
    local state = nameplate and nameplate._actuallyRaidCCState
    if not state then
        return
    end

    local wasActive = state.active
    state.active = false
    state.retryAt = nil
    state.retryScheduled = false
    if state.overlay then
        state.overlay.arrow:Hide()
        state.overlay:Hide()
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
    for index = 1, 40 do
        local name, _, _, _, _, _, _, _, _, _, spellID = UnitDebuff(unit, index)
        if not name then
            break
        end
        if (spellID and trackedSpellIDs[spellID]) or self.trackedSpellNames[name] then
            return true
        end
    end
    return false
end

function RaidCC:UpdateArrow(state)
    local valid = state.active
        and state.unit
        and UnitExists(state.unit)
        and UnitGUID(state.unit) == state.guid
        and self.raidGUIDs[state.guid] == true
    if valid and self:HasTrackedCC(state.unit) then
        state.overlay.arrow:Show()
    else
        state.overlay.arrow:Hide()
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

    if not self:ShouldOverrideUnit(unit) then
        self:RemoveOverride(nameplate, false)
        return
    end

    if not self:HasCompatibleFrames(nameplate) then
        state.active = false
        state.overlay:Hide()
        state.retryCount = (state.retryCount or 0) + 1
        state.retryAt = Now()
        if state.retryCount <= 2 then
            self:ScheduleGuardedRetry(nameplate, state)
        else
            self:WarnCompatibility()
        end
        return
    end

    state.retryCount = 0
    state.retryScheduled = false
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
        return
    end
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
        return
    end
    local state = nameplate._actuallyRaidCCState
    if state then
        self:RemoveOverride(nameplate, true)
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
    for nameplate in C_NamePlateManager.EnumerateActiveNamePlates() do
        self.visiblePlates[nameplate] = true
        local unit = nameplate._unit or nameplate._turboTrackedUnit
        if unit then
            local state = self:GetState(nameplate)
            state.unit = unit
            state.guid = UnitGUID(unit)
            self.unitToPlate[unit] = nameplate
        end
    end
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
    if self:GetCVarValue("nameplateShowFriends") ~= "1" then
        SetCVar("nameplateShowFriends", "1")
    end
    if self:GetCVarValue("nameplateShowEnemies") ~= "1" then
        SetCVar("nameplateShowEnemies", "1")
    end
    self.cvarGuard = false
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
end

function RaidCC:RestoreCVars(clearSnapshot)
    local snapshot = self.db and self.db.cvarSnapshot
    if type(snapshot) == "table" and snapshot.valid and SetCVar then
        self.cvarGuard = true
        SetCVar("nameplateShowFriends", snapshot.friends or "0")
        SetCVar("nameplateShowEnemies", snapshot.enemies or "0")
        self.cvarGuard = false
    end
    if clearSnapshot and self.db then
        self.db.cvarSnapshot = nil
    end
end

function RaidCC:EnterActiveMode()
    if self.runtimeActive then
        self:ForceRequiredCVars()
        self:RebuildRaidGUIDCache()
        self:ReevaluateVisiblePlates()
        return
    end
    self:SaveCVarSnapshot()
    self.runtimeActive = true
    self:ForceRequiredCVars()
    self:RebuildRaidGUIDCache()
    self:ReevaluateVisiblePlates()
end

function RaidCC:LeaveActiveMode()
    for nameplate in pairs(self.visiblePlates) do
        self:RemoveOverride(nameplate, false)
    end
    self.runtimeActive = false
    self:RestoreCVars(true)
    ClearTable(self.raidGUIDs)
end

function RaidCC:RefreshMode()
    if self:ShouldModeBeActive() then
        self:EnterActiveMode()
    elseif self.runtimeActive then
        self:LeaveActiveMode()
    elseif self.db and self.db.cvarSnapshot and self.db.cvarSnapshot.valid then
        -- Recover a snapshot left by a reload/logout that came back disabled
        -- or outside a raid.
        self:RestoreCVars(true)
    end
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
    if not shouldBeActive then
        self:RefreshMode()
        return
    end
    if not self.runtimeActive then
        self:EnterActiveMode()
        return
    end
    self:RebuildRaidGUIDCache()
    self:ReevaluateVisiblePlates()
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
    for spellID in pairs(trackedSpellIDs) do
        local name = GetSpellInfo and GetSpellInfo(spellID)
        if name then
            self.trackedSpellNames[name] = true
        end
    end
    -- Ascension may remap IDs, but stable English names still qualify.
    self.trackedSpellNames.Cyclone = true
    self.trackedSpellNames.Shadowfury = true
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
    self:BuildTrackedSpellNames()
    self:DiscoverVisiblePlates()
    self.initialized = true
    self:RefreshMode()
    if self.Options and self.Options.Refresh then
        self.Options:Refresh()
    end
end

local Events = {}

function Events.ADDON_LOADED(loadedAddon)
    if loadedAddon == Addon.name then
        RaidCC:Initialize()
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
    if not RaidCC.runtimeActive or RaidCC.cvarGuard then
        return
    end
    -- Wrath and Ascension builds report different CVAR_UPDATE names. Checking
    -- the two required values on any CVar event avoids depending on that label.
    RaidCC:ForceRequiredCVars()
end

function Events.PLAYER_LOGOUT()
    if RaidCC.runtimeActive then
        -- Keep the valid snapshot so a reload cannot mistake the temporary
        -- both-on state for the player's original preference.
        RaidCC:RestoreCVars(false)
    end
end

RaidCC.eventFrame = CreateFrame("Frame")
for event in pairs(Events) do
    pcall(RaidCC.eventFrame.RegisterEvent, RaidCC.eventFrame, event)
end
RaidCC.eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event ~= "ADDON_LOADED" and not RaidCC.initialized then
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
