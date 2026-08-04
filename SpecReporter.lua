local Addon = Actually

local Reporter = {}
Addon.SpecReporter = Reporter

local PREFIX = "ACTSPECS"
local PROTOCOL = 1
local CHUNK_SIZE = 160
local SEND_INTERVAL = 0.20
local BOOK_TRANSFER_SECONDS = 15
local MAX_QUEUE = 500
local COLLECTOR_TIMEOUT = 600
local MIN_SCAN_INTERVAL = 5

local function Now()
    return GetTime and GetTime() or 0
end

local function Stamp()
    return time and time() or 0
end

local function Encode(value)
    return string.gsub(tostring(value or ""), "([^%w%-%._ ])", function(character)
        return string.format("%%%02X", string.byte(character))
    end)
end

local function Hash(value)
    local hash = 5381
    value = tostring(value or "")
    for index = 1, string.len(value) do
        hash = (hash * 33 + string.byte(value, index)) % 2147483647
    end
    return tostring(hash)
end

local function Normalize(identity)
    if Addon.Util and Addon.Util.NormalizeCharacter then
        return Addon.Util.NormalizeCharacter(identity)
    end
    return string.lower(string.match(tostring(identity or ""), "^[^-]+") or "")
end

local function CharacterName()
    if GetUnitName then
        local name = GetUnitName("player", true)
        if name and name ~= "" then return name end
    end
    local name = UnitName and UnitName("player") or "Unknown"
    local realm = GetRealmName and GetRealmName() or ""
    realm = string.gsub(realm, "%s+", "")
    return realm ~= "" and (name .. "-" .. realm) or name
end

local function SafeCall(func, ...)
    if type(func) ~= "function" then return false, "unavailable" end
    local results = { pcall(func, ...) }
    if not results[1] then return false, results[2] end
    table.remove(results, 1)
    return true, results
end

local function EntryID(entry)
    return type(entry) == "table"
        and tonumber(entry.ID or entry.id or entry.entryID or entry.EntryID) or nil
end

local function EntrySpells(entry)
    if type(entry) ~= "table" then return {} end
    local spells = entry.Spells or entry.spells
    if type(spells) == "table" then return spells end
    local spellID = tonumber(entry.spellID or entry.spellId or entry.SpellID)
    return spellID and { spellID } or {}
end

local function SortedUniqueNumbers(values)
    local present, result = {}, {}
    for _, value in pairs(type(values) == "table" and values or {}) do
        value = tonumber(value)
        if value and value > 0 and not present[value] then
            present[value] = true
            table.insert(result, value)
        end
    end
    table.sort(result)
    return result
end

local function JoinNumbers(values)
    local result = {}
    for _, value in ipairs(SortedUniqueNumbers(values)) do
        table.insert(result, tostring(value))
    end
    return table.concat(result, ",")
end

local function SortedEntries(entries)
    local result = {}
    for _, entry in ipairs(type(entries) == "table" and entries or {}) do
        if EntryID(entry) then table.insert(result, entry) end
    end
    table.sort(result, function(left, right) return EntryID(left) < EntryID(right) end)
    return result
end

local function ActiveBook()
    local advancement = C_CharacterAdvancement
    if advancement and type(advancement.GetActiveSpecID) == "function" then
        local ok, values = SafeCall(advancement.GetActiveSpecID)
        local book = ok and tonumber(values[1]) or nil
        if book and book >= 1 and book <= 99 then return math.floor(book), "active-spec-id" end
    end
    return 1, "active-only-fallback"
end

local function ActiveChrSpec()
    local advancement = C_CharacterAdvancement
    if advancement and type(advancement.GetActiveChrSpec) == "function" then
        local ok, values = SafeCall(advancement.GetActiveChrSpec)
        if ok then return tonumber(values[1]) end
    end
    return nil
end

local function SpellbookFallback()
    local spells = {}
    local tabs = GetNumSpellTabs and GetNumSpellTabs() or 0
    for tab = 1, tabs do
        local _, _, offset, count = GetSpellTabInfo(tab)
        offset, count = tonumber(offset) or 0, tonumber(count) or 0
        for slot = offset + 1, offset + count do
            local _, spellID = GetSpellBookItemInfo(slot, BOOKTYPE_SPELL or "spell")
            if tonumber(spellID) then table.insert(spells, tonumber(spellID)) end
        end
    end
    return spells
end

