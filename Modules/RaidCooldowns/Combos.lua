local ARC = Actually.Modules.RaidCooldowns
local Combos = ARC:NewModule("Combos")

local FAILURE_STATUSES = {
    DEAD = true,
    OFFLINE = true,
    UNAVAILABLE = true,
    BUSY = true,
    TIMEOUT = true,
}

local function shortName(value)
    local name = type(value) == "table" and value.name or value
    name = tostring(name or "Unknown")
    return string.match(name, "^[^-]+") or name
end

local function clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    return math.max(minimum, math.min(maximum, value))
end

local function tenths(value)
    value = tonumber(value) or 0
    if value >= 0 then return math.floor(value * 10 + 0.5) end
    return math.ceil(value * 10 - 0.5)
end

local function activeCount(values)
    local count = 0
    for _ in pairs(values or {}) do count = count + 1 end
    return count
end

function Combos:Initialize()
    self.active = nil
    self.pendingComboID = nil
    self.pendingStartedAt = nil
    self.incoming = {}
    self.incomingComboID = nil
    self.incomingRequesterKey = nil
    self.incomingLastSyncAt = nil
    self.remoteSequences = {}
    self.counter = 0
    self.alertFrames = {}
    self.nextSyncAt = 0
    self.syncInFlightID = nil
    self.syncSendDeadline = nil
    self.lastAlertSound = -100
    self.lastPreflightRefreshComboID = nil
    self.lastPreflightRefreshAt = nil
    self.initialized = true
end

function Combos:AcceptSequence(identity, session, sequence)
    self.remoteSequences = self.remoteSequences or {}
    local previous = self.remoteSequences[identity.key]
    if previous and previous.session == session and sequence <= previous.sequence then return false end
    self.remoteSequences[identity.key] = { session = session, sequence = sequence }
    return true
end

function Combos:NextComboID()
    self.counter = self.counter + 1
    return tostring(ARC.Comms.session) .. ":C:" .. tostring(self.counter)
end

function Combos:NormalizeActions(rawActions)
    local actions, unique = {}, {}
    for _, raw in ipairs(rawActions or {}) do
        local spellID = ARC.Registry:Canonicalize(type(raw) == "table" and raw.spellID or raw)
        if spellID and not unique[spellID] then
            unique[spellID] = true
            table.insert(actions, {
                spellID = spellID,
                offset = clamp(type(raw) == "table" and raw.offset or 0, -10, 10),
            })
        end
    end
    return actions
end

function Combos:ActionsConflict(left, right)
    if not left or not right then return false end
    return math.abs((tonumber(left.offset) or 0) - (tonumber(right.offset) or 0))
        < (ARC.Constants.COMBO_SAME_PLAYER_MIN_GAP or 1.5)
end

function Combos:IsCandidateTimingCompatible(action, playerKey, ignoredActionID)
    local active = self.active
    if not active then return true end
    for _, otherID in ipairs(active.order or {}) do
        local other = active.actions[otherID]
        if other and other.id ~= (ignoredActionID or action.id)
            and other.targetKey == playerKey
            and other.status ~= "FAILED"
            and self:ActionsConflict(action, other) then
            return false
        end
    end
    return true
end

function Combos:PlanActions(actions)
    actions = actions or {}
    local candidatesByIndex, searchOrder = {}, {}
    for index, action in ipairs(actions) do
        local rows = ARC.Automation:GetCandidates(action.spellID, nil, {}, {})
        candidatesByIndex[index] = rows
        if table.getn(rows) == 0 then
            return nil, index, "no ready player"
        end
        table.insert(searchOrder, index)
    end
    table.sort(searchOrder, function(left, right)
        local leftCount = table.getn(candidatesByIndex[left])
        local rightCount = table.getn(candidatesByIndex[right])
        if leftCount ~= rightCount then return leftCount < rightCount end
        return left < right
    end)

    local planned, assignedByPlayer, simulatedLoad = {}, {}, {}
    local function search(position)
        if position > table.getn(searchOrder) then return true end
        local actionIndex = searchOrder[position]
        local action = actions[actionIndex]
        local choices = {}
        for _, row in ipairs(candidatesByIndex[actionIndex]) do
            table.insert(choices, row)
        end
        table.sort(choices, function(left, right)
            local leftScore = left.score + (simulatedLoad[left.key] or 0) * 100
            local rightScore = right.score + (simulatedLoad[right.key] or 0) * 100
            if leftScore ~= rightScore then return leftScore < rightScore end
            if left.name ~= right.name then return left.name < right.name end
            return tostring(left.key) < tostring(right.key)
        end)

        for _, row in ipairs(choices) do
            local compatible = true
            for _, assignedAction in ipairs(assignedByPlayer[row.key] or {}) do
                if self:ActionsConflict(action, assignedAction) then
                    compatible = false
                    break
                end
            end
            if compatible then
                planned[actionIndex] = row.key
                assignedByPlayer[row.key] = assignedByPlayer[row.key] or {}
                table.insert(assignedByPlayer[row.key], action)
                simulatedLoad[row.key] = (simulatedLoad[row.key] or 0) + 1
                if search(position + 1) then return true end
                simulatedLoad[row.key] = simulatedLoad[row.key] - 1
                table.remove(assignedByPlayer[row.key])
                planned[actionIndex] = nil
            end
        end
        return false
    end

    if not search(1) then return nil, nil, "same-player timing conflict" end
    return planned
