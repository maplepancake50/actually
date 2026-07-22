Actually = Actually or {}
local Addon = Actually

local FapAlert = {}
Addon.FapAlert = FapAlert

local MESSAGE_KIND = "FAP"
local PROTOCOL = "1"
local DISPLAY_SECONDS = 3
local COOLDOWN_SECONDS = 60

local function Trim(value)
    return string.gsub(tostring(value or ""), "^%s*(.-)%s*$", "%1")
end

local function ShortName(value)
    return string.lower(string.match(Trim(value), "^([^%-]+)") or Trim(value))
end

local function InRaid()
    return GetNumRaidMembers and GetNumRaidMembers() > 0
end

local function Now()
    return time and time() or (GetTime and GetTime() or 0)
end

local function IsOfficer(identity)
    if not Addon.Official or not Addon.Official.IsOfficer then return false end
    if Addon.Official:IsOfficer(identity) == true then return true end
    if not identity or string.find(tostring(identity), "-", 1, true) then return false end

    -- CHAT_MSG_ADDON may omit the realm on older clients, while actually's
    -- authority list stores the canonical Name-Realm identity.
    local realm = GetRealmName and string.gsub(Trim(GetRealmName()), "%s+", "") or ""
    return realm ~= "" and Addon.Official:IsOfficer(Trim(identity) .. "-" .. realm) == true
end

local function IsCurrentRaidMember(name)
    local wanted = ShortName(name)
    if wanted == "" or not InRaid() then return false end

    for index = 1, GetNumRaidMembers() do
        local raidName = GetRaidRosterInfo(index)
        if raidName and ShortName(raidName) == wanted then
            return true
        end
    end
    return false
end

local function PlayAlertSound()
    -- Custom procedural wind swish shipped with the addon. Older clients do
    -- not reliably report a missing file, so PlaySound remains the API fallback.
    if PlaySoundFile then
        local played = pcall(PlaySoundFile,
            "Interface\\AddOns\\actually\\Sounds\\FapWindWhoosh.wav")
        if played then return end
    end
    if PlaySound then
        pcall(PlaySound, "RaidWarning")
    end
end

function FapAlert:Create()
    if self.frame then return end

    local frame = CreateFrame("Frame", "ActuallyFapAlertFrame", UIParent)
    frame:SetWidth(360)
    frame:SetHeight(250)
    frame:SetPoint("RIGHT", UIParent, "RIGHT", -240, 170)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100)
    frame:Hide()

    local glow = frame:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture("Interface\\Cooldown\\star4")
    glow:SetPoint("CENTER", frame, "CENTER", 0, -5)
    glow:SetWidth(190)
    glow:SetHeight(190)
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.82, 0.12, 0.8)
    frame.glow = glow

    local icon = frame:CreateTexture(nil, "ARTWORK")
    local itemTexture = GetItemIcon and GetItemIcon(5634)
    icon:SetTexture(itemTexture or "Interface\\Icons\\INV_Potion_04")
    icon:SetPoint("CENTER", frame, "CENTER", 0, -5)
    icon:SetWidth(128)
    icon:SetHeight(128)
    icon:SetTexCoord(0.09, 0.91, 0.09, 0.91)
    frame.icon = icon

    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    text:SetPoint("BOTTOM", icon, "TOP", 0, 18)
    text:SetText("USE FAP NOW")
    text:SetTextColor(1, 0.35, 0.05, 1)
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(3, -3)
    frame.text = text

    frame:SetScript("OnUpdate", function(alertFrame, elapsed)
        alertFrame.remaining = (alertFrame.remaining or 0) - elapsed
        if alertFrame.remaining <= 0 then
            alertFrame:Hide()
            return
        end

        local now = GetTime and GetTime() or 0
        local pulse = 1 + 0.07 * math.sin(now * 8)
        alertFrame:SetScale(pulse)
        local alpha = alertFrame.remaining < 0.75 and (alertFrame.remaining / 0.75) or 1
        alertFrame:SetAlpha(alpha)
    end)

    self.frame = frame
end

function FapAlert:IsEnabled()
    return not (Addon.db and Addon.db.fapAlert and Addon.db.fapAlert.enabled == false)
end

