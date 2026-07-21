Actually = Actually or {}
local Addon = Actually

local FocusAssignments = {}
Addon.FocusAssignments = FocusAssignments

local KIND = "FA"
local PROTOCOL = 1

local function ClearTable(value)
    for key in pairs(value or {}) do
        value[key] = nil
    end
end

local function ShortName(identity)
    return Addon.Util.ShortName(identity)
end

local function PlayerKey(identity)
    return Addon.Util.NormalizeCharacter(identity)
end

local function Encode(value)
    return string.gsub(tostring(value or ""), "([^%w%-%._ ])", function(character)
        return string.format("%%%02X", string.byte(character))
    end)
end

local function Decode(value)
    return string.gsub(value or "", "%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
end

local function Distribution()
    if (GetNumRaidMembers and GetNumRaidMembers() or 0) > 0 then
        return "RAID"
    end
    if (GetNumPartyMembers and GetNumPartyMembers() or 0) > 0 then
        return "PARTY"
    end
end

local function QueueMessage(message)
    local channel = Distribution()
    if not channel then return false end
    if Addon.Sync and Addon.Sync.initialized and Addon.Sync.QueueMessage then
        Addon.Sync:QueueMessage(message, channel)
        return true
    end
    if SendAddonMessage then
        return pcall(SendAddonMessage, Addon.MESSAGE_PREFIX, message, channel)
    end
    return false
end

function FocusAssignments:InitializeStorage()
    Addon.db.focusAssignments = type(Addon.db.focusAssignments) == "table"
        and Addon.db.focusAssignments or {}
    local db = Addon.db.focusAssignments
    db.targetsText = tostring(db.targetsText or "")
    db.dps = type(db.dps) == "table" and db.dps or {}
    db.preferred = type(db.preferred) == "table" and db.preferred or {}
    self.db = db
end

function FocusAssignments:GetPlayerName()
    return ShortName(UnitName and UnitName("player"))
end

function FocusAssignments:ScanRoster()
    self.roster = self.roster or {}
    ClearTable(self.roster)

    local raidCount = GetNumRaidMembers and GetNumRaidMembers() or 0
    if raidCount > 0 then
        for index = 1, raidCount do
            local name, rank, subgroup, level, class, classFile, zone, online, dead = GetRaidRosterInfo(index)
            if name then
                local shortName = ShortName(name)
                local key = PlayerKey(shortName)
                self.roster[key] = {
                    key = key,
                    name = shortName,
                    fullName = name,
                    rank = rank or 0,
                    subgroup = subgroup,
                    level = level,
                    class = class,
                    classFile = classFile,
                    online = online and true or false,
                    dead = dead,
                    unit = "raid" .. index,
                }
            end
        end
    else
        local partyLeaderIndex = GetPartyLeaderIndex and GetPartyLeaderIndex()
        local function AddUnit(unit, rank)
            if not UnitExists or not UnitExists(unit) then return end
            local name = UnitName(unit)
            if not name then return end
            local shortName = ShortName(name)
            local key = PlayerKey(shortName)
            local _, classFile = UnitClass(unit)
            self.roster[key] = {
                key = key,
                name = shortName,
                fullName = name,
                rank = rank or 0,
                classFile = classFile,
                online = not UnitIsConnected or UnitIsConnected(unit) and true or false,
                dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit),
                unit = unit,
            }
        end

        local playerRank = ((partyLeaderIndex == 0)
            or (UnitIsPartyLeader and UnitIsPartyLeader("player"))) and 2 or 0
        AddUnit("player", playerRank)
        local partyCount = GetNumPartyMembers and GetNumPartyMembers() or 0
        for index = 1, partyCount do
            local unit = "party" .. index
            local rank = ((partyLeaderIndex == index)
                or (UnitIsPartyLeader and UnitIsPartyLeader(unit))) and 2 or 0
            AddUnit(unit, rank)
        end
    end

    return self.roster
end


function FocusAssignments:GetSortedRoster()
    local rows = {}
    for key, member in pairs(self.roster or {}) do
        member.key = key
        member.isDPS = self.db.dps[key] and true or false
        table.insert(rows, member)
    end
    table.sort(rows, function(left, right)
        if left.isDPS ~= right.isDPS then return left.isDPS end
        return string.lower(left.name) < string.lower(right.name)
    end)
    return rows
