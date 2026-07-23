local ARC = Actually.Modules.RaidCooldowns
local SpellConfig = ARC:NewModule("SpellConfig")

local PAGE_SIZE = 8
local ROW_HEIGHT = 46
local ROW_GAP = 3

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

local function sortedRegistryIDs(filter)
    local ids = {}
    filter = string.lower(tostring(filter or ""))
    for spellID, entry in pairs(ARC.Registry.entries) do
        if entry.valid then
            local name = ARC.SpellInfo:ResolveSpellName(spellID)
            local haystack = string.lower(tostring(spellID) .. " " .. tostring(name)
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

function SpellConfig:GetSpellSettings(spellID)
    local settings = ARC.db.profile.spells[spellID]
    if type(settings) ~= "table" then
        settings = {}
        ARC.db.profile.spells[spellID] = settings
    end
    return settings
end

function SpellConfig:SetSpellEnabled(spellID, enabled)
    self:GetSpellSettings(spellID).enabled = enabled and true or false
    ARC.Renderer:MarkDirty("spell visibility")
    ARC.Renderer:Reconcile()
end

function SpellConfig:SetAll(enabled)
    for spellID, entry in pairs(ARC.Registry.entries) do
        if entry.valid then self:GetSpellSettings(spellID).enabled = enabled and true or false end
    end
    ARC.Renderer:MarkDirty("all spell visibility")
    ARC.Renderer:Reconcile()
    self:Refresh()
end

function SpellConfig:ResetAll()
    for spellID, entry in pairs(ARC.Registry.entries) do
        if entry.valid then self:GetSpellSettings(spellID).enabled = nil end
    end
    ARC.Renderer:MarkDirty("reset spell visibility")
    ARC.Renderer:Reconcile()
    self:Refresh()
end

function SpellConfig:CreateRow(index)
    local row = CreateFrame("Frame", nil, self.listPanel)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", self.listPanel, "TOPLEFT", 5,
        -5 - ((index - 1) * (ROW_HEIGHT + ROW_GAP)))
    row:SetPoint("TOPRIGHT", self.listPanel, "TOPRIGHT", -5,
        -5 - ((index - 1) * (ROW_HEIGHT + ROW_GAP)))
    setBackdrop(row, { 0.055, 0.060, 0.075, 0.96 }, { 0.18, 0.22, 0.28, 1 })

    row.accent = row:CreateTexture(nil, "ARTWORK")
    row.accent:SetWidth(3)
    row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -3)
    row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 3, 3)
    row.accent:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.accent:SetVertexColor(0.20, 0.55, 0.75, 0.9)

    row.check = CreateFrame("CheckButton", "ActuallyARCSpellConfigCheck" .. tostring(index),
        row, "UICheckButtonTemplate")
    row.check:SetWidth(24)
    row.check:SetHeight(24)
    row.check:SetPoint("LEFT", row, "LEFT", 7, 0)
    row.check:SetScript("OnClick", function(button)
        if row.spellID then
            self:SetSpellEnabled(row.spellID, button:GetChecked() and true or false)
        end
    end)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(32)
    row.icon:SetHeight(32)
    row.icon:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetJustifyH("LEFT")
    row.name:SetJustifyV("TOP")
    row.name:SetHeight(16)
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
    row.name:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.name:SetTextColor(0.92, 0.96, 1.00)

    row.meta = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.meta:SetJustifyH("LEFT")
    row.meta:SetJustifyV("BOTTOM")
    row.meta:SetHeight(14)
    row.meta:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 5)
    row.meta:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.meta:SetTextColor(0.47, 0.62, 0.72)

    self.rows[index] = row
    return row
end

