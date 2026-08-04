local ARC = Actually.Modules.RaidCooldowns
local Activity = ARC:NewModule("Activity")

local PAGE_SIZE = 14
local DEFAULT_MAX_EVENTS = 500
local CAST_DEDUPE_WINDOW = 0.80
local RECENT_RESULT_WINDOW = 1.50
local LATE_LEDGER_WINDOW = 8.0

local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local RESULT_COLORS = {
    PENDING = { 0.45, 0.82, 1.00 },
    ON_TIME = { 0.30, 1.00, 0.48 },
    LATE = { 1.00, 0.72, 0.18 },
    EARLY = { 1.00, 0.42, 0.15 },
    MISSED = { 1.00, 0.24, 0.20 },
    NO_ACK = { 1.00, 0.50, 0.22 },
    SKIPPED = { 0.62, 0.68, 0.74 },
    UNPLANNED = { 0.82, 0.47, 1.00 },
    OTHER_CAST = { 1.00, 0.55, 0.24 },
    CANCELLED = { 0.46, 0.50, 0.55 },
    INTERRUPTED = { 0.58, 0.62, 0.68 },
}

local RESULT_LABELS = {
    PENDING = "PENDING",
    ON_TIME = "ON TIME",
    LATE = "LATE",
    EARLY = "EARLY",
    MISSED = "MISSED",
    NO_ACK = "NO ACK",
    SKIPPED = "SKIPPED",
    UNPLANNED = "UNPLANNED",
    OTHER_CAST = "OTHER CD",
    CANCELLED = "CANCELLED",
    INTERRUPTED = "INTERRUPTED",
}

local ISSUE_RESULTS = {
    LATE = true,
    EARLY = true,
    MISSED = true,
    NO_ACK = true,
    SKIPPED = true,
    UNPLANNED = true,
    OTHER_CAST = true,
    INTERRUPTED = true,
}

local function setBackdrop(frame, background, border)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(background[1], background[2], background[3], background[4] or 1)
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

local function shortName(value)
    if type(value) == "table" then value = value.name or value.fullName end
    value = tostring(value or "Unknown")
    return string.match(value, "^[^-]+") or value
end

local function playerName(playerKey)
    local player = ARC.State and ARC.State.players and ARC.State.players[playerKey]
    local roster = ARC.Roster and ARC.Roster.byKey and ARC.Roster.byKey[playerKey]
    return shortName(player or roster or playerKey)
end

local function spellName(spellID)
    if ARC.SpellInfo and ARC.SpellInfo.ResolveSpellName then
        return ARC.SpellInfo:ResolveSpellName(spellID)
    end
    return tostring(spellID or "Unknown")
end

local function resultColor(result)
    return unpack(RESULT_COLORS[result] or { 0.82, 0.86, 0.90 })
end

local function formatSeconds(value)
    value = tonumber(value)
    if not value then return nil end
    return string.format("%.1fs", math.max(0, value))
end

function Activity:GetProfile()
    local root = ARC.db and ARC.db.profile
    if not root then return nil end
    root.activity = type(root.activity) == "table" and root.activity or {}
    local profile = root.activity
    if profile.enabled == nil then profile.enabled = true end
    profile.maxEvents = math.max(100,
        math.min(2000, tonumber(profile.maxEvents) or DEFAULT_MAX_EVENTS))
    profile.events = type(profile.events) == "table" and profile.events or {}
    profile.sequence = tonumber(profile.sequence) or 0
    return profile
end

function Activity:GetUIProfile()
    local root = ARC.db and ARC.db.profile
    if not root then return nil end
    root.activityUI = type(root.activityUI) == "table" and root.activityUI or {}
    local profile = root.activityUI
    profile.point = profile.point or "CENTER"
    profile.relativePoint = profile.relativePoint or profile.point
    profile.x = tonumber(profile.x) or 0
    profile.y = tonumber(profile.y) or 0
    if profile.filter ~= "timeline" and profile.filter ~= "issues"
        and profile.filter ~= "players" then profile.filter = "timeline" end
    return profile
end

function Activity:CanTrack()
    local profile = self:GetProfile()
    return profile and profile.enabled ~= false and ARC:HasCommandAuthority()
        and not self:IsInsideInstance()