end

function FocusAssignments:SetDPS(name, enabled)
    local key = PlayerKey(name)
    if key == "" then return end
    self.db.dps[key] = enabled and true or nil
    self:BuildAssignments()
end

function FocusAssignments:ParseTargets(text)
    local targets = {}
    local seen = {}
    text = string.gsub(text or "", ",", "\n")
    for rawName in string.gmatch(text .. "\n", "([^\r\n]*)[\r\n]") do
        local name = Addon.Util.Trim(rawName)
        local key = PlayerKey(name)
        if name ~= "" and not seen[key] then
            seen[key] = true
            table.insert(targets, { key = key, name = name })
        end
    end
    return targets
end

function FocusAssignments:CanPublish()
    local raidCount = GetNumRaidMembers and GetNumRaidMembers() or 0
    if raidCount > 0 then
        return (IsRaidLeader and IsRaidLeader()) or (IsRaidOfficer and IsRaidOfficer())
    end
    local partyCount = GetNumPartyMembers and GetNumPartyMembers() or 0
    if partyCount > 0 then
        return IsPartyLeader and IsPartyLeader()
    end
    return true
end

function FocusAssignments:BuildAssignments()
    self:ScanRoster()
    self.assignments = self.assignments or {}
    self.assignmentByPlayer = self.assignmentByPlayer or {}
    ClearTable(self.assignments)
    ClearTable(self.assignmentByPlayer)

    local targets = self:ParseTargets(self.db.targetsText)
    local eligible = {}
    local eligibleByKey = {}
    local usedPlayers = {}

    for _, member in ipairs(self:GetSortedRoster()) do
        if member.isDPS and member.online then
            table.insert(eligible, member)
            eligibleByKey[member.key] = member
        end
    end

    for _, target in ipairs(targets) do
        local preferredKey = self.db.preferred[target.key]
        local member = preferredKey and eligibleByKey[preferredKey]
        if member and not usedPlayers[member.key] then
            self.assignments[target.key] = {
                target = target.name,
                player = member.name,
                playerKey = member.key,
                preferred = true,
            }
            self.assignmentByPlayer[member.key] = target.name
            usedPlayers[member.key] = true
        end
    end

    local nextEligible = 1
    for _, target in ipairs(targets) do
        if not self.assignments[target.key] then
            while eligible[nextEligible] and usedPlayers[eligible[nextEligible].key] do
                nextEligible = nextEligible + 1
            end
            local member = eligible[nextEligible]
            if member then
                local hadPreference = self.db.preferred[target.key] ~= nil
                self.assignments[target.key] = {
                    target = target.name,
                    player = member.name,
                    playerKey = member.key,
                    preferred = not hadPreference,
                }
                self.assignmentByPlayer[member.key] = target.name
                usedPlayers[member.key] = true
                if not hadPreference then
                    self.db.preferred[target.key] = member.key
                end
                nextEligible = nextEligible + 1
            else
                self.assignments[target.key] = { target = target.name, preferred = false }
            end
        end
    end

    if self:CanPublish() then
        self:SetMyAssignment(self.assignmentByPlayer[PlayerKey(self:GetPlayerName())], true)
    end
    self:NotifyChanged()
    return self.assignments
end

function FocusAssignments:ResetPreferredAssignments()
    ClearTable(self.db.preferred)
    self:BuildAssignments()
end

function FocusAssignments:RaidRank(identity)
    local wanted = PlayerKey(identity)
    local raidCount = GetNumRaidMembers and GetNumRaidMembers() or 0
    if raidCount > 0 then
        for index = 1, raidCount do
            local name, rank = GetRaidRosterInfo(index)
            if name and PlayerKey(name) == wanted then return rank or 0 end
        end
        return 0
    end
    self:ScanRoster()
    return self.roster[wanted] and self.roster[wanted].rank or 0
end

function FocusAssignments:IsTrustedSender(sender)
    if not sender then return false end
    return self:RaidRank(sender) > 0
end

