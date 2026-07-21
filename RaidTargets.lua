Actually = Actually or {}
local Addon = Actually

-- Headless raid-assist target logger.
--
-- The officer controls START/STOP. Every participating client records only
-- its own PLAYER_TARGET_CHANGED events locally. After STOP, participants
-- upload the completed timeline to the officer and retain it until the
-- officer acknowledges successful processing.
local RaidTargets = {}
Addon.RaidTargets = RaidTargets

local KIND = "AL"
local PROTOCOL = 1
local NO_TARGET = "(no target)"
-- Same checksummed/chunked envelope as Sync.lua. The Assist Log header also
-- carries a run ID, so its data chunk is slightly smaller to stay <240 bytes.
local TRANSFER_CHUNK_SIZE = 150
local TRANSFER_RETRY_SECONDS = 10
local TRANSFER_SLOW_RETRY_SECONDS = 30
local MAX_TRANSFER_CHUNKS = 2000
local CLOCK_PING_COUNT = 3
local CLOCK_PING_INTERVAL = 0.45

local function Now()
    return GetTime and GetTime() or 0
end

local function Stamp()
    return time and time() or 0
end

local function ShortName(identity)
    return Addon.Util.ShortName(identity)
end

local function PlayerKey(identity)
    return Addon.Util.NormalizeCharacter(identity)
end

local function Encode(value)
    return string.gsub(tostring(value or ""), "([^%w%-%._ ])", function(character)
        return string.format("%%%02X", string.byte(character))
    end)
end

