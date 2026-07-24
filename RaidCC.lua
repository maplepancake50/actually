local Addon = Actually

Addon.RaidCC = Addon.RaidCC or {}
local RaidCC = Addon.RaidCC

local HEARTBEAT_INTERVAL = 0.30
local ARROW_TEXTURE = "Interface\\AddOns\\Actually\\Textures\\RaidCCArrow.tga"
local WARNING_INTERVAL = 30
local MIN_ARROW_SIZE = 18
local MAX_ARROW_SIZE = 72
local MIN_ARROW_OFFSET = 0
local MAX_ARROW_OFFSET = 24
local MIN_ARROW_THRESHOLD = 1
local MAX_ARROW_THRESHOLD = 40
local MIN_SOUND_THRESHOLD = 1
local MAX_SOUND_THRESHOLD = 40
local SOUND_COOLDOWN = 2

local DEFAULT_VISUAL_SETTINGS = {
    arrowSize = 38,
    arrowOffset = 4,
    pulse = false,
    glow = false,
}

local DEFAULT_EFFECT_SETTINGS = {
    arrowEnabled = true,
    arrowThreshold = 1,
    color = "green",
    soundEnabled = false,
    soundThreshold = 3,
    sound = "raid_warning",
}

local SOUND_OPTIONS = {
    { key = "raid_warning", label = "Raid Warning",
        path = "Sound\\Interface\\RaidWarning.wav" },
    { key = "ready_check", label = "Ready Check",
        path = "Sound\\Interface\\ReadyCheck.wav" },
    { key = "pvp_flag", label = "PvP Flag Alert",
        path = "Sound\\Spells\\PVPFlagTaken.wav" },
    { key = "alarm_1", label = "Alarm Clock 1",
        path = "Sound\\Interface\\AlarmClockWarning1.wav" },
    { key = "alarm_2", label = "Alarm Clock 2",
        path = "Sound\\Interface\\AlarmClockWarning2.wav" },
    { key = "alarm_3", label = "Alarm Clock 3",
        path = "Sound\\Interface\\AlarmClockWarning3.wav" },
    { key = "md_fairy_pop", label = "MD Fairy Pop",
        path = "Interface\\AddOns\\Actually\\Sounds\\RaidCC\\md_fairy_pop_v2.ogg" },
    { key = "md_man_urgent", label = "MD Man Urgent",
        path = "Interface\\AddOns\\Actually\\Sounds\\RaidCC\\md_man_urgent.ogg" },
    { key = "md_woman_urgent", label = "MD Woman Urgent",
        path = "Interface\\AddOns\\Actually\\Sounds\\RaidCC\\md_woman_urgent.ogg" },
}
local SOUND_BY_KEY = {}
for _, option in ipairs(SOUND_OPTIONS) do
    SOUND_BY_KEY[option.key] = option
end

-- TurboPlates 1.4.5 compatibility boundary (audited against its Core.lua and
-- Nameplates.lua).
--
-- This module never reads TurboPlates' private addon namespace. It only uses
-- fields attached to the original world nameplate: myPlate, liteContainer,
-- liteQuestIcon, _isLite, _unit, _turboTrackedUnit, and _turboTrackedGUID.
-- myPlate is initially created on the original plate and may then be reparented
-- to WorldFrame by C_NamePlateManager.ApplyFPSIncrease. liteContainer and
-- liteQuestIcon remain on the original plate. Only the three visual fields are
-- hidden; all classification/tracking fields are read-only. An unrecognised
-- plate is left entirely alone.
local FULL_FRAME_FIELD = "myPlate"
local LITE_FRAME_FIELD = "liteContainer"
local LITE_ICON_FIELD = "liteQuestIcon"

local CC_CYCLONE = "cyclone"
local CC_SHADOWFURY = "shadowfury"
local AURA_REJUVENATION = "rejuvenation"
local AURA_WILD_GROWTH = "wild-growth"

local EFFECT_COLOR_OPTIONS = {
    { key = "green", label = "Green", color = { 0.15, 1.00, 0.25 } },
    { key = "purple", label = "Purple", color = { 0.72, 0.20, 1.00 } },
    { key = "red", label = "Red", color = { 1.00, 0.18, 0.18 } },
    { key = "yellow", label = "Yellow", color = { 1.00, 0.88, 0.16 } },
    { key = "blue", label = "Blue", color = { 0.20, 0.62, 1.00 } },
    { key = "orange", label = "Orange", color = { 1.00, 0.48, 0.10 } },
    { key = "white", label = "White", color = { 1.00, 1.00, 1.00 } },
}
local EFFECT_COLOR_BY_KEY = {}
for _, option in ipairs(EFFECT_COLOR_OPTIONS) do
    EFFECT_COLOR_BY_KEY[option.key] = option
end

local BUILTIN_EFFECTS = {
    {
        key = CC_CYCLONE,
        name = "Cyclone",
        spellIDs = { 33786 },
        defaultColor = "green",
        priority = 400,
    },
    {
        key = CC_SHADOWFURY,
        name = "Shadowfury",
        spellIDs = { 30283, 30413, 30414, 47846, 47847 },
        defaultColor = "purple",
        priority = 300,
    },
    {
        key = AURA_WILD_GROWTH,
        name = "Wild Growth",
        displayName = "Wild Growth (Test)",
        spellIDs = { 52348 },
        defaultColor = "purple",
        priority = 200,
    },
    {
        key = AURA_REJUVENATION,
        name = "Rejuvenation",
        displayName = "Rejuvenation (Test)",
        spellIDs = { 26892 },
        defaultColor = "green",
        priority = 100,
    },
}

-- Match TurboPlates' own conflict audit. Ascension_NamePlates is represented
-- by useNewNameplates rather than a normally loaded addon.
local INCOMPATIBLE_NAMEPLATE_ADDONS = {
    "Kui_Nameplates",
    "TidyPlates_ThreatPlates",
    "PlateBuffs",
}

RaidCC.trackedSpellIDs = RaidCC.trackedSpellIDs or {}
RaidCC.raidGUIDs = RaidCC.raidGUIDs or {}
RaidCC.visiblePlates = RaidCC.visiblePlates or {}
RaidCC.unitToPlate = RaidCC.unitToPlate or {}
RaidCC.trackedSpellNames = RaidCC.trackedSpellNames or {}
RaidCC.effectsByKey = RaidCC.effectsByKey or {}
RaidCC.effectOrder = RaidCC.effectOrder or {}
RaidCC.runtimeActive = false
RaidCC.initialized = false
RaidCC.cvarGuard = false
RaidCC.elapsed = 0
RaidCC.lastWarningAt = -WARNING_INTERVAL
RaidCC.lastEnvironmentWarningAt = -WARNING_INTERVAL
RaidCC.lastEnvironmentWarningCode = nil
RaidCC.debugEnabled = false
RaidCC.soundThresholdReached = type(RaidCC.soundThresholdReached) == "table"
    and RaidCC.soundThresholdReached or {}
RaidCC.lastThresholdSoundAt = type(RaidCC.lastThresholdSoundAt) == "table"
    and RaidCC.lastThresholdSoundAt or {}
RaidCC.affectedFriendlyCounts = type(RaidCC.affectedFriendlyCounts) == "table"
    and RaidCC.affectedFriendlyCounts or {}
RaidCC.friendlyAuraCounts = RaidCC.friendlyAuraCounts or {}
RaidCC.settingsRefreshing = false

local function ClearTable(value)
    if wipe then
        wipe(value)
        return
    end
    for key in pairs(value) do
        value[key] = nil
    end
end

local function Now()
    return GetTime and GetTime() or 0
end

local function CountTable(value)
    local count = 0
    for _ in pairs(value or {}) do
        count = count + 1
    end
    return count
end

local function Clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function Round(value)
    return math.floor((tonumber(value) or 0) + 0.5)
end

local function UnitDescription(unit)
    if not unit then return "unit=nil" end
    local name = UnitName and UnitName(unit)
    local guid = UnitGUID and UnitGUID(unit)
    return "unit=" .. tostring(unit) .. " name=" .. tostring(name)
        .. " guid=" .. tostring(guid)
end

local function IsRaid()
    if IsInRaid then
        return IsInRaid() and true or false
    end
    return GetNumRaidMembers and (GetNumRaidMembers() or 0) > 0 or false
end

local function IsNamedAddOnLoaded(name)
    if not IsAddOnLoaded then
        return false
    end
    local ok, loaded = pcall(IsAddOnLoaded, name)
    return ok and loaded and true or false
end

local function GetBooleanCVar(name)
    if C_CVar and C_CVar.GetBool then
        local ok, value = pcall(C_CVar.GetBool, name)
        if ok then
            return value == true or value == 1 or value == "1"
        end
    end
    if GetCVar then
        local ok, value = pcall(GetCVar, name)
        if ok then
            return value == true or value == 1 or value == "1"
        end
    end
    return false
end

local function RaidCount()
    if GetNumGroupMembers then
        return GetNumGroupMembers() or 0
    end
    return GetNumRaidMembers and GetNumRaidMembers() or 0
end

local function IsFriendlyGroupUnitToken(unit)
    return unit == "player"
        or (type(unit) == "string" and string.match(unit, "^raid%d+$") ~= nil)
end

local function GetPlateForUnit(unit)
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        return C_NamePlate.GetNamePlateForUnit(unit)
    end
end

local function SafeHide(frame)
    if frame and frame.Hide then
        frame:Hide()
    end
end

local function SafeShow(frame)
    if frame and frame.Show then
        frame:Show()
    end
end

function RaidCC:Print(message)
    if Addon.Print then
        Addon:Print("Raid CC: " .. tostring(message))
    end
end

function RaidCC:Debug(message)
    if self.debugEnabled or (self.db and self.db.debug == true) then
        self:Print("DEBUG " .. tostring(message))
    end
end

function RaidCC:SetDebug(enabled)
    self.debugEnabled = enabled and true or false
    if self.db then self.db.debug = self.debugEnabled end
    self:Print("debug " .. (self.debugEnabled and "enabled" or "disabled"))
    if self.debugEnabled then self:PrintStatus() end
end

function RaidCC:NormalizeSettings()
    if not self.db then return end
    self.db.arrowSize = Round(Clamp(
        self.db.arrowSize or DEFAULT_VISUAL_SETTINGS.arrowSize,
        MIN_ARROW_SIZE, MAX_ARROW_SIZE))
    self.db.arrowOffset = Round(Clamp(
        self.db.arrowOffset or DEFAULT_VISUAL_SETTINGS.arrowOffset,
        MIN_ARROW_OFFSET, MAX_ARROW_OFFSET))
    self.db.pulse = self.db.pulse == true
    self.db.glow = self.db.glow == true
    self.db.effectSettings = type(self.db.effectSettings) == "table"
        and self.db.effectSettings or {}
    self.db.customEffects = type(self.db.customEffects) == "table"
        and self.db.customEffects or {}

    if not self.db.effectSettingsVersion then
        local legacyArrowThreshold = Round(Clamp(
            self.db.arrowThreshold or DEFAULT_EFFECT_SETTINGS.arrowThreshold,
            MIN_ARROW_THRESHOLD, MAX_ARROW_THRESHOLD))
        local legacySoundFilter = self.db.soundFilter
        for _, definition in ipairs(BUILTIN_EFFECTS) do
            local settings = self.db.effectSettings[definition.key] or {}
            settings.arrowEnabled = true
            settings.arrowThreshold = legacyArrowThreshold
            settings.color = definition.defaultColor
            settings.soundEnabled = self.db.soundEnabled == true
                and legacySoundFilter == definition.key
            settings.soundThreshold = Round(Clamp(
                self.db.soundThreshold or DEFAULT_EFFECT_SETTINGS.soundThreshold,
                MIN_SOUND_THRESHOLD, MAX_SOUND_THRESHOLD))
            settings.sound = SOUND_BY_KEY[self.db.sound]
                and self.db.sound or DEFAULT_EFFECT_SETTINGS.sound
            self.db.effectSettings[definition.key] = settings
        end
        self.db.effectSettingsVersion = 1
    end
end

