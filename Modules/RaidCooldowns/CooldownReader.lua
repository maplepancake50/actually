local ARC = Actually.Modules.RaidCooldowns
local CooldownReader = ARC:NewModule("CooldownReader")

CooldownReader.retryDelays = { 0.05, 0.15, 0.35, 0.70 }

local function hasActiveCooldown(value)
    if not value then return false end
    if (tonumber(value.remaining) or 0) > 0
        and (tonumber(value.duration) or 0) > 2 then return true end
    local charges = tonumber(value.charges)
    local maximum = tonumber(value.maxCharges)
    return maximum and maximum > 0 and charges and charges < maximum or false
end

function CooldownReader:Initialize()
    self.cooldowns = {}
    self.pendingTargets = {}
    self.castTokens = {}
    self.activeCastRetries = {}
end

function CooldownReader:Read(capability, result)
    local start, duration, enabled
    if capability.bookSlot then
        start, duration, enabled = GetSpellCooldown(capability.bookSlot, ARC.Constants.BOOK_TYPE)
    else
        start, duration, enabled = GetSpellCooldown(capability.spellbookID)
    end
    start, duration = tonumber(start) or 0, tonumber(duration) or 0
    local remaining = math.max(0, start + duration - ARC:Now())
    local probableGCD = duration > 0 and duration <= 2 and remaining > 0
    if probableGCD then
        start, duration, remaining = 0, 0, 0
    end
    local charges, maxCharges, chargeStart, chargeDuration = nil, nil, 0, 0
    if capability.chargeCapable ~= false and type(GetSpellCharges) == "function" then
        local ok, current, maximum, rechargeStart, rechargeDuration = pcall(
            GetSpellCharges, capability.spellbookID or capability.canonicalID)
        if ok then
            charges, maxCharges = tonumber(current), tonumber(maximum)
            chargeStart, chargeDuration = tonumber(rechargeStart) or 0,
                tonumber(rechargeDuration) or 0
            capability.chargeCapable = maxCharges and maxCharges > 0 or false
        end
    end
    local chargeRemaining = math.max(0, chargeStart + chargeDuration - ARC:Now())
    if maxCharges and maxCharges > 0 then
        if charges and charges > 0 then
            start, duration, remaining = 0, 0, 0
        else
            start, duration, remaining = chargeStart, chargeDuration, chargeRemaining
        end
    end
    result = result or {}
    result.start = start
    result.duration = duration
    result.remaining = remaining
    result.enabled = enabled
    result.probableGCD = probableGCD
    result.charges = charges
    result.maxCharges = maxCharges
    result.chargeRemaining = chargeRemaining
    return result
end

function CooldownReader:ReadAll()
    local snapshot = {}
    for canonicalID, capability in pairs(ARC.Spellbook:GetCapabilities()) do
        local value = self:Read(capability)
        if not hasActiveCooldown(value) and not self.activeCastRetries[canonicalID] then
            self.pendingTargets[canonicalID] = nil
        end
        value.target = self.pendingTargets[canonicalID]
        snapshot[canonicalID] = value
    end
    return snapshot
end

function CooldownReader:RefreshFromCapabilities(reason)
    local snapshot = self:ReadAll()
    self.cooldowns = snapshot
    local playerKey, identity = ARC.Roster:GetPlayer()
    if not playerKey then return end
    ARC.State:ApplyLocalSnapshot(playerKey, identity, ARC.Spellbook:GetCapabilities(), snapshot,
        ARC.Spellbook.capabilityRevision)
    ARC:Debug("cooldown refresh: " .. tostring(reason))
end

function CooldownReader:RefreshKnown(reason, broadcast)
    local playerKey = ARC.Roster:GetPlayer()
    if not playerKey then return false end
    local anyChanged = false
    for canonicalID, capability in pairs(ARC.Spellbook:GetCapabilities()) do
        local value = self:Read(capability, self.cooldowns[canonicalID])
        if not hasActiveCooldown(value) and not self.activeCastRetries[canonicalID] then
            self.pendingTargets[canonicalID] = nil
        end
        value.target = self.pendingTargets[canonicalID]
        self.cooldowns[canonicalID] = value
        if ARC.State:UpdateLocalCooldown(playerKey, canonicalID, value) then anyChanged = true end
    end
    if anyChanged and broadcast and ARC.Comms.initialized then
        ARC.Comms:ScheduleState(0.2, reason or "cooldown")
    end
    return anyChanged
end

function CooldownReader:RefreshOne(canonicalID, reason, broadcast)
    local capability = ARC.Spellbook.capabilities[canonicalID]
    local playerKey = ARC.Roster:GetPlayer()
    if not capability or not playerKey then return nil, false end
    local value = self:Read(capability, self.cooldowns[canonicalID])
    value.target = self.pendingTargets[canonicalID]
    self.cooldowns[canonicalID] = value
    local changed = ARC.State:UpdateLocalCooldown(playerKey, canonicalID, value)
    if changed and broadcast and ARC.Comms.initialized then
        ARC.Comms:ScheduleState(0.2, reason or "cooldown")
    end
    return value, changed
end

function CooldownReader:ScheduleRefresh(delay, reason)
    if self.refreshTimer then return end
    self.refreshTimer = ARC:ScheduleTimer(function()
        self.refreshTimer = nil
        self:RefreshKnown(reason, true)
    end, delay or 0.1)
end

function CooldownReader:OnLocalCast(canonicalID, target)
    if not ARC.Spellbook.capabilities[canonicalID] then return end
    local previous = self.cooldowns[canonicalID]
    local previousCharges = previous and tonumber(previous.charges)
    local previousMaximum = previous and tonumber(previous.maxCharges)
    local previousChargeRemaining = previous and tonumber(previous.chargeRemaining) or 0
    self.pendingTargets[canonicalID] = target
    local token = (self.castTokens[canonicalID] or 0) + 1
    self.castTokens[canonicalID] = token
    self.activeCastRetries[canonicalID] = token

    local function attempt(index)
        if token ~= self.castTokens[canonicalID] then return end
        local value = self:RefreshOne(canonicalID, "cast retry", false)
        local realCooldown = value and value.remaining > 0 and value.duration > 2
        if value and value.maxCharges and value.maxCharges > 0
            and value.charges and value.charges < value.maxCharges then
            local chargeChanged = previousCharges == nil
                or previousMaximum ~= value.maxCharges
                or previousCharges ~= value.charges
                or (tonumber(value.chargeRemaining) or 0) > previousChargeRemaining + 0.25
            realCooldown = realCooldown or chargeChanged
        end
        if realCooldown or index >= #self.retryDelays then
            if self.activeCastRetries[canonicalID] == token then
                self.activeCastRetries[canonicalID] = nil
            end
            if realCooldown and ARC.Comms.initialized then
                ARC.Comms:SendCast(canonicalID, value, target)
            elseif not realCooldown then
                self.pendingTargets[canonicalID] = nil
                self:RefreshOne(canonicalID, "cast retry exhausted", false)
            end
            if ARC.Comms.initialized then ARC.Comms:ScheduleState(0.2, "cast") end
            return
        end
        ARC:ScheduleTimer(function() attempt(index + 1) end, self.retryDelays[index + 1])
    end

    ARC:ScheduleTimer(function() attempt(1) end, self.retryDelays[1])
end
