local ARC = Actually.Modules.RaidCooldowns
local SpoofTest = ARC:NewModule("SpoofTest")

local PAGE_SIZE = 9

local function sortedRegistryIDs()
    local ids = {}
    for spellID, entry in pairs(ARC.Registry.entries) do
        if entry.valid then table.insert(ids, spellID) end
    end
    table.sort(ids, function(left, right)
        local leftName = string.lower(ARC.SpellInfo:ResolveSpellName(left))
        local rightName = string.lower(ARC.SpellInfo:ResolveSpellName(right))
        if leftName ~= rightName then return leftName < rightName end
        return left < right
    end)
    return ids
end

function SpoofTest:GetDuration()
    local duration = tonumber(self.durationBox:GetText()) or 30
    duration = math.max(3, math.min(duration, ARC.Constants.MAX_COOLDOWN))
    ARC.db.profile.spoofUI.duration = duration
    self.durationBox:SetText(tostring(duration))
    return duration
end

function SpoofTest:Use(spellID)
    local duration = self:GetDuration()
    local now = ARC:Now()
    local playerKey, identity = ARC.Roster:GetPlayer()
    if not playerKey then return end
    local player = ARC.State:GetOrCreate(playerKey, identity, "SELF")
    self.active = true
    player.source = "SELF"
    player.lastSeen = now
    player.spells[spellID] = {
        spellID = spellID,
        known = true,
        readyAt = now + duration,
        remaining = duration,
        duration = duration,
        confidence = "SPOOF",
        lastUpdate = now,
    }
    ARC.State:Changed("spoof cast")
    if ARC.Comms.initialized then
        ARC.Comms:SendCast(spellID, { remaining = duration, duration = duration }, nil)
        ARC.Comms:ScheduleState(0.2, "spoof cast")
    end
    ARC:Print("SpoofTest used " .. ARC.SpellInfo:ResolveSpellName(spellID)
        .. " (" .. tostring(spellID) .. ") for " .. tostring(duration) .. " sec")
end

function SpoofTest:Reset()
    self.active = false
    ARC.Spellbook:Scan("spoof reset")
    if ARC.Comms.initialized then ARC.Comms:SendState(true, "spoof reset") end
    ARC:Print("SpoofTest cleared; real spell state restored")
end

function SpoofTest:CreateRow(index)
    local row = CreateFrame("Frame", nil, self.frame)
    row:SetHeight(30)
    row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 10, -61 - ((index - 1) * 31))
    row:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -10, -61 - ((index - 1) * 31))

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(26)
    row.icon:SetHeight(26)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)

    row.button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.button:SetWidth(48)
    row.button:SetHeight(22)
    row.button:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.button:SetText("USE")

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetJustifyH("LEFT")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
    row.label:SetPoint("RIGHT", row.button, "LEFT", -7, 0)

    self.rows[index] = row
    return row
end

function SpoofTest:Refresh()
    self.ids = sortedRegistryIDs()
    local pages = math.max(1, math.ceil(table.getn(self.ids) / PAGE_SIZE))
    self.page = math.max(1, math.min(self.page or 1, pages))
    local first = ((self.page - 1) * PAGE_SIZE) + 1
    for index = 1, PAGE_SIZE do
        local row = self.rows[index] or self:CreateRow(index)
        local spellID = self.ids[first + index - 1]
        if spellID then
            row.spellID = spellID
            row.icon:SetTexture(ARC.SpellInfo:ResolveSpellIcon(spellID))
            row.label:SetText(ARC.SpellInfo:ResolveSpellName(spellID) .. "  |cff888888" .. spellID .. "|r")
            row.button:SetScript("OnClick", function() self:Use(spellID) end)
            row:Show()
        else
            row:Hide()
        end
    end
    self.pageText:SetText("Page " .. tostring(self.page) .. "/" .. tostring(pages))
    if self.page <= 1 then self.previous:Disable() else self.previous:Enable() end
    if self.page >= pages then self.next:Disable() else self.next:Enable() end
end

function SpoofTest:Initialize()
    self.rows = {}
    self.page = 1
    local profile = ARC.db.profile.spoofUI
    local frame = CreateFrame("Frame", "ActuallyARCSpoofTestFrame", UIParent)
    frame:SetWidth(355)
    frame:SetHeight(379)
    frame:SetPoint(profile.point or "CENTER", UIParent, profile.point or "CENTER", profile.x or 320, profile.y or 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.03, 0.05, 0.08, 0.96)
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        profile.point, profile.x, profile.y = point, x, y
    end)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
    frame.title:SetText("ARC Spoof Test - " .. ARC.Constants.WIP_TEXT)

    frame.durationLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.durationLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -37)
    frame.durationLabel:SetText("Fake cooldown:")

    self.durationBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    self.durationBox:SetWidth(48)
    self.durationBox:SetHeight(20)
    self.durationBox:SetAutoFocus(false)
    self.durationBox:SetNumeric(true)
    self.durationBox:SetMaxLetters(6)
    self.durationBox:SetPoint("LEFT", frame.durationLabel, "RIGHT", 8, 0)
    self.durationBox:SetText(tostring(profile.duration or 30))

    frame.seconds = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.seconds:SetPoint("LEFT", self.durationBox, "RIGHT", 5, 0)
    frame.seconds:SetText("sec")

    self.previous = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    self.previous:SetWidth(58)
    self.previous:SetHeight(22)
    self.previous:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
    self.previous:SetText("Prev")
    self.previous:SetScript("OnClick", function() self.page = self.page - 1 self:Refresh() end)

    self.next = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    self.next:SetWidth(58)
    self.next:SetHeight(22)
    self.next:SetPoint("LEFT", self.previous, "RIGHT", 5, 0)
    self.next:SetText("Next")
    self.next:SetScript("OnClick", function() self.page = self.page + 1 self:Refresh() end)

    self.pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.pageText:SetPoint("LEFT", self.next, "RIGHT", 8, 0)

    self.reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    self.reset:SetWidth(68)
    self.reset:SetHeight(22)
    self.reset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
    self.reset:SetText("Reset")
    self.reset:SetScript("OnClick", function() self:Reset() end)

    self.frame = frame
    frame:Hide()
    self:Refresh()
end

function SpoofTest:Toggle()
    local shown = not self.frame:IsShown()
    if shown then self:Refresh() self.frame:Show() else self.frame:Hide() end
    return shown
end
