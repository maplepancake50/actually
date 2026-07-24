local ARC = Actually.Modules.RaidCooldowns
local Commander = ARC:NewModule("Commander")

local ROW_HEIGHT = 50
local MIN_SCALE = 0.65
local MAX_SCALE = 1.80

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

local function cursorX()
    local x = GetCursorPosition and GetCursorPosition() or 0
    local scale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    return x / math.max(scale, 0.01)
end

local function savePosition(frame, profile)
    local point, _, _, x, y = frame:GetPoint(1)
    profile.point, profile.x, profile.y = point, x, y
end

local function applyLockIcon(button, locked)
    local state = locked and "Locked" or "Unlocked"
    button:SetText("")
    button:SetNormalTexture("Interface\\Buttons\\LockButton-" .. state .. "-Up")
    button:SetPushedTexture("Interface\\Buttons\\LockButton-" .. state .. "-Down")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
end

local function copyArray(source)
    local result = {}
    for _, value in ipairs(source or {}) do table.insert(result, value) end
    return result
end

local function newID(prefix)
    local epoch = time and time() or 0
    return tostring(prefix) .. ":" .. tostring(epoch) .. ":" .. tostring(math.random(100000, 999999))
end

local function spellIconText(spellID)
    local icon = ARC.SpellInfo:ResolveSpellIcon(spellID)
    return icon and ("|T" .. tostring(icon) .. ":16:16:0:0|t ") or ""
end

local function shortName(player)
    local name = type(player) == "table" and player.name or player
    name = tostring(name or "Unknown")
    return string.match(name, "^[^-]+") or name
end

function Commander:GetBundles()
    local bundles = ARC.db.profile.cooldownBundles
    if type(bundles) ~= "table" then
        bundles = {}
        ARC.db.profile.cooldownBundles = bundles
    end
    for _, bundle in ipairs(bundles) do
        if type(bundle) == "table" and not bundle.id then bundle.id = newID("bundle") end
    end
    return bundles
end

function Commander:GetPlans()
    local plans = ARC.db.profile.commandPlans
    if type(plans) ~= "table" then
        plans = {}
        ARC.db.profile.commandPlans = plans
    end
    for _, plan in ipairs(plans) do
        if type(plan) == "table" then
            if not plan.id then plan.id = newID("command") end
            if type(plan.stages) ~= "table" then plan.stages = {} end
        end
    end
    return plans
end

function Commander:FindPlan(planID)
    for index, plan in ipairs(self:GetPlans()) do
        if plan.id == planID then return plan, index end
    end
end

function Commander:FindBundle(bundleID)
    for _, bundle in ipairs(self:GetBundles()) do
        if bundle.id == bundleID then return bundle end
    end
end

function Commander:ResolveStage(stage)
    if type(stage) ~= "table" then return nil end
    local bundle = stage.bundleID and self:FindBundle(stage.bundleID)
    local source = bundle or stage
    local unique, spells = {}, {}
    for _, rawID in ipairs(source.spells or {}) do
        local spellID = ARC.Registry:Canonicalize(rawID)
        if spellID and not unique[spellID] then
            unique[spellID] = true
            table.insert(spells, spellID)
        end
    end
    return {
        name = tostring(source.name or stage.name or "Cooldown stage"),
        spells = spells,
        bundleID = stage.bundleID,
        missingBundle = stage.bundleID and not bundle and true or false,
    }
end

function Commander:GetStageIndex(plan)
    local count = table.getn(plan and plan.stages or {})
    if count == 0 then return 1 end
    local index = tonumber(self.progress[plan.id]) or 1
    index = math.max(1, math.min(index, count))
    self.progress[plan.id] = index
    return index
end

function Commander:GetCurrentStage(plan)
    local index = self:GetStageIndex(plan)
    return self:ResolveStage(plan and plan.stages and plan.stages[index]), index
end

function Commander:ResetPlan(planID)
    local plan = self:FindPlan(planID)
    if not plan then return false end
    if self:IsPlanActive(planID) then
        ARC:Print("cancel the active stage before resetting this command")
        return false
    end
    self.progress[planID] = 1
    ARC:Print("reset command " .. tostring(plan.name) .. " to stage 1")
    self:Refresh()
    return true
end

