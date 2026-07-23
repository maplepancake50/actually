local ARC = Actually.Modules.RaidCooldowns
local Bundles = ARC:NewModule("Bundles")

local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local FAILURE_STATUSES = {
    DECLINED = true,
    DEAD = true,
    OFFLINE = true,
    UNAVAILABLE = true,
    BUSY = true,
    TIMEOUT = true,
}

local function setBackdrop(frame, background, border)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(background[1], background[2], background[3], background[4] or 1)
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

local function shortName(value)
    local name = type(value) == "table" and value.name or value
    name = tostring(name or "Unknown")
    return string.match(name, "^[^-]+") or name
end

local function activeIncomingCount(incoming)
    local count = 0
    for _ in pairs(incoming or {}) do count = count + 1 end
    return count
end

local function refreshConfig()
    if ARC.BundleConfig and ARC.BundleConfig.frame and ARC.BundleConfig.frame:IsShown() then
        ARC.BundleConfig:Refresh()
    end
end

function Bundles:Initialize()
    self.active = nil
    self.incoming = {}
    self.incomingOrder = {}
    self.activeIncomingID = nil
    self.counter = 0
    self.remoteSequences = {}
    self:CreateAlert()
    self:CreateOfficerSummary()
    self.initialized = true
end

function Bundles:AcceptSequence(identity, session, sequence)
    self.remoteSequences = self.remoteSequences or {}
    local previous = self.remoteSequences[identity.key]
    if previous and previous.session == session and sequence <= previous.sequence then return false end
    self.remoteSequences[identity.key] = { session = session, sequence = sequence }
    return true
end

function Bundles:NextBundleID()
    self.counter = self.counter + 1
    return tostring(ARC.Comms.session) .. ":B:" .. tostring(self.counter)
end

function Bundles:Start(name, spellIDs)
    if not ARC.Roster:IsLocalCoordinator() then
        ARC:Print("only the party leader, raid leader, or raid assistants can request bundles")
        return false
    end
    if not ARC.Roster:IsGrouped() then
        ARC:Print("join a party or raid before requesting a cooldown bundle")
        return false
    end
    if self.active then
        ARC:Print("a cooldown bundle is already active")
        return false
    end
    if ARC.Requests.outgoing then
        ARC:Print("cancel the active single cooldown request before starting a bundle")
        return false
    end

    local unique, ordered = {}, {}
    for _, rawID in ipairs(spellIDs or {}) do
        local spellID = ARC.Registry:Canonicalize(rawID)
        if spellID and not unique[spellID] then
            unique[spellID] = true
            table.insert(ordered, spellID)
        end
    end
    if table.getn(ordered) == 0 then ARC:Print("bundle has no valid spells") return false end
    if table.getn(ordered) > ARC.Constants.MAX_BUNDLE_SPELLS then
        ARC:Print("bundle rejected: maximum "
            .. tostring(ARC.Constants.MAX_BUNDLE_SPELLS) .. " cooldowns")
        return false
    end

    local bundle = {
        id = self:NextBundleID(),
        name = tostring(name or "Cooldown Bundle"),
        createdAt = ARC:Now(),
        spellIDs = ordered,
        items = {},
        completed = 0,
        failed = 0,
    }
    self.active = bundle
    for index, spellID in ipairs(ordered) do
        local item = {
            id = bundle.id .. ":" .. tostring(index),
            spellID = spellID,
            attempted = {},
            timeout = ARC.Requests:GetTimeout(),
            status = "PENDING",
        }
        bundle.items[item.id] = item
        local candidate = ARC.Requests:FindCandidate(spellID, nil, item.attempted)
        if candidate then
            self:Assign(item, candidate)
        else
            item.status = "FAILED"
            bundle.failed = bundle.failed + 1
            ARC:Print(bundle.name .. ": nobody has "
                .. ARC.SpellInfo:ResolveSpellName(spellID) .. " ready")
        end
    end
    ARC:Print("started bundle " .. bundle.name .. " with "
        .. tostring(table.getn(ordered)) .. " cooldowns")
    self:ShowOfficerSummary(bundle)
    self:CheckFinished()
    ARC.Renderer:MarkDirty("bundle started")
    ARC.Renderer:Reconcile()
    refreshConfig()
    return self.active ~= nil