function RaidCC:GetVisualSettings()
    return self.db or DEFAULT_VISUAL_SETTINGS
end

function RaidCC:NormalizeEffectSettings(effectKey, defaultColor)
    if not self.db or not effectKey then return nil end
    local settings = self.db.effectSettings[effectKey]
    if type(settings) ~= "table" then
        settings = {}
        self.db.effectSettings[effectKey] = settings
    end
    if settings.arrowEnabled == nil then settings.arrowEnabled = true end
    settings.arrowEnabled = settings.arrowEnabled == true
    settings.arrowThreshold = Round(Clamp(
        settings.arrowThreshold or DEFAULT_EFFECT_SETTINGS.arrowThreshold,
        MIN_ARROW_THRESHOLD, MAX_ARROW_THRESHOLD))
    if not EFFECT_COLOR_BY_KEY[settings.color] then
        settings.color = EFFECT_COLOR_BY_KEY[defaultColor]
            and defaultColor or DEFAULT_EFFECT_SETTINGS.color
    end
    settings.soundEnabled = settings.soundEnabled == true
    settings.soundThreshold = Round(Clamp(
        settings.soundThreshold or DEFAULT_EFFECT_SETTINGS.soundThreshold,
        MIN_SOUND_THRESHOLD, MAX_SOUND_THRESHOLD))
    if not SOUND_BY_KEY[settings.sound] then
        settings.sound = DEFAULT_EFFECT_SETTINGS.sound
    end
    return settings
end

function RaidCC:BuildEffectRegistry()
    ClearTable(self.trackedSpellIDs)
    ClearTable(self.trackedSpellNames)
    ClearTable(self.effectsByKey)
    ClearTable(self.effectOrder)

    local function Register(definition)
        self.effectsByKey[definition.key] = definition
        table.insert(self.effectOrder, definition)
        self:NormalizeEffectSettings(definition.key, definition.defaultColor)
        for _, spellID in ipairs(definition.spellIDs) do
            self.trackedSpellIDs[spellID] = definition.key
            local resolvedName = GetSpellInfo and GetSpellInfo(spellID)
            if resolvedName then
                self.trackedSpellNames[resolvedName] = definition.key
            end
        end
        self.trackedSpellNames[definition.name] = definition.key
    end

    for _, source in ipairs(BUILTIN_EFFECTS) do
        local definition = {
            key = source.key,
            name = source.name,
            displayName = source.displayName or source.name,
            spellIDs = source.spellIDs,
            defaultColor = source.defaultColor,
            priority = source.priority,
            custom = false,
        }
        local icon
        if GetSpellInfo then
            local _, _, resolvedIcon = GetSpellInfo(source.spellIDs[1])
            icon = resolvedIcon
        end
        definition.icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark"
        Register(definition)
    end

    local custom = {}
    for savedKey, saved in pairs(self.db.customEffects) do
        local spellID = tonumber(type(saved) == "table" and saved.id or savedKey)
        local name, rank, icon
        if spellID and GetSpellInfo then
            name, rank, icon = GetSpellInfo(spellID)
        end
        if spellID
            and name
            and not self.trackedSpellIDs[spellID]
            and not self.trackedSpellNames[name] then
            table.insert(custom, {
                key = "custom:" .. tostring(spellID),
                name = rank and rank ~= "" and (name .. " (" .. rank .. ")") or name,
                auraName = name,
                spellID = spellID,
                spellIDs = { spellID },
                defaultColor = "yellow",
                priority = 50,
                icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
                custom = true,
            })
        end
    end
    table.sort(custom, function(left, right)
        return string.lower(left.name) < string.lower(right.name)
    end)
    for _, definition in ipairs(custom) do
        Register(definition)
        self.trackedSpellNames[definition.auraName] = definition.key
    end

    if not self.effectsByKey[self.db.selectedEffectKey] then
        self.db.selectedEffectKey = self.effectOrder[1] and self.effectOrder[1].key
    end
end

function RaidCC:GetEffectOptions()
    return self.effectOrder
end

function RaidCC:GetSelectedEffectKey()
    return self.db and self.db.selectedEffectKey
end

function RaidCC:GetSelectedEffect()
    return self.effectsByKey[self:GetSelectedEffectKey()]
end

function RaidCC:GetEffectDisplayName(effectOrKey)
    local effect = type(effectOrKey) == "table"
        and effectOrKey or self.effectsByKey[effectOrKey or self:GetSelectedEffectKey()]
    return effect and (effect.displayName or effect.name) or "No tracked effect"
end

function RaidCC:GetEffectSettings(effectKey)
    effectKey = effectKey or self:GetSelectedEffectKey()
    local effect = self.effectsByKey[effectKey]
    return effect and self:NormalizeEffectSettings(effectKey, effect.defaultColor) or nil
end

function RaidCC:SetSelectedEffect(effectKey)
    if not self.db or not self.effectsByKey[effectKey] then return false end
    self.db.selectedEffectKey = effectKey
    self:RefreshSettingsPanel()
    return true
end

function RaidCC:AddCustomEffect(spellID, colorKey)
    spellID = Round(tonumber(spellID) or 0)
    local name = spellID > 0 and GetSpellInfo and GetSpellInfo(spellID)
    if not name then
        self:Print("Spell ID " .. tostring(spellID) .. " is not available in the client.")
        return false
    end
    local existingKey = self.trackedSpellIDs[spellID] or self.trackedSpellNames[name]
    if existingKey then
        local existing = self.effectsByKey[existingKey]
        self:Print((existing and existing.name or name) .. " is already being tracked.")
        self:SetSelectedEffect(existingKey)
        return false
    end

    local savedKey = tostring(spellID)
    self.db.customEffects[savedKey] = {
        id = spellID,
        addedAt = time and time() or 0,
    }
    local effectKey = "custom:" .. savedKey
    self.db.effectSettings[effectKey] = {
        arrowEnabled = true,
        arrowThreshold = 1,
        color = EFFECT_COLOR_BY_KEY[colorKey] and colorKey or "yellow",
        soundEnabled = false,
        soundThreshold = 1,
        sound = DEFAULT_EFFECT_SETTINGS.sound,
    }
    self:BuildEffectRegistry()
    self.db.selectedEffectKey = effectKey
    self:UpdateSoundThreshold(false)
    self:RefreshTrackedArrows()
    self:RefreshSettingsPanel()
    self:Print(name .. " added to Mass Dispel Helper.")
    return true
end

function RaidCC:RemoveSelectedCustomEffect()
    local effect = self:GetSelectedEffect()
    if not effect or not effect.custom then return false end
    local name = effect.name
    self.db.customEffects[tostring(effect.spellID)] = nil
    self.db.effectSettings[effect.key] = nil
    self.soundThresholdReached[effect.key] = nil
    self.lastThresholdSoundAt[effect.key] = nil
    self.affectedFriendlyCounts[effect.key] = nil
    self:BuildEffectRegistry()
    self:UpdateSoundThreshold(false)
    self:RefreshTrackedArrows()
    self:RefreshSettingsPanel()
    self:Print(name .. " removed from Mass Dispel Helper.")
    return true
end

function RaidCC:GetSoundOptions()
    return SOUND_OPTIONS
end

function RaidCC:GetEffectColorOptions()
    return EFFECT_COLOR_OPTIONS
end

function RaidCC:GetSoundLabel(effectKey)
    local settings = self:GetEffectSettings(effectKey) or DEFAULT_EFFECT_SETTINGS
    local option = SOUND_BY_KEY[settings.sound]
        or SOUND_BY_KEY[DEFAULT_EFFECT_SETTINGS.sound]
    return option and option.label or "Raid Warning"
end

function RaidCC:GetSoundFilterLabel()
    return self:GetEffectDisplayName()
end

function RaidCC:GetEffectColor(effectKey)
    local settings = self:GetEffectSettings(effectKey) or DEFAULT_EFFECT_SETTINGS
    local option = EFFECT_COLOR_BY_KEY[settings.color]
        or EFFECT_COLOR_BY_KEY[DEFAULT_EFFECT_SETTINGS.color]
    return option.color
end

function RaidCC:GetEffectColorLabel(effectKey)
    local settings = self:GetEffectSettings(effectKey) or DEFAULT_EFFECT_SETTINGS
    local option = EFFECT_COLOR_BY_KEY[settings.color]
        or EFFECT_COLOR_BY_KEY[DEFAULT_EFFECT_SETTINGS.color]
    return option.label
end

function RaidCC:RefreshSettingsConsumers()
    self:UpdateSoundThreshold(false)
    self:RefreshTrackedArrows()
    self:RefreshArrowVisuals()
    self:RefreshSettingsPanel()
    self:RefreshOptionsStatus()
end

function RaidCC:SetArrowSize(value)
    if not self.db then return end
    self.db.arrowSize = Round(Clamp(value, MIN_ARROW_SIZE, MAX_ARROW_SIZE))
    self:RefreshSettingsConsumers()
end

function RaidCC:SetArrowOffset(value)
    if not self.db then return end
    self.db.arrowOffset = Round(Clamp(value, MIN_ARROW_OFFSET, MAX_ARROW_OFFSET))
    self:RefreshSettingsConsumers()
end

function RaidCC:SetArrowThreshold(value, effectKey)
    local settings = self:GetEffectSettings(effectKey)
    if not settings then return end
    settings.arrowThreshold = Round(Clamp(
        value, MIN_ARROW_THRESHOLD, MAX_ARROW_THRESHOLD))
    self:RefreshSettingsConsumers()
end

function RaidCC:SetArrowEnabled(enabled, effectKey)
    local settings = self:GetEffectSettings(effectKey)
    if not settings then return end
    settings.arrowEnabled = enabled == true
    self:RefreshSettingsConsumers()
end

function RaidCC:SetEffectColor(colorKey, effectKey)
    local settings = self:GetEffectSettings(effectKey)
    if not settings or not EFFECT_COLOR_BY_KEY[colorKey] then return false end
    settings.color = colorKey
    self:RefreshSettingsConsumers()
    return true
end

function RaidCC:SetPulseEnabled(enabled)
    if not self.db then return end
    self.db.pulse = enabled == true
    self:RefreshSettingsConsumers()
end

function RaidCC:SetGlowEnabled(enabled)
    if not self.db then return end
    self.db.glow = enabled == true
    self:RefreshSettingsConsumers()
end

function RaidCC:SetSoundEnabled(enabled, effectKey)
    local settings = self:GetEffectSettings(effectKey)
    if not settings then return end
    settings.soundEnabled = enabled == true
    self:RefreshSettingsConsumers()
end

function RaidCC:SetSoundThreshold(value, effectKey)
    local settings = self:GetEffectSettings(effectKey)
    if not settings then return end
    settings.soundThreshold = Round(Clamp(
        value, MIN_SOUND_THRESHOLD, MAX_SOUND_THRESHOLD))
    self:RefreshSettingsConsumers()
end

function RaidCC:SetSound(key, preview, effectKey)
    local settings = self:GetEffectSettings(effectKey)
    if not settings or not SOUND_BY_KEY[key] then return false end
    settings.sound = key
    self:RefreshSettingsConsumers()
    if preview then
        self:PlayConfiguredSound(true, effectKey)
    end
    return true
end

function RaidCC:ResetVisualSettings()
    if not self.db then return end
    for key, value in pairs(DEFAULT_VISUAL_SETTINGS) do
        self.db[key] = value
    end
    for _, effect in ipairs(self.effectOrder) do
        self.db.effectSettings[effect.key] = {
            arrowEnabled = true,
            arrowThreshold = DEFAULT_EFFECT_SETTINGS.arrowThreshold,
            color = effect.defaultColor,
            soundEnabled = false,
            soundThreshold = DEFAULT_EFFECT_SETTINGS.soundThreshold,
            sound = DEFAULT_EFFECT_SETTINGS.sound,
        }
    end
    ClearTable(self.soundThresholdReached)
    ClearTable(self.lastThresholdSoundAt)
    self:RefreshSettingsConsumers()
end

