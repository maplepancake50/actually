local ARC = Actually.Modules.RaidCooldowns
local Bundles = ARC:NewModule("Bundles")

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

local function shortName(value)
    local name = type(value) == "table" and value.name or value
    name = tostring(name or "Unknown")
    return string.match(name, "^[^-]+") or name
end

local function activeIncomingCount(incoming)
    local count = 0
    for _ in pairs(incoming or {}) do count = count + 1 end
    return count
end

local function refreshConfig()
    if ARC.BundleConfig and ARC.BundleConfig.frame and ARC.BundleConfig.frame:IsShown() then
        ARC.BundleConfig:Refresh()
    end
end

function Bundles:Initialize()
    self.active = nil
    self.incoming = {}
    self.incomingOrder = {}
    self.activeIncomingID = nil
    self.incomingLastSyncAt = nil
    self.nextSyncAt = 0
    self.counter = 0
    self.remoteSequences = {}
    local okAlert, alertReason = pcall(self.CreateAlert, self)
    if not okAlert then
        self.alert = nil
        ARC:Print("bundle alert unavailable: " .. tostring(alertReason))
    end
    local okSummary, summaryReason = pcall(self.CreateOfficerSummary, self)
    if not okSummary then
        self.officerSummary = nil
        ARC:Print("bundle summary unavailable: " .. tostring(summaryReason))
    end
    self.initialized = true
end

function Bundles:AcceptSequence(identity, session, sequence)
    self.remoteSequences = self.remoteSequences or {}
    local previous = self.remoteSequences[identity.key]
    if previous and previous.session == session and sequence <= previous.sequence then return false end
    self.remoteSequences[identity.key] = { session = session, sequence = sequence }
    return true
end

function Bundles:NextBundleID()
    self.counter = self.counter + 1
    return tostring(ARC.Comms.session) .. ":B:" .. tostring(self.counter)
end

function Bundles:Start(name, spellIDs, leaseReady, startedCallback)
    if not ARC:RequireCommandAuthority() then return false end
    if not ARC.Roster:IsGrouped() then
        ARC:Print("join a party or raid before requesting a cooldown bundle")
        return false
    end
    if self.active then
        ARC:Print("a cooldown bundle is already active")
        return false
    end
    if ARC.Requests.outgoing then
        ARC:Print("cancel the active single cooldown request before starting a bundle")
        return false
    end
    if not leaseReady and not ARC.Automation:HasLocalLease() then
        return ARC.Automation:Acquire(function()
            Bundles:Start(name, spellIDs, true, startedCallback)
        end)
    end

    local unique, ordered = {}, {}
    for _, rawID in ipairs(spellIDs or {}) do
        local spellID = ARC.Registry:Canonicalize(rawID)
        if spellID and not unique[spellID] then
            unique[spellID] = true
            table.insert(ordered, spellID)
        end
    end
    if table.getn(ordered) == 0 then ARC:Print("bundle has no valid spells") return false end
    if table.getn(ordered) > ARC.Constants.MAX_BUNDLE_SPELLS then
        ARC:Print("bundle rejected: maximum "
            .. tostring(ARC.Constants.MAX_BUNDLE_SPELLS) .. " cooldowns")
        return false
    end

    local bundle = {
        id = self:NextBundleID(),
        name = tostring(name or "Cooldown Bundle"),
        createdAt = ARC:Now(),
        spellIDs = ordered,
        items = {},
        completed = 0,
        failed = 0,
        leaseToken = ARC.Automation:GetLeaseToken(),
    }
    self.active = bundle
    self.nextSyncAt = 0
    local planned = ARC.Automation:PlanSpells(ordered)
    for index, spellID in ipairs(ordered) do
        local item = {
            id = bundle.id .. ":" .. tostring(index),
            order = index,
            spellID = spellID,
            attempted = {},
            timeout = ARC.Requests:GetTimeout(),
            status = "PENDING",
            attemptCounter = 0,
            history = {},
        }
        bundle.items[item.id] = item
        local candidate = planned[index]
        if candidate then
            self:Assign(item, candidate)
        else
            item.status = "FAILED"
            bundle.failed = bundle.failed + 1
            ARC:Print(bundle.name .. ": nobody has "
                .. ARC.SpellInfo:ResolveSpellName(spellID) .. " ready")
        end
    end
    ARC:Print("started bundle " .. bundle.name .. " with "
        .. tostring(table.getn(ordered)) .. " cooldowns")
    self:ShowOfficerSummary(bundle)
    self:CheckFinished()
    ARC.Renderer:MarkDirty("bundle started")
    ARC.Renderer:Reconcile()
    refreshConfig()
    if startedCallback then startedCallback(self.active ~= nil, self.active) end
    return self.active ~= nil
