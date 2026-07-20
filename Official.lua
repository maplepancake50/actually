Actually = Actually or {}
local Addon = Actually

local Official = {}
Addon.Official = Official

local OFFICER_COMMAND = "council cachekeeper"
local OFFICER_REVOKE_COMMAND = OFFICER_COMMAND .. " off"
local AUDIT_LIMIT = 100

function Official:GetPlayerIdentity()
    local name = UnitName("player") or "Unknown"
    local realm = GetRealmName and GetRealmName()
    if realm and realm ~= "" then
        realm = string.gsub(realm, "%s+", "")
        return name .. "-" .. realm
    end
    return name
end

function Official:IsOfficer(identity)
    identity = identity or self:GetPlayerIdentity()
    return Addon.db
        and Addon.db.authority
        and Addon.db.authority.officers
        and Addon.db.authority.officers[identity] == true
end

function Official:SetCurrentOfficer(enabled)
    local identity = self:GetPlayerIdentity()
    Addon.db.authority.officers[identity] = enabled and true or nil
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

