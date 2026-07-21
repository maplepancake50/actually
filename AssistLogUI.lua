Actually = Actually or {}
local Addon = Actually

-- Standalone Assist Log window, visually aligned with TierBoard.lua without
-- attaching itself to the tier-board navigation. Open with /actually assistlog.
local UI = {}
Addon.AssistLogUI = UI

local WIDTH = 970
local ROW_HEIGHT = 24
local LOGO = "Interface\\AddOns\\actually\\Textures\\AssistLogLogo"

local COLORS = {
    panel = { 0.025, 0.030, 0.045, 0.995 },
    inset = { 0.035, 0.040, 0.055, 0.98 },
    rowA = { 0.045, 0.050, 0.065, 0.94 },
    rowB = { 0.060, 0.065, 0.080, 0.94 },
    border = { 0.20, 0.55, 0.75, 1 },
    cyan = { 0.35, 0.78, 1.00, 1 },
    gold = { 1.00, 0.78, 0.22, 1 },
    green = { 0.45, 1.00, 0.55, 1 },
    amber = { 1.00, 0.85, 0.35, 1 },
    red = { 1.00, 0.48, 0.42, 1 },
    muted = { 0.57, 0.63, 0.70, 1 },
    text = { 0.88, 0.92, 0.97, 1 },
}

local function FormatTime(seconds, tenths)
    seconds = math.max(0, tonumber(seconds) or 0)
    local minutes = math.floor(seconds / 60)
    local remainder = seconds - minutes * 60
    return tenths and string.format("%02d:%04.1f", minutes, remainder)
        or string.format("%02d:%02d", minutes, math.floor(remainder))
end

local function FightLabel(fight)
    local label = Addon.Util.Trim(fight and fight.label)
    return label ~= "" and label or "Raid fight"
end

local function DateLabel(epoch)
    return date and date("%Y-%m-%d %H:%M", epoch or 0) or tostring(epoch or "")
end

local function FindFight(runID)
    for _, fight in ipairs(Addon.RaidTargets:GetFights()) do
        if fight.id == runID then return fight end
    end
end

local function ResultColor(percent)
    percent = tonumber(percent) or 0
    if percent >= 90 then return COLORS.green end
    if percent >= 70 then return COLORS.amber end
    return COLORS.red
end

local function TeamResult(fight)
    local matched, eligible, received = 0, 0, 0
    for _, row in ipairs(Addon.RaidTargets:BuildFightOverview(fight) or {}) do
        if not row.isCaller and row.matchedSeconds then
            matched = matched + row.matchedSeconds
            eligible = eligible + row.eligibleSeconds
            received = received + 1
        end
    end
    return matched, eligible, eligible > 0 and (matched / eligible * 100) or 0, received
end

local function StyleButton(button, text, width, accent)
    accent = accent or COLORS.border
    button:SetWidth(width or 80)
    button:SetHeight(24)
    button:SetText(text)
    button:SetNormalFontObject("GameFontNormalSmall")
    button:SetHighlightFontObject("GameFontHighlightSmall")
    button:SetDisabledFontObject("GameFontDisableSmall")
    Addon.Util.SetBackdrop(button, { 0.045, 0.055, 0.075, 0.98 }, accent)
    button:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.90, 0.95, 1.00, 1)
        self:SetBackdropColor(0.075, 0.095, 0.125, 1)
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(accent[1], accent[2], accent[3], accent[4] or 1)
        self:SetBackdropColor(0.045, 0.055, 0.075, 0.98)
    end)
end

