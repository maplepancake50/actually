local Addon = Actually

Addon.EnemyMarkers = Addon.EnemyMarkers or {}
local EnemyMarkers = Addon.EnemyMarkers

local ARROW_TEXTURE = "Interface\\AddOns\\Actually\\Textures\\RaidCCArrow.blp"
local FULL_FRAME_FIELD = "myPlate"
local MIN_SIZE = 18
local MAX_SIZE = 90
local MIN_HEIGHT = 0
local MAX_HEIGHT = 200
local PRESET_VERSION = 1

local CATEGORY_DEFINITIONS = {
    {
        key = "healer",
        label = "Enemy Healer Arrow",
        shortLabel = "Healer",
        priority = 200,
        defaultColor = "green",
        defaultSize = 44,
        defaultHeight = 12,
    },
    {
        key = "frontline",
        label = "Enemy Frontline Arrow",
        shortLabel = "Frontline",
        priority = 100,
        defaultColor = "red",
        defaultSize = 44,
        defaultHeight = 12,
    },
}

local CATEGORY_BY_KEY = {}
for _, definition in ipairs(CATEGORY_DEFINITIONS) do
    CATEGORY_BY_KEY[definition.key] = definition
end

local COLOR_OPTIONS = {
    { key = "green", label = "Green", color = { 0.15, 1.00, 0.25 } },
    { key = "red", label = "Red", color = { 1.00, 0.18, 0.18 } },
    { key = "purple", label = "Purple", color = { 0.72, 0.20, 1.00 } },
    { key = "yellow", label = "Yellow", color = { 1.00, 0.88, 0.16 } },
    { key = "blue", label = "Blue", color = { 0.20, 0.62, 1.00 } },
    { key = "orange", label = "Orange", color = { 1.00, 0.48, 0.10 } },
    { key = "white", label = "White", color = { 1.00, 1.00, 1.00 } },
}

local COLOR_BY_KEY = {}
for _, option in ipairs(COLOR_OPTIONS) do
    COLOR_BY_KEY[option.key] = option
end

EnemyMarkers.visiblePlates = EnemyMarkers.visiblePlates or {}
EnemyMarkers.unitToPlate = EnemyMarkers.unitToPlate or {}
EnemyMarkers.nameIndexes = EnemyMarkers.nameIndexes or {}
EnemyMarkers.initialized = false
EnemyMarkers.settingsRefreshing = false

local function ClearTable(value)
    if wipe then
        wipe(value)
        return
    end
    for key in pairs(value or {}) do
        value[key] = nil
    end
end

local function Clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function Round(value)
    return math.floor((tonumber(value) or 0) + 0.5)
end

local function Trim(value)
    if Addon.Util and Addon.Util.Trim then
        return Addon.Util.Trim(value)
    end
    return string.gsub(tostring(value or ""), "^%s*(.-)%s*$", "%1")
end

local function NormalizeIdentity(value)
    if Addon.Util and Addon.Util.NormalizeIdentity then
        return Addon.Util.NormalizeIdentity(value)
    end
    return string.lower(string.gsub(Trim(value), "%s+", ""))
end

local function NormalizeCharacter(value)
    if Addon.Util and Addon.Util.NormalizeCharacter then
        return Addon.Util.NormalizeCharacter(value)
    end
    return string.lower(string.match(Trim(value), "^([^%-]+)") or Trim(value))
end

local function CountTable(value)
    local count = 0
    for _ in pairs(value or {}) do count = count + 1 end
    return count
end

local function IsNamedAddOnLoaded(name)
    if not IsAddOnLoaded then return false end
    local ok, loaded = pcall(IsAddOnLoaded, name)
    return ok and loaded and true or false
end

local function GetPlateForUnit(unit)
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        return C_NamePlate.GetNamePlateForUnit(unit)
    end
end

local function GetUnitIdentity(unit)
    local name, realm
    if UnitFullName then
        name, realm = UnitFullName(unit)
    end
    if not name and UnitName then
        name, realm = UnitName(unit)
    end
    name = Trim(name)
    realm = Trim(realm)
    if name == "" then return nil end

    local full = name
    if realm ~= "" and not string.find(name, "-", 1, true) then
        full = name .. "-" .. realm
    end
    return NormalizeIdentity(full), NormalizeCharacter(name), full
end

local function GetNameEntries(text)
    local entries = {}
    local seen = {}
    text = string.gsub(tostring(text or ""), "\r", "\n")
    for value in string.gmatch(text, "[^\n,;]+") do
        value = Trim(value)
        local normalized = NormalizeIdentity(value)
        if normalized ~= "" and not seen[normalized] then
            seen[normalized] = true
            table.insert(entries, value)
        end
    end
    return entries
end

local function SetBackdrop(frame, background, border)
    if Addon.Util and Addon.Util.SetBackdrop then
        Addon.Util.SetBackdrop(frame, background, border)
    end
end

function EnemyMarkers:Print(message)
    if Addon.Print then
        Addon:Print("Enemy Markers: " .. tostring(message))
    elseif DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("actually: Enemy Markers: " .. tostring(message))
    end
end

function EnemyMarkers:GetOfficerPresetText()
    local authority
    if Addon.Official and Addon.Official.GetAuthority then
        authority = Addon.Official:GetAuthority()
    else
        authority = Addon.db and Addon.db.authority
    end

    local names = {}
    local seen = {}
    local function Add(identity)
        identity = Trim(identity)
        local key = NormalizeIdentity(identity)
        if identity ~= "" and not seen[key] then
            seen[key] = true
            table.insert(names, identity)
        end
    end

    if type(authority) == "table" then
        Add(authority.owner)
        for identity, enabled in pairs(authority.officers or {}) do
            if enabled == true then Add(identity) end
        end
    end
    table.sort(names, function(left, right)
        return string.lower(left) < string.lower(right)
    end)
    return table.concat(names, "\n")
end

