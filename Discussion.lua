Actually = Actually or {}
local Addon = Actually

local Discussion = {}
Addon.Discussion = Discussion

local MESSAGE_PREFIX = "ACTUALLY"
local MAX_TEXT_LENGTH = 160
local MAX_COMMUNITY_POSTS = 100

local function Trim(value)
    return string.gsub(value or "", "^%s*(.-)%s*$", "%1")
end

local function NormalizeIdentity(identity)
    identity = string.gsub(Trim(identity), "%s+", "")
    return string.lower(identity)
end

local function PlayerIdentity()
    if Addon.Official and Addon.Official.GetPlayerIdentity then
        return Addon.Official:GetPlayerIdentity()
    end
    return UnitName("player") or "Unknown"
end

local function CleanText(value)
    value = Trim(value)
    value = string.gsub(value, "[\r\n|]", " ")
    value = string.gsub(value, "%s+", " ")
    return string.sub(value, 1, MAX_TEXT_LENGTH)
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
    thread.comments = type(thread.comments) == "table" and thread.comments or {}
    return thread
end

function Discussion:Broadcast(spellID, kind, text)
    if not SendAddonMessage or not IsInGuild or not IsInGuild() then
        return
    end
    SendAddonMessage(MESSAGE_PREFIX, "DISC|" .. tostring(spellID) .. "|" .. kind .. "|" .. text, "GUILD")
end

function Discussion:SetPriority(spellID, author, text, broadcast)
    local thread = self:GetThread(spellID)
    if not thread then
        return
    end

    text = CleanText(text)
    local authorKey = NormalizeIdentity(author)
    if text == "" then
        thread.priority[authorKey] = nil
    else
        thread.priority[authorKey] = {
            author = author,
            text = text,
            timestamp = time and time() or 0,
        }
    end

    if broadcast then
        self:Broadcast(spellID, "P", text)
    end
    self:Refresh()
end

function Discussion:AddComment(spellID, author, text, broadcast)
    local thread = self:GetThread(spellID)
    if not thread then
        return
    end

    text = CleanText(text)
    if text == "" then
        return
    end

    table.insert(thread.comments, {
        author = author,
        text = text,
        timestamp = time and time() or 0,
    })
    while #thread.comments > MAX_COMMUNITY_POSTS do
        table.remove(thread.comments, 1)
    end

    if broadcast then
        self:Broadcast(spellID, "C", text)
    end
    self:Refresh()
end

