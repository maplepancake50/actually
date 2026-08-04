local ARC = Actually.Modules.RaidCooldowns
local Diagnostics = ARC:NewModule("Diagnostics")

local ROLE_REQUESTER = "REQUESTER"
local ROLE_USER1 = "USER1"
local ROLE_USER2 = "USER2"
local ROLE_LABELS = {
    [ROLE_REQUESTER] = "Requester",
    [ROLE_USER1] = "User 1",
    [ROLE_USER2] = "User 2",
}
local VALID_ROLES = {
    [ROLE_REQUESTER] = true,
    [ROLE_USER1] = true,
    [ROLE_USER2] = true,
}
local PARTICIPANT_TIMEOUT = 12
local HEARTBEAT_INTERVAL = 3
local MAX_LOG_LINES = 500
local LOG_TRIM_BATCH = 100
local REPORT_CHUNK_BYTES = 850
local MAX_REPORT_BYTES = 60000
local MAX_REPORT_CHUNKS = 80
local REPORT_COLLECTION_TIMEOUT = 120
local REPORT_RESPONSE_COOLDOWN = 10

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

local function shortName(value)
    local name = type(value) == "table" and value.name or value
    name = tostring(name or "Unknown")
    return string.match(name, "^[^-]+") or name
end

local function stripColors(value)
    value = tostring(value or "")
    value = string.gsub(value, "|c%x%x%x%x%x%x%x%x", "")
    value = string.gsub(value, "|r", "")
    return value
end

local function validInteger(value, minimum, maximum)
    return type(value) == "number" and value == math.floor(value)
        and value >= minimum and value <= maximum
end

local function countTable(values)
    local count = 0
    for _ in pairs(values or {}) do count = count + 1 end
    return count
end

local function makeButton(parent, width, text)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetWidth(width)
    button:SetHeight(23)
    button:SetText(text)
    return button
end

function Diagnostics:IsCaptureEnabled()
    return self.role ~= nil
        or self.activeRunID ~= nil
        or (self.frame and self.frame:IsShown())
        or (ARC.OfficerConfig and ARC.OfficerConfig.IsHosting
            and ARC.OfficerConfig:IsHosting("diagnostics"))
        or (ARC.db and ARC.db.profile and ARC.db.profile.debug == true)
end

function Diagnostics:Record(kind, message, red, green, blue)
    if kind ~= "ERROR" and not self:IsCaptureEnabled() then return end
    self.logs = self.logs or {}
    local elapsed = ARC:Now() - (self.startedAt or ARC:Now())
    local plain = string.format("%07.2f  %-8s  %s",
        elapsed, tostring(kind or "INFO"), stripColors(message))
    table.insert(self.logs, plain)
    if table.getn(self.logs) > MAX_LOG_LINES then
        local compacted = {}
        for index = LOG_TRIM_BATCH + 1, table.getn(self.logs) do
            table.insert(compacted, self.logs[index])
        end
        self.logs = compacted
    end
    if self.logFrame then
        self.logFrame:AddMessage(plain, red or 0.78, green or 0.86, blue or 0.94)
    end
end

function Diagnostics:RecordInternal(kind, message)
    if kind ~= "ERROR" and not self:IsCaptureEnabled() then return end
    local colors = {
        DEBUG = { 0.58, 0.68, 0.76 },
        PRINT = { 0.55, 0.80, 1.00 },
        TEST = { 0.45, 1.00, 0.55 },
        ERROR = { 1.00, 0.35, 0.25 },
    }
    local color = colors[kind] or { 0.78, 0.86, 0.94 }
    self:Record(kind, message, color[1], color[2], color[3])
end

function Diagnostics:SummarizeFields(fields, startIndex)
    local parts = {}
    startIndex = startIndex or 1
    local maximum = math.min((fields and fields.n) or table.getn(fields or {}), startIndex + 6)
    for index = startIndex, maximum do
        local value = fields[index]
        if type(value) == "table" then
            table.insert(parts, "rows=" .. tostring(table.getn(value)))
        elseif value ~= nil and value ~= "" then
            local text = tostring(value)
            if #text > 28 then text = string.sub(text, 1, 25) .. "..." end
            table.insert(parts, text)
        end
    end
    return table.concat(parts, " | ")
end

function Diagnostics:RecordARC(direction, messageType, counterpart, fields, startIndex, protocol)
    if not self.initialized or not self:IsCaptureEnabled() then return end
    local detail = self:SummarizeFields(fields, startIndex)
    local message = tostring(messageType or "UNKNOWN")
        .. "  " .. tostring(counterpart or "")
    if protocol then message = message .. "  p" .. tostring(protocol) end
    if detail ~= "" then message = message .. "  " .. detail end
    if direction == "RX" then
        self:Record("ARC RX", message, 0.38, 0.86, 1.00)
    elseif direction == "TX" then
        self:Record("ARC TX", message, 0.72, 0.55, 1.00)
    else
        self:Record("ARC " .. tostring(direction), message, 1.00, 0.55, 0.25)
    end
end

function Diagnostics:ClearLog()
    self.logs = {}
    self.startedAt = ARC:Now()
    if self.logFrame then self.logFrame:Clear() end
    self:Record("TEST", "diagnostic log cleared", 0.45, 1.00, 0.55)
end

function Diagnostics:GetExportText()
    return table.concat(self.logs or {}, "\n")
end