function RaidCC:PlayConfiguredSound(force, effectKey)
    local settings = self:GetEffectSettings(effectKey)
    if not settings then return false end
    if not force and settings.soundEnabled ~= true then
        return false
    end
    local option = SOUND_BY_KEY[settings.sound]
        or SOUND_BY_KEY[DEFAULT_EFFECT_SETTINGS.sound]
    if not option or not PlaySoundFile then
        return false
    end
    PlaySoundFile(option.path)
    return true
end

function RaidCC:GetUnitTrackedAuraKinds(unit)
    local kinds = {}
    if not unit or not UnitExists(unit) then return kinds end

    local function RecordAura(name, spellID)
        local kind = (spellID and self.trackedSpellIDs[spellID])
            or self.trackedSpellNames[name]
        if kind then kinds[kind] = true end
    end

    if UnitDebuff then
        for index = 1, 40 do
            local name, _, _, _, _, _, _, _, _, _, spellID = UnitDebuff(unit, index)
            if not name then break end
            RecordAura(name, spellID)
        end
    end

    if UnitBuff then
        for index = 1, 40 do
            local name, _, _, _, _, _, _, _, _, _, spellID = UnitBuff(unit, index)
            if not name then break end
            RecordAura(name, spellID)
        end
    end
    return kinds
end

function RaidCC:BuildFriendlyAuraSummary()
    local summary = { byKind = {} }
    local seenGUIDs = {}
    for index = 1, RaidCount() do
        local unit = "raid" .. index
        local guid = UnitExists(unit) and UnitGUID(unit)
        if guid
            and not seenGUIDs[guid]
            and (not UnitIsPlayer or UnitIsPlayer(unit)) then
            seenGUIDs[guid] = true
            local kinds = self:GetUnitTrackedAuraKinds(unit)
            for kind in pairs(kinds) do
                summary.byKind[kind] = (summary.byKind[kind] or 0) + 1
            end
        end
    end
    return summary
end

function RaidCC:CountFriendlySoundMatches(effectKey)
    local summary = self:BuildFriendlyAuraSummary()
    self.friendlyAuraCounts = summary.byKind
    effectKey = effectKey or self:GetSelectedEffectKey()
    return summary.byKind[effectKey] or 0
end

function RaidCC:ShouldDisplayAuraKind(kind)
    if not kind then return false end
    local settings = self:GetEffectSettings(kind)
    return settings
        and settings.arrowEnabled == true
        and (self.friendlyAuraCounts[kind] or 0) >= settings.arrowThreshold
end

function RaidCC:UpdateSoundThreshold(allowSound)
    local summary = self:BuildFriendlyAuraSummary()
    self.friendlyAuraCounts = summary.byKind
    for _, effect in ipairs(self.effectOrder) do
        local key = effect.key
        local settings = self:GetEffectSettings(key)
        local count = summary.byKind[key] or 0
        self.affectedFriendlyCounts[key] = count
        if self.runtimeActive and settings.soundEnabled == true then
            local reached = count >= settings.soundThreshold
            if reached and not self.soundThresholdReached[key] and allowSound then
                local current = Now()
                local lastPlayed = self.lastThresholdSoundAt[key] or -SOUND_COOLDOWN
                if current - lastPlayed >= SOUND_COOLDOWN
                    and self:PlayConfiguredSound(false, key) then
                    self.lastThresholdSoundAt[key] = current
                    self:Debug("threshold sound played effect=" .. tostring(key)
                        .. " count=" .. tostring(count)
                        .. " threshold=" .. tostring(settings.soundThreshold))
                end
            end
            self.soundThresholdReached[key] = reached
        else
            self.soundThresholdReached[key] = false
        end
    end
    self:RefreshSettingsStatus()
end

function RaidCC:GetCompatibilityStatus()
    if not IsNamedAddOnLoaded("TurboPlates") then
        return false, "turboplates-not-loaded",
            "TurboPlates is not enabled for this character. Enable it and reload the UI."
    end

    if GetBooleanCVar("useNewNameplates") then
        return false, "ascension-nameplates",
            "Ascension New Nameplates is enabled. Disable it and reload the UI so TurboPlates can own the plates."
    end

    local elvEngine = ElvUI and ElvUI[1]
    if elvEngine
        and elvEngine.private
        and elvEngine.private.nameplates
        and elvEngine.private.nameplates.enable then
        return false, "elvui-nameplates",
            "ElvUI NamePlates is enabled. Disable only ElvUI's NamePlates module and reload the UI."
    end

    for _, addonName in ipairs(INCOMPATIBLE_NAMEPLATE_ADDONS) do
        if IsNamedAddOnLoaded(addonName) then
            return false, "conflict-" .. string.lower(addonName),
                addonName .. " is loaded and conflicts with TurboPlates. Disable it and reload the UI."
        end
    end

    if not C_NamePlate
        or not C_NamePlate.GetNamePlateForUnit
        or not C_NamePlateManager
        or not C_NamePlateManager.EnumerateActiveNamePlates then
        return false, "nameplate-api-missing",
            "The required Ascension nameplate-manager APIs are unavailable."
    end

    return true, "ready", "TurboPlates is loaded and ready."
end

function RaidCC:GetRuntimeStatus()
    if not self:IsEnabled() then
        return "disabled", "Disabled. Your normal nameplate settings are unchanged."
    end

    local compatible, _, message = self:GetCompatibilityStatus()
    if not compatible then
        return "blocked", "Unavailable: " .. message
    end

    if not IsRaid() then
        return "waiting", "Ready. It activates automatically in raids and battlegrounds."
    end

    if self.runtimeActive then
        return "active", "Active: raid members are name-only and tracked effects display coloured arrows."
    end

    return "waiting", "Preparing the raid nameplate override."
end

function RaidCC:RefreshOptionsStatus()
    if Addon.CacheTips and Addon.CacheTips.RefreshRaidCCToggle then
        Addon.CacheTips:RefreshRaidCCToggle()
    end
end

function RaidCC:PrintStatus()
    local active, compatible, retrying = 0, 0, 0
    for nameplate in pairs(self.visiblePlates or {}) do
        local state = nameplate._actuallyRaidCCState
        if self:HasCompatibleFrames(nameplate) then compatible = compatible + 1 end
        if state and state.active then active = active + 1 end
        if state and state.retryAt then retrying = retrying + 1 end
    end
    local environmentCompatible, environmentCode = self:GetCompatibilityStatus()
    self:Print("status enabled=" .. tostring(self.db and self.db.enabled == true)
        .. " inRaid=" .. tostring(IsRaid())
        .. " runtime=" .. tostring(self.runtimeActive)
        .. " environment=" .. tostring(environmentCode)
        .. " environmentCompatible=" .. tostring(environmentCompatible)
        .. " raidGUIDs=" .. tostring(CountTable(self.raidGUIDs))
        .. " visible=" .. tostring(CountTable(self.visiblePlates))
        .. " compatible=" .. tostring(compatible)
        .. " overridden=" .. tostring(active)
        .. " retrying=" .. tostring(retrying)
        .. " friendsCVar=" .. tostring(self:GetCVarValue("nameplateShowFriends"))
        .. " enemiesCVar=" .. tostring(self:GetCVarValue("nameplateShowEnemies")))
end

function RaidCC:HandleCommand(input)
    local command = string.lower(string.gsub(tostring(input or ""), "^%s*(.-)%s*$", "%1"))
    if command == "debug" then
        self:SetDebug(not (self.debugEnabled or (self.db and self.db.debug == true)))
    elseif command == "status" then
        self:PrintStatus()
    elseif command == "scan" then
        self:RebuildRaidGUIDCache()
        self:ReevaluateVisiblePlates()
        self:PrintStatus()
    elseif command == "settings" or command == "options" then
        self:ToggleSettings()
    else
        self:Print(
            "commands: /raidcc settings, /raidcc debug, /raidcc status, /raidcc scan")
    end
end

function RaidCC:WarnCompatibility()
    local current = Now()
    if current - self.lastWarningAt < WARNING_INTERVAL then
        return
    end
    self.lastWarningAt = current
    self:Print("compatible TurboPlates plate fields were not found; raid override was skipped")
end

function RaidCC:WarnEnvironment(code, message)
    local current = Now()
    if self.lastEnvironmentWarningCode == code
        and current - self.lastEnvironmentWarningAt < WARNING_INTERVAL then
        return
    end
    self.lastEnvironmentWarningCode = code
    self.lastEnvironmentWarningAt = current
    self:Print("inactive: " .. tostring(message))
end

function RaidCC:IsModeRequested()
    return self.db and self.db.enabled == true and IsRaid()
end

function RaidCC:ShouldModeBeActive()
    if not self:IsModeRequested() then
        return false
    end
    local compatible = self:GetCompatibilityStatus()
    return compatible and true or false
end

function RaidCC:IsEnabled()
    return self.db and self.db.enabled == true or false
end

function RaidCC:SetEnabled(enabled)
    if not self.db then
        return
    end
    self.db.enabled = enabled and true or false
    self:RefreshMode()
    if self.runtimeActive then
        self:ReevaluateVisiblePlates()
    elseif enabled then
        local compatible, code, message = self:GetCompatibilityStatus()
        if not compatible then
            self:WarnEnvironment(code, message)
        elseif not IsRaid() then
            self:Print("enabled; waiting for a raid or battleground")
        end
    end
    self:RefreshOptionsStatus()
end

function RaidCC:RebuildRaidGUIDCache()
    ClearTable(self.raidGUIDs)
    if not IsRaid() then
        return
    end
    for index = 1, RaidCount() do
        local guid = UnitGUID("raid" .. index)
        if guid then
            self.raidGUIDs[guid] = true
        end
    end
    self:Debug("raid GUID cache rebuilt count=" .. tostring(CountTable(self.raidGUIDs)))
end

function RaidCC:ClassifyUnit(unit)
    if not self.runtimeActive then
        return false, "runtime-inactive"
    end
    if not unit then
        return false, "missing-unit"
    end
    if not UnitExists(unit) then
        return false, "unit-does-not-exist"
    end
    if not UnitIsPlayer(unit) then
        return false, "not-player"
    end
    if UnitIsUnit(unit, "player") then
        return false, "self"
    end
    local guid = UnitGUID(unit)
    if not guid then
        return false, "missing-guid"
    end
    if self.raidGUIDs[guid] ~= true then
        return false, "not-raid-member"
    end
    return true, "raid-member"
end

function RaidCC:ShouldOverrideUnit(unit)
    local allowed = self:ClassifyUnit(unit)
    return allowed
end

function RaidCC:HasCompatibleFrames(nameplate)
    return nameplate and (
        nameplate[FULL_FRAME_FIELD]
        or nameplate[LITE_FRAME_FIELD]
    ) and true or false
end

function RaidCC:CreateArrowVisual(parent, anchor)
    local arrowVisual = CreateFrame("Frame", nil, parent)
    arrowVisual:SetSize(DEFAULT_VISUAL_SETTINGS.arrowSize, DEFAULT_VISUAL_SETTINGS.arrowSize)
    arrowVisual:SetPoint("BOTTOM", anchor, "TOP", 0, DEFAULT_VISUAL_SETTINGS.arrowOffset)
    arrowVisual:EnableMouse(false)
    arrowVisual.anchor = anchor

    local arrowShadow = arrowVisual:CreateTexture(nil, "ARTWORK")
    arrowShadow:SetTexture(ARROW_TEXTURE)
    arrowShadow:SetSize(DEFAULT_VISUAL_SETTINGS.arrowSize, DEFAULT_VISUAL_SETTINGS.arrowSize)
    arrowShadow:SetPoint("CENTER", arrowVisual, "CENTER", 2, -2)
    arrowShadow:SetVertexColor(0, 0, 0, 1)
    arrowShadow:SetAlpha(0.80)
    arrowVisual.arrowShadow = arrowShadow

    local arrowGlow = arrowVisual:CreateTexture(nil, "ARTWORK")
    arrowGlow:SetTexture(ARROW_TEXTURE)
    arrowGlow:SetSize(
        DEFAULT_VISUAL_SETTINGS.arrowSize + 12,
        DEFAULT_VISUAL_SETTINGS.arrowSize + 12)
    arrowGlow:SetPoint("CENTER", arrowVisual, "CENTER", 0, 0)
    arrowGlow:SetBlendMode("ADD")
    arrowGlow:SetAlpha(0.32)
    arrowGlow:Hide()
    arrowVisual.arrowGlow = arrowGlow

    local arrow = arrowVisual:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture(ARROW_TEXTURE)
    arrow:SetAllPoints(arrowVisual)
    arrow:SetVertexColor(1, 1, 1, 1)
    arrowVisual.arrow = arrow

    arrowVisual:SetScript("OnUpdate", function(self)
        if self.pulseEnabled and GetTime then
            self:SetAlpha(0.68 + 0.32 * ((math.sin(GetTime() * 6) + 1) * 0.5))
        elseif self:GetAlpha() ~= 1 then
            self:SetAlpha(1)
        end
    end)
    arrowVisual:Hide()
    return arrowVisual