end

function Bundles:Assign(item, playerKey)
    local bundle = self.active
    if not bundle or not item then return false end
    item.targetKey = playerKey
    item.attempted[playerKey] = true
    item.assignedAt = ARC:Now()
    -- SENT has a short acknowledgement deadline. A QUEUED response clears it;
    -- the full response timer starts only when the recipient sends ACTIVE.
    item.deadline = item.assignedAt + item.timeout
    item.status = "SENT"
    ARC.Renderer:MarkDirty("bundle assignment")
    local selfKey, selfIdentity = ARC.Roster:GetPlayer()
    if playerKey == selfKey then
        self:OnRemoteRequest(selfIdentity, ARC.Comms.session, ARC.Comms:NextSequence(),
            bundle.id, bundle.name, item.id, playerKey, item.spellID, item.timeout)
    else
        ARC.Comms:SendBundleRequest(bundle.id, bundle.name, item.id, playerKey,
            item.spellID, item.timeout)
    end
    return true
end

function Bundles:CancelAssignment(item)
    if not item or not item.targetKey then return end
    local selfKey = ARC.Roster:GetPlayer()
    if item.targetKey == selfKey then
        if self.incoming[item.id] then self:RemoveIncoming(item.id) end
    else
        ARC.Comms:SendBundleCancel(item.id, item.targetKey)
    end
end

function Bundles:Failover(item, reason)
    local bundle = self.active
    if not bundle or not item or item.status == "DONE" or item.status == "FAILED" then return end
    self:CancelAssignment(item)
    local candidate = ARC.Requests:FindCandidate(item.spellID, nil, item.attempted)
    if candidate and ARC.db.profile.requests.autoFailover ~= false then
        ARC:Print(bundle.name .. ": " .. shortName(ARC.State.players[item.targetKey])
            .. " skipped for " .. ARC.SpellInfo:ResolveSpellName(item.spellID)
            .. " (" .. tostring(reason) .. ")")
        self:Assign(item, candidate)
    else
        item.status = "FAILED"
        bundle.failed = bundle.failed + 1
        ARC.Renderer:MarkDirty("bundle item failed")
        ARC:Print(bundle.name .. ": " .. ARC.SpellInfo:ResolveSpellName(item.spellID)
            .. " failed (" .. tostring(reason) .. ")")
        self:CheckFinished()
    end
end

function Bundles:Complete(item, source)
    local bundle = self.active
    if not bundle or not item or item.status == "DONE" or item.status == "FAILED" then
        return false
    end
    -- Observed cooldowns may complete a queued item before its prompt appears.
    -- Remove that assignment from the recipient's queue as well.
    self:CancelAssignment(item)
    item.status = "DONE"
    item.deadline = nil
    bundle.completed = bundle.completed + 1
    ARC.Renderer:MarkDirty("bundle item complete")
    ARC:Print(bundle.name .. ": " .. shortName(ARC.State.players[item.targetKey])
        .. " used " .. ARC.SpellInfo:ResolveSpellName(item.spellID)
        .. (source and " (" .. tostring(source) .. ")" or ""))
    self:CheckFinished()
    return true
end

function Bundles:CheckFinished()
    local bundle = self.active
    if not bundle then return end
    for _, item in pairs(bundle.items) do
        if item.status ~= "DONE" and item.status ~= "FAILED" then return end
    end
    ARC:Print("bundle " .. bundle.name .. " finished: "
        .. tostring(bundle.completed) .. " used, " .. tostring(bundle.failed) .. " failed")
    self.active = nil
    ARC.Renderer:MarkDirty("bundle complete")
    ARC.Renderer:Reconcile()
    refreshConfig()
end

