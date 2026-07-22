local ACD = Actually.Modules.AscensionCooldowns
local Registry = ACD:NewModule("Registry")

Registry.entries = {
    [280860] = {
        key = "green_salve",
        fallbackName = "Green Salve",
        category = "utility",
        group = 1,
        priority = 10,
        alwaysShow = true,
        aliases = {},
        fallbackCD = nil,
    },
    [520175] = {
        key = "wand_of_time",
        fallbackName = "Wand of Time",
        category = "test",
        group = 1,
        priority = 100,
        alwaysShow = true,
        aliases = { 520702, 520703, 520704 },
        castAliases = { 520702, 520703, 520704 },
        fallbackCD = nil,
    },
    [1180523] = {
        key = "power_word_barrier",
        fallbackName = "Power Word: Barrier",
        category = "raid_defensive",
        group = 1,
        priority = 200,
        alwaysShow = true,
        notarget = true,
        aliases = {},
        fallbackCD = nil,
    },
    [64205] = {
        key = "divine_sacrifice",
        fallbackName = "Divine Sacrifice",
        category = "raid_defensive",
        group = 1,
        priority = 220,
        alwaysShow = true,
        notarget = true,
        aliases = {},
        fallbackCD = nil,
    },
    [31821] = {
        key = "aura_mastery",
        fallbackName = "Aura Mastery",
        category = "raid_defensive",
        group = 1,
        priority = 215,
        alwaysShow = true,
        notarget = true,
        aliases = {},
        fallbackCD = nil,
    },
    [33206] = {
        key = "pain_suppression",
        fallbackName = "Pain Suppression",
        category = "external_defensive",
        group = 1,
        priority = 210,
        alwaysShow = true,
        aliases = {},
        fallbackCD = nil,
    },
    [6940] = {
        key = "hand_of_sacrifice",
        fallbackName = "Hand of Sacrifice",
        category = "external_defensive",
        group = 1,
        priority = 208,
        alwaysShow = true,
        aliases = {},
        fallbackCD = nil,
    },
    [51052] = {
        key = "anti_magic_zone",
        fallbackName = "Anti-Magic Zone",
        category = "raid_defensive",
        group = 1,
        priority = 218,
        alwaysShow = true,
        notarget = true,
        aliases = {},
        fallbackCD = nil,
    },
    [16190] = {
        key = "mana_tide_totem",
        fallbackName = "Mana Tide Totem",
        category = "mana",
        group = 1,
        priority = 175,
        alwaysShow = true,
        notarget = true,
        aliases = {},
        fallbackCD = nil,
    },
    [57934] = {
        key = "tricks_of_the_trade",
        fallbackName = "Tricks of the Trade",
        category = "external_offensive",
        group = 1,
        priority = 150,
        alwaysShow = true,
        aliases = {},
        fallbackCD = nil,
    },
    [954501] = {
        key = "smoke_bomb",
        fallbackName = "Smoke Bomb",
        category = "raid_defensive",
        group = 1,
        priority = 205,
        alwaysShow = true,
        notarget = true,
        aliases = {},
        fallbackCD = nil,
    },
    [270182] = {
        key = "holy_supernova",
        fallbackName = "Holy Supernova",
        category = "utility",
        group = 1,
        priority = 120,
        alwaysShow = true,
        notarget = true,
        aliases = {},
        fallbackCD = nil,
    },
    [64044] = {
        key = "psychic_horror",
        fallbackName = "Psychic Horror",
        category = "control",
        group = 1,
        priority = 100,
        alwaysShow = true,
        aliases = {},
        fallbackCD = nil,
    },
    [12042] = {
        key = "arcane_power",
        fallbackName = "Arcane Power",
        category = "personal_offensive",
        group = 1,
        priority = 145,
        alwaysShow = true,
        notarget = true,
        aliases = {},
        fallbackCD = nil,
    },
    [280520] = {
        key = "gravebound_champion",
        fallbackName = "Gravebound Champion",
        category = "personal_offensive",
        group = 1,
        priority = 148,
        alwaysShow = true,
        notarget = true,
        aliases = {},
        fallbackCD = nil,
    },
    [280095] = {
        key = "embrace_the_void",
        fallbackName = "Embrace the Void",
        category = "personal_defensive",
        group = 1,
        priority = 160,
        alwaysShow = true,
        notarget = true,
        aliases = {},
        fallbackCD = nil,
    },
    [280695] = {
        key = "harvesting_grounds",
        fallbackName = "Harvesting Grounds",
        category = "utility",
        group = 1,
        priority = 125,
        alwaysShow = true,
        notarget = true,
        aliases = {},
        fallbackCD = nil,
    },
    [49016] = {
        key = "hysteria",
        fallbackName = "Hysteria",
        category = "external_offensive",
        group = 1,
        priority = 155,
        alwaysShow = true,
        aliases = {},
        fallbackCD = nil,
    },
    [760052] = {
        key = "mass_invisibility",
        fallbackName = "Mass Invisibility",
        category = "raid_utility",
        group = 1,
        priority = 180,
        alwaysShow = true,
        notarget = true,
        aliases = {},
        fallbackCD = nil,
    },
    [954523] = {
        key = "solar_beam",
        fallbackName = "Solar Beam",
        category = "control",
        group = 1,
        priority = 135,
        alwaysShow = true,
        notarget = true,
        aliases = {},
        fallbackCD = nil,
    },
    [49576] = {
        key = "death_grip",
        fallbackName = "Death Grip",
        category = "control",
        group = 1,
        priority = 130,
        alwaysShow = true,
        aliases = {},
        fallbackCD = nil,
    },
    [51490] = {
        key = "thunderstorm",
        fallbackName = "Thunderstorm",
        category = "control",
        group = 1,
        priority = 90,
        alwaysShow = true,
        aliases = {},
        fallbackCD = nil,
    },
    [2825] = {
        key = "bloodlust",
        fallbackName = "Bloodlust",
        category = "raid_offensive",
        group = 1,
        priority = 240,
        alwaysShow = true,
        notarget = true,
        aliases = {},
        fallbackCD = nil,
    },
    [23920] = {
        key = "spell_reflection",
        fallbackName = "Spell Reflection",
        category = "personal_defensive",
        group = 1,
        priority = 140,
        alwaysShow = true,
        notarget = true,
        aliases = {},
        fallbackCD = nil,
    },
    [954514] = {
        key = "skull_banner",
        fallbackName = "Skull Banner",
        category = "raid_offensive",
        group = 1,
        priority = 230,
        alwaysShow = true,
        notarget = true,
        aliases = {},
        fallbackCD = nil,
    },
    [64901] = {
        key = "hymn_of_hope",
        fallbackName = "Hymn of Hope",
        category = "mana",
        group = 1,
        priority = 170,
        alwaysShow = true,
        notarget = true,
        aliases = {},
        fallbackCD = nil,
    },
    [29166] = {
        key = "innervate",
        fallbackName = "Innervate",
        category = "mana",
        group = 1,
        priority = 165,
        alwaysShow = true,
        aliases = {},
        fallbackCD = nil,
    },
    [1180270] = {
        key = "war_banner",
        fallbackName = "War Banner",
        category = "raid_defensive",
        group = 1,
        priority = 190,
        alwaysShow = true,
        notarget = true,
        aliases = {},
        fallbackCD = nil,
    },
    [28260] = {
        key = "arterial_bind",
        fallbackName = "Arterial Bind",
        category = "raid_utility",
        group = 1,
        priority = 185,
        alwaysShow = true,
        notarget = true,
        aliases = {},
        fallbackCD = nil,
    },
    [281130] = {
        key = "bramblepatch",
        fallbackName = "Bramblepatch",
        category = "raid_utility",
        group = 1,
        priority = 180,
        alwaysShow = true,
        notarget = true,
        aliases = {},
        fallbackCD = nil,
    },
    [954507] = {
        key = "mass_entanglement",
        fallbackName = "Mass Entanglement",
        category = "control",
        group = 1,
        priority = 132,
        alwaysShow = true,
        aliases = {},
        fallbackCD = nil,
    },
    [280840] = {
        key = "buy_time",
        fallbackName = "Buy Time",
        category = "control",
        group = 1,
        priority = 200,
        alwaysShow = true,
        aliases = {},
        fallbackCD = nil,
    },
    [280080] = {
        key = "backtrack",
        fallbackName = "Backtrack",
        category = "control",
        group = 1,
        priority = 128,
        alwaysShow = true,
        aliases = {},
        fallbackCD = nil,
    },
    [280425] = {
        key = "gravity_bomb",
        fallbackName = "Gravity Bomb",
        category = "control",
        group = 1,
        priority = 138,
        alwaysShow = true,
        aliases = {},
        fallbackCD = nil,
    },
    [280175] = {
        key = "infinite_clone",
        fallbackName = "Infinite Clone",
        category = "personal_defensive",
        group = 1,
        priority = 162,
        alwaysShow = true,
        notarget = true,
        aliases = {},
        fallbackCD = nil,
    },
    [280385] = {
        key = "clasp_of_infinity",
        fallbackName = "Clasp of Infinity",
        category = "control",
        group = 1,
        priority = 126,
        alwaysShow = true,
        aliases = {},
        fallbackCD = nil,
    },
    [281120] = {
        key = "dimensional_divergence",
        fallbackName = "Dimensional Divergence",
        category = "control",
        group = 1,
        priority = 136,
        alwaysShow = true,
        aliases = {},
        fallbackCD = nil,
    },
    [280810] = {
        key = "vision_of_doom",
        fallbackName = "Vision of Doom",
        category = "raid_utility",
        group = 1,
        priority = 188,
        alwaysShow = true,
        aliases = {},
        fallbackCD = nil,
    },
    [280560] = {
        key = "grace_of_alexstrasza",
        fallbackName = "Grace of Alexstrasza",
        category = "raid_defensive",
        group = 1,
        priority = 225,
        alwaysShow = true,
        notarget = true,
        aliases = {},
        fallbackCD = nil,
    },
    [280595] = {
        key = "breath_of_neltharion",
        fallbackName = "Breath of Neltharion",
        category = "raid_offensive",
        group = 1,
        priority = 172,
        alwaysShow = true,
        notarget = true,
        aliases = {},
        fallbackCD = nil,
    },
    [502820] = {
        key = "sacred_grove",
        fallbackName = "Sacred Grove",
        category = "raid_defensive",
        group = 1,
        priority = 228,
        alwaysShow = true,
        notarget = true,
        aliases = { 502821, 502822, 800179, 800180, 800186 },
        fallbackCD = nil,
    },
    [280445] = {
        key = "war_golem",
        fallbackName = "War Golem",
        category = "raid_defensive",
        group = 1,
        priority = 205,
        alwaysShow = true,
        notarget = true,
        aliases = {},
        auraAliases = { 800330 },
        detection = "both",
        fallbackCD = nil,
    },
}