end

function Combos:RefreshLocalPreflightState(comboID)
    local now = ARC:Now()
    if self.lastPreflightRefreshComboID == comboID
        and now - (self.lastPreflightRefreshAt or 0) < 0.25 then
        return true
    end
    if not ARC.Spellbook or type(ARC.Spellbook.Scan) ~= "function" then return true end
    local ok, reason = pcall(ARC.Spellbook.Scan, ARC.Spellbook, "combo preflight")
    if not ok then
        ARC:Debug("combo preflight refresh failed: " .. tostring(reason))
        return false
    end
    self.lastPreflightRefreshComboID = comboID
    self.lastPreflightRefreshAt = now
    return true
end

function Combos:Start(definition, leaseReady)
    if type(definition) ~= "table" then return false end
    if not ARC:RequireCommandAuthority() then return false end
    if Actually.FeatureSwitches
        and not Actually.FeatureSwitches:Require("arc_commander", "ARC timed combos") then
        return false
    end
    if not ARC.Roster:IsGrouped() then
        ARC:Print("join a party or raid before starting a timed combo")
        return false
    end
    if self.active or self.pendingComboID then
        ARC:Print("a timed combo is already active")
        return false
    end
    if ARC.Requests.outgoing or ARC.Bundles.active then
        ARC:Print("finish or cancel the active cooldown command before starting a combo")
        return false
    end

    local configuredID = tostring(definition.id or definition.name or "combo")
    if not leaseReady and not ARC.Automation:HasLocalLease() then
        self.pendingComboID = configuredID
        self.pendingStartedAt = ARC:Now()
        local started = ARC.Automation:Acquire(function(acquired, reason)
            Combos.pendingComboID = nil
            Combos.pendingStartedAt = nil
            if acquired then
                Combos:Start(definition, true)
            else
                ARC:Print("timed combo could not start: " .. tostring(reason or "control unavailable"))
            end
        end)
        if not started then
            self.pendingComboID = nil
            self.pendingStartedAt = nil
        end
        return started
    end

    local normalized = self:NormalizeActions(definition.actions)
    if table.getn(normalized) == 0 then
        ARC:Print("timed combo has no valid actions")
        ARC.Automation:ReleaseLease()
        return false
    end
    if table.getn(normalized) > ARC.Constants.MAX_COMBO_ACTIONS then
        ARC:Print("timed combo has too many actions")
        ARC.Automation:ReleaseLease()
        return false
    end

    local leadTime = clamp(definition.leadTime or 5, 2, 15)
    for _, action in ipairs(normalized) do
        if leadTime + action.offset < 1 then
            ARC:Print(ARC.SpellInfo:ResolveSpellName(action.spellID)
                .. " needs at least one second of notice; increase the combo countdown")
            ARC.Automation:ReleaseLease()
            return false
        end
    end

    local active = {
        id = self:NextComboID(),
        definitionID = configuredID,
        name = tostring(definition.name or "Timed Combo"),
        state = "PREFLIGHT",
        leadTime = leadTime,
        createdAt = ARC:Now(),
        leaseToken = ARC.Automation:GetLeaseToken(),
        actions = {},
        order = {},
        completed = 0,
        failed = 0,
    }
    self.active = active
    self.nextSyncAt = 0
    self.syncInFlightID = nil
    self.syncSendDeadline = nil

    local planned, unavailableIndex, planReason = self:PlanActions(normalized)
    if not planned then
        if unavailableIndex then
            ARC:Print(active.name .. ": nobody has "
                .. ARC.SpellInfo:ResolveSpellName(normalized[unavailableIndex].spellID)
                .. " ready")
        else
            ARC:Print(active.name .. ": no safe assignment; one player would need "
                .. "multiple actions within "
                .. string.format("%.1f", ARC.Constants.COMBO_SAME_PLAYER_MIN_GAP or 1.5)
                .. " seconds")
        end
        self:CancelActive("preflight failed: " .. tostring(planReason))
        return false
    end

    for index, configured in ipairs(normalized) do
        local action = {
            id = active.id .. ":" .. tostring(index),
            order = index,
            spellID = configured.spellID,
            offset = configured.offset,
            attempted = {},
            attemptCounter = 0,
            status = "PENDING",
        }
        active.actions[action.id] = action
        table.insert(active.order, action.id)
    end

    active.building = true
    for index, actionID in ipairs(active.order) do
        local action = active.actions[actionID]
        self:AssignPreflight(action, planned[index])
        if not self.active then return false end
    end
    active.building = nil

    ARC:Print("preparing timed combo " .. active.name)
    self:CheckPreflight()
    return self.active ~= nil
