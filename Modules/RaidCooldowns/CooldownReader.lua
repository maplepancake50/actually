local ARC = Actually.Modules.RaidCooldowns
local CooldownReader = ARC:NewModule("CooldownReader")

CooldownReader.retryDelays = { 0.05, 0.15, 0.35, 0.70 }

function CooldownReader:Initialize()
    self.cooldowns = {}
    self.pendingTargets = {}
    self.castTokens = {}
end

function CooldownReader:Read(capability)
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
    return {
        start = start,
        duration = duration,
        remaining = remaining,
        enabled = enabled,
        probableGCD = probableGCD,
    }
end

function CooldownReader:ReadAll()
    local snapshot = {}
    for canonicalID, capability in pairs(ARC.Spellbook:GetCapabilities()) do
        snapshot[canonicalID] = self:Read(capability)
        snapshot[canonicalID].target = self.pendingTargets[canonicalID]
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
        local value = self:Read(capability)
        value.target = self.pendingTargets[canonicalID]
        self.cooldowns[canonicalID] = value
        if ARC.State:UpdateLocalCooldown(playerKey, canonicalID, value) then anyChanged = true end
    end
    if anyChanged and broadcast and ARC.Comms.initialized then
        ARC.Comms:ScheduleState(0.2, reason or "cooldown")
    end
    return anyChanged
end

function CooldownReader:ScheduleRefresh(delay, reason)
    if self.refreshTimer then ARC:CancelTimer(self.refreshTimer, true) end
    self.refreshTimer = ARC:ScheduleTimer(function()
        self.refreshTimer = nil
        self:RefreshKnown(reason, true)
    end, delay or 0.1)
end

function CooldownReader:OnLocalCast(canonicalID, target)
    if not ARC.Spellbook.capabilities[canonicalID] then return end
    self.pendingTargets[canonicalID] = target
    local token = (self.castTokens[canonicalID] or 0) + 1
    self.castTokens[canonicalID] = token

    local function attempt(index)
        if token ~= self.castTokens[canonicalID] then return end
        self:RefreshKnown("cast retry", false)
        local value = self.cooldowns[canonicalID]
        local realCooldown = value and value.remaining > 0 and value.duration > 2
        if realCooldown or index >= #self.retryDelays then
            if realCooldown and ARC.Comms.initialized then
                ARC.Comms:SendCast(canonicalID, value, target)
            end
            if ARC.Comms.initialized then ARC.Comms:ScheduleState(0.2, "cast") end
            return
        end
        ARC:ScheduleTimer(function() attempt(index + 1) end, self.retryDelays[index + 1])
    end

    ARC:ScheduleTimer(function() attempt(1) end, self.retryDelays[1])
end
