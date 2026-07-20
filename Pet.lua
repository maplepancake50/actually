Actually = Actually or {}
local Addon = Actually

local Pet = {}
Addon.Pet = Pet

local PET_SIZE = 128
local SHEET_COLUMNS = 4
local SHEET_ROWS = 4
local MAIN_SHEET = "Interface\\AddOns\\actually\\Textures\\ActuallyPet"
local EXTRAS_SHEET = "Interface\\AddOns\\actually\\Textures\\ActuallyPetExtras"

local ANIMATIONS = {
    blink = {
        frames = { 5, 6, 7, 8 },
        durations = { 0.08, 0.08, 0.12, 0.10 },
    },
    sneeze = {
        frames = { 9, 10, 10, 11, 12, 9 },
        durations = { 0.28, 0.24, 0.18, 0.16, 0.28, 0.18 },
    },
    happy = {
        frames = { 13, 14, 13, 14, 1 },
        durations = { 0.10, 0.12, 0.10, 0.16, 0.10 },
    },
    sleepy = {
        frames = { 15, 16, 15, 16, 15, 1 },
        durations = { 0.45, 0.50, 0.45, 0.50, 0.35, 0.10 },
    },
    doubleBlink = {
        frames = { 5, 6, 7, 8, 5, 6, 7, 8 },
        durations = { 0.07, 0.07, 0.10, 0.10, 0.07, 0.07, 0.10, 0.12 },
    },
    curious = {
        frames = { 1, 5, 6, 5, 1 },
        durations = { 0.16, 0.22, 0.32, 0.22, 0.12 },
    },
    perky = {
        frames = { 1, 13, 14, 13, 1 },
        durations = { 0.12, 0.16, 0.22, 0.16, 0.12 },
    },
    drag = {
        sheet = "extras",
        frames = { 1, 2, 3, 4, 5, 6, 7, 8 },
        durations = { 0.10, 0.10, 0.10, 0.10, 0.10, 0.10, 0.10, 0.10 },
        loop = true,
    },
    crows = {
        sheet = "extras",
        frames = { 9, 10, 11, 12, 13, 14, 15, 16 },
        durations = { 0.16, 0.16, 0.16, 0.16, 0.16, 0.16, 0.16, 0.20 },
    },
}

local CHATTER = {
    "actually!",
    "hi hi!",
    "need a tier list?",
    "*adjusts glasses*",
    "I am helping!",
    "RAT MODELZ",
    "@pika",
    "going cache?",
}

local DRAG_CHATTER = {
    "wheee!",
    "I can fly!",
    "where are we going?",
    "hold onto my glasses!",
    "up we go!",
    "tiny taxi!",
}

local function RandomBlinkDelay()
    return 3 + math.random() * 4
end

local function RandomSneezeDelay()
    return 42 + math.random() * 34
end

local function RandomSleepDelay()
    return 75 + math.random() * 45
end

local function RandomEmoteDelay()
    return 16 + math.random() * 18
end

function Pet:SetSpriteFrame(frameNumber)
    if not self.texture then
        return
    end

    local zeroIndex = frameNumber - 1
    local column = zeroIndex % SHEET_COLUMNS
    local row = math.floor(zeroIndex / SHEET_COLUMNS)
    self.texture:SetTexCoord(
        column / SHEET_COLUMNS,
        (column + 1) / SHEET_COLUMNS,
        row / SHEET_ROWS,
        (row + 1) / SHEET_ROWS
    )
end

function Pet:SetSheet(sheet)
    if not self.texture or self.currentSheet == sheet then
        return
    end

    self.currentSheet = sheet
    self.texture:SetTexture(sheet == "extras" and EXTRAS_SHEET or MAIN_SHEET)
end

function Pet:ResetTimers()
    self.blinkTimer = RandomBlinkDelay()
    self.sneezeTimer = RandomSneezeDelay()
    self.sleepTimer = RandomSleepDelay()
    self.emoteTimer = RandomEmoteDelay()
end

function Pet:PlayPassiveEmote()
    self.blinkTimer = RandomBlinkDelay()
    local roll = math.random(1, 100)
    if roll <= 44 then
        self:Play("perky")
    elseif roll <= 70 then
        self:Play("curious")
    elseif roll <= 90 then
        self:Play("doubleBlink")
    else
        self:Play("crows")
    end
end

function Pet:Play(name)
    local animation = ANIMATIONS[name]
    if not animation or not self.frame then
        return
    end

    self.animation = animation
    self.animationName = name
    self.animationIndex = 1
    self.animationRemaining = animation.durations[1]
    self:SetSheet(animation.sheet or "main")
    self:SetSpriteFrame(animation.frames[1])
end

function Pet:FinishAnimation()
    self.animation = nil
    self.animationName = nil
    self.animationIndex = nil
    self.animationRemaining = nil
    self.idleClock = 0
    self:SetSheet("main")
    self:SetSpriteFrame(1)
end

function Pet:ShowBubble(message, duration)
    if not self.bubble then
        return
    end

    self.bubble.text:SetText(message)
    self.bubble:SetAlpha(1)
    self.bubble:Show()
    self.bubbleRemaining = duration or 1.8
end