end

function Bundles:Assign(item, playerKey)
    local bundle = self.active
    if not bundle or not item then return false end
    item.targetKey = playerKey
    item.attempted[playerKey] = true
    item.attemptCounter = (item.attemptCounter or 0) + 1
    item.attemptID = item.id .. ":A:" .. tostring(item.attemptCounter)
    item.assignedAt = ARC:Now()
    local assignedSpell = ARC.State.players[playerKey]
        and ARC.State.players[playerKey].spells[item.spellID]
    item.assignedCharges = assignedSpell and assignedSpell.charges
    item.deadline = item.assignedAt + item.timeout
    local ahead = 0
    for _, other in pairs(bundle.items) do
        if other ~= item and other.targetKey == playerKey
            and other.status ~= "DONE" and other.status ~= "FAILED" then
            ahead = ahead + 1
        end
    end
    item.queueDeadline = item.assignedAt + item.timeout * (ahead + 1) + 3
    item.status = "SENT"
    ARC.Automation:Reserve(item.attemptID, ARC.Roster:GetPlayer(), playerKey,
        item.spellID, item.queueDeadline + ARC.Constants.BUNDLE_SYNC_TIMEOUT, "bundle")
    ARC.Renderer:MarkDirty("bundle assignment")
    local selfKey, selfIdentity = ARC.Roster:GetPlayer()
    if playerKey == selfKey then
        self:OnRemoteRequest(selfIdentity, ARC.Comms.session, ARC.Comms:NextSequence(),
            bundle.id, bundle.name, item.id, item.attemptID, bundle.leaseToken,
            playerKey, item.spellID, item.timeout, item.order)
    else
        ARC.Comms:SendBundleRequest(bundle.id, bundle.name, item.id, item.attemptID,
            bundle.leaseToken, playerKey, item.spellID, item.timeout, item.order)
    end
    return true
end

function Bundles:CancelAssignment(item)
    if not item or not item.targetKey then return end
    local selfKey = ARC.Roster:GetPlayer()
    if item.targetKey == selfKey then
        if self.incoming[item.id]
            and self.incoming[item.id].attemptID == item.attemptID then
            self:RemoveIncoming(item.id)
        end
    else
        local bundle = self.active
        ARC.Comms:SendBundleCancel(item.id, item.attemptID,
            bundle and bundle.leaseToken, item.targetKey)
    end
    ARC.Automation:Release(item.attemptID)
end

function Bundles:Failover(item, reason)
    local bundle = self.active
    if not bundle or not item or item.status == "DONE" or item.status == "FAILED" then return end
    local oldTarget = item.targetKey
    item.history[oldTarget] = {
        attemptID = item.attemptID,
        expiresAt = ARC:Now() + ARC.Constants.LATE_CAST_GRACE,
    }
    self:CancelAssignment(item)
    ARC.Automation:RecordFailure(oldTarget, item.spellID, reason)
    local candidate = ARC.Requests:FindCandidate(item.spellID, nil, item.attempted)
    if candidate and ARC.db.profile.requests.autoFailover ~= false then
        ARC:Print(bundle.name .. ": " .. shortName(ARC.State.players[oldTarget])
            .. " skipped for " .. ARC.SpellInfo:ResolveSpellName(item.spellID)
            .. " (" .. tostring(reason) .. ")")
        self:Assign(item, candidate)
    else
        item.status = "FAILED"
        bundle.failed = bundle.failed + 1
        ARC.Renderer:MarkDirty("bundle item failed")
        ARC:Print(bundle.name .. ": " .. ARC.SpellInfo:ResolveSpellName(item.spellID)
            .. " failed (" .. tostring(reason) .. ")")
        self:CheckFinished()
    end
end

