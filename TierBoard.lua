Actually = Actually or {}
local Addon = Actually

local Board = {}
Addon.Board = Board
local SetBackdrop = Addon.Util.SetBackdrop

local TIER_COLORS = {
    S = { 0.85, 0.25, 0.25 },
    A = { 1.00, 0.55, 0.20 },
    B = { 0.95, 0.80, 0.25 },
    C = { 0.35, 0.75, 0.35 },
    D = { 0.35, 0.55, 0.85 },
    U = { 0.42, 0.42, 0.46 },
}

local TIER_NAMES = {
    S = "S",
    A = "A",
    B = "B",
    C = "C",
    D = "D",
}

local CARD_WIDTH = 62
local CARD_HEIGHT = 66
local CARD_GAP = 5
local CONTENT_WIDTH = 842
local ROW_WIDTH = 928
local RANKED_VIEW_HEIGHT = 382
local POOL_ROW_HEIGHT = 124
local RANKED_TIERS = { "S", "A", "B", "C", "D" }
local NAV_RAIL_WIDTH = 952
local NAV_RAIL_PADDING = 8
local NAV_TAB_GAP = 8
local NAV_TAB_WIDTH = (NAV_RAIL_WIDTH - NAV_RAIL_PADDING * 2 - NAV_TAB_GAP * 3) / 4
local NAV_TAB_HEIGHT = 56
local NAV_TAB_Y = 6
local NAV_SECOND_ROW_HEIGHT = NAV_TAB_HEIGHT + 12
local NAV_EXPANDED_HEIGHT = NAV_SECOND_ROW_HEIGHT + 8
local BOARD_BASE_HEIGHT = 750
local NAV_RAIL_BASE_HEIGHT = 68
local TIER_FOOTER_BASE_Y = 80
local NAV_SECTIONS = {
    {
        key = "tier",
        label = "TIER LIST",
        title = "Tier List",
        icon = "Interface\\AddOns\\actually\\Textures\\TabIconTier",
        color = { 0.66, 0.16, 0.10 },
        border = { 1.00, 0.52, 0.18 },
    },
    {
        key = "gear",
        label = "GEAR",
        title = "Gear",
        icon = "Interface\\AddOns\\actually\\Textures\\TabIconGear",
        description = "Equipment sets, upgrade paths and gearing notes will live here.",
        color = { 0.10, 0.32, 0.62 },
        border = { 0.28, 0.78, 1.00 },
    },
    {
        key = "leveling",
        label = "WILDCARD\nPROGRESSION",
        title = "Wildcard Progression",
        icon = "Interface\\AddOns\\actually\\Textures\\TabIconWildcard",
        description = "Advice for progressing your build on Wildcard",
        color = { 0.16, 0.50, 0.18 },
        border = { 0.58, 1.00, 0.30 },
    },
    {
        key = "cache",
        label = "CACHE TIPS",
        title = "Cache Tips",
        icon = "Interface\\AddOns\\actually\\Textures\\TabIconCache",
        description = "Short cache strategies, reminders and discoveries will live here.",
        color = { 0.34, 0.16, 0.56 },
        border = { 0.48, 0.80, 1.00 },
    },
}
local SPELL_CATEGORIES = {
    "CC", "Defensive", "Immunity", "Interrupt", "Mobility", "Other",
}
local CATEGORY_INDEX = {}
for index, category in ipairs(SPELL_CATEGORIES) do
    CATEGORY_INDEX[category] = index
end
local FILTER_CATEGORIES = { "All" }
for _, category in ipairs(SPELL_CATEGORIES) do
    table.insert(FILTER_CATEGORIES, category)
end

function Board:GetSpellCategories()
    return SPELL_CATEGORIES
end

function Board:RefreshSectionTabs()
    if not self.sectionTabs then
        return
    end

    for _, section in ipairs(NAV_SECTIONS) do
        local tab = self.sectionTabs[section.key]
        local active = self.activeSection == section.key
        local red = math.min(1, section.color[1] + (active and 0.13 or 0))
        local green = math.min(1, section.color[2] + (active and 0.13 or 0))
        local blue = math.min(1, section.color[3] + (active and 0.13 or 0))
        tab:ClearAllPoints()
        tab:SetWidth(NAV_TAB_WIDTH)
        tab:SetHeight(NAV_TAB_HEIGHT)
        tab:SetPoint("BOTTOMLEFT", self.sectionRail, "BOTTOMLEFT", tab.offsetX, self.primaryNavY or NAV_TAB_Y)
        tab:SetBackdropColor(red, green, blue, 0.98)
        tab:SetBackdropBorderColor(
            section.border[1],
            section.border[2],
            section.border[3],
            active and 1 or 0.58
        )
        tab.icon:SetAlpha(active and 1 or 0.80)
        tab.label:SetTextColor(1, 1, 1, active and 1 or 0.76)
        tab.activeGlow:SetAlpha(active and 0.08 or 0)
        for _, glowEdge in ipairs(tab.glowEdges) do
            glowEdge:SetVertexColor(section.border[1], section.border[2], section.border[3], 1)
            glowEdge:SetAlpha(active and 0.95 or 0)
        end
    end
end

function Board:RefreshSectionNavigationPermissions()
    if not self.frame or not self.sectionRail or not self.assistTrackerTab then
        return
    end

    local isOfficer = Addon.Official and Addon.Official:IsOfficer()
    if not isOfficer and self.activeSection == "assist" then
        self:SetSection("tier")
        return
    end
    self.primaryNavY = isOfficer and (NAV_TAB_Y + NAV_SECOND_ROW_HEIGHT) or NAV_TAB_Y
    self.frame:SetHeight(BOARD_BASE_HEIGHT + (isOfficer and NAV_EXPANDED_HEIGHT or 0))
    self.sectionRail:SetHeight(NAV_RAIL_BASE_HEIGHT + (isOfficer and NAV_SECOND_ROW_HEIGHT or 0))

    if self.tierFooter then
        self.tierFooter:ClearAllPoints()
        self.tierFooter:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 12,
            TIER_FOOTER_BASE_Y + (isOfficer and NAV_EXPANDED_HEIGHT or 0))
        self.tierFooter:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -12,
            TIER_FOOTER_BASE_Y + (isOfficer and NAV_EXPANDED_HEIGHT or 0))
    end

    local contentBottom = TIER_FOOTER_BASE_Y + (isOfficer and NAV_EXPANDED_HEIGHT or 0)
    if Addon.Gear and Addon.Gear.frame then
        Addon.Gear.frame:ClearAllPoints()
        Addon.Gear.frame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 5, -5)
        Addon.Gear.frame:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -5, contentBottom)
    end
    if Addon.AssistLogUI and Addon.AssistLogUI.frame then
        Addon.AssistLogUI:ResizeToParent(contentBottom)
    end

    if isOfficer then
        self.assistTrackerTab:Show()
    else
        self.assistTrackerTab:Hide()
    end
    self:RefreshSectionTabs()
    self:RefreshAssistTrackerTab()
end

function Board:RefreshAssistTrackerTab()
    local tab = self.assistTrackerTab
    if not tab then return end
    local active = self.activeSection == "assist"
    tab:SetBackdropColor(active and 0.13 or 0.08, active and 0.40 or 0.30, active and 0.50 or 0.38, 0.98)
    tab:SetBackdropBorderColor(0.24, 0.86, 1.00, active and 1 or 0.72)
    if tab.activeGlow then tab.activeGlow:SetAlpha(active and 0.95 or 0) end
end

function Board:SetSection(sectionKey)
    local selected
    if sectionKey == "assist" and Addon.Official and Addon.Official:IsOfficer() then
        selected = { key = "assist", title = "Assist Tracker" }
    end
    for _, section in ipairs(NAV_SECTIONS) do
        if section.key == sectionKey then
            selected = section
            break
        end
    end
    if not selected then
        return
    end

    self.activeSection = selected.key
    local showTier = selected.key == "tier"
    for _, widget in ipairs(self.tierSectionWidgets or {}) do
        if showTier then widget:Show() else widget:Hide() end
    end
    -- Some 3.3.5 UI skins detach InputBox/dropdown artwork from the filter
    -- bar's inherited visibility. Toggle the controls themselves as well.
    for _, widget in ipairs(self.filterControls or {}) do
        widget:SetAlpha(showTier and 1 or 0)
        if showTier then widget:Show() else widget:Hide() end
    end
    if self.filterBar then
        self.filterBar:SetAlpha(showTier and 1 or 0)
        -- Older UI skins can reparent InputBoxTemplate border artwork so it
        -- ignores both Hide() and parent alpha. Moving the complete filter
        -- group off-screen is the only reliable way to suppress that orphaned
        -- border on Gear and the other non-tier sections.
        self.filterBar:ClearAllPoints()
        if showTier then
            self.filterBar:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 80, -77)
            self.filterBar:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -16, -77)
        else
            self.filterBar:SetPoint("TOPLEFT", self.frame, "TOPLEFT", -4000, 4000)
        end
    end
    if showTier then
        self:RefreshListControls()
    end
    if not showTier then
        if self.filterSearchBox then self.filterSearchBox:ClearFocus() end
        if self.spellEditor then self.spellEditor:Hide() end
        if Addon.BatchCapture and Addon.BatchCapture.frame then Addon.BatchCapture.frame:Hide() end
    end
    if Addon.Gear then
        Addon.Gear:SetVisible(selected.key == "gear")
    end
    if Addon.AssistLogUI then
        Addon.AssistLogUI:SetVisible(selected.key == "assist")
    end
    if Addon.CacheTips then
        Addon.CacheTips:SetVisible(selected.key == "cache")
    end
    if selected.key == "tier" then
        self.sectionPanel:Hide()
    elseif selected.key == "gear" or selected.key == "assist" then
        self.sectionPanel:Hide()
    else
        local showPlaceholder = selected.key ~= "cache"
        if showPlaceholder then
            self.sectionPanel.icon:SetTexture(selected.icon)
            self.sectionPanel.title:SetText(selected.title)
            self.sectionPanel.description:SetText(selected.description)
            self.sectionPanel.icon:Show()
            self.sectionPanel.title:Show()
            self.sectionPanel.description:Show()
            if self.sectionPanel.hint then self.sectionPanel.hint:Show() end
        else
            self.sectionPanel.icon:Hide()
            self.sectionPanel.title:Hide()
            self.sectionPanel.description:Hide()
            if self.sectionPanel.hint then self.sectionPanel.hint:Hide() end
        end
        self.sectionPanel:SetBackdropBorderColor(
            selected.border[1], selected.border[2], selected.border[3], 1
        )
        self.sectionPanel:Show()
    end
    self:RefreshSectionTabs()
    self:RefreshAssistTrackerTab()
end

