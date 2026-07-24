Actually = Actually or {}
local Addon = Actually

local CacheTips = {}
Addon.CacheTips = CacheTips
local SetBackdrop = Addon.Util.SetBackdrop
local ROLE_PANEL_TOP = -376

local ROLE_DEFINITIONS = {
    {
        key = "healer", title = "HEALER",
        color = { 0.18, 0.76, 0.32 }, border = { 0.32, 1.00, 0.48 },
        icon = "cross",
    },
    {
        key = "dps", title = "DPS",
        color = { 0.92, 0.20, 0.24 }, border = { 1.00, 0.38, 0.42 },
        icon = "Interface\\Icons\\INV_Weapon_ShortBlade_05",
    },
    {
        key = "frontline", title = "FRONTLINE",
        color = { 0.16, 0.44, 0.90 }, border = { 0.28, 0.68, 1.00 },
        icon = "Interface\\Icons\\INV_Shield_06",
    },
}

function CacheTips:CanEdit()
    if not Addon.Official or not Addon.Official:IsOfficer() then
        return false
    end
    return not Addon.Sync or not Addon.Sync.IsOfficialEditReady
        or Addon.Sync:IsOfficialEditReady()
end

function CacheTips:CommitRole(role)
    local draft = self.pendingDrafts and self.pendingDrafts[role]
    if draft == nil then return false end
    self.pendingDrafts[role] = nil
    if draft == tostring(Addon.db.cacheTips[role] or "") then
        return false
    end
    if not self:CanEdit() then
        self:Refresh()
        return false
    end

    Addon.db.cacheTips[role] = draft
    local meta = Addon.db.cacheTipsMeta[role]
    local stamp = time and time() or 0
    meta.updatedAt = math.max(stamp, (tonumber(meta.updatedAt) or 0) + 1)
    meta.updatedBy = Addon.Official:GetPlayerIdentity()
    meta.authorityRevision = tonumber(Addon.Official:GetAuthority().revision) or 0
    if Addon.Official.RecordActivity then
        Addon.Official:RecordActivity("Updated " .. string.upper(role) .. " Cache Tips.")
    end
    if Addon.Sync then
        Addon.Sync:MarkDirty(true)
    end
    return true
end

function CacheTips:QueueRoleDraft(role, text)
    if not self:CanEdit() then
        self:Refresh()
        return
    end
    self.pendingDrafts = self.pendingDrafts or {}
    self.pendingDrafts[role] = tostring(text or "")
    self.nextDraftCommitAt = (GetTime and GetTime() or 0) + 2
end

function CacheTips:CommitPending()
    for _, definition in ipairs(ROLE_DEFINITIONS) do
        self:CommitRole(definition.key)
    end
    self.nextDraftCommitAt = nil
end

local function CreateHealerCross(parent, color)
    local vertical = parent:CreateTexture(nil, "ARTWORK")
    vertical:SetWidth(13)
    vertical:SetHeight(38)
    vertical:SetPoint("CENTER")
    vertical:SetTexture("Interface\\Buttons\\WHITE8X8")
    vertical:SetVertexColor(color[1], color[2], color[3], 1)
    local horizontal = parent:CreateTexture(nil, "ARTWORK")
    horizontal:SetWidth(38)
    horizontal:SetHeight(13)
    horizontal:SetPoint("CENTER")
    horizontal:SetTexture("Interface\\Buttons\\WHITE8X8")
    horizontal:SetVertexColor(color[1], color[2], color[3], 1)
end