function Commander:StageAvailability(stage)
    local ready, total, shortest = 0, 0
    local spells = stage and stage.spells or {}
    local planned = ARC.Automation:PlanSpells(spells)
    for index, spellID in ipairs(spells) do
        total = total + 1
        if planned[index] then
            ready = ready + 1
        else
            for playerKey, player in pairs(ARC.State.players or {}) do
                local spell = player.spells and player.spells[spellID]
                local selfKey = ARC.Roster:GetPlayer()
                local peerReady = playerKey == selfKey
                    or (player.source == "REPORT" and ARC.State.peers[playerKey])
                if spell and peerReady and player.connected ~= false and not player.dead and not player.stale then
                    local remaining = math.max(0, (spell.readyAt or 0) - ARC:Now())
                    if remaining > 0 and (not shortest or remaining < shortest) then shortest = remaining end
                end
            end
        end
    end
    return ready, total, shortest
end

function Commander:IsPlanActive(planID)
    return self.activePlanID == planID and ARC.Bundles and ARC.Bundles.active
end

function Commander:StartPlan(planID)
    if not ARC:RequireCommandAuthority() then return false end
    local plan = self:FindPlan(planID)
    if not plan then ARC:Print("command plan no longer exists") return false end
    if self.pendingPlanID or self.activePlanID or ARC.Bundles.active or ARC.Requests.outgoing then
        ARC:Print("finish or cancel the active cooldown command first")
        return false
    end
    local stage, stageIndex = self:GetCurrentStage(plan)
    if not stage or table.getn(stage.spells) == 0 then
        ARC:Print(tostring(plan.name) .. " stage " .. tostring(stageIndex) .. " has no valid cooldowns")
        return false
    end

    local bundleName = tostring(plan.name) .. " - " .. tostring(stage.name)
    self.pendingPlanID = plan.id
    local started = ARC.Bundles:Start(bundleName, stage.spells, false,
        function(success, bundle)
            Commander.pendingPlanID = nil
            if success and bundle then
                Commander.activePlanID = plan.id
                Commander.activeStageIndex = stageIndex
                Commander.activeBundleID = bundle.id
                ARC:Print("command " .. tostring(plan.name) .. " stage "
                    .. tostring(stageIndex) .. "/" .. tostring(table.getn(plan.stages))
                    .. " issued")
            end
            Commander:Refresh()
        end)
    if not started then self.pendingPlanID = nil end
    self:Refresh()
    return started
end

function Commander:OnBundleFinished(bundle)
    if not bundle or bundle.id ~= self.activeBundleID then return end
    local plan = self:FindPlan(self.activePlanID)
    local policy = ARC.db.profile.automation
        and ARC.db.profile.automation.stageAdvancePolicy or "any"
    local shouldAdvance = (bundle.completed or 0) > 0
        and (policy ~= "all" or (bundle.failed or 0) == 0)
    if plan and shouldAdvance then
        local count = table.getn(plan.stages or {})
        local nextStage = (self.activeStageIndex or 1) + 1
        if nextStage > count then nextStage = 1 end
        self.progress[plan.id] = nextStage
        ARC:Print("command " .. tostring(plan.name) .. " advanced to stage "
            .. tostring(nextStage) .. "/" .. tostring(count))
    elseif plan then
        ARC:Print("command " .. tostring(plan.name) .. " did not advance because no cooldown was used")
    end
    self.activePlanID, self.activeStageIndex, self.activeBundleID = nil, nil, nil
    self:Refresh()
end

function Commander:OnBundleCancelled(bundle)
    if not bundle or bundle.id ~= self.activeBundleID then return end
    local plan = self:FindPlan(self.activePlanID)
    if plan then
        ARC:Print("command " .. tostring(plan.name) .. " remains on stage "
            .. tostring(self.activeStageIndex or self:GetStageIndex(plan)))
    end
    self.activePlanID, self.activeStageIndex, self.activeBundleID = nil, nil, nil
    self:Refresh()
end

function Commander:ShowTooltip(button)
    local plan = button and button.plan
    if not plan or not GameTooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:SetText(tostring(plan.name), 0.32, 0.86, 1.00)
    local current = self:GetStageIndex(plan)
    for index, rawStage in ipairs(plan.stages or {}) do
        local stage = self:ResolveStage(rawStage)
        local prefix = index == current and "|cff55ff88> " or "|cff8aa0b0  "
        GameTooltip:AddLine(prefix .. "Stage " .. tostring(index) .. ": "
            .. tostring(stage and stage.name or "Missing stage") .. "|r", 1, 1, 1)
        if stage then
            for _, spellID in ipairs(stage.spells) do
                local candidate = ARC.Requests:FindCandidate(spellID, nil, {})
                local target = candidate and (ARC.State.players[candidate]
                    or (ARC.Roster.byKey and ARC.Roster.byKey[candidate]))
                GameTooltip:AddDoubleLine("    " .. spellIconText(spellID)
                    .. ARC.SpellInfo:ResolveSpellName(spellID),
                    target and ("-> " .. shortName(target)) or "not ready",
                    0.88, 0.92, 1.00,
                    target and 0.35 or 1.00, target and 1.00 or 0.40, target and 0.35 or 0.30)
            end
            if stage.missingBundle then
                GameTooltip:AddLine("    Saved bundle was deleted; using its saved snapshot.",
                    1.00, 0.55, 0.20)
            end
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: issue current stage", 0.35, 1.00, 0.35)
    GameTooltip:AddLine(self:IsPlanActive(plan.id)
        and "Right-click: cancel active stage"
        or "Right-click: reset to stage 1", 1.00, 0.72, 0.20)
    GameTooltip:Show()
