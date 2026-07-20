Actually = Actually or {}
local Addon = Actually

local Pet = {}
Addon.Pet = Pet

local PET_SIZE = 128
local SHEET_COLUMNS = 4
local SHEET_ROWS = 4
local MAIN_SHEET = "Interface\\AddOns\\actually\\Textures\\ActuallyPet"
local SAD_SHEET = "Interface\\AddOns\\actually\\Textures\\ActuallyPetSad"
local ANALYSIS_SHEET = "Interface\\AddOns\\actually\\Textures\\ActuallyPetAnalysis"
local ACTIVITY_SHEET = "Interface\\AddOns\\actually\\Textures\\ActuallyPetActivities"
local TYPING_SHEET = "Interface\\AddOns\\actually\\Textures\\ActuallyPetTyping"
local THOUGHT_SHEET = "Interface\\AddOns\\actually\\Textures\\ActuallyPetThoughts"
local CROW_LAUNCH_SHEET = "Interface\\AddOns\\actually\\Textures\\ActuallyPetCrowLaunch"
local LEVITATE_CLOUD_SHEET = "Interface\\AddOns\\actually\\Textures\\ActuallyPetLevitateCloud"
local SPEECH_BUBBLE_TEXTURE = "Interface\\AddOns\\actually\\Textures\\ActuallyPetSpeechBubble"
local ACTION_BOX_TEXTURE = "Interface\\AddOns\\actually\\Textures\\ActuallyPetActionBox"
local GHOST_AURA_TEXTURE = "Interface\\AddOns\\actually\\Textures\\ActuallyPetGhostAura"
local RAPID_CLICK_COUNT = 5
local RAPID_CLICK_WINDOW = 1.75
local CROW_RETURN_DELAY = 6
local CROW_EFFECT_TIME_SCALE = 1.3
-- Showcase the detailed equipment/spell poses long enough to read clearly.
local INSPECT_DURATION_SCALE = 3.75

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
    talkNeutral = {
        frames = { 1, 2, 1, 2, 1, 2, 1 },
        durations = { 0.09, 0.11, 0.09, 0.13, 0.09, 0.11, 0.10 },
    },
    talkBlink = {
        frames = { 1, 2, 5, 6, 7, 8, 2, 1 },
        durations = { 0.09, 0.10, 0.06, 0.07, 0.09, 0.08, 0.12, 0.10 },
    },
    talkGlance = {
        frames = { 1, 2, 3, 3, 2, 1 },
        durations = { 0.10, 0.10, 0.16, 0.12, 0.11, 0.10 },
    },
    talkBrows = {
        frames = { 1, 4, 2, 4, 1, 2, 1 },
        durations = { 0.09, 0.14, 0.10, 0.15, 0.09, 0.11, 0.10 },
    },
    talkDry = {
        frames = { 1, 15, 16, 15, 2, 1 },
        durations = { 0.10, 0.16, 0.18, 0.14, 0.11, 0.10 },
    },
    talkEmphatic = {
        frames = { 1, 2, 13, 14, 2, 13, 14, 1 },
        durations = { 0.08, 0.09, 0.11, 0.10, 0.09, 0.12, 0.11, 0.10 },
    },
    typingGaze = {
        sheet = "typing",
        frames = { 1, 3, 3, 3, 5, 6, 7, 8, 3 },
        durations = { 0.12, 0.85, 0.90, 0.75, 0.07, 0.07, 0.10, 0.08, 0.90 },
        loop = true,
    },
    readBook = {
        sheet = "analysis",
        durationScale = 2.25,
        frames = { 1, 2, 3, 6, 7, 8, 9, 10, 11, 12, 10, 9, 2, 1 },
        durations = { 0.20, 0.20, 0.24, 0.28, 0.24, 0.20, 0.26, 0.24, 0.32, 0.30, 0.24, 0.22, 0.18, 0.14 },
    },
    magnify = {
        sheet = "analysis",
        durationScale = 2.25,
        frames = { 1, 3, 4, 5, 4, 13, 14, 5, 4, 1 },
        durations = { 0.16, 0.18, 0.22, 0.32, 0.20, 0.26, 0.28, 0.24, 0.18, 0.14 },
    },
    crowLanding = {
        sheet = "activities",
        durationScale = 2.25,
        frames = { 1, 3, 2, 3, 4, 4, 2, 4 },
        durations = { 0.18, 0.16, 0.22, 0.16, 0.38, 0.30, 0.26, 0.42 },
    },
    inspectSword = {
        sheet = "activities",
        durationScale = INSPECT_DURATION_SCALE,
        frames = { 5, 6, 7, 8, 7, 6, 5 },
        durations = { 0.22, 0.28, 0.30, 0.26, 0.28, 0.24, 0.18 },
    },
    inspectBow = {
        sheet = "activities",
        durationScale = INSPECT_DURATION_SCALE,
        frames = { 9, 10, 11, 12, 11, 10, 9 },
        durations = { 0.22, 0.27, 0.32, 0.28, 0.30, 0.24, 0.18 },
    },
    healing = {
        sheet = "activities",
        durationScale = INSPECT_DURATION_SCALE,
        frames = { 13, 14, 15, 14, 15, 16, 15, 14, 13 },
        durations = { 0.18, 0.22, 0.30, 0.22, 0.32, 0.30, 0.24, 0.20, 0.16 },
    },
    sad = {
        sheet = "sad",
        frames = { 1, 4, 12, 15, 16, 15, 1 },
        durations = { 0.22, 0.24, 0.28, 0.36, 0.48, 0.25, 0.14 },
    },
    research = {
        sheet = "analysis",
        frames = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 },
        durations = { 0.24, 0.24, 0.24, 0.26, 0.22, 0.22, 0.22, 0.24, 0.22, 0.24, 0.28, 0.28, 0.22, 0.22, 0.24, 0.26 },
        loop = true,
    },
}

