local Addon = Actually

Addon.Modules = Addon.Modules or {}
if not Addon.RegisterModule then
    function Addon:RegisterModule(name, module)
        self.Modules[name] = module
        return module
    end
end

local ACD = Addon:RegisterModule("AscensionCooldowns", {})
Addon.AscensionCooldowns = ACD

ACD.Constants = {
    MODULE_NAME = "AscensionCooldowns",
    DISPLAY_NAME = "Ascension Cooldowns",
    GLOBAL_TABLE = "Actually.Modules.AscensionCooldowns",
    SAVED_VARIABLES = "ActuallyDB",
    COMM_PREFIX = "AscCD",
    PROTOCOL_VERSION = 1,
    SLASH_KEY = "ACTUALLY_ASCENSION_COOLDOWNS",
    SLASH_COMMANDS = { "/acd", "/ascensioncooldowns" },
    BOOK_TYPE = BOOKTYPE_SPELL or "spell",
    MAX_COOLDOWN = 604800,
    REPORT_MIN_INTERVAL = 1.0,
    REQUEST_THROTTLE = 5.0,
    REPORT_STALE_AFTER = 45.0,
    REPORT_FORGET_AFTER = 300.0,
    UI_UPDATE_INTERVAL = 0.1,
}

ACD.Modules = {}

function ACD:NewModule(name)
    local module = {}
    self.Modules[name] = module
    self[name] = module
    return module
end

function ACD:Now()
    return GetTime and GetTime() or 0
end

function ACD:Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff80c0ffACD:|r " .. tostring(message))
    end
end

function ACD:Debug(message)
    if self.db and self.db.profile and self.db.profile.debug then
        self:Print("|cffaaaaaa" .. tostring(message) .. "|r")
    end
end
