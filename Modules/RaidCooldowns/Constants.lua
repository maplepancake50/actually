local Addon = Actually

Addon.Modules = Addon.Modules or {}
if not Addon.RegisterModule then
    function Addon:RegisterModule(name, module)
        self.Modules[name] = module
        return module
    end
end

local ARC = Addon:RegisterModule("RaidCooldowns", {})
Addon.RaidCooldowns = ARC

ARC.Constants = {
    MODULE_NAME = "RaidCooldowns",
    DISPLAY_NAME = "Actually Raid Cooldowns",
    WIP_TEXT = "|cffff9f1aWORK IN PROGRESS|r",
    GLOBAL_TABLE = "Actually.Modules.RaidCooldowns",
    SAVED_VARIABLES = "ActuallyDB",
    COMM_PREFIX = "ARC",
    PROTOCOL_VERSION = 5,
    SLASH_KEY = "ACTUALLY_RAID_COOLDOWNS",
    SLASH_COMMANDS = { "/arc", "/actuallyraidcooldowns" },
    BOOK_TYPE = BOOKTYPE_SPELL or "spell",
    MAX_COOLDOWN = 604800,
    MAX_BUNDLE_SPELLS = 12,
    BUNDLE_SYNC_INTERVAL = 3.0,
    BUNDLE_SYNC_TIMEOUT = 12.0,
    REPORT_MIN_INTERVAL = 1.0,
    REQUEST_THROTTLE = 5.0,
    REPORT_STALE_AFTER = 45.0,
    REPORT_FORGET_AFTER = 300.0,
    GROUP_CAPABILITY_SCAN_INTERVAL = 10.0,
    UI_UPDATE_INTERVAL = 0.1,
}

ARC.Modules = {}

function ARC:NewModule(name)
    local module = {}
    self.Modules[name] = module
    self[name] = module
    return module
end

function ARC:Now()
    return GetTime and GetTime() or 0
end

function ARC:Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff80c0ffARC:|r " .. tostring(message))
    end
end

function ARC:Debug(message)
    if self.db and self.db.profile and self.db.profile.debug then
        self:Print("|cffaaaaaa" .. tostring(message) .. "|r")
    end
end
