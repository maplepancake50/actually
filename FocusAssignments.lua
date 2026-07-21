Actually = Actually or {}
local Addon = Actually

local FocusAssignments = {}
Addon.FocusAssignments = FocusAssignments

local KIND = "FA"
local PROTOCOL = 3
local ACK_RETRY_SECONDS = 3
local MAX_SEND_ATTEMPTS = 3
local AUTO_BROADCAST_DELAY = 1

local function ClearTable(value)
    for key in pairs(value or {}) do value[key] = nil end
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

local function IsSafeIdentifier(value, maximumLength)
    value = Addon.Util.Trim(value or "")
    if value == "" or string.len(value) > maximumLength then return false end
    for index = 1, string.len(value) do
        local byte = string.byte(value, index)
        local asciiLetter = (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)
        local extendedLetter = byte >= 128
        local punctuation = byte == 39 or byte == 45
        local digit = byte >= 48 and byte <= 57
        if not asciiLetter and not extendedLetter and not punctuation and not digit then
            return false
        end
    end
    return true
end

local function ValidateTargetName(value)
    value = Addon.Util.Trim(value or "")
    if value == "" then return nil, "Target name is empty." end
    if not IsSafeIdentifier(value, 48) then
        return nil, "Target names may only contain name characters, apostrophes, hyphens, and digits."
    end
    return value
end

local function QueueMessage(message, channel, target, priority, tag)
    if Addon.Sync and Addon.Sync.initialized and Addon.Sync.QueueMessage then
        return Addon.Sync:QueueMessage(message, channel, target, priority or "ALERT", tag)
    end
    if SendAddonMessage then
        return pcall(SendAddonMessage, Addon.MESSAGE_PREFIX, message, channel, target)
    end
    return false
end

function FocusAssignments:InitializeStorage()
    Addon.db.focusAssignments = type(Addon.db.focusAssignments) == "table"
        and Addon.db.focusAssignments or {}
    local db = Addon.db.focusAssignments
    db.targetsText = tostring(db.targetsText or "")
    db.assignedTarget = tostring(db.assignedTarget or "")
    db.assignedBy = tostring(db.assignedBy or "")
    db.assignmentRevision = tostring(db.assignmentRevision or "")
    db.dps = type(db.dps) == "table" and db.dps or {}
    db.preferred = type(db.preferred) == "table" and db.preferred or {}
    self.db = db
end

function FocusAssignments:GetPlayerName()
    return ShortName(UnitName and UnitName("player"))
end

function FocusAssignments:GetMyAssignment()
    return self.myAssignment or (self.db and self.db.assignedTarget ~= "" and self.db.assignedTarget) or nil
end

function FocusAssignments:GetAssignmentForPlayer(identity)
    local key = PlayerKey(identity)
    if key == PlayerKey(self:GetPlayerName()) then return self:GetMyAssignment() end
    return self.assignmentByPlayer and self.assignmentByPlayer[key] or nil
end

function FocusAssignments:ScanRoster()
    self.roster = self.roster or {}
    ClearTable(self.roster)
    local raidCount = GetNumRaidMembers and GetNumRaidMembers() or 0
    if raidCount > 0 then
        for index = 1, raidCount do
            local name, rank, subgroup, level, class, classFile, zone, online, dead = GetRaidRosterInfo(index)
            if name then
                local shortName = ShortName(name)
                local key = PlayerKey(shortName)
                self.roster[key] = {
                    key = key, name = shortName, fullName = name, rank = rank or 0,
                    subgroup = subgroup, level = level, class = class, classFile = classFile,
                    online = online and true or false, dead = dead, unit = "raid" .. index,
                }
            end
        end
    else
        local partyLeaderIndex = GetPartyLeaderIndex and GetPartyLeaderIndex()
        local function AddUnit(unit, rank)
            if not UnitExists or not UnitExists(unit) then return end
            local name = UnitName(unit)
            if not name then return end
            local shortName = ShortName(name)
            local key = PlayerKey(shortName)
            local _, classFile = UnitClass(unit)
            self.roster[key] = {
                key = key, name = shortName, fullName = name, rank = rank or 0,
                classFile = classFile,
                online = not UnitIsConnected or UnitIsConnected(unit) and true or false,
                dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit), unit = unit,
            }
        end
        local playerRank = ((partyLeaderIndex == 0)
            or (UnitIsPartyLeader and UnitIsPartyLeader("player"))) and 2 or 0
        AddUnit("player", playerRank)
        local partyCount = GetNumPartyMembers and GetNumPartyMembers() or 0
        for index = 1, partyCount do
            local unit = "party" .. index
            local rank = ((partyLeaderIndex == index)
                or (UnitIsPartyLeader and UnitIsPartyLeader(unit))) and 2 or 0
            AddUnit(unit, rank)
        end
    end
    return self.roster