end

function Combos:AssignPreflight(action, playerKey)
    local active = self.active
    if not active or active.state ~= "PREFLIGHT" or not action then return false end
    action.targetKey = playerKey
    action.attempted[playerKey] = true
    action.attemptCounter = action.attemptCounter + 1
    action.attemptID = action.id .. ":A:" .. tostring(action.attemptCounter)
    action.preflightRetries = 0
    action.assignedAt = ARC:Now()
    action.preflightDeadline = action.assignedAt + ARC.Constants.COMBO_PREFLIGHT_TIMEOUT
    action.status = "PREPARING"
    ARC.Automation:Reserve(action.attemptID, ARC.Roster:GetPlayer(), playerKey,
        action.spellID, action.preflightDeadline + ARC.Constants.COMBO_SYNC_TIMEOUT, "combo")

    local selfKey, selfIdentity = ARC.Roster:GetPlayer()
    if playerKey == selfKey then
        self:OnRemotePrepare(selfIdentity, ARC.Comms.session, ARC.Comms:NextSequence(),
            active.id, active.name, action.id, action.attemptID, active.leaseToken,
            playerKey, action.spellID, action.offset)
    else
        ARC.Comms:SendComboPrepare(active.id, active.name, action.id, action.attemptID,
            active.leaseToken, playerKey, action.spellID, action.offset)
    end
    return true
end

function Combos:RetryPreflight(action)
    local active = self.active
    if not active or active.state ~= "PREFLIGHT" or not action
        or action.status ~= "PREPARING" then return false end
    action.preflightRetries = (action.preflightRetries or 0) + 1
    action.preflightDeadline = ARC:Now() + ARC.Constants.COMBO_PREFLIGHT_TIMEOUT
    ARC.Automation:Reserve(action.attemptID, ARC.Roster:GetPlayer(), action.targetKey,
        action.spellID, action.preflightDeadline + ARC.Constants.COMBO_SYNC_TIMEOUT, "combo")
    local selfKey, selfIdentity = ARC.Roster:GetPlayer()
    if action.targetKey == selfKey then
        self:OnRemotePrepare(selfIdentity, ARC.Comms.session, ARC.Comms:NextSequence(),
            active.id, active.name, action.id, action.attemptID, active.leaseToken,
            action.targetKey, action.spellID, action.offset)
    else
        ARC.Comms:SendComboPrepare(active.id, active.name, action.id, action.attemptID,
            active.leaseToken, action.targetKey, action.spellID, action.offset)
    end
    ARC:Debug("retried timed combo preflight for "
        .. ARC.SpellInfo:ResolveSpellName(action.spellID))
    return true
end

function Combos:CancelAssignment(action)
    if not action or not action.attemptID then return end
    local active = self.active
    local selfKey = ARC.Roster:GetPlayer()
    if action.targetKey == selfKey then
        self:RemoveIncoming(action.id)
    else
        ARC.Comms:SendComboDrop(active and active.id or "", action.id, action.attemptID,
            active and active.leaseToken, action.targetKey)
    end
    ARC.Automation:Release(action.attemptID)
end

function Combos:PreflightFailover(action, reason)
    local active = self.active
    if not active or active.state ~= "PREFLIGHT" or not action then return false end
    local oldTarget = action.targetKey
    self:CancelAssignment(action)
    ARC.Automation:RecordFailure(oldTarget, action.spellID, reason)
    local candidate = ARC.Automation:FindCandidate(
        action.spellID, nil, action.attempted, nil, function(playerKey)
            return self:IsCandidateTimingCompatible(action, playerKey, action.id)
        end)
    if not candidate then
        ARC:Print(active.name .. ": preflight failed for "
            .. ARC.SpellInfo:ResolveSpellName(action.spellID)
            .. " (" .. tostring(reason) .. "); countdown not started")
        self:CancelActive("preflight failed")
        return false
    end
    ARC:Print(active.name .. ": replacing " .. shortName(ARC.State.players[oldTarget])
        .. " before countdown (" .. tostring(reason) .. ")")
    return self:AssignPreflight(action, candidate)
end

function Combos:CheckPreflight()
    local active = self.active
    if not active or active.state ~= "PREFLIGHT" or active.building then return false end
    for _, actionID in ipairs(active.order) do
        local action = active.actions[actionID]
        if not action or action.status ~= "READY" then return false end
        local eligible, reason = ARC.Requests:IsEligible(action.targetKey, action.spellID)
        if not eligible then
            self:PreflightFailover(action, reason)
            return false
        end
    end
    return self:BeginCountdown()
end

function Combos:BuildRows(active)
    local rows = {}
    for _, actionID in ipairs(active and active.order or {}) do
        local action = active.actions[actionID]
        if action and action.status ~= "DONE" and action.status ~= "FAILED" then
            table.insert(rows, {
                action.id,
                action.attemptID,
                action.targetKey,
                action.spellID,
                tenths(action.offset),
            })
        end
    end
    return rows
