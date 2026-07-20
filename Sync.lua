Actually = Actually or {}
local Addon = Actually

local Sync = {}
Addon.Sync = Sync
local ShortName = Addon.Util.ShortName
local NormalizeCharacter = Addon.Util.NormalizeCharacter

local PREFIX = Addon.MESSAGE_PREFIX
local PROTOCOL = 2
local HEARTBEAT_INTERVAL = 30
local PEER_TIMEOUT = 75
local RETRY_INTERVAL = 10
local MAX_RETRIES = 2
local REQUEST_COOLDOWN = 25
local CHUNK_SIZE = 180
local MAX_TRANSFER_CHUNKS = 2000
local MAX_LIVE_PAYLOAD = 240
-- Development fallback for cross-guild testing. Production discovery is GUILD.
local BOOTSTRAP_PEERS = { "Bolty" }

-- GetTime drives session timers; time is reserved for persistent identifiers.
local function Now()
    return GetTime and GetTime() or 0
end

local function Stamp()
    return time and time() or 0
end

local function GuildChannelAvailable()
    if GetGuildInfo and GetGuildInfo("player") then
        return true
    end
    if IsInGuild then
        local succeeded, inGuild = pcall(IsInGuild)
        if succeeded and inGuild then
            return true
        end
    end
    return false
end

local function IsActivePeer(peer, now)
    return peer and now - (tonumber(peer.lastSeen) or 0) <= PEER_TIMEOUT
end

local function PeerKey(identity)
    return NormalizeCharacter(identity)
end

local function Encode(value)
    local encoded = string.gsub(tostring(value or ""), "([^%w%-%._ ])", function(character)
        return string.format("%%%02X", string.byte(character))
    end)
    return encoded
end