end

function RaidCC:ApplyArrowVisualSettings(overlay)
    if not overlay or not overlay.arrowVisual then return end
    local settings = self:GetVisualSettings()
    local visual = overlay.arrowVisual
    local size = Round(Clamp(settings.arrowSize, MIN_ARROW_SIZE, MAX_ARROW_SIZE))
    local offset = Round(Clamp(settings.arrowOffset, MIN_ARROW_OFFSET, MAX_ARROW_OFFSET))

    visual:SetSize(size, size)
    visual:ClearAllPoints()
    visual:SetPoint("BOTTOM", visual.anchor, "TOP", 0, offset)
    visual.arrowShadow:SetSize(size, size)
    visual.arrowGlow:SetSize(size + 12, size + 12)
    visual.pulseEnabled = settings.pulse == true

    if visual:IsShown() and settings.glow == true then
        visual.arrowGlow:Show()
    else
        visual.arrowGlow:Hide()
    end
    if not visual.pulseEnabled then
        visual:SetAlpha(1)
    end
end

function RaidCC:ShowArrowVisual(overlay, kind)
    if not overlay or not overlay.arrowVisual then return end
    local visual = overlay.arrowVisual
    local color = self:GetEffectColor(kind) or { 1, 1, 1 }
    visual.arrow:SetVertexColor(color[1], color[2], color[3], 1)
    visual.arrowGlow:SetVertexColor(color[1], color[2], color[3], 1)
    visual:Show()
    self:ApplyArrowVisualSettings(overlay)
end

function RaidCC:HideArrowVisual(overlay)
    if not overlay or not overlay.arrowVisual then return end
    overlay.arrowVisual:Hide()
    overlay.arrowVisual:SetAlpha(1)
    overlay.arrowVisual.arrowGlow:Hide()
end

function RaidCC:RefreshArrowVisuals()
    for nameplate in pairs(self.visiblePlates or {}) do
        local state = nameplate._actuallyRaidCCState
        local overlay = state and state.overlay
        if overlay then
            self:ApplyArrowVisualSettings(overlay)
            if state.arrowShown and state.arrowKind then
                self:ShowArrowVisual(overlay, state.arrowKind)
            else
                self:HideArrowVisual(overlay)
            end
        end
    end
    if self.settingsPreviewOverlay then
        self:ApplyArrowVisualSettings(self.settingsPreviewOverlay)
        self:ShowArrowVisual(
            self.settingsPreviewOverlay,
            self:GetSelectedEffectKey() or AURA_REJUVENATION)
    end
end

function RaidCC:RefreshTrackedArrows()
    for nameplate in pairs(self.visiblePlates or {}) do
        local state = nameplate._actuallyRaidCCState
        if state and state.active then
            self:UpdateArrow(state)
        end
    end
end