function SpellConfig:Refresh()
    if not self.frame then return end
    self.filteredIDs = sortedRegistryIDs(self.search:GetText())
    local count = table.getn(self.filteredIDs)
    local pages = math.max(1, math.ceil(count / PAGE_SIZE))
    self.page = math.max(1, math.min(self.page or 1, pages))
    local first = ((self.page - 1) * PAGE_SIZE) + 1

    for index = 1, PAGE_SIZE do
        local row = self.rows[index] or self:CreateRow(index)
        local spellID = self.filteredIDs[first + index - 1]
        if spellID then
            local entry = ARC.Registry:Get(spellID)
            local settings = ARC.db.profile.spells[spellID] or {}
            row.spellID = spellID
            row.icon:SetTexture(ARC.SpellInfo:ResolveSpellIcon(spellID))
            row.name:SetText(ARC.SpellInfo:ResolveSpellName(spellID))
            row.meta:SetText("ID " .. tostring(spellID) .. "  |  "
                .. tostring(entry and entry.category or "uncategorized"))
            local enabled = settings.enabled ~= false
            row.check:SetChecked(enabled)
            if enabled then
                row.name:SetTextColor(0.92, 0.96, 1.00)
                row.meta:SetTextColor(0.47, 0.68, 0.78)
                row.accent:SetVertexColor(0.20, 0.65, 0.86, 0.95)
                row:SetBackdropColor(0.055, 0.065, 0.085, 0.98)
            else
                row.name:SetTextColor(0.48, 0.50, 0.55)
                row.meta:SetTextColor(0.32, 0.35, 0.40)
                row.accent:SetVertexColor(0.20, 0.23, 0.28, 0.65)
                row:SetBackdropColor(0.035, 0.038, 0.045, 0.94)
            end
            row:Show()
        else
            row.spellID = nil
            row:Hide()
        end
    end

    self.pageText:SetText("Page " .. tostring(self.page) .. "/" .. tostring(pages)
        .. "  (" .. tostring(count) .. " spells)")
    if self.page <= 1 then self.previous:Disable() else self.previous:Enable() end
    if self.page >= pages then self.next:Disable() else self.next:Enable() end
end

