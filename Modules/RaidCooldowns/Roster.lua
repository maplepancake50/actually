local ARC = Actually.Modules.RaidCooldowns
local Roster = ARC:NewModule("Roster")

local function normalize(name)
    if type(name) ~= "string" then return nil end
    name = string.gsub(name, "%s+", "")
    return name ~= "" and string.lower(name) or nil
end

local function shortName(name)
    return name and (string.match(name, "^[^-]+") or name) or nil
end

local function guildInfo(unit)
    if type(GetGuildInfo) ~= "function" then return nil, false end
    local ok, guild = pcall(GetGuildInfo, unit)
    if not ok then return nil, false end
    if type(guild) ~= "string" or guild == "" then guild = nil end
    return guild, true
end

function Roster:Initialize()
    self.byKey = {}
    self.byName = {}
    self.byGUID = {}
    self.generation = 0
end

function Roster:PlayerKey(guid, fullName)
    return guid or normalize(fullName)
end

function Roster:AddUnit(unit)
    if not UnitExists or not UnitExists(unit) then return end
    local name = GetUnitName and GetUnitName(unit, true) or UnitName(unit)
    if not name then return end
    local guid = UnitGUID and UnitGUID(unit)
    local key = self:PlayerKey(guid, name)
    if not key then return end
    local guild, guildKnown = guildInfo(unit)
    local identity = {
        key = key,
        name = name,
        shortName = shortName(name),
        guid = guid,
        unit = unit,
        guild = guild,
        guildKnown = guildKnown,
        connected = not UnitIsConnected or UnitIsConnected(unit) and true or false,
        dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) and true or false,
    }
    self.byKey[key] = identity
    if guid then self.byGUID[guid] = identity end
    self.byName[normalize(name)] = identity
    local short = normalize(shortName(name))
    if short and not self.byName[short] then self.byName[short] = identity end
end

function Roster:Scan()
    self.byKey, self.byName, self.byGUID = {}, {}, {}
    self:AddUnit("player")
    local raidCount = GetNumRaidMembers and GetNumRaidMembers() or 0
    if raidCount > 0 then
        for index = 1, raidCount do self:AddUnit("raid" .. index) end
    else
        local partyCount = GetNumPartyMembers and GetNumPartyMembers() or 0
        for index = 1, partyCount do self:AddUnit("party" .. index) end
    end
    self.generation = self.generation + 1
    ARC.State:UpdateRoster(self)
    if ARC.Automation and ARC.Automation.initialized then ARC.Automation:OnRosterChanged() end
    if ARC.UserList and ARC.UserList.initialized and ARC.UserList.frame:IsShown() then
        ARC.UserList:Refresh()
    end
    if ARC.Requests and ARC.Requests.initialized then ARC.Requests:OnRosterChanged() end
    if ARC.Bundles and ARC.Bundles.initialized then ARC.Bundles:OnRosterChanged() end
    if ARC.Combos and ARC.Combos.initialized then ARC.Combos:OnRosterChanged() end
end

function Roster:UpdateUnitStatus(unit)
    if not unit or not UnitExists or not UnitExists(unit) then return false end
    local guid = UnitGUID and UnitGUID(unit)
    local identity = guid and self.byGUID[guid]
    if not identity then return false end
    local wasConnected = identity.connected
    local connected = not UnitIsConnected or UnitIsConnected(unit) and true or false
    local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) and true or false
    if identity.connected == connected and identity.dead == dead then return false end

    identity.connected = connected
    identity.dead = dead
    identity.unit = unit
    local player = ARC.State and ARC.State.players and ARC.State.players[identity.key]
    if player then
        player.connected = connected
        player.dead = dead
        player.unit = unit
        ARC.State:Changed("unit status")
    end
    return true, connected, wasConnected
end

function Roster:GetPlayer()
    local guid = UnitGUID and UnitGUID("player")
    local name = GetUnitName and GetUnitName("player", true) or UnitName("player")
    local key = self:PlayerKey(guid, name)
    local identity = self.byKey[key]
    if identity then return key, identity end
    local guild, guildKnown = guildInfo("player")
    return key, {
        key = key,
        guid = guid,
        name = name,
        unit = "player",
        guild = guild,
        guildKnown = guildKnown,
        connected = true,
    }
end

function Roster:FindSender(sender)
    return self.byName[normalize(sender)] or self.byName[normalize(shortName(sender))]
end

function Roster:FindGUID(guid)
    return guid and self.byGUID[guid] or nil
end

function Roster:IsInBattleground()
    if type(IsInInstance) == "function" then
        local ok, inInstance, instanceType = pcall(IsInInstance)
        if ok and inInstance and instanceType ~= nil then return instanceType == "pvp" end
    end
    if type(UnitInBattleground) == "function" then
        local ok, battleground = pcall(UnitInBattleground, "player")
        if ok and battleground then return true end
    end
    return false
end

function Roster:GetDistribution()
    if self:IsInBattleground() then return "BATTLEGROUND" end
    if (GetNumRaidMembers and GetNumRaidMembers() or 0) > 0 then return "RAID" end
    if (GetNumPartyMembers and GetNumPartyMembers() or 0) > 0 then return "PARTY" end
    return nil
end

function Roster:IsGrouped()
    return self:GetDistribution() ~= nil
end

function Roster:IsCoordinator(identity)
    return identity ~= nil and ARC:HasCommandAuthority(identity) or false
end

function Roster:IsLocalCoordinator()
    return ARC:HasCommandAuthority()
end
