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
    PROTOCOL_VERSION = 6,
    SLASH_KEY = "ACTUALLY_RAID_COOLDOWNS",
    SLASH_COMMANDS = { "/arc", "/actuallyraidcooldowns" },
    BOOK_TYPE = BOOKTYPE_SPELL or "spell",
    MAX_COOLDOWN = 604800,
    MAX_BUNDLE_SPELLS = 12,
    MAX_COMMAND_PLANS = 12,
    BUNDLE_SYNC_INTERVAL = 3.0,
    BUNDLE_SYNC_TIMEOUT = 12.0,
    USE_SYNC_INTERVAL = 2.0,
    USE_SYNC_TIMEOUT = 7.0,
    LEASE_CLAIM_WINDOW = 0.35,
    LEASE_HEARTBEAT_INTERVAL = 3.0,
    LEASE_DURATION = 15.0,
    LATE_CAST_GRACE = 2.5,
    OBSERVED_CAST_HOLD = 5.0,
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

function ARC:HasConfigurationAuthority(identity)
    local official = Actually and Actually.Official
    if not official then return false end
    if type(identity) == "table" then
        identity = identity.name or identity.fullName
    end
    if type(official.IsOfficer) == "function" then
        local ok, allowed = pcall(official.IsOfficer, official, identity)
        if ok and allowed == true then return true end
    end
    if type(official.IsLeader) == "function" then
        local ok, allowed = pcall(official.IsLeader, official, identity)
        if ok and allowed == true then return true end
    end
    return false
end

function ARC:HasCommandAuthority(identity)
    return self:HasConfigurationAuthority(identity)
end

function ARC:RequireConfigurationAuthority(identity)
    if self:HasConfigurationAuthority(identity) then return true end
    self:Print("only an actually officer or the actually leader can change ARC configuration")
    return false
end

function ARC:RequireCommandAuthority(identity)
    if self:HasCommandAuthority(identity) then return true end
    self:Print("only an actually officer or the actually leader can use ARC Commander")
    return false
end

function ARC:EnforceAuthorityVisibility()
    if self:HasCommandAuthority() then return true end
    for _, moduleName in ipairs({
        "Commander", "CommanderConfig", "BundleConfig", "OfficerConfig",
        "SpellConfig", "UserList",
    }) do
        local module = self[moduleName]
        if module and module.frame and module.frame:IsShown() then module.frame:Hide() end
    end
    if self.Bundles and self.Bundles.officerSummary
        and self.Bundles.officerSummary:IsShown() then
        self.Bundles.officerSummary:Hide()
    end
    return false
end

function ARC:ShowWindowContextMenu(dropdown, title, closeFunction)
    if not dropdown or type(closeFunction) ~= "function" then return end
    local function closeWindow()
        if CloseDropDownMenus then CloseDropDownMenus() end
        closeFunction()
    end
    local menu = {
        {
            text = tostring(title or self.Constants.DISPLAY_NAME),
            isTitle = true,
            notCheckable = true,
        },
        {
            text = "Close Window",
            notCheckable = true,
            func = closeWindow,
        },
    }
    if type(EasyMenu) == "function" then
        EasyMenu(menu, dropdown, "cursor", 0, 0, "MENU")
        return
    end
    if type(UIDropDownMenu_Initialize) == "function"
        and type(UIDropDownMenu_CreateInfo) == "function"
        and type(UIDropDownMenu_AddButton) == "function"
        and type(ToggleDropDownMenu) == "function" then
        UIDropDownMenu_Initialize(dropdown, function()
            for _, item in ipairs(menu) do
                local info = UIDropDownMenu_CreateInfo()
                for key, value in pairs(item) do info[key] = value end
                UIDropDownMenu_AddButton(info)
            end
        end, "MENU")
        ToggleDropDownMenu(1, nil, dropdown, "cursor", 0, 0)
        return
    end
    closeWindow()
end
