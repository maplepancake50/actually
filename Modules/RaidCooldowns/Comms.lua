local ARC = Actually.Modules.RaidCooldowns
local Comms = ARC:NewModule("Comms")

local function validInteger(value, minimum, maximum)
    return type(value) == "number" and value == math.floor(value)
        and value >= minimum and value <= maximum
end

local function validString(value, maximum)
    return type(value) == "string" and #value > 0 and #value <= maximum
end

function Comms:Initialize()
    self.session = tostring(time and time() or 0) .. ":" .. tostring(math.random(100000, 999999))
    self.sequence = 0
    self.lastRequest = -100
    self.lastState = -100
    self.stateDueAt = nil
    self.remoteRequests = {}
    self.protocolWarnings = {}
    ARC:RegisterComm(ARC.Constants.COMM_PREFIX, function(...)
        self:OnCommReceived(...)
    end)
    self.initialized = true
    self:SchedulePeriodicReport()
end

function Comms:NextSequence()
    self.sequence = self.sequence + 1
    return self.sequence
end

function Comms:Send(messageType, priority, ...)
    local distribution = ARC.Roster:GetDistribution()
    if not distribution then return false end
    local payload = ARC:Serialize(messageType, ARC.Constants.PROTOCOL_VERSION, ...)
    ARC:SendCommMessage(ARC.Constants.COMM_PREFIX, payload, distribution, nil, priority or "NORMAL")
    return true
end

function Comms:RequestState(force)
    local now = ARC:Now()
    if type(self.lastRequest) ~= "number" then self.lastRequest = -100 end
    if not force and now - self.lastRequest < ARC.Constants.REQUEST_THROTTLE then return false end
    self.lastRequest = now
    return self:Send("REQ", "NORMAL", self.session)
end

function Comms:BuildStateRows()
    local rows = {}
    local playerKey = ARC.Roster:GetPlayer()
    local player = playerKey and ARC.State.players[playerKey]
    if not player then return rows end
    local now = ARC:Now()
    for canonicalID, spell in pairs(player.spells) do
        table.insert(rows, {
            canonicalID,
            math.floor(math.max(0, (spell.readyAt or 0) - now) * 10 + 0.5),
            math.floor(math.max(0, spell.duration or 0) * 10 + 0.5),
            math.floor(math.max(0, tonumber(spell.charges) or 0)),
            math.floor(math.max(0, tonumber(spell.maxCharges) or 0)),
        })
    end
    table.sort(rows, function(a, b) return a[1] < b[1] end)
    return rows
end

function Comms:SendState(force, reason)
    local now = ARC:Now()
    if type(self.lastState) ~= "number" then self.lastState = -100 end
    if not force and now - self.lastState < ARC.Constants.REPORT_MIN_INTERVAL then
        self:ScheduleState(ARC.Constants.REPORT_MIN_INTERVAL - (now - self.lastState), reason)
        return false
    end
    self.lastState = now
    ARC:Debug("sending STATE: " .. tostring(reason))
    return self:Send("STATE", "NORMAL", self.session, self:NextSequence(),
        ARC.Spellbook.capabilityRevision, self:BuildStateRows())
end

function Comms:ScheduleState(delay, reason)
    delay = math.max(0, tonumber(delay) or 0.1)
    local dueAt = ARC:Now() + delay
    if self.stateTimer and self.stateDueAt and self.stateDueAt <= dueAt then return end
    if self.stateTimer then ARC:CancelTimer(self.stateTimer, true) end
    self.stateDueAt = dueAt
    self.stateTimer = ARC:ScheduleTimer(function()
        self.stateTimer = nil
        self.stateDueAt = nil
        self:SendState(false, reason)
    end, delay)
end

