Actually = Actually or {}
local Addon = Actually

local Discussion = {}
Addon.Discussion = Discussion
local Trim = Addon.Util.Trim
local ShortName = Addon.Util.ShortName
local NormalizeIdentity = Addon.Util.NormalizeCharacter
local SetBackdrop = Addon.Util.SetBackdrop

local MESSAGE_PREFIX = Addon.MESSAGE_PREFIX
local MAX_TEXT_LENGTH = 160

local function PlayerIdentity()
    return UnitName("player") or "Unknown"
end

local function CleanText(value)
    value = Trim(value)
    value = string.gsub(value, "[\r\n|]", " ")
    value = string.gsub(value, "%s+", " ")
    return string.sub(value, 1, MAX_TEXT_LENGTH)
end

local function SpellLabel(spellID)
    local name = GetSpellInfo and GetSpellInfo(spellID)
    return name or ("spell ID " .. tostring(spellID))
end

local function RecordOfficerActivity(action, author)
    if not Addon.Official or not Addon.Official.RecordActivity then
        return
    end
    if Addon.Official:RecordActivity(action, ShortName(author)) and Addon.Board then
        Addon.Board:RefreshAuditLog()
    end
end

function Discussion:GetThread(spellID)
    if not Addon.db then
        return nil
    end

    local key = tostring(spellID)
    local thread = Addon.db.discussions[key]
    if type(thread) ~= "table" then
        thread = {}
        Addon.db.discussions[key] = thread
    end
    thread.priority = type(thread.priority) == "table" and thread.priority or {}
    thread.priorityDeleted = type(thread.priorityDeleted) == "table" and thread.priorityDeleted or {}
    thread.comments = type(thread.comments) == "table" and thread.comments or {}
    thread.deleted = type(thread.deleted) == "table" and thread.deleted or {}

    local migratedPriority = {}
    for savedKey, entry in pairs(thread.priority) do
        if type(entry) == "table" then
            entry.author = ShortName(entry.author or savedKey)
            entry.officer = true
            migratedPriority[NormalizeIdentity(entry.author)] = entry
        end
    end
    thread.priority = migratedPriority

    for index, entry in ipairs(thread.comments) do
        entry.author = ShortName(entry.author)
        entry.id = entry.id or ("legacy." .. tostring(index) .. "." .. NormalizeIdentity(entry.author))
    end
    return thread
end

function Discussion:Broadcast(spellID, kind, text, commentID, officer)
    if not SendAddonMessage then
        return
    end

    local payload
    if kind == "C" then
        payload = "DISC|" .. tostring(spellID) .. "|C|" .. tostring(commentID or "") .. "|" .. (officer and "1" or "0") .. "|" .. (text or "")
    elseif kind == "D" then
        payload = "DISC|" .. tostring(spellID) .. "|" .. kind .. "|" .. tostring(commentID or "") .. "|" .. (text or "")
    else
        payload = "DISC|" .. tostring(spellID) .. "|" .. kind .. "|" .. (text or "")
    end
    if Addon.Sync and Addon.Sync.BroadcastLive then
        Addon.Sync:BroadcastLive(payload)
    elseif IsInGuild and IsInGuild() then
        SendAddonMessage(MESSAGE_PREFIX, payload, "GUILD")
    end
end