end

function Activity:IsInsideInstance()
    if type(IsInInstance) ~= "function" then return false end
    local ok, inInstance = pcall(IsInInstance)
    return ok and inInstance == true
end

function Activity:DiscardPendingAttempts()
    local profile = self:GetProfile()
    local removed = 0
    for index = table.getn(profile and profile.events or {}), 1, -1 do
        local event = profile.events[index]
        if event.result == "PENDING" then
            if event.attemptID then self.attempts[event.attemptID] = nil end
            table.remove(profile.events, index)
            removed = removed + 1
        end
    end
    if removed > 0 then self:RefreshIfVisible() end
    return removed
end

function Activity:OnLocationChanged()
    local inside = self:IsInsideInstance()
    if inside then self:DiscardPendingAttempts() end
    self.insideInstance = inside
    self.lastCasts = {}
    self.recentResults = {}
    self:RefreshIfVisible()
end

function Activity:NowWall()
    return time and time() or 0
end

function Activity:Trim()
    local profile = self:GetProfile()
    if not profile then return end
    while table.getn(profile.events) > profile.maxEvents do
        local removed = table.remove(profile.events, 1)
        if removed and removed.attemptID and self.attempts[removed.attemptID] == removed then
            self.attempts[removed.attemptID] = nil
        end
    end
end

function Activity:RebuildAttemptIndex()
    self.attempts = {}
    local profile = self:GetProfile()
    for _, event in ipairs(profile and profile.events or {}) do
        if event.attemptID then self.attempts[event.attemptID] = event end
    end
end

function Activity:NextEventID()
    local profile = self:GetProfile()
    profile.sequence = profile.sequence + 1
    return tostring(self:NowWall()) .. ":" .. tostring(profile.sequence)
end

function Activity:AddEvent(event)
    if not self:CanTrack() then return nil end
    local profile = self:GetProfile()
    event.id = event.id or self:NextEventID()
    event.recordedAt = event.recordedAt or self:NowWall()
    event.playerName = event.playerName or playerName(event.playerKey)
    event.spellName = event.spellName or spellName(event.spellID)
    event.result = event.result or "PENDING"
    table.insert(profile.events, event)
    if event.attemptID then self.attempts[event.attemptID] = event end
    self:Trim()
    self:RefreshIfVisible()
    return event
end

function Activity:BeginAttempt(data)
    if not self:CanTrack() or type(data) ~= "table" or not data.attemptID then return nil end
    local existing = self.attempts[data.attemptID]
    if existing then return existing end
    return self:AddEvent({
        attemptID = data.attemptID,
        kind = data.kind or "single",
        context = data.context,
        contextID = data.contextID,
        playerKey = data.playerKey,
        spellID = data.spellID,
        result = "PENDING",
        startedAt = tonumber(data.startedAt) or ARC:Now(),
        requestedAt = self:NowWall(),
        dueAt = tonumber(data.dueAt),
        deadline = tonumber(data.deadline),
        promptedAt = tonumber(data.promptedAt),
        details = data.details,
    })
end

function Activity:MarkPrompted(attemptID, promptedAt)
    if not self:CanTrack() then return false end
    local event = attemptID and self.attempts[attemptID]
    if not event then return false end
    event.promptedAt = event.promptedAt or tonumber(promptedAt) or ARC:Now()
    self:RefreshIfVisible()
    return true
end

function Activity:MarkRecentResult(playerKey, spellID)
    if not playerKey or not spellID then return end
    local key = tostring(playerKey) .. ":" .. tostring(spellID)
    self.recentResults[key] = ARC:Now() + RECENT_RESULT_WINDOW
end

