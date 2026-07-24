local ARC = Actually.Modules.RaidCooldowns
local BundleConfig = ARC:NewModule("BundleConfig")

local PAGE_SIZE = 8
local ROW_HEIGHT = 43
local ROW_GAP = 2
local MIN_SCALE = 0.65
local MAX_SCALE = 1.80

local function applyLockIcon(button, locked)
    local state = locked and "Locked" or "Unlocked"
    button:SetText("")
    button:SetNormalTexture("Interface\\Buttons\\LockButton-" .. state .. "-Up")
    button:SetPushedTexture("Interface\\Buttons\\LockButton-" .. state .. "-Down")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
end

local function showLockTooltip(button, locked)
    if not GameTooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(locked and "Bundle window locked" or "Bundle window unlocked")
    GameTooltip:AddLine(locked and "Click to unlock background movement and resizing."
        or "Click to lock background movement and resizing.", 0.35, 1.00, 0.35)
    GameTooltip:Show()
end

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

local function sortedSpellIDs(filter)
    local ids = {}
    filter = string.lower(string.gsub(string.gsub(
        tostring(filter or ""), "^%s+", ""), "%s+$", ""))
    for spellID, entry in pairs(ARC.Registry.entries) do
        if entry.valid then
            local name = ARC.SpellInfo:ResolveSpellName(spellID)
            local haystack = string.lower(tostring(spellID) .. " " .. tostring(name)
                .. " " .. tostring(entry.category or ""))
            if filter == "" or string.find(haystack, filter, 1, true) then
                table.insert(ids, spellID)
            end
        end
    end
    table.sort(ids, function(left, right)
        local leftName = string.lower(ARC.SpellInfo:ResolveSpellName(left))
        local rightName = string.lower(ARC.SpellInfo:ResolveSpellName(right))
        if leftName ~= rightName then return leftName < rightName end
        return left < right
    end)
    return ids
end

local function trim(value)
    return string.gsub(string.gsub(tostring(value or ""), "^%s+", ""), "%s+$", "")
end

local function normalizedName(value)
    return string.lower(trim(value))
end

local function newBundleID()
    local epoch = time and time() or 0
    return "bundle:" .. tostring(epoch) .. ":" .. tostring(math.random(100000, 999999))
end

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

local function spellIconText(spellID)
    local icon = ARC.SpellInfo:ResolveSpellIcon(spellID)
    if not icon then return "" end
    return "|T" .. tostring(icon) .. ":16:16:0:0|t "
end

local function playerShortName(player)
    local name = type(player) == "table" and player.name or player
    name = tostring(name or "Unknown")
    return string.match(name, "^[^-]+") or name
end

local function statusColor(status)
    if status == "DONE" then return 0.35, 1.00, 0.35 end
    if status == "FAILED" then return 1.00, 0.35, 0.35 end
    if status == "ACTIVE" then return 1.00, 0.78, 0.20 end
    if status == "QUEUED" then return 0.72, 0.48, 1.00 end
    return 0.65, 0.78, 0.88
end

function BundleConfig:GetSelectedSpellIDs()
    local ids, seen = {}, {}
    for _, spellID in ipairs(self.selectionOrder or {}) do
        if self.selected and self.selected[spellID] and ARC.Registry:Get(spellID)
            and not seen[spellID] then
            seen[spellID] = true
            table.insert(ids, spellID)
        end
    end
    for _, spellID in ipairs(self.spellIDs or {}) do
        if self.selected and self.selected[spellID] and ARC.Registry:Get(spellID)
            and not seen[spellID] then
            seen[spellID] = true
            table.insert(ids, spellID)
        end
    end
    self.selectionOrder = ids
    local copy = {}
    for _, spellID in ipairs(ids) do table.insert(copy, spellID) end
    return copy
end

function BundleConfig:GetSelectionIndex(spellID)
    for index, selectedID in ipairs(self:GetSelectedSpellIDs()) do
        if selectedID == spellID then return index end
    end
end

function BundleConfig:SetSpellSelected(spellID, selected)
    if not spellID or not ARC.Registry:Get(spellID) then return end
    self.selected = self.selected or {}
    self.selectionOrder = self.selectionOrder or {}
    if selected then
        self.selected[spellID] = true
        if not self:GetSelectionIndex(spellID) then table.insert(self.selectionOrder, spellID) end
    else
        self.selected[spellID] = nil
        for index = table.getn(self.selectionOrder), 1, -1 do
            if self.selectionOrder[index] == spellID then table.remove(self.selectionOrder, index) end
        end
    end
    self.dirty = true
    self:Refresh()