function EnemyMarkers:NormalizeSettings()
    self.db.categories = type(self.db.categories) == "table" and self.db.categories or {}
    self.db.enabled = self.db.enabled == true
    self.db.selectedCategory = CATEGORY_BY_KEY[self.db.selectedCategory]
        and self.db.selectedCategory or "healer"

    for _, definition in ipairs(CATEGORY_DEFINITIONS) do
        local settings = type(self.db.categories[definition.key]) == "table"
            and self.db.categories[definition.key] or {}
        self.db.categories[definition.key] = settings
        if settings.enabled == nil then settings.enabled = true end
        settings.enabled = settings.enabled == true
        settings.names = tostring(settings.names or "")
        settings.color = COLOR_BY_KEY[settings.color]
            and settings.color or definition.defaultColor
        settings.size = Round(Clamp(
            settings.size or definition.defaultSize, MIN_SIZE, MAX_SIZE))
        settings.height = Round(Clamp(
            settings.height or definition.defaultHeight, MIN_HEIGHT, MAX_HEIGHT))
        -- Horizontal placement is intentionally fixed over the nameplate.
        -- Clear the former saved option when upgrading existing profiles.
        settings.xOffset = nil
        settings.pulse = settings.pulse == true
        if settings.glow == nil then settings.glow = true end
        settings.glow = settings.glow == true
    end

    local presetVersion = tonumber(self.db.presetVersion) or 0
    if presetVersion < PRESET_VERSION then
        local preset = self:GetOfficerPresetText()
        local frontline = self.db.categories.frontline
        if Trim(frontline.names) == "" and preset ~= "" then
            frontline.names = preset
            self.db.presetVersion = PRESET_VERSION
        elseif preset ~= "" then
            self.db.presetVersion = PRESET_VERSION
        end
    end
end

function EnemyMarkers:GetCategorySettings(categoryKey)
    local definition = CATEGORY_BY_KEY[categoryKey or self.db.selectedCategory]
    if not definition then return nil end
    return self.db.categories[definition.key]
end

function EnemyMarkers:GetCategoryDefinition(categoryKey)
    return CATEGORY_BY_KEY[categoryKey or self.db.selectedCategory]
end

function EnemyMarkers:BuildNameIndexes()
    ClearTable(self.nameIndexes)
    for _, definition in ipairs(CATEGORY_DEFINITIONS) do
        local index = { full = {}, short = {}, count = 0 }
        local settings = self:GetCategorySettings(definition.key)
        for _, entry in ipairs(GetNameEntries(settings.names)) do
            local normalized = NormalizeIdentity(entry)
            if string.find(normalized, "-", 1, true) then
                index.full[normalized] = true
            else
                index.short[NormalizeCharacter(entry)] = true
            end
            index.count = index.count + 1
        end
        self.nameIndexes[definition.key] = index
    end
end

function EnemyMarkers:GetCategoryNameCount(categoryKey)
    local index = self.nameIndexes[categoryKey]
    return index and index.count or 0
end

function EnemyMarkers:MatchUnit(unit)
    local fullName, shortName = GetUnitIdentity(unit)
    if not fullName then return nil end
    for _, definition in ipairs(CATEGORY_DEFINITIONS) do
        local settings = self:GetCategorySettings(definition.key)
        local index = self.nameIndexes[definition.key]
        if settings.enabled and index
            and (index.full[fullName] or index.short[shortName]) then
            return definition.key
        end
    end
end

function EnemyMarkers:IsEligibleEnemyPlayer(unit)
    if not unit or not UnitExists(unit) then return false end
    if UnitIsPlayer and not UnitIsPlayer(unit) then return false end
    if UnitIsUnit and UnitIsUnit(unit, "player") then return false end
    if UnitIsFriend and UnitIsFriend("player", unit) then return false end
    if UnitCanAttack and not UnitCanAttack("player", unit) then return false end
    return true
end

local function CreateArrowVisual(parent)
    local visual = CreateFrame("Frame", nil, parent)
    visual:SetSize(44, 44)
    visual:EnableMouse(false)

    local shadow = visual:CreateTexture(nil, "ARTWORK")
    shadow:SetTexture(ARROW_TEXTURE)
    shadow:SetPoint("CENTER", visual, "CENTER", 2, -2)
    shadow:SetVertexColor(0, 0, 0, 1)
    shadow:SetAlpha(0.82)
    visual.shadow = shadow

    local glow = visual:CreateTexture(nil, "ARTWORK")
    glow:SetTexture(ARROW_TEXTURE)
    glow:SetPoint("CENTER", visual, "CENTER", 0, 0)
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0.34)
    glow:Hide()
    visual.glow = glow

    local arrow = visual:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture(ARROW_TEXTURE)
    arrow:SetAllPoints(visual)
    visual.arrow = arrow

    if visual.CreateAnimationGroup then
        local ok, pulse = pcall(function()
            local group = visual:CreateAnimationGroup()
            if not group or not group.CreateAnimation
                or not group.SetLooping or not group.Play or not group.Stop then
                return nil
            end
            local fadeOut = group:CreateAnimation("Alpha")
            local fadeIn = group:CreateAnimation("Alpha")
            fadeOut:SetChange(-0.32)
            fadeOut:SetDuration(0.35)
            fadeOut:SetOrder(1)
            fadeIn:SetChange(0.32)
            fadeIn:SetDuration(0.35)
            fadeIn:SetOrder(2)
            group:SetLooping("REPEAT")
            return group
        end)
        if ok and pulse then visual.pulseAnimation = pulse end
    end
    visual:Hide()
    return visual
end