local function Decode(value)
    return string.gsub(value or "", "%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
end

local function Hash(value)
    local hash = 5381
    for index = 1, string.len(value or "") do
        hash = (hash * 33 + string.byte(value, index)) % 2147483647
    end
    return tostring(hash)
end

local function DirectMessage(message, channel, target)
    if not SendAddonMessage then
        return false
    end
    return pcall(SendAddonMessage, Addon.MESSAGE_PREFIX, message, channel, target)
end

local function QueuedMessage(message, channel, target)
    if Addon.Sync and Addon.Sync.initialized and Addon.Sync.QueueMessage then
        Addon.Sync:QueueMessage(message, channel, target)
        return true
    end
    return DirectMessage(message, channel, target)
end

local function TransportLog(message)
    if Addon.Sync and Addon.Sync.Log then
        Addon.Sync:Log("Assist Log: " .. tostring(message))
    end
end

local function CurrentTarget()
    if not UnitExists or not UnitExists("target") then
        return NO_TARGET, ""
    end
    local name = UnitName and UnitName("target")
    if not name or name == "" then
        return NO_TARGET, ""
    end
    return name, (UnitGUID and UnitGUID("target")) or ""
end

local function RaidRank(identity)
    local wanted = PlayerKey(identity)
    local count = GetNumRaidMembers and GetNumRaidMembers() or 0
    for index = 1, count do
        local name, rank = GetRaidRosterInfo(index)
        if PlayerKey(name) == wanted then
            return tonumber(rank) or 0
        end
    end
    return -1
end

local function IsRaidMember(identity)
    return RaidRank(identity) >= 0
end

local function FindRaidMember(identity)
    local wanted = PlayerKey(identity)
    local count = GetNumRaidMembers and GetNumRaidMembers() or 0
    for index = 1, count do
        local name = GetRaidRosterInfo(index)
        if name and PlayerKey(name) == wanted then
            return ShortName(name)
        end
    end
end

local function CaptureLocalChange(run)
    if not run then
        return false
    end
    run.localChanges = type(run.localChanges) == "table" and run.localChanges or {}
    local target, guid = CurrentTarget()
    local previous = run.localChanges[#run.localChanges]
    if previous and previous.target == target and (previous.guid or "") == guid then
        return false
    end
    table.insert(run.localChanges, {
        at = Now(),
        target = target,
        guid = guid,
    })
    return true
end

local function NormalizeEvents(localChanges, clockOffset, officerStart, duration)
    local events = {}
    local previous
    for _, change in ipairs(localChanges or {}) do
        local timestamp = (tonumber(change.at) or 0) - (tonumber(clockOffset) or 0) - officerStart
        timestamp = math.max(0, math.min(duration, timestamp))
        local event = {
            t = timestamp,
            target = change.target or NO_TARGET,
            guid = change.guid or "",
        }
        if not previous or previous.target ~= event.target or previous.guid ~= event.guid then
            table.insert(events, event)
            previous = event
        end
    end
    table.sort(events, function(left, right)
        return (left.t or 0) < (right.t or 0)
    end)
    return events
end

local function SerializeParticipantRun(run)
    local records = { string.format("%.3f", tonumber(run.startedAtLocal) or 0) }
    for _, change in ipairs(run.localChanges or {}) do
        table.insert(records, table.concat({
            string.format("%.3f", tonumber(change.at) or 0),
            Encode(change.guid),
            Encode(change.target),
        }, ","))
    end
    return table.concat(records, ";")
end

local function DeserializeParticipantRun(payload)
    local records = {}
    for record in string.gmatch((payload or "") .. ";", "(.-);") do
        table.insert(records, record)
    end
    local startedAtLocal = tonumber(records[1])
    if not startedAtLocal then
        return nil
    end
    local changes = {}
    for index = 2, #records do
        local at, guid, target = string.match(records[index], "^([^,]+),([^,]*),(.*)$")
        if not at then
            return nil
        end
        table.insert(changes, {
            at = tonumber(at) or startedAtLocal,
            guid = Decode(guid),
            target = Decode(target),
        })
    end
    return { startedAtLocal = startedAtLocal, localChanges = changes }
end

local function SplitChunks(payload)
    local chunks = {}
    for index = 1, string.len(payload), TRANSFER_CHUNK_SIZE do
        table.insert(chunks, string.sub(payload, index, index + TRANSFER_CHUNK_SIZE - 1))
    end
    if #chunks == 0 then
        chunks[1] = ""
    end
    return chunks
end

local function FindFightByID(runID)
    if RaidTargets.activeOfficerRun and RaidTargets.activeOfficerRun.id == runID then
        return RaidTargets.activeOfficerRun
    end
    local fights = Addon.db and Addon.db.assistLog and Addon.db.assistLog.fights or {}
    for index = #fights, 1, -1 do
        if fights[index].id == runID then
            return fights[index]
        end
    end
    return nil
end

local function TargetAt(events, timestamp)
    local current = { target = NO_TARGET, guid = "" }
    for _, event in ipairs(events or {}) do
        if (event.t or 0) > timestamp then
            break
        end
        current = event
    end
    return current
end

local function SortedUniqueBoundaries(callerEvents, playerEvents, duration)
    local boundaries = { 0, duration }
    for _, events in ipairs({ callerEvents or {}, playerEvents or {} }) do
        for _, event in ipairs(events) do
            local timestamp = tonumber(event.t) or 0
            if timestamp > 0 and timestamp < duration then
                table.insert(boundaries, timestamp)
            end
        end
    end
    table.sort(boundaries)
    local unique = {}
    for _, timestamp in ipairs(boundaries) do
        if #unique == 0 or math.abs(timestamp - unique[#unique]) > 0.0005 then
            table.insert(unique, timestamp)
        end
    end
    return unique
end

local function MergeSegment(segments, segment)
    local previous = segments[#segments]
    if previous and previous.match == segment.match
        and previous.callerGUID == segment.callerGUID
        and previous.playerGUID == segment.playerGUID then
        previous.endAt = segment.endAt
        previous.duration = previous.endAt - previous.startAt
    else
        table.insert(segments, segment)
    end
end

function RaidTargets:Initialize()
    if self.initialized then
        return
    end
    self.initialized = true
    Addon.db.assistLog = type(Addon.db.assistLog) == "table" and Addon.db.assistLog or {}
    Addon.db.assistLog.fights = type(Addon.db.assistLog.fights) == "table" and Addon.db.assistLog.fights or {}
    Addon.db.assistLog.pendingUploads = type(Addon.db.assistLog.pendingUploads) == "table"
        and Addon.db.assistLog.pendingUploads or {}
    -- GetTime() can restart from a smaller value after a full client restart.
    -- Force every unacknowledged saved upload to retry in this login.
    for _, upload in pairs(Addon.db.assistLog.pendingUploads) do
        upload.lastSentAt = 0
    end

    self.activeOfficerRun = Addon.db.assistLog.activeOfficerRun
    self.participantRun = Addon.db.assistLog.activeParticipantRun
    if self.activeOfficerRun and Now() + 1 < (tonumber(self.activeOfficerRun.startedAt) or 0) then
        self.activeOfficerRun = nil
        Addon.db.assistLog.activeOfficerRun = nil
    end
    if self.participantRun and Now() + 1 < (tonumber(self.participantRun.startedAtLocal) or 0) then
        self.participantRun = nil
        Addon.db.assistLog.activeParticipantRun = nil
    end
    self.incomingTransfers = {}
    self.retryElapsed = 0
    self.nextClockPing = 0
    self.clockPingsSent = 0

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:RegisterEvent("RAID_ROSTER_UPDATE")
    frame:SetScript("OnEvent", function(_, event, ...)
        RaidTargets:OnEvent(event, ...)
    end)
    frame:SetScript("OnUpdate", function(_, elapsed)
        RaidTargets:OnUpdate(elapsed)
    end)
    self.frame = frame
end

function RaidTargets:IsRunning()
    return self.activeOfficerRun ~= nil
end

function RaidTargets:CanControl()
    return Addon.Official and Addon.Official.IsOfficer and Addon.Official:IsOfficer() == true
end

function RaidTargets:GetSelectedCaller()
    local selected = Addon.db and Addon.db.assistLog and Addon.db.assistLog.selectedCaller
    return selected and selected ~= "" and selected or ShortName(UnitName and UnitName("player"))
end

function RaidTargets:SetSelectedCaller(specification)
    if not self:CanControl() then
        return nil, "Only an actually officer can choose the Assist Log shot caller."
    end
    local value = Addon.Util.Trim(specification)
    local lowered = string.lower(value)
    if lowered == "target" then
        value = UnitName and UnitName("target") or ""
    elseif lowered == "me" or lowered == "self" or lowered == "officer" or lowered == "clear" then
        value = UnitName and UnitName("player") or ""
    end
    if value == "" then
        return nil, "Usage: /actually assistlog caller <raid player|target|me>"
    end
    local member = FindRaidMember(value)
    if not member then
        return nil, tostring(value) .. " is not in your current raid."
    end
    Addon.db.assistLog.selectedCaller = member
    self:NotifyChanged()
    return member
end

function RaidTargets:HandleCommand(arguments)
    local command, rest = string.match(Addon.Util.Trim(arguments), "^(%S+)%s*(.*)$")
    command = string.lower(command or "")
    if command ~= "caller" then
        return false
    end
    if rest == "" then
        Addon:Print("Assist Log shot caller: " .. tostring(self:GetSelectedCaller())
            .. ". Set with /actually assistlog caller <raid player|target|me>.")
        return true
    end
    local caller, errorMessage = self:SetSelectedCaller(rest)
    if caller then
        Addon:Print("Assist Log shot caller set to " .. caller .. ".")
    else
        Addon:Print(errorMessage)
    end
    return true
end

function RaidTargets:GetActiveRun()
    return self.activeOfficerRun
end

function RaidTargets:GetFights()
    return Addon.db and Addon.db.assistLog and Addon.db.assistLog.fights or {}
end

function RaidTargets:GetLastFight()
    local fights = self:GetFights()
    return fights[#fights]
end

function RaidTargets:GetPendingUploadCount()
    local count = 0
    for _ in pairs(Addon.db.assistLog.pendingUploads or {}) do
        count = count + 1
    end
    return count
end

function RaidTargets:NotifyChanged()
    if Addon.AssistLogUI and Addon.AssistLogUI.OnDataChanged then
        Addon.AssistLogUI:OnDataChanged()
    end
end

function RaidTargets:Start(label)
    if self.activeOfficerRun then
        return nil, "An assist log is already running."
    end
    if not GetNumRaidMembers or GetNumRaidMembers() == 0 then
        return nil, "Assist Log can only start while you are in a raid."
    end
    local ownName = UnitName and UnitName("player")
    if not self:CanControl() then
        return nil, "Only an actually officer can start Assist Log."
    end
    local callerName = FindRaidMember(self:GetSelectedCaller())
    if not callerName then
        return nil, "The selected shot caller is not in this raid. Set one with /actually assistlog caller <player|target|me>."
    end

    local run = {
        id = tostring(Stamp()) .. "." .. tostring(math.random(100000, 999999)),
        schema = 1,
        label = Addon.Util.Trim(label),
        officer = ShortName(ownName),
        officerKey = PlayerKey(ownName),
        caller = callerName,
        callerKey = PlayerKey(callerName),
        startedAt = Now(),
        startedEpoch = Stamp(),
        localChanges = {},
        players = {},
        clock = {},
        expected = {},
        state = "recording",
    }
    local count = GetNumRaidMembers()
    for index = 1, count do
        local name = GetRaidRosterInfo(index)
        if name and name ~= "" then
            local key = PlayerKey(name)
            run.expected[key] = ShortName(name)
            run.players[key] = { name = ShortName(name), status = key == run.officerKey and "recording" or "waiting" }
        end
    end

    self.activeOfficerRun = run
    Addon.db.assistLog.activeOfficerRun = run
    CaptureLocalChange(run)
    self.clockPingsSent = 0
    self.nextClockPing = Now() + 0.10

    DirectMessage(table.concat({
        KIND, "S", tostring(PROTOCOL), Encode(run.id), Encode(run.label), Encode(run.caller),
        string.format("%.3f", run.startedAt),
    }, "|"), "RAID")
    TransportLog("Started " .. run.id .. " for " .. tostring(count) .. " raid members.")
    self:NotifyChanged()
    return run
end

function RaidTargets:Stop()
    local run = self.activeOfficerRun
    if not run then
        return nil, "No assist log is running."
    end
    CaptureLocalChange(run)
    run.stoppedAt = Now()
    run.stoppedEpoch = Stamp()
    run.duration = math.max(0, run.stoppedAt - run.startedAt)
    run.state = "receiving"

    local ownPlayer = run.players[run.officerKey] or { name = run.officer }
    ownPlayer.status = "received"
    ownPlayer.version = Addon.version
    ownPlayer.clockRTT = 0
    ownPlayer.changes = NormalizeEvents(run.localChanges, 0, run.startedAt, run.duration)
    run.players[run.officerKey] = ownPlayer
    run.localChanges = nil

    for key, player in pairs(run.players) do
        if key ~= run.officerKey then
            player.status = player.status == "recording" and "awaiting upload" or "no addon response"
        end
    end

    self.activeOfficerRun = nil
    Addon.db.assistLog.activeOfficerRun = nil
    table.insert(Addon.db.assistLog.fights, run)
    Addon.db.assistLog.lastFightID = run.id

    DirectMessage(table.concat({
        KIND, "E", tostring(PROTOCOL), Encode(run.id), string.format("%.3f", run.duration),
    }, "|"), "RAID")
    TransportLog("Stopped " .. run.id .. "; waiting for post-fight uploads.")
    self:NotifyChanged()
    return run
end

function RaidTargets:DeleteFight(runID)
    local fights = self:GetFights()
    for index = #fights, 1, -1 do
        if fights[index].id == runID then
            table.remove(fights, index)
            self:NotifyChanged()
            return true
        end
    end
    return false
end

function RaidTargets:DeletePlayerContribution(runID, playerKey)
    local fight = FindFightByID(runID)
    if not fight then
        return nil, "Fight not found."
    end
    if playerKey == fight.callerKey then
        return nil, "The shot caller timeline is required for every comparison; delete the whole fight instead."
    end
    local player = fight.players and fight.players[playerKey]
    if not player then
        return nil, "Player contribution not found."
    end
    fight.removedPlayers = type(fight.removedPlayers) == "table" and fight.removedPlayers or {}
    fight.removedPlayers[playerKey] = Stamp()
    fight.players[playerKey] = {
        name = player.name,
        status = "contribution removed",
        removedEpoch = Stamp(),
    }
    self:NotifyChanged()
    return true
end

function RaidTargets:ClearHistory()
    if self.activeOfficerRun then
        return nil, "Stop the active assist log before clearing history."
    end
    Addon.db.assistLog.fights = {}
    Addon.db.assistLog.lastFightID = nil
    self:NotifyChanged()
    return true
end

function RaidTargets:BuildPlayerAnalysis(fight, playerKey)
    fight = fight or self:GetLastFight()
    if not fight then
        return nil, "No fight is available."
    end
    local caller = fight.players and fight.players[fight.callerKey]
    local player = fight.players and fight.players[playerKey]
    if not caller or caller.status ~= "received" or not caller.changes then
        return nil, "The shot caller timeline is unavailable."
    end
    if not player or player.status ~= "received" or not player.changes then
        return nil, "That player's timeline has not been received."
    end

    local duration = tonumber(fight.duration) or 0
    local boundaries = SortedUniqueBoundaries(caller.changes, player.changes, duration)
    local analysis = {
        playerKey = playerKey,
        playerName = player.name,
        callerName = caller.name,
        duration = duration,
        matchedSeconds = 0,
        eligibleSeconds = 0,
        segments = {},
    }
    for index = 1, #boundaries - 1 do
        local startAt = boundaries[index]
        local endAt = boundaries[index + 1]
        if endAt > startAt then
            local callerTarget = TargetAt(caller.changes, startAt)
            local playerTarget = TargetAt(player.changes, startAt)
            local eligible = callerTarget.guid and callerTarget.guid ~= ""
            local matches = eligible and playerTarget.guid == callerTarget.guid
            local segmentDuration = endAt - startAt
            if eligible then
                analysis.eligibleSeconds = analysis.eligibleSeconds + segmentDuration
                if matches then
                    analysis.matchedSeconds = analysis.matchedSeconds + segmentDuration
                end
            end
            MergeSegment(analysis.segments, {
                startAt = startAt,
                endAt = endAt,
                duration = segmentDuration,
                eligible = eligible,
                match = matches,
                callerTarget = callerTarget.target or NO_TARGET,
                callerGUID = callerTarget.guid or "",
                playerTarget = playerTarget.target or NO_TARGET,
                playerGUID = playerTarget.guid or "",
            })
        end
    end
    analysis.percent = analysis.eligibleSeconds > 0
        and (analysis.matchedSeconds / analysis.eligibleSeconds * 100) or 0
    return analysis
end

function RaidTargets:BuildFightOverview(fight)
    fight = fight or self:GetLastFight()
    if not fight then
        return nil, "No fight is available."
    end
    local rows = {}
    for key, player in pairs(fight.players or {}) do
        local row = { key = key, name = player.name, status = player.status, isCaller = key == fight.callerKey }
        if player.status == "received" then
            local analysis = self:BuildPlayerAnalysis(fight, key)
            if analysis then
                row.matchedSeconds = analysis.matchedSeconds
                row.eligibleSeconds = analysis.eligibleSeconds
                row.percent = analysis.percent
            end
        end
        table.insert(rows, row)
    end
    table.sort(rows, function(left, right)
        return string.lower(left.name or "") < string.lower(right.name or "")
    end)
    return rows
end

function RaidTargets:BuildOverallPerformance()
    local byPlayer = {}
    for _, fight in ipairs(self:GetFights()) do
        for key, player in pairs(fight.players or {}) do
            if key ~= fight.callerKey and player.status == "received"
                and not (fight.removedPlayers and fight.removedPlayers[key]) then
                local analysis = self:BuildPlayerAnalysis(fight, key)
                if analysis then
                    local aggregate = byPlayer[key] or {
                        key = key,
                        name = player.name,
                        fights = {},
                        fightCount = 0,
                        matchedSeconds = 0,
                        eligibleSeconds = 0,
                    }
                    aggregate.name = player.name or aggregate.name
                    aggregate.fightCount = aggregate.fightCount + 1
                    aggregate.matchedSeconds = aggregate.matchedSeconds + analysis.matchedSeconds
                    aggregate.eligibleSeconds = aggregate.eligibleSeconds + analysis.eligibleSeconds
                    table.insert(aggregate.fights, {
                        fightID = fight.id,
                        label = fight.label,
                        startedEpoch = fight.startedEpoch,
                        duration = fight.duration,
                        matchedSeconds = analysis.matchedSeconds,
                        eligibleSeconds = analysis.eligibleSeconds,
                        percent = analysis.percent,
                    })
                    byPlayer[key] = aggregate
                end
            end
        end
    end

    local rows = {}
    for _, aggregate in pairs(byPlayer) do
        aggregate.percent = aggregate.eligibleSeconds > 0
            and (aggregate.matchedSeconds / aggregate.eligibleSeconds * 100) or 0
        table.sort(aggregate.fights, function(left, right)
            return (left.startedEpoch or 0) > (right.startedEpoch or 0)
        end)
        table.insert(rows, aggregate)
    end
    table.sort(rows, function(left, right)
        if math.abs((left.percent or 0) - (right.percent or 0)) > 0.0001 then
            return (left.percent or 0) > (right.percent or 0)
        end
        return string.lower(left.name or "") < string.lower(right.name or "")
    end)
    return rows
end

function RaidTargets:BuildPlayerHistory(playerKey)
    local rows = {}
    for _, fight in ipairs(self:GetFights()) do
        local player = fight.players and fight.players[playerKey]
        if player or (fight.expected and fight.expected[playerKey]) then
            local row = {
                fightID = fight.id,
                label = fight.label,
                startedEpoch = fight.startedEpoch,
                duration = fight.duration,
                status = player and player.status or "no data",
                isCaller = playerKey == fight.callerKey,
            }
            if player and player.status == "received" and not row.isCaller
                and not (fight.removedPlayers and fight.removedPlayers[playerKey]) then
                local analysis = self:BuildPlayerAnalysis(fight, playerKey)
                if analysis then
                    row.matchedSeconds = analysis.matchedSeconds
                    row.eligibleSeconds = analysis.eligibleSeconds
                    row.percent = analysis.percent
                end
            end
            table.insert(rows, row)
        end
    end
    table.sort(rows, function(left, right)
        return (left.startedEpoch or 0) > (right.startedEpoch or 0)
    end)
    return rows
end

function RaidTargets:SendClockPing()
    local run = self.activeOfficerRun
    if not run then
        return
    end
    self.clockPingsSent = self.clockPingsSent + 1
    local pingID = tostring(self.clockPingsSent)
    local sentAt = Now()
    DirectMessage(table.concat({
        KIND, "P", tostring(PROTOCOL), Encode(run.id), pingID, string.format("%.6f", sentAt),
    }, "|"), "RAID")
end

function RaidTargets:QueueUpload(run)
    local payload = SerializeParticipantRun(run)
    local transferID = run.id .. "." .. tostring(math.random(100000, 999999))
    local upload = {
        runID = run.id,
        officer = run.officer,
        transferID = transferID,
        payload = payload,
        digest = Hash(payload),
        chunks = SplitChunks(payload),
        createdEpoch = Stamp(),
        lastSentAt = 0,
        attempts = 0,
    }
    Addon.db.assistLog.pendingUploads[run.id] = upload
    self:SendUpload(upload)
    return upload
end

function RaidTargets:SendUpload(upload)
    if not upload or not upload.officer or upload.officer == "" then
        return
    end
    upload.chunks = type(upload.chunks) == "table" and upload.chunks or SplitChunks(upload.payload or "")
    local total = #upload.chunks
    if total > MAX_TRANSFER_CHUNKS then
        return
    end
    for index, chunk in ipairs(upload.chunks) do
        QueuedMessage(table.concat({
            KIND, "D", tostring(PROTOCOL), Encode(upload.runID), Encode(upload.transferID),
            tostring(index), tostring(total), upload.digest, chunk,
        }, "|"), "WHISPER", upload.officer)
    end
    -- Sync.lua accounts for its 0.15s/message queue when scheduling retries;
    -- do the same so a large first transfer finishes before retrying.
    upload.lastSentAt = Now() + (total * 0.15)
    upload.attempts = (upload.attempts or 0) + 1
    TransportLog("Queued " .. tostring(total) .. " chunk(s) for " .. ShortName(upload.officer)
        .. " (attempt " .. tostring(upload.attempts) .. ").")
end

function RaidTargets:ApplyTransfer(fight, sender, transferID, payload)
    local decoded = DeserializeParticipantRun(payload)
    if not decoded then
        return false
    end
    local key = PlayerKey(sender)
    if fight.removedPlayers and fight.removedPlayers[key] then
        -- The officer deliberately removed this contribution. A duplicate or
        -- delayed retry must still be acknowledged so the sender can wipe its
        -- pending copy, but it must not restore the deleted timeline.
        QueuedMessage(table.concat({
            KIND, "C", tostring(PROTOCOL), Encode(fight.id), Encode(transferID),
        }, "|"), "WHISPER", sender)
        return true
    end
    local clock = fight.clock and fight.clock[key]
    local offset = clock and tonumber(clock.offset)
    if not offset then
        -- Fallback only. The normal path uses the lowest-RTT NTP-style ping.
        offset = decoded.startedAtLocal - fight.startedAt
    end
    local player = fight.players[key] or { name = ShortName(sender) }
    player.name = ShortName(sender)
    player.status = "received"
    player.receivedEpoch = Stamp()
    player.clockOffset = offset
    player.clockRTT = clock and clock.rtt or nil
    player.changes = NormalizeEvents(decoded.localChanges, offset, fight.startedAt, fight.duration or 0)
    fight.players[key] = player
    QueuedMessage(table.concat({
        KIND, "C", tostring(PROTOCOL), Encode(fight.id), Encode(transferID),
    }, "|"), "WHISPER", sender)
    TransportLog("Processed target timeline from " .. ShortName(sender) .. " and queued acknowledgement.")
    self:NotifyChanged()
    return true
end

function RaidTargets:HandleStart(runID, label, caller, sender)
    -- This follows the tier-sync authority model: the originating client
    -- gates the action with Official:IsOfficer(), and peers accept the synced
    -- result. Recipients still require the sender to be in their live raid.
    if not IsRaidMember(sender) or self.participantRun then
        return
    end
    local run = {
        id = runID,
        label = label,
        caller = caller,
        officer = ShortName(sender),
        officerKey = PlayerKey(sender),
        startedAtLocal = Now(),
        startedEpoch = Stamp(),
        localChanges = {},
    }
    self.participantRun = run
    Addon.db.assistLog.activeParticipantRun = run
    CaptureLocalChange(run)
    DirectMessage(table.concat({
        KIND, "A", tostring(PROTOCOL), Encode(run.id), string.format("%.6f", run.startedAtLocal), Encode(Addon.version),
    }, "|"), "WHISPER", run.officer)
end

function RaidTargets:HandleStop(runID, duration, sender)
    local run = self.participantRun
    if not run or run.id ~= runID or PlayerKey(sender) ~= run.officerKey then
        return
    end
    CaptureLocalChange(run)
    run.duration = tonumber(duration) or 0
    run.stoppedAtLocal = Now()
    self.participantRun = nil
    Addon.db.assistLog.activeParticipantRun = nil
    self:QueueUpload(run)
end

function RaidTargets:HandleClockResponse(runID, pingID, officerSentAt, peerReceivedAt, peerSentAt, sender)
    local fight = FindFightByID(runID)
    if not fight or fight.officerKey ~= PlayerKey(UnitName("player")) then
        return
    end
    local receivedAt = Now()
    local t0 = tonumber(officerSentAt)
    local t1 = tonumber(peerReceivedAt)
    local t2 = tonumber(peerSentAt)
    if not t0 or not t1 or not t2 then
        return
    end
    local rtt = math.max(0, (receivedAt - t0) - (t2 - t1))
    local offset = ((t1 - t0) + (t2 - receivedAt)) / 2
    local key = PlayerKey(sender)
    fight.clock = fight.clock or {}
    local previous = fight.clock[key]
    if not previous or rtt < (previous.rtt or math.huge) then
        fight.clock[key] = { offset = offset, rtt = rtt, pingID = pingID }
    end
end

function RaidTargets:HandleDataChunk(runID, transferID, index, total, digest, chunk, sender)
    local fight = FindFightByID(runID)
    if not fight or not index or not total or total < 1 or total > MAX_TRANSFER_CHUNKS or index > total then
        return
    end
    if fight.expected and not fight.expected[PlayerKey(sender)] then
        return
    end
    local transferKey = PlayerKey(sender) .. ":" .. transferID
    local transfer = self.incomingTransfers[transferKey]
    if not transfer then
        transfer = { runID = runID, transferID = transferID, sender = sender, total = total,
            digest = digest, chunks = {}, received = 0, updatedAt = Now() }
        self.incomingTransfers[transferKey] = transfer
    end
    if transfer.total ~= total or transfer.digest ~= digest then
        self.incomingTransfers[transferKey] = nil
        return
    end
    if not transfer.chunks[index] then
        transfer.chunks[index] = chunk
        transfer.received = transfer.received + 1
    end
    transfer.updatedAt = Now()
    if transfer.received == transfer.total then
        local parts = {}
        for partIndex = 1, transfer.total do
            if not transfer.chunks[partIndex] then
                return
            end
            table.insert(parts, transfer.chunks[partIndex])
        end
        local payload = table.concat(parts)
        self.incomingTransfers[transferKey] = nil
        if Hash(payload) == digest then
            self:ApplyTransfer(fight, sender, transferID, payload)
        end
    end
end

function RaidTargets:HandleMessage(message, channel, sender)
    if not sender or PlayerKey(sender) == PlayerKey(UnitName("player")) then
        return
    end
    local action, protocolText, rest = string.match(message or "", "^" .. KIND .. "|([^|]+)|([^|]+)|(.*)$")
    if tonumber(protocolText) ~= PROTOCOL then
        return
    end

    if action == "S" and channel == "RAID" then
        local runID, label, caller = string.match(rest, "^([^|]+)|([^|]*)|([^|]*)|")
        self:HandleStart(Decode(runID), Decode(label), Decode(caller), sender)
    elseif action == "A" and channel == "WHISPER" then
        local runID, localStart, version = string.match(rest, "^([^|]+)|([^|]+)|([^|]*)$")
        local fight = FindFightByID(Decode(runID))
        if fight and fight.state == "recording" then
            local key = PlayerKey(sender)
            local player = fight.players[key] or { name = ShortName(sender) }
            player.status = "recording"
            player.version = Decode(version)
            fight.players[key] = player
            fight.clock = fight.clock or {}
            fight.clock[key] = fight.clock[key] or {
                offset = (tonumber(localStart) or 0) - Now(),
                -- Finite sentinel because SavedVariables must serialize it.
                rtt = 999999,
                fallback = true,
            }
            self:NotifyChanged()
        end
    elseif action == "P" and channel == "RAID" then
        local runID, pingID, officerSentAt = string.match(rest, "^([^|]+)|([^|]+)|([^|]+)$")
        runID = Decode(runID)
        if self.participantRun and self.participantRun.id == runID
            and PlayerKey(sender) == self.participantRun.officerKey then
            local receivedAt = Now()
            local sentAt = Now()
            DirectMessage(table.concat({ KIND, "R", tostring(PROTOCOL), Encode(runID), pingID,
                officerSentAt, string.format("%.6f", receivedAt), string.format("%.6f", sentAt) }, "|"),
                "WHISPER", self.participantRun.officer)
        end
    elseif action == "R" and channel == "WHISPER" then
        local runID, pingID, t0, t1, t2 = string.match(rest,
            "^([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)$")
        self:HandleClockResponse(Decode(runID), pingID, t0, t1, t2, sender)
    elseif action == "E" and channel == "RAID" then
        local runID, duration = string.match(rest, "^([^|]+)|([^|]+)$")
        self:HandleStop(Decode(runID), duration, sender)
    elseif action == "D" and channel == "WHISPER" then
        local runID, transferID, index, total, digest, chunk = string.match(rest,
            "^([^|]+)|([^|]+)|(%d+)|(%d+)|([^|]+)|(.*)$")
        self:HandleDataChunk(Decode(runID), Decode(transferID), tonumber(index), tonumber(total), digest, chunk, sender)
    elseif action == "C" and channel == "WHISPER" then
        local runID, transferID = string.match(rest, "^([^|]+)|([^|]+)$")
        runID, transferID = Decode(runID), Decode(transferID)
        local upload = Addon.db.assistLog.pendingUploads[runID]
        if upload and upload.transferID == transferID and PlayerKey(sender) == PlayerKey(upload.officer) then
            -- Officer has validated and processed the data. This is the only
            -- point at which the sending player's saved copy is auto-wiped.
            Addon.db.assistLog.pendingUploads[runID] = nil
            TransportLog("Officer acknowledged " .. runID .. "; removed local pending payload.")
            self:NotifyChanged()
        end
    end
end

function RaidTargets:OnEvent(event, ...)
    if event == "PLAYER_TARGET_CHANGED" then
        CaptureLocalChange(self.activeOfficerRun)
        CaptureLocalChange(self.participantRun)
        return
    end
    if event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        if prefix == Addon.MESSAGE_PREFIX then
            self:HandleMessage(message, channel, sender)
        end
    end
end

function RaidTargets:OnUpdate(elapsed)
    if self.activeOfficerRun and self.clockPingsSent < CLOCK_PING_COUNT and Now() >= self.nextClockPing then
        self:SendClockPing()
        self.nextClockPing = Now() + CLOCK_PING_INTERVAL
    end

    self.retryElapsed = (self.retryElapsed or 0) + elapsed
    if self.retryElapsed >= 2 then
        self.retryElapsed = 0
        for _, upload in pairs(Addon.db.assistLog.pendingUploads or {}) do
            local retryDelay = (upload.attempts or 0) <= 2
                and TRANSFER_RETRY_SECONDS or TRANSFER_SLOW_RETRY_SECONDS
            if Now() - (upload.lastSentAt or 0) >= retryDelay then
                self:SendUpload(upload)
            end
        end
        for key, transfer in pairs(self.incomingTransfers or {}) do
            if Now() - (transfer.updatedAt or 0) > 35 then
                self.incomingTransfers[key] = nil
            end
        end
    end
end
