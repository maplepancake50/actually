local addonName = ...

Actually = Actually or {}
local Addon = Actually
Addon.Modules = Addon.Modules or {}
local Util = Addon.Util or {}
Addon.Util = Util

Addon.name = addonName or "actually"
Addon.version = "0.3.0"
Addon.MESSAGE_PREFIX = "ACTUALLY"
Addon.tierOrder = { "S", "A", "B", "C", "D", "U" }
Addon.DEFAULT_PERSONAL_LIST_NAME = "My Tier List"
Addon.OFFICIAL_LIST_NAME = "Official Tier List"

function Util.Trim(value)
    local trimmed = string.gsub(tostring(value or ""), "^%s*(.-)%s*$", "%1")
    return trimmed
end

function Util.ShortName(identity)
    local value = Util.Trim(identity)
    if value == "" then
        return "Unknown"
    end
    return Util.Trim(string.match(value, "^([^%-]+)") or value)
end

function Util.NormalizeIdentity(identity)
    return string.lower(string.gsub(Util.Trim(identity), "%s+", ""))
end

function Util.NormalizeCharacter(identity)
    return string.lower(string.gsub(Util.ShortName(identity), "%s+", ""))
end

function Util.DeepCopy(source)
    local result = {}
    if type(source) ~= "table" then
        return result
    end
    for key, value in pairs(source) do
        result[key] = type(value) == "table" and Util.DeepCopy(value) or value
    end
    return result
end

function Util.NewPersistentID()
    local timestamp = time and time() or 0
    return tostring(timestamp) .. "." .. tostring(math.random(100000, 999999))
end

function Util.SetBackdrop(frame, color, borderColor)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(color[1], color[2], color[3], color[4] or 1)
    frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
end

local defaults = {
    version = 11,
    customSpells = {},
    spellTombstones = {},
    sync = {
        knownPeers = {},
    },
    assistLog = {
        fights = {},
        pendingUploads = {},
        activeParticipantRuns = {},
        deletedFights = {},
        timerPosition = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 150 },
    },
    focusAssignments = {
        targetsText = "",
        assignedTarget = "",
        assignedBy = "",
        assignmentRevision = "",
        dps = {},
        preferred = {},
    },
    callerArrow = {
        enabled = false,
        x = 0,
        y = -145,
        size = 110,
    },
    fapAlert = {
        enabled = true,
        cooldownUntil = 0,
    },
    cacheTips = {
        healer = "",
        dps = "",
        frontline = "",
    },
    backups = {
        snapshots = {},
    },
    discussions = {},
    gear = {
        sets = {},
        tombstones = {},
    },
    authority = {
        officers = {},
        revision = 0,
        updatedAt = 0,
        updatedBy = "",
        changeID = "",
        stateVersion = 1,
    },
    lists = {
        personal = {},
        official = {
            name = Addon.OFFICIAL_LIST_NAME,
            board = {},
            revision = 0,
            audit = {},
            baseBoard = {},
            baseRevision = 0,
            baseLastModifiedAt = 0,
            operations = {},
            operationClock = 0,
            baseAuthorityRevision = 0,
        },
    },
    activeList = {
        kind = "personal",
        name = Addon.DEFAULT_PERSONAL_LIST_NAME,
    },
    minimap = {
        angle = 225,
    },
    pet = {
        shown = false,
        visibilityVersion = 1,
        x = 360,
        y = -180,
        scale = 1,
    },
}

local function CopyDefaults(source, destination)
    if type(destination) ~= "table" then
        destination = {}
    end

    for key, value in pairs(source) do
        if type(value) == "table" then
            destination[key] = CopyDefaults(value, destination[key])
        elseif destination[key] == nil then
            destination[key] = value
        end
    end

    return destination
end

local function IsLegacyBoardAudit(entry)
    if type(entry) ~= "table" or entry.activity then
        return false
    end
    local action = string.lower(tostring(entry.action or ""))
    if string.find(action, "^granted official edit access")
        or string.find(action, "^revoked official edit access")
        or string.find(action, "^changed .- category")
        or string.find(action, "^marked .- as coa")
        or string.find(action, "^unmarked .- as coa") then
        return false
    end
    return true
end