if StaticPopupDialogs then
    StaticPopupDialogs.ACTUALLY_ASSISTLOG_DELETE_FIGHT = {
        text = "Delete the entire Assist Log fight '%s'?\n\nThis permanently removes every player's contribution from officer history.",
        button1 = YES,
        button2 = NO,
        OnAccept = function()
            local ui = Addon.AssistLogUI
            if ui.pendingDeleteFightID then
                Addon.RaidTargets:DeleteFight(ui.pendingDeleteFightID)
                ui.pendingDeleteFightID = nil
                local last = Addon.RaidTargets:GetLastFight()
                ui.selectedFightID = last and last.id or nil
                ui.view = "history"
                ui.returnView = nil
                ui:Refresh()
            end
        end,
        OnCancel = function() Addon.AssistLogUI.pendingDeleteFightID = nil end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopupDialogs.ACTUALLY_ASSISTLOG_REMOVE_PLAYER = {
        text = "Remove %s's contribution from this fight?\n\nIt will be excluded from the fight and Overall Performance views.",
        button1 = YES,
        button2 = NO,
        OnAccept = function()
            local ui = Addon.AssistLogUI
            if ui.pendingRemoveFightID and ui.pendingRemovePlayerKey then
                local ok, errorMessage = Addon.RaidTargets:DeletePlayerContribution(
                    ui.pendingRemoveFightID, ui.pendingRemovePlayerKey)
                if not ok and errorMessage then Addon:Print(errorMessage) end
                ui.selectedFightID = ui.pendingRemoveFightID
                ui.pendingRemoveFightID = nil
                ui.pendingRemovePlayerKey = nil
                ui.view = "fight"
                ui.returnView = nil
                ui:Refresh()
            end
        end,
        OnCancel = function()
            Addon.AssistLogUI.pendingRemoveFightID = nil
            Addon.AssistLogUI.pendingRemovePlayerKey = nil
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

function UI:Create()
    if self.frame then return self.frame end

    local parent = Addon.Board and Addon.Board.frame
    if not parent then return nil end

    local frame = CreateFrame("Frame", "ActuallyAssistLogFrame", parent)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, -5)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -5, 156)
    frame:SetFrameLevel(parent:GetFrameLevel() + 21)
    Addon.Util.SetBackdrop(frame, COLORS.panel, COLORS.border)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function()
        if Addon.Board and Addon.Board.frame and not Addon.Board.dragging then
            Addon.Board.frame:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function()
        if Addon.Board and Addon.Board.frame then
            Addon.Board.frame:StopMovingOrSizing()
        end
    end)

    local logoBadge = CreateFrame("Frame", nil, frame)
    logoBadge:SetWidth(58); logoBadge:SetHeight(58)
    logoBadge:SetPoint("TOPLEFT", frame, "TOPLEFT", 13, -11)
    Addon.Util.SetBackdrop(logoBadge, { 0.08, 0.055, 0.018, 0.98 }, { 1.0, 0.76, 0.18, 1 })
    local logo = logoBadge:CreateTexture(nil, "ARTWORK")
    logo:SetPoint("TOPLEFT", logoBadge, "TOPLEFT", 3, -3)
    logo:SetPoint("BOTTOMRIGHT", logoBadge, "BOTTOMRIGHT", -3, 3)
    logo:SetTexture(LOGO)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 84, -14)
    title:SetText("Assist Log")
    title:SetTextColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -4)
    subtitle:SetText("Tracks whether DPS are using /assist")
    subtitle:SetTextColor(0.52, 0.62, 0.72)

    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -43, -26)
    status:SetJustifyH("RIGHT")
    frame.status = status

    local divider = frame:CreateTexture(nil, "BACKGROUND")
    divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -78)
    divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -78)
    divider:SetHeight(2)
    divider:SetTexture("Interface\\Buttons\\WHITE8X8")
    divider:SetVertexColor(0.20, 0.55, 0.75, 0.45)

    local toolbar = CreateFrame("Frame", nil, frame)
    toolbar:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -86)
    toolbar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -86)
    toolbar:SetHeight(34)
    Addon.Util.SetBackdrop(toolbar, COLORS.inset, { 0.13, 0.32, 0.43, 1 })

    local labelBox = CreateFrame("EditBox", "ActuallyAssistLogLabel", toolbar, "InputBoxTemplate")
    labelBox:SetWidth(155); labelBox:SetHeight(20)
    labelBox:SetPoint("LEFT", toolbar, "LEFT", 12, 0)
    labelBox:SetAutoFocus(false); labelBox:SetMaxLetters(60); labelBox:SetText("Raid fight")
    labelBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    labelBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    frame.labelBox = labelBox

    local start = CreateFrame("Button", nil, toolbar)
    StyleButton(start, "Start", 62, { 0.25, 0.85, 0.42, 1 })
    start:SetPoint("LEFT", labelBox, "RIGHT", 10, 0)
    start:SetScript("OnClick", function()
        local run, errorMessage = Addon.RaidTargets:Start(labelBox:GetText())
        if not run then Addon:Print(errorMessage); return end
        Addon:Print("Assist Log started. Raid addon users are recording their selected targets.")
        UI.view = "active"
        UI:Refresh()
    end)
    frame.start = start

    local stop = CreateFrame("Button", nil, toolbar)
    StyleButton(stop, "Stop", 62, { 0.90, 0.30, 0.28, 1 })
    stop:SetPoint("LEFT", start, "RIGHT", 6, 0)
    stop:SetScript("OnClick", function()
        local fight, errorMessage = Addon.RaidTargets:Stop()
        if not fight then Addon:Print(errorMessage); return end
        Addon:Print("Assist Log stopped. Waiting for raid uploads.")
        UI.selectedFightID = fight.id
        UI.view = "fight"
        UI:Refresh()
    end)
    frame.stop = stop

    local last = CreateFrame("Button", nil, toolbar)
    StyleButton(last, "Last Fight", 78)
    last:SetPoint("LEFT", stop, "RIGHT", 18, 0)
    last:SetScript("OnClick", function()
        local fight = Addon.RaidTargets:GetLastFight()
        UI.selectedFightID = fight and fight.id or nil
        UI.returnView = nil
        UI.view = fight and "fight" or "empty"
        UI:Refresh()
    end)
    frame.last = last

    local history = CreateFrame("Button", nil, toolbar)
    StyleButton(history, "All Fights", 78)
    history:SetPoint("LEFT", last, "RIGHT", 6, 0)
    history:SetScript("OnClick", function() UI.view = "history"; UI.returnView = nil; UI:Refresh() end)
    frame.history = history

    local overall = CreateFrame("Button", nil, toolbar)
    StyleButton(overall, "Overall Performance", 126, { 0.80, 0.62, 0.16, 1 })
    overall:SetPoint("LEFT", history, "RIGHT", 6, 0)
    overall:SetScript("OnClick", function() UI.view = "overall"; UI.returnView = nil; UI:Refresh() end)
    frame.overall = overall

    local back = CreateFrame("Button", nil, toolbar)
    StyleButton(back, "Back", 54)
    back:SetPoint("LEFT", overall, "RIGHT", 10, 0)
    back:SetScript("OnClick", function()
        local destination = UI.returnView or (UI.view == "playerHistory" and "overall" or "fight")
        UI.view = destination
        -- Preserve the second leg of player -> player history -> overall.
        UI.returnView = destination == "playerHistory" and "overall" or nil
        UI:Refresh()
    end)
    back:Hide()
    frame.back = back

    local deleteAction = CreateFrame("Button", nil, toolbar)
    StyleButton(deleteAction, "Delete Fight", 96, { 0.80, 0.25, 0.22, 1 })
    deleteAction:SetPoint("RIGHT", toolbar, "RIGHT", -8, 0)
    deleteAction:Hide()
    frame.deleteAction = deleteAction

    local contentPanel = CreateFrame("Frame", nil, frame)
    contentPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -128)
    contentPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
    Addon.Util.SetBackdrop(contentPanel, { 0.018, 0.022, 0.034, 0.99 }, { 0.13, 0.32, 0.43, 1 })

    local scroll = CreateFrame("ScrollFrame", "ActuallyAssistLogScroll", contentPanel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", contentPanel, "TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", contentPanel, "BOTTOMRIGHT", -28, 8)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(WIDTH - 76)
    child:SetHeight(460)
    scroll:SetScrollChild(child)
    frame.scroll, frame.child, frame.rows = scroll, child, {}

    frame:SetScript("OnUpdate", function(_, elapsed)
        UI.elapsed = (UI.elapsed or 0) + elapsed
        if UI.elapsed >= 0.5 then UI.elapsed = 0; UI:RefreshStatus() end
    end)
    frame:SetScript("OnShow", function()
        if Addon.Board then Addon.Board:RefreshAssistTrackerTab() end
    end)
    frame:SetScript("OnHide", function()
        if Addon.Board then Addon.Board:RefreshAssistTrackerTab() end
    end)

    self.frame = frame
    self.view = "fight"
    frame:Hide()
    return frame
end

function UI:ResizeToParent(bottom)
    if not self.frame or not Addon.Board or not Addon.Board.frame then return end
    self.frame:ClearAllPoints()
    self.frame:SetPoint("TOPLEFT", Addon.Board.frame, "TOPLEFT", 5, -5)
    self.frame:SetPoint("BOTTOMRIGHT", Addon.Board.frame, "BOTTOMRIGHT", -5, tonumber(bottom) or 156)
end

function UI:SetVisible(visible)
    if not visible then
        if self.frame then self.frame:Hide() end
        return
    end
    if not Addon.RaidTargets:CanControl() then return end
    self:Create()
    if not self.frame then return end
    if Addon.RaidTargets:IsRunning() then self.view = "active"
    elseif Addon.RaidTargets:GetLastFight() then
        self.view = self.view or "fight"
        self.selectedFightID = self.selectedFightID or Addon.RaidTargets:GetLastFight().id
    else self.view = "empty" end
    self:Refresh()
    self.frame:Show()
end

function UI:AcquireRow(index)
    local row = self.frame.rows[index]
    if row then row:Show(); return row end
    row = CreateFrame("Button", nil, self.frame.child)
    row:SetWidth(WIDTH - 88); row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", self.frame.child, "TOPLEFT", 2, -(index - 1) * ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp")
    Addon.Util.SetBackdrop(row, COLORS.rowA, { 0.10, 0.16, 0.22, 0.7 })
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", row, "LEFT", 9, 0)
    text:SetPoint("RIGHT", row, "RIGHT", -9, 0)
    text:SetJustifyH("LEFT")
    row.text = text
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(row)
    highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
    highlight:SetVertexColor(0.20, 0.65, 0.90, 0.16)
    self.frame.rows[index] = row
    return row
