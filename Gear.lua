Actually = Actually or {}
local Addon = Actually

local Gear = { setOffset = 0, setButtons = {}, slotButtons = {} }
Addon.Gear = Gear

local SetBackdrop = Addon.Util.SetBackdrop
local MAX_VISIBLE_SETS = 10

local SLOT_LAYOUT = {
    { key = "head", label = "Head", inventory = "HeadSlot", x = 24, y = -62, side = "left" },
    { key = "neck", label = "Neck", inventory = "NeckSlot", x = 24, y = -111, side = "left" },
    { key = "shoulder", label = "Shoulders", inventory = "ShoulderSlot", x = 24, y = -160, side = "left" },
    { key = "back", label = "Back", inventory = "BackSlot", x = 24, y = -209, side = "left" },
    { key = "chest", label = "Chest", inventory = "ChestSlot", x = 24, y = -258, side = "left" },
    { key = "shirt", label = "Shirt", inventory = "ShirtSlot", x = 24, y = -307, side = "left" },
    { key = "tabard", label = "Tabard", inventory = "TabardSlot", x = 24, y = -356, side = "left" },
    { key = "wrist", label = "Wrist", inventory = "WristSlot", x = 24, y = -405, side = "left" },

    { key = "hands", label = "Hands", inventory = "HandsSlot", x = 364, y = -62, side = "right" },
    { key = "waist", label = "Waist", inventory = "WaistSlot", x = 364, y = -111, side = "right" },
    { key = "legs", label = "Legs", inventory = "LegsSlot", x = 364, y = -160, side = "right" },
    { key = "feet", label = "Feet", inventory = "FeetSlot", x = 364, y = -209, side = "right" },
    { key = "finger1", label = "Ring 1", inventory = "Finger0Slot", x = 364, y = -258, side = "right" },
    { key = "finger2", label = "Ring 2", inventory = "Finger1Slot", x = 364, y = -307, side = "right" },
    { key = "trinket1", label = "Trinket 1", inventory = "Trinket0Slot", x = 364, y = -356, side = "right" },
    { key = "trinket2", label = "Trinket 2", inventory = "Trinket1Slot", x = 364, y = -405, side = "right" },

    { key = "mainhand", label = "Main Hand", inventory = "MainHandSlot", x = 96, side = "bottom" },
    { key = "offhand", label = "Off Hand", inventory = "SecondaryHandSlot", x = 194, side = "bottom" },
    { key = "ranged", label = "Ranged / Relic", inventory = "RangedSlot", x = 294, side = "bottom" },
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
    if not Addon.Official or not Addon.Official:IsOfficer() then
        return false
    end
    return not Addon.Sync or not Addon.Sync.IsOfficialEditReady
        or Addon.Sync:IsOfficialEditReady()
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
    -- Clicking another frame does not reliably remove EditBox focus in 3.3.5.
    -- Clear it before refreshing so the newly selected set's fields are loaded
    -- instead of retaining the previous set's draft text.
    if self.nameEdit then self.nameEdit:ClearFocus() end
    if self.notesEdit then self.notesEdit:ClearFocus() end
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
        -- IsShown() on a child can remain true while its parent is hidden.  Require
        -- the main addon window and Gear section as well, so normal chat linking
        -- resumes immediately when Actually is closed or another tab is selected.
        local board = Addon.Board
        local captureActive = Gear.frame
            and Gear.frame:IsShown()
            and board
            and board.frame
            and board.frame:IsShown()
            and board.activeSection == "gear"
        if captureActive and ParseItemLink(link) then
            if Gear:CaptureItemLink(link) then
                return true
            end
        end
        return Gear.originalInsertLink(link)
    end
end

function Gear:DeactivateLinkCapture()
    if not self.selectedSlot then
        return
    end
    self.selectedSlot = nil
    self:RefreshSlots()
end

function Gear:SelectSlot(slotKey)
    self.selectedSlot = slotKey
    self:SetStatus(self:IsOfficer()
        and "Shift-click an item link to fill the selected slot; right-click a filled slot to clear it."
        or "Hover a filled slot to inspect its item.")
    self:RefreshSlots()
end

function Gear:RefreshSlotGuide()
    if not self.slotGuideTitle or not self.slotGuideText then
        return
    end

    local button = self.selectedSlot and self.slotButtons[self.selectedSlot]
    if button then
        self.slotGuideTitle:SetText("SELECTED: " .. string.upper(button.slotLabel or self.selectedSlot))
        self.slotGuideTitle:SetTextColor(0.42, 0.88, 1)
        self.slotGuideText:SetText(self:IsOfficer()
            and "Shift-click an item link\nto place it in this slot."
            or "Hover the equipped item\nto inspect its details.")
    else
        self.slotGuideTitle:SetText("BUILD LOADOUT")
        self.slotGuideTitle:SetTextColor(0.48, 0.74, 0.92)
        self.slotGuideText:SetText(self:IsOfficer()
            and "Choose a slot, then Shift-click\nan item link from bags or chat."
            or "Hover any equipped item\nto inspect its details.")
    end
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
    self:RefreshSlotGuide()
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
    if self.buildCountText then
        self.buildCountText:SetText(tostring(#sets) .. (#sets == 1 and " SAVED BUILD" or " SAVED BUILDS"))
    end
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
        self:DeactivateLinkCapture()
        self.frame:Hide()
        if self.nameEdit then self.nameEdit:ClearFocus() end
        if self.notesEdit then self.notesEdit:ClearFocus() end
        GameTooltip:Hide()
    end
end

function Gear:CreateSlot(parent, slotInfo)
    local button = CreateFrame("Button", nil, parent)
    button:SetWidth(42)
    button:SetHeight(42)
    if slotInfo.side == "bottom" then
        button:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", slotInfo.x, 28)
    else
        button:SetPoint("TOPLEFT", parent, "TOPLEFT", slotInfo.x, slotInfo.y)
    end
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    SetBackdrop(button, { 0.035, 0.045, 0.06, 0.98 }, { 0.18, 0.28, 0.38, 1 })

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 4, -4)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4, 4)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.icon = icon

    local _, emptyTexture = GetInventorySlotInfo(slotInfo.inventory)
    button.emptyTexture = emptyTexture
    button.slotLabel = slotInfo.label

    local selection = button:CreateTexture(nil, "OVERLAY")
    selection:SetAllPoints(button)
    selection:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    selection:SetBlendMode("ADD")
    selection:SetVertexColor(0.25, 0.82, 1, 0.9)
    selection:Hide()
    button.selection = selection

    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if slotInfo.side == "left" then
        label:SetPoint("LEFT", button, "RIGHT", 5, 0)
        label:SetJustifyH("LEFT")
    elseif slotInfo.side == "right" then
        label:SetPoint("RIGHT", button, "LEFT", -5, 0)
        label:SetJustifyH("RIGHT")
    else
        label:SetPoint("TOP", button, "BOTTOM", 0, -2)
        label:SetWidth(92)
        label:SetHeight(14)
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
    frame:SetFrameLevel(parent:GetFrameLevel() + 24)
    SetBackdrop(frame, { 0.015, 0.022, 0.034, 0.998 }, { 0.28, 0.78, 1.00, 1 })
    frame:Hide()
    self.frame = frame

    local headerBar = CreateFrame("Frame", nil, frame)
    headerBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -10)
    headerBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -10)
    headerBar:SetHeight(52)
    SetBackdrop(headerBar, { 0.028, 0.055, 0.080, 0.99 }, { 0.20, 0.55, 0.75, 0.95 })

    local gearIcon = headerBar:CreateTexture(nil, "ARTWORK")
    gearIcon:SetWidth(36)
    gearIcon:SetHeight(36)
    gearIcon:SetPoint("LEFT", headerBar, "LEFT", 10, 0)
    gearIcon:SetTexture("Interface\\AddOns\\actually\\Textures\\TabIconGear")
    gearIcon:SetAlpha(0.95)

    local title = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", headerBar, "TOPLEFT", 55, -8)
    title:SetText("Official Gear Builds")
    title:SetTextColor(1, 0.82, 0.24)

    local permission = headerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    permission:SetPoint("TOPLEFT", headerBar, "TOPLEFT", 55, -30)
    permission:SetWidth(600)
    permission:SetJustifyH("LEFT")
    self.permissionText = permission

    local buildCount = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    buildCount:SetPoint("RIGHT", headerBar, "RIGHT", -18, 0)
    buildCount:SetWidth(170)
    buildCount:SetJustifyH("RIGHT")
    buildCount:SetTextColor(0.42, 0.80, 1)
    self.buildCountText = buildCount

    local leftPane = CreateFrame("Frame", nil, frame)
    leftPane:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -72)
    leftPane:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 52)
    leftPane:SetWidth(180)
    leftPane:EnableMouse(true)
    leftPane:EnableMouseWheel(true)
    SetBackdrop(leftPane, { 0.026, 0.038, 0.055, 0.99 }, { 0.16, 0.42, 0.60, 1 })

    local buildsHeader = CreateFrame("Frame", nil, leftPane)
    buildsHeader:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 1, -1)
    buildsHeader:SetPoint("TOPRIGHT", leftPane, "TOPRIGHT", -1, -1)
    buildsHeader:SetHeight(38)
    SetBackdrop(buildsHeader, { 0.045, 0.095, 0.135, 0.98 }, { 0.12, 0.30, 0.42, 0 })

    local buildsLabel = buildsHeader:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    buildsLabel:SetPoint("LEFT", buildsHeader, "LEFT", 10, 0)
    buildsLabel:SetText("SAVED BUILDS")
    buildsLabel:SetTextColor(0.48, 0.82, 1)

    for index = 1, MAX_VISIBLE_SETS do
        local button = CreateFrame("Button", nil, leftPane)
        button:SetWidth(160)
        button:SetHeight(34)
        button:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 10, -(48 + (index - 1) * 38))
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
    pageText:SetPoint("BOTTOM", leftPane, "BOTTOM", 0, 45)
    pageText:SetTextColor(0.5, 0.65, 0.75)
    self.pageText = pageText
    leftPane:SetScript("OnMouseWheel", function(_, delta)
        local sets = Gear:GetSortedSets()
        local maximumOffset = math.max(0, #sets - MAX_VISIBLE_SETS)
        Gear.setOffset = math.max(0, math.min(maximumOffset, (Gear.setOffset or 0) - delta))
        Gear:RefreshSetButtons(sets)
    end)

    local newButton = CreateFrame("Button", nil, leftPane, "UIPanelButtonTemplate")
    newButton:SetWidth(152)
    newButton:SetHeight(24)
    newButton:SetPoint("BOTTOM", leftPane, "BOTTOM", 0, 12)
    newButton:SetText("+  New Build")
    newButton:SetScript("OnClick", function() Gear:CreateSet() end)
    self.newButton = newButton

    local paperDoll = CreateFrame("Frame", nil, frame)
    paperDoll:SetPoint("TOPLEFT", frame, "TOPLEFT", 202, -72)
    paperDoll:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 202, 52)
    paperDoll:SetWidth(430)
    SetBackdrop(paperDoll, { 0.023, 0.032, 0.046, 0.99 }, { 0.16, 0.44, 0.64, 1 })
    self.paperDoll = paperDoll

    local equipmentHeader = CreateFrame("Frame", nil, paperDoll)
    equipmentHeader:SetPoint("TOPLEFT", paperDoll, "TOPLEFT", 1, -1)
    equipmentHeader:SetPoint("TOPRIGHT", paperDoll, "TOPRIGHT", -1, -1)
    equipmentHeader:SetHeight(38)
    SetBackdrop(equipmentHeader, { 0.045, 0.095, 0.135, 0.98 }, { 0.12, 0.30, 0.42, 0 })

    local dollTitle = equipmentHeader:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dollTitle:SetPoint("CENTER", equipmentHeader, "CENTER", 0, 0)
    dollTitle:SetText("EQUIPMENT")
    dollTitle:SetTextColor(0.48, 0.82, 1)

    local guideCard = CreateFrame("Frame", nil, paperDoll)
    guideCard:SetWidth(184)
    guideCard:SetHeight(310)
    guideCard:SetPoint("TOP", paperDoll, "TOP", 0, -66)
    SetBackdrop(guideCard, { 0.030, 0.055, 0.078, 0.96 }, { 0.14, 0.35, 0.50, 0.85 })

    local guideIcon = guideCard:CreateTexture(nil, "BACKGROUND")
    guideIcon:SetWidth(126)
    guideIcon:SetHeight(126)
    guideIcon:SetPoint("CENTER", guideCard, "CENTER", 0, 35)
    guideIcon:SetTexture("Interface\\AddOns\\actually\\Textures\\TabIconGear")
    guideIcon:SetAlpha(0.075)

    local guideTitle = guideCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    guideTitle:SetPoint("CENTER", guideCard, "CENTER", 0, 12)
    guideTitle:SetWidth(164)
    guideTitle:SetJustifyH("CENTER")
    self.slotGuideTitle = guideTitle

    local guideText = guideCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    guideText:SetPoint("TOP", guideTitle, "BOTTOM", 0, -12)
    guideText:SetWidth(164)
    guideText:SetJustifyH("CENTER")
    guideText:SetTextColor(0.62, 0.72, 0.80)
    self.slotGuideText = guideText

    local weaponBar = CreateFrame("Frame", nil, paperDoll)
    weaponBar:SetPoint("BOTTOMLEFT", paperDoll, "BOTTOMLEFT", 68, 7)
    weaponBar:SetPoint("BOTTOMRIGHT", paperDoll, "BOTTOMRIGHT", -68, 7)
    weaponBar:SetHeight(88)
    SetBackdrop(weaponBar, { 0.025, 0.045, 0.063, 0.96 }, { 0.12, 0.30, 0.42, 0.75 })

    local weaponLabel = weaponBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    weaponLabel:SetPoint("TOP", weaponBar, "TOP", 0, -4)
    weaponLabel:SetText("WEAPONS")
    weaponLabel:SetTextColor(0.42, 0.70, 0.88)

    for _, slotInfo in ipairs(SLOT_LAYOUT) do
        self:CreateSlot(paperDoll, slotInfo)
    end

    local notesPanel = CreateFrame("Frame", nil, frame)
    notesPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 640, -72)
    notesPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 52)
    SetBackdrop(notesPanel, { 0.026, 0.038, 0.055, 0.99 }, { 0.16, 0.42, 0.60, 1 })
    self.notesPanel = notesPanel

    local detailsHeader = CreateFrame("Frame", nil, notesPanel)
    detailsHeader:SetPoint("TOPLEFT", notesPanel, "TOPLEFT", 1, -1)
    detailsHeader:SetPoint("TOPRIGHT", notesPanel, "TOPRIGHT", -1, -1)
    detailsHeader:SetHeight(38)
    SetBackdrop(detailsHeader, { 0.045, 0.095, 0.135, 0.98 }, { 0.12, 0.30, 0.42, 0 })

    local detailsTitle = detailsHeader:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    detailsTitle:SetPoint("LEFT", detailsHeader, "LEFT", 10, 0)
    detailsTitle:SetText("BUILD DETAILS")
    detailsTitle:SetTextColor(0.48, 0.82, 1)

    local nameLabel = notesPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", notesPanel, "TOPLEFT", 12, -52)
    nameLabel:SetText("BUILD NAME")

    local nameEdit = CreateFrame("EditBox", nil, notesPanel, "InputBoxTemplate")
    nameEdit:SetWidth(292)
    nameEdit:SetHeight(25)
    nameEdit:SetPoint("TOPLEFT", notesPanel, "TOPLEFT", 12, -72)
    nameEdit:SetAutoFocus(false)
    nameEdit:SetMaxLetters(80)
    nameEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() Gear:Refresh() end)
    nameEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() Gear:SaveSelectedSet() end)
    self.nameEdit = nameEdit

    local notesLabel = notesPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    notesLabel:SetPoint("TOPLEFT", notesPanel, "TOPLEFT", 12, -112)
    notesLabel:SetText("BUILD NOTES")

    local noteBorder = CreateFrame("Frame", nil, notesPanel)
    noteBorder:SetPoint("TOPLEFT", notesPanel, "TOPLEFT", 10, -134)
    noteBorder:SetPoint("BOTTOMRIGHT", notesPanel, "BOTTOMRIGHT", -10, 58)
    SetBackdrop(noteBorder, { 0.015, 0.022, 0.032, 1 }, { 0.12, 0.30, 0.42, 1 })

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
        -- GetStringHeight belongs to FontString on newer clients and is not
        -- available on Ascension's 3.3.5 EditBox. Estimate wrapped text height
        -- from the active font and edit width so the scroll child still grows.
        local fontHeight = 12
        if self.GetFont then
            local _, configuredHeight = self:GetFont()
            fontHeight = tonumber(configuredHeight) or fontHeight
        end

        local usableWidth = math.max(1, self:GetWidth() - 6)
        local approximateCharacterWidth = math.max(1, fontHeight * 0.55)
        local charactersPerLine = math.max(1, math.floor(usableWidth / approximateCharacterWidth))
        local visualLines = 0
        local text = (self:GetText() or ""):gsub("\t", "    ")
        for line in (text .. "\n"):gmatch("(.-)\n") do
            visualLines = visualLines + math.max(1, math.ceil(#line / charactersPerLine))
        end
        self:SetHeight(math.max(380, visualLines * (fontHeight + 3) + 18))
    end)
    noteScroll:SetScrollChild(notesEdit)
    self.notesEdit = notesEdit

    local saveButton = CreateFrame("Button", nil, notesPanel, "UIPanelButtonTemplate")
    saveButton:SetWidth(100)
    saveButton:SetHeight(24)
    saveButton:SetPoint("BOTTOMRIGHT", notesPanel, "BOTTOMRIGHT", -10, 17)
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

    local statusBar = CreateFrame("Frame", nil, frame)
    statusBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 202, 12)
    statusBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 12)
    statusBar:SetHeight(28)
    SetBackdrop(statusBar, { 0.025, 0.050, 0.070, 0.98 }, { 0.12, 0.30, 0.42, 0.8 })

    local emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    emptyText:SetPoint("CENTER", frame, "CENTER", 95, 25)
    emptyText:SetWidth(560)
    emptyText:SetJustifyH("CENTER")
    self.emptyText = emptyText

    local status = statusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("LEFT", statusBar, "LEFT", 10, 0)
    status:SetPoint("RIGHT", statusBar, "RIGHT", -10, 0)
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
    frame:SetScript("OnHide", function()
        Gear:DeactivateLinkCapture()
        if Gear.nameEdit then Gear.nameEdit:ClearFocus() end
        if Gear.notesEdit then Gear.notesEdit:ClearFocus() end
    end)

    self:InstallLinkCapture()
    self:Refresh()
end