function Board:CreateSectionNavigation(closeButton)
    local frame = self.frame
    local panel = CreateFrame("Frame", nil, frame)
    panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -5)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 5)
    panel:SetFrameLevel(frame:GetFrameLevel() + 20)
    -- Leave the visual-only panel mouse-transparent so dragging reaches the
    -- board frame and behaves identically on every navigation section.
    panel:EnableMouse(false)
    SetBackdrop(panel, { 0.025, 0.030, 0.045, 0.995 }, { 0.25, 0.72, 1.00, 1 })

    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(128)
    icon:SetHeight(128)
    icon:SetPoint("CENTER", panel, "CENTER", 0, 78)
    panel.icon = icon

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOP", icon, "BOTTOM", 0, -20)
    panel.title = title

    local description = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    description:SetPoint("TOP", title, "BOTTOM", 0, -16)
    description:SetWidth(540)
    description:SetJustifyH("CENTER")
    description:SetJustifyV("TOP")
    panel.description = description

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOP", description, "BOTTOM", 0, -20)
    hint:SetText("Section ready for content")
    hint:SetTextColor(0.52, 0.62, 0.72)
    panel.hint = hint

    self.sectionPanel = panel

    local rail = CreateFrame("Frame", nil, frame)
    rail:SetWidth(NAV_RAIL_WIDTH)
    rail:SetHeight(NAV_RAIL_BASE_HEIGHT)
    rail:SetPoint("BOTTOM", frame, "BOTTOM", 0, 8)
    rail:SetFrameLevel(frame:GetFrameLevel() + 24)
    rail:EnableMouse(true)
    rail:RegisterForDrag("LeftButton")
    rail:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    rail:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
    end)
    SetBackdrop(rail, { 0.025, 0.030, 0.045, 0.995 }, { 0.20, 0.55, 0.75, 1 })

    local railInset = rail:CreateTexture(nil, "BACKGROUND")
    railInset:SetPoint("TOPLEFT", rail, "TOPLEFT", 8, -5)
    railInset:SetPoint("TOPRIGHT", rail, "TOPRIGHT", -8, -5)
    railInset:SetHeight(3)
    railInset:SetTexture("Interface\\Buttons\\WHITE8X8")
    railInset:SetVertexColor(0.20, 0.55, 0.75, 0.32)
    self.sectionRail = rail

    self.sectionTabs = {}
    for index, section in ipairs(NAV_SECTIONS) do
        local sectionInfo = section
        local tab = CreateFrame("Button", nil, rail)
        tab:SetWidth(NAV_TAB_WIDTH)
        tab:SetHeight(NAV_TAB_HEIGHT)
        tab:SetFrameLevel(frame:GetFrameLevel() + 30)
        tab.offsetX = NAV_RAIL_PADDING + (index - 1) * (NAV_TAB_WIDTH + NAV_TAB_GAP)
        SetBackdrop(tab, { sectionInfo.color[1], sectionInfo.color[2], sectionInfo.color[3], 0.98 }, sectionInfo.border)

        local spine = tab:CreateTexture(nil, "BACKGROUND")
        spine:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 5, 4)
        spine:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -5, 4)
        spine:SetHeight(5)
        spine:SetTexture("Interface\\Buttons\\WHITE8X8")
        spine:SetVertexColor(sectionInfo.color[1] * 0.45, sectionInfo.color[2] * 0.45, sectionInfo.color[3] * 0.45, 1)

        local activeGlow = tab:CreateTexture(nil, "BACKGROUND")
        activeGlow:SetAllPoints(tab)
        activeGlow:SetTexture("Interface\\Buttons\\WHITE8X8")
        activeGlow:SetVertexColor(sectionInfo.border[1], sectionInfo.border[2], sectionInfo.border[3], 1)
        tab.activeGlow = activeGlow

        local glowTop = tab:CreateTexture(nil, "OVERLAY")
        glowTop:SetPoint("BOTTOMLEFT", tab, "TOPLEFT", -3, -1)
        glowTop:SetPoint("BOTTOMRIGHT", tab, "TOPRIGHT", 3, -1)
        glowTop:SetHeight(4)

        local glowBottom = tab:CreateTexture(nil, "OVERLAY")
        glowBottom:SetPoint("TOPLEFT", tab, "BOTTOMLEFT", -3, 1)
        glowBottom:SetPoint("TOPRIGHT", tab, "BOTTOMRIGHT", 3, 1)
        glowBottom:SetHeight(4)

        local glowLeft = tab:CreateTexture(nil, "OVERLAY")
        glowLeft:SetPoint("TOPRIGHT", tab, "TOPLEFT", 1, 3)
        glowLeft:SetPoint("BOTTOMRIGHT", tab, "BOTTOMLEFT", 1, -3)
        glowLeft:SetWidth(4)

        local glowRight = tab:CreateTexture(nil, "OVERLAY")
        glowRight:SetPoint("TOPLEFT", tab, "TOPRIGHT", -1, 3)
        glowRight:SetPoint("BOTTOMLEFT", tab, "BOTTOMRIGHT", -1, -3)
        glowRight:SetWidth(4)

        tab.glowEdges = { glowTop, glowBottom, glowLeft, glowRight }
        for _, glowEdge in ipairs(tab.glowEdges) do
            glowEdge:SetTexture("Interface\\Buttons\\WHITE8X8")
            glowEdge:SetBlendMode("ADD")
            glowEdge:SetAlpha(0)
        end

        local tabIcon = tab:CreateTexture(nil, "ARTWORK")
        tabIcon:SetWidth(42)
        tabIcon:SetHeight(42)
        tabIcon:SetPoint("LEFT", tab, "LEFT", 18, 1)
        tabIcon:SetTexture(sectionInfo.icon)
        tab.icon = tabIcon

        local label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", tabIcon, "RIGHT", 12, 0)
        label:SetWidth(140)
        label:SetJustifyH("LEFT")
        label:SetText(sectionInfo.label)
        tab.label = label

        tab:SetScript("OnClick", function()
            Board:SetSection(sectionInfo.key)
        end)
        tab:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(1, 1, 1, 1)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(sectionInfo.title, sectionInfo.border[1], sectionInfo.border[2], sectionInfo.border[3])
            GameTooltip:Show()
        end)
        tab:SetScript("OnLeave", function()
            GameTooltip:Hide()
            Board:RefreshSectionTabs()
        end)
        self.sectionTabs[sectionInfo.key] = tab
    end

    local assistTab = CreateFrame("Button", nil, rail)
    assistTab:SetWidth(NAV_TAB_WIDTH)
    assistTab:SetHeight(NAV_TAB_HEIGHT)
    assistTab:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", NAV_RAIL_PADDING, NAV_TAB_Y)
    assistTab:SetFrameLevel(frame:GetFrameLevel() + 30)
    SetBackdrop(assistTab, { 0.08, 0.30, 0.38, 0.98 }, { 0.24, 0.86, 1.00, 1 })

    local assistSpine = assistTab:CreateTexture(nil, "BACKGROUND")
    assistSpine:SetPoint("BOTTOMLEFT", assistTab, "BOTTOMLEFT", 5, 4)
    assistSpine:SetPoint("BOTTOMRIGHT", assistTab, "BOTTOMRIGHT", -5, 4)
    assistSpine:SetHeight(5)
    assistSpine:SetTexture("Interface\\Buttons\\WHITE8X8")
    assistSpine:SetVertexColor(0.03, 0.18, 0.25, 1)

    local assistGlowTop = assistTab:CreateTexture(nil, "OVERLAY")
    assistGlowTop:SetPoint("BOTTOMLEFT", assistTab, "TOPLEFT", -3, -1)
    assistGlowTop:SetPoint("BOTTOMRIGHT", assistTab, "TOPRIGHT", 3, -1)
    assistGlowTop:SetHeight(4)
    local assistGlowBottom = assistTab:CreateTexture(nil, "OVERLAY")
    assistGlowBottom:SetPoint("TOPLEFT", assistTab, "BOTTOMLEFT", -3, 1)
    assistGlowBottom:SetPoint("TOPRIGHT", assistTab, "BOTTOMRIGHT", 3, 1)
    assistGlowBottom:SetHeight(4)
    local assistGlowLeft = assistTab:CreateTexture(nil, "OVERLAY")
    assistGlowLeft:SetPoint("TOPRIGHT", assistTab, "TOPLEFT", 1, 3)
    assistGlowLeft:SetPoint("BOTTOMRIGHT", assistTab, "BOTTOMLEFT", 1, -3)
    assistGlowLeft:SetWidth(4)
    local assistGlowRight = assistTab:CreateTexture(nil, "OVERLAY")
    assistGlowRight:SetPoint("TOPLEFT", assistTab, "TOPRIGHT", -1, 3)
    assistGlowRight:SetPoint("BOTTOMLEFT", assistTab, "BOTTOMRIGHT", -1, -3)
    assistGlowRight:SetWidth(4)
    local assistGlows = { assistGlowTop, assistGlowBottom, assistGlowLeft, assistGlowRight }
    for _, glow in ipairs(assistGlows) do
        glow:SetTexture("Interface\\Buttons\\WHITE8X8")
        glow:SetBlendMode("ADD")
        glow:SetVertexColor(0.24, 0.86, 1.00, 1)
        glow:SetAlpha(0)
    end
    assistTab.activeGlow = {
        SetAlpha = function(_, alpha)
            for _, glow in ipairs(assistGlows) do glow:SetAlpha(alpha) end
        end,
    }

    local assistIcon = assistTab:CreateTexture(nil, "ARTWORK")
    assistIcon:SetWidth(44)
    assistIcon:SetHeight(44)
    assistIcon:SetPoint("LEFT", assistTab, "LEFT", 17, 1)
    assistIcon:SetTexture("Interface\\AddOns\\actually\\Textures\\TabIconAssist")

    local assistLabel = assistTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    assistLabel:SetPoint("LEFT", assistIcon, "RIGHT", 11, 0)
    assistLabel:SetWidth(145)
    assistLabel:SetJustifyH("LEFT")
    assistLabel:SetText("ASSIST TRACKER")
    assistLabel:SetTextColor(0.80, 0.96, 1.00, 1)

    assistTab:SetScript("OnClick", function()
        if Addon.Official and Addon.Official:IsOfficer() and Addon.AssistLogUI then
            Board:SetSection("assist")
        end
    end)
    assistTab:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1, 1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:SetText("Assist Tracker", 0.24, 0.86, 1.00)
        GameTooltip:Show()
    end)
    assistTab:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        Board:RefreshAssistTrackerTab()
    end)
    self.assistTrackerTab = assistTab

    closeButton:SetFrameLevel(frame:GetFrameLevel() + 32)
    self.activeSection = "tier"
    panel:Hide()
    self:RefreshSectionNavigationPermissions()
end

local function NormalizeCategory(category)
    if category == "Control" or category == "Stun" then
        return "CC"
    elseif category == "Support" or category == "Dispel" or category == "Threat" then
        return "Other"
    end

    for _, validCategory in ipairs(SPELL_CATEGORIES) do
        if category == validCategory then
            return category
        end
    end

    return "Other"
end

