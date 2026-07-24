local ARC = Actually.Modules.RaidCooldowns
local SpecAPIProbe = ARC:NewModule("SpecAPIProbe")

local MAX_LINES = 1200
local EVENT_WORDS = {
    "SPEC", "TALENT", "ADVANCEMENT", "BUILD",
}

local function pack(...)
    return { n = select("#", ...), ... }
end

local function describe(value, depth, seen)
    local valueType = type(value)
    if valueType == "string" then return string.format("%q", value) end
    if valueType ~= "table" then return tostring(value) end
    if (depth or 0) >= 2 then return "{...}" end
    seen = seen or {}
    if seen[value] then return "<recursive>" end
    seen[value] = true
    local parts, count = {}, 0
    for key, child in pairs(value) do
        count = count + 1
        if count > 30 then
            table.insert(parts, "...")
            break
        end
        table.insert(parts, "[" .. describe(key, (depth or 0) + 1, seen)
            .. "]=" .. describe(child, (depth or 0) + 1, seen))
    end
    seen[value] = nil
    table.sort(parts)
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function safeCall(func, ...)
    if type(func) ~= "function" then return false, "unavailable" end
    local results = pack(pcall(func, ...))
    if not results[1] then return false, tostring(results[2]) end
    local values = {}
    for index = 2, results.n do
        table.insert(values, results[index])
    end
    return true, values, results.n - 1
end

