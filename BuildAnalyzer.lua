Actually = Actually or {}
local Addon = Actually

local Analyzer = {}
Addon.Analyzer = Analyzer

local TIERS = { "S", "A", "B", "C", "D" }
local TIER_SCORE = { S = 5, A = 4, B = 3, C = 2, D = 1 }
local SCORE_TIER = { [1] = "D", [2] = "C", [3] = "B", [4] = "A", [5] = "S" }
local TIER_COLORS = {
    S = { 0.96, 0.30, 0.30 },
    A = { 1.00, 0.61, 0.24 },
    B = { 0.98, 0.83, 0.28 },
    C = { 0.39, 0.82, 0.42 },
    D = { 0.40, 0.63, 0.96 },
}

local function SetBackdrop(frame, color, borderColor)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(color[1], color[2], color[3], color[4] or 1)
    frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
end

local function NormalizedName(name)
    return string.lower(name or "")
end

local function SpellIDFromLink(link)
    if type(link) ~= "string" then
        return nil
    end
    return tonumber(string.match(link, "spell:(%d+)"))
end

function Analyzer:GetKnownSpells()
    local byName = {}
    local bookType = BOOKTYPE_SPELL or "spell"
    local tabCount = GetNumSpellTabs and GetNumSpellTabs() or 0

    for tabIndex = 1, tabCount do
        local _, _, offset, count = GetSpellTabInfo(tabIndex)
        offset = tonumber(offset) or 0
        count = tonumber(count) or 0

        for spellIndex = offset + 1, offset + count do
            local name = GetSpellName and GetSpellName(spellIndex, bookType)
            if not name and GetSpellInfo then
                name = GetSpellInfo(spellIndex, bookType)
            end

            if name then
                local spellID
                if GetSpellBookItemInfo then
                    local _, itemID = GetSpellBookItemInfo(spellIndex, bookType)
                    spellID = tonumber(itemID)
                end
                if not spellID and GetSpellLink then
                    spellID = SpellIDFromLink(GetSpellLink(spellIndex, bookType))
                end

                local key = NormalizedName(name)
                byName[key] = {
                    id = spellID,
                    name = name,
                }
            end
        end
    end

    local spells = {}
    for _, spell in pairs(byName) do
        table.insert(spells, spell)
    end
    return spells
end

function Analyzer:GetOfficialRankings()
    local byID = {}
    local byName = {}
    local official = Addon.db and Addon.db.lists and Addon.db.lists.official
    local board = official and official.board or {}

    for _, tier in ipairs(TIERS) do
        for _, key in ipairs(board[tier] or {}) do
            local spell = Addon.Board and Addon.Board.spellsByKey and Addon.Board.spellsByKey[key]
            local spellID = spell and spell.spellID or tonumber(string.match(key or "", "^spell:(%d+)$"))
            local name = spell and spell.name
            if not name and spellID and GetSpellInfo then
                name = GetSpellInfo(spellID)
            end

            if spellID then
                local ranking = {
                    key = key,
                    id = spellID,
                    name = name or ("Spell " .. tostring(spellID)),
                    icon = spell and spell.icon,
                    tier = tier,
                    score = TIER_SCORE[tier],
                }
                if not ranking.icon and GetSpellInfo then
                    local _, _, icon = GetSpellInfo(spellID)
                    ranking.icon = icon
                end
                ranking.icon = ranking.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
                byID[spellID] = ranking
                if name then
                    byName[NormalizedName(name)] = ranking
                end
            end
        end
    end

    return byID, byName
end

