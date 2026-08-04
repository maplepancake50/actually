local ARC = Actually.Modules.RaidCooldowns
local ComboConfig = ARC:NewModule("ComboConfig")

local PAGE_SIZE = 10
local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function setBackdrop(frame, background, border)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(background[1], background[2], background[3], background[4] or 1)
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

local function trim(value)
    return string.match(tostring(value or ""), "^%s*(.-)%s*$")
end

local function normalizedName(value)
    return string.lower(trim(value))
end

local function newID()
    local epoch = time and time() or 0
    return "combo:" .. tostring(epoch) .. ":" .. tostring(math.random(100000, 999999))
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, tonumber(value) or minimum))
end

local function sortedSpellIDs(filter)
    local ids = {}
    filter = string.lower(trim(filter))
    for spellID, entry in pairs(ARC.Registry.entries or {}) do
        if entry.valid then
            local name = ARC.SpellInfo:ResolveSpellName(spellID)
            local haystack = string.lower(tostring(name) .. " " .. tostring(spellID)
                .. " " .. tostring(entry.category or ""))
            if filter == "" or string.find(haystack, filter, 1, true) then
                table.insert(ids, spellID)
            end
        end
    end
    table.sort(ids, function(left, right)
        local leftName = string.lower(ARC.SpellInfo:ResolveSpellName(left))
        local rightName = string.lower(ARC.SpellInfo:ResolveSpellName(right))
        if leftName ~= rightName then return leftName < rightName end
        return left < right
    end)
    return ids
end

local function createButton(parent, width, text)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetWidth(width)
    button:SetHeight(24)
    button:SetText(text)
    return button
end

local function createEditBox(parent, width)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetWidth(width)
    box:SetHeight(22)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetTextInsets(6, 6, 0, 0)
    setBackdrop(box, { 0.005, 0.012, 0.020, 0.98 }, { 0.16, 0.45, 0.64, 0.95 })
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return box
end

function ComboConfig:GetCombos()
    local combos = ARC.db.profile.timedCombos
    if type(combos) ~= "table" then
        combos = {}
        ARC.db.profile.timedCombos = combos
    end
    for _, combo in ipairs(combos) do
        if type(combo) == "table" then
            if not combo.id then combo.id = newID() end
            if type(combo.actions) ~= "table" then combo.actions = {} end
            combo.leadTime = clamp(combo.leadTime or 5, 2, 15)
        end
    end
    return combos
end

function ComboConfig:SetName(value)
    self.refreshing = true
    self.nameBox:SetText(tostring(value or ""))
    self.nameBox:SetCursorPosition(0)
    self.refreshing = false
end

function ComboConfig:SetLead(value)
    self.refreshing = true
    self.leadBox:SetText(string.format("%.1f", clamp(value or 5, 2, 15)))
    self.refreshing = false
end

function ComboConfig:NewCombo()
    self.editingIndex = nil
    self.selected = {}
    self.page = 1
    self:SetName("")
    self:SetLead(5)
    self:Refresh()
end

function ComboConfig:LoadCombo(index)
    local combos = self:GetCombos()
    if table.getn(combos) == 0 then return self:NewCombo() end
    index = math.max(1, math.min(tonumber(index) or 1, table.getn(combos)))
    local combo = combos[index]
    self.editingIndex = index
    self.selected = {}
    for _, action in ipairs(combo.actions or {}) do
        local spellID = ARC.Registry:Canonicalize(action.spellID)
        if spellID then self.selected[spellID] = tonumber(action.offset) or 0 end
    end
    self.page = 1
    self:SetName(combo.name or "")
    self:SetLead(combo.leadTime or 5)
    self:Refresh()
end

function ComboConfig:GetActions()
    local actions = {}
    for _, spellID in ipairs(sortedSpellIDs("")) do
        if self.selected[spellID] ~= nil then
            table.insert(actions, {
                spellID = spellID,
                offset = clamp(self.selected[spellID], -10, 10),
            })
        end
    end
    return actions
end

