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
local REMINDER_INTERVAL = 300
local CONTROL_REPLAY_INTERVAL = 5
local CONTROL_REPLAY_SECONDS = 300
local RUN_QUERY_INTERVAL = 15
local PENDING_QUERY_INTERVAL = 300
local MAX_ACTIVE_PARTICIPANT_RUNS = 8
local MAX_ACTIVE_RUN_AGE = 6 * 60 * 60
local TOMBSTONE_RETENTION = 180 * 24 * 60 * 60
local MAX_TOMBSTONES = 1000
local MAX_UPLOAD_ATTEMPTS = 20
local MAX_SAVED_FIGHTS = 200
local MAX_RUN_NOTES = 100
local UPDATE_INTERVAL = 0.10

local KIND = "AL"
local PROTOCOL = 2
local NO_TARGET = "(no target)"
-- Same checksummed/chunked envelope as Sync.lua. The Assist Tracker header also
-- carries a run ID, so its data chunk is slightly smaller to stay <240 bytes.
local TRANSFER_CHUNK_SIZE = 150
local TRANSFER_RETRY_SECONDS = 10
local TRANSFER_SLOW_RETRY_SECONDS = 300
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

local function Hash(value)
    local hash = 5381
    for index = 1, string.len(value or "") do
        hash = (hash * 33 + string.byte(value, index)) % 2147483647
    end
    return tostring(hash)
end

local function DirectMessage(message, channel, target, priority, tag)
    if Addon.Sync and Addon.Sync.initialized and Addon.Sync.QueueMessage then
        return Addon.Sync:QueueMessage(message, channel, target, priority or "ALERT", tag)
    end
    if not SendAddonMessage then
        return false
    end
    return pcall(SendAddonMessage, Addon.MESSAGE_PREFIX, message, channel, target)
end

local function QueuedMessage(message, channel, target, priority, tag)
    return DirectMessage(message, channel, target, priority or "NORMAL", tag)
end

local function TransportLog(message)
    -- Participant clients operate silently. Keep Assist Tracker out of the
    -- shared sync debug log unless this character is authorized to control it.
    if not Addon.RaidTargets or not Addon.RaidTargets.CanControl
        or not Addon.RaidTargets:CanControl() then
        return
    end
    if Addon.Sync and Addon.Sync.Log then
        Addon.Sync:Log("Assist Tracker: " .. tostring(message))
    end
end

local function CopyKeys(source)
    local copy = {}
    for key, value in pairs(source or {}) do
        if value then copy[key] = value end
    end
    return copy
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

local function FindRaidUnit(identity)
    local wanted = PlayerKey(identity)
    local count = GetNumRaidMembers and GetNumRaidMembers() or 0
    for index = 1, count do
        local unit = "raid" .. tostring(index)
        local name = UnitName and UnitName(unit)
        if not name and GetRaidRosterInfo then name = GetRaidRosterInfo(index) end
        if name and PlayerKey(name) == wanted then return unit end
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
    local records = { table.concat({
        string.format("%.3f", tonumber(run.startedAtLocal) or 0),
        string.format("%.6f", tonumber(run.clockOffsetEstimate) or 0),
    }, ",") }
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
    local startedText, offsetText = string.match(records[1] or "", "^([^,]+),?(.*)$")
    local startedAtLocal = tonumber(startedText)
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
    return {
        startedAtLocal = startedAtLocal,
        clockOffsetEstimate = tonumber(offsetText),
        localChanges = changes,
    }
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

local function SendStartControl(run, channel, target)
    return DirectMessage(table.concat({
        KIND, "S", tostring(PROTOCOL), Encode(run.id), Encode(run.label), Encode(run.caller),
        string.format("%.3f", tonumber(run.startedAt) or 0), string.format("%.6f", Now()),
    }, "|"), channel or "RAID", target)
end

local function SendStopControl(run, channel, target)
    return DirectMessage(table.concat({
        KIND, "E", tostring(PROTOCOL), Encode(run.id), string.format("%.3f", tonumber(run.duration) or 0),
    }, "|"), channel or "RAID", target)
