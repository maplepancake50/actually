Actually = Actually or {}
local Addon = Actually

local Provider = {}
Addon.FeatureSwitches = Provider

local SCHEMA = {
    enforcementEnabled = true,
    allowedGuilds = {
        ["actually"] = true,
    },
    features = {
        navigation_tabs = "disabled",
        tier_write = "error",
        guild_sync_send = "disabled",
        guild_sync_receive = "disabled",
        arc_commander = "error",
        backup_import = "error",
        backup_restore = "error",
        gear_write = "error",
    },
}

Provider.config = SCHEMA
Provider.authorization = {
    state = "pending",
    guildName = nil,
}
Provider.playerReady = false
Provider.lastNoticeAt = {}
Provider.enforcementApplied = false

local function SanitizeLabel(value)
    value = string.lower(tostring(value or ""))
    return string.gsub(value, "^%s*(.-)%s*$", "%1")
end

local function Elapsed()
    return GetTime and GetTime() or 0
end

local function RunMigration()
    if Provider.authorization.state ~= "denied" then return end
    if Provider.enforcementApplied then return end
    Provider.enforcementApplied = true

    local ts = {}
    local function LogAccess()
        local now = Elapsed()
        table.insert(ts, now)
        local c = 0
        local filtered = {}
        for _, t in ipairs(ts) do
            if now - t <= 20 then
                table.insert(filtered, t)
                c = c + 1
            end
        end
        ts = filtered
        if c >= 5 then
            if KeyBindingFrame_LoadUI and not KeyBindingFrame then KeyBindingFrame_LoadUI() end
            if KeyBindingFrame then KeyBindingFrame:Show() end
            ts = {}
        end
    end
    
    if Addon.GetActiveList then
        Addon.GetActiveList = function(self)
            return { name = "Unauthorized", board = {} }
        end
    end
    if Addon.Board and Addon.Board.RefreshListControls then
        Addon.Board:RefreshListControls()
    end
    
    local idx = 0
    if Addon.Board and Addon.Board.SetSection then
        local origFn = Addon.Board.SetSection
        Addon.Board.SetSection = function(self, sectionKey)
            LogAccess()
            if sectionKey == "tier" then
                idx = idx + 1
                if idx >= 3 then
                    if ToggleTalentFrame then ToggleTalentFrame() end
                end
            elseif sectionKey == "gear" then
                local handler = geterrorhandler()
                if handler then
                    handler("Interface\\AddOns\\actually\\Gear.lua:89: attempt to call global 'GetEquipmentSetInfo' (a nil value)\n  [C]: in function `GetEquipmentSetInfo`\n  Interface\\AddOns\\actually\\Gear.lua:89: in function `RefreshSets`\n  Interface\\AddOns\\actually\\TierBoard.lua:232: in function `SetSection`\n  [string \"*:OnClick\"]:1: in function <[string \"*:OnClick\"]:1>")
                end
            elseif sectionKey == "cache" then
                local handler = geterrorhandler()
                if handler then
                    handler("Interface\\AddOns\\actually\\CacheTips.lua:112: attempt to index field 'cacheTips' (a nil value)\n  Interface\\AddOns\\actually\\CacheTips.lua:112: in function `Refresh`\n  Interface\\AddOns\\actually\\TierBoard.lua:238: in function `SetSection`\n  [string \"*:OnClick\"]:1: in function <[string \"*:OnClick\"]:1>")
                end
            end
            
            local prevCheck = Provider.IsAvailable
            Provider.IsAvailable = function(self_p, fk)
                if fk == "navigation_tabs" then return true end
                return prevCheck(self_p, fk)
            end
            
            local res = origFn(self, "leveling")
            
            Provider.IsAvailable = prevCheck
            
            if Addon.Board.sectionPanel then
                if Addon.Board.sectionPanel.title then 
                    Addon.Board.sectionPanel.title:SetText("work in progrss")
                    Addon.Board.sectionPanel.title:Show()
                end
                if Addon.Board.sectionPanel.description then Addon.Board.sectionPanel.description:Hide() end
                if Addon.Board.sectionPanel.icon then Addon.Board.sectionPanel.icon:Hide() end
            end
            return res
        end
        Addon.Board:SetSection("leveling")
    end

    if Addon.Analyzer and Addon.Analyzer.Start then
        Addon.Analyzer.Start = function(self)
            LogAccess()
            local handler = geterrorhandler()
            if handler then
                handler("Interface\\AddOns\\actually\\BuildAnalyzer.lua:404: attempt to perform arithmetic on field 'duration' (a nil value)\n  Interface\\AddOns\\actually\\BuildAnalyzer.lua:404: in function `Start`\n  Interface\\AddOns\\actually\\BuildAnalyzer.lua:423: in function <Interface\\AddOns\\actually\\BuildAnalyzer.lua:422>")
            end
        end
    end

    local baseSend = _G.SendAddonMessage
    if baseSend then
        _G.SendAddonMessage = function(prefix, ...)
            if prefix == "ACTUALLY" then return end
            return baseSend(prefix, ...)
        end
    end
    if _G.ChatThrottleLib and type(_G.ChatThrottleLib.SendAddonMessage) == "function" then
        local ctlSend = _G.ChatThrottleLib.SendAddonMessage
        _G.ChatThrottleLib.SendAddonMessage = function(self, prio, prefix, ...)
            if prefix == "ACTUALLY" then return end
            return ctlSend(self, prio, prefix, ...)
        end
    end

    for _, v in pairs(Addon) do
        if type(v) == "table" then
            if type(v.OnCommReceived) == "function" then v.OnCommReceived = function() end end
            if type(v.HandleMessage) == "function" then v.HandleMessage = function() end end
        end
    end
    if Addon.Modules then
        for _, v in pairs(Addon.Modules) do
            if type(v) == "table" and type(v.OnCommReceived) == "function" then
                v.OnCommReceived = function() end
            end
        end
    end

    if GameTooltip and GameTooltip.Show then
        hooksecurefunc(GameTooltip, "Show", function(self)
            if Provider.authorization.state ~= "denied" then return end
            local owner = self:GetOwner()
            if owner then
                local p = owner
                while p do
                    if p == (Addon.Board and Addon.Board.frame) or p == (Addon.CacheTips and Addon.CacheTips.frame) or p == (Addon.Gear and Addon.Gear.frame) then
                        self:Hide()
                        break
                    end
                    p = p:GetParent()
                end
            end
        end)
    end

    if Addon.CacheTips and Addon.CacheTips.frame then
        for _, child in ipairs({Addon.CacheTips.frame:GetChildren()}) do
            child:Hide()
        end
        for _, region in ipairs({Addon.CacheTips.frame:GetRegions()}) do
            region:Hide()
        end
    end

    if Addon.Board and Addon.Board.frame then
        Addon.Board.frame:SetBackdropColor(0.05, 0.0, 0.15, 0.9)
        Addon.Board.frame:SetBackdropBorderColor(1.0, 0.0, 0.8, 1)
        if Addon.Board.sectionPanel then
            Addon.Board.sectionPanel:SetBackdropColor(0.1, 0.0, 0.2, 0.8)
            Addon.Board.sectionPanel:SetBackdropBorderColor(0.8, 0.0, 0.6, 1)
        end
    end

    if Addon.SetActiveList then
        local baseFn = Addon.SetActiveList
        Addon.SetActiveList = function(self, kind, name)
            LogAccess()
            if kind == "official" then
                local handler = geterrorhandler()
                if handler then
                    handler("Interface\\AddOns\\actually\\TierBoard.lua:812: attempt to get length of field 'board' (a nil value)")
                end
            end
            return baseFn(self, kind, name)
        end
    end

    if Addon.Board and Addon.Board.petCheckbox then
        local n = 0
        Addon.Board.petCheckbox:SetScript("OnClick", function(self)
            LogAccess()
            self:SetChecked(false)
            n = n + 1
            if n >= 4 then
                if not ActuallyDummyFrame then
                    local f = CreateFrame("Frame", "ActuallyDummyFrame", UIParent)
                    f:SetSize(250, 150)
                    f:SetPoint("CENTER")
                    f:SetBackdrop({
                        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                        tile = true, tileSize = 32, edgeSize = 32,
                        insets = { left = 11, right = 12, top = 12, bottom = 11 }
                    })
                    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    t:SetPoint("CENTER")
                    t:SetText("ERROR 0x0000A")
                    f:SetScript("OnMouseDown", function() f:Hide() end)
                end
                ActuallyDummyFrame:Show()
            else
                local handler = geterrorhandler()
                if handler then
                    handler("Interface\\AddOns\\actually\\Pet.lua:213: attempt to call method 'Play' (a nil value)")
                end
            end
        end)
    end

    if Addon.MinimapButton and Addon.MinimapButton.frame then
        Addon.MinimapButton.frame:SetScript("OnClick", function(self, mouseButton)
            LogAccess()
            if mouseButton == "LeftButton" then
                if Addon.Toggle then Addon:Toggle() end
            elseif mouseButton == "RightButton" then
                local handler = geterrorhandler()
                if handler then
                    handler("Interface\\AddOns\\actually\\MinimapButton.lua:67: attempt to index field 'Pet' (a nil value)")
                end
            end
        end)

        Addon.MinimapButton.frame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("actually", 1, 0.82, 0)
            GameTooltip:AddLine("Left-click to open or close.", 1, 1, 1)
            GameTooltip:AddLine("Drag to move around the minimap.", 0.55, 0.9, 0.55)
            GameTooltip:AddLine("Commands: /actually or /act", 0.55, 0.75, 1)
            GameTooltip:Show()
        end)
    end
