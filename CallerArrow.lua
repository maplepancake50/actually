Actually = Actually or {}
local Addon = Actually

-- Player-facing pointer for the officer-selected shot caller. Only the small
-- caller-name assignment is synchronized; bearings remain entirely local.
local CallerArrow = {}
Addon.CallerArrow = CallerArrow

local TWO_PI = math.pi * 2
local UPDATE_INTERVAL = 0.05
local MAP_REFRESH_INTERVAL = 1
local DEFAULT_MAP_ASPECT = 1.5
local CALLER_PROTOCOL = 1
local CALLER_KIND = "SC"
local DEFAULT_ARROW_SIZE = 110
local MIN_ARROW_SIZE = 72
local MAX_ARROW_SIZE = 180
local DEATH_PULSE_SECONDS = 3
local DEATH_HOLD_SECONDS = 6
local DEATH_FADE_SECONDS = 1

local function PlayerKey(identity)
    return Addon.Util.NormalizeCharacter(identity)
end

local function Encode(value)
    local encoded = string.gsub(tostring(value or ""), "([^%w%-%._ ])", function(character)
        return string.format("%%%02X", string.byte(character))
    end)
    return encoded
end

local function Decode(value)
    local decoded = string.gsub(value or "", "%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
    return decoded
end

local function IsWorldMapVisible()
    return WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown()
end

local function FindRaidUnit(identity)
    local wanted = PlayerKey(identity)
    if wanted == "" then return nil end
    if PlayerKey(UnitName and UnitName("player")) == wanted then
        return "player"
    end
    local count = GetNumRaidMembers and GetNumRaidMembers() or 0
    for index = 1, count do
        local unit = "raid" .. tostring(index)
        local name = UnitName and UnitName(unit)
        if not name and GetRaidRosterInfo then
            name = GetRaidRosterInfo(index)
        end
        if PlayerKey(name) == wanted then
            return unit
        end
    end
    return nil
end

local function IsRaidMember(identity)
    return FindRaidUnit(identity) ~= nil
end

local function ValidPosition(x, y)
    x, y = tonumber(x), tonumber(y)
    return x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1
        and not (x == 0 and y == 0)
end

local function MapAspect()
    if WorldMapDetailFrame and WorldMapDetailFrame.GetWidth and WorldMapDetailFrame.GetHeight then
        local width = tonumber(WorldMapDetailFrame:GetWidth()) or 0
        local height = tonumber(WorldMapDetailFrame:GetHeight()) or 0
        if width > 0 and height > 0 then return width / height end
    end
    return DEFAULT_MAP_ASPECT
end

local function RotateTexture(texture, angle)
    -- Same square-texture rotation principle used by waypoint arrows: rotate
    -- the four texture corners around their center rather than rotating a UI frame.
    local sine = math.sin(angle + 2.3561944901923) * 0.70710678118655
    local cosine = math.cos(angle + 2.3561944901923) * 0.70710678118655
    texture:SetTexCoord(
        0.5 - sine, 0.5 + cosine,
        0.5 + cosine, 0.5 + sine,
        0.5 - cosine, 0.5 - sine,
        0.5 + sine, 0.5 - cosine
    )
end

function CallerArrow:Create()
    if self.frame then return self.frame end

    local frame = CreateFrame("Button", "ActuallyCallerArrowFrame", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:RegisterForClicks("RightButtonUp")
    frame:EnableMouseWheel(true)

    local arrow = frame:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    arrow:SetPoint("TOP", frame, "TOP", 0, 0)
    arrow:SetBlendMode("BLEND")
    arrow:SetAlpha(1)
    arrow:SetVertexColor(0.15, 0.86, 1, 1)
    frame.arrow = arrow

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", arrow, "BOTTOM", 0, 3)
    title:SetWidth(240)
    title:SetHeight(38)
    title:SetJustifyH("CENTER")
    title:SetJustifyV("TOP")
    title:SetTextColor(0.82, 0.94, 1)
    frame.title = title

    frame:SetScript("OnDragStart", function(owner)
        owner:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(owner)
        owner:StopMovingOrSizing()
        CallerArrow:SavePosition()
    end)
    frame:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            CallerArrow:ShowMenu()
        end
    end)
    frame:SetScript("OnMouseWheel", function(_, delta)
        CallerArrow:SetArrowSize(CallerArrow:GetArrowSize() + (delta > 0 and 10 or -10))
    end)
    self.frame = frame
    self.menuFrame = CreateFrame("Frame", "ActuallyCallerArrowMenu", UIParent, "UIDropDownMenuTemplate")
    self:SetArrowSize(Addon.db.callerArrow and Addon.db.callerArrow.size or DEFAULT_ARROW_SIZE)
    self:RestorePosition()
    frame:Hide()
    return frame
end

function CallerArrow:GetArrowSize()
    return tonumber(Addon.db and Addon.db.callerArrow and Addon.db.callerArrow.size)
        or DEFAULT_ARROW_SIZE
end

function CallerArrow:SetArrowSize(size)
    size = math.max(MIN_ARROW_SIZE, math.min(MAX_ARROW_SIZE,
        math.floor((tonumber(size) or DEFAULT_ARROW_SIZE) + 0.5)))
    Addon.db.callerArrow = type(Addon.db.callerArrow) == "table" and Addon.db.callerArrow or {}
    Addon.db.callerArrow.size = size
    if self.frame then
        self.frame:SetWidth(size + 12)
        self.frame:SetHeight(size + 40)
        self.frame.arrow:SetWidth(size)
        self.frame.arrow:SetHeight(size)
    end
    return size
end

function CallerArrow:ShowMenu()
    if not self.menuFrame or not EasyMenu then return end
    local current = self:GetArrowSize()
    local sizes = {
        { text = "Small", value = 80 },
        { text = "Medium", value = 110 },
        { text = "Large", value = 140 },
        { text = "Extra Large", value = 180 },
    }
    local menu = {
        { text = "Shot Caller", isTitle = true, notCheckable = true },
    }
    for _, choice in ipairs(sizes) do
        local value = choice.value
        table.insert(menu, {
            text = choice.text,
            checked = math.abs(current - value) < 5,
            func = function() CallerArrow:SetArrowSize(value) end,
        })
    end
    table.insert(menu, {
        text = "Hide", notCheckable = true,
        func = function() CallerArrow:SetEnabled(false) end,
    })
    EasyMenu(menu, self.menuFrame, "cursor", 0, 0, "MENU", 2)
end

function CallerArrow:UpdateDeathState(dead)
    dead = dead and true or false
    if self.targetDead == dead then return end
    self.targetDead = dead
    if not self.frame then return end
    if dead then
        self.frame.arrow:Hide()
        self.frame.title:SetTextColor(1.00, 0.28, 0.24)
        self.frame.title:SetFontObject(GameFontNormalLarge)
        self.frame.title:SetText("SHOT CALLER DEAD\nSOMEONE ELSE SHOT CALL")
        self.frame.title:SetAlpha(1)
        self.deathPulseStartedAt = GetTime and GetTime() or 0
        self.deathAlertExpired = nil
    else
        self.frame.arrow:Show()
        self.frame.arrow:SetVertexColor(0.15, 0.86, 1.00, 1)
        self.frame.title:SetTextColor(0.82, 0.94, 1.00)
        self.frame.title:SetFontObject(GameFontNormal)
        self.frame.title:SetText("SHOT CALLER")
        self.frame.title:SetAlpha(1)
        self.deathPulseStartedAt = nil
        self.deathAlertExpired = nil
    end
end

function CallerArrow:UpdateDeathAlert()
    if not self.targetDead or not self.frame then return false end
    if self.deathAlertExpired or not self.deathPulseStartedAt then return false end
    local elapsed = (GetTime and GetTime() or 0) - self.deathPulseStartedAt
    if elapsed < DEATH_PULSE_SECONDS then
        local wave = (math.sin(elapsed * math.pi * 3) + 1) / 2
        self.frame.title:SetAlpha(0.50 + wave * 0.50)
        return true
    end
    local fadeStartsAt = DEATH_PULSE_SECONDS + DEATH_HOLD_SECONDS
    if elapsed < fadeStartsAt then
        self.frame.title:SetAlpha(1)
        return true
    end
    if elapsed < fadeStartsAt + DEATH_FADE_SECONDS then
        self.frame.title:SetAlpha(1 - ((elapsed - fadeStartsAt) / DEATH_FADE_SECONDS))
        return true
    end
    self.frame.title:SetAlpha(0)
    self.deathAlertExpired = true
    return false
end

function CallerArrow:RestorePosition()
    local frame = self.frame
    if not frame then return end
    Addon.db.callerArrow = type(Addon.db.callerArrow) == "table" and Addon.db.callerArrow or {}
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER",
        tonumber(Addon.db.callerArrow.x) or 0,
        tonumber(Addon.db.callerArrow.y) or -145)
