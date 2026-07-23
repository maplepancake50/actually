local Addon = Actually
local RaidCC = Addon.Modules.RaidCC

RaidCC.Options = RaidCC.Options or {}
local Options = RaidCC.Options

local TOOLTIP = "While in a raid, enables friendly and enemy player nameplates, displays raid members as names only, and marks tracked crowd control."

function Options:Refresh()
    if self.checkbox and RaidCC.db then
        self.checkbox:SetChecked(RaidCC.db.enabled == true)
    end
end

function Options:Create()
    if self.panel then
        return
    end

    local panel = CreateFrame("Frame", "ActuallyRaidCCOptionsPanel")
    panel.name = "Actually Raid CC"
    self.panel = panel

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Actually Raid CC")

    local checkbox = CreateFrame("CheckButton", "ActuallyRaidCCEnableCheckbox", panel, "InterfaceOptionsCheckButtonTemplate")
    checkbox:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -2, -16)
    _G[checkbox:GetName() .. "Text"]:SetText("Enable Raid CC Mode")
    checkbox.tooltipText = TOOLTIP
    checkbox:SetScript("OnClick", function(self)
        if not RaidCC.db then
            return
        end
        RaidCC.db.enabled = self:GetChecked() and true or false
        RaidCC:RefreshMode()
        RaidCC:ReevaluateVisiblePlates()
    end)
    self.checkbox = checkbox

    panel:SetScript("OnShow", function()
        Options:Refresh()
    end)

    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

Options:Create()
