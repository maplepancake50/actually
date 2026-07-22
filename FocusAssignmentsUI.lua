Actually = Actually or {}
local Addon = Actually
local Module = Addon.FocusAssignments

local UI = {}
Module.UI = UI

local ROW_HEIGHT = 24
local ROSTER_ROWS = 15
local ASSIGNMENT_ROWS = 13
local SetBackdrop = Addon.Util.SetBackdrop

local function MakeButton(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetWidth(width)
    button:SetHeight(height)
    button:SetText(text)
    return button
end

function UI:Create()
    if self.frame then return end
    local frame = CreateFrame("Frame", "ActuallyFocusAssignmentsFrame", UIParent)
    frame:SetWidth(800)
    frame:SetHeight(620)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 10)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    SetBackdrop(frame, { 0.025, 0.030, 0.045, 0.995 }, { 0.24, 0.72, 1.00, 1 })
    frame:Hide()
    self.frame = frame

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -15)
    title:SetText("Focus Assignments")

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    subtitle:SetText("Mark eligible DPS with the dagger. Preferred mappings survive roster changes.")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    local myPanel = CreateFrame("Frame", nil, frame)
    myPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -60)
    myPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -15, -60)
    myPanel:SetHeight(50)
    SetBackdrop(myPanel, { 0.06, 0.08, 0.12, 0.96 }, { 0.18, 0.46, 0.68, 1 })

    self.myAssignmentText = myPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.myAssignmentText:SetPoint("LEFT", myPanel, "LEFT", 12, 0)
    self.myAssignmentText:SetWidth(750)
    self.myAssignmentText:SetJustifyH("LEFT")

    local rosterPanel = CreateFrame("Frame", nil, frame)
    rosterPanel:SetPoint("TOPLEFT", myPanel, "BOTTOMLEFT", 0, -10)
    rosterPanel:SetWidth(365)
    rosterPanel:SetHeight(440)
    SetBackdrop(rosterPanel, { 0.035, 0.045, 0.065, 0.96 }, { 0.16, 0.34, 0.50, 1 })

    local rosterTitle = rosterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rosterTitle:SetPoint("TOPLEFT", rosterPanel, "TOPLEFT", 10, -10)
    rosterTitle:SetText("Raid roster")
    local rosterHint = rosterPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rosterHint:SetPoint("TOPRIGHT", rosterPanel, "TOPRIGHT", -25, -11)
    rosterHint:SetText("|cffff4545†|r eligible DPS")

    local rosterScroll = CreateFrame("ScrollFrame", "ActuallyFocusRosterScroll", rosterPanel,
        "FauxScrollFrameTemplate")
    rosterScroll:SetPoint("TOPLEFT", rosterPanel, "TOPLEFT", 6, -38)
    rosterScroll:SetPoint("BOTTOMRIGHT", rosterPanel, "BOTTOMRIGHT", -26, 8)
    self.rosterScroll = rosterScroll
    self.rosterRows = {}

    for index = 1, ROSTER_ROWS do
        local row = CreateFrame("Frame", nil, rosterPanel)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", rosterPanel, "TOPLEFT", 9, -38 - ((index - 1) * ROW_HEIGHT))
        row:SetPoint("RIGHT", rosterPanel, "RIGHT", -28, 0)
        if index % 2 == 0 then
            local shade = row:CreateTexture(nil, "BACKGROUND")
            shade:SetAllPoints(row)
            shade:SetTexture("Interface\\Buttons\\WHITE8X8")
            shade:SetVertexColor(1, 1, 1, 0.025)
        end

        local dagger = CreateFrame("Button", nil, row)
        dagger:SetWidth(24)
        dagger:SetHeight(22)
        dagger:SetPoint("LEFT", row, "LEFT", 0, 0)
        dagger.text = dagger:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        dagger.text:SetAllPoints(dagger)
        dagger:SetScript("OnClick", function(self)
            if self.member then Module:SetDPS(self.member.name, not self.member.isDPS) end
        end)
        row.dagger = dagger

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("LEFT", dagger, "RIGHT", 2, 0)
        row.name:SetWidth(132)
        row.name:SetJustifyH("LEFT")
        row.assignment = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.assignment:SetPoint("LEFT", row.name, "RIGHT", 5, 0)
        row.assignment:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.assignment:SetJustifyH("LEFT")
        self.rosterRows[index] = row
    end
    rosterScroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function() UI:RefreshRoster() end)
    end)

    local rightPanel = CreateFrame("Frame", nil, frame)
    rightPanel:SetPoint("TOPLEFT", rosterPanel, "TOPRIGHT", 10, 0)
    rightPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 70)
    SetBackdrop(rightPanel, { 0.035, 0.045, 0.065, 0.96 }, { 0.16, 0.34, 0.50, 1 })

    local targetsTitle = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    targetsTitle:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 10, -10)
    targetsTitle:SetText("Focus target names")
    local targetsHint = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    targetsHint:SetPoint("TOPRIGHT", rightPanel, "TOPRIGHT", -12, -11)
    targetsHint:SetText("one per line")

    local editBorder = CreateFrame("Frame", nil, rightPanel)
    editBorder:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 10, -32)
    editBorder:SetPoint("TOPRIGHT", rightPanel, "TOPRIGHT", -10, -32)
    editBorder:SetHeight(125)
    SetBackdrop(editBorder, { 0.012, 0.016, 0.024, 1 }, { 0.12, 0.25, 0.38, 1 })

    local targetScroll = CreateFrame("ScrollFrame", "ActuallyFocusTargetScroll", editBorder,
        "UIPanelScrollFrameTemplate")
    targetScroll:SetPoint("TOPLEFT", editBorder, "TOPLEFT", 7, -7)
    targetScroll:SetPoint("BOTTOMRIGHT", editBorder, "BOTTOMRIGHT", -27, 7)
    local targetEdit = CreateFrame("EditBox", nil, targetScroll)
    targetEdit:SetMultiLine(true)
    targetEdit:SetAutoFocus(false)
    targetEdit:SetFontObject(ChatFontNormal)
    targetEdit:SetWidth(350)
    targetEdit:SetHeight(110)
    targetEdit:SetTextInsets(2, 2, 2, 2)
    targetEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    targetEdit:SetScript("OnTextChanged", function(self)
        if self.GetNumLines then self:SetHeight(math.max(110, self:GetNumLines() * 14 + 8)) end
        targetScroll:UpdateScrollChildRect()
    end)
    targetScroll:SetScrollChild(targetEdit)
    self.targetEdit = targetEdit

    local build = MakeButton(rightPanel, "Build", 78, 25)
    build:SetPoint("TOPLEFT", editBorder, "BOTTOMLEFT", 0, -7)
    build:SetScript("OnClick", function()
        Module.db.targetsText = UI.targetEdit:GetText() or ""
        Module:BuildAssignments()
        Module:SetStatus("Assignments rebuilt.", 0.3, 1, 0.3)
    end)
    local reset = MakeButton(rightPanel, "Reset mapping", 110, 25)
    reset:SetPoint("LEFT", build, "RIGHT", 5, 0)
    reset:SetScript("OnClick", function()
        Module.db.targetsText = UI.targetEdit:GetText() or ""
        Module:ResetPreferredAssignments()
        Module:SetStatus("Saved target-to-player mapping reset.", 1, 0.8, 0.2)
    end)
    local broadcast = MakeButton(rightPanel, "Broadcast", 105, 25)
    broadcast:SetPoint("LEFT", reset, "RIGHT", 5, 0)
    broadcast:SetScript("OnClick", function()
        Module.db.targetsText = UI.targetEdit:GetText() or ""
        Module:BroadcastAssignments()
    end)

    local assignmentsTitle = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    assignmentsTitle:SetPoint("TOPLEFT", build, "BOTTOMLEFT", 0, -11)
    assignmentsTitle:SetText("Current assignments")
    local assignmentScroll = CreateFrame("ScrollFrame", "ActuallyFocusAssignmentScroll", rightPanel,
        "FauxScrollFrameTemplate")
    assignmentScroll:SetPoint("TOPLEFT", assignmentsTitle, "BOTTOMLEFT", -3, -2)
    assignmentScroll:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -25, 7)
    self.assignmentScroll = assignmentScroll
    self.assignmentRows = {}
    for index = 1, ASSIGNMENT_ROWS do
        local label = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", assignmentsTitle, "BOTTOMLEFT", 0, -6 - ((index - 1) * 17))
        label:SetWidth(370)
        label:SetJustifyH("LEFT")
        self.assignmentRows[index] = label
    end
    assignmentScroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, 17, function() UI:RefreshAssignments() end)
    end)

    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 18)
    status:SetWidth(610)
    status:SetJustifyH("LEFT")
    self.statusLabel = status
    local rescan = MakeButton(frame, "Rescan raid", 110, 25)
    rescan:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 12)
    rescan:SetScript("OnClick", function()
        Module:BuildAssignments()
        Module:SetStatus("Raid roster rescanned.", 0.3, 1, 0.3)
    end)

    targetEdit:SetText(Module.db.targetsText or "")
    self:Refresh()