function Bundles:Complete(item, source, playerKey)
    local bundle = self.active
    if not bundle or not item or item.status == "DONE" or item.status == "FAILED" then
        return false
    end
    -- Observed cooldowns may complete a queued item before its prompt appears.
    -- Remove that assignment from the recipient's queue as well.
    item.completedBy = playerKey or item.targetKey
    self:CancelAssignment(item)
    ARC.Automation:RecordSuccess(item.completedBy, item.spellID)
    item.status = "DONE"
    item.deadline = nil
    bundle.completed = bundle.completed + 1
    ARC.Renderer:MarkDirty("bundle item complete")
    ARC:Print(bundle.name .. ": " .. shortName(ARC.State.players[item.completedBy or item.targetKey])
        .. " used " .. ARC.SpellInfo:ResolveSpellName(item.spellID)
        .. (source and " (" .. tostring(source) .. ")" or ""))
    self:CheckFinished()
    return true
end

function Bundles:CheckFinished()
    local bundle = self.active
    if not bundle then return end
    for _, item in pairs(bundle.items) do
        if item.status ~= "DONE" and item.status ~= "FAILED" then return end
    end
    ARC:Print("bundle " .. bundle.name .. " finished: "
        .. tostring(bundle.completed) .. " used, " .. tostring(bundle.failed) .. " failed")
    if ARC.Commander and ARC.Commander.OnBundleFinished then
        ARC.Commander:OnBundleFinished(bundle)
    end
    ARC.Comms:SendBundleEnd(bundle.id, bundle.leaseToken)
    self.active = nil
    self.nextSyncAt = nil
    ARC.Renderer:MarkDirty("bundle complete")
    ARC.Renderer:Reconcile()
    refreshConfig()
end

function Bundles:CancelActive(reason, leaseLost)
    local bundle = self.active
    if not bundle then return false end
    local selfKey = ARC.Roster:GetPlayer()
    for _, item in pairs(bundle.items) do
        if item.status ~= "DONE" and item.status ~= "FAILED"
            and item.targetKey ~= selfKey then
            ARC.Comms:SendBundleCancel(item.id, item.attemptID,
                bundle.leaseToken, item.targetKey)
        end
        ARC.Automation:Release(item.attemptID)
    end
    if self.incomingBundleID == bundle.id then
        self.incoming = {}
        self.incomingOrder = {}
        self.activeIncomingID = nil
        self.incomingBundleID = nil
        self.incomingRequesterKey = nil
        self.incomingLastSyncAt = nil
        if self.alert then self.alert:Hide() end
    end
    if ARC.Commander and ARC.Commander.OnBundleCancelled then
        ARC.Commander:OnBundleCancelled(bundle)
    end
    self.active = nil
    self.nextSyncAt = nil
    ARC.Comms:SendBundleEnd(bundle.id, bundle.leaseToken)
    ARC:Print("bundle cancelled" .. (reason and ": " .. tostring(reason) or ""))
    ARC.Renderer:MarkDirty("bundle cancelled")
    ARC.Renderer:Reconcile()
    refreshConfig()
    if not leaseLost then ARC.Automation:ReleaseLease() end
    return true
end

function Bundles:GetAssignment(playerKey, spellID)
    local bundle = self.active
    if not bundle then return nil end
    for _, item in pairs(bundle.items) do
        if item.targetKey == playerKey and item.spellID == spellID
            and item.status ~= "DONE" and item.status ~= "FAILED" then return item end
    end
end

function Bundles:SendStatus(incoming, status)
    if not incoming then return false end
    local selfKey, selfIdentity = ARC.Roster:GetPlayer()
    if incoming.requesterKey == selfKey then
        self:OnRemoteStatus(selfIdentity, ARC.Comms.session, ARC.Comms:NextSequence(),
            incoming.bundleID, incoming.itemID, incoming.attemptID,
            incoming.leaseToken, status, incoming.spellID)
        return true
    end
    return ARC.Comms:SendBundleStatus(incoming.bundleID, incoming.itemID,
        incoming.attemptID, incoming.leaseToken, status, incoming.spellID)
end

function Bundles:RemoveFromIncomingOrder(itemID)
    self.incomingOrder = self.incomingOrder or {}
    for index = table.getn(self.incomingOrder), 1, -1 do
        if self.incomingOrder[index] == itemID then table.remove(self.incomingOrder, index) end
    end
end