end

function UI:ClearRows()
    for _, row in ipairs(self.frame.rows) do
        row:Hide(); row:SetScript("OnClick", nil)
    end
    self.rowCount = 0
    self.frame.scroll:SetVerticalScroll(0)
end

function UI:AddRow(text, onClick, color, kind)
    self.rowCount = (self.rowCount or 0) + 1
    local row = self:AcquireRow(self.rowCount)
    row.text:SetText(text or "")
    color = color or COLORS.text
    row.text:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    row:SetScript("OnClick", onClick)
    row:EnableMouse(onClick ~= nil)
    if kind == "header" then
        row:SetBackdropColor(0.055, 0.085, 0.115, 0.98)
        row:SetBackdropBorderColor(0.20, 0.55, 0.75, 0.8)
    elseif kind == "spacer" then
        row:SetBackdropColor(0.018, 0.022, 0.034, 0)
        row:SetBackdropBorderColor(0, 0, 0, 0)
    else
        local base = self.rowCount % 2 == 0 and COLORS.rowA or COLORS.rowB
        row:SetBackdropColor(base[1], base[2], base[3], base[4])
        row:SetBackdropBorderColor(0.10, 0.16, 0.22, 0.7)
    end
    return row
end

function UI:FinishRows()
    self.frame.child:SetHeight(math.max(460, (self.rowCount or 0) * ROW_HEIGHT + 8))
    self.frame.scroll:UpdateScrollChildRect()