local CHATTER = {
    "well, actually...",
    "technically...",
    "need a tier list?",
    "*adjusts glasses*",
    "minor correction.",
    "RAT MODELZ",
    "@pika",
    "going cache?",
    "Are we a zerg guild?",
    "we need to go nez mode",
    "i forgot to merc",
    "petjob just whispered me",
    "i get the next mount",
    "they have 30 at prime time I promise",
    "I have a frontline bear build",
    "I can make melee work",
    "I'm top 0.00001% in retail",
    "we should just flank them",
    "its fine the servers are in Russia",
    "I just woke up",
    "50g for felcom? pls?",
    "our guild has the most aura",
    "it was better when it was high risk",
    "link dps",
    "this isn't a pad build",
    "I was CCed the whole time",
    "im the healer Padlord atm",
    "im multi top 10",
    "season 2 was the best",
    "I dropped my Alva sword",
    "why didnt you grip me?",
    "I got knocked",
    "I don't want to prestige again",
    "premade?",
    "I got one shot",
    "I got that spec nerfed",
    "I got that nerfed in season 4",
    "match? we have 5",
    "I'll play rogue",
    "we can win",
    "did unfaithful rescipricator get nerfed?",
    "I have hit 3.7m with unfaithful rescipricator",
    "HOTs are just pad for heals",
    "FRESH",
    "FRESH SOUTHSHORE",
    "consumes allowed in wargames. I already used.",
    "I hate frontlines",
    "anyone got fap?",
    "can anyone shotcall?",
    "shotcalling lowers my dps by 50%",
    "No, I never used that buff at cache",
    "Everyone in my guild is s++ tier",
}

local DRAG_CHATTER = {
    "flying now",
    "where are we going?",
    "where is cache?",
    "summon pls",
    "my hs is on cooldown",
}

local TALKING_ANIMATIONS = {
    "talkNeutral",
    "talkBlink",
    "talkGlance",
    "talkBrows",
    "talkDry",
    "talkEmphatic",
}

local LEFT_CLICK_SAFE_ANIMATIONS = {
    blink = true,
    doubleBlink = true,
    curious = true,
    perky = true,
    happy = true,
    typingGaze = true,
    talkNeutral = true,
    talkBlink = true,
    talkGlance = true,
    talkBrows = true,
    talkDry = true,
    talkEmphatic = true,
}

local PERIODIC_ACTIVITIES = {
    "readBook",
    "magnify",
    "crowLanding",
    "inspectSword",
    "inspectBow",
    "healing",
}

local DRAG_RELEASE_ANIMATIONS = {
    "curious",
    "perky",
    "doubleBlink",
    "talkDry",
    "talkBrows",
    "happy",
}