end

function CallerArrow:SavePosition()
    if not self.frame then return end
    local frameX, frameY = self.frame:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    if not frameX or not frameY or not parentX or not parentY then return end
    Addon.db.callerArrow = type(Addon.db.callerArrow) == "table" and Addon.db.callerArrow or {}
    Addon.db.callerArrow.x = frameX - parentX
    Addon.db.callerArrow.y = frameY - parentY
    self:RestorePosition()
end

function CallerArrow:SetTarget(identity, revision, force)
    local currentRevision = Addon.db.assistLog.selectedCallerRevision or ""
    if not force and revision and currentRevision ~= "" and revision < currentRevision then
        return false
    end
    self.targetName = Addon.Util.ShortName(identity)
    Addon.db.assistLog.selectedCaller = self.targetName
    if revision then Addon.db.assistLog.selectedCallerRevision = revision end
    self.elapsed = UPDATE_INTERVAL
    self.mapRefreshElapsed = MAP_REFRESH_INTERVAL
    self:RefreshVisibility()
    if Addon.CacheTips and Addon.CacheTips.RefreshArrowToggle then
        Addon.CacheTips:RefreshArrowToggle()
    end
    return true
end

function CallerArrow:IsEnabled()
    return Addon.db and Addon.db.callerArrow and Addon.db.callerArrow.enabled == true