function Pet:UpdateAnimation(elapsed)
    if not self.animation then
        self.idleClock = (self.idleClock or 0) + elapsed
        local phase = math.floor(self.idleClock / 0.65) % 4
        self:SetSpriteFrame(phase == 1 and 2 or 1)
        return
    end

    self.animationRemaining = self.animationRemaining - elapsed
    while self.animation and self.animationRemaining <= 0 do
        self.animationIndex = self.animationIndex + 1
        if self.animationIndex > #self.animation.frames then
            if self.animation.loop then
                self.animationIndex = 1
                self:SetSpriteFrame(self.animation.frames[1])
                self.animationRemaining = self.animationRemaining + self.animation.durations[1]
            else
                self:FinishAnimation()
            end
        else
            self:SetSpriteFrame(self.animation.frames[self.animationIndex])
            self.animationRemaining = self.animationRemaining + self.animation.durations[self.animationIndex]
        end
    end
end

function Pet:UpdateBubble(elapsed)
    if not self.bubbleRemaining then
        return
    end

    self.bubbleRemaining = self.bubbleRemaining - elapsed
    if self.bubbleRemaining <= 0 then
        self.bubbleRemaining = nil
        self.bubble:Hide()
    elseif self.bubbleRemaining < 0.35 then
        self.bubble:SetAlpha(self.bubbleRemaining / 0.35)
    end
end

function Pet:Update(elapsed)
    self:UpdateAnimation(elapsed)
    self:UpdateBubble(elapsed)

    if self.animation then
        return
    end

    self.blinkTimer = self.blinkTimer - elapsed
    self.sneezeTimer = self.sneezeTimer - elapsed
    self.sleepTimer = self.sleepTimer - elapsed
    self.emoteTimer = self.emoteTimer - elapsed

    if self.sneezeTimer <= 0 then
        self.sneezeTimer = RandomSneezeDelay()
        self:Play("sneeze")
        self:ShowBubble("achoo!", 1.2)
    elseif self.sleepTimer <= 0 then
        self.sleepTimer = RandomSleepDelay()
        self:Play("sleepy")
    elseif self.emoteTimer <= 0 then
        self.emoteTimer = RandomEmoteDelay()
        self:PlayPassiveEmote()
    elseif self.blinkTimer <= 0 then
        self.blinkTimer = RandomBlinkDelay()
        self:Play("blink")
    end
end

function Pet:SavePosition()
    local petX, petY = self.frame:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    if petX and petY and parentX and parentY then
        Addon.db.pet.x = petX - parentX
        Addon.db.pet.y = petY - parentY
    end
end

function Pet:ApplyPosition()
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", UIParent, "CENTER", Addon.db.pet.x or 360, Addon.db.pet.y or -180)
end

function Pet:ResetPosition()
    Addon.db.pet.x = 360
    Addon.db.pet.y = -180
    self:ApplyPosition()
    self:Show()
    self:Play("happy")
    self:ShowBubble("I'm back!", 1.5)
end

function Pet:Show()
    if not self.frame then
        return
    end
    Addon.db.pet.shown = true
    self.frame:Show()
end

function Pet:Hide()
    if not self.frame then
        return
    end
    Addon.db.pet.shown = false
    self.frame:Hide()
end

function Pet:Toggle()
    if not self.frame then
        return
    end
    if self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
        self:Play("happy")
    end
end

function Pet:CreateBubble(parent)
    local bubble = CreateFrame("Frame", nil, parent)
    bubble:SetWidth(138)
    bubble:SetHeight(34)
    bubble:SetPoint("BOTTOM", parent, "TOP", 0, -8)
    bubble:SetFrameStrata("TOOLTIP")
    bubble:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    bubble:SetBackdropColor(0.03, 0.09, 0.15, 0.94)
    bubble:SetBackdropBorderColor(0.25, 0.75, 1, 1)

    local text = bubble:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER", bubble, "CENTER", 0, 1)
    text:SetWidth(126)
    text:SetJustifyH("CENTER")
    bubble.text = text
    bubble:Hide()
    self.bubble = bubble
end

function Pet:Create()
    if self.frame then
        return
    end

    local button = CreateFrame("Button", "ActuallyPetFrame", UIParent)
    button:SetWidth(PET_SIZE)
    button:SetHeight(PET_SIZE)
    button:SetFrameStrata("HIGH")
    button:SetClampedToScreen(true)
    button:SetMovable(true)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local texture = button:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints(button)
    self.texture = texture
    self.frame = button
    self:SetSheet("main")
    self:SetSpriteFrame(1)
    self:CreateBubble(button)
    self:ApplyPosition()
    self:ResetTimers()

    button:SetScript("OnUpdate", function(_, elapsed)
        Pet:Update(elapsed)
    end)

    button:SetScript("OnMouseDown", function()
        Pet.wasDragged = false
    end)

    button:SetScript("OnDragStart", function(self)
        Pet.wasDragged = true
        self:StartMoving()
        Pet:Play("drag")
        Pet:ShowBubble(DRAG_CHATTER[math.random(1, #DRAG_CHATTER)], 1.4)
        GameTooltip:Hide()
    end)

    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        Pet:SavePosition()
        Pet:Play("happy")
    end)

    button:SetScript("OnClick", function(_, mouseButton)
        if Pet.wasDragged then
            Pet.wasDragged = false
            return
        end

        if mouseButton == "RightButton" then
            Addon:Toggle()
            Pet:Play("happy")
            Pet:ShowBubble("tier time!", 1.4)
        else
            Pet:Play("happy")
            Pet:ShowBubble(CHATTER[math.random(1, #CHATTER)], 1.8)
        end
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Actually", 0.35, 0.8, 1)
        GameTooltip:AddLine("Left-click to say hello.", 1, 1, 1)
        GameTooltip:AddLine("Right-click to toggle the tier board.", 0.65, 0.85, 1)
        GameTooltip:AddLine("Drag to move me.", 0.55, 0.9, 0.55)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    if Addon.db.pet.shown == false then
        button:Hide()
    else
        button:Show()
    end
end
