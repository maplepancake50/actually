Actually = Actually or {}
local Addon = Actually

local MinimapButton = {}
Addon.MinimapButton = MinimapButton

local RADIUS = 80

local function UpdatePosition(button)
    local angle = math.rad(Addon.db.minimap.angle or 225)
    local x = math.cos(angle) * RADIUS
    local y = math.sin(angle) * RADIUS

    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function UpdateDragPosition(button)
    local minimapX, minimapY = Minimap:GetCenter()
    local cursorX, cursorY = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cursorX = cursorX / scale
    cursorY = cursorY / scale

    Addon.db.minimap.angle = math.deg(math.atan2(cursorY - minimapY, cursorX - minimapX)) % 360
    UpdatePosition(button)
end

function MinimapButton:Create()
    if self.frame then
        return
    end

    local button = CreateFrame("Button", "ActuallyMinimapButton", Minimap)
    button:SetWidth(32)
    button:SetHeight(32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetWidth(24)
    icon:SetHeight(24)
    icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    icon:SetTexture("Interface\\AddOns\\actually\\Textures\\NerdFace")
    icon:SetTexCoord(0, 1, 0, 1)
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetWidth(53)
    border:SetHeight(53)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetWidth(32)
    highlight:SetHeight(32)
    highlight:SetPoint("CENTER")
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")

    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "LeftButton" then
            Addon:Toggle()
        end
    end)

    button:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", UpdateDragPosition)
        GameTooltip:Hide()
    end)

    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:UnlockHighlight()
        UpdatePosition(self)
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("actually", 1, 0.82, 0)
        GameTooltip:AddLine("Left-click to open or close.", 1, 1, 1)
        GameTooltip:AddLine("Drag to move around the minimap.", 0.55, 0.9, 0.55)
        GameTooltip:AddLine("Commands: /actually or /act", 0.55, 0.75, 1)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    self.frame = button
    UpdatePosition(button)
end