end

function Combos:BeginCountdown()
    local active = self.active
    if not active or active.state ~= "PREFLIGHT" then return false end
    local now = ARC:Now()
    active.state = "COUNTDOWN"
    active.goAt = now
    active.anchorAt = now + active.leadTime
    for _, actionID in ipairs(active.order) do
        local action = active.actions[actionID]
        action.status = "COUNTDOWN"
        action.dueAt = active.anchorAt + action.offset
        action.deadline = action.dueAt + ARC.Constants.COMBO_LATE_TOLERANCE
        local spell = ARC.State.players[action.targetKey]
            and ARC.State.players[action.targetKey].spells[action.spellID]
        action.assignedCharges = spell and spell.charges
        if ARC.Activity and ARC.Activity.initialized then
            ARC.Activity:BeginAttempt({
                attemptID = action.attemptID,
                kind = "combo",
                context = active.name,
                contextID = active.id,
                playerKey = action.targetKey,
                spellID = action.spellID,
                startedAt = now,
                promptedAt = now,
                dueAt = action.dueAt,
                deadline = action.deadline,
            })
        end
    end
    self.nextSyncAt = now + ARC.Constants.COMBO_SYNC_INTERVAL
    local rows = self:BuildRows(active)
    ARC.Comms:SendComboGo(active.id, active.name, active.leaseToken,
        active.leadTime, rows)
    local selfKey, selfIdentity = ARC.Roster:GetPlayer()
    self:OnRemoteGo(selfIdentity, ARC.Comms.session, ARC.Comms:NextSequence(),
        active.id, active.name, active.leaseToken, active.leadTime, rows, true)

    local assignments = {}
    for _, actionID in ipairs(active.order) do
        local action = active.actions[actionID]
        table.insert(assignments, ARC.SpellInfo:ResolveSpellName(action.spellID)
            .. " -> " .. shortName(ARC.State.players[action.targetKey])
            .. " (" .. string.format("%+.1fs", action.offset) .. ")")
    end
    ARC:Print(active.name .. " countdown started: " .. table.concat(assignments, ", "))
    return true
end

function Combos:MarkFailed(action, reason)
    local active = self.active
    if not active or active.state ~= "COUNTDOWN" or not action
        or action.status == "DONE" or action.status == "FAILED" then return false end
    local target = action.targetKey
    self:CancelAssignment(action)
    action.status = "FAILED"
    action.failureReason = reason
    active.failed = active.failed + 1
    if ARC.Activity and ARC.Activity.initialized then
        ARC.Activity:FailAttempt(action.attemptID, reason, true)
    end
    ARC.Automation:RecordFailure(target, action.spellID, reason)
    ARC:Print(active.name .. ": " .. ARC.SpellInfo:ResolveSpellName(action.spellID)
        .. " failed for " .. shortName(ARC.State.players[target])
        .. " (" .. tostring(reason) .. "); no mid-countdown replacement")
    self:CheckFinished()
    return true
end

function Combos:Complete(action, source)
    local active = self.active
    if not active or active.state ~= "COUNTDOWN" or not action
        or action.status == "DONE" or action.status == "FAILED" then return false end
    local target = action.targetKey
    self:CancelAssignment(action)
    action.status = "DONE"
    action.completedAt = ARC:Now()
    active.completed = active.completed + 1
    if ARC.Activity and ARC.Activity.initialized then
        ARC.Activity:FinishAttempt(action.attemptID, "ON_TIME", {
            playerKey = target,
            source = source,
            finishedAt = action.completedAt,
        })
    end
    ARC.Automation:RecordSuccess(target, action.spellID)
    ARC:Print(active.name .. ": " .. shortName(ARC.State.players[target])
        .. " used " .. ARC.SpellInfo:ResolveSpellName(action.spellID)
        .. (source and " (" .. tostring(source) .. ")" or ""))
    self:CheckFinished()
    return true
end

function Combos:HandleObservedUse(action, observedAt, source)
    if not action or action.status ~= "COUNTDOWN" then return false end
    observedAt = tonumber(observedAt) or ARC:Now()
    if observedAt < (action.dueAt or 0) - ARC.Constants.COMBO_EARLY_TOLERANCE then
        return self:MarkFailed(action, "used early")
    end
    if observedAt <= (action.deadline or 0) then
        return self:Complete(action, source or "timed cast detected")
    end
    return false
end

function Combos:CheckFinished()
    local active = self.active
    if not active or active.state ~= "COUNTDOWN" then return false end
    for _, actionID in ipairs(active.order) do
        local status = active.actions[actionID] and active.actions[actionID].status
        if status ~= "DONE" and status ~= "FAILED" then return false end
    end
    ARC.Comms:SendComboEnd(active.id, active.leaseToken)
    self:ClearIncomingCombo(active.id)
    ARC:Print("timed combo " .. active.name .. " finished: "
        .. tostring(active.completed) .. " on time, "
        .. tostring(active.failed) .. " failed")
    self.active = nil
    self.syncInFlightID = nil
    self.syncSendDeadline = nil
    ARC.Automation:ReleaseLease()
    return true