local function CreateRolePanel(root, definition, anchor)
    local panel = CreateFrame("Frame", nil, root)
    panel:SetWidth(292)
    panel:SetPoint(anchor.point, root, anchor.point, anchor.x or 0, ROLE_PANEL_TOP)
    panel:SetPoint(anchor.bottom, root, anchor.bottom, anchor.x or 0, 0)
    SetBackdrop(panel,
        { definition.color[1] * 0.10, definition.color[2] * 0.10, definition.color[3] * 0.10, 0.97 },
        { definition.border[1], definition.border[2], definition.border[3], 0.95 })

    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 5, -5)
    header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -5, -5)
    header:SetHeight(50)
    SetBackdrop(header,
        { definition.color[1] * 0.24, definition.color[2] * 0.24, definition.color[3] * 0.24, 0.98 },
        { definition.border[1], definition.border[2], definition.border[3], 0.55 })

    local iconFrame = CreateFrame("Frame", nil, header)
    iconFrame:SetWidth(42)
    iconFrame:SetHeight(42)
    iconFrame:SetPoint("LEFT", header, "LEFT", 8, 0)
    if definition.icon == "cross" then
        CreateHealerCross(iconFrame, definition.border)
    else
        local icon = iconFrame:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(iconFrame)
        icon:SetTexture(definition.icon)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", iconFrame, "RIGHT", 10, 0)
    title:SetText(definition.title)
    title:SetTextColor(definition.border[1], definition.border[2], definition.border[3])

    local inputBackground = CreateFrame("Frame", nil, panel)
    inputBackground:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -65)
    inputBackground:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 10)
    SetBackdrop(inputBackground, { 0.012, 0.016, 0.025, 0.98 },
        { definition.border[1], definition.border[2], definition.border[3], 0.36 })
    inputBackground:EnableMouse(true)

    local scrollName = "ActuallyCacheTips" .. definition.title .. "Scroll"
    local scroll = CreateFrame("ScrollFrame", scrollName, inputBackground, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", inputBackground, "TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", inputBackground, "BOTTOMRIGHT", -28, 8)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetWidth(230)
    edit:SetHeight(20)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetTextColor(0.88, 0.91, 0.96)
    edit:SetJustifyH("LEFT")
    edit:SetJustifyV("TOP")
    edit:SetMaxLetters(8000)
    scroll:SetScrollChild(edit)
    local measure = panel:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    measure:SetWidth(230)
    measure:SetAlpha(0)
    local function ResizeEdit()
        measure:SetText(edit:GetText() or "")
        edit:SetHeight(math.max(20, scroll:GetHeight() or 0, (measure:GetStringHeight() or 0) + 22))
    end
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput then CacheTips:QueueRoleDraft(definition.key, self:GetText() or "") end
        ResizeEdit()
    end)
    scroll:SetScript("OnSizeChanged", ResizeEdit)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEditFocusGained", function()
        inputBackground:SetBackdropBorderColor(
            definition.border[1], definition.border[2], definition.border[3], 0.95)
    end)
    edit:SetScript("OnEditFocusLost", function()
        CacheTips:CommitRole(definition.key)
        inputBackground:SetBackdropBorderColor(
            definition.border[1], definition.border[2], definition.border[3], 0.36)
    end)
    inputBackground:SetScript("OnMouseDown", function()
        if CacheTips:CanEdit() then edit:SetFocus() end
    end)
    edit:SetText(Addon.db.cacheTips[definition.key] or "")
    ResizeEdit()

    return panel, edit, inputBackground
end

