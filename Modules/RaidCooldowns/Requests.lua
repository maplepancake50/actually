local ARC = Actually.Modules.RaidCooldowns
local Automation = ARC:NewModule("Automation")
local Requests = ARC:NewModule("Requests")

local function automationShortName(player)
    local name = player and player.name or "Unknown"
    return string.match(tostring(name), "^[^-]+") or tostring(name)
end

function Automation:Initialize()
    self.reservations = {}
    self.failures = {}
    self.observed = {}
    self.lastAssigned = {}
    self.assignmentSequence = 0
    self.lease = nil
    self.leaseCounter = 0
    self.nextLeaseHeartbeat = 0
    self.initialized = true
end

function Automation:HasWork()
    return (ARC.Requests and ARC.Requests.outgoing)
        or (ARC.Bundles and ARC.Bundles.active)
end

function Automation:HasLocalLease()
    local selfKey = ARC.Roster:GetPlayer()
    return self.lease and self.lease.ownerKey == selfKey
        and not self.lease.provisional
        and (self.lease.expiresAt or 0) > ARC:Now()
end

function Automation:GetLeaseToken()
    return self:HasLocalLease() and self.lease.token or nil
end

function Automation:CancelLocalWork(reason)
    if ARC.Requests and ARC.Requests.outgoing then
        ARC.Requests:CancelOutgoing(reason or "another commander took control", true)
    end
    if ARC.Bundles and ARC.Bundles.active then
        ARC.Bundles:CancelActive(reason or "another commander took control", true)
    end
end

function Automation:Acquire(callback)
    if type(callback) ~= "function" then return false end
    local now = ARC:Now()
    local selfKey = ARC.Roster:GetPlayer()
    if self:HasLocalLease() then callback(true) return true end
    if self.lease and not self.lease.provisional
        and (self.lease.expiresAt or 0) > now
        and self.lease.ownerKey ~= selfKey then
        ARC:Print("cooldown command already controlled by "
            .. automationShortName(ARC.State.players[self.lease.ownerKey]
                or ARC.Roster.byKey[self.lease.ownerKey]))
        callback(false, "another coordinator already controls ARC")
        return false
    end

    self.leaseCounter = self.leaseCounter + 1
    local token = tostring(ARC.Comms.session) .. ":L:" .. tostring(self.leaseCounter)
    self.lease = {
        ownerKey = selfKey,
        token = token,
        provisional = true,
        expiresAt = now + ARC.Constants.LEASE_DURATION,
    }
    ARC.Comms:SendLeaseClaim(token, ARC.Constants.LEASE_DURATION)
    ARC:ScheduleTimer(function()
        local lease = Automation.lease
        if not lease or lease.token ~= token or lease.ownerKey ~= selfKey then
            ARC:Print("cooldown command yielded to another coordinator")
            callback(false, "another coordinator won the command lease")
            return
        end
        lease.provisional = false
        lease.expiresAt = ARC:Now() + ARC.Constants.LEASE_DURATION
        Automation.nextLeaseHeartbeat = 0
        ARC.Comms:SendLeaseHold(token, ARC.Constants.LEASE_DURATION)
        callback(true)
    end, ARC.Constants.LEASE_CLAIM_WINDOW)
    return true
end

function Automation:AbortProvisionalAcquire()
    local lease = self.lease
    if not lease or not lease.provisional
        or lease.ownerKey ~= ARC.Roster:GetPlayer() then
        return false
    end
    self.lease = nil
    ARC.Comms:SendLeaseRelease(lease.token)
    return true
end

function Automation:OnLeaseClaim(identity, token, duration)
    if not ARC.Roster:IsCoordinator(identity) then return false end
    local now = ARC:Now()
    local selfKey = ARC.Roster:GetPlayer()
    local lease = self.lease
    if lease and not lease.provisional and (lease.expiresAt or 0) > now then
        if lease.ownerKey == selfKey then
            ARC.Comms:SendLeaseHold(lease.token,
                math.max(1, lease.expiresAt - now))
        end
        return lease.ownerKey == identity.key and lease.token == token
    end
    if not lease or (lease.expiresAt or 0) <= now
        or tostring(identity.key) < tostring(lease.ownerKey or "") then
        self.lease = {
            ownerKey = identity.key,
            token = token,
            provisional = true,
            expiresAt = now + duration,
        }
        return true
    end
    return false