end

local function SendCancelControl(runID, channel, target)
    return DirectMessage(table.concat({ KIND, "X", tostring(PROTOCOL), Encode(runID) }, "|"),
        channel or "RAID", target)
end

local function SendRunQuery(runID, officer)
    return DirectMessage(table.concat({ KIND, "V", tostring(PROTOCOL), Encode(runID) }, "|"),
        "WHISPER", officer)
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

function RaidTargets:PruneDeletedFights()
    local tombstones = Addon.db.assistLog.deletedFights or {}
    local ordered = {}
    local now = Stamp()
    for runID, tombstone in pairs(tombstones) do
        if type(tombstone) ~= "table"
            or now - (tonumber(tombstone.deletedEpoch) or 0) > TOMBSTONE_RETENTION then
            tombstones[runID] = nil
        else
            table.insert(ordered, { id = runID, timestamp = tonumber(tombstone.deletedEpoch) or 0 })
        end
    end
    table.sort(ordered, function(left, right) return left.timestamp > right.timestamp end)
    for index = MAX_TOMBSTONES + 1, #ordered do
        tombstones[ordered[index].id] = nil
    end
end

function RaidTargets:TombstoneFight(fight, silent)
    if not fight or not fight.id then return end
    Addon.db.assistLog.deletedFights = type(Addon.db.assistLog.deletedFights) == "table"
        and Addon.db.assistLog.deletedFights or {}
    Addon.db.assistLog.deletedFights[fight.id] = {
        deletedEpoch = Stamp(),
        officerKey = fight.officerKey,
        expected = CopyKeys(fight.expected),
    }
    self:PruneDeletedFights()
    if not silent then SendCancelControl(fight.id, "RAID") end
end

function RaidTargets:PruneSavedFights()
    local fights = Addon.db.assistLog.fights or {}
    while #fights > MAX_SAVED_FIGHTS do
        local oldestIndex = 1
        local oldestEpoch = tonumber(fights[1] and fights[1].startedEpoch) or 0
        for index = 2, #fights do
            local startedEpoch = tonumber(fights[index].startedEpoch) or 0
            if startedEpoch < oldestEpoch then
                oldestIndex, oldestEpoch = index, startedEpoch
            end
        end
        local removed = table.remove(fights, oldestIndex)
        if removed then
            self:TombstoneFight(removed, true)
            if self.receivingFights then self.receivingFights[removed.id] = nil end
        end
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
    Addon.db.assistLog.deletedFights = type(Addon.db.assistLog.deletedFights) == "table"
        and Addon.db.assistLog.deletedFights or {}
    self:PruneDeletedFights()
    self:PruneSavedFights()
    -- GetTime() can restart from a smaller value after a full client restart.
    -- Force every unacknowledged saved upload to retry in this login.
    for _, upload in pairs(Addon.db.assistLog.pendingUploads) do
        upload.lastSentAt = 0
        upload.nextQueryAt = Now() + 2
        if (tonumber(upload.attempts) or 0) >= MAX_UPLOAD_ATTEMPTS then
            upload.dormant = true
        end
    end

    self.activeOfficerRun = Addon.db.assistLog.activeOfficerRun
    Addon.db.assistLog.activeParticipantRuns = type(Addon.db.assistLog.activeParticipantRuns) == "table"
        and Addon.db.assistLog.activeParticipantRuns or {}
    local legacyParticipantRun = Addon.db.assistLog.activeParticipantRun
    if type(legacyParticipantRun) == "table" and legacyParticipantRun.id then
        Addon.db.assistLog.activeParticipantRuns[legacyParticipantRun.id] = legacyParticipantRun
    end
    Addon.db.assistLog.activeParticipantRun = nil
    self.participantRuns = Addon.db.assistLog.activeParticipantRuns
    if self.activeOfficerRun and Now() + 1 < (tonumber(self.activeOfficerRun.startedAt) or 0) then
        self.activeOfficerRun = nil
        Addon.db.assistLog.activeOfficerRun = nil
    end
    for runID, run in pairs(self.participantRuns) do
        if type(run) ~= "table" or not run.id
            or Now() + 1 < (tonumber(run.startedAtLocal) or 0)
            or Stamp() - (tonumber(run.startedEpoch) or Stamp()) > MAX_ACTIVE_RUN_AGE then
            self.participantRuns[runID] = nil
        else
            run.nextQueryAt = Now() + 1
        end
    end
    if self.activeOfficerRun then
        self.activeOfficerRun.nextStartBroadcastAt = Now() + 1
    end
    self.receivingFights = {}
    for _, fight in ipairs(Addon.db.assistLog.fights) do
        if fight.state == "receiving"
            and Stamp() <= (tonumber(fight.stopBroadcastUntilEpoch) or 0) then
            fight.nextStopBroadcastAt = Now() + 1
            self.receivingFights[fight.id] = fight
        end
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
        return nil, "Only an actually officer can choose the Assist Tracker shot caller."
    end
    local value = Addon.Util.Trim(specification)
    local lowered = string.lower(value)
    if lowered == "target" then
        value = UnitName and UnitName("target") or ""
    elseif lowered == "me" or lowered == "self" or lowered == "officer" or lowered == "clear" then
        value = UnitName and UnitName("player") or ""
    end
    if value == "" then
        return nil, "Usage: /actually assisttracker caller <raid player|target|me>"
    end
    local member = FindRaidMember(value)
    if not member then
        return nil, tostring(value) .. " is not in your current raid."
    end
    Addon.db.assistLog.selectedCaller = member
    if Addon.CallerArrow and Addon.CallerArrow.AssignTarget then
        Addon.CallerArrow:AssignTarget(member)
    end
    self:NotifyChanged()
    return member