end

function FocusAssignments:GetSortedRoster()
    local rows = {}
    for key, member in pairs(self.roster or {}) do
        member.key = key
        member.isDPS = self.db.dps[key] and true or false
        table.insert(rows, member)
    end
    table.sort(rows, function(left, right)
        if left.isDPS ~= right.isDPS then return left.isDPS end
        return string.lower(left.name) < string.lower(right.name)
    end)
    return rows
end

function FocusAssignments:SetDPS(name, enabled)
    local key = PlayerKey(name)
    if key == "" then return end
    self.db.dps[key] = enabled and true or nil
    self:BuildAssignments()
    if self.liveEnabled then self:ScheduleBroadcast() end
end

function FocusAssignments:ParseTargets(text)
    local targets, seen, invalid = {}, {}, {}
    text = string.gsub(text or "", ",", "\n")
    for rawName in string.gmatch(text .. "\n", "([^\r\n]*)[\r\n]") do
        local trimmed = Addon.Util.Trim(rawName)
        if trimmed ~= "" then
            local name, errorMessage = ValidateTargetName(trimmed)
            if name then
                local key = PlayerKey(name)
                if not seen[key] then
                    seen[key] = true
                    table.insert(targets, { key = key, name = name })
                end
            else
                table.insert(invalid, trimmed .. ": " .. errorMessage)
            end
        end
    end
    return targets, invalid
end

function FocusAssignments:CanPublish()
    local raidCount = GetNumRaidMembers and GetNumRaidMembers() or 0
    if raidCount > 0 then
        return (IsRaidLeader and IsRaidLeader()) or (IsRaidOfficer and IsRaidOfficer())
    end
    local partyCount = GetNumPartyMembers and GetNumPartyMembers() or 0
    if partyCount > 0 then return IsPartyLeader and IsPartyLeader() end
    return true
end

function FocusAssignments:BuildAssignments()
    self:ScanRoster()
    ClearTable(self.assignments)
    ClearTable(self.assignmentByPlayer)
    local targets, invalid = self:ParseTargets(self.db.targetsText)
    self.invalidTargets = invalid
    local eligible, eligibleByKey, usedPlayers = {}, {}, {}
    for _, member in ipairs(self:GetSortedRoster()) do
        if member.isDPS and member.online then
            table.insert(eligible, member)
            eligibleByKey[member.key] = member
        end
    end
    for _, target in ipairs(targets) do
        local preferredKey = self.db.preferred[target.key]
        local member = preferredKey and eligibleByKey[preferredKey]
        if member and not usedPlayers[member.key] then
            self.assignments[target.key] = {
                target = target.name, player = member.name, playerKey = member.key, preferred = true,
            }
            self.assignmentByPlayer[member.key] = target.name
            usedPlayers[member.key] = true
        end
    end
    local nextEligible = 1
    for _, target in ipairs(targets) do
        if not self.assignments[target.key] then
            while eligible[nextEligible] and usedPlayers[eligible[nextEligible].key] do
                nextEligible = nextEligible + 1
            end
            local member = eligible[nextEligible]
            if member then
                local hadPreference = self.db.preferred[target.key] ~= nil
                self.assignments[target.key] = {
                    target = target.name, player = member.name, playerKey = member.key,
                    preferred = not hadPreference,
                }
                self.assignmentByPlayer[member.key] = target.name
                usedPlayers[member.key] = true
                if not hadPreference then self.db.preferred[target.key] = member.key end
                nextEligible = nextEligible + 1
            else
                self.assignments[target.key] = { target = target.name, preferred = false }
            end
        end
    end
    self:NotifyChanged()
    return self.assignments
end

function FocusAssignments:ResetPreferredAssignments()
    ClearTable(self.db.preferred)
    self:BuildAssignments()
    if self.liveEnabled then self:ScheduleBroadcast() end
end

function FocusAssignments:RaidRank(identity)
    local wanted = PlayerKey(identity)
    local raidCount = GetNumRaidMembers and GetNumRaidMembers() or 0
    if raidCount > 0 then
        for index = 1, raidCount do
            local name, rank = GetRaidRosterInfo(index)
            if name and PlayerKey(name) == wanted then return rank or 0 end
        end
        return -1
    end
    self:ScanRoster()
    return self.roster[wanted] and self.roster[wanted].rank or -1
end

function FocusAssignments:IsTrustedSender(sender)
    return sender and self:RaidRank(sender) > 0
end

function FocusAssignments:NewRevision()
    local epoch = time and time() or 0
    return string.format("%010d.%06d.%s", epoch, math.random(0, 999999), PlayerKey(self:GetPlayerName()))
