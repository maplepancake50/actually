Actually = Actually or {}
local Addon = Actually

local Official = {}
Addon.Official = Official

local OFFICER_COMMAND = "council cachekeeper"
local OFFICER_REVOKE_COMMAND = OFFICER_COMMAND .. " off"
local AUDIT_LIMIT = 100
local MESSAGE_PREFIX = "ACTUALLY"
local AUTH_TOKEN = "cachekeeper-v1"

local function Trim(value)
    return string.gsub(value or "", "^%s*(.-)%s*$", "%1")
end

local function NormalizeIdentity(identity)
    identity = string.gsub(Trim(identity), "%s+", "")
    return string.lower(identity)
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

function Official:SetCurrentOfficer(enabled)
    local identity = self:GetPlayerIdentity()
    local key = NormalizeIdentity(identity)
    if enabled and not Addon.db.authority.owner then
        Addon.db.authority.owner = identity
        Addon:Print(identity .. " is now the official-list owner.")
    elseif enabled and not self:IsOwner() then
        Addon:Print("Only " .. tostring(Addon.db.authority.owner) .. " can grant officer access.")
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
    if not SendAddonMessage then
        Addon:Print("This client does not expose SendAddonMessage.")
        return false
    end

    local payload = table.concat({ action, AUTH_TOKEN, targetKey, self:GetPlayerIdentity() }, "|")
    SendAddonMessage(MESSAGE_PREFIX, payload, "WHISPER", whisperTarget)
    return true
end

function Official:GrantOfficer(target)
    if not self:IsOwner() then
        Addon:Print("Only the official-list owner can grant officer access.")
        return false
    end

    local targetKey, whisperTarget, displayIdentity = self:ResolveTarget(target)
    if not targetKey then
        Addon:Print("Usage: /actually make officer PlayerName")
        return false
    end

    Addon.db.authority.officers[targetKey] = true
    self:RecordChange("Granted official edit access to " .. displayIdentity .. ".")
    self:SendAuthorization("GRANT", targetKey, whisperTarget)
    Addon:Print("Officer grant sent to " .. displayIdentity .. ". They must be online with actually loaded.")
    return true
end

function Official:RevokeOfficer(target)
    if not self:IsOwner() then
        Addon:Print("Only the official-list owner can revoke officer access.")
        return false
    end

    local targetKey, whisperTarget, displayIdentity = self:ResolveTarget(target)
    if not targetKey then
        Addon:Print("Usage: /actually remove officer PlayerName")
        return false
    end

    Addon.db.authority.officers[targetKey] = nil
    self:RecordChange("Revoked official edit access from " .. displayIdentity .. ".")
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

function Official:RecordChange(action, author)
    if not self:IsOfficer() then
        return false
    end

    local official = Addon.db.lists.official
    official.revision = (tonumber(official.revision) or 0) + 1
    official.audit = type(official.audit) == "table" and official.audit or {}

    local entry = {
        revision = official.revision,
        author = author or self:GetPlayerIdentity(),
        timestamp = time and time() or 0,
        action = tostring(action or "Updated the official tier list."),
    }
    table.insert(official.audit, entry)
    while #official.audit > AUDIT_LIMIT do
        table.remove(official.audit, 1)
    end

    official.lastModifiedBy = entry.author
    official.lastModifiedAt = entry.timestamp
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

if RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix(MESSAGE_PREFIX)
end

local messageFrame = CreateFrame("Frame")
messageFrame:RegisterEvent("CHAT_MSG_ADDON")
messageFrame:SetScript("OnEvent", function(_, event, prefix, message, channel, sender)
    if event == "CHAT_MSG_ADDON" and prefix == MESSAGE_PREFIX and channel == "WHISPER" then
        Official:ReceiveAuthorization(message, sender)
    end
end)