function FapAlert:SetEnabled(enabled, preview)
    Addon.db.fapAlert = type(Addon.db.fapAlert) == "table" and Addon.db.fapAlert or {}
    Addon.db.fapAlert.enabled = enabled == true

    if not enabled and self.frame then
        self.frame:Hide()
    elseif enabled and preview then
        self:Show(true)
    end

    if Addon.CacheTips and Addon.CacheTips.RefreshFapToggle then
        Addon.CacheTips:RefreshFapToggle()
    end
end

function FapAlert:GetCooldownRemaining()
    local untilTime = Addon.db and Addon.db.fapAlert
        and tonumber(Addon.db.fapAlert.cooldownUntil) or 0
    return math.max(0, math.ceil(untilTime - Now()))
end

function FapAlert:StartCooldown()
    Addon.db.fapAlert = type(Addon.db.fapAlert) == "table" and Addon.db.fapAlert or {}
    Addon.db.fapAlert.cooldownUntil = Now() + COOLDOWN_SECONDS
end

function FapAlert:Show(force)
    if not force and not self:IsEnabled() then return false end
    self:Create()
    self.frame.remaining = DISPLAY_SECONDS
    self.frame:SetScale(1)
    self.frame:SetAlpha(1)
    self.frame:Show()

    PlayAlertSound()
    return true
end

function FapAlert:Trigger()
    if not InRaid() then
        Addon:Print("FAP alert is raid-only. Join a raid before using /actually fap.")
        return false
    end
    if not IsOfficer() then
        Addon:Print("Only an actually officer can trigger the FAP alert.")
        return false
    end
    if not SendAddonMessage and not (Addon.Sync and Addon.Sync.QueueMessage) then
        Addon:Print("This client cannot send addon messages.")
        return false
    end

    local remaining = self:GetCooldownRemaining()
    if remaining > 0 then
        Addon:Print("FAP alert is on cooldown for " .. tostring(remaining) .. " more seconds.")
        return false
    end

    local token = tostring(Now()) .. "." .. tostring(math.random(100000, 999999))
    local message = MESSAGE_KIND .. "|" .. PROTOCOL .. "|" .. token
    local sent
    if Addon.Sync and Addon.Sync.QueueMessage then
        sent = Addon.Sync:QueueMessage(message, "RAID", nil, "ALERT")
    else
        sent = pcall(SendAddonMessage, Addon.MESSAGE_PREFIX, message, "RAID")
    end
    if not sent then
        Addon:Print("Could not send the FAP alert to the raid.")
        return false
    end

    self.lastToken = token
    self:StartCooldown()
    if self:IsEnabled() then self:Show() end
    Addon:Print("FAP alert sent. Raid cooldown started for 60 seconds.")
    return true
end

function FapAlert:HandleMessage(message, channel, sender)
    if channel ~= "RAID" or not IsCurrentRaidMember(sender) then return end

    local token = string.match(message or "", "^" .. MESSAGE_KIND .. "|" .. PROTOCOL .. "|([%w%.%-]+)$")
    if not token or token == self.lastToken then return end
    if not IsOfficer(sender) then return end

    self.lastToken = token
    local remaining = self:GetCooldownRemaining()
    if remaining > 0 then
        Addon:Print("Ignored FAP alert from " .. tostring(sender)
            .. ": cooldown has " .. tostring(remaining) .. " seconds remaining.")
        return
    end

    self:StartCooldown()
    if self:IsEnabled() then self:Show() end
    Addon:Print("FAP alert triggered by " .. tostring(sender) .. ". Cooldown started for 60 seconds.")
end

function FapAlert:Initialize()
    if self.initialized then return end
    self.initialized = true
    self:Create()

    local events = CreateFrame("Frame")
    events:RegisterEvent("CHAT_MSG_ADDON")
    events:SetScript("OnEvent", function(_, event, prefix, message, channel, sender)
        if event == "CHAT_MSG_ADDON" and prefix == Addon.MESSAGE_PREFIX
            and string.sub(message or "", 1, string.len(MESSAGE_KIND) + 1) == MESSAGE_KIND .. "|" then
            FapAlert:HandleMessage(message, channel, sender)
        end
    end)
    self.eventFrame = events
end