local function InitializeListStorage(db)
    local previousVersion = tonumber(db.version) or 0
    db.lists = type(db.lists) == "table" and db.lists or {}
    db.lists.personal = type(db.lists.personal) == "table" and db.lists.personal or {}
    db.lists.official = CopyDefaults(defaults.lists.official, db.lists.official)
    db.lists.official.audit = type(db.lists.official.audit) == "table" and db.lists.official.audit or {}
    db.authority = CopyDefaults(defaults.authority, db.authority)
    db.authority.officers = type(db.authority.officers) == "table" and db.authority.officers or {}
    db.authority.revision = tonumber(db.authority.revision) or 0
    if db.authority.owner and db.authority.owner ~= "" and db.authority.revision < 1 then
        db.authority.revision = 1
    end
    db.authority.updatedAt = tonumber(db.authority.updatedAt) or 0
    db.authority.updatedBy = tostring(db.authority.updatedBy or db.authority.owner or "")
    db.authority.changeID = tostring(db.authority.changeID or "")
    db.authority.stateVersion = 1
    local official = db.lists.official
    if type(official.operations) ~= "table" then
        official.operations = {}
    end
    if type(official.baseBoard) ~= "table" or not official.operationStateVersion then
        -- Version 7 used one revision for board and authorization activity.
        -- Recover the last genuine board revision before freezing the baseline.
        local boardRevision
        local boardModifiedAt
        local boardModifiedBy
        for _, entry in ipairs(official.audit or {}) do
            if IsLegacyBoardAudit(entry) then
                local entryRevision = tonumber(entry.revision) or 0
                local entryTimestamp = tonumber(entry.timestamp) or 0
                if not boardRevision or entryRevision > boardRevision
                    or (entryRevision == boardRevision and entryTimestamp > boardModifiedAt) then
                    boardRevision = entryRevision
                    boardModifiedAt = entryTimestamp
                    boardModifiedBy = entry.author
                end
            end
        end
        official.baseBoard = Util.DeepCopy(official.board)
        official.baseRevision = boardRevision or tonumber(official.revision) or 0
        official.baseLastModifiedBy = boardModifiedBy or official.lastModifiedBy
        official.baseLastModifiedAt = boardModifiedAt or tonumber(official.lastModifiedAt) or 0
        official.operations = {}
        official.operationClock = 0
        official.operationStateVersion = 2
    end
    if previousVersion < 11 then
        official.baseAuthorityRevision = db.authority.revision
    else
        official.baseAuthorityRevision = tonumber(official.baseAuthorityRevision) or db.authority.revision
    end
    for _, operation in pairs(official.operations) do
        if type(operation) == "table" and operation.authorityRevision == nil then
            operation.authorityRevision = db.authority.revision
        end
    end
    official.operationStateVersion = 2
    db.discussions = type(db.discussions) == "table" and db.discussions or {}
    db.gear = type(db.gear) == "table" and db.gear or {}
    db.gear.sets = type(db.gear.sets) == "table" and db.gear.sets or {}
    db.gear.tombstones = type(db.gear.tombstones) == "table" and db.gear.tombstones or {}
    db.spellTombstones = type(db.spellTombstones) == "table" and db.spellTombstones or {}
    db.sync = type(db.sync) == "table" and db.sync or {}
    db.sync.knownPeers = type(db.sync.knownPeers) == "table" and db.sync.knownPeers or {}
    db.assistLog = type(db.assistLog) == "table" and db.assistLog or {}
    db.assistLog.fights = type(db.assistLog.fights) == "table" and db.assistLog.fights or {}
    db.assistLog.pendingUploads = type(db.assistLog.pendingUploads) == "table"
        and db.assistLog.pendingUploads or {}
    db.assistLog.activeParticipantRuns = type(db.assistLog.activeParticipantRuns) == "table"
        and db.assistLog.activeParticipantRuns or {}
    db.assistLog.deletedFights = type(db.assistLog.deletedFights) == "table"
        and db.assistLog.deletedFights or {}
    db.backups = type(db.backups) == "table" and db.backups or {}
    db.backups.snapshots = type(db.backups.snapshots) == "table" and db.backups.snapshots or {}

    if type(db.lists.personal[Addon.DEFAULT_PERSONAL_LIST_NAME]) ~= "table" then
        db.lists.personal[Addon.DEFAULT_PERSONAL_LIST_NAME] = {
            name = Addon.DEFAULT_PERSONAL_LIST_NAME,
            board = Util.DeepCopy(db.board),
        }
    end

    for name, list in pairs(db.lists.personal) do
        if type(list) ~= "table" then
            db.lists.personal[name] = { name = name, board = {} }
        else
            list.name = name
            list.board = type(list.board) == "table" and list.board or {}
        end
    end

    if type(db.activeList) ~= "table" then
        db.activeList = {}
    end
    if db.activeList.kind == "official" then
        db.activeList.name = Addon.OFFICIAL_LIST_NAME
    elseif db.activeList.kind ~= "personal" or not db.lists.personal[db.activeList.name] then
        db.activeList.kind = "personal"
        db.activeList.name = Addon.DEFAULT_PERSONAL_LIST_NAME
    end

    db.board = nil
    db.version = 11