function Activity:FinishAttempt(attemptID, result, data)
    local event = attemptID and self.attempts[attemptID]
    if not event then return false end
    if not self:CanTrack() then
        if event.result == "PENDING" then self:DiscardPendingAttempts() end
        return false
    end
    data = type(data) == "table" and data or {}
    local now = tonumber(data.finishedAt) or ARC:Now()
    event.result = result or event.result or "INTERRUPTED"
    event.finishedAt = now
    event.finishedWall = self:NowWall()
    event.reason = data.reason or event.reason
    event.source = data.source or event.source
    event.completedBy = data.playerKey or event.completedBy
    if data.playerKey then
        event.playerKey = data.playerKey
        event.playerName = playerName(data.playerKey)
    end
    if data.responseTime ~= nil then
        event.responseTime = math.max(0, tonumber(data.responseTime) or 0)
    elseif event.promptedAt then
        event.responseTime = math.max(0, now - event.promptedAt)
    elseif event.startedAt then
        event.responseTime = math.max(0, now - event.startedAt)
    end
    if event.dueAt and (event.result == "ON_TIME" or event.result == "LATE"
        or event.result == "EARLY") then
        event.timingDelta = now - event.dueAt
    end
    if event.result == "ON_TIME" or event.result == "LATE"
        or event.result == "EARLY" then
        self:MarkRecentResult(event.playerKey, event.spellID)
    end
    self:RefreshIfVisible()
    return true
end

function Activity:FailureResult(reason, wasPrompted)
    reason = string.lower(tostring(reason or "failed"))
    if string.find(reason, "used early", 1, true) then return "EARLY" end
    if string.find(reason, "queue timeout", 1, true) then return "NO_ACK" end
    if string.find(reason, "timeout", 1, true)
        or string.find(reason, "missed timing", 1, true) then
        return wasPrompted and "MISSED" or "NO_ACK"
    end
    if reason == "offline" or reason == "dead" or reason == "stale report"
        or reason == "spell unavailable" or reason == "unavailable"
        or reason == "declined" or reason == "busy" then
        return "SKIPPED"
    end
    return "SKIPPED"
end

function Activity:FailAttempt(attemptID, reason, wasPrompted)
    return self:FinishAttempt(attemptID, self:FailureResult(reason, wasPrompted), {
        reason = reason,
    })
end

function Activity:CancelAttempt(attemptID, reason)
    return self:FinishAttempt(attemptID, "CANCELLED", { reason = reason or "cancelled" })
end

function Activity:FindRecentFailedAttempt(playerKey, spellID)
    local profile = self:GetProfile()
    local nowWall = self:NowWall()
    for index = table.getn(profile and profile.events or {}), 1, -1 do
        local event = profile.events[index]
        if event.playerKey == playerKey and event.spellID == spellID
            and (event.result == "MISSED" or event.result == "NO_ACK"
                or event.result == "SKIPPED")
            and event.finishedWall and nowWall >= event.finishedWall
            and nowWall - event.finishedWall <= LATE_LEDGER_WINDOW then
            return event
        end
    end
end

function Activity:GetExpectedSpells(playerKey)
    local expected, seen = {}, {}
    local function add(spellID, context)
        if not spellID then return end
        local key = tostring(spellID) .. ":" .. tostring(context or "")
        if seen[key] then return end
        seen[key] = true
        table.insert(expected, { spellID = spellID, context = context })
    end

    local request = ARC.Requests and ARC.Requests.outgoing
    if request and request.targetKey == playerKey then
        add(request.spellID, "single request")
    end
    local bundle = ARC.Bundles and ARC.Bundles.active
    for _, item in pairs(bundle and bundle.items or {}) do
        if item.targetKey == playerKey and item.status ~= "DONE" and item.status ~= "FAILED" then
            add(item.spellID, bundle.name)
        end
    end
    local combo = ARC.Combos and ARC.Combos.active
    if combo and combo.state == "COUNTDOWN" then
        for _, actionID in ipairs(combo.order or {}) do
            local action = combo.actions[actionID]
            if action and action.targetKey == playerKey and action.status == "COUNTDOWN" then
                add(action.spellID, combo.name)
            end
        end
    end
    return expected
end

