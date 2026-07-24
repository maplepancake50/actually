local ARC = Actually.Modules.RaidCooldowns
local OfficerConfig = ARC:NewModule("OfficerConfig")

local FRAME_WIDTH = 1082
local FRAME_HEIGHT = 696
local HEADER_HEIGHT = 82
local PANE_HEIGHT = 602

local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function setBackdrop(frame, background, border)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(background[1], background[2], background[3], background[4] or 1)
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function savePosition(frame, profile)
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    profile.point = point
    profile.relativePoint = relativePoint
    profile.x = x
    profile.y = y
end

local function getFitScale(profile)
    local requested = clamp(tonumber(profile.scale) or 1, 0.65, 1.15)
    if not UIParent or not UIParent.GetWidth or not UIParent.GetHeight then
        return requested
    end
    local availableWidth = math.max(1, (UIParent:GetWidth() or FRAME_WIDTH) - 30)
    local availableHeight = math.max(1, (UIParent:GetHeight() or FRAME_HEIGHT) - 30)
    local fit = math.min(1, availableWidth / FRAME_WIDTH, availableHeight / FRAME_HEIGHT)
    return math.max(0.65, math.min(requested, fit))
end

local function preparePane(frame, parent, point, relativePoint, x)
    frame:SetParent(parent)
    frame:ClearAllPoints()
    frame:SetPoint(point, parent, relativePoint, x, -HEADER_HEIGHT)
    frame:SetScale(1)
    frame:SetHeight(PANE_HEIGHT)
    frame:SetMovable(false)
    frame:SetClampedToScreen(false)
    frame:SetScript("OnDragStart", nil)
    frame:SetScript("OnDragStop", nil)
    frame:SetFrameLevel(parent:GetFrameLevel() + 2)
    if frame.dragBar then frame.dragBar:Hide() end
    if frame.close then frame.close:Hide() end
    if frame.lock then frame.lock:Hide() end
    if frame.resizeGrip then frame.resizeGrip:Hide() end
    if frame.scaleText then frame.scaleText:Hide() end
end

function OfficerConfig:Refresh()
    if ARC.BundleConfig and ARC.BundleConfig.Refresh then ARC.BundleConfig:Refresh() end
    if ARC.CommanderConfig and ARC.CommanderConfig.Refresh then
        ARC.CommanderConfig:Refresh()
    end
end

function OfficerConfig:Initialize()
    local bundleFrame = ARC.BundleConfig and ARC.BundleConfig.frame
    local commandFrame = ARC.CommanderConfig and ARC.CommanderConfig.frame
    if not bundleFrame or not commandFrame then
        error("bundle and command editors must initialize before OfficerConfig")
    end

    local profile = ARC.db.profile.officerConfigUI
    local frame = CreateFrame("Frame", "ActuallyARCOfficerConfigFrame", UIParent)
    frame:SetWidth(FRAME_WIDTH)
    frame:SetHeight(FRAME_HEIGHT)
    frame:SetPoint(
        profile.point or "CENTER",
        UIParent,
        profile.relativePoint or profile.point or "CENTER",
        profile.x or 0,
        profile.y or 0)
    frame:SetScale(getFitScale(profile))
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    setBackdrop(frame, { 0.012, 0.022, 0.034, 0.995 }, { 0.20, 0.70, 0.96, 1 })
    self.frame = frame

    frame.dragBar = CreateFrame("Frame", nil, frame)
    frame.dragBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    frame.dragBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -42, -4)
    frame.dragBar:SetHeight(50)
    frame.dragBar:EnableMouse(true)
    frame.dragBar:RegisterForDrag("LeftButton")
    frame.dragBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame.dragBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        savePosition(frame, profile)
    end)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -12)
    frame.title:SetText("Actually Raid Cooldowns - Officer Configuration - "
        .. ARC.Constants.WIP_TEXT)
    frame.title:SetTextColor(0.92, 0.96, 1.00)

    frame.subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -5)
    frame.subtitle:SetText(
        "1. Build reusable cooldown bundles    2. Assemble bundles into commander buttons")
    frame.subtitle:SetTextColor(0.48, 0.72, 0.84)

    frame.behavior = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.behavior:SetPoint("TOPLEFT", frame.subtitle, "BOTTOMLEFT", 0, -5)
    frame.behavior:SetWidth(FRAME_WIDTH - 32)
    frame.behavior:SetJustifyH("LEFT")
    frame.behavior:SetText(
        "Choose spells; ARC chooses ready players and queues multiple prompts per player. "
        .. "By default, a command advances after any successful cooldown and loops after its final stage.")
    frame.behavior:SetTextColor(0.72, 0.80, 0.88)

    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
    frame.close:SetScript("OnClick", function() OfficerConfig:Hide() end)

    preparePane(bundleFrame, frame, "TOPLEFT", "TOPLEFT", 8)
    preparePane(commandFrame, frame, "TOPRIGHT", "TOPRIGHT", -8)

    bundleFrame.title:SetText("1. Cooldown Bundle Builder")
    bundleFrame.subtitle:SetText(
        "Choose cooldowns; ARC selects ready players and keeps this prompt order")
    commandFrame.title:SetText("2. Commander Button Builder")
    commandFrame.subtitle:SetText(
        "Choose bundle stages in click order; changes remain drafts until Save")

    commandFrame:SetHeight(PANE_HEIGHT)
    ARC.CommanderConfig.listPanel:SetHeight(380)

    frame.divider = frame:CreateTexture(nil, "ARTWORK")
    frame.divider:SetWidth(1)
    frame.divider:SetPoint("TOP", frame, "TOP", -6, -88)
    frame.divider:SetPoint("BOTTOM", frame, "BOTTOM", -6, 16)
    frame.divider:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.divider:SetVertexColor(0.20, 0.56, 0.78, 0.55)

    bundleFrame:Show()
    commandFrame:Show()
    frame:Hide()
end

function OfficerConfig:Show(focus)
    if not ARC:RequireConfigurationAuthority() then return false end
    self.focus = focus or self.focus or "plans"
    if ARC.BundleConfig and ARC.BundleConfig.frame then ARC.BundleConfig.frame:Show() end
    if ARC.CommanderConfig and ARC.CommanderConfig.frame then
        ARC.CommanderConfig.frame:Show()
    end
    self:Refresh()
    self.frame:Show()
    return true
end

function OfficerConfig:Hide()
    if not self.frame then return end
    if ARC.BundleConfig and ARC.BundleConfig.nameBox then
        ARC.BundleConfig.nameBox:ClearFocus()
    end
    if ARC.CommanderConfig and ARC.CommanderConfig.nameBox then
        ARC.CommanderConfig.nameBox:ClearFocus()
    end
    self.frame:Hide()
end

function OfficerConfig:Toggle(focus)
    if self.frame:IsShown() then
        self:Hide()
        return false
    end
    return self:Show(focus)
end