local function CreateTierLabel(row, tier, text, fontObject)
    local color = TIER_COLORS[tier]
    local label = CreateFrame("Frame", nil, row)
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -4)
    label:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 4)
    label:SetWidth(54)
    SetBackdrop(label, { color[1], color[2], color[3], 0.95 }, { color[1], color[2], color[3], 1 })

    local labelText = label:CreateFontString(nil, "OVERLAY", fontObject)
    labelText:SetPoint("CENTER")
    labelText:SetText(text)
    return label
end

local function SetDropdownSelection(dropdown, value)
    UIDropDownMenu_SetSelectedValue(dropdown, value)
    UIDropDownMenu_SetText(dropdown, value)
end

local function InitializeSelectionDropdown(dropdown, options, getSelectedIndex, onSelected)
    UIDropDownMenu_Initialize(dropdown, function(_, level)
        for index, option in ipairs(options) do
            local selectedIndex = index
            local selectedOption = option
            local info = UIDropDownMenu_CreateInfo()
            info.text = selectedOption
            info.value = selectedOption
            info.checked = getSelectedIndex() == selectedIndex
            info.func = function()
                SetDropdownSelection(dropdown, selectedOption)
                CloseDropDownMenus()
                onSelected(selectedIndex, selectedOption)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
end

local function GetCursorUIPosition()
    local scale = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    return x / scale, y / scale
end

local function CursorInside(frame, x, y)
    local left = frame:GetLeft()
    local right = frame:GetRight()
    local bottom = frame:GetBottom()
    local top = frame:GetTop()
    return left and right and bottom and top and x >= left and x <= right and y >= bottom and y <= top
end

local function IsFrameInside(frame, ancestor)
    while frame do
        if frame == ancestor then
            return true
        end
        frame = frame:GetParent()
    end
    return false
end

local function UpdateScrollRange(area, contentHeight)
    local maximum = math.max(0, contentHeight - area.viewport:GetHeight())
    area.canvas:SetHeight(math.max(contentHeight, area.viewport:GetHeight()))
    area.bar:SetMinMaxValues(0, maximum)

    if maximum > 0 then
        area.bar:Show()
        if area.bar:GetValue() > maximum then
            area.bar:SetValue(maximum)
        end
    else
        area.bar:SetValue(0)
        area.bar:Hide()
    end
end

function Board:SortPool()
    table.sort(self.state.U, function(leftKey, rightKey)
        local left = self.spellsByKey[leftKey]
        local right = self.spellsByKey[rightKey]
        local leftCategory = string.lower(left.category or "")
        local rightCategory = string.lower(right.category or "")

        if leftCategory ~= rightCategory then
            return leftCategory < rightCategory
        end

        local leftName = string.lower(left.name or "")
        local rightName = string.lower(right.name or "")
        if leftName ~= rightName then
            return leftName < rightName
        end

        return leftKey < rightKey
    end)
end

function Board:MatchesFilters(spell)
    if self.filterCategory and self.filterCategory ~= "All" and spell.category ~= self.filterCategory then
        return false
    end

    if self.filterCOA and not spell.coa then
        return false
    end

    local search = self.searchText or ""
    if search ~= "" then
        local name = string.lower(spell.name or "")
        local id = spell.spellID and tostring(spell.spellID) or ""
        if not string.find(name, search, 1, true) and not string.find(id, search, 1, true) then
            return false
        end
    end

    return true
end

function Board:GetVisibleKeys(tier)
    local visible = {}
    for _, key in ipairs(self.state[tier]) do
        local spell = self.spellsByKey[key]
        if spell and self:MatchesFilters(spell) then
            table.insert(visible, key)
        end
    end
    return visible
end

function Board:VisibleIndexToStateIndex(tier, visibleIndex)
    local visible = self.rows[tier].visibleKeys or {}
    if #visible == 0 then
        return #self.state[tier] + 1
    end

    if visibleIndex <= #visible then
        local targetKey = visible[visibleIndex]
        for stateIndex, key in ipairs(self.state[tier]) do
            if key == targetKey then
                return stateIndex
            end
        end
    end

    local lastVisibleKey = visible[#visible]
    for stateIndex, key in ipairs(self.state[tier]) do
        if key == lastVisibleKey then
            return stateIndex + 1
        end
    end

    return #self.state[tier] + 1
end

function Board:BuildCustomSpell(spellID, saved)
    local name, _, icon = GetSpellInfo(spellID)
    if not name then
        return nil
    end

    return {
        key = "spell:" .. tostring(spellID),
        spellID = spellID,
        name = name,
        icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
        category = NormalizeCategory(saved.category),
        coa = saved.coa == true,
        note = "Added in game from spell ID " .. tostring(spellID) .. ".",
        custom = true,
    }
end

-- Catalog and persisted custom-spell metadata
function Board:BuildCatalog()
    self.catalog = {}
    self.spellsByKey = {}

    for savedKey, saved in pairs(Addon.db.customSpells) do
        local spellID = tonumber(saved.id or savedKey)
        if spellID then
            saved.category = NormalizeCategory(saved.category)
            saved.coa = saved.coa == true
            saved.updatedAt = tonumber(saved.updatedAt) or 0
            local spell = self:BuildCustomSpell(spellID, saved)
            if spell then
                table.insert(self.catalog, spell)
                self.spellsByKey[spell.key] = spell
            end
        end
    end
end

function Board:UpsertCustomSpell(spellID, category, coa)
    local name = GetSpellInfo(spellID)
    if not name then
        return nil
    end

    local savedKey = tostring(spellID)
    local existingSaved = Addon.db.customSpells[savedKey]
    if coa == nil then
        coa = existingSaved and existingSaved.coa == true
    end
    Addon.db.customSpells[savedKey] = {
        id = spellID,
        category = NormalizeCategory(category),
        coa = coa == true,
        updatedAt = time and time() or 0,
    }
    Addon.db.spellTombstones[savedKey] = nil

    local key = "spell:" .. savedKey
    local spell = self:BuildCustomSpell(spellID, Addon.db.customSpells[savedKey])
    local existing = self.spellsByKey[key]
    if existing then
        for field, value in pairs(spell) do
            existing[field] = value
        end
        local card = self.cards[key]
        if card then
            card.spell = existing
            card.icon:SetTexture(existing.icon)
            card.label:SetText(existing.name)
        else
            self.cards[key] = self:CreateCard(existing)
        end
    else
        table.insert(self.catalog, spell)
        self.spellsByKey[key] = spell
        self.cards[key] = self:CreateCard(spell)
    end

    return self.spellsByKey[key]
end

function Board:AddCustomSpell(spellID, category, coa)
    local spell = self:UpsertCustomSpell(spellID, category, coa)
    if not spell then
        Addon:Print("Spell ID " .. tostring(spellID) .. " is not available in the client.")
        return false
    end

    if not self:FindSpellLocation(spell.key) then
        table.insert(self.state.U, spell.key)
    end

    self:SortPool()
    self:SaveState("Added or updated " .. spell.name .. " (spell ID " .. tostring(spell.spellID) .. ").", spell.key)
    if Addon.Sync and not Addon:IsOfficialList() then
        Addon.Sync:MarkDirty(true)
    end
    self:Layout()
    Addon:Print(spell.name .. " added to the Pool.")
    return true
end

function Board:AddCustomSpells(entries)
    if not Addon:CanEditActiveList() then
        Addon:Print(Addon.OFFICIAL_LIST_NAME .. " is read-only.")
        return 0, #(entries or {})
    end

    local changedKeys = {}
    local added = 0
    local unavailable = 0
    for _, entry in ipairs(entries or {}) do
        local spell = self:UpsertCustomSpell(entry.spellID, entry.category, entry.coa)
        if spell then
            if not self:FindSpellLocation(spell.key) then
                table.insert(self.state.U, spell.key)
            end
            table.insert(changedKeys, spell.key)
            added = added + 1
        else
            unavailable = unavailable + 1
        end
    end

    if added == 0 then
        return 0, unavailable
    end
    self:SortPool()
    self:SaveState("Added or updated " .. tostring(added) .. " spells from Batch Capture.", changedKeys)
    if Addon.Sync and not Addon:IsOfficialList() then
        Addon.Sync:MarkDirty(true)
    end
    self:Layout()
    Addon:Print("Batch Capture added " .. tostring(added) .. " spell(s) to the Pool.")
    return added, unavailable
end

function Board:SetCustomSpellCategory(spell, category)
    if not spell or not spell.custom or not spell.spellID then
        return
    end

    if not Addon:CanEditActiveList() then
        Addon:Print(Addon.OFFICIAL_LIST_NAME .. " is read-only.")
        return
    end

    category = NormalizeCategory(category)
    if spell.category == category then
        return
    end

    local saved = Addon.db.customSpells[tostring(spell.spellID)]
    if not saved then
        return
    end

    local oldCategory = spell.category
    saved.category = category
    saved.updatedAt = time and time() or 0
    spell.category = category

    self:SortPool()
    self:SaveState()
    if Addon:IsOfficialList() and Addon.Official then
        Addon.Official:RecordActivity("Changed " .. spell.name .. " category from " .. oldCategory .. " to " .. category .. ".")
    end
    if Addon.Sync then
        Addon.Sync:MarkDirty(true)
    end
    self:Layout()
    Addon:Print(spell.name .. " category changed to " .. category .. ".")
end

function Board:SetCustomSpellCOA(spell, enabled)
    if not spell or not spell.custom or not spell.spellID then
        return
    end

    if not Addon:CanEditActiveList() then
        Addon:Print(Addon.OFFICIAL_LIST_NAME .. " is read-only.")
        return
    end

    enabled = enabled == true
    if spell.coa == enabled then
        return
    end

    local saved = Addon.db.customSpells[tostring(spell.spellID)]
    if not saved then
        return
    end

    saved.coa = enabled
    saved.updatedAt = time and time() or 0
    spell.coa = enabled
    local action = enabled and "Marked " or "Unmarked "
    self:SaveState()
    if Addon:IsOfficialList() and Addon.Official then
        Addon.Official:RecordActivity(action .. spell.name .. " as COA.")
    end
    if Addon.Sync then
        Addon.Sync:MarkDirty(true)
    end
    self:Layout()
    Addon:Print(spell.name .. (enabled and " marked as COA." or " is no longer marked as COA."))
end

function Board:DeleteCustomSpell(spell)
    if not spell or not spell.custom or not spell.spellID then
        return
    end

    if not Addon:CanEditActiveList() then
        Addon:Print(Addon.OFFICIAL_LIST_NAME .. " is read-only.")
        return
    end

    local key = spell.key
    Addon.db.customSpells[tostring(spell.spellID)] = nil
    Addon.db.spellTombstones[tostring(spell.spellID)] = time and time() or 0

    for _, tier in ipairs(Addon.tierOrder) do
        for index = #self.state[tier], 1, -1 do
            if self.state[tier][index] == key then
                table.remove(self.state[tier], index)
            end
        end
    end

    for index = #self.catalog, 1, -1 do
        if self.catalog[index].key == key then
            table.remove(self.catalog, index)
        end
    end

    local card = self.cards[key]
    if card then
        card:Hide()
        card:SetParent(UIParent)
    end
    self.cards[key] = nil
    self.spellsByKey[key] = nil

    self:SaveState("Deleted " .. spell.name .. " (spell ID " .. tostring(spell.spellID) .. ").", spell.key)
    if Addon.Sync and not Addon:IsOfficialList() then
        Addon.Sync:MarkDirty(true)
    end
    self:Layout()
    Addon:Print(spell.name .. " deleted. Add ID " .. tostring(spell.spellID) .. " again to restore it.")
end

function Board:ReloadFromDatabase()
    local oldCards = self.cards or {}
    self:BuildCatalog()
    self.cards = {}

    for _, spell in ipairs(self.catalog) do
        local card = oldCards[spell.key]
        if card then
            card.spell = spell
            card.icon:SetTexture(spell.icon)
            card.label:SetText(spell.name)
            self.cards[spell.key] = card
            oldCards[spell.key] = nil
        else
            self.cards[spell.key] = self:CreateCard(spell)
        end
    end

    for _, card in pairs(oldCards) do
        card:Hide()
        card:SetParent(UIParent)
    end

    self:BuildState()
    self:RefreshListControls()
    self:RefreshAuditLog()
    self:Layout()
end

function Board:ShowSpellContextMenu(card)
    if not self.contextMenu or not card or not card.spell then
        return
    end

    self.contextSpell = card.spell
    self.contextMenuOpen = true
    self.contextMouseWasDown = IsMouseButtonDown("LeftButton")
    ToggleDropDownMenu(1, nil, self.contextMenu, card, 0, 0)
end

function Board:UpdateContextMenuClickAway()
    if not self.contextMenuOpen then
        return
    end

    if not DropDownList1 or not DropDownList1:IsShown() then
        self.contextMenuOpen = false
        self.contextMouseWasDown = false
        return
    end

    local mouseDown = IsMouseButtonDown("LeftButton")
    if mouseDown and not self.contextMouseWasDown then
        local focus = GetMouseFocus()
        local insideMenu = IsFrameInside(focus, DropDownList1)
        if DropDownList2 and DropDownList2:IsShown() then
            insideMenu = insideMenu or IsFrameInside(focus, DropDownList2)
        end

        if not insideMenu then
            CloseDropDownMenus()
            self.contextMenuOpen = false
        end
    end

    self.contextMouseWasDown = mouseDown
end

function Board:BuildState()
    self.state = { S = {}, A = {}, B = {}, C = {}, D = {}, U = {} }
    local assigned = {}
    local activeList = Addon:GetActiveList()
    local activeBoard = activeList and activeList.board or {}

    for _, tier in ipairs(Addon.tierOrder) do
        local saved = activeBoard[tier]
        if type(saved) == "table" then
            for _, key in ipairs(saved) do
                if self.spellsByKey[key] and not assigned[key] then
                    table.insert(self.state[tier], key)
                    assigned[key] = true
                end
            end
        end
    end

    for _, spell in ipairs(self.catalog) do
        if not assigned[spell.key] then
            table.insert(self.state.U, spell.key)
        end
    end

    self:SortPool()
    if not Addon:IsOfficialList() then
        self:SaveState()
    end
end

function Board:SnapshotState()
    local board = {}
    for _, tier in ipairs(Addon.tierOrder) do
        board[tier] = {}
        for index, key in ipairs(self.state[tier]) do
            board[tier][index] = key
        end
    end
    return board
end

function Board:SaveState(auditAction, changedKeys)
    if not Addon:CanEditActiveList() then
        return
    end

    local snapshot = self:SnapshotState()
    if Addon:IsOfficialList() and auditAction and Addon.Official then
        Addon.Official:RecordBoardChange(auditAction, snapshot, changedKeys)
        self:RefreshAuditLog()
    elseif not Addon:IsOfficialList() then
        Addon:GetActiveList().board = snapshot
    end
end

function Board:ResetState()
    self:BuildState()
    self:Layout()
end

function Board:FindSpellLocation(key)
    for _, tier in ipairs(Addon.tierOrder) do
        for index, candidate in ipairs(self.state[tier]) do
            if candidate == key then
                return tier, index
            end
        end
    end
end

-- Drag/drop placement
function Board:GetDropTarget(x, y)
    for _, tier in ipairs(Addon.tierOrder) do
        local row = self.rows[tier]
        if CursorInside(row.dropViewport, x, y) and CursorInside(row.content, x, y) then
            local localX = x - row.content:GetLeft()
            local localY = row.content:GetTop() - y
            local columns = math.max(1, math.floor(CONTENT_WIDTH / (CARD_WIDTH + CARD_GAP)))
            local column = math.floor(localX / (CARD_WIDTH + CARD_GAP))
            local line = math.floor(localY / (CARD_HEIGHT + CARD_GAP))
            local visibleIndex = line * columns + column + 1
            visibleIndex = math.max(1, math.min(visibleIndex, #(row.visibleKeys or {}) + 1))
            return tier, self:VisibleIndexToStateIndex(tier, visibleIndex)
        end
    end
end

function Board:StartDrag(card)
    if self.dragging then
        return
    end
    if not Addon:CanEditActiveList() then
        Addon:Print(Addon.OFFICIAL_LIST_NAME .. " is read-only.")
        return
    end

    self.dragging = card
    card.dragSawButtonDown = false
    card:SetParent(UIParent)
    card:SetFrameStrata("TOOLTIP")
    card:SetAlpha(0.88)
    card:ClearAllPoints()
    card:SetScript("OnUpdate", function(self)
        local x, y = GetCursorUIPosition()
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)

        if IsMouseButtonDown("LeftButton") then
            self.dragSawButtonDown = true
        elseif self.dragSawButtonDown then
            Board:StopDrag(self)
        end
    end)
end

function Board:StopDrag(card)
    if self.dragging ~= card then
        return
    end

    card:SetScript("OnUpdate", nil)
    card.dragSawButtonDown = nil
    card:SetFrameStrata("DIALOG")
    card:SetAlpha(1)

    local x, y = GetCursorUIPosition()
    local destinationTier, destinationIndex = self:GetDropTarget(x, y)
    local sourceTier, sourceIndex = self:FindSpellLocation(card.spell.key)

    if destinationTier and sourceTier then
        table.remove(self.state[sourceTier], sourceIndex)
        if sourceTier == destinationTier and destinationIndex > sourceIndex then
            destinationIndex = destinationIndex - 1
        end
        destinationIndex = math.max(1, math.min(destinationIndex, #self.state[destinationTier] + 1))
        table.insert(self.state[destinationTier], destinationIndex, card.spell.key)
        self:SortPool()
        local action
        if sourceTier == destinationTier then
            action = "Reordered " .. card.spell.name .. " within " .. sourceTier .. "."
        else
            action = "Moved " .. card.spell.name .. " from " .. sourceTier .. " to " .. destinationTier .. "."
        end
        self:SaveState(action, card.spell.key)
    end

    self.dragging = nil
    self:Layout()
end

function Board:CreateCard(spell)
    local card = CreateFrame("Button", nil, self.frame)
    card:SetWidth(CARD_WIDTH)
    card:SetHeight(CARD_HEIGHT)
    card:SetFrameStrata("DIALOG")
    card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    SetBackdrop(card, { 0.08, 0.08, 0.10, 0.98 }, { 0.35, 0.35, 0.40, 1 })

    card.spell = spell

    local icon = card:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(42)
    icon:SetHeight(42)
    icon:SetPoint("TOP", card, "TOP", 0, -5)
    icon:SetTexture(spell.icon)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    card.icon = icon

    local label = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", -8, -2)
    label:SetPoint("TOPRIGHT", icon, "BOTTOMRIGHT", 8, -2)
    label:SetHeight(14)
    label:SetJustifyH("CENTER")
    label:SetText(spell.name)
    card.label = label

    local highlight = card:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetAllPoints(icon)
    highlight:SetBlendMode("ADD")

    card:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.spell.spellID then
            GameTooltip:SetHyperlink("spell:" .. tostring(self.spell.spellID))
            GameTooltip:AddLine("Category: " .. self.spell.category, 0.35, 0.75, 1)
        else
            GameTooltip:SetText(self.spell.name, 1, 0.82, 0)
            GameTooltip:AddLine(self.spell.category, 0.35, 0.75, 1)
            GameTooltip:AddLine(self.spell.note, 1, 1, 1, true)
        end
        if self.spell.coa then
            GameTooltip:AddLine("COA", 1, 0.76, 0.18)
        end

        GameTooltip:Show()
    end)
    card:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    card:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            GameTooltip:Hide()
            Board:StartDrag(self)
        end
    end)
    card:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            Board:StopDrag(self)
        elseif button == "RightButton" then
            GameTooltip:Hide()
            Board:ShowSpellContextMenu(self)
        end
    end)

    return card
end

-- Board rows and scrolling
function Board:CreateScrollArea(parent, width, height)
    local area = {}

    local viewport = CreateFrame("ScrollFrame", nil, parent)
    viewport:SetWidth(width - 22)
    viewport:SetHeight(height)
    viewport:EnableMouseWheel(true)

    local canvas = CreateFrame("Frame", nil, viewport)
    canvas:SetWidth(width - 22)
    canvas:SetHeight(height)
    viewport:SetScrollChild(canvas)

    local bar = CreateFrame("Slider", nil, parent)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(16)
    bar:SetHeight(height - 4)
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(CARD_HEIGHT + CARD_GAP)
    bar:SetValue(0)
    bar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    SetBackdrop(bar, { 0.035, 0.035, 0.045, 0.95 }, { 0.20, 0.20, 0.24, 1 })
    bar:SetScript("OnValueChanged", function(self, value)
        viewport:SetVerticalScroll(value)
    end)

    viewport:SetScript("OnMouseWheel", function(self, delta)
        local minimum, maximum = bar:GetMinMaxValues()
        local value = math.max(minimum, math.min(maximum, bar:GetValue() - delta * (CARD_HEIGHT + CARD_GAP)))
        bar:SetValue(value)
    end)

    area.viewport = viewport
    area.canvas = canvas
    area.bar = bar
    return area
end

function Board:CreateRow(tier, parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetWidth(ROW_WIDTH)
    row:SetHeight(76)
    SetBackdrop(row, { 0.055, 0.055, 0.065, 0.94 }, { 0.22, 0.22, 0.25, 1 })

    local tierLabel = CreateTierLabel(row, tier, TIER_NAMES[tier], "GameFontNormalHuge")

    local content = CreateFrame("Frame", nil, row)
    content:SetPoint("TOPLEFT", tierLabel, "TOPRIGHT", 7, 0)
    content:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -5, 4)
    row.content = content
    row.dropViewport = self.rankedArea.viewport
    row.cardParent = self.rankedArea.canvas

    self.rows[tier] = row
end

function Board:CreatePoolRow()
    local row = CreateFrame("Frame", nil, self.frame)
    row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 14, -498)
    row:SetWidth(952)
    row:SetHeight(POOL_ROW_HEIGHT)
    SetBackdrop(row, { 0.055, 0.055, 0.065, 0.94 }, { 0.22, 0.22, 0.25, 1 })

    local tierLabel = CreateTierLabel(row, "U", "POOL", "GameFontNormalLarge")

    self.poolArea = self:CreateScrollArea(row, 880, POOL_ROW_HEIGHT - 8)
    self.poolArea.viewport:SetPoint("TOPLEFT", tierLabel, "TOPRIGHT", 7, 0)
    self.poolArea.bar:SetPoint("TOPRIGHT", row, "TOPRIGHT", -5, -4)

    row.content = self.poolArea.canvas
    row.dropViewport = self.poolArea.viewport
    row.cardParent = self.poolArea.canvas
    self.rows.U = row
end

function Board:Layout()
    if self.dragging then
        return
    end

    local columns = math.max(1, math.floor(CONTENT_WIDTH / (CARD_WIDTH + CARD_GAP)))

    for _, card in pairs(self.cards) do
        card:Hide()
    end

    local rankedHeight = 0
    local visibleTotal = 0
    for _, tier in ipairs(RANKED_TIERS) do
        local row = self.rows[tier]
        row.visibleKeys = self:GetVisibleKeys(tier)
        visibleTotal = visibleTotal + #row.visibleKeys
        local lines = math.max(1, math.ceil(#row.visibleKeys / columns))
        local rowHeight = math.max(76, lines * (CARD_HEIGHT + CARD_GAP) + 5)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.rankedArea.canvas, "TOPLEFT", 0, -rankedHeight)
        row:SetHeight(rowHeight)
        rankedHeight = rankedHeight + rowHeight + 2
    end
    UpdateScrollRange(self.rankedArea, rankedHeight)

    self.rows.U.visibleKeys = self:GetVisibleKeys("U")
    visibleTotal = visibleTotal + #self.rows.U.visibleKeys
    local poolLines = math.max(1, math.ceil(#self.rows.U.visibleKeys / columns))
    local poolHeight = poolLines * (CARD_HEIGHT + CARD_GAP) + 4
    UpdateScrollRange(self.poolArea, poolHeight)

    if self.filterCountText then
        self.filterCountText:SetText(tostring(visibleTotal) .. " / " .. tostring(#self.catalog) .. " spells")
    end

    for _, tier in ipairs(Addon.tierOrder) do
        local row = self.rows[tier]
        for index, key in ipairs(row.visibleKeys) do
            local card = self.cards[key]
            local zeroIndex = index - 1
            local column = zeroIndex % columns
            local line = math.floor(zeroIndex / columns)
            card:SetParent(row.cardParent)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", row.content, "TOPLEFT", column * (CARD_WIDTH + CARD_GAP), -line * (CARD_HEIGHT + CARD_GAP))
            card:SetFrameStrata("DIALOG")
            card:Show()
        end
    end
end

function Board:CreateFilterBar()
    local bar = CreateFrame("Frame", nil, self.frame)
    bar:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 80, -77)
    bar:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -16, -77)
    bar:SetHeight(25)
    self.filterBar = bar

    local searchLabel = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    searchLabel:SetPoint("LEFT", bar, "LEFT", 2, 0)
    searchLabel:SetText("Search")

    local searchBox = CreateFrame("EditBox", nil, bar, "InputBoxTemplate")
    searchBox:SetWidth(170)
    searchBox:SetHeight(22)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 11, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(60)
    self.filterSearchBox = searchBox

    local categoryLabel = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    categoryLabel:SetPoint("LEFT", searchBox, "RIGHT", 18, 0)
    categoryLabel:SetText("Category")

    local categoryDropdown = CreateFrame("Frame", "ActuallyCategoryFilterDropdown", bar, "UIDropDownMenuTemplate")
    categoryDropdown:SetPoint("LEFT", categoryLabel, "RIGHT", -13, -2)
    UIDropDownMenu_SetWidth(categoryDropdown, 125)
    self.filterCategoryDropdown = categoryDropdown
    bar.categoryIndex = 1

    local coaCheckbox = CreateFrame("CheckButton", "ActuallyCOAFilterCheckButton", bar, "UICheckButtonTemplate")
    coaCheckbox:SetWidth(24)
    coaCheckbox:SetHeight(24)
    coaCheckbox:SetPoint("LEFT", categoryDropdown, "RIGHT", -4, 2)
    coaCheckbox:SetChecked(false)
    self.filterCOACheckbox = coaCheckbox

    local coaLabel = coaCheckbox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    coaLabel:SetPoint("LEFT", coaCheckbox, "RIGHT", 1, 1)
    coaLabel:SetText("COA only")

    local countText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    self.filterCountText = countText

    local function RefreshFilters()
        self.searchText = string.lower(searchBox:GetText() or "")
        self.filterCategory = FILTER_CATEGORIES[bar.categoryIndex]
        self.filterCOA = coaCheckbox:GetChecked() and true or false
        self:ResetScrollPositions()
        self:Layout()
    end

    searchBox:SetScript("OnTextChanged", RefreshFilters)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        self:SetText("")
    end)
    searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    InitializeSelectionDropdown(categoryDropdown, FILTER_CATEGORIES, function()
        return bar.categoryIndex
    end, function(index)
        bar.categoryIndex = index
        RefreshFilters()
    end)
    SetDropdownSelection(categoryDropdown, "All")
    coaCheckbox:SetScript("OnClick", RefreshFilters)

    self.searchText = ""
    self.filterCategory = "All"
    self.filterCOA = false
    self.filterControls = { searchBox, categoryDropdown, coaCheckbox }
end

function Board:CreateResetConfirmations()
    StaticPopupDialogs.ACTUALLY_RESET_PERSONAL = {
        text = "Reset %s?\n\nEvery spell will be returned to the Pool.",
        button1 = YES,
        button2 = NO,
        OnAccept = function()
            Addon:ResetBoard()
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
    }

    StaticPopupDialogs.ACTUALLY_RESET_OFFICIAL_FIRST = {
        text = "Reset the OFFICIAL TIER LIST?\n\nThis affects the guild-approved rankings and will be recorded in the audit log.",
        button1 = "Continue",
        button2 = CANCEL,
        OnAccept = function()
            StaticPopup_Show("ACTUALLY_RESET_OFFICIAL_SECOND")
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        showAlert = 1,
    }

    StaticPopupDialogs.ACTUALLY_RESET_OFFICIAL_SECOND = {
        text = "SECOND WARNING\n\nEvery official spell placement will be returned to the Pool.",
        button1 = "Continue",
        button2 = CANCEL,
        OnAccept = function()
            StaticPopup_Show("ACTUALLY_RESET_OFFICIAL_FINAL")
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        showAlert = 1,
    }

    StaticPopupDialogs.ACTUALLY_RESET_OFFICIAL_FINAL = {
        text = "FINAL WARNING (3 OF 3)\n\nAre you absolutely sure you want to reset the Official Tier List?",
        button1 = "RESET OFFICIAL",
        button2 = CANCEL,
        OnAccept = function()
            Addon:ResetBoard()
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        showAlert = 1,
    }
end

function Board:RequestReset()
    if not Addon:CanEditActiveList() then
        Addon:Print(Addon.OFFICIAL_LIST_NAME .. " is read-only.")
        return
    end

    if Addon:IsOfficialList() then
        StaticPopup_Show("ACTUALLY_RESET_OFFICIAL_FIRST")
    else
        StaticPopup_Show("ACTUALLY_RESET_PERSONAL", Addon.db.activeList.name)
    end
end

function Board:CreateContextMenu()
    local menu = CreateFrame("Frame", "ActuallySpellContextMenu", UIParent, "UIDropDownMenuTemplate")

    UIDropDownMenu_Initialize(menu, function(dropdown, level)
        local spell = Board.contextSpell
        if not spell then
            return
        end

        if level == 2 and UIDROPDOWNMENU_MENU_VALUE == "ACTUALLY_CATEGORY" then
            for _, category in ipairs(SPELL_CATEGORIES) do
                local selectedCategory = category
                local categoryChoice = UIDropDownMenu_CreateInfo()
                categoryChoice.text = selectedCategory
                categoryChoice.value = selectedCategory
                categoryChoice.checked = spell.category == selectedCategory
                categoryChoice.func = function()
                    CloseDropDownMenus()
                    Board:SetCustomSpellCategory(spell, selectedCategory)
                end
                UIDropDownMenu_AddButton(categoryChoice, level)
            end
            return
        elseif level ~= 1 then
            return
        end

        local title = UIDropDownMenu_CreateInfo()
        title.text = spell.name
        title.isTitle = true
        title.notCheckable = true
        UIDropDownMenu_AddButton(title, level)

        local discussion = UIDropDownMenu_CreateInfo()
        discussion.text = "Discussion"
        discussion.notCheckable = true
        discussion.func = function()
            CloseDropDownMenus()
            Board:ShowDiscussion(spell)
        end
        UIDropDownMenu_AddButton(discussion, level)

        local category = UIDropDownMenu_CreateInfo()
        category.text = "Category: " .. tostring(spell.category or "Other")
        category.notCheckable = true
        category.hasArrow = true
        category.value = "ACTUALLY_CATEGORY"
        category.disabled = not spell.custom or not Addon:CanEditActiveList()
        UIDropDownMenu_AddButton(category, level)

        local coa = UIDropDownMenu_CreateInfo()
        coa.text = "COA"
        coa.checked = spell.coa == true
        coa.disabled = not spell.custom or not Addon:CanEditActiveList()
        coa.func = function()
            CloseDropDownMenus()
            Board:SetCustomSpellCOA(spell, not spell.coa)
        end
        UIDropDownMenu_AddButton(coa, level)

        local delete = UIDropDownMenu_CreateInfo()
        delete.text = "Delete Spell"
        delete.notCheckable = true
        delete.disabled = not spell.custom or not Addon:CanEditActiveList()
        delete.colorCode = "|cffff5555"
        delete.func = function()
            CloseDropDownMenus()
            Board:DeleteCustomSpell(spell)
        end
        UIDropDownMenu_AddButton(delete, level)

        local cancel = UIDropDownMenu_CreateInfo()
        cancel.text = CANCEL
        cancel.notCheckable = true
        cancel.func = function()
            CloseDropDownMenus()
        end
        UIDropDownMenu_AddButton(cancel, level)
    end, "MENU")

    self.contextMenu = menu
end

function Board:ShowDiscussion(spell)
    if not Addon.Discussion or not Addon.Discussion.Show then
        Addon:Print("Discussion module is not loaded. Try /reload.")
        return
    end

    local opened, errorMessage = pcall(Addon.Discussion.Show, Addon.Discussion, spell)
    if not opened then
        Addon:Print("Could not open Discussion: " .. tostring(errorMessage))
        return
    end

    if not Addon.Discussion.frame or not Addon.Discussion.frame:IsShown() then
        Addon:Print("Discussion did not open. Try /reload.")
    end
end

function Board:CreateSpellEditor()
    local editor = CreateFrame("Frame", "ActuallyAddSpellFrame", self.frame)
    editor:SetWidth(390)
    editor:SetHeight(230)
    editor:SetPoint("CENTER", self.frame, "CENTER", 0, 35)
    editor:SetFrameStrata("FULLSCREEN_DIALOG")
    editor:EnableMouse(true)
    SetBackdrop(editor, { 0.035, 0.035, 0.05, 0.99 }, { 0.25, 0.65, 0.90, 1 })
    editor:Hide()

    local title = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", editor, "TOPLEFT", 16, -15)
    title:SetText("Add a spell")

    local close = CreateFrame("Button", nil, editor, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", editor, "TOPRIGHT", -4, -4)

    local idLabel = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    idLabel:SetPoint("TOPLEFT", editor, "TOPLEFT", 18, -54)
    idLabel:SetText("Spell ID")

    local input = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
    input:SetWidth(145)
    input:SetHeight(24)
    input:SetPoint("LEFT", idLabel, "RIGHT", 14, 0)
    input:SetAutoFocus(false)
    input:SetMaxLetters(10)
    local preview = CreateFrame("Button", nil, editor)
    preview:SetWidth(42)
    preview:SetHeight(42)
    preview:SetPoint("TOPRIGHT", editor, "TOPRIGHT", -22, -50)
    local previewIcon = preview:CreateTexture(nil, "ARTWORK")
    previewIcon:SetAllPoints(preview)
    previewIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    previewIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local previewName = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    previewName:SetPoint("TOPLEFT", editor, "TOPLEFT", 18, -91)
    previewName:SetPoint("RIGHT", preview, "LEFT", -10, 0)
    previewName:SetJustifyH("LEFT")
    previewName:SetText("Enter an ID to preview it")
    local categoryLabel = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    categoryLabel:SetPoint("TOPLEFT", editor, "TOPLEFT", 18, -128)
    categoryLabel:SetText("Category")

    local categoryDropdown = CreateFrame("Frame", "ActuallyAddSpellCategoryDropdown", editor, "UIDropDownMenuTemplate")
    categoryDropdown:SetPoint("LEFT", categoryLabel, "RIGHT", -13, -2)
    UIDropDownMenu_SetWidth(categoryDropdown, 140)
    editor.categoryIndex = #SPELL_CATEGORIES
    InitializeSelectionDropdown(categoryDropdown, SPELL_CATEGORIES, function()
        return editor.categoryIndex
    end, function(index)
        editor.categoryIndex = index
    end)
    SetDropdownSelection(categoryDropdown, SPELL_CATEGORIES[editor.categoryIndex])

    local coaCheckbox = CreateFrame("CheckButton", "ActuallyAddSpellCOACheckButton", editor, "UICheckButtonTemplate")
    coaCheckbox:SetWidth(24)
    coaCheckbox:SetHeight(24)
    coaCheckbox:SetPoint("LEFT", categoryDropdown, "RIGHT", -4, 2)
    coaCheckbox:SetChecked(false)

    local coaLabel = coaCheckbox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    coaLabel:SetPoint("LEFT", coaCheckbox, "RIGHT", 1, 1)
    coaLabel:SetText("COA")

    local hint = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", editor, "TOPLEFT", 18, -161)
    hint:SetText("The native tooltip supplies description and cooldown text.")

    local addButton = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    addButton:SetWidth(110)
    addButton:SetHeight(25)
    addButton:SetPoint("BOTTOMRIGHT", editor, "BOTTOMRIGHT", -18, 15)
    addButton:SetText("Add to Pool")
    addButton:Disable()
    editor.addButton = addButton

    local function ShowSpellTooltip(owner)
        if not editor.spellID then
            return
        end
        GameTooltip:SetOwner(owner or editor, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("spell:" .. tostring(editor.spellID))
        GameTooltip:Show()
    end

    local function UpdatePreview()
        local spellID = tonumber(input:GetText())
        local name, rank, icon = spellID and GetSpellInfo(spellID)
        if name then
            editor.spellID = spellID
            previewIcon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            previewName:SetText(rank and rank ~= "" and (name .. " (" .. rank .. ")") or name)
            addButton:Enable()
            ShowSpellTooltip(editor)
        else
            editor.spellID = nil
            previewIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            previewName:SetText("Unknown spell ID")
            addButton:Disable()
            GameTooltip:Hide()
        end
    end

    input:SetScript("OnTextChanged", UpdatePreview)
    input:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        editor:Hide()
    end)
    input:SetScript("OnEnterPressed", function(self)
        if editor.spellID and addButton:IsEnabled() == 1 then
            addButton:Click()
        end
    end)

    preview:SetScript("OnEnter", function(self)
        ShowSpellTooltip(self)
    end)
    preview:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    addButton:SetScript("OnClick", function()
        if editor.spellID and Board:AddCustomSpell(
            editor.spellID,
            SPELL_CATEGORIES[editor.categoryIndex],
            coaCheckbox:GetChecked() and true or false
        ) then
            editor:Hide()
        end
    end)

    editor:SetScript("OnShow", function()
        editor.categoryIndex = #SPELL_CATEGORIES
        SetDropdownSelection(categoryDropdown, SPELL_CATEGORIES[editor.categoryIndex])
        coaCheckbox:SetChecked(false)
        input:SetText("")
        input:SetFocus()
    end)
    editor:SetScript("OnHide", function()
        input:ClearFocus()
        GameTooltip:Hide()
    end)

    self.spellEditor = editor
end

function Board:ShowSpellEditor()
    if not Addon:CanEditActiveList() then
        Addon:Print("Switch to a personal list before adding spells.")
        return
    end
    if self.spellEditor then
        self.spellEditor:Show()
    end
end

function Board:RefreshListControls()
    if not self.listSubtitle then
        return
    end

    local isOfficer = Addon.Official and Addon.Official:IsOfficer()
    if Addon:IsOfficialList() then
        local official = Addon.db.lists.official
        local revision = tonumber(official.revision) or 0
        local syncReady = not Addon.Sync or not Addon.Sync.IsOfficialEditReady
            or Addon.Sync:IsOfficialEditReady()
        local canEdit = isOfficer and syncReady
        local mode
        if isOfficer and not syncReady then
            mode = "|cffffcc55SYNCING - EDIT LOCKED|r"
        else
            mode = isOfficer and "|cff77dd77OFFICER EDIT|r" or "|cffaaaaaaread-only|r"
        end
        local editorName = official.lastModifiedBy and Addon.Util.ShortName(official.lastModifiedBy)
        local lastEditor = editorName and ("  |cffaaaaaaby " .. editorName .. "|r") or ""
        self.listSubtitle:SetText(mode .. "  Rev " .. revision .. lastEditor)
        if canEdit then
            self.resetButton:Enable()
            self.addSpellButton:Enable()
            self.batchCaptureButton:Enable()
        else
            self.resetButton:Disable()
            self.addSpellButton:Disable()
            self.batchCaptureButton:Disable()
        end
        if self.officialBadge then
            self.officialBadge:SetBackdropColor(0.24, 0.16, 0.025, 1)
            self.officialBadge:SetBackdropBorderColor(1, 0.93, 0.45, 1)
        end
    else
        self.listSubtitle:SetText(Addon.db.activeList.name .. "  |cff77cc77(personal)|r")
        self.resetButton:Enable()
        self.addSpellButton:Enable()
        self.batchCaptureButton:Enable()
        if self.officialBadge then
            self.officialBadge:SetBackdropColor(0.16, 0.105, 0.025, 0.98)
            self.officialBadge:SetBackdropBorderColor(1, 0.76, 0.18, 1)
        end
    end

    if self.auditButton then
        local audit = Addon.db.lists.official.audit or {}
        self.auditButton:SetText("Audit Log (" .. tostring(#audit) .. ")")
        if isOfficer then
            self.auditButton:Show()
        else
            self.auditButton:Hide()
            if self.auditFrame then
                self.auditFrame:Hide()
            end
        end
    end
    if Addon.Gear and Addon.Gear.frame then
        Addon.Gear:RefreshPermissions()
    end
    if Addon.CacheTips and Addon.CacheTips.RefreshPermissions then
        Addon.CacheTips:RefreshPermissions()
    end
    self:RefreshSectionNavigationPermissions()
end

function Board:RefreshAuditLog()
    if not self.auditArea or not self.auditRows then
        return
    end

    for _, row in ipairs(self.auditRows) do
        row:Hide()
    end

    local audit = Addon.db.lists.official.audit or {}
    local rowIndex = 0
    local contentHeight = 0
    if #audit == 0 then
        rowIndex = 1
        local row = self.auditRows[rowIndex]
        if not row then
            row = self.auditArea.canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row:SetWidth(490)
            row:SetJustifyH("LEFT")
            self.auditRows[rowIndex] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.auditArea.canvas, "TOPLEFT", 8, -8)
        row:SetHeight(28)
        row:SetText("No official-list activity has been recorded yet.")
        row:Show()
        contentHeight = 44
    else
        for index = #audit, 1, -1 do
            rowIndex = rowIndex + 1
            local entry = audit[index]
            local row = self.auditRows[rowIndex]
            if not row then
                row = self.auditArea.canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row:SetWidth(490)
                row:SetJustifyH("LEFT")
                row:SetJustifyV("TOP")
                self.auditRows[rowIndex] = row
            end

            local timestamp = "Unknown time"
            if entry.timestamp and entry.timestamp > 0 and date then
                timestamp = date("%d %b %Y %H:%M", entry.timestamp)
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.auditArea.canvas, "TOPLEFT", 8, -(8 + contentHeight))
            local entryHeight = entry.activity and 60 or 42
            local entryLabel = entry.activity and "Officer Discussion" or ("Revision " .. tostring(entry.revision or "?"))
            row:SetHeight(entryHeight)
            row:SetText(
                "|cffffd36a" .. entryLabel .. "|r  "
                    .. timestamp .. "  |cff69ccf0" .. tostring(entry.author or "Unknown") .. "|r\n"
                    .. tostring(entry.action or "Updated the official tier list.")
            )
            row:Show()
            contentHeight = contentHeight + entryHeight + 2
        end
        contentHeight = contentHeight + 8
    end

    UpdateScrollRange(self.auditArea, contentHeight)
    self.auditArea.bar:SetValue(0)
    self:RefreshListControls()
end

function Board:ResetScrollPositions()
    if self.rankedArea then
        self.rankedArea.bar:SetValue(0)
    end
    if self.poolArea then
        self.poolArea.bar:SetValue(0)
    end
end

function Board:SwitchList(kind, name)
    if not Addon:SetActiveList(kind, name) then
        Addon:Print("That tier list could not be found.")
        return
    end

    if self.spellEditor then
        self.spellEditor:Hide()
    end
    if self.saveListFrame then
        self.saveListFrame:Hide()
    end
    CloseDropDownMenus()
    self:BuildState()
    self:RefreshListControls()
    self:ResetScrollPositions()
    self:Layout()
end

function Board:ValidateNewListName(name)
    name = string.gsub(name or "", "^%s*(.-)%s*$", "%1")
    if name == "" then
        Addon:Print("Enter a name for the tier list.")
        return nil
    end
    if string.len(name) > 32 then
        Addon:Print("Tier-list names can be at most 32 characters.")
        return nil
    end
    if Addon.db.lists.personal[name] then
        Addon:Print("A personal tier list with that name already exists.")
        return nil
    end
    return name
end

-- Personal-list persistence and import/export
function Board:SaveCurrentAs(name)
    name = self:ValidateNewListName(name)
    if not name then
        return false
    end

    Addon.db.lists.personal[name] = {
        name = name,
        board = self:SnapshotState(),
    }
    Addon:SetActiveList("personal", name)
    self:BuildState()
    self:RefreshListControls()
    self:Layout()
    Addon:Print("Saved personal tier list: " .. name)
    return true
end

function Board:ExportCurrentList()
    local segments = { "ACT1" }
    for _, tier in ipairs(Addon.tierOrder) do
        local records = {}
        for _, key in ipairs(self.state[tier]) do
            local spell = self.spellsByKey[key]
            if spell and spell.spellID then
                local categoryIndex = CATEGORY_INDEX[NormalizeCategory(spell.category)] or #SPELL_CATEGORIES
                local coaFlag = spell.coa and 1 or 0
                table.insert(records, tostring(spell.spellID) .. "." .. tostring(categoryIndex) .. "." .. tostring(coaFlag))
            end
        end
        table.insert(segments, tier .. "=" .. table.concat(records, ","))
    end
    return table.concat(segments, "|")
end

function Board:ImportPersonalList(name, encoded)
    name = self:ValidateNewListName(name)
    if not name then
        return false
    end

    encoded = string.gsub(encoded or "", "%s", "")
    if string.len(encoded) > 50000 or string.sub(encoded, 1, 5) ~= "ACT1|" then
        Addon:Print("That is not a valid actually tier-list string.")
        return false
    end

    local pending = {}
    local seenIDs = {}
    local seenTiers = {}
    for segment in string.gmatch(string.sub(encoded, 6), "[^|]+") do
        local tier, payload = string.match(segment, "^([SABCDU])=(.*)$")
        if not tier or seenTiers[tier] then
            Addon:Print("The import string is malformed or contains a duplicate tier.")
            return false
        end
        seenTiers[tier] = true

        if payload ~= "" then
            for token in string.gmatch(payload, "[^,]+") do
                local spellIDText, categoryIndexText, coaFlagText = string.match(token, "^(%d+)%.(%d+)%.([01])$")
                if not spellIDText then
                    spellIDText, categoryIndexText = string.match(token, "^(%d+)%.(%d+)$")
                    coaFlagText = "0"
                end
                local spellID = tonumber(spellIDText)
                local categoryIndex = tonumber(categoryIndexText)
                if not spellID or not SPELL_CATEGORIES[categoryIndex] or seenIDs[spellID] then
                    Addon:Print("The import string contains an invalid or duplicate spell entry.")
                    return false
                end
                seenIDs[spellID] = true
                table.insert(pending, {
                    id = spellID,
                    category = SPELL_CATEGORIES[categoryIndex],
                    coa = coaFlagText == "1",
                    tier = tier,
                })
                if #pending > 750 then
                    Addon:Print("That tier list is too large to import safely.")
                    return false
                end
            end
        end
    end

    for _, tier in ipairs(Addon.tierOrder) do
        if not seenTiers[tier] then
            Addon:Print("The import string is missing tier " .. tier .. ".")
            return false
        end
    end

    local board = { S = {}, A = {}, B = {}, C = {}, D = {}, U = {} }
    local imported = 0
    local unavailable = 0
    for _, entry in ipairs(pending) do
        local spell = self:UpsertCustomSpell(entry.id, entry.category, entry.coa)
        if spell then
            table.insert(board[entry.tier], spell.key)
            imported = imported + 1
        else
            unavailable = unavailable + 1
        end
    end

    if #pending > 0 and imported == 0 then
        Addon:Print("None of those spell IDs are available in this client.")
        return false
    end

    Addon.db.lists.personal[name] = { name = name, board = board }
    self:SwitchList("personal", name)
    if Addon.Sync then
        Addon.Sync:MarkDirty(true)
    end
    Addon:Print("Imported " .. tostring(imported) .. " spells into " .. name .. ".")
    if unavailable > 0 then
        Addon:Print(tostring(unavailable) .. " unavailable spell IDs were skipped.")
    end
    return true
end

function Board:CreateListSelector()
    local menu = CreateFrame("Frame", "ActuallyTierListSelectorMenu", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(menu, function(dropdown, level)
        local official = UIDropDownMenu_CreateInfo()
        official.text = Addon.OFFICIAL_LIST_NAME
        official.value = "official"
        official.checked = Addon:IsOfficialList()
        official.func = function()
            Board:SwitchList("official", Addon.OFFICIAL_LIST_NAME)
        end
        UIDropDownMenu_AddButton(official, level)

        local names = {}
        for name in pairs(Addon.db.lists.personal) do
            table.insert(names, name)
        end
        table.sort(names, function(left, right)
            return string.lower(left) < string.lower(right)
        end)

        for _, name in ipairs(names) do
            local selectedName = name
            local info = UIDropDownMenu_CreateInfo()
            info.text = selectedName
            info.value = selectedName
            info.checked = not Addon:IsOfficialList() and Addon.db.activeList.name == selectedName
            info.func = function()
                Board:SwitchList("personal", selectedName)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end, "MENU")
    self.listSelectorMenu = menu
end

function Board:CreateSaveListFrame()
    local dialog = CreateFrame("Frame", "ActuallySaveTierListFrame", self.frame)
    dialog:SetWidth(360)
    dialog:SetHeight(150)
    dialog:SetPoint("CENTER", self.frame, "CENTER", 0, 30)
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:EnableMouse(true)
    SetBackdrop(dialog, { 0.035, 0.035, 0.05, 0.99 }, { 0.25, 0.65, 0.85, 1 })
    dialog:Hide()

    local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -16)
    title:SetText("Save as a personal tier list")

    local close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -4, -4)

    local input = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
    input:SetWidth(320)
    input:SetHeight(24)
    input:SetPoint("TOPLEFT", dialog, "TOPLEFT", 18, -55)
    input:SetAutoFocus(false)
    input:SetMaxLetters(32)

    local cancel = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    cancel:SetWidth(80)
    cancel:SetHeight(22)
    cancel:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -105, 15)
    cancel:SetText("Cancel")
    cancel:SetScript("OnClick", function()
        dialog:Hide()
    end)

    local save = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    save:SetWidth(80)
    save:SetHeight(22)
    save:SetPoint("LEFT", cancel, "RIGHT", 8, 0)
    save:SetText("Save")

    local function SaveList()
        if Board:SaveCurrentAs(input:GetText()) then
            input:ClearFocus()
            dialog:Hide()
        end
    end
    save:SetScript("OnClick", SaveList)
    input:SetScript("OnEnterPressed", SaveList)
    input:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        dialog:Hide()
    end)
    dialog:SetScript("OnShow", function()
        input:SetText("")
        input:SetFocus()
    end)

    self.saveListFrame = dialog
end

function Board:CreateTransferFrame()
    local dialog = CreateFrame("Frame", "ActuallyTierListTransferFrame", self.frame)
    dialog:SetWidth(660)
    dialog:SetHeight(410)
    dialog:SetPoint("CENTER", self.frame, "CENTER", 0, 15)
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:EnableMouse(true)
    SetBackdrop(dialog, { 0.025, 0.025, 0.04, 0.995 }, { 0.80, 0.62, 0.16, 1 })
    dialog:Hide()

    local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", dialog, "TOPLEFT", 18, -16)
    title:SetText("Import / Export Tier List")

    local close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -4, -4)

    local hint = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", dialog, "TOPLEFT", 18, -42)
    hint:SetText("Export, press Ctrl+C, then paste the string into another actually client.")

    local nameLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", dialog, "TOPLEFT", 18, -72)
    nameLabel:SetText("New personal list name")

    local nameInput = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
    nameInput:SetWidth(330)
    nameInput:SetHeight(22)
    nameInput:SetPoint("LEFT", nameLabel, "RIGHT", 12, 0)
    nameInput:SetAutoFocus(false)
    nameInput:SetMaxLetters(32)

    local textBorder = CreateFrame("Frame", nil, dialog)
    textBorder:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -100)
    textBorder:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -16, 58)
    SetBackdrop(textBorder, { 0.01, 0.01, 0.015, 1 }, { 0.25, 0.25, 0.30, 1 })

    local scroll = CreateFrame("ScrollFrame", "ActuallyTransferTextScrollFrame", textBorder, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", textBorder, "TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", textBorder, "BOTTOMRIGHT", -28, 8)

    local textInput = CreateFrame("EditBox", nil, scroll)
    textInput:SetWidth(580)
    textInput:SetHeight(230)
    textInput:SetMultiLine(true)
    textInput:SetAutoFocus(false)
    textInput:SetMaxLetters(50000)
    textInput:SetFontObject(ChatFontNormal)
    textInput:SetTextInsets(4, 4, 4, 4)
    scroll:SetScrollChild(textInput)

    textInput:SetScript("OnTextChanged", function(self)
        local approximateLines = math.max(1, math.ceil(string.len(self:GetText() or "") / 72))
        self:SetHeight(math.max(230, approximateLines * 15 + 12))
        scroll:UpdateScrollChildRect()
    end)
    textInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        dialog:Hide()
    end)

    local export = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    export:SetWidth(125)
    export:SetHeight(24)
    export:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 18, 18)
    export:SetText("Export Current")

    local clear = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    clear:SetWidth(75)
    clear:SetHeight(24)
    clear:SetPoint("LEFT", export, "RIGHT", 8, 0)
    clear:SetText("Clear")

    local import = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    import:SetWidth(145)
    import:SetHeight(24)
    import:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -18, 18)
    import:SetText("Import as Personal")

    local function ExportCurrent()
        textInput:SetText(Board:ExportCurrentList())
        textInput:SetFocus()
        textInput:HighlightText()
    end

    export:SetScript("OnClick", ExportCurrent)
    clear:SetScript("OnClick", function()
        textInput:SetText("")
        textInput:SetFocus()
    end)
    import:SetScript("OnClick", function()
        if Board:ImportPersonalList(nameInput:GetText(), textInput:GetText()) then
            textInput:ClearFocus()
            nameInput:ClearFocus()
            dialog:Hide()
        end
    end)
    dialog:SetScript("OnShow", function()
        local sourceName = Addon:IsOfficialList() and "Official Copy" or (Addon.db.activeList.name .. " Copy")
        nameInput:SetText(string.sub(sourceName, 1, 32))
        ExportCurrent()
    end)

    self.transferFrame = dialog