function Activity:OnCast(playerKey, spellID, source)
    if not self:CanTrack() or not playerKey or not spellID then return false end
    local now = ARC:Now()
    local castKey = tostring(playerKey) .. ":" .. tostring(spellID)
    if self.lastCasts[castKey] and now - self.lastCasts[castKey] < CAST_DEDUPE_WINDOW then
        return false
    end
    self.lastCasts[castKey] = now

    if self.recentResults[castKey] and self.recentResults[castKey] >= now then
        return false
    end

    local lease = ARC.Automation and ARC.Automation.lease
    local selfKey = ARC.Roster and ARC.Roster:GetPlayer()
    if lease and lease.ownerKey ~= selfKey and (lease.expiresAt or 0) > now then
        -- Another officer owns the command. Their client is authoritative for
        -- classifying the cast, so do not create a false unplanned entry here.
        return false
    end

    local recent = self:FindRecentFailedAttempt(playerKey, spellID)
    if recent then
        return self:FinishAttempt(recent.attemptID, "LATE", {
            playerKey = playerKey,
            source = source or "cast detected after deadline",
            reason = "cast detected after the ARC response window",
            finishedAt = now,
        })
    end

    local expected = self:GetExpectedSpells(playerKey)
    for _, value in ipairs(expected) do
        if value.spellID == spellID then
            -- The request handler will resolve this attempt. Avoid racing it
            -- and labelling a valid response as unplanned.
            return false
        end
    end

    local details
    local result = "UNPLANNED"
    if table.getn(expected) > 0 then
        result = "OTHER_CAST"
        local names = {}
        for _, value in ipairs(expected) do
            table.insert(names, spellName(value.spellID))
        end
        details = "Expected: " .. table.concat(names, ", ")
    else
        details = "No ARC assignment was active"
    end

    self:AddEvent({
        kind = "observed",
        playerKey = playerKey,
        spellID = spellID,
        result = result,
        source = source,
        finishedAt = now,
        finishedWall = self:NowWall(),
        details = details,
    })
    return true
end

function Activity:DescribeEvent(event)
    if event.details and event.details ~= "" then return event.details end
    if event.result == "PENDING" then
        return event.context and ("Awaiting " .. tostring(event.context)) or "Awaiting response"
    elseif event.result == "ON_TIME" then
        if event.timingDelta then
            return string.format("%+.1fs from cue", event.timingDelta)
        end
        return event.responseTime and ("Responded in " .. formatSeconds(event.responseTime))
            or "Requested cooldown detected"
    elseif event.result == "LATE" then
        if event.timingDelta then return string.format("%+.1fs from cue", event.timingDelta) end
        return event.reason or "Used after the response window"
    elseif event.result == "EARLY" then
        if event.timingDelta then return string.format("%.1fs before cue", math.abs(event.timingDelta)) end
        return event.reason or "Used before the cue"
    elseif event.result == "UNPLANNED" then
        return "No ARC assignment was active"
    elseif event.result == "OTHER_CAST" then
        return event.reason or "A different tracked cooldown was used"
    elseif event.result == "CANCELLED" then
        return event.reason or "Cancelled by coordinator"
    end
    return event.reason or tostring(event.context or "")
end

function Activity:GetTimeline(issuesOnly)
    local profile = self:GetProfile()
    local rows = {}
    for _, event in ipairs(profile and profile.events or {}) do
        if not issuesOnly or ISSUE_RESULTS[event.result] then table.insert(rows, event) end
    end
    table.sort(rows, function(left, right)
        if (left.recordedAt or 0) ~= (right.recordedAt or 0) then
            return (left.recordedAt or 0) > (right.recordedAt or 0)
        end
        return tostring(left.id or "") > tostring(right.id or "")
    end)
    return rows
end

function Activity:GetPlayerSummary()
    local profile = self:GetProfile()
    local byPlayer = {}
    for _, event in ipairs(profile and profile.events or {}) do
        if event.playerKey and event.result ~= "PENDING"
            and event.result ~= "CANCELLED" and event.result ~= "INTERRUPTED" then
            local summary = byPlayer[event.playerKey]
            if not summary then
                summary = {
                    playerKey = event.playerKey,
                    playerName = event.playerName or playerName(event.playerKey),
                    onTime = 0, late = 0, early = 0, missed = 0,
                    noAck = 0, skipped = 0, unplanned = 0,
                }
                byPlayer[event.playerKey] = summary
            end
            if event.result == "ON_TIME" then summary.onTime = summary.onTime + 1
            elseif event.result == "LATE" then summary.late = summary.late + 1
            elseif event.result == "EARLY" then summary.early = summary.early + 1
            elseif event.result == "MISSED" then summary.missed = summary.missed + 1
            elseif event.result == "NO_ACK" then summary.noAck = summary.noAck + 1
            elseif event.result == "SKIPPED" then summary.skipped = summary.skipped + 1
            elseif event.result == "UNPLANNED" or event.result == "OTHER_CAST" then
                summary.unplanned = summary.unplanned + 1
            end
        end
    end
    local rows = {}
    for _, summary in pairs(byPlayer) do
        summary.responded = summary.onTime + summary.late + summary.early
        summary.expected = summary.responded + summary.missed
        summary.rate = summary.expected > 0 and summary.onTime / summary.expected or nil
        table.insert(rows, summary)
    end
    table.sort(rows, function(left, right)
        if (left.playerName or "") ~= (right.playerName or "") then
            return string.lower(left.playerName or "") < string.lower(right.playerName or "")
        end
        return tostring(left.playerKey) < tostring(right.playerKey)
    end)
    return rows