end

function Addon:GetActiveList()
    if self.db.activeList.kind == "official" then
        return self.db.lists.official
    end
    return self.db.lists.personal[self.db.activeList.name]
end

function Addon:IsOfficialList()
    return self.db.activeList.kind == "official"
end

function Addon:CanEditActiveList()
    if not self:IsOfficialList() then
        return true
    end
    if not self.Official or not self.Official:IsOfficer() then
        return false
    end
    return not self.Sync or not self.Sync.IsOfficialEditReady or self.Sync:IsOfficialEditReady()
end

function Addon:SetActiveList(kind, name)
    if kind == "official" then
        self.db.activeList.kind = "official"
        self.db.activeList.name = self.OFFICIAL_LIST_NAME
        return true
    end

    if kind == "personal" and self.db.lists.personal[name] then
        self.db.activeList.kind = "personal"
        self.db.activeList.name = name
        return true
    end
    return false
end

function Addon:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0actually:|r " .. tostring(message))
end

function Addon:ResetBoard()
    if not self:CanEditActiveList() then
        self:Print(self.OFFICIAL_LIST_NAME .. " is read-only.")
        return
    end

    if self:IsOfficialList() and self.Official then
        self.Official:RecordBoardReset("Reset every spell placement to the Pool.")
    else
        self:GetActiveList().board = {}
    end
    if self.Board then
        self.Board:ResetState()
        self.Board:RefreshListControls()
        self.Board:RefreshAuditLog()
    end
    self:Print("Tier board reset.")
end