end

function Commander:CreateButton(index)
    local button = CreateFrame("Button", nil, self.frame)
    button:SetHeight(ROW_HEIGHT - 3)
    button:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 7, -29 - ((index - 1) * ROW_HEIGHT))
    button:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -7, -29 - ((index - 1) * ROW_HEIGHT))
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    setBackdrop(button, { 0.025, 0.040, 0.055, 0.90 }, { 0.14, 0.34, 0.46, 0.95 })

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetWidth(36)
    button.icon:SetHeight(36)
    button.icon:SetPoint("LEFT", button, "LEFT", 6, 0)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button.glow = button:CreateTexture(nil, "OVERLAY")
    button.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    button.glow:SetBlendMode("ADD")
    button.glow:SetWidth(56)
    button.glow:SetHeight(56)
    button.glow:SetPoint("CENTER", button.icon, "CENTER", 0, 0)
    button.glow:SetVertexColor(0.25, 1.00, 0.35, 0.75)
    button.glow:Hide()

    button.name = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.name:SetPoint("TOPLEFT", button.icon, "TOPRIGHT", 8, -2)
    button.name:SetPoint("RIGHT", button, "RIGHT", -66, 0)
    button.name:SetJustifyH("LEFT")

    button.status = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    button.status:SetPoint("BOTTOMLEFT", button.icon, "BOTTOMRIGHT", 8, 4)
    button.status:SetPoint("RIGHT", button, "RIGHT", -66, 0)
    button.status:SetJustifyH("LEFT")

    button.stage = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.stage:SetPoint("RIGHT", button, "RIGHT", -8, 0)
    button.stage:SetWidth(52)
    button.stage:SetJustifyH("RIGHT")

    button:SetScript("OnClick", function(self, mouseButton)
        if not self.plan then return end
        if mouseButton == "RightButton" and Commander:IsPlanActive(self.plan.id) then
            ARC.Bundles:CancelActive("cancelled from commander bar")
        elseif mouseButton == "RightButton" then Commander:ResetPlan(self.plan.id)
        elseif self.arcActionable then Commander:StartPlan(self.plan.id) end
    end)
    button:SetScript("OnEnter", function(self) Commander:ShowTooltip(self) end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    self.buttons[index] = button
    return button
end

function Commander:RefreshButton(button, plan)
    local stage, stageIndex = self:GetCurrentStage(plan)
    local stageCount = table.getn(plan.stages or {})
    local firstSpell = stage and stage.spells[1]
    button.plan = plan
    button.name:SetText(tostring(plan.name or "Unnamed command"))
    button.icon:SetTexture(firstSpell and ARC.SpellInfo:ResolveSpellIcon(firstSpell)
        or "Interface\\Icons\\INV_Misc_QuestionMark")
    button.stage:SetText(stageCount > 0
        and (tostring(stageIndex) .. "/" .. tostring(stageCount)) or "0/0")

    local active = self:IsPlanActive(plan.id)
    local ready, total, shortest = self:StageAvailability(stage)
    if active then
        button.status:SetText("ACTIVE - requests in progress")
        button.status:SetTextColor(0.76, 0.55, 1.00)
        button.stage:SetTextColor(0.76, 0.55, 1.00)
        button.glow:SetVertexColor(0.72, 0.35, 1.00, 0.85)
        button.glow:Show()
        button.arcActionable = false
        button:SetBackdropBorderColor(0.72, 0.35, 1.00, 1)
    elseif self.activePlanID or ARC.Bundles.active or ARC.Requests.outgoing then
        button.status:SetText("BUSY - ANOTHER COMMAND")
        button.status:SetTextColor(0.58, 0.62, 0.68)
        button.stage:SetTextColor(0.58, 0.62, 0.68)
        button.glow:Hide()
        button.arcActionable = false
        button:SetBackdropBorderColor(0.22, 0.26, 0.30, 0.92)
    elseif not ARC:HasCommandAuthority() then
        button.status:SetText("OFFICER ACCESS REQUIRED")
        button.status:SetTextColor(0.58, 0.62, 0.68)
        button.stage:SetTextColor(0.58, 0.62, 0.68)
        button.glow:Hide()
        button.arcActionable = false
        button:SetBackdropBorderColor(0.22, 0.26, 0.30, 0.92)
    elseif not ARC.Roster:IsGrouped() then
        button.status:SetText("NOT GROUPED")
        button.status:SetTextColor(0.58, 0.62, 0.68)
        button.stage:SetTextColor(0.58, 0.62, 0.68)
        button.glow:Hide()
        button.arcActionable = false
        button:SetBackdropBorderColor(0.22, 0.26, 0.30, 0.92)
    elseif total > 0 and ready == total then
        button.status:SetText("READY " .. tostring(ready) .. "/" .. tostring(total))
        button.status:SetTextColor(0.35, 1.00, 0.35)
        button.stage:SetTextColor(0.35, 1.00, 0.35)
        button.glow:SetVertexColor(0.25, 1.00, 0.35, 0.75)
        button.glow:Show()
        button.arcActionable = true
        button:SetBackdropBorderColor(0.20, 0.76, 0.30, 1)
    elseif ready > 0 then
        button.status:SetText("PARTIAL " .. tostring(ready) .. "/" .. tostring(total))
        button.status:SetTextColor(1.00, 0.72, 0.20)
        button.stage:SetTextColor(1.00, 0.72, 0.20)
        button.glow:Hide()
        button.arcActionable = true
        button:SetBackdropBorderColor(0.82, 0.52, 0.14, 1)
    else
        button.status:SetText(shortest and ("WAIT " .. tostring(math.ceil(shortest)))
            or (total > 0 and "NO READY OWNER" or "EMPTY STAGE"))
        button.status:SetTextColor(0.58, 0.62, 0.68)
        button.stage:SetTextColor(0.58, 0.62, 0.68)
        button.glow:Hide()
        button.arcActionable = false
        button:SetBackdropBorderColor(0.22, 0.26, 0.30, 0.92)
    end
end

function Commander:Refresh()
    if not self.frame then return end
    if not ARC:HasCommandAuthority() then
        self.frame:Hide()
        return
    end
    local plans = {}
    for _, plan in ipairs(self:GetPlans()) do
        if type(plan.stages) == "table" and table.getn(plan.stages) > 0 then
            table.insert(plans, plan)
        end
    end
    local count = math.min(table.getn(plans), ARC.Constants.MAX_COMMAND_PLANS)
    for index = 1, count do
        local button = self.buttons[index] or self:CreateButton(index)
        self:RefreshButton(button, plans[index])
        button:Show()
    end
    for index = count + 1, table.getn(self.buttons) do self.buttons[index]:Hide() end
    if count == 0 then self.frame.empty:Show() else self.frame.empty:Hide() end
    self.frame:SetHeight(39 + math.max(1, count) * ROW_HEIGHT)
end

function Commander:ApplyLayoutLock()
    local profile = ARC.db.profile.commanderUI
    local locked = profile.locked ~= false
    applyLockIcon(self.frame.lock, locked)
    if locked then
        self.frame.resizeGrip:Hide()
        self.frame:SetBackdropColor(0.02, 0.035, 0.055, 0.62)
        self.frame:SetBackdropBorderColor(0.12, 0.34, 0.46, 0.88)
    else
        self.frame.resizeGrip:Show()
        self.frame:SetBackdropColor(0.03, 0.055, 0.085, 0.82)
        self.frame:SetBackdropBorderColor(0.24, 0.86, 1.00, 1)
    end
end

function Commander:ToggleLayoutLock()
    local profile = ARC.db.profile.commanderUI
    profile.locked = not (profile.locked ~= false)
    self:ApplyLayoutLock()
end

function Commander:BeginScaleResize()
    local profile = ARC.db.profile.commanderUI
    if profile.locked ~= false then return end
    local grip = self.frame.resizeGrip
    grip.startCursorX = cursorX()
    grip.startScale = self.frame:GetScale()
    grip:SetScript("OnUpdate", function()
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            Commander:EndScaleResize()
            return
        end
        local nextScale = grip.startScale
            + ((cursorX() - grip.startCursorX) / math.max(Commander.frame:GetWidth(), 1))
        nextScale = clamp(nextScale, MIN_SCALE, MAX_SCALE)
        Commander.frame:SetScale(nextScale)
        profile.scale = nextScale
    end)
end

function Commander:EndScaleResize()
    if self.frame and self.frame.resizeGrip then self.frame.resizeGrip:SetScript("OnUpdate", nil) end
end

function Commander:CreateFrame()
    local profile = ARC.db.profile.commanderUI
    local frame = CreateFrame("Frame", "ActuallyARCCommanderFrame", UIParent)
    frame:SetWidth(286)
    frame:SetHeight(89)
    frame:SetPoint(profile.point or "CENTER", UIParent, profile.point or "CENTER",
        profile.x or -330, profile.y or 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScale(clamp(tonumber(profile.scale) or 1, MIN_SCALE, MAX_SCALE))
    setBackdrop(frame, { 0.02, 0.035, 0.055, 0.62 }, { 0.12, 0.34, 0.46, 0.88 })
    frame:SetScript("OnDragStart", function(self)
        if profile.locked == false then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition(self, profile)
    end)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            ARC:ShowWindowContextMenu(frame.contextMenu, "ARC Commander", function()
                profile.shown = false
                frame:Hide()
            end)
        end
    end)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    frame.title:SetText("ARC Commander - " .. ARC.Constants.WIP_TEXT)

    frame.lock = CreateFrame("Button", nil, frame)
    frame.lock:SetWidth(20)
    frame.lock:SetHeight(20)
    frame.lock:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -7, -4)
    frame.lock:SetScript("OnClick", function() self:ToggleLayoutLock() end)

    frame.dragBar = CreateFrame("Frame", nil, frame)
    frame.dragBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
    frame.dragBar:SetPoint("TOPRIGHT", frame.lock, "TOPLEFT", -4, 2)
    frame.dragBar:SetHeight(22)
    frame.dragBar:EnableMouse(true)
    frame.dragBar:RegisterForDrag("LeftButton")
    frame.dragBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame.dragBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        savePosition(frame, profile)
    end)
    frame.dragBar:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            ARC:ShowWindowContextMenu(frame.contextMenu, "ARC Commander", function()
                profile.shown = false
                frame:Hide()
            end)
        end
    end)

    frame.contextMenu = CreateFrame("Frame", "ActuallyARCCommanderContextMenu",
        UIParent, "UIDropDownMenuTemplate")

    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.empty:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -34)
    frame.empty:SetText("No command plans. Use /arc commander config")

    frame.resizeGrip = CreateFrame("Button", nil, frame)
    frame.resizeGrip:SetWidth(18)
    frame.resizeGrip:SetHeight(18)
    frame.resizeGrip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    frame.resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    frame.resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    frame.resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    frame.resizeGrip:SetScript("OnMouseDown", function() self:BeginScaleResize() end)
    frame.resizeGrip:SetScript("OnMouseUp", function() self:EndScaleResize() end)

    self.frame = frame
    self:ApplyLayoutLock()
    if profile.shown == false or not ARC:HasCommandAuthority() then
        frame:Hide()
    else
        frame:Show()
    end