end

function FocusAssignments:BuildAssignmentMessage(revision, target)
    local body = table.concat({ revision, target or "" }, "|")
    return table.concat({ KIND, "S", tostring(PROTOCOL), Encode(revision),
        Encode(target or ""), Hash(body) }, "|")
end

function FocusAssignments:SendAssignment(member, target, revision)
    local message = self:BuildAssignmentMessage(revision, target)
    local key = member.key
    local tag = "FA:" .. revision .. ":" .. key
    QueueMessage(message, "WHISPER", member.fullName or member.name, "ALERT", tag)
    self.pendingAcks[key] = {
        player = member.fullName or member.name, target = target, message = message,
        revision = revision, digest = string.match(message, "([^|]+)$"),
        sentAt = GetTime and GetTime() or 0, attempts = 1, tag = tag,
    }
end

function FocusAssignments:ApplyAssignment(target, sender, revision)
    self.myAssignment = target ~= "" and target or nil
    self.db.assignedTarget = target or ""
    self.db.assignedBy = ShortName(sender)
    self.db.assignmentRevision = revision
    return "OK"
end

function FocusAssignments:SendAck(sender, revision, digest, status)
    if not sender or sender == "" then return end
    QueueMessage(table.concat({ KIND, "K", tostring(PROTOCOL), Encode(revision), digest, status }, "|"),
        "WHISPER", sender, "ALERT", "FAACK:" .. revision)
end

function FocusAssignments:BroadcastAssignments()
    if not self:CanPublish() then
        self:SetStatus("Only the raid leader or an assistant can broadcast assignments.", 1, 0.3, 0.3)
        return false
    end
    self:BuildAssignments()
    if #self.invalidTargets > 0 then
        self:SetStatus("Invalid target: " .. tostring(self.invalidTargets[1]), 1, 0.3, 0.3)
        return false
    end
    local raidCount = GetNumRaidMembers and GetNumRaidMembers() or 0
    local partyCount = GetNumPartyMembers and GetNumPartyMembers() or 0
    if raidCount == 0 and partyCount == 0 then
        self:SetStatus("Join a party or raid before broadcasting.", 1, 0.75, 0.25)
        return false
    end
    self.scheduledBroadcastAt = nil
    local revision = self:NewRevision()
    for _, member in ipairs(self:GetSortedRoster()) do
        local target = self.assignmentByPlayer[member.key] or ""
        if member.online and string.len(self:BuildAssignmentMessage(revision, target)) > 240 then
            self:SetStatus("Target name is too long to send safely.", 1, 0.3, 0.3)
            return false
        end
    end
    self.liveEnabled = true
    self.currentRevision = revision
    if Addon.Sync and Addon.Sync.CancelQueuedTagPrefix then
        Addon.Sync:CancelQueuedTagPrefix("FA:")
    end
    ClearTable(self.pendingAcks)
    ClearTable(self.acknowledgements)
    local ownKey = PlayerKey(self:GetPlayerName())
    local sent = 0
    for _, member in ipairs(self:GetSortedRoster()) do
        if member.online then
            local target = self.assignmentByPlayer[member.key] or ""
            if member.key == ownKey then
                local status = self:ApplyAssignment(target, self:GetPlayerName(), self.currentRevision)
                self.acknowledgements[member.key] = status
            else
                self:SendAssignment(member, target, self.currentRevision)
            end
            sent = sent + 1
        end
    end
    self:SetStatus("Sent assignments to " .. tostring(sent) .. " online raid member" .. (sent == 1 and "." or "s."), 0.3, 1, 0.3)
    self:NotifyChanged()
    return true
end

function FocusAssignments:ScheduleBroadcast(delay)
    if self.liveEnabled and self:CanPublish() then
        self.scheduledBroadcastAt = (GetTime and GetTime() or 0) + (delay or AUTO_BROADCAST_DELAY)
    end
end