end

function RaidTargets:HandleCommand(arguments)
    -- The feature is intentionally undiscoverable through commands for
    -- ordinary raid members. Their recording/upload work remains headless.
    if not self:CanControl() then
        return true
    end
    local command, rest = string.match(Addon.Util.Trim(arguments), "^(%S+)%s*(.*)$")
    command = string.lower(command or "")
    if command == "start" then
        local run, errorMessage = self:Start(rest ~= "" and rest or "Raid fight")
        Addon:Print(run and "Assist Tracker started. Use /actually assisttracker stop when the fight is over."
            or errorMessage)
        return true
    elseif command == "stop" then
        local fight, errorMessage = self:Stop()
        Addon:Print(fight and "Assist Tracker stopped. Waiting for raid uploads." or errorMessage)
        return true
    elseif command == "toggle" then
        if self:IsRunning() then
            local fight, errorMessage = self:Stop()
            Addon:Print(fight and "Assist Tracker stopped. Waiting for raid uploads." or errorMessage)
        else
            local run, errorMessage = self:Start(rest ~= "" and rest or "Raid fight")
            Addon:Print(run and "Assist Tracker started. Use this macro again to stop it." or errorMessage)
        end
        return true
    elseif command == "pending" then
        local option = string.lower(Addon.Util.Trim(rest))
        if option == "clear" then
            if Addon.Sync and Addon.Sync.CancelQueuedTagPrefix then Addon.Sync:CancelQueuedTagPrefix("AL:") end
            Addon.db.assistLog.pendingUploads = {}
            Addon:Print("Cleared all local Assist Tracker pending uploads.")
        elseif option == "retry" then
            local retried = 0
            for _, upload in pairs(Addon.db.assistLog.pendingUploads or {}) do
                if not upload.retryDisabled then
                    upload.dormant = nil
                    upload.attempts = 0
                    upload.lastSentAt = 0
                    upload.nextQueryAt = 0
                    self:SendUpload(upload)
                    retried = retried + 1
                end
            end
            Addon:Print("Retried " .. tostring(retried) .. " pending Assist Tracker upload(s).")
        else
            local total, dormant, failed = 0, 0, 0
            for _, upload in pairs(Addon.db.assistLog.pendingUploads or {}) do
                total = total + 1
                if upload.dormant then dormant = dormant + 1 end
                if upload.retryDisabled then failed = failed + 1 end
            end
            Addon:Print("Pending Assist Tracker uploads: " .. tostring(total)
                .. " (dormant: " .. tostring(dormant) .. ", too large: " .. tostring(failed) .. ").")
        end
        return true
    elseif command == "timer" then
        if Addon.AssistLogUI and Addon.AssistLogUI.ShowTimer then Addon.AssistLogUI:ShowTimer() end
        return true
    elseif command ~= "caller" then
        return false
    end
    if rest == "" then
        Addon:Print("Assist Tracker shot caller: " .. tostring(self:GetSelectedCaller())
            .. ". Set with /actually assisttracker caller <raid player|target|me>.")
        return true
    end
    local caller, errorMessage = self:SetSelectedCaller(rest)
    if caller then
        Addon:Print("Assist Tracker shot caller set to " .. caller .. ".")
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