end

function Activity:GetCounts()
    local counts = { onTime = 0, late = 0, attention = 0, unplanned = 0, pending = 0 }
    local profile = self:GetProfile()
    for _, event in ipairs(profile and profile.events or {}) do
        if event.result == "ON_TIME" then counts.onTime = counts.onTime + 1
        elseif event.result == "LATE" then counts.late = counts.late + 1
        elseif event.result == "UNPLANNED" or event.result == "OTHER_CAST" then
            counts.unplanned = counts.unplanned + 1
        elseif event.result == "PENDING" then counts.pending = counts.pending + 1
        elseif event.result ~= "CANCELLED" then counts.attention = counts.attention + 1 end
    end
    return counts
end

function Activity:RefreshIfVisible()
    if self.frame and self.frame:IsShown() then self:Refresh() end
end

function Activity:SetFilter(filter)
    if filter ~= "timeline" and filter ~= "issues" and filter ~= "players" then return end
    self.filter = filter
    self.page = 1
    local profile = self:GetUIProfile()
    if profile then profile.filter = filter end
    self:Refresh()
end

function Activity:ShowTooltip(row)
    local data = row and row.data
    if not data or not GameTooltip then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    if self.filter == "players" then
        GameTooltip:SetText(tostring(data.playerName), 0.32, 0.86, 1.00)
        GameTooltip:AddLine("On-time responses: " .. tostring(data.onTime), 0.30, 1.00, 0.48)
        GameTooltip:AddLine("Late responses: " .. tostring(data.late), 1.00, 0.72, 0.18)
        GameTooltip:AddLine("Early or missed: "
            .. tostring(data.early + data.missed), 1.00, 0.35, 0.20)
        GameTooltip:AddLine("No acknowledgement: " .. tostring(data.noAck), 1.00, 0.50, 0.22)
        GameTooltip:AddLine("Dead/offline/unavailable: " .. tostring(data.skipped),
            0.65, 0.70, 0.76)
        GameTooltip:AddLine("Unplanned or other cooldown: " .. tostring(data.unplanned),
            0.82, 0.47, 1.00)
    else
        GameTooltip:SetText(tostring(data.playerName or "Unknown"), 0.32, 0.86, 1.00)
        GameTooltip:AddLine(tostring(data.spellName or spellName(data.spellID)),
            0.92, 0.96, 1.00)
        GameTooltip:AddLine(RESULT_LABELS[data.result] or tostring(data.result),
            resultColor(data.result))
        GameTooltip:AddLine(self:DescribeEvent(data), 0.80, 0.86, 0.92, true)
        if data.context then
            GameTooltip:AddLine("Command: " .. tostring(data.context), 0.58, 0.72, 0.84, true)
        end
        GameTooltip:AddLine("Unplanned does not automatically mean incorrect; "
            .. "it may have been an emergency decision.", 0.70, 0.62, 0.82, true)
    end
    GameTooltip:Show()
end