function FocusAssignments:HandleMessage(message, channel, sender)
    if not message or string.sub(message, 1, 3) ~= KIND .. "|" then return end
    if not sender or PlayerKey(sender) == PlayerKey(self:GetPlayerName()) then return end
    local command, protocolText, rest = string.match(message, "^" .. KIND .. "|([^|]+)|([^|]+)|(.*)$")
    if tonumber(protocolText) ~= PROTOCOL then return end
    if command == "S" and channel == "WHISPER" then
        if not self:IsTrustedSender(sender) then return end
        local revision, target, digest = string.match(rest, "^([^|]+)|([^|]*)|([^|]+)$")
        revision, target = Decode(revision), Decode(target)
        local validTarget = target == "" or ValidateTargetName(target)
        if not revision or revision == "" or not validTarget then return end
        if Hash(table.concat({ revision, target }, "|")) ~= digest then return end
        local previous = self.receivedRevisionBySender[PlayerKey(sender)]
        if previous and revision < previous then return end
        self.receivedRevisionBySender[PlayerKey(sender)] = revision
        local status = self:ApplyAssignment(target, sender, revision)
        self:SendAck(sender, revision, digest, status)
    elseif command == "K" and channel == "WHISPER" and self:CanPublish() then
        local revision, digest, status = string.match(rest, "^([^|]+)|([^|]+)|([^|]+)$")
        revision = Decode(revision)
        local key = PlayerKey(sender)
        local pending = self.pendingAcks[key]
        if pending and pending.revision == revision and pending.digest == digest then
            self.pendingAcks[key] = nil
            self.acknowledgements[key] = status
            if Addon.Sync and Addon.Sync.CancelQueuedTag then Addon.Sync:CancelQueuedTag(pending.tag)
            elseif Addon.Sync and Addon.Sync.ForgetTag then Addon.Sync:ForgetTag(pending.tag) end
            self:NotifyChanged()
        elseif revision == self.currentRevision then
            self.acknowledgements[key] = status
            self:NotifyChanged()
        end
    end
end

function FocusAssignments:SetStatus(text, red, green, blue)
    self.statusText = text
    self.statusColor = { red or 0.8, green or 0.8, blue or 0.8 }
    self:NotifyChanged()
end

function FocusAssignments:NotifyChanged()
    if self.UI and self.UI.Refresh then self.UI:Refresh() end
end

function FocusAssignments:Show()
    if self.UI then self.UI:Show() end
end

function FocusAssignments:Toggle()
    if self.UI then self.UI:Toggle() end
end

function FocusAssignments:OnEvent(event, ...)
    if event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
        self:BuildAssignments()
        self:ScheduleBroadcast()
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        if prefix == Addon.MESSAGE_PREFIX then self:HandleMessage(message, channel, sender) end
    end
end

function FocusAssignments:OnUpdate(elapsed)
    self.updateElapsed = (self.updateElapsed or 0) + elapsed
    if self.updateElapsed < 0.25 then return end
    self.updateElapsed = 0
    local now = GetTime and GetTime() or 0
    if self.scheduledBroadcastAt and now >= self.scheduledBroadcastAt then
        self.scheduledBroadcastAt = nil
        self:BroadcastAssignments()
    end
    for key, pending in pairs(self.pendingAcks) do
        local queued = Addon.Sync and Addon.Sync.HasQueuedTag and Addon.Sync:HasQueuedTag(pending.tag)
        local finishedAt = Addon.Sync and Addon.Sync.GetTagFinishedAt and Addon.Sync:GetTagFinishedAt(pending.tag)
        local retryFrom = finishedAt or pending.sentAt or 0
        if not queued and now - retryFrom >= ACK_RETRY_SECONDS then
            if pending.attempts >= MAX_SEND_ATTEMPTS then
                self.pendingAcks[key] = nil
                self.acknowledgements[key] = "NO RESPONSE"
                if Addon.Sync and Addon.Sync.ForgetTag then Addon.Sync:ForgetTag(pending.tag) end
                self:NotifyChanged()
            else
                pending.attempts = pending.attempts + 1
                pending.sentAt = now
                QueueMessage(pending.message, "WHISPER", pending.player, "ALERT", pending.tag)
            end
        end
    end
end

function FocusAssignments:Initialize()
    if self.initialized then return end
    self.initialized = true
    self:InitializeStorage()
    self.roster, self.assignments, self.assignmentByPlayer = {}, {}, {}
    self.pendingAcks, self.acknowledgements, self.receivedRevisionBySender = {}, {}, {}
    self.myAssignment = self.db.assignedTarget ~= "" and self.db.assignedTarget or nil
    if self.db.assignedBy ~= "" and self.db.assignmentRevision ~= "" then
        self.receivedRevisionBySender[PlayerKey(self.db.assignedBy)] = self.db.assignmentRevision
    end
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("RAID_ROSTER_UPDATE")
    frame:RegisterEvent("PARTY_MEMBERS_CHANGED")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:SetScript("OnEvent", function(_, event, ...) FocusAssignments:OnEvent(event, ...) end)
    frame:SetScript("OnUpdate", function(_, elapsed) FocusAssignments:OnUpdate(elapsed) end)
    self.eventFrame = frame
    if self.UI and self.UI.Create then self.UI:Create() end
    self:BuildAssignments()
    SLASH_ACTUALLYFOCUS1 = "/focusassign"
    SLASH_ACTUALLYFOCUS2 = "/fa"
    SlashCmdList.ACTUALLYFOCUS = function() FocusAssignments:Toggle() end
end