function Bundles:CancelActive(reason)
    local bundle = self.active
    if not bundle then return false end
    local selfKey = ARC.Roster:GetPlayer()
    for _, item in pairs(bundle.items) do
        if item.status ~= "DONE" and item.status ~= "FAILED"
            and item.targetKey ~= selfKey then
            ARC.Comms:SendBundleCancel(item.id, item.targetKey)
        end
    end
    if self.incomingBundleID == bundle.id then
        self.incoming = {}
        self.incomingOrder = {}
        self.activeIncomingID = nil
        self.incomingBundleID = nil
        self.incomingRequesterKey = nil
        self.alert:Hide()
    end
    self.active = nil
    ARC:Print("bundle cancelled" .. (reason and ": " .. tostring(reason) or ""))
    ARC.Renderer:MarkDirty("bundle cancelled")
    ARC.Renderer:Reconcile()
    refreshConfig()
    return true
end

function Bundles:GetAssignment(playerKey, spellID)
    local bundle = self.active
    if not bundle then return nil end
    for _, item in pairs(bundle.items) do
        if item.targetKey == playerKey and item.spellID == spellID
            and item.status ~= "DONE" and item.status ~= "FAILED" then return item end
    end
end

function Bundles:SendStatus(incoming, status)
    if not incoming then return false end
    local selfKey, selfIdentity = ARC.Roster:GetPlayer()
    if incoming.requesterKey == selfKey then
        self:OnRemoteStatus(selfIdentity, ARC.Comms.session, ARC.Comms:NextSequence(),
            incoming.bundleID, incoming.itemID, status, incoming.spellID)
        return true
    end
    return ARC.Comms:SendBundleStatus(incoming.bundleID, incoming.itemID,
        status, incoming.spellID)
end

function Bundles:RemoveFromIncomingOrder(itemID)
    self.incomingOrder = self.incomingOrder or {}
    for index = table.getn(self.incomingOrder), 1, -1 do
        if self.incomingOrder[index] == itemID then table.remove(self.incomingOrder, index) end
    end
end

function Bundles:ActivateIncoming(itemID, playSound)
    local incoming = self.incoming[itemID]
    if not incoming then return false end
    local selfKey = ARC.Roster:GetPlayer()
    local eligible, reason = ARC.Requests:IsEligible(selfKey, incoming.spellID)
    if not eligible then
        local player = ARC.State.players[selfKey]
        self:RemoveIncoming(itemID, true)
        self:SendStatus(incoming, player and player.dead and "DEAD" or "UNAVAILABLE")
        ARC:Debug("skipped queued bundle item locally: " .. tostring(reason))
        return false
    end

    self.activeIncomingID = itemID
    incoming.state = "ACTIVE"
    incoming.deadline = ARC:Now() + incoming.timeout
    self:SendStatus(incoming, "ACTIVE")
    self:RefreshAlert(playSound)
    return true
end

function Bundles:ActivateNext()
    self.activeIncomingID = nil
    self.incomingOrder = self.incomingOrder or {}
    while true do
        local nextID
        for _, itemID in ipairs(self.incomingOrder) do
            local incoming = self.incoming[itemID]
            if incoming and incoming.state == "QUEUED" then
                nextID = itemID
                break
            end
        end
        if not nextID then
            if activeIncomingCount(self.incoming) == 0 then
                self.incomingBundleID = nil
                self.incomingRequesterKey = nil
            end
            self.alert:Hide()
            return false
        end
        if self:ActivateIncoming(nextID, true) then return true end
    end
end

function Bundles:RemoveIncoming(itemID, suppressPromotion)
    local wasActive = self.activeIncomingID == itemID
    self.incoming[itemID] = nil
    self:RemoveFromIncomingOrder(itemID)
    if wasActive then self.activeIncomingID = nil end
    if activeIncomingCount(self.incoming) == 0 then
        self.incomingBundleID = nil
        self.incomingRequesterKey = nil
        self.alert:Hide()
    elseif wasActive and not suppressPromotion then
        self:ActivateNext()
    elseif self.activeIncomingID then
        self:RefreshAlert(false)
    else
        self.alert:Hide()
    end
    return wasActive
end

function Bundles:RejectIncoming(itemID, status)
    local incoming = self.incoming[itemID]
    if not incoming then return end
    local wasActive = self:RemoveIncoming(itemID, true)
    self:SendStatus(incoming, status or "DECLINED")
    if wasActive then self:ActivateNext() end
end