function Diagnostics:BuildLocalReport()
    local playerKey, identity = ARC.Roster:GetPlayer()
    local body = self:GetExportText()
    local truncated = false
    if #body > MAX_REPORT_BYTES then
        body = string.sub(body, #body - MAX_REPORT_BYTES + 1)
        truncated = true
    end
    local lines = {
        "ARC CLIENT REPORT",
        "Player: " .. tostring(identity and identity.name or playerKey),
        "Role: " .. tostring(self.role and ROLE_LABELS[self.role] or "Not selected"),
        "Protocol: " .. tostring(ARC.Constants.PROTOCOL_VERSION),
        "Run: " .. tostring(self.activeRunID or "none"),
    }
    if truncated then
        table.insert(lines, "Note: report was truncated to its most recent 60000 bytes")
    end
    table.insert(lines, "------------------------------------------------------------")
    table.insert(lines, body)
    return table.concat(lines, "\n")
end

function Diagnostics:NextSequence()
    self.sequence = (self.sequence or 0) + 1
    return self.sequence
end

function Diagnostics:SendTest(kind, ...)
    local distribution = ARC.Roster:GetDistribution()
    local fields = { n = select("#", ...), ... }
    if not distribution then
        self:Record("TEST", "cannot send " .. tostring(kind) .. ": not grouped",
            1.00, 0.35, 0.25)
        return false
    end
    local payload = ARC:Serialize("ARC_TEST", ARC.Constants.TEST_WIRE_VERSION,
        kind, self.session, self:NextSequence(), self.role or "",
        self.activeRunID or "", ...)
    ARC:SendCommMessage(ARC.Constants.TEST_PREFIX, payload,
        distribution, nil, "NORMAL")
    local detail = self:SummarizeFields(fields, 1)
    self:Record("TEST TX", tostring(kind) .. "  " .. tostring(distribution)
        .. (detail ~= "" and ("  " .. detail) or ""),
        0.76, 0.60, 1.00)
    return true
end

function Diagnostics:SendTestWhisper(kind, target, ...)
    if type(target) ~= "string" or target == "" then return false end
    local fields = { n = select("#", ...), ... }
    local payload = ARC:Serialize("ARC_TEST", ARC.Constants.TEST_WIRE_VERSION,
        kind, self.session, self:NextSequence(), self.role or "",
        self.activeRunID or "", ...)
    ARC:SendCommMessage(ARC.Constants.TEST_PREFIX, payload,
        "WHISPER", target, kind == "LOG_CHUNK" and "BULK" or "NORMAL")
    local detail = self:SummarizeFields(fields, 1)
    self:Record("TEST TX", tostring(kind) .. "  WHISPER -> " .. shortName(target)
        .. (detail ~= "" and ("  " .. detail) or ""),
        0.76, 0.60, 1.00)
    return true
end

function Diagnostics:RecordParticipant(identity, role, runID)
    if not identity or not VALID_ROLES[role] then return false end
    local previous = self.participants[identity.key]
    self.participants[identity.key] = {
        key = identity.key,
        name = identity.name,
        role = role,
        runID = runID,
        lastSeen = ARC:Now(),
        lastRTT = previous and previous.lastRTT,
        connected = identity.connected,
    }
    self:RefreshPanel()
    return true
end

function Diagnostics:BroadcastHello()
    if not self.role then return false end
    local _, identity = ARC.Roster:GetPlayer()
    self:RecordParticipant(identity, self.role, self.activeRunID)
    self.nextHelloAt = ARC:Now() + HEARTBEAT_INTERVAL
    return self:SendTest("HELLO")
end

function Diagnostics:SetRole(role)
    if role == ROLE_REQUESTER and not ARC:RequireCommandAuthority() then return false end
    if not VALID_ROLES[role] then return false end
    self.role = role
    self:Record("TEST", "local role set to " .. ROLE_LABELS[role],
        0.45, 1.00, 0.55)
    self:BroadcastHello()
    self:RefreshPanel()
    return true
end

function Diagnostics:LeaveTest()
    if self.role then self:SendTest("LEAVE") end
    local selfKey = ARC.Roster:GetPlayer()
    self.participants[selfKey] = nil
    self.role = nil
    self.activeRunID = nil
    self:Record("TEST", "left three-player test", 1.00, 0.72, 0.20)
    self:RefreshPanel()
end

function Diagnostics:GetRoleParticipants(role)
    local now, result = ARC:Now(), {}
    for key, participant in pairs(self.participants or {}) do
        if now - (participant.lastSeen or 0) <= PARTICIPANT_TIMEOUT
            and participant.role == role then
            participant.key = key
            table.insert(result, participant)
        end
    end
    table.sort(result, function(left, right)
        return string.lower(tostring(left.name)) < string.lower(tostring(right.name))
    end)
    return result
end

function Diagnostics:GetParticipant(role)
    local values = self:GetRoleParticipants(role)
    if table.getn(values) == 1 then return values[1] end
    return nil, table.getn(values)
end

function Diagnostics:StartSession()
    if not ARC:RequireCommandAuthority() then return false end
    if not ARC.Roster:IsGrouped() then
        ARC:Print("join a party or raid before starting the ARC test")
        return false
    end
    self:SetRole(ROLE_REQUESTER)
    self.runCounter = (self.runCounter or 0) + 1
    self.activeRunID = tostring(self.session) .. ":RUN:" .. tostring(self.runCounter)
    self:ClearLog()
    self:Record("TEST", "started three-player session " .. self.activeRunID,
        0.45, 1.00, 0.55)
    self:SendTest("START", self.activeRunID)
    self:BroadcastHello()
    return true
end

function Diagnostics:StopSession()
    if self.role == ROLE_REQUESTER then self:SendTest("STOP") end
    self:Record("TEST", "test session stopped", 1.00, 0.72, 0.20)
    self.activeRunID = nil
    self:RefreshPanel()
end

function Diagnostics:PingTesters()
    if not ARC:RequireCommandAuthority() then return false end
    self.pingCounter = (self.pingCounter or 0) + 1
    local nonce = tostring(self.session) .. ":PING:" .. tostring(self.pingCounter)
    self.pendingPings[nonce] = {
        sentAt = ARC:Now(),
        responders = {},
    }
    self:SendTest("PING", nonce)
    self:Record("TEST", "ping sent to both users", 0.45, 1.00, 0.55)
    return true
end

function Diagnostics:SendReportChunks(collectionID, requester)
    local now = ARC:Now()
    if now - (self.lastReportResponseAt or -100)
        < REPORT_RESPONSE_COOLDOWN then
        self:Record("REPORT", "ignored repeated report request from "
            .. shortName(requester), 1.00, 0.72, 0.20)
        return false
    end
    self.lastReportResponseAt = now
    local report = self:BuildLocalReport()
    local total = math.max(1, math.ceil(#report / REPORT_CHUNK_BYTES))
    if total > MAX_REPORT_CHUNKS then
        self:Record("REPORT", "local report exceeded the transfer limit",
            1.00, 0.35, 0.25)
        return false
    end
    self:Record("REPORT", "sending " .. tostring(total) .. " log chunk(s) to "
        .. shortName(requester), 0.45, 1.00, 0.55)
    for index = 1, total do
        local firstByte = (index - 1) * REPORT_CHUNK_BYTES + 1
        local chunk = string.sub(report, firstByte, firstByte + REPORT_CHUNK_BYTES - 1)
        self:SendTestWhisper("LOG_CHUNK", requester.name,
            collectionID, index, total, chunk)
    end
    return true
end

function Diagnostics:BuildCombinedReport(collection)
    local lines = {
        "ARC THREE-PLAYER COMBINED DIAGNOSTIC REPORT",
        "Protocol: " .. tostring(ARC.Constants.PROTOCOL_VERSION),
        "Run: " .. tostring(self.activeRunID or "none"),
        "Collection: " .. tostring(collection.id),
        "------------------------------------------------------------",
    }
    for _, member in ipairs(collection.members or {}) do
        table.insert(lines, "")
        table.insert(lines, "============================================================")
        table.insert(lines, ROLE_LABELS[member.role] .. ": " .. tostring(member.name))
        table.insert(lines, "============================================================")
        local report = collection.reports[member.key]
        if report then
            table.insert(lines, report)
        else
            table.insert(lines, "[NO REPORT RECEIVED BEFORE TIMEOUT]")
        end
    end
    return table.concat(lines, "\n")
end

function Diagnostics:FinishReportCollection(timedOut)
    local collection = self.reportCollection
    if not collection then return false end
    self.combinedExport = self:BuildCombinedReport(collection)
    self.combinedCollectionID = collection.id
    self.reportCollection = nil
    local received = 0
    for _, member in ipairs(collection.members or {}) do
        if collection.reports[member.key] then received = received + 1 end
    end
    self:Record("REPORT", "combined report ready: " .. tostring(received)
        .. "/3 clients" .. (timedOut and " (collection timed out)" or ""),
        received == 3 and 0.45 or 1.00,
        received == 3 and 1.00 or 0.55,
        received == 3 and 0.55 or 0.25)
    ARC:Print("combined ARC diagnostic report ready ("
        .. tostring(received) .. "/3); click Export Combined")
    self:RefreshPanel()
    return true
end

function Diagnostics:CheckReportCollection()
    local collection = self.reportCollection
    if not collection then return false end
    for _, member in ipairs(collection.members or {}) do
        if not collection.reports[member.key] then return false end
    end
    return self:FinishReportCollection(false)
end

function Diagnostics:CollectReports()
    if not self:RequireRequesterTest() then return false end
    if self.reportCollection then
        ARC:Print("a three-player report collection is already in progress")
        return false
    end
    local now = ARC:Now()
    if now - (self.lastCollectionAt or -100) < REPORT_RESPONSE_COOLDOWN then
        ARC:Print("wait a few seconds before collecting the three reports again")
        return false
    end
    local requester = self:GetParticipant(ROLE_REQUESTER)
    local user1 = self:GetParticipant(ROLE_USER1)
    local user2 = self:GetParticipant(ROLE_USER2)
    if not requester or not user1 or not user2 then
        ARC:Print("assign exactly one Requester, User 1, and User 2 before collecting logs")
        return false
    end
    local selfKey = ARC.Roster:GetPlayer()
    if requester.key ~= selfKey then
        ARC:Print("the local player must hold the Requester role")
        return false
    end
    self.reportCounter = (self.reportCounter or 0) + 1
    local collectionID = tostring(self.session) .. ":REPORT:"
        .. tostring(self.reportCounter)
    self.reportCollection = {
        id = collectionID,
        startedAt = ARC:Now(),
        deadline = ARC:Now() + REPORT_COLLECTION_TIMEOUT,
        members = {
            { role = ROLE_REQUESTER, key = requester.key, name = requester.name },
            { role = ROLE_USER1, key = user1.key, name = user1.name },
            { role = ROLE_USER2, key = user2.key, name = user2.name },
        },
        expected = {
            [user1.key] = ROLE_USER1,
            [user2.key] = ROLE_USER2,
        },
        reports = {
            [requester.key] = self:BuildLocalReport(),
        },
        chunks = {},
    }
    self.lastCollectionAt = now
    self.combinedExport = nil
    self.combinedCollectionID = nil
    self:Record("REPORT", "requesting logs from User 1 and User 2",
        0.45, 1.00, 0.55)
    self:SendTest("LOG_REQUEST", collectionID)
    self:RefreshPanel()
    return true
end

function Diagnostics:ReceiveReportChunk(identity, collectionID, index, total, chunk)
    local collection = self.reportCollection
    if self.role ~= ROLE_REQUESTER or not collection
        or collection.id ~= collectionID
        or not collection.expected[identity.key] then return false end
    if not validInteger(index, 1, MAX_REPORT_CHUNKS)
        or not validInteger(total, 1, MAX_REPORT_CHUNKS)
        or index > total or type(chunk) ~= "string"
        or #chunk > REPORT_CHUNK_BYTES then return false end
    local entry = collection.chunks[identity.key]
    if not entry then
        entry = { total = total, received = 0, bytes = 0, parts = {} }
        collection.chunks[identity.key] = entry
    elseif entry.total ~= total then
        self:Record("REPORT", "rejected inconsistent log transfer from "
            .. shortName(identity), 1.00, 0.35, 0.25)
        return false
    end
    if entry.parts[index] then return false end
    if entry.bytes + #chunk > MAX_REPORT_BYTES + 2048 then
        self:Record("REPORT", "rejected oversized log transfer from "
            .. shortName(identity), 1.00, 0.35, 0.25)
        return false
    end
    entry.parts[index] = chunk
    entry.received = entry.received + 1
    entry.bytes = entry.bytes + #chunk
    if entry.received < entry.total then return true end
    local parts = {}
    for part = 1, entry.total do
        if not entry.parts[part] then return true end
        table.insert(parts, entry.parts[part])
    end
    collection.reports[identity.key] = table.concat(parts)
    local participant = self.participants[identity.key]
    if participant then participant.lastSeen = ARC:Now() end
    self:Record("REPORT", "received complete log from "
        .. shortName(identity) .. " (" .. tostring(entry.bytes) .. " bytes)",
        0.45, 1.00, 0.55)
    self:CheckReportCollection()
    return true
end

function Diagnostics:AcceptTestSequence(identity, session, sequence)
    local previous = self.remoteSequences[identity.key]
    if previous and previous.session == session and sequence <= previous.sequence then
        return false
    end
    self.remoteSequences[identity.key] = {
        session = session,
        sequence = sequence,
    }
    return true
end

function Diagnostics:OnTestComm(prefix, message, distribution, sender)
    if prefix ~= ARC.Constants.TEST_PREFIX or type(message) ~= "string"
        or #message > 2048 then return end
    local identity = ARC.Roster:FindSender(sender)
    if not identity then return end
    local selfKey = ARC.Roster:GetPlayer()
    if identity.key == selfKey then return end
    local decoded = { ARC:Deserialize(message) }
    if not decoded[1] or decoded[2] ~= "ARC_TEST"
        or decoded[3] ~= ARC.Constants.TEST_WIRE_VERSION then return end
    local kind, session, sequence, role, runID =
        decoded[4], decoded[5], decoded[6], decoded[7], decoded[8]
    if type(kind) ~= "string" or type(session) ~= "string" or #session > 80
        or not validInteger(sequence, 0, 2147483647)
        or type(role) ~= "string" or type(runID) ~= "string" then return end
    -- Bulk report whispers can arrive around later heartbeat traffic from a
    -- different throttle queue. Chunk identity/index validation handles their
    -- replay protection without incorrectly dropping an out-of-order chunk.
    if kind ~= "LOG_CHUNK"
        and not self:AcceptTestSequence(identity, session, sequence) then return end
    local detail = self:SummarizeFields(decoded, 9)
    self:Record("TEST RX", tostring(kind) .. "  from " .. shortName(identity)
        .. " / " .. tostring(distribution)
        .. (detail ~= "" and ("  " .. detail) or ""),
        0.38, 0.86, 1.00)

    if kind == "HELLO" then
        self:RecordParticipant(identity, role, runID)
        if role == ROLE_REQUESTER and ARC.Roster:IsCoordinator(identity) then
            self.activeRunID = runID ~= "" and runID or nil
        end
    elseif kind == "LEAVE" then
        self.participants[identity.key] = nil
        self:RefreshPanel()
    elseif kind == "START" then
        if not ARC.Roster:IsCoordinator(identity) then return end
        local incomingRunID = decoded[9]
        if type(incomingRunID) ~= "string" or #incomingRunID > 120 then return end
        self.activeRunID = incomingRunID
        self:Record("TEST", "joined session from " .. shortName(identity),
            0.45, 1.00, 0.55)
        self:BroadcastHello()
    elseif kind == "STOP" then
        if not ARC.Roster:IsCoordinator(identity) then return end
        self.activeRunID = nil
        self:Record("TEST", "requester stopped the session", 1.00, 0.72, 0.20)
    elseif kind == "PING" then
        if not ARC.Roster:IsCoordinator(identity) then return end
        local nonce = decoded[9]
        if type(nonce) == "string" and #nonce <= 120
            and (self.role == ROLE_USER1 or self.role == ROLE_USER2) then
            self:SendTest("PONG", nonce)
        end
    elseif kind == "PONG" and self.role == ROLE_REQUESTER then
        local nonce = decoded[9]
        local ping = self.pendingPings[nonce]
        if ping and not ping.responders[identity.key] then
            ping.responders[identity.key] = true
            local milliseconds = math.floor((ARC:Now() - ping.sentAt) * 1000 + 0.5)
            local participant = self.participants[identity.key]
            if participant then
                participant.lastRTT = milliseconds
                participant.lastSeen = ARC:Now()
            end
            self:Record("PING", shortName(identity) .. "  " .. tostring(milliseconds) .. " ms",
                0.45, 1.00, 0.55)
        end
    elseif kind == "LOG_REQUEST" then
        local collectionID = decoded[9]
        if ARC.Roster:IsCoordinator(identity)
            and self.activeRunID and runID == self.activeRunID
            and type(collectionID) == "string" and #collectionID <= 120
            and (self.role == ROLE_USER1 or self.role == ROLE_USER2) then
            self:SendReportChunks(collectionID, identity)
        end
    elseif kind == "LOG_CHUNK" then
        local collectionID, index, total, chunk =
            decoded[9], decoded[10], decoded[11], decoded[12]
        local collection = self.reportCollection
        if self.activeRunID and runID == self.activeRunID
            and type(collectionID) == "string" and #collectionID <= 120
            and collection and collection.expected[identity.key] == role then
            self:ReceiveReportChunk(identity, collectionID, index, total, chunk)
        end
    elseif kind == "CASE" then
        local caseName, caseDetail = decoded[9], decoded[10]
        if type(caseName) == "string" and #caseName <= 60
            and type(caseDetail) == "string" and #caseDetail <= 180 then
            self:Record("CASE", shortName(identity) .. " started " .. caseName
                .. (caseDetail ~= "" and (" - " .. caseDetail) or ""),
                0.95, 0.82, 0.30)
        end
    end
    self:RefreshPanel()
end

function Diagnostics:FindReadySpell(playerKey, requireUnique, excluded)
    local player = ARC.State.players[playerKey]
    local ids = {}
    for spellID in pairs(player and player.spells or {}) do
        if ARC.Registry:Get(spellID) and not (excluded and excluded[spellID])
            and ARC.Requests:IsEligible(playerKey, spellID) then
            table.insert(ids, spellID)
        end
    end
    table.sort(ids, function(left, right)
        local leftName = string.lower(ARC.SpellInfo:ResolveSpellName(left))
        local rightName = string.lower(ARC.SpellInfo:ResolveSpellName(right))
        if leftName ~= rightName then return leftName < rightName end
        return left < right
    end)
    for _, spellID in ipairs(ids) do
        local candidates = ARC.Automation:GetCandidates(
            spellID, requireUnique and nil or playerKey, {}, {})
        if candidates[1] and candidates[1].key == playerKey then
            if not requireUnique or table.getn(candidates) == 1 then return spellID end
        end
    end
end

function Diagnostics:FindTwoUserSpells()
    local user1 = self:GetParticipant(ROLE_USER1)
    local user2 = self:GetParticipant(ROLE_USER2)
    if not user1 or not user2 then return nil, nil, "assign exactly one User 1 and one User 2" end
    local first = self:FindReadySpell(user1.key, true)
    if not first then
        return nil, nil, shortName(user1) .. " has no uniquely assignable ready ARC spell"
    end
    local second = self:FindReadySpell(user2.key, true, { [first] = true })
    if not second then
        return nil, nil, shortName(user2) .. " has no different uniquely assignable ready ARC spell"
    end
    return first, second
end

function Diagnostics:FindThreePlayerSpells()
    local requester = self:GetParticipant(ROLE_REQUESTER)
    local user1 = self:GetParticipant(ROLE_USER1)
    local user2 = self:GetParticipant(ROLE_USER2)
    if not requester or not user1 or not user2 then
        return nil, nil, nil, "assign exactly one Requester, User 1, and User 2"
    end
    local excluded = {}
    local requesterSpell = self:FindReadySpell(requester.key, true, excluded)
    if not requesterSpell then
        return nil, nil, nil, shortName(requester)
            .. " has no uniquely assignable ready ARC spell"
    end
    excluded[requesterSpell] = true
    local user1Spell = self:FindReadySpell(user1.key, true, excluded)
    if not user1Spell then
        return nil, nil, nil, shortName(user1)
            .. " has no different uniquely assignable ready ARC spell"
    end
    excluded[user1Spell] = true
    local user2Spell = self:FindReadySpell(user2.key, true, excluded)
    if not user2Spell then
        return nil, nil, nil, shortName(user2)
            .. " has no different uniquely assignable ready ARC spell"
    end
    return requesterSpell, user1Spell, user2Spell
end

function Diagnostics:FindTwoSpellsForUser(playerKey)
    local first = self:FindReadySpell(playerKey, true)
    if not first then return nil, nil, "tester has no uniquely assignable ready ARC spell" end
    local second = self:FindReadySpell(playerKey, true, { [first] = true })
    if not second then
        return nil, nil, "tester needs two different uniquely assignable ready ARC spells"
    end
    return first, second
end

function Diagnostics:ValidateSetup()
    self:Record("CHECK", "----- setup validation -----", 0.95, 0.82, 0.30)
    local passed = true
    local function check(ok, text)
        if not ok then passed = false end
        Diagnostics:Record(ok and "PASS" or "FAIL", text,
            ok and 0.45 or 1.00, ok and 1.00 or 0.30, ok and 0.55 or 0.25)
    end
    check(ARC.Roster:IsGrouped(), "party or raid channel available")
    for _, role in ipairs({ ROLE_REQUESTER, ROLE_USER1, ROLE_USER2 }) do
        local participant, count = self:GetParticipant(role)
        check(participant ~= nil, ROLE_LABELS[role] .. " present exactly once"
            .. (participant and (": " .. shortName(participant))
                or (" (detected " .. tostring(count or 0) .. ")")))
        if participant then
            local selfKey = ARC.Roster:GetPlayer()
            local peer = participant.key == selfKey or ARC.State.peers[participant.key]
            local state = ARC.State.players[participant.key]
            local rosterIdentity = ARC.Roster.byKey[participant.key]
            check(peer and true or false, shortName(participant) .. " ARC protocol detected")
            check(rosterIdentity and rosterIdentity.connected ~= false,
                shortName(participant) .. " connected in the current roster")
            check(state and not state.dead, shortName(participant) .. " is alive")
            check(state and not state.stale, shortName(participant) .. " cooldown state is fresh")
        end
    end
    local first, second, reason = self:FindTwoUserSpells()
    check(first and second, first and ("two-user test pair: "
        .. ARC.SpellInfo:ResolveSpellName(first) .. " + "
        .. ARC.SpellInfo:ResolveSpellName(second)) or tostring(reason))
    self:Record("CHECK", passed and "SETUP READY" or "SETUP NEEDS ATTENTION",
        passed and 0.45 or 1.00, passed and 1.00 or 0.35, passed and 0.55 or 0.25)
    return passed
end

function Diagnostics:RequireRequesterTest()
    if not ARC:RequireCommandAuthority() then return false end
    if self.role ~= ROLE_REQUESTER then
        ARC:Print("select Requester in the ARC test panel first")
        return false
    end
    if not self.activeRunID then
        ARC:Print("start a three-player test session first")
        return false
    end
    return true
end

function Diagnostics:RunSingle(role)
    if not self:RequireRequesterTest() then return false end
    local participant = self:GetParticipant(role)
    if not participant then
        ARC:Print("the selected test user is missing or duplicated")
        return false
    end
    local spellID = self:FindReadySpell(participant.key, false)
    if not spellID then
        ARC:Print(shortName(participant) .. " has no ready registered ARC spell")
        return false
    end
    self:Record("TEST", "single request -> " .. shortName(participant)
        .. " / " .. ARC.SpellInfo:ResolveSpellName(spellID), 0.45, 1.00, 0.55)
    self:SendTest("CASE", "Single request", shortName(participant)
        .. " / " .. ARC.SpellInfo:ResolveSpellName(spellID))
    return ARC.Requests:Start(participant.key, spellID)
end

function Diagnostics:RunBundle()
    if not self:RequireRequesterTest() then return false end
    local first, second, reason = self:FindTwoUserSpells()
    if not first then ARC:Print(reason) return false end
    self:Record("TEST", "two-user bundle -> "
        .. ARC.SpellInfo:ResolveSpellName(first) .. " + "
        .. ARC.SpellInfo:ResolveSpellName(second), 0.45, 1.00, 0.55)
    self:SendTest("CASE", "Two-user bundle",
        ARC.SpellInfo:ResolveSpellName(first) .. " + "
        .. ARC.SpellInfo:ResolveSpellName(second))
    return ARC.Bundles:Start("ARC 3-player diagnostic bundle", { first, second })
end

function Diagnostics:RunThreePlayerBundle()
    if not self:RequireRequesterTest() then return false end
    local requesterSpell, user1Spell, user2Spell, reason =
        self:FindThreePlayerSpells()
    if not requesterSpell then ARC:Print(reason) return false end
    local detail = "Requester / " .. ARC.SpellInfo:ResolveSpellName(requesterSpell)
        .. ", User 1 / " .. ARC.SpellInfo:ResolveSpellName(user1Spell)
        .. ", User 2 / " .. ARC.SpellInfo:ResolveSpellName(user2Spell)
    self:Record("TEST", "three-player bundle -> " .. detail, 0.45, 1.00, 0.55)
    self:SendTest("CASE", "Three-player bundle", detail)
    return ARC.Bundles:Start("ARC three-player diagnostic bundle",
        { requesterSpell, user1Spell, user2Spell })
end

function Diagnostics:RunCombo()
    if not self:RequireRequesterTest() then return false end
    local first, second, reason = self:FindTwoUserSpells()
    if not first then ARC:Print(reason) return false end
    self:Record("TEST", "timed combo -> "
        .. ARC.SpellInfo:ResolveSpellName(first) .. " at -1.0s, "
        .. ARC.SpellInfo:ResolveSpellName(second) .. " at +0.0s",
        0.45, 1.00, 0.55)
    self:SendTest("CASE", "Two-user timed combo",
        ARC.SpellInfo:ResolveSpellName(first) .. " at -1.0s, "
        .. ARC.SpellInfo:ResolveSpellName(second) .. " at +0.0s")
    return ARC.Combos:Start({
        id = "diagnostic:" .. tostring(self.activeRunID),
        name = "ARC 3-player diagnostic combo",
        leadTime = 5,
        actions = {
            { spellID = first, offset = -1 },
            { spellID = second, offset = 0 },
        },
    })
end

function Diagnostics:RunQueuedBundle(role)
    if not self:RequireRequesterTest() then return false end
    local participant = self:GetParticipant(role)
    if not participant then
        ARC:Print("the selected test user is missing or duplicated")
        return false
    end
    local first, second, reason = self:FindTwoSpellsForUser(participant.key)
    if not first then ARC:Print(shortName(participant) .. ": " .. reason) return false end
    local detail = shortName(participant) .. " / "
        .. ARC.SpellInfo:ResolveSpellName(first) .. " then "
        .. ARC.SpellInfo:ResolveSpellName(second)
    self:Record("TEST", "queued same-user bundle -> " .. detail, 0.45, 1.00, 0.55)
    self:SendTest("CASE", "Queued same-user bundle", detail)
    return ARC.Bundles:Start("ARC queued diagnostic bundle", { first, second })
end

function Diagnostics:RunSameUserCombo(role)
    if not self:RequireRequesterTest() then return false end
    local participant = self:GetParticipant(role)
    if not participant then
        ARC:Print("the selected test user is missing or duplicated")
        return false
    end
    local first, second, reason = self:FindTwoSpellsForUser(participant.key)
    if not first then ARC:Print(shortName(participant) .. ": " .. reason) return false end
    local detail = shortName(participant) .. " / "
        .. ARC.SpellInfo:ResolveSpellName(first) .. " at -2.0s, "
        .. ARC.SpellInfo:ResolveSpellName(second) .. " at +0.0s"
    self:Record("TEST", "same-user timed combo -> " .. detail, 0.45, 1.00, 0.55)
    self:SendTest("CASE", "Same-user timed combo", detail)
    return ARC.Combos:Start({
        id = "diagnostic:same:" .. tostring(self.activeRunID),
        name = "ARC same-user diagnostic combo",
        leadTime = 5,
        actions = {
            { spellID = first, offset = -2 },
            { spellID = second, offset = 0 },
        },
    })
end

function Diagnostics:CancelActive()
    if not self:RequireRequesterTest() then return false end
    if ARC.Requests.outgoing then
        self:SendTest("CASE", "Cancel active", "single request")
        ARC.Requests:CancelOutgoing("diagnostic cancellation")
        return true
    elseif ARC.Bundles.active then
        self:SendTest("CASE", "Cancel active", "cooldown bundle")
        ARC.Bundles:CancelActive("diagnostic cancellation")
        return true
    elseif ARC.Combos.active or ARC.Combos.pendingComboID then
        self:SendTest("CASE", "Cancel active", "timed combo")
        ARC.Combos:CancelActive("diagnostic cancellation")
        return true
    end
    ARC:Print("there is no active ARC request, bundle, or combo to cancel")
    return false
end

function Diagnostics:ParticipantText(role)
    local values = self:GetRoleParticipants(role)
    if table.getn(values) == 0 then return "|cff777f8aWAITING|r" end
    local names = {}
    for _, value in ipairs(values) do table.insert(names, shortName(value)) end
    if table.getn(values) > 1 then
        return "|cffff4444CONFLICT: " .. table.concat(names, ", ") .. "|r"
    end
    local participant = values[1]
    local selfKey = ARC.Roster:GetPlayer()
    local rosterIdentity = ARC.Roster.byKey[participant.key]
    if not rosterIdentity then
        return "|cffff5555" .. shortName(participant) .. " - OUT OF ROSTER|r"
    end
    if rosterIdentity.connected == false then
        return "|cffff5555" .. shortName(participant) .. " - OFFLINE|r"
    end
    local peer = participant.key == selfKey or ARC.State.peers[participant.key]
    local state = ARC.State.players[participant.key]
    if not peer then return "|cffff5555" .. shortName(participant) .. " - NO ARC PEER|r" end
    if not state or state.stale then
        return "|cffffaa33" .. shortName(participant) .. " - STALE STATE|r"
    end
    if state.dead then return "|cffff5555" .. shortName(participant) .. " - DEAD|r" end
    local ready = 0
    for spellID in pairs(state.spells or {}) do
        if ARC.Registry:Get(spellID)
            and ARC.Requests:IsEligible(participant.key, spellID) then
            ready = ready + 1
        end
    end
    local age = math.max(0, ARC:Now() - (participant.lastSeen or ARC:Now()))
    local rtt = participant.lastRTT and (" / " .. tostring(participant.lastRTT) .. "ms") or ""
    return "|cff55ff88" .. shortName(participant) .. " - READY / "
        .. tostring(ready) .. " CD" .. (ready == 1 and "" or "s") .. "|r"
        .. string.format(" |cff7f8f9f%.1fs%s|r", age, rtt)
end

function Diagnostics:BuildTrackerText()
    local now = ARC:Now()
    local lines = {}
    local lease = ARC.Automation and ARC.Automation.lease
    if lease then
        local owner = ARC.State.players[lease.ownerKey] or ARC.Roster.byKey[lease.ownerKey]
        table.insert(lines, "Lease: " .. shortName(owner)
            .. string.format("  %.1fs", math.max(0, (lease.expiresAt or 0) - now)))
    else
        table.insert(lines, "Lease: none")
    end

    local request = ARC.Requests and ARC.Requests.outgoing
    if request then
        table.insert(lines, "Single TX: " .. ARC.SpellInfo:ResolveSpellName(request.spellID)
            .. " -> " .. shortName(ARC.State.players[request.targetKey])
            .. "  " .. tostring(request.status)
            .. string.format("  %.1fs", math.max(0, (request.deadline or 0) - now)))
    elseif ARC.Requests and ARC.Requests.incoming then
        local incoming = ARC.Requests.incoming
        table.insert(lines, "Single RX: " .. ARC.SpellInfo:ResolveSpellName(incoming.spellID)
            .. string.format("  %.1fs", math.max(0, (incoming.deadline or 0) - now)))
    else
        table.insert(lines, "Single: idle")
    end

    local bundle = ARC.Bundles and ARC.Bundles.active
    if bundle then
        local active, total, nextDeadline = 0, 0
        for _, item in pairs(bundle.items or {}) do
            total = total + 1
            if item.status ~= "DONE" and item.status ~= "FAILED" then
                active = active + 1
                local deadline = item.status == "QUEUED"
                    and item.queueDeadline or item.deadline
                if deadline and (not nextDeadline or deadline < nextDeadline) then
                    nextDeadline = deadline
                end
            end
        end
        table.insert(lines, "Bundle TX: " .. tostring(bundle.name)
            .. "  active " .. tostring(active) .. "/" .. tostring(total)
            .. "  used " .. tostring(bundle.completed or 0)
            .. "  failed " .. tostring(bundle.failed or 0)
            .. (nextDeadline and string.format("  timer %.1fs",
                math.max(0, nextDeadline - now)) or ""))
    else
        local incomingCount = countTable(ARC.Bundles and ARC.Bundles.incoming)
        local incomingID = ARC.Bundles and ARC.Bundles.activeIncomingID
        local incoming = incomingID and ARC.Bundles.incoming[incomingID]
        if incoming then
            table.insert(lines, "Bundle RX: "
                .. ARC.SpellInfo:ResolveSpellName(incoming.spellID)
                .. "  " .. tostring(incoming.state)
                .. (incoming.deadline and string.format("  %.1fs",
                    math.max(0, incoming.deadline - now)) or "")
                .. "  queue " .. tostring(math.max(0, incomingCount - 1)))
        else
            table.insert(lines, "Bundle RX queue: "
                .. tostring(incomingCount) .. " action(s)")
        end
    end

    local combo = ARC.Combos and ARC.Combos.active
    if combo then
        local timer = ""
        if combo.state == "COUNTDOWN" then
            timer = string.format("  anchor %.1fs",
                math.max(0, (combo.anchorAt or 0) - now))
        elseif combo.state == "PREFLIGHT" then
            local nextDeadline
            for _, action in pairs(combo.actions or {}) do
                if action.status == "PREPARING" and action.preflightDeadline
                    and (not nextDeadline or action.preflightDeadline < nextDeadline) then
                    nextDeadline = action.preflightDeadline
                end
            end
            if nextDeadline then
                timer = string.format("  preflight %.1fs",
                    math.max(0, nextDeadline - now))
            end
        end
        table.insert(lines, "Combo TX: " .. tostring(combo.name)
            .. "  " .. tostring(combo.state) .. timer
            .. "  done " .. tostring(combo.completed or 0)
            .. "  failed " .. tostring(combo.failed or 0))
    else
        local nearest
        for _, incoming in pairs(ARC.Combos and ARC.Combos.incoming or {}) do
            if incoming.dueAt then
                local remaining = incoming.dueAt - now
                if not nearest or remaining < nearest then nearest = remaining end
            end
        end
        table.insert(lines, "Combo RX: "
            .. tostring(countTable(ARC.Combos and ARC.Combos.incoming)) .. " action(s)"
            .. (nearest and string.format("  next %.1fs", nearest) or ""))
    end

    local collection = self.reportCollection
    if collection then
        local received = 0
        for _, member in ipairs(collection.members or {}) do
            if collection.reports[member.key] then received = received + 1 end
        end
        table.insert(lines, "Reports: collecting " .. tostring(received)
            .. "/3  timeout "
            .. string.format("%.1fs", math.max(0, collection.deadline - now)))
    elseif self.combinedExport then
        table.insert(lines, "Reports: |cff55ff88combined report ready|r")
    else
        table.insert(lines, "Reports: idle")
    end
    return table.concat(lines, "\n")
end

function Diagnostics:RefreshPanel()
    if not self.frame then return end
    self.frame.roleText:SetText("Local role: "
        .. (self.role and ROLE_LABELS[self.role] or "|cff777f8aNot selected|r")
        .. "    Run: " .. (self.activeRunID and "|cff55ff88ACTIVE|r" or "|cff777f8aStopped|r"))
    self.frame.requesterValue:SetText(self:ParticipantText(ROLE_REQUESTER))
    self.frame.user1Value:SetText(self:ParticipantText(ROLE_USER1))
    self.frame.user2Value:SetText(self:ParticipantText(ROLE_USER2))
    self.frame.trackers:SetText(self:BuildTrackerText())
    local officer = ARC:HasCommandAuthority()
    for _, button in ipairs(self.requesterButtons or {}) do
        if officer then button:Enable() else button:Disable() end
    end
end

function Diagnostics:ShowExport(text, title)
    self.exportFrame.title:SetText(title or "ARC Diagnostic Log - press Ctrl+C")
    self.exportBox:SetText(text or self:GetExportText())
    self.exportBox:HighlightText()
    self.exportBox:SetFocus()
    self.exportFrame:Show()
end

function Diagnostics:ShowCombinedExport()
    if not self.combinedExport then
        ARC:Print("no combined report is ready; click Collect 3 Reports first")
        return false
    end
    self:ShowExport(self.combinedExport,
        "ARC Combined Three-Player Report - press Ctrl+C")
    return true
end

function Diagnostics:CreateExportFrame()
    local frame = CreateFrame("Frame", "ActuallyARCDiagnosticExportFrame", UIParent)
    frame:SetWidth(720)
    frame:SetHeight(470)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)
    setBackdrop(frame, { 0.008, 0.016, 0.026, 0.99 }, { 0.22, 0.72, 0.96, 1 })
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 13, -12)
    frame.title:SetText("ARC Diagnostic Log - press Ctrl+C")
    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -38)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -31, 14)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(660)
    edit:SetHeight(7000)
    edit:SetTextInsets(5, 5, 5, 5)
    edit:SetScript("OnEscapePressed", function() frame:Hide() end)
    scroll:SetScrollChild(edit)
    self.exportFrame = frame
    self.exportBox = edit
    frame:Hide()