function Addon:Toggle()
    if not self.Board or not self.Board.frame then
        return
    end

    if self.Board.frame:IsShown() then
        self.Board.frame:Hide()
    else
        self.Board.frame:Show()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, loadedAddon)
    if event ~= "ADDON_LOADED" or loadedAddon ~= Addon.name then
        return
    end

    ActuallyDB = CopyDefaults(defaults, ActuallyDB)
    -- Pet visibility is session-only: every reload or login starts hidden.
    ActuallyDB.pet.shown = false
    ActuallyDB.pet.visibilityVersion = 1
    InitializeListStorage(ActuallyDB)
    Addon.db = ActuallyDB

    if Addon.Board then
        Addon.Board:Create()
    end
    if Addon.MinimapButton then
        Addon.MinimapButton:Create()
    end
    if Addon.Pet then
        Addon.Pet:Create()
    end
    if Addon.Sync then
        Addon.Sync:Initialize()
    end
    if Addon.Backups then
        Addon.Backups:Initialize()
    end
    if Addon.RaidTargets then
        Addon.RaidTargets:Initialize()
    end
    if Addon.AssistLogUI and Addon.AssistLogUI.CreateTimer then
        Addon.AssistLogUI:CreateTimer()
    end
    if Addon.CallerArrow then
        Addon.CallerArrow:Initialize()
    end
    if Addon.FapAlert then
        Addon.FapAlert:Initialize()
    end
    if Addon.CacheTips then
        Addon.CacheTips:Create()
    end
    SLASH_ACTUALLY1 = "/actually"
    SLASH_ACTUALLY2 = "/act"
    SlashCmdList.ACTUALLY = function(message)
        local rawMessage = string.gsub(message or "", "^%s*(.-)%s*$", "%1")
        local lowerMessage = string.lower(rawMessage)
        if lowerMessage == "arc" or string.sub(lowerMessage, 1, 4) == "arc " then
            local arc = Addon.Modules and Addon.Modules.RaidCooldowns
            if arc and arc.DebugCommands and type(arc.DebugCommands.Handle) == "function" then
                local argument = lowerMessage == "arc" and "" or string.sub(rawMessage, 5)
                arc.DebugCommands:Handle(argument)
            else
                Addon:Print("Actually Raid Cooldowns is not available")
            end
            return
        end
        if lowerMessage == "reset" then
            if Addon.Board and Addon.Board.RequestReset then
                Addon.Board:RequestReset()
            else
                Addon:ResetBoard()
            end
        elseif lowerMessage == "pet" then
            Addon.Pet:Toggle()
        elseif lowerMessage == "pet reset" then
            Addon.Pet:ResetPosition()
        elseif lowerMessage == "pet sneeze" then
            Addon.Pet:Show()
            Addon.Pet:Play("sneeze")
        elseif lowerMessage == "pet emote" then
            Addon.Pet:Show()
            Addon.Pet:PlayPassiveEmote()
        elseif lowerMessage == "pet sad" then
            Addon.Pet:Show()
            Addon.Pet:Play("sad")
        elseif lowerMessage == "fap" and Addon.FapAlert then
            Addon.FapAlert:Trigger()
        elseif lowerMessage == "sync" and Addon.Sync then
            Addon.Sync:PrintStatus(false)
        elseif lowerMessage == "sync now" and Addon.Sync then
            Addon.Sync:PrintStatus(true)
        elseif lowerMessage == "sync debug" and Addon.Sync then
            Addon.Sync:SetDebug(not Addon.Sync.debugEnabled)
        elseif lowerMessage == "sync log" and Addon.Sync then
            Addon.Sync:PrintLog()
        elseif (lowerMessage == "backup" or lowerMessage == "backups") and Addon.Backups then
            Addon.Backups:HandleCommand("")
        elseif string.sub(lowerMessage, 1, 7) == "backup " and Addon.Backups then
            Addon.Backups:HandleCommand(string.sub(rawMessage, 8))
        elseif (lowerMessage == "assisttracker" or lowerMessage == "assist tracker") and Addon.AssistLogUI then
            Addon.AssistLogUI:Show()
        elseif string.sub(lowerMessage, 1, 14) == "assisttracker " and Addon.RaidTargets then
            if not Addon.RaidTargets:HandleCommand(string.sub(rawMessage, 15)) then
                Addon:Print("Assist Tracker: start [fight], stop, toggle [fight], timer, caller <player|target|me>, pending [retry|clear]")
            end
        elseif string.sub(lowerMessage, 1, 15) == "assist tracker " and Addon.RaidTargets then
            if not Addon.RaidTargets:HandleCommand(string.sub(rawMessage, 16)) then
                Addon:Print("Assist Tracker: start [fight], stop, toggle [fight], timer, caller <player|target|me>, pending [retry|clear]")
            end
        elseif (lowerMessage == "caller" or lowerMessage == "shotcaller") and Addon.RaidTargets then
            Addon.RaidTargets:HandleCommand("caller")
        elseif string.sub(lowerMessage, 1, 7) == "caller " and Addon.RaidTargets then
            Addon.RaidTargets:HandleCommand("caller " .. string.sub(rawMessage, 8))
        elseif string.sub(lowerMessage, 1, 11) == "shotcaller " and Addon.RaidTargets then
            Addon.RaidTargets:HandleCommand("caller " .. string.sub(rawMessage, 12))
        elseif lowerMessage == "leader" and Addon.Official then
            Addon.Official:HandleLeaderCommand("")
        elseif string.sub(lowerMessage, 1, 7) == "leader " and Addon.Official then
            Addon.Official:HandleLeaderCommand(string.sub(rawMessage, 8))
        elseif string.sub(lowerMessage, 1, 10) == "sync pull " and Addon.Sync then
            Addon.Sync:ForceSync(string.sub(rawMessage, 11))
        elseif Addon.Official and Addon.Official:HandleHiddenCommand(lowerMessage) then
            return
        elseif Addon.Official and Addon.Official:HandleOwnerCommand(rawMessage, lowerMessage) then
            return
        else
            Addon:Toggle()
        end
    end

    Addon:Print("Prototype loaded. Type /actually to open the board.")
    self:UnregisterEvent("ADDON_LOADED")
end)
