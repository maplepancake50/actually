local ARC = Actually.Modules.RaidCooldowns
local Requests = ARC:NewModule("Requests")

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

local function playerShortName(player)
    local name = player and player.name or "Unknown"
    return string.match(name, "^[^-]+") or name
end

function Requests:Initialize()
    self.outgoing = nil
    self.incoming = nil
    self.requestCounter = 0
    self.remoteSequences = {}
    self:CreateAlert()
    self.initialized = true
end

function Requests:GetTimeout()
    local value = tonumber(ARC.db.profile.requests and ARC.db.profile.requests.timeout) or 8
    return math.max(3, math.min(value, 30))
end

function Requests:IsEligible(playerKey, spellID, allowRequestedCooldown)
    local player = ARC.State.players[playerKey]
    local spell = player and player.spells and player.spells[spellID]
    if not player or not spell then return false, "spell unavailable" end
    local selfKey = ARC.Roster:GetPlayer()
    if playerKey ~= selfKey and (player.source ~= "REPORT" or not ARC.State.peers[playerKey]) then
        return false, "ARC not detected"
    end
    if player.connected == false then return false, "offline" end
    if player.dead then return false, "dead" end
    if player.stale then return false, "stale report" end
    local remaining = math.max(0, (spell.readyAt or 0) - ARC:Now())
    if not allowRequestedCooldown and remaining > 0.5 then return false, "cooldown not ready" end
    return true
end

function Requests:FindCandidate(spellID, preferredKey, attempted)
    attempted = attempted or {}
    if preferredKey and not attempted[preferredKey] then
        local eligible = self:IsEligible(preferredKey, spellID)
        if eligible then return preferredKey end
    end
    local candidates = {}
    for playerKey in pairs(ARC.State.players) do
        if not attempted[playerKey] and self:IsEligible(playerKey, spellID) then
            table.insert(candidates, playerKey)
        end
    end
    table.sort(candidates, function(left, right)
        local leftPlayer, rightPlayer = ARC.State.players[left], ARC.State.players[right]
        return string.lower(playerShortName(leftPlayer)) < string.lower(playerShortName(rightPlayer))
    end)
    return candidates[1]
end

function Requests:NextRequestID()
    self.requestCounter = self.requestCounter + 1
    return tostring(ARC.Comms.session) .. ":R:" .. tostring(self.requestCounter)
end

function Requests:Start(playerKey, spellID)
    spellID = ARC.Registry:Canonicalize(spellID)
    if not spellID then ARC:Print("request rejected: unregistered spell") return false end
    if not ARC.Roster:IsLocalCoordinator() then
        ARC:Print("only the party leader, raid leader, or raid assistants can request cooldowns")
        return false
    end
    if not ARC.Roster:IsGrouped() then
        ARC:Print("join a party or raid before requesting a cooldown")
        return false
    end
    if ARC.Bundles and ARC.Bundles.active then
        ARC:Print("cancel the active cooldown bundle before making a single request")
        return false
    end
    if self.outgoing then self:CancelOutgoing("replaced by a new request") end

    local request = {
        id = self:NextRequestID(),
        spellID = spellID,
        attempted = {},
        createdAt = ARC:Now(),
        timeout = self:GetTimeout(),
    }
    self.outgoing = request
    local candidate = self:FindCandidate(spellID, playerKey, request.attempted)
    if not candidate then
        self.outgoing = nil
        ARC:Print("no living, connected player has "
            .. ARC.SpellInfo:ResolveSpellName(spellID) .. " ready")
        ARC.Renderer:MarkDirty("request unavailable")
        return false
    end
    return self:Assign(candidate, "requested")
end