function Discussion:SetPriority(spellID, author, text, broadcast, eventTimestamp)
    local thread = self:GetThread(spellID)
    if not thread then
        return
    end

    text = CleanText(text)
    eventTimestamp = tonumber(eventTimestamp) or (time and time() or 0)
    local authorKey = NormalizeIdentity(author)
    local existing = thread.priority[authorKey]
    local hadNote = existing ~= nil
    local existingTime = existing and tonumber(existing.timestamp) or -1
    local deletedTime = tonumber(thread.priorityDeleted[authorKey]) or -1
    if text == "" then
        if eventTimestamp < existingTime or eventTimestamp <= deletedTime then
            return
        end
    elseif eventTimestamp < math.max(existingTime, deletedTime)
        or (eventTimestamp == existingTime and existing and text <= tostring(existing.text or "")) then
        return
    end
    if text == "" then
        thread.priority[authorKey] = nil
        thread.priorityDeleted[authorKey] = eventTimestamp
    else
        thread.priorityDeleted[authorKey] = nil
        thread.priority[authorKey] = {
            author = ShortName(author),
            text = text,
            timestamp = eventTimestamp,
            officer = true,
        }
    end

    if broadcast then
        self:Broadcast(spellID, "P", tostring(eventTimestamp) .. "|" .. text)
    end
    if broadcast then
        if text == "" then
            if hadNote then
                RecordOfficerActivity("Removed Officer Note for " .. SpellLabel(spellID) .. ".", author)
            end
        else
            RecordOfficerActivity("Officer Note for " .. SpellLabel(spellID) .. ": " .. text, author)
        end
    end
    if Addon.Sync then
        Addon.Sync:MarkDirty(broadcast == true)
    end
    self:Refresh()
end

function Discussion:AddComment(spellID, author, text, broadcast, commentID, officer)
    local thread = self:GetThread(spellID)
    if not thread then
        return
    end

    text = CleanText(text)
    if text == "" then
        return
    end

    commentID = commentID or Addon.Util.NewPersistentID()
    local commentTimestamp = tonumber(string.match(commentID, "^(%d+)")) or (time and time() or 0)
    if thread.deleted[commentID] then
        return
    end
    if officer == nil then
        officer = NormalizeIdentity(author) == NormalizeIdentity(PlayerIdentity())
            and Addon.Official and Addon.Official:IsOfficer()
    end
    for _, entry in ipairs(thread.comments) do
        if entry.id == commentID then
            return
        end
    end

    table.insert(thread.comments, {
        id = commentID,
        author = ShortName(author),
        text = text,
        timestamp = commentTimestamp,
        officer = officer == true,
    })
    if broadcast then
        self:Broadcast(spellID, "C", text, commentID, officer)
    end
    if broadcast and officer then
        RecordOfficerActivity("Officer community comment on " .. SpellLabel(spellID) .. ": " .. text, author)
    end
    if Addon.Sync then
        Addon.Sync:MarkDirty(broadcast == true)
    end
    self:Refresh()
end

function Discussion:CanDeleteComment(entry)
    if Addon.Official and Addon.Official:IsOfficer() then
        return true
    end
    return entry and NormalizeIdentity(entry.author) == NormalizeIdentity(PlayerIdentity())
end

function Discussion:DeleteComment(spellID, commentID, broadcast, deletedAt)
    local thread = self:GetThread(spellID)
    if not thread or not commentID then
        return
    end

    local deleted
    for index = #thread.comments, 1, -1 do
        if thread.comments[index].id == commentID then
            deleted = thread.comments[index]
            table.remove(thread.comments, index)
            break
        end
    end

    deletedAt = tonumber(deletedAt) or (time and time() or 0)
    thread.deleted[commentID] = math.max(tonumber(thread.deleted[commentID]) or 0, deletedAt)
    if broadcast then
        self:Broadcast(spellID, "D", tostring(deletedAt), commentID)
        if deleted and Addon.Official and Addon.Official:IsOfficer() then
            RecordOfficerActivity(
                "Moderated " .. ShortName(deleted.author) .. "'s comment on " .. SpellLabel(spellID) .. ": " .. tostring(deleted.text or ""),
                PlayerIdentity()
            )
        end
    end
    if Addon.Sync then
        Addon.Sync:MarkDirty(broadcast == true)
    end
    self:Refresh()
end

local function CreateScrollArea(parent, name, topOffset, height)
    local scroll = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, topOffset)
    scroll:SetWidth(712)
    scroll:SetHeight(height)

    local canvas = CreateFrame("Frame", nil, scroll)
    canvas:SetWidth(682)
    canvas:SetHeight(1)
    scroll:SetScrollChild(canvas)
    scroll.canvas = canvas
    scroll.rows = {}
    return scroll
end