function Bundles:RejectAll(status)
    local pending = {}
    for _, incoming in pairs(self.incoming) do table.insert(pending, incoming) end
    self.incoming = {}
    self.incomingOrder = {}
    self.activeIncomingID = nil
    self.incomingBundleID = nil
    self.incomingRequesterKey = nil
    self.alert:Hide()
    for _, incoming in ipairs(pending) do
        self:SendStatus(incoming, status or "DECLINED")
    end
end

function Bundles:OnRemoteRequest(requester, session, sequence, bundleID, bundleName,
    itemID, targetKey, spellID, timeout)
    if not self:AcceptSequence(requester, session, sequence) then return end
    if not ARC.Roster:IsCoordinator(requester) then
        ARC:Debug("rejected bundle request from non-coordinator " .. tostring(requester.name))
        return
    end
    local selfKey = ARC.Roster:GetPlayer()
    if targetKey ~= selfKey then return end
    if ARC.Requests.incoming
        or (self.incomingBundleID and (self.incomingBundleID ~= bundleID
            or self.incomingRequesterKey ~= requester.key)) then
        ARC.Comms:SendBundleStatus(bundleID, itemID, "BUSY", spellID)
        return
    end
    if activeIncomingCount(self.incoming) >= ARC.Constants.MAX_BUNDLE_SPELLS then
        ARC.Comms:SendBundleStatus(bundleID, itemID, "BUSY", spellID)
        return
    end
    local eligible, reason = ARC.Requests:IsEligible(selfKey, spellID)
    if not eligible then
        local player = ARC.State.players[selfKey]
        ARC.Comms:SendBundleStatus(bundleID, itemID,
            player and player.dead and "DEAD" or "UNAVAILABLE", spellID)
        ARC:Debug("declined bundle item locally: " .. tostring(reason))
        return
    end

    self.incomingBundleID = bundleID
    self.incomingRequesterKey = requester.key
    local incoming = {
        bundleID = bundleID,
        bundleName = bundleName,
        itemID = itemID,
        requesterKey = requester.key,
        requesterName = shortName(requester),
        spellID = spellID,
        timeout = math.max(3, math.min(timeout, 30)),
        state = "QUEUED",
    }
    self.incoming[itemID] = incoming
    self.incomingOrder = self.incomingOrder or {}
    table.insert(self.incomingOrder, itemID)
    if not self.activeIncomingID then
        self:ActivateIncoming(itemID, true)
    else
        self:SendStatus(incoming, "QUEUED")
    end
end

function Bundles:OnRemoteStatus(identity, session, sequence, bundleID, itemID, status, spellID)
    if not self:AcceptSequence(identity, session, sequence) then return end
    local bundle = self.active
    local item = bundle and bundle.id == bundleID and bundle.items[itemID]
    if not item or item.targetKey ~= identity.key or item.spellID ~= spellID then return end
    if item.status == "DONE" or item.status == "FAILED" then return end
    if status == "QUEUED" then
        item.status = "QUEUED"
        item.deadline = nil
        ARC.Renderer:MarkDirty("bundle queued")
    elseif status == "ACTIVE" or status == "ACK" then
        item.status = "ACTIVE"
        item.deadline = ARC:Now() + item.timeout
        ARC.Renderer:MarkDirty("bundle prompt active")
    elseif status == "CAST" then
        self:Complete(item, "confirmed")
    elseif FAILURE_STATUSES[status] then
        self:Failover(item, string.lower(status))
    end
end

function Bundles:OnRemoteCancel(requester, session, sequence, itemID, targetKey)
    if not self:AcceptSequence(requester, session, sequence) then return end
    if not ARC.Roster:IsCoordinator(requester) then return end
    local selfKey = ARC.Roster:GetPlayer()
    if targetKey == selfKey and self.incoming[itemID] then self:RemoveIncoming(itemID) end
end

function Bundles:OnLocalCast(spellID)
    local ids = {}
    for itemID, incoming in pairs(self.incoming) do
        if incoming.spellID == spellID then table.insert(ids, itemID) end
    end
    for _, itemID in ipairs(ids) do
        local incoming = self.incoming[itemID]
        if incoming then
            local wasActive = self:RemoveIncoming(itemID, true)
            self:SendStatus(incoming, "CAST")
            if wasActive then self:ActivateNext() end
        end
    end