end

function UI:RefreshStatus()
    if not self.frame then return end
    local active = Addon.RaidTargets:GetActiveRun()
    local pending = Addon.RaidTargets:GetPendingUploadCount()
    local canControl = Addon.RaidTargets:CanControl()
    if active then
        self.frame.status:SetText("|cff55ff77RECORDING  " .. FormatTime(GetTime() - active.startedAt) .. "|r")
    elseif pending > 0 then
        self.frame.status:SetText("|cffffcc55Pending officer acknowledgement: " .. pending .. "|r")
    else
        self.frame.status:SetText(canControl
            and ("|cff69ccf0Officer ready|r  |cffffc738Caller: "
                .. tostring(Addon.RaidTargets:GetSelectedCaller()) .. "|r")
            or "|cff888f99Observer mode|r")
    end
    if active then
        self.frame.start:Disable(); self.frame.stop:Enable()
    else
        if canControl then self.frame.start:Enable() else self.frame.start:Disable() end
        self.frame.stop:Disable()
    end
end

function UI:ConfigureContextAction()
    local button = self.frame.deleteAction
    button:Hide(); button:SetScript("OnClick", nil)
    if self.view == "fight" and self.selectedFightID then
        local fight = FindFight(self.selectedFightID)
        if fight then
            button:SetText("Delete Fight")
            button:SetScript("OnClick", function() UI:RequestDeleteFight(fight) end)
            button:Show()
        end
    elseif self.view == "player" and self.selectedFightID and self.selectedPlayerKey then
        local fight = FindFight(self.selectedFightID)
        local player = fight and fight.players and fight.players[self.selectedPlayerKey]
        if fight and player and self.selectedPlayerKey ~= fight.callerKey and player.status == "received" then
            button:SetText("Remove Contribution")
            button:SetWidth(128)
            button:SetScript("OnClick", function() UI:RequestRemoveContribution(fight, self.selectedPlayerKey) end)
            button:Show()
            return
        end
    end
    button:SetWidth(96)
