Actually = Actually or {}
local Addon = Actually

local Gear = { setOffset = 0, setButtons = {}, slotButtons = {} }
Addon.Gear = Gear

local SetBackdrop = Addon.Util.SetBackdrop
local MAX_VISIBLE_SETS = 10

local SLOT_LAYOUT = {
    { key = "head", label = "Head", inventory = "HeadSlot", x = 30, y = -105, side = "left" },
    { key = "neck", label = "Neck", inventory = "NeckSlot", x = 30, y = -160, side = "left" },
    { key = "shoulder", label = "Shoulders", inventory = "ShoulderSlot", x = 30, y = -215, side = "left" },
    { key = "back", label = "Back", inventory = "BackSlot", x = 30, y = -270, side = "left" },
    { key = "chest", label = "Chest", inventory = "ChestSlot", x = 30, y = -325, side = "left" },
    { key = "shirt", label = "Shirt", inventory = "ShirtSlot", x = 30, y = -380, side = "left" },
    { key = "tabard", label = "Tabard", inventory = "TabardSlot", x = 30, y = -435, side = "left" },
    { key = "wrist", label = "Wrist", inventory = "WristSlot", x = 30, y = -490, side = "left" },

    { key = "hands", label = "Hands", inventory = "HandsSlot", x = 334, y = -105, side = "right" },
    { key = "waist", label = "Waist", inventory = "WaistSlot", x = 334, y = -160, side = "right" },
    { key = "legs", label = "Legs", inventory = "LegsSlot", x = 334, y = -215, side = "right" },
    { key = "feet", label = "Feet", inventory = "FeetSlot", x = 334, y = -270, side = "right" },
    { key = "finger1", label = "Ring 1", inventory = "Finger0Slot", x = 334, y = -325, side = "right" },
    { key = "finger2", label = "Ring 2", inventory = "Finger1Slot", x = 334, y = -380, side = "right" },
    { key = "trinket1", label = "Trinket 1", inventory = "Trinket0Slot", x = 334, y = -435, side = "right" },
    { key = "trinket2", label = "Trinket 2", inventory = "Trinket1Slot", x = 334, y = -490, side = "right" },

    { key = "mainhand", label = "Main Hand", inventory = "MainHandSlot", x = 107, y = -565, side = "bottom" },
    { key = "offhand", label = "Off Hand", inventory = "SecondaryHandSlot", x = 176, y = -565, side = "bottom" },
    { key = "ranged", label = "Ranged / Relic", inventory = "RangedSlot", x = 245, y = -565, side = "bottom" },
}

local function Now()
    return time and time() or 0
end

local function PlayerIdentity()
    if Addon.Official and Addon.Official.GetPlayerIdentity then
        return Addon.Official:GetPlayerIdentity()
    end
    return UnitName("player") or "Unknown"
end

function Gear:IsOfficer()
    return Addon.Official and Addon.Official:IsOfficer() or false
end

function Gear:GetStorage()
    Addon.db.gear = type(Addon.db.gear) == "table" and Addon.db.gear or {}
    Addon.db.gear.sets = type(Addon.db.gear.sets) == "table" and Addon.db.gear.sets or {}
    Addon.db.gear.tombstones = type(Addon.db.gear.tombstones) == "table" and Addon.db.gear.tombstones or {}
    return Addon.db.gear
end

function Gear:GetSortedSets()
    local sets = {}
    for id, set in pairs(self:GetStorage().sets) do
        if type(set) == "table" then
            set.id = tostring(set.id or id)
            set.name = tostring(set.name or "Unnamed Gear Set")
            set.notes = tostring(set.notes or "")
            set.slots = type(set.slots) == "table" and set.slots or {}
            table.insert(sets, set)
        end
    end
    table.sort(sets, function(left, right)
        local leftOrder = tonumber(left.order) or 0
        local rightOrder = tonumber(right.order) or 0
        if leftOrder ~= rightOrder then
            return leftOrder < rightOrder
        end
        if string.lower(left.name) ~= string.lower(right.name) then
            return string.lower(left.name) < string.lower(right.name)
        end
        return left.id < right.id
    end)
    return sets
end

function Gear:GetSelectedSet()
    if not self.selectedSetID then
        return nil
    end
    return self:GetStorage().sets[self.selectedSetID]
end

function Gear:SetStatus(message, isError)
    if not self.statusText then
        return
    end
    self.statusText:SetText(message or "")
    self.statusText:SetTextColor(isError and 1 or 0.48, isError and 0.35 or 0.82, isError and 0.35 or 1)