local function BuildSnapshot()
    local advancement = C_CharacterAdvancement
    local book, mode = ActiveBook()
    local knownSpells, abilityEntries, talentEntries = {}, {}, {}

    if advancement and type(advancement.GetKnownSpells) == "function" then
        local ok, values = SafeCall(advancement.GetKnownSpells)
        if ok and type(values[1]) == "table" then knownSpells = values[1] end
    else
        knownSpells = SpellbookFallback()
        mode = mode .. "+spellbook"
    end
    if advancement and type(advancement.GetKnownSpellEntries) == "function" then
        local ok, values = SafeCall(advancement.GetKnownSpellEntries)
        if ok and type(values[1]) == "table" then abilityEntries = values[1] end
    end
    if advancement and type(advancement.GetKnownTalentEntries) == "function" then
        local ok, values = SafeCall(advancement.GetKnownTalentEntries)
        if ok and type(values[1]) == "table" then talentEntries = values[1] end
    end

    local abilityRows = {}
    for _, entry in ipairs(SortedEntries(abilityEntries)) do
        table.insert(abilityRows, tostring(EntryID(entry)) .. ":" .. JoinNumbers(EntrySpells(entry)))
    end

    local talentRows = {}
    for _, entry in ipairs(SortedEntries(talentEntries)) do
        local id = EntryID(entry)
        local rank, maximum = 0, 0
        if advancement and type(advancement.GetTalentRankByID) == "function" then
            local ok, values = SafeCall(advancement.GetTalentRankByID, id)
            if ok then
                rank = math.max(0, tonumber(values[1]) or 0)
                maximum = math.max(rank, tonumber(values[2]) or 0)
            end
        end
        table.insert(talentRows, table.concat({
            tostring(id), tostring(rank), tostring(maximum), JoinNumbers(EntrySpells(entry)),
        }, ":"))
    end

    local exported = ""
    if advancement and type(advancement.ExportBuild) == "function" then
        local ok, values = SafeCall(advancement.ExportBuild, false)
        if ok and type(values[1]) == "string" then exported = values[1] end
    end

    local localizedClass, classToken = UnitClass and UnitClass("player")
    local lines = {
        "V\t" .. tostring(PROTOCOL),
        "N\t" .. Encode(CharacterName()),
        "R\t" .. Encode(GetRealmName and GetRealmName() or ""),
        "C\t" .. Encode(localizedClass or classToken or ""),
        "M\t" .. Encode(mode),
        "B\t" .. tostring(book),
        "I\t" .. tostring(ActiveChrSpec() or ""),
        "D\t" .. tostring(Stamp()),
        "S\t" .. JoinNumbers(knownSpells),
        "A\t" .. table.concat(abilityRows, ";"),
        "T\t" .. table.concat(talentRows, ";"),
        "X\t" .. Encode(exported),
    }
    return {
        book = book,
        payload = table.concat(lines, "\n"),
        capturedAt = Stamp(),
    }
end

function Reporter:IsCollector(sender)
    return Addon.Official and type(Addon.Official.IsLeader) == "function"
        and Addon.Official:IsLeader(sender) == true
end

function Reporter:Queue(message, target, readyAt)
    if type(message) ~= "string" or #message > 240 or not target or target == ""
        or table.getn(self.queue) >= MAX_QUEUE then return false end
    table.insert(self.queue, {
        message = message,
        target = target,
        readyAt = tonumber(readyAt) or Now(),
    })
    return true
end

function Reporter:Manifest()
    local books = {}
    for book, record in pairs(self.db.books or {}) do
        book = tonumber(book)
        if book and book >= 1 and book <= 12
            and type(record) == "table" and record.hash then
            table.insert(books, { book = book, hash = tostring(record.hash) })
        end
    end
    table.sort(books, function(left, right) return left.book < right.book end)
    local encoded = {}
    for _, record in ipairs(books) do
        table.insert(encoded, tostring(record.book) .. ":" .. record.hash)
    end
    return table.concat(encoded, ",")
end

function Reporter:SendManifest()
    local collector = self.collector
    if not collector or Now() - collector.lastSeen > COLLECTOR_TIMEOUT then return false end
    local message = table.concat({
        "M", tostring(PROTOCOL), collector.session, tostring(self.db.revision or 0),
        tostring(self.db.activeBook or 0), self:Manifest(),
    }, "|")
    return self:Queue(message, collector.name)
end

