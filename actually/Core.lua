local addonName = ...

Actually = Actually or {}
local Addon = Actually

Addon.name = addonName or "actually"
Addon.version = "0.1.0"
Addon.tierOrder = { "S", "A", "B", "C", "D", "U" }

local defaults = {
    version = 2,
    board = {},
    customSpells = {},
    minimap = {
        angle = 225,
    },
    window = {},
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

function Addon:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0actually:|r " .. tostring(message))
end

function Addon:ResetBoard()
    ActuallyDB.board = {}
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
    Addon.db = ActuallyDB

    if Addon.Board then
        Addon.Board:Create()
    end
    if Addon.MinimapButton then
        Addon.MinimapButton:Create()
    end

    SLASH_ACTUALLY1 = "/actually"
    SLASH_ACTUALLY2 = "/act"
    SlashCmdList.ACTUALLY = function(message)
        message = string.lower(message or "")
        if message == "reset" then
            Addon:ResetBoard()
        else
            Addon:Toggle()
        end
    end

    Addon:Print("Prototype loaded. Type /actually to open the board.")
    self:UnregisterEvent("ADDON_LOADED")
end)