local function SetPulseRunning(visual, shouldPulse)
    local pulse = visual and visual.pulseAnimation
    if pulse then
        if shouldPulse then
            if not pulse.IsPlaying or not pulse:IsPlaying() then
                visual:SetAlpha(1)
                pulse:Play()
            end
        else
            if not pulse.IsPlaying or pulse:IsPlaying() then pulse:Stop() end
            visual:SetAlpha(1)
        end
        if visual.SetScript then visual:SetScript("OnUpdate", nil) end
        return
    end
    if not visual or not visual.SetScript then return end
    if shouldPulse then
        visual:SetScript("OnUpdate", function(self)
            if GetTime then
                self:SetAlpha(0.68
                    + 0.32 * ((math.sin(GetTime() * 6) + 1) * 0.5))
            end
        end)
    else
        visual:SetScript("OnUpdate", nil)
        visual:SetAlpha(1)
    end
end

local function GetVisibleElementHeight(element, fallback)
    if not element or not element.IsShown or not element:IsShown() then return 0 end
    if element.displayedCount ~= nil and (element.displayedCount or 0) <= 0 then
        return 0
    end

    -- TurboPlates aura containers stay 30px tall even when their configurable
    -- icons are taller. Read the actual visible pooled icons first.
    local height = 0
    local displayedCount = tonumber(element.displayedCount) or 0
    if displayedCount > 0 and type(element.icons) == "table" then
        for index = 1, displayedCount do
            local icon = element.icons[index]
            if icon and (not icon.IsShown or icon:IsShown()) and icon.GetHeight then
                height = math.max(height, icon:GetHeight() or 0)
            end
        end
    end
    if height <= 0 then
        height = element.GetHeight and element:GetHeight() or 0
    end
    if not height or height <= 0 then height = fallback end
    return math.min(math.max(height, fallback), 100)
end

local function IsTurboDebuffTopAnchored(frame)
    if not frame or not frame.IsShown or not frame:IsShown() then return false end
    if frame.cachedAnchor ~= nil then
        return frame.cachedAnchor == "TOP"
    end
    if frame.GetPoint then
        local point, _, relativePoint = frame:GetPoint(1)
        return point == "BOTTOM" and relativePoint == "TOP"
    end
    return false
end

local function InstallLayoutVisibilityHook(element, state)
    if not element or element._actuallyEnemyMarkerLayoutHooked
        or not hooksecurefunc then
        return
    end
    element._actuallyEnemyMarkerLayoutHooked = true
    hooksecurefunc(element, "Show", function()
        EnemyMarkers:SchedulePosition(state)
    end)
    hooksecurefunc(element, "Hide", function()
        EnemyMarkers:SchedulePosition(state)
    end)
end

function EnemyMarkers:InstallLayoutHooks(state)
    local myPlate = state and state.myPlate
    if not myPlate then return end
    InstallLayoutVisibilityHook(myPlate.nameText, state)
    InstallLayoutVisibilityHook(myPlate.debuffContainer, state)
    InstallLayoutVisibilityHook(myPlate.buffContainer, state)
    InstallLayoutVisibilityHook(myPlate.healerIcon, state)
    InstallLayoutVisibilityHook(myPlate.turboDebuff, state)
end

function EnemyMarkers:PositionVisual(state)
    local visual = state and state.visual
    local myPlate = state and state.myPlate
    local settings = state and self:GetCategorySettings(state.category)
    if not visual or not myPlate or not settings then return end
    self:InstallLayoutHooks(state)

    local anchor = myPlate.hp or myPlate
    local y = settings.height
    y = y + GetVisibleElementHeight(myPlate.nameText, 12)
    if myPlate.nameText and myPlate.nameText.IsShown and myPlate.nameText:IsShown() then
        y = y + 3
    end
    local debuffHeight = GetVisibleElementHeight(myPlate.debuffContainer, 22)
    if debuffHeight > 0 then y = y + debuffHeight + 4 end
    local buffHeight = GetVisibleElementHeight(myPlate.buffContainer, 22)
    if buffHeight > 0 then y = y + buffHeight + 4 end
    local healerIconHeight = GetVisibleElementHeight(myPlate.healerIcon, 24)
    if healerIconHeight > 0 then y = y + healerIconHeight + 4 end
    if IsTurboDebuffTopAnchored(myPlate.turboDebuff) then
        local turboDebuffHeight = GetVisibleElementHeight(myPlate.turboDebuff, 32)
        if turboDebuffHeight > 0 then y = y + turboDebuffHeight + 4 end
    end

    visual:ClearAllPoints()
    visual:SetPoint("BOTTOM", anchor, "TOP", 0, y)
end

function EnemyMarkers:ApplyVisual(state)
    local visual = state and state.visual
    local settings = state and self:GetCategorySettings(state.category)
    if not visual or not settings then return end
    local option = COLOR_BY_KEY[settings.color] or COLOR_BY_KEY.green
    local color = option.color
    local size = settings.size

    visual:SetSize(size, size)
    visual.shadow:SetSize(size, size)
    visual.glow:SetSize(size + 14, size + 14)
    visual.arrow:SetVertexColor(color[1], color[2], color[3], 1)
    visual.glow:SetVertexColor(color[1], color[2], color[3], 1)
    if settings.glow then visual.glow:Show() else visual.glow:Hide() end
    self:PositionVisual(state)
    visual:Show()
    SetPulseRunning(visual, settings.pulse)
end

function EnemyMarkers:HideState(state)
    if not state then return end
    state.category = nil
    state.matched = false
    state.positionScheduled = false
    if state.visual then
        SetPulseRunning(state.visual, false)
        state.visual.glow:Hide()
        state.visual:Hide()
    end
end

function EnemyMarkers:GetState(nameplate)
    local state = nameplate._actuallyEnemyMarkerState
    if not state then
        state = {
            unit = nil,
            guid = nil,
            category = nil,
            matched = false,
            retryCount = 0,
            retryScheduled = false,
            positionScheduled = false,
            visual = nil,
            myPlate = nil,
        }
        nameplate._actuallyEnemyMarkerState = state
    end
    return state
end

