local ARC = Actually.Modules.RaidCooldowns
local CommanderConfig = ARC:NewModule("CommanderConfig")

local PAGE_SIZE = 7
local ROW_HEIGHT = 48
local ROW_GAP = 3

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

local function trim(value)
    return string.gsub(string.gsub(tostring(value or ""), "^%s+", ""), "%s+$", "")
end

local function copyArray(source)
    local result = {}
    for _, value in ipairs(source or {}) do table.insert(result, value) end
    return result
end

local function newID()
    local epoch = time and time() or 0
    return "command:" .. tostring(epoch) .. ":" .. tostring(math.random(100000, 999999))
end

local function savePosition(frame, profile)
    local point, _, _, x, y = frame:GetPoint(1)
    profile.point, profile.x, profile.y = point, x, y
end

local function spellIconText(spellID)
    local icon = ARC.SpellInfo:ResolveSpellIcon(spellID)
    return icon and ("|T" .. tostring(icon) .. ":16:16:0:0|t ") or ""
end

function CommanderConfig:ShowBundleTooltip(owner, bundleID)
    if not GameTooltip or not owner or not bundleID then return end
    local bundle = ARC.Commander:FindBundle(bundleID)
    if not bundle then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:SetText(tostring(bundle.name or "Unnamed stage bundle"), 0.32, 0.86, 1.00)
    local order = self:GetSelectionIndex(bundleID)
    if order then
        GameTooltip:AddLine("Selected as stage " .. tostring(order), 0.35, 1.00, 0.35)
    else
        GameTooltip:AddLine("Not included in this command", 0.65, 0.70, 0.76)
    end
    GameTooltip:AddLine(" ")
    local count = 0
    for _, spellID in ipairs(bundle.spells or {}) do
        count = count + 1
        GameTooltip:AddLine(spellIconText(spellID)
            .. ARC.SpellInfo:ResolveSpellName(spellID), 0.92, 0.96, 1.00)
    end
    if count == 0 then GameTooltip:AddLine("No cooldowns saved", 1.00, 0.35, 0.35) end
    GameTooltip:Show()
end

function CommanderConfig:GetSelectionIndex(bundleID)
    for index, selectedID in ipairs(self.selectionOrder or {}) do
        if selectedID == bundleID then return index end
    end
end

function CommanderConfig:SyncEditingPlan()
    local plans = ARC.Commander:GetPlans()
    local plan = self.editingIndex and plans[self.editingIndex]
    if not plan then return false end
    if ARC.Commander.activePlanID == plan.id then
        ARC:Print("cancel the active command before changing its stages")
        return false
    end
    local stages = {}
    for _, bundleID in ipairs(self.selectionOrder or {}) do
        local bundle = ARC.Commander:FindBundle(bundleID)
        if bundle then
            table.insert(stages, {
                bundleID = bundle.id,
                name = tostring(bundle.name or "Cooldown stage"),
                spells = copyArray(bundle.spells),
            })
        end
    end
    plan.stages = stages
    ARC.Commander.progress[plan.id] = 1
    ARC.Commander:Refresh()
    return true
end

function CommanderConfig:SetSelected(bundleID, selected)
    if not bundleID then return end
    local plans = ARC.Commander:GetPlans()
    local editing = self.editingIndex and plans[self.editingIndex]
    if editing and ARC.Commander.activePlanID == editing.id then
        ARC:Print("cancel the active command before changing its stages")
        self:Refresh()
        return
    end
    if selected then
        self.selected[bundleID] = true
        if not self:GetSelectionIndex(bundleID) then table.insert(self.selectionOrder, bundleID) end
    else
        self.selected[bundleID] = nil
        for index = table.getn(self.selectionOrder), 1, -1 do
            if self.selectionOrder[index] == bundleID then table.remove(self.selectionOrder, index) end
        end
    end
    self:SyncEditingPlan()
    self:Refresh()
end