function Comms:SendCast(canonicalID, value, target)
    if not ARC.Registry:Get(canonicalID) then return false end
    local remaining = math.floor(math.max(0, value.remaining or 0) * 10 + 0.5)
    local duration = math.floor(math.max(0, value.duration or 0) * 10 + 0.5)
    local charges = math.floor(math.max(0, tonumber(value.charges) or 0))
    local maxCharges = math.floor(math.max(0, tonumber(value.maxCharges) or 0))
    if target and #target > 60 then target = string.sub(target, 1, 60) end
    return self:Send("CAST", "ALERT", self.session, self:NextSequence(), canonicalID,
        remaining, duration, target, charges, maxCharges)
end

function Comms:SendLeaseClaim(token, duration)
    return self:Send("LEASE_CLAIM", "ALERT", self.session, self:NextSequence(),
        token, math.floor(duration * 10 + 0.5))
end

function Comms:SendLeaseHold(token, duration)
    return self:Send("LEASE_HOLD", "ALERT", self.session, self:NextSequence(),
        token, math.floor(duration * 10 + 0.5))
end

function Comms:SendLeaseRelease(token)
    return self:Send("LEASE_RELEASE", "NORMAL", self.session, self:NextSequence(), token)
end

function Comms:SendUseRequest(requestID, attemptID, leaseToken, targetKey, canonicalID, timeout)
    return self:Send("USE_REQ", "ALERT", self.session, self:NextSequence(), requestID,
        attemptID, leaseToken, targetKey, canonicalID, math.floor(timeout * 10 + 0.5))
end

function Comms:SendUseStatus(requestID, attemptID, leaseToken, status, canonicalID)
    return self:Send("USE_STATUS", "ALERT", self.session, self:NextSequence(),
        requestID, attemptID, leaseToken, status, canonicalID)
end

function Comms:SendUseCancel(requestID, attemptID, leaseToken, targetKey)
    return self:Send("USE_CANCEL", "ALERT", self.session, self:NextSequence(),
        requestID, attemptID, leaseToken, targetKey)
end

function Comms:SendUseSync(requestID, attemptID, leaseToken, targetKey, canonicalID, remaining)
    return self:Send("USE_SYNC", "ALERT", self.session, self:NextSequence(),
        requestID, attemptID, leaseToken, targetKey, canonicalID,
        math.floor(math.max(0, remaining) * 10 + 0.5))
end

function Comms:SendUseEnd(requestID, leaseToken)
    return self:Send("USE_END", "ALERT", self.session, self:NextSequence(),
        requestID, leaseToken)
end

function Comms:SendBundleRequest(bundleID, bundleName, itemID, attemptID,
    leaseToken, targetKey, canonicalID, timeout, order)
    if #bundleName > 60 then bundleName = string.sub(bundleName, 1, 60) end
    return self:Send("BUNDLE_REQ", "ALERT", self.session, self:NextSequence(),
        bundleID, bundleName, itemID, attemptID, leaseToken, targetKey, canonicalID,
        math.floor(timeout * 10 + 0.5), math.floor(tonumber(order) or 1))
end

function Comms:SendBundleStatus(bundleID, itemID, attemptID, leaseToken, status, canonicalID)
    return self:Send("BUNDLE_STATUS", "ALERT", self.session, self:NextSequence(),
        bundleID, itemID, attemptID, leaseToken, status, canonicalID)
end

function Comms:SendBundleCancel(itemID, attemptID, leaseToken, targetKey)
    return self:Send("BUNDLE_CANCEL", "ALERT", self.session, self:NextSequence(),
        itemID, attemptID, leaseToken, targetKey)
end

function Comms:SendBundleSync(bundleID, bundleName, leaseToken, rows)
    if #bundleName > 60 then bundleName = string.sub(bundleName, 1, 60) end
    return self:Send("BUNDLE_SYNC", "NORMAL", self.session, self:NextSequence(),
        bundleID, bundleName, leaseToken, rows)
end

function Comms:SendBundleEnd(bundleID, leaseToken)
    return self:Send("BUNDLE_END", "ALERT", self.session, self:NextSequence(),
        bundleID, leaseToken)