end

function Automation:OnLeaseHold(identity, token, duration)
    if not ARC.Roster:IsCoordinator(identity) then return false end
    local now = ARC:Now()
    local selfKey = ARC.Roster:GetPlayer()
    local lease = self.lease
    local accept = not lease or (lease.expiresAt or 0) <= now
        or (lease.ownerKey == identity.key and lease.token == token)
        or lease.provisional
        or tostring(identity.key) < tostring(lease.ownerKey or "")
    if not accept then
        if lease.ownerKey == selfKey then
            ARC.Comms:SendLeaseHold(lease.token,
                math.max(1, lease.expiresAt - now))
        end
        return false
    end
    local replacedOwner = lease and lease.ownerKey
    local replacedToken = lease and lease.token
    local lostLocal = lease and lease.ownerKey == selfKey
        and (lease.token ~= token or identity.key ~= selfKey)
    self.lease = {
        ownerKey = identity.key,
        token = token,
        provisional = false,
        expiresAt = now + duration,
    }
    if replacedOwner and replacedOwner ~= identity.key and not lostLocal then
        if ARC.Requests and ARC.Requests.incoming
            and ARC.Requests.incoming.leaseToken == replacedToken then
            ARC.Requests:ClearIncoming()
        end
        if ARC.Bundles and ARC.Bundles.incoming then
            local remove = {}
            for itemID, incoming in pairs(ARC.Bundles.incoming) do
                if incoming.leaseToken == replacedToken then table.insert(remove, itemID) end
            end
            for _, itemID in ipairs(remove) do ARC.Bundles:RemoveIncoming(itemID, true) end
            if not ARC.Bundles.activeIncomingID then ARC.Bundles:ActivateNext() end
        end
    end
    if lostLocal then self:CancelLocalWork("another coordinator won the command lease") end
    return true
end

function Automation:AcceptLease(identity, token)
    if not ARC.Roster:IsCoordinator(identity) or type(token) ~= "string" then return false end
    local lease = self.lease
    if lease and lease.ownerKey == identity.key and lease.token == token
        and (lease.expiresAt or 0) > ARC:Now() then return true end
    return self:OnLeaseHold(identity, token, ARC.Constants.LEASE_DURATION)
end

function Automation:ReleaseLease(silent)
    local selfKey = ARC.Roster:GetPlayer()
    local lease = self.lease
    if lease and lease.ownerKey == selfKey then
        if not silent and ARC.Comms and ARC.Comms.initialized then
            ARC.Comms:SendLeaseRelease(lease.token)
        end
        self.lease = nil
    end
end

function Automation:OnLeaseRelease(identity, token)
    if not ARC.Roster:IsCoordinator(identity) then return end
    local lease = self.lease
    if lease and lease.ownerKey == identity.key and lease.token == token then
        self.lease = nil
    end
end

function Automation:Reserve(attemptID, ownerKey, targetKey, spellID, expiresAt, kind)
    if not attemptID or not targetKey or not spellID then return end
    self.reservations[attemptID] = {
        ownerKey = ownerKey,
        targetKey = targetKey,
        spellID = spellID,
        expiresAt = expiresAt or (ARC:Now() + 30),
        kind = kind,
    }
end

function Automation:Release(attemptID)
    if attemptID then self.reservations[attemptID] = nil end
end