function EnemyMarkers:EnsureVisual(nameplate, state)
    local myPlate = nameplate and nameplate[FULL_FRAME_FIELD]
    if not myPlate then return false end

    local parentMatches = state.visual and state.myPlate == myPlate
    if not parentMatches then
        if state.visual then
            SetPulseRunning(state.visual, false)
            state.visual:Hide()
        end
        state.visual = CreateArrowVisual(myPlate)
        state.myPlate = myPlate
        if state.visual.SetFrameLevel and myPlate.GetFrameLevel then
            state.visual:SetFrameLevel((myPlate:GetFrameLevel() or 0) + 20)
        end
    end
    return true
end

function EnemyMarkers:ScheduleRetry(nameplate, state)
    if state.retryScheduled or not C_Timer or not C_Timer.After then return end
    if (state.retryCount or 0) >= 4 then return end
    state.retryScheduled = true
    state.retryCount = (state.retryCount or 0) + 1
    local delays = { 0, 0.05, 0.20, 0.50 }
    local delay = delays[state.retryCount] or 0.50
    local expectedUnit = state.unit
    local expectedGUID = state.guid
    C_Timer.After(delay, function()
        state.retryScheduled = false
        if not EnemyMarkers:IsEnabled()
            or state.unit ~= expectedUnit
            or state.guid ~= expectedGUID
            or not expectedUnit
            or not UnitExists(expectedUnit)
            or UnitGUID(expectedUnit) ~= expectedGUID then
            return
        end
        EnemyMarkers:EvaluatePlate(nameplate, expectedUnit)
    end)
end

function EnemyMarkers:SchedulePosition(state)
    if not state or not state.matched or state.positionScheduled
        or not C_Timer or not C_Timer.After then
        return
    end
    state.positionScheduled = true
    local expectedUnit = state.unit
    local expectedGUID = state.guid
    -- TurboPlates batches aura layout at 0.05s (or 0.10s in Potato mode).
    -- Reposition after that batch without polling the plate.
    C_Timer.After(0.12, function()
        state.positionScheduled = false
        if state.matched
            and state.unit == expectedUnit
            and state.guid == expectedGUID
            and expectedUnit
            and UnitExists(expectedUnit)
            and UnitGUID(expectedUnit) == expectedGUID then
            EnemyMarkers:PositionVisual(state)
        end
    end)
end

function EnemyMarkers:EvaluatePlate(nameplate, unit)
    if not nameplate then return end
    local state = self:GetState(nameplate)
    unit = unit or state.unit or nameplate._unit or nameplate._turboTrackedUnit
    local guid = unit and UnitExists(unit) and UnitGUID(unit) or nil

    if state.unit and self.unitToPlate[state.unit] == nameplate and state.unit ~= unit then
        self.unitToPlate[state.unit] = nil
    end
    state.unit = unit
    state.guid = guid
    if unit then self.unitToPlate[unit] = nameplate end

    if not self.db.enabled
        or not IsNamedAddOnLoaded("TurboPlates")
        or not self:IsEligibleEnemyPlayer(unit) then
        self:HideState(state)
        return
    end

    local category = self:MatchUnit(unit)
    if not category then
        self:HideState(state)
        return
    end

    if not self:EnsureVisual(nameplate, state) then
        self:HideState(state)
        state.unit = unit
        state.guid = guid
        self:ScheduleRetry(nameplate, state)
        return
    end

    state.retryCount = 0
    state.retryScheduled = false
    state.category = category
    state.matched = true
    self:ApplyVisual(state)
end

function EnemyMarkers:SafeEvaluatePlate(nameplate, unit)
    local ok, reason = pcall(self.EvaluatePlate, self, nameplate, unit)
    if not ok then
        self:HideState(nameplate and nameplate._actuallyEnemyMarkerState)
        self:Print("plate update failed safely: " .. tostring(reason))
    end
end

function EnemyMarkers:OnPlateAdded(unit, suppliedNameplate)
    if not self.initialized then return end
    local nameplate = suppliedNameplate or GetPlateForUnit(unit)
    if not nameplate then return end
    local existing = nameplate._actuallyEnemyMarkerState
    local guid = UnitGUID(unit)
    if self.visiblePlates[nameplate] and existing
        and existing.unit == unit and existing.guid == guid then return end
    self.visiblePlates[nameplate] = true
    local state = self:GetState(nameplate)
    state.retryCount = 0
    self:SafeEvaluatePlate(nameplate, unit)
end

function EnemyMarkers:OnPlateRemoved(unit, suppliedNameplate)
    if not self.initialized then return end
    local nameplate = suppliedNameplate or self.unitToPlate[unit] or GetPlateForUnit(unit)
    if not nameplate then return end
    if not self.visiblePlates[nameplate]
        and not (nameplate._actuallyEnemyMarkerState
            and nameplate._actuallyEnemyMarkerState.unit) then return end
    local state = nameplate._actuallyEnemyMarkerState
    if state then
        self:HideState(state)
        state.unit = nil
        state.guid = nil
        state.retryCount = 0
        state.retryScheduled = false
    end
    self.unitToPlate[unit] = nil
    self.visiblePlates[nameplate] = nil
end

function EnemyMarkers:DiscoverVisiblePlates()
    if not C_NamePlateManager
        or not C_NamePlateManager.EnumerateActiveNamePlates then
        return
    end
    for nameplate in C_NamePlateManager.EnumerateActiveNamePlates() do
        self.visiblePlates[nameplate] = true
        local unit = nameplate._unit or nameplate._turboTrackedUnit
        if unit then self:SafeEvaluatePlate(nameplate, unit) end
    end
end

function EnemyMarkers:ReevaluateVisiblePlates(discover)
    if discover then self:DiscoverVisiblePlates() end
    for nameplate in pairs(self.visiblePlates) do
        local state = nameplate._actuallyEnemyMarkerState
        self:SafeEvaluatePlate(nameplate, state and state.unit)
    end
    self:RefreshSettingsStatus()
end

function EnemyMarkers:RefreshVisibleAppearance(categoryKey)
    for nameplate in pairs(self.visiblePlates) do
        local state = nameplate._actuallyEnemyMarkerState
        if state and state.matched
            and (not categoryKey or state.category == categoryKey) then
            self:ApplyVisual(state)
        end
    end
    self:RefreshSettingsPanel()