function Bundles:ActivateIncoming(itemID, playSound)
    local incoming = self.incoming[itemID]
    if not incoming then return false end
    local selfKey = ARC.Roster:GetPlayer()
    local eligible, reason = ARC.Requests:IsEligible(selfKey, incoming.spellID)
    if not eligible then
        local player = ARC.State.players[selfKey]
        self:RemoveIncoming(itemID, true)
        self:SendStatus(incoming, player and player.dead and "DEAD" or "UNAVAILABLE")
        ARC:Debug("skipped queued bundle item locally: " .. tostring(reason))
        return false
    end

    self.activeIncomingID = itemID
    incoming.state = "ACTIVE"
    incoming.deadline = ARC:Now() + incoming.timeout
    self:SendStatus(incoming, "ACTIVE")
    self:RefreshAlert(playSound)
    return true
end

function Bundles:ActivateNext()
    self.activeIncomingID = nil
    self.incomingOrder = self.incomingOrder or {}
    while true do
        local nextID
        for _, itemID in ipairs(self.incomingOrder) do
            local incoming = self.incoming[itemID]
            if incoming and incoming.state == "QUEUED" then
                nextID = itemID
                break
            end
        end
        if not nextID then
            if activeIncomingCount(self.incoming) == 0 then
                self.incomingBundleID = nil
                self.incomingRequesterKey = nil
                self.incomingLastSyncAt = nil
            end
            if self.alert then self.alert:Hide() end
            return false
        end
        if self:ActivateIncoming(nextID, true) then return true end
    end
end

function Bundles:RemoveIncoming(itemID, suppressPromotion)
    local removed = self.incoming[itemID]
    local wasActive = self.activeIncomingID == itemID
    self.incoming[itemID] = nil
    if removed then ARC.Automation:Release(removed.attemptID) end
    self:RemoveFromIncomingOrder(itemID)
    if wasActive then self.activeIncomingID = nil end
    if activeIncomingCount(self.incoming) == 0 then
        self.incomingBundleID = nil
        self.incomingRequesterKey = nil
        self.incomingLastSyncAt = nil
        if self.alert then self.alert:Hide() end
    elseif wasActive and not suppressPromotion then
        self:ActivateNext()
    elseif self.activeIncomingID then
        self:RefreshAlert(false)
    else
        if self.alert then self.alert:Hide() end
    end
    return wasActive
end

function Bundles:RejectIncoming(itemID, status)
    local incoming = self.incoming[itemID]
    if not incoming then return end
    local wasActive = self:RemoveIncoming(itemID, true)
    self:SendStatus(incoming, status or "DECLINED")
    if wasActive then self:ActivateNext() end
end

function Bundles:RejectAll(status)
    local pending = {}
    for _, incoming in pairs(self.incoming) do table.insert(pending, incoming) end
    self.incoming = {}
    self.incomingOrder = {}
    self.activeIncomingID = nil
    self.incomingBundleID = nil
    self.incomingRequesterKey = nil
    self.incomingLastSyncAt = nil
    if self.alert then self.alert:Hide() end
    for _, incoming in ipairs(pending) do
        ARC.Automation:Release(incoming.attemptID)
        self:SendStatus(incoming, status or "DECLINED")
    end
end