end

function UI:RequestDeleteFight(fight)
    if not fight then return end
    self.pendingDeleteFightID = fight.id
    if StaticPopup_Show then
        StaticPopup_Show("ACTUALLY_ASSISTLOG_DELETE_FIGHT", FightLabel(fight))
    end
end

function UI:RequestRemoveContribution(fight, playerKey)
    local player = fight and fight.players and fight.players[playerKey]
    if not player then return end
    self.pendingRemoveFightID = fight.id
    self.pendingRemovePlayerKey = playerKey
    if StaticPopup_Show then
        StaticPopup_Show("ACTUALLY_ASSISTLOG_REMOVE_PLAYER", player.name or "player")
    end
end

function UI:ShowActive()
    local run = Addon.RaidTargets:GetActiveRun()
    if not run then self:AddRow("No Assist Log is recording.", nil, COLORS.muted); return end
    self:AddRow("RECORDING  " .. FightLabel(run), nil, COLORS.green, "header")
    self:AddRow("Controller: " .. tostring(run.officer) .. "     Shot caller: "
        .. tostring(run.caller or run.officer) .. "     Elapsed: " .. FormatTime(GetTime() - run.startedAt))
    self:AddRow("", nil, nil, "spacer")
    self:AddRow("RAID ADDON RESPONSES", nil, COLORS.cyan, "header")
    local players = {}
    for _, player in pairs(run.players or {}) do table.insert(players, player) end
    table.sort(players, function(a, b) return string.lower(a.name or "") < string.lower(b.name or "") end)
    for _, player in ipairs(players) do
        self:AddRow(string.format("%-30s %s", player.name or "?", player.status or "waiting"))
    end
end

function UI:ShowHistory()
    self:AddRow("ALL FIGHTS", nil, COLORS.cyan, "header")
    self:AddRow("Every retained fight with its weighted raid-wide follower result.", nil, COLORS.muted)
    self:AddRow("", nil, nil, "spacer")
    local fights = Addon.RaidTargets:GetFights()
    if #fights == 0 then self:AddRow("No completed fights have been saved.", nil, COLORS.muted); return end
    for index = #fights, 1, -1 do
        local fight = fights[index]
        local _, eligible, percent, received = TeamResult(fight)
        local result = eligible > 0 and string.format("raid match %5.1f%%  (%d followers)", percent, received)
            or "waiting for follower data"
        local text = string.format("%s   %-27s  %s   %s", DateLabel(fight.startedEpoch),
            FightLabel(fight), FormatTime(fight.duration), result)
        self:AddRow(text, function()
            UI.selectedFightID = fight.id; UI.returnView = "history"; UI.view = "fight"; UI:Refresh()
        end, eligible > 0 and ResultColor(percent) or COLORS.muted)
    end
