local ARC = Actually.Modules.RaidCooldowns
local State = ARC:NewModule("State")

State.sourceRank = { UNKNOWN = 0, OBSERVED = 1, REPORT = 2, SELF = 3 }

local function clearTable(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
end

local function copySpell(canonicalID, value, confidence, now)
    local duration = math.max(0, tonumber(value.duration) or 0)
    local remaining = math.max(0, tonumber(value.remaining) or 0)
    if duration > 0 and remaining > duration + 2 then duration = remaining end
    return {
        spellID = canonicalID,
        known = true,
        readyAt = remaining > 0 and (now + remaining) or 0,
        remaining = remaining,
        duration = duration,
        target = value.target,
        confidence = confidence,
        lastUpdate = now,
    }
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
    local updated = copySpell(canonicalID, value, "SELF", now)
    updated.target = value.target or old.target
    local changed = math.abs((old.readyAt or 0) - updated.readyAt) > 0.25
        or math.abs((old.duration or 0) - updated.duration) > 0.25
        or old.target ~= updated.target
    player.spells[canonicalID] = updated
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
    local replacement = {}
    for canonicalID, value in pairs(rows) do
        replacement[canonicalID] = copySpell(canonicalID, value, "REPORT", now)
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
    if ARC.Requests and ARC.Requests.initialized then
        ARC.Requests:OnReportedCast(playerKey, canonicalID)
    end
    if ARC.Bundles and ARC.Bundles.initialized then
        ARC.Bundles:OnReportedCast(playerKey, canonicalID)
    end
    return true
end

function State:ObserveCast(playerKey, identity, canonicalID, target)
    local player = self.players[playerKey]
    if player and self.sourceRank[player.source or "UNKNOWN"] >= self.sourceRank.REPORT then return false end
    local entry = ARC.Registry:Get(canonicalID)
    local duration = self.lastEffectiveDuration[canonicalID] or (entry and entry.fallbackCD)
    if not duration or duration <= 0 then return false end
    local now = ARC:Now()
    player = self:GetOrCreate(playerKey, identity, "OBSERVED")
    player.source = "OBSERVED"
    player.lastSeen = now
    player.spells[canonicalID] = copySpell(canonicalID, {
        duration = duration,
        remaining = duration,
        target = target,
    }, "OBSERVED", now)
    self:Changed("observed cast")
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
