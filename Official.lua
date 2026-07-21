Actually = Actually or {}
local Addon = Actually

local Official = {}
Addon.Official = Official
local Trim = Addon.Util.Trim
local NormalizeIdentity = Addon.Util.NormalizeIdentity

local OFFICER_COMMAND = "council cachekeeper"
local OFFICER_REVOKE_COMMAND = OFFICER_COMMAND .. " off"
local AUDIT_LIMIT = 100
local MESSAGE_PREFIX = Addon.MESSAGE_PREFIX
-- Coordination token only; Lua source is client-readable and this is not security.
local AUTH_TOKEN = "cachekeeper-v1"

-- The baseline is the pre-operation official board. Operations are immutable
-- and replayed in Lamport order, so independent concurrent moves both survive.
local function CopyBoard(source)
    local board = {}
    local assigned = {}
    for _, tier in ipairs(Addon.tierOrder) do
        board[tier] = {}
        for _, key in ipairs(type(source) == "table" and type(source[tier]) == "table" and source[tier] or {}) do
            key = tostring(key)
            if not assigned[key] then
                table.insert(board[tier], key)
                assigned[key] = true
            end
        end
    end
    return board
end

local function FindPlacement(board, wantedKey)
    wantedKey = tostring(wantedKey)
    for _, tier in ipairs(Addon.tierOrder) do
        for index, key in ipairs(board[tier] or {}) do
            if tostring(key) == wantedKey then
                return tier, index
            end
        end
    end
end

local function RemovePlacement(board, wantedKey)
    local tier, index = FindPlacement(board, wantedKey)
    if tier then
        table.remove(board[tier], index)
    end
end

local function ValidTier(wantedTier)
    for _, tier in ipairs(Addon.tierOrder) do
        if tier == wantedTier then
            return tier
        end
    end
    return "U"
end

local function OperationLess(left, right)
    local leftClock = tonumber(left.clock) or 0
    local rightClock = tonumber(right.clock) or 0
    if leftClock ~= rightClock then
        return leftClock < rightClock
    end
    return tostring(left.id) < tostring(right.id)
end

function Official:GetPlayerIdentity()
    local name = UnitName("player") or "Unknown"
    local realm = GetRealmName and GetRealmName()
    if realm and realm ~= "" then
        realm = string.gsub(realm, "%s+", "")
        return name .. "-" .. realm
    end
    return name
end

function Official:GetPlayerKey()
    return NormalizeIdentity(self:GetPlayerIdentity())
end

function Official:ResolveTarget(target)
    target = Trim(target)
    if target == "" then
        return nil
    end

    local name, realm = string.match(target, "^([^%-]+)%-(.+)$")
    if not name then
        name = target
        realm = GetRealmName and GetRealmName() or ""
    end
    name = Trim(name)
    realm = string.gsub(Trim(realm), "%s+", "")
    if name == "" then
        return nil
    end

    local identity = realm ~= "" and (name .. "-" .. realm) or name
    return NormalizeIdentity(identity), name, identity
end

function Official:IsOfficer(identity)
    identity = identity or self:GetPlayerIdentity()
    local officers = Addon.db and Addon.db.authority and Addon.db.authority.officers
    if not officers then
        return false
    end

    local key = NormalizeIdentity(identity)
    if officers[key] == true or officers[identity] == true then
        return true
    end
    for savedIdentity, enabled in pairs(officers) do
        if enabled == true and NormalizeIdentity(savedIdentity) == key then
            officers[key] = true
            return true
        end
    end
    return false
end

function Official:IsOwner()
    local owner = Addon.db and Addon.db.authority and Addon.db.authority.owner
    return owner and NormalizeIdentity(owner) == self:GetPlayerKey()
end

function Official:IsLeader()
    return self:IsOwner()
end

function Official:SetCurrentOfficer(enabled)
    local identity = self:GetPlayerIdentity()
    local key = NormalizeIdentity(identity)
    if enabled and not Addon.db.authority.owner then
        Addon.db.authority.owner = identity
        Addon:Print(identity .. " is now the actually leader.")
    elseif enabled and not self:IsOwner() then
        Addon:Print("Only the actually leader, " .. tostring(Addon.db.authority.owner) .. ", can grant officer access.")
        return
    end

    Addon.db.authority.officers[key] = enabled and true or nil
    if enabled then
        Addon:Print(identity .. " can now edit the Official Tier List.")
    else
        Addon:Print(identity .. " no longer has official-list edit access.")
    end

    if Addon.Board then
        Addon.Board:RefreshListControls()
    end
end