end

function Combos:CancelActive(reason, leaseLost)
    local active = self.active
    self.pendingComboID = nil
    self.pendingStartedAt = nil
    if not active then
        if not leaseLost and ARC.Automation then ARC.Automation:ReleaseLease() end
        return false
    end
    for _, actionID in ipairs(active.order or {}) do
        local action = active.actions[actionID]
        if action then
            if action.status ~= "DONE" and action.status ~= "FAILED"
                and ARC.Activity and ARC.Activity.initialized then
                ARC.Activity:CancelAttempt(action.attemptID, reason)
            end
            self:CancelAssignment(action)
        end
    end
    ARC.Comms:SendComboEnd(active.id, active.leaseToken)
    self:ClearIncomingCombo(active.id)
    self.active = nil
    self.syncInFlightID = nil
    self.syncSendDeadline = nil
    ARC:Print("timed combo cancelled" .. (reason and ": " .. tostring(reason) or ""))
    if not leaseLost then ARC.Automation:ReleaseLease() end
    return true
end

function Combos:SendStatus(incoming, status)
    if not incoming then return false end
    local selfKey, selfIdentity = ARC.Roster:GetPlayer()
    if incoming.requesterKey == selfKey then
        self:OnRemoteStatus(selfIdentity, ARC.Comms.session, ARC.Comms:NextSequence(),
            incoming.comboID, incoming.actionID, incoming.attemptID,
            incoming.leaseToken, status, incoming.spellID)
        return true
    end
    return ARC.Comms:SendComboStatus(incoming.comboID, incoming.actionID,
        incoming.attemptID, incoming.leaseToken, status, incoming.spellID)
end

function Combos:SendPrepareStatus(requester, comboID, actionID, attemptID,
    leaseToken, status, spellID)
    local selfKey, selfIdentity = ARC.Roster:GetPlayer()
    if requester and requester.key == selfKey then
        self:OnRemoteStatus(selfIdentity, ARC.Comms.session, ARC.Comms:NextSequence(),
            comboID, actionID, attemptID, leaseToken, status, spellID)
        return true
    end
    return ARC.Comms:SendComboStatus(comboID, actionID, attemptID,
        leaseToken, status, spellID)
end

function Combos:GetAlertFrame(actionID)
    for _, frame in ipairs(self.alertFrames) do
        if not frame.arcComboActionID then
            frame.arcComboActionID = actionID
            return frame
        end
    end
    local index = table.getn(self.alertFrames) + 1
    local frame = ARC.AlertUI:CreateAlertFrame("ActuallyARCComboAlertFrame" .. tostring(index))
    frame.arcComboActionID = actionID
    table.insert(self.alertFrames, frame)
    return frame
end

function Combos:ReleaseAlert(incoming)
    local frame = incoming and incoming.alert
    if not frame then return end
    frame:Hide()
    frame.arcComboActionID = nil
    incoming.alert = nil
end

function Combos:RemoveIncoming(actionID)
    local incoming = self.incoming[actionID]
    if not incoming then return nil end
    self:ReleaseAlert(incoming)
    ARC.Automation:Release(incoming.attemptID)
    self.incoming[actionID] = nil
    if activeCount(self.incoming) == 0 then
        self.incomingComboID = nil
        self.incomingRequesterKey = nil
        self.incomingLastSyncAt = nil
    end
    return incoming
end

function Combos:ClearIncomingCombo(comboID)
    local remove = {}
    for actionID, incoming in pairs(self.incoming) do
        if not comboID or incoming.comboID == comboID then table.insert(remove, actionID) end
    end
    for _, actionID in ipairs(remove) do self:RemoveIncoming(actionID) end
end