function ComboConfig:Save()
    if not ARC:RequireConfigurationAuthority() then return false end
    local name = trim(self.nameBox:GetText())
    if name == "" then ARC:Print("enter a name for the timed combo") return false end
    local actions = self:GetActions()
    if table.getn(actions) == 0 then
        ARC:Print("select at least one spell for the timed combo")
        return false
    end
    if table.getn(actions) > ARC.Constants.MAX_COMBO_ACTIONS then
        ARC:Print("timed combos can contain at most "
            .. tostring(ARC.Constants.MAX_COMBO_ACTIONS) .. " actions")
        return false
    end
    local leadTime = clamp(self.leadBox:GetText(), 2, 15)
    for _, action in ipairs(actions) do
        if leadTime + action.offset < 1 then
            ARC:Print(ARC.SpellInfo:ResolveSpellName(action.spellID)
                .. " would receive less than one second of notice")
            return false
        end
    end

    local combos = self:GetCombos()
    if not self.editingIndex
        and table.getn(combos) >= ARC.Constants.MAX_TIMED_COMBOS then
        ARC:Print("timed combo limit reached: maximum "
            .. tostring(ARC.Constants.MAX_TIMED_COMBOS))
        return false
    end
    for index, other in ipairs(combos) do
        if index ~= self.editingIndex and normalizedName(other.name) == normalizedName(name) then
            ARC:Print("a timed combo named " .. name .. " already exists")
            return false
        end
    end
    local combo = self.editingIndex and combos[self.editingIndex] or nil
    if not combo then
        combo = { id = newID() }
        table.insert(combos, combo)
        self.editingIndex = table.getn(combos)
    end
    combo.name = name
    combo.leadTime = leadTime
    combo.actions = actions
    self:SetLead(leadTime)
    ARC:Print("saved timed combo " .. name .. " (" .. tostring(table.getn(actions))
        .. " actions)")
    self:Refresh()
    if ARC.Commander and ARC.Commander.Refresh then ARC.Commander:Refresh() end
    return combo
end

function ComboConfig:Delete()
    if not ARC:RequireConfigurationAuthority() then return false end
    local combos = self:GetCombos()
    local combo = self.editingIndex and combos[self.editingIndex]
    if not combo then return false end
    if ARC.Combos and ARC.Combos.active
        and ARC.Combos.active.definitionID == tostring(combo.id) then
        ARC:Print("cancel the active timed combo before deleting it")
        return false
    end
    local name = combo.name
    table.remove(combos, self.editingIndex)
    ARC:Print("deleted timed combo " .. tostring(name))
    if table.getn(combos) > 0 then
        self:LoadCombo(math.min(self.editingIndex, table.getn(combos)))
    else
        self:NewCombo()
    end
    if ARC.Commander and ARC.Commander.Refresh then ARC.Commander:Refresh() end
    return true
end

function ComboConfig:CreateRow(index)
    local row = CreateFrame("Frame", nil, self.list)
    row:SetHeight(43)
    row:SetPoint("TOPLEFT", self.list, "TOPLEFT", 5, -5 - (index - 1) * 45)
    row:SetPoint("RIGHT", self.list, "RIGHT", -5, 0)
    setBackdrop(row, { 0.008, 0.018, 0.028, 0.95 }, { 0.10, 0.27, 0.38, 0.90 })

    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetPoint("LEFT", row, "LEFT", 5, 0)
    row.check:SetWidth(25)
    row.check:SetHeight(25)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("LEFT", row.check, "RIGHT", 3, 0)
    row.icon:SetWidth(31)
    row.icon:SetHeight(31)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -4)
    row.name:SetPoint("RIGHT", row, "RIGHT", -125, 0)
    row.name:SetJustifyH("LEFT")

    row.meta = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.meta:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 3)
    row.meta:SetPoint("RIGHT", row, "RIGHT", -125, 0)
    row.meta:SetJustifyH("LEFT")
    row.meta:SetTextColor(0.35, 0.70, 0.88)

    row.offsetLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.offsetLabel:SetPoint("RIGHT", row, "RIGHT", -67, 0)
    row.offsetLabel:SetText("Offset")

    row.offset = createEditBox(row, 55)
    row.offset:SetPoint("RIGHT", row, "RIGHT", -7, 0)
    row.offset:SetJustifyH("CENTER")

    row.check:SetScript("OnClick", function(button)
        if ComboConfig.refreshing or not row.spellID then return end
        if button:GetChecked() then
            ComboConfig.selected[row.spellID] = tonumber(row.offset:GetText()) or 0
        else
            ComboConfig.selected[row.spellID] = nil
        end
        ComboConfig:RefreshStatus()
    end)
    row.offset:SetScript("OnTextChanged", function(box)
        if ComboConfig.refreshing or not row.spellID or not row.check:GetChecked() then return end
        ComboConfig.selected[row.spellID] = tonumber(box:GetText()) or 0
        ComboConfig:RefreshStatus()
    end)
    row.offset:SetScript("OnEditFocusLost", function(box)
        local value = clamp(box:GetText(), -10, 10)
        box:SetText(string.format("%.1f", value))
        if row.spellID and row.check:GetChecked() then
            ComboConfig.selected[row.spellID] = value
        end
        ComboConfig:RefreshStatus()
    end)
    self.rows[index] = row