function Activity:CreateFrame()
    local ui = self:GetUIProfile()
    local frame = CreateFrame("Frame", "ActuallyARCActivityFrame", UIParent)
    frame:SetWidth(920)
    frame:SetHeight(560)
    frame:SetPoint(ui.point, UIParent, ui.relativePoint, ui.x, ui.y)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(owner) owner:StartMoving() end)
    frame:SetScript("OnDragStop", function(owner)
        owner:StopMovingOrSizing()
        local point, _, relativePoint, x, y = owner:GetPoint(1)
        ui.point, ui.relativePoint, ui.x, ui.y = point, relativePoint, x, y
    end)
    setBackdrop(frame, { 0.008, 0.016, 0.026, 0.985 }, { 0.18, 0.66, 0.94, 1 })
    self.frame = frame

    local dropdown = CreateFrame("Frame", "ActuallyARCActivityMenu", frame,
        "UIDropDownMenuTemplate")
    dropdown:Hide()
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            ARC:ShowWindowContextMenu(dropdown, "ARC Response History",
                function() Activity:Hide() end)
        end
    end)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -13)
    frame.title:SetText("ARC Response History - Officer Only - " .. ARC.Constants.WIP_TEXT)
    frame.title:SetTextColor(0.92, 0.96, 1.00)

    frame.subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -5)
    frame.subtitle:SetWidth(825)
    frame.subtitle:SetJustifyH("LEFT")
    frame.subtitle:SetText(
        "Tracks ARC responses and registered cooldowns used outside assignments. "
        .. "Unplanned is evidence for review, not an automatic accusation.")
    frame.subtitle:SetTextColor(0.55, 0.72, 0.84)

    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
    frame.close:SetScript("OnClick", function() Activity:Hide() end)

    frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.summary:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -62)
    frame.summary:SetWidth(890)
    frame.summary:SetJustifyH("LEFT")

    local filters = {
        { key = "timeline", text = "Timeline" },
        { key = "issues", text = "Needs Review" },
        { key = "players", text = "Player Summary" },
    }
    frame.filterButtons = {}
    local prior
    for _, definition in ipairs(filters) do
        local filterKey = definition.key
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetWidth(definition.key == "players" and 118 or 100)
        button:SetHeight(23)
        if prior then button:SetPoint("LEFT", prior, "RIGHT", 7, 0)
        else button:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -87) end
        button:SetText(definition.text)
        button:SetScript("OnClick", function() Activity:SetFilter(filterKey) end)
        button.filterKey = filterKey
        table.insert(frame.filterButtons, button)
        prior = button
    end

    frame.clear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.clear:SetWidth(105)
    frame.clear:SetHeight(23)
    frame.clear:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -15, -87)
    frame.clear:SetText("Clear History")
    frame.clear:SetScript("OnClick", function()
        local now = ARC:Now()
        if not Activity.clearConfirmUntil or Activity.clearConfirmUntil < now then
            Activity.clearConfirmUntil = now + 5
            frame.clear:SetText("Confirm Clear")
            return
        end
        Activity:Clear()
        Activity.clearConfirmUntil = nil
        frame.clear:SetText("Clear History")
    end)

    local list = CreateFrame("Frame", nil, frame)
    list:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -120)
    list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 48)
    setBackdrop(list, { 0.002, 0.007, 0.012, 0.96 }, { 0.10, 0.30, 0.43, 0.95 })
    frame.list = list

    frame.headers = {}
    local headerNames = { "Time", "Player", "Cooldown", "Result", "Details" }
    local headerX = { 8, 76, 210, 405, 505 }
    local headerWidths = { 64, 130, 190, 96, 378 }
    for index, name in ipairs(headerNames) do
        local header = list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header:SetPoint("TOPLEFT", list, "TOPLEFT", headerX[index], -8)
        header:SetWidth(headerWidths[index])
        header:SetJustifyH("LEFT")
        header:SetText(name)
        header:SetTextColor(0.40, 0.76, 0.96)
        frame.headers[index] = header
    end

    frame.rows = {}
    for index = 1, PAGE_SIZE do
        local rowIndex = index
        local row = CreateFrame("Frame", nil, list)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 5, -25 - (index - 1) * 27)
        row:SetPoint("TOPRIGHT", list, "TOPRIGHT", -5, -25 - (index - 1) * 27)
        row:SetHeight(25)
        row:EnableMouse(true)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints(row)
        row.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        row.bg:SetVertexColor(index % 2 == 0 and 0.025 or 0.012,
            index % 2 == 0 and 0.070 or 0.042,
            index % 2 == 0 and 0.100 or 0.065, 0.88)
        row.values = {}
        for column = 1, 5 do
            local value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            value:SetPoint("LEFT", row, "LEFT", headerX[column], 0)
            value:SetWidth(headerWidths[column])
            value:SetJustifyH("LEFT")
            value:SetWordWrap(false)
            row.values[column] = value
        end
        row:SetScript("OnEnter", function(owner)
            owner.bg:SetVertexColor(0.08, 0.22, 0.32, 0.95)
            Activity:ShowTooltip(owner)
        end)
        row:SetScript("OnLeave", function(owner)
            owner.bg:SetVertexColor(rowIndex % 2 == 0 and 0.025 or 0.012,
                rowIndex % 2 == 0 and 0.070 or 0.042,
                rowIndex % 2 == 0 and 0.100 or 0.065, 0.88)
            if GameTooltip then GameTooltip:Hide() end
        end)
        frame.rows[index] = row
    end

    frame.empty = list:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.empty:SetPoint("CENTER", list, "CENTER", 0, 0)
    frame.empty:SetText("No ARC response history yet")
    frame.empty:SetTextColor(0.48, 0.58, 0.66)

    frame.prev = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.prev:SetWidth(72)
    frame.prev:SetHeight(23)
    frame.prev:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 15, 15)
    frame.prev:SetText("Prev")
    frame.prev:SetScript("OnClick", function()
        Activity.page = math.max(1, (Activity.page or 1) - 1)
        Activity:Refresh()
    end)

    frame.next = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.next:SetWidth(72)
    frame.next:SetHeight(23)
    frame.next:SetPoint("LEFT", frame.prev, "RIGHT", 7, 0)
    frame.next:SetText("Next")
    frame.next:SetScript("OnClick", function()
        Activity.page = (Activity.page or 1) + 1
        Activity:Refresh()
    end)

    frame.page = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.page:SetPoint("LEFT", frame.next, "RIGHT", 10, 0)
    frame.page:SetWidth(180)
    frame.page:SetJustifyH("LEFT")

    frame.note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.note:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 20)
    frame.note:SetText("Open-world activity only - stored locally on this officer's client")
    frame.note:SetTextColor(0.45, 0.55, 0.62)

    frame:SetScript("OnShow", function()
        if not ARC:HasCommandAuthority() then frame:Hide() return end
        Activity:Refresh()
    end)
    frame:Hide()
