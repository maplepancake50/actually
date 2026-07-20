local addonName = ...

Actually = Actually or {}
local Addon = Actually
local Util = Addon.Util or {}
Addon.Util = Util

Addon.name = addonName or "actually"
Addon.version = "0.1.0"
Addon.MESSAGE_PREFIX = "ACTUALLY"
Addon.tierOrder = { "S", "A", "B", "C", "D", "U" }
Addon.DEFAULT_PERSONAL_LIST_NAME = "My Tier List"
Addon.OFFICIAL_LIST_NAME = "Official Tier List"

function Util.Trim(value)
    return string.gsub(tostring(value or ""), "^%s*(.-)%s*$", "%1")
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
    version = 8,
    customSpells = {},
    spellTombstones = {},
    sync = {
        knownPeers = {},
    },
    discussions = {},
    authority = {
        officers = {},
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
    db.lists = type(db.lists) == "table" and db.lists or {}
    db.lists.personal = type(db.lists.personal) == "table" and db.lists.personal or {}
    db.lists.official = CopyDefaults(defaults.lists.official, db.lists.official)
    db.lists.official.audit = type(db.lists.official.audit) == "table" and db.lists.official.audit or {}
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
        official.operationStateVersion = 1
    end
    db.authority = CopyDefaults(defaults.authority, db.authority)
    db.authority.officers = type(db.authority.officers) == "table" and db.authority.officers or {}
    db.discussions = type(db.discussions) == "table" and db.discussions or {}
    db.spellTombstones = type(db.spellTombstones) == "table" and db.spellTombstones or {}
    db.sync = type(db.sync) == "table" and db.sync or {}
    db.sync.knownPeers = type(db.sync.knownPeers) == "table" and db.sync.knownPeers or {}

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
    db.version = 8
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
    return not self:IsOfficialList() or (self.Official and self.Official:IsOfficer())
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

    SLASH_ACTUALLY1 = "/actually"
    SLASH_ACTUALLY2 = "/act"
    SlashCmdList.ACTUALLY = function(message)
        local rawMessage = string.gsub(message or "", "^%s*(.-)%s*$", "%1")
        local lowerMessage = string.lower(rawMessage)
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
        elseif lowerMessage == "sync" and Addon.Sync then
            Addon.Sync:PrintStatus(false)
        elseif lowerMessage == "sync now" and Addon.Sync then
            Addon.Sync:PrintStatus(true)
        elseif lowerMessage == "sync debug" and Addon.Sync then
            Addon.Sync:SetDebug(not Addon.Sync.debugEnabled)
        elseif lowerMessage == "sync log" and Addon.Sync then
            Addon.Sync:PrintLog()
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
