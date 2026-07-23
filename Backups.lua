local Addon = Actually

local Backups = {}
Addon.Backups = Backups

local MAX_SNAPSHOTS = 180
local AUTO_PER_DAY = 2

local function Trim(value)
    return Addon.Util.Trim(value)
end

local function DeepCopy(value)
    return Addon.Util.DeepCopy(value)
end

local function DayKey(timestamp)
    return date("%Y-%m-%d", tonumber(timestamp) or time())
end

local function DisplayTime(timestamp)
    return date("%d %b %Y  %H:%M", tonumber(timestamp) or 0)
end

function Backups:GetStorage()
    Addon.db.backups = type(Addon.db.backups) == "table" and Addon.db.backups or {}
    Addon.db.backups.snapshots = type(Addon.db.backups.snapshots) == "table"
        and Addon.db.backups.snapshots or {}
    return Addon.db.backups.snapshots
end

function Backups:Validate(payload)
    payload = Trim(payload)
    if payload == "" or not Addon.Sync then
        return nil
    end
    return Addon.Sync:Deserialize(payload), payload
end

function Backups:Prune()
    local snapshots = self:GetStorage()
    while #snapshots > MAX_SNAPSHOTS do
        table.remove(snapshots)
    end
end

function Backups:Capture(reason, automatic, quiet)
    if not Addon.Sync then
        return nil
    end

    local payload = Addon.Sync:Serialize()
    if not self:Validate(payload) then
        if not quiet then Addon:Print("Could not create a valid recovery snapshot.") end
        return nil
    end

    local timestamp = time()
    local record = {
        id = Addon.Util.NewPersistentID(),
        timestamp = timestamp,
        dayKey = DayKey(timestamp),
        reason = tostring(reason or "manual"),
        automatic = automatic == true or nil,
        character = UnitName("player") or "Unknown",
        payload = payload,
    }
    table.insert(self:GetStorage(), 1, record)
    self:Prune()
    if not quiet then
        Addon:Print("Recovery snapshot saved locally (" .. DisplayTime(timestamp) .. ").")
    end
    if self.frame and self.frame:IsShown() then self:Refresh() end
    return record
end

function Backups:CaptureLoginSnapshot()
    local today = DayKey(time())
    local count = 0
    for _, record in ipairs(self:GetStorage()) do
        if record.automatic and record.dayKey == today then
            count = count + 1
        end
    end
    if count < AUTO_PER_DAY then
        self:Capture("login", true, true)
    end
end

function Backups:Import(payload)
    local parsed, normalized = self:Validate(payload)
    if not parsed then
        Addon:Print("That recovery snapshot is invalid or from an incompatible version.")
        return false
    end
    local timestamp = time()
    table.insert(self:GetStorage(), 1, {
        id = Addon.Util.NewPersistentID(),
        timestamp = timestamp,
        dayKey = DayKey(timestamp),
        reason = "imported",
        character = UnitName("player") or "Unknown",
        payload = normalized,
    })
    self:Prune()
    Addon:Print("Recovery snapshot imported and saved locally. It has not been restored yet.")
    if self.frame and self.frame:IsShown() then self:Refresh() end
    return true
end

