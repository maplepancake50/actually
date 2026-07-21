Actually = Actually or {}
local Addon = Actually

local FapAlert = {}
Addon.FapAlert = FapAlert

local MESSAGE_KIND = "FAP"
local PROTOCOL = "1"
local DISPLAY_SECONDS = 4
local SEND_COOLDOWN = 2

local function Trim(value)
    return string.gsub(tostring(value or ""), "^%s*(.-)%s*$", "%1")
end

local function ShortName(value)
    return string.lower(string.match(Trim(value), "^([^%-]+)") or Trim(value))
end

local function InRaid()
    return GetNumRaidMembers and GetNumRaidMembers() > 0
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
    frame:SetHeight(300)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100)
    frame:Hide()

    local glow = frame:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture("Interface\\Cooldown\\star4")
    glow:SetPoint("CENTER", frame, "CENTER", 0, 20)
    glow:SetWidth(270)
    glow:SetHeight(270)
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.82, 0.12, 0.8)
    frame.glow = glow

    local iconBorder = frame:CreateTexture(nil, "ARTWORK")
    iconBorder:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    iconBorder:SetPoint("CENTER", frame, "CENTER", 0, 22)
    iconBorder:SetWidth(190)
    iconBorder:SetHeight(190)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    local itemTexture = GetItemIcon and GetItemIcon(5634)
    icon:SetTexture(itemTexture or "Interface\\Icons\\INV_Potion_04")
    icon:SetPoint("CENTER", frame, "CENTER", 0, 22)
    icon:SetWidth(164)
    icon:SetHeight(164)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    frame.icon = icon

    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    text:SetPoint("TOP", icon, "BOTTOM", 0, -15)
    text:SetText("USE FAP NOW")
    text:SetTextColor(1, 0.12, 0.05, 1)
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
        local pulse = 1 + 0.10 * math.sin(now * 9)
        alertFrame:SetScale(pulse)
        local alpha = alertFrame.remaining < 0.6 and (alertFrame.remaining / 0.6) or 1
        alertFrame:SetAlpha(alpha)
    end)

    self.frame = frame
end

function FapAlert:Show()
    self:Create()
    self.frame.remaining = DISPLAY_SECONDS
    self.frame:SetScale(1)
    self.frame:SetAlpha(1)
    self.frame:Show()

    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo and ChatTypeInfo.RAID_WARNING then
        RaidNotice_AddMessage(RaidWarningFrame, "USE FAP NOW", ChatTypeInfo.RAID_WARNING)
    end
    PlayAlertSound()
end

function FapAlert:Trigger()
    if not InRaid() then
        Addon:Print("FAP alert is raid-only. Join a raid before using /actually fap.")
        return false
    end
    if not SendAddonMessage and not (Addon.Sync and Addon.Sync.QueueMessage) then
        Addon:Print("This client cannot send addon messages.")
        return false
    end

    local now = GetTime and GetTime() or 0
    if now - (self.lastSentAt or -100) < SEND_COOLDOWN then
        Addon:Print("FAP alert is on a short cooldown.")
        return false
    end
    self.lastSentAt = now

    local token = tostring(time and time() or 0) .. "." .. tostring(math.random(100000, 999999))
    self.lastToken = token
    self:Show()
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
    return true
end

function FapAlert:HandleMessage(message, channel, sender)
    if channel ~= "RAID" or not IsCurrentRaidMember(sender) then return end

    local token = string.match(message or "", "^" .. MESSAGE_KIND .. "|" .. PROTOCOL .. "|([%w%.%-]+)$")
    if not token or token == self.lastToken then return end

    self.lastToken = token
    self:Show()
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