function RaidTargets:TrackCallerDeath(run)
    if not run or not run.caller then return end
    local unit = FindRaidUnit(run.caller)
    if not unit or not UnitIsDeadOrGhost then return end
    local dead = UnitIsDeadOrGhost(unit) and true or false
    if run.callerWasDead == nil then
        run.callerWasDead = dead
        return
    end
    if dead and not run.callerWasDead then
        run.notes = type(run.notes) == "table" and run.notes or {}
        local callerName = ShortName(run.caller)
        table.insert(run.notes, {
            at = math.max(0, Now() - (tonumber(run.startedAt) or Now())),
            epoch = Stamp(),
            kind = "caller_death",
            player = callerName,
            text = callerName .. " died while serving as shot caller.",
        })
        while #run.notes > MAX_RUN_NOTES do table.remove(run.notes, 1) end
        self:NotifyChanged()
    end
    run.callerWasDead = dead
end

function RaidTargets:Start(label)
    if self.activeOfficerRun then
        return nil, "An Assist Tracker session is already running."
    end
    if not GetNumRaidMembers or GetNumRaidMembers() == 0 then
        return nil, "Assist Tracker can only start while you are in a raid."
    end
    local ownName = UnitName and UnitName("player")
    if not self:CanControl() then
        return nil, "Only an actually officer can start Assist Tracker."
    end
    local callerName = FindRaidMember(self:GetSelectedCaller())
    if not callerName then
        return nil, "The selected shot caller is not in this raid. Set one with /actually assisttracker caller <player|target|me>."
    end

    label = string.sub(Addon.Util.Trim(label), 1, 60)
    local run = {
        id = tostring(Stamp()) .. "." .. tostring(math.random(100000, 999999)),
        schema = 2,
        label = label,
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
        notes = {},
        state = "recording",
        nextReminderAt = Now() + REMINDER_INTERVAL,
        nextStartBroadcastAt = Now() + CONTROL_REPLAY_INTERVAL,
    }
    local callerUnit = FindRaidUnit(callerName)
    run.callerWasDead = callerUnit and UnitIsDeadOrGhost
        and (UnitIsDeadOrGhost(callerUnit) and true or false) or false
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

    SendStartControl(run, "RAID")
    TransportLog("Started " .. run.id .. " for " .. tostring(count) .. " raid members.")
    self:NotifyChanged()
    return run
end

function RaidTargets:Stop()
    local run = self.activeOfficerRun
    if not run then
        return nil, "No Assist Tracker session is running."
    end
    CaptureLocalChange(run)
    run.stoppedAt = Now()
    run.stoppedEpoch = Stamp()
    run.duration = math.max(0, run.stoppedAt - run.startedAt)
    run.state = "receiving"
    run.stopBroadcastUntilEpoch = Stamp() + CONTROL_REPLAY_SECONDS
    run.nextStopBroadcastAt = Now() + CONTROL_REPLAY_INTERVAL

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
    self.receivingFights[run.id] = run
    self:PruneSavedFights()
    Addon.db.assistLog.lastFightID = run.id

    SendStopControl(run, "RAID")
    TransportLog("Stopped " .. run.id .. "; waiting for post-fight uploads.")
    self:NotifyChanged()
    return run
end