local THOUGHTS = { 1, 2, 3 }

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

local function RandomActivityDelay()
    return 29.4 + math.random() * 30.8
end

local function RandomThoughtDelay()
    return 26.6 + math.random() * 21
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

function Pet:SetGhostAuraFrame(frameNumber)
    if not self.ghostAuraTexture then
        return
    end

    local zeroIndex = frameNumber - 1
    local column = zeroIndex % 2
    local row = math.floor(zeroIndex / 2)
    self.ghostAuraTexture:SetTexCoord(column / 2, (column + 1) / 2, row / 2, (row + 1) / 2)
end

function Pet:SetGhostState(isGhost)
    isGhost = isGhost and true or false
    if self.isGhost == isGhost or not self.texture then
        return
    end

    self.isGhost = isGhost
    if isGhost then
        self.texture:SetDesaturated(true)
        self.texture:SetVertexColor(0.55, 0.88, 1, 0.68)
        self.ghostAuraClock = 0
        self:SetGhostAuraFrame(1)
        self.ghostAuraTexture:SetAlpha(0.34)
        self.ghostAuraTexture:Show()
    else
        self.texture:SetDesaturated(false)
        self.texture:SetVertexColor(1, 1, 1, 1)
        self.ghostAuraTexture:Hide()
    end
end

function Pet:RefreshGhostState()
    self:SetGhostState(UnitIsDeadOrGhost and UnitIsDeadOrGhost("player"))
end

function Pet:UpdateGhostAura(elapsed)
    if not self.isGhost or not self.ghostAuraTexture then
        return
    end

    self.ghostAuraClock = (self.ghostAuraClock or 0) + elapsed
    local frameNumber = math.floor(self.ghostAuraClock / 0.55) % 3 + 1
    self:SetGhostAuraFrame(frameNumber)
    self.ghostAuraTexture:SetAlpha(0.30 + 0.07 * (0.5 + 0.5 * math.sin(self.ghostAuraClock * 2.4)))
end

function Pet:SetSheet(sheet)
    if not self.texture or self.currentSheet == sheet then
        return
    end

    self.currentSheet = sheet
    if sheet == "sad" then
        self.texture:SetTexture(SAD_SHEET)
    elseif sheet == "analysis" then
        self.texture:SetTexture(ANALYSIS_SHEET)
    elseif sheet == "activities" then
        self.texture:SetTexture(ACTIVITY_SHEET)
    elseif sheet == "typing" then
        self.texture:SetTexture(TYPING_SHEET)
    else
        self.texture:SetTexture(MAIN_SHEET)
    end
end

local function IsPlayerTyping()
    if ChatEdit_GetActiveWindow then
        local editBox = ChatEdit_GetActiveWindow()
        if editBox and editBox:IsShown() and editBox:HasFocus() then
            return true
        end
    end

    for index = 1, (NUM_CHAT_WINDOWS or 10) do
        local editBox = _G["ChatFrame" .. index .. "EditBox"]
        if editBox and editBox:IsShown() and editBox:HasFocus() then
            return true
        end
    end

    return false
end

function Pet:UpdateTypingGaze(elapsed)
    self.typingCheckTimer = (self.typingCheckTimer or 0) - elapsed
    if self.typingCheckTimer > 0 then
        return
    end
    self.typingCheckTimer = 0.08

    local typing = IsPlayerTyping()
    if typing == self.isWatchingChat then
        return
    end

    self.isWatchingChat = typing
    if typing then
        if not self.isDragging and self.animationName ~= "research" then
            self:Play("typingGaze")
        end
    elseif self.animationName == "typingGaze" then
        self:FinishAnimation()
    end
end

function Pet:ResetTimers()
    self.blinkTimer = RandomBlinkDelay()
    self.sneezeTimer = RandomSneezeDelay()
    self.sleepTimer = RandomSleepDelay()
    self.emoteTimer = RandomEmoteDelay()
    self.activityTimer = RandomActivityDelay()
    self.thoughtTimer = RandomThoughtDelay()
end

function Pet:SetCrowLaunchFrame(frameNumber)
    if not self.crowLaunchTexture then
        return
    end

    local zeroIndex = frameNumber - 1
    local column = zeroIndex % 2
    local row = math.floor(zeroIndex / 2)
    self.crowLaunchTexture:SetTexCoord(column / 2, (column + 1) / 2, row / 2, (row + 1) / 2)
