local ARC = Actually.Modules.RaidCooldowns
local Renderer = ARC:NewModule("Renderer")

function Renderer:Initialize()
    self.rows = {}
    self.orderedGroups = {}
    self.dirty = true
    self.elapsed = 0
end

function Renderer:MarkDirty(reason)
    self.dirty = true
    self.dirtyReason = reason
end

function Renderer:GetSourcePlayers()
    if ARC.TestMode and ARC.TestMode.active then return ARC.TestMode.players end
    return ARC.State:GetPlayers()
end

function Renderer:ShouldDisplay(playerKey, spellID, spell, now)
    local profile = ARC.db and ARC.db.profile
    if not profile or not profile.enabled then return false end
    if profile.hideWhileSolo and not ARC.Roster:IsGrouped() then return false end
    local selfKey = ARC.Roster:GetPlayer()
    if profile.ignoreSelf and playerKey == selfKey then return false end
    local spellSettings = profile.spells[spellID] or {}
    if spellSettings.enabled == false then return false end
    local active = (spell.readyAt or 0) > now
    local entry = ARC.Registry:Get(spellID)
    local alwaysShow = spellSettings.alwaysShow
    if alwaysShow == nil then alwaysShow = entry and entry.alwaysShow end
    return active or alwaysShow == true
end

function Renderer:BuildRow(playerKey, player, spellID, spell, now)
    local entry = ARC.Registry:Get(spellID)
    local spellSettings = ARC.db.profile.spells[spellID] or {}
    local remaining = math.max(0, (spell.readyAt or 0) - now)
    return {
        key = tostring(playerKey) .. ":" .. tostring(spellID),
        playerKey = playerKey,
        playerName = player.name or tostring(playerKey),
        source = player.source,
        unit = player.unit,
        dead = player.dead,
        connected = player.connected,
        spellID = spellID,
        spellName = ARC.SpellInfo:ResolveSpellName(spellID),
        icon = ARC.SpellInfo:ResolveSpellIcon(spellID),
        group = spellSettings.group or (entry and entry.group) or 1,
        priority = spellSettings.priority or (entry and entry.priority) or 0,
        readyAt = spell.readyAt or 0,
        remaining = remaining,
        duration = spell.duration or 0,
        ready = remaining <= 0,
        target = spell.target,
        confidence = spell.confidence,
        stale = player.stale,
    }
end

function Renderer:CompareRows(left, right)
    if left.priority ~= right.priority then return left.priority > right.priority end
    if left.ready ~= right.ready then return not left.ready end
    if left.dead ~= right.dead then return not left.dead end
    if math.abs(left.remaining - right.remaining) > 0.1 then return left.remaining < right.remaining end
    if left.spellID ~= right.spellID then return left.spellID < right.spellID end
    return string.lower(left.playerName) < string.lower(right.playerName)
end

function Renderer:Reconcile()
    local now = ARC:Now()
    local rows, groups = {}, {}
    for playerKey, player in pairs(self:GetSourcePlayers()) do
        rows[playerKey] = {}
        for spellID, spell in pairs(player.spells or {}) do
            if self:ShouldDisplay(playerKey, spellID, spell, now) then
                local row = self:BuildRow(playerKey, player, spellID, spell, now)
                rows[playerKey][spellID] = row
                groups[row.group] = groups[row.group] or {}
                table.insert(groups[row.group], row)
            end
        end
        if not next(rows[playerKey]) then rows[playerKey] = nil end
    end
    for _, group in pairs(groups) do
        table.sort(group, function(left, right) return self:CompareRows(left, right) end)
    end
    self.rows, self.orderedGroups = rows, groups
    self.dirty = false
    if self.onReconcile then self.onReconcile(self, rows, groups) end
end