local function GetRow(area, index)
    local row = area.rows[index]
    if row then
        return row
    end

    row = CreateFrame("Frame", nil, area.canvas)
    row:SetWidth(676)
    row:SetHeight(68)

    row.crown = row:CreateTexture(nil, "ARTWORK")
    row.crown:SetWidth(18)
    row.crown:SetHeight(18)
    row.crown:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -6)
    row.crown:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
    row.crown:Hide()

    row.author = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    row.author:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -8)
    row.author:SetPoint("TOPRIGHT", row, "TOPRIGHT", -72, -8)
    row.author:SetJustifyH("LEFT")

    row.body = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.body:SetPoint("TOPLEFT", row.author, "BOTTOMLEFT", 0, -4)
    row.body:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -31)
    row.body:SetJustifyH("LEFT")
    row.body:SetJustifyV("TOP")

    row.delete = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.delete:SetWidth(58)
    row.delete:SetHeight(19)
    row.delete:SetPoint("TOPRIGHT", row, "TOPRIGHT", -7, -6)
    row.delete:SetText("Delete")
    row.delete:SetScript("OnClick", function(self)
        local entry = self.entry
        if Discussion.spell and entry and Discussion:CanDeleteComment(entry) then
            Discussion:DeleteComment(Discussion.spell.spellID, entry.id, true)
        end
    end)
    row.delete:Hide()

    area.rows[index] = row
    return row
end

local function RefreshRows(area, entries, officerRows)
    for _, row in ipairs(area.rows) do
        row:Hide()
    end

    if #entries == 0 then
        local row = GetRow(area, 1)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", area.canvas, "TOPLEFT", 0, 0)
        row.author:SetText(officerRows and "No officer notes yet." or "No community discussion yet.")
        row.author:ClearAllPoints()
        row.author:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -8)
        row.author:SetPoint("TOPRIGHT", row, "TOPRIGHT", -72, -8)
        row.author:SetTextColor(0.6, 0.6, 0.65)
        row.body:SetText("")
        row.crown:Hide()
        row.delete:Hide()
        SetBackdrop(row, { 0.04, 0.04, 0.055, 0.72 }, { 0.16, 0.18, 0.22, 1 })
        row:Show()
        area.canvas:SetHeight(68)
        area:UpdateScrollChildRect()
        return
    end

    for index, entry in ipairs(entries) do
        local row = GetRow(area, index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", area.canvas, "TOPLEFT", 0, -(index - 1) * 72)
        local isOfficerPost = officerRows or entry.officer == true
        row.author:ClearAllPoints()
        row.author:SetPoint("TOPLEFT", row, "TOPLEFT", isOfficerPost and 31 or 10, -8)
        row.author:SetPoint("TOPRIGHT", row, "TOPRIGHT", -72, -8)
        if isOfficerPost then
            row.crown:Show()
        else
            row.crown:Hide()
        end
        row.author:SetText(ShortName(entry.author))
        row.body:SetText(entry.text or "")
        if officerRows then
            row.author:SetTextColor(1, 0.78, 0.22)
            row.body:SetTextColor(1, 0.88, 0.52)
            SetBackdrop(row, { 0.13, 0.09, 0.025, 0.88 }, { 0.68, 0.48, 0.10, 1 })
            row.delete:Hide()
        else
            row.author:SetTextColor(0.40, 0.78, 1)
            row.body:SetTextColor(0.92, 0.92, 0.95)
            SetBackdrop(row, { 0.04, 0.05, 0.07, 0.88 }, { 0.16, 0.34, 0.46, 1 })
            row.delete.entry = entry
            if Discussion:CanDeleteComment(entry) then
                row.delete:Show()
            else
                row.delete:Hide()
            end
        end
        row:Show()
    end

    area.canvas:SetHeight(math.max(1, #entries * 72))
    area:UpdateScrollChildRect()
end

function Discussion:Refresh()
    if not self.frame or not self.frame:IsShown() or not self.spell then
        return
    end

    local thread = self:GetThread(self.spell.spellID)
    local priority = {}
    for _, entry in pairs(thread.priority) do
        table.insert(priority, entry)
    end
    table.sort(priority, function(left, right)
        return string.lower(left.author or "") < string.lower(right.author or "")
    end)

    RefreshRows(self.priorityArea, priority, true)
    RefreshRows(self.communityArea, thread.comments, false)
    self.priorityArea:SetVerticalScroll(0)
    self.communityArea:SetVerticalScroll(math.max(0, self.communityArea.canvas:GetHeight() - self.communityArea:GetHeight()))

    local isOfficer = Addon.Official and Addon.Official:IsOfficer()
    local ownEntry = thread.priority[NormalizeIdentity(PlayerIdentity())]
    self.priorityInput:SetText(ownEntry and ownEntry.text or "")
    if isOfficer then
        self.priorityAccess:Show()
        self.priorityInput:Show()
        self.priorityButton:Show()
        self.priorityInput:Enable()
        self.priorityInput:SetTextColor(1, 0.86, 0.42)
        self.priorityButton:Enable()
        self.priorityAccess:SetText("Your officer note (saving an empty note removes it)")
        self.priorityAccess:SetTextColor(1, 0.78, 0.22)
        self.communityTitle:ClearAllPoints()
        self.communityTitle:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 18, -378)
        self.communityArea:ClearAllPoints()
        self.communityArea:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 18, -402)
        self.communityArea:SetHeight(205)
    else
        self.priorityAccess:Hide()
        self.priorityInput:Hide()
        self.priorityButton:Hide()
        self.communityTitle:ClearAllPoints()
        self.communityTitle:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 18, -278)
        self.communityArea:ClearAllPoints()
        self.communityArea:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 18, -302)
        self.communityArea:SetHeight(305)
    end