function RaidTargets:DeleteFight(runID)
    local fights = self:GetFights()
    for index = #fights, 1, -1 do
        if fights[index].id == runID then
            self:TombstoneFight(fights[index])
            table.remove(fights, index)
            if self.receivingFights then self.receivingFights[runID] = nil end
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
        return nil, "Stop the active Assist Tracker session before clearing history."
    end
    for _, fight in ipairs(Addon.db.assistLog.fights or {}) do
        self:TombstoneFight(fight)
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
        tag = "AL:" .. transferID,
        nextQueryAt = Now() + PENDING_QUERY_INTERVAL,
    }
    if #upload.chunks > MAX_TRANSFER_CHUNKS then
        upload.retryDisabled = true
        upload.failedReason = "Timeline exceeds the transfer limit."
        if self:CanControl() then
            Addon:Print("An Assist Tracker timeline was too large to upload and remains saved locally."
                .. " Use /actually assisttracker pending to inspect pending data.")
        end
    end
    Addon.db.assistLog.pendingUploads[run.id] = upload
    self:SendUpload(upload)
    return upload
end

function RaidTargets:SendUpload(upload)
    if not upload or not upload.officer or upload.officer == "" then
        return
    end
    if upload.retryDisabled or upload.dormant then return end
    upload.tag = upload.tag or (upload.transferID and ("AL:" .. upload.transferID))
    if (tonumber(upload.attempts) or 0) >= MAX_UPLOAD_ATTEMPTS then
        upload.dormant = true
        TransportLog("Paused an unacknowledged upload after " .. tostring(MAX_UPLOAD_ATTEMPTS) .. " attempts.")
        return
    end
    upload.chunks = type(upload.chunks) == "table" and upload.chunks or SplitChunks(upload.payload or "")
    local total = #upload.chunks
    if total > MAX_TRANSFER_CHUNKS then
        upload.retryDisabled = true
        upload.failedReason = "Timeline exceeds the transfer limit."
        return
    end
    if Addon.Sync and Addon.Sync.CanQueueMessages and not Addon.Sync:CanQueueMessages(total, "BULK") then
        upload.lastSentAt = Now()
        return
    end
    for index, chunk in ipairs(upload.chunks) do
        QueuedMessage(table.concat({
            KIND, "D", tostring(PROTOCOL), Encode(upload.runID), Encode(upload.transferID),
            tostring(index), tostring(total), upload.digest, chunk,
        }, "|"), "WHISPER", upload.officer, "BULK", upload.tag)
    end
    upload.lastSentAt = Now()
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
        }, "|"), "WHISPER", sender, "ALERT")
        return true
    end
    local existingPlayer = fight.players and fight.players[key]
    if existingPlayer and existingPlayer.status == "received" and existingPlayer.changes then
        -- A retransmission may use a new transfer ID after saved-data recovery.
        -- Once accepted, never let a later payload silently rewrite history.
        QueuedMessage(table.concat({
            KIND, "C", tostring(PROTOCOL), Encode(fight.id), Encode(transferID),
        }, "|"), "WHISPER", sender, "ALERT")
        return true
    end
    local clock = fight.clock and fight.clock[key]
    local offset = clock and tonumber(clock.offset)
    if not offset then
        -- Fallback only. The normal path uses the lowest-RTT NTP-style ping,
        -- followed by the START acknowledgement estimate. The participant's
        -- estimate still places late-discovery data at the correct fight time.
        offset = decoded.clockOffsetEstimate or (decoded.startedAtLocal - fight.startedAt)
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
    }, "|"), "WHISPER", sender, "ALERT")
    TransportLog("Processed target timeline from " .. ShortName(sender) .. " and queued acknowledgement.")
    self:NotifyChanged()
    return true
end