function Renderer:OnUpdate(elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < ARC.Constants.UI_UPDATE_INTERVAL then return end
    self.elapsed = 0
    if ARC.EnforceAuthorityVisibility then ARC:EnforceAuthorityVisibility() end
    local now = ARC:Now()
    local needsReconcile = self.dirty
    for _, spells in pairs(self.rows) do
        for _, row in pairs(spells) do
            local previous = row.remaining or 0
            local remaining = math.max(0, (row.readyAt or 0) - now)
            local shownBefore = math.ceil(previous)
            row.remaining = remaining
            row.ready = remaining <= 0
            if shownBefore ~= math.ceil(remaining) and self.onTick then self.onTick(self, row) end
            if previous > 0 and remaining <= 0 then needsReconcile = true end
        end
    end
    if needsReconcile then self:Reconcile() end
    if ARC.State:ExpireRemoteReports() and ARC.Comms.initialized then
        ARC.Comms:RequestState(false)
    end
    if ARC.Automation and ARC.Automation.initialized then ARC.Automation:OnUpdate(now) end
    if ARC.Requests and ARC.Requests.initialized then ARC.Requests:OnUpdate(now) end
    if ARC.Bundles and ARC.Bundles.initialized then ARC.Bundles:OnUpdate(now) end
    if ARC.Commander and ARC.Commander.initialized then ARC.Commander:OnUpdate(elapsed) end
end

function Renderer:CountRows()
    local count = 0
    for _, spells in pairs(self.rows) do for _ in pairs(spells) do count = count + 1 end end
    return count
end
local Addon = Actually
local ARC = Addon.Modules.RaidCooldowns
local AlertUI = ARC:NewModule("AlertUI")

local MIN_SCALE = 0.60
local MAX_SCALE = 1.80
local DEFAULT_POINT = "CENTER"
local DEFAULT_X = 0
local DEFAULT_Y = 140
local DEFAULT_SOUND = "raid_warning"

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
    { key = "alliance_bell", label = "Alliance Bell",
        path = "Sound\\Doodad\\BellTollAlliance.wav" },
    { key = "horde_bell", label = "Horde Bell",
        path = "Sound\\Doodad\\BellTollHorde.wav" },
    { key = "night_elf_bell", label = "Night Elf Bell",
        path = "Sound\\Doodad\\BellTollNightElf.wav" },
    { key = "boat_horn", label = "Boat Horn",
        path = "Sound\\Doodad\\BoatDockedWarning.wav" },
}

local SOUND_BY_KEY = {}
for _, option in ipairs(SOUND_OPTIONS) do SOUND_BY_KEY[option.key] = option end

local function clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function roundScale(value)
    return math.floor(clamp(value, MIN_SCALE, MAX_SCALE) * 20 + 0.5) / 20
end

local function cacheTips()
    return Addon.CacheTips
end

function AlertUI:GetProfile()
    if not ARC.db or not ARC.db.profile then return nil end
    local root = ARC.db.profile
    root.alertUI = type(root.alertUI) == "table" and root.alertUI or {}
    local profile = root.alertUI

    -- Preserve the old single-request position the first time the shared alert
    -- setting is introduced. Bundle and single requests now use one anchor.
    if profile.version ~= 1 then
        local legacy = type(root.requestUI) == "table" and root.requestUI or nil
        profile.point = legacy and legacy.point or profile.point or DEFAULT_POINT
        profile.x = legacy and tonumber(legacy.x) or tonumber(profile.x) or DEFAULT_X
        profile.y = legacy and tonumber(legacy.y) or tonumber(profile.y) or DEFAULT_Y
        profile.scale = roundScale(profile.scale or 1)
        profile.version = 1
    end

    profile.point = profile.point or DEFAULT_POINT
    profile.x = tonumber(profile.x) or DEFAULT_X
    profile.y = tonumber(profile.y) or DEFAULT_Y
    profile.scale = roundScale(profile.scale or 1)
    if profile.soundEnabled == nil then
        profile.soundEnabled = not (root.requests and root.requests.sound == false)
    end
    if not SOUND_BY_KEY[profile.sound] then profile.sound = DEFAULT_SOUND end
    if profile.bounce == nil then profile.bounce = false end
    if profile.glow == nil then profile.glow = true end
    if profile.pulse == nil then profile.pulse = true end
    return profile