end

function EnemyMarkers:IsEnabled()
    return self.db and self.db.enabled == true or false
end

function EnemyMarkers:SetEnabled(enabled)
    if not self.db then return end
    self.db.enabled = enabled == true
    self:UpdateRuntimeEvents()
    if self.db.enabled then
        self:ReevaluateVisiblePlates(true)
    else
        for nameplate in pairs(self.visiblePlates) do
            local state = nameplate._actuallyEnemyMarkerState
            self:HideState(state)
            if state then
                state.unit = nil
                state.guid = nil
                state.retryCount = 0
                state.retryScheduled = false
            end
        end
        -- Removal events are disabled with the feature, so retained mappings
        -- would become stale before the next enable.
        ClearTable(self.visiblePlates)
        ClearTable(self.unitToPlate)
    end
    self:RefreshSettingsStatus()
    if Addon.CacheTips and Addon.CacheTips.RefreshEnemyMarkerToggle then
        Addon.CacheTips:RefreshEnemyMarkerToggle()
    end
end

function EnemyMarkers:UpdateRuntimeEvents()
    if not self.eventFrame then return end
    for _, event in ipairs({
        "UNIT_AURA", "UNIT_NAME_UPDATE",
        "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    }) do
        if self:IsEnabled() then
            pcall(self.eventFrame.RegisterEvent, self.eventFrame, event)
        else
            pcall(self.eventFrame.UnregisterEvent, self.eventFrame, event)
        end
    end
end

function EnemyMarkers:GetRuntimeStatus()
    if not self:IsEnabled() then
        return "disabled", "Disabled. TurboPlates is unchanged."
    end
    if not IsNamedAddOnLoaded("TurboPlates") then
        return "blocked", "TurboPlates is not enabled for this character."
    end
    local matched = 0
    for nameplate in pairs(self.visiblePlates) do
        local state = nameplate._actuallyEnemyMarkerState
        if state and state.matched then matched = matched + 1 end
    end
    return "active", tostring(matched) .. " visible named enemy player"
        .. (matched == 1 and "" or "s") .. " marked."
end

function EnemyMarkers:SetSelectedCategory(categoryKey)
    if not CATEGORY_BY_KEY[categoryKey] then return false end
    if self.settingsFrame and self.settingsFrame.namesEdit
        and self.settingsFrame.namesEdit:HasFocus() then
        self.settingsFrame.namesEdit:ClearFocus()
    end
    self.db.selectedCategory = categoryKey
    self:RefreshSettingsPanel()
    return true
end

function EnemyMarkers:SetCategoryEnabled(enabled, categoryKey)
    local settings = self:GetCategorySettings(categoryKey)
    if not settings then return end
    settings.enabled = enabled == true
    self:ReevaluateVisiblePlates(false)
    self:RefreshSettingsPanel()
end

function EnemyMarkers:SetCategoryNamesText(text, categoryKey)
    local settings = self:GetCategorySettings(categoryKey)
    if not settings then return end
    settings.names = tostring(text or "")
    self:BuildNameIndexes()
    self:ReevaluateVisiblePlates(false)
end

function EnemyMarkers:SetColor(colorKey, categoryKey)
    local settings = self:GetCategorySettings(categoryKey)
    if not settings or not COLOR_BY_KEY[colorKey] then return false end
    settings.color = colorKey
    self:RefreshVisibleAppearance(categoryKey or self.db.selectedCategory)
    return true
end

function EnemyMarkers:SetSize(value, categoryKey)
    local settings = self:GetCategorySettings(categoryKey)
    if not settings then return end
    settings.size = Round(Clamp(value, MIN_SIZE, MAX_SIZE))
    self:RefreshVisibleAppearance(categoryKey or self.db.selectedCategory)
end

function EnemyMarkers:SetHeight(value, categoryKey)
    local settings = self:GetCategorySettings(categoryKey)
    if not settings then return end
    settings.height = Round(Clamp(value, MIN_HEIGHT, MAX_HEIGHT))
    self:RefreshVisibleAppearance(categoryKey or self.db.selectedCategory)
end

function EnemyMarkers:SetPulse(enabled, categoryKey)
    local settings = self:GetCategorySettings(categoryKey)
    if not settings then return end
    settings.pulse = enabled == true
    self:RefreshVisibleAppearance(categoryKey or self.db.selectedCategory)
end

function EnemyMarkers:SetGlow(enabled, categoryKey)
    local settings = self:GetCategorySettings(categoryKey)
    if not settings then return end
    settings.glow = enabled == true
    self:RefreshVisibleAppearance(categoryKey or self.db.selectedCategory)
end

function EnemyMarkers:ResetSelectedAppearance()
    local definition = self:GetCategoryDefinition()
    local settings = self:GetCategorySettings()
    if not definition or not settings then return end
    settings.color = definition.defaultColor
    settings.size = definition.defaultSize
    settings.height = definition.defaultHeight
    settings.pulse = false
    settings.glow = true
    self:RefreshVisibleAppearance(definition.key)
end

local function SetSliderText(slider, label, value)
    if slider and slider.valueText then
        slider.valueText:SetText(label .. ": " .. tostring(Round(value)))
    end
end

function EnemyMarkers:CreateSettingsPanel()
    if self.settingsFrame then return self.settingsFrame end

    local frame = CreateFrame("Frame", "ActuallyEnemyMarkerSettingsFrame", UIParent)
    frame:SetWidth(650)
    frame:SetHeight(680)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 10)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart", function(owner) owner:StartMoving() end)
    frame:SetScript("OnDragStop", function(owner) owner:StopMovingOrSizing() end)
    SetBackdrop(frame, { 0.025, 0.032, 0.045, 0.98 }, { 0.84, 0.26, 0.24, 0.95 })

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -16)
    title:SetText("Enemy Player Arrow Settings")
    title:SetTextColor(1.00, 0.55, 0.30)

    local description = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -7)
    description:SetWidth(590)
    description:SetJustifyH("LEFT")
    description:SetText(
        "Marks only named enemy players. TurboPlates health, cast, buff, and debuff frames remain active.")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    local selectorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    selectorLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -72)
    selectorLabel:SetText("Editing arrow")

    local selector = CreateFrame(
        "Frame", "ActuallyEnemyMarkerCategoryDropdown", frame, "UIDropDownMenuTemplate")
    selector:SetPoint("TOPLEFT", selectorLabel, "BOTTOMLEFT", -15, -3)
    UIDropDownMenu_SetWidth(selector, 220)
    UIDropDownMenu_Initialize(selector, function()
        for _, definition in ipairs(CATEGORY_DEFINITIONS) do
            local categoryKey = definition.key
            local info = UIDropDownMenu_CreateInfo()
            info.text = definition.label
            info.value = categoryKey
            info.checked = EnemyMarkers.db.selectedCategory == categoryKey
            info.func = function()
                EnemyMarkers:SetSelectedCategory(categoryKey)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local categoryEnabled = CreateFrame(
        "CheckButton", "ActuallyEnemyMarkerCategoryEnabled", frame, "UICheckButtonTemplate")
    categoryEnabled:SetPoint("TOPLEFT", frame, "TOPLEFT", 342, -84)
    local categoryEnabledLabel = categoryEnabled:CreateFontString(
        nil, "OVERLAY", "GameFontHighlight")
    categoryEnabledLabel:SetPoint("LEFT", categoryEnabled, "RIGHT", 4, 1)
    categoryEnabledLabel:SetText("Show this arrow category")
    categoryEnabled:SetScript("OnClick", function(owner)
        if EnemyMarkers.settingsRefreshing then return end
        EnemyMarkers:SetCategoryEnabled(
            owner:GetChecked() == 1 or owner:GetChecked() == true)
    end)

    local namesPanel = CreateFrame("Frame", nil, frame)
    namesPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -132)
    namesPanel:SetWidth(306)
    namesPanel:SetHeight(486)
    SetBackdrop(namesPanel, { 0.035, 0.045, 0.060, 0.98 }, { 0.34, 0.58, 0.78, 0.78 })

    local namesTitle = namesPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    namesTitle:SetPoint("TOPLEFT", namesPanel, "TOPLEFT", 12, -12)
    namesTitle:SetText("Enemy player names")

    local namesHelp = namesPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    namesHelp:SetPoint("TOPLEFT", namesTitle, "BOTTOMLEFT", 0, -5)
    namesHelp:SetWidth(280)
    namesHelp:SetJustifyH("LEFT")
    namesHelp:SetText(
        "One name per line. Name-Realm is exact; a bare name matches that character on any realm.")

    local inputBackground = CreateFrame("Frame", nil, namesPanel)
    inputBackground:SetPoint("TOPLEFT", namesPanel, "TOPLEFT", 10, -68)
    inputBackground:SetPoint("BOTTOMRIGHT", namesPanel, "BOTTOMRIGHT", -10, 76)
    SetBackdrop(inputBackground, { 0.012, 0.016, 0.025, 0.98 }, { 0.30, 0.45, 0.60, 0.58 })

    local scroll = CreateFrame(
        "ScrollFrame", "ActuallyEnemyMarkerNamesScroll", inputBackground,
        "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", inputBackground, "TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", inputBackground, "BOTTOMRIGHT", -28, 8)

    local namesEdit = CreateFrame("EditBox", nil, scroll)
    namesEdit:SetWidth(240)
    namesEdit:SetHeight(250)
    namesEdit:SetMultiLine(true)
    namesEdit:SetAutoFocus(false)
    namesEdit:SetFontObject("ChatFontNormal")
    namesEdit:SetTextColor(0.90, 0.93, 0.98)
    namesEdit:SetJustifyH("LEFT")
    namesEdit:SetJustifyV("TOP")
    namesEdit:SetMaxLetters(5000)
    scroll:SetScrollChild(namesEdit)
    namesEdit:SetScript("OnEscapePressed", function(owner) owner:ClearFocus() end)
    namesEdit:SetScript("OnTextChanged", function(owner, userInput)
        if userInput and not EnemyMarkers.settingsRefreshing then
            EnemyMarkers:SetCategoryNamesText(owner:GetText() or "")
            EnemyMarkers:RefreshSettingsStatus()
        end
    end)

    local namesStatus = namesPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    namesStatus:SetPoint("BOTTOMLEFT", namesPanel, "BOTTOMLEFT", 12, 48)
    namesStatus:SetWidth(278)
    namesStatus:SetJustifyH("LEFT")

    local precedence = namesPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    precedence:SetPoint("BOTTOMLEFT", namesPanel, "BOTTOMLEFT", 12, 13)
    precedence:SetWidth(278)
    precedence:SetJustifyH("LEFT")
    precedence:SetText("|cffffcc44If a name is in both lists, Enemy Healer Arrow wins.|r")

    local appearance = CreateFrame("Frame", nil, frame)
    appearance:SetPoint("TOPLEFT", frame, "TOPLEFT", 334, -132)
    appearance:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 62)
    SetBackdrop(appearance, { 0.045, 0.034, 0.038, 0.98 }, { 0.78, 0.35, 0.28, 0.78 })

    local appearanceTitle = appearance:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    appearanceTitle:SetPoint("TOPLEFT", appearance, "TOPLEFT", 12, -12)
    appearanceTitle:SetText("Arrow appearance and position")

    local preview = CreateFrame("Frame", nil, appearance)
    preview:SetPoint("TOPLEFT", appearance, "TOPLEFT", 12, -38)
    preview:SetPoint("TOPRIGHT", appearance, "TOPRIGHT", -12, -38)
    preview:SetHeight(105)
    SetBackdrop(preview, { 0.018, 0.022, 0.030, 0.98 }, { 0.32, 0.38, 0.46, 0.70 })

    local previewBar = preview:CreateTexture(nil, "ARTWORK")
    previewBar:SetTexture("Interface\\Buttons\\WHITE8X8")
    previewBar:SetVertexColor(0.28, 0.30, 0.34, 1)
    previewBar:SetSize(150, 10)
    previewBar:SetPoint("BOTTOM", preview, "BOTTOM", 0, 16)
    local previewVisual = CreateArrowVisual(preview)
    previewVisual:SetPoint("BOTTOM", previewBar, "TOP", 0, 8)
    previewVisual:Show()

    local colorLabel = appearance:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    colorLabel:SetPoint("TOPLEFT", appearance, "TOPLEFT", 14, -154)
    colorLabel:SetText("Arrow colour")

    local colorDropdown = CreateFrame(
        "Frame", "ActuallyEnemyMarkerColorDropdown", appearance,
        "UIDropDownMenuTemplate")
    colorDropdown:SetPoint("TOPLEFT", colorLabel, "BOTTOMLEFT", -15, -2)
    UIDropDownMenu_SetWidth(colorDropdown, 150)
    UIDropDownMenu_Initialize(colorDropdown, function()
        local settings = EnemyMarkers:GetCategorySettings()
        for _, option in ipairs(COLOR_OPTIONS) do
            local colorKey = option.key
            local info = UIDropDownMenu_CreateInfo()
            info.text = option.label
            info.value = colorKey
            info.checked = settings and settings.color == colorKey
            info.func = function() EnemyMarkers:SetColor(colorKey) end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local function CreateSlider(name, y, minimum, maximum, setter)
        local slider = CreateFrame("Slider", name, appearance, "OptionsSliderTemplate")
        slider:SetPoint("TOPLEFT", appearance, "TOPLEFT", 18, y)
        slider:SetWidth(255)
        slider:SetMinMaxValues(minimum, maximum)
        slider:SetValueStep(1)
        _G[name .. "Low"]:SetText(tostring(minimum))
        _G[name .. "High"]:SetText(tostring(maximum))
        _G[name .. "Text"]:SetText("")
        local valueText = appearance:CreateFontString(
            nil, "OVERLAY", "GameFontHighlightSmall")
        valueText:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 3)
        slider.valueText = valueText
        slider:SetScript("OnValueChanged", function(owner)
            if EnemyMarkers.settingsRefreshing then return end
            setter(EnemyMarkers, owner:GetValue())
        end)
        return slider
    end

    local sizeSlider = CreateSlider(
        "ActuallyEnemyMarkerSizeSlider", -250, MIN_SIZE, MAX_SIZE,
        EnemyMarkers.SetSize)
    local heightSlider = CreateSlider(
        "ActuallyEnemyMarkerHeightSlider", -318, MIN_HEIGHT, MAX_HEIGHT,
        EnemyMarkers.SetHeight)
    local positionHelp = appearance:CreateFontString(
        nil, "OVERLAY", "GameFontHighlightSmall")
    positionHelp:SetPoint("TOPLEFT", appearance, "TOPLEFT", 14, -366)
    positionHelp:SetWidth(270)
    positionHelp:SetJustifyH("LEFT")
    positionHelp:SetText(
        "The arrow automatically clears TurboPlates' name, debuffs, and buffs. Extra height adds up to 200 more pixels.")

    local pulse = CreateFrame(
        "CheckButton", "ActuallyEnemyMarkerPulse", appearance, "UICheckButtonTemplate")
    pulse:SetPoint("BOTTOMLEFT", appearance, "BOTTOMLEFT", 10, 42)
    local pulseLabel = pulse:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pulseLabel:SetPoint("LEFT", pulse, "RIGHT", 3, 1)
    pulseLabel:SetText("Pulse")
    pulse:SetScript("OnClick", function(owner)
        if not EnemyMarkers.settingsRefreshing then
            EnemyMarkers:SetPulse(owner:GetChecked() == 1 or owner:GetChecked() == true)
        end
    end)

    local glow = CreateFrame(
        "CheckButton", "ActuallyEnemyMarkerGlow", appearance, "UICheckButtonTemplate")
    glow:SetPoint("LEFT", pulseLabel, "RIGHT", 24, 0)
    local glowLabel = glow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    glowLabel:SetPoint("LEFT", glow, "RIGHT", 3, 1)
    glowLabel:SetText("Glow")
    glow:SetScript("OnClick", function(owner)
        if not EnemyMarkers.settingsRefreshing then
            EnemyMarkers:SetGlow(owner:GetChecked() == 1 or owner:GetChecked() == true)
        end
    end)

    local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    reset:SetWidth(124)
    reset:SetHeight(24)
    reset:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 18)
    reset:SetText("Reset Appearance")
    reset:SetScript("OnClick", function()
        EnemyMarkers:ResetSelectedAppearance()
    end)

    local done = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    done:SetWidth(90)
    done:SetHeight(24)
    done:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 18)
    done:SetText("Done")
    done:SetScript("OnClick", function() frame:Hide() end)

    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("BOTTOM", frame, "BOTTOM", 0, 25)
    status:SetWidth(330)

    frame.categorySelector = selector
    frame.categoryEnabled = categoryEnabled
    frame.namesEdit = namesEdit
    frame.namesStatus = namesStatus
    frame.colorDropdown = colorDropdown
    frame.sizeSlider = sizeSlider
    frame.heightSlider = heightSlider
    frame.pulse = pulse
    frame.glow = glow
    frame.previewVisual = previewVisual
    frame.status = status
    frame:Hide()
    self.settingsFrame = frame
    return frame