end

function CallerArrow:IsTargetInRaid()
    local unit = self.targetName and FindRaidUnit(self.targetName)
    return unit ~= nil and unit ~= "player"
end

function CallerArrow:SetEnabled(enabled, notifyIfUnavailable)
    Addon.db.callerArrow = type(Addon.db.callerArrow) == "table" and Addon.db.callerArrow or {}
    Addon.db.callerArrow.enabled = enabled == true
    if self.events then
        self.events:SetScript("OnUpdate", enabled and function(_, elapsed)
            CallerArrow:OnUpdate(elapsed)
        end or nil)
    end
    self.elapsed = UPDATE_INTERVAL
    self.mapRefreshElapsed = MAP_REFRESH_INTERVAL
    if enabled and not self:IsTargetInRaid() and notifyIfUnavailable then
        Addon:Print("You must be in a raid with the shotcaller to see the arrow.")
    end
    if enabled then self:RefreshVisibility() else self:Hide() end
    if Addon.CacheTips and Addon.CacheTips.RefreshArrowToggle then
        Addon.CacheTips:RefreshArrowToggle()
    end
end

function CallerArrow:NewRevision()
    local epoch = time and time() or 0
    local savedClock = tonumber(string.match(Addon.db.assistLog.selectedCallerRevision or "", "^(%d+)")) or 0
    epoch = math.max(epoch, savedClock + 1)
    local author = PlayerKey(UnitName and UnitName("player"))
    return string.format("%010d.%06d.%s", epoch, math.random(0, 999999), author)
end

function CallerArrow:BroadcastTarget(identity, revision, channel, target)
    if not identity or identity == "" then return false end
    if not Addon.Official or not Addon.Official:IsOfficer() then return false end
    local message = table.concat({ CALLER_KIND, tostring(CALLER_PROTOCOL), "S",
        Encode(identity), Encode(revision or Addon.db.assistLog.selectedCallerRevision or "") }, "|")
    if Addon.Sync and Addon.Sync.QueueMessage then
        return Addon.Sync:QueueMessage(message, channel or "RAID", target, "ALERT")
    end
    if not SendAddonMessage then return false end
    return pcall(SendAddonMessage, Addon.MESSAGE_PREFIX, message, channel or "RAID", target)
end

function CallerArrow:AssignTarget(identity)
    local revision = self:NewRevision()
    self:SetTarget(identity, revision, true)
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        self:BroadcastTarget(self.targetName, revision, "RAID")
    end
end

function CallerArrow:RequestTarget()
    if not GetNumRaidMembers or GetNumRaidMembers() == 0 then return end
    local now = GetTime and GetTime() or 0
    if now - (self.lastQueryAt or -100) < 8 then return end
    self.lastQueryAt = now
    local message = table.concat({ CALLER_KIND, tostring(CALLER_PROTOCOL), "Q" }, "|")
    if Addon.Sync and Addon.Sync.QueueMessage then
        Addon.Sync:QueueMessage(message, "RAID", nil, "ALERT")
    elseif SendAddonMessage then
        pcall(SendAddonMessage, Addon.MESSAGE_PREFIX, message, "RAID")
    end
end

