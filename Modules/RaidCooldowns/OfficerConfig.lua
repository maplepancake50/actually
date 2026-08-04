local ARC = Actually.Modules.RaidCooldowns
local OfficerConfig = ARC:NewModule("OfficerConfig")

local FRAME_WIDTH = 1120
local FRAME_HEIGHT = 790
local CONTENT_TOP = 94

local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local TABS = {
    {
        key = "plans",
        label = "Plans",
        width = 70,
        officer = true,
        description = "Build reusable cooldown bundles, then assemble them into commander buttons.",
    },
    {
        key = "combos",
        label = "Timed Combos",
        width = 105,
        officer = true,
        module = "ComboConfig",
        description = "Build synchronized countdowns with a separate timing offset for each cooldown.",
    },
    {
        key = "spells",
        label = "Spell Visibility",
        width = 105,
        officer = true,
        module = "SpellConfig",
        description = "Choose which registered cooldowns appear in the officer cooldown display.",
    },
    {
        key = "activity",
        label = "Activity",
        width = 78,
        officer = true,
        module = "Activity",
        description = "Review requested responses, timing misses, and unassigned cooldown uses.",
    },
    {
        key = "diagnostics",
        label = "Diagnostics",
        width = 90,
        module = "Diagnostics",
        description = "Run the three-player ARC test harness and collect combined reports.",
    },
    {
        key = "spoof",
        label = "Spell Spoof",
        width = 88,
        officer = true,
        module = "SpoofTest",
        description = "Simulate registered cooldown ownership and uses for local officer testing.",
    },
    {
        key = "probe",
        label = "API Probe",
        width = 82,
        module = "SpecAPIProbe",
        description = "Inspect Ascension build, specialization, spellbook, and talent APIs.",
    },
}

local TAB_ALIASES = {
    bundle = "plans",
    bundles = "plans",
    command = "plans",
    commands = "plans",
    commander = "plans",
    combo = "combos",
    config = "spells",
    spell = "spells",
    history = "activity",
    responses = "activity",
    performance = "activity",
    diag = "diagnostics",
    test = "diagnostics",
    testpanel = "diagnostics",
    specprobe = "probe",
}

local function setBackdrop(frame, background, border)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(background[1], background[2], background[3], background[4] or 1)
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function savePosition(frame, profile)
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    profile.point = point
    profile.relativePoint = relativePoint
    profile.x = x
    profile.y = y
end

local function getFitScale(profile)
    local requested = clamp(tonumber(profile.scale) or 1, 0.65, 1.15)
    if not UIParent or not UIParent.GetWidth or not UIParent.GetHeight then
        return requested
    end
    local availableWidth = math.max(1, (UIParent:GetWidth() or FRAME_WIDTH) - 30)
    local availableHeight = math.max(1, (UIParent:GetHeight() or FRAME_HEIGHT) - 30)
    local fit = math.min(1, availableWidth / FRAME_WIDTH, availableHeight / FRAME_HEIGHT)
    return math.max(0.65, math.min(requested, fit))
end

local function normalizeTab(key)
    key = string.lower(tostring(key or "plans"))
    return TAB_ALIASES[key] or key
end

local function getTab(key)
    key = normalizeTab(key)
    for _, definition in ipairs(TABS) do
        if definition.key == key then return definition end
    end
    return nil
end

local function hasPanel(definition)
    if definition.key == "plans" then
        return ARC.BundleConfig and ARC.BundleConfig.frame
            and ARC.CommanderConfig and ARC.CommanderConfig.frame
    end
    local module = definition.module and ARC[definition.module]
    return module and module.frame
end

local function canUse(definition)
    return not definition.officer or ARC:HasConfigurationAuthority()
end