function Combos:OnRemotePrepare(requester, session, sequence, comboID, comboName,
    actionID, attemptID, leaseToken, targetKey, spellID, offset, sequenceAccepted)
    if not sequenceAccepted and not self:AcceptSequence(requester, session, sequence) then return end
    if not ARC.Automation:AcceptLease(requester, leaseToken) then return end
    ARC.Automation:Reserve(attemptID, requester.key, targetKey, spellID,
        ARC:Now() + ARC.Constants.COMBO_PREFLIGHT_TIMEOUT
            + ARC.Constants.COMBO_SYNC_TIMEOUT, "combo")
    local selfKey = ARC.Roster:GetPlayer()
    if targetKey ~= selfKey then return end
    if not self:RefreshLocalPreflightState(comboID) then
        self:SendPrepareStatus(requester, comboID, actionID, attemptID,
            leaseToken, "UNAVAILABLE", spellID)
        return
    end

    local existing = self.incoming[actionID]
    if existing and existing.attemptID == attemptID then
        existing.lastSyncAt = ARC:Now()
        self:SendStatus(existing, "READY")
        return
    elseif existing then
        self:RemoveIncoming(actionID)
    end

    if ARC.Requests.incoming or next(ARC.Bundles.incoming or {})
        or (self.incomingComboID and (self.incomingComboID ~= comboID
            or self.incomingRequesterKey ~= requester.key)) then
        self:SendPrepareStatus(requester, comboID, actionID, attemptID,
            leaseToken, "BUSY", spellID)
        return
    end
    local eligible, reason = ARC.Requests:IsEligible(selfKey, spellID)
    if not eligible then
        local player = ARC.State.players[selfKey]
        self:SendPrepareStatus(requester, comboID, actionID, attemptID, leaseToken,
            player and player.dead and "DEAD" or "UNAVAILABLE", spellID)
        ARC:Debug("declined combo preflight locally: " .. tostring(reason))
        return
    end

    self.incomingComboID = comboID
    self.incomingRequesterKey = requester.key
    self.incomingLastSyncAt = ARC:Now()
    local incoming = {
        comboID = comboID,
        comboName = comboName,
        actionID = actionID,
        attemptID = attemptID,
        leaseToken = leaseToken,
        requesterKey = requester.key,
        spellID = spellID,
        offset = offset,
        state = "PREPARED",
        preparedAt = ARC:Now(),
        lastSyncAt = ARC:Now(),
    }
    self.incoming[actionID] = incoming
    self:SendStatus(incoming, "READY")
end

function Combos:OnRemoteStatus(identity, session, sequence, comboID, actionID,
    attemptID, leaseToken, status, spellID)
    if not self:AcceptSequence(identity, session, sequence) then return end
    local active = self.active
    local action = active and active.id == comboID and active.actions[actionID]
    if not action or action.attemptID ~= attemptID or action.targetKey ~= identity.key
        or action.spellID ~= spellID or active.leaseToken ~= leaseToken then return end

    if status == "READY" and active.state == "PREFLIGHT" then
        action.status = "READY"
        action.preflightDeadline = ARC:Now() + ARC.Constants.COMBO_PREFLIGHT_TIMEOUT
        self:CheckPreflight()
    elseif status == "CAST" and active.state == "COUNTDOWN" then
        self:HandleObservedUse(action, ARC:Now(), "confirmed")
    elseif status == "EARLY" and active.state == "COUNTDOWN" then
        self:MarkFailed(action, "used early")
    elseif FAILURE_STATUSES[status] then
        if active.state == "PREFLIGHT" then
            self:PreflightFailover(action, string.lower(status))
        else
            self:MarkFailed(action, string.lower(status))
        end
    end
end

function Combos:OnRemoteDrop(requester, session, sequence, comboID, actionID,
    attemptID, leaseToken, targetKey)
    if not self:AcceptSequence(requester, session, sequence) then return end
    if not ARC.Automation:AcceptLease(requester, leaseToken) then return end
    ARC.Automation:Release(attemptID)
    local selfKey = ARC.Roster:GetPlayer()
    local incoming = self.incoming[actionID]
    if targetKey == selfKey and incoming and incoming.comboID == comboID
        and incoming.attemptID == attemptID then self:RemoveIncoming(actionID) end
end

function Combos:ApplyGoRows(requester, comboID, comboName, leaseToken,
    anchorRemaining, rows)
    local now = ARC:Now()
    local selfKey = ARC.Roster:GetPlayer()
    local validAttempts = {}
    for _, row in ipairs(rows or {}) do
        local actionID = row.actionID or row[1]
        local attemptID = row.attemptID or row[2]
        local targetKey = row.targetKey or row[3]
        local spellID = row.spellID or row[4]
        local offset = row.offset
        if offset == nil then offset = (tonumber(row[5]) or 0) / 10 end
        validAttempts[attemptID] = true
        ARC.Automation:Reserve(attemptID, requester.key, targetKey, spellID,
            now + anchorRemaining + math.max(0, offset)
                + ARC.Constants.COMBO_LATE_TOLERANCE
                + ARC.Constants.COMBO_SYNC_TIMEOUT, "combo")
        if targetKey == selfKey then
            local incoming = self.incoming[actionID]
            if incoming and incoming.attemptID == attemptID then
                incoming.comboName = comboName
                incoming.lastSyncAt = now
                incoming.state = "COUNTDOWN"
                if not incoming.dueAt then
                    incoming.dueAt = now + anchorRemaining + offset
                    incoming.deadline = incoming.dueAt + ARC.Constants.COMBO_LATE_TOLERANCE
                    incoming.alert = self:GetAlertFrame(incoming.actionID)
                    self:RefreshIncomingAlert(incoming, now, true)
                end
            end
        end
    end
    ARC.Automation:ReleasePrefix(comboID .. ":", requester.key, validAttempts)
    local remove = {}
    for actionID, incoming in pairs(self.incoming) do
        if incoming.comboID == comboID and incoming.requesterKey == requester.key
            and not validAttempts[incoming.attemptID] then
            table.insert(remove, actionID)
        end
    end
    for _, actionID in ipairs(remove) do self:RemoveIncoming(actionID) end
    self.incomingLastSyncAt = now