function RaidTargets:HandleStart(runID, label, caller, controllerSentAt, sender)
    -- This follows the tier-sync authority model: the originating client
    -- gates the action with Official:IsOfficer(), and peers accept the synced
    -- result. Recipients still require the sender to be in their live raid.
    if not IsRaidMember(sender) or not runID or runID == "" then
        return
    end
    self.participantRuns = self.participantRuns or {}
    local existing = self.participantRuns[runID]
    if existing then
        if PlayerKey(sender) == existing.officerKey then
            DirectMessage(table.concat({
                KIND, "A", tostring(PROTOCOL), Encode(existing.id),
                string.format("%.6f", existing.startedAtLocal), Encode(Addon.version),
            }, "|"), "WHISPER", existing.officer)
        end
        return
    end
    local senderKey = PlayerKey(sender)
    local activeCount = 0
    for existingID, activeRun in pairs(self.participantRuns) do
        activeCount = activeCount + 1
        if activeRun.officerKey == senderKey then
            -- One controller can only own one live watch. A newer START from
            -- that controller supersedes a stale watch whose STOP was missed.
            self.participantRuns[existingID] = nil
            activeCount = activeCount - 1
        end
    end
    if activeCount >= MAX_ACTIVE_PARTICIPANT_RUNS then
        TransportLog("Ignored START because the participant watch cap was reached.")
        return
    end
    local run = {
        id = runID,
        label = label,
        caller = caller,
        officer = ShortName(sender),
        officerKey = PlayerKey(sender),
        startedAtLocal = Now(),
        clockOffsetEstimate = Now() - (tonumber(controllerSentAt) or Now()),
        startedEpoch = Stamp(),
        localChanges = {},
        nextQueryAt = Now() + RUN_QUERY_INTERVAL,
    }
    self.participantRuns[runID] = run
    Addon.db.assistLog.activeParticipantRuns = self.participantRuns
    CaptureLocalChange(run)
    DirectMessage(table.concat({
        KIND, "A", tostring(PROTOCOL), Encode(run.id), string.format("%.6f", run.startedAtLocal), Encode(Addon.version),
    }, "|"), "WHISPER", run.officer)
end