Registry.allowedDetection = {
    cast = true,
    aura = true,
    both = true,
    cooldown = true,
}

local function addAlias(map, value, canonicalID, label, diagnostics)
    if value == nil then return end
    local key = type(value) == "string" and string.lower(value) or value
    if map[key] and map[key] ~= canonicalID then
        table.insert(diagnostics, "duplicate " .. label .. " alias: " .. tostring(value))
        return
    end
    map[key] = canonicalID
end

function Registry:Initialize()
    self.aliases = {}
    self.castAliases = {}
    self.auraAliases = {}
    self.nameAliases = {}
    self.diagnostics = {}

    for canonicalID, entry in pairs(self.entries) do
        local valid = true
        if type(canonicalID) ~= "number" or canonicalID <= 0 then
            table.insert(self.diagnostics, "invalid canonical spell ID: " .. tostring(canonicalID))
            valid = false
        end
        if type(entry) ~= "table" or type(entry.key) ~= "string" or entry.key == "" then
            table.insert(self.diagnostics, "spell " .. tostring(canonicalID) .. " has no valid key")
            valid = false
        end
        if type(entry.fallbackName) ~= "string" or entry.fallbackName == "" then
            table.insert(self.diagnostics, "spell " .. tostring(canonicalID) .. " has no fallbackName")
        end
        if entry.detection and not self.allowedDetection[entry.detection] then
            table.insert(self.diagnostics, "spell " .. tostring(canonicalID) .. " has invalid detection")
            valid = false
        end
        if entry.fallbackCD ~= nil and (type(entry.fallbackCD) ~= "number" or entry.fallbackCD <= 0) then
            table.insert(self.diagnostics, "spell " .. tostring(canonicalID) .. " has invalid fallbackCD")
            entry.fallbackCD = nil
        end

        entry.canonicalID = canonicalID
        entry.valid = valid
        addAlias(self.aliases, canonicalID, canonicalID, "spell", self.diagnostics)
        addAlias(self.nameAliases, entry.fallbackName, canonicalID, "name", self.diagnostics)
        for _, alias in ipairs(entry.aliases or {}) do
            addAlias(self.aliases, alias, canonicalID, "spell", self.diagnostics)
        end
        for _, alias in ipairs(entry.castAliases or {}) do
            addAlias(self.castAliases, alias, canonicalID, "cast", self.diagnostics)
        end
        for _, alias in ipairs(entry.auraAliases or {}) do
            addAlias(self.auraAliases, alias, canonicalID, "aura", self.diagnostics)
        end
    end

    for _, diagnostic in ipairs(self.diagnostics) do
        ACD:Print("Registry: " .. diagnostic)
    end
end

function Registry:Canonicalize(value, mode)
    if value == nil then return nil end
    local key = type(value) == "string" and string.lower(value) or tonumber(value) or value
    local specific = mode == "cast" and self.castAliases or mode == "aura" and self.auraAliases or nil
    local canonical = (specific and specific[key]) or self.aliases[key] or self.nameAliases[key]
    local entry = canonical and self.entries[canonical]
    if entry and entry.valid then return canonical end
    return nil
end

function Registry:Get(canonicalID)
    local entry = self.entries[canonicalID]
    return entry and entry.valid and entry or nil
end