end

function BundleConfig:MoveSelectedSpell(spellID, direction)
    local ids = self:GetSelectedSpellIDs()
    local current
    for index, selectedID in ipairs(ids) do
        if selectedID == spellID then current = index break end
    end
    if not current then return end
    local target = math.max(1, math.min(table.getn(ids), current + direction))
    if target == current then return end
    ids[current], ids[target] = ids[target], ids[current]
    self.selectionOrder = ids
    self.dirty = true
    self:Refresh()
end

function BundleConfig:ShowSelectedTooltip(owner)
    if not GameTooltip or not owner then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:SetText("Selected cooldown order", 0.32, 0.86, 1.00)
    local ids = self:GetSelectedSpellIDs()
    if table.getn(ids) == 0 then
        GameTooltip:AddLine("No cooldowns selected", 1.00, 0.35, 0.35)
    else
        for index, spellID in ipairs(ids) do
            GameTooltip:AddLine(tostring(index) .. ". " .. spellIconText(spellID)
                .. ARC.SpellInfo:ResolveSpellName(spellID), 0.92, 0.96, 1.00)
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(
        "ARC chooses ready players when the bundle is issued.", 0.55, 0.76, 0.88)
    GameTooltip:Show()
end

function BundleConfig:GetCurrentBundleName()
    local active = ARC.Bundles and ARC.Bundles.active
    if active then return active.name end
    local bundles = self:GetBundles()
    local saved = self.editingIndex and bundles[self.editingIndex]
    local name = trim(self.nameBox and self.nameBox:GetText() or (saved and saved.name))
    return name ~= "" and name or "Unsaved cooldown bundle"
end

function BundleConfig:ShowBundleTooltip(owner)
    if not GameTooltip or not owner then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()

    local active = ARC.Bundles and ARC.Bundles.active
    if active then
        GameTooltip:SetText(tostring(active.name), 0.32, 0.86, 1.00)
        GameTooltip:AddLine("Requested cooldowns", 0.72, 0.78, 0.88)
        local statuses = {}
        for _, item in pairs(active.items or {}) do statuses[item.spellID] = item end
        for _, spellID in ipairs(active.spellIDs or {}) do
            local item = statuses[spellID]
            local status = item and item.status or "PENDING"
            local red, green, blue = statusColor(status)
            local target = item and item.targetKey
                and (ARC.State.players[item.targetKey]
                    or (ARC.Roster.byKey and ARC.Roster.byKey[item.targetKey]))
            local detail = target and playerShortName(target) or nil
            detail = detail and (detail .. " - " .. status) or status
            GameTooltip:AddDoubleLine(spellIconText(spellID)
                .. ARC.SpellInfo:ResolveSpellName(spellID), detail,
                1, 1, 1, red, green, blue)
        end
    else
        GameTooltip:SetText(self:GetCurrentBundleName(), 0.32, 0.86, 1.00)
        GameTooltip:AddLine("Spells that will be requested", 0.72, 0.78, 0.88)
        local ids = self:GetSelectedSpellIDs()
        if table.getn(ids) == 0 then
            GameTooltip:AddLine("No spells selected", 1.00, 0.35, 0.35)
        else
            for _, spellID in ipairs(ids) do
                GameTooltip:AddLine(spellIconText(spellID)
                    .. ARC.SpellInfo:ResolveSpellName(spellID), 1, 1, 1)
            end
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click to open or request this bundle.", 0.55, 0.62, 0.70)
    GameTooltip:Show()
end

function BundleConfig:HideBundleTooltip(owner)
    if owner and self.tooltipOwner ~= owner then return end
    self.tooltipOwner = nil
    if GameTooltip then GameTooltip:Hide() end
end

function BundleConfig:UpdateBundleTooltip(owner, elapsed)
    if self.tooltipOwner ~= owner then return end
    owner.arcTooltipElapsed = (owner.arcTooltipElapsed or 0) + (elapsed or 0)
    if owner.arcTooltipElapsed < 0.25 then return end
    owner.arcTooltipElapsed = 0
    self:ShowBundleTooltip(owner)
end