function Bundles:OnRemoteRequest(requester, session, sequence, bundleID, bundleName,
    itemID, attemptID, leaseToken, targetKey, spellID, timeout, order, sequenceAccepted)
    if not sequenceAccepted and not self:AcceptSequence(requester, session, sequence) then return end
    if not ARC.Automation:AcceptLease(requester, leaseToken) then
        ARC:Debug("rejected bundle request from non-coordinator " .. tostring(requester.name))
        return
    end
    ARC.Automation:Reserve(attemptID, requester.key, targetKey, spellID,
        ARC:Now() + timeout + ARC.Constants.BUNDLE_SYNC_TIMEOUT, "bundle")
    local selfKey = ARC.Roster:GetPlayer()
    if targetKey ~= selfKey then return end
    local existing = self.incoming[itemID]
    if existing and existing.attemptID == attemptID then
        existing.lastSyncAt = ARC:Now()
        self.incomingLastSyncAt = ARC:Now()
        self:SendStatus(existing, existing.state == "ACTIVE" and "ACTIVE" or "QUEUED")
        return
    elseif existing then
        self:RemoveIncoming(itemID)
    end
    if ARC.Requests.incoming
        or (self.incomingBundleID and (self.incomingBundleID ~= bundleID
            or self.incomingRequesterKey ~= requester.key)) then
        ARC.Comms:SendBundleStatus(bundleID, itemID, attemptID, leaseToken,
            "BUSY", spellID)
        return
    end
    if activeIncomingCount(self.incoming) >= ARC.Constants.MAX_BUNDLE_SPELLS
        or not self.alert then
        ARC.Comms:SendBundleStatus(bundleID, itemID, attemptID, leaseToken,
            "BUSY", spellID)
        return
    end
    local eligible, reason = ARC.Requests:IsEligible(selfKey, spellID)
    if not eligible then
        local player = ARC.State.players[selfKey]
        ARC.Comms:SendBundleStatus(bundleID, itemID, attemptID, leaseToken,
            player and player.dead and "DEAD" or "UNAVAILABLE", spellID)
        ARC:Debug("declined bundle item locally: " .. tostring(reason))
        return
    end

    self.incomingBundleID = bundleID
    self.incomingRequesterKey = requester.key
    self.incomingLastSyncAt = ARC:Now()
    local incoming = {
        bundleID = bundleID,
        bundleName = bundleName,
        itemID = itemID,
        attemptID = attemptID,
        leaseToken = leaseToken,
        requesterKey = requester.key,
        requesterName = shortName(requester),
        spellID = spellID,
        timeout = math.max(3, math.min(timeout, 30)),
        order = tonumber(order) or 1,
        state = "QUEUED",
        lastSyncAt = ARC:Now(),
    }
    self.incoming[itemID] = incoming
    self.incomingOrder = self.incomingOrder or {}
    table.insert(self.incomingOrder, itemID)
    table.sort(self.incomingOrder, function(leftID, rightID)
        local left, right = self.incoming[leftID], self.incoming[rightID]
        return (left and left.order or 1) < (right and right.order or 1)
    end)
    if not self.activeIncomingID then
        self:ActivateIncoming(itemID, true)
    else
        self:SendStatus(incoming, "QUEUED")
    end
end

function Bundles:OnRemoteStatus(identity, session, sequence, bundleID, itemID,
    attemptID, leaseToken, status, spellID)
    if not self:AcceptSequence(identity, session, sequence) then return end
    local bundle = self.active
    local item = bundle and bundle.id == bundleID and bundle.items[itemID]
    if not item or item.spellID ~= spellID or bundle.leaseToken ~= leaseToken then return end
    local prior = item.history and item.history[identity.key]
    local current = item.targetKey == identity.key and item.attemptID == attemptID
    local oldCast = status == "CAST" and prior and prior.attemptID == attemptID
        and (prior.expiresAt or 0) >= ARC:Now()
    if not current and not oldCast then return end
    if item.status == "DONE" or item.status == "FAILED" then return end
    if status == "QUEUED" then
        item.status = "QUEUED"
        ARC.Renderer:MarkDirty("bundle queued")
    elseif status == "ACTIVE" or status == "ACK" then
        local wasActive = item.status == "ACTIVE"
        item.status = "ACTIVE"
        if not wasActive then item.deadline = ARC:Now() + item.timeout end
        ARC.Renderer:MarkDirty("bundle prompt active")
    elseif status == "CAST" then
        self:Complete(item, "confirmed", identity.key)
    elseif FAILURE_STATUSES[status] then
        self:Failover(item, string.lower(status))
    end
end

function Bundles:OnRemoteCancel(requester, session, sequence, itemID, attemptID,
    leaseToken, targetKey)
    if not self:AcceptSequence(requester, session, sequence) then return end
    if not ARC.Automation:AcceptLease(requester, leaseToken) then return end
    ARC.Automation:Release(attemptID)
    local selfKey = ARC.Roster:GetPlayer()
    if targetKey == selfKey and self.incoming[itemID]
        and self.incoming[itemID].attemptID == attemptID then self:RemoveIncoming(itemID) end
end

