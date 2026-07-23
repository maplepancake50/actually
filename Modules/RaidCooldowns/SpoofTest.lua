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

local function formatDuration(seconds)
    seconds = math.floor((tonumber(seconds) or 0) + 0.5)
    if seconds >= 3600 and seconds % 3600 == 0 then
        return tostring(seconds / 3600) .. "h"
    end
    if seconds >= 60 then
        local minutes, remainder = math.floor(seconds / 60), seconds % 60
        return remainder > 0 and (tostring(minutes) .. "m " .. tostring(remainder) .. "s")
            or (tostring(minutes) .. "m")
    end
    return tostring(seconds) .. "s"
end

function SpoofTest:GetSpellCooldownDuration(spellID)
    local duration = tonumber(ARC.db.profile.spoofUI.duration) or 30
    return math.max(1, math.min(duration, ARC.Constants.MAX_COOLDOWN))
end

function SpoofTest:Use(spellID)
    if not ARC.db.profile.debug then
        ARC:Print("SpoofTest is disabled; use /arc debug before sending fake state")
        return false
    end
    local duration = self:GetSpellCooldownDuration(spellID)
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
        cooldownStartedAt = now,
        confidence = "SPOOF",
        lastUpdate = now,
    }
    ARC.State:Changed("spoof cast")
    if ARC.Comms.initialized then
        ARC.Comms:SendCast(spellID, { remaining = duration, duration = duration }, nil)
        ARC.Comms:ScheduleState(0.2, "spoof cast")
    end
    ARC:Print("SpoofTest used " .. ARC.SpellInfo:ResolveSpellName(spellID)
        .. " (" .. tostring(spellID) .. ") with a simulated "
        .. tostring(duration) .. " sec cooldown")
    self.resetToken = (self.resetToken or 0) + 1
    local token = self.resetToken
    self.resetAt = math.max(self.resetAt or 0, now + duration + 2)
    ARC:ScheduleTimer(function()
        if SpoofTest.active and SpoofTest.resetToken == token then
            SpoofTest:Reset()
            ARC:Print("SpoofTest auto-reset after the simulated cooldowns completed")
        end
    end, math.max(1, self.resetAt - now))
    return true
end

function SpoofTest:Reset(silent)
    if not self.active then return false end
    self.active = false
    self.resetToken = (self.resetToken or 0) + 1
    self.resetAt = nil
    ARC.Spellbook:Scan("spoof reset")
    if ARC.Comms.initialized then ARC.Comms:SendState(true, "spoof reset") end
    if not silent then ARC:Print("SpoofTest cleared; real spell state restored") end
    return true
end

function SpoofTest:CreateRow(index)
    local row = CreateFrame("Frame", nil, self.frame)
    row:SetHeight(30)
    row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 10, -55 - ((index - 1) * 31))
    row:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -10, -55 - ((index - 1) * 31))

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
            local duration = self:GetSpellCooldownDuration(spellID)
            row.spellID = spellID
            row.icon:SetTexture(ARC.SpellInfo:ResolveSpellIcon(spellID))
            row.label:SetText(ARC.SpellInfo:ResolveSpellName(spellID)
                .. "  |cff888888" .. spellID .. "|r  "
                .. "|cff66ccff" .. formatDuration(duration) .. "|r")
            row.button:Enable()
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
    profile.duration = tonumber(profile.duration) or 30
    local frame = CreateFrame("Frame", "ActuallyARCSpoofTestFrame", UIParent)
    frame:SetWidth(355)
    frame:SetHeight(373)
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
    frame:SetScript("OnHide", function()
        if SpoofTest.active then SpoofTest:Reset() end
    end)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
    frame.title:SetText("ARC Spoof Test - " .. ARC.Constants.WIP_TEXT)

    frame.cooldownNote = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.cooldownNote:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -34)
    frame.cooldownNote:SetText("Fake cooldown:")

    self.durationInput = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    self.durationInput:SetWidth(42)
    self.durationInput:SetHeight(20)
    self.durationInput:SetPoint("LEFT", frame.cooldownNote, "RIGHT", 8, 0)
    self.durationInput:SetAutoFocus(false)
    self.durationInput:SetNumeric(true)
    self.durationInput:SetMaxLetters(4)
    self.durationInput:SetText(tostring(profile.duration))
    self.durationInput:SetScript("OnEnterPressed", function(editBox)
        local duration = tonumber(editBox:GetText())
        if not duration or duration < 1 then duration = 30 end
        duration = math.floor(math.min(duration, ARC.Constants.MAX_COOLDOWN) + 0.5)
        profile.duration = duration
        editBox:SetText(tostring(duration))
        editBox:ClearFocus()
        self:Refresh()
    end)
    self.durationInput:SetScript("OnEscapePressed", function(editBox)
        editBox:SetText(tostring(profile.duration))
        editBox:ClearFocus()
    end)

    frame.cooldownUnit = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.cooldownUnit:SetPoint("LEFT", self.durationInput, "RIGHT", 5, 0)
    frame.cooldownUnit:SetText("seconds (press Enter)")

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
