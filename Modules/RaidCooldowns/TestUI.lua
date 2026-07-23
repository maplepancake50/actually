local ARC = Actually.Modules.RaidCooldowns
local TestUI = ARC:NewModule("TestUI")

local ROW_HEIGHT = 28
local MAX_ROWS = 30
local MIN_SCALE = 0.65
local MAX_SCALE = 1.80

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function cursorX()
    local x = GetCursorPosition and GetCursorPosition() or 0
    local scale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    return x / math.max(scale, 0.01)
end

local function savePosition(frame, profile)
    local point, _, _, x, y = frame:GetPoint(1)
    profile.point, profile.x, profile.y = point, x, y
end

function TestUI:ApplyLayoutLock()
    local frame, profile = self.frame, ARC.db.profile.testUI
    if not frame then return end
    local locked = profile.locked ~= false
    frame.lock:SetText(locked and "Unlock" or "Lock")
    if locked then
        frame.resizeGrip:Hide()
        frame.unlockHint:Hide()
        frame:SetBackdropColor(0.02, 0.035, 0.055, 0.58)
        frame:SetBackdropBorderColor(0.12, 0.34, 0.46, 0.85)
    else
        frame.resizeGrip:Show()
        frame.unlockHint:Show()
        frame:SetBackdropColor(0.03, 0.055, 0.085, 0.78)
        frame:SetBackdropBorderColor(0.24, 0.86, 1.00, 1)
    end
end

function TestUI:ToggleLayoutLock()
    local profile = ARC.db.profile.testUI
    profile.locked = not (profile.locked ~= false)
    self:ApplyLayoutLock()
end

function TestUI:BeginScaleResize()
    local frame, profile = self.frame, ARC.db.profile.testUI
    if profile.locked ~= false then return end
    local grip = frame.resizeGrip
    grip.startCursorX = cursorX()
    grip.startScale = frame:GetScale()
    grip:SetScript("OnUpdate", function()
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            TestUI:EndScaleResize()
            return
        end
        local nextScale = grip.startScale
            + ((cursorX() - grip.startCursorX) / math.max(frame:GetWidth(), 1))
        nextScale = clamp(nextScale, MIN_SCALE, MAX_SCALE)
        frame:SetScale(nextScale)
        profile.scale = nextScale
        frame.scaleText:SetText(string.format("%d%%", math.floor(nextScale * 100 + 0.5)))
    end)
end

function TestUI:EndScaleResize()
    if self.frame and self.frame.resizeGrip then self.frame.resizeGrip:SetScript("OnUpdate", nil) end
end

local function formatCooldown(row)
    if row.stale then return "STALE", 0.65, 0.65, 0.65 end
    if row.ready then return "READY", 0.35, 1.0, 0.35 end
    local remaining = math.max(0, row.remaining or 0)
    if remaining >= 60 then
        return string.format("%d:%02d", math.floor(remaining / 60), math.floor(remaining % 60)), 1.0, 0.82, 0.2
    end
    return tostring(math.ceil(remaining)), 1.0, 0.45, 0.2
end

function TestUI:CreateRow(index)
    local row = CreateFrame("Frame", nil, self.frame)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 8, -25 - ((index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -8, -25 - ((index - 1) * ROW_HEIGHT))

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(24)
    row.icon:SetHeight(24)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)

    row.action = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.action:SetWidth(66)
    row.action:SetHeight(20)
    row.action:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.action:SetScript("OnClick", function()
        local data = row.data
        if not data then return end
        if ARC.Requests:IsOutgoingTarget(data.playerKey, data.spellID) then
            ARC.Requests:CancelOutgoing("cancelled by coordinator")
        else
            ARC.Requests:Start(data.playerKey, data.spellID)
        end
    end)

    row.cooldown = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.cooldown:SetWidth(46)
    row.cooldown:SetJustifyH("RIGHT")
    row.cooldown:SetPoint("RIGHT", row.action, "LEFT", -6, 0)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetJustifyH("LEFT")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
    row.label:SetPoint("RIGHT", row.cooldown, "LEFT", -7, 0)

    self.widgets[index] = row
    return row
end