end

function Bundles:OnReportedCast(playerKey, spellID)
    local item = self:GetAssignment(playerKey, spellID)
    if item then self:Complete(item, "observed") end
end

function Bundles:OnRosterChanged()
    if not self.initialized then return end
    if self.incomingRequesterKey then
        local requester = ARC.Roster.byKey[self.incomingRequesterKey]
        if not requester or not ARC.Roster:IsCoordinator(requester) then self:RejectAll("UNAVAILABLE") end
    end
    self:OnUpdate(ARC:Now())
end

function Bundles:OnPlayerDeath()
    if activeIncomingCount(self.incoming) > 0 then self:RejectAll("DEAD") end
end

function Bundles:OnUpdate(now)
    if not self.initialized then return end
    local bundle = self.active
    if bundle then
        if not ARC.Roster:IsLocalCoordinator() then
            self:CancelActive("coordinator authority lost")
        else
            local ids = {}
            for itemID in pairs(bundle.items) do table.insert(ids, itemID) end
            for _, itemID in ipairs(ids) do
                local item = self.active and self.active.items[itemID]
                if item and item.status ~= "DONE" and item.status ~= "FAILED" then
                    local target = ARC.State.players[item.targetKey]
                    if not target or target.connected == false then
                        self:Failover(item, "offline")
                    elseif target.dead then
                        self:Failover(item, "dead")
                    elseif target.stale then
                        self:Failover(item, "stale report")
                    elseif not target.spells or not target.spells[item.spellID] then
                        self:Failover(item, "spell unavailable")
                    elseif (target.spells[item.spellID].readyAt or 0) > now + 0.5 then
                        self:Complete(item, "cooldown detected")
                    elseif item.status ~= "QUEUED" and item.deadline
                        and now >= item.deadline then
                        self:Failover(item, "timeout")
                    end
                end
            end
        end
    end

    local selfKey = ARC.Roster:GetPlayer()
    local player = ARC.State.players[selfKey]
    if activeIncomingCount(self.incoming) > 0
        and UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
        self:RejectAll("DEAD")
    else
        local unavailable = {}
        for itemID, incoming in pairs(self.incoming) do
            if not player or not player.spells or not player.spells[incoming.spellID] then
                table.insert(unavailable, itemID)
            end
        end
        for _, itemID in ipairs(unavailable) do self:RejectIncoming(itemID, "UNAVAILABLE") end
        local active = self.activeIncomingID and self.incoming[self.activeIncomingID]
        if active and active.deadline and now >= active.deadline then
            self:RejectIncoming(active.itemID, "TIMEOUT")
        end
    end
    if self.activeIncomingID then self:UpdateAlert(now) end
end

function Bundles:CreateAlert()
    local profile = ARC.db.profile.bundleAlertUI
    local frame = CreateFrame("Frame", "ActuallyARCBundleAlertFrame", UIParent)
    frame:SetWidth(430)
    frame:SetHeight(158)
    frame:SetPoint(profile.point or "CENTER", UIParent, profile.point or "CENTER",
        profile.x or 0, profile.y or 150)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    setBackdrop(frame, { 0.025, 0.030, 0.045, 0.99 }, { 0.72, 0.30, 1.00, 1 })
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        profile.point, profile.x, profile.y = point, x, y
    end)

    frame.heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.heading:SetPoint("TOP", frame, "TOP", 0, -14)
    frame.heading:SetText("ARC COOLDOWN BUNDLE")
    frame.heading:SetTextColor(0.78, 0.46, 1.00)

    frame.message = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.message:SetPoint("TOP", frame.heading, "BOTTOM", 0, -7)

    frame.spells = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.spells:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -61)
    frame.spells:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
    frame.spells:SetJustifyH("CENTER")
    frame.spells:SetJustifyV("TOP")

    frame.timer = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.timer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 16)
    frame.timer:SetTextColor(1.00, 0.72, 0.20)

    frame.decline = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.decline:SetWidth(100)
    frame.decline:SetHeight(22)
    frame.decline:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 9)
    frame.decline:SetText("Can't use")
    frame.decline:SetScript("OnClick", function()
        if Bundles.activeIncomingID then
            Bundles:RejectIncoming(Bundles.activeIncomingID, "DECLINED")
        end
    end)

    frame:Hide()
    self.alert = frame