end

function Activity:Refresh()
    local frame = self.frame
    if not frame then return end
    if not ARC:HasCommandAuthority() then frame:Hide() return end
    if self.clearConfirmUntil and self.clearConfirmUntil < ARC:Now() then
        self.clearConfirmUntil = nil
        frame.clear:SetText("Clear History")
    end

    self.filter = self.filter or self:GetUIProfile().filter or "timeline"
    for _, button in ipairs(frame.filterButtons) do
        if button.filterKey == self.filter then button:Disable() else button:Enable() end
    end

    local counts = self:GetCounts()
    frame.summary:SetText("|cff55ff88On time: " .. tostring(counts.onTime)
        .. "|r   |cffffb82eLate: " .. tostring(counts.late)
        .. "|r   |cffff5544Needs review: " .. tostring(counts.attention)
        .. "|r   |cffd078ffUnplanned/other: " .. tostring(counts.unplanned)
        .. "|r   |cff70c8ffPending: " .. tostring(counts.pending) .. "|r")

    local rows
    if self.filter == "players" then rows = self:GetPlayerSummary()
    else rows = self:GetTimeline(self.filter == "issues") end
    local pages = math.max(1, math.ceil(table.getn(rows) / PAGE_SIZE))
    self.page = math.max(1, math.min(tonumber(self.page) or 1, pages))
    frame.page:SetText("Page " .. tostring(self.page) .. "/" .. tostring(pages)
        .. " (" .. tostring(table.getn(rows)) .. " rows)")
    if self.page > 1 then frame.prev:Enable() else frame.prev:Disable() end
    if self.page < pages then frame.next:Enable() else frame.next:Disable() end

    local playerHeaders = { "", "Player", "On time / Late", "Early / Missed",
        "Unplanned / Correct %" }
    local timelineHeaders = { "Time", "Player", "Cooldown", "Result", "Details" }
    local headers = self.filter == "players" and playerHeaders or timelineHeaders
    for index, header in ipairs(frame.headers) do header:SetText(headers[index]) end

    local first = (self.page - 1) * PAGE_SIZE + 1
    for index, row in ipairs(frame.rows) do
        local data = rows[first + index - 1]
        row.data = data
        if not data then
            row:Hide()
        else
            row:Show()
            if self.filter == "players" then
                row.values[1]:SetText("")
                row.values[2]:SetText(tostring(data.playerName))
                row.values[3]:SetText(tostring(data.onTime) .. " / " .. tostring(data.late))
                row.values[4]:SetText(tostring(data.early + data.missed))
                row.values[5]:SetText(tostring(data.unplanned) .. "   |   "
                    .. (data.rate and tostring(math.floor(data.rate * 100 + 0.5)) .. "%" or "-"))
                row.values[1]:SetTextColor(0.58, 0.68, 0.76)
                row.values[2]:SetTextColor(0.92, 0.96, 1.00)
                row.values[3]:SetTextColor(0.45, 0.94, 0.62)
                row.values[4]:SetTextColor(1.00, 0.35, 0.20)
                row.values[5]:SetTextColor(0.82, 0.72, 0.92)
            else
                local stamp = tonumber(data.finishedWall or data.recordedAt or data.requestedAt)
                row.values[1]:SetText(stamp and date("%H:%M:%S", stamp) or "--:--:--")
                row.values[2]:SetText(tostring(data.playerName or playerName(data.playerKey)))
                row.values[3]:SetText(tostring(data.spellName or spellName(data.spellID)))
                row.values[4]:SetText(RESULT_LABELS[data.result] or tostring(data.result))
                row.values[5]:SetText(self:DescribeEvent(data))
                row.values[1]:SetTextColor(0.58, 0.68, 0.76)
                row.values[2]:SetTextColor(0.92, 0.96, 1.00)
                row.values[3]:SetTextColor(0.70, 0.86, 0.96)
                row.values[4]:SetTextColor(resultColor(data.result))
                row.values[5]:SetTextColor(0.72, 0.79, 0.85)
            end
        end
    end
    if table.getn(rows) == 0 then frame.empty:Show() else frame.empty:Hide() end