function CommanderConfig:MoveSelected(bundleID, direction)
    local current = self:GetSelectionIndex(bundleID)
    if not current then return end
    local target = math.max(1, math.min(table.getn(self.selectionOrder), current + direction))
    if target == current then return end
    self.selectionOrder[current], self.selectionOrder[target]
        = self.selectionOrder[target], self.selectionOrder[current]
    self:SyncEditingPlan()
    self:Refresh()
end

function CommanderConfig:NewPlan()
    self.editingIndex = nil
    self.selected = {}
    self.selectionOrder = {}
    self.nameBox:SetText("")
    self.nameBox:ClearFocus()
    self.page = 1
    self:Refresh()
end

function CommanderConfig:CreatePlan()
    local plans = ARC.Commander:GetPlans()
    if table.getn(plans) >= ARC.Constants.MAX_COMMAND_PLANS then
        ARC:Print("command bar supports at most "
            .. tostring(ARC.Constants.MAX_COMMAND_PLANS) .. " saved buttons")
        return nil
    end
    local index = table.getn(plans) + 1
    local plan = {
        id = newID(),
        name = "New Command " .. tostring(index),
        stages = {},
    }
    plans[index] = plan
    self.editingIndex = index
    self.selected = {}
    self.selectionOrder = {}
    self.nameBox:SetText(plan.name)
    self.nameBox:ClearFocus()
    self.page = 1
    ARC.Commander.progress[plan.id] = 1
    ARC.Commander:Refresh()
    self:Refresh()
    ARC:Print("created " .. plan.name .. "; tick a stage bundle to add it to the commander bar")
    return plan
end

function CommanderConfig:LoadPlan(index)
    local plans = ARC.Commander:GetPlans()
    if table.getn(plans) == 0 then self:NewPlan() return end
    index = math.max(1, math.min(index or 1, table.getn(plans)))
    local plan = plans[index]
    self.editingIndex = index
    self.selected = {}
    self.selectionOrder = {}
    for _, stage in ipairs(plan.stages or {}) do
        if stage.bundleID and ARC.Commander:FindBundle(stage.bundleID)
            and not self.selected[stage.bundleID] then
            self.selected[stage.bundleID] = true
            table.insert(self.selectionOrder, stage.bundleID)
        end
    end
    self.nameBox:SetText(plan.name or "")
    self.nameBox:ClearFocus()
    self.page = 1
    self:Refresh()
end

function CommanderConfig:SavePlan()
    if table.getn(self.selectionOrder) == 0 then
        ARC:Print("select at least one saved bundle as a command stage")
        return nil
    end
    local plans = ARC.Commander:GetPlans()
    local index = self.editingIndex
    if not index or not plans[index] then
        if table.getn(plans) >= ARC.Constants.MAX_COMMAND_PLANS then
            ARC:Print("command bar supports at most "
                .. tostring(ARC.Constants.MAX_COMMAND_PLANS) .. " saved buttons")
            return nil
        end
        index = table.getn(plans) + 1
        plans[index] = { id = newID() }
    end
    local plan = plans[index]
    local name = trim(self.nameBox:GetText())
    if name == "" then name = "Cooldown Command " .. tostring(index) end
    if string.len(name) > 48 then name = string.sub(name, 1, 48) end
    local stages = {}
    for _, bundleID in ipairs(self.selectionOrder) do
        local bundle = ARC.Commander:FindBundle(bundleID)
        if bundle then
            table.insert(stages, {
                bundleID = bundle.id,
                name = tostring(bundle.name or "Cooldown stage"),
                spells = copyArray(bundle.spells),
            })
        end
    end
    if table.getn(stages) == 0 then
        ARC:Print("none of the selected stage bundles still exist")
        return nil
    end
    plan.name, plan.stages = name, stages
    self.editingIndex = index
    self.nameBox:SetText(name)
    ARC.Commander.progress[plan.id] = 1
    ARC.Commander:Refresh()
    ARC:Print("saved command " .. name .. " with "
        .. tostring(table.getn(stages)) .. " stage" .. (table.getn(stages) == 1 and "" or "s"))
    self:Refresh()
    return plan