end

function UI:RefreshRoster()
    if not self.rosterRows then return end
    local roster = Module:GetSortedRoster()
    local offset = FauxScrollFrame_GetOffset(self.rosterScroll)
    FauxScrollFrame_Update(self.rosterScroll, #roster, ROSTER_ROWS, ROW_HEIGHT)
    for index, row in ipairs(self.rosterRows) do
        local member = roster[index + offset]
        if member then
            row:Show()
            row.dagger.member = member
            row.dagger.text:SetText(member.isDPS and "|cffff4040†|r" or "|cff555566†|r")
            local color = RAID_CLASS_COLORS and member.classFile and RAID_CLASS_COLORS[member.classFile]
            if color then row.name:SetTextColor(color.r, color.g, color.b) else row.name:SetTextColor(1, 1, 1) end
            row.name:SetText(member.name)
            local target = Module.assignmentByPlayer[member.key]
            local acknowledgement = Module.acknowledgements and Module.acknowledgements[member.key]
            local pending = Module.pendingAcks and Module.pendingAcks[member.key]
            local acknowledgementColor = acknowledgement == "OK" and "66dd88" or "ff7777"
            local acknowledgementText = pending and " |cffffcc44[WAITING]|r"
                or (acknowledgement and (" |cff" .. acknowledgementColor .. "[" .. acknowledgement .. "]|r") or "")
            if target then
                row.assignment:SetText("|cffaaaaaa→|r " .. target .. acknowledgementText)
            elseif member.isDPS then
                row.assignment:SetText("|cff777777available|r" .. acknowledgementText)
            else
                row.assignment:SetText(acknowledgementText)
            end
        else
            row:Hide()
            row.dagger.member = nil
        end
    end
end

function UI:RefreshAssignments()
    if not self.assignmentRows then return end
    local targets = Module:ParseTargets(Module.db.targetsText)
    local offset = FauxScrollFrame_GetOffset(self.assignmentScroll)
    FauxScrollFrame_Update(self.assignmentScroll, #targets, ASSIGNMENT_ROWS, 17)
    for index, label in ipairs(self.assignmentRows) do
        local target = targets[index + offset]
        if target then
            local assignment = Module.assignments[target.key]
            if assignment and assignment.player then
                local temporary = assignment.preferred and "" or " |cffffcc33(temporary)|r"
                label:SetText("|cffffffff" .. assignment.target .. "|r  →  |cff7fd5ff"
                    .. assignment.player .. "|r" .. temporary)
            else
                label:SetText("|cffffffff" .. target.name .. "|r  →  |cffff5555unassigned|r")
            end
        else
            label:SetText("")
        end
    end
end

function UI:RefreshMyAssignment()
    if not self.myAssignmentText then return end
    local waiting, ok, failed = 0, 0, 0
    for _ in pairs(Module.pendingAcks or {}) do waiting = waiting + 1 end
    for _, status in pairs(Module.acknowledgements or {}) do
        if status == "OK" then ok = ok + 1 else failed = failed + 1 end
    end
    if Module.currentRevision then
        self.myAssignmentText:SetText(string.format(
            "Delivery: |cff66dd88%d received|r  |cffffcc44%d waiting|r  |cffff7777%d failed/no response|r",
            ok, waiting, failed))
    else
        self.myAssignmentText:SetText("Build and broadcast assignments. This module does not create or edit macros.")
    end
end

function UI:Refresh()
    if not self.frame then return end
    self:RefreshRoster()
    self:RefreshAssignments()
    self:RefreshMyAssignment()
    local color = Module.statusColor or { 0.75, 0.8, 0.9 }
    self.statusLabel:SetText(Module.statusText or "Configuration unavailable.")
    self.statusLabel:SetTextColor(color[1], color[2], color[3])
end

function UI:Show()
    if not self.frame then self:Create() end
    if not Module:CanPublish() then
        Addon:Print("Focus Assignments configuration is restricted to actually officers and leaders.")
        return
    end
    Module:BuildAssignments()
    self:Refresh()
    self.frame:Show()
end

function UI:Toggle()
    if not self.frame then self:Create() end
    if self.frame:IsShown() then self.frame:Hide() else self:Show() end
end
