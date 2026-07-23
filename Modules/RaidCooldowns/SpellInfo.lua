local ARC = Actually.Modules.RaidCooldowns
local SpellInfo = ARC:NewModule("SpellInfo")

function SpellInfo:GetRawInfo(spellID)
    if not GetSpellInfo then return nil end
    return GetSpellInfo(spellID)
end

function SpellInfo:ResolveSpellName(spellID)
    local name = self:GetRawInfo(spellID)
    local entry = ARC.Registry:Get(spellID)
    return name or (entry and entry.fallbackName) or ("Unknown spell " .. tostring(spellID))
end

function SpellInfo:ResolveSpellIcon(spellID)
    local _, _, icon = self:GetRawInfo(spellID)
    local entry = ARC.Registry:Get(spellID)
    return icon or (entry and entry.fallbackIcon) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

function SpellInfo:ResolveSpellLink(spellID)
    local link = GetSpellLink and GetSpellLink(spellID)
    return link or self:ResolveSpellName(spellID)
end

function SpellInfo:CanonicalizeSpellID(spellID, mode)
    return ARC.Registry:Canonicalize(spellID, mode)
end