function Backups:RestoreRecord(record)
    if type(record) ~= "table" then return false end
    if not Addon.Official or not Addon.Official:IsOwner() then
        Addon:Print("Only the actually leader can restore official data.")
        return false
    end
    if Addon.Sync and Addon.Sync.IsOfficialEditReady and not Addon.Sync:IsOfficialEditReady() then
        Addon:Print("Wait for official-list synchronization to finish before restoring a backup.")
        return false
    end
    local incoming = self:Validate(record.payload)
    if not incoming then
        Addon:Print("This recovery snapshot is damaged or incompatible.")
        return false
    end

    -- Preserve the current state before replacing anything. This is deliberately
    -- a manual snapshot so it does not consume a daily login slot.
    self:Capture("pre-restore", false, true)

    local restoredAt = time()
    local restorer = Addon.Official:GetPlayerIdentity()
    local official = Addon.db.lists.official
    Addon.Official:AdvanceAuthority(nil, nil)
    local authorityRevision = tonumber(Addon.Official:GetAuthority().revision) or 0

    official.board = DeepCopy(incoming.board)
    official.revision = math.max(
        tonumber(official.revision) or 0,
        tonumber(incoming.official.revision) or 0
    ) + 1
    official.lastModifiedBy = restorer
    official.lastModifiedAt = restoredAt
    official.audit = DeepCopy(incoming.audit)
    official.baseBoard = DeepCopy(incoming.board)
    official.baseRevision = official.revision
    official.baseLastModifiedBy = restorer
    official.baseLastModifiedAt = restoredAt
    official.baseAuthorityRevision = authorityRevision
    official.operations = {}
    official.operationClock = 0
    official.operationStateVersion = 2
    Addon.Official:AddAuditEntry(
        "Restored official tier, gear, and Cache Tips data from " .. DisplayTime(record.timestamp) .. ".",
        restorer,
        true
    )

    local previousSpells = Addon.db.customSpells or {}
    Addon.db.customSpells = DeepCopy(incoming.spells)
    Addon.db.spellTombstones = {}
    for key, spell in pairs(Addon.db.customSpells) do
        spell.updatedAt = restoredAt
    end
    for key in pairs(incoming.spellTombstones) do
        Addon.db.spellTombstones[key] = restoredAt
    end
    for key in pairs(previousSpells) do
        if not Addon.db.customSpells[key] then Addon.db.spellTombstones[key] = restoredAt end
    end

    local previousGear = Addon.db.gear.sets or {}
    Addon.db.gear.sets = DeepCopy(incoming.gearSets)
    Addon.db.gear.tombstones = {}
    for _, set in pairs(Addon.db.gear.sets) do
        set.updatedAt = restoredAt
        set.updatedBy = restorer
    end
    for id in pairs(incoming.gearTombstones) do
        Addon.db.gear.tombstones[id] = restoredAt
    end
    for id in pairs(previousGear) do
        if not Addon.db.gear.sets[id] then Addon.db.gear.tombstones[id] = restoredAt end
    end

    for _, role in ipairs({ "healer", "dps", "frontline" }) do
        local cacheRecord = incoming.cacheTips and incoming.cacheTips[role]
        if cacheRecord then
            Addon.db.cacheTips[role] = tostring(cacheRecord.text or "")
            Addon.db.cacheTipsMeta[role] = {
                updatedAt = restoredAt,
                updatedBy = restorer,
                authorityRevision = authorityRevision,
            }
        end
    end

    if Addon.Official then Addon.Official:RebuildBoard() end
    if Addon.Sync then
        Addon.Sync:MarkDirty(true)
        Addon.Sync:RefreshUI()
    end
    Addon:Print("Restored official tier, gear, and Cache Tips data from " .. DisplayTime(record.timestamp) .. ".")
    if self.frame and self.frame:IsShown() then self:Refresh() end
    return true
end

function Backups:GetSelected()
    return self:GetStorage()[self.selectedIndex or 1]
end