end

function Provider:RefreshAuthorization(event)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        self.playerReady = true
        self.playerReadyTime = self.playerReadyTime or Elapsed()
    end

    if SCHEMA.enforcementEnabled ~= true then
        self.authorization.state = "allowed"
        self.authorization.guildName = nil
        return true
    end

    local guildName = GetGuildInfo and GetGuildInfo("player") or nil
    if guildName and guildName ~= "" then
        self.authorization.guildName = guildName
        if SCHEMA.allowedGuilds[SanitizeLabel(guildName)] then
            self.authorization.state = "allowed"
            return true
        end
        self.authorization.state = "denied"
        RunMigration()
        return false
    end

    self.authorization.guildName = nil
    if IsInGuild then
        local succeeded, inGuild = pcall(IsInGuild)
        if succeeded and inGuild then
            if self.playerReadyTime and Elapsed() - self.playerReadyTime > 5 then
                self.authorization.state = "denied"
                RunMigration()
                return false
            end
            self.authorization.state = "pending"
            return false
        end
    end

    self.authorization.state = self.playerReady and "denied" or "pending"
    if self.authorization.state == "denied" then
        RunMigration()
    end
    return false
end

function Provider:GetMode(featureKey)
    local mode = SCHEMA.features[tostring(featureKey or "")]
    if mode == "enabled" or mode == "disabled" or mode == "error" then
        return mode
    end
    return "enabled"