end

function Combos:OnRemoteGo(requester, session, sequence, comboID, comboName,
    leaseToken, leadTime, rows, sequenceAccepted)
    if not sequenceAccepted and not self:AcceptSequence(requester, session, sequence) then return end
    if not ARC.Automation:AcceptLease(requester, leaseToken) then return end
    self:ApplyGoRows(requester, comboID, comboName, leaseToken, leadTime, rows)
end

function Combos:OnRemoteSync(requester, session, sequence, comboID, comboName,
    leaseToken, anchorRemaining, rows)
    if not self:AcceptSequence(requester, session, sequence) then return end
    if not ARC.Automation:AcceptLease(requester, leaseToken) then return end
    self:ApplyGoRows(requester, comboID, comboName, leaseToken, anchorRemaining, rows)
end

function Combos:OnRemoteEnd(requester, session, sequence, comboID, leaseToken)
    if not self:AcceptSequence(requester, session, sequence) then return end
    if not ARC.Automation:AcceptLease(requester, leaseToken) then return end
    ARC.Automation:ReleasePrefix(comboID .. ":", requester.key)
    self:ClearIncomingCombo(comboID)
end

function Combos:OnLocalCast(spellID)
    local now = ARC:Now()
    local ids = {}
    for actionID, incoming in pairs(self.incoming) do
        if incoming.spellID == spellID then table.insert(ids, actionID) end
    end
    for _, actionID in ipairs(ids) do
        local incoming = self.incoming[actionID]
        if incoming then
            if incoming.state == "COUNTDOWN" and incoming.dueAt then
                local status = now < incoming.dueAt - ARC.Constants.COMBO_EARLY_TOLERANCE
                    and "EARLY" or "CAST"
                self:SendStatus(incoming, status)
            else
                self:SendStatus(incoming, "UNAVAILABLE")
            end
            self:RemoveIncoming(actionID)
        end
    end
end

function Combos:OnReportedCast(playerKey, spellID)
    local active = self.active
    if not active or active.state ~= "COUNTDOWN" then return end
    for _, actionID in ipairs(active.order) do
        local action = active.actions[actionID]
        if action.targetKey == playerKey and action.spellID == spellID
            and action.status == "COUNTDOWN" then
            self:HandleObservedUse(action, ARC:Now(), "observed")
            return
        end
    end
end

function Combos:RefreshIncomingAlert(incoming, now, playSound)
    local frame = incoming and incoming.alert
    if not frame or not incoming.dueAt then return end
    local name = string.upper(ARC.SpellInfo:ResolveSpellName(incoming.spellID))
    local remaining = incoming.dueAt - now
    frame.icon:SetTexture(ARC.SpellInfo:ResolveSpellIcon(incoming.spellID))
    frame.detail:SetText(tostring(incoming.comboName))
    frame.arcDeadline = incoming.deadline
    if remaining > 0 then
        frame.heading:SetText(name .. " IN " .. tostring(math.max(1, math.ceil(remaining))))
        frame.timer:SetText(string.format("USE IN %.1f SEC", remaining))
    else
        frame.heading:SetText("USE " .. name .. " NOW")
        frame.timer:SetText(string.format("%.1f SEC WINDOW",
            math.max(0, (incoming.deadline or now) - now)))
        if not incoming.dueSoundPlayed then
            incoming.dueSoundPlayed = true
            self:PlayAlertSound()
        end
    end
    frame:Show()
    if playSound then self:PlayAlertSound() end
end

function Combos:PlayAlertSound()
    local now = ARC:Now()
    if now - (self.lastAlertSound or -100) < 0.20 then return false end
    self.lastAlertSound = now
    return ARC.AlertUI:PlaySound()
end

function Combos:OnPlayerDeath()
    local pending = {}
    for actionID in pairs(self.incoming) do table.insert(pending, actionID) end
    for _, actionID in ipairs(pending) do
        local incoming = self.incoming[actionID]
        if incoming then
            self:SendStatus(incoming, "DEAD")
            self:RemoveIncoming(actionID)
        end
    end
end

function Combos:OnRosterChanged()
    if not self.initialized then return end
    if self.incomingRequesterKey then
        local requester = ARC.Roster.byKey[self.incomingRequesterKey]
        if not requester or not ARC.Roster:IsCoordinator(requester) then
            self:ClearIncomingCombo()
        end
    end
    self:OnUpdate(ARC:Now())
end