function RaidCC:CreateSettingsPanel()
    if self.settingsFrame then
        return self.settingsFrame
    end

    local frame = CreateFrame("Frame", "ActuallyRaidCCSettingsFrame", UIParent)
    frame:SetWidth(600)
    frame:SetHeight(690)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(owner)
        owner:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(owner)
        owner:StopMovingOrSizing()
    end)
    if Addon.Util and Addon.Util.SetBackdrop then
        Addon.Util.SetBackdrop(
            frame,
            { 0.025, 0.030, 0.045, 0.98 },
            { 0.34, 0.78, 0.96, 0.96 })
    end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -16)
    title:SetText("Mass Dispel Helper")
    title:SetTextColor(0.35, 0.88, 1.00)

    local description = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    description:SetWidth(540)
    description:SetJustifyH("LEFT")
    description:SetText(
        "Select an effect below. Its arrow and sound rules are saved separately; add more effects by spell ID.")
    description:SetTextColor(0.68, 0.74, 0.82)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)

    local effectSelector = CreateFrame("Frame", nil, frame)
    effectSelector:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -65)
    effectSelector:SetWidth(564)
    effectSelector:SetHeight(58)
    if Addon.Util and Addon.Util.SetBackdrop then
        Addon.Util.SetBackdrop(
            effectSelector,
            { 0.040, 0.050, 0.070, 0.97 },
            { 0.30, 0.62, 0.88, 0.86 })
    end

    local effectLabel = effectSelector:CreateFontString(
        nil, "OVERLAY", "GameFontHighlightSmall")
    effectLabel:SetPoint("TOPLEFT", effectSelector, "TOPLEFT", 12, -8)
    effectLabel:SetText("Editing tracked effect")
    effectLabel:SetTextColor(0.78, 0.88, 1.00)

    local effectDropdown = CreateFrame(
        "Frame", "ActuallyRaidCCEffectDropdown",
        effectSelector, "UIDropDownMenuTemplate")
    effectDropdown:SetPoint("TOPLEFT", effectSelector, "TOPLEFT", -3, -19)
    UIDropDownMenu_SetWidth(effectDropdown, 235)
    UIDropDownMenu_Initialize(effectDropdown, function()
        local selected = RaidCC:GetSelectedEffectKey()
        for _, effect in ipairs(RaidCC:GetEffectOptions()) do
            local key = effect.key
            local info = UIDropDownMenu_CreateInfo()
            info.text = RaidCC:GetEffectDisplayName(effect)
                .. (effect.custom and "  |cff80d8ff(Custom)|r" or "")
            info.value = key
            info.checked = selected == key
            info.func = function()
                RaidCC:SetSelectedEffect(key)
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local colorLabel = effectSelector:CreateFontString(
        nil, "OVERLAY", "GameFontHighlightSmall")
    colorLabel:SetPoint("TOPLEFT", effectSelector, "TOPLEFT", 275, -8)
    colorLabel:SetText("Arrow colour")
    colorLabel:SetTextColor(0.78, 0.88, 1.00)

    local colorDropdown = CreateFrame(
        "Frame", "ActuallyRaidCCEffectColorDropdown",
        effectSelector, "UIDropDownMenuTemplate")
    colorDropdown:SetPoint("TOPLEFT", effectSelector, "TOPLEFT", 260, -19)
    UIDropDownMenu_SetWidth(colorDropdown, 105)
    UIDropDownMenu_Initialize(colorDropdown, function()
        local settings = RaidCC:GetEffectSettings()
        local selected = settings and settings.color
        for _, option in ipairs(RaidCC:GetEffectColorOptions()) do
            local key, label = option.key, option.label
            local info = UIDropDownMenu_CreateInfo()
            info.text = label
            info.value = key
            info.checked = selected == key
            info.func = function()
                RaidCC:SetEffectColor(key)
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local addEffect = CreateFrame("Button", nil, effectSelector, "UIPanelButtonTemplate")
    addEffect:SetWidth(82)
    addEffect:SetHeight(24)
    addEffect:SetPoint("TOPLEFT", effectSelector, "TOPLEFT", 397, -21)
    addEffect:SetText("Add Spell")
    addEffect:SetScript("OnClick", function()
        RaidCC:ShowCustomEffectEditor()
    end)

    local removeEffect = CreateFrame(
        "Button", nil, effectSelector, "UIPanelButtonTemplate")
    removeEffect:SetWidth(72)
    removeEffect:SetHeight(24)
    removeEffect:SetPoint("TOPRIGHT", effectSelector, "TOPRIGHT", -10, -21)
    removeEffect:SetText("Remove")
    removeEffect:SetScript("OnClick", function()
        RaidCC:RemoveSelectedCustomEffect()
    end)

    local preview = CreateFrame("Frame", nil, frame)
    preview:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -135)
    preview:SetWidth(220)
    preview:SetHeight(150)
    if Addon.Util and Addon.Util.SetBackdrop then
        Addon.Util.SetBackdrop(
            preview,
            { 0.035, 0.055, 0.075, 0.96 },
            { 0.20, 0.55, 0.72, 0.78 })
    end

    local previewTitle = preview:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    previewTitle:SetPoint("TOPLEFT", preview, "TOPLEFT", 12, -10)
    previewTitle:SetText("Appearance Preview")
    previewTitle:SetTextColor(0.55, 0.90, 1.00)

    local previewName = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    previewName:SetPoint("BOTTOM", preview, "BOTTOM", 0, 25)
    previewName:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    previewName:SetText("Friendly Healer")
    previewName:SetTextColor(0.30, 0.95, 0.45)

    local previewOverlay = {
        nameText = previewName,
        arrowVisual = self:CreateArrowVisual(preview, previewName),
    }
    previewOverlay.arrow = previewOverlay.arrowVisual.arrow
    previewOverlay.arrowShadow = previewOverlay.arrowVisual.arrowShadow
    previewOverlay.arrowGlow = previewOverlay.arrowVisual.arrowGlow
    self.settingsPreviewOverlay = previewOverlay

    local visual = CreateFrame("Frame", nil, frame)
    visual:SetPoint("TOPLEFT", frame, "TOPLEFT", 250, -135)
    visual:SetWidth(332)
    visual:SetHeight(150)
    if Addon.Util and Addon.Util.SetBackdrop then
        Addon.Util.SetBackdrop(
            visual,
            { 0.045, 0.040, 0.070, 0.96 },
            { 0.52, 0.38, 0.82, 0.82 })
    end

    local visualTitle = visual:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    visualTitle:SetPoint("TOPLEFT", visual, "TOPLEFT", 12, -10)
    visualTitle:SetText("Arrow Appearance")
    visualTitle:SetTextColor(0.82, 0.70, 1.00)

    local sizeLabel = visual:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sizeLabel:SetPoint("TOPLEFT", visual, "TOPLEFT", 18, -39)
    sizeLabel:SetText("Size: 38 px")
    sizeLabel:SetTextColor(0.88, 0.91, 0.96)

    local sizeSlider = CreateFrame(
        "Slider", "ActuallyRaidCCArrowSizeSlider", visual, "OptionsSliderTemplate")
    sizeSlider:SetWidth(205)
    sizeSlider:SetHeight(16)
    sizeSlider:SetPoint("TOPLEFT", visual, "TOPLEFT", 18, -62)
    sizeSlider:SetMinMaxValues(MIN_ARROW_SIZE, MAX_ARROW_SIZE)
    sizeSlider:SetValueStep(1)
    _G[sizeSlider:GetName() .. "Low"]:SetText(tostring(MIN_ARROW_SIZE))
    _G[sizeSlider:GetName() .. "High"]:SetText(tostring(MAX_ARROW_SIZE))
    _G[sizeSlider:GetName() .. "Text"]:SetText("")
    sizeSlider:SetScript("OnValueChanged", function(owner)
        if RaidCC.settingsRefreshing then return end
        RaidCC:SetArrowSize(owner:GetValue())
    end)

    local offsetLabel = visual:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    offsetLabel:SetPoint("TOPLEFT", visual, "TOPLEFT", 18, -94)
    offsetLabel:SetText("Gap: 4 px")
    offsetLabel:SetTextColor(0.88, 0.91, 0.96)

    local offsetSlider = CreateFrame(
        "Slider", "ActuallyRaidCCArrowOffsetSlider", visual, "OptionsSliderTemplate")
    offsetSlider:SetWidth(205)
    offsetSlider:SetHeight(16)
    offsetSlider:SetPoint("TOPLEFT", visual, "TOPLEFT", 18, -117)
    offsetSlider:SetMinMaxValues(MIN_ARROW_OFFSET, MAX_ARROW_OFFSET)
    offsetSlider:SetValueStep(1)
    _G[offsetSlider:GetName() .. "Low"]:SetText(tostring(MIN_ARROW_OFFSET))
    _G[offsetSlider:GetName() .. "High"]:SetText(tostring(MAX_ARROW_OFFSET))
    _G[offsetSlider:GetName() .. "Text"]:SetText("")
    offsetSlider:SetScript("OnValueChanged", function(owner)
        if RaidCC.settingsRefreshing then return end
        RaidCC:SetArrowOffset(owner:GetValue())
    end)

    local function CreateVisualCheckbox(name, label, y, setter)
        local checkbox = CreateFrame("CheckButton", name, visual, "UICheckButtonTemplate")
        checkbox:SetWidth(26)
        checkbox:SetHeight(26)
        checkbox:SetPoint("TOPRIGHT", visual, "TOPRIGHT", -78, y)
        local text = checkbox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", checkbox, "RIGHT", 2, 1)
        text:SetText(label)
        checkbox:SetScript("OnClick", function(owner)
            setter(RaidCC, owner:GetChecked() == 1 or owner:GetChecked() == true)
        end)
        return checkbox
    end

    local pulseCheckbox = CreateVisualCheckbox(
        "ActuallyRaidCCPulseCheckButton", "Pulse", -48, RaidCC.SetPulseEnabled)
    local glowCheckbox = CreateVisualCheckbox(
        "ActuallyRaidCCGlowCheckButton", "Glow", -89, RaidCC.SetGlowEnabled)

    local arrowRule = CreateFrame("Frame", nil, frame)
    arrowRule:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -297)
    arrowRule:SetWidth(564)
    arrowRule:SetHeight(102)
    if Addon.Util and Addon.Util.SetBackdrop then
        Addon.Util.SetBackdrop(
            arrowRule,
            { 0.030, 0.060, 0.050, 0.97 },
            { 0.28, 0.88, 0.56, 0.86 })
    end

    local arrowRuleTitle = arrowRule:CreateFontString(
        nil, "OVERLAY", "GameFontNormal")
    arrowRuleTitle:SetPoint("TOPLEFT", arrowRule, "TOPLEFT", 12, -10)
    arrowRuleTitle:SetText("When Arrows Appear")
    arrowRuleTitle:SetTextColor(0.40, 1.00, 0.68)

    local arrowRuleDescription = arrowRule:CreateFontString(
        nil, "OVERLAY", "GameFontHighlightSmall")
    arrowRuleDescription:SetPoint("TOPLEFT", arrowRuleTitle, "BOTTOMLEFT", 0, -5)
    arrowRuleDescription:SetWidth(300)
    arrowRuleDescription:SetJustifyH("LEFT")
    arrowRuleDescription:SetText(
        "This rule belongs only to the selected effect. Other tracked effects keep their own arrow rules.")
    arrowRuleDescription:SetTextColor(0.70, 0.78, 0.76)

    local arrowEnabled = CreateFrame(
        "CheckButton", "ActuallyRaidCCArrowEnabledCheckButton",
        arrowRule, "UICheckButtonTemplate")
    arrowEnabled:SetWidth(26)
    arrowEnabled:SetHeight(26)
    arrowEnabled:SetPoint("TOPLEFT", arrowRule, "TOPLEFT", 328, -8)
    local arrowEnabledLabel = arrowEnabled:CreateFontString(
        nil, "OVERLAY", "GameFontHighlightSmall")
    arrowEnabledLabel:SetPoint("LEFT", arrowEnabled, "RIGHT", 3, 1)
    arrowEnabledLabel:SetText("Show arrows for this effect")
    arrowEnabled:SetScript("OnClick", function(owner)
        RaidCC:SetArrowEnabled(
            owner:GetChecked() == 1 or owner:GetChecked() == true)
    end)

    local arrowThresholdLabel = arrowRule:CreateFontString(
        nil, "OVERLAY", "GameFontHighlightSmall")
    arrowThresholdLabel:SetPoint("TOPLEFT", arrowRule, "TOPLEFT", 340, -48)
    arrowThresholdLabel:SetText("Arrow trigger count: 1 friendly")
    arrowThresholdLabel:SetTextColor(0.88, 0.94, 0.92)

    local arrowThresholdSlider = CreateFrame(
        "Slider", "ActuallyRaidCCArrowThresholdSlider",
        arrowRule, "OptionsSliderTemplate")
    arrowThresholdSlider:SetWidth(200)
    arrowThresholdSlider:SetHeight(16)
    arrowThresholdSlider:SetPoint("TOPLEFT", arrowRule, "TOPLEFT", 340, -71)
    arrowThresholdSlider:SetMinMaxValues(MIN_ARROW_THRESHOLD, MAX_ARROW_THRESHOLD)
    arrowThresholdSlider:SetValueStep(1)
    _G[arrowThresholdSlider:GetName() .. "Low"]:SetText(
        tostring(MIN_ARROW_THRESHOLD))
    _G[arrowThresholdSlider:GetName() .. "High"]:SetText(
        tostring(MAX_ARROW_THRESHOLD))
    _G[arrowThresholdSlider:GetName() .. "Text"]:SetText("")
    arrowThresholdSlider:SetScript("OnValueChanged", function(owner)
        if RaidCC.settingsRefreshing then return end
        RaidCC:SetArrowThreshold(owner:GetValue())
    end)

    local sound = CreateFrame("Frame", nil, frame)
    sound:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -411)
    sound:SetWidth(564)
    sound:SetHeight(216)
    if Addon.Util and Addon.Util.SetBackdrop then
        Addon.Util.SetBackdrop(
            sound,
            { 0.055, 0.040, 0.025, 0.97 },
            { 0.92, 0.60, 0.18, 0.86 })
    end

    local soundTitle = sound:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    soundTitle:SetPoint("TOPLEFT", sound, "TOPLEFT", 12, -10)
    soundTitle:SetText("When Sound Plays")
    soundTitle:SetTextColor(1.00, 0.76, 0.30)

    local soundDescription = sound:CreateFontString(
        nil, "OVERLAY", "GameFontHighlightSmall")
    soundDescription:SetPoint("TOPLEFT", soundTitle, "BOTTOMLEFT", 0, -5)
    soundDescription:SetWidth(530)
    soundDescription:SetJustifyH("LEFT")
    soundDescription:SetText(
        "Rule for Cyclone: play Raid Warning when 3 friendly raid/BG members are affected by it. Nameplates do not need to be visible.")
    soundDescription:SetTextColor(0.72, 0.75, 0.80)

    local soundEnabled = CreateFrame(
        "CheckButton", "ActuallyRaidCCSoundCheckButton", sound, "UICheckButtonTemplate")
    soundEnabled:SetWidth(26)
    soundEnabled:SetHeight(26)
    soundEnabled:SetPoint("TOPLEFT", sound, "TOPLEFT", 12, -62)
    local soundEnabledLabel = soundEnabled:CreateFontString(
        nil, "OVERLAY", "GameFontHighlight")
    soundEnabledLabel:SetPoint("LEFT", soundEnabled, "RIGHT", 3, 1)
    soundEnabledLabel:SetText("Enable this sound alert")
    soundEnabled:SetScript("OnClick", function(owner)
        RaidCC:SetSoundEnabled(owner:GetChecked() == 1 or owner:GetChecked() == true)
    end)

    local thresholdLabel = sound:CreateFontString(
        nil, "OVERLAY", "GameFontHighlightSmall")
    thresholdLabel:SetPoint("TOPLEFT", sound, "TOPLEFT", 18, -105)
    thresholdLabel:SetText("Sound trigger count: 3 friendlies")
    thresholdLabel:SetTextColor(0.88, 0.91, 0.96)

    local thresholdSlider = CreateFrame(
        "Slider", "ActuallyRaidCCSoundThresholdSlider", sound, "OptionsSliderTemplate")
    thresholdSlider:SetWidth(210)
    thresholdSlider:SetHeight(16)
    thresholdSlider:SetPoint("TOPLEFT", sound, "TOPLEFT", 18, -128)
    thresholdSlider:SetMinMaxValues(MIN_SOUND_THRESHOLD, MAX_SOUND_THRESHOLD)
    thresholdSlider:SetValueStep(1)
    _G[thresholdSlider:GetName() .. "Low"]:SetText(tostring(MIN_SOUND_THRESHOLD))
    _G[thresholdSlider:GetName() .. "High"]:SetText(tostring(MAX_SOUND_THRESHOLD))
    _G[thresholdSlider:GetName() .. "Text"]:SetText("")
    thresholdSlider:SetScript("OnValueChanged", function(owner)
        if RaidCC.settingsRefreshing then return end
        RaidCC:SetSoundThreshold(owner:GetValue())
    end)

    local soundEffectLabel = sound:CreateFontString(
        nil, "OVERLAY", "GameFontHighlightSmall")
    soundEffectLabel:SetPoint("TOPLEFT", sound, "TOPLEFT", 275, -70)
    soundEffectLabel:SetText("This rule belongs to")
    soundEffectLabel:SetTextColor(0.88, 0.91, 0.96)

    local soundEffectName = sound:CreateFontString(
        nil, "OVERLAY", "GameFontHighlight")
    soundEffectName:SetPoint("TOPLEFT", sound, "TOPLEFT", 275, -91)
    soundEffectName:SetWidth(250)
    soundEffectName:SetJustifyH("LEFT")
    soundEffectName:SetText("Cyclone")
    soundEffectName:SetTextColor(1.00, 0.78, 0.30)

    local soundChoiceLabel = sound:CreateFontString(
        nil, "OVERLAY", "GameFontHighlightSmall")
    soundChoiceLabel:SetPoint("TOPLEFT", sound, "TOPLEFT", 275, -126)
    soundChoiceLabel:SetText("Sound to play")
    soundChoiceLabel:SetTextColor(0.88, 0.91, 0.96)

    local soundDropdown = CreateFrame(
        "Frame", "ActuallyRaidCCSoundDropdown", sound, "UIDropDownMenuTemplate")
    soundDropdown:SetPoint("TOPLEFT", sound, "TOPLEFT", 260, -139)
    UIDropDownMenu_SetWidth(soundDropdown, 180)
    UIDropDownMenu_Initialize(soundDropdown, function()
        local settings = RaidCC:GetEffectSettings()
        local selected = settings and settings.sound
        for _, option in ipairs(RaidCC:GetSoundOptions()) do
            local key, label = option.key, option.label
            local info = UIDropDownMenu_CreateInfo()
            info.text = label
            info.value = key
            info.checked = selected == key
            info.func = function()
                RaidCC:SetSound(key, true)
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local testSound = CreateFrame("Button", nil, sound, "UIPanelButtonTemplate")
    testSound:SetWidth(95)
    testSound:SetHeight(24)
    testSound:SetPoint("TOPRIGHT", sound, "TOPRIGHT", -17, -160)
    testSound:SetText("Test Sound")
    testSound:SetScript("OnClick", function()
        RaidCC:PlayConfiguredSound(true)
    end)

    local status = sound:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", sound, "BOTTOMLEFT", 18, 15)
    status:SetWidth(405)
    status:SetJustifyH("LEFT")
    status:SetText("Sound disabled")

    local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    reset:SetWidth(105)
    reset:SetHeight(24)
    reset:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 14)
    reset:SetText("Reset Defaults")
    reset:SetScript("OnClick", function()
        RaidCC:ResetVisualSettings()
    end)

    local done = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    done:SetWidth(80)
    done:SetHeight(24)
    done:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 14)
    done:SetText("Done")
    done:SetScript("OnClick", function()
        frame:Hide()
    end)

    self.settingsFrame = frame
    self.settingsSizeLabel = sizeLabel
    self.settingsSizeSlider = sizeSlider
    self.settingsOffsetLabel = offsetLabel
    self.settingsOffsetSlider = offsetSlider
    self.settingsPulseCheckbox = pulseCheckbox
    self.settingsGlowCheckbox = glowCheckbox
    self.settingsEffectDropdown = effectDropdown
    self.settingsColorDropdown = colorDropdown
    self.settingsRemoveEffectButton = removeEffect
    self.settingsArrowRuleDescription = arrowRuleDescription
    self.settingsArrowEnabledCheckbox = arrowEnabled
    self.settingsArrowThresholdLabel = arrowThresholdLabel
    self.settingsArrowThresholdSlider = arrowThresholdSlider
    self.settingsSoundCheckbox = soundEnabled
    self.settingsSoundEffectName = soundEffectName
    self.settingsRuleDescription = soundDescription
    self.settingsThresholdLabel = thresholdLabel
    self.settingsThresholdSlider = thresholdSlider
    self.settingsSoundDropdown = soundDropdown
    self.settingsStatus = status

    if UISpecialFrames then
        table.insert(UISpecialFrames, frame:GetName())
    end
    frame:Hide()
    self:RefreshSettingsPanel()
    return frame