end

function Pet:SetLevitateCloudFrame(frameNumber)
    if not self.levitateCloudTexture then
        return
    end

    local zeroIndex = frameNumber - 1
    local column = zeroIndex % 2
    local row = math.floor(zeroIndex / 2)
    self.levitateCloudTexture:SetTexCoord(column / 2, (column + 1) / 2, row / 2, (row + 1) / 2)
end

function Pet:SetScreenPosition(x, y)
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
end

function Pet:SetCrowScreenPosition(x, y)
    self.crowLaunchFrame:ClearAllPoints()
    self.crowLaunchFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
end

function Pet:SetLevitateCloudPosition(x, y)
    self.levitateCloudFrame:ClearAllPoints()
    self.levitateCloudFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
end

function Pet:CancelCrowLaunch()
    if not self.crowLaunch then
        return
    end

    self.crowLaunch = nil
    if self.crowLaunchFrame then
        self.crowLaunchFrame:Hide()
    end
    if self.levitateCloudFrame then
        self.levitateCloudFrame:Hide()
    end
    self.frame:SetAlpha(1)
    self.frame:SetClampedToScreen(true)
    self.frame:EnableMouse(true)
    self:ApplyPosition()
end

function Pet:TriggerCrowLaunch()
    if self.crowLaunch or not self.crowLaunchFrame then
        return false
    end
    if Addon.Analyzer and Addon.Analyzer.running then
        return false
    end

    local startX, startY = self.frame:GetCenter()
    if not startX or not startY then
        return false
    end

    local screenWidth = UIParent:GetWidth()
    local direction = startX >= screenWidth / 2 and 1 or -1
    self.crowLaunch = {
        stage = "rise",
        elapsed = 0,
        startX = startX,
        startY = startY,
        direction = direction,
    }
    self.rapidClickCount = 0
    self.rapidClickStarted = nil
    self:HideBubble()
    self:HideThought(true)
    self:FinishAnimation()
    self.frame:SetClampedToScreen(false)
    self.frame:EnableMouse(false)
    self.crowLaunchFrame:SetAlpha(1)
    self.levitateCloudFrame:Hide()
    self:SetCrowLaunchFrame(1)
    self:SetCrowScreenPosition(startX, startY - 112)
    self.crowLaunchFrame:Show()
    GameTooltip:Hide()
    return true
end

function Pet:RegisterRapidClick()
    if self.crowLaunch then
        return true
    end

    local now = GetTime()
    if not self.rapidClickStarted or now - self.rapidClickStarted > RAPID_CLICK_WINDOW then
        self.rapidClickStarted = now
        self.rapidClickCount = 1
    else
        self.rapidClickCount = (self.rapidClickCount or 0) + 1
    end

    if self.rapidClickCount >= RAPID_CLICK_COUNT then
        self.rapidClickCount = 0
        self.rapidClickStarted = nil
        return self:TriggerCrowLaunch()
    end
    return false
end