function BundleConfig:ApplyLayoutLock()
    local frame, profile = self.frame, ARC.db.profile.bundleUI
    if not frame then return end
    local locked = profile.locked ~= false
    applyLockIcon(frame.lock, locked)
    if locked then
        frame.resizeGrip:Hide()
        frame:SetBackdropColor(0.025, 0.025, 0.040, 0.72)
        frame:SetBackdropBorderColor(0.32, 0.18, 0.48, 0.88)
    else
        frame.resizeGrip:Show()
        frame:SetBackdropColor(0.035, 0.030, 0.055, 0.88)
        frame:SetBackdropBorderColor(0.72, 0.30, 1.00, 1)
    end
end

function BundleConfig:ToggleLayoutLock()
    local profile = ARC.db.profile.bundleUI
    profile.locked = not (profile.locked ~= false)
    self:ApplyLayoutLock()
end

function BundleConfig:BeginScaleResize()
    local frame, profile = self.frame, ARC.db.profile.bundleUI
    if profile.locked ~= false then return end
    local grip = frame.resizeGrip
    grip.startCursorX = cursorX()
    grip.startScale = frame:GetScale()
    grip:SetScript("OnUpdate", function()
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            BundleConfig:EndScaleResize()
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

function BundleConfig:EndScaleResize()
    if self.frame and self.frame.resizeGrip then self.frame.resizeGrip:SetScript("OnUpdate", nil) end
end

function BundleConfig:GetBundles()
    local bundles = ARC.db.profile.cooldownBundles
    if type(bundles) ~= "table" then
        bundles = {}
        ARC.db.profile.cooldownBundles = bundles
    end
    for _, bundle in ipairs(bundles) do
        if type(bundle) == "table" and not bundle.id then bundle.id = newBundleID() end
    end
    return bundles
end

function BundleConfig:GetDependentPlans(bundleID)
    local dependents = {}
    if not bundleID or not ARC.Commander or not ARC.Commander.GetPlans then
        return dependents
    end
    for _, plan in ipairs(ARC.Commander:GetPlans()) do
        for _, stage in ipairs(plan.stages or {}) do
            if stage.bundleID == bundleID then
                table.insert(dependents, tostring(plan.name or "Unnamed command"))
                break
            end
        end
    end
    table.sort(dependents)
    return dependents
end

function BundleConfig:NewBundle()
    self.editingIndex = nil
    self.selected = {}
    self.selectionOrder = {}
    self:SetNameText("")
    self.nameBox:ClearFocus()
    self.spellPage = 1
    self.dirty = false
    self:Refresh()
end

function BundleConfig:LoadBundle(index)
    local bundles = self:GetBundles()
    if table.getn(bundles) == 0 then self:NewBundle() return end
    index = math.max(1, math.min(index or 1, table.getn(bundles)))
    local bundle = bundles[index]
    self.editingIndex = index
    self.selected = {}
    self.selectionOrder = {}
    for _, spellID in ipairs(bundle.spells or {}) do
        if ARC.Registry:Get(spellID) and not self.selected[spellID] then
            self.selected[spellID] = true
            table.insert(self.selectionOrder, spellID)
        end
    end
    self:SetNameText(bundle.name or "")
    self.nameBox:ClearFocus()
    self.spellPage = 1
    self.dirty = false
    self:Refresh()
end

function BundleConfig:SaveBundle()
    local ids = self:GetSelectedSpellIDs()
    if table.getn(ids) == 0 then ARC:Print("select at least one cooldown for the bundle") return nil end
    if table.getn(ids) > ARC.Constants.MAX_BUNDLE_SPELLS then
        ARC:Print("bundles can contain at most "
            .. tostring(ARC.Constants.MAX_BUNDLE_SPELLS) .. " cooldowns")
        return nil
    end

    local bundles = self:GetBundles()
    local index = self.editingIndex
    local existing = index and bundles[index]
    index = existing and index or (table.getn(bundles) + 1)
    local name = trim(self.nameBox:GetText())
    if name == "" then name = "Cooldown Bundle " .. tostring(index) end
    if #name > 60 then name = string.sub(name, 1, 60) end
    for otherIndex, other in ipairs(bundles) do
        if otherIndex ~= index and normalizedName(other.name) == normalizedName(name) then
            ARC:Print("a bundle named " .. name .. " already exists; choose a unique name")
            return nil
        end
    end
    local bundle = existing or { id = newBundleID() }
    bundle.name = name
    bundle.spells = ids
    bundles[index] = bundle
    self.editingIndex = index
    self:SetNameText(name)
    self.dirty = false
    ARC:Print("saved bundle " .. name .. " (" .. tostring(table.getn(ids)) .. " spells)")
    self:Refresh()
    if ARC.CommanderConfig and ARC.CommanderConfig.Refresh then
        ARC.CommanderConfig:Refresh()
    end
    return bundle
end

function BundleConfig:SetNameText(value)
    self.refreshingName = true
    self.nameBox:SetText(value or "")
    self.refreshingName = false
end

function BundleConfig:DeleteBundle()
    local bundles = self:GetBundles()
    if not self.editingIndex or not bundles[self.editingIndex] then return false end
    local bundle = bundles[self.editingIndex]
    local name = bundle.name
    local dependents = self:GetDependentPlans(bundle.id)
    if table.getn(dependents) > 0 then
        ARC:Print("cannot delete " .. tostring(name) .. "; used by command"
            .. (table.getn(dependents) == 1 and " " or "s ")
            .. table.concat(dependents, ", ")
            .. ". Remove it from those commands and save them first.")
        return false
    end
    table.remove(bundles, self.editingIndex)
    ARC:Print("deleted bundle " .. tostring(name))
    if table.getn(bundles) > 0 then
        self:LoadBundle(math.min(self.editingIndex, table.getn(bundles)))
    else
        self:NewBundle()
    end
    if ARC.CommanderConfig and ARC.CommanderConfig.Refresh then
        ARC.CommanderConfig:Refresh()
    end
    return true
end

function BundleConfig:RequestBundle()
    local bundle = self:SaveBundle()
    if bundle then ARC.Bundles:Start(bundle.name, bundle.spells) end
    self:Refresh()
end

function BundleConfig:CreateRow(index)
    local row = CreateFrame("Frame", nil, self.listPanel)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", self.listPanel, "TOPLEFT", 5,
        -5 - ((index - 1) * (ROW_HEIGHT + ROW_GAP)))
    row:SetPoint("TOPRIGHT", self.listPanel, "TOPRIGHT", -5,
        -5 - ((index - 1) * (ROW_HEIGHT + ROW_GAP)))
    setBackdrop(row, { 0.050, 0.055, 0.072, 0.82 }, { 0.18, 0.22, 0.28, 0.92 })

    row.check = CreateFrame("CheckButton", "ActuallyARCBundleSpellCheck" .. tostring(index),
        row, "UICheckButtonTemplate")
    row.check:SetWidth(24)
    row.check:SetHeight(24)
    row.check:SetPoint("LEFT", row, "LEFT", 7, 0)
    row.check:SetScript("OnClick", function(button)
        if row.spellID then self:SetSpellSelected(row.spellID, button:GetChecked() and true or false) end
    end)

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
        if row.spellID then self:MoveSelectedSpell(row.spellID, 1) end
    end)

    row.up = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.up:SetWidth(22)
    row.up:SetHeight(20)
    row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
    row.up:SetText("^")
    row.up:SetScript("OnClick", function()
        if row.spellID then self:MoveSelectedSpell(row.spellID, -1) end
    end)

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