function Requests:Assign(playerKey, reason)
    local request = self.outgoing
    if not request then return false end
    request.targetKey = playerKey
    request.attempted[playerKey] = true
    request.assignedAt = ARC:Now()
    request.deadline = request.assignedAt + request.timeout
    request.status = "SENT"

    local target = ARC.State.players[playerKey]
    ARC:Print("requesting " .. ARC.SpellInfo:ResolveSpellName(request.spellID)
        .. " from " .. playerShortName(target)
        .. (reason and " (" .. tostring(reason) .. ")" or ""))

    local selfKey, selfIdentity = ARC.Roster:GetPlayer()
    if playerKey == selfKey then
        self:OnRemoteRequest(selfIdentity, ARC.Comms.session, ARC.Comms:NextSequence(),
            request.id, playerKey, request.spellID, request.timeout)
    else
        ARC.Comms:SendUseRequest(request.id, playerKey, request.spellID, request.timeout)
    end
    ARC.Renderer:MarkDirty("request assigned")
    ARC.Renderer:Reconcile()
    return true
end

function Requests:CancelAssignment(request, targetKey)
    if not request or not targetKey then return end
    local selfKey = ARC.Roster:GetPlayer()
    if targetKey == selfKey and self.incoming and self.incoming.id == request.id then
        self:ClearIncoming()
    else
        ARC.Comms:SendUseCancel(request.id, targetKey)
    end
end

function Requests:Failover(reason)
    local request = self.outgoing
    if not request then return false end
    local oldTarget = request.targetKey
    self:CancelAssignment(request, oldTarget)
    local candidate = self:FindCandidate(request.spellID, nil, request.attempted)
    if candidate and ARC.db.profile.requests.autoFailover ~= false then
        ARC:Print(playerShortName(ARC.State.players[oldTarget]) .. " skipped: " .. tostring(reason))
        return self:Assign(candidate, "automatic fallback")
    end
    ARC:Print("request ended: " .. tostring(reason) .. "; no other ready player")
    self.outgoing = nil
    ARC.Renderer:MarkDirty("request failed")
    ARC.Renderer:Reconcile()
    return false
end

function Requests:Complete(playerKey, source)
    local request = self.outgoing
    if not request or request.targetKey ~= playerKey then return false end
    ARC:Print(playerShortName(ARC.State.players[playerKey]) .. " used "
        .. ARC.SpellInfo:ResolveSpellName(request.spellID)
        .. (source and " (" .. tostring(source) .. ")" or ""))
    self.outgoing = nil
    ARC.Renderer:MarkDirty("request complete")
    ARC.Renderer:Reconcile()
    return true
end

function Requests:CancelOutgoing(reason)
    local request = self.outgoing
    if not request then return false end
    self:CancelAssignment(request, request.targetKey)
    self.outgoing = nil
    ARC:Print("request cancelled" .. (reason and ": " .. tostring(reason) or ""))
    ARC.Renderer:MarkDirty("request cancelled")
    ARC.Renderer:Reconcile()
    return true
end

function Requests:IsOutgoingTarget(playerKey, spellID)
    local request = self.outgoing
    return request and request.targetKey == playerKey and request.spellID == spellID
end

function Requests:AcceptSequence(identity, session, sequence)
    self.remoteSequences = self.remoteSequences or {}
    local previous = self.remoteSequences[identity.key]
    if previous and previous.session == session and sequence <= previous.sequence then return false end
    self.remoteSequences[identity.key] = { session = session, sequence = sequence }
    return true
end

function Requests:SendStatus(status)
    local incoming = self.incoming
    if not incoming then return false end
    local requester = ARC.Roster.byKey[incoming.requesterKey]
    local selfKey, selfIdentity = ARC.Roster:GetPlayer()
    if incoming.requesterKey == selfKey then
        self:OnRemoteStatus(selfIdentity, ARC.Comms.session, ARC.Comms:NextSequence(),
            incoming.id, status, incoming.spellID)
        return true
    end
    if not requester then return false end
    return ARC.Comms:SendUseStatus(incoming.id, status, incoming.spellID)
end

function Requests:ClearIncoming()
    self.incoming = nil
    if self.alert then self.alert:Hide() end
end

function Requests:RejectIncoming(status)
    if self.incoming then self:SendStatus(status or "DECLINED") end
    self:ClearIncoming()