end

function AlertUI:GetSoundOptions()
    return SOUND_OPTIONS
end

function AlertUI:GetSound()
    local profile = self:GetProfile()
    return profile and profile.sound or DEFAULT_SOUND
end

function AlertUI:GetSoundLabel()
    local option = SOUND_BY_KEY[self:GetSound()] or SOUND_BY_KEY[DEFAULT_SOUND]
    return option.label
end

function AlertUI:IsSoundEnabled()
    local profile = self:GetProfile()
    return profile and profile.soundEnabled ~= false or false
end

function AlertUI:SetSoundEnabled(enabled)
    local profile = self:GetProfile()
    if not profile then return end
    profile.soundEnabled = enabled == true
    local tips = cacheTips()
    if tips and tips.RefreshARCAlertControls then tips:RefreshARCAlertControls() end
end

function AlertUI:SetSound(key, preview)
    local profile = self:GetProfile()
    if not profile or not SOUND_BY_KEY[key] then return false end
    profile.sound = key
    local tips = cacheTips()
    if tips and tips.RefreshARCAlertControls then tips:RefreshARCAlertControls() end
    if preview then self:PlaySound(true) end
    return true
end

function AlertUI:PlaySound(force)
    local profile = self:GetProfile()
    if not profile or (not force and profile.soundEnabled == false) then return false end
    local option = SOUND_BY_KEY[profile.sound] or SOUND_BY_KEY[DEFAULT_SOUND]
    if not option or not PlaySoundFile then return false end
    PlaySoundFile(option.path)
    return true
end

function AlertUI:GetEffect(effect)
    local profile = self:GetProfile()
    return profile and profile[effect] == true or false
end

function AlertUI:SetEffect(effect, enabled)
    if effect ~= "bounce" and effect ~= "glow" and effect ~= "pulse" then return false end
    local profile = self:GetProfile()
    if not profile then return false end
    profile[effect] = enabled == true
    self:RefreshVisualOptions()
    local tips = cacheTips()
    if tips and tips.RefreshARCAlertControls then tips:RefreshARCAlertControls() end
    return true
end

function AlertUI:GetScale()
    local profile = self:GetProfile()
    return profile and profile.scale or 1
end

function AlertUI:ApplyScale(frame, pulse)
    if not frame then return end
    frame:SetScale(self:GetScale() * (tonumber(pulse) or 1))
end

function AlertUI:ApplyBasePosition(frame, stackIndex)
    local profile = self:GetProfile()
    if not frame or not profile then return end
    local offset = math.max(0, (tonumber(stackIndex) or 1) - 1) * 285 * profile.scale
    local y = profile.y - offset
    if string.find(profile.point or "", "BOTTOM", 1, true) then y = profile.y + offset end
    frame:ClearAllPoints()
    frame:SetPoint(profile.point, UIParent, profile.point, profile.x, y)
end

function AlertUI:Arrange()
    local visibleIndex = 0
    for _, frame in ipairs(self.frames or {}) do
        if frame:IsShown() then
            visibleIndex = visibleIndex + 1
            self:ApplyBasePosition(frame, visibleIndex)
        else
            self:ApplyBasePosition(frame, 1)
        end
        self:ApplyScale(frame)
    end
end

function AlertUI:SetScale(value)
    local profile = self:GetProfile()
    if not profile then return end
    profile.scale = roundScale(value)
    self:Arrange()
    if self.preview and self.preview:IsShown() then
        self:ApplyBasePosition(self.preview, 1)
        self:ApplyScale(self.preview)
    end
    local tips = cacheTips()
    if tips and tips.RefreshARCAlertControls then tips:RefreshARCAlertControls() end
end