end

function RaidCC:RefreshSettingsStatus()
    if not self.settingsStatus then return end
    local effectKey = self:GetSelectedEffectKey()
    local settings = self:GetEffectSettings(effectKey)
    if not settings then return end
    local count = self.affectedFriendlyCounts[effectKey] or 0
    local threshold = settings.soundThreshold
    local watched = self:GetSoundFilterLabel()
    if settings.soundEnabled ~= true then
        self.settingsStatus:SetText(
            "Alert off  |  " .. watched .. ": " .. tostring(count) .. " affected")
        self.settingsStatus:SetTextColor(0.62, 0.66, 0.72)
    elseif not self.runtimeActive then
        self.settingsStatus:SetText(
            "Waiting for active mode  |  " .. watched .. ": " .. tostring(count)
                .. " of " .. tostring(threshold) .. " affected")
        self.settingsStatus:SetTextColor(1.00, 0.78, 0.30)
    elseif self.soundThresholdReached[effectKey] then
        self.settingsStatus:SetText(
            "Sound played  |  " .. watched .. ": " .. tostring(count)
                .. " affected; rearms below " .. tostring(threshold))
        self.settingsStatus:SetTextColor(1.00, 0.55, 0.22)
    else
        self.settingsStatus:SetText(
            "Armed  |  " .. watched .. ": " .. tostring(count)
                .. " of " .. tostring(threshold) .. " affected")
        self.settingsStatus:SetTextColor(0.35, 1.00, 0.48)
    end
end

function RaidCC:RefreshSettingsPanel()
    if not self.settingsFrame or self.settingsRefreshing then return end
    local settings = self:GetVisualSettings()
    local effect = self:GetSelectedEffect()
    local effectSettings = self:GetEffectSettings()
    if not effect or not effectSettings then return end
    self.settingsRefreshing = true

    UIDropDownMenu_SetSelectedValue(self.settingsEffectDropdown, effect.key)
    UIDropDownMenu_SetText(
        self.settingsEffectDropdown,
        self:GetEffectDisplayName(effect)
            .. (effect.custom and " (Custom)" or ""))
    UIDropDownMenu_SetSelectedValue(self.settingsColorDropdown, effectSettings.color)
    UIDropDownMenu_SetText(
        self.settingsColorDropdown, self:GetEffectColorLabel(effect.key))
    if effect.custom then
        self.settingsRemoveEffectButton:Enable()
    else
        self.settingsRemoveEffectButton:Disable()
    end
    self.settingsSizeSlider:SetValue(settings.arrowSize)
    self.settingsSizeLabel:SetText("Size: " .. tostring(settings.arrowSize) .. " px")
    self.settingsOffsetSlider:SetValue(settings.arrowOffset)
    self.settingsOffsetLabel:SetText("Gap: " .. tostring(settings.arrowOffset) .. " px")
    self.settingsPulseCheckbox:SetChecked(settings.pulse == true)
    self.settingsGlowCheckbox:SetChecked(settings.glow == true)
    self.settingsArrowEnabledCheckbox:SetChecked(effectSettings.arrowEnabled == true)
    self.settingsArrowThresholdSlider:SetValue(effectSettings.arrowThreshold)
    self.settingsArrowThresholdLabel:SetText(
        "Arrow trigger count: " .. tostring(effectSettings.arrowThreshold)
            .. (effectSettings.arrowThreshold == 1 and " friendly" or " friendlies"))
    if effectSettings.arrowThreshold == 1 then
        self.settingsArrowRuleDescription:SetText(
            self:GetEffectDisplayName(effect)
                .. ": every affected friendly shows an arrow immediately.")
    else
        self.settingsArrowRuleDescription:SetText(
            self:GetEffectDisplayName(effect)
                .. ": below " .. tostring(effectSettings.arrowThreshold)
                .. ", no arrows show; reaching "
                .. tostring(effectSettings.arrowThreshold)
                .. " reveals arrows on every affected friendly.")
    end
    self.settingsSoundCheckbox:SetChecked(effectSettings.soundEnabled == true)
    self.settingsThresholdSlider:SetValue(effectSettings.soundThreshold)
    self.settingsThresholdLabel:SetText(
        "Sound trigger count: " .. tostring(effectSettings.soundThreshold)
            .. (effectSettings.soundThreshold == 1 and " friendly" or " friendlies"))
    self.settingsSoundEffectName:SetText(self:GetEffectDisplayName(effect))
    UIDropDownMenu_SetSelectedValue(self.settingsSoundDropdown, effectSettings.sound)
    UIDropDownMenu_SetText(
        self.settingsSoundDropdown, self:GetSoundLabel(effect.key))
    self.settingsRuleDescription:SetText(
        "Rule for " .. self:GetEffectDisplayName(effect)
            .. ": play " .. self:GetSoundLabel(effect.key)
            .. " when " .. tostring(effectSettings.soundThreshold)
            .. " friendly raid/BG "
            .. (effectSettings.soundThreshold == 1 and "member is" or "members are")
            .. " affected by it"
            .. ". Nameplates do not need to be visible.")

    self.settingsRefreshing = false
    self:RefreshArrowVisuals()
    self:RefreshSettingsStatus()
end