end

function EnemyMarkers:RefreshSettingsStatus()
    local frame = self.settingsFrame
    if not frame or not frame.status then return end
    local state, status = self:GetRuntimeStatus()
    frame.status:SetText(status)
    if state == "active" then
        frame.status:SetTextColor(0.30, 1.00, 0.42)
    elseif state == "blocked" then
        frame.status:SetTextColor(1.00, 0.30, 0.22)
    else
        frame.status:SetTextColor(0.72, 0.75, 0.80)
    end
end

function EnemyMarkers:RefreshSettingsPanel()
    local frame = self.settingsFrame
    if not frame then return end
    local definition = self:GetCategoryDefinition()
    local settings = self:GetCategorySettings()
    if not definition or not settings then return end

    self.settingsRefreshing = true
    UIDropDownMenu_SetText(frame.categorySelector, definition.label)
    UIDropDownMenu_SetText(
        frame.colorDropdown,
        (COLOR_BY_KEY[settings.color] or COLOR_BY_KEY.green).label)
    frame.categoryEnabled:SetChecked(settings.enabled)
    if not frame.namesEdit:HasFocus()
        and frame.namesEdit:GetText() ~= settings.names then
        frame.namesEdit:SetText(settings.names)
    end
    frame.namesStatus:SetText(
        tostring(self:GetCategoryNameCount(definition.key))
        .. " unique name"
        .. (self:GetCategoryNameCount(definition.key) == 1 and "" or "s")
        .. " in " .. definition.shortLabel)
    frame.sizeSlider:SetValue(settings.size)
    frame.heightSlider:SetValue(settings.height)
    SetSliderText(frame.sizeSlider, "Arrow size", settings.size)
    SetSliderText(frame.heightSlider, "Extra height", settings.height)
    frame.pulse:SetChecked(settings.pulse)
    frame.glow:SetChecked(settings.glow)

    local option = COLOR_BY_KEY[settings.color] or COLOR_BY_KEY.green
    frame.previewVisual:SetSize(settings.size, settings.size)
    frame.previewVisual.shadow:SetSize(settings.size, settings.size)
    frame.previewVisual.glow:SetSize(settings.size + 14, settings.size + 14)
    frame.previewVisual.arrow:SetVertexColor(
        option.color[1], option.color[2], option.color[3], 1)
    frame.previewVisual.glow:SetVertexColor(
        option.color[1], option.color[2], option.color[3], 1)
    if settings.glow then
        frame.previewVisual.glow:Show()
    else
        frame.previewVisual.glow:Hide()
    end
    frame.previewVisual:Show()
    SetPulseRunning(frame.previewVisual, settings.pulse)
    self.settingsRefreshing = false
    self:RefreshSettingsStatus()