function Bundles:OnRemoteSync(requester, session, sequence, bundleID, bundleName,
    leaseToken, rows)
    if not self:AcceptSequence(requester, session, sequence) then return end
    if not ARC.Automation:AcceptLease(requester, leaseToken) then return end
    local now = ARC:Now()
    local selfKey = ARC.Roster:GetPlayer()
    local validSelf = {}
    local validAttempts = {}
    for _, row in ipairs(rows or {}) do
        local itemID, attemptID, targetKey, spellID, remaining =
            row.itemID, row.attemptID, row.targetKey, row.spellID, row.remaining
        ARC.Automation:Reserve(attemptID, requester.key, targetKey, spellID,
            now + remaining + ARC.Constants.BUNDLE_SYNC_TIMEOUT, "bundle")
        validAttempts[attemptID] = true
        if targetKey == selfKey and remaining > 0 then
            validSelf[itemID] = attemptID
            local incoming = self.incoming[itemID]
            if incoming and incoming.attemptID == attemptID then
                incoming.lastSyncAt = now
                self:SendStatus(incoming,
                    incoming.state == "ACTIVE" and "ACTIVE" or "QUEUED")
            else
                self:OnRemoteRequest(requester, session, sequence, bundleID, bundleName,
                    itemID, attemptID, leaseToken, targetKey, spellID, remaining,
                    row.order, true)
            end
        end
    end
    ARC.Automation:ReleasePrefix(bundleID .. ":", requester.key, validAttempts)
    local remove = {}
    for itemID, incoming in pairs(self.incoming) do
        if incoming.bundleID == bundleID and incoming.requesterKey == requester.key
            and validSelf[itemID] ~= incoming.attemptID then
            table.insert(remove, itemID)
        end
    end
    for _, itemID in ipairs(remove) do self:RemoveIncoming(itemID) end
    if next(validSelf) then
        self.incomingLastSyncAt = now
    end
end

function Bundles:OnRemoteEnd(requester, session, sequence, bundleID, leaseToken)
    if not self:AcceptSequence(requester, session, sequence) then return end
    if not ARC.Automation:AcceptLease(requester, leaseToken) then return end
    ARC.Automation:ReleasePrefix(bundleID .. ":", requester.key)
    if self.incomingBundleID == bundleID
        and self.incomingRequesterKey == requester.key then self:RejectAll("UNAVAILABLE") end
end

function Bundles:OnLocalCast(spellID)
    local ids = {}
    for itemID, incoming in pairs(self.incoming) do
        if incoming.spellID == spellID then table.insert(ids, itemID) end
    end
    for _, itemID in ipairs(ids) do
        local incoming = self.incoming[itemID]
        if incoming then
            local wasActive = self:RemoveIncoming(itemID, true)
            self:SendStatus(incoming, "CAST")
            if wasActive then self:ActivateNext() end
        end
    end
end

function Bundles:OnReportedCast(playerKey, spellID)
    local item = self:GetAssignment(playerKey, spellID)
    if item then self:Complete(item, "observed", playerKey) return end
    local bundle = self.active
    for _, candidate in pairs(bundle and bundle.items or {}) do
        local prior = candidate.history and candidate.history[playerKey]
        if candidate.spellID == spellID and candidate.status ~= "DONE"
            and candidate.status ~= "FAILED" and prior
            and (prior.expiresAt or 0) >= ARC:Now() then
            self:Complete(candidate, "late fallback cast", playerKey)
            return
        end
    end
end

function Bundles:OnRosterChanged()
    if not self.initialized then return end
    if self.incomingRequesterKey then
        local requester = ARC.Roster.byKey[self.incomingRequesterKey]
        if not requester or not ARC.Roster:IsCoordinator(requester) then self:RejectAll("UNAVAILABLE") end
    end
    self:OnUpdate(ARC:Now())
end

function Bundles:OnPlayerDeath()
    if activeIncomingCount(self.incoming) > 0 then self:RejectAll("DEAD") end
end

function Bundles:BuildSyncRows()
    local rows = {}
    local bundle = self.active
    for _, item in pairs(bundle and bundle.items or {}) do
        if item.status ~= "DONE" and item.status ~= "FAILED" and item.targetKey then
            table.insert(rows, {
                item.id,
                item.attemptID,
                item.targetKey,
                item.spellID,
                math.floor(item.timeout * 10 + 0.5),
                item.order or 1,
            })
        end
    end
    table.sort(rows, function(left, right) return (left[6] or 1) < (right[6] or 1) end)
    return rows
end