function Analyzer:Calculate()
    local known = self:GetKnownSpells()
    local officialByID, officialByName = self:GetOfficialRankings()
    local matchedByKey = {}
    local matches = {}
    local scoreTotal = 0

    for _, knownSpell in ipairs(known) do
        local ranking = knownSpell.id and officialByID[knownSpell.id]
        if not ranking then
            ranking = officialByName[NormalizedName(knownSpell.name)]
        end
        if ranking and not matchedByKey[ranking.key] then
            matchedByKey[ranking.key] = true
            table.insert(matches, ranking)
            scoreTotal = scoreTotal + ranking.score
        end
    end

    table.sort(matches, function(left, right)
        if left.score ~= right.score then
            return left.score > right.score
        end
        return NormalizedName(left.name) < NormalizedName(right.name)
    end)

    local average
    local grade
    if #matches > 0 then
        average = scoreTotal / #matches
        grade = SCORE_TIER[math.max(1, math.min(5, math.floor(average + 0.5)))]
    end

    return {
        matches = matches,
        knownCount = #known,
        ignoredCount = math.max(0, #known - #matches),
        average = average,
        grade = grade,
    }
end

function Analyzer:SetProgress(percent)
    percent = math.max(1, math.min(100, math.floor(percent)))
    self.progressFill:SetWidth(math.max(3, 220 * percent / 100))
    self.progressText:SetText(tostring(percent) .. "%")

    if percent < 28 then
        self.statusText:SetText("Opening your spellbook...")
    elseif percent < 62 then
        self.statusText:SetText("Checking official rankings...")
    elseif percent < 88 then
        self.statusText:SetText("Comparing utility spells...")
    else
        self.statusText:SetText("Calculating your average...")
    end
end

function Analyzer:AttachProgressToPet()
    if not self.progressFrame then
        return
    end

    self.progressFrame:ClearAllPoints()
    if Addon.Pet and Addon.Pet.frame then
        self.progressFrame:SetPoint("BOTTOM", Addon.Pet.frame, "TOP", 0, 8)
    else
        self.progressFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 90)
    end
end

function Analyzer:AttachToPet()
    if not self.frame or not Addon.Pet or not Addon.Pet.frame then
        return false
    end

    local pet = Addon.Pet.frame
    local petX = pet:GetCenter()
    local screenX = UIParent:GetCenter()

    self.frame:ClearAllPoints()
    if petX and screenX and petX < screenX then
        self.frame:SetPoint("LEFT", pet, "RIGHT", 18, 0)
    else
        self.frame:SetPoint("RIGHT", pet, "LEFT", -18, 0)
    end
    return true
end