end

function Board:ShowTransferFrame()
    if self.transferFrame then
        self.transferFrame:Show()
    end
end

function Board:CreateAuditFrame()
    local dialog = CreateFrame("Frame", "ActuallyOfficialAuditFrame", self.frame)
    dialog:SetWidth(580)
    dialog:SetHeight(430)
    dialog:SetPoint("CENTER", self.frame, "CENTER", 0, 10)
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:EnableMouse(true)
    SetBackdrop(dialog, { 0.025, 0.025, 0.04, 0.995 }, { 0.80, 0.62, 0.16, 1 })
    dialog:Hide()

    local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", dialog, "TOPLEFT", 18, -16)
    title:SetText("Official Tier List Audit Log")

    local close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -4, -4)

    local hint = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", dialog, "TOPLEFT", 18, -43)
    hint:SetText("Newest changes appear first. Up to 100 entries are retained.")

    self.auditArea = self:CreateScrollArea(dialog, 540, 340)
    self.auditArea.viewport:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20, -70)
    self.auditArea.bar:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -20, -72)
    self.auditRows = {}
    self.auditFrame = dialog
end

function Board:ShowAuditLog()
    if not Addon.Official or not Addon.Official:IsOfficer() then
        return
    end
    if self.auditFrame then
        self.auditFrame:Show()
        self:RefreshAuditLog()
    end
