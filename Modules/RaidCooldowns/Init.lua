local Addon = Actually
local ARC = Addon.Modules.RaidCooldowns

LibStub("AceTimer-3.0"):Embed(ARC)
LibStub("AceComm-3.0"):Embed(ARC)
LibStub("AceSerializer-3.0"):Embed(ARC)

local Events = {}

local function initializeOptional(moduleName)
    local module = ARC[moduleName]
    if not module or type(module.Initialize) ~= "function" then
        ARC:Print(moduleName .. " unavailable; restart the game client after addon file updates")
        return false
    end
    local ok, reason = pcall(module.Initialize, module)
    if not ok then
        ARC:Print(moduleName .. " failed to initialize: " .. tostring(reason))
        return false
    end
    return true
end

local function copyDefaults(source, destination)
    destination = type(destination) == "table" and destination or {}
    for key, value in pairs(source) do
        if type(value) == "table" then
            destination[key] = copyDefaults(value, destination[key])
        elseif destination[key] == nil then
            destination[key] = value
        end
    end
    return destination
end

function ARC:Initialize()
    if self.initialized or self.initializing then return end
    self.initializing = true
    local ok, reason = pcall(function()
        self.Registry:Initialize()
        ActuallyDB = ActuallyDB or {}
        local legacyProfileKey = "ascension" .. "Cooldowns"
        if type(ActuallyDB.raidCooldowns) ~= "table"
            and type(ActuallyDB[legacyProfileKey]) == "table" then
            ActuallyDB.raidCooldowns = ActuallyDB[legacyProfileKey]
        end
        ActuallyDB.raidCooldowns = copyDefaults(self.Defaults.profile, ActuallyDB.raidCooldowns)
        ActuallyDB[legacyProfileKey] = nil
        self.db = { profile = ActuallyDB.raidCooldowns }

        -- Build all state and request handlers before opening communications.
        -- A later optional window failure can no longer leave an empty reporter running.
        self.State:Initialize()
        self.Roster:Initialize()
        self.Roster:Scan()
        self.Spellbook:Initialize()
        self.CooldownReader:Initialize()
        self.Renderer:Initialize()
        initializeOptional("AlertUI")
        self.Automation:Initialize()
        self.Requests:Initialize()
        self.Bundles:Initialize()
        self.Comms:Initialize()
        self.Spellbook:StartGroupedFallbackScans()
        self.DebugCommands:RegisterSlashCommands()

        self.ticker = CreateFrame("Frame")
        self.ticker:SetScript("OnUpdate", function(_, elapsed)
            if ARC.initialized then ARC.Renderer:OnUpdate(elapsed) end
        end)
    end)
    self.initializing = false
    if not ok then
        self.initialized = false
        self:Print("failed to initialize safely: " .. tostring(reason))
        return
    end
    self.initialized = true
    initializeOptional("Commander")
    initializeOptional("UserList")
    initializeOptional("SpellConfig")
    initializeOptional("BundleConfig")
    initializeOptional("CommanderConfig")
    initializeOptional("TestUI")
    initializeOptional("SpoofTest")
    if Actually.CacheTips and Actually.CacheTips.RefreshARCAlertControls then
        Actually.CacheTips:RefreshARCAlertControls()
    end
    self:Print("|cffff9f1a========== WORK IN PROGRESS ==========|r")
    self:Print("loaded; /act arc for commands")
    self:Print("|cffff9f1a======================================|r")
end

function Events.ADDON_LOADED(loadedAddon)
    if loadedAddon == Addon.name then ARC:Initialize() end
end

function Events.PLAYER_ENTERING_WORLD()
    ARC.Roster:Scan()
    ARC.Spellbook:ScheduleSafetyScans()
    ARC.Spellbook:ScheduleScan(0.1, "entering world")
    ARC.Comms:RequestState(false)
    ARC.Comms:ScheduleState(1.0, "entering world")
end

function Events.SPELLS_CHANGED()
    ARC.Spellbook:ScheduleScan(0.2, "spells changed")
end

function Events.LEARNED_SPELL_IN_TAB()
    ARC.Spellbook:ScheduleScan(0.2, "learned spell")
end

function Events.PLAYER_TALENT_UPDATE()
    ARC.Spellbook:ScheduleScan(0.2, "talent update")
end

function Events.SPELL_UPDATE_COOLDOWN()
    ARC.CooldownReader:ScheduleRefresh(0.08, "cooldown event")
end

function Events.PLAYER_DEAD()
    ARC.Requests:OnPlayerDeath()
    ARC.Bundles:OnPlayerDeath()
end

function Events.COMBAT_LOG_EVENT_UNFILTERED(...)
    ARC.CombatLog:OnEvent(...)
end

local function rosterChanged()
    ARC.Roster:Scan()
    ARC.Spellbook:ScheduleScan(0.1, "roster change")
    ARC.Comms:RequestState(false)
    ARC.Comms:ScheduleState(0.5, "roster")
end

local function unitStatusChanged(unit)
    if not unit or not UnitExists(unit) then return end
    local identity = ARC.Roster:FindGUID(UnitGUID and UnitGUID(unit))
    if not identity then return end
    local connected = not UnitIsConnected or UnitIsConnected(unit) and true or false
    local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) and true or false
    if identity.connected ~= connected or identity.dead ~= dead then rosterChanged() end
end

Events.RAID_ROSTER_UPDATE = rosterChanged
Events.PARTY_MEMBERS_CHANGED = rosterChanged
Events.UPDATE_BATTLEFIELD_STATUS = rosterChanged
Events.ZONE_CHANGED_NEW_AREA = rosterChanged
Events.UNIT_CONNECTION = unitStatusChanged
Events.UNIT_FLAGS = unitStatusChanged

ARC.eventFrame = CreateFrame("Frame")
for event in pairs(Events) do ARC.eventFrame:RegisterEvent(event) end
ARC.eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event ~= "ADDON_LOADED" and not ARC.initialized then return end
    local handler = Events[event]
    if handler then handler(...) end
end)