function Combos:OnUpdate(now)
    if not self.initialized then return end
    if not self.pendingComboID and not self.active and not next(self.incoming) then return end
    if self.pendingComboID and now - (self.pendingStartedAt or 0)
        > math.max(2, ARC.Constants.LEASE_CLAIM_WINDOW + 1) then
        self.pendingComboID = nil
        self.pendingStartedAt = nil
        if ARC.Automation.AbortProvisionalAcquire then ARC.Automation:AbortProvisionalAcquire() end
        ARC:Print("pending timed combo expired; try again")
    end

    local active = self.active
    if active then
        if not ARC.Roster:IsLocalCoordinator() then
            self:CancelActive("coordinator authority lost")
        elseif active.state == "PREFLIGHT" then
            for _, actionID in ipairs(active.order) do
                local action = self.active and self.active.actions[actionID]
                if action and (action.status == "PREPARING" or action.status == "READY") then
                    local eligible, reason = ARC.Requests:IsEligible(action.targetKey, action.spellID)
                    if not eligible then
                        self:PreflightFailover(action, reason)
                    elseif action.status == "PREPARING"
                        and now >= (action.preflightDeadline or 0) then
                        if (action.preflightRetries or 0)
                            < (ARC.Constants.COMBO_PREFLIGHT_RETRIES or 0) then
                            self:RetryPreflight(action)
                        else
                            self:PreflightFailover(action, "timeout")
                        end
                    end
                end
            end
        elseif active.state == "COUNTDOWN" then
            if self.syncInFlightID == active.id
                and now >= (self.syncSendDeadline or 0) then
                self.syncInFlightID = nil
                self.syncSendDeadline = nil
            end
            if now >= (self.nextSyncAt or 0) and not self.syncInFlightID then
                local comboID = active.id
                self.syncInFlightID = comboID
                self.syncSendDeadline = now + ARC.Constants.COMBO_SYNC_TIMEOUT + 8
                local sent = ARC.Comms:SendComboSync(active.id, active.name,
                    active.leaseToken, math.max(0, active.anchorAt - now),
                    self:BuildRows(active), function()
                        if Combos.syncInFlightID == comboID then
                            Combos.syncInFlightID = nil
                            Combos.syncSendDeadline = nil
                        end
                    end)
                if not sent then
                    self.syncInFlightID = nil
                    self.syncSendDeadline = nil
                end
                self.nextSyncAt = now + ARC.Constants.COMBO_SYNC_INTERVAL
            end
            for _, actionID in ipairs(active.order) do
                local action = self.active and self.active.actions[actionID]
                if action and action.status == "COUNTDOWN" then
                    local target = ARC.State.players[action.targetKey]
                    local spell = target and target.spells and target.spells[action.spellID]
                    if not target or target.connected == false then
                        self:MarkFailed(action, "offline")
                    elseif target.dead then
                        self:MarkFailed(action, "dead")
                    elseif target.stale then
                        self:MarkFailed(action, "stale report")
                    elseif not spell then
                        self:MarkFailed(action, "spell unavailable")
                    elseif ARC.Automation:WasUsedAfterAssignment(
                        spell, action.assignedAt, action.assignedCharges) then
                        self:HandleObservedUse(action, spell.cooldownStartedAt or now,
                            "cooldown detected")
                    elseif now >= (action.deadline or 0) then
                        self:MarkFailed(action, "missed timing window")
                    end
                end
            end
        end
    end

    if activeCount(self.incoming) > 0 then
        local selfKey = ARC.Roster:GetPlayer()
        local player = ARC.State.players[selfKey]
        local lease = ARC.Automation and ARC.Automation.lease
        local leaseMissing = self.incomingRequesterKey ~= selfKey
            and (not lease or lease.ownerKey ~= self.incomingRequesterKey
                or (lease.expiresAt or 0) <= now)
        local hasCountdown = false
        for _, incoming in pairs(self.incoming) do
            if incoming.state == "COUNTDOWN" then hasCountdown = true break end
        end
        if leaseMissing then
            ARC:Debug("cleared timed combo after coordinator lease expired")
            self:ClearIncomingCombo()
        elseif hasCountdown and self.incomingRequesterKey ~= selfKey
            and now - (self.incomingLastSyncAt or 0) > ARC.Constants.COMBO_SYNC_TIMEOUT then
            ARC:Debug("cleared timed combo after coordinator heartbeat expired")
            self:ClearIncomingCombo()
        elseif UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
            self:OnPlayerDeath()
        else
            local remove = {}
            for actionID, incoming in pairs(self.incoming) do
                if not player or not player.spells or not player.spells[incoming.spellID] then
                    table.insert(remove, { actionID, "UNAVAILABLE" })
                elseif incoming.state == "PREPARED" then
                    local eligible = ARC.Requests:IsEligible(selfKey, incoming.spellID)
                    if not eligible then table.insert(remove, { actionID, "UNAVAILABLE" }) end
                elseif incoming.state == "COUNTDOWN" then
                    self:RefreshIncomingAlert(incoming, now, false)
                    if now >= (incoming.deadline or 0) then
                        table.insert(remove, { actionID, "TIMEOUT" })
                    end
                end
            end
            for _, value in ipairs(remove) do
                local incoming = self.incoming[value[1]]
                if incoming then
                    self:SendStatus(incoming, value[2])
                    self:RemoveIncoming(value[1])
                end
            end
        end
    end
end