function RaidCC:CreateCustomEffectEditor()
    if self.customEffectEditor then return self.customEffectEditor end
    local parent = self.settingsFrame or UIParent
    local editor = CreateFrame(
        "Frame", "ActuallyRaidCCAddEffectFrame", parent)
    editor:SetWidth(420)
    editor:SetHeight(230)
    editor:SetPoint("CENTER", parent, "CENTER", 0, 20)
    editor:SetFrameStrata("FULLSCREEN_DIALOG")
    editor:EnableMouse(true)
    if Addon.Util and Addon.Util.SetBackdrop then
        Addon.Util.SetBackdrop(
            editor,
            { 0.025, 0.035, 0.050, 0.995 },
            { 0.28, 0.76, 1.00, 1.00 })
    end

    local title = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", editor, "TOPLEFT", 16, -15)
    title:SetText("Add a Tracked Effect")

    local close = CreateFrame("Button", nil, editor, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", editor, "TOPRIGHT", -4, -4)

    local idLabel = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    idLabel:SetPoint("TOPLEFT", editor, "TOPLEFT", 18, -56)
    idLabel:SetText("Spell ID")

    local input = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
    input:SetWidth(145)
    input:SetHeight(24)
    input:SetPoint("LEFT", idLabel, "RIGHT", 14, 0)
    input:SetAutoFocus(false)
    input:SetMaxLetters(10)

    local preview = CreateFrame("Button", nil, editor)
    preview:SetWidth(42)
    preview:SetHeight(42)
    preview:SetPoint("TOPRIGHT", editor, "TOPRIGHT", -22, -50)
    local previewIcon = preview:CreateTexture(nil, "ARTWORK")
    previewIcon:SetAllPoints(preview)
    previewIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    previewIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local previewName = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    previewName:SetPoint("TOPLEFT", editor, "TOPLEFT", 18, -94)
    previewName:SetPoint("RIGHT", preview, "LEFT", -10, 0)
    previewName:SetJustifyH("LEFT")
    previewName:SetText("Enter an ID to preview it")

    local colorLabel = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colorLabel:SetPoint("TOPLEFT", editor, "TOPLEFT", 18, -130)
    colorLabel:SetText("Default arrow colour")

    local colorDropdown = CreateFrame(
        "Frame", "ActuallyRaidCCAddEffectColorDropdown",
        editor, "UIDropDownMenuTemplate")
    colorDropdown:SetPoint("LEFT", colorLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(colorDropdown, 115)
    UIDropDownMenu_Initialize(colorDropdown, function()
        for _, option in ipairs(RaidCC:GetEffectColorOptions()) do
            local key, label = option.key, option.label
            local info = UIDropDownMenu_CreateInfo()
            info.text = label
            info.value = key
            info.checked = editor.colorKey == key
            info.func = function()
                editor.colorKey = key
                UIDropDownMenu_SetSelectedValue(colorDropdown, key)
                UIDropDownMenu_SetText(colorDropdown, label)
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local hint = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", editor, "TOPLEFT", 18, -166)
    hint:SetWidth(380)
    hint:SetJustifyH("LEFT")
    hint:SetText(
        "The effect is detected in both buffs and debuffs. Its arrow and sound rules can be edited after adding it.")
    hint:SetTextColor(0.68, 0.74, 0.82)

    local addButton = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    addButton:SetWidth(115)
    addButton:SetHeight(25)
    addButton:SetPoint("BOTTOMRIGHT", editor, "BOTTOMRIGHT", -18, 15)
    addButton:SetText("Add Effect")
    addButton:Disable()

    local function ShowSpellTooltip(owner)
        if not editor.spellID then return end
        GameTooltip:SetOwner(owner or editor, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("spell:" .. tostring(editor.spellID))
        GameTooltip:Show()
    end

    local function UpdatePreview()
        local spellID = tonumber(input:GetText())
        local name, rank, icon
        if spellID and GetSpellInfo then
            name, rank, icon = GetSpellInfo(spellID)
        end
        if name then
            editor.spellID = spellID
            previewIcon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            previewName:SetText(
                rank and rank ~= "" and (name .. " (" .. rank .. ")") or name)
            addButton:Enable()
        else
            editor.spellID = nil
            previewIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            previewName:SetText("Unknown spell ID")
            addButton:Disable()
            GameTooltip:Hide()
        end
    end

    input:SetScript("OnTextChanged", UpdatePreview)
    input:SetScript("OnEscapePressed", function(owner)
        owner:ClearFocus()
        editor:Hide()
    end)
    input:SetScript("OnEnterPressed", function()
        if editor.spellID then addButton:Click() end
    end)
    preview:SetScript("OnEnter", function(owner)
        ShowSpellTooltip(owner)
    end)
    preview:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    addButton:SetScript("OnClick", function()
        if editor.spellID
            and RaidCC:AddCustomEffect(editor.spellID, editor.colorKey) then
            editor:Hide()
        end
    end)
    editor:SetScript("OnShow", function()
        editor.colorKey = "yellow"
        UIDropDownMenu_SetSelectedValue(colorDropdown, editor.colorKey)
        UIDropDownMenu_SetText(colorDropdown, "Yellow")
        input:SetText("")
        input:SetFocus()
    end)
    editor:SetScript("OnHide", function()
        input:ClearFocus()
        GameTooltip:Hide()
    end)

    editor.input = input
    editor:Hide()
    self.customEffectEditor = editor
    return editor
end

function RaidCC:ShowCustomEffectEditor()
    local editor = self:CreateCustomEffectEditor()
    editor:Show()
    if editor.Raise then editor:Raise() end
end

function RaidCC:ToggleSettings()
    if not self.initialized then
        self:Initialize()
    end
    local frame = self:CreateSettingsPanel()
    if frame:IsShown() then
        frame:Hide()
    else
        self:UpdateSoundThreshold(false)
        self:RefreshSettingsPanel()
        frame:Show()
        if frame.Raise then frame:Raise() end
    end
end

function RaidCC:CreateOverlay(nameplate)
    local overlay = CreateFrame("Frame", nil, nameplate)
    overlay:SetAllPoints(nameplate)
    if overlay.SetFrameLevel and nameplate.GetFrameLevel then
        overlay:SetFrameLevel((nameplate:GetFrameLevel() or 0) + 10)
    end
    overlay:EnableMouse(false)

    local nameText = overlay:CreateFontString(nil, "OVERLAY")
    nameText:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    nameText:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    overlay.nameText = nameText

    local arrowVisual = self:CreateArrowVisual(overlay, nameText)
    overlay.arrowVisual = arrowVisual
    overlay.arrow = arrowVisual.arrow
    overlay.arrowShadow = arrowVisual.arrowShadow
    overlay.arrowGlow = arrowVisual.arrowGlow
    self:ApplyArrowVisualSettings(overlay)

    overlay:Hide()
    return overlay
end

function RaidCC:GetState(nameplate)
    local state = nameplate._actuallyRaidCCState
    if not state then
        state = {
            active = false,
            unit = nil,
            guid = nil,
            overlay = self:CreateOverlay(nameplate),
            retryAt = nil,
            retryCount = 0,
            retryScheduled = false,
            debugDecision = nil,
            arrowShown = false,
            arrowKind = nil,
        }
        nameplate._actuallyRaidCCState = state
    end
    return state
end

function RaidCC:ScheduleGuardedRetry(nameplate, state)
    if state.retryScheduled or not C_Timer or not C_Timer.After then
        return
    end
    state.retryScheduled = true
    local expectedUnit = state.unit
    local expectedGUID = state.guid
    C_Timer.After(0, function()
        state.retryScheduled = false
        if state.unit ~= expectedUnit
            or state.guid ~= expectedGUID
            or not expectedUnit
            or not UnitExists(expectedUnit)
            or UnitGUID(expectedUnit) ~= expectedGUID then
            return
        end
        RaidCC:SafeEvaluatePlate(nameplate, expectedUnit)
    end)
end

local function FindNameText(nameplate)
    local lite = nameplate[LITE_FRAME_FIELD]
    local full = nameplate[FULL_FRAME_FIELD]
    if nameplate._isLite and lite then
        return lite.liteNameText
    end
    if full then
        return full.nameText
    end
    if lite then
        return lite.liteNameText
    end
end

function RaidCC:CopyNameAppearance(nameplate, unit, overlay)
    local source = FindNameText(nameplate)
    local target = overlay.nameText
    local displayed = source and source.GetText and source:GetText()
    target:SetText(displayed and displayed ~= "" and displayed or (UnitName(unit) or ""))

    if source and source.GetFont then
        local path, size, flags = source:GetFont()
        if path and size then
            target:SetFont(path, size, flags)
        end
    end
    if source and source.GetTextColor then
        target:SetTextColor(source:GetTextColor())
    else
        target:SetTextColor(1, 1, 1, 1)
    end
    if source and source.GetShadowColor and target.SetShadowColor then
        target:SetShadowColor(source:GetShadowColor())
    end
    if source and source.GetShadowOffset and target.SetShadowOffset then
        target:SetShadowOffset(source:GetShadowOffset())
    end
end

function RaidCC:InstallShowSuppression(frame, nameplate)
    if not frame or frame._actuallyRaidCCShowHooked or not hooksecurefunc then
        return
    end
    frame._actuallyRaidCCShowHooked = true
    hooksecurefunc(frame, "Show", function(self)
        local state = nameplate._actuallyRaidCCState
        if state and state.active then
            self:Hide()
        end
    end)
end

function RaidCC:InstallHooks(nameplate)
    self:InstallShowSuppression(nameplate[FULL_FRAME_FIELD], nameplate)
    self:InstallShowSuppression(nameplate[LITE_FRAME_FIELD], nameplate)
    self:InstallShowSuppression(nameplate[LITE_ICON_FIELD], nameplate)
end

function RaidCC:SuppressTurboPlates(nameplate)
    SafeHide(nameplate[FULL_FRAME_FIELD])
    SafeHide(nameplate[LITE_FRAME_FIELD])
    SafeHide(nameplate[LITE_ICON_FIELD])
end

function RaidCC:RemoveOverride(nameplate, plateIsBeingRemoved, reason)
    local state = nameplate and nameplate._actuallyRaidCCState
    if not state then
        return
    end

    local wasActive = state.active
    state.active = false
    state.retryAt = nil
    state.retryScheduled = false
    state.arrowShown = false
    state.arrowKind = nil
    if state.overlay then
        self:HideArrowVisual(state.overlay)
        state.overlay:Hide()
    end
    if wasActive then
        self:Debug("override removed reason=" .. tostring(reason or "reevaluated")
            .. " " .. UnitDescription(state.unit))
    end
    if plateIsBeingRemoved or not wasActive then
        return
    end

    -- _isLite is TurboPlates' display-mode decision and is never changed here.
    if nameplate._isLite then
        SafeHide(nameplate[FULL_FRAME_FIELD])
        SafeShow(nameplate[LITE_FRAME_FIELD])
    else
        SafeHide(nameplate[LITE_FRAME_FIELD])
        SafeHide(nameplate[LITE_ICON_FIELD])
        SafeShow(nameplate[FULL_FRAME_FIELD])
    end
end

function RaidCC:FindTrackedAura(unit, requireDisplayThreshold)
    if not unit or not UnitExists(unit) then
        return false
    end
    local bestKind
    local bestName
    local bestSpellID
    local bestPriority = 0
    local function ConsiderAura(name, spellID)
        local kind = (spellID and self.trackedSpellIDs[spellID])
            or self.trackedSpellNames[name]
        if requireDisplayThreshold and not self:ShouldDisplayAuraKind(kind) then
            return
        end
        local effect = kind and self.effectsByKey[kind]
        local priority = effect and effect.priority or 0
        if priority > bestPriority then
            bestKind = kind
            bestName = name
            bestSpellID = spellID
            bestPriority = priority
        end
    end

    if UnitDebuff then
        for index = 1, 40 do
            local name, _, _, _, _, _, _, _, _, _, spellID = UnitDebuff(unit, index)
            if not name then
                break
            end
            ConsiderAura(name, spellID)
        end
    end

    if UnitBuff then
        for index = 1, 40 do
            local name, _, _, _, _, _, _, _, _, _, spellID = UnitBuff(unit, index)
            if not name then
                break
            end
            ConsiderAura(name, spellID)
        end
    end

    if bestKind then
        return true, bestKind, bestName, bestSpellID
    end
    return false, nil, nil, nil
end

function RaidCC:UpdateArrow(state)
    local valid = state.active
        and state.unit
        and UnitExists(state.unit)
        and UnitGUID(state.unit) == state.guid
        and self.raidGUIDs[state.guid] == true
    local hasAura, kind, spellName, spellID
    if valid then
        hasAura, kind, spellName, spellID = self:FindTrackedAura(state.unit, true)
    end
    if hasAura then
        self:ShowArrowVisual(state.overlay, kind)
    else
        self:HideArrowVisual(state.overlay)
    end
    local shown = hasAura and true or false
    if state.arrowShown ~= shown or state.arrowKind ~= kind then
        state.arrowShown = shown
        state.arrowKind = kind
        self:Debug("tracked aura arrow " .. (shown and ("shown:" .. tostring(kind)) or "hidden")
            .. " " .. UnitDescription(state.unit)
            .. (shown and (" spell=" .. tostring(spellName)
                .. " spellID=" .. tostring(spellID)) or ""))
    end
end

function RaidCC:ApplyOverride(nameplate, unit, state)
    state.active = true
    state.retryAt = nil
    self:InstallHooks(nameplate)
    self:CopyNameAppearance(nameplate, unit, state.overlay)
    self:SuppressTurboPlates(nameplate)
    state.overlay:Show()
    self:UpdateArrow(state)
end

function RaidCC:EvaluatePlate(nameplate, unit)
    if not nameplate then
        return
    end
    local state = self:GetState(nameplate)
    unit = unit or state.unit or nameplate._unit or nameplate._turboTrackedUnit
    local guid = unit and UnitExists(unit) and UnitGUID(unit) or nil

    if state.unit and self.unitToPlate[state.unit] == nameplate and state.unit ~= unit then
        self.unitToPlate[state.unit] = nil
    end
    state.unit = unit
    state.guid = guid
    if unit then
        self.unitToPlate[unit] = nameplate
    end

    local shouldOverride, decision = self:ClassifyUnit(unit)
    if not shouldOverride then
        if state.debugDecision ~= decision then
            state.debugDecision = decision
            self:Debug("plate decision=" .. tostring(decision) .. " "
                .. UnitDescription(unit))
        end
        self:RemoveOverride(nameplate, false, decision)
        return
    end

    if not self:HasCompatibleFrames(nameplate) then
        state.active = false
        state.overlay:Hide()
        state.retryCount = (state.retryCount or 0) + 1
        state.retryAt = Now()
        local retryDecision = "waiting-compatible-frames:" .. tostring(state.retryCount)
        if state.debugDecision ~= retryDecision then
            state.debugDecision = retryDecision
            self:Debug("plate decision=waiting-compatible-frames retry="
                .. tostring(state.retryCount) .. " " .. UnitDescription(unit)
                .. " full=" .. tostring(nameplate[FULL_FRAME_FIELD] ~= nil)
                .. " lite=" .. tostring(nameplate[LITE_FRAME_FIELD] ~= nil)
                .. " liteIcon=" .. tostring(nameplate[LITE_ICON_FIELD] ~= nil))
        end
        if state.retryCount <= 2 then
            self:ScheduleGuardedRetry(nameplate, state)
        else
            self:WarnCompatibility()
        end
        return
    end

    state.retryCount = 0
    state.retryScheduled = false
    if state.debugDecision ~= "override-active" then
        state.debugDecision = "override-active"
        self:Debug("plate decision=override-active " .. UnitDescription(unit)
            .. " isLite=" .. tostring(nameplate._isLite and true or false))
    end
    self:ApplyOverride(nameplate, unit, state)
end

function RaidCC:SafeEvaluatePlate(nameplate, unit)
    local ok, reason = pcall(self.EvaluatePlate, self, nameplate, unit)
    if not ok then
        self:RemoveOverride(nameplate, false)
        self:Print("plate evaluation failed safely: " .. tostring(reason))
    end
end

function RaidCC:OnPlateAdded(unit, suppliedNameplate)
    local nameplate = suppliedNameplate or GetPlateForUnit(unit)
    if not nameplate then
        self:Debug("plate added but no frame was resolved " .. UnitDescription(unit))
        return
    end
    self:Debug("plate added source=" .. (suppliedNameplate and "manager" or "event")
        .. " " .. UnitDescription(unit))
    self.visiblePlates[nameplate] = true
    local state = self:GetState(nameplate)
    state.unit = unit
    state.guid = UnitGUID(unit)
    state.retryCount = 0
    self:SafeEvaluatePlate(nameplate, unit)
end

function RaidCC:OnPlateRemoved(unit, suppliedNameplate)
    local nameplate = suppliedNameplate or self.unitToPlate[unit] or GetPlateForUnit(unit)
    if not nameplate then
        self:Debug("plate removed but no tracked frame was resolved " .. UnitDescription(unit))
        return
    end
    self:Debug("plate removed source=" .. (suppliedNameplate and "manager" or "event")
        .. " " .. UnitDescription(unit))
    local state = nameplate._actuallyRaidCCState
    if state then
        self:RemoveOverride(nameplate, true, "plate-removed")
        state.unit = nil
        state.guid = nil
        state.retryCount = 0
        state.retryScheduled = false
    end
    self.unitToPlate[unit] = nil
    self.visiblePlates[nameplate] = nil
end

function RaidCC:DiscoverVisiblePlates()
    if not C_NamePlateManager or not C_NamePlateManager.EnumerateActiveNamePlates then
        return
    end
    local discovered = 0
    for nameplate in C_NamePlateManager.EnumerateActiveNamePlates() do
        discovered = discovered + 1
        self.visiblePlates[nameplate] = true
        local unit = nameplate._unit or nameplate._turboTrackedUnit
        if unit then
            local state = self:GetState(nameplate)
            state.unit = unit
            state.guid = UnitGUID(unit)
            self.unitToPlate[unit] = nameplate
        end
    end
    self:Debug("active plate discovery enumerated=" .. tostring(discovered)
        .. " tracked=" .. tostring(CountTable(self.visiblePlates)))
end

function RaidCC:ReevaluateVisiblePlates()
    self:DiscoverVisiblePlates()
    for nameplate in pairs(self.visiblePlates) do
        local state = nameplate._actuallyRaidCCState
        self:SafeEvaluatePlate(nameplate, state and state.unit)
    end
end

function RaidCC:GetCVarValue(name)
    local value = GetCVar and GetCVar(name)
    return value ~= nil and tostring(value) or "0"
end

function RaidCC:ForceRequiredCVars()
    if not SetCVar then
        return
    end
    self.cvarGuard = true
    local changed = {}
    local ok, reason = pcall(function()
        if self:GetCVarValue("nameplateShowFriends") ~= "1" then
            SetCVar("nameplateShowFriends", "1")
            table.insert(changed, "friends")
        end
        if self:GetCVarValue("nameplateShowEnemies") ~= "1" then
            SetCVar("nameplateShowEnemies", "1")
            table.insert(changed, "enemies")
        end
    end)
    self.cvarGuard = false
    if not ok then
        self:Print("could not enable required nameplate settings: " .. tostring(reason))
        return false
    end
    if #changed > 0 then
        self:Debug("forced nameplate CVars: " .. table.concat(changed, ","))
    end
    return true
end

function RaidCC:SaveCVarSnapshot()
    local snapshot = self.db.cvarSnapshot
    if type(snapshot) == "table" and snapshot.valid then
        return
    end
    self.db.cvarSnapshot = {
        valid = true,
        friends = self:GetCVarValue("nameplateShowFriends"),
        enemies = self:GetCVarValue("nameplateShowEnemies"),
    }
    self:Debug("saved CVar snapshot friends=" .. tostring(self.db.cvarSnapshot.friends)
        .. " enemies=" .. tostring(self.db.cvarSnapshot.enemies))
end

function RaidCC:RestoreCVars(clearSnapshot)
    local snapshot = self.db and self.db.cvarSnapshot
    if type(snapshot) == "table" and snapshot.valid and SetCVar then
        self.cvarGuard = true
        local ok, reason = pcall(function()
            SetCVar("nameplateShowFriends", snapshot.friends or "0")
            SetCVar("nameplateShowEnemies", snapshot.enemies or "0")
        end)
        self.cvarGuard = false
        if not ok then
            self:Print("could not restore previous nameplate settings: " .. tostring(reason))
            return false
        end
        self:Debug("restored CVar snapshot friends=" .. tostring(snapshot.friends)
            .. " enemies=" .. tostring(snapshot.enemies)
            .. " clear=" .. tostring(clearSnapshot and true or false))
    end
    if clearSnapshot and self.db then
        self.db.cvarSnapshot = nil
    end
    return true
end

function RaidCC:EnterActiveMode()
    local compatible, code, message = self:GetCompatibilityStatus()
    if not compatible then
        self:WarnEnvironment(code, message)
        return
    end
    if self.runtimeActive then
        if not self:ForceRequiredCVars() then
            self:LeaveActiveMode()
            return
        end
        self:RebuildRaidGUIDCache()
        self:UpdateSoundThreshold(true)
        self:ReevaluateVisiblePlates()
        return
    end
    self:SaveCVarSnapshot()
    self.runtimeActive = true
    ClearTable(self.soundThresholdReached)
    ClearTable(self.affectedFriendlyCounts)
    self:Debug("entering active raid mode")
    if not self:ForceRequiredCVars() then
        self.runtimeActive = false
        self:RestoreCVars(true)
        return
    end
    self:RebuildRaidGUIDCache()
    self:UpdateSoundThreshold(true)
    self:ReevaluateVisiblePlates()
end

function RaidCC:LeaveActiveMode()
    for nameplate in pairs(self.visiblePlates) do
        self:RemoveOverride(nameplate, false, "mode-disabled")
    end
    self.runtimeActive = false
    ClearTable(self.soundThresholdReached)
    ClearTable(self.affectedFriendlyCounts)
    ClearTable(self.friendlyAuraCounts)
    self:RefreshSettingsStatus()
    self:Debug("leaving active raid mode")
    self:RestoreCVars(true)
    ClearTable(self.raidGUIDs)
end

function RaidCC:RefreshMode()
    local requested = self:IsModeRequested()
    local compatible, code, message = self:GetCompatibilityStatus()
    if requested and compatible then
        self:EnterActiveMode()
    else
        if self.runtimeActive then
            self:LeaveActiveMode()
        elseif self.db and self.db.cvarSnapshot and self.db.cvarSnapshot.valid then
            -- Recover a snapshot left by a reload/logout that came back disabled,
            -- outside a raid, or without a usable TurboPlates environment.
            self:RestoreCVars(true)
        end
        if requested and not compatible then
            self:WarnEnvironment(code, message)
        end
    end
    self:RefreshOptionsStatus()
end

function RaidCC:OnHeartbeat(elapsed)
    if not self.runtimeActive then
        return
    end
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < HEARTBEAT_INTERVAL then
        return
    end
    self.elapsed = 0

    local compatible = self:GetCompatibilityStatus()
    if not compatible then
        self:RefreshMode()
        return
    end

    for nameplate in pairs(self.visiblePlates) do
        local state = nameplate._actuallyRaidCCState
        if state then
            if state.retryAt then
                local currentGUID = state.unit and UnitExists(state.unit) and UnitGUID(state.unit)
                if currentGUID == state.guid then
                    self:SafeEvaluatePlate(nameplate, state.unit)
                else
                    self:RemoveOverride(nameplate, false)
                end
            elseif state.active then
                local valid = state.unit
                    and UnitExists(state.unit)
                    and UnitGUID(state.unit) == state.guid
                    and self.raidGUIDs[state.guid] == true
                if not valid then
                    self:SafeEvaluatePlate(nameplate, state.unit)
                else
                    self:InstallHooks(nameplate)
                    self:SuppressTurboPlates(nameplate)
                    self:CopyNameAppearance(nameplate, state.unit, state.overlay)
                    self:UpdateArrow(state)
                end
            end
        end
    end
end

function RaidCC:OnRosterChanged()
    local shouldBeActive = self:ShouldModeBeActive()
    self:Debug("roster changed shouldBeActive=" .. tostring(shouldBeActive)
        .. " runtime=" .. tostring(self.runtimeActive)
        .. " raidCount=" .. tostring(RaidCount()))
    self:RefreshMode()
end

function RaidCC:OnUnitChanged(unit, auraOnly)
    local nameplate = unit and self.unitToPlate[unit]
    local state = nameplate and nameplate._actuallyRaidCCState
    local validState = state
        and state.active
        and state.unit == unit
        and UnitGUID(unit) == state.guid
    local relevantAuraChanged = auraOnly
        and self.runtimeActive
        and (IsFriendlyGroupUnitToken(unit) or validState)
    if relevantAuraChanged then
        -- Both thresholds inspect raid/BG unit auras directly, so neither
        -- depends on every affected player having a visible nameplate.
        self:UpdateSoundThreshold(true)
        self:RefreshTrackedArrows()
        return
    end
    if not validState then
        return
    end
    if auraOnly then
        self:UpdateArrow(state)
    else
        self:CopyNameAppearance(nameplate, unit, state.overlay)
    end
end

function RaidCC:Initialize()
    if self.initialized then
        return
    end
    ActuallyDB = ActuallyDB or {}
    ActuallyDB.raidCC = type(ActuallyDB.raidCC) == "table" and ActuallyDB.raidCC or {}
    if ActuallyDB.raidCC.enabled == nil then
        ActuallyDB.raidCC.enabled = false
    end
    self.db = ActuallyDB.raidCC
    if self.db.debug == nil then self.db.debug = false end
    self:NormalizeSettings()
    self.debugEnabled = self.db.debug == true
    self:BuildEffectRegistry()
    self:DiscoverVisiblePlates()
    self.initialized = true
    self:RefreshMode()
    self:Debug("initialized")
    if Addon.CacheTips and Addon.CacheTips.RefreshRaidCCToggle then
        Addon.CacheTips:RefreshRaidCCToggle()
    end
end

local Events = {}

function Events.ADDON_LOADED(addonName)
    if addonName == "TurboPlates"
        or addonName == "ElvUI"
        or addonName == "Kui_Nameplates"
        or addonName == "TidyPlates_ThreatPlates"
        or addonName == "PlateBuffs" then
        RaidCC:RefreshMode()
    end
end

function Events.PLAYER_LOGIN()
    RaidCC:RefreshMode()
end

function Events.PLAYER_ENTERING_WORLD()
    RaidCC:RefreshMode()
    if RaidCC.runtimeActive then
        RaidCC:RebuildRaidGUIDCache()
        RaidCC:ReevaluateVisiblePlates()
    end
end

function Events.GROUP_ROSTER_UPDATE()
    RaidCC:OnRosterChanged()
end

Events.RAID_ROSTER_UPDATE = Events.GROUP_ROSTER_UPDATE

function Events.ZONE_CHANGED_NEW_AREA()
    RaidCC:OnRosterChanged()
end

function Events.NAME_PLATE_UNIT_ADDED(unit)
    RaidCC:OnPlateAdded(unit)
end

function Events.NAME_PLATE_UNIT_REMOVED(unit)
    RaidCC:OnPlateRemoved(unit)
end

function Events.UNIT_AURA(unit)
    RaidCC:OnUnitChanged(unit, true)
end

function Events.UNIT_NAME_UPDATE(unit)
    RaidCC:OnUnitChanged(unit, false)
end

function Events.CVAR_UPDATE(cvarName)
    if RaidCC.cvarGuard then
        return
    end
    if not RaidCC.runtimeActive then
        if RaidCC:IsModeRequested() then
            RaidCC:RefreshMode()
        end
        return
    end
    local compatible = RaidCC:GetCompatibilityStatus()
    if not compatible then
        RaidCC:RefreshMode()
        return
    end
    -- Wrath and Ascension builds report different CVAR_UPDATE names. Checking
    -- the two required values on any CVar event avoids depending on that label.
    if not RaidCC:ForceRequiredCVars() then
        RaidCC:LeaveActiveMode()
    end
end

function Events.PLAYER_LOGOUT()
    if RaidCC.runtimeActive then
        -- Keep the valid snapshot so a reload cannot mistake the temporary
        -- both-on state for the player's original preference.
        -- Clear runtime first so a delayed CVAR_UPDATE cannot force both on again.
        RaidCC.runtimeActive = false
        RaidCC:RestoreCVars(false)
    end
end

RaidCC.eventFrame = CreateFrame("Frame")
for event in pairs(Events) do
    pcall(RaidCC.eventFrame.RegisterEvent, RaidCC.eventFrame, event)
end
RaidCC.eventFrame:SetScript("OnEvent", function(_, event, ...)
    if not RaidCC.initialized then
        return
    end
    local handler = Events[event]
    if handler then
        handler(...)
    end
end)

-- TurboPlates 1.4.5 uses these manager callbacks for its authoritative plate
-- lifecycle. OptionalDeps guarantees its callback registration happens first.
-- The traditional NAME_PLATE events above remain as a harmless fallback.
if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("NamePlateManager.UnitAdded", function(_, unit, nameplate)
        RaidCC:OnPlateAdded(unit, nameplate)
    end)
    EventRegistry:RegisterCallback("NamePlateManager.UnitRemoved", function(_, unit, nameplate)
        RaidCC:OnPlateRemoved(unit, nameplate)
    end)
end

RaidCC.heartbeatFrame = CreateFrame("Frame")
RaidCC.heartbeatFrame:SetScript("OnUpdate", function(_, elapsed)
    RaidCC:OnHeartbeat(elapsed)
end)

if SlashCmdList then
    SLASH_ACTUALLYRAIDCC1 = "/raidcc"
    SLASH_ACTUALLYRAIDCC2 = "/rcc"
    SlashCmdList.ACTUALLYRAIDCC = function(input)
        RaidCC:HandleCommand(input)
    end
end