function BundleConfig:Refresh()
    if not self.frame then return end
    local bundles = self:GetBundles()
    local bundleCount = table.getn(bundles)
    if self.editingIndex and not bundles[self.editingIndex] then self.editingIndex = nil end
    if self.editingIndex then
        self.bundleText:SetText("Bundle " .. tostring(self.editingIndex) .. "/" .. tostring(bundleCount))
    else
        self.bundleText:SetText("New bundle  (" .. tostring(bundleCount) .. " saved)")
    end
    if self.dirtyText then
        if not self.editingIndex then
            self.dirtyText:SetText("NEW - NOT SAVED")
            self.dirtyText:SetTextColor(1.00, 0.70, 0.20)
        elseif self.dirty then
            self.dirtyText:SetText("UNSAVED CHANGES")
            self.dirtyText:SetTextColor(1.00, 0.70, 0.20)
        else
            self.dirtyText:SetText("SAVED")
            self.dirtyText:SetTextColor(0.35, 1.00, 0.35)
        end
    end
    if self.editingIndex and self.editingIndex > 1 then self.previousBundle:Enable()
    else self.previousBundle:Disable() end
    if (self.editingIndex and self.editingIndex < bundleCount)
        or (not self.editingIndex and bundleCount > 0) then self.nextBundle:Enable()
    else self.nextBundle:Disable() end

    local ids = self.spellIDs
    local pages = math.max(1, math.ceil(table.getn(ids) / PAGE_SIZE))
    self.spellPage = math.max(1, math.min(self.spellPage or 1, pages))
    local first = ((self.spellPage - 1) * PAGE_SIZE) + 1
    for index = 1, PAGE_SIZE do
        local row = self.rows[index] or self:CreateRow(index)
        local spellID = ids[first + index - 1]
        if spellID then
            local entry = ARC.Registry:Get(spellID)
            row.spellID = spellID
            row.icon:SetTexture(ARC.SpellInfo:ResolveSpellIcon(spellID))
            row.name:SetText(ARC.SpellInfo:ResolveSpellName(spellID))
            local orderIndex = self:GetSelectionIndex(spellID)
            row.meta:SetText((orderIndex and ("Order " .. tostring(orderIndex) .. "  |  ") or "")
                .. "ID " .. tostring(spellID) .. "  |  "
                .. tostring(entry and entry.category or "uncategorized"))
            row.check:SetChecked(self.selected[spellID] and true or false)
            if orderIndex then
                local count = table.getn(self:GetSelectedSpellIDs())
                row.up:Show()
                row.down:Show()
                if orderIndex > 1 then row.up:Enable() else row.up:Disable() end
                if orderIndex < count then row.down:Enable() else row.down:Disable() end
            else
                row.up:Hide()
                row.down:Hide()
            end
            row:Show()
        else
            row.spellID = nil
            row:Hide()
        end
    end
    self.pageText:SetText("Spells " .. tostring(self.spellPage) .. "/" .. tostring(pages))
    if self.spellPage > 1 then self.previousPage:Enable() else self.previousPage:Disable() end
    if self.spellPage < pages then self.nextPage:Enable() else self.nextPage:Disable() end
    if self.editingIndex then self.delete:Enable() else self.delete:Disable() end
    if self.selectedSummaryText then
        local selected = self:GetSelectedSpellIDs()
        local names = {}
        for _, spellID in ipairs(selected) do
            table.insert(names, ARC.SpellInfo:ResolveSpellName(spellID))
        end
        local summary = table.concat(names, "  >  ")
        if string.len(summary) > 76 then summary = string.sub(summary, 1, 73) .. "..." end
        self.selectedSummaryText:SetText("Selected (" .. tostring(table.getn(selected))
            .. "): " .. (summary ~= "" and summary or "none"))
    end
    if ARC.Bundles.active then
        self.cancel:SetText("Cancel Active")
        self.cancel:Enable()
    else
        self.cancel:SetText("Cancel Active")
        self.cancel:Disable()
    end