local function preparePanel(panel, parent, point, relativeTo, relativePoint, x, y)
    panel:SetParent(parent)
    panel:ClearAllPoints()
    panel:SetPoint(point, relativeTo, relativePoint, x or 0, y or 0)
    panel:SetScale(1)
    panel:SetMovable(false)
    panel:SetClampedToScreen(false)
    panel:SetScript("OnDragStart", nil)
    panel:SetScript("OnDragStop", nil)
    panel:SetFrameStrata(parent:GetFrameStrata())
    panel:SetFrameLevel(parent:GetFrameLevel() + 2)
    if panel.dragBar then panel.dragBar:Hide() end
    if panel.close then panel.close:Hide() end
    if panel.lock then panel.lock:Hide() end
    if panel.resizeGrip then panel.resizeGrip:Hide() end
    if panel.scaleText then panel.scaleText:Hide() end
end

function OfficerConfig:HidePanels()
    for _, definition in ipairs(TABS) do
        if definition.key == "plans" then
            if ARC.BundleConfig and ARC.BundleConfig.frame then ARC.BundleConfig.frame:Hide() end
            if ARC.CommanderConfig and ARC.CommanderConfig.frame then
                ARC.CommanderConfig.frame:Hide()
            end
        elseif definition.module then
            local module = ARC[definition.module]
            if module and module.frame then module.frame:Hide() end
        end
    end
end

function OfficerConfig:RefreshTabs()
    local prior
    for _, definition in ipairs(TABS) do
        local button = self.tabButtons[definition.key]
        local visible = hasPanel(definition) and canUse(definition)
        if visible then
            button:ClearAllPoints()
            if prior then
                button:SetPoint("LEFT", prior, "RIGHT", 5, 0)
            else
                button:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 14, -43)
            end
            button:Show()
            if definition.key == self.activeTab then button:Disable() else button:Enable() end
            prior = button
        else
            button:Hide()
        end
    end
end

function OfficerConfig:Refresh()
    if self.activeTab == "plans" then
        if ARC.BundleConfig and ARC.BundleConfig.Refresh then ARC.BundleConfig:Refresh() end
        if ARC.CommanderConfig and ARC.CommanderConfig.Refresh then
            ARC.CommanderConfig:Refresh()
        end
        return
    end
    local definition = getTab(self.activeTab)
    local module = definition and definition.module and ARC[definition.module]
    if not module then return end
    if module.Refresh then module:Refresh()
    elseif module.RefreshPanel then module:RefreshPanel()
    elseif module.RefreshHeader then module:RefreshHeader() end
end

function OfficerConfig:ShowPanel(key)
    local definition = getTab(key)
    if not definition or not hasPanel(definition) then return false end
    if definition.officer and not ARC:RequireConfigurationAuthority() then return false end

    self:HidePanels()
    self.activeTab = definition.key
    self.frame.subtitle:SetText(definition.description)

    if definition.key == "plans" then
        local bundleFrame = ARC.BundleConfig.frame
        local commandFrame = ARC.CommanderConfig.frame
        preparePanel(bundleFrame, self.content, "LEFT", self.content, "LEFT", 5, 0)
        preparePanel(commandFrame, self.content, "RIGHT", self.content, "RIGHT", -5, 0)
        bundleFrame:SetHeight(602)
        commandFrame:SetHeight(602)
        ARC.CommanderConfig.listPanel:SetHeight(380)
        bundleFrame.title:SetText("1. Cooldown Bundle Builder")
        bundleFrame.subtitle:SetText(
            "New Bundle -> choose cooldowns -> Create Bundle. Edit with Save Changes.")
        commandFrame.title:SetText("2. Commander Button Builder")
        commandFrame.subtitle:SetText(
            "Choose stages plus an Enabled, Disabled, or Error-on-press behavior.")
        bundleFrame:Show()
        commandFrame:Show()
        self.divider:Show()
    else
        local module = ARC[definition.module]
        preparePanel(module.frame, self.content, "CENTER", self.content, "CENTER", 0, 0)
        module.frame:Show()
        self.divider:Hide()
    end

    self:RefreshTabs()
    self:Refresh()
    return true
end