function AlertUI:SavePosition(frame)
    local profile = self:GetProfile()
    if not profile or not frame then return end
    local point, _, _, x, y = frame:GetPoint(1)
    profile.point = point or DEFAULT_POINT
    profile.x = tonumber(x) or DEFAULT_X
    profile.y = tonumber(y) or DEFAULT_Y
    self:Arrange()
    if self.preview and self.preview:IsShown() then self:ApplyBasePosition(self.preview, 1) end
    local tips = cacheTips()
    if tips and tips.RefreshARCAlertControls then tips:RefreshARCAlertControls() end
end

function AlertUI:Reset()
    local profile = self:GetProfile()
    if not profile then return end
    profile.point = DEFAULT_POINT
    profile.x = DEFAULT_X
    profile.y = DEFAULT_Y
    profile.scale = 1
    profile.soundEnabled = true
    profile.sound = DEFAULT_SOUND
    profile.bounce = false
    profile.glow = true
    profile.pulse = true
    self:Arrange()
    if self.preview and self.preview:IsShown() then
        self:ApplyBasePosition(self.preview, 1)
        self:ApplyScale(self.preview)
    end
    local tips = cacheTips()
    if tips and tips.RefreshARCAlertControls then tips:RefreshARCAlertControls() end
end

function AlertUI:UpdateVisual(frame, now)
    if not frame then return end
    local profile = self:GetProfile()
    if not profile then return end
    now = tonumber(now) or 0

    local pulse = profile.pulse and (1 + 0.07 * math.sin(now * 8)) or 1
    self:ApplyScale(frame, pulse)

    local iconY = -5
    if profile.bounce then iconY = iconY + math.abs(math.sin(now * 5)) * 14 end
    frame.icon:ClearAllPoints()
    frame.icon:SetPoint("CENTER", frame, "CENTER", 0, iconY)

    if profile.glow then
        frame.glow:Show()
        local glowWave = 0.5 + 0.5 * math.sin(now * 6)
        -- UI-ActionButton-Border has substantial transparent padding. This
        -- larger texture size places its visible ring on the 128px icon edge.
        local glowSize = 220 + glowWave * 10
        frame.glow:SetWidth(glowSize)
        frame.glow:SetHeight(glowSize)
        frame.glow:SetAlpha(0.70 + glowWave * 0.30)
    else
        frame.glow:Hide()
    end
end

function AlertUI:RefreshVisualOptions()
    local now = GetTime and GetTime() or 0
    for _, frame in ipairs(self.frames or {}) do self:UpdateVisual(frame, now) end
    if self.preview then self:UpdateVisual(self.preview, now) end
end

local function createVisualFrame(name)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetWidth(520)
    frame:SetHeight(290)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100)
    frame:SetClampedToScreen(true)

    local glow = frame:CreateTexture(nil, "OVERLAY")
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetPoint("CENTER", frame, "CENTER", 0, -5)
    glow:SetWidth(225)
    glow:SetHeight(225)
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1.00, 0.72, 0.08, 1.00)
    frame.glow = glow

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\Spell_Holy_BorrowedTime")
    icon:SetPoint("CENTER", frame, "CENTER", 0, -5)
    icon:SetWidth(128)
    icon:SetHeight(128)
    icon:SetTexCoord(0.09, 0.91, 0.09, 0.91)
    frame.icon = icon
    glow:ClearAllPoints()
    glow:SetPoint("CENTER", icon, "CENTER", 0, 0)

    local heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    heading:SetPoint("BOTTOM", icon, "TOP", 0, 18)
    heading:SetWidth(510)
    heading:SetJustifyH("CENTER")
    heading:SetText("USE COOLDOWN NOW")
    heading:SetTextColor(1, 0.35, 0.05, 1)
    heading:SetShadowColor(0, 0, 0, 1)
    heading:SetShadowOffset(3, -3)
    frame.heading = heading

    local detail = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    detail:SetPoint("TOP", icon, "BOTTOM", 0, -9)
    detail:SetWidth(500)
    detail:SetJustifyH("CENTER")
    detail:SetTextColor(1, 0.82, 0.34)
    detail:SetShadowColor(0, 0, 0, 1)
    detail:SetShadowOffset(1, -1)
    frame.detail = detail

    local timer = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timer:SetPoint("TOP", detail, "BOTTOM", 0, -5)
    timer:SetWidth(480)
    timer:SetJustifyH("CENTER")
    timer:SetTextColor(1.00, 0.72, 0.20)
    timer:SetShadowColor(0, 0, 0, 1)
    timer:SetShadowOffset(1, -1)
    frame.timer = timer

    local wip = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    wip:SetPoint("TOP", frame, "TOP", 0, -5)
    wip:SetText("ARC - WORK IN PROGRESS")
    wip:SetTextColor(1, 0.63, 0.10)
    wip:SetShadowColor(0, 0, 0, 1)
    wip:SetShadowOffset(1, -1)
    frame.wip = wip

    return frame