end

function Requests:OnRemoteRequest(requester, session, sequence, requestID, targetKey, spellID, timeout)
    if not self:AcceptSequence(requester, session, sequence) then return end
    if not ARC.Roster:IsCoordinator(requester) then
        ARC:Debug("rejected cooldown request from non-coordinator " .. tostring(requester.name))
        return
    end
    local selfKey = ARC.Roster:GetPlayer()
    if targetKey ~= selfKey then return end
    if self.incoming or (ARC.Bundles and next(ARC.Bundles.incoming or {})) then
        ARC.Comms:SendUseStatus(requestID, "BUSY", spellID)
        return
    end

    local player = ARC.State.players[selfKey]
    local eligible, reason = self:IsEligible(selfKey, spellID)
    if not eligible then
        local status = player and player.dead and "DEAD" or "UNAVAILABLE"
        ARC.Comms:SendUseStatus(requestID, status, spellID)
        ARC:Debug("declined request locally: " .. tostring(reason))
        return
    end

    self.incoming = {
        id = requestID,
        requesterKey = requester.key,
        requesterName = playerShortName(requester),
        spellID = spellID,
        receivedAt = ARC:Now(),
        deadline = ARC:Now() + math.max(3, math.min(timeout, 30)),
    }
    self:ShowAlert()
    self:SendStatus("ACK")
end

function Requests:OnRemoteStatus(identity, session, sequence, requestID, status, spellID)
    if not self:AcceptSequence(identity, session, sequence) then return end
    local request = self.outgoing
    if not request or request.id ~= requestID or request.targetKey ~= identity.key
        or request.spellID ~= spellID then return end
    if status == "ACK" then
        request.status = "ACK"
        ARC.Renderer:MarkDirty("request acknowledged")
    elseif status == "CAST" then
        self:Complete(identity.key, "confirmed")
    elseif FAILURE_STATUSES[status] then
        self:Failover(string.lower(status))
    end
end

function Requests:OnRemoteCancel(requester, session, sequence, requestID, targetKey)
    if not self:AcceptSequence(requester, session, sequence) then return end
    if not ARC.Roster:IsCoordinator(requester) then return end
    local selfKey = ARC.Roster:GetPlayer()
    if targetKey == selfKey and self.incoming and self.incoming.id == requestID then
        self:ClearIncoming()
    end
end

function Requests:OnLocalCast(spellID)
    if self.incoming and self.incoming.spellID == spellID then
        self:SendStatus("CAST")
        self:ClearIncoming()
    end
end

function Requests:OnReportedCast(playerKey, spellID)
    local request = self.outgoing
    if request and request.targetKey == playerKey and request.spellID == spellID then
        self:Complete(playerKey, "observed")
    end
end

function Requests:OnRosterChanged()
    if not self.initialized then return end
    local incoming = self.incoming
    if incoming then
        local requester = ARC.Roster.byKey[incoming.requesterKey]
        if not requester or not ARC.Roster:IsCoordinator(requester) then self:ClearIncoming() end
    end
    self:OnUpdate(ARC:Now())
end

function Requests:OnPlayerDeath()
    if self.incoming then self:RejectIncoming("DEAD") end
end

function Requests:OnUpdate(now)
    if not self.initialized then return end
    local request = self.outgoing
    if request then
        local target = ARC.State.players[request.targetKey]
        if not ARC.Roster:IsLocalCoordinator() then
            self:CancelOutgoing("coordinator authority lost")
        elseif not target or target.connected == false then
            self:Failover("offline")
        elseif target.dead then
            self:Failover("dead")
        elseif target.stale then
            self:Failover("stale report")
        elseif not target.spells or not target.spells[request.spellID] then
            self:Failover("spell unavailable")
        elseif (target.spells[request.spellID].readyAt or 0) > now + 0.5 then
            self:Complete(request.targetKey, "cooldown detected")
        elseif now >= (request.deadline or 0) then
            self:Failover("timeout")
        end
    end

    local incoming = self.incoming
    if incoming then
        local selfKey = ARC.Roster:GetPlayer()
        local player = ARC.State.players[selfKey]
        if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
            self:RejectIncoming("DEAD")
        elseif not player or not player.spells or not player.spells[incoming.spellID] then
            self:RejectIncoming("UNAVAILABLE")
        elseif now >= incoming.deadline then
            self:RejectIncoming("TIMEOUT")
        else
            self:UpdateAlert(now)
        end
    end