end

function Diagnostics:CreateFrame()
    local profile = ARC.db.profile.diagnosticsUI
    local frame = CreateFrame("Frame", "ActuallyARCDiagnosticsFrame", UIParent)
    frame:SetWidth(820)
    frame:SetHeight(650)
    frame:SetPoint(profile.point or "CENTER", UIParent, profile.point or "CENTER",
        profile.x or 0, profile.y or 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(owner) owner:StartMoving() end)
    frame:SetScript("OnDragStop", function(owner)
        owner:StopMovingOrSizing()
        local point, _, _, x, y = owner:GetPoint(1)
        profile.point, profile.x, profile.y = point, x, y
    end)
    setBackdrop(frame, { 0.008, 0.016, 0.026, 0.985 }, { 0.20, 0.70, 0.96, 1 })

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -12)
    frame.title:SetText("ARC Three-Player Test Harness - " .. ARC.Constants.WIP_TEXT)
    frame.title:SetTextColor(0.92, 0.96, 1.00)
    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    frame.roleText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.roleText:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -40)
    frame.roleText:SetWidth(790)
    frame.roleText:SetJustifyH("LEFT")

    local requesterRole = makeButton(frame, 92, "Requester")
    requesterRole:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -62)
    requesterRole:SetScript("OnClick", function() self:SetRole(ROLE_REQUESTER) end)
    local user1Role = makeButton(frame, 76, "User 1")
    user1Role:SetPoint("LEFT", requesterRole, "RIGHT", 5, 0)
    user1Role:SetScript("OnClick", function() self:SetRole(ROLE_USER1) end)
    local user2Role = makeButton(frame, 76, "User 2")
    user2Role:SetPoint("LEFT", user1Role, "RIGHT", 5, 0)
    user2Role:SetScript("OnClick", function() self:SetRole(ROLE_USER2) end)
    local leave = makeButton(frame, 62, "Leave")
    leave:SetPoint("LEFT", user2Role, "RIGHT", 5, 0)
    leave:SetScript("OnClick", function() self:LeaveTest() end)

    local start = makeButton(frame, 90, "Start Session")
    start:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -62)
    start:SetScript("OnClick", function() self:StartSession() end)
    local stop = makeButton(frame, 55, "Stop")
    stop:SetPoint("RIGHT", start, "LEFT", -5, 0)
    stop:SetScript("OnClick", function() self:StopSession() end)
    local validate = makeButton(frame, 70, "Validate")
    validate:SetPoint("RIGHT", stop, "LEFT", -5, 0)
    validate:SetScript("OnClick", function() self:ValidateSetup() end)
    local ping = makeButton(frame, 55, "Ping")
    ping:SetPoint("RIGHT", validate, "LEFT", -5, 0)
    ping:SetScript("OnClick", function() self:PingTesters() end)
    self.requesterButtons = { requesterRole, start, stop, validate, ping }

    local cards = {}
    for index, role in ipairs({ ROLE_REQUESTER, ROLE_USER1, ROLE_USER2 }) do
        local card = CreateFrame("Frame", nil, frame)
        card:SetWidth(257)
        card:SetHeight(48)
        card:SetPoint("TOPLEFT", frame, "TOPLEFT", 14 + (index - 1) * 264, -94)
        setBackdrop(card, { 0.012, 0.028, 0.044, 0.96 }, { 0.12, 0.38, 0.55, 0.95 })
        card.label = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        card.label:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -7)
        card.label:SetText(ROLE_LABELS[role])
        card.value = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        card.value:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 8, 8)
        card.value:SetWidth(241)
        card.value:SetJustifyH("LEFT")
        cards[role] = card
    end
    frame.requesterValue = cards[ROLE_REQUESTER].value
    frame.user1Value = cards[ROLE_USER1].value
    frame.user2Value = cards[ROLE_USER2].value

    local singleRequester = makeButton(frame, 120, "Single -> Requester")
    singleRequester:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -151)
    singleRequester:SetScript("OnClick", function() self:RunSingle(ROLE_REQUESTER) end)
    local single1 = makeButton(frame, 105, "Single -> User 1")
    single1:SetPoint("LEFT", singleRequester, "RIGHT", 5, 0)
    single1:SetScript("OnClick", function() self:RunSingle(ROLE_USER1) end)
    local single2 = makeButton(frame, 105, "Single -> User 2")
    single2:SetPoint("LEFT", single1, "RIGHT", 5, 0)
    single2:SetScript("OnClick", function() self:RunSingle(ROLE_USER2) end)
    local bundle = makeButton(frame, 116, "Two-User Bundle")
    bundle:SetPoint("LEFT", single2, "RIGHT", 5, 0)
    bundle:SetScript("OnClick", function() self:RunBundle() end)
    local threeBundle = makeButton(frame, 126, "Three-Player Bundle")
    threeBundle:SetPoint("LEFT", bundle, "RIGHT", 5, 0)
    threeBundle:SetScript("OnClick", function() self:RunThreePlayerBundle() end)
    local combo = makeButton(frame, 124, "Two-User Combo")
    combo:SetPoint("LEFT", threeBundle, "RIGHT", 5, 0)
    combo:SetScript("OnClick", function() self:RunCombo() end)
    local state = makeButton(frame, 92, "Request State")
    state:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -178)
    state:SetScript("OnClick", function() ARC.Comms:RequestState(false) end)
    table.insert(self.requesterButtons, singleRequester)
    table.insert(self.requesterButtons, single1)
    table.insert(self.requesterButtons, single2)
    table.insert(self.requesterButtons, bundle)
    table.insert(self.requesterButtons, threeBundle)
    table.insert(self.requesterButtons, combo)

    local queued1 = makeButton(frame, 118, "Queue 2 -> User 1")
    queued1:SetPoint("LEFT", state, "RIGHT", 5, 0)
    queued1:SetScript("OnClick", function() self:RunQueuedBundle(ROLE_USER1) end)
    local queued2 = makeButton(frame, 118, "Queue 2 -> User 2")
    queued2:SetPoint("LEFT", queued1, "RIGHT", 5, 0)
    queued2:SetScript("OnClick", function() self:RunQueuedBundle(ROLE_USER2) end)
    local sameCombo = makeButton(frame, 145, "Same-User Combo (U1)")
    sameCombo:SetPoint("LEFT", queued2, "RIGHT", 5, 0)
    sameCombo:SetScript("OnClick", function() self:RunSameUserCombo(ROLE_USER1) end)
    local cancel = makeButton(frame, 92, "Cancel Active")
    cancel:SetPoint("LEFT", sameCombo, "RIGHT", 5, 0)
    cancel:SetScript("OnClick", function() self:CancelActive() end)
    table.insert(self.requesterButtons, queued1)
    table.insert(self.requesterButtons, queued2)
    table.insert(self.requesterButtons, sameCombo)
    table.insert(self.requesterButtons, cancel)

    local tracker = CreateFrame("Frame", nil, frame)
    tracker:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -211)
    tracker:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    tracker:SetHeight(101)
    setBackdrop(tracker, { 0.005, 0.012, 0.020, 0.96 }, { 0.12, 0.33, 0.46, 0.95 })
    tracker.title = tracker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tracker.title:SetPoint("TOPLEFT", tracker, "TOPLEFT", 8, -7)
    tracker.title:SetText("Live timers and automation state")
    frame.trackers = tracker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.trackers:SetPoint("TOPLEFT", tracker, "TOPLEFT", 8, -23)
    frame.trackers:SetPoint("BOTTOMRIGHT", tracker, "BOTTOMRIGHT", -8, 7)
    frame.trackers:SetJustifyH("LEFT")
    frame.trackers:SetJustifyV("TOP")

    local logBox = CreateFrame("Frame", nil, frame)
    logBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -321)
    logBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 46)
    setBackdrop(logBox, { 0.002, 0.006, 0.011, 0.98 }, { 0.10, 0.29, 0.41, 0.95 })
    local log = CreateFrame("ScrollingMessageFrame", nil, logBox)
    log:SetPoint("TOPLEFT", logBox, "TOPLEFT", 8, -7)
    log:SetPoint("BOTTOMRIGHT", logBox, "BOTTOMRIGHT", -8, 7)
    log:SetFontObject(ChatFontNormal)
    log:SetJustifyH("LEFT")
    log:SetFading(false)
    log:SetMaxLines(MAX_LOG_LINES)
    log:EnableMouseWheel(true)
    log:SetScript("OnMouseWheel", function(owner, delta)
        if delta > 0 then owner:ScrollUp() else owner:ScrollDown() end
    end)
    logBox:Show()
    log:Show()
    self.logFrame = log

    local clear = makeButton(frame, 65, "Clear Log")
    clear:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 14)
    clear:SetScript("OnClick", function() self:ClearLog() end)
    local export = makeButton(frame, 75, "Export Log")
    export:SetPoint("LEFT", clear, "RIGHT", 5, 0)
    export:SetScript("OnClick", function() self:ShowExport() end)
    local collect = makeButton(frame, 105, "Collect 3 Reports")
    collect:SetPoint("LEFT", export, "RIGHT", 5, 0)
    collect:SetScript("OnClick", function() self:CollectReports() end)
    local combined = makeButton(frame, 105, "Export Combined")
    combined:SetPoint("LEFT", collect, "RIGHT", 5, 0)
    combined:SetScript("OnClick", function() self:ShowCombinedExport() end)
    table.insert(self.requesterButtons, collect)
    table.insert(self.requesterButtons, combined)
    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 20)
    note:SetText("All three players must run protocol "
        .. tostring(ARC.Constants.PROTOCOL_VERSION) .. " and select different roles.")

    self.frame = frame
    frame:SetScript("OnShow", function()
        self:BroadcastHello()
        self:RefreshPanel()
    end)
    frame:Hide()