function OfficerConfig:Initialize()
    local profile = ARC.db.profile.officerConfigUI
    local frame = CreateFrame("Frame", "ActuallyARCOfficerConfigFrame", UIParent)
    frame:SetWidth(FRAME_WIDTH)
    frame:SetHeight(FRAME_HEIGHT)
    frame:SetPoint(
        profile.point or "CENTER",
        UIParent,
        profile.relativePoint or profile.point or "CENTER",
        profile.x or 0,
        profile.y or 0)
    frame:SetScale(getFitScale(profile))
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    setBackdrop(frame, { 0.012, 0.022, 0.034, 0.995 }, { 0.20, 0.70, 0.96, 1 })
    self.frame = frame

    frame.dragBar = CreateFrame("Frame", nil, frame)
    frame.dragBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    frame.dragBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -42, -4)
    frame.dragBar:SetHeight(35)
    frame.dragBar:EnableMouse(true)
    frame.dragBar:RegisterForDrag("LeftButton")
    frame.dragBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame.dragBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        savePosition(frame, profile)
    end)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -12)
    frame.title:SetText("Actually Raid Cooldowns - ARC Console - "
        .. ARC.Constants.WIP_TEXT)
    frame.title:SetTextColor(0.92, 0.96, 1.00)

    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
    frame.close:SetScript("OnClick", function() OfficerConfig:Hide() end)

    frame.subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.subtitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -73)
    frame.subtitle:SetWidth(FRAME_WIDTH - 32)
    frame.subtitle:SetJustifyH("LEFT")
    frame.subtitle:SetTextColor(0.48, 0.72, 0.84)

    self.content = CreateFrame("Frame", nil, frame)
    self.content:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -CONTENT_TOP)
    self.content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)

    self.tabButtons = {}
    for _, definition in ipairs(TABS) do
        local tabKey = definition.key
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetWidth(definition.width)
        button:SetHeight(24)
        button:SetText(definition.label)
        button:SetScript("OnClick", function() OfficerConfig:Show(tabKey) end)
        self.tabButtons[tabKey] = button
    end

    self.divider = self.content:CreateTexture(nil, "ARTWORK")
    self.divider:SetWidth(1)
    self.divider:SetPoint("TOP", self.content, "TOP", -6, -40)
    self.divider:SetPoint("BOTTOM", self.content, "BOTTOM", -6, 40)
    self.divider:SetTexture("Interface\\Buttons\\WHITE8X8")
    self.divider:SetVertexColor(0.20, 0.56, 0.78, 0.55)

    frame:SetScript("OnHide", function() OfficerConfig:HidePanels() end)
    self.activeTab = ARC:HasConfigurationAuthority() and "plans" or "diagnostics"
    self:RefreshTabs()
    frame:Hide()
end

function OfficerConfig:Show(focus)
    local definition = getTab(focus or self.activeTab)
    if definition and definition.officer and not ARC:HasConfigurationAuthority() then
        ARC:RequireConfigurationAuthority()
        return false
    end
    if not definition or not hasPanel(definition) then
        definition = getTab(ARC:HasConfigurationAuthority() and "plans" or "diagnostics")
    end
    if not definition or not hasPanel(definition) then
        ARC:Print("ARC console panel unavailable; fully restart the game client")
        return false
    end
    if definition.officer and not ARC:RequireConfigurationAuthority() then return false end
    if not self:ShowPanel(definition.key) then return false end
    self.frame:Show()
    return true
end

function OfficerConfig:Hide()
    if not self.frame then return end
    for _, moduleName in ipairs({
        "BundleConfig", "CommanderConfig", "ComboConfig", "SpellConfig",
        "Diagnostics", "SpoofTest", "SpecAPIProbe",
    }) do
        local module = ARC[moduleName]
        if module and module.nameBox then module.nameBox:ClearFocus() end
        if module and module.searchBox then module.searchBox:ClearFocus() end
        if module and module.search then module.search:ClearFocus() end
    end
    self.frame:Hide()
end

function OfficerConfig:Toggle(focus)
    local key = normalizeTab(focus or self.activeTab)
    if self.frame:IsShown() and self.activeTab == key then
        self:Hide()
        return false
    end
    return self:Show(key)
end

function OfficerConfig:IsHosting(key)
    return self.frame and self.frame:IsShown() and self.activeTab == normalizeTab(key)
end

function OfficerConfig:IsPublicTab()
    return self:IsHosting("diagnostics") or self:IsHosting("probe")
end
