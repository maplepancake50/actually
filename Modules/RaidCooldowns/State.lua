local ARC = Actually.Modules.RaidCooldowns
local State = ARC:NewModule("State")

State.sourceRank = { UNKNOWN = 0, OBSERVED = 1, REPORT = 2, SELF = 3 }

local function clearTable(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
end

local function writeSpell(target, canonicalID, value, confidence, now)
    local duration = math.max(0, tonumber(value.duration) or 0)
    local remaining = math.max(0, tonumber(value.remaining) or 0)
    if duration > 0 and remaining > duration + 2 then duration = remaining end
    local cooldownStartedAt = tonumber(value.cooldownStartedAt)
    if not cooldownStartedAt and duration > 0 and remaining > 0 then
        cooldownStartedAt = now - math.max(0, duration - remaining)
    end
    target = target or {}
    target.spellID = canonicalID
    target.known = true
    target.readyAt = remaining > 0 and (now + remaining) or 0
    target.remaining = remaining
    target.duration = duration
    target.cooldownStartedAt = cooldownStartedAt
    target.charges = tonumber(value.charges)
    target.maxCharges = tonumber(value.maxCharges)
    target.chargeRemaining = math.max(0, tonumber(value.chargeRemaining) or 0)
    target.target = value.target
    target.confidence = confidence
    target.lastUpdate = now
    return target
end

local function copySpell(canonicalID, value, confidence, now)
    return writeSpell({}, canonicalID, value, confidence, now)
end

local function spellActive(value, now)
    if not value then return false end
    if (tonumber(value.readyAt) or 0) > now then return true end
    local charges = tonumber(value.charges)
    local maximum = tonumber(value.maxCharges)
    return maximum and maximum > 0 and charges and charges < maximum or false
end

function State:Initialize()
    self.players = {}
    self.peers = {}
    self.lastEffectiveDuration = {}
    self.revision = 0
end

function State:Changed(reason)
    self.revision = self.revision + 1
    if ARC.Renderer and ARC.Renderer.MarkDirty then
        ARC.Renderer:MarkDirty(reason)
    end
    if ARC.UserList and ARC.UserList.initialized and ARC.UserList.frame:IsShown() then
        ARC.UserList:Refresh()
    end
end

function State:GetOrCreate(playerKey, identity, source)
    local player = self.players[playerKey]
    if not player then
        player = { key = playerKey, spells = {}, source = source or "UNKNOWN" }
        self.players[playerKey] = player
    end
    if identity then
        player.name = identity.name or player.name
        player.guid = identity.guid or player.guid
        player.unit = identity.unit or player.unit
        player.connected = identity.connected
        player.dead = identity.dead
    end
    return player
end

function State:ApplyLocalSnapshot(playerKey, identity, capabilities, cooldowns, capabilityRevision)
    local now = ARC:Now()
    local player = self:GetOrCreate(playerKey, identity, "SELF")
    local replacement = {}
    for canonicalID in pairs(capabilities or {}) do
        local value = cooldowns and cooldowns[canonicalID] or { remaining = 0, duration = 0 }
        replacement[canonicalID] = copySpell(canonicalID, value, "SELF", now)
        if replacement[canonicalID].duration > 2 then
            self.lastEffectiveDuration[canonicalID] = replacement[canonicalID].duration
        end
    end
    player.spells = replacement
    player.source = "SELF"
    player.capabilityRevision = capabilityRevision or 0
    player.lastSeen = now
    self:Changed("local snapshot")
end

function State:UpdateLocalCooldown(playerKey, canonicalID, value)
    local player = self.players[playerKey]
    if not player or player.source ~= "SELF" or not player.spells[canonicalID] then return false end
    local now = ARC:Now()
    local old = player.spells[canonicalID]
    local oldReadyAt = old.readyAt or 0
    local oldDuration = old.duration or 0
    local oldCharges = old.charges
    local oldMaxCharges = old.maxCharges
    local oldTarget = old.target
    local updated = writeSpell(old, canonicalID, value, "SELF", now)
    local changed = math.abs(oldReadyAt - updated.readyAt) > 0.25
        or math.abs(oldDuration - updated.duration) > 0.25
        or oldCharges ~= updated.charges
        or oldMaxCharges ~= updated.maxCharges
        or oldTarget ~= updated.target
    player.lastSeen = now
    if updated.duration > 2 then self.lastEffectiveDuration[canonicalID] = updated.duration end
    if changed then self:Changed("local cooldown") end
    return changed
end

function State:ApplyReport(playerKey, identity, session, sequence, capabilityRevision, rows)
    local now = ARC:Now()
    local peer = self.peers[playerKey]
    if peer and peer.session == session and sequence <= (peer.sequence or -1) then
        return false, "old sequence"
    end
    if not peer or peer.session ~= session then peer = {} end
    peer.protocol = ARC.Constants.PROTOCOL_VERSION
    peer.session = session
    peer.sequence = sequence
    peer.capabilityRevision = capabilityRevision
    peer.lastSeen = now
    self.peers[playerKey] = peer

    local player = self:GetOrCreate(playerKey, identity, "REPORT")
    local previousSpells = player.spells or {}
    local replacement = {}
    for canonicalID, value in pairs(rows) do
        replacement[canonicalID] = copySpell(canonicalID, value, "REPORT", now)
        local previous = previousSpells[canonicalID]
        if previous and previous.target and spellActive(previous, now)
            and spellActive(replacement[canonicalID], now) then
            replacement[canonicalID].target = previous.target
        end
        if replacement[canonicalID].duration > 2 then
            self.lastEffectiveDuration[canonicalID] = replacement[canonicalID].duration
        end
    end
    player.spells = replacement
    player.source = "REPORT"
    player.session = session
    player.sequence = sequence
    player.capabilityRevision = capabilityRevision
    player.lastSeen = now
    player.stale = false
    if ARC.Automation and ARC.Automation.ClearObservedForPlayer then
        ARC.Automation:ClearObservedForPlayer(playerKey, replacement)
    end
    self:Changed("complete report")
    return true
end

function State:ApplyCast(playerKey, identity, session, sequence, canonicalID, value)
    local now = ARC:Now()
    local peer = self.peers[playerKey]
    if peer and peer.session == session and sequence <= (peer.sequence or -1) then
        return false, "old sequence"
    end
    if not peer or peer.session ~= session then peer = {} end
    peer.protocol = ARC.Constants.PROTOCOL_VERSION
    peer.session = session
    peer.sequence = sequence
    peer.lastSeen = now
    self.peers[playerKey] = peer

    local player = self:GetOrCreate(playerKey, identity, "REPORT")
    player.source = "REPORT"
    player.session = session
    player.sequence = sequence
    player.lastSeen = now
    player.stale = false
    player.spells[canonicalID] = copySpell(canonicalID, value, "REPORT", now)
    if player.spells[canonicalID].duration > 2 then
        self.lastEffectiveDuration[canonicalID] = player.spells[canonicalID].duration
    end
    self:Changed("cast report")
    if ARC.Automation and ARC.Automation.ObserveCast then
        ARC.Automation:ObserveCast(playerKey, canonicalID)
    end
    if ARC.Requests and ARC.Requests.initialized then
        ARC.Requests:OnReportedCast(playerKey, canonicalID)
    end
    if ARC.Bundles and ARC.Bundles.initialized then
        ARC.Bundles:OnReportedCast(playerKey, canonicalID)
    end
    if ARC.Combos and ARC.Combos.initialized then
        ARC.Combos:OnReportedCast(playerKey, canonicalID)
    end
    if ARC.Activity and ARC.Activity.initialized then
        ARC.Activity:OnCast(playerKey, canonicalID, "ARC cast report")
    end
    return true
end

function State:ObserveCast(playerKey, identity, canonicalID, target)
    local player = self.players[playerKey]
    local entry = ARC.Registry:Get(canonicalID)
    local duration = self.lastEffectiveDuration[canonicalID] or (entry and entry.fallbackCD)
    if ARC.Automation and ARC.Automation.ObserveCast then
        ARC.Automation:ObserveCast(playerKey, canonicalID)
    end
    if not duration or duration <= 0 then return false end
    local now = ARC:Now()
    local existingSource = player and player.source
    player = self:GetOrCreate(playerKey, identity, existingSource or "OBSERVED")
    if not existingSource
        or self.sourceRank[existingSource or "UNKNOWN"] < self.sourceRank.REPORT then
        player.source = "OBSERVED"
    end
    player.lastSeen = now
    player.spells[canonicalID] = copySpell(canonicalID, {
        duration = duration,
        remaining = duration,
        target = target,
    }, "OBSERVED", now)
    self:Changed("observed cast")
    if ARC.Requests and ARC.Requests.initialized then
        ARC.Requests:OnReportedCast(playerKey, canonicalID)
    end
    if ARC.Bundles and ARC.Bundles.initialized then
        ARC.Bundles:OnReportedCast(playerKey, canonicalID)
    end
    if ARC.Combos and ARC.Combos.initialized then
        ARC.Combos:OnReportedCast(playerKey, canonicalID)
    end
    return true
end

function State:UpdateRoster(roster)
    local changed = false
    for playerKey, player in pairs(self.players) do
        local identity = roster.byKey[playerKey]
        if identity then
            player.unit = identity.unit
            player.connected = identity.connected
            player.dead = identity.dead
        elseif player.source ~= "SELF" then
            self.players[playerKey] = nil
            self.peers[playerKey] = nil
            changed = true
        end
    end
    if changed then self:Changed("roster departure") end
end

function State:ExpireRemoteReports()
    local now = ARC:Now()
    local requested = false
    for playerKey, player in pairs(self.players) do
        if player.source == "REPORT" then
            local age = now - (player.lastSeen or 0)
            if age >= ARC.Constants.REPORT_STALE_AFTER and not player.stale then
                player.stale = true
                requested = true
                self:Changed("stale report")
            end
            if age >= ARC.Constants.REPORT_FORGET_AFTER then
                local active = false
                for _, spell in pairs(player.spells) do
                    if (spell.readyAt or 0) > now then active = true break end
                end
                if not active and next(player.spells) then
                    clearTable(player.spells)
                    self:Changed("expired report")
                end
            end
        end
    end
    return requested
end

function State:GetPlayers()
    return self.players
end