end

function Discussion:Show(spell)
    if not spell or not spell.spellID then
        return
    end
    if not self.frame then
        self:Create()
    end

    self.spell = spell
    self.title:SetText(spell.name .. " - Discussion")
    self.icon:SetTexture(spell.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    self.communityInput:SetText("")
    self.frame:Show()
    self:Refresh()
end

function Discussion:Create()
    if self.frame then
        return
    end

    local frame = CreateFrame("Frame", "ActuallyDiscussionFrame", UIParent)
    frame:SetWidth(760)
    frame:SetHeight(760)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 5)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    SetBackdrop(frame, { 0.025, 0.025, 0.038, 0.99 }, { 0.72, 0.52, 0.12, 1 })
    frame:Hide()
    self.frame = frame

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(42)
    icon:SetHeight(42)
    icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -13)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    self.icon = icon

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 10, 0)
    title:SetPoint("RIGHT", close, "LEFT", -8, 0)
    title:SetJustifyH("LEFT")
    self.title = title

    local priorityTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    priorityTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -64)
    priorityTitle:SetText("OFFICER NOTES")
    priorityTitle:SetTextColor(1, 0.78, 0.22)

    self.priorityArea = CreateScrollArea(frame, "ActuallyDiscussionPriorityScroll", -88, 170)

    local priorityAccess = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    priorityAccess:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -268)
    self.priorityAccess = priorityAccess

    local priorityInput = CreateFrame("EditBox", nil, frame)
    priorityInput:SetWidth(600)
    priorityInput:SetHeight(65)
    priorityInput:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -290)
    priorityInput:SetMultiLine(true)
    priorityInput:SetAutoFocus(false)
    priorityInput:SetMaxLetters(MAX_TEXT_LENGTH)
    priorityInput:SetTextInsets(7, 7, 7, 7)
    priorityInput:SetFontObject(GameFontHighlight)
    SetBackdrop(priorityInput, { 0.07, 0.05, 0.02, 0.94 }, { 0.60, 0.43, 0.10, 1 })
    self.priorityInput = priorityInput

    local priorityButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    priorityButton:SetWidth(94)
    priorityButton:SetHeight(24)
    priorityButton:SetPoint("LEFT", priorityInput, "RIGHT", 8, 0)
    priorityButton:SetText("Save Note")
    priorityButton:SetScript("OnClick", function()
        if not Discussion.spell or not Addon.Official or not Addon.Official:IsOfficer() then
            return
        end
        Discussion:SetPriority(Discussion.spell.spellID, PlayerIdentity(), priorityInput:GetText(), true)
    end)
    self.priorityButton = priorityButton

    local communityTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    communityTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -378)
    communityTitle:SetText("COMMUNITY DISCUSSION")
    communityTitle:SetTextColor(0.40, 0.78, 1)
    self.communityTitle = communityTitle

    self.communityArea = CreateScrollArea(frame, "ActuallyDiscussionCommunityScroll", -402, 205)

    local communityLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    communityLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -616)
    communityLabel:SetText("Add your comment")

    local communityInput = CreateFrame("EditBox", nil, frame)
    communityInput:SetWidth(600)
    communityInput:SetHeight(75)
    communityInput:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -638)
    communityInput:SetMultiLine(true)
    communityInput:SetAutoFocus(false)
    communityInput:SetMaxLetters(MAX_TEXT_LENGTH)
    communityInput:SetTextInsets(7, 7, 7, 7)
    communityInput:SetFontObject(GameFontHighlight)
    SetBackdrop(communityInput, { 0.04, 0.05, 0.07, 0.96 }, { 0.16, 0.40, 0.55, 1 })
    self.communityInput = communityInput

    local postButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    postButton:SetWidth(94)
    postButton:SetHeight(24)
    postButton:SetPoint("LEFT", communityInput, "RIGHT", 8, 0)
    postButton:SetText("Post")
    postButton:SetScript("OnClick", function()
        if not Discussion.spell then
            return
        end
        local text = CleanText(communityInput:GetText())
        if text == "" then
            return
        end
        Discussion:AddComment(Discussion.spell.spellID, PlayerIdentity(), text, true)
        communityInput:SetText("")
    end)

    priorityInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    communityInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