end

function Bundles:CreateOfficerSummary()
    local frame = CreateFrame("Frame", "ActuallyARCBundleSummaryFrame", UIParent)
    frame:SetWidth(370)
    frame:SetHeight(150)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -180)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)
    setBackdrop(frame, { 0.020, 0.035, 0.050, 0.96 }, { 0.20, 0.76, 1.00, 1 })

    frame.heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.heading:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
    frame.heading:SetText("COOLDOWN BUNDLE REQUESTED")
    frame.heading:SetTextColor(0.32, 0.86, 1.00)

    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    frame.bundleName = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.bundleName:SetPoint("TOPLEFT", frame.heading, "BOTTOMLEFT", 0, -5)
    frame.bundleName:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    frame.bundleName:SetJustifyH("LEFT")

    frame.spells = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.spells:SetPoint("TOPLEFT", frame.bundleName, "BOTTOMLEFT", 0, -9)
    frame.spells:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    frame.spells:SetJustifyH("LEFT")
    frame.spells:SetJustifyV("TOP")

    frame:Hide()
    self.officerSummary = frame
end

function Bundles:PlayAlertSound()
    local now = ARC:Now()
    if self.lastAlertSound and now - self.lastAlertSound <= 1 then return false end
    self.lastAlertSound = now
    if ARC.db.profile.requests.sound == false then return false end
    if PlaySoundFile then PlaySoundFile("Sound\\Interface\\RaidWarning.wav")
    elseif PlaySound then PlaySound("RaidWarning") end
    return true
end

function Bundles:ShowOfficerSummary(bundle)
    local frame = self.officerSummary
    if not frame or not bundle then return end
    local lines = {}
    for _, spellID in ipairs(bundle.spellIDs or {}) do
        local icon = ARC.SpellInfo:ResolveSpellIcon(spellID)
        local prefix = icon and ("|T" .. tostring(icon) .. ":16:16:0:0|t ") or ""
        table.insert(lines, prefix .. ARC.SpellInfo:ResolveSpellName(spellID))
    end
    frame.bundleName:SetText(tostring(bundle.name) .. "  |cff7fcfff("
        .. tostring(table.getn(lines)) .. " spells)|r")
    frame.spells:SetText(table.concat(lines, "\n"))
    frame:SetHeight(78 + math.max(1, table.getn(lines)) * 18)
    frame:Show()
    self:PlayAlertSound()

    self.summaryToken = (self.summaryToken or 0) + 1
    local token = self.summaryToken
    ARC:ScheduleTimer(function()
        if Bundles.summaryToken == token and Bundles.officerSummary then
            Bundles.officerSummary:Hide()
        end
    end, 6)
end

function Bundles:RefreshAlert(playSound)
    local incoming = self.activeIncomingID and self.incoming[self.activeIncomingID]
    if not incoming then self.alert:Hide() return end
    local queued = math.max(0, activeIncomingCount(self.incoming) - 1)
    self.alert.message:SetText(tostring(incoming.requesterName)
        .. " requests: " .. tostring(incoming.bundleName))
    local line = "USE " .. string.upper(ARC.SpellInfo:ResolveSpellName(incoming.spellID)) .. "!"
    if queued > 0 then
        line = line .. "\n|cffaaaaaa" .. tostring(queued)
            .. (queued == 1 and " more cooldown queued|r" or " more cooldowns queued|r")
    end
    self.alert.spells:SetText(line)
    self.alert:SetHeight(158)
    self:UpdateAlert(ARC:Now())
    self.alert:Show()

    if playSound then self:PlayAlertSound() end
end

function Bundles:UpdateAlert(now)
    local incoming = self.activeIncomingID and self.incoming[self.activeIncomingID]
    if incoming and incoming.deadline then
        self.alert.timer:SetText("Respond within "
            .. tostring(math.max(0, math.ceil(incoming.deadline - now))) .. " sec")
    else
        self.alert.timer:SetText("")
    end
end