function FocusAssignments:BroadcastAssignments()
    if not self:CanPublish() then
        self:SetStatus("Only the raid leader or an assistant can broadcast assignments.", 1, 0.3, 0.3)
        return false
    end
    if not Distribution() then
        self:SetStatus("Join a party or raid before broadcasting.", 1, 0.75, 0.25)
        return false
    end

    self:BuildAssignments()
    local broadcastID = tostring(math.floor((GetTime and GetTime() or 0) * 10) % 1000000)
    QueueMessage(table.concat({ KIND, "R", tostring(PROTOCOL), broadcastID }, "|"))
    local count = 0
    for _, target in ipairs(self:ParseTargets(self.db.targetsText)) do
        local assignment = self.assignments[target.key]
        if assignment and assignment.player then
            QueueMessage(table.concat({
                KIND, "A", tostring(PROTOCOL), broadcastID,
                Encode(assignment.player), Encode(assignment.target),
            }, "|"))
            count = count + 1
        end
    end
    QueueMessage(table.concat({ KIND, "E", tostring(PROTOCOL), broadcastID }, "|"))
    self:SetStatus("Broadcasting " .. tostring(count) .. " focus assignment" .. (count == 1 and "." or "s."), 0.3, 1, 0.3)
    return true
end

function FocusAssignments:HandleMessage(message, sender)
    if not message or PlayerKey(sender) == PlayerKey(self:GetPlayerName()) then return end
    local kind, command, protocol, broadcastID, player, target = string.match(
        message, "^([^|]*)|([^|]*)|([^|]*)|([^|]*)|?([^|]*)|?(.*)$")
    if kind ~= KIND or tonumber(protocol) ~= PROTOCOL or broadcastID == "" then return end
    if not self:IsTrustedSender(sender) then return end

    if command == "R" then
        self.receivingID = broadcastID
        self.receivedMyTarget = nil
        return
    end
    if broadcastID ~= self.receivingID then return end
    if command == "A" then
        if PlayerKey(Decode(player)) == PlayerKey(self:GetPlayerName()) then
            self.receivedMyTarget = Decode(target)
        end
    elseif command == "E" then
        self:SetMyAssignment(self.receivedMyTarget)
        self.receivingID = nil
        self:SetStatus("Assignments received from " .. ShortName(sender) .. ".", 0.3, 1, 0.3)
    end
end

function FocusAssignments:SetMyAssignment(target, localOnly)
    target = Addon.Util.Trim(target or "")
    if target == "" then target = nil end
    self.myAssignment = target
    if InCombatLockdown and InCombatLockdown() then
        self.pendingSecureTarget = target or false
    else
        self.pendingSecureTarget = nil
        if self.UI and self.UI.ApplySecureTarget then
            self.UI:ApplySecureTarget(target)
        end
    end
    if not localOnly then self:NotifyChanged() end
end

function FocusAssignments:SetStatus(text, red, green, blue)
    self.statusText = text
    self.statusColor = { red or 0.8, green or 0.8, blue or 0.8 }
    self:NotifyChanged()
end

function FocusAssignments:NotifyChanged()
    if self.UI and self.UI.Refresh then self.UI:Refresh() end
end

function FocusAssignments:Show()
    if self.UI then self.UI:Show() end
end

function FocusAssignments:Toggle()
    if self.UI then self.UI:Toggle() end
end

function FocusAssignments:OnEvent(event, ...)
    if event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
        self:BuildAssignments()
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, _, sender = ...
        if prefix == Addon.MESSAGE_PREFIX then self:HandleMessage(message, sender) end
    elseif event == "PLAYER_REGEN_ENABLED" and self.pendingSecureTarget ~= nil then
        local pending = self.pendingSecureTarget
        self.pendingSecureTarget = nil
        self:SetMyAssignment(pending ~= false and pending or nil)
    end
end

function FocusAssignments:Initialize()
    if self.initialized then return end
    self.initialized = true
    self:InitializeStorage()
    self.roster = {}
    self.assignments = {}
    self.assignmentByPlayer = {}

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("RAID_ROSTER_UPDATE")
    frame:RegisterEvent("PARTY_MEMBERS_CHANGED")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", function(_, event, ...)
        FocusAssignments:OnEvent(event, ...)
    end)
    self.eventFrame = frame

    if self.UI and self.UI.Create then self.UI:Create() end
    self:BuildAssignments()

    SLASH_ACTUALLYFOCUS1 = "/focusassign"
    SLASH_ACTUALLYFOCUS2 = "/fa"
    SlashCmdList.ACTUALLYFOCUS = function() FocusAssignments:Toggle() end
end