end

function ComboConfig:RefreshStatus()
    local combos = self:GetCombos()
    local count = table.getn(combos)
    if self.editingIndex and combos[self.editingIndex] then
        self.comboText:SetText("Combo " .. tostring(self.editingIndex) .. "/" .. tostring(count))
        self.save:SetText("Save Changes")
        self.delete:Show()
    else
        self.comboText:SetText("New combo  (" .. tostring(count) .. " saved)")
        self.save:SetText("Create Combo")
        self.delete:Hide()
    end
    local selected = table.getn(self:GetActions())
    self.selectedText:SetText(tostring(selected) .. "/" .. tostring(ARC.Constants.MAX_COMBO_ACTIONS)
        .. " actions selected")
end

function ComboConfig:Refresh()
    if not self.frame then return end
    local ids = sortedSpellIDs(self.searchBox:GetText())
    local pageCount = math.max(1, math.ceil(table.getn(ids) / PAGE_SIZE))
    self.page = math.max(1, math.min(self.page or 1, pageCount))
    local startIndex = (self.page - 1) * PAGE_SIZE + 1
    self.refreshing = true
    for rowIndex = 1, PAGE_SIZE do
        local row = self.rows[rowIndex]
        local spellID = ids[startIndex + rowIndex - 1]
        row.spellID = spellID
        if spellID then
            local entry = ARC.Registry:Get(spellID)
            row.icon:SetTexture(ARC.SpellInfo:ResolveSpellIcon(spellID))
            row.name:SetText(ARC.SpellInfo:ResolveSpellName(spellID))
            row.meta:SetText("ID " .. tostring(spellID) .. "  |  "
                .. tostring(entry and entry.category or "cooldown"))
            row.check:SetChecked(self.selected[spellID] ~= nil)
            row.offset:SetText(string.format("%.1f", tonumber(self.selected[spellID]) or 0))
            row:Show()
        else
            row:Hide()
        end
    end
    self.refreshing = false
    self.pageText:SetText("Spells " .. tostring(self.page) .. "/" .. tostring(pageCount))
    if self.page > 1 then self.prevPage:Enable() else self.prevPage:Disable() end
    if self.page < pageCount then self.nextPage:Enable() else self.nextPage:Disable() end
    local combos = self:GetCombos()
    if self.editingIndex and self.editingIndex > 1 then self.prevCombo:Enable()
    else self.prevCombo:Disable() end
    if (self.editingIndex and self.editingIndex < table.getn(combos))
        or (not self.editingIndex and table.getn(combos) > 0) then self.nextCombo:Enable()
    else self.nextCombo:Disable() end
    self:RefreshStatus()
end

