local ACD = Actually.Modules.AscensionCooldowns
local Debug = ACD:NewModule("DebugCommands")

local function sortedSpellIDs(spells)
    local ids = {}
    for spellID in pairs(spells) do table.insert(ids, spellID) end
    table.sort(ids)
    return ids
end

local function describe(value, depth, seen)
    local valueType = type(value)
    if valueType == "string" then return string.format("%q", value) end
    if valueType ~= "table" then return tostring(value) end
    if depth >= 2 then return "{...}" end
    seen = seen or {}
    if seen[value] then return "<recursive>" end
    seen[value] = true
    local parts, count = {}, 0
    for key, child in pairs(value) do
        count = count + 1
        if count > 20 then table.insert(parts, "...") break end
        table.insert(parts, "[" .. describe(key, depth + 1, seen) .. "]=" .. describe(child, depth + 1, seen))
    end
    seen[value] = nil
    table.sort(parts)
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function callProbe(label, func, ...)
    if type(func) ~= "function" then
        ACD:Print(label .. " unavailable")
        return
    end
    local function pack(...)
        return { n = select("#", ...), ... }
    end
    local results = pack(pcall(func, ...))
    if not results[1] then
        ACD:Print(label .. " ERROR: " .. tostring(results[2]))
        return
    end
    local values = {}
    for index = 2, results.n do
        table.insert(values, describe(results[index], 0))
    end
    ACD:Print(label .. " => " .. (#values > 0 and table.concat(values, " | ") or "<no values>"))
end

function Debug:Probe()
    local localizedClass, classToken = UnitClass("player")
    ACD:Print("class=" .. tostring(localizedClass) .. " token=" .. tostring(classToken)
        .. " tabs=" .. tostring(GetNumSpellTabs and GetNumSpellTabs() or 0)
        .. " channel=" .. tostring(ACD.Roster:GetDistribution() or "SOLO"))
    for _, canonicalID in ipairs(sortedSpellIDs(ACD.Registry.entries)) do
        local entry = ACD.Registry:Get(canonicalID)
        if entry then
            local rawName, _, rawIcon = ACD.SpellInfo:GetRawInfo(canonicalID)
            local capability = ACD.Spellbook.capabilities[canonicalID]
            local cooldown = capability and ACD.CooldownReader:Read(capability) or {}
            ACD:Print(string.format("id=%d fallback=%s api=%s icon=%s aliases=%s found=%s source=%s slot=%s bookID=%s type=%s talentEntry=%s rank=%s/%s start=%.2f duration=%.2f enabled=%s remaining=%.2f",
                canonicalID, tostring(entry.fallbackName), tostring(rawName), tostring(rawIcon or ACD.SpellInfo:ResolveSpellIcon(canonicalID)),
                table.concat(entry.aliases or {}, ","), capability and "yes" or "no",
                tostring(capability and capability.source),
                tostring(capability and capability.bookSlot), tostring(capability and capability.spellbookID),
                tostring(capability and capability.itemType), tostring(capability and capability.talentEntryID),
                tostring(capability and capability.talentRank), tostring(capability and capability.talentMaxRank),
                tonumber(cooldown.start) or 0,
                tonumber(cooldown.duration) or 0, tostring(cooldown.enabled), tonumber(cooldown.remaining) or 0))
        end
    end
end

function Debug:State()
    local now = ACD:Now()
    local count = 0
    for playerKey, player in pairs(ACD.State.players) do
        ACD:Print(string.format("player=%s key=%s source=%s age=%.1f stale=%s", tostring(player.name), tostring(playerKey),
            tostring(player.source), now - (player.lastSeen or now), tostring(player.stale and true or false)))
        for _, spellID in ipairs(sortedSpellIDs(player.spells)) do
            local spell = player.spells[spellID]
            ACD:Print(string.format("  %d %s remaining=%.1f duration=%.1f confidence=%s target=%s",
                spellID, ACD.SpellInfo:ResolveSpellName(spellID), math.max(0, (spell.readyAt or 0) - now),
                spell.duration or 0, tostring(spell.confidence), tostring(spell.target)))
            count = count + 1
        end
    end
    if count == 0 then ACD:Print("state is empty") end
end

function Debug:Peers()
    local now, count = ACD:Now(), 0
    for playerKey, peer in pairs(ACD.State.peers) do
        ACD:Print(string.format("peer=%s protocol=%s session=%s sequence=%s age=%.1f",
            tostring(playerKey), tostring(peer.protocol), tostring(peer.session), tostring(peer.sequence),
            now - (peer.lastSeen or now)))
        count = count + 1
    end
    if count == 0 then ACD:Print("no addon peers") end
end

function Debug:APIProbe(argument)
    local spellID = tonumber(argument)
    if not spellID or spellID <= 0 then
        ACD:Print("usage: /acd apiprobe <numeric spellID>")
        return
    end

    local spellName = ACD.SpellInfo:ResolveSpellName(spellID)
    ACD:Print("API probe id=" .. tostring(spellID) .. " name=" .. tostring(spellName))
    callProbe("GetSpellInfo(id)", GetSpellInfo, spellID)
    callProbe("GetSpellCooldown(id)", GetSpellCooldown, spellID)
    callProbe("GetSpellCooldown(name)", GetSpellCooldown, spellName)
    callProbe("GetSpellCharges(id)", GetSpellCharges, spellID)
    callProbe("IsPassiveSpell(id)", IsPassiveSpell, spellID)
    callProbe("IsPassiveSpell(id,spell)", IsPassiveSpell, spellID, ACD.Constants.BOOK_TYPE)
    callProbe("IsUsableSpell(id)", IsUsableSpell, spellID)
    callProbe("IsUsableSpell(name)", IsUsableSpell, spellName)
    callProbe("IsSpellKnown(id)", IsSpellKnown, spellID)
    callProbe("CA_IsSpellKnown(id)", CA_IsSpellKnown, spellID)
    callProbe("CA_GetTalentInfo(id)", CA_GetTalentInfo, spellID)
    callProbe("FindSpellBookSlotByID(id)", FindSpellBookSlotByID, spellID)

    if type(CAO_Known) == "table" then
        ACD:Print("CAO_Known[id] => " .. describe(CAO_Known[spellID], 0))
    else
        ACD:Print("CAO_Known unavailable (type=" .. type(CAO_Known) .. ")")
    end
    local talentReference
    if type(CAO_Talent_References) == "table" then
        talentReference = CAO_Talent_References[spellID]
        ACD:Print("CAO_Talent_References[id] => " .. describe(talentReference, 0))
    else
        ACD:Print("CAO_Talent_References unavailable (type=" .. type(CAO_Talent_References) .. ")")
    end
    if type(CAO_Talents) == "table" and talentReference ~= nil then
        ACD:Print("CAO_Talents[reference] => " .. describe(CAO_Talents[talentReference], 0))
    else
        ACD:Print("CAO_Talents lookup unavailable")
    end
    if type(CAO_Spells) == "table" then
        ACD:Print("CAO_Spells[id] => " .. describe(CAO_Spells[spellID], 0))
    else
        ACD:Print("CAO_Spells unavailable (type=" .. type(CAO_Spells) .. ")")
    end

    if C_Spell then
        callProbe("C_Spell:IsAnyRankKnown(id)", C_Spell.IsAnyRankKnown, C_Spell, spellID)
        callProbe("C_Spell.GetFirstRank(id)", C_Spell.GetFirstRank, spellID)
        callProbe("C_Spell:GetSpellID(id)", C_Spell.GetSpellID, C_Spell, spellID)
    else
        ACD:Print("C_Spell unavailable")
    end

    if C_CharacterAdvancement then
        local entry
        if type(C_CharacterAdvancement.GetEntryBySpellID) == "function" then
            local ok, result = pcall(C_CharacterAdvancement.GetEntryBySpellID, spellID)
            if ok then
                entry = result
                ACD:Print("C_CharacterAdvancement.GetEntryBySpellID(id) => " .. describe(result, 0))
            else
                ACD:Print("C_CharacterAdvancement.GetEntryBySpellID(id) ERROR: " .. tostring(result))
            end
        else
            ACD:Print("C_CharacterAdvancement.GetEntryBySpellID unavailable")
        end

        local activeSpec
        if type(C_CharacterAdvancement.GetActiveChrSpec) == "function" then
            local ok, result = pcall(C_CharacterAdvancement.GetActiveChrSpec)
            if ok then activeSpec = result end
            ACD:Print("C_CharacterAdvancement.GetActiveChrSpec() => " .. describe(result, 0))
        end
        local entryID = type(entry) == "table" and (entry.ID or entry.id or entry.entryID) or nil
        if entryID then
            callProbe("C_CharacterAdvancement.GetTalentRankByID(entryID)",
                C_CharacterAdvancement.GetTalentRankByID, entryID)
            callProbe("C_CharacterAdvancement.GetPendingRankByEntryID(entryID)",
                C_CharacterAdvancement.GetPendingRankByEntryID, entryID)
            callProbe("CA_GetEntryRank(entryID)", CA_GetEntryRank, entryID)
        end
        if entryID and activeSpec ~= nil then
            callProbe("C_CharacterAdvancement.UnitTalentRankByID(player,entryID,spec)",
                C_CharacterAdvancement.UnitTalentRankByID, "player", entryID, activeSpec)
        else
            ACD:Print("UnitTalentRankByID skipped: no mapped entry ID or active specialization")
        end

        if type(C_CharacterAdvancement.GetKnownTalentEntries) == "function" then
            local ok, entries = pcall(C_CharacterAdvancement.GetKnownTalentEntries)
            if not ok then
                ACD:Print("GetKnownTalentEntries ERROR: " .. tostring(entries))
            elseif type(entries) ~= "table" then
                ACD:Print("GetKnownTalentEntries => " .. describe(entries, 0))
            else
                local matches = 0
                for _, entry in ipairs(entries) do
                    local entryID = tonumber(entry.ID or entry.id or entry.spellID)
                    local entryName = entry.name
                    local spellMatch = false
                    for _, entrySpellID in ipairs(entry.Spells or entry.spells or {}) do
                        if tonumber(entrySpellID) == spellID then spellMatch = true break end
                    end
                    if entryID == spellID or spellMatch
                        or (entryName and string.lower(entryName) == string.lower(spellName)) then
                        matches = matches + 1
                        ACD:Print("known talent match => " .. describe(entry, 0))
                    end
                end
                ACD:Print("GetKnownTalentEntries count=" .. tostring(table.getn(entries))
                    .. " matches=" .. tostring(matches))
            end
        else
            ACD:Print("C_CharacterAdvancement.GetKnownTalentEntries unavailable")
        end
    else
        ACD:Print("C_CharacterAdvancement unavailable")
    end
end

function Debug:DumpTalents(filter)
    if not C_CharacterAdvancement or type(C_CharacterAdvancement.GetKnownTalentEntries) ~= "function" then
        ACD:Print("C_CharacterAdvancement.GetKnownTalentEntries unavailable")
        return
    end
    local ok, entries = pcall(C_CharacterAdvancement.GetKnownTalentEntries)
    if not ok then ACD:Print("GetKnownTalentEntries ERROR: " .. tostring(entries)) return end
    if type(entries) ~= "table" then ACD:Print("GetKnownTalentEntries returned " .. describe(entries, 0)) return end
    filter = filter and string.lower(filter) or nil
    local shown = 0
    for index, entry in ipairs(entries) do
        local haystack = string.lower(tostring(entry.ID or entry.id or "") .. " "
            .. tostring(entry.name or "") .. " " .. tostring(entry.spellID or entry.spellId or ""))
        if not filter or filter == "" or string.find(haystack, filter, 1, true) then
            ACD:Print("talent " .. tostring(index) .. " => " .. describe(entry, 0))
            shown = shown + 1
        end
    end
    ACD:Print("known talents total=" .. tostring(table.getn(entries)) .. " shown=" .. tostring(shown))
end

function Debug:FindHiddenTalents()
    if not C_CharacterAdvancement or type(C_CharacterAdvancement.GetKnownTalentEntries) ~= "function" then
        ACD:Print("C_CharacterAdvancement.GetKnownTalentEntries unavailable")
        return
    end
    local ok, entries = pcall(C_CharacterAdvancement.GetKnownTalentEntries)
    if not ok or type(entries) ~= "table" then
        ACD:Print("unable to read known talents: " .. tostring(entries))
        return
    end

    local hidden, active = 0, 0
    for _, entry in ipairs(entries) do
        for _, spellID in ipairs(entry.Spells or entry.spells or {}) do
            local known = false
            if type(CA_IsSpellKnown) == "function" then
                local knownOK, result = pcall(CA_IsSpellKnown, spellID)
                known = knownOK and result and true or false
            end
            if not known and C_Spell and type(C_Spell.IsAnyRankKnown) == "function" then
                local knownOK, result = pcall(C_Spell.IsAnyRankKnown, C_Spell, spellID)
                known = knownOK and result and true or false
            end

            local slot
            if type(FindSpellBookSlotByID) == "function" then
                local slotOK, result = pcall(FindSpellBookSlotByID, spellID)
                if slotOK then slot = result end
            end

            if known and slot == nil then
                local name, rank = ACD.SpellInfo:GetRawInfo(spellID)
                local isPassive = type(rank) == "string" and string.lower(rank) == "passive"
                if type(IsPassiveSpell) == "function" then
                    local passiveOK, result = pcall(IsPassiveSpell, spellID, ACD.Constants.BOOK_TYPE)
                    if passiveOK and result ~= nil then isPassive = result and true or false end
                end
                ACD:Print(string.format("hidden id=%s name=%s rank=%s entry=%s candidate=%s",
                    tostring(spellID), tostring(name), tostring(rank), tostring(entry.ID or entry.id),
                    isPassive and "no-passive" or "yes"))
                hidden = hidden + 1
                if not isPassive then active = active + 1 end
            end
        end
    end
    ACD:Print("hidden known talents=" .. tostring(hidden) .. " active candidates=" .. tostring(active))
end

function Debug:Help()
    ACD:Print("commands: ui, spoof, probe, apiprobe <id>, findhidden, scan, state, peers, request, test, debug, dumpbook [filter], dumptalents [filter]")
end

function Debug:Handle(input)
    input = input or ""
    local command, argument = string.match(input, "^%s*(%S*)%s*(.-)%s*$")
    command = string.lower(command or "")
    if command == "ui" then
        local shown = ACD.TestUI:Toggle()
        ACD:Print("test UI " .. (shown and "shown" or "hidden"))
    elseif command == "spoof" then
        local shown = ACD.SpoofTest:Toggle()
        ACD:Print("SpoofTest " .. (shown and "shown" or "hidden"))
    elseif command == "probe" then self:Probe()
    elseif command == "apiprobe" then self:APIProbe(argument)
    elseif command == "scan" then ACD.Spellbook:Scan("manual"); ACD:Print("scan complete")
    elseif command == "state" then self:State()
    elseif command == "peers" then self:Peers()
    elseif command == "request" then ACD.Comms:RequestState(true); ACD:Print("state requested")
    elseif command == "test" then
        local active = ACD.TestMode:Toggle()
        ACD:Print("test state " .. (active and "enabled" or "disabled") .. "; rows=" .. ACD.Renderer:CountRows())
    elseif command == "debug" then
        ACD.db.profile.debug = not ACD.db.profile.debug
        ACD:Print("debug " .. (ACD.db.profile.debug and "enabled" or "disabled"))
    elseif command == "dumpbook" then ACD.Spellbook:Dump(argument ~= "" and argument or nil)
    elseif command == "dumptalents" then self:DumpTalents(argument ~= "" and argument or nil)
    elseif command == "findhidden" then self:FindHiddenTalents()
    else self:Help() end
end

function Debug:RegisterSlashCommands()
    local key = ACD.Constants.SLASH_KEY
    SlashCmdList[key] = function(input) self:Handle(input) end
    for index, slash in ipairs(ACD.Constants.SLASH_COMMANDS) do
        _G["SLASH_" .. key .. index] = slash
    end
end