end

function CommanderConfig:DeletePlan()
    local plans = ARC.Commander:GetPlans()
    if not self.editingIndex or not plans[self.editingIndex] then return end
    local plan = plans[self.editingIndex]
    if ARC.Commander.activePlanID == plan.id then
        ARC:Print("cancel the active command before deleting it")
        return
    end
    ARC.Commander.progress[plan.id] = nil
    table.remove(plans, self.editingIndex)
    ARC:Print("deleted command " .. tostring(plan.name))
    ARC.Commander:Refresh()
    if table.getn(plans) > 0 then
        self:LoadPlan(math.min(self.editingIndex, table.getn(plans)))
    else
        self:NewPlan()
    end
end

function CommanderConfig:CreateRow(index)
    local row = CreateFrame("Frame", nil, self.listPanel)
    row:EnableMouse(true)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", self.listPanel, "TOPLEFT", 5,
        -5 - ((index - 1) * (ROW_HEIGHT + ROW_GAP)))
    row:SetPoint("TOPRIGHT", self.listPanel, "TOPRIGHT", -5,
        -5 - ((index - 1) * (ROW_HEIGHT + ROW_GAP)))
    setBackdrop(row, { 0.040, 0.052, 0.068, 0.88 }, { 0.14, 0.30, 0.40, 0.92 })
    row:SetScript("OnEnter", function()
        if row.bundleID then self:ShowBundleTooltip(row, row.bundleID) end
    end)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    row.check = CreateFrame("CheckButton", "ActuallyARCCommandStageCheck" .. tostring(index),
        row, "UICheckButtonTemplate")
    row.check:SetWidth(24)
    row.check:SetHeight(24)
    row.check:SetPoint("LEFT", row, "LEFT", 7, 0)
    row.check:SetScript("OnClick", function(button)
        if row.bundleID then self:SetSelected(row.bundleID, button:GetChecked() and true or false) end
    end)
    row.check:SetScript("OnEnter", function(button)
        if row.bundleID then self:ShowBundleTooltip(button, row.bundleID) end
    end)
    row.check:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(32)
    row.icon:SetHeight(32)
    row.icon:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.down = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.down:SetWidth(22)
    row.down:SetHeight(20)
    row.down:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.down:SetText("v")
    row.down:SetScript("OnClick", function()
        if row.bundleID then self:MoveSelected(row.bundleID, 1) end
    end)
    row.down:SetScript("OnEnter", function(button)
        if row.bundleID then self:ShowBundleTooltip(button, row.bundleID) end
    end)
    row.down:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    row.up = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.up:SetWidth(22)
    row.up:SetHeight(20)
    row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
    row.up:SetText("^")
    row.up:SetScript("OnClick", function()
        if row.bundleID then self:MoveSelected(row.bundleID, -1) end
    end)
    row.up:SetScript("OnEnter", function(button)
        if row.bundleID then self:ShowBundleTooltip(button, row.bundleID) end
    end)
    row.up:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
    row.name:SetPoint("RIGHT", row.up, "LEFT", -6, 0)
    row.name:SetHeight(16)
    row.name:SetJustifyH("LEFT")

    row.meta = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.meta:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 5)
    row.meta:SetPoint("RIGHT", row.up, "LEFT", -6, 0)
    row.meta:SetHeight(14)
    row.meta:SetJustifyH("LEFT")
    row.meta:SetTextColor(0.47, 0.68, 0.78)

    self.rows[index] = row
    return row
end

