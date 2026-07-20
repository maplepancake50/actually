local addonName = ...

Actually = Actually or {}
local Addon = Actually

Addon.name = addonName or "actually"
Addon.version = "0.1.0"
Addon.tierOrder = { "S", "A", "B", "C", "D", "U" }
Addon.DEFAULT_PERSONAL_LIST_NAME = "My Tier List"
Addon.OFFICIAL_LIST_NAME = "Official Tier List"

local defaults = {
    version = 3,
    customSpells = {},
    lists = {
        personal = {},
        official = {
            name = Addon.OFFICIAL_LIST_NAME,
            board = {},
            revision = 0,
            audit = {},
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
        shown = true,
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

local function CopyTable(source)
    local result = {}
    if type(source) ~= "table" then
        return result
    end

    for key, value in pairs(source) do
        if type(value) == "table" then
            result[key] = CopyTable(value)
        else
            result[key] = value
        end
    end
    return result
end

local function InitializeListStorage(db)
    db.lists = type(db.lists) == "table" and db.lists or {}
    db.lists.personal = type(db.lists.personal) == "table" and db.lists.personal or {}
    db.lists.official = CopyDefaults(defaults.lists.official, db.lists.official)

    if type(db.lists.personal[Addon.DEFAULT_PERSONAL_LIST_NAME]) ~= "table" then
        db.lists.personal[Addon.DEFAULT_PERSONAL_LIST_NAME] = {
            name = Addon.DEFAULT_PERSONAL_LIST_NAME,
            board = CopyTable(db.board),
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
    db.version = 3
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
    return not self:IsOfficialList()
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

    self:GetActiveList().board = {}
    if self.Board then
        self.Board:ResetState()
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

    SLASH_ACTUALLY1 = "/actually"
    SLASH_ACTUALLY2 = "/act"
    SlashCmdList.ACTUALLY = function(message)
        message = string.lower(message or "")
        if message == "reset" then
            Addon:ResetBoard()
        elseif message == "pet" then
            Addon.Pet:Toggle()
        elseif message == "pet reset" then
            Addon.Pet:ResetPosition()
        elseif message == "pet sneeze" then
            Addon.Pet:Show()
            Addon.Pet:Play("sneeze")
        elseif message == "pet emote" then
            Addon.Pet:Show()
            Addon.Pet:PlayPassiveEmote()
        else
            Addon:Toggle()
        end
    end

    Addon:Print("Prototype loaded. Type /actually to open the board.")
    self:UnregisterEvent("ADDON_LOADED")
end)