function CallerArrow:HandleMessage(message, channel, sender)
    if not sender or not IsRaidMember(sender) then return end
    local action, rest = string.match(message or "", "^" .. CALLER_KIND .. "|"
        .. tostring(CALLER_PROTOCOL) .. "|([^|]+)|?(.*)$")
    if action == "Q" and (channel == "RAID" or channel == "WHISPER") then
        if Addon.Official and Addon.Official:IsOfficer() then
            local selected = Addon.db.assistLog.selectedCaller
            if selected and selected ~= "" then
                self:BroadcastTarget(selected, Addon.db.assistLog.selectedCallerRevision, "WHISPER", sender)
            end
        end
    elseif action == "S" and (channel == "RAID" or channel == "WHISPER")
        and Addon.Official and Addon.Official:IsOfficer(sender) then
        local identity, revision = string.match(rest, "^([^|]+)|?(.*)$")
        identity, revision = Decode(identity), Decode(revision)
        if identity ~= "" and IsRaidMember(identity) then
            self:SetTarget(identity, revision ~= "" and revision or nil)
        end
    end
end

function CallerArrow:Hide()
    if self.frame then self.frame:Hide() end
end

function CallerArrow:RefreshVisibility()
    if not self:IsEnabled() or not self.targetName then
        self:Hide()
        return false
    end
    local unit = FindRaidUnit(self.targetName)
    if not unit or unit == "player" then
        self:Hide()
        return false
    end
    if UnitIsConnected and not UnitIsConnected(unit) then
        self:Hide()
        return false
    end
    self.unit = unit
    return true
end

function CallerArrow:ReadPositions()
    if not GetPlayerMapPosition then return nil end
    local playerX, playerY = GetPlayerMapPosition("player")
    local targetX, targetY = GetPlayerMapPosition(self.unit)
    if ValidPosition(playerX, playerY) and ValidPosition(targetX, targetY) then
        return playerX, playerY, targetX, targetY
    end

    if not IsWorldMapVisible() and SetMapToCurrentZone
        and (self.mapRefreshElapsed or 0) >= MAP_REFRESH_INTERVAL then
        self.mapRefreshElapsed = 0
        SetMapToCurrentZone()
        playerX, playerY = GetPlayerMapPosition("player")
        targetX, targetY = GetPlayerMapPosition(self.unit)
        if ValidPosition(playerX, playerY) and ValidPosition(targetX, targetY) then
            return playerX, playerY, targetX, targetY
        end
    end
    return nil
end

function CallerArrow:OnUpdate(elapsed)
    self.elapsed = (self.elapsed or 0) + elapsed
    self.mapRefreshElapsed = (self.mapRefreshElapsed or 0) + elapsed
    if self.elapsed < UPDATE_INTERVAL then return end
    self.elapsed = 0

    if not self:RefreshVisibility() then return end
    local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(self.unit)
    self:UpdateDeathState(dead)
    if dead then
        if self:UpdateDeathAlert() then self.frame:Show() else self.frame:Hide() end
        return
    end
    local playerX, playerY, targetX, targetY = self:ReadPositions()
    if not playerX then
        self:Hide()
        return
    end

    local deltaX = (targetX - playerX) * MapAspect()
    local deltaY = targetY - playerY
    if math.abs(deltaX) < 0.000001 and math.abs(deltaY) < 0.000001 then
        self:Hide()
        return
    end

    local direction = math.atan2(deltaX, -deltaY)
    if direction > 0 then direction = TWO_PI - direction else direction = -direction end
    local facing = GetPlayerFacing and GetPlayerFacing()
    if not facing then
        self:Hide()
        return
    end
    local relativeAngle = (direction - facing) % TWO_PI
    RotateTexture(self.frame.arrow, relativeAngle)
    self.frame:Show()
end

function CallerArrow:Initialize()
    if self.initialized then return end
    self.initialized = true
    self:Create()
    self.targetName = Addon.db and Addon.db.assistLog and Addon.db.assistLog.selectedCaller

    local events = CreateFrame("Frame")
    events:RegisterEvent("RAID_ROSTER_UPDATE")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    events:RegisterEvent("CHAT_MSG_ADDON")
    events:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then
            local prefix, message, channel, sender = ...
            if prefix == Addon.MESSAGE_PREFIX and string.sub(message or "", 1, 3) == CALLER_KIND .. "|" then
                CallerArrow:HandleMessage(message, channel, sender)
            end
            return
        end
        CallerArrow.elapsed = UPDATE_INTERVAL
        CallerArrow.mapRefreshElapsed = MAP_REFRESH_INTERVAL
        CallerArrow:RefreshVisibility()
        CallerArrow:RequestTarget()
    end)
    -- Keep updates on this always-shown controller frame. The visual arrow is
    -- hidden whenever position data is unavailable, and hidden frames do not
    -- receive OnUpdate callbacks on this client.
    if self:IsEnabled() then
        events:SetScript("OnUpdate", function(_, elapsed) CallerArrow:OnUpdate(elapsed) end)
    end
    self.events = events
    self:RequestTarget()
end