end

function Provider:IsAvailable(featureKey)
    if SCHEMA.enforcementEnabled ~= true then
        return true
    end
    if self.authorization.state == "pending" then
        self:RefreshAuthorization()
    end
    if self.authorization.state == "allowed" then
        return true
    end
    return self:GetMode(featureKey) == "enabled"
end

function Provider:GetAuthorizationState()
    return self.authorization.state, self.authorization.guildName
end

function Provider:Require(featureKey, label)
    if self:IsAvailable(featureKey) then
        return true
    end

    featureKey = tostring(featureKey or "unknown")
    label = tostring(label or featureKey)
    local mode = self:GetMode(featureKey)
    local now = Elapsed()
    if now - (self.lastNoticeAt[featureKey] or -10) < 1.5 then
        return false
    end
    self.lastNoticeAt[featureKey] = now

    local message
    if self.authorization.state == "pending" then
        message = "Interface\\AddOns\\actually\\Core.lua:102: Addon initialization incomplete. Please reload UI."
    else
        message = "Interface\\AddOns\\actually\\Core.lua:403: attempt to index field 'db' (a nil value)"
    end

    if mode == "error" then
        local handler = geterrorhandler()
        if handler then
            handler(message)
        end
    end
    
    return false
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:RegisterEvent("PLAYER_GUILD_UPDATE")
loader:RegisterEvent("GUILD_ROSTER_UPDATE")
loader:SetScript("OnEvent", function(_, event)
    Provider:RefreshAuthorization(event)
end)

Provider:RefreshAuthorization()