end

function Comms:SchedulePeriodicReport()
    local delay = math.random(25, 35)
    self.periodicTimer = ARC:ScheduleTimer(function()
        self:SendState(true, "periodic")
        self:SchedulePeriodicReport()
    end, delay)
end

function Comms:DecodeRows(serializedRows)
    if type(serializedRows) ~= "table" then return nil, "rows are not a table" end
    local rows = {}
    for index, row in ipairs(serializedRows) do
        if index > 200 or type(row) ~= "table" then return nil, "invalid row" end
        local canonicalID = ARC.Registry:Canonicalize(row[1])
        local remainingTenths, durationTenths = row[2], row[3]
        local charges, maxCharges = row[4] or 0, row[5] or 0
        if not canonicalID then return nil, "unregistered spell" end
        if not validInteger(remainingTenths, 0, ARC.Constants.MAX_COOLDOWN * 10) then
            return nil, "invalid remaining"
        end
        if not validInteger(durationTenths, 0, ARC.Constants.MAX_COOLDOWN * 10) then
            return nil, "invalid duration"
        end
        if not validInteger(charges, 0, 100) or not validInteger(maxCharges, 0, 100)
            or charges > maxCharges then return nil, "invalid charges" end
        rows[canonicalID] = {
            remaining = remainingTenths / 10,
            duration = durationTenths / 10,
            charges = charges,
            maxCharges = maxCharges,
        }
    end
    return rows
end