function Official:HandleHiddenCommand(message)
    if message == OFFICER_COMMAND then
        self:SetCurrentOfficer(true)
        return true
    elseif message == OFFICER_REVOKE_COMMAND then
        self:SetCurrentOfficer(false)
        return true
    end
    return false
end

function Official:SendAuthorization(action, targetKey, whisperTarget)
    if not SendAddonMessage and not (Addon.Sync and Addon.Sync.QueueMessage) then
        Addon:Print("This client does not expose SendAddonMessage.")
        return false
    end

    local payload = table.concat({ action, AUTH_TOKEN, targetKey, self:GetPlayerIdentity() }, "|")
    if Addon.Sync and Addon.Sync.QueueMessage then
        Addon.Sync:QueueMessage(payload, "WHISPER", whisperTarget, "ALERT")
    else
        SendAddonMessage(MESSAGE_PREFIX, payload, "WHISPER", whisperTarget)
    end
    return true
end

function Official:BroadcastLeader(action, identity, whisperTarget)
    local payload = table.concat({ "AUTH", "LEADER", action, AUTH_TOKEN, identity or "" }, "|")
    if Addon.Sync and Addon.Sync.BroadcastLive then
        Addon.Sync:BroadcastLive(payload)
        if whisperTarget and whisperTarget ~= "" and Addon.Sync.QueueMessage then
            Addon.Sync:QueueMessage(payload, "WHISPER", whisperTarget, "ALERT")
        end
    elseif SendAddonMessage and whisperTarget and whisperTarget ~= "" then
        SendAddonMessage(MESSAGE_PREFIX, payload, "WHISPER", whisperTarget)
    end
end

function Official:SetLeader(target)
    target = Trim(target)
    local lowered = string.lower(target)
    if lowered == "me" or lowered == "self" then
        target = UnitName("player") or ""
    elseif lowered == "target" then
        target = UnitName("target") or ""
    end
    local targetKey, whisperTarget, identity = self:ResolveTarget(target)
    if not targetKey then
        return nil, "Usage: /actually leader <player|target|me>"
    end
    Addon.db.authority.owner = identity
    Addon.db.authority.officers[targetKey] = true
    self:BroadcastLeader("SET", identity, whisperTarget)
    if Addon.Sync then Addon.Sync:MarkDirty(true) end
    if Addon.Board then Addon.Board:RefreshListControls() end
    return identity
end

function Official:ClearLeader()
    local previous = Addon.db.authority.owner
    Addon.db.authority.owner = nil
    self:BroadcastLeader("CLEAR", "")
    if Addon.Sync then Addon.Sync:MarkDirty(true) end
    if Addon.Board then Addon.Board:RefreshListControls() end
    return previous
end

function Official:HandleLeaderCommand(arguments)
    local value = Trim(arguments)
    local lowered = string.lower(value)
    if value == "" then
        Addon:Print("Actually leader: " .. tostring(Addon.db.authority.owner or "none")
            .. ". Use /actually leader <player> or /actually leader clear.")
        return true
    elseif lowered == "clear" or lowered == "none" or lowered == "reset" then
        local previous = self:ClearLeader()
        Addon:Print(previous and ("Actually leader cleared (was " .. tostring(previous) .. ").")
            or "Actually leader is already clear.")
        return true
    end
    local identity, errorMessage = self:SetLeader(value)
    if identity then
        Addon:Print(identity .. " is now the actually leader.")
    else
        Addon:Print(errorMessage)
    end
    return true
end

function Official:GrantOfficer(target)
    if not self:IsOwner() then
        Addon:Print("Only the actually leader can grant officer access.")
        return false
    end

    local targetKey, whisperTarget, displayIdentity = self:ResolveTarget(target)
    if not targetKey then
        Addon:Print("Usage: /actually make officer PlayerName")
        return false
    end

    Addon.db.authority.officers[targetKey] = true
    self:RecordActivity("Granted official edit access to " .. displayIdentity .. ".")
    if Addon.Sync then
        Addon.Sync:MarkDirty(true)
    end
    self:SendAuthorization("GRANT", targetKey, whisperTarget)
    Addon:Print("Officer grant sent to " .. displayIdentity .. ". They must be online with actually loaded.")
    return true
end

function Official:RevokeOfficer(target)
    if not self:IsOwner() then
        Addon:Print("Only the actually leader can revoke officer access.")
        return false
    end

    local targetKey, whisperTarget, displayIdentity = self:ResolveTarget(target)
    if not targetKey then
        Addon:Print("Usage: /actually remove officer PlayerName")
        return false
    end

    Addon.db.authority.officers[targetKey] = nil
    self:RecordActivity("Revoked official edit access from " .. displayIdentity .. ".")
    if Addon.Sync then
        Addon.Sync:MarkDirty(true)
    end
    self:SendAuthorization("REVOKE", targetKey, whisperTarget)
    Addon:Print("Officer revoke sent to " .. displayIdentity .. ".")
    return true
