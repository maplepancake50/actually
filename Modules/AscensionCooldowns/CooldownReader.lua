local ACD = Actually.Modules.AscensionCooldowns
local CooldownReader = ACD:NewModule("CooldownReader")

CooldownReader.retryDelays = { 0.05, 0.15, 0.35, 0.70 }

function CooldownReader:Initialize()
    self.cooldowns = {}
    self.pendingTargets = {}
    self.castTokens = {}
end

function CooldownReader:Read(capability)
    local start, duration, enabled
    if capability.bookSlot then
        start, duration, enabled = GetSpellCooldown(capability.bookSlot, ACD.Constants.BOOK_TYPE)
    else
        start, duration, enabled = GetSpellCooldown(capability.spellbookID)
    end
    start, duration = tonumber(start) or 0, tonumber(duration) or 0
    local remaining = math.max(0, start + duration - ACD:Now())
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
    for canonicalID, capability in pairs(ACD.Spellbook:GetCapabilities()) do
        snapshot[canonicalID] = self:Read(capability)
        snapshot[canonicalID].target = self.pendingTargets[canonicalID]
    end
    return snapshot
end

function CooldownReader:RefreshFromCapabilities(reason)
    local snapshot = self:ReadAll()
    self.cooldowns = snapshot
    local playerKey, identity = ACD.Roster:GetPlayer()
    if not playerKey then return end
    ACD.State:ApplyLocalSnapshot(playerKey, identity, ACD.Spellbook:GetCapabilities(), snapshot,
        ACD.Spellbook.capabilityRevision)
    ACD:Debug("cooldown refresh: " .. tostring(reason))
end

function CooldownReader:RefreshKnown(reason, broadcast)
    local playerKey = ACD.Roster:GetPlayer()
    if not playerKey then return false end
    local anyChanged = false
    for canonicalID, capability in pairs(ACD.Spellbook:GetCapabilities()) do
        local value = self:Read(capability)
        value.target = self.pendingTargets[canonicalID]
        self.cooldowns[canonicalID] = value
        if ACD.State:UpdateLocalCooldown(playerKey, canonicalID, value) then anyChanged = true end
    end
    if anyChanged and broadcast and ACD.Comms.initialized then
        ACD.Comms:ScheduleState(0.2, reason or "cooldown")
    end
    return anyChanged
end

function CooldownReader:ScheduleRefresh(delay, reason)
    if self.refreshTimer then ACD:CancelTimer(self.refreshTimer, true) end
    self.refreshTimer = ACD:ScheduleTimer(function()
        self.refreshTimer = nil
        self:RefreshKnown(reason, true)
    end, delay or 0.1)
end

function CooldownReader:OnLocalCast(canonicalID, target)
    if not ACD.Spellbook.capabilities[canonicalID] then return end
    self.pendingTargets[canonicalID] = target
    local token = (self.castTokens[canonicalID] or 0) + 1
    self.castTokens[canonicalID] = token

    local function attempt(index)
        if token ~= self.castTokens[canonicalID] then return end
        self:RefreshKnown("cast retry", false)
        local value = self.cooldowns[canonicalID]
        local realCooldown = value and value.remaining > 0 and value.duration > 2
        if realCooldown or index >= #self.retryDelays then
            if realCooldown and ACD.Comms.initialized then
                ACD.Comms:SendCast(canonicalID, value, target)
            end
            if ACD.Comms.initialized then ACD.Comms:ScheduleState(0.2, "cast") end
            return
        end
        ACD:ScheduleTimer(function() attempt(index + 1) end, self.retryDelays[index + 1])
    end

    ACD:ScheduleTimer(function() attempt(1) end, self.retryDelays[1])
end