function Reporter:SendBook(book)
    local collector = self.collector
    local record = self.db.books and self.db.books[tonumber(book)]
    if not collector or not record or type(record.payload) ~= "string" then return false end
    local total = math.ceil(#record.payload / CHUNK_SIZE)
    if total < 1 or total > 200 then return false end
    local transferID = tostring(Stamp()) .. "." .. tostring(math.random(100000, 999999))
    local startedAt = Now()
    local spacing = total > 1 and (BOOK_TRANSFER_SECONDS / (total - 1)) or 0
    spacing = math.max(SEND_INTERVAL, spacing)
    for index = 1, total do
        local startIndex = ((index - 1) * CHUNK_SIZE) + 1
        local chunk = string.sub(record.payload, startIndex, startIndex + CHUNK_SIZE - 1)
        local message = table.concat({
            "D", tostring(PROTOCOL), collector.session, transferID, tostring(book),
            tostring(index), tostring(total), tostring(record.hash), chunk,
        }, "|")
        if not self:Queue(message, collector.name, startedAt + ((index - 1) * spacing)) then
            return false
        end
    end
    return true
end

function Reporter:Scan(reason)
    local snapshot = BuildSnapshot()
    local semanticPayload = string.gsub(snapshot.payload, "\nD\t%d+", "\nD\t")
    local contentHash = Hash(semanticPayload)
    local prior = self.db.books[snapshot.book]
    local changed = not prior or prior.contentHash ~= contentHash
    self.db.activeBook = snapshot.book
    self.lastObservedBook = snapshot.book
    if changed then
        local hash = Hash(snapshot.payload)
        self.db.revision = (tonumber(self.db.revision) or 0) + 1
        self.db.books[snapshot.book] = {
            payload = snapshot.payload,
            hash = hash,
            contentHash = contentHash,
            capturedAt = snapshot.capturedAt,
        }
        if self.collector and Now() - self.collector.lastSeen <= COLLECTOR_TIMEOUT then
            self.manifestDueAt = Now() + math.random(10, 60) / 10
        end
    end
    self.lastScanAt = Now()
    self.scanDueAt = nil
    return changed
end

function Reporter:ScheduleScan(delay)
    local dueAt = Now() + math.max(0.2, tonumber(delay) or 1)
    if self.lastScanAt then dueAt = math.max(dueAt, self.lastScanAt + MIN_SCAN_INTERVAL) end
    if not self.scanDueAt or dueAt < self.scanDueAt then self.scanDueAt = dueAt end
end

function Reporter:HandleMessage(message, channel, sender)
    if type(message) ~= "string" or not sender then return end
    local kind, protocol, rest = string.match(message, "^([^|]+)|(%d+)|(.*)$")
    if tonumber(protocol) ~= PROTOCOL then return end
    if kind == "H" and channel == "GUILD" then
        local session = string.match(rest, "^([^|]+)$")
        if not session or #session > 80 or not self:IsCollector(sender) then return end
        self.collector = { name = sender, key = Normalize(sender), session = session, lastSeen = Now() }
        self.manifestDueAt = Now() + math.random(5, 120) / 10
    elseif kind == "Q" and channel == "WHISPER" then
        local session, booksText = string.match(rest, "^([^|]+)|([%d,]*)$")
        if not session or not self.collector or Normalize(sender) ~= self.collector.key
            or session ~= self.collector.session or not self:IsCollector(sender) then return end
        self.collector.lastSeen = Now()
        local requested, count = {}, 0
        for value in string.gmatch(booksText or "", "(%d+)") do
            local book = tonumber(value)
            if book and self.db.books[book] and not requested[book] and count < 1 then
                requested[book] = true
                count = count + 1
                self:SendBook(book)
            end
        end
    end
end

function Reporter:OnUpdate(elapsed)
    self.updateElapsed = (self.updateElapsed or 0) + elapsed
    local activeWork = table.getn(self.queue) > 0 or self.scanDueAt or self.manifestDueAt
    if self.updateElapsed < (activeWork and 0.10 or 1) then return end
    elapsed = self.updateElapsed
    self.updateElapsed = 0
    local now = Now()
    self.elapsed = self.elapsed + elapsed
    self.bookPollElapsed = self.bookPollElapsed + elapsed
    if self.bookPollElapsed >= 1 then
        self.bookPollElapsed = 0
        local book = ActiveBook()
        if book ~= self.lastObservedBook then self:ScheduleScan(1.5) end
    end
    if self.scanDueAt and now >= self.scanDueAt then self:Scan("scheduled") end
    if self.manifestDueAt and now >= self.manifestDueAt then
        self.manifestDueAt = nil
        self:SendManifest()
    end
    if self.elapsed >= SEND_INTERVAL and table.getn(self.queue) > 0
        and now >= (self.queue[1].readyAt or 0) then
        self.elapsed = 0
        local queued = table.remove(self.queue, 1)
        pcall(SendAddonMessage, PREFIX, queued.message, "WHISPER", queued.target)
    end
end

function Reporter:Initialize()
    if self.initialized or type(SendAddonMessage) ~= "function" then return end
    ActuallyDB = ActuallyDB or {}
    ActuallyDB.specReporter = type(ActuallyDB.specReporter) == "table"
        and ActuallyDB.specReporter or {}
    self.db = ActuallyDB.specReporter
    self.db.version = PROTOCOL
    self.db.revision = tonumber(self.db.revision) or 0
    self.db.books = type(self.db.books) == "table" and self.db.books or {}
    self.queue = {}
    self.elapsed = 0
    self.bookPollElapsed = 0
    self.updateElapsed = 0
    self.lastObservedBook = ActiveBook()
    if type(RegisterAddonMessagePrefix) == "function" then
        pcall(RegisterAddonMessagePrefix, PREFIX)
    end
    self.initialized = true
    self:ScheduleScan(2)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("LEARNED_SPELL_IN_TAB")
events:RegisterEvent("PLAYER_TALENT_UPDATE")
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loaded = ...
        if loaded == Addon.name then Reporter:Initialize() end
    elseif not Reporter.initialized then
        return
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        if prefix == PREFIX then Reporter:HandleMessage(message, channel, sender) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        Reporter:ScheduleScan(2)
    else
        Reporter:ScheduleScan(1.5)
    end
end)
events:SetScript("OnUpdate", function(_, elapsed)
    if Reporter.initialized then Reporter:OnUpdate(elapsed) end
end)
Reporter.frame = events
