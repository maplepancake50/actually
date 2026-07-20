Actually = Actually or {}
local Addon = Actually

local Board = {}
Addon.Board = Board

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
    U = "?",
}

local CARD_WIDTH = 62
local CARD_HEIGHT = 66
local CARD_GAP = 5
local CONTENT_WIDTH = 842
local ROW_WIDTH = 928
local RANKED_VIEW_HEIGHT = 382
local POOL_ROW_HEIGHT = 198
local RANKED_TIERS = { "S", "A", "B", "C", "D" }
local CUSTOM_CATEGORIES = {
    "CC", "Defensive", "Immunity", "Interrupt", "Mobility", "Other",
}
local FILTER_CATEGORIES = {
    "All", "CC", "Defensive", "Immunity", "Interrupt", "Mobility", "Other",
}

local function NormalizeCategory(category)
    if category == "Control" or category == "Stun" then
        return "CC"
    elseif category == "Support" or category == "Dispel" or category == "Threat" then
        return "Other"
    end

    for _, validCategory in ipairs(CUSTOM_CATEGORIES) do
        if category == validCategory then
            return category
        end
    end

    return "Other"
end

local function SetBackdrop(frame, color, borderColor)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(color[1], color[2], color[3], color[4] or 1)
    frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
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
    local name, rank, icon = GetSpellInfo(spellID)
    if not name then
        return nil
    end

    return {
        key = "spell:" .. tostring(spellID),
        spellID = spellID,
        name = name,
        rank = rank,
        icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
        category = NormalizeCategory(saved.category),
        note = "Added in game from spell ID " .. tostring(spellID) .. ".",
        custom = true,
    }
end

function Board:BuildCatalog()
    self.catalog = {}
    self.spellsByKey = {}

    for savedKey, saved in pairs(Addon.db.customSpells) do
        local spellID = tonumber(saved.id or savedKey)
        if spellID then
            saved.category = NormalizeCategory(saved.category)
            local spell = self:BuildCustomSpell(spellID, saved)
            if spell then
                table.insert(self.catalog, spell)
                self.spellsByKey[spell.key] = spell
            end
        end
    end
end

function Board:AddCustomSpell(spellID, category)
    local name = GetSpellInfo(spellID)
    if not name then
        Addon:Print("Spell ID " .. tostring(spellID) .. " is not available in the client.")
        return false
    end

    local savedKey = tostring(spellID)
    Addon.db.customSpells[savedKey] = {
        id = spellID,
        category = NormalizeCategory(category),
    }

    local key = "spell:" .. savedKey
    local spell = self:BuildCustomSpell(spellID, Addon.db.customSpells[savedKey])
    local existing = self.spellsByKey[key]
    if existing then
        for field, value in pairs(spell) do
            existing[field] = value
        end
        local card = self.cards[key]
        card.spell = existing
        card.icon:SetTexture(existing.icon)
        card.label:SetText(existing.name)
    else
        table.insert(self.catalog, spell)
        self.spellsByKey[key] = spell
        self.cards[key] = self:CreateCard(spell)
        table.insert(self.state.U, key)
    end

    self:SortPool()
    self:SaveState()
    self:Layout()
    Addon:Print(name .. " added to the Pool.")
    return true
end

function Board:DeleteCustomSpell(spell)
    if not spell or not spell.custom or not spell.spellID then
        return
    end

    local key = spell.key
    Addon.db.customSpells[tostring(spell.spellID)] = nil

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

    self:SaveState()
    self:Layout()
    Addon:Print(spell.name .. " deleted. Add ID " .. tostring(spell.spellID) .. " again to restore it.")
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

    for _, tier in ipairs(Addon.tierOrder) do
        local saved = Addon.db.board[tier]
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
    self:SaveState()
end