function RaidTargets:HandleStop(runID, duration, sender)
    local run = self.participantRuns and self.participantRuns[runID]
    if not run then
        local upload = Addon.db.assistLog.pendingUploads[runID]
        if upload and PlayerKey(sender) == PlayerKey(upload.officer) and upload.dormant then
            upload.dormant = nil
            upload.attempts = 0
            upload.lastSentAt = 0
            self:SendUpload(upload)
        end
        return
    end
    if run.id ~= runID or PlayerKey(sender) ~= run.officerKey then
        return
    end
    CaptureLocalChange(run)
    run.duration = tonumber(duration) or 0
    run.stoppedAtLocal = Now()
    self.participantRuns[runID] = nil
    Addon.db.assistLog.activeParticipantRuns = self.participantRuns
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
    if not index or not total or total < 1 or total > MAX_TRANSFER_CHUNKS or index > total then
        return
    end
    local tombstone = Addon.db.assistLog.deletedFights and Addon.db.assistLog.deletedFights[runID]
    if tombstone then
        if tombstone.expected and tombstone.expected[PlayerKey(sender)] then
            QueuedMessage(table.concat({
                KIND, "C", tostring(PROTOCOL), Encode(runID), Encode(transferID),
            }, "|"), "WHISPER", sender, "ALERT")
        end
        return
    end
    local fight = FindFightByID(runID)
    if not fight then return end
    local senderKey = PlayerKey(sender)
    if fight.expected and not fight.expected[senderKey] then
        if fight.state == "receiving" and IsRaidMember(sender) then
            fight.expected[senderKey] = ShortName(sender)
            fight.players = fight.players or {}
            fight.players[senderKey] = fight.players[senderKey] or {
                name = ShortName(sender), status = "awaiting upload",
            }
        else
            return
        end
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

    if action == "S" and (channel == "RAID" or channel == "WHISPER") then
        local runID, label, caller, _, controllerSentAt = string.match(rest,
            "^([^|]+)|([^|]*)|([^|]*)|([^|]+)|([^|]+)$")
        self:HandleStart(Decode(runID), Decode(label), Decode(caller), controllerSentAt, sender)
    elseif action == "A" and channel == "WHISPER" then
        local runID, localStart, version = string.match(rest, "^([^|]+)|([^|]+)|([^|]*)$")
        local fight = FindFightByID(Decode(runID))
        if fight and fight.state == "recording" and IsRaidMember(sender) then
            local key = PlayerKey(sender)
            fight.expected = fight.expected or {}
            fight.expected[key] = ShortName(sender)
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
        local participantRun = self.participantRuns and self.participantRuns[runID]
        if participantRun and PlayerKey(sender) == participantRun.officerKey then
            local receivedAt = Now()
            local sentAt = Now()
            DirectMessage(table.concat({ KIND, "R", tostring(PROTOCOL), Encode(runID), pingID,
                officerSentAt, string.format("%.6f", receivedAt), string.format("%.6f", sentAt) }, "|"),
                "WHISPER", participantRun.officer)
        end
    elseif action == "R" and channel == "WHISPER" then
        local runID, pingID, t0, t1, t2 = string.match(rest,
            "^([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)$")
        self:HandleClockResponse(Decode(runID), pingID, t0, t1, t2, sender)
    elseif action == "E" and channel == "RAID" then
        local runID, duration = string.match(rest, "^([^|]+)|([^|]+)$")
        self:HandleStop(Decode(runID), duration, sender)
    elseif action == "E" and channel == "WHISPER" then
        local runID, duration = string.match(rest, "^([^|]+)|([^|]+)$")
        self:HandleStop(Decode(runID), duration, sender)
    elseif action == "V" and channel == "WHISPER" then
        local runID = Decode(rest)
        local fight = FindFightByID(runID)
        local senderKey = PlayerKey(sender)
        if fight and fight.officerKey == PlayerKey(UnitName("player"))
            and ((fight.state == "recording" and IsRaidMember(sender))
                or (fight.expected and fight.expected[senderKey])
                or (fight.state == "receiving" and IsRaidMember(sender))) then
            if fight.state == "recording" then
                SendStartControl(fight, "WHISPER", sender)
            else
                fight.expected = fight.expected or {}
                fight.expected[senderKey] = ShortName(sender)
                SendStopControl(fight, "WHISPER", sender)
            end
        else
            SendCancelControl(runID, "WHISPER", sender)
        end
    elseif action == "X" and (channel == "RAID" or channel == "WHISPER") then
        local runID = Decode(rest)
        local active = self.participantRuns and self.participantRuns[runID]
        local pending = Addon.db.assistLog.pendingUploads[runID]
        local senderKey = PlayerKey(sender)
        if active and senderKey == active.officerKey then
            self.participantRuns[runID] = nil
        end
        if pending and senderKey == PlayerKey(pending.officer) then
            if pending.tag and Addon.Sync and Addon.Sync.CancelQueuedTag then
                Addon.Sync:CancelQueuedTag(pending.tag)
            end
            Addon.db.assistLog.pendingUploads[runID] = nil
        end
        self:NotifyChanged()
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
            if upload.tag and Addon.Sync and Addon.Sync.CancelQueuedTag then
                Addon.Sync:CancelQueuedTag(upload.tag)
            elseif upload.tag and Addon.Sync and Addon.Sync.ForgetTag then
                Addon.Sync:ForgetTag(upload.tag)
            end
            Addon.db.assistLog.pendingUploads[runID] = nil
            TransportLog("Officer acknowledged " .. runID .. "; removed local pending payload.")
            self:NotifyChanged()
        end
    end
end

function RaidTargets:OnEvent(event, ...)
    if event == "PLAYER_TARGET_CHANGED" then
        CaptureLocalChange(self.activeOfficerRun)
        for _, run in pairs(self.participantRuns or {}) do
            CaptureLocalChange(run)
        end
        return
    end
    if event == "RAID_ROSTER_UPDATE" then
        if self.activeOfficerRun then self.activeOfficerRun.nextStartBroadcastAt = 0 end
        for _, run in pairs(self.participantRuns or {}) do run.nextQueryAt = 0 end
        return
    end
    if event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        if prefix == Addon.MESSAGE_PREFIX and message and string.sub(message, 1, 3) == KIND .. "|" then
            self:HandleMessage(message, channel, sender)
        end
    end