local function summarize(value)
    if type(value) == "string" then
        local prefix = string.sub(value, 1, 180)
        return string.format("%q%s (length=%d)", prefix, #value > 180 and "..." or "", #value)
    end
    if type(value) ~= "table" then return tostring(value) end
    local count, samples = 0, {}
    for key, child in pairs(value) do
        count = count + 1
        if table.getn(samples) < 4 then
            table.insert(samples, "[" .. tostring(key) .. "]=" .. describe(child, 1))
        end
    end
    table.sort(samples)
    return string.format("table(count=%d, array=%d) {%s%s}", count, table.getn(value),
        table.concat(samples, ", "), count > table.getn(samples) and ", ..." or "")
end

local function summarizeCall(func, ...)
    local ok, values, valueCount = safeCall(func, ...)
    if not ok then return "ERROR " .. tostring(values) end
    local summaries = {}
    for index = 1, valueCount do
        table.insert(summaries, summarize(values[index]))
    end
    return table.getn(summaries) > 0 and table.concat(summaries, " | ") or "<no values>"
end

local function entryID(entry)
    if type(entry) ~= "table" then return nil end
    return tonumber(entry.ID or entry.id or entry.entryID or entry.EntryID)
end

local function entryName(entry)
    if type(entry) ~= "table" then return nil end
    return entry.name or entry.Name or entry.title or entry.Title
end

local function entrySpells(entry)
    if type(entry) ~= "table" then return {} end
    local spells = entry.Spells or entry.spells
    if type(spells) == "table" then return spells end
    local spellID = tonumber(entry.spellID or entry.spellId or entry.SpellID)
    return spellID and { spellID } or {}
end

local function looksRelevantEvent(event)
    event = string.upper(tostring(event or ""))
    if event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then return true end
    for _, word in ipairs(EVENT_WORDS) do
        if string.find(event, word, 1, true) then return true end
    end
    return false
end

function SpecAPIProbe:Append(text, color)
    text = tostring(text)
    table.insert(self.lines, (color or "") .. text .. (color and "|r" or ""))
    while table.getn(self.lines) > MAX_LINES do table.remove(self.lines, 1) end
    if not self.output then return end
    self.output:SetText(table.concat(self.lines, "\n"))
    self.output:SetCursorPosition(0)
    local height = math.max(1, table.getn(self.lines) * 14 + 8)
    self.output:SetHeight(height)
    self.scrollChild:SetHeight(height)
    if self.scrollFrame and self.scrollFrame.UpdateScrollChildRect then
        self.scrollFrame:UpdateScrollChildRect()
    end
end

function SpecAPIProbe:Heading(text)
    self:Append("")
    self:Append("== " .. tostring(text) .. " ==", "|cff69ccf0")
end

function SpecAPIProbe:Clear()
    self.lines = {}
    if self.output then self.output:SetText("") end
    if self.scrollChild then self.scrollChild:SetHeight(1) end
end

function SpecAPIProbe:GetActiveSpec()
    local advancement = C_CharacterAdvancement
    local func = advancement and advancement.GetActiveChrSpec
    local ok, values = safeCall(func)
    if not ok then return nil, values end
    return values[1], values
end

function SpecAPIProbe:GetActiveBook()
    local advancement = C_CharacterAdvancement
    local func = advancement and advancement.GetActiveSpecID
    local ok, values = safeCall(func)
    if not ok then return nil, values end
    return tonumber(values[1]), values
end

function SpecAPIProbe:GetKnownEntries()
    local advancement = C_CharacterAdvancement
    local func = advancement and advancement.GetKnownTalentEntries
    local ok, values = safeCall(func)
    if not ok then return nil, values end
    if type(values[1]) ~= "table" then
        return nil, "returned " .. describe(values[1], 0)
    end
    return values[1]
end

function SpecAPIProbe:RefreshHeader()
    if not self.frame then return end
    local chrSpec = self:GetActiveSpec()
    local activeBook = self:GetActiveBook()
    self.frame.status:SetText("Active book: " .. tostring(activeBook or "unknown")
        .. "   ChrSpec ID: " .. tostring(chrSpec or "unknown")
        .. "   Selected probe book: " .. tostring(self.selectedSpec))
end

function SpecAPIProbe:ProbeAPIs()
    self:Heading("Ascension API inventory")
    if type(C_CharacterAdvancement) ~= "table" then
        self:Append("C_CharacterAdvancement is " .. type(C_CharacterAdvancement), "|cffff6666")
        return
    end

    local names = {}
    for name, value in pairs(C_CharacterAdvancement) do
        local lowerName = string.lower(tostring(name))
        if type(value) == "function" and (string.find(lowerName, "spec", 1, true)
            or string.find(lowerName, "talent", 1, true)
            or string.find(lowerName, "spell", 1, true)
            or string.find(lowerName, "entry", 1, true)
            or string.find(lowerName, "build", 1, true)) then
            table.insert(names, tostring(name))
        end
    end
    table.sort(names)
    self:Append("Relevant C_CharacterAdvancement functions: " .. tostring(table.getn(names)))
    for _, name in ipairs(names) do self:Append("  " .. name .. "()") end

    for _, globalName in ipairs({
        "CA_IsSpellKnown", "CA_GetTalentInfo", "CA_GetEntryRank",
        "CAO_Known", "CAO_Talent_References", "CAO_Talents", "CAO_Spells",
    }) do
        self:Append(globalName .. " type=" .. type(_G[globalName]))
    end
end

function SpecAPIProbe:ProbeActive()
    self:Heading("Active specialization")
    local chrSpec, valuesOrError = self:GetActiveSpec()
    if chrSpec == nil then
        self:Append("GetActiveChrSpec failed: " .. tostring(valuesOrError), "|cffff6666")
    else
        self:Append("GetActiveChrSpec (internal ID) => "
            .. describe(valuesOrError, 0), "|cff55dd55")
    end
    local activeBook, bookValues = self:GetActiveBook()
    if activeBook then
        self:Append("GetActiveSpecID (book number) => "
            .. describe(bookValues, 0), "|cff55dd55")
        self:SetSelectedSpec(activeBook)
    else
        self:Append("GetActiveSpecID failed: " .. tostring(bookValues), "|cffff6666")
    end
    self:RefreshHeader()
end

function SpecAPIProbe:CountRanksForSpec(entries, spec)
    local advancement = C_CharacterAdvancement
    local rankFunc = advancement and advancement.UnitTalentRankByID
    if type(rankFunc) ~= "function" then return nil, "unavailable" end
    local ranked, errors = 0, 0
    for _, entry in ipairs(entries or {}) do
        local id = entryID(entry)
        if id then
            local ok, values = safeCall(rankFunc, "player", id, spec)
            if not ok then
                errors = errors + 1
            elseif (tonumber(values[1]) or 0) > 0 then
                ranked = ranked + 1
            end
        end
    end
    return ranked, errors
end

function SpecAPIProbe:ProbeBookMatrix()
    self:Heading("Active build status")
    local advancement = C_CharacterAdvancement
    if type(advancement) ~= "table" then
        self:Append("C_CharacterAdvancement unavailable", "|cffff6666")
        return
    end
    self:Append("GetActiveSpecID (book number) => "
        .. summarizeCall(advancement.GetActiveSpecID))
    self:Append("GetActiveChrSpec (internal ID) => "
        .. summarizeCall(advancement.GetActiveChrSpec))
    self:Append("IsActiveBuildAvailable() => "
        .. summarizeCall(advancement.IsActiveBuildAvailable))
    self:Append("CanSwitchActiveChrSpec() => "
        .. summarizeCall(advancement.CanSwitchActiveChrSpec))
    self:Append("The last two APIs describe the current build; they do not enumerate unlocked books.",
        "|cffffcc55")
end

function SpecAPIProbe:ProbeSelectedBookReads()
    self:Heading("Active-build read API behavior")
    local advancement = C_CharacterAdvancement
    if type(advancement) ~= "table" then
        self:Append("C_CharacterAdvancement unavailable", "|cffff6666")
        return
    end
    local calls = {
        { "GetKnownSpells()", advancement.GetKnownSpells },
        { "GetKnownSpellEntries()", advancement.GetKnownSpellEntries },
        { "GetKnownTalentEntries()", advancement.GetKnownTalentEntries },
        { "ExportBuild(false)", advancement.ExportBuild, false },
        { "ExportBuild(true)", advancement.ExportBuild, true },
    }
    for _, call in ipairs(calls) do
        self:Append("  " .. call[1] .. " => " .. summarizeCall(call[2], unpack(call, 3)))
    end
end

function SpecAPIProbe:CaptureEnvironment()
    self:Heading("ENVIRONMENT AND API FINGERPRINT")
    local version, build, buildDate, interfaceVersion
    if type(GetBuildInfo) == "function" then
        version, build, buildDate, interfaceVersion = GetBuildInfo()
    end
    local localizedClass, classToken = UnitClass and UnitClass("player")
    self:Append(string.format(
        "realm=%s player=%s class=%s classToken=%s clientVersion=%s build=%s buildDate=%s interface=%s locale=%s",
        tostring(GetRealmName and GetRealmName() or "?"),
        tostring(UnitName and UnitName("player") or "?"),
        tostring(localizedClass), tostring(classToken), tostring(version), tostring(build),
        tostring(buildDate), tostring(interfaceVersion),
        tostring(GetLocale and GetLocale() or "?")))

    local advancement = C_CharacterAdvancement
    self:Append("C_CharacterAdvancement type=" .. type(advancement))
    local functionNames = {}
    if type(advancement) == "table" then
        for name, value in pairs(advancement) do
            if type(value) == "function" then table.insert(functionNames, tostring(name)) end
        end
        table.sort(functionNames)
    end
    self:Append("C_CharacterAdvancement functions(" .. tostring(table.getn(functionNames))
        .. ")=" .. table.concat(functionNames, ","))

    local capabilityNames = {
        "GetActiveSpecID", "GetActiveChrSpec", "GetKnownSpells", "GetKnownSpellEntries",
        "GetKnownTalentEntries", "GetTalentRankByID", "UnitTalentRankByID", "ExportBuild",
        "GetSpellsByClass", "GetTalentsByClass", "GetKnownSpellEntriesForClass",
        "GetKnownTalentEntriesForClass", "IsKnownSpellID", "SwitchActiveChrSpec",
    }
    local capabilities = {}
    for _, name in ipairs(capabilityNames) do
        table.insert(capabilities, name .. "=" .. type(type(advancement) == "table"
            and advancement[name] or nil))
    end
    for _, name in ipairs({
        "CA_IsSpellKnown", "IsSpellKnown", "GetNumSpellTabs", "GetSpellTabInfo",
        "GetSpellBookItemInfo", "GetSpellBookItemName",
    }) do
        table.insert(capabilities, name .. "=" .. type(_G[name]))
    end
    self:Append("scannerCapabilities={" .. table.concat(capabilities, ",") .. "}")
end

local function sortedNumericValues(values)
    local result = {}
    if type(values) ~= "table" then return result end
    for _, value in pairs(values) do
        value = tonumber(value)
        if value then table.insert(result, value) end
    end
    table.sort(result)
    return result
end

local function joinedNumericValues(values)
    local strings = {}
    for _, value in ipairs(sortedNumericValues(values)) do
        table.insert(strings, tostring(value))
    end
    return table.concat(strings, ",")
end

local function joinedNumericKeys(values)
    local numbers, strings = {}, {}
    for key, enabled in pairs(type(values) == "table" and values or {}) do
        if enabled and tonumber(key) then table.insert(numbers, tonumber(key)) end
    end
    table.sort(numbers)
    for _, value in ipairs(numbers) do table.insert(strings, tostring(value)) end
    return table.concat(strings, ",")
end

function SpecAPIProbe:CaptureActiveBuild(reason)
    local advancement = C_CharacterAdvancement
    local book = self:GetActiveBook()
    local chrSpec = self:GetActiveSpec()
    self:Heading("AUTOMATED CAPTURE book " .. tostring(book) .. " (" .. tostring(reason) .. ")")
    self:Append("activeBook=" .. tostring(book) .. " chrSpecID=" .. tostring(chrSpec),
        "|cff55dd55")

    local knownSpells, spellEntries, talentEntries
    local spellsOK, spellValues = safeCall(advancement and advancement.GetKnownSpells)
    if spellsOK then knownSpells = spellValues[1] end
    local abilitiesOK, abilityValues = safeCall(advancement and advancement.GetKnownSpellEntries)
    if abilitiesOK then spellEntries = abilityValues[1] end
    local talentsOK, talentValues = safeCall(advancement and advancement.GetKnownTalentEntries)
    if talentsOK then talentEntries = talentValues[1] end

    self:Append("knownSpells count=" .. tostring(type(knownSpells) == "table"
        and table.getn(knownSpells) or 0) .. " ids=" .. joinedNumericValues(knownSpells))

    self:Append("abilityEntries count=" .. tostring(type(spellEntries) == "table"
        and table.getn(spellEntries) or 0))
    for _, entry in ipairs(type(spellEntries) == "table" and spellEntries or {}) do
        self:Append(string.format("  ability entry=%s name=%s tab=%s spells=%s",
            tostring(entryID(entry)), tostring(entryName(entry) or "?"),
            tostring(entry.Tab or entry.tab or "?"), joinedNumericValues(entrySpells(entry))))
    end

    self:Append("talentEntries count=" .. tostring(type(talentEntries) == "table"
        and table.getn(talentEntries) or 0))
    for _, entry in ipairs(type(talentEntries) == "table" and talentEntries or {}) do
        local id = entryID(entry)
        local rankText = "unavailable"
        if id and advancement and type(advancement.GetTalentRankByID) == "function" then
            rankText = summarizeCall(advancement.GetTalentRankByID, id)
        end
        self:Append(string.format("  talent entry=%s rank=%s name=%s tab=%s spells=%s",
            tostring(id), rankText, tostring(entryName(entry) or "?"),
            tostring(entry.Tab or entry.tab or "?"), joinedNumericValues(entrySpells(entry))))
    end

    local tabs, spellbookCount = GetNumSpellTabs and GetNumSpellTabs() or 0, 0
    local tabSummary = {}
    for tab = 1, tabs do
        local tabName, _, _, count = GetSpellTabInfo(tab)
        count = tonumber(count) or 0
        spellbookCount = spellbookCount + count
        table.insert(tabSummary, tostring(tabName) .. "=" .. tostring(count))
    end
    self:Append("spellbook total=" .. tostring(spellbookCount)
        .. " tabs={" .. table.concat(tabSummary, ", ") .. "}")
    self:Append("ExportBuild(false) => "
        .. summarizeCall(advancement and advancement.ExportBuild, false))
    self:Append("ExportBuild(true) => "
        .. summarizeCall(advancement and advancement.ExportBuild, true))

    if self.autoRun and book then self.autoRun.captured[book] = true end
end

function SpecAPIProbe:FindChangeSpecSlashHandler()
    if type(SlashCmdList) ~= "table" then return nil end
    for key, handler in pairs(SlashCmdList) do
        if type(handler) == "function" then
            for index = 1, 20 do
                local slash = _G["SLASH_" .. tostring(key) .. tostring(index)]
                if type(slash) == "string" and string.lower(slash) == "/cs" then
                    return handler, key
                end
            end
        end
    end
    return nil
end

function SpecAPIProbe:InvokeChangeSpec(book)
    local handler, key = self:FindChangeSpecSlashHandler()
    if handler then
        local ok, result = pcall(handler, tostring(book))
        if not ok then return false, result end
        return true, "SlashCmdList[" .. tostring(key) .. "] => " .. tostring(result)
    end

    if type(ChatEdit_ParseText) ~= "function" then
        return false, "ChatEdit_ParseText unavailable"
    end
    local editBox
    if type(ChatEdit_ChooseBoxForSend) == "function" then
        local chooseOK, chosen = pcall(ChatEdit_ChooseBoxForSend)
        if chooseOK then editBox = chosen end
    end
    editBox = editBox or ChatFrameEditBox
    if not editBox or type(editBox.SetText) ~= "function"
        or type(editBox.GetText) ~= "function" then
        return false, "chat edit box unavailable"
    end

    local priorText = editBox:GetText() or ""
    local priorCursor = type(editBox.GetCursorPosition) == "function"
        and editBox:GetCursorPosition() or 0
    local parseOK, parseResult = pcall(function()
        editBox:SetText("/cs " .. tostring(book))
        return ChatEdit_ParseText(editBox, 1)
    end)
    editBox:SetText(priorText)
    if type(editBox.SetCursorPosition) == "function" then
        editBox:SetCursorPosition(math.min(priorCursor, #priorText))
    end
    if not parseOK then return false, parseResult end
    return true, "ChatEdit_ParseText('/cs " .. tostring(book)
        .. "', send=1) => " .. tostring(parseResult)
end

function SpecAPIProbe:ScheduleAutomatedRun(delay, callback)
    if self.autoTimer then ARC:CancelTimer(self.autoTimer, true) end
    self.autoTimer = ARC:ScheduleTimer(function()
        self.autoTimer = nil
        if self.autoRun then callback(self) end
    end, delay or 0.1)
end

function SpecAPIProbe:FinishAutomatedRun(message)
    local run = self.autoRun
    if not run then return end
    self:Append("")
    self:Append(message, "|cff55dd55")
    self:Append("Captured books: " .. joinedNumericKeys(run.captured))
    self:Append("Click Select all, press Ctrl+C, and send the result.", "|cff69ccf0")
    self.autoRun = nil
    if self.autoButton then self.autoButton:Enable() end
    if self.cancelButton then self.cancelButton:Disable() end
    self:RefreshHeader()
end

function SpecAPIProbe:PollOriginalBook()
    local run = self.autoRun
    if not run then return end
    if self:GetActiveBook() == run.originalBook then
        self:FinishAutomatedRun("Automated /cs test complete; original book restored.")
        return
    end
    if ARC:Now() >= run.deadline then
        self:FinishAutomatedRun("Automated /cs test complete, but restoration timed out. "
            .. "Please type /cs " .. tostring(run.originalBook) .. " manually.")
        return
    end
    self:ScheduleAutomatedRun(0.25, self.PollOriginalBook)
end

function SpecAPIProbe:RestoreOriginalBook()
    local run = self.autoRun
    if not run then return end
    if self:GetActiveBook() == run.originalBook then
        self:FinishAutomatedRun("Automated /cs test complete; original book already active.")
        return
    end
    self:Append("Returning to original book with /cs " .. tostring(run.originalBook) .. "...")
    local ok, reason = self:InvokeChangeSpec(run.originalBook)
    if not ok then
        self:FinishAutomatedRun("Test complete, but /cs restoration failed: " .. tostring(reason))
        return
    end
    run.deadline = ARC:Now() + 12
    self:ScheduleAutomatedRun(0.25, self.PollOriginalBook)
end

function SpecAPIProbe:CaptureSwitchedBook()
    local run = self.autoRun
    if not run then return end
    self:CaptureActiveBuild("activated through /cs")
    run.targetBook = run.targetBook + 1
    self:ScheduleAutomatedRun(0.5, self.AutomatedRunStep)
end

function SpecAPIProbe:PollTargetBook()
    local run = self.autoRun
    if not run then return end
    if self:GetActiveBook() == run.targetBook then
        self:Append("/cs activated book " .. tostring(run.targetBook)
            .. "; waiting for build data to settle.")
        self:ScheduleAutomatedRun(2, self.CaptureSwitchedBook)
        return
    end
    if ARC:Now() >= run.deadline then
        self:Append("Book " .. tostring(run.targetBook)
            .. " did not activate through /cs; stopping at the first unavailable book.",
            "|cffffcc55")
        self:RestoreOriginalBook()
        return
    end
    self:ScheduleAutomatedRun(0.25, self.PollTargetBook)
end

function SpecAPIProbe:AutomatedRunStep()
    local run = self.autoRun
    if not run then return end
    if run.cancelled or run.targetBook > 12 then
        self:RestoreOriginalBook()
        return
    end
    if run.captured[run.targetBook] then
        run.targetBook = run.targetBook + 1
        self:ScheduleAutomatedRun(0.1, self.AutomatedRunStep)
        return
    end

    self:Append("Invoking Ascension command /cs " .. tostring(run.targetBook) .. "...")
    local ok, reason = self:InvokeChangeSpec(run.targetBook)
    self:Append("  " .. tostring(reason))
    if not ok then
        self:RestoreOriginalBook()
        return
    end
    run.deadline = ARC:Now() + 12
    self:ScheduleAutomatedRun(0.25, self.PollTargetBook)
end

function SpecAPIProbe:RunAutomatedTest()
    local activeBook = self:GetActiveBook()
    if not activeBook then
        self:Append("Cannot determine the active specialization book.", "|cffff6666")
        return
    end
    local slashHandler, slashKey = self:FindChangeSpecSlashHandler()
    local hasChatParser = type(ChatEdit_ParseText) == "function"
        and (type(ChatEdit_ChooseBoxForSend) == "function" or ChatFrameEditBox)
    if not slashHandler and not hasChatParser then
        self:Append("Neither a /cs handler nor Ascension's chat parser is available.",
            "|cffff6666")
        return
    end

    self:Clear()
    self.autoRun = {
        originalBook = activeBook,
        targetBook = 1,
        captured = {},
        slashKey = slashKey,
        switchRoute = slashHandler and "SlashCmdList" or "ChatEdit_ParseText",
    }
    self:Heading("ONE-CLICK AUTOMATED /cs SPEC TEST")
    self:Append("Starting on book " .. tostring(activeBook)
        .. ". Switching uses Ascension's registered /cs command handler, not "
        .. "C_CharacterAdvancement.SwitchActiveChrSpec.", "|cff69ccf0")
    self:Append("Detected /cs route: " .. tostring(self.autoRun.switchRoute)
        .. (slashKey and (" key=" .. tostring(slashKey)) or ""))
    self:CaptureEnvironment()
    self:CaptureActiveBuild("starting book")
    if self.autoButton then self.autoButton:Disable() end
    if self.cancelButton then self.cancelButton:Enable() end
    self:ScheduleAutomatedRun(0.5, self.AutomatedRunStep)
end

function SpecAPIProbe:CancelAutomatedTest()
    if not self.autoRun then return end
    self.autoRun.cancelled = true
    self:Append("Cancellation requested; returning to the starting book.", "|cffffcc55")
    self:RestoreOriginalBook()
end

function SpecAPIProbe:ProbeSpec()
    self:Heading("Talent ranks for specialization book " .. tostring(self.selectedSpec))
    local entries, reason = self:GetKnownEntries()
    if not entries then
        self:Append("GetKnownTalentEntries failed: " .. tostring(reason), "|cffff6666")
        return
    end
    local advancement = C_CharacterAdvancement
    local rankFunc = advancement and advancement.UnitTalentRankByID
    if type(rankFunc) ~= "function" then
        self:Append("UnitTalentRankByID is unavailable", "|cffff6666")
        return
    end

    local tested, ranked, errors = 0, 0, 0
    local results = {}
    for _, entry in ipairs(entries) do
        local id = entryID(entry)
        if id then
            tested = tested + 1
            local ok, values = safeCall(rankFunc, "player", id, self.selectedSpec)
            if not ok then
                errors = errors + 1
                if errors <= 5 then
                    table.insert(results, "  ERROR entry=" .. tostring(id) .. ": " .. tostring(values))
                end
            else
                local rank = tonumber(values[1]) or 0
                if rank > 0 then
                    ranked = ranked + 1
                    local spellIDs = {}
                    for _, spellID in ipairs(entrySpells(entry)) do
                        table.insert(spellIDs, tostring(spellID))
                    end
                    table.insert(results, string.format("  entry=%s rank=%s values=%s name=%s spells=%s",
                        tostring(id), tostring(rank), describe(values, 0),
                        tostring(entryName(entry) or "?"), table.concat(spellIDs, ",")))
                end
            end
        end
    end
    self:Append(string.format("tested=%d ranked=%d errors=%d", tested, ranked, errors),
        errors == 0 and "|cff55dd55" or "|cffffcc55")
    for _, line in ipairs(results) do self:Append(line) end
    if ranked == 0 then
        self:Append("No positive ranks. This may mean the book is locked/empty, or the API's spec argument differs.")
    end
end

function SpecAPIProbe:DumpSpellbook()
    self:Heading("Complete active spellbook")
    local tabs = GetNumSpellTabs and GetNumSpellTabs() or 0
    local total = 0
    for tab = 1, tabs do
        local tabName, _, offset, count = GetSpellTabInfo(tab)
        offset, count = tonumber(offset) or 0, tonumber(count) or 0
        self:Append(string.format("Tab %d: %s offset=%d count=%d",
            tab, tostring(tabName), offset, count), "|cffccccff")
        for slot = offset + 1, offset + count do
            local itemType, spellID = GetSpellBookItemInfo(slot, ARC.Constants.BOOK_TYPE)
            local spellName, spellRank = GetSpellBookItemName(slot, ARC.Constants.BOOK_TYPE)
            self:Append(string.format("  slot=%d type=%s id=%s name=%s rank=%s",
                slot, tostring(itemType), tostring(spellID), tostring(spellName), tostring(spellRank)))
            total = total + 1
        end
    end
    self:Append("Total active spellbook entries: " .. tostring(total), "|cff55dd55")
end

function SpecAPIProbe:DumpTalents()
    self:Heading("Known talent entry schema")
    local entries, reason = self:GetKnownEntries()
    if not entries then
        self:Append("GetKnownTalentEntries failed: " .. tostring(reason), "|cffff6666")
        return
    end
    self:Append("Known talent entries: " .. tostring(table.getn(entries)), "|cff55dd55")
    for index, entry in ipairs(entries) do
        self:Append("  [" .. tostring(index) .. "] " .. describe(entry, 0))
    end
end

function SpecAPIProbe:SetSelectedSpec(value)
    self.selectedSpec = math.max(1, math.min(12, tonumber(value) or 1))
    self:RefreshHeader()
end

function SpecAPIProbe:StartEventCapture()
    if not self.eventFrame then return end
    self.eventFrame:UnregisterAllEvents()
    if type(self.eventFrame.RegisterAllEvents) == "function" then
        self.eventFrame:RegisterAllEvents()
        self.lastObservedBook = self:GetActiveBook()
        self.lastObservedChrSpec = self:GetActiveSpec()
        self:Append("Event capture enabled (relevant events only are displayed).", "|cffaaaaaa")
        return
    end
    for _, event in ipairs({
        "PLAYER_TALENT_UPDATE", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB",
        "ACTIVE_TALENT_GROUP_CHANGED", "CHARACTER_POINTS_CHANGED",
        "PLAYER_ENTERING_WORLD",
    }) do
        pcall(self.eventFrame.RegisterEvent, self.eventFrame, event)
    end
    self:Append("Filtered event capture enabled.", "|cffaaaaaa")
end

function SpecAPIProbe:StopEventCapture()
    if self.eventFrame then self.eventFrame:UnregisterAllEvents() end
end

function SpecAPIProbe:Toggle()
    if self.frame:IsShown() then
        self.frame:Hide()
        return false
    end
    self.frame:Show()
    return true
end

local function createButton(parent, text, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetWidth(width)
    button:SetHeight(22)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

function SpecAPIProbe:Initialize()
    self.lines = {}
    self.selectedSpec = 1

    local frame = CreateFrame("Frame", "ActuallyARCSpecAPIProbeFrame", UIParent)
    frame:SetWidth(760)
    frame:SetHeight(590)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(window) window:StartMoving() end)
    frame:SetScript("OnDragStop", function(window) window:StopMovingOrSizing() end)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.03, 0.04, 0.07, 0.97)
    frame:SetBackdropBorderColor(0.30, 0.65, 0.85, 1)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -12)
    frame.title:SetText("ARC Ascension Build / Spec API Probe")

    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)

    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.status:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -6)

    local apiButton = createButton(frame, "API inventory", 94, function() self:ProbeAPIs() end)
    apiButton:SetPoint("TOPLEFT", frame.status, "BOTTOMLEFT", 0, -9)
    local activeButton = createButton(frame, "Active book", 82, function() self:ProbeActive() end)
    activeButton:SetPoint("LEFT", apiButton, "RIGHT", 5, 0)
    local previousButton = createButton(frame, "<", 26, function()
        self:SetSelectedSpec(self.selectedSpec - 1)
    end)
    previousButton:SetPoint("LEFT", activeButton, "RIGHT", 10, 0)
    local probeButton = createButton(frame, "Probe book 1", 98, function() self:ProbeSpec() end)
    probeButton:SetPoint("LEFT", previousButton, "RIGHT", 3, 0)
    self.probeButton = probeButton
    local nextButton = createButton(frame, ">", 26, function()
        self:SetSelectedSpec(self.selectedSpec + 1)
    end)
    nextButton:SetPoint("LEFT", probeButton, "RIGHT", 3, 0)
    local spellbookButton = createButton(frame, "Spellbook", 78, function() self:DumpSpellbook() end)
    spellbookButton:SetPoint("LEFT", nextButton, "RIGHT", 10, 0)
    local talentsButton = createButton(frame, "Talent schema", 94, function() self:DumpTalents() end)
    talentsButton:SetPoint("LEFT", spellbookButton, "RIGHT", 5, 0)
    local clearButton = createButton(frame, "Clear", 55, function() self:Clear() end)
    clearButton:SetPoint("LEFT", talentsButton, "RIGHT", 5, 0)
    local copyButton = createButton(frame, "Select all", 68, function()
        self.output:SetFocus()
        self.output:HighlightText()
    end)
    copyButton:SetPoint("LEFT", clearButton, "RIGHT", 5, 0)

    local matrixButton = createButton(frame, "Active status", 94, function()
        self:ProbeBookMatrix()
    end)
    matrixButton:SetPoint("TOPLEFT", apiButton, "BOTTOMLEFT", 0, -5)
    local readButton = createButton(frame, "Read active build APIs", 155, function()
        self:ProbeSelectedBookReads()
    end)
    readButton:SetPoint("LEFT", matrixButton, "RIGHT", 5, 0)
    local autoButton = createButton(frame, "Run all books via /cs", 150, function()
        self:RunAutomatedTest()
    end)
    autoButton:SetPoint("LEFT", readButton, "RIGHT", 8, 0)
    local cancelButton = createButton(frame, "Cancel", 58, function()
        self:CancelAutomatedTest()
    end)
    cancelButton:SetPoint("LEFT", autoButton, "RIGHT", 5, 0)
    cancelButton:Disable()
    self.autoButton = autoButton
    self.cancelButton = cancelButton

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -118)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -31, 14)
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(706)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    local output = CreateFrame("EditBox", nil, scrollChild)
    output:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 2, -2)
    output:SetWidth(700)
    output:SetHeight(1)
    output:SetMultiLine(true)
    output:SetAutoFocus(false)
    output:SetFontObject(GameFontHighlightSmall)
    output:SetJustifyH("LEFT")
    output:SetTextInsets(0, 0, 0, 0)
    output:SetScript("OnEscapePressed", function(editBox)
        editBox:HighlightText(0, 0)
        editBox:ClearFocus()
    end)
    output:SetText("")

    self.frame = frame
    self.scrollFrame = scrollFrame
    self.scrollChild = scrollChild
    self.output = output

    local eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event, ...)
        if not self.frame:IsShown() then return end
        local activeBook = self:GetActiveBook()
        local chrSpec = self:GetActiveSpec()
        if activeBook ~= self.lastObservedBook or chrSpec ~= self.lastObservedChrSpec then
            self:Append(string.format(
                "[spec change %.3f] event=%s book %s -> %s, ChrSpec %s -> %s",
                ARC:Now(), tostring(event), tostring(self.lastObservedBook), tostring(activeBook),
                tostring(self.lastObservedChrSpec), tostring(chrSpec)), "|cff55dd55")
            self.lastObservedBook = activeBook
            self.lastObservedChrSpec = chrSpec
            self:SetSelectedSpec(activeBook or self.selectedSpec)
        end
        if looksRelevantEvent(event) then
            local values = { ... }
            local shown = {}
            for index = 1, math.min(table.getn(values), 5) do
                table.insert(shown, describe(values[index], 0))
            end
            self:Append(string.format("[event %.3f] %s %s", ARC:Now(), tostring(event),
                table.concat(shown, " ")), "|cffffcc55")
            self:RefreshHeader()
        end
    end)
    self.eventFrame = eventFrame

    frame:SetScript("OnShow", function()
        self:RefreshHeader()
        self:StartEventCapture()
        if table.getn(self.lines) == 0 then
            self:Append("Read-only probe. It never activates a specialization or changes talents.")
            self:ProbeActive()
            self:ProbeAPIs()
        end
    end)
    frame:SetScript("OnHide", function() self:StopEventCapture() end)
    frame:Hide()
    self.initialized = true
end

local originalSetSelectedSpec = SpecAPIProbe.SetSelectedSpec
function SpecAPIProbe:SetSelectedSpec(value)
    originalSetSelectedSpec(self, value)
    if self.probeButton then
        self.probeButton:SetText("Probe book " .. tostring(self.selectedSpec))
    end
end