function Board:SaveState()
    Addon.db.board = {}
    for _, tier in ipairs(Addon.tierOrder) do
        Addon.db.board[tier] = {}
        for index, key in ipairs(self.state[tier]) do
            Addon.db.board[tier][index] = key
        end
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
        self:SaveState()
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
        GameTooltip:AddLine("Drag to another row or position.", 0.55, 0.9, 0.55)
        GameTooltip:AddLine("Right-click for spell options.", 0.85, 0.70, 0.35)
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

    local color = TIER_COLORS[tier]
    local tierLabel = CreateFrame("Frame", nil, row)
    tierLabel:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -4)
    tierLabel:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 4)
    tierLabel:SetWidth(54)
    SetBackdrop(tierLabel, { color[1], color[2], color[3], 0.95 }, { color[1], color[2], color[3], 1 })

    local text = tierLabel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    text:SetPoint("CENTER")
    text:SetText(TIER_NAMES[tier])
    if tier == "U" then
        text:SetFontObject(GameFontNormalLarge)
        text:SetText("POOL")
    end

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

    local color = TIER_COLORS.U
    local tierLabel = CreateFrame("Frame", nil, row)
    tierLabel:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -4)
    tierLabel:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 4)
    tierLabel:SetWidth(54)
    SetBackdrop(tierLabel, { color[1], color[2], color[3], 0.95 }, { color[1], color[2], color[3], 1 })

    local text = tierLabel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    text:SetPoint("CENTER")
    text:SetText("POOL")

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
    bar:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 16, -77)
    bar:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -16, -77)
    bar:SetHeight(25)

    local searchLabel = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    searchLabel:SetPoint("LEFT", bar, "LEFT", 2, 0)
    searchLabel:SetText("Search")

    local searchBox = CreateFrame("EditBox", nil, bar, "InputBoxTemplate")
    searchBox:SetWidth(190)
    searchBox:SetHeight(22)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 11, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(60)

    local categoryLabel = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    categoryLabel:SetPoint("LEFT", searchBox, "RIGHT", 18, 0)
    categoryLabel:SetText("Category")

    local categoryDropdown = CreateFrame("Frame", "ActuallyCategoryFilterDropdown", bar, "UIDropDownMenuTemplate")
    categoryDropdown:SetPoint("LEFT", categoryLabel, "RIGHT", -13, -2)
    UIDropDownMenu_SetWidth(categoryDropdown, 125)
    UIDropDownMenu_SetText(categoryDropdown, "All")
    bar.categoryIndex = 1

    local clearButton = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    clearButton:SetWidth(72)
    clearButton:SetHeight(22)
    clearButton:SetPoint("LEFT", categoryDropdown, "RIGHT", -7, 2)
    clearButton:SetText("Clear")

    local countText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    self.filterCountText = countText

    local function RefreshFilters()
        self.searchText = string.lower(searchBox:GetText() or "")
        self.filterCategory = FILTER_CATEGORIES[bar.categoryIndex]
        if self.rankedArea then
            self.rankedArea.bar:SetValue(0)
        end
        if self.poolArea then
            self.poolArea.bar:SetValue(0)
        end
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

    UIDropDownMenu_Initialize(categoryDropdown, function(dropdown, level)
        for index, category in ipairs(FILTER_CATEGORIES) do
            local selectedIndex = index
            local selectedCategory = category
            local info = UIDropDownMenu_CreateInfo()
            info.text = selectedCategory
            info.value = selectedCategory
            info.checked = bar.categoryIndex == selectedIndex
            info.func = function()
                bar.categoryIndex = selectedIndex
                UIDropDownMenu_SetSelectedValue(categoryDropdown, selectedCategory)
                UIDropDownMenu_SetText(categoryDropdown, selectedCategory)
                CloseDropDownMenus()
                RefreshFilters()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetSelectedValue(categoryDropdown, "All")

    clearButton:SetScript("OnClick", function()
        bar.categoryIndex = 1
        UIDropDownMenu_SetSelectedValue(categoryDropdown, "All")
        UIDropDownMenu_SetText(categoryDropdown, "All")
        searchBox:SetText("")
        RefreshFilters()
    end)

    self.searchText = ""
    self.filterCategory = "All"
    self.filterBar = bar
end

function Board:CreateContextMenu()
    local menu = CreateFrame("Frame", "ActuallySpellContextMenu", UIParent, "UIDropDownMenuTemplate")

    StaticPopupDialogs.ACTUALLY_DELETE_SPELL = {
        text = "Delete %s from actually?",
        button1 = YES,
        button2 = NO,
        OnAccept = function(dialog, spell)
            Board:DeleteCustomSpell(spell)
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
    }

    UIDropDownMenu_Initialize(menu, function(dropdown, level)
        local spell = Board.contextSpell
        if not spell then
            return
        end

        local title = UIDropDownMenu_CreateInfo()
        title.text = spell.name
        title.isTitle = true
        title.notCheckable = true
        UIDropDownMenu_AddButton(title, level)

        local delete = UIDropDownMenu_CreateInfo()
        delete.text = "Delete Spell"
        delete.notCheckable = true
        delete.disabled = not spell.custom
        delete.colorCode = "|cffff5555"
        delete.func = function()
            CloseDropDownMenus()
            StaticPopup_Show("ACTUALLY_DELETE_SPELL", spell.name, nil, spell)
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
    editor.input = input

    local preview = CreateFrame("Button", nil, editor)
    preview:SetWidth(42)
    preview:SetHeight(42)
    preview:SetPoint("TOPRIGHT", editor, "TOPRIGHT", -22, -50)
    local previewIcon = preview:CreateTexture(nil, "ARTWORK")
    previewIcon:SetAllPoints(preview)
    previewIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    previewIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    editor.previewIcon = previewIcon

    local previewName = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    previewName:SetPoint("TOPLEFT", editor, "TOPLEFT", 18, -91)
    previewName:SetPoint("RIGHT", preview, "LEFT", -10, 0)
    previewName:SetJustifyH("LEFT")
    previewName:SetText("Enter an ID to preview it")
    editor.previewName = previewName

    local categoryLabel = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    categoryLabel:SetPoint("TOPLEFT", editor, "TOPLEFT", 18, -128)
    categoryLabel:SetText("Category")

    local categoryDropdown = CreateFrame("Frame", "ActuallyAddSpellCategoryDropdown", editor, "UIDropDownMenuTemplate")
    categoryDropdown:SetPoint("LEFT", categoryLabel, "RIGHT", -13, -2)
    UIDropDownMenu_SetWidth(categoryDropdown, 140)
    editor.categoryIndex = #CUSTOM_CATEGORIES
    UIDropDownMenu_Initialize(categoryDropdown, function(dropdown, level)
        for index, category in ipairs(CUSTOM_CATEGORIES) do
            local selectedIndex = index
            local selectedCategory = category
            local info = UIDropDownMenu_CreateInfo()
            info.text = selectedCategory
            info.value = selectedCategory
            info.checked = editor.categoryIndex == selectedIndex
            info.func = function()
                editor.categoryIndex = selectedIndex
                UIDropDownMenu_SetSelectedValue(categoryDropdown, selectedCategory)
                UIDropDownMenu_SetText(categoryDropdown, selectedCategory)
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetSelectedValue(categoryDropdown, CUSTOM_CATEGORIES[editor.categoryIndex])
    UIDropDownMenu_SetText(categoryDropdown, CUSTOM_CATEGORIES[editor.categoryIndex])

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
        if editor.spellID and Board:AddCustomSpell(editor.spellID, CUSTOM_CATEGORIES[editor.categoryIndex]) then
            editor:Hide()
        end
    end)

    editor:SetScript("OnShow", function()
        editor.categoryIndex = #CUSTOM_CATEGORIES
        UIDropDownMenu_SetSelectedValue(categoryDropdown, CUSTOM_CATEGORIES[editor.categoryIndex])
        UIDropDownMenu_SetText(categoryDropdown, CUSTOM_CATEGORIES[editor.categoryIndex])
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
    if self.spellEditor then
        self.spellEditor:Show()
    end
end

function Board:Create()
    if self.frame then
        return
    end

    self:BuildCatalog()

    local frame = CreateFrame("Frame", "ActuallyTierBoardFrame", UIParent)
    frame:SetWidth(980)
    frame:SetHeight(710)
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

    local headerBadge = CreateFrame("Frame", nil, frame)
    headerBadge:SetWidth(64)
    headerBadge:SetHeight(64)
    headerBadge:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -5)

    local badgeIcon = headerBadge:CreateTexture(nil, "ARTWORK")
    badgeIcon:SetWidth(60)
    badgeIcon:SetHeight(60)
    badgeIcon:SetPoint("CENTER")
    badgeIcon:SetTexture("Interface\\AddOns\\actually\\Textures\\NerdFace")
    badgeIcon:SetTexCoord(0, 1, 0, 1)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 80, -24)
    title:SetText("Cache Abiity Tier List")

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("LEFT", title, "RIGHT", 12, 0)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)

    local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    reset:SetWidth(90)
    reset:SetHeight(22)
    reset:SetPoint("TOPRIGHT", close, "TOPLEFT", -4, -2)
    reset:SetText("Reset Board")
    reset:SetScript("OnClick", function()
        Addon:ResetBoard()
    end)

    local addSpell = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addSpell:SetWidth(90)
    addSpell:SetHeight(22)
    addSpell:SetPoint("RIGHT", reset, "LEFT", -5, 0)
    addSpell:SetText("Add Spell")
    addSpell:SetScript("OnClick", function()
        Board:ShowSpellEditor()
    end)

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
    self:CreateContextMenu()
    self:Layout()
    self:CreateSpellEditor()
    frame:Hide()
end