function Pet:UpdateCrowLaunch(elapsed)
    local launch = self.crowLaunch
    if not launch then
        return false
    end

    launch.elapsed = launch.elapsed + elapsed
    local screenWidth = UIParent:GetWidth()
    local screenHeight = UIParent:GetHeight()

    if launch.stage == "rise" then
        local duration = 0.48 * CROW_EFFECT_TIME_SCALE
        local progress = math.min(launch.elapsed / duration, 1)
        local eased = 1 - (1 - progress) * (1 - progress)
        self:SetCrowScreenPosition(launch.startX, launch.startY - 112 + 98 * eased)
        if progress >= 0.55 then
            self:SetCrowLaunchFrame(2)
        end
        if progress >= 1 then
            launch.stage = "blast"
            launch.elapsed = 0
            self:SetCrowLaunchFrame(3)
        end
    elseif launch.stage == "blast" then
        local duration = 0.68 * CROW_EFFECT_TIME_SCALE
        local progress = math.min(launch.elapsed / duration, 1)
        local eased = 1 - (1 - progress) * (1 - progress) * (1 - progress)
        local petX = launch.startX + launch.direction * screenWidth * 0.34 * eased
        local petY = launch.startY + (screenHeight - launch.startY + PET_SIZE * 1.3) * eased
        self:SetScreenPosition(petX, petY)
        self:SetCrowScreenPosition(launch.startX, launch.startY - 14 + 34 * progress)
        if progress > 0.55 then
            self.crowLaunchFrame:SetAlpha((1 - progress) / 0.45)
        end
        if progress >= 1 then
            launch.stage = "wait"
            launch.elapsed = 0
            launch.offscreenX = petX
            self.crowLaunchFrame:Hide()
        end
    elseif launch.stage == "wait" then
        if launch.elapsed >= CROW_RETURN_DELAY then
            launch.stage = "return"
            launch.elapsed = 0
            launch.returnX = launch.startX + launch.direction * screenWidth * 0.18
            launch.returnY = screenHeight + PET_SIZE
            self:SetScreenPosition(launch.returnX, launch.returnY)
            self:SetLevitateCloudFrame(1)
            self.levitateCloudFrame:SetAlpha(1)
            self:SetLevitateCloudPosition(launch.returnX, launch.returnY - 34)
            self.levitateCloudFrame:Show()
        end
    elseif launch.stage == "return" then
        local duration = 2.6
        local progress = math.min(launch.elapsed / duration, 1)
        local eased = progress * progress * (3 - 2 * progress)
        local sway = math.sin(progress * math.pi * 5) * 18 * (1 - progress)
        local petX = launch.returnX + (launch.startX - launch.returnX) * eased + sway
        local bob = math.sin(progress * math.pi * 6) * 4 * (1 - progress)
        local petY = launch.returnY + (launch.startY - launch.returnY) * eased + bob
        self:SetScreenPosition(petX, petY)
        self:SetLevitateCloudPosition(petX, petY - 34)
        self:SetLevitateCloudFrame(math.floor(launch.elapsed / 0.32) % 2 + 1)
        if progress >= 1 then
            launch.stage = "landing"
            launch.elapsed = 0
            self:SetScreenPosition(launch.startX, launch.startY)
            self:SetLevitateCloudPosition(launch.startX, launch.startY - 34)
            self:SetLevitateCloudFrame(3)
        end
    elseif launch.stage == "landing" then
        local duration = 0.65
        local progress = math.min(launch.elapsed / duration, 1)
        self:SetScreenPosition(launch.startX, launch.startY)
        self:SetLevitateCloudPosition(launch.startX, launch.startY - 34 + 5 * progress)
        self.levitateCloudFrame:SetAlpha(1 - progress)
        if progress >= 1 then
            self.levitateCloudFrame:Hide()
            self.crowLaunch = nil
            self.frame:SetAlpha(1)
            self.frame:SetClampedToScreen(true)
            self.frame:EnableMouse(true)
            self:ApplyPosition()
            self:ResetTimers()
            self:Play("curious")
        end
    end

    return true
end

function Pet:PlayPassiveEmote()
    self.blinkTimer = RandomBlinkDelay()
    local roll = math.random(1, 100)
    if roll <= 42 then
        self:Play("perky")
    elseif roll <= 68 then
        self:Play("curious")
    elseif roll <= 92 then
        self:Play("doubleBlink")
    else
        self:Play("sad")
    end
end