end

function Board:Create()
    if self.frame then
        return
    end

    self:BuildCatalog()

    local frame = CreateFrame("Frame", "ActuallyTierBoardFrame", UIParent)
    frame:SetWidth(980)
    frame:SetHeight(BOARD_BASE_HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not Board.dragging then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    frame:SetScript("OnUpdate", function()
        Board:UpdateContextMenuClickAway()
    end)
    SetBackdrop(frame, { 0.025, 0.025, 0.035, 0.98 }, { 0.20, 0.55, 0.75, 1 })
    self.frame = frame

    if Addon.Analyzer then
        Addon.Analyzer:Create(frame)
        if Addon.Analyzer.launchButton then
            Addon.Analyzer.launchButton:ClearAllPoints()
            Addon.Analyzer.launchButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 700, -20)
        end
    end

    local headerBadge = CreateFrame("Frame", nil, frame)
    headerBadge:SetWidth(58)
    headerBadge:SetHeight(58)
    headerBadge:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -9)

    local badgeIcon = headerBadge:CreateTexture(nil, "ARTWORK")
    badgeIcon:SetWidth(54)
    badgeIcon:SetHeight(54)
    badgeIcon:SetPoint("CENTER")
    badgeIcon:SetTexture("Interface\\AddOns\\actually\\Textures\\NerdFace")
    badgeIcon:SetTexCoord(0, 1, 0, 1)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 80, -17)
    title:SetText("Cache Ability Tier List")

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 80, -42)
    subtitle:SetWidth(245)
    subtitle:SetHeight(16)
    subtitle:SetJustifyH("LEFT")
    self.listSubtitle = subtitle

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)

    local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    reset:SetWidth(90)
    reset:SetHeight(22)
    reset:SetText("Reset Board")
    reset:SetScript("OnClick", function()
        Board:RequestReset()
    end)
    self.resetButton = reset

    local addSpell = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addSpell:SetWidth(90)
    addSpell:SetHeight(22)
    addSpell:SetText("Add Spell")
    addSpell:SetScript("OnClick", function()
        Board:ShowSpellEditor()
    end)
    self.addSpellButton = addSpell

    local batchCapture = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    batchCapture:SetWidth(105)
    batchCapture:SetHeight(22)
    batchCapture:SetText("Batch Capture")
    batchCapture:SetScript("OnClick", function()
        if Addon.BatchCapture then
            Addon.BatchCapture:Show()
        end
    end)
    self.batchCaptureButton = batchCapture

    local auditButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    auditButton:SetWidth(100)
    auditButton:SetHeight(22)
    auditButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 835, -22)
    auditButton:SetText("Audit Log (0)")
    auditButton:SetScript("OnClick", function()
        Board:ShowAuditLog()
    end)
    self.auditButton = auditButton

    local officialBadge = CreateFrame("Frame", nil, frame)
    officialBadge:SetWidth(210)
    officialBadge:SetHeight(38)
    officialBadge:SetPoint("TOPLEFT", frame, "TOPLEFT", 335, -14)
    SetBackdrop(officialBadge, { 0.16, 0.105, 0.025, 0.98 }, { 1.00, 0.76, 0.18, 1 })
    self.officialBadge = officialBadge

    local discussionHint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    discussionHint:SetPoint("TOPLEFT", frame, "TOPLEFT", 560, -18)
    discussionHint:SetWidth(125)
    discussionHint:SetHeight(34)
    discussionHint:SetJustifyH("LEFT")
    discussionHint:SetJustifyV("MIDDLE")
    discussionHint:SetText("Right-click a spell\nfor Discussion")
    discussionHint:SetTextColor(1, 0.78, 0.22)

    local crownGlow = officialBadge:CreateTexture(nil, "BACKGROUND")
    crownGlow:SetWidth(48)
    crownGlow:SetHeight(48)
    crownGlow:SetPoint("LEFT", officialBadge, "LEFT", -5, 0)
    crownGlow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    crownGlow:SetBlendMode("ADD")
    crownGlow:SetVertexColor(1, 0.72, 0.12, 0.55)

    local crown = officialBadge:CreateTexture(nil, "ARTWORK")
    crown:SetWidth(22)
    crown:SetHeight(22)
    crown:SetPoint("LEFT", officialBadge, "LEFT", 7, 0)
    crown:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")

    local officialList = CreateFrame("Button", nil, officialBadge, "UIPanelButtonTemplate")
    officialList:SetWidth(168)
    officialList:SetHeight(26)
    officialList:SetPoint("RIGHT", officialBadge, "RIGHT", -5, 0)
    officialList:SetText("OFFICIAL TIER LIST")
    officialList:GetFontString():SetTextColor(1, 0.82, 0.24)
    officialList:SetScript("OnClick", function()
        Board:SwitchList("official", Addon.OFFICIAL_LIST_NAME)
    end)
    officialList:SetScript("OnEnter", function()
        officialBadge:SetBackdropBorderColor(1, 0.93, 0.45, 1)
        crownGlow:SetAlpha(0.95)
    end)
    officialList:SetScript("OnLeave", function()
        if Addon:IsOfficialList() then
            officialBadge:SetBackdropBorderColor(1, 0.93, 0.45, 1)
        else
            officialBadge:SetBackdropBorderColor(1, 0.76, 0.18, 1)
        end
        crownGlow:SetAlpha(1)
    end)

    local headerDivider = frame:CreateTexture(nil, "BACKGROUND")
    headerDivider:SetPoint("TOPLEFT", frame, "TOPLEFT", 80, -67)
    headerDivider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -67)
    headerDivider:SetHeight(1)
    headerDivider:SetTexture("Interface\\Buttons\\WHITE8X8")
    headerDivider:SetVertexColor(0.20, 0.55, 0.75, 0.34)

    local footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, TIER_FOOTER_BASE_Y)
    footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, TIER_FOOTER_BASE_Y)
    footer:SetHeight(34)
    self.tierFooter = footer
    SetBackdrop(footer, { 0.035, 0.04, 0.055, 0.96 }, { 0.13, 0.32, 0.43, 1 })

    local selectList = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    selectList:SetWidth(120)
    selectList:SetHeight(22)
    selectList:SetText("Select Tier List")
    selectList:SetScript("OnClick", function(self)
        ToggleDropDownMenu(1, nil, Board.listSelectorMenu, self, 0, 0)
    end)

    local saveList = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    saveList:SetWidth(90)
    saveList:SetHeight(22)
    saveList:SetText("Save As")
    saveList:SetScript("OnClick", function()
        Board.saveListFrame:Show()
    end)

    local transfer = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    transfer:SetWidth(115)
    transfer:SetHeight(22)
    transfer:SetText("Import / Export")
    transfer:SetScript("OnClick", function()
        Board:ShowTransferFrame()
    end)

    transfer:SetPoint("RIGHT", footer, "RIGHT", -6, 0)
    saveList:SetPoint("RIGHT", transfer, "LEFT", -6, 0)
    selectList:SetPoint("RIGHT", saveList, "LEFT", -6, 0)

    local petCheckbox = CreateFrame("CheckButton", "ActuallyShowPetCheckButton", footer, "UICheckButtonTemplate")
    petCheckbox:SetWidth(24)
    petCheckbox:SetHeight(24)
    petCheckbox:SetPoint("LEFT", footer, "LEFT", 6, 0)
    petCheckbox:SetChecked(Addon.db.pet.shown == true)

    local petCheckboxLabel = petCheckbox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    petCheckboxLabel:SetPoint("LEFT", petCheckbox, "RIGHT", 2, 1)
    petCheckboxLabel:SetText("Arnold")

    reset:SetParent(footer)
    addSpell:SetParent(footer)
    batchCapture:SetParent(footer)
    reset:SetPoint("LEFT", footer, "LEFT", 100, 0)
    addSpell:SetPoint("LEFT", reset, "RIGHT", 6, 0)
    batchCapture:SetPoint("LEFT", addSpell, "RIGHT", 6, 0)

    petCheckbox:SetScript("OnClick", function(self)
        if self:GetChecked() then
            Addon.Pet:Show()
            Addon.Pet:Play("happy")
        else
            Addon.Pet:Hide()
        end
    end)
    self.petCheckbox = petCheckbox

    self.rows = {}
    self.rankedArea = self:CreateScrollArea(frame, 952, RANKED_VIEW_HEIGHT)
    self.rankedArea.viewport:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -108)
    self.rankedArea.bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -110)
    for _, tier in ipairs(RANKED_TIERS) do
        self:CreateRow(tier, self.rankedArea.canvas)
    end
    self:CreatePoolRow()

    self.cards = {}
    for _, spell in ipairs(self.catalog) do
        self.cards[spell.key] = self:CreateCard(spell)
    end

    self:BuildState()
    self:CreateFilterBar()
    self:CreateResetConfirmations()
    self:CreateContextMenu()
    self:CreateListSelector()
    self:CreateSaveListFrame()
    self:CreateTransferFrame()
    self:CreateAuditFrame()
    self:RefreshListControls()
    self:Layout()
    self:CreateSpellEditor()
    self.tierSectionWidgets = {
        headerBadge, title, subtitle, reset, addSpell, batchCapture, auditButton,
        officialBadge, discussionHint, headerDivider, footer, self.filterBar, self.rankedArea.viewport,
        self.rankedArea.bar, self.rows.U,
    }
    if Addon.Analyzer and Addon.Analyzer.launchButton then
        table.insert(self.tierSectionWidgets, Addon.Analyzer.launchButton)
    end
    self:CreateSectionNavigation(close)
    if Addon.Gear then
        Addon.Gear:Create(frame)
    end
    self:RefreshSectionNavigationPermissions()
    frame:Hide()
end