function Automation:ReleasePrefix(prefix, ownerKey, validAttempts)
    if type(prefix) ~= "string" then return end
    for attemptID, value in pairs(self.reservations) do
        if string.sub(attemptID, 1, #prefix) == prefix
            and (not ownerKey or value.ownerKey == ownerKey)
            and (not validAttempts or not validAttempts[attemptID]) then
            self.reservations[attemptID] = nil
        end
    end
end

function Automation:IsReserved(targetKey, spellID, exceptAttempt)
    local now = ARC:Now()
    for attemptID, value in pairs(self.reservations) do
        if (value.expiresAt or 0) <= now then
            self.reservations[attemptID] = nil
        elseif attemptID ~= exceptAttempt and value.targetKey == targetKey
            and value.spellID == spellID then
            return true
        end
    end
    local observed = self.observed[targetKey] and self.observed[targetKey][spellID]
    return observed and observed > now or false
end

function Automation:GetLoad(targetKey)
    local now, count = ARC:Now(), 0
    for attemptID, value in pairs(self.reservations) do
        if (value.expiresAt or 0) <= now then
            self.reservations[attemptID] = nil
        elseif value.targetKey == targetKey then
            count = count + 1
        end
    end
    return count
end

function Automation:RecordFailure(targetKey, spellID, reason)
    if ARC.db.profile.automation
        and ARC.db.profile.automation.failureMemory == false then return end
    local delays = { timeout = 30, declined = 20, unavailable = 12, busy = 6,
        offline = 10, dead = 10, ["stale report"] = 8 }
    local delay = delays[string.lower(tostring(reason or ""))] or 8
    self.failures[targetKey] = self.failures[targetKey] or {}
    self.failures[targetKey][spellID] = ARC:Now() + delay
end

function Automation:RecordSuccess(targetKey, spellID)
    if self.failures[targetKey] then self.failures[targetKey][spellID] = nil end
    self.assignmentSequence = self.assignmentSequence + 1
    self.lastAssigned[targetKey] = self.assignmentSequence
end

function Automation:ObserveCast(targetKey, spellID)
    self.observed[targetKey] = self.observed[targetKey] or {}
    self.observed[targetKey][spellID] = ARC:Now() + ARC.Constants.OBSERVED_CAST_HOLD
end

function Automation:ClearObservedForPlayer(targetKey, reportedSpells)
    local observed = self.observed[targetKey]
    if not observed then return end
    local now = ARC:Now()
    for spellID in pairs(observed) do
        local spell = reportedSpells and reportedSpells[spellID]
        if spell and (spell.readyAt or 0) > now then observed[spellID] = nil end
    end
    if not next(observed) then self.observed[targetKey] = nil end
end

function Automation:FindCandidate(spellID, preferredKey, attempted, simulatedLoad)
    attempted = attempted or {}
    simulatedLoad = simulatedLoad or {}
    local now = ARC:Now()
    local candidates = {}
    for playerKey, player in pairs(ARC.State.players or {}) do
        if not attempted[playerKey]
            and ARC.Requests:IsEligible(playerKey, spellID)
            and not self:IsReserved(playerKey, spellID) then
            local failureUntil = self.failures[playerKey]
                and self.failures[playerKey][spellID] or 0
            local score = (self:GetLoad(playerKey) + (simulatedLoad[playerKey] or 0)) * 100
                + (failureUntil > now and 40 or 0)
                + (self.lastAssigned[playerKey] or 0) * 0.001
            if preferredKey == playerKey then score = score - 10000 end
            table.insert(candidates, {
                key = playerKey,
                score = score,
                name = string.lower(automationShortName(player)),
            })
        end
    end
    table.sort(candidates, function(left, right)
        if left.score ~= right.score then return left.score < right.score end
        if left.name ~= right.name then return left.name < right.name end
        return tostring(left.key) < tostring(right.key)
    end)
    return candidates[1] and candidates[1].key or nil
end

function Automation:PlanSpells(spellIDs)
    local plan, simulatedLoad = {}, {}
    for index, spellID in ipairs(spellIDs or {}) do
        local playerKey = self:FindCandidate(spellID, nil, {}, simulatedLoad)
        plan[index] = playerKey
        if playerKey then simulatedLoad[playerKey] = (simulatedLoad[playerKey] or 0) + 1 end
    end
    return plan
end

function Automation:CooldownBeganAfter(spell, assignedAt)
    if not spell or (spell.readyAt or 0) <= ARC:Now() + 0.5 then return false end
    return (spell.cooldownStartedAt or 0) >= (assignedAt or 0) - 1.0
end

function Automation:WasUsedAfterAssignment(spell, assignedAt, assignedCharges)
    if self:CooldownBeganAfter(spell, assignedAt) then return true end
    return assignedCharges ~= nil and spell and spell.maxCharges and spell.maxCharges > 0
        and spell.charges ~= nil and spell.charges < assignedCharges
end

function Automation:OnUpdate(now)
    for attemptID, value in pairs(self.reservations) do
        if (value.expiresAt or 0) <= now then self.reservations[attemptID] = nil end
    end
    for playerKey, spells in pairs(self.observed) do
        for spellID, expiresAt in pairs(spells) do
            if expiresAt <= now then spells[spellID] = nil end
        end
        if not next(spells) then self.observed[playerKey] = nil end
    end
    local lease = self.lease
    local selfKey = ARC.Roster:GetPlayer()
    if lease and (lease.expiresAt or 0) <= now then
        self.lease = nil
    elseif lease and lease.ownerKey == selfKey and not lease.provisional then
        if not ARC.Roster:IsLocalCoordinator() then
            self:CancelLocalWork("coordinator authority lost")
            self:ReleaseLease()
        elseif self:HasWork() then
            if now >= (self.nextLeaseHeartbeat or 0) then
                lease.expiresAt = now + ARC.Constants.LEASE_DURATION
                ARC.Comms:SendLeaseHold(lease.token, ARC.Constants.LEASE_DURATION)
                self.nextLeaseHeartbeat = now + ARC.Constants.LEASE_HEARTBEAT_INTERVAL
            end
        else
            self:ReleaseLease()
        end
    end
end

function Automation:OnRosterChanged()
    local lease = self.lease
    if not lease then return end
    local identity = ARC.Roster.byKey[lease.ownerKey]
    if not identity or not ARC.Roster:IsCoordinator(identity) then
        local oldToken = lease.token
        self.lease = nil
        if ARC.Requests and ARC.Requests.incoming
            and ARC.Requests.incoming.leaseToken == oldToken then
            ARC.Requests:ClearIncoming()
        end
        if ARC.Bundles and ARC.Bundles.incoming then
            local remove = {}
            for itemID, incoming in pairs(ARC.Bundles.incoming) do
                if incoming.leaseToken == oldToken then table.insert(remove, itemID) end
            end
            for _, itemID in ipairs(remove) do ARC.Bundles:RemoveIncoming(itemID, true) end
            if not ARC.Bundles.activeIncomingID then ARC.Bundles:ActivateNext() end
        end
    end
end

local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local FAILURE_STATUSES = {
    DECLINED = true,
    DEAD = true,
    OFFLINE = true,
    UNAVAILABLE = true,
    BUSY = true,
    TIMEOUT = true,
}

local function setBackdrop(frame, background, border)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(background[1], background[2], background[3], background[4] or 1)
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

local function playerShortName(player)
    local name = player and player.name or "Unknown"
    return string.match(name, "^[^-]+") or name
end

function Requests:Initialize()
    self.outgoing = nil
    self.incoming = nil
    self.requestCounter = 0
    self.remoteSequences = {}
    local ok, reason = pcall(self.CreateAlert, self)
    if not ok then
        self.alert = nil
        ARC:Print("request alert unavailable: " .. tostring(reason))
    end
    self.initialized = true
end

function Requests:GetTimeout()
    local value = tonumber(ARC.db.profile.requests and ARC.db.profile.requests.timeout) or 8
    return math.max(3, math.min(value, 30))
end

function Requests:IsEligible(playerKey, spellID, allowRequestedCooldown)
    local player = ARC.State.players[playerKey]
    local spell = player and player.spells and player.spells[spellID]
    if not player or not spell then return false, "spell unavailable" end
    local selfKey = ARC.Roster:GetPlayer()
    if playerKey ~= selfKey and (player.source ~= "REPORT" or not ARC.State.peers[playerKey]) then
        return false, "ARC not detected"
    end
    if player.connected == false then return false, "offline" end
    if player.dead then return false, "dead" end
    if player.stale then return false, "stale report" end
    if spell.maxCharges and spell.maxCharges > 0
        and spell.charges and spell.charges > 0 then return true end
    local remaining = math.max(0, (spell.readyAt or 0) - ARC:Now())
    if not allowRequestedCooldown and remaining > 0.5 then return false, "cooldown not ready" end
    return true
end

function Requests:FindCandidate(spellID, preferredKey, attempted)
    return ARC.Automation:FindCandidate(spellID, preferredKey, attempted)
end

function Requests:NextRequestID()
    self.requestCounter = self.requestCounter + 1
    return tostring(ARC.Comms.session) .. ":R:" .. tostring(self.requestCounter)
end

function Requests:Start(playerKey, spellID, leaseReady)
    spellID = ARC.Registry:Canonicalize(spellID)
    if not spellID then ARC:Print("request rejected: unregistered spell") return false end
    if not ARC:RequireCommandAuthority() then return false end
    if not ARC.Roster:IsGrouped() then
        ARC:Print("join a party or raid before requesting a cooldown")
        return false
    end
    if ARC.Bundles and ARC.Bundles.active then
        ARC:Print("cancel the active cooldown bundle before making a single request")
        return false
    end
    if not leaseReady and not ARC.Automation:HasLocalLease() then
        return ARC.Automation:Acquire(function(acquired)
            if acquired then Requests:Start(playerKey, spellID, true) end
        end)
    end
    if self.outgoing then self:CancelOutgoing("replaced by a new request", true) end

    local request = {
        id = self:NextRequestID(),
        spellID = spellID,
        attempted = {},
        createdAt = ARC:Now(),
        timeout = self:GetTimeout(),
        attemptCounter = 0,
        history = {},
    }
    self.outgoing = request
    local candidate = self:FindCandidate(spellID, playerKey, request.attempted)
    if not candidate then
        self.outgoing = nil
        ARC:Print("no living, connected player has "
            .. ARC.SpellInfo:ResolveSpellName(spellID) .. " ready")
        ARC.Renderer:MarkDirty("request unavailable")
        return false
    end
    return self:Assign(candidate, "requested")
end

function Requests:Assign(playerKey, reason)
    local request = self.outgoing
    if not request then return false end
    request.targetKey = playerKey
    request.attempted[playerKey] = true
    request.attemptCounter = (request.attemptCounter or 0) + 1
    request.attemptID = request.id .. ":A:" .. tostring(request.attemptCounter)
    request.assignedAt = ARC:Now()
    local assignedSpell = ARC.State.players[playerKey]
        and ARC.State.players[playerKey].spells[request.spellID]
    request.assignedCharges = assignedSpell and assignedSpell.charges
    request.deadline = request.assignedAt + request.timeout
    request.nextSyncAt = 0
    request.status = "SENT"
    request.leaseToken = request.leaseToken or ARC.Automation:GetLeaseToken()
    ARC.Automation:Reserve(request.attemptID, ARC.Roster:GetPlayer(), playerKey,
        request.spellID, request.deadline + ARC.Constants.USE_SYNC_TIMEOUT, "single")

    local target = ARC.State.players[playerKey]
    ARC:Print("requesting " .. ARC.SpellInfo:ResolveSpellName(request.spellID)
        .. " from " .. playerShortName(target)
        .. (reason and " (" .. tostring(reason) .. ")" or ""))

    local selfKey, selfIdentity = ARC.Roster:GetPlayer()
    if playerKey == selfKey then
        self:OnRemoteRequest(selfIdentity, ARC.Comms.session, ARC.Comms:NextSequence(),
            request.id, request.attemptID, request.leaseToken,
            playerKey, request.spellID, request.timeout)
    else
        ARC.Comms:SendUseRequest(request.id, request.attemptID,
            request.leaseToken, playerKey, request.spellID, request.timeout)
    end
    ARC.Renderer:MarkDirty("request assigned")
    ARC.Renderer:Reconcile()
    return true
end

function Requests:CancelAssignment(request, targetKey)
    if not request or not targetKey then return end
    local selfKey = ARC.Roster:GetPlayer()
    if targetKey == selfKey and self.incoming and self.incoming.id == request.id
        and self.incoming.attemptID == request.attemptID then
        self:ClearIncoming()
    else
        ARC.Comms:SendUseCancel(request.id, request.attemptID,
            request.leaseToken, targetKey)
    end
    ARC.Automation:Release(request.attemptID)
end

function Requests:Failover(reason)
    local request = self.outgoing
    if not request then return false end
    local oldTarget = request.targetKey
    request.history[oldTarget] = {
        attemptID = request.attemptID,
        expiresAt = ARC:Now() + ARC.Constants.LATE_CAST_GRACE,
    }
    self:CancelAssignment(request, oldTarget)
    ARC.Automation:RecordFailure(oldTarget, request.spellID, reason)
    local candidate = self:FindCandidate(request.spellID, nil, request.attempted)
    if candidate and ARC.db.profile.requests.autoFailover ~= false then
        ARC:Print(playerShortName(ARC.State.players[oldTarget]) .. " skipped: " .. tostring(reason))
        return self:Assign(candidate, "automatic fallback")
    end
    ARC:Print("request ended: " .. tostring(reason) .. "; no other ready player")
    self.outgoing = nil
    ARC.Comms:SendUseEnd(request.id, request.leaseToken)
    ARC.Renderer:MarkDirty("request failed")
    ARC.Renderer:Reconcile()
    return false
end

function Requests:Complete(playerKey, source)
    local request = self.outgoing
    if not request then return false end
    local prior = request.history and request.history[playerKey]
    if request.targetKey ~= playerKey
        and (not prior or (prior.expiresAt or 0) < ARC:Now()) then return false end
    self:CancelAssignment(request, request.targetKey)
    ARC.Automation:RecordSuccess(playerKey, request.spellID)
    ARC:Print(playerShortName(ARC.State.players[playerKey]) .. " used "
        .. ARC.SpellInfo:ResolveSpellName(request.spellID)
        .. (source and " (" .. tostring(source) .. ")" or ""))
    self.outgoing = nil
    ARC.Comms:SendUseEnd(request.id, request.leaseToken)
    ARC.Renderer:MarkDirty("request complete")
    ARC.Renderer:Reconcile()
    return true
end

function Requests:CancelOutgoing(reason, leaseLost)
    local request = self.outgoing
    if not request then return false end
    self:CancelAssignment(request, request.targetKey)
    self.outgoing = nil
    ARC.Comms:SendUseEnd(request.id, request.leaseToken)
    ARC:Print("request cancelled" .. (reason and ": " .. tostring(reason) or ""))
    ARC.Renderer:MarkDirty("request cancelled")
    ARC.Renderer:Reconcile()
    if not leaseLost then ARC.Automation:ReleaseLease() end
    return true
end

function Requests:IsOutgoingTarget(playerKey, spellID)
    local request = self.outgoing
    return request and request.targetKey == playerKey and request.spellID == spellID
end

function Requests:AcceptSequence(identity, session, sequence)
    self.remoteSequences = self.remoteSequences or {}
    local previous = self.remoteSequences[identity.key]
    if previous and previous.session == session and sequence <= previous.sequence then return false end
    self.remoteSequences[identity.key] = { session = session, sequence = sequence }
    return true
end

function Requests:SendStatus(status)
    local incoming = self.incoming
    if not incoming then return false end
    local requester = ARC.Roster.byKey[incoming.requesterKey]
    local selfKey, selfIdentity = ARC.Roster:GetPlayer()
    if incoming.requesterKey == selfKey then
        self:OnRemoteStatus(selfIdentity, ARC.Comms.session, ARC.Comms:NextSequence(),
            incoming.id, incoming.attemptID, incoming.leaseToken, status, incoming.spellID)
        return true
    end
    if not requester then return false end
    return ARC.Comms:SendUseStatus(incoming.id, incoming.attemptID,
        incoming.leaseToken, status, incoming.spellID)
end

function Requests:ClearIncoming()
    if self.incoming then ARC.Automation:Release(self.incoming.attemptID) end
    self.incoming = nil
    if self.alert then self.alert:Hide() end
end

function Requests:RejectIncoming(status)
    if self.incoming then self:SendStatus(status or "DECLINED") end
    self:ClearIncoming()
end

function Requests:OnRemoteRequest(requester, session, sequence, requestID, attemptID,
    leaseToken, targetKey, spellID, timeout, sequenceAccepted)
    if not sequenceAccepted and not self:AcceptSequence(requester, session, sequence) then return end
    if not ARC.Automation:AcceptLease(requester, leaseToken) then
        ARC:Debug("rejected cooldown request from non-coordinator " .. tostring(requester.name))
        return
    end
    ARC.Automation:Reserve(attemptID, requester.key, targetKey, spellID,
        ARC:Now() + timeout + ARC.Constants.USE_SYNC_TIMEOUT, "single")
    local selfKey = ARC.Roster:GetPlayer()
    if targetKey ~= selfKey then return end
    if self.incoming and self.incoming.id == requestID
        and self.incoming.attemptID == attemptID then
        self.incoming.lastSyncAt = ARC:Now()
        self:SendStatus("ACK")
        return
    end
    if self.incoming or (ARC.Bundles and next(ARC.Bundles.incoming or {})) then
        ARC.Comms:SendUseStatus(requestID, attemptID, leaseToken, "BUSY", spellID)
        return
    end
    if not self.alert then
        ARC.Comms:SendUseStatus(requestID, attemptID, leaseToken, "UNAVAILABLE", spellID)
        return
    end

    local player = ARC.State.players[selfKey]
    local eligible, reason = self:IsEligible(selfKey, spellID)
    if not eligible then
        local status = player and player.dead and "DEAD" or "UNAVAILABLE"
        ARC.Comms:SendUseStatus(requestID, attemptID, leaseToken, status, spellID)
        ARC:Debug("declined request locally: " .. tostring(reason))
        return
    end

    self.incoming = {
        id = requestID,
        attemptID = attemptID,
        leaseToken = leaseToken,
        requesterKey = requester.key,
        requesterName = playerShortName(requester),
        spellID = spellID,
        receivedAt = ARC:Now(),
        lastSyncAt = ARC:Now(),
        deadline = ARC:Now() + math.max(3, math.min(timeout, 30)),
    }
    self:ShowAlert()
    self:SendStatus("ACK")
end

function Requests:OnRemoteStatus(identity, session, sequence, requestID, attemptID,
    leaseToken, status, spellID)
    if not self:AcceptSequence(identity, session, sequence) then return end
    local request = self.outgoing
    if not request or request.id ~= requestID or request.spellID ~= spellID
        or request.leaseToken ~= leaseToken then return end
    local prior = request.history and request.history[identity.key]
    local current = request.targetKey == identity.key and request.attemptID == attemptID
    local oldCast = status == "CAST" and prior and prior.attemptID == attemptID
        and (prior.expiresAt or 0) >= ARC:Now()
    if not current and not oldCast then return end
    if status == "ACK" then
        local firstAck = request.status ~= "ACK"
        request.status = "ACK"
        if firstAck then request.deadline = ARC:Now() + request.timeout end
        ARC.Renderer:MarkDirty("request acknowledged")
    elseif status == "CAST" then
        self:Complete(identity.key, "confirmed")
    elseif FAILURE_STATUSES[status] then
        self:Failover(string.lower(status))
    end
end

function Requests:OnRemoteCancel(requester, session, sequence, requestID, attemptID,
    leaseToken, targetKey)
    if not self:AcceptSequence(requester, session, sequence) then return end
    if not ARC.Automation:AcceptLease(requester, leaseToken) then return end
    ARC.Automation:Release(attemptID)
    local selfKey = ARC.Roster:GetPlayer()
    if targetKey == selfKey and self.incoming and self.incoming.id == requestID
        and self.incoming.attemptID == attemptID then
        self:ClearIncoming()
    end
end

function Requests:OnRemoteSync(requester, session, sequence, requestID, attemptID,
    leaseToken, targetKey, spellID, remaining)
    if not self:AcceptSequence(requester, session, sequence) then return end
    if not ARC.Automation:AcceptLease(requester, leaseToken) then return end
    local selfKey = ARC.Roster:GetPlayer()
    if self.incoming and self.incoming.id == requestID
        and (targetKey ~= selfKey or self.incoming.attemptID ~= attemptID) then
        self:ClearIncoming()
    end
    if targetKey == selfKey and remaining > 0 then
        if self.incoming and self.incoming.attemptID == attemptID then
            self.incoming.lastSyncAt = ARC:Now()
            self:SendStatus("ACK")
        else
            self:OnRemoteRequest(requester, session, sequence, requestID, attemptID,
                leaseToken, targetKey, spellID, remaining, true)
        end
    end
    if targetKey and targetKey ~= "" then
        ARC.Automation:Reserve(attemptID, requester.key, targetKey, spellID,
            ARC:Now() + remaining + ARC.Constants.USE_SYNC_TIMEOUT, "single")
        ARC.Automation:ReleasePrefix(requestID .. ":", requester.key, { [attemptID] = true })
    end
end

function Requests:OnRemoteEnd(requester, session, sequence, requestID, leaseToken)
    if not self:AcceptSequence(requester, session, sequence) then return end
    if not ARC.Automation:AcceptLease(requester, leaseToken) then return end
    ARC.Automation:ReleasePrefix(requestID .. ":", requester.key)
    if self.incoming and self.incoming.id == requestID then self:ClearIncoming() end
end

function Requests:OnLocalCast(spellID)
    if self.incoming and self.incoming.spellID == spellID then
        self:SendStatus("CAST")
        self:ClearIncoming()
    end
end

function Requests:OnReportedCast(playerKey, spellID)
    local request = self.outgoing
    local prior = request and request.history and request.history[playerKey]
    if request and request.spellID == spellID
        and (request.targetKey == playerKey
            or (prior and (prior.expiresAt or 0) >= ARC:Now())) then
        self:Complete(playerKey, "observed")
    end
end

function Requests:OnRosterChanged()
    if not self.initialized then return end
    local incoming = self.incoming
    if incoming then
        local requester = ARC.Roster.byKey[incoming.requesterKey]
        if not requester or not ARC.Roster:IsCoordinator(requester) then self:ClearIncoming() end
    end
    self:OnUpdate(ARC:Now())
end

function Requests:OnPlayerDeath()
    if self.incoming then self:RejectIncoming("DEAD") end
end

function Requests:OnUpdate(now)
    if not self.initialized then return end
    local request = self.outgoing
    if request then
        local target = ARC.State.players[request.targetKey]
        if not ARC.Roster:IsLocalCoordinator() then
            self:CancelOutgoing("coordinator authority lost")
        elseif not target or target.connected == false then
            self:Failover("offline")
        elseif target.dead then
            self:Failover("dead")
        elseif target.stale then
            self:Failover("stale report")
        elseif not target.spells or not target.spells[request.spellID] then
            self:Failover("spell unavailable")
        elseif ARC.Automation:WasUsedAfterAssignment(target.spells[request.spellID],
            request.assignedAt, request.assignedCharges) then
            self:Complete(request.targetKey, "cooldown detected")
        elseif now >= (request.deadline or 0) then
            self:Failover("timeout")
        elseif now >= (request.nextSyncAt or 0) then
            ARC.Comms:SendUseSync(request.id, request.attemptID,
                request.leaseToken, request.targetKey, request.spellID,
                math.max(0, request.deadline - now))
            request.nextSyncAt = now + ARC.Constants.USE_SYNC_INTERVAL
        end
    end

    local incoming = self.incoming
    if incoming then
        local selfKey = ARC.Roster:GetPlayer()
        local player = ARC.State.players[selfKey]
        if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
            self:RejectIncoming("DEAD")
        elseif not player or not player.spells or not player.spells[incoming.spellID] then
            self:RejectIncoming("UNAVAILABLE")
        elseif incoming.requesterKey ~= selfKey
            and now - (incoming.lastSyncAt or incoming.receivedAt or 0)
                > ARC.Constants.USE_SYNC_TIMEOUT then
            self:ClearIncoming()
        elseif now >= incoming.deadline then
            self:RejectIncoming("TIMEOUT")
        else
            self:UpdateAlert(now)
        end
    end
end

function Requests:CreateAlert()
    local frame = ARC.AlertUI:CreateAlertFrame("ActuallyARCRequestAlertFrame")
    self.alert = frame
end

function Requests:ShowAlert()
    local incoming = self.incoming
    if not incoming or not self.alert then return end
    self.alert.icon:SetTexture(ARC.SpellInfo:ResolveSpellIcon(incoming.spellID))
    self.alert.heading:SetText("USE "
        .. string.upper(ARC.SpellInfo:ResolveSpellName(incoming.spellID)) .. " NOW")
    self.alert.detail:SetText("")
    self.alert.arcDeadline = incoming.deadline
    self:UpdateAlert(ARC:Now())
    self.alert:Show()
    ARC.AlertUI:PlaySound()
end

function Requests:UpdateAlert(now)
    if not self.incoming or not self.alert then return end
    self.alert.arcDeadline = self.incoming.deadline
    self.alert.timer:SetText(tostring(math.max(0, math.ceil(self.incoming.deadline - now)))
        .. " SEC TO RESPOND")
end