function Bundles:OnUpdate(now)
    if not self.initialized then return end
    local selfKey = ARC.Roster:GetPlayer()
    local bundle = self.active
    if bundle then
        if not ARC.Roster:IsLocalCoordinator() then
            self:CancelActive("coordinator authority lost")
        else
            if now >= (self.nextSyncAt or 0) then
                ARC.Comms:SendBundleSync(bundle.id, bundle.name, bundle.leaseToken,
                    self:BuildSyncRows())
                self.nextSyncAt = now + ARC.Constants.BUNDLE_SYNC_INTERVAL
            end
            if self.incomingBundleID == bundle.id and self.incomingRequesterKey == selfKey then
                self.incomingLastSyncAt = now
            end
            local ids = {}
            for itemID in pairs(bundle.items) do table.insert(ids, itemID) end
            for _, itemID in ipairs(ids) do
                local item = self.active and self.active.items[itemID]
                if item and item.status ~= "DONE" and item.status ~= "FAILED" then
                    local target = ARC.State.players[item.targetKey]
                    if not target or target.connected == false then
                        self:Failover(item, "offline")
                    elseif target.dead then
                        self:Failover(item, "dead")
                    elseif target.stale then
                        self:Failover(item, "stale report")
                    elseif not target.spells or not target.spells[item.spellID] then
                        self:Failover(item, "spell unavailable")
                    elseif ARC.Automation:WasUsedAfterAssignment(target.spells[item.spellID],
                        item.assignedAt, item.assignedCharges) then
                        self:Complete(item, "cooldown detected")
                    elseif item.status == "QUEUED" and item.queueDeadline
                        and now >= item.queueDeadline then
                        self:Failover(item, "queue timeout")
                    elseif item.status ~= "QUEUED" and item.deadline and now >= item.deadline then
                        self:Failover(item, "timeout")
                    end
                end
            end
        end
    end

    local player = ARC.State.players[selfKey]
    if activeIncomingCount(self.incoming) > 0 and self.incomingRequesterKey ~= selfKey
        and now - (self.incomingLastSyncAt or 0) > ARC.Constants.BUNDLE_SYNC_TIMEOUT then
        ARC:Debug("cleared stale bundle queue after coordinator heartbeat expired")
        self:RejectAll("UNAVAILABLE")
    elseif activeIncomingCount(self.incoming) > 0
        and UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
        self:RejectAll("DEAD")
    else
        local unavailable = {}
        for itemID, incoming in pairs(self.incoming) do
            if not player or not player.spells or not player.spells[incoming.spellID] then
                table.insert(unavailable, itemID)
            end
        end
        for _, itemID in ipairs(unavailable) do self:RejectIncoming(itemID, "UNAVAILABLE") end
        local active = self.activeIncomingID and self.incoming[self.activeIncomingID]
        if active and active.deadline and now >= active.deadline then
            self:RejectIncoming(active.itemID, "TIMEOUT")
        end
    end
    if self.activeIncomingID then self:UpdateAlert(now) end
end

function Bundles:CreateAlert()
    local frame = ARC.AlertUI:CreateAlertFrame("ActuallyARCBundleAlertFrame")
    self.alert = frame
end

function Bundles:CreateOfficerSummary()
    local profile = ARC.db.profile.bundleSummaryUI
    local frame = CreateFrame("Frame", "ActuallyARCBundleSummaryFrame", UIParent)
    frame:SetWidth(370)
    frame:SetHeight(150)
    frame:SetPoint(profile.point or "TOP", UIParent, profile.point or "TOP",
        profile.x or 0, profile.y or -180)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        profile.point, profile.x, profile.y = point, x, y
    end)
    setBackdrop(frame, { 0.020, 0.035, 0.050, 0.96 }, { 0.20, 0.76, 1.00, 1 })

    frame.heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.heading:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
    frame.heading:SetText("COOLDOWN BUNDLE REQUESTED")
    frame.heading:SetTextColor(0.32, 0.86, 1.00)

    frame.wip = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.wip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 9)
    frame.wip:SetText(ARC.Constants.WIP_TEXT)

    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    frame.bundleName = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.bundleName:SetPoint("TOPLEFT", frame.heading, "BOTTOMLEFT", 0, -5)
    frame.bundleName:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    frame.bundleName:SetJustifyH("LEFT")

    frame.spells = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.spells:SetPoint("TOPLEFT", frame.bundleName, "BOTTOMLEFT", 0, -9)
    frame.spells:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    frame.spells:SetJustifyH("LEFT")
    frame.spells:SetJustifyV("TOP")

    frame:Hide()
    self.officerSummary = frame
end

function Bundles:PlayAlertSound()
    local now = ARC:Now()
    if self.lastAlertSound and now - self.lastAlertSound <= 1 then return false end
    self.lastAlertSound = now
    return ARC.AlertUI:PlaySound()
end