function CacheTips:Create()
    if self.root or not Addon.Board or not Addon.Board.sectionPanel then return end
    Addon.db.cacheTips = type(Addon.db.cacheTips) == "table" and Addon.db.cacheTips or {}
    local panel = Addon.Board.sectionPanel
    local root = CreateFrame("Frame", nil, panel)
    root:SetPoint("TOPLEFT", panel, "TOPLEFT", 22, -20)
    root:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -22, 92)
    root:Hide()
    self.root = root

    local title = root:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", root, "TOPLEFT", 2, -2)
    title:SetText("Cache Tips")
    title:SetTextColor(0.78, 0.64, 1.00)

    local subtitle = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -7)
    subtitle:SetText("Shared guild role notes  |  Officers can edit")
    subtitle:SetTextColor(0.57, 0.66, 0.76)

    local utility = CreateFrame("Frame", nil, root)
    utility:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -70)
    utility:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -70)
    utility:SetHeight(122)
    SetBackdrop(utility, { 0.075, 0.045, 0.12, 0.96 }, { 0.58, 0.38, 0.88, 0.92 })

    local utilityTitle = utility:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    utilityTitle:SetPoint("TOPLEFT", utility, "TOPLEFT", 16, -12)
    utilityTitle:SetText("Cache Utility")
    utilityTitle:SetTextColor(0.82, 0.70, 1.00)

    local checkbox = CreateFrame("CheckButton", "ActuallyArrowToShotcallerCheckButton", utility,
        "UICheckButtonTemplate")
    checkbox:SetWidth(26)
    checkbox:SetHeight(26)
    checkbox:SetPoint("TOPLEFT", utility, "TOPLEFT", 15, -43)
    local checkboxLabel = checkbox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    checkboxLabel:SetPoint("LEFT", checkbox, "RIGHT", 4, 1)
    checkboxLabel:SetText("Arrow to Shotcaller")

    local arrowStatus = utility:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arrowStatus:SetPoint("LEFT", checkboxLabel, "RIGHT", 12, 0)
    arrowStatus:SetWidth(155)
    arrowStatus:SetJustifyH("LEFT")
    self.arrowCheckbox = checkbox
    self.arrowStatus = arrowStatus

    checkbox:SetScript("OnClick", function(owner)
        if Addon.CallerArrow then
            Addon.CallerArrow:SetEnabled(owner:GetChecked() == 1 or owner:GetChecked() == true, true)
        end
    end)

    local fapCheckbox = CreateFrame("CheckButton", "ActuallyFapAlerterCheckButton", utility,
        "UICheckButtonTemplate")
    fapCheckbox:SetWidth(26)
    fapCheckbox:SetHeight(26)
    fapCheckbox:SetPoint("TOPLEFT", utility, "TOPLEFT", 15, -75)
    local fapLabel = fapCheckbox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fapLabel:SetPoint("LEFT", fapCheckbox, "RIGHT", 4, 1)
    fapLabel:SetText("FAP Alerter")
    self.fapCheckbox = fapCheckbox

    fapCheckbox:SetScript("OnClick", function(owner)
        if Addon.FapAlert then
            local enabled = owner:GetChecked() == 1 or owner:GetChecked() == true
            Addon.FapAlert:SetEnabled(enabled, enabled)
        end
    end)

    local raidCCPanel = CreateFrame("Frame", nil, utility)
    raidCCPanel:SetPoint("TOPLEFT", utility, "TOPLEFT", 282, -39)
    raidCCPanel:SetPoint("BOTTOMRIGHT", utility, "BOTTOMRIGHT", -10, 10)
    SetBackdrop(
        raidCCPanel,
        { 0.035, 0.055, 0.070, 0.94 },
        { 0.25, 0.68, 0.82, 0.84 })
    self.raidCCPanel = raidCCPanel

    local raidCCCheckbox = CreateFrame("CheckButton", "ActuallyRaidCCCheckButton", raidCCPanel,
        "UICheckButtonTemplate")
    raidCCCheckbox:SetWidth(26)
    raidCCCheckbox:SetHeight(26)
    raidCCCheckbox:SetPoint("TOPLEFT", raidCCPanel, "TOPLEFT", 7, -7)
    local raidCCLabel = raidCCCheckbox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    raidCCLabel:SetPoint("LEFT", raidCCCheckbox, "RIGHT", 4, 1)
    raidCCLabel:SetText(
        "Mass Dispel Helper - Note: |cffff2020changes friendly nameplates while in raid|r")
    self.raidCCCheckbox = raidCCCheckbox
    self.raidCCLabel = raidCCLabel

    raidCCCheckbox:SetScript("OnClick", function(owner)
        if Addon.RaidCC then
            local enabled = owner:GetChecked() == 1 or owner:GetChecked() == true
            Addon.RaidCC:SetEnabled(enabled)
        end
    end)
    raidCCCheckbox:SetScript("OnEnter", function(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText("Mass Dispel Helper", 1, 1, 1)
        GameTooltip:AddLine("While in a raid or battleground, displays raid members as names only. Cyclone and Rejuvenation show green arrows; Shadowfury and Wild Growth show purple arrows.", nil, nil, nil, true)
        if Addon.RaidCC and Addon.RaidCC.GetRuntimeStatus then
            local state, status = Addon.RaidCC:GetRuntimeStatus()
            local r, g, b = 1, 0.82, 0
            if state == "active" then
                r, g, b = 0.25, 1, 0.35
            elseif state == "blocked" then
                r, g, b = 1, 0.25, 0.20
            elseif state == "disabled" then
                r, g, b = 0.72, 0.72, 0.72
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(status, r, g, b, true)
        end
        GameTooltip:AddLine("Previous friendly/enemy visibility settings are restored when the mode stops.", 0.72, 0.78, 0.86, true)
        GameTooltip:Show()
    end)
    raidCCCheckbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local raidCCSettings = CreateFrame("Button", nil, raidCCPanel, "UIPanelButtonTemplate")
    raidCCSettings:SetWidth(90)
    raidCCSettings:SetHeight(22)
    raidCCSettings:SetPoint("TOPLEFT", raidCCLabel, "BOTTOMLEFT", 0, -6)
    raidCCSettings:SetText("Settings")
    raidCCSettings:SetScript("OnClick", function()
        if Addon.RaidCC and Addon.RaidCC.ToggleSettings then
            Addon.RaidCC:ToggleSettings()
        end
    end)
    raidCCSettings:SetScript("OnEnter", function(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText("Mass Dispel Helper Settings", 1, 1, 1)
        GameTooltip:AddLine(
            "Give each tracked effect its own arrow and sound rules, or add custom buffs and debuffs by spell ID.",
            nil, nil, nil, true)
        GameTooltip:Show()
    end)
    raidCCSettings:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    self.raidCCSettingsButton = raidCCSettings

    local arcAlerts = CreateFrame("Frame", nil, root)
    arcAlerts:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -202)
    arcAlerts:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -202)
    arcAlerts:SetHeight(125)
    SetBackdrop(arcAlerts, { 0.030, 0.055, 0.075, 0.97 }, { 0.20, 0.72, 0.96, 0.88 })

    local arcTitle = arcAlerts:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    arcTitle:SetPoint("TOPLEFT", arcAlerts, "TOPLEFT", 16, -12)
    arcTitle:SetText("ARC Alerts")
    arcTitle:SetTextColor(0.32, 0.86, 1.00)

    local arcDescription = arcAlerts:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arcDescription:SetPoint("TOPLEFT", arcTitle, "BOTTOMLEFT", 0, -7)
    arcDescription:SetText("Personal position and size for Actually Raid Cooldown alerts")
    arcDescription:SetTextColor(0.62, 0.70, 0.80)

    local arcMove = CreateFrame("Button", nil, arcAlerts, "UIPanelButtonTemplate")
    arcMove:SetWidth(130)
    arcMove:SetHeight(24)
    arcMove:SetPoint("TOPRIGHT", arcAlerts, "TOPRIGHT", -330, -25)
    arcMove:SetText("Preview / Move")
    arcMove:SetScript("OnClick", function()
        local arc = Addon.Modules and Addon.Modules.RaidCooldowns
        if arc and arc.AlertUI and arc.AlertUI.initialized then
            arc.AlertUI:TogglePositioning()
        end
    end)
    self.arcAlertMoveButton = arcMove

    local arcScaleLabel = arcAlerts:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arcScaleLabel:SetPoint("TOPRIGHT", arcAlerts, "TOPRIGHT", -132, -14)
    arcScaleLabel:SetWidth(150)
    arcScaleLabel:SetJustifyH("CENTER")
    arcScaleLabel:SetText("Size: 100%")
    arcScaleLabel:SetTextColor(0.86, 0.90, 0.96)
    self.arcAlertScaleLabel = arcScaleLabel

    local arcScale = CreateFrame("Slider", "ActuallyARCAlertScaleSlider", arcAlerts,
        "OptionsSliderTemplate")
    arcScale:SetWidth(150)
    arcScale:SetHeight(16)
    arcScale:SetPoint("TOPRIGHT", arcAlerts, "TOPRIGHT", -132, -39)
    arcScale:SetMinMaxValues(0.60, 1.80)
    arcScale:SetValueStep(0.05)
    _G[arcScale:GetName() .. "Low"]:SetText("60%")
    _G[arcScale:GetName() .. "High"]:SetText("180%")
    _G[arcScale:GetName() .. "Text"]:SetText("")
    arcScale:SetScript("OnValueChanged", function(owner)
        if CacheTips.refreshingARCAlertControls then return end
        local arc = Addon.Modules and Addon.Modules.RaidCooldowns
        if arc and arc.AlertUI and arc.AlertUI.initialized then
            arc.AlertUI:SetScale(owner:GetValue())
        end
    end)
    self.arcAlertScaleSlider = arcScale

    local arcReset = CreateFrame("Button", nil, arcAlerts, "UIPanelButtonTemplate")
    arcReset:SetWidth(80)
    arcReset:SetHeight(24)
    arcReset:SetPoint("TOPRIGHT", arcAlerts, "TOPRIGHT", -15, -25)
    arcReset:SetText("Reset")
    arcReset:SetScript("OnClick", function()
        local arc = Addon.Modules and Addon.Modules.RaidCooldowns
        if arc and arc.AlertUI and arc.AlertUI.initialized then arc.AlertUI:Reset() end
    end)
    self.arcAlertResetButton = arcReset

    local arcSound = CreateFrame("CheckButton", "ActuallyARCAlertSoundCheckButton",
        arcAlerts, "UICheckButtonTemplate")
    arcSound:SetWidth(26)
    arcSound:SetHeight(26)
    arcSound:SetPoint("TOPLEFT", arcAlerts, "TOPLEFT", 15, -65)
    local arcSoundLabel = arcSound:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arcSoundLabel:SetPoint("LEFT", arcSound, "RIGHT", 3, 1)
    arcSoundLabel:SetText("Sound")
    arcSound:SetScript("OnClick", function(owner)
        local arc = Addon.Modules and Addon.Modules.RaidCooldowns
        if arc and arc.AlertUI and arc.AlertUI.initialized then
            arc.AlertUI:SetSoundEnabled(owner:GetChecked() == 1 or owner:GetChecked() == true)
        end
    end)
    self.arcAlertSoundCheckbox = arcSound

    local arcSoundDropdown = CreateFrame("Frame", "ActuallyARCAlertSoundDropdown",
        arcAlerts, "UIDropDownMenuTemplate")
    arcSoundDropdown:SetPoint("LEFT", arcSoundLabel, "RIGHT", -8, -1)
    UIDropDownMenu_SetWidth(arcSoundDropdown, 145)
    UIDropDownMenu_Initialize(arcSoundDropdown, function()
        local arc = Addon.Modules and Addon.Modules.RaidCooldowns
        if not arc or not arc.AlertUI then return end
        local selected = arc.AlertUI:GetSound()
        for _, option in ipairs(arc.AlertUI:GetSoundOptions()) do
            local soundKey, soundLabel = option.key, option.label
            local info = UIDropDownMenu_CreateInfo()
            info.text = soundLabel
            info.value = soundKey
            info.checked = selected == soundKey
            info.func = function()
                arc.AlertUI:SetSound(soundKey, true)
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    self.arcAlertSoundDropdown = arcSoundDropdown

    local function CreateEffectCheckbox(name, label, x, effect)
        local checkbox = CreateFrame("CheckButton", name, arcAlerts, "UICheckButtonTemplate")
        checkbox:SetWidth(26)
        checkbox:SetHeight(26)
        checkbox:SetPoint("TOPLEFT", arcAlerts, "TOPLEFT", x, -65)
        local text = checkbox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", checkbox, "RIGHT", 3, 1)
        text:SetText(label)
        checkbox:SetScript("OnClick", function(owner)
            local arc = Addon.Modules and Addon.Modules.RaidCooldowns
            if arc and arc.AlertUI and arc.AlertUI.initialized then
                arc.AlertUI:SetEffect(effect,
                    owner:GetChecked() == 1 or owner:GetChecked() == true)
            end
        end)
        return checkbox
    end

    self.arcAlertBounceCheckbox = CreateEffectCheckbox(
        "ActuallyARCAlertBounceCheckButton", "Bounce", 330, "bounce")
    self.arcAlertGlowCheckbox = CreateEffectCheckbox(
        "ActuallyARCAlertGlowCheckButton", "Glow", 445, "glow")
    self.arcAlertPulseCheckbox = CreateEffectCheckbox(
        "ActuallyARCAlertPulseCheckButton", "Pulse", 545, "pulse")

    local arcOfficerConfig = CreateFrame("Button", nil, arcAlerts)
    arcOfficerConfig:SetWidth(80)
    arcOfficerConfig:SetHeight(23)
    arcOfficerConfig:SetPoint("TOPRIGHT", arcAlerts, "TOPRIGHT", -15, -66)
    SetBackdrop(
        arcOfficerConfig,
        { 0.035, 0.16, 0.27, 1.00 },
        { 0.22, 0.72, 1.00, 0.96 })
    local arcOfficerConfigText = arcOfficerConfig:CreateFontString(
        nil, "OVERLAY", "GameFontHighlightSmall")
    arcOfficerConfigText:SetPoint("CENTER", arcOfficerConfig, "CENTER", 0, 0)
    arcOfficerConfigText:SetText("Config")
    arcOfficerConfigText:SetTextColor(0.72, 0.91, 1.00)
    local arcOfficerHighlight = arcOfficerConfig:CreateTexture(nil, "HIGHLIGHT")
    arcOfficerHighlight:SetAllPoints(arcOfficerConfig)
    arcOfficerHighlight:SetTexture("Interface\\Buttons\\WHITE8X8")
    arcOfficerHighlight:SetVertexColor(0.20, 0.64, 1.00, 0.18)

    local arcOfficerLabel = arcAlerts:CreateFontString(
        nil, "OVERLAY", "GameFontHighlightSmall")
    arcOfficerLabel:SetPoint("RIGHT", arcOfficerConfig, "LEFT", -8, 0)
    arcOfficerLabel:SetText("Officer:")
    arcOfficerLabel:SetTextColor(0.52, 0.78, 0.96)

    arcOfficerConfig:SetScript("OnClick", function()
        local arc = Addon.Modules and Addon.Modules.RaidCooldowns
        if not arc or not arc.HasConfigurationAuthority
            or not arc:HasConfigurationAuthority() then
            return
        end
        if arc.OfficerConfig and arc.OfficerConfig.Toggle then
            arc.OfficerConfig:Toggle("plans")
        elseif arc.CommanderConfig and arc.CommanderConfig.Toggle then
            arc.CommanderConfig:Toggle()
        elseif arc.Print then
            arc:Print("officer configuration is unavailable")
        end
    end)
    arcOfficerConfig:Hide()
    arcOfficerLabel:Hide()
    self.arcOfficerConfigButton = arcOfficerConfig
    self.arcOfficerConfigLabel = arcOfficerLabel

    local roleHeading = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    roleHeading:SetPoint("TOPLEFT", root, "TOPLEFT", 2, -344)
    roleHeading:SetText("Role Tips")
    roleHeading:SetTextColor(0.82, 0.86, 0.94)

    self.roleEdits = {}
    self.roleBackgrounds = {}
    self.pendingDrafts = {}
    local anchors = {
        { point = "TOPLEFT", bottom = "BOTTOMLEFT", x = 0 },
        { point = "TOP", bottom = "BOTTOM", x = 0 },
        { point = "TOPRIGHT", bottom = "BOTTOMRIGHT", x = 0 },
    }
    for index, definition in ipairs(ROLE_DEFINITIONS) do
        local rolePanel, edit, inputBackground = CreateRolePanel(root, definition, anchors[index])
        self.roleEdits[definition.key] = edit
        self.roleBackgrounds[definition.key] = inputBackground
        self[definition.key .. "Panel"] = rolePanel
    end

    root:SetScript("OnUpdate", function()
        if CacheTips.nextDraftCommitAt
            and (GetTime and GetTime() or 0) >= CacheTips.nextDraftCommitAt then
            CacheTips:CommitPending()
        end
    end)

    self:Refresh()
    self:RefreshArrowToggle()
    self:RefreshFapToggle()
    self:RefreshRaidCCToggle()
    self:RefreshARCAlertControls()
end

function CacheTips:RefreshPermissions()
    local canEdit = self:CanEdit()
    for _, definition in ipairs(ROLE_DEFINITIONS) do
        local edit = self.roleEdits and self.roleEdits[definition.key]
        if edit then
            if canEdit then
                edit:Enable()
                edit:SetTextColor(0.88, 0.91, 0.96)
            else
                if edit:HasFocus() then edit:ClearFocus() end
                edit:Disable()
                edit:SetTextColor(0.78, 0.82, 0.90)
            end
        end
    end
end

function CacheTips:Refresh()
    if not self.root then return end
    for _, definition in ipairs(ROLE_DEFINITIONS) do
        local edit = self.roleEdits and self.roleEdits[definition.key]
        if edit and not edit:HasFocus() then
            edit:SetText(Addon.db.cacheTips[definition.key] or "")
        end
    end
    self:RefreshPermissions()
end

function CacheTips:RefreshARCAlertControls()
    if not self.arcAlertScaleSlider then return end
    local arc = Addon.Modules and Addon.Modules.RaidCooldowns
    local ready = arc and arc.AlertUI and arc.AlertUI.initialized and arc.db and arc.db.profile
    local hasOfficerAccess = arc and arc.HasConfigurationAuthority
        and arc:HasConfigurationAuthority() == true
    if self.arcOfficerConfigButton and self.arcOfficerConfigLabel then
        if hasOfficerAccess then
            self.arcOfficerConfigButton:Show()
            self.arcOfficerConfigLabel:Show()
        else
            self.arcOfficerConfigButton:Hide()
            self.arcOfficerConfigLabel:Hide()
        end
    end
    self.refreshingARCAlertControls = true
    local scale = ready and arc.AlertUI:GetScale() or 1
    self.arcAlertScaleSlider:SetValue(scale)
    self.arcAlertScaleLabel:SetText("Size: " .. tostring(math.floor(scale * 100 + 0.5)) .. "%")
    self.arcAlertMoveButton:SetText(ready and arc.AlertUI:IsPositioning()
        and "Done Moving" or "Preview / Move")
    if self.arcAlertSoundCheckbox then
        self.arcAlertSoundCheckbox:SetChecked(ready and arc.AlertUI:IsSoundEnabled() or false)
    end
    if self.arcAlertSoundDropdown and UIDropDownMenu_SetText then
        UIDropDownMenu_SetText(self.arcAlertSoundDropdown,
            ready and arc.AlertUI:GetSoundLabel() or "Raid Warning")
    end
    if self.arcAlertBounceCheckbox then
        self.arcAlertBounceCheckbox:SetChecked(
            ready and arc.AlertUI:GetEffect("bounce") or false)
    end
    if self.arcAlertGlowCheckbox then
        self.arcAlertGlowCheckbox:SetChecked(
            ready and arc.AlertUI:GetEffect("glow") or false)
    end
    if self.arcAlertPulseCheckbox then
        self.arcAlertPulseCheckbox:SetChecked(
            ready and arc.AlertUI:GetEffect("pulse") or false)
    end
    self.refreshingARCAlertControls = false
    if ready then
        self.arcAlertScaleSlider:Enable()
        self.arcAlertMoveButton:Enable()
        self.arcAlertResetButton:Enable()
        if self.arcAlertSoundCheckbox then self.arcAlertSoundCheckbox:Enable() end
        if self.arcAlertSoundDropdown and UIDropDownMenu_EnableDropDown then
            UIDropDownMenu_EnableDropDown(self.arcAlertSoundDropdown)
        end
        if self.arcAlertBounceCheckbox then self.arcAlertBounceCheckbox:Enable() end
        if self.arcAlertGlowCheckbox then self.arcAlertGlowCheckbox:Enable() end
        if self.arcAlertPulseCheckbox then self.arcAlertPulseCheckbox:Enable() end
    else
        self.arcAlertScaleSlider:Disable()
        self.arcAlertMoveButton:Disable()
        self.arcAlertResetButton:Disable()
        if self.arcAlertSoundCheckbox then self.arcAlertSoundCheckbox:Disable() end
        if self.arcAlertSoundDropdown and UIDropDownMenu_DisableDropDown then
            UIDropDownMenu_DisableDropDown(self.arcAlertSoundDropdown)
        end
        if self.arcAlertBounceCheckbox then self.arcAlertBounceCheckbox:Disable() end
        if self.arcAlertGlowCheckbox then self.arcAlertGlowCheckbox:Disable() end
        if self.arcAlertPulseCheckbox then self.arcAlertPulseCheckbox:Disable() end
    end
end

function CacheTips:RefreshFapToggle()
    if not self.fapCheckbox then return end
    self.fapCheckbox:SetChecked(Addon.FapAlert and Addon.FapAlert:IsEnabled() or false)
end

function CacheTips:RefreshRaidCCToggle()
    if not self.raidCCCheckbox then return end
    local available = Addon.RaidCC and Addon.RaidCC.IsEnabled
    self.raidCCCheckbox:SetChecked(available and Addon.RaidCC:IsEnabled() or false)
    if self.raidCCSettingsButton then
        if available and Addon.RaidCC.ToggleSettings then
            self.raidCCSettingsButton:Enable()
        else
            self.raidCCSettingsButton:Disable()
        end
    end
    if not self.raidCCLabel then return end
    local state = Addon.RaidCC and Addon.RaidCC.GetRuntimeStatus
        and Addon.RaidCC:GetRuntimeStatus() or "disabled"
    if state == "active" then
        self.raidCCLabel:SetTextColor(0.25, 1, 0.35)
    elseif state == "blocked" then
        self.raidCCLabel:SetTextColor(1, 0.25, 0.20)
    elseif state == "waiting" then
        self.raidCCLabel:SetTextColor(1, 0.82, 0)
    else
        self.raidCCLabel:SetTextColor(1, 1, 1)
    end
end

function CacheTips:RefreshArrowToggle()
    if not self.arrowCheckbox then return end
    local arrow = Addon.CallerArrow
    local enabled = arrow and arrow:IsEnabled()
    self.arrowCheckbox:SetChecked(enabled == true)
    local target = arrow and arrow.targetName
    if not target or target == "" then
        self.arrowStatus:SetText("No shotcaller assigned")
        self.arrowStatus:SetTextColor(0.62, 0.66, 0.72)
    elseif enabled and arrow:IsTargetInRaid() then
        self.arrowStatus:SetText("Following " .. target)
        self.arrowStatus:SetTextColor(0.38, 1.00, 0.58)
    elseif enabled then
        self.arrowStatus:SetText("Waiting for " .. target)
        self.arrowStatus:SetTextColor(1.00, 0.48, 0.38)
    else
        self.arrowStatus:SetText("Shotcaller: " .. target)
        self.arrowStatus:SetTextColor(0.62, 0.76, 0.92)
    end
end

function CacheTips:SetVisible(visible)
    if not self.root then return end
    if visible then
        local bottom = Addon.Official and Addon.Official:IsOfficer() and 168 or 92
        self.root:ClearAllPoints()
        self.root:SetPoint("TOPLEFT", Addon.Board.sectionPanel, "TOPLEFT", 22, -20)
        self.root:SetPoint("BOTTOMRIGHT", Addon.Board.sectionPanel, "BOTTOMRIGHT", -22, bottom)
        self:RefreshArrowToggle()
        self:RefreshFapToggle()
        self:RefreshRaidCCToggle()
        self:RefreshARCAlertControls()
        self:Refresh()
        self.root:Show()
    else
        self:CommitPending()
        for _, edit in pairs(self.roleEdits or {}) do edit:ClearFocus() end
        local arc = Addon.Modules and Addon.Modules.RaidCooldowns
        if arc and arc.AlertUI and arc.AlertUI.StopPositioning then
            arc.AlertUI:StopPositioning()
        end
        self.root:Hide()
    end
end