function Pet:PlayTalkingAnimation()
    local available = {}
    for _, animationName in ipairs(TALKING_ANIMATIONS) do
        if animationName ~= self.lastTalkingAnimation then
            table.insert(available, animationName)
        end
    end
    local animationName = available[math.random(1, #available)]
    self.lastTalkingAnimation = animationName
    self:Play(animationName)
end

function Pet:CanAcceptLeftClick()
    if self.crowLaunch then
        return false
    end
    return not self.animationName or LEFT_CLICK_SAFE_ANIMATIONS[self.animationName] == true
end

function Pet:GetNextChatter()
    self.chatterHistory = self.chatterHistory or {}
    local recent = {}
    for _, message in ipairs(self.chatterHistory) do
        recent[message] = true
    end

    local available = {}
    for _, message in ipairs(CHATTER) do
        if not recent[message] then
            table.insert(available, message)
        end
    end

    local message = available[math.random(1, #available)]
    table.insert(self.chatterHistory, message)
    while #self.chatterHistory > 5 do
        table.remove(self.chatterHistory, 1)
    end
    return message
end

function Pet:PlayPeriodicActivity()
    local available = {}
    for _, animationName in ipairs(PERIODIC_ACTIVITIES) do
        if animationName ~= self.lastPeriodicActivity then
            table.insert(available, animationName)
        end
    end
    local animationName = available[math.random(1, #available)]
    self.lastPeriodicActivity = animationName
    self:Play(animationName)
end

function Pet:PlayDragReleaseAnimation()
    local available = {}
    for _, animationName in ipairs(DRAG_RELEASE_ANIMATIONS) do
        if animationName ~= self.lastDragReleaseAnimation then
            table.insert(available, animationName)
        end
    end
    local animationName = available[math.random(1, #available)]
    self.lastDragReleaseAnimation = animationName
    self:Play(animationName)
end

function Pet:Play(name)
    local animation = ANIMATIONS[name]
    if not animation or not self.frame then
        return
    end

    self.animation = animation
    self.animationName = name
    self.animationIndex = 1
    self.animationRemaining = animation.durations[1] * (animation.durationScale or 1)
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

function Pet:SetBubbleStyle(isAction)
    if not self.bubble then
        return
    end

    self.bubble:ClearAllPoints()
    self.bubble.text:ClearAllPoints()
    if isAction then
        self.bubble:SetWidth(230)
        self.bubble:SetHeight(115)
        self.bubble:SetPoint("BOTTOM", self.frame, "TOP", 0, -52)
        self.bubble.background:SetTexture(ACTION_BOX_TEXTURE)
        self.bubble.background:SetTexCoord(0, 1, 0, 1)
        self.bubble.text:SetPoint("CENTER", self.bubble, "CENTER", 0, 3)
    else
        self.bubble:SetWidth(230)
        self.bubble:SetHeight(115)
        self.bubble:SetPoint("BOTTOM", self.frame, "TOP", 0, -42)
        self.bubble.background:SetTexture(SPEECH_BUBBLE_TEXTURE)
        self.bubble.background:SetTexCoord(0, 1, 0, 1)
        self.bubble.text:SetPoint("CENTER", self.bubble, "CENTER", 0, 13)
    end
end

local function IsActionBubbleMessage(message)
    local normalized = string.lower(message or "")
    return normalized == "achoo!"
        or string.find(normalized, "adjusts glasses", 1, true) ~= nil
        or (string.sub(normalized, 1, 1) == "*" and string.sub(normalized, -1) == "*")
end

function Pet:ShowBubble(message, duration)
    if not self.bubble then
        return
    end

    self:HideThought(true)
    self:SetBubbleStyle(IsActionBubbleMessage(message))
    self.bubble.text:SetText(message)
    self.bubble:SetAlpha(1)
    self.bubble:Show()
    self.bubbleRemaining = duration or 1.8
end

function Pet:HideThought(resetTimer)
    self.thoughtRemaining = nil
    if self.thoughtBubble then
        self.thoughtBubble:Hide()
    end
    if resetTimer then
        self.thoughtTimer = RandomThoughtDelay()
    end
end

function Pet:ShowThought()
    if not self.thoughtBubble then
        return
    end

    local available = {}
    for _, thought in ipairs(THOUGHTS) do
        if thought ~= self.lastThought then
            table.insert(available, thought)
        end
    end

    local thought = available[math.random(1, #available)]
    local zeroIndex = thought - 1
    local column = zeroIndex % 2
    local row = math.floor(zeroIndex / 2)
    self.lastThought = thought
    self.thoughtTexture:SetTexCoord(column / 2, (column + 1) / 2, row / 2, (row + 1) / 2)
    self.thoughtBubble:SetAlpha(1)
    self.thoughtBubble:Show()
    self.thoughtRemaining = 4.5
    self.thoughtTimer = RandomThoughtDelay()
end

function Pet:HideBubble()
    self.bubbleRemaining = nil
    if self.bubble then
        self.bubble:Hide()
    end
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
                self.animationRemaining = self.animationRemaining + self.animation.durations[1] * (self.animation.durationScale or 1)
            else
                self:FinishAnimation()
            end
        else
            self:SetSpriteFrame(self.animation.frames[self.animationIndex])
            self.animationRemaining = self.animationRemaining + self.animation.durations[self.animationIndex] * (self.animation.durationScale or 1)
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

function Pet:UpdateThought(elapsed)
    if self.thoughtRemaining then
        self.thoughtRemaining = self.thoughtRemaining - elapsed
        if self.thoughtRemaining <= 0 then
            self:HideThought(false)
        elseif self.thoughtRemaining < 0.45 then
            self.thoughtBubble:SetAlpha(self.thoughtRemaining / 0.45)
        end
        return
    end

    self.thoughtTimer = (self.thoughtTimer or RandomThoughtDelay()) - elapsed
    if self.thoughtTimer > 0 then
        return
    end

    local analyzerRunning = Addon.Analyzer and Addon.Analyzer.running
    if self.bubbleRemaining or self.isDragging or self.isWatchingChat or self.animation or analyzerRunning then
        self.thoughtTimer = 5
        return
    end

    self:ShowThought()
end

function Pet:Update(elapsed)
    self:UpdateGhostAura(elapsed)
    if self:UpdateCrowLaunch(elapsed) then
        return
    end

    self:UpdateTypingGaze(elapsed)
    if self.isWatchingChat and not self.isDragging and not self.animation then
        self:Play("typingGaze")
    end
    self:UpdateAnimation(elapsed)
    self:UpdateBubble(elapsed)
    self:UpdateThought(elapsed)

    if self.animation then
        return
    end

    self.blinkTimer = self.blinkTimer - elapsed
    self.sneezeTimer = self.sneezeTimer - elapsed
    self.sleepTimer = self.sleepTimer - elapsed
    self.emoteTimer = self.emoteTimer - elapsed
    self.activityTimer = self.activityTimer - elapsed

    if self.sneezeTimer <= 0 then
        self.sneezeTimer = RandomSneezeDelay()
        self:Play("sneeze")
        self:ShowBubble("achoo!", 1.2)
    elseif self.activityTimer <= 0 then
        self.activityTimer = RandomActivityDelay()
        self:PlayPeriodicActivity()
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
    self:CancelCrowLaunch()
    Addon.db.pet.x = 360
    Addon.db.pet.y = -180
    self:ApplyPosition()
    self:Show()
    self:PlayTalkingAnimation()
    self:ShowBubble("I'm back!", 1.5)
end

function Pet:Show()
    if not self.frame then
        return
    end
    Addon.db.pet.shown = true
    self.frame:Show()
    if Addon.Board and Addon.Board.petCheckbox then
        Addon.Board.petCheckbox:SetChecked(true)
    end
end

function Pet:Hide(keepAnalyzerOpen)
    if not self.frame then
        return
    end
    self:CancelCrowLaunch()
    Addon.db.pet.shown = false
    self:HideThought(false)
    self.frame:Hide()
    if Addon.Analyzer and not keepAnalyzerOpen then
        if Addon.Analyzer.running and Addon.Analyzer.Cancel then
            Addon.Analyzer:Cancel()
        elseif Addon.Analyzer.frame and Addon.Analyzer.frame:IsShown() then
            Addon.Analyzer.frame:Hide()
        end
    end
    if Addon.Board and Addon.Board.petCheckbox then
        Addon.Board.petCheckbox:SetChecked(false)
    end
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
    bubble:SetWidth(230)
    bubble:SetHeight(115)
    bubble:SetPoint("BOTTOM", parent, "TOP", 0, -42)
    bubble:SetFrameStrata("TOOLTIP")

    local background = bubble:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(bubble)
    background:SetTexture(SPEECH_BUBBLE_TEXTURE)

    local text = bubble:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER", bubble, "CENTER", 0, 13)
    text:SetWidth(154)
    text:SetHeight(60)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    local font, fontSize, fontFlags = text:GetFont()
    if font and fontSize then
        text:SetFont(font, fontSize * 1.5, fontFlags)
    end

    bubble.text = text
    bubble.background = background
    bubble:Hide()
    self.bubble = bubble
end

function Pet:CreateThoughtBubble(parent)
    local bubble = CreateFrame("Frame", nil, parent)
    bubble:SetWidth(104)
    bubble:SetHeight(104)
    bubble:SetPoint("BOTTOM", parent, "TOP", 0, -8)
    bubble:SetFrameStrata("TOOLTIP")

    local texture = bubble:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints(bubble)
    texture:SetTexture(THOUGHT_SHEET)
    bubble:Hide()

    self.thoughtBubble = bubble
    self.thoughtTexture = texture
end

function Pet:CreateCrowLaunchEffect()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetWidth(236)
    frame:SetHeight(236)
    frame:SetFrameStrata("TOOLTIP")

    local texture = frame:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints(frame)
    texture:SetTexture(CROW_LAUNCH_SHEET)
    frame:Hide()

    self.crowLaunchFrame = frame
    self.crowLaunchTexture = texture
end

function Pet:CreateLevitateCloudEffect()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetWidth(170)
    frame:SetHeight(170)
    frame:SetFrameStrata("MEDIUM")

    local texture = frame:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints(frame)
    texture:SetTexture(LEVITATE_CLOUD_SHEET)
    frame:Hide()

    self.levitateCloudFrame = frame
    self.levitateCloudTexture = texture
end

function Pet:CreateContextMenu()
    local menu = CreateFrame("Frame", "ActuallyPetContextMenu", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(menu, function(_, level)
        if level ~= 1 then
            return
        end

        local info = UIDropDownMenu_CreateInfo()
        info.text = "Hide Arnold"
        info.notCheckable = true
        info.func = function()
            CloseDropDownMenus()
            Pet:Hide()
        end
        UIDropDownMenu_AddButton(info, level)
    end, "MENU")
    self.contextMenu = menu
end

function Pet:Create()
    if self.frame then
        return
    end

    local button = CreateFrame("Button", "ActuallyPetFrame", UIParent)
    button:SetWidth(PET_SIZE)
    button:SetHeight(PET_SIZE)
    button:SetFrameStrata("DIALOG")
    button:SetFrameLevel(100)
    button:SetClampedToScreen(true)
    button:SetMovable(true)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local ghostAura = button:CreateTexture(nil, "BACKGROUND")
    ghostAura:SetTexture(GHOST_AURA_TEXTURE)
    ghostAura:SetWidth(154)
    ghostAura:SetHeight(154)
    ghostAura:SetPoint("CENTER", button, "CENTER", 0, -2)
    ghostAura:SetBlendMode("ADD")
    ghostAura:Hide()
    self.ghostAuraTexture = ghostAura

    local texture = button:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints(button)
    self.texture = texture
    self.frame = button
    self:SetSheet("main")
    self:SetSpriteFrame(1)
    self:CreateBubble(button)
    self:CreateThoughtBubble(button)
    self:CreateCrowLaunchEffect()
    self:CreateLevitateCloudEffect()
    self:CreateContextMenu()
    self:ApplyPosition()
    self:ResetTimers()
    button:RegisterEvent("PLAYER_ENTERING_WORLD")
    button:RegisterEvent("PLAYER_DEAD")
    button:RegisterEvent("PLAYER_ALIVE")
    button:RegisterEvent("PLAYER_UNGHOST")
    button:SetScript("OnEvent", function()
        Pet:RefreshGhostState()
    end)
    self:RefreshGhostState()

    button:SetScript("OnUpdate", function(_, elapsed)
        Pet:Update(elapsed)
    end)

    button:SetScript("OnMouseDown", function()
        Pet.wasDragged = false
    end)

    button:SetScript("OnDragStart", function(self)
        Pet.wasDragged = true
        Pet.isDragging = true
        self:StartMoving()
        Pet:PlayPassiveEmote()
        Pet:ShowBubble(DRAG_CHATTER[math.random(1, #DRAG_CHATTER)], 1.4)
        GameTooltip:Hide()
    end)

    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        Pet.isDragging = false
        Pet:SavePosition()
        Pet:PlayDragReleaseAnimation()
    end)

    button:SetScript("OnClick", function(_, mouseButton)
        if Pet.wasDragged then
            Pet.wasDragged = false
            return
        end

        if mouseButton == "RightButton" then
            ToggleDropDownMenu(1, nil, Pet.contextMenu, "cursor", 0, 0)
        else
            if not Pet:CanAcceptLeftClick() then
                return
            end
            if Pet:RegisterRapidClick() then
                return
            end
            Pet:PlayTalkingAnimation()
            Pet:ShowBubble(Pet:GetNextChatter(), 1.8)
        end
    end)

    if Addon.db.pet.shown == false then
        button:Hide()
    else
        button:Show()
    end
end