end

function Commander:Initialize()
    ARC.db.profile.commanderProgress = ARC.db.profile.commanderProgress or {}
    self.progress = ARC.db.profile.commanderProgress
    self.buttons = {}
    self.elapsed = 0
    self:GetBundles()
    self:GetPlans()
    self:CreateFrame()
    self:Refresh()
    self.initialized = true
end

function Commander:OnUpdate(elapsed)
    self.elapsed = (self.elapsed or 0) + (elapsed or 0)
    if self.elapsed < 0.25 then return end
    self.elapsed = 0
    if not ARC:HasCommandAuthority() then
        if self.frame then self.frame:Hide() end
        return
    elseif ARC.db.profile.commanderUI.shown ~= false and not self.frame:IsShown() then
        self.frame:Show()
    end
    self:Refresh()
end

function Commander:Show()
    if not ARC:RequireCommandAuthority() then
        if self.frame then self.frame:Hide() end
        return false
    end
    ARC.db.profile.commanderUI.shown = true
    self:Refresh()
    self.frame:Show()
    return true
end

function Commander:Toggle()
    if not ARC:RequireCommandAuthority() then
        if self.frame then self.frame:Hide() end
        return false
    end
    local shown = not self.frame:IsShown()
    ARC.db.profile.commanderUI.shown = shown
    if shown then self:Show() else self.frame:Hide() end
    return shown
end
