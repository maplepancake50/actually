Actually = Actually or {}
local Addon = Actually

local BatchCapture = { queue = {}, byID = {}, rows = {} }
Addon.BatchCapture = BatchCapture

local MAX_QUEUE_SIZE = 100
local ROW_HEIGHT = 44
local SetBackdrop = Addon.Util.SetBackdrop

local function Categories()
    return Addon.Board:GetSpellCategories()
end

local function SetDropdownSelection(dropdown, value)
    UIDropDownMenu_SetSelectedValue(dropdown, value)
    UIDropDownMenu_SetText(dropdown, value)
end

function BatchCapture:SetStatus(message, errorColor)
    if not self.status then
        return
    end
    self.status:SetText(message or "")
    if errorColor then
        self.status:SetTextColor(1, 0.35, 0.35)
    else
        self.status:SetTextColor(0.55, 0.85, 1)
    end
end

function BatchCapture:QueueSpell(spellID)
    spellID = tonumber(spellID)
    if not spellID or self.byID[spellID] or Addon.db.customSpells[tostring(spellID)] then
        return false
    end
    if #self.queue >= MAX_QUEUE_SIZE then
        return false
    end

    local name, rank, icon = GetSpellInfo(spellID)
    if not name then
        return false
    end
    local categories = Categories()
    local entry = {
        spellID = spellID,
        name = rank and rank ~= "" and (name .. " (" .. rank .. ")") or name,
        icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
        category = categories[self.defaultCategoryIndex or #categories],
        coa = self.defaultCOA == true,
    }
    table.insert(self.queue, entry)
    self.byID[spellID] = entry
    return true
end

function BatchCapture:CaptureText(text)
    text = tostring(text or "")
    local ids = {}
    local found = {}
    for idText in string.gmatch(text, "spell:(%d+)") do
        local spellID = tonumber(idText)
        if spellID and not found[spellID] then
            found[spellID] = true
            table.insert(ids, spellID)
        end
    end
    if #ids == 0 and not string.find(text, "item:", 1, true) then
        for idText in string.gmatch(text, "%d+") do
            local spellID = tonumber(idText)
            if spellID and not found[spellID] then
                found[spellID] = true
                table.insert(ids, spellID)
            end
        end
    end

    local added = 0
    for _, spellID in ipairs(ids) do
        if self:QueueSpell(spellID) then
            added = added + 1
        end
    end
    if #ids > 0 then
        self:SetStatus(
            added > 0 and ("Queued " .. tostring(added) .. " spell(s).")
                or "Those spells are already queued, already added, or unavailable.",
            added == 0
        )
        self:Refresh()
    end
    return added, #ids
end

function BatchCapture:RemoveEntry(entry)
    for index = #self.queue, 1, -1 do
        if self.queue[index] == entry then
            table.remove(self.queue, index)
            break
        end
    end
    self.byID[entry.spellID] = nil
    self:Refresh()
end

function BatchCapture:Clear()
    self.queue = {}
    self.byID = {}
    self:SetStatus("Queue cleared.")
    self:Refresh()
end

function BatchCapture:GetRow(index)
    if self.rows[index] then
        return self.rows[index]
    end
    local row = CreateFrame("Frame", nil, self.scrollChild)
    row:SetWidth(624)
    row:SetHeight(40)
    SetBackdrop(row, { 0.04, 0.045, 0.06, 0.92 }, { 0.16, 0.24, 0.32, 1 })

    local iconButton = CreateFrame("Button", nil, row)
    iconButton:SetWidth(34)
    iconButton:SetHeight(34)
    iconButton:SetPoint("LEFT", row, "LEFT", 4, 0)
    local icon = iconButton:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(iconButton)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = icon

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    name:SetPoint("LEFT", iconButton, "RIGHT", 8, 7)
    name:SetWidth(275)
    name:SetJustifyH("LEFT")
    row.name = name

    local idText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    idText:SetPoint("LEFT", iconButton, "RIGHT", 8, -9)
    idText:SetWidth(275)
    idText:SetJustifyH("LEFT")
    idText:SetTextColor(0.55, 0.65, 0.75)
    row.idText = idText

    local category = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    category:SetWidth(105)
    category:SetHeight(22)
    category:SetPoint("LEFT", row, "LEFT", 330, 0)
    category:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    category:SetScript("OnClick", function(_, button)
        local entry = row.entry
        if not entry then return end
        local categories = Categories()
        local selected = 1
        for categoryIndex, value in ipairs(categories) do
            if value == entry.category then selected = categoryIndex break end
        end
        selected = button == "RightButton" and (selected - 1) or (selected + 1)
        if selected < 1 then selected = #categories elseif selected > #categories then selected = 1 end
        entry.category = categories[selected]
        category:SetText(entry.category)
    end)
    category:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Category", 1, 0.82, 0.2)
        GameTooltip:AddLine("Left-click forwards; right-click backwards.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    category:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.category = category

    local coa = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    coa:SetWidth(24)
    coa:SetHeight(24)
    coa:SetPoint("LEFT", category, "RIGHT", 15, 0)
    coa:SetScript("OnClick", function(self)
        if row.entry then row.entry.coa = self:GetChecked() and true or false end
    end)
    row.coa = coa
    local coaLabel = coa:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    coaLabel:SetPoint("LEFT", coa, "RIGHT", 0, 1)
    coaLabel:SetText("COA")

    local remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    remove:SetWidth(28)
    remove:SetHeight(22)
    remove:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    remove:SetText("X")
    remove:SetScript("OnClick", function()
        if row.entry then BatchCapture:RemoveEntry(row.entry) end
    end)

    iconButton:SetScript("OnEnter", function(self)
        if not row.entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("spell:" .. tostring(row.entry.spellID))
        GameTooltip:Show()
    end)
    iconButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.rows[index] = row
    return row
end

function BatchCapture:Refresh()
    if not self.frame then return end
    for index, entry in ipairs(self.queue) do
        local row = self:GetRow(index)
        row.entry = entry
        row:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
        row.icon:SetTexture(entry.icon)
        row.name:SetText(entry.name)
        row.idText:SetText("Spell ID " .. tostring(entry.spellID))
        row.category:SetText(entry.category)
        row.coa:SetChecked(entry.coa == true)
        row:Show()
    end
    for index = #self.queue + 1, #self.rows do
        self.rows[index].entry = nil
        self.rows[index]:Hide()
    end
    self.scrollChild:SetHeight(math.max(1, #self.queue * ROW_HEIGHT))
    self.countText:SetText(tostring(#self.queue) .. " / " .. tostring(MAX_QUEUE_SIZE) .. " queued")
    if #self.queue > 0 then self.addAllButton:Enable() else self.addAllButton:Disable() end
end

function BatchCapture:InstallLinkCapture()
    if self.linkCaptureInstalled or type(ChatEdit_InsertLink) ~= "function" then
        return
    end
    self.linkCaptureInstalled = true
    self.originalInsertLink = ChatEdit_InsertLink
    ChatEdit_InsertLink = function(link)
        if BatchCapture.frame and BatchCapture.frame:IsShown() then
            local _, recognized = BatchCapture:CaptureText(link)
            if recognized > 0 then
                return true
            end
        end
        return BatchCapture.originalInsertLink(link)
    end
end

function BatchCapture:Create()
    if self.frame then return end
    local parent = Addon.Board.frame or UIParent
    local frame = CreateFrame("Frame", "ActuallyBatchCaptureFrame", parent)
    frame:SetWidth(700)
    frame:SetHeight(520)
    frame:SetPoint("CENTER", parent, "CENTER", 0, 20)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    SetBackdrop(frame, { 0.025, 0.03, 0.045, 0.995 }, { 0.25, 0.65, 0.90, 1 })
    frame:Hide()
    self.frame = frame

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -16)
    title:SetText("Batch Capture")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    local instructions = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    instructions:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -45)
    instructions:SetWidth(660)
    instructions:SetJustifyH("LEFT")
    instructions:SetText("While this window is open, Shift-click spell links to queue them. You can also paste links or IDs below.")

    local input = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    input:SetWidth(455)
    input:SetHeight(24)
    input:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -78)
    input:SetAutoFocus(false)
    input:SetMaxLetters(4096)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    input:SetScript("OnEnterPressed", function(self)
        BatchCapture:CaptureText(self:GetText())
        self:SetText("")
    end)
    self.input = input

    local queueText = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    queueText:SetWidth(95)
    queueText:SetHeight(24)
    queueText:SetPoint("LEFT", input, "RIGHT", 8, 0)
    queueText:SetText("Queue Text")
    queueText:SetScript("OnClick", function()
        BatchCapture:CaptureText(input:GetText())
        input:SetText("")
    end)

    local clear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clear:SetWidth(70)
    clear:SetHeight(24)
    clear:SetPoint("LEFT", queueText, "RIGHT", 6, 0)
    clear:SetText("Clear")
    clear:SetScript("OnClick", function() BatchCapture:Clear() end)

    local defaultLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    defaultLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -116)
    defaultLabel:SetText("Defaults for new captures:")

    local dropdown = CreateFrame("Frame", "ActuallyBatchCaptureCategoryDropdown", frame, "UIDropDownMenuTemplate")
    dropdown:SetPoint("LEFT", defaultLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(dropdown, 120)
    self.defaultCategoryIndex = #Categories()
    UIDropDownMenu_Initialize(dropdown, function(_, level)
        for index, category in ipairs(Categories()) do
            local selectedIndex, selectedCategory = index, category
            local info = UIDropDownMenu_CreateInfo()
            info.text = selectedCategory
            info.value = selectedCategory
            info.checked = BatchCapture.defaultCategoryIndex == selectedIndex
            info.func = function()
                BatchCapture.defaultCategoryIndex = selectedIndex
                SetDropdownSelection(dropdown, selectedCategory)
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    SetDropdownSelection(dropdown, Categories()[self.defaultCategoryIndex])

    local defaultCOA = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    defaultCOA:SetWidth(24)
    defaultCOA:SetHeight(24)
    defaultCOA:SetPoint("LEFT", dropdown, "RIGHT", -4, 2)
    defaultCOA:SetScript("OnClick", function(self) BatchCapture.defaultCOA = self:GetChecked() and true or false end)
    local defaultCOALabel = defaultCOA:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    defaultCOALabel:SetPoint("LEFT", defaultCOA, "RIGHT", 1, 1)
    defaultCOALabel:SetText("COA")

    local applyAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    applyAll:SetWidth(105)
    applyAll:SetHeight(22)
    applyAll:SetPoint("LEFT", defaultCOALabel, "RIGHT", 14, 0)
    applyAll:SetText("Apply to All")
    applyAll:SetScript("OnClick", function()
        local category = Categories()[BatchCapture.defaultCategoryIndex]
        for _, entry in ipairs(BatchCapture.queue) do
            entry.category = category
            entry.coa = BatchCapture.defaultCOA == true
        end
        BatchCapture:Refresh()
    end)

    local scroll = CreateFrame("ScrollFrame", "ActuallyBatchCaptureScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -151)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -42, 65)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(624)
    child:SetHeight(1)
    scroll:SetScrollChild(child)
    self.scrollChild = child

    local count = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    count:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 39)
    self.countText = count
    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 18)
    status:SetWidth(470)
    status:SetJustifyH("LEFT")
    self.status = status

    local addAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addAll:SetWidth(130)
    addAll:SetHeight(27)
    addAll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 18)
    addAll:SetText("Add All to Pool")
    addAll:SetScript("OnClick", function()
        local added, unavailable = Addon.Board:AddCustomSpells(BatchCapture.queue)
        if added > 0 then
            BatchCapture:Clear()
            BatchCapture:SetStatus("Added " .. tostring(added) .. " spell(s)." .. (unavailable > 0 and (" " .. tostring(unavailable) .. " unavailable.") or ""))
        end
    end)
    self.addAllButton = addAll

    frame:SetScript("OnShow", function()
        BatchCapture:InstallLinkCapture()
        BatchCapture:SetStatus("Capture is active.")
        BatchCapture:Refresh()
    end)
    frame:SetScript("OnHide", function()
        input:ClearFocus()
        GameTooltip:Hide()
    end)
    self:Refresh()
    self:InstallLinkCapture()
end

function BatchCapture:Show()
    if not Addon:CanEditActiveList() then
        Addon:Print(Addon.OFFICIAL_LIST_NAME .. " is read-only.")
        return
    end
    self:Create()
    self.frame:Show()
end