end

function UI:ShowOverall()
    self:AddRow("OVERALL PERFORMANCE", nil, COLORS.gold, "header")
    self:AddRow("Weighted by actual shot-caller target time across every retained contribution.", nil, COLORS.muted)
    self:AddRow("Removed contributions and fights with missing data are excluded.", nil, COLORS.muted)
    self:AddRow("", nil, nil, "spacer")
    self:AddRow("PLAYER                         FIGHTS       SAME / CALLER TARGET TIME          OVERALL", nil,
        COLORS.cyan, "header")
    local rows = Addon.RaidTargets:BuildOverallPerformance()
    if #rows == 0 then self:AddRow("No follower contributions are available yet.", nil, COLORS.muted); return end
    for _, result in ipairs(rows) do
        local playerKey = result.key
        self:AddRow(string.format("%-30s %3d          %s / %s                 %5.1f%%", result.name,
            result.fightCount, FormatTime(result.matchedSeconds, true),
            FormatTime(result.eligibleSeconds, true), result.percent), function()
                UI.selectedPlayerKey = playerKey; UI.returnView = "overall"; UI.view = "playerHistory"; UI:Refresh()
            end, ResultColor(result.percent))
    end
end

function UI:ShowPlayerHistory(playerKey)
    local rows = Addon.RaidTargets:BuildPlayerHistory(playerKey)
    local firstFight = rows[1] and FindFight(rows[1].fightID)
    local firstPlayer = firstFight and firstFight.players and firstFight.players[playerKey]
    local name = firstPlayer and firstPlayer.name or playerKey
    self:AddRow("PLAYER HISTORY  " .. tostring(name), nil, COLORS.gold, "header")
    self:AddRow("Every fight in which this player appeared. Click a received fight for interval details.", nil, COLORS.muted)
    self:AddRow("", nil, nil, "spacer")
    for _, result in ipairs(rows) do
        local text
        local color = COLORS.muted
        if result.isCaller then
            text = string.format("%s   %-28s  SHOT CALLER", DateLabel(result.startedEpoch), FightLabel(result))
            color = COLORS.gold
        elseif result.matchedSeconds then
            text = string.format("%s   %-28s  %s / %s   %5.1f%%", DateLabel(result.startedEpoch),
                FightLabel(result), FormatTime(result.matchedSeconds, true),
                FormatTime(result.eligibleSeconds, true), result.percent)
            color = ResultColor(result.percent)
        else
            text = string.format("%s   %-28s  %s", DateLabel(result.startedEpoch), FightLabel(result), result.status or "no data")
        end
        local clickable = result.matchedSeconds and function()
            UI.selectedFightID = result.fightID; UI.returnView = "playerHistory"; UI.view = "player"; UI:Refresh()
        end or nil
        self:AddRow(text, clickable, color)
    end
end