function TestUI:Initialize()
    self.widgets = {}
    local profile = ARC.db.profile.testUI
    local frame = CreateFrame("Frame", "ActuallyARCTestFrame", UIParent)
    frame:SetWidth(420)
    frame:SetHeight(51)
    frame:SetPoint(profile.point or "CENTER", UIParent, profile.point or "CENTER", profile.x or 0, profile.y or 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetScale(clamp(tonumber(profile.scale) or 1, MIN_SCALE, MAX_SCALE))
    frame:SetScript("OnDragStart", function(self)
        if profile.locked == false then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition(self, profile)
    end)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    frame.title:SetText("Actually Raid Cooldowns")

    frame.config = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.config:SetWidth(52)
    frame.config:SetHeight(18)
    frame.config:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -7, -5)
    frame.config:SetText("Config")
    frame.config:SetScript("OnClick", function()
        if ARC.SpellConfig and ARC.SpellConfig.Show then
            ARC.SpellConfig:Show()
        else
            ARC:Print("SpellConfig unavailable; fully restart the game client")
        end
    end)

    frame.bundles = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.bundles:SetWidth(60)
    frame.bundles:SetHeight(18)
    frame.bundles:SetPoint("RIGHT", frame.config, "LEFT", -4, 0)
    frame.bundles:SetText("Bundles")
    frame.bundles:SetScript("OnClick", function()
        if ARC.BundleConfig and ARC.BundleConfig.Show then
            ARC.BundleConfig:Show()
        else
            ARC:Print("BundleConfig unavailable; fully restart the game client")
        end
    end)
    frame.bundles:SetScript("OnEnter", function(button)
        if ARC.BundleConfig and ARC.BundleConfig.ShowBundleTooltip then
            ARC.BundleConfig:ShowBundleTooltip(button)
        end
    end)
    frame.bundles:SetScript("OnLeave", function()
        if ARC.BundleConfig and ARC.BundleConfig.HideBundleTooltip then
            ARC.BundleConfig:HideBundleTooltip()
        end
    end)

    frame.lock = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.lock:SetWidth(52)
    frame.lock:SetHeight(18)
    frame.lock:SetPoint("RIGHT", frame.bundles, "LEFT", -4, 0)
    frame.lock:SetScript("OnClick", function() self:ToggleLayoutLock() end)

    frame.resizeGrip = CreateFrame("Button", nil, frame)
    frame.resizeGrip:SetWidth(18)
    frame.resizeGrip:SetHeight(18)
    frame.resizeGrip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    frame.resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    frame.resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    frame.resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    frame.resizeGrip:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    frame.resizeGrip:SetScript("OnMouseDown", function() self:BeginScaleResize() end)
    frame.resizeGrip:SetScript("OnMouseUp", function() self:EndScaleResize() end)

    frame.unlockHint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.unlockHint:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -21, 5)
    frame.unlockHint:SetText("drag window  |  resize")
    frame.unlockHint:SetTextColor(0.35, 0.80, 1.00)

    frame.scaleText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.scaleText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 7, 5)
    frame.scaleText:SetText(string.format("%d%%", math.floor(frame:GetScale() * 100 + 0.5)))

    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.empty:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -29)
    frame.empty:SetText("No registered cooldowns detected")

    self.frame = frame
    self:ApplyLayoutLock()
    ARC.Renderer.onReconcile = function(_, rows, groups) self:Refresh(rows, groups) end
    ARC.Renderer.onTick = function() self:Refresh(ARC.Renderer.rows, ARC.Renderer.orderedGroups) end
    if profile.shown == false then frame:Hide() else frame:Show() end
    self:Refresh(ARC.Renderer.rows, ARC.Renderer.orderedGroups)
end

function TestUI:Refresh(rows, groups)
    if not self.frame then return end
    local ordered = {}
    for _, spells in pairs(groups or {}) do
        for _, row in ipairs(spells) do table.insert(ordered, row) end
    end
    table.sort(ordered, function(left, right) return ARC.Renderer:CompareRows(left, right) end)

    local count = math.min(table.getn(ordered), MAX_ROWS)
    for index = 1, count do
        local data = ordered[index]
        local widget = self.widgets[index] or self:CreateRow(index)
        widget.data = data
        widget.icon:SetTexture(data.icon)
        widget.label:SetText(tostring(data.playerName) .. " - " .. tostring(data.spellName))
        local text, red, green, blue = formatCooldown(data)
        widget.cooldown:SetText(text)
        widget.cooldown:SetTextColor(red, green, blue)
        widget:SetAlpha((data.connected == false or data.dead) and 0.5 or 1.0)
        local outgoing = ARC.Requests.outgoing
        if ARC.Roster:IsLocalCoordinator() then
            widget.action:Show()
            if ARC.Requests:IsOutgoingTarget(data.playerKey, data.spellID) then
                widget.action:SetText("CANCEL")
                widget.action:Enable()
            elseif ARC.Bundles and ARC.Bundles:GetAssignment(data.playerKey, data.spellID) then
                widget.action:SetText("ASSIGNED")
                widget.action:Disable()
            elseif ARC.Bundles and ARC.Bundles.active then
                widget.action:SetText("BUNDLE")
                widget.action:Disable()
            elseif outgoing then
                widget.action:SetText("BUSY")
                widget.action:Disable()
            elseif ARC.Requests:IsEligible(data.playerKey, data.spellID) then
                widget.action:SetText("REQUEST")
                widget.action:Enable()
            else
                widget.action:SetText("WAIT")
                widget.action:Disable()
            end
        else
            widget.action:Hide()
        end
        widget:Show()
    end
    for index = count + 1, table.getn(self.widgets) do self.widgets[index]:Hide() end
    if count == 0 then self.frame.empty:Show() else self.frame.empty:Hide() end
    self.frame:SetHeight(42 + math.max(1, count) * ROW_HEIGHT)
end

function TestUI:Toggle()
    local shown = not self.frame:IsShown()
    ARC.db.profile.testUI.shown = shown
    if shown then self.frame:Show() else self.frame:Hide() end
    return shown
end
