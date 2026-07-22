Actually = Actually or {}
local Addon = Actually

local CacheTips = {}
Addon.CacheTips = CacheTips
local SetBackdrop = Addon.Util.SetBackdrop

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
    panel:SetPoint(anchor.point, root, anchor.point, anchor.x or 0, -246)
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
        if userInput then Addon.db.cacheTips[definition.key] = self:GetText() or "" end
        ResizeEdit()
    end)
    scroll:SetScript("OnSizeChanged", ResizeEdit)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEditFocusGained", function()
        inputBackground:SetBackdropBorderColor(
            definition.border[1], definition.border[2], definition.border[3], 0.95)
    end)
    edit:SetScript("OnEditFocusLost", function()
        inputBackground:SetBackdropBorderColor(
            definition.border[1], definition.border[2], definition.border[3], 0.36)
    end)
    inputBackground:SetScript("OnMouseDown", function() edit:SetFocus() end)
    edit:SetText(Addon.db.cacheTips[definition.key] or "")
    ResizeEdit()

    return panel, edit
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
    subtitle:SetText("Personal raid utilities and role notes")
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
    checkboxLabel:SetText("Arrow to Raid Shotcaller")

    local arrowStatus = utility:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arrowStatus:SetPoint("RIGHT", utility, "RIGHT", -18, -15)
    arrowStatus:SetWidth(430)
    arrowStatus:SetJustifyH("RIGHT")
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

    local roleHeading = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    roleHeading:SetPoint("TOPLEFT", root, "TOPLEFT", 2, -214)
    roleHeading:SetText("Role Tips")
    roleHeading:SetTextColor(0.82, 0.86, 0.94)

    self.roleEdits = {}
    local anchors = {
        { point = "TOPLEFT", bottom = "BOTTOMLEFT", x = 0 },
        { point = "TOP", bottom = "BOTTOM", x = 0 },
        { point = "TOPRIGHT", bottom = "BOTTOMRIGHT", x = 0 },
    }
    for index, definition in ipairs(ROLE_DEFINITIONS) do
        local rolePanel, edit = CreateRolePanel(root, definition, anchors[index])
        self.roleEdits[definition.key] = edit
        self[definition.key .. "Panel"] = rolePanel
    end

    self:RefreshArrowToggle()
    self:RefreshFapToggle()
end

function CacheTips:RefreshFapToggle()
    if not self.fapCheckbox then return end
    self.fapCheckbox:SetChecked(Addon.FapAlert and Addon.FapAlert:IsEnabled() or false)
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
        self.arrowStatus:SetText("Waiting for " .. target .. " to join your raid")
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
        self.root:Show()
    else
        for _, edit in pairs(self.roleEdits or {}) do edit:ClearFocus() end
        self.root:Hide()
    end
end