end

function EnemyMarkers:ToggleSettings()
    if not self.initialized then self:Initialize() end
    local frame = self:CreateSettingsPanel()
    if frame:IsShown() then
        frame:Hide()
    else
        self:RefreshSettingsPanel()
        frame:Show()
        if frame.Raise then frame:Raise() end
    end
end

function EnemyMarkers:Initialize()
    if self.initialized then return end
    ActuallyDB = ActuallyDB or {}
    ActuallyDB.enemyMarkers = type(ActuallyDB.enemyMarkers) == "table"
        and ActuallyDB.enemyMarkers or {}
    self.db = ActuallyDB.enemyMarkers
    self:NormalizeSettings()
    self:BuildNameIndexes()
    self.initialized = true
    self:UpdateRuntimeEvents()
    if self:IsEnabled() then self:DiscoverVisiblePlates() end
    if Addon.CacheTips and Addon.CacheTips.RefreshEnemyMarkerToggle then
        Addon.CacheTips:RefreshEnemyMarkerToggle()
    end
end

local Events = {}

function Events.ADDON_LOADED(addonName)
    if addonName == "TurboPlates" and EnemyMarkers.initialized then
        EnemyMarkers:ReevaluateVisiblePlates(true)
    end
end

function Events.PLAYER_ENTERING_WORLD()
    if not EnemyMarkers.initialized then return end
    EnemyMarkers:NormalizeSettings()
    EnemyMarkers:BuildNameIndexes()
    EnemyMarkers:UpdateRuntimeEvents()
    if EnemyMarkers:IsEnabled() then EnemyMarkers:ReevaluateVisiblePlates(true) end