end

function Gear:Touch(set, action)
    local stamp = Now()
    set.updatedAt = math.max(stamp, (tonumber(set.updatedAt) or 0) + 1)
    set.updatedBy = PlayerIdentity()
    if Addon.Official and Addon.Official.RecordActivity then
        Addon.Official:RecordActivity(action or ("Updated gear set " .. tostring(set.name) .. "."))
    end
    if Addon.Sync then
        Addon.Sync:MarkDirty(true)
    end
end

function Gear:SelectSet(id)
    if id and not self:GetStorage().sets[id] then
        id = nil
    end
    local previous = self:GetSelectedSet()
    if previous and previous.id ~= id and self:IsOfficer() and self.nameEdit and self.notesEdit then
        local draftName = Addon.Util.Trim(self.nameEdit:GetText())
        local draftNotes = self.notesEdit:GetText() or ""
        if draftName ~= "" and (draftName ~= previous.name or draftNotes ~= (previous.notes or "")) then
            previous.name = draftName
            previous.notes = draftNotes
            self:Touch(previous, "Updated gear set " .. previous.name .. ".")
        end
    end
    self.selectedSetID = id
    self.selectedSlot = nil
    self.deleteArmedUntil = nil
    self:Refresh()
end

function Gear:CreateSet()
    if not self:IsOfficer() then
        Addon:Print("Only officers can edit gear guides.")
        return
    end
    local sets = self:GetSortedSets()
    local id = Addon.Util.NewPersistentID()
    while self:GetStorage().sets[id] do
        id = Addon.Util.NewPersistentID()
    end
    local set = {
        id = id,
        name = "Gear Set " .. tostring(#sets + 1),
        notes = "",
        slots = {},
        order = Now() * 100 + #sets,
    }
    self:GetStorage().sets[id] = set
    self:Touch(set, "Created gear set " .. set.name .. ".")
    self:SelectSet(id)
    if self.nameEdit then
        self.nameEdit:SetFocus()
        self.nameEdit:HighlightText()
    end
end

function Gear:SaveSelectedSet()
    if not self:IsOfficer() then
        Addon:Print("Only officers can edit gear guides.")
        return
    end
    local set = self:GetSelectedSet()
    if not set then
        return
    end
    local name = Addon.Util.Trim(self.nameEdit:GetText())
    if name == "" then
        self:SetStatus("Give this gear set a name before saving.", true)
        return
    end
    set.name = name
    set.notes = self.notesEdit:GetText() or ""
    self:Touch(set, "Updated gear set " .. set.name .. ".")
    self:SetStatus("Saved " .. set.name .. ".")
    self:Refresh()
end

function Gear:DeleteSelectedSet()
    if not self:IsOfficer() then
        Addon:Print("Only officers can edit gear guides.")
        return
    end
    local set = self:GetSelectedSet()
    if not set then
        return
    end
    local now = GetTime and GetTime() or 0
    if not self.deleteArmedUntil or now > self.deleteArmedUntil then
        self.deleteArmedUntil = now + 4
        self.deleteButton:SetText("Confirm Delete")
        self:SetStatus("Click Confirm Delete within four seconds.", true)
        return
    end

    local storage = self:GetStorage()
    local deletedAt = math.max(Now(), (tonumber(set.updatedAt) or 0) + 1, (tonumber(storage.tombstones[set.id]) or 0) + 1)
    storage.sets[set.id] = nil
    storage.tombstones[set.id] = deletedAt
    if Addon.Official and Addon.Official.RecordActivity then
        Addon.Official:RecordActivity("Deleted gear set " .. set.name .. ".")
    end
    if Addon.Sync then
        Addon.Sync:MarkDirty(true)
    end
    self.selectedSetID = nil
    self.selectedSlot = nil
    self.deleteArmedUntil = nil
    self:Refresh()
end

local function ParseItemLink(link)
    link = tostring(link or "")
    local itemString = string.match(link, "|H(item:[^|]+)|h") or string.match(link, "(item:[^%s|]+)")
    if not itemString then
        return nil
    end
    local itemID = tonumber(string.match(itemString, "item:(%d+)"))
    if not itemID then
        return nil
    end
    if string.find(link, "|Hitem:", 1, true) then
        return link, itemID
    end
    return itemString, itemID
end

function Gear:CaptureItemLink(link)
    local itemLink, itemID = ParseItemLink(link)
    if not itemLink then
        return false
    end
    if not self:IsOfficer() then
        self:SetStatus("Gear guides are read-only for non-officers.", true)
        return true
    end
    local set = self:GetSelectedSet()
    if not set then
        self:SetStatus("Create or select a gear set first.", true)
        return true
    end
    if not self.selectedSlot then
        self:SetStatus("Click an equipment slot, then Shift-click the item link.", true)
        return true
    end

    set.slots[self.selectedSlot] = { link = itemLink, itemID = itemID }
    self:Touch(set, "Updated an item in gear set " .. set.name .. ".")
    self:SetStatus("Item saved. Select another slot to continue.")
    self:RefreshSlots()
    return true
end

function Gear:ClearSlot(slotKey)
    if not self:IsOfficer() then
        return
    end
    local set = self:GetSelectedSet()
    if not set or not set.slots[slotKey] then
        return
    end
    set.slots[slotKey] = nil
    self:Touch(set, "Cleared an item from gear set " .. set.name .. ".")
    self:SetStatus("Item removed from " .. set.name .. ".")
    self:RefreshSlots()
end

function Gear:InstallLinkCapture()
    if self.linkCaptureInstalled or type(ChatEdit_InsertLink) ~= "function" then
        return
    end
    self.linkCaptureInstalled = true
    self.originalInsertLink = ChatEdit_InsertLink
    ChatEdit_InsertLink = function(link)
        if Gear.frame and Gear.frame:IsShown() and ParseItemLink(link) then
            if Gear:CaptureItemLink(link) then
                return true
            end
        end
        return Gear.originalInsertLink(link)
    end
end

function Gear:SelectSlot(slotKey)
    self.selectedSlot = slotKey
    self:SetStatus(self:IsOfficer()
        and "Shift-click an item link to fill the selected slot; right-click a filled slot to clear it."
        or "Hover a filled slot to inspect its item.")
    self:RefreshSlots()
end

function Gear:RefreshSlots()
    if not self.slotButtons then
        return
    end
    local set = self:GetSelectedSet()
    self.itemInfoPending = false
    for slotKey, button in pairs(self.slotButtons) do
        local saved = set and set.slots and set.slots[slotKey]
        local savedLink = type(saved) == "table" and saved.link or saved
        local savedItemID = type(saved) == "table" and saved.itemID or nil
        button.itemLink = savedLink
        if saved then
            local name, canonicalLink, quality, _, _, _, _, _, _, texture = GetItemInfo(savedLink or savedItemID)
            button.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
            button.icon:SetVertexColor(1, 1, 1, 1)
            button.itemName = name or string.match(savedLink or "", "%[(.-)%]") or ("Item " .. tostring(savedItemID or ""))
            button.itemLink = savedLink or canonicalLink
            if not name then
                self.itemInfoPending = true
            end
            if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
                local color = ITEM_QUALITY_COLORS[quality]
                button:SetBackdropBorderColor(color.r, color.g, color.b, 1)
            else
                button:SetBackdropBorderColor(0.38, 0.58, 0.72, 1)
            end
        else
            button.icon:SetTexture(button.emptyTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
            button.icon:SetVertexColor(0.38, 0.43, 0.52, 0.75)
            button.itemName = nil
            button:SetBackdropBorderColor(0.18, 0.28, 0.38, 1)
        end
        if self.selectedSlot == slotKey then
            button:SetBackdropBorderColor(0.35, 0.85, 1, 1)
            button.selection:Show()
        else
            button.selection:Hide()
        end
    end
end

function Gear:RefreshSetButtons(sets)
    local maximumOffset = math.max(0, #sets - MAX_VISIBLE_SETS)
    if self.selectedSetID then
        for index, set in ipairs(sets) do
            if set.id == self.selectedSetID then
                if index <= (self.setOffset or 0) then
                    self.setOffset = index - 1
                elseif index > (self.setOffset or 0) + MAX_VISIBLE_SETS then
                    self.setOffset = index - MAX_VISIBLE_SETS
                end
                break
            end
        end
    end
    self.setOffset = math.max(0, math.min(self.setOffset or 0, maximumOffset))
    for index, button in ipairs(self.setButtons) do
        local set = sets[self.setOffset + index]
        button.setID = set and set.id or nil
        if set then
            button.text:SetText(set.name)
            button:Show()
            if set.id == self.selectedSetID then
                button:SetBackdropColor(0.14, 0.38, 0.62, 1)
                button:SetBackdropBorderColor(0.36, 0.85, 1, 1)
            else
                button:SetBackdropColor(0.055, 0.075, 0.105, 0.98)
                button:SetBackdropBorderColor(0.14, 0.28, 0.40, 1)
            end
        else
            button:Hide()
        end
    end
    self.pageText:SetText(#sets == 0 and "No saved builds" or (tostring(self.setOffset + 1) .. "-" .. tostring(math.min(#sets, self.setOffset + MAX_VISIBLE_SETS)) .. " of " .. tostring(#sets)))
end

function Gear:RefreshPermissions()
    local officer = self:IsOfficer()
    if officer then
        self.newButton:Show()
        self.saveButton:Show()
        self.deleteButton:Show()
        self.nameEdit:Enable()
        self.notesEdit:Enable()
        self.permissionText:SetText("|cff77dd77OFFICER EDIT|r  Select a slot, then Shift-click an item link")
    else
        self.newButton:Hide()
        self.saveButton:Hide()
        self.deleteButton:Hide()
        self.nameEdit:Disable()
        self.notesEdit:Disable()
        self.permissionText:SetText("|cffaaaaaaOFFICIAL GEAR GUIDE  read-only|r")
    end
end

function Gear:Refresh()
    if not self.frame then
        return
    end
    local sets = self:GetSortedSets()
    local selected = self:GetSelectedSet()
    if not selected and #sets > 0 then
        self.selectedSetID = sets[1].id
        selected = sets[1]
    end
    self:RefreshSetButtons(sets)
    self:RefreshPermissions()

    if selected then
        if not self.nameEdit:HasFocus() then
            self.nameEdit:SetText(selected.name)
        end
        if not self.notesEdit:HasFocus() then
            self.notesEdit:SetText(selected.notes or "")
        end
        self.emptyText:Hide()
        self.paperDoll:Show()
        self.notesPanel:Show()
        self.deleteButton:SetText("Delete")
    else
        self.nameEdit:SetText("")
        self.notesEdit:SetText("")
        self.emptyText:SetText(self:IsOfficer()
            and "No gear builds yet. Click New Build to create the first one."
            or "No official gear builds have been published yet.")
        self.emptyText:Show()
        self.paperDoll:Hide()
        self.notesPanel:Hide()
    end
    self:RefreshSlots()
end

function Gear:SetVisible(visible)
    if not self.frame then
        return
    end
    if visible then
        self.frame:Show()
        self:Refresh()
    else
        self.frame:Hide()
        if self.nameEdit then self.nameEdit:ClearFocus() end
        if self.notesEdit then self.notesEdit:ClearFocus() end
        GameTooltip:Hide()
    end
end

function Gear:CreateSlot(parent, slotInfo)
    local button = CreateFrame("Button", nil, parent)
    button:SetWidth(48)
    button:SetHeight(48)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", slotInfo.x, slotInfo.y)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    SetBackdrop(button, { 0.035, 0.045, 0.06, 0.98 }, { 0.18, 0.28, 0.38, 1 })

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 4, -4)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4, 4)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.icon = icon

    local _, emptyTexture = GetInventorySlotInfo(slotInfo.inventory)
    button.emptyTexture = emptyTexture

    local selection = button:CreateTexture(nil, "OVERLAY")
    selection:SetAllPoints(button)
    selection:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    selection:SetBlendMode("ADD")
    selection:SetVertexColor(0.25, 0.82, 1, 0.9)
    selection:Hide()
    button.selection = selection

    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if slotInfo.side == "left" then
        label:SetPoint("LEFT", button, "RIGHT", 5, 0)
        label:SetJustifyH("LEFT")
    elseif slotInfo.side == "right" then
        label:SetPoint("RIGHT", button, "LEFT", -5, 0)
        label:SetJustifyH("RIGHT")
    else
        label:SetPoint("TOP", button, "BOTTOM", 0, -2)
        label:SetJustifyH("CENTER")
    end
    label:SetText(slotInfo.label)

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            Gear:ClearSlot(slotInfo.key)
        else
            Gear:SelectSlot(slotInfo.key)
        end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.itemLink then
            GameTooltip:SetHyperlink(self.itemLink)
            if Gear:IsOfficer() then
                GameTooltip:AddLine("Right-click to clear this slot.", 0.55, 0.85, 1, true)
            end
        else
            GameTooltip:AddLine(slotInfo.label, 1, 0.82, 0.2)
            if Gear:IsOfficer() then
                GameTooltip:AddLine("Click, then Shift-click an item link.", 1, 1, 1, true)
            end
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.slotButtons[slotInfo.key] = button
end

function Gear:Create(parent)
    if self.frame then
        return
    end
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, -5)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -5, 80)
    frame:SetFrameLevel(parent:GetFrameLevel() + 20)
    SetBackdrop(frame, { 0.018, 0.026, 0.040, 0.995 }, { 0.28, 0.78, 1.00, 1 })
    frame:Hide()
    self.frame = frame

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -17)
    title:SetText("Official Gear Builds")

    local permission = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    permission:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -43)
    permission:SetWidth(570)
    permission:SetJustifyH("LEFT")
    self.permissionText = permission

    local leftPane = CreateFrame("Frame", nil, frame)
    leftPane:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -68)
    leftPane:SetWidth(176)
    leftPane:SetHeight(545)
    leftPane:EnableMouse(true)
    leftPane:EnableMouseWheel(true)
    SetBackdrop(leftPane, { 0.03, 0.04, 0.055, 0.98 }, { 0.13, 0.32, 0.43, 1 })

    local buildsLabel = leftPane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    buildsLabel:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 10, -10)
    buildsLabel:SetText("SAVED BUILDS")

    for index = 1, MAX_VISIBLE_SETS do
        local button = CreateFrame("Button", nil, leftPane)
        button:SetWidth(156)
        button:SetHeight(40)
        button:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 10, -(35 + (index - 1) * 44))
        SetBackdrop(button, { 0.055, 0.075, 0.105, 0.98 }, { 0.14, 0.28, 0.40, 1 })
        local buttonText = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        buttonText:SetPoint("LEFT", button, "LEFT", 9, 0)
        buttonText:SetPoint("RIGHT", button, "RIGHT", -9, 0)
        buttonText:SetJustifyH("LEFT")
        buttonText:SetWordWrap(false)
        button.text = buttonText
        button:SetScript("OnClick", function(self)
            if self.setID then Gear:SelectSet(self.setID) end
        end)
        self.setButtons[index] = button
    end

    local pageText = leftPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pageText:SetPoint("BOTTOM", leftPane, "BOTTOM", 0, 12)
    pageText:SetTextColor(0.5, 0.65, 0.75)
    self.pageText = pageText
    leftPane:SetScript("OnMouseWheel", function(_, delta)
        local sets = Gear:GetSortedSets()
        local maximumOffset = math.max(0, #sets - MAX_VISIBLE_SETS)
        Gear.setOffset = math.max(0, math.min(maximumOffset, (Gear.setOffset or 0) - delta))
        Gear:RefreshSetButtons(sets)
    end)

    local newButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    newButton:SetWidth(98)
    newButton:SetHeight(24)
    newButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 13)
    newButton:SetText("New Build")
    newButton:SetScript("OnClick", function() Gear:CreateSet() end)
    self.newButton = newButton

    local paperDoll = CreateFrame("Frame", nil, frame)
    paperDoll:SetPoint("TOPLEFT", frame, "TOPLEFT", 198, -68)
    paperDoll:SetWidth(414)
    paperDoll:SetHeight(545)
    SetBackdrop(paperDoll, { 0.028, 0.035, 0.048, 0.98 }, { 0.15, 0.34, 0.48, 1 })
    self.paperDoll = paperDoll

    local dollTitle = paperDoll:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dollTitle:SetPoint("TOP", paperDoll, "TOP", 0, -48)
    dollTitle:SetText("EQUIPMENT")
    dollTitle:SetTextColor(0.45, 0.72, 0.92)

    local silhouette = paperDoll:CreateTexture(nil, "BACKGROUND")
    silhouette:SetWidth(166)
    silhouette:SetHeight(350)
    silhouette:SetPoint("TOP", paperDoll, "TOP", 0, -95)
    silhouette:SetTexture("Interface\\Buttons\\WHITE8X8")
    silhouette:SetVertexColor(0.055, 0.075, 0.105, 0.72)

    for _, slotInfo in ipairs(SLOT_LAYOUT) do
        self:CreateSlot(paperDoll, slotInfo)
    end

    local notesPanel = CreateFrame("Frame", nil, frame)
    notesPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 620, -68)
    notesPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 52)
    SetBackdrop(notesPanel, { 0.03, 0.04, 0.055, 0.98 }, { 0.13, 0.32, 0.43, 1 })
    self.notesPanel = notesPanel

    local nameLabel = notesPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", notesPanel, "TOPLEFT", 12, -13)
    nameLabel:SetText("BUILD NAME")

    local nameEdit = CreateFrame("EditBox", nil, notesPanel, "InputBoxTemplate")
    nameEdit:SetWidth(292)
    nameEdit:SetHeight(25)
    nameEdit:SetPoint("TOPLEFT", notesPanel, "TOPLEFT", 12, -34)
    nameEdit:SetAutoFocus(false)
    nameEdit:SetMaxLetters(80)
    nameEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() Gear:Refresh() end)
    nameEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() Gear:SaveSelectedSet() end)
    self.nameEdit = nameEdit

    local notesLabel = notesPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    notesLabel:SetPoint("TOPLEFT", notesPanel, "TOPLEFT", 12, -73)
    notesLabel:SetText("BUILD NOTES")

    local noteBorder = CreateFrame("Frame", nil, notesPanel)
    noteBorder:SetPoint("TOPLEFT", notesPanel, "TOPLEFT", 10, -94)
    noteBorder:SetPoint("BOTTOMRIGHT", notesPanel, "BOTTOMRIGHT", -10, 49)
    SetBackdrop(noteBorder, { 0.018, 0.024, 0.034, 1 }, { 0.12, 0.25, 0.34, 1 })

    local noteScroll = CreateFrame("ScrollFrame", nil, noteBorder, "UIPanelScrollFrameTemplate")
    noteScroll:SetPoint("TOPLEFT", noteBorder, "TOPLEFT", 8, -8)
    noteScroll:SetPoint("BOTTOMRIGHT", noteBorder, "BOTTOMRIGHT", -28, 8)
    local notesEdit = CreateFrame("EditBox", nil, noteScroll)
    notesEdit:SetWidth(260)
    notesEdit:SetHeight(380)
    notesEdit:SetMultiLine(true)
    notesEdit:SetAutoFocus(false)
    notesEdit:SetFontObject(GameFontHighlight)
    notesEdit:SetTextInsets(3, 3, 3, 3)
    notesEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    notesEdit:SetScript("OnTextChanged", function(self)
        self:SetHeight(math.max(380, self:GetStringHeight() + 18))
    end)
    noteScroll:SetScrollChild(notesEdit)
    self.notesEdit = notesEdit

    local saveButton = CreateFrame("Button", nil, notesPanel, "UIPanelButtonTemplate")
    saveButton:SetWidth(100)
    saveButton:SetHeight(24)
    saveButton:SetPoint("BOTTOMRIGHT", notesPanel, "BOTTOMRIGHT", -10, 13)
    saveButton:SetText("Save Build")
    saveButton:SetScript("OnClick", function() Gear:SaveSelectedSet() end)
    self.saveButton = saveButton

    local deleteButton = CreateFrame("Button", nil, notesPanel, "UIPanelButtonTemplate")
    deleteButton:SetWidth(105)
    deleteButton:SetHeight(24)
    deleteButton:SetPoint("RIGHT", saveButton, "LEFT", -6, 0)
    deleteButton:SetText("Delete")
    deleteButton:SetScript("OnClick", function() Gear:DeleteSelectedSet() end)
    self.deleteButton = deleteButton

    local emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    emptyText:SetPoint("CENTER", frame, "CENTER", 95, 25)
    emptyText:SetWidth(560)
    emptyText:SetJustifyH("CENTER")
    self.emptyText = emptyText

    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 198, 18)
    status:SetWidth(720)
    status:SetJustifyH("LEFT")
    self.statusText = status

    frame:SetScript("OnUpdate", function(_, elapsed)
        if not Gear.itemInfoPending then return end
        Gear.itemRetryElapsed = (Gear.itemRetryElapsed or 0) + elapsed
        if Gear.itemRetryElapsed >= 0.5 then
            Gear.itemRetryElapsed = 0
            Gear:RefreshSlots()
        end
    end)
    frame:SetScript("OnShow", function()
        Gear:InstallLinkCapture()
        Gear:SetStatus(Gear:IsOfficer()
            and "Select a slot, then Shift-click an item link to add it."
            or "Official gear builds are read-only.")
        Gear:Refresh()
    end)

    self:InstallLinkCapture()
    self:Refresh()
end