function Analyzer:UpdateRows(matches)
    for _, row in ipairs(self.rows) do
        row:Hide()
    end

    local rowHeight = 42
    for index, spell in ipairs(matches) do
        local row = self.rows[index]
        if not row then
            row = CreateFrame("Button", nil, self.resultsCanvas)
            row:SetWidth(386)
            row:SetHeight(rowHeight)
            SetBackdrop(row, { 0.055, 0.06, 0.075, 0.96 }, { 0.18, 0.21, 0.26, 1 })

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetWidth(32)
            row.icon:SetHeight(32)
            row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 9, 1)
            row.nameText:SetWidth(280)
            row.nameText:SetJustifyH("LEFT")

            row.tierText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            row.tierText:SetPoint("RIGHT", row, "RIGHT", -13, 0)

            row:SetScript("OnEnter", function(self)
                if self.spellID then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink("spell:" .. tostring(self.spellID))
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            self.rows[index] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.resultsCanvas, "TOPLEFT", 0, -(index - 1) * (rowHeight + 3))
        row.icon:SetTexture(spell.icon)
        row.nameText:SetText(spell.name)
        row.tierText:SetText(spell.tier)
        local color = TIER_COLORS[spell.tier]
        row.tierText:SetTextColor(color[1], color[2], color[3])
        row.spellID = spell.id
        row:Show()
    end

    local contentHeight = math.max(252, #matches * (rowHeight + 3))
    self.resultsCanvas:SetHeight(contentHeight)
    local maximum = math.max(0, contentHeight - 252)
    self.resultsBar:SetMinMaxValues(0, maximum)
    self.resultsBar:SetValue(0)
    if maximum > 0 then
        self.resultsBar:Show()
    else
        self.resultsBar:Hide()
    end
end

function Analyzer:ShowResults()
    self.running = false
    self.progressFrame:Hide()
    self.resultsPanel:Show()
    self.startButton:Enable()
    self.startButton:SetText("Analyse Again")

    local result = self.pendingResult
    self:UpdateRows(result.matches)

    if result.grade then
        local color = TIER_COLORS[result.grade]
        self.gradeText:SetText(result.grade)
        self.gradeText:SetTextColor(color[1], color[2], color[3])
        self.summaryText:SetText(
            tostring(#result.matches) .. " official-ranked spells found  |  " ..
            tostring(result.ignoredCount) .. " unlisted spells ignored"
        )
        self.emptyText:Hide()
        self.resultsViewport:Show()
    else
        self.gradeText:SetText("--")
        self.gradeText:SetTextColor(0.65, 0.68, 0.72)
        self.summaryText:SetText("No official-ranked known spells found")
        self.resultsViewport:Hide()
        self.resultsBar:Hide()
        self.emptyText:SetText("Nothing was scored. Add spells to the Official Tier List, or learn one of its ranked spells, then try again.")
        self.emptyText:Show()
    end

    if not self.detached and not self:AttachToPet() then
        self.frame:ClearAllPoints()
        self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 15)
    end
    self.frame:Show()

    if Addon.Pet then
        Addon.Pet:Play("happy")
        Addon.Pet:ShowBubble(result.grade and ("Your build is " .. result.grade .. " tier!") or "No ranked spells yet!", 2.4)
    end
end

function Analyzer:Start()
    if self.running then
        return
    end

    if self.frame:IsShown() then
        self.frame:Hide()
    end
    self.pendingResult = self:Calculate()
    self.elapsed = 0
    self.duration = 4 + math.random() * 3
    self.running = true
    self:SetProgress(1)
    self.resultsPanel:Hide()
    self.startButton:Disable()
    self.startButton:SetText("Analysing...")

    if Addon.Pet then
        Addon.Pet:Show()
        Addon.Pet:HideBubble()
        Addon.Pet:Play("research")
    end

    self:AttachProgressToPet()
    self.progressFrame:Show()
end

function Analyzer:Cancel()
    if not self.running then
        return
    end

    self.running = false
    self.progressFrame:Hide()
    self.startButton:Enable()
    self.startButton:SetText("Analyse Again")
    if Addon.Pet and Addon.Pet.animationName == "research" then
        Addon.Pet:FinishAnimation()
    end
end

function Analyzer:Update(elapsed)
    if not self.running then
        return
    end

    self.elapsed = self.elapsed + elapsed
    local progress = math.min(1, self.elapsed / self.duration)
    self:SetProgress(math.max(1, math.floor(progress * 100)))
    if progress >= 1 then
        self:SetProgress(100)
        self:ShowResults()
    end
end

function Analyzer:Create(parent)
    if self.frame then
        return
    end

    local launch = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    launch:SetWidth(124)
    launch:SetHeight(26)
    launch:SetPoint("TOPLEFT", parent, "TOPLEFT", 230, -18)
    launch:SetText("Analyse Build")
    launch:SetScript("OnClick", function()
        Analyzer:Start()
    end)
    launch:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Analyse Build", 0.35, 0.8, 1)
        GameTooltip:AddLine("Compare your known spells with the Official Tier List.", 1, 1, 1, true)
        GameTooltip:AddLine("Unlisted spells are ignored.", 0.55, 0.9, 0.55)
        GameTooltip:Show()
    end)
    launch:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    self.launchButton = launch

    local frame = CreateFrame("Frame", "ActuallyBuildAnalyzerFrame", UIParent)
    frame:SetWidth(470)
    frame:SetHeight(500)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 15)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        Analyzer.detached = true
    end)
    SetBackdrop(frame, { 0.025, 0.035, 0.055, 0.99 }, { 0.25, 0.72, 1.00, 1 })

    frame:SetScript("OnHide", function()
        if Analyzer.running then
            Analyzer:Cancel()
        end
    end)
    self.frame = frame

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -20)
    title:SetText("Actually's Build Analysis")

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -5)
    subtitle:SetText("Known spells compared with the Official Tier List")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    local start = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    start:SetWidth(124)
    start:SetHeight(25)
    start:SetPoint("BOTTOM", frame, "BOTTOM", 0, 16)
    start:SetText("Analyse Again")
    start:SetScript("OnClick", function()
        Analyzer:Start()
    end)
    self.startButton = start

    local progressOverlay = CreateFrame("Frame", "ActuallyBuildAnalyzerProgressFrame", UIParent)
    progressOverlay:SetWidth(250)
    progressOverlay:SetHeight(48)
    progressOverlay:SetFrameStrata("TOOLTIP")
    progressOverlay:SetClampedToScreen(true)
    progressOverlay:SetScript("OnUpdate", function(_, elapsed)
        Analyzer:Update(elapsed)
    end)
    self.progressFrame = progressOverlay

    local status = progressOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    status:SetPoint("TOP", progressOverlay, "TOP", 0, 0)
    status:SetText("Opening your spellbook...")
    self.statusText = status

    local progress = CreateFrame("Frame", nil, progressOverlay)
    progress:SetWidth(226)
    progress:SetHeight(24)
    progress:SetPoint("TOP", status, "BOTTOM", 0, -5)
    SetBackdrop(progress, { 0.04, 0.045, 0.06, 1 }, { 0.22, 0.28, 0.36, 1 })

    local fill = progress:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", progress, "TOPLEFT", 3, -3)
    fill:SetPoint("BOTTOMLEFT", progress, "BOTTOMLEFT", 3, 3)
    fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    fill:SetVertexColor(0.20, 0.70, 1.00, 1)
    self.progressFill = fill

    local progressText = progress:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    progressText:SetPoint("CENTER")
    self.progressText = progressText

    local results = CreateFrame("Frame", nil, frame)
    results:SetPoint("TOPLEFT", frame, "TOPLEFT", 28, -76)
    results:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 57)
    self.resultsPanel = results

    local averageLabel = results:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    averageLabel:SetPoint("TOP", results, "TOP", 0, -2)
    averageLabel:SetText("AVERAGE UTILITY SCORE")

    local grade = results:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    grade:SetPoint("TOP", averageLabel, "BOTTOM", 0, -2)
    grade:SetText("--")
    self.gradeText = grade

    local summary = results:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOP", grade, "BOTTOM", 0, -5)
    summary:SetWidth(400)
    summary:SetJustifyH("CENTER")
    self.summaryText = summary

    local viewport = CreateFrame("ScrollFrame", nil, results)
    viewport:SetWidth(386)
    viewport:SetHeight(252)
    viewport:SetPoint("TOPLEFT", results, "TOPLEFT", 4, -92)
    viewport:EnableMouseWheel(true)
    self.resultsViewport = viewport

    local canvas = CreateFrame("Frame", nil, viewport)
    canvas:SetWidth(386)
    canvas:SetHeight(252)
    viewport:SetScrollChild(canvas)
    self.resultsCanvas = canvas

    local bar = CreateFrame("Slider", nil, results)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(15)
    bar:SetHeight(248)
    bar:SetPoint("TOPRIGHT", results, "TOPRIGHT", -1, -94)
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(45)
    bar:SetValue(0)
    bar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    SetBackdrop(bar, { 0.035, 0.04, 0.055, 0.95 }, { 0.18, 0.21, 0.27, 1 })
    bar:SetScript("OnValueChanged", function(_, value)
        viewport:SetVerticalScroll(value)
    end)
    viewport:SetScript("OnMouseWheel", function(_, delta)
        local minimum, maximum = bar:GetMinMaxValues()
        bar:SetValue(math.max(minimum, math.min(maximum, bar:GetValue() - delta * 45)))
    end)
    self.resultsBar = bar

    local empty = results:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    empty:SetPoint("CENTER", results, "CENTER", 0, -25)
    empty:SetWidth(350)
    empty:SetJustifyH("CENTER")
    empty:SetJustifyV("MIDDLE")
    self.emptyText = empty

    self.rows = {}
    self.progressFrame:Hide()
    self.resultsPanel:Hide()
    frame:Hide()
end