end

function Events.NAME_PLATE_UNIT_ADDED(unit)
    if EnemyMarkers:IsEnabled() then EnemyMarkers:OnPlateAdded(unit) end
end

function Events.NAME_PLATE_UNIT_REMOVED(unit)
    if EnemyMarkers:IsEnabled() then EnemyMarkers:OnPlateRemoved(unit) end
end

function Events.UNIT_NAME_UPDATE(unit)
    if not EnemyMarkers.initialized or not EnemyMarkers:IsEnabled() then return end
    local nameplate = EnemyMarkers.unitToPlate[unit]
    if nameplate then EnemyMarkers:SafeEvaluatePlate(nameplate, unit) end
end

function Events.UNIT_AURA(unit)
    if not EnemyMarkers.initialized or not EnemyMarkers:IsEnabled() then return end
    local nameplate = EnemyMarkers.unitToPlate[unit]
    local state = nameplate and nameplate._actuallyEnemyMarkerState
    if state and state.matched and UnitGUID(unit) == state.guid then
        EnemyMarkers:SchedulePosition(state)
    end
end

EnemyMarkers.eventFrame = CreateFrame("Frame")
for event in pairs(Events) do
    pcall(EnemyMarkers.eventFrame.RegisterEvent, EnemyMarkers.eventFrame, event)
end
EnemyMarkers.eventFrame:SetScript("OnEvent", function(_, event, ...)
    local handler = Events[event]
    if handler then handler(...) end
end)

if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("NamePlateManager.UnitAdded", function(_, unit, nameplate)
        if EnemyMarkers:IsEnabled() then EnemyMarkers:OnPlateAdded(unit, nameplate) end
    end)
    EventRegistry:RegisterCallback("NamePlateManager.UnitRemoved", function(_, unit, nameplate)
        if EnemyMarkers:IsEnabled() then EnemyMarkers:OnPlateRemoved(unit, nameplate) end
    end)
end