end

function BundleConfig:Initialize()
    self.rows = {}
    self.selected = {}
    self.selectionOrder = {}
    self.filter = ""
    self.spellIDs = sortedSpellIDs(self.filter)
    self.spellPage = 1
    local profile = ARC.db.profile.bundleUI

    local frame = CreateFrame("Frame", "ActuallyARCBundleConfigFrame", UIParent)
    frame:SetWidth(520)
    frame:SetHeight(602)
    frame:SetPoint(profile.point or "CENTER", UIParent, profile.point or "CENTER",
        profile.x or 0, profile.y or 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    setBackdrop(frame, { 0.025, 0.025, 0.035, 0.99 }, { 0.45, 0.24, 0.68, 1 })
    frame:SetScale(clamp(tonumber(profile.scale) or 1, MIN_SCALE, MAX_SCALE))
    frame:SetScript("OnDragStart", function(self)
        if profile.locked == false then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition(self, profile)
    end)
    self.frame = frame

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
    frame.title:SetText("Actually Raid Cooldowns - CD Bundles - " .. ARC.Constants.WIP_TEXT)
    frame.title:SetTextColor(0.92, 0.96, 1.00)

    frame.dragBar = CreateFrame("Frame", nil, frame)
    frame.dragBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
    frame.dragBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -94, -3)
    frame.dragBar:SetHeight(54)
    frame.dragBar:EnableMouse(true)
    frame.dragBar:RegisterForDrag("LeftButton")
    frame.dragBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame.dragBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        savePosition(frame, profile)
    end)

    frame.subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -5)
    frame.subtitle:SetText(
        "Choose cooldowns; ARC selects ready players and queues each player's prompts in this order")
    frame.subtitle:SetTextColor(0.58, 0.50, 0.72)

    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    frame.lock = CreateFrame("Button", nil, frame)
    frame.lock:SetWidth(20)
    frame.lock:SetHeight(20)
    frame.lock:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -34, -5)
    frame.lock:SetScript("OnClick", function(button)
        self:ToggleLayoutLock()
        showLockTooltip(button, profile.locked ~= false)
    end)
    frame.lock:SetScript("OnEnter", function(button)
        showLockTooltip(button, profile.locked ~= false)
    end)
    frame.lock:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    self.previousBundle = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    self.previousBundle:SetWidth(50)
    self.previousBundle:SetHeight(22)
    self.previousBundle:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -62)
    self.previousBundle:SetText("Prev")
    self.previousBundle:SetScript("OnClick", function() self:LoadBundle(self.editingIndex - 1) end)

    self.nextBundle = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    self.nextBundle:SetWidth(50)
    self.nextBundle:SetHeight(22)
    self.nextBundle:SetPoint("LEFT", self.previousBundle, "RIGHT", 5, 0)
    self.nextBundle:SetText("Next")
    self.nextBundle:SetScript("OnClick", function() self:LoadBundle((self.editingIndex or 0) + 1) end)

    self.bundleText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.bundleText:SetPoint("LEFT", self.nextBundle, "RIGHT", 8, 0)

    frame.searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.searchLabel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -184, -66)
    frame.searchLabel:SetText("Search:")

    self.searchBox = CreateFrame("EditBox", nil, frame)
    self.searchBox:SetWidth(140)
    self.searchBox:SetHeight(22)
    self.searchBox:SetPoint("LEFT", frame.searchLabel, "RIGHT", 7, 0)
    self.searchBox:SetAutoFocus(false)
    self.searchBox:SetFontObject(GameFontHighlightSmall)
    self.searchBox:SetTextInsets(6, 6, 0, 0)
    setBackdrop(self.searchBox, { 0.008, 0.012, 0.020, 0.96 }, { 0.24, 0.46, 0.62, 1 })
    self.searchBox:SetScript("OnEscapePressed", function(editBox) editBox:ClearFocus() end)
    self.searchBox:SetScript("OnEnterPressed", function(editBox) editBox:ClearFocus() end)
    self.searchBox:SetScript("OnTextChanged", function(editBox)
        self.filter = editBox:GetText() or ""
        self.spellIDs = sortedSpellIDs(self.filter)
        self.spellPage = 1
        self:Refresh()
    end)

    frame.nameLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.nameLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -96)
    frame.nameLabel:SetText("Bundle name:")

    self.nameBox = CreateFrame("EditBox", nil, frame)
    self.nameBox:SetHeight(24)
    self.nameBox:SetPoint("LEFT", frame.nameLabel, "RIGHT", 8, 0)
    self.nameBox:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
    self.nameBox:SetAutoFocus(false)
    self.nameBox:SetFontObject(GameFontHighlightSmall)
    self.nameBox:SetTextInsets(6, 6, 0, 0)
    setBackdrop(self.nameBox, { 0.008, 0.012, 0.020, 0.96 }, { 0.30, 0.20, 0.44, 1 })
    self.nameBox:SetScript("OnEscapePressed", function(editBox) editBox:ClearFocus() end)
    self.nameBox:SetScript("OnEnterPressed", function(editBox) editBox:ClearFocus() end)
    self.nameBox:SetScript("OnTextChanged", function()
        if not self.refreshingName then
            self.dirty = true
            self:Refresh()
        end
    end)

    self.selectedSummary = CreateFrame("Frame", nil, frame)
    self.selectedSummary:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -119)
    self.selectedSummary:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -119)
    self.selectedSummary:SetHeight(20)
    self.selectedSummary:EnableMouse(true)
    setBackdrop(
        self.selectedSummary,
        { 0.025, 0.045, 0.062, 0.88 },
        { 0.16, 0.42, 0.58, 0.90 })
    self.selectedSummaryText = self.selectedSummary:CreateFontString(
        nil, "OVERLAY", "GameFontHighlightSmall")
    self.selectedSummaryText:SetPoint("LEFT", self.selectedSummary, "LEFT", 6, 0)
    self.selectedSummaryText:SetPoint("RIGHT", self.selectedSummary, "RIGHT", -6, 0)
    self.selectedSummaryText:SetJustifyH("LEFT")
    self.selectedSummaryText:SetTextColor(0.62, 0.82, 0.94)
    self.selectedSummary:SetScript("OnEnter", function(owner)
        self:ShowSelectedTooltip(owner)
    end)
    self.selectedSummary:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    self.listPanel = CreateFrame("Frame", nil, frame)
    self.listPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -145)
    self.listPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -7, -145)
    self.listPanel:SetHeight(380)
    setBackdrop(self.listPanel, { 0.020, 0.024, 0.034, 0.72 }, { 0.25, 0.16, 0.36, 0.92 })

    self.previousPage = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    self.previousPage:SetWidth(50)
    self.previousPage:SetHeight(22)
    self.previousPage:SetPoint("TOPLEFT", self.listPanel, "BOTTOMLEFT", 4, -7)
    self.previousPage:SetText("Prev")
    self.previousPage:SetScript("OnClick", function()
        self.spellPage = self.spellPage - 1
        self:Refresh()
    end)

    self.nextPage = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    self.nextPage:SetWidth(50)
    self.nextPage:SetHeight(22)
    self.nextPage:SetPoint("LEFT", self.previousPage, "RIGHT", 5, 0)
    self.nextPage:SetText("Next")
    self.nextPage:SetScript("OnClick", function()
        self.spellPage = self.spellPage + 1
        self:Refresh()
    end)

    self.pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.pageText:SetPoint("LEFT", self.nextPage, "RIGHT", 8, 0)

    self.new = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    self.new:SetWidth(58)
    self.new:SetHeight(22)
    self.new:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 10)
    self.new:SetText("New")
    self.new:SetScript("OnClick", function() self:NewBundle() end)

    self.save = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    self.save:SetWidth(58)
    self.save:SetHeight(22)
    self.save:SetPoint("LEFT", self.new, "RIGHT", 5, 0)
    self.save:SetText("Save")
    self.save:SetScript("OnClick", function() self:SaveBundle() end)

    self.delete = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    self.delete:SetWidth(58)
    self.delete:SetHeight(22)
    self.delete:SetPoint("LEFT", self.save, "RIGHT", 5, 0)
    self.delete:SetText("Delete")
    self.delete:SetScript("OnClick", function() self:DeleteBundle() end)

    self.dirtyText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.dirtyText:SetPoint("BOTTOM", frame, "BOTTOM", 35, 15)

    self.cancel = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    self.cancel:SetWidth(100)
    self.cancel:SetHeight(22)
    self.cancel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 10)
    self.cancel:SetText("Cancel Active")
    self.cancel:SetScript("OnClick", function()
        ARC.Bundles:CancelActive("cancelled by coordinator")
        self:Refresh()
    end)

    frame.resizeGrip = CreateFrame("Button", nil, frame)
    frame.resizeGrip:SetWidth(18)
    frame.resizeGrip:SetHeight(18)
    frame.resizeGrip:SetPoint("BOTTOM", frame, "BOTTOM", 0, 2)
    frame.resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    frame.resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    frame.resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    frame.resizeGrip:SetScript("OnMouseDown", function() self:BeginScaleResize() end)
    frame.resizeGrip:SetScript("OnMouseUp", function() self:EndScaleResize() end)

    frame.scaleText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.scaleText:SetPoint("BOTTOM", frame.resizeGrip, "TOP", 0, 1)
    frame.scaleText:SetText(string.format("%d%%", math.floor(frame:GetScale() * 100 + 0.5)))

    frame:Hide()
    self:ApplyLayoutLock()
    local bundles = self:GetBundles()
    if table.getn(bundles) > 0 then self:LoadBundle(1) else self:NewBundle() end
end

function BundleConfig:Show()
    if ARC.OfficerConfig and ARC.OfficerConfig.frame then
        return ARC.OfficerConfig:Show("bundles")
    end
    if not ARC:RequireConfigurationAuthority() then return false end
    self:Refresh()
    self.frame:Show()
    return true
end

function BundleConfig:Toggle()
    if ARC.OfficerConfig and ARC.OfficerConfig.frame then
        return ARC.OfficerConfig:Toggle("bundles")
    end
    if self.frame:IsShown() then
        self.frame:Hide()
        return false
    end
    return self:Show()
end