local function Decode(value)
    local decoded = string.gsub(value or "", "%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
    return decoded
end

local function Fields(line)
    local fields = {}
    for value in string.gmatch((line or "") .. "\t", "(.-)\t") do
        table.insert(fields, value)
    end
    return fields
end

local function Split(value, separator)
    local values = {}
    if not value or value == "" then
        return values
    end
    local pattern = "([^" .. separator .. "]+)"
    for item in string.gmatch(value, pattern) do
        table.insert(values, item)
    end
    return values
end

local function Hash(value)
    local hash = 5381
    for index = 1, string.len(value) do
        hash = (hash * 33 + string.byte(value, index)) % 2147483647
    end
    return tostring(hash)
end

local function BoardLine(tier, board)
    local encoded = {}
    for _, key in ipairs(board[tier] or {}) do
        table.insert(encoded, Encode(key))
    end
    return table.concat({ "B", tier, table.concat(encoded, ",") }, "\t")
end

function Sync:Serialize()
    -- Records are sorted after the version/header lines so identical state always
    -- produces the same digest regardless of Lua table iteration order.
    local lines = { "V\t" .. tostring(PROTOCOL) }
    local official = Addon.db.lists.official
    if Addon.Official and Addon.Official.EnsureOperationState then
        official = Addon.Official:EnsureOperationState()
        Addon.Official:RebuildBoard()
    end
    table.insert(lines, table.concat({
        "O",
        tostring(tonumber(official.revision) or 0),
        Encode(official.lastModifiedBy),
        tostring(tonumber(official.lastModifiedAt) or 0),
    }, "\t"))

    table.insert(lines, table.concat({
        "E",
        tostring(tonumber(official.baseRevision) or 0),
        Encode(official.baseLastModifiedBy),
        tostring(tonumber(official.baseLastModifiedAt) or 0),
        tostring(tonumber(official.operationClock) or 0),
    }, "\t"))

    for _, tier in ipairs(Addon.tierOrder) do
        table.insert(lines, BoardLine(tier, official.board or {}))
        local encoded = {}
        for _, key in ipairs((official.baseBoard or {})[tier] or {}) do
            table.insert(encoded, Encode(key))
        end
        table.insert(lines, table.concat({ "G", tier, table.concat(encoded, ",") }, "\t"))
    end

    for id, operation in pairs(official.operations or {}) do
        table.insert(lines, table.concat({
            "Y", Encode(operation.id or id), tostring(tonumber(operation.clock) or 0),
            Encode(operation.author), tostring(tonumber(operation.timestamp) or 0), Encode(operation.kind),
            Encode(operation.key), Encode(operation.tier), Encode(operation.before), Encode(operation.after),
        }, "\t"))
    end

    local spellKeys = {}
    for key in pairs(Addon.db.customSpells or {}) do
        table.insert(spellKeys, key)
    end
    table.sort(spellKeys)
    for _, key in ipairs(spellKeys) do
        local spell = Addon.db.customSpells[key]
        table.insert(lines, table.concat({
            "S", tostring(spell.id or key), Encode(spell.category), spell.coa and "1" or "0",
            tostring(tonumber(spell.updatedAt) or 0),
        }, "\t"))
    end

    for key, deletedAt in pairs(Addon.db.spellTombstones or {}) do
        table.insert(lines, table.concat({ "T", tostring(key), tostring(tonumber(deletedAt) or 0) }, "\t"))
    end

    for _, peerName in pairs(Addon.db.sync.knownPeers or {}) do
        table.insert(lines, table.concat({ "K", Encode(peerName) }, "\t"))
    end

    local discussionKeys = {}
    for key in pairs(Addon.db.discussions or {}) do
        table.insert(discussionKeys, key)
    end
    table.sort(discussionKeys)
    for _, spellID in ipairs(discussionKeys) do
        local thread = Addon.db.discussions[spellID]
        if type(thread) == "table" then
            for authorKey, entry in pairs(thread.priority or {}) do
                table.insert(lines, table.concat({
                    "P", tostring(spellID), Encode(authorKey), Encode(entry.author), Encode(entry.text),
                    tostring(tonumber(entry.timestamp) or 0),
                }, "\t"))
            end
            for authorKey, deletedAt in pairs(thread.priorityDeleted or {}) do
                table.insert(lines, table.concat({
                    "R", tostring(spellID), Encode(authorKey), tostring(tonumber(deletedAt) or 0),
                }, "\t"))
            end
            for _, entry in ipairs(thread.comments or {}) do
                table.insert(lines, table.concat({
                    "C", tostring(spellID), Encode(entry.id), Encode(entry.author), Encode(entry.text),
                    tostring(tonumber(entry.timestamp) or 0), entry.officer and "1" or "0",
                }, "\t"))
            end
            for commentID, deletedAt in pairs(thread.deleted or {}) do
                table.insert(lines, table.concat({
                    "X", tostring(spellID), Encode(commentID), tostring(tonumber(deletedAt) or 0),
                }, "\t"))
            end
        end
    end

    for _, entry in ipairs(official.audit or {}) do
        if not entry.id then
            entry.id = Hash(tostring(entry.author) .. tostring(entry.timestamp) .. tostring(entry.action) .. tostring(entry.revision))
        end
        table.insert(lines, table.concat({
            "A", Encode(entry.id), tostring(tonumber(entry.revision) or 0), Encode(entry.author),
            tostring(tonumber(entry.timestamp) or 0), entry.activity and "1" or "0", Encode(entry.action),
        }, "\t"))
    end

    local ordered = {}
    for index = 3, #lines do
        table.insert(ordered, lines[index])
    end
    table.sort(ordered)
    return lines[1] .. "\n" .. lines[2] .. "\n" .. table.concat(ordered, "\n")
end

function Sync:GetSnapshot()
    if not self.cachedSnapshot then
        self.cachedSnapshot = self:Serialize()
        self.cachedDigest = Hash(self.cachedSnapshot)
    end
    return self.cachedSnapshot, self.cachedDigest
end

function Sync:Invalidate()
    self.cachedSnapshot = nil
    self.cachedDigest = nil
end

function Sync:RefreshUI()
    if Addon.Board and Addon.Board.frame then
        Addon.Board:ReloadFromDatabase()
    end
    if Addon.Discussion then
        Addon.Discussion:Refresh()
    end
end

function Sync:Log(message)
    self.logs = self.logs or {}
    local entry = string.format("%.1f", Now()) .. "  " .. tostring(message)
    table.insert(self.logs, entry)
    while #self.logs > 60 do
        table.remove(self.logs, 1)
    end
    if self.debugEnabled and Addon.Print then
        Addon:Print("SYNC " .. tostring(message))
    end
end

function Sync:PrintLog()
    Addon:Print("Sync log (newest last):")
    local first = math.max(1, #(self.logs or {}) - 19)
    for index = first, #(self.logs or {}) do
        DEFAULT_CHAT_FRAME:AddMessage("|cff999999" .. self.logs[index] .. "|r")
    end
end

function Sync:SetDebug(enabled)
    self.debugEnabled = enabled == true
    Addon:Print("Sync debug " .. (self.debugEnabled and "enabled." or "disabled."))
    self:Log("Debug mode changed.")
end

local function EnsureThread(spellID)
    local key = tostring(spellID)
    local thread = Addon.db.discussions[key]
    if type(thread) ~= "table" then
        thread = {}
        Addon.db.discussions[key] = thread
    end
    thread.priority = type(thread.priority) == "table" and thread.priority or {}
    thread.priorityDeleted = type(thread.priorityDeleted) == "table" and thread.priorityDeleted or {}
    thread.comments = type(thread.comments) == "table" and thread.comments or {}
    thread.deleted = type(thread.deleted) == "table" and thread.deleted or {}
    return thread
end

function Sync:Deserialize(snapshot)
    local data = { board = {}, baseBoard = {}, operations = {}, spells = {}, spellTombstones = {}, knownPeers = {}, priority = {}, priorityDeleted = {}, comments = {}, deleted = {}, audit = {} }
    for line in string.gmatch((snapshot or "") .. "\n", "(.-)\n") do
        local field = Fields(line)
        local kind = field[1]
        if kind == "V" then
            if tonumber(field[2]) ~= PROTOCOL then
                return nil
            end
        elseif kind == "O" then
            data.official = { revision = tonumber(field[2]) or 0, lastModifiedBy = Decode(field[3]), lastModifiedAt = tonumber(field[4]) or 0 }
        elseif kind == "E" then
            data.base = {
                revision = tonumber(field[2]) or 0,
                lastModifiedBy = Decode(field[3]),
                lastModifiedAt = tonumber(field[4]) or 0,
                operationClock = tonumber(field[5]) or 0,
            }
        elseif kind == "B" and field[2] then
            data.board[field[2]] = {}
            for _, key in ipairs(Split(field[3], ",")) do
                table.insert(data.board[field[2]], Decode(key))
            end
        elseif kind == "G" and field[2] then
            data.baseBoard[field[2]] = {}
            for _, key in ipairs(Split(field[3], ",")) do
                table.insert(data.baseBoard[field[2]], Decode(key))
            end
        elseif kind == "Y" then
            local id = Decode(field[2])
            if id ~= "" then
                data.operations[id] = {
                    id = id,
                    clock = tonumber(field[3]) or 0,
                    author = Decode(field[4]),
                    timestamp = tonumber(field[5]) or 0,
                    kind = Decode(field[6]),
                    key = Decode(field[7]),
                    tier = Decode(field[8]),
                    before = Decode(field[9]),
                    after = Decode(field[10]),
                }
            end
        elseif kind == "S" and tonumber(field[2]) then
            data.spells[tostring(field[2])] = { id = tonumber(field[2]), category = Decode(field[3]), coa = field[4] == "1", updatedAt = tonumber(field[5]) or 0 }
        elseif kind == "T" then
            data.spellTombstones[tostring(field[2])] = tonumber(field[3]) or 0
        elseif kind == "K" then
            local peerName = Decode(field[2])
            if peerName ~= "" then
                data.knownPeers[PeerKey(peerName)] = peerName
            end
        elseif kind == "P" then
            table.insert(data.priority, { spellID = field[2], key = Decode(field[3]), author = Decode(field[4]), text = Decode(field[5]), timestamp = tonumber(field[6]) or 0 })
        elseif kind == "R" then
            table.insert(data.priorityDeleted, { spellID = field[2], key = Decode(field[3]), timestamp = tonumber(field[4]) or 0 })
        elseif kind == "C" then
            table.insert(data.comments, { spellID = field[2], id = Decode(field[3]), author = Decode(field[4]), text = Decode(field[5]), timestamp = tonumber(field[6]) or 0, officer = field[7] == "1" })
        elseif kind == "X" then
            table.insert(data.deleted, { spellID = field[2], id = Decode(field[3]), timestamp = tonumber(field[4]) or 0 })
        elseif kind == "A" then
            table.insert(data.audit, { id = Decode(field[2]), revision = tonumber(field[3]) or 0, author = Decode(field[4]), timestamp = tonumber(field[5]) or 0, activity = field[6] == "1", action = Decode(field[7]) })
        end
    end
    return data.official and data.base and data or nil
end

local function RemoveComment(thread, commentID)
    for index = #thread.comments, 1, -1 do
        if thread.comments[index].id == commentID then
            table.remove(thread.comments, index)
        end
    end
end

local function BoardSignature(board)
    local parts = {}
    for _, tier in ipairs(Addon.tierOrder) do
        table.insert(parts, tier .. ":" .. table.concat(board[tier] or {}, ","))
    end
    return table.concat(parts, ";")
end

local function OperationSignature(operation)
    return table.concat({
        tostring(operation.clock or 0), tostring(operation.author or ""), tostring(operation.timestamp or 0),
        tostring(operation.kind or ""), tostring(operation.key or ""), tostring(operation.tier or ""),
        tostring(operation.before or ""), tostring(operation.after or ""),
    }, "|")
end

function Sync:ApplySnapshot(snapshot)
    local incoming = self:Deserialize(snapshot)
    if not incoming then
        self:Log("Rejected an invalid snapshot.")
        return false, false
    end

    local changed = false

    -- Official placements are an operation-set CRDT. Baselines only compete
    -- during migration; after that, operations are unioned and replayed.
    local official = Addon.db.lists.official
    if Addon.Official and Addon.Official.EnsureOperationState then
        official = Addon.Official:EnsureOperationState()
    end
    local localBaseRevision = tonumber(official.baseRevision) or 0
    local localBaseModified = tonumber(official.baseLastModifiedAt) or 0
    local incomingBaseRevision = tonumber(incoming.base.revision) or 0
    local incomingBaseModified = tonumber(incoming.base.lastModifiedAt) or 0
    local incomingBasePreferred = incomingBaseRevision > localBaseRevision
        or (incomingBaseRevision == localBaseRevision and incomingBaseModified > localBaseModified)
        or (incomingBaseRevision == localBaseRevision and incomingBaseModified == localBaseModified
            and BoardSignature(incoming.baseBoard) > BoardSignature(official.baseBoard or {}))
    if incomingBasePreferred then
        official.baseBoard = incoming.baseBoard
        official.baseRevision = incomingBaseRevision
        official.baseLastModifiedBy = incoming.base.lastModifiedBy ~= "" and incoming.base.lastModifiedBy or nil
        official.baseLastModifiedAt = incomingBaseModified
        changed = true
    end

    official.operations = type(official.operations) == "table" and official.operations or {}
    for id, operation in pairs(incoming.operations) do
        local localOperation = official.operations[id]
        if not localOperation or OperationSignature(operation) > OperationSignature(localOperation) then
            official.operations[id] = operation
            changed = true
        end
    end
    official.operationClock = math.max(tonumber(official.operationClock) or 0, tonumber(incoming.base.operationClock) or 0)
    if Addon.Official and Addon.Official.RebuildBoard then
        local oldSignature = BoardSignature(official.board or {})
        Addon.Official:RebuildBoard()
        if BoardSignature(official.board or {}) ~= oldSignature then
            changed = true
        end
    end

    -- Spell metadata and officer notes are last-write-wins records. Tombstones
    -- win ties so an older snapshot cannot resurrect a deletion.
    for key, spell in pairs(incoming.spells) do
        local localSpell = Addon.db.customSpells[key]
        local localUpdated = localSpell and tonumber(localSpell.updatedAt) or -1
        local deletedAt = tonumber(Addon.db.spellTombstones[key]) or -1
        local incomingSignature = tostring(spell.category) .. (spell.coa and "1" or "0")
        local localSignature = localSpell and (tostring(localSpell.category) .. (localSpell.coa and "1" or "0")) or ""
        if spell.updatedAt > math.max(localUpdated, deletedAt)
            or (spell.updatedAt == localUpdated and spell.updatedAt > deletedAt and incomingSignature > localSignature)
            or (not localSpell and deletedAt < 0) then
            Addon.db.customSpells[key] = spell
            Addon.db.spellTombstones[key] = nil
            changed = true
        end
    end
    for key, deletedAt in pairs(incoming.spellTombstones) do
        local localSpell = Addon.db.customSpells[key]
        local localUpdated = localSpell and tonumber(localSpell.updatedAt) or -1
        if deletedAt >= localUpdated and deletedAt > (tonumber(Addon.db.spellTombstones[key]) or -1) then
            Addon.db.customSpells[key] = nil
            Addon.db.spellTombstones[key] = deletedAt
            changed = true
        end
    end

    for key, peerName in pairs(incoming.knownPeers) do
        Addon.db.sync.knownPeers[key] = ShortName(peerName)
    end

    for _, entry in ipairs(incoming.priority) do
        local thread = EnsureThread(entry.spellID)
        local localEntry = thread.priority[entry.key]
        local localTime = localEntry and tonumber(localEntry.timestamp) or -1
        local deletedAt = tonumber(thread.priorityDeleted[entry.key]) or -1
        local localText = localEntry and tostring(localEntry.text) or ""
        if entry.timestamp > math.max(localTime, deletedAt)
            or (entry.timestamp == localTime and entry.timestamp > deletedAt and tostring(entry.text) > localText) then
            thread.priority[entry.key] = { author = entry.author, text = entry.text, timestamp = entry.timestamp, officer = true }
            thread.priorityDeleted[entry.key] = nil
            changed = true
        end
    end
    for _, entry in ipairs(incoming.priorityDeleted) do
        local thread = EnsureThread(entry.spellID)
        local localEntry = thread.priority[entry.key]
        local localTime = localEntry and tonumber(localEntry.timestamp) or -1
        if entry.timestamp >= localTime and entry.timestamp > (tonumber(thread.priorityDeleted[entry.key]) or -1) then
            thread.priority[entry.key] = nil
            thread.priorityDeleted[entry.key] = entry.timestamp
            changed = true
        end
    end

    -- Comments are immutable records keyed by ID; deletions are permanent IDs.
    for _, entry in ipairs(incoming.comments) do
        local thread = EnsureThread(entry.spellID)
        if not thread.deleted[entry.id] then
            local exists = false
            for _, localEntry in ipairs(thread.comments) do
                if localEntry.id == entry.id then
                    exists = true
                    break
                end
            end
            if not exists then
                table.insert(thread.comments, entry)
                changed = true
            end
        end
    end
    for _, entry in ipairs(incoming.deleted) do
        local thread = EnsureThread(entry.spellID)
        if entry.timestamp > (tonumber(thread.deleted[entry.id]) or -1) then
            thread.deleted[entry.id] = entry.timestamp
            RemoveComment(thread, entry.id)
            changed = true
        end
    end

    for _, thread in pairs(Addon.db.discussions) do
        if type(thread) == "table" and type(thread.comments) == "table" then
            table.sort(thread.comments, function(left, right)
                if (left.timestamp or 0) ~= (right.timestamp or 0) then
                    return (left.timestamp or 0) < (right.timestamp or 0)
                end
                return tostring(left.id) < tostring(right.id)
            end)
        end
    end

    -- Audit entries are a bounded union, sorted deterministically on every merge.
    local auditIDs = {}
    for _, entry in ipairs(official.audit or {}) do
        entry.id = entry.id or Hash(tostring(entry.author) .. tostring(entry.timestamp) .. tostring(entry.action) .. tostring(entry.revision))
        auditIDs[entry.id] = true
    end
    for _, entry in ipairs(incoming.audit) do
        if not auditIDs[entry.id] then
            table.insert(official.audit, entry)
            auditIDs[entry.id] = true
            changed = true
        end
    end
    table.sort(official.audit, function(left, right)
        if (left.timestamp or 0) ~= (right.timestamp or 0) then
            return (left.timestamp or 0) < (right.timestamp or 0)
        end
        return tostring(left.id) < tostring(right.id)
    end)
    while #official.audit > 100 do
        table.remove(official.audit, 1)
    end

    self:Invalidate()
    if changed then
        self:RefreshUI()
    end
    self:Log(changed and "Snapshot merged and UI refreshed." or "Snapshot received; local data was already current.")
    return changed, true
end

function Sync:GetLeader()
    local leader = self.selfKey
    local now = Now()
    for key, peer in pairs(self.peers) do
        if IsActivePeer(peer, now) and key < leader then
            leader = key
        end
    end
    return leader
end

function Sync:GetActivePeerCount()
    local count = 0
    local now = Now()
    for _, peer in pairs(self.peers) do
        if IsActivePeer(peer, now) then
            count = count + 1
        end
    end
    return count
end

function Sync:BeginLeaderTerm()
    local now = Now()
    local _, ownDigest = self:GetSnapshot()
    local requested = 0
    for _, peer in pairs(self.peers) do
        if IsActivePeer(peer, now) and peer.digest and peer.digest ~= ownDigest then
            self:RequestSnapshot(peer.name, true)
            requested = requested + 1
        end
    end
    self.leaderSettlingUntil = now + 5
    self:Log("Leader reconciliation started; requested " .. tostring(requested) .. " differing peer snapshot(s).")
    self:SendHeartbeat()
end

function Sync:RememberPeer(identity)
    local key = PeerKey(identity)
    if key ~= "" then
        Addon.db.sync.knownPeers[key] = ShortName(identity)
    end
end

function Sync:QueueMessage(message, channel, target)
    table.insert(self.sendQueue, { message = message, channel = channel, target = target })
end

function Sync:BroadcastLive(message)
    if GuildChannelAvailable() then
        self:QueueMessage(message, "GUILD")
        return
    end
    local now = Now()
    for _, peer in pairs(self.peers) do
        if IsActivePeer(peer, now) then
            self:QueueMessage(message, "WHISPER", peer.name)
        end
    end
end

function Sync:BroadcastOfficialChange(operations, auditEntry)
    if not self.initialized then
        return
    end
    for _, operation in ipairs(operations or {}) do
        local payload = table.concat({
            "SYNC", "O", Encode(operation.id), tostring(tonumber(operation.clock) or 0),
            Encode(operation.author), tostring(tonumber(operation.timestamp) or 0), Encode(operation.kind),
            Encode(operation.key), Encode(operation.tier), Encode(operation.before), Encode(operation.after),
        }, "|")
        if string.len(payload) <= MAX_LIVE_PAYLOAD then
            self:BroadcastLive(payload)
        else
            self:Log("Official operation exceeded the live-message limit; snapshot recovery will deliver it.")
        end
    end
    if auditEntry then
        local payload = table.concat({
            "SYNC", "J", Encode(auditEntry.id), tostring(tonumber(auditEntry.revision) or 0),
            Encode(auditEntry.author), tostring(tonumber(auditEntry.timestamp) or 0), Encode(auditEntry.action),
        }, "|")
        if string.len(payload) <= MAX_LIVE_PAYLOAD then
            self:BroadcastLive(payload)
        else
            self:Log("Official audit entry exceeded the live-message limit; snapshot recovery will deliver it.")
        end
    end
end

function Sync:SendHello(channel, target)
    channel = channel or "GUILD"
    if channel == "GUILD" and Now() - (self.lastGuildHello or -100) < 1 then
        return
    end
    local _, digest = self:GetSnapshot()
    self:QueueMessage("SYNC|H|" .. tostring(PROTOCOL) .. "|" .. digest, channel, target)
    if channel == "GUILD" then
        self.lastGuildHello = Now()
    end
end

function Sync:SendHeartbeat()
    if GuildChannelAvailable() then
        self:SendHello("GUILD")
        return
    end
    local leader = self:GetLeader()
    local now = Now()
    if leader == self.selfKey then
        for _, peer in pairs(self.peers) do
            if IsActivePeer(peer, now) then
                self:SendHello("WHISPER", peer.name)
            end
        end
    else
        local peer = self.peers[leader]
        if peer then
            self:SendHello("WHISPER", peer.name)
        end
    end
end

function Sync:DiscoverKnownPeers()
    local candidates = {}
    local included = {}
    for _, name in ipairs(BOOTSTRAP_PEERS) do
        local key = PeerKey(name)
        if key ~= self.selfKey then
            table.insert(candidates, Addon.db.sync.knownPeers[key] or name)
            included[key] = true
        end
    end
    local remembered = {}
    for _, name in pairs(Addon.db.sync.knownPeers or {}) do
        local key = PeerKey(name)
        if key ~= self.selfKey and not included[key] then
            table.insert(remembered, name)
        end
    end
    table.sort(remembered, function(left, right)
        return PeerKey(left) < PeerKey(right)
    end)
    for _, name in ipairs(remembered) do
        table.insert(candidates, name)
    end

    local sent = 0
    for _, name in ipairs(candidates) do
        if sent >= 8 then
            break
        end
        self:SendHello("WHISPER", name)
        sent = sent + 1
    end
    if sent > 0 then
        self:Log("Peer discovery whispered " .. tostring(sent) .. " known/bootstrap users.")
    end
end

function Sync:RequestSnapshot(target, force)
    if not target or target == "" then
        return
    end
    local key = PeerKey(target)
    local now = Now()
    if not force and now - (self.lastRequest[key] or -100) < REQUEST_COOLDOWN then
        return
    end
    self.lastRequest[key] = now
    local _, digest = self:GetSnapshot()
    self:QueueMessage("SYNC|Q|" .. digest, "WHISPER", target)
    self:Log("Requested a snapshot from " .. ShortName(target) .. ".")
end

function Sync:QueueTransferChunks(transferID, transfer)
    for index, chunk in ipairs(transfer.chunks) do
        self:QueueMessage(
            "SYNC|S|" .. transferID .. "|" .. tostring(index) .. "|" .. tostring(#transfer.chunks)
                .. "|" .. transfer.digest .. "|" .. chunk,
            "WHISPER",
            transfer.target
        )
    end
end

function Sync:SendSnapshot(target)
    for _, transfer in pairs(self.outgoing) do
        if PeerKey(transfer.target) == PeerKey(target) then
            return
        end
    end

    local snapshot, digest = self:GetSnapshot()
    local encoded = Encode(snapshot)
    local transferID = tostring(Stamp()) .. tostring(math.random(1000, 9999))
    local chunks = {}
    for startIndex = 1, string.len(encoded), CHUNK_SIZE do
        table.insert(chunks, string.sub(encoded, startIndex, startIndex + CHUNK_SIZE - 1))
    end
    if #chunks == 0 or #chunks > MAX_TRANSFER_CHUNKS then
        self:Log("Snapshot for " .. ShortName(target) .. " exceeded the transfer limit.")
        return
    end

    local transfer = { target = target, chunks = chunks, digest = digest, sentAt = Now() + (#chunks * 0.15), retries = 0 }
    self.outgoing[transferID] = transfer
    self:QueueTransferChunks(transferID, transfer)
    self:Log("Sending snapshot " .. transferID .. " to " .. ShortName(target) .. " in " .. tostring(#chunks) .. " chunks.")
end

function Sync:MarkDirty(announce)
    self:Invalidate()
    if not self.initialized or announce == false then
        return
    end
    if self:GetLeader() == self.selfKey then
        self:SendHeartbeat()
    else
        local _, digest = self:GetSnapshot()
        if GuildChannelAvailable() then
            self:QueueMessage("SYNC|U|" .. digest, "GUILD")
        else
            local leader = self.peers[self:GetLeader()]
            if leader then
                self:QueueMessage("SYNC|U|" .. digest, "WHISPER", leader.name)
            end
        end
    end
end

function Sync:PrintStatus(force)
    local leaderKey = self:GetLeader()
    local leaderName = leaderKey == self.selfKey and ShortName(UnitName("player")) or leaderKey
    local peerCount = 1
    local now = Now()
    for _, peer in pairs(self.peers) do
        if IsActivePeer(peer, now) then
            peerCount = peerCount + 1
            if PeerKey(peer.name) == leaderKey then
                leaderName = ShortName(peer.name)
            end
        end
    end
    local _, digest = self:GetSnapshot()
    local spellCount = 0
    for _ in pairs(Addon.db.customSpells or {}) do spellCount = spellCount + 1 end
    local commentCount = 0
    for _, thread in pairs(Addon.db.discussions or {}) do
        commentCount = commentCount + #(thread.comments or {})
    end
    Addon:Print(
        "Sync leader: " .. leaderName
            .. "; users: " .. tostring(peerCount)
            .. "; official rev: " .. tostring(Addon.db.lists.official.revision or 0)
            .. "; spells: " .. tostring(spellCount)
            .. "; comments: " .. tostring(commentCount)
            .. "; queue: " .. tostring(#self.sendQueue)
            .. (leaderKey == self.selfKey and now < (self.leaderSettlingUntil or 0) and "; reconciling" or "")
            .. "; digest: " .. digest .. "."
    )
    if force then
        self:ForceSync()
    end
end

function Sync:ForceSync(target)
    if target and target ~= "" then
        self:RememberPeer(target)
        self:RequestSnapshot(target, true)
        self:SendHeartbeat()
        Addon:Print("Forced snapshot request sent to " .. ShortName(target) .. ".")
        return
    end

    local leader = self:GetLeader()
    local requested = 0
    local now = Now()
    for key, peer in pairs(self.peers) do
        if IsActivePeer(peer, now) and (leader == self.selfKey or key == leader) then
            self:RequestSnapshot(peer.name, true)
            requested = requested + 1
        end
    end
    self:SendHeartbeat()
    if requested == 0 then
        if not GuildChannelAvailable() then
            self:DiscoverKnownPeers()
        end
        Addon:Print("No other active addon user is visible yet; discovery heartbeat sent.")
    else
        Addon:Print("Forced synchronization requested from " .. tostring(requested) .. " peer(s).")
    end
end

function Sync:HandleHello(sender, channel, digest)
    local key = PeerKey(sender)
    local wasKnown = self.peers[key] ~= nil
    self.peers[key] = { name = sender, lastSeen = Now(), digest = digest }
    self:Log("Heartbeat from " .. ShortName(sender) .. " via " .. tostring(channel) .. "; digest " .. tostring(digest) .. ".")
    if channel == "GUILD" and not wasKnown then
        self:SendHello("WHISPER", sender)
    end

    local _, ownDigest = self:GetSnapshot()
    if digest ~= ownDigest then
        local leader = self:GetLeader()
        if leader == self.selfKey or leader == key then
            self:RequestSnapshot(sender)
        end
    end
end

function Sync:ApplyLiveOfficialOperation(rest, sender)
    local id, clock, author, timestamp, kind, key, tier, before, after = string.match(
        rest or "", "^([^|]+)|(%d+)|([^|]*)|(%d+)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$"
    )
    id, author, kind = Decode(id), Decode(author), Decode(kind)
    if id == "" or (kind ~= "MOVE" and kind ~= "REMOVE" and kind ~= "RESET") then
        return false
    end
    local operation = {
        id = id,
        clock = tonumber(clock) or 0,
        author = author,
        timestamp = tonumber(timestamp) or 0,
        kind = kind,
        key = Decode(key),
        tier = Decode(tier),
        before = Decode(before),
        after = Decode(after),
    }
    local official = Addon.Official:EnsureOperationState()
    local existing = official.operations[id]
    if existing and OperationSignature(existing) >= OperationSignature(operation) then
        return false
    end
    official.operations[id] = operation
    official.operationClock = math.max(tonumber(official.operationClock) or 0, operation.clock)
    Addon.Official:RebuildBoard()
    self:Invalidate()
    self:RefreshUI()
    self:Log("Applied live official operation from " .. ShortName(sender) .. ".")
    return true
end

function Sync:ApplyLiveAudit(rest)
    local id, revision, author, timestamp, action = string.match(rest or "", "^([^|]+)|(%d+)|([^|]*)|(%d+)|(.*)$")
    id = Decode(id)
    if id == "" then
        return false
    end
    local official = Addon.db.lists.official
    official.audit = type(official.audit) == "table" and official.audit or {}
    for _, entry in ipairs(official.audit) do
        if entry.id == id then
            return false
        end
    end
    table.insert(official.audit, {
        id = id,
        revision = tonumber(revision) or tonumber(official.revision) or 0,
        author = Decode(author),
        timestamp = tonumber(timestamp) or 0,
        action = Decode(action),
    })
    table.sort(official.audit, function(left, right)
        if (left.timestamp or 0) ~= (right.timestamp or 0) then
            return (left.timestamp or 0) < (right.timestamp or 0)
        end
        return tostring(left.id) < tostring(right.id)
    end)
    while #official.audit > 100 do
        table.remove(official.audit, 1)
    end
    self:Invalidate()
    if Addon.Board then
        Addon.Board:RefreshAuditLog()
    end
    return true
end

function Sync:HandleMessage(message, channel, sender)
    local kind, rest = string.match(message or "", "^SYNC|([^|]+)|(.*)$")
    if not kind then
        return
    end

    local senderKey = PeerKey(sender)
    self:RememberPeer(sender)
    local peer = self.peers[senderKey] or {}
    peer.name = sender
    peer.lastSeen = Now()
    self.peers[senderKey] = peer

    if kind == "H" then
        local protocol, digest = string.match(rest, "^(%d+)|(.+)$")
        if tonumber(protocol) == PROTOCOL then
            self:HandleHello(sender, channel, digest)
        end
    elseif kind == "O" then
        self:ApplyLiveOfficialOperation(rest, sender)
    elseif kind == "J" then
        self:ApplyLiveAudit(rest)
    elseif kind == "U" then
        local key = PeerKey(sender)
        self.peers[key] = { name = sender, lastSeen = Now(), digest = rest }
        self:Log("Update notice from " .. ShortName(sender) .. ".")
        local _, ownDigest = self:GetSnapshot()
        if self:GetLeader() == self.selfKey and rest ~= ownDigest then
            self:RequestSnapshot(sender)
        end
    elseif kind == "L" then
        self.peers[PeerKey(sender)] = nil
        self:Log(ShortName(sender) .. " logged off.")
    elseif kind == "Q" and channel == "WHISPER" then
        self:Log("Snapshot requested by " .. ShortName(sender) .. ".")
        self:SendSnapshot(sender)
        self:SendHello("WHISPER", sender)
    elseif kind == "A" and channel == "WHISPER" then
        self.outgoing[rest] = nil
        self:Log("Transfer " .. tostring(rest) .. " acknowledged by " .. ShortName(sender) .. ".")
    elseif kind == "S" and channel == "WHISPER" then
        local transferID, indexText, totalText, digest, chunk = string.match(rest, "^([^|]+)|(%d+)|(%d+)|(%d+)|(.*)$")
        local index = tonumber(indexText)
        local total = tonumber(totalText)
        if not transferID or not index or not total or not digest or total < 1 or total > MAX_TRANSFER_CHUNKS or index > total then
            return
        end
        local transferKey = PeerKey(sender) .. ":" .. transferID
        local transfer = self.incoming[transferKey]
        if not transfer then
            transfer = { sender = sender, total = total, digest = digest, parts = {}, received = 0, updatedAt = Now() }
            self.incoming[transferKey] = transfer
            self:Log("Receiving transfer " .. transferID .. " from " .. ShortName(sender) .. " (" .. tostring(total) .. " chunks).")
        end
        if transfer.total ~= total or transfer.digest ~= digest then
            self.incoming[transferKey] = nil
            return
        end
        if not transfer.parts[index] then
            transfer.parts[index] = chunk
            transfer.received = transfer.received + 1
        end
        transfer.updatedAt = Now()
        if transfer.received == transfer.total then
            local complete = {}
            for partIndex = 1, transfer.total do
                if not transfer.parts[partIndex] then
                    return
                end
                table.insert(complete, transfer.parts[partIndex])
            end
            self.incoming[transferKey] = nil
            local snapshot = Decode(table.concat(complete))
            if Hash(snapshot) ~= transfer.digest then
                self:Log("Transfer " .. transferID .. " from " .. ShortName(sender) .. " failed checksum validation.")
            else
                local _, valid = self:ApplySnapshot(snapshot)
                if valid then
                    self:Log("Transfer " .. transferID .. " completed from " .. ShortName(sender) .. ".")
                    self:QueueMessage("SYNC|A|" .. transferID, "WHISPER", sender)
                    if self:GetLeader() == self.selfKey then
                        self:SendHeartbeat()
                    end
                end
            end
        end
    end
end

function Sync:OnUpdate(elapsed)
    self.sendElapsed = self.sendElapsed + elapsed
    if self.sendElapsed >= 0.15 and #self.sendQueue > 0 then
        self.sendElapsed = 0
        local queued = table.remove(self.sendQueue, 1)
        if queued.channel ~= "GUILD" or GuildChannelAvailable() then
            local sent, errorMessage = pcall(SendAddonMessage, PREFIX, queued.message, queued.channel, queued.target)
            if not sent then
                self:Log("Send failed on " .. tostring(queued.channel) .. ": " .. tostring(errorMessage))
            end
        end
    end

    local now = Now()
    if now >= self.nextHeartbeat then
        self.nextHeartbeat = now + HEARTBEAT_INTERVAL
        self:SendHeartbeat()
    end
    if now >= self.nextDiscovery then
        self.nextDiscovery = now + 60
        if self:GetActivePeerCount() == 0 and not GuildChannelAvailable() then
            self:DiscoverKnownPeers()
        end
    end

    local leader = self:GetLeader()
    if leader ~= self.lastLeader then
        self.lastLeader = leader
        if leader == self.selfKey then
            self:BeginLeaderTerm()
        end
    end

    for transferID, transfer in pairs(self.outgoing) do
        if now - transfer.sentAt >= RETRY_INTERVAL then
            if transfer.retries >= MAX_RETRIES then
                self.outgoing[transferID] = nil
                self:Log("Transfer " .. transferID .. " to " .. ShortName(transfer.target) .. " failed after retries.")
            else
                transfer.retries = transfer.retries + 1
                transfer.sentAt = now
                self:Log("Retrying transfer " .. transferID .. " to " .. ShortName(transfer.target) .. ".")
                self:QueueTransferChunks(transferID, transfer)
            end
        end
    end
    for key, transfer in pairs(self.incoming) do
        if now - transfer.updatedAt > 35 then
            self.incoming[key] = nil
        end
    end
end

function Sync:Initialize()
    if self.initialized or not SendAddonMessage then
        return
    end
    self.initialized = true
    self.selfKey = PeerKey(UnitName("player"))
    self.peers = {}
    self.sendQueue = {}
    self.outgoing = {}
    self.incoming = {}
    self.lastRequest = {}
    self.sendElapsed = 0
    self.nextHeartbeat = Now() + 2
    self.nextDiscovery = Now() + 3
    self.lastLeader = nil
    self.leaderSettlingUntil = 0
    local canonicalPeers = {}
    for _, peerName in pairs(Addon.db.sync.knownPeers or {}) do
        canonicalPeers[PeerKey(peerName)] = ShortName(peerName)
    end
    Addon.db.sync.knownPeers = canonicalPeers
    self:RememberPeer(UnitName("player"))
    self.logs = {}
    self.debugEnabled = false
    self:Log("Sync initialized for " .. ShortName(UnitName("player")) .. ".")

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:RegisterEvent("PLAYER_LOGOUT")
    frame:SetScript("OnEvent", function(_, event, prefix, message, channel, sender)
        if event == "PLAYER_LOGOUT" then
            if GuildChannelAvailable() then
                pcall(SendAddonMessage, PREFIX, "SYNC|L|", "GUILD")
            else
                local now = Now()
                for _, peer in pairs(Sync.peers or {}) do
                    if IsActivePeer(peer, now) then
                        pcall(SendAddonMessage, PREFIX, "SYNC|L|", "WHISPER", peer.name)
                    end
                end
            end
        elseif event == "CHAT_MSG_ADDON" and prefix == PREFIX and sender and PeerKey(sender) ~= Sync.selfKey then
            Sync:HandleMessage(message, channel, sender)
        end
    end)
    frame:SetScript("OnUpdate", function(_, elapsed)
        Sync:OnUpdate(elapsed)
    end)
    self.frame = frame
end