end

local messageFrame = CreateFrame("Frame")
messageFrame:RegisterEvent("CHAT_MSG_ADDON")
messageFrame:SetScript("OnEvent", function(_, event, prefix, message, channel, sender)
    if event ~= "CHAT_MSG_ADDON" or prefix ~= MESSAGE_PREFIX
        or (channel ~= "GUILD" and channel ~= "WHISPER") or not Addon.db then
        return
    end

    if NormalizeIdentity(sender) == NormalizeIdentity(PlayerIdentity()) then
        return
    end

    local spellIDText, commentID, officerFlag, text = string.match(message or "", "^DISC|(%d+)|C|([^|]+)|([01])|(.*)$")
    if spellIDText then
        local spellID = tonumber(spellIDText)
        if not spellID then
            return
        end
        Discussion:AddComment(spellID, ShortName(sender), text, false, commentID, officerFlag == "1")
        return
    end

    local kind
    spellIDText, kind, commentID, text = string.match(message or "", "^DISC|(%d+)|([CD])|([^|]*)|(.*)$")
    if spellIDText then
        local spellID = tonumber(spellIDText)
        if not spellID or commentID == "" then
            return
        end

        if kind == "D" then
            Discussion:DeleteComment(spellID, commentID, false, tonumber(text))
        else
            Discussion:AddComment(spellID, ShortName(sender), text, false, commentID)
        end
        return
    end

    local priorityTimestamp
    spellIDText, priorityTimestamp, text = string.match(message or "", "^DISC|(%d+)|P|(%d+)|(.*)$")
    if spellIDText then
        local spellID = tonumber(spellIDText)
        if spellID then
            Discussion:SetPriority(spellID, ShortName(sender), text, false, tonumber(priorityTimestamp))
        end
        return
    end

    spellIDText, kind, text = string.match(message or "", "^DISC|(%d+)|([PC])|(.*)$")
    local spellID = tonumber(spellIDText)
    if not spellID then
        return
    end

    if kind == "P" then
        Discussion:SetPriority(spellID, ShortName(sender), text, false)
    else
        Discussion:AddComment(spellID, ShortName(sender), text, false)
    end
end)