function UI:ShowFight(fight)
    if not fight then self:AddRow("No completed fight is available.", nil, COLORS.muted); return end
    self:AddRow(FightLabel(fight), nil, COLORS.gold, "header")
    local _, eligible, teamPercent, followers = TeamResult(fight)
    local teamText = eligible > 0 and string.format("Raid follower match: %.1f%% across %d received timelines", teamPercent, followers)
        or "Raid follower match: waiting for data"
    self:AddRow("Duration: " .. FormatTime(fight.duration, true) .. "     Controller: " .. tostring(fight.officer)
        .. "     Shot caller: " .. tostring(fight.caller or ((fight.players[fight.callerKey] or {}).name) or "?") )
    self:AddRow(teamText)
    self:AddRow("Click a follower to inspect exact matching and wrong-target intervals.", nil, COLORS.muted)
    self:AddRow("", nil, nil, "spacer")
    self:AddRow("PLAYER                         SAME TARGET / CALLER TARGET TIME            MATCH", nil,
        COLORS.cyan, "header")
    for _, result in ipairs(Addon.RaidTargets:BuildFightOverview(fight) or {}) do
        local text, color, clickable
        if result.isCaller then
            text = string.format("%-30s SHOT CALLER", result.name or "?")
            color = COLORS.gold
        elseif result.matchedSeconds then
            text = string.format("%-30s %s / %s                         %5.1f%%", result.name,
                FormatTime(result.matchedSeconds, true), FormatTime(result.eligibleSeconds, true), result.percent)
            color = ResultColor(result.percent)
            local playerKey = result.key
            clickable = function()
                UI.selectedFightID = fight.id; UI.selectedPlayerKey = playerKey
                UI.returnView = "fight"; UI.view = "player"; UI:Refresh()
            end
        else
            text = string.format("%-30s %s", result.name or "?", result.status or "no data")
            color = COLORS.muted
        end
        self:AddRow(text, clickable, color)
    end
end

function UI:ShowPlayer(fight, playerKey)
    local analysis, errorMessage = Addon.RaidTargets:BuildPlayerAnalysis(fight, playerKey)
    if not analysis then self:AddRow(errorMessage or "Player analysis unavailable.", nil, COLORS.red); return end
    self:AddRow(analysis.playerName .. "  vs  " .. analysis.callerName, nil, COLORS.gold, "header")
    self:AddRow(string.format("Same exact target: %s of %s  (%.1f%%)",
        FormatTime(analysis.matchedSeconds, true), FormatTime(analysis.eligibleSeconds, true), analysis.percent),
        nil, ResultColor(analysis.percent))
    self:AddRow("Green is an exact GUID match. Red shows what the caller and follower selected instead.", nil, COLORS.muted)
    self:AddRow("", nil, nil, "spacer")
    for _, segment in ipairs(analysis.segments) do
        if segment.eligible then
            if segment.match then
                self:AddRow(string.format("%s - %s   MATCH   %5.1fs   %s", FormatTime(segment.startAt, true),
                    FormatTime(segment.endAt, true), segment.duration, segment.callerTarget), nil, COLORS.green)
            else
                self:AddRow(string.format("%s - %s   WRONG   %5.1fs   caller: %s   follower: %s",
                    FormatTime(segment.startAt, true), FormatTime(segment.endAt, true), segment.duration,
                    segment.callerTarget, segment.playerTarget), nil, COLORS.red)
            end
        end
    end
end

function UI:Refresh()
    self:Create(); self:ClearRows()
    local nested = self.view == "player" or self.view == "playerHistory"
        or (self.view == "fight" and self.returnView == "history")
    if nested then self.frame.back:Show() else self.frame.back:Hide() end
    self:ConfigureContextAction()

    if self.view == "active" then self:ShowActive()
    elseif self.view == "history" then self:ShowHistory()
    elseif self.view == "overall" then self:ShowOverall()
    elseif self.view == "playerHistory" then self:ShowPlayerHistory(self.selectedPlayerKey)
    elseif self.view == "player" then self:ShowPlayer(FindFight(self.selectedFightID), self.selectedPlayerKey)
    elseif self.view == "fight" then
        local fight = FindFight(self.selectedFightID) or Addon.RaidTargets:GetLastFight()
        if fight then self.selectedFightID = fight.id end
        self:ShowFight(fight)
    else self:AddRow("No completed fight is available.", nil, COLORS.muted) end
    self:FinishRows(); self:RefreshStatus()
end

function UI:OnDataChanged()
    if self.frame and self.frame:IsShown() then self:Refresh() end
end

function UI:Show()
    if not Addon.RaidTargets:CanControl() then
        return
    end
    if Addon.Board and Addon.Board.frame then
        Addon.Board.frame:Show()
        Addon.Board:SetSection("assist")
    end
end