end

function Official:HandleOwnerCommand(rawMessage, lowerMessage)
    local grantPrefix = "make officer "
    local revokePrefix = "remove officer "
    if string.sub(lowerMessage, 1, string.len(grantPrefix)) == grantPrefix then
        self:GrantOfficer(string.sub(rawMessage, string.len(grantPrefix) + 1))
        return true
    elseif string.sub(lowerMessage, 1, string.len(revokePrefix)) == revokePrefix then
        self:RevokeOfficer(string.sub(rawMessage, string.len(revokePrefix) + 1))
        return true
    end
    return false
end

function Official:EnsureOperationState()
    local official = Addon.db.lists.official
    official.baseBoard = type(official.baseBoard) == "table" and official.baseBoard or CopyBoard(official.board)
    official.baseRevision = tonumber(official.baseRevision) or tonumber(official.revision) or 0
    official.baseLastModifiedAt = tonumber(official.baseLastModifiedAt) or tonumber(official.lastModifiedAt) or 0
    official.operations = type(official.operations) == "table" and official.operations or {}
    official.operationClock = tonumber(official.operationClock) or 0
    official.operationStateVersion = 1
    return official
end

function Official:RebuildBoard()
    local official = self:EnsureOperationState()
    local board = CopyBoard(official.baseBoard)
    local operations = {}
    local highestClock = tonumber(official.operationClock) or 0
    for id, operation in pairs(official.operations) do
        if type(operation) == "table" then
            operation.id = tostring(operation.id or id)
            highestClock = math.max(highestClock, tonumber(operation.clock) or 0)
            table.insert(operations, operation)
        end
    end
    table.sort(operations, OperationLess)

    for _, operation in ipairs(operations) do
        if operation.kind == "RESET" then
            board = CopyBoard({})
        elseif operation.kind == "REMOVE" then
            RemovePlacement(board, operation.key)
        elseif operation.kind == "MOVE" and operation.key then
            local key = tostring(operation.key)
            local tier = ValidTier(operation.tier)
            RemovePlacement(board, key)
            local destination = board[tier]
            local insertAt
            if operation.before and operation.before ~= "" then
                local beforeTier, beforeIndex = FindPlacement(board, operation.before)
                if beforeTier == tier then
                    insertAt = beforeIndex
                end
            end
            if not insertAt and operation.after and operation.after ~= "" then
                local afterTier, afterIndex = FindPlacement(board, operation.after)
                if afterTier == tier then
                    insertAt = afterIndex + 1
                end
            end
            table.insert(destination, math.max(1, math.min(insertAt or (#destination + 1), #destination + 1)), key)
        end
    end

    official.board = board
    official.operationClock = highestClock
    official.revision = (tonumber(official.baseRevision) or 0) + #operations
    local latest = operations[#operations]
    if latest then
        official.lastModifiedBy = latest.author
        official.lastModifiedAt = tonumber(latest.timestamp) or 0
    else
        official.lastModifiedBy = official.baseLastModifiedBy
        official.lastModifiedAt = tonumber(official.baseLastModifiedAt) or 0
    end
    return board
end

function Official:NewOperation(kind, fields, author)
    local official = self:EnsureOperationState()
    official.operationClock = (tonumber(official.operationClock) or 0) + 1
    author = author or self:GetPlayerIdentity()
    local id = tostring(official.operationClock) .. "." .. NormalizeIdentity(author) .. "." .. tostring(math.random(100000, 999999))
    local operation = {
        id = id,
        clock = official.operationClock,
        author = author,
        timestamp = time and time() or 0,
        kind = kind,
    }
    for key, value in pairs(fields or {}) do
        operation[key] = value
    end
    official.operations[id] = operation
    return operation
end

function Official:AddAuditEntry(action, author, activity)
    local official = self:EnsureOperationState()
    official.audit = type(official.audit) == "table" and official.audit or {}
    local entry = {
        id = Addon.Util.NewPersistentID(),
        revision = tonumber(official.revision) or 0,
        author = author or self:GetPlayerIdentity(),
        timestamp = time and time() or 0,
        action = tostring(action or "Updated the official tier list."),
        activity = activity == true or nil,
    }
    table.insert(official.audit, entry)
    while #official.audit > AUDIT_LIMIT do
        table.remove(official.audit, 1)
    end
    return entry
end

function Official:RecordBoardChange(action, newBoard, changedKeys, author)
    if not self:IsOfficer() then
        return false
    end

    local official = self:EnsureOperationState()
    newBoard = CopyBoard(newBoard)
    if type(changedKeys) ~= "table" then
        changedKeys = changedKeys and { tostring(changedKeys) } or {}
    end
    if #changedKeys == 0 then
        local seen = {}
        for _, board in ipairs({ official.board or {}, newBoard }) do
            for _, tier in ipairs(Addon.tierOrder) do
                for _, key in ipairs(board[tier] or {}) do
                    seen[tostring(key)] = true
                end
            end
        end
        for key in pairs(seen) do
            local oldTier, oldIndex = FindPlacement(official.board or {}, key)
            local newTier, newIndex = FindPlacement(newBoard, key)
            if oldTier ~= newTier or oldIndex ~= newIndex then
                table.insert(changedKeys, key)
            end
        end
        table.sort(changedKeys)
    end

    local madeOperation = false
    local createdOperations = {}
    for _, key in ipairs(changedKeys) do
        key = tostring(key)
        local tier, index = FindPlacement(newBoard, key)
        if tier then
            local row = newBoard[tier]
            table.insert(createdOperations, self:NewOperation("MOVE", {
                key = key,
                tier = tier,
                before = row[index + 1],
                after = row[index - 1],
            }, author))
        else
            table.insert(createdOperations, self:NewOperation("REMOVE", { key = key }, author))
        end
        madeOperation = true
    end
    if not madeOperation then
        return false
    end

    self:RebuildBoard()
    local auditEntry = self:AddAuditEntry(action, author, false)
    if Addon.Sync then
        Addon.Sync:BroadcastOfficialChange(createdOperations, auditEntry)
        Addon.Sync:MarkDirty(true)
    end
    return true
end

function Official:RecordBoardReset(action, author)
    if not self:IsOfficer() then
        return false
    end
    local operation = self:NewOperation("RESET", nil, author)
    self:RebuildBoard()
    local auditEntry = self:AddAuditEntry(action, author, false)
    if Addon.Sync then
        Addon.Sync:BroadcastOfficialChange({ operation }, auditEntry)
        Addon.Sync:MarkDirty(true)
    end
    return true
end

function Official:RecordActivity(action, author)
    if not self:IsOfficer() then
        return false
    end

    self:AddAuditEntry(action or "Officer discussion activity.", author, true)
    return true
end

function Official:ReceiveAuthorization(message, sender)
    local action, token, targetKey, ownerIdentity = string.match(message or "", "^([^|]+)|([^|]+)|([^|]+)|(.+)$")
    if token ~= AUTH_TOKEN or targetKey ~= self:GetPlayerKey() then
        return
    end

    if action == "GRANT" then
        Addon.db.authority.owner = ownerIdentity
        Addon.db.authority.officers[targetKey] = true
        Addon:Print("Official edit access received from " .. tostring(sender) .. ".")
    elseif action == "REVOKE" then
        Addon.db.authority.officers[targetKey] = nil
        Addon:Print("Official edit access was revoked by " .. tostring(sender) .. ".")
    else
        return
    end

    if Addon.Board then
        Addon.Board:RefreshListControls()
    end
end

function Official:ReceiveLeader(message)
    local action, token, identity = string.match(message or "", "^AUTH|LEADER|([^|]+)|([^|]+)|(.*)$")
    if token ~= AUTH_TOKEN then return end
    if action == "CLEAR" then
        Addon.db.authority.owner = nil
    elseif action == "SET" and identity ~= "" then
        local key = NormalizeIdentity(identity)
        Addon.db.authority.owner = identity
        Addon.db.authority.officers[key] = true
    else
        return
    end
    if Addon.Board then Addon.Board:RefreshListControls() end
end

if RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix(MESSAGE_PREFIX)
end

local messageFrame = CreateFrame("Frame")
messageFrame:RegisterEvent("CHAT_MSG_ADDON")
messageFrame:SetScript("OnEvent", function(_, event, prefix, message, channel, sender)
    local messageKind = string.match(message or "", "^([^|]+)|")
    if event ~= "CHAT_MSG_ADDON" or prefix ~= MESSAGE_PREFIX
        or (messageKind ~= "AUTH" and messageKind ~= "GRANT" and messageKind ~= "REVOKE") then return end
    if string.find(message or "", "^AUTH|LEADER|") and (channel == "GUILD" or channel == "WHISPER") then
        Official:ReceiveLeader(message, sender)
    elseif channel == "WHISPER" then
        Official:ReceiveAuthorization(message, sender)
    end
end)