function ComboConfig:Initialize()
    self.selected = {}
    self.page = 1
    self.rows = {}
    local profile = ARC.db.profile.comboUI
    local frame = CreateFrame("Frame", "ActuallyARCComboConfigFrame", UIParent)
    frame:SetWidth(610)
    frame:SetHeight(665)
    frame:SetPoint(profile.point or "CENTER", UIParent, profile.point or "CENTER",
        profile.x or 0, profile.y or 0)
    frame:SetScale(clamp(profile.scale or 1, 0.70, 1.25))
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(owner) owner:StartMoving() end)
    frame:SetScript("OnDragStop", function(owner)
        owner:StopMovingOrSizing()
        local point, _, _, x, y = owner:GetPoint(1)
        profile.point, profile.x, profile.y = point, x, y
    end)
    setBackdrop(frame, { 0.010, 0.020, 0.032, 0.99 }, { 0.20, 0.70, 0.96, 1 })
    self.frame = frame

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -13)
    frame.title:SetText("ARC Timed Combos - " .. ARC.Constants.WIP_TEXT)
    frame.title:SetTextColor(0.92, 0.96, 1.00)

    frame.subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -5)
    frame.subtitle:SetText(
        "ARC replaces unavailable players during preflight, then freezes assignments for the countdown.")
    frame.subtitle:SetTextColor(0.48, 0.72, 0.84)

    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    self.prevCombo = createButton(frame, 52, "Prev")
    self.prevCombo:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -62)
    self.nextCombo = createButton(frame, 52, "Next")
    self.nextCombo:SetPoint("LEFT", self.prevCombo, "RIGHT", 5, 0)
    self.comboText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.comboText:SetPoint("LEFT", self.nextCombo, "RIGHT", 9, 0)

    local nameLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameLabel:SetPoint("TOPLEFT", self.prevCombo, "BOTTOMLEFT", 0, -12)
    nameLabel:SetText("Combo name:")
    self.nameBox = createEditBox(frame, 330)
    self.nameBox:SetPoint("LEFT", nameLabel, "RIGHT", 8, 0)

    local leadLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    leadLabel:SetPoint("LEFT", self.nameBox, "RIGHT", 13, 0)
    leadLabel:SetText("Countdown:")
    self.leadBox = createEditBox(frame, 50)
    self.leadBox:SetPoint("LEFT", leadLabel, "RIGHT", 6, 0)
    self.leadBox:SetJustifyH("CENTER")
    local seconds = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    seconds:SetPoint("LEFT", self.leadBox, "RIGHT", 5, 0)
    seconds:SetText("sec")
    self.leadBox:SetScript("OnEditFocusLost", function(box)
        box:SetText(string.format("%.1f", clamp(box:GetText(), 2, 15)))
        ComboConfig:RefreshStatus()
    end)

    local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    searchLabel:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -14)
    searchLabel:SetText("Search:")
    self.searchBox = createEditBox(frame, 430)
    self.searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 8, 0)
    self.searchBox:SetScript("OnTextChanged", function()
        if ComboConfig.refreshing then return end
        ComboConfig.page = 1
        ComboConfig:Refresh()
    end)

    self.selectedText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.selectedText:SetPoint("LEFT", self.searchBox, "RIGHT", 9, 0)
    self.selectedText:SetTextColor(0.35, 0.85, 1.00)

    self.list = CreateFrame("Frame", nil, frame)
    self.list:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -140)
    self.list:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
    self.list:SetHeight(460)
    setBackdrop(self.list, { 0.004, 0.010, 0.018, 0.98 }, { 0.12, 0.39, 0.56, 1 })
    for index = 1, PAGE_SIZE do self:CreateRow(index) end

    self.prevPage = createButton(frame, 52, "Prev")
    self.prevPage:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 49)
    self.nextPage = createButton(frame, 52, "Next")
    self.nextPage:SetPoint("LEFT", self.prevPage, "RIGHT", 5, 0)
    self.pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.pageText:SetPoint("LEFT", self.nextPage, "RIGHT", 9, 0)

    self.new = createButton(frame, 90, "New Combo")
    self.new:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 14)
    self.save = createButton(frame, 110, "Create Combo")
    self.save:SetPoint("LEFT", self.new, "RIGHT", 7, 0)
    self.delete = createButton(frame, 100, "Delete Combo")
    self.delete:SetPoint("LEFT", self.save, "RIGHT", 7, 0)

    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 20)
    note:SetWidth(260)
    note:SetJustifyH("RIGHT")
    note:SetText("Offset -1.0 = 1 sec before anchor.\n"
        .. "Same player requires a 1.5 sec gap. No replacements after GO.")
    note:SetTextColor(0.55, 0.68, 0.76)

    self.prevCombo:SetScript("OnClick", function()
        if ComboConfig.editingIndex and ComboConfig.editingIndex > 1 then
            ComboConfig:LoadCombo(ComboConfig.editingIndex - 1)
        end
    end)
    self.nextCombo:SetScript("OnClick", function()
        local combos = ComboConfig:GetCombos()
        if not ComboConfig.editingIndex and table.getn(combos) > 0 then
            ComboConfig:LoadCombo(1)
        elseif ComboConfig.editingIndex and ComboConfig.editingIndex < table.getn(combos) then
            ComboConfig:LoadCombo(ComboConfig.editingIndex + 1)
        end
    end)
    self.prevPage:SetScript("OnClick", function()
        ComboConfig.page = math.max(1, ComboConfig.page - 1)
        ComboConfig:Refresh()
    end)
    self.nextPage:SetScript("OnClick", function()
        ComboConfig.page = ComboConfig.page + 1
        ComboConfig:Refresh()
    end)
    self.new:SetScript("OnClick", function() ComboConfig:NewCombo() end)
    self.save:SetScript("OnClick", function() ComboConfig:Save() end)
    self.delete:SetScript("OnClick", function() ComboConfig:Delete() end)

    local combos = self:GetCombos()
    if table.getn(combos) > 0 then self:LoadCombo(1) else self:NewCombo() end
    frame:Hide()
end

function ComboConfig:Show()
    if ARC.OfficerConfig and ARC.OfficerConfig.frame then
        return ARC.OfficerConfig:Show("combos")
    end
    if not ARC:RequireConfigurationAuthority() then return false end
    self:Refresh()
    self.frame:Show()
    return true
end

function ComboConfig:Toggle()
    if ARC.OfficerConfig and ARC.OfficerConfig.frame then
        return ARC.OfficerConfig:Toggle("combos")
    end
    if self.frame:IsShown() then self.frame:Hide() return false end
    return self:Show()
end