function CommanderConfig:Refresh()
    if not self.frame then return end
    local plans = ARC.Commander:GetPlans()
    local planCount = table.getn(plans)
    if self.editingIndex and not plans[self.editingIndex] then self.editingIndex = nil end
    if self.editingIndex then
        self.planText:SetText("Command " .. tostring(self.editingIndex) .. "/" .. tostring(planCount))
    else
        self.planText:SetText("New command  (" .. tostring(planCount) .. " saved)")
    end
    if self.editingIndex and self.editingIndex > 1 then self.previousPlan:Enable()
    else self.previousPlan:Disable() end
    if (self.editingIndex and self.editingIndex < planCount)
        or (not self.editingIndex and planCount > 0) then self.nextPlan:Enable()
    else self.nextPlan:Disable() end

    local bundles = ARC.Commander:GetBundles()
    local pages = math.max(1, math.ceil(table.getn(bundles) / PAGE_SIZE))
    self.page = math.max(1, math.min(self.page or 1, pages))
    local first = ((self.page - 1) * PAGE_SIZE) + 1
    for index = 1, PAGE_SIZE do
        local row = self.rows[index] or self:CreateRow(index)
        local bundle = bundles[first + index - 1]
        if bundle then
            row.bundleID = bundle.id
            local firstSpell = bundle.spells and bundle.spells[1]
            row.icon:SetTexture(firstSpell and ARC.SpellInfo:ResolveSpellIcon(firstSpell)
                or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.name:SetText(tostring(bundle.name or "Unnamed bundle"))
            local order = self:GetSelectionIndex(bundle.id)
            row.meta:SetText((order and ("Stage " .. tostring(order) .. "  |  ") or "")
                .. tostring(table.getn(bundle.spells or {})) .. " cooldown"
                .. (table.getn(bundle.spells or {}) == 1 and "" or "s"))
            row.check:SetChecked(self.selected[bundle.id] and true or false)
            if order then
                row.up:Show()
                row.down:Show()
                if order > 1 then row.up:Enable() else row.up:Disable() end
                if order < table.getn(self.selectionOrder) then row.down:Enable() else row.down:Disable() end
            else
                row.up:Hide()
                row.down:Hide()
            end
            row:Show()
        else
            row.bundleID = nil
            row:Hide()
        end
    end
    self.pageText:SetText("Stage bundles " .. tostring(self.page) .. "/" .. tostring(pages))
    if self.page > 1 then self.previousPage:Enable() else self.previousPage:Disable() end
    if self.page < pages then self.nextPage:Enable() else self.nextPage:Disable() end
    if self.editingIndex then self.delete:Enable() else self.delete:Disable() end
    if table.getn(bundles) == 0 then self.empty:Show() else self.empty:Hide() end
end

function CommanderConfig:Initialize()
    self.rows = {}
    self.selected = {}
    self.selectionOrder = {}
    self.page = 1
    local profile = ARC.db.profile.commanderConfigUI

    local frame = CreateFrame("Frame", "ActuallyARCCommanderConfigFrame", UIParent)
    frame:SetWidth(530)
    frame:SetHeight(548)
    frame:SetPoint(profile.point or "CENTER", UIParent, profile.point or "CENTER",
        profile.x or 0, profile.y or 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    setBackdrop(frame, { 0.020, 0.030, 0.045, 0.99 }, { 0.18, 0.62, 0.82, 1 })
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition(self, profile)
    end)
    self.frame = frame

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
    frame.title:SetText("ARC Command Plans - " .. ARC.Constants.WIP_TEXT)
    frame.title:SetTextColor(0.92, 0.96, 1.00)

    frame.subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -5)
    frame.subtitle:SetText("Build stage bundles with /act arc bundles, then select them in click order")
    frame.subtitle:SetTextColor(0.48, 0.72, 0.84)

    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    self.previousPlan = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    self.previousPlan:SetWidth(50)
    self.previousPlan:SetHeight(22)
    self.previousPlan:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -64)
    self.previousPlan:SetText("Prev")
    self.previousPlan:SetScript("OnClick", function() self:LoadPlan(self.editingIndex - 1) end)

    self.nextPlan = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    self.nextPlan:SetWidth(50)
    self.nextPlan:SetHeight(22)
    self.nextPlan:SetPoint("LEFT", self.previousPlan, "RIGHT", 5, 0)
    self.nextPlan:SetText("Next")
    self.nextPlan:SetScript("OnClick", function()
        self:LoadPlan((self.editingIndex or 0) + 1)
    end)

    self.planText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.planText:SetPoint("LEFT", self.nextPlan, "RIGHT", 8, 0)

    frame.nameLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.nameLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -98)
    frame.nameLabel:SetText("Button name:")

    self.nameBox = CreateFrame("EditBox", nil, frame)
    self.nameBox:SetHeight(24)
    self.nameBox:SetPoint("LEFT", frame.nameLabel, "RIGHT", 8, 0)
    self.nameBox:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
    self.nameBox:SetAutoFocus(false)
    self.nameBox:SetFontObject(GameFontHighlightSmall)
    self.nameBox:SetTextInsets(6, 6, 0, 0)
    setBackdrop(self.nameBox, { 0.008, 0.014, 0.024, 0.98 }, { 0.14, 0.42, 0.58, 1 })
    self.nameBox:SetScript("OnEscapePressed", function(editBox) editBox:ClearFocus() end)
    self.nameBox:SetScript("OnEnterPressed", function(editBox) editBox:ClearFocus() end)

    self.listPanel = CreateFrame("Frame", nil, frame)
    self.listPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -126)
    self.listPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -7, -126)
    self.listPanel:SetHeight(366)
    setBackdrop(self.listPanel, { 0.015, 0.024, 0.036, 0.82 }, { 0.12, 0.34, 0.46, 0.94 })

    self.empty = self.listPanel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    self.empty:SetPoint("CENTER", self.listPanel, "CENTER", 0, 0)
    self.empty:SetText("No stage bundles saved.\nUse /act arc bundles first.")

    self.previousPage = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    self.previousPage:SetWidth(50)
    self.previousPage:SetHeight(22)
    self.previousPage:SetPoint("TOPLEFT", self.listPanel, "BOTTOMLEFT", 4, -7)
    self.previousPage:SetText("Prev")
    self.previousPage:SetScript("OnClick", function()
        self.page = self.page - 1
        self:Refresh()
    end)

    self.nextPage = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    self.nextPage:SetWidth(50)
    self.nextPage:SetHeight(22)
    self.nextPage:SetPoint("LEFT", self.previousPage, "RIGHT", 5, 0)
    self.nextPage:SetText("Next")
    self.nextPage:SetScript("OnClick", function()
        self.page = self.page + 1
        self:Refresh()
    end)

    self.pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.pageText:SetPoint("LEFT", self.nextPage, "RIGHT", 8, 0)

    self.new = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    self.new:SetWidth(64)
    self.new:SetHeight(22)
    self.new:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 10)
    self.new:SetText("New")
    self.new:SetScript("OnClick", function() self:CreatePlan() end)

    self.save = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    self.save:SetWidth(64)
    self.save:SetHeight(22)
    self.save:SetPoint("LEFT", self.new, "RIGHT", 5, 0)
    self.save:SetText("Save")
    self.save:SetScript("OnClick", function() self:SavePlan() end)

    self.delete = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    self.delete:SetWidth(64)
    self.delete:SetHeight(22)
    self.delete:SetPoint("LEFT", self.save, "RIGHT", 5, 0)
    self.delete:SetText("Delete")
    self.delete:SetScript("OnClick", function() self:DeletePlan() end)

    frame:Hide()
    local plans = ARC.Commander:GetPlans()
    if table.getn(plans) > 0 then self:LoadPlan(1) else self:NewPlan() end
end

function CommanderConfig:Show()
    if not ARC:RequireConfigurationAuthority() then return false end
    self:Refresh()
    self.frame:Show()
    return true
end

function CommanderConfig:Toggle()
    if self.frame:IsShown() then
        self.frame:Hide()
        return false
    end
    return self:Show()
end