function Comms:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= ARC.Constants.COMM_PREFIX or type(message) ~= "string" then return end
    local identity = ARC.Roster:FindSender(sender)
    if not identity then
        ARC:Debug("rejected message from non-roster sender " .. tostring(sender))
        return
    end
    local playerKey = ARC.Roster:GetPlayer()
    if identity.key == playerKey then return end

    local decoded = { ARC:Deserialize(message) }
    if not decoded[1] then
        ARC:Debug("rejected malformed message")
        return
    end
    local messageType, protocol = decoded[2], decoded[3]
    if protocol ~= ARC.Constants.PROTOCOL_VERSION then
        if not self.protocolWarnings[identity.key] then
            self.protocolWarnings[identity.key] = true
            ARC:Print("protocol mismatch with " .. tostring(identity.name)
                .. "; update ARC on both clients")
        end
        ARC:Debug("rejected protocol " .. tostring(protocol))
        return
    end

    if messageType == "REQ" then
        local now = ARC:Now()
        if now - (self.remoteRequests[identity.key] or -100) < 3 then return end
        self.remoteRequests[identity.key] = now
        self:ScheduleState(math.random(10, 40) / 100, "request")
        return
    end

    local session, sequence = decoded[4], decoded[5]
    if type(session) ~= "string" or #session < 1 or #session > 80
        or not validInteger(sequence, 0, 2147483647) then
        ARC:Debug("rejected invalid session or sequence")
        return
    end

    if messageType == "STATE" then
        local capabilityRevision, encodedRows = decoded[6], decoded[7]
        if not validInteger(capabilityRevision, 0, 2147483647) then return end
        local rows, reason = self:DecodeRows(encodedRows)
        if not rows then ARC:Debug("rejected STATE: " .. tostring(reason)) return end
        ARC.State:ApplyReport(identity.key, identity, session, sequence, capabilityRevision, rows)
    elseif messageType == "CAST" then
        local canonicalID = ARC.Registry:Canonicalize(decoded[6])
        local remainingTenths, durationTenths, target = decoded[7], decoded[8], decoded[9]
        local charges, maxCharges = decoded[10] or 0, decoded[11] or 0
        if not canonicalID
            or not validInteger(remainingTenths, 0, ARC.Constants.MAX_COOLDOWN * 10)
            or not validInteger(durationTenths, 0, ARC.Constants.MAX_COOLDOWN * 10)
            or not validInteger(charges, 0, 100)
            or not validInteger(maxCharges, 0, 100) or charges > maxCharges
            or (target ~= nil and (type(target) ~= "string" or #target > 60)) then return end
        ARC.State:ApplyCast(identity.key, identity, session, sequence, canonicalID, {
            remaining = remainingTenths / 10,
            duration = durationTenths / 10,
            target = target,
            charges = charges,
            maxCharges = maxCharges,
        })
    elseif messageType == "LEASE_CLAIM" or messageType == "LEASE_HOLD" then
        local token, durationTenths = decoded[6], decoded[7]
        if not validString(token, 120) or not validInteger(durationTenths, 10, 300) then
            return
        end
        if messageType == "LEASE_CLAIM" then
            ARC.Automation:OnLeaseClaim(identity, token, durationTenths / 10)
        else
            ARC.Automation:OnLeaseHold(identity, token, durationTenths / 10)
        end
    elseif messageType == "LEASE_RELEASE" then
        local token = decoded[6]
        if validString(token, 120) then ARC.Automation:OnLeaseRelease(identity, token) end
    elseif messageType == "USE_REQ" then
        local requestID, attemptID, leaseToken, targetKey =
            decoded[6], decoded[7], decoded[8], decoded[9]
        local canonicalID = ARC.Registry:Canonicalize(decoded[10])
        local timeoutTenths = decoded[11]
        if not validString(requestID, 120) or not validString(attemptID, 160)
            or not validString(leaseToken, 120) or not validString(targetKey, 100)
            or not canonicalID or not validInteger(timeoutTenths, 30, 300) then return end
        ARC.Requests:OnRemoteRequest(identity, session, sequence, requestID, attemptID,
            leaseToken, targetKey, canonicalID, timeoutTenths / 10)
    elseif messageType == "USE_STATUS" then
        local requestID, attemptID, leaseToken, status =
            decoded[6], decoded[7], decoded[8], decoded[9]
        local canonicalID = ARC.Registry:Canonicalize(decoded[10])
        local allowed = status == "ACK" or status == "CAST" or status == "DECLINED"
            or status == "DEAD" or status == "OFFLINE" or status == "UNAVAILABLE"
            or status == "BUSY" or status == "TIMEOUT"
        if not validString(requestID, 120) or not validString(attemptID, 160)
            or not validString(leaseToken, 120) or not allowed or not canonicalID then return end
        ARC.Requests:OnRemoteStatus(identity, session, sequence, requestID, attemptID,
            leaseToken, status, canonicalID)
    elseif messageType == "USE_CANCEL" then
        local requestID, attemptID, leaseToken, targetKey =
            decoded[6], decoded[7], decoded[8], decoded[9]
        if not validString(requestID, 120) or not validString(attemptID, 160)
            or not validString(leaseToken, 120) or not validString(targetKey, 100) then return end
        ARC.Requests:OnRemoteCancel(identity, session, sequence, requestID, attemptID,
            leaseToken, targetKey)
    elseif messageType == "USE_SYNC" then
        local requestID, attemptID, leaseToken, targetKey =
            decoded[6], decoded[7], decoded[8], decoded[9]
        local canonicalID = ARC.Registry:Canonicalize(decoded[10])
        local remainingTenths = decoded[11]
        if not validString(requestID, 120) or not validString(attemptID, 160)
            or not validString(leaseToken, 120) or type(targetKey) ~= "string"
            or #targetKey > 100 or not canonicalID
            or not validInteger(remainingTenths, 0, 300) then return end
        ARC.Requests:OnRemoteSync(identity, session, sequence, requestID, attemptID,
            leaseToken, targetKey, canonicalID, remainingTenths / 10)
    elseif messageType == "USE_END" then
        local requestID, leaseToken = decoded[6], decoded[7]
        if not validString(requestID, 120) or not validString(leaseToken, 120) then return end
        ARC.Requests:OnRemoteEnd(identity, session, sequence, requestID, leaseToken)
    elseif messageType == "BUNDLE_REQ" then
        local bundleID, bundleName, itemID, attemptID, leaseToken, targetKey =
            decoded[6], decoded[7], decoded[8], decoded[9], decoded[10], decoded[11]
        local canonicalID = ARC.Registry:Canonicalize(decoded[12])
        local timeoutTenths, order = decoded[13], decoded[14]
        if not validString(bundleID, 120) or not validString(bundleName, 60)
            or not validString(itemID, 140) or not validString(attemptID, 180)
            or not validString(leaseToken, 120) or not validString(targetKey, 100)
            or not canonicalID or not validInteger(timeoutTenths, 30, 300)
            or not validInteger(order, 1, ARC.Constants.MAX_BUNDLE_SPELLS) then return end
        ARC.Bundles:OnRemoteRequest(identity, session, sequence, bundleID, bundleName,
            itemID, attemptID, leaseToken, targetKey, canonicalID,
            timeoutTenths / 10, order)
    elseif messageType == "BUNDLE_STATUS" then
        local bundleID, itemID, attemptID, leaseToken, status =
            decoded[6], decoded[7], decoded[8], decoded[9], decoded[10]
        local canonicalID = ARC.Registry:Canonicalize(decoded[11])
        local allowed = status == "ACK" or status == "ACTIVE" or status == "QUEUED"
            or status == "CAST" or status == "DECLINED"
            or status == "DEAD" or status == "OFFLINE" or status == "UNAVAILABLE"
            or status == "BUSY" or status == "TIMEOUT"
        if not validString(bundleID, 120) or not validString(itemID, 140)
            or not validString(attemptID, 180) or not validString(leaseToken, 120)
            or not allowed or not canonicalID then return end
        ARC.Bundles:OnRemoteStatus(identity, session, sequence, bundleID,
            itemID, attemptID, leaseToken, status, canonicalID)
    elseif messageType == "BUNDLE_CANCEL" then
        local itemID, attemptID, leaseToken, targetKey =
            decoded[6], decoded[7], decoded[8], decoded[9]
        if not validString(itemID, 140) or not validString(attemptID, 180)
            or not validString(leaseToken, 120) or not validString(targetKey, 100) then return end
        ARC.Bundles:OnRemoteCancel(identity, session, sequence, itemID, attemptID,
            leaseToken, targetKey)
    elseif messageType == "BUNDLE_SYNC" then
        local bundleID, bundleName, leaseToken, encodedRows =
            decoded[6], decoded[7], decoded[8], decoded[9]
        if not validString(bundleID, 120) or not validString(bundleName, 60)
            or not validString(leaseToken, 120) or type(encodedRows) ~= "table" then return end
        local rows = {}
        for index, row in ipairs(encodedRows) do
            if index > ARC.Constants.MAX_BUNDLE_SPELLS or type(row) ~= "table" then return end
            local canonicalID = ARC.Registry:Canonicalize(row[4])
            if not validString(row[1], 140) or not validString(row[2], 180)
                or not validString(row[3], 100) or not canonicalID
                or not validInteger(row[5], 30, 300)
                or not validInteger(row[6], 1, ARC.Constants.MAX_BUNDLE_SPELLS) then return end
            table.insert(rows, {
                itemID = row[1],
                attemptID = row[2],
                targetKey = row[3],
                spellID = canonicalID,
                remaining = row[5] / 10,
                order = row[6],
            })
        end
        ARC.Bundles:OnRemoteSync(identity, session, sequence, bundleID,
            bundleName, leaseToken, rows)
    elseif messageType == "BUNDLE_END" then
        local bundleID, leaseToken = decoded[6], decoded[7]
        if not validString(bundleID, 120) or not validString(leaseToken, 120) then return end
        ARC.Bundles:OnRemoteEnd(identity, session, sequence, bundleID, leaseToken)
    end
end