end

function RaidTargets:OnUpdate(elapsed)
    self.updateElapsed = (self.updateElapsed or 0) + elapsed
    if self.updateElapsed < UPDATE_INTERVAL then return end
    elapsed = self.updateElapsed
    self.updateElapsed = 0
    local now = Now()
    local epoch = Stamp()
    if self.activeOfficerRun and now >= (tonumber(self.activeOfficerRun.nextStartBroadcastAt) or 0) then
        SendStartControl(self.activeOfficerRun, "RAID")
        self.activeOfficerRun.nextStartBroadcastAt = now + CONTROL_REPLAY_INTERVAL
    end
    self:TrackCallerDeath(self.activeOfficerRun)
    if self.activeOfficerRun and self.clockPingsSent < CLOCK_PING_COUNT and Now() >= self.nextClockPing then
        self:SendClockPing()
        self.nextClockPing = Now() + CLOCK_PING_INTERVAL
    end

    local function RemindController(run)
        if not run then return end
        local startedAt = tonumber(run.startedAt or run.startedAtLocal) or Now()
        run.nextReminderAt = tonumber(run.nextReminderAt) or (startedAt + REMINDER_INTERVAL)
        if Now() >= run.nextReminderAt then
            local minutes = math.max(5, math.floor((Now() - startedAt) / 60))
            Addon:Print("Assist Tracker is still recording (" .. tostring(minutes)
                .. " minutes). Stop it with /actually assisttracker stop when the fight is over.")
            run.nextReminderAt = Now() + REMINDER_INTERVAL
        end
    end
    RemindController(self.activeOfficerRun)

    for runID, fight in pairs(self.receivingFights or {}) do
        if epoch > (tonumber(fight.stopBroadcastUntilEpoch) or 0) then
            self.receivingFights[runID] = nil
        elseif now >= (tonumber(fight.nextStopBroadcastAt) or 0) then
            SendStopControl(fight, "RAID")
            fight.nextStopBroadcastAt = now + CONTROL_REPLAY_INTERVAL
        end
    end

    for runID, run in pairs(self.participantRuns or {}) do
        if epoch - (tonumber(run.startedEpoch) or epoch) > MAX_ACTIVE_RUN_AGE then
            self.participantRuns[runID] = nil
            TransportLog("Expired stale participant watch " .. tostring(runID) .. ".")
        elseif now >= (tonumber(run.nextQueryAt) or 0) then
            SendRunQuery(runID, run.officer)
            run.nextQueryAt = now + RUN_QUERY_INTERVAL
        end
    end

    for runID, upload in pairs(Addon.db.assistLog.pendingUploads or {}) do
        if now >= (tonumber(upload.nextQueryAt) or 0) then
            SendRunQuery(runID, upload.officer)
            upload.nextQueryAt = now + PENDING_QUERY_INTERVAL
        end
    end

    self.cleanupElapsed = (self.cleanupElapsed or 0) + elapsed
    if self.cleanupElapsed >= 60 then
        self.cleanupElapsed = 0
        self:PruneDeletedFights()
    end

    self.retryElapsed = (self.retryElapsed or 0) + elapsed
    if self.retryElapsed >= 2 then
        self.retryElapsed = 0
        for _, upload in pairs(Addon.db.assistLog.pendingUploads or {}) do
            local retryDelay = (upload.attempts or 0) <= 2 and TRANSFER_RETRY_SECONDS
                or TRANSFER_SLOW_RETRY_SECONDS
            upload.tag = upload.tag or (upload.transferID and ("AL:" .. upload.transferID))
            local queued = upload.tag and Addon.Sync and Addon.Sync.HasQueuedTag
                and Addon.Sync:HasQueuedTag(upload.tag)
            local finishedAt = upload.tag and Addon.Sync and Addon.Sync.GetTagFinishedAt
                and Addon.Sync:GetTagFinishedAt(upload.tag)
            if not upload.retryDisabled and not upload.dormant
                and not queued and Now() - (finishedAt or upload.lastSentAt or 0) >= retryDelay then
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