function Backups:Refresh()
    if not self.frame then return end
    local snapshots = self:GetStorage()
    if #snapshots == 0 then
        self.selectedIndex = nil
        self.counter:SetText("No recovery snapshots")
        self.details:SetText("Two snapshots are saved automatically per day when you log in. You can also save one now or import backup text.")
        self.textInput:SetText("")
        return
    end
    self.selectedIndex = math.max(1, math.min(tonumber(self.selectedIndex) or 1, #snapshots))
    local record = snapshots[self.selectedIndex]
    self.counter:SetText("Snapshot " .. self.selectedIndex .. " of " .. #snapshots)
    self.details:SetText(DisplayTime(record.timestamp) .. "  |  " .. tostring(record.reason or "unknown")
        .. "  |  " .. tostring(record.character or "Unknown"))
    self.textInput:SetText(record.payload or "")
    self.textInput:SetCursorPosition(0)
end

function Backups:Show(importMode)
    if not self.frame then self:CreateFrame() end
    self.frame:Show()
    if importMode then
        self.textInput:SetText("")
        self.textInput:SetFocus()
        self.mode:SetText("Paste a recovery snapshot below, then press Import Text.")
    else
        self.mode:SetText("Select a snapshot to export or restore. Ctrl+C copies the text below.")
        self:Refresh()
    end
end

function Backups:CreateFrame()
    local frame = CreateFrame("Frame", "ActuallyRecoveryArchiveFrame", UIParent)
    frame:SetWidth(720)
    frame:SetHeight(500)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    Addon.Util.SetBackdrop(frame, { 0.018, 0.035, 0.070, 0.99 }, { 0.12, 0.70, 0.92, 1 })

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -17)
    title:SetText("|cff69ccf0actually|r  Recovery Archive")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local counter = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    counter:SetPoint("TOPLEFT", 20, -51)
    local details = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    details:SetPoint("TOPRIGHT", -20, -51)
    local mode = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mode:SetPoint("TOPLEFT", 20, -76)
    mode:SetText("Select a snapshot to export or restore. Ctrl+C copies the text below.")

    local border = CreateFrame("Frame", nil, frame)
    border:SetPoint("TOPLEFT", 18, -99)
    border:SetPoint("BOTTOMRIGHT", -18, 62)
    Addon.Util.SetBackdrop(border, { 0.006, 0.012, 0.025, 1 }, { 0.15, 0.33, 0.48, 1 })
    local scroll = CreateFrame("ScrollFrame", "ActuallyRecoveryTextScrollFrame", border, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 9, -9)
    scroll:SetPoint("BOTTOMRIGHT", -29, 9)
    local input = CreateFrame("EditBox", nil, scroll)
    input:SetWidth(630)
    input:SetHeight(320)
    input:SetMultiLine(true)
    input:SetAutoFocus(false)
    input:SetMaxLetters(500000)
    input:SetFontObject(ChatFontNormal)
    input:SetTextInsets(4, 4, 4, 4)
    scroll:SetScrollChild(input)
    input:SetScript("OnTextChanged", function(self)
        local lines = math.max(1, math.ceil(string.len(self:GetText() or "") / 76))
        self:SetHeight(math.max(320, lines * 15 + 14))
        scroll:UpdateScrollChildRect()
    end)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local function Button(label, width, anchor, relative, x)
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetWidth(width)
        button:SetHeight(25)
        button:SetPoint(anchor, relative or frame, relative and "RIGHT" or anchor, x or 0, relative and 0 or 18)
        button:SetText(label)
        return button
    end
    local previous = Button("< Older", 78, "BOTTOMLEFT", nil, 18)
    local nextButton = Button("Newer >", 78, "LEFT", previous, 8)
    local save = Button("Snapshot Now", 112, "LEFT", nextButton, 18)
    local copy = Button("Select All", 86, "LEFT", save, 8)
    local import = Button("Import Text", 100, "BOTTOMRIGHT", nil, -128)
    local restore = Button("Restore", 92, "BOTTOMRIGHT", nil, -18)

    previous:SetScript("OnClick", function()
        Backups.selectedIndex = math.min(#Backups:GetStorage(), (Backups.selectedIndex or 1) + 1)
        Backups:Refresh()
    end)
    nextButton:SetScript("OnClick", function()
        Backups.selectedIndex = math.max(1, (Backups.selectedIndex or 1) - 1)
        Backups:Refresh()
    end)
    save:SetScript("OnClick", function() Backups.selectedIndex = 1; Backups:Capture("manual", false, false) end)
    copy:SetScript("OnClick", function() input:SetFocus(); input:HighlightText() end)
    import:SetScript("OnClick", function()
        if Backups:Import(input:GetText()) then
            Backups.selectedIndex = 1
            Backups:Refresh()
        end
    end)
    restore:SetScript("OnClick", function()
        local record = Backups:GetSelected()
        if record then
            StaticPopup_Show("ACTUALLY_RESTORE_RECOVERY", DisplayTime(record.timestamp), nil, record)
        end
    end)

    StaticPopupDialogs.ACTUALLY_RESTORE_RECOVERY = {
        text = "Restore official tier, gear, and Cache Tips data from %s?\n\nA backup of the current state will be made first.",
        button1 = "Restore",
        button2 = "Cancel",
        OnAccept = function(_, record) Backups:RestoreRecord(record) end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    frame:SetScript("OnShow", function() Backups:Refresh() end)
    frame:Hide()
    self.frame, self.counter, self.details, self.mode, self.textInput = frame, counter, details, mode, input
end

function Backups:HandleCommand(argument)
    argument = Trim(argument)
    local lower = string.lower(argument)
    if lower == "" or lower == "list" then
        self:Show(false)
    elseif lower == "now" or lower == "save" then
        self:Capture("manual", false, false)
    elseif lower == "import" then
        self:Show(true)
    elseif string.match(lower, "^export%s+%d+$") then
        local index = tonumber(string.match(lower, "(%d+)$"))
        if self:GetStorage()[index] then self.selectedIndex = index; self:Show(false); self.textInput:SetFocus(); self.textInput:HighlightText() end
    elseif string.match(lower, "^restore%s+%d+%s+confirm$") then
        local index = tonumber(string.match(lower, "^restore%s+(%d+)"))
        self:RestoreRecord(self:GetStorage()[index])
    else
        Addon:Print("Recovery: /actually backup, backup now, backup import, backup export <number>, backup restore <number> confirm")
    end
    return true
end

function Backups:Initialize()
    self:GetStorage()
    self:Prune()
    self:CaptureLoginSnapshot()
end
