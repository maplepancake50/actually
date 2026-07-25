local ARC = Actually.Modules.RaidCooldowns
local UserList = ARC:NewModule("UserList")

local MAX_ROWS = 40
local ROWS_PER_COLUMN = 20
local COLUMN_WIDTH = 390
local SINGLE_COLUMN_WIDTH = 410
local DOUBLE_COLUMN_WIDTH = 800

local function playerName(identity)
    if not identity then return "Unknown" end
    return identity.name or identity.shortName or "Unknown"
end

local function formatGuild(guild, guildKnown)
    if not guildKnown then return "|cff777f8aUnknown guild|r" end
    if type(guild) ~= "string" or guild == "" then
        return "|cff8a929cUnguilded|r"
    end
    return "|cff70c6ff<" .. guild .. ">|r"
end

function UserList:IsAllowed()
    return ARC.Roster and ARC.Roster:IsLocalCoordinator()
end

function UserList:GetUsers()
    local users = {}
    local localKey, localIdentity = ARC.Roster:GetPlayer()
    if localKey then
        table.insert(users, {
            key = localKey,
            name = playerName(localIdentity),
            guild = localIdentity and localIdentity.guild,
            guildKnown = localIdentity and localIdentity.guildKnown,
            localPlayer = true,
        })
    end

    for key in pairs(ARC.State.peers or {}) do
        if key ~= localKey then
            local identity = ARC.Roster.byKey[key]
            if identity then
                table.insert(users, {
                    key = key,
                    name = playerName(identity),
                    guild = identity.guild,
                    guildKnown = identity.guildKnown,
                    connected = identity.connected,
                })
            end
        end
    end

    table.sort(users, function(left, right)
        return string.lower(left.name) < string.lower(right.name)
    end)
    return users
end

function UserList:CreateRow(index)
    local row = CreateFrame("Frame", nil, self.frame)
    row:SetWidth(375)
    row:SetHeight(20)

    row.number = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.number:SetWidth(24)
    row.number:SetJustifyH("RIGHT")
    row.number:SetPoint("LEFT", row, "LEFT", 0, 0)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetWidth(100)
    row.name:SetJustifyH("LEFT")
    row.name:SetPoint("LEFT", row.number, "RIGHT", 9, 0)

    row.guild = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.guild:SetWidth(120)
    row.guild:SetJustifyH("LEFT")
    row.guild:SetPoint("LEFT", row.name, "RIGHT", 6, 0)

    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.status:SetJustifyH("RIGHT")
    row.status:SetPoint("RIGHT", row, "RIGHT", 0, 0)

    self.rows[index] = row
    return row
end

function UserList:Refresh()
    if not self.frame then return end
    if self.frame:IsShown() and not self:IsAllowed() then
        self.frame:Hide()
        ARC:Print("user list closed: actually officer or leader access is required")
        return
    end

    local users = self:GetUsers()
    local count = math.min(table.getn(users), MAX_ROWS)
    local columns = count > ROWS_PER_COLUMN and 2 or 1
    self.frame.count:SetText(tostring(table.getn(users)) .. " player"
        .. (table.getn(users) == 1 and "" or "s") .. " detected")
    if count == 0 then self.frame.empty:Show() else self.frame.empty:Hide() end

    for index = 1, count do
        local user = users[index]
        local row = self.rows[index] or self:CreateRow(index)
        local column = math.floor((index - 1) / ROWS_PER_COLUMN)
        local rowIndex = (index - 1) % ROWS_PER_COLUMN
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.frame, "TOPLEFT",
            13 + (column * COLUMN_WIDTH), -58 - (rowIndex * 20))
        row.number:SetText(tostring(index) .. ".")
        row.name:SetText(user.name)
        row.guild:SetText(formatGuild(user.guild, user.guildKnown))
        if user.localPlayer then
            row.status:SetText("|cff69ccf0Installed (you)|r")
        elseif user.connected == false then
            row.status:SetText("|cff888888Offline|r")
        else
            row.status:SetText("|cff55dd55Installed|r")
        end
        row:Show()
    end
    for index = count + 1, MAX_ROWS do
        if self.rows[index] then self.rows[index]:Hide() end
    end

    self.frame:SetWidth(columns == 2 and DOUBLE_COLUMN_WIDTH or SINGLE_COLUMN_WIDTH)
    self.frame:SetHeight(math.max(105, 78 + (math.min(count, ROWS_PER_COLUMN) * 20)))
end

function UserList:RequestRefresh()
    ARC.Roster:Scan()
    ARC.Comms:RequestState(true)
    self:Refresh()
    if self.refreshTimer then ARC:CancelTimer(self.refreshTimer, true) end
    self.refreshTimer = ARC:ScheduleTimer(function()
        self.refreshTimer = nil
        self:Refresh()
    end, 0.8)
end

function UserList:Open()
    if not self:IsAllowed() then
        ARC:Print("only an actually officer or the actually leader can open the user list")
        return false
    end
    self.frame:Show()
    self:RequestRefresh()
    return true
end

function UserList:Initialize()
    self.rows = {}

    local frame = CreateFrame("Frame", "ActuallyUserListFrame", UIParent)
    frame:SetWidth(SINGLE_COLUMN_WIDTH)
    frame:SetHeight(105)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(window) window:StartMoving() end)
    frame:SetScript("OnDragStop", function(window) window:StopMovingOrSizing() end)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.04, 0.05, 0.08, 0.96)
    frame:SetBackdropBorderColor(0.30, 0.65, 0.85, 1)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -11)
    frame.title:SetText("Actually Users")

    frame.count = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.count:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -6)

    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)

    frame.refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.refresh:SetWidth(66)
    frame.refresh:SetHeight(20)
    frame.refresh:SetPoint("TOPRIGHT", frame.close, "TOPLEFT", -3, -4)
    frame.refresh:SetText("Refresh")
    frame.refresh:SetScript("OnClick", function() self:RequestRefresh() end)

    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    frame.empty:SetPoint("CENTER", frame, "CENTER", 0, -12)
    frame.empty:SetText("No Actually users detected")

    frame:SetScript("OnShow", function() self:Refresh() end)
    frame:Hide()
    self.frame = frame
    self.initialized = true
end