end

function AlertUI:CreateAlertFrame(name)
    local frame = createVisualFrame(name)

    frame:SetScript("OnShow", function()
        frame:SetAlpha(1)
        AlertUI:Arrange()
    end)
    frame:SetScript("OnHide", function()
        frame.arcDeadline = nil
        frame:SetAlpha(1)
        AlertUI:Arrange()
    end)
    frame:SetScript("OnUpdate", function(alertFrame)
        if not alertFrame:IsShown() then return end
        local now = GetTime and GetTime() or 0
        AlertUI:UpdateVisual(alertFrame, now)
        local remaining = alertFrame.arcDeadline and (alertFrame.arcDeadline - now) or nil
        alertFrame:SetAlpha(remaining and remaining < 0.75 and math.max(0, remaining / 0.75) or 1)
    end)

    self.frames = self.frames or {}
    table.insert(self.frames, frame)
    self:ApplyBasePosition(frame, 1)
    self:ApplyScale(frame)
    frame:Hide()
    return frame
end

function AlertUI:CreatePreview()
    if self.preview then return end
    local frame = createVisualFrame("ActuallyARCAlertPlacementFrame")
    frame.icon:SetTexture("Interface\\Icons\\Spell_Holy_BorrowedTime")
    frame.heading:SetText("DRAG ARC ALERT")
    frame.detail:SetText("Cooldown requests will appear here")
    frame.timer:SetText("Adjust size in Cache Tips")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(owner) owner:StartMoving() end)
    frame:SetScript("OnDragStop", function(owner)
        owner:StopMovingOrSizing()
        AlertUI:SavePosition(owner)
    end)
    frame:SetScript("OnUpdate", function(owner)
        if owner:IsShown() then AlertUI:UpdateVisual(owner, GetTime and GetTime() or 0) end
    end)
    self.preview = frame
    self:ApplyBasePosition(frame, 1)
    self:ApplyScale(frame)
    frame:Hide()
end

function AlertUI:IsPositioning()
    return self.preview and self.preview:IsShown() or false
end

function AlertUI:StartPositioning()
    self:CreatePreview()
    self:ApplyBasePosition(self.preview, 1)
    self:ApplyScale(self.preview)
    self.preview:SetAlpha(1)
    self.preview:Show()
    local tips = cacheTips()
    if tips and tips.RefreshARCAlertControls then tips:RefreshARCAlertControls() end
end

function AlertUI:StopPositioning()
    if self.preview then self.preview:Hide() end
    local tips = cacheTips()
    if tips and tips.RefreshARCAlertControls then tips:RefreshARCAlertControls() end
end

function AlertUI:TogglePositioning()
    if self:IsPositioning() then self:StopPositioning() else self:StartPositioning() end
    return self:IsPositioning()
end

function AlertUI:Initialize()
    if self.initialized then return end
    self.frames = {}
    self:GetProfile()
    self:CreatePreview()
    self:RefreshVisualOptions()
    self.initialized = true
end
