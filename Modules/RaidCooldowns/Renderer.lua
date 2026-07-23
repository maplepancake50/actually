local ARC = Actually.Modules.RaidCooldowns
local Renderer = ARC:NewModule("Renderer")

function Renderer:Initialize()
    self.rows = {}
    self.orderedGroups = {}
    self.dirty = true
    self.elapsed = 0
end

function Renderer:MarkDirty(reason)
    self.dirty = true
    self.dirtyReason = reason
end

function Renderer:GetSourcePlayers()
    if ARC.TestMode and ARC.TestMode.active then return ARC.TestMode.players end
    return ARC.State:GetPlayers()
end

function Renderer:ShouldDisplay(playerKey, spellID, spell, now)
    local profile = ARC.db and ARC.db.profile
    if not profile or not profile.enabled then return false end
    if profile.hideWhileSolo and not ARC.Roster:IsGrouped() then return false end
    local selfKey = ARC.Roster:GetPlayer()
    if profile.ignoreSelf and playerKey == selfKey then return false end
    local spellSettings = profile.spells[spellID] or {}
    if spellSettings.enabled == false then return false end
    local active = (spell.readyAt or 0) > now
    local entry = ARC.Registry:Get(spellID)
    local alwaysShow = spellSettings.alwaysShow
    if alwaysShow == nil then alwaysShow = entry and entry.alwaysShow end
    return active or alwaysShow == true
end

function Renderer:BuildRow(playerKey, player, spellID, spell, now)
    local entry = ARC.Registry:Get(spellID)
    local spellSettings = ARC.db.profile.spells[spellID] or {}
    local remaining = math.max(0, (spell.readyAt or 0) - now)
    return {
        key = tostring(playerKey) .. ":" .. tostring(spellID),
        playerKey = playerKey,
        playerName = player.name or tostring(playerKey),
        unit = player.unit,
        dead = player.dead,
        connected = player.connected,
        spellID = spellID,
        spellName = ARC.SpellInfo:ResolveSpellName(spellID),
        icon = ARC.SpellInfo:ResolveSpellIcon(spellID),
        group = spellSettings.group or (entry and entry.group) or 1,
        priority = spellSettings.priority or (entry and entry.priority) or 0,
        readyAt = spell.readyAt or 0,
        remaining = remaining,
        duration = spell.duration or 0,
        ready = remaining <= 0,
        target = spell.target,
        confidence = spell.confidence,
        stale = player.stale,
    }
end

function Renderer:CompareRows(left, right)
    if left.priority ~= right.priority then return left.priority > right.priority end
    if left.ready ~= right.ready then return not left.ready end
    if left.dead ~= right.dead then return not left.dead end
    if math.abs(left.remaining - right.remaining) > 0.1 then return left.remaining < right.remaining end
    if left.spellID ~= right.spellID then return left.spellID < right.spellID end
    return string.lower(left.playerName) < string.lower(right.playerName)
end

function Renderer:Reconcile()
    local now = ARC:Now()
    local rows, groups = {}, {}
    for playerKey, player in pairs(self:GetSourcePlayers()) do
        rows[playerKey] = {}
        for spellID, spell in pairs(player.spells or {}) do
            if self:ShouldDisplay(playerKey, spellID, spell, now) then
                local row = self:BuildRow(playerKey, player, spellID, spell, now)
                rows[playerKey][spellID] = row
                groups[row.group] = groups[row.group] or {}
                table.insert(groups[row.group], row)
            end
        end
        if not next(rows[playerKey]) then rows[playerKey] = nil end
    end
    for _, group in pairs(groups) do
        table.sort(group, function(left, right) return self:CompareRows(left, right) end)
    end
    self.rows, self.orderedGroups = rows, groups
    self.dirty = false
    if self.onReconcile then self.onReconcile(self, rows, groups) end
end

function Renderer:OnUpdate(elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < ARC.Constants.UI_UPDATE_INTERVAL then return end
    self.elapsed = 0
    local now = ARC:Now()
    local needsReconcile = self.dirty
    for _, spells in pairs(self.rows) do
        for _, row in pairs(spells) do
            local previous = row.remaining or 0
            local remaining = math.max(0, (row.readyAt or 0) - now)
            local shownBefore = math.ceil(previous)
            row.remaining = remaining
            row.ready = remaining <= 0
            if shownBefore ~= math.ceil(remaining) and self.onTick then self.onTick(self, row) end
            if previous > 0 and remaining <= 0 then needsReconcile = true end
        end
    end
    if needsReconcile then self:Reconcile() end
    if ARC.State:ExpireRemoteReports() and ARC.Comms.initialized then
        ARC.Comms:RequestState(false)
    end
    if ARC.Requests and ARC.Requests.initialized then ARC.Requests:OnUpdate(now) end
    if ARC.Bundles and ARC.Bundles.initialized then ARC.Bundles:OnUpdate(now) end
end

function Renderer:CountRows()
    local count = 0
    for _, spells in pairs(self.rows) do for _ in pairs(spells) do count = count + 1 end end
    return count
end
