local ARC = Actually.Modules.RaidCooldowns
local CombatLog = ARC:NewModule("CombatLog")

CombatLog.supportedEvents = {
    SPELL_CAST_SUCCESS = "cast",
    SPELL_RESURRECT = "cast",
    SPELL_AURA_APPLIED = "aura",
}

function CombatLog:OnEvent(...)
    local _, combatEvent, sourceGUID, sourceName, _, destGUID, destName, _, spellID, spellName = ...
    local mode = self.supportedEvents[combatEvent]
    if not mode then return end
    local canonicalID = ARC.Registry:Canonicalize(spellID, mode)
        or ARC.Registry:Canonicalize(spellName, mode)
    if not canonicalID then return end
    local entry = ARC.Registry:Get(canonicalID)
    if not entry then return end
    if mode == "aura" then
        local auraConfigured = entry.detection == "aura" or entry.detection == "both"
            or ARC.Registry.auraAliases[spellID] == canonicalID
            or (spellName and ARC.Registry.auraAliases[string.lower(spellName)] == canonicalID)
        if not auraConfigured then return end
    end
    if entry.detection == "cast" and mode ~= "cast" then return end
    if entry.detection == "aura" and mode ~= "aura" then return end

    local target = entry.notarget and nil or destName
    local playerGUID = UnitGUID and UnitGUID("player")
    if sourceGUID and playerGUID and sourceGUID == playerGUID then
        ARC.CooldownReader:OnLocalCast(canonicalID, target)
        return
    end

    local identity = ARC.Roster:FindGUID(sourceGUID)
    if not identity and sourceName then identity = ARC.Roster:FindSender(sourceName) end
    if not identity then return end
    ARC.State:ObserveCast(identity.key, identity, canonicalID, target)
end