function SpellConfig:Initialize()
    self.rows = {}
    self.page = 1
    local profile = ARC.db.profile.configUI
    local frame = CreateFrame("Frame", "ActuallyARCSpellConfigFrame", UIParent)
    frame:SetWidth(500)
    frame:SetHeight(594)
    frame:SetPoint(profile.point or "CENTER", UIParent, profile.point or "CENTER",
        profile.x or 0, profile.y or 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    setBackdrop(frame, { 0.025, 0.025, 0.035, 0.985 }, { 0.20, 0.55, 0.75, 1 })
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        profile.point, profile.x, profile.y = point, x, y
    end)
    self.frame = frame

    frame.header = CreateFrame("Frame", nil, frame)
    frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -5)
    frame.header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
    frame.header:SetHeight(58)
    setBackdrop(frame.header, { 0.035, 0.045, 0.065, 0.99 }, { 0.14, 0.38, 0.52, 1 })
    frame.header:SetFrameLevel(frame:GetFrameLevel() + 10)

    frame.headerAccent = frame.header:CreateTexture(nil, "ARTWORK")
    frame.headerAccent:SetPoint("BOTTOMLEFT", frame.header, "BOTTOMLEFT", 6, 4)
    frame.headerAccent:SetPoint("BOTTOMRIGHT", frame.header, "BOTTOMRIGHT", -6, 4)
    frame.headerAccent:SetHeight(3)
    frame.headerAccent:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.headerAccent:SetVertexColor(0.20, 0.65, 0.86, 0.8)

    frame.headerContent = CreateFrame("Frame", nil, frame.header)
    frame.headerContent:SetAllPoints(frame.header)
    frame.headerContent:SetFrameLevel(frame.header:GetFrameLevel() + 10)

    frame.title = frame.headerContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.title:SetPoint("TOPLEFT", frame.headerContent, "TOPLEFT", 14, -10)
    frame.title:SetText("Actually Raid Cooldowns - " .. ARC.Constants.WIP_TEXT)
    frame.title:SetTextColor(0.92, 0.96, 1.00)

    frame.subtitle = frame.headerContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -4)
    frame.subtitle:SetText("Choose which tracked spells appear in your cooldown display")
    frame.subtitle:SetTextColor(0.52, 0.66, 0.76)

    frame.close = CreateFrame("Button", nil, frame.headerContent, "UIPanelCloseButton")
    frame.close:SetWidth(28)
    frame.close:SetHeight(28)
    frame.close:SetPoint("TOPRIGHT", frame.headerContent, "TOPRIGHT", -2, -2)
    frame.close:SetFrameLevel(frame.headerContent:GetFrameLevel() + 5)
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    frame.toolbar = CreateFrame("Frame", nil, frame)
    frame.toolbar:SetPoint("TOPLEFT", frame.header, "BOTTOMLEFT", 0, -5)
    frame.toolbar:SetPoint("TOPRIGHT", frame.header, "BOTTOMRIGHT", 0, -5)
    frame.toolbar:SetHeight(44)
    setBackdrop(frame.toolbar, { 0.040, 0.043, 0.055, 0.98 }, { 0.16, 0.19, 0.24, 1 })

    frame.searchLabel = frame.toolbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.searchLabel:SetPoint("LEFT", frame.toolbar, "LEFT", 12, 0)
    frame.searchLabel:SetText("Search:")

    self.search = CreateFrame("EditBox", nil, frame.toolbar)
    self.search:SetHeight(24)
    self.search:SetPoint("LEFT", frame.searchLabel, "RIGHT", 8, 0)
    self.search:SetPoint("RIGHT", frame.toolbar, "RIGHT", -12, 0)
    self.search:SetAutoFocus(false)
    self.search:SetFontObject(GameFontHighlightSmall)
    self.search:SetTextInsets(6, 6, 0, 0)
    setBackdrop(self.search, { 0.008, 0.012, 0.020, 0.95 }, { 0.18, 0.38, 0.50, 1 })
    self.search:SetScript("OnEscapePressed", function(editBox) editBox:ClearFocus() end)
    self.search:SetScript("OnEnterPressed", function(editBox) editBox:ClearFocus() end)
    self.search:SetScript("OnTextChanged", function()
        self.page = 1
        self:Refresh()
    end)

    self.listPanel = CreateFrame("Frame", nil, frame)
    self.listPanel:SetPoint("TOPLEFT", frame.toolbar, "BOTTOMLEFT", 0, -5)
    self.listPanel:SetPoint("TOPRIGHT", frame.toolbar, "BOTTOMRIGHT", 0, -5)
    self.listPanel:SetHeight(402)
    setBackdrop(self.listPanel, { 0.020, 0.024, 0.034, 0.98 }, { 0.14, 0.30, 0.40, 1 })

    frame.footer = CreateFrame("Frame", nil, frame)
    frame.footer:SetPoint("TOPLEFT", self.listPanel, "BOTTOMLEFT", 0, -5)
    frame.footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 5)
    setBackdrop(frame.footer, { 0.035, 0.038, 0.050, 0.99 }, { 0.14, 0.30, 0.40, 1 })

    self.previous = CreateFrame("Button", nil, frame.footer, "UIPanelButtonTemplate")
    self.previous:SetWidth(54)
    self.previous:SetHeight(22)
    self.previous:SetPoint("TOPLEFT", frame.footer, "TOPLEFT", 10, -8)
    self.previous:SetText("Prev")
    self.previous:SetScript("OnClick", function()
        self.page = self.page - 1
        self:Refresh()
    end)

    self.next = CreateFrame("Button", nil, frame.footer, "UIPanelButtonTemplate")
    self.next:SetWidth(54)
    self.next:SetHeight(22)
    self.next:SetPoint("LEFT", self.previous, "RIGHT", 5, 0)
    self.next:SetText("Next")
    self.next:SetScript("OnClick", function()
        self.page = self.page + 1
        self:Refresh()
    end)

    self.pageText = frame.footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.pageText:SetPoint("LEFT", self.next, "RIGHT", 8, 0)
    self.pageText:SetTextColor(0.62, 0.72, 0.80)

    self.showAll = CreateFrame("Button", nil, frame.footer, "UIPanelButtonTemplate")
    self.showAll:SetWidth(78)
    self.showAll:SetHeight(22)
    self.showAll:SetPoint("BOTTOMLEFT", frame.footer, "BOTTOMLEFT", 10, 8)
    self.showAll:SetText("Show All")
    self.showAll:SetScript("OnClick", function() self:SetAll(true) end)

    self.hideAll = CreateFrame("Button", nil, frame.footer, "UIPanelButtonTemplate")
    self.hideAll:SetWidth(78)
    self.hideAll:SetHeight(22)
    self.hideAll:SetPoint("LEFT", self.showAll, "RIGHT", 6, 0)
    self.hideAll:SetText("Hide All")
    self.hideAll:SetScript("OnClick", function() self:SetAll(false) end)

    self.reset = CreateFrame("Button", nil, frame.footer, "UIPanelButtonTemplate")
    self.reset:SetWidth(102)
    self.reset:SetHeight(22)
    self.reset:SetPoint("LEFT", self.hideAll, "RIGHT", 6, 0)
    self.reset:SetText("Reset Defaults")
    self.reset:SetScript("OnClick", function() self:ResetAll() end)

    frame.note = frame.footer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.note:SetJustifyH("RIGHT")
    frame.note:SetPoint("BOTTOMRIGHT", frame.footer, "BOTTOMRIGHT", -10, 13)
    frame.note:SetText("Local display only")

    frame:Hide()
    self:Refresh()
end

function SpellConfig:Show()
    if not ARC.Roster:IsLocalCoordinator() then
        ARC:Print("only the party leader, raid leader, or raid assistants can change ARC configuration")
        return false
    end
    self:Refresh()
    self.frame:Show()
    return true
end

function SpellConfig:Toggle()
    if self.frame:IsShown() then
        self.search:ClearFocus()
        self.frame:Hide()
        return false
    else
        return self:Show()
    end
end