end

function Requests:CreateAlert()
    local profile = ARC.db.profile.requestUI
    local frame = CreateFrame("Frame", "ActuallyARCRequestAlertFrame", UIParent)
    frame:SetWidth(390)
    frame:SetHeight(142)
    frame:SetPoint(profile.point or "CENTER", UIParent, profile.point or "CENTER",
        profile.x or 0, profile.y or 140)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    setBackdrop(frame, { 0.025, 0.030, 0.045, 0.98 }, { 0.24, 0.86, 1.00, 1 })
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        profile.point, profile.x, profile.y = point, x, y
    end)

    frame.accent = frame:CreateTexture(nil, "ARTWORK")
    frame.accent:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.accent:SetVertexColor(0.20, 0.70, 0.95, 0.9)
    frame.accent:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -6)
    frame.accent:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
    frame.accent:SetHeight(4)

    frame.heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.heading:SetPoint("TOP", frame, "TOP", 0, -15)
    frame.heading:SetText("ARC REQUEST")
    frame.heading:SetTextColor(0.30, 0.86, 1.00)

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetWidth(48)
    frame.icon:SetHeight(48)
    frame.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -46)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    frame.message = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.message:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 12, -1)
    frame.message:SetPoint("RIGHT", frame, "RIGHT", -18, 0)
    frame.message:SetJustifyH("LEFT")

    frame.spell = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.spell:SetPoint("TOPLEFT", frame.message, "BOTTOMLEFT", 0, -7)
    frame.spell:SetPoint("RIGHT", frame, "RIGHT", -18, 0)
    frame.spell:SetJustifyH("LEFT")

    frame.timer = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.timer:SetPoint("TOPLEFT", frame.spell, "BOTTOMLEFT", 0, -5)
    frame.timer:SetTextColor(1.00, 0.72, 0.20)

    frame.decline = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.decline:SetWidth(92)
    frame.decline:SetHeight(22)
    frame.decline:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 10)
    frame.decline:SetText("Can't use")
    frame.decline:SetScript("OnClick", function() Requests:RejectIncoming("DECLINED") end)

    frame:Hide()
    self.alert = frame
end

function Requests:ShowAlert()
    local incoming = self.incoming
    if not incoming or not self.alert then return end
    self.alert.icon:SetTexture(ARC.SpellInfo:ResolveSpellIcon(incoming.spellID))
    self.alert.message:SetText(tostring(incoming.requesterName) .. " says:")
    self.alert.spell:SetText("USE " .. string.upper(ARC.SpellInfo:ResolveSpellName(incoming.spellID)) .. "!")
    self:UpdateAlert(ARC:Now())
    self.alert:Show()
    if ARC.db.profile.requests.sound ~= false then
        if PlaySoundFile then
            PlaySoundFile("Sound\\Interface\\RaidWarning.wav")
        elseif PlaySound then
            PlaySound("RaidWarning")
        end
    end
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo and ChatTypeInfo.RAID_WARNING then
        RaidNotice_AddMessage(RaidWarningFrame,
            tostring(incoming.requesterName) .. ": USE "
                .. ARC.SpellInfo:ResolveSpellName(incoming.spellID) .. "!",
            ChatTypeInfo.RAID_WARNING)
    end
end

function Requests:UpdateAlert(now)
    if not self.incoming or not self.alert then return end
    self.alert.timer:SetText("Respond within "
        .. tostring(math.max(0, math.ceil(self.incoming.deadline - now))) .. " sec")
end
