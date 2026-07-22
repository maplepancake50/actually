local Addon = Actually
local ACD = Addon.Modules.AscensionCooldowns

LibStub("AceTimer-3.0"):Embed(ACD)
LibStub("AceComm-3.0"):Embed(ACD)
LibStub("AceSerializer-3.0"):Embed(ACD)

local Events = {}

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

function ACD:Initialize()
    if self.initialized then return end
    self.initialized = true
    self.Registry:Initialize()
    ActuallyDB = ActuallyDB or {}
    ActuallyDB.ascensionCooldowns = copyDefaults(self.Defaults.profile, ActuallyDB.ascensionCooldowns)
    self.db = { profile = ActuallyDB.ascensionCooldowns }
    self.State:Initialize()
    self.Roster:Initialize()
    self.Roster:Scan()
    self.Spellbook:Initialize()
    self.CooldownReader:Initialize()
    self.Renderer:Initialize()
    self.TestUI:Initialize()
    self.SpoofTest:Initialize()
    self.Comms:Initialize()
    self.DebugCommands:RegisterSlashCommands()

    self.ticker = CreateFrame("Frame")
    self.ticker:SetScript("OnUpdate", function(_, elapsed) self.Renderer:OnUpdate(elapsed) end)
    self:Print("loaded; /acd for commands")
end

function Events.ADDON_LOADED(loadedAddon)
    if loadedAddon == Addon.name then ACD:Initialize() end
end

function Events.PLAYER_ENTERING_WORLD()
    ACD.Roster:Scan()
    ACD.Spellbook:ScheduleSafetyScans()
    ACD.Spellbook:ScheduleScan(0.1, "entering world")
    ACD.Comms:RequestState(false)
    ACD.Comms:ScheduleState(1.0, "entering world")
end

function Events.SPELLS_CHANGED()
    ACD.Spellbook:ScheduleScan(0.2, "spells changed")
end

function Events.LEARNED_SPELL_IN_TAB()
    ACD.Spellbook:ScheduleScan(0.2, "learned spell")
end

function Events.PLAYER_TALENT_UPDATE()
    ACD.Spellbook:ScheduleScan(0.2, "talent update")
end

function Events.SPELL_UPDATE_COOLDOWN()
    ACD.CooldownReader:ScheduleRefresh(0.08, "cooldown event")
end

function Events.COMBAT_LOG_EVENT_UNFILTERED(...)
    ACD.CombatLog:OnEvent(...)
end

local function rosterChanged()
    ACD.Roster:Scan()
    ACD.Comms:RequestState(false)
    ACD.Comms:ScheduleState(0.5, "roster")
end

Events.RAID_ROSTER_UPDATE = rosterChanged
Events.PARTY_MEMBERS_CHANGED = rosterChanged

ACD.eventFrame = CreateFrame("Frame")
for event in pairs(Events) do ACD.eventFrame:RegisterEvent(event) end
ACD.eventFrame:SetScript("OnEvent", function(_, event, ...)
    local handler = Events[event]
    if handler then handler(...) end
end)