function Bundles:PlayFailureSound()
    local now = ARC:Now()
    if self.lastAlertSound and now - self.lastAlertSound <= 1 then return false end
    self.lastAlertSound = now
    if not ARC.AlertUI:IsSoundEnabled() then return false end
    if PlaySound then PlaySound("igQuestFailed")
    elseif PlaySoundFile then PlaySoundFile("Sound\\Interface\\Error.wav") end
    return true
end

function Bundles:ShowOfficerSummary(bundle)
    local frame = self.officerSummary
    if not frame or not bundle then return end
    local lines, assigned = {}, 0
    for _, spellID in ipairs(bundle.spellIDs or {}) do
        local item
        for _, candidate in pairs(bundle.items or {}) do
            if candidate.spellID == spellID then item = candidate break end
        end
        local icon = ARC.SpellInfo:ResolveSpellIcon(spellID)
        local prefix = icon and ("|T" .. tostring(icon) .. ":16:16:0:0|t ") or ""
        if item and item.targetKey and item.status ~= "FAILED" then
            assigned = assigned + 1
            local target = ARC.State.players[item.targetKey]
                or (ARC.Roster.byKey and ARC.Roster.byKey[item.targetKey])
            table.insert(lines, prefix .. ARC.SpellInfo:ResolveSpellName(spellID)
                .. "  |cff66ff88-> " .. shortName(target) .. "|r")
        else
            table.insert(lines, prefix .. ARC.SpellInfo:ResolveSpellName(spellID)
                .. "  |cffff5555NOT SENT - no ready owner|r")
        end
    end
    local total = table.getn(lines)
    if assigned == 0 then
        frame.heading:SetText("BUNDLE NOT SENT")
        frame.heading:SetTextColor(1.00, 0.28, 0.28)
        frame:SetBackdropBorderColor(0.85, 0.16, 0.16, 1)
    elseif assigned < total then
        frame.heading:SetText("BUNDLE PARTIALLY REQUESTED")
        frame.heading:SetTextColor(1.00, 0.76, 0.20)
        frame:SetBackdropBorderColor(0.90, 0.58, 0.12, 1)
    else
        frame.heading:SetText("COOLDOWN BUNDLE REQUESTED")
        frame.heading:SetTextColor(0.32, 0.86, 1.00)
        frame:SetBackdropBorderColor(0.20, 0.76, 1.00, 1)
    end
    frame.bundleName:SetText(tostring(bundle.name) .. "  |cff7fcfff("
        .. tostring(assigned) .. "/" .. tostring(total) .. " sent)|r")
    frame.spells:SetText(table.concat(lines, "\n"))
    frame:SetHeight(78 + math.max(1, table.getn(lines)) * 18)
    frame:Show()
    if assigned > 0 then self:PlayAlertSound() else self:PlayFailureSound() end

    self.summaryToken = (self.summaryToken or 0) + 1
    local token = self.summaryToken
    ARC:ScheduleTimer(function()
        if Bundles.summaryToken == token and Bundles.officerSummary then
            Bundles.officerSummary:Hide()
        end
    end, 6)
end

function Bundles:RefreshAlert(playSound)
    local incoming = self.activeIncomingID and self.incoming[self.activeIncomingID]
    if not incoming then self.alert:Hide() return end
    local queued = math.max(0, activeIncomingCount(self.incoming) - 1)
    self.alert.icon:SetTexture(ARC.SpellInfo:ResolveSpellIcon(incoming.spellID))
    self.alert.heading:SetText("USE "
        .. string.upper(ARC.SpellInfo:ResolveSpellName(incoming.spellID)) .. " NOW")
    local line = tostring(incoming.bundleName)
    if queued > 0 then
        line = line .. "  |cffaaaaaa(" .. tostring(queued)
            .. (queued == 1 and " more cooldown queued|r" or " more cooldowns queued|r")
            .. ")"
    end
    self.alert.detail:SetText(line)
    self.alert.arcDeadline = incoming.deadline
    self:UpdateAlert(ARC:Now())
    self.alert:Show()

    if playSound then self:PlayAlertSound() end
end

function Bundles:UpdateAlert(now)
    local incoming = self.activeIncomingID and self.incoming[self.activeIncomingID]
    if incoming and incoming.deadline then
        self.alert.arcDeadline = incoming.deadline
        self.alert.timer:SetText(tostring(math.max(0, math.ceil(incoming.deadline - now)))
            .. " SEC TO RESPOND")
    else
        self.alert.arcDeadline = nil
        self.alert.timer:SetText("")
    end
end
