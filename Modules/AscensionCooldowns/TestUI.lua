local ACD = Actually.Modules.AscensionCooldowns
local TestUI = ACD:NewModule("TestUI")

local ROW_HEIGHT = 28
local MAX_ROWS = 30

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

    row.cooldown = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.cooldown:SetWidth(46)
    row.cooldown:SetJustifyH("RIGHT")
    row.cooldown:SetPoint("RIGHT", row, "RIGHT", 0, 0)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetJustifyH("LEFT")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
    row.label:SetPoint("RIGHT", row.cooldown, "LEFT", -7, 0)

    self.widgets[index] = row
    return row
end

function TestUI:Initialize()
    self.widgets = {}
    local profile = ACD.db.profile.testUI
    local frame = CreateFrame("Frame", "ActuallyACDTestFrame", UIParent)
    frame:SetWidth(285)
    frame:SetHeight(51)
    frame:SetPoint(profile.point or "CENTER", UIParent, profile.point or "CENTER", profile.x or 0, profile.y or 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.03, 0.05, 0.08, 0.92)
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        profile.point, profile.x, profile.y = point, x, y
    end)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    frame.title:SetText("Actually Cooldowns (test)")

    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.empty:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -29)
    frame.empty:SetText("No registered cooldowns detected")

    self.frame = frame
    ACD.Renderer.onReconcile = function(_, rows, groups) self:Refresh(rows, groups) end
    ACD.Renderer.onTick = function() self:Refresh(ACD.Renderer.rows, ACD.Renderer.orderedGroups) end
    if profile.shown == false then frame:Hide() else frame:Show() end
    self:Refresh(ACD.Renderer.rows, ACD.Renderer.orderedGroups)
end

function TestUI:Refresh(rows, groups)
    if not self.frame then return end
    local ordered = {}
    for _, spells in pairs(groups or {}) do
        for _, row in ipairs(spells) do table.insert(ordered, row) end
    end
    table.sort(ordered, function(left, right) return ACD.Renderer:CompareRows(left, right) end)

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
        widget:Show()
    end
    for index = count + 1, table.getn(self.widgets) do self.widgets[index]:Hide() end
    if count == 0 then self.frame.empty:Show() else self.frame.empty:Hide() end
    self.frame:SetHeight(27 + math.max(1, count) * ROW_HEIGHT)
end

function TestUI:Toggle()
    local shown = not self.frame:IsShown()
    ACD.db.profile.testUI.shown = shown
    if shown then self.frame:Show() else self.frame:Hide() end
    return shown
end