end

function Activity:Clear()
    if not ARC:RequireCommandAuthority() then return false end
    local profile = self:GetProfile()
    for index = table.getn(profile.events), 1, -1 do profile.events[index] = nil end
    self.attempts = {}
    self.recentResults = {}
    self.lastCasts = {}
    self.page = 1
    self:Refresh()
    ARC:Print("response history cleared")
    return true
end

function Activity:Show()
    if ARC.OfficerConfig and ARC.OfficerConfig.frame then
        return ARC.OfficerConfig:Show("activity")
    end
    if not ARC:RequireCommandAuthority() then return false end
    self:Refresh()
    self.frame:Show()
    return true
end

function Activity:Hide()
    if ARC.OfficerConfig and ARC.OfficerConfig.IsHosting
        and ARC.OfficerConfig:IsHosting("activity") then
        ARC.OfficerConfig:Hide()
        return
    end
    if self.frame then self.frame:Hide() end
end

function Activity:Toggle()
    if ARC.OfficerConfig and ARC.OfficerConfig.frame then
        return ARC.OfficerConfig:Toggle("activity")
    end
    if not ARC:RequireCommandAuthority() then return false end
    if self.frame:IsShown() then self:Hide() return false end
    return self:Show()
end

function Activity:Initialize()
    if self.initialized then return end
    self.attempts = {}
    self.recentResults = {}
    self.lastCasts = {}
    self.page = 1
    self.filter = self:GetUIProfile().filter or "timeline"
    self:RebuildAttemptIndex()
    self.insideInstance = self:IsInsideInstance()
    if self.insideInstance then
        self:DiscardPendingAttempts()
    else
        for _, event in ipairs(self:GetProfile().events) do
            if event.result == "PENDING" then
                event.result = "INTERRUPTED"
                event.reason = "addon session ended before ARC recorded an outcome"
                event.finishedWall = self:NowWall()
            end
        end
    end
    self:Trim()
    self:CreateFrame()
    self.initialized = true
end
