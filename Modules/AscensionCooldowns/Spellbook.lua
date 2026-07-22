local ACD = Actually.Modules.AscensionCooldowns
local Spellbook = ACD:NewModule("Spellbook")

local function sameCapabilities(left, right)
    for spellID, value in pairs(left) do
        if not right[spellID]
            or right[spellID].bookSlot ~= value.bookSlot
            or right[spellID].spellbookID ~= value.spellbookID
            or right[spellID].source ~= value.source
            or right[spellID].talentRank ~= value.talentRank then return false end
    end
    for spellID in pairs(right) do
        if not left[spellID] then return false end
    end
    return true
end

local function getTalentMetadata(spellID)
    if not C_CharacterAdvancement
        or type(C_CharacterAdvancement.GetEntryBySpellID) ~= "function" then return nil end
    local entryOK, entry = pcall(C_CharacterAdvancement.GetEntryBySpellID, spellID)
    if not entryOK or type(entry) ~= "table" then return nil end
    local entryID = entry.ID or entry.id or entry.entryID
    if not entryID then return nil end
    local currentRank, maxRank
    if type(C_CharacterAdvancement.GetTalentRankByID) == "function" then
        local rankOK, current, maximum = pcall(C_CharacterAdvancement.GetTalentRankByID, entryID)
        if rankOK then currentRank, maxRank = current, maximum end
    end
    return entryID, currentRank, maxRank
end

local function canonicalizeSpell(returnedID, itemName)
    local canonicalID = ACD.Registry:Canonicalize(returnedID)
        or ACD.Registry:Canonicalize(itemName)
    if canonicalID or type(returnedID) ~= "number" then return canonicalID end
    if C_Spell and type(C_Spell.GetFirstRank) == "function" then
        local ok, firstRankID = pcall(C_Spell.GetFirstRank, returnedID)
        if ok then return ACD.Registry:Canonicalize(firstRankID) end
    end
    return nil
end

local function isAscensionSpellKnown(spellID)
    if type(spellID) ~= "number" then return false end
    if C_Spell and type(C_Spell.IsAnyRankKnown) == "function" then
        local ok, known = pcall(C_Spell.IsAnyRankKnown, C_Spell, spellID)
        if ok and known then return true end
    end
    if type(CA_IsSpellKnown) == "function" then
        local ok, known = pcall(CA_IsSpellKnown, spellID)
        if ok and known then return true end
    end
    return false
end

function Spellbook:Initialize()
    self.capabilities = {}
    self.capabilityRevision = 0
    self.scanGeneration = 0
end

function Spellbook:ScheduleScan(delay, reason)
    if self.scanTimer then ACD:CancelTimer(self.scanTimer, true) end
    self.scanTimer = ACD:ScheduleTimer(function()
        self.scanTimer = nil
        self:Scan(reason)
    end, delay or 0.2)
end

function Spellbook:ScheduleSafetyScans()
    for _, delay in ipairs({ 0.5, 2, 10 }) do
        ACD:ScheduleTimer(function() self:Scan("world safety") end, delay)
    end
end

function Spellbook:Scan(reason)
    local found = {}
    local tabs = GetNumSpellTabs and GetNumSpellTabs() or 0
    for tab = 1, tabs do
        local _, _, offset, count = GetSpellTabInfo(tab)
        offset, count = tonumber(offset) or 0, tonumber(count) or 0
        for slot = offset + 1, offset + count do
            local itemType, returnedID = GetSpellBookItemInfo(slot, ACD.Constants.BOOK_TYPE)
            local itemName = GetSpellBookItemName(slot, ACD.Constants.BOOK_TYPE)
            local canonicalID = canonicalizeSpell(returnedID, itemName)
            if canonicalID then
                found[canonicalID] = {
                    known = true,
                    bookSlot = slot,
                    spellbookID = returnedID,
                    name = itemName or ACD.SpellInfo:ResolveSpellName(canonicalID),
                    itemType = itemType,
                    tab = tab,
                    source = "SPELLBOOK",
                }
            end
        end
    end


    -- Ascension talents and hidden abilities may be known without receiving a
    -- normal spellbook slot. Query only registered IDs and aliases so this
    -- remains bounded by the cooldown catalogue.
    for canonicalID, entry in pairs(ACD.Registry.entries) do
        if entry.valid and not found[canonicalID] then
            local knownID
            if isAscensionSpellKnown(canonicalID) then knownID = canonicalID end
            if not knownID then
                for _, aliasID in ipairs(entry.aliases or {}) do
                    if isAscensionSpellKnown(aliasID) then knownID = aliasID break end
                end
            end
            if knownID then
                local talentEntryID, talentRank, talentMaxRank = getTalentMetadata(knownID)
                found[canonicalID] = {
                    known = true,
                    bookSlot = nil,
                    spellbookID = knownID,
                    name = ACD.SpellInfo:ResolveSpellName(knownID),
                    itemType = "ascension",
                    source = "ASCENSION",
                    talentEntryID = talentEntryID,
                    talentRank = talentRank,
                    talentMaxRank = talentMaxRank,
                }
            end
        end
    end

    local changed = not sameCapabilities(self.capabilities, found)
    self.capabilities = found
    self.scanGeneration = self.scanGeneration + 1
    if changed then self.capabilityRevision = self.capabilityRevision + 1 end
    ACD:Debug("spellbook scan " .. tostring(reason) .. ": " .. tostring(self:Count()) .. " tracked")
    ACD.CooldownReader:RefreshFromCapabilities(changed and "capabilities" or "scan")
    if changed and ACD.Comms.initialized then ACD.Comms:ScheduleState(0.1, "capabilities") end
    return changed
end

function Spellbook:Count()
    local count = 0
    for _ in pairs(self.capabilities) do count = count + 1 end
    return count
end

function Spellbook:GetCapabilities()
    return self.capabilities
end

function Spellbook:Dump(filter)
    filter = filter and string.lower(filter) or nil
    local tabs = GetNumSpellTabs and GetNumSpellTabs() or 0
    for tab = 1, tabs do
        local _, _, offset, count = GetSpellTabInfo(tab)
        offset, count = tonumber(offset) or 0, tonumber(count) or 0
        for slot = offset + 1, offset + count do
            local itemType, returnedID = GetSpellBookItemInfo(slot, ACD.Constants.BOOK_TYPE)
            local itemName = GetSpellBookItemName(slot, ACD.Constants.BOOK_TYPE)
            local canonicalID = canonicalizeSpell(returnedID, itemName)
            local haystack = string.lower(tostring(returnedID) .. " " .. tostring(itemName) .. " " .. tostring(canonicalID))
            if not filter or string.find(haystack, filter, 1, true) then
                ACD:Print(string.format("book tab=%d slot=%d type=%s id=%s name=%s match=%s canonical=%s",
                    tab, slot, tostring(itemType), tostring(returnedID), tostring(itemName),
                    canonicalID and "yes" or "no", tostring(canonicalID)))
            end
        end
    end
end