end

function Diagnostics:Initialize()
    if self.initialized then return end
    self.logs = self.logs or {}
    self.participants = {}
    self.pendingPings = {}
    self.remoteSequences = {}
    self.sequence = 0
    self.runCounter = 0
    self.reportCounter = 0
    self.reportCollection = nil
    self.combinedExport = nil
    self.lastReportResponseAt = -100
    self.lastCollectionAt = -100
    self.startedAt = ARC:Now()
    self.session = tostring(time and time() or 0)
        .. ":" .. tostring(math.random(100000, 999999))
    self.nextHelloAt = 0
    self.nextRefreshAt = 0
    self:CreateFrame()
    self:CreateExportFrame()
    ARC:RegisterComm(ARC.Constants.TEST_PREFIX, function(...)
        self:OnTestComm(...)
    end)
    self.initialized = true
    self:Record("TEST", "three-player diagnostic harness ready", 0.45, 1.00, 0.55)
end

function Diagnostics:OnUpdate(now)
    if not self.initialized then return end
    if not self.role and not self.activeRunID and not self.reportCollection
        and not (self.frame and self.frame:IsShown()) then return end
    if self.role and ARC.Roster:IsGrouped() and now >= (self.nextHelloAt or 0) then
        self:BroadcastHello()
    end
    if now < (self.nextRefreshAt or 0) then return end
    self.nextRefreshAt = now + 0.20
    for key, participant in pairs(self.participants) do
        if key ~= ARC.Roster:GetPlayer()
            and now - (participant.lastSeen or 0) > PARTICIPANT_TIMEOUT then
            self.participants[key] = nil
        end
    end
    for nonce, ping in pairs(self.pendingPings) do
        if now - (ping.sentAt or now) >= 3 then
            for _, role in ipairs({ ROLE_USER1, ROLE_USER2 }) do
                local participant = self:GetParticipant(role)
                if participant and not ping.responders[participant.key] then
                    self:Record("PING", ROLE_LABELS[role] .. " / "
                        .. shortName(participant) .. " did not respond within 3.0s",
                        1.00, 0.35, 0.25)
                end
            end
            self.pendingPings[nonce] = nil
        end
    end
    if self.reportCollection and now >= self.reportCollection.deadline then
        self:FinishReportCollection(true)
    end
    if self.frame and self.frame:IsShown() then self:RefreshPanel() end
end

function Diagnostics:Show()
    if not self.frame then
        ARC:Print("diagnostic panel unavailable; fully restart the game client")
        return false
    end
    if ARC.OfficerConfig and ARC.OfficerConfig.frame then
        return ARC.OfficerConfig:Show("diagnostics")
    end
    self.frame:Show()
    self:RefreshPanel()
    return true
end

function Diagnostics:Toggle()
    if not self.frame then
        ARC:Print("diagnostic panel unavailable; fully restart the game client")
        return false
    end
    if ARC.OfficerConfig and ARC.OfficerConfig.frame then
        return ARC.OfficerConfig:Toggle("diagnostics")
    end
    if self.frame:IsShown() then self.frame:Hide() return false end
    return self:Show()
end