local function CreateScrollArea(parent, topOffset, height)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, topOffset)
    scroll:SetWidth(592)
    scroll:SetHeight(height)

    local canvas = CreateFrame("Frame", nil, scroll)
    canvas:SetWidth(562)
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
    row:SetWidth(556)
    row:SetHeight(56)

    row.author = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.author:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -7)
    row.author:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -7)
    row.author:SetJustifyH("LEFT")

    row.body = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.body:SetPoint("TOPLEFT", row.author, "BOTTOMLEFT", 0, -4)
    row.body:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -27)
    row.body:SetJustifyH("LEFT")
    row.body:SetJustifyV("TOP")

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
        row.author:SetText(officerRows and "No officer reasoning yet." or "No community discussion yet.")
        row.author:SetTextColor(0.6, 0.6, 0.65)
        row.body:SetText("")
        SetBackdrop(row, { 0.04, 0.04, 0.055, 0.72 }, { 0.16, 0.18, 0.22, 1 })
        row:Show()
        area.canvas:SetHeight(56)
        area:UpdateScrollChildRect()
        return
    end

    for index, entry in ipairs(entries) do
        local row = GetRow(area, index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", area.canvas, "TOPLEFT", 0, -(index - 1) * 60)
        row.author:SetText(entry.author or "Unknown")
        row.body:SetText(entry.text or "")
        if officerRows then
            row.author:SetTextColor(1, 0.78, 0.22)
            row.body:SetTextColor(1, 0.88, 0.52)
            SetBackdrop(row, { 0.13, 0.09, 0.025, 0.88 }, { 0.68, 0.48, 0.10, 1 })
        else
            row.author:SetTextColor(0.40, 0.78, 1)
            row.body:SetTextColor(0.92, 0.92, 0.95)
            SetBackdrop(row, { 0.04, 0.05, 0.07, 0.88 }, { 0.16, 0.34, 0.46, 1 })
        end
        row:Show()
    end

    area.canvas:SetHeight(math.max(1, #entries * 60))
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
        self.priorityInput:Enable()
        self.priorityInput:SetTextColor(1, 0.86, 0.42)
        self.priorityButton:Enable()
        self.priorityAccess:SetText("Your officer note (saving an empty note removes it)")
        self.priorityAccess:SetTextColor(1, 0.78, 0.22)
    else
        self.priorityInput:Disable()
        self.priorityInput:SetText("Officer access required")
        self.priorityInput:SetTextColor(0.48, 0.48, 0.52)
        self.priorityButton:Disable()
        self.priorityAccess:SetText("Officer priority reasoning")
        self.priorityAccess:SetTextColor(0.65, 0.55, 0.30)
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
    self.title:SetText(spell.name .. " — Reasoning & Discussion")
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
    frame:SetWidth(640)
    frame:SetHeight(650)
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
    icon:SetWidth(36)
    icon:SetHeight(36)
    icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -13)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    self.icon = icon

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 10, 0)
    title:SetPoint("RIGHT", close, "LEFT", -8, 0)
    title:SetJustifyH("LEFT")
    self.title = title

    local priorityTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    priorityTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -58)
    priorityTitle:SetText("OFFICER PRIORITY REASONING")
    priorityTitle:SetTextColor(1, 0.78, 0.22)

    self.priorityArea = CreateScrollArea(frame, -78, 140)

    local priorityAccess = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    priorityAccess:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -226)
    self.priorityAccess = priorityAccess

    local priorityInput = CreateFrame("EditBox", nil, frame)
    priorityInput:SetWidth(500)
    priorityInput:SetHeight(54)
    priorityInput:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -245)
    priorityInput:SetMultiLine(true)
    priorityInput:SetAutoFocus(false)
    priorityInput:SetMaxLetters(MAX_TEXT_LENGTH)
    priorityInput:SetTextInsets(7, 7, 7, 7)
    priorityInput:SetFontObject(GameFontHighlightSmall)
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

    local communityTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    communityTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -314)
    communityTitle:SetText("COMMUNITY DISCUSSION")
    communityTitle:SetTextColor(0.40, 0.78, 1)

    self.communityArea = CreateScrollArea(frame, -334, 168)

    local communityLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    communityLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -510)
    communityLabel:SetText("Add your comment")

    local communityInput = CreateFrame("EditBox", nil, frame)
    communityInput:SetWidth(500)
    communityInput:SetHeight(58)
    communityInput:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -529)
    communityInput:SetMultiLine(true)
    communityInput:SetAutoFocus(false)
    communityInput:SetMaxLetters(MAX_TEXT_LENGTH)
    communityInput:SetTextInsets(7, 7, 7, 7)
    communityInput:SetFontObject(GameFontHighlightSmall)
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
    if event ~= "CHAT_MSG_ADDON" or prefix ~= MESSAGE_PREFIX or channel ~= "GUILD" or not Addon.db then
        return
    end

    if NormalizeIdentity(sender) == NormalizeIdentity(PlayerIdentity()) then
        return
    end

    local spellIDText, kind, text = string.match(message or "", "^DISC|(%d+)|([PC])|(.*)$")
    local spellID = tonumber(spellIDText)
    if not spellID then
        return
    end

    if kind == "P" then
        Discussion:SetPriority(spellID, sender, text, false)
    else
        Discussion:AddComment(spellID, sender, text, false)
    end
end)
