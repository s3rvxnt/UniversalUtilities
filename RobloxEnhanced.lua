-- ============================================================================
-- RobloxEnhancement.lua
-- Comprehensive In-Game Enhancement Suite for Roblox
-- Features:
--   1. Streamer Mode (Visual-only display/username/ID spoofing & overhead redaction)
--   2. Personal Space Bubble (Smooth distance falloff + temporal lerp fade + 10-step drag & slide slider)
--   3. Universal Player Locator & ESP (Box adornments, 28-slot highlight pool, raycast tracers, team quick-toggle)
--   4. Leaderboard Context Tools (Track/Untrack button, animated 2x2 accordion copy panel for ID/Profile/Names)
--   5. Chat Enhancements (Timestamp prefixes, username/display name mention audio chimes)
--   6. Anti-AFK (Inactivity kick prevention)
--   7. Native ESC Menu Integration (Seamlessly injected at top of Settings page)
-- ============================================================================

if not game:IsLoaded() then
    game.Loaded:Wait()
end

-- ============================================================================
-- Section 1: Services & Environment Bootstrap
-- ============================================================================
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Teams = game:GetService("Teams")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local SoundService = game:GetService("SoundService")

while not Players.LocalPlayer do
    task.wait()
end
local LocalPlayer = Players.LocalPlayer

local function GetLocalPlayer()
    if not LocalPlayer then
        LocalPlayer = Players.LocalPlayer
    end
    return LocalPlayer
end

-- ============================================================================
-- Section 2: Unified Lifecycle & Cleanup (Hot-Reload Safety)
-- ============================================================================
local genv = (typeof(getgenv) == "function" and getgenv()) or nil

if genv and genv.__EnhancementCleanup then
    pcall(genv.__EnhancementCleanup)
    genv.__EnhancementCleanup = nil
end

local Janitor = {}
local function Own(x)
    table.insert(Janitor, x)
    return x
end

-- ============================================================================
-- Section 3: Configuration & State Management
-- ============================================================================
local CONFIG_FILE = "roblox_enhancement_config.json"

local config = {
    streamer_mode = true,
    personal_space_bubble = 0,
    chat_timestamps = true,
    mention_chimes = true,
    anti_afk = true,
    locator_esp = true,
    locator_tracers = true,
    locator_distance = true,
}

local function LoadConfig()
    pcall(function()
        if typeof(readfile) == "function" and typeof(isfile) == "function" then
            if isfile(CONFIG_FILE) then
                local raw = readfile(CONFIG_FILE)
                local data = HttpService:JSONDecode(raw)
                if type(data) == "table" then
                    for k, v in pairs(data) do
                        config[k] = v
                    end
                end
            end
        end
    end)
end

local function SaveConfig()
    pcall(function()
        if typeof(writefile) == "function" then
            writefile(CONFIG_FILE, HttpService:JSONEncode(config))
        end
    end)
end

LoadConfig()

-- ============================================================================
-- Section 4: Streamer Mode Engine
-- Visual-Only Metamethod Spoofing + Overhead / CoreGui Redaction
-- Scripts reading properties receive genuine unredacted values.
-- ============================================================================
local StreamerMode = {}
local OriginalTexts = setmetatable({}, { __mode = "k" })
local HookedObjects = setmetatable({}, { __mode = "k" })
local StreamerConns = {}
local isRedacting = false
local isStreamerActive = false

local function EscapeReplacement(s)
    return (s:gsub("%%", "%%%%"))
end

local function BuildCaseInsensitivePattern(s)
    local pattern = ""
    for i = 1, #s do
        local c = s:sub(i, i)
        if c:match("%a") then
            pattern = pattern .. "[" .. c:lower() .. c:upper() .. "]"
        elseif c:match("[%^%$%(%)%%%.%[%]%*%+%-%?]") then
            pattern = pattern .. "%" .. c
        else
            pattern = pattern .. c
        end
    end
    return pattern
end

local TargetCache = {
    targets = {},
    dirty = true,
}

local function InvalidateTargets()
    TargetCache.dirty = true
end

local function GetCompiledTargets()
    if not TargetCache.dirty then
        return TargetCache.targets
    end

    local targets = {}
    local function Add(str, replacement)
        if typeof(str) == "string" and #str > 1 then
            local pat = BuildCaseInsensitivePattern(str)
            table.insert(targets, { pattern = pat, rep = EscapeReplacement(replacement), len = #str })
        end
    end

    local lp = GetLocalPlayer()
    if lp then
        Add(tostring(lp.UserId), "00000000")
        Add(lp.DisplayName, "Streamer")
        Add(lp.Name, "Streamer")
    end

    local allPlayers = Players:GetPlayers()
    for idx, p in ipairs(allPlayers) do
        if p ~= lp then
            local anon = "Player " .. tostring(idx)
            Add(tostring(p.UserId), "00000000")
            Add(p.DisplayName, anon)
            Add(p.Name, anon)
        end
    end

    table.sort(targets, function(a, b) return a.len > b.len end)
    TargetCache.targets = targets
    TargetCache.dirty = false
    return targets
end

Own(Players.PlayerAdded:Connect(InvalidateTargets))
Own(Players.PlayerRemoving:Connect(InvalidateTargets))

local function RedactString(str)
    if typeof(str) ~= "string" or str == "" then return str end
    local targets = GetCompiledTargets()
    local res = str
    for _, t in ipairs(targets) do
        res = res:gsub(t.pattern, t.rep)
    end
    return res
end

local function IsEnhancementGui(obj)
    local current = obj
    while current and current ~= game do
        if current.Name:sub(1, 12) == "Enhancement_" or current.Name:sub(1, 17) == "RobloxEnhancement" then
            return true
        end
        current = current.Parent
    end
    return false
end

-- Metamethod Handlers (Dynamic routing via executor environment preserves C++ pointers across hot-reloads)
local originalIndex = genv and genv.__EnhancementOriginalIndex
local originalNewIndex = genv and genv.__EnhancementOriginalNewIndex

local function IndexHandler(self, key)
    if isStreamerActive and typeof(self) == "Instance" then
        if key == "Text" or (key == "DisplayName" and self:IsA("Humanoid")) then
            local orig = OriginalTexts[self]
            if orig ~= nil then
                return orig
            end
        end
    end
    return originalIndex(self, key)
end

local function NewIndexHandler(self, key, value)
    if isStreamerActive and not isRedacting and typeof(self) == "Instance" then
        if key == "Text" then
            if self:IsA("TextLabel") or self:IsA("TextButton") then
                if not IsEnhancementGui(self) then
                    local strVal = tostring(value or "")
                    OriginalTexts[self] = strVal
                    local redacted = RedactString(strVal)
                    return originalNewIndex(self, key, redacted)
                end
            end
        elseif key == "DisplayName" and self:IsA("Humanoid") then
            local strVal = tostring(value or "")
            OriginalTexts[self] = strVal
            local redacted = RedactString(strVal)
            return originalNewIndex(self, key, redacted)
        end
    end
    return originalNewIndex(self, key, value)
end

if typeof(hookmetamethod) == "function" then
    if not originalIndex then
        originalIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
            if genv and genv.__EnhancementIndexHandler then
                return genv.__EnhancementIndexHandler(self, key)
            end
            return IndexHandler(self, key)
        end))
        if genv then genv.__EnhancementOriginalIndex = originalIndex end
    end
    if genv then genv.__EnhancementIndexHandler = IndexHandler end

    if not originalNewIndex then
        originalNewIndex = hookmetamethod(game, "__newindex", newcclosure(function(self, key, value)
            if genv and genv.__EnhancementNewIndexHandler then
                return genv.__EnhancementNewIndexHandler(self, key, value)
            end
            return NewIndexHandler(self, key, value)
        end))
        if genv then genv.__EnhancementOriginalNewIndex = originalNewIndex end
    end
    if genv then genv.__EnhancementNewIndexHandler = NewIndexHandler end
end

local function GetRawText(obj)
    if originalIndex then
        return originalIndex(obj, "Text")
    end
    return obj.Text
end

local function SetRawText(obj, val)
    if originalNewIndex then
        return originalNewIndex(obj, "Text", val)
    end
    obj.Text = val
end

local function GetRawDisplayName(hum)
    if originalIndex then
        return originalIndex(hum, "DisplayName")
    end
    return hum.DisplayName
end

local function SetRawDisplayName(hum, val)
    if originalNewIndex then
        return originalNewIndex(hum, "DisplayName", val)
    end
    hum.DisplayName = val
end

local function RedactOverhead(hum)
    if not hum or not hum:IsA("Humanoid") then return end
    local p = hum.Parent and Players:GetPlayerFromCharacter(hum.Parent)
    local trueName = p and (p.DisplayName ~= "" and p.DisplayName or p.Name)
    local raw = GetRawDisplayName(hum)
    if not raw or raw == "" then return end
    if trueName then
        OriginalTexts[hum] = trueName
    elseif not OriginalTexts[hum] then
        OriginalTexts[hum] = raw
    end
    local redacted = RedactString(OriginalTexts[hum])
    if raw ~= redacted then
        isRedacting = true
        pcall(function() SetRawDisplayName(hum, redacted) end)
        isRedacting = false
    end
end

local function HookHumanoid(hum)
    if not hum or not hum:IsA("Humanoid") then return end
    if HookedObjects[hum] then return end
    HookedObjects[hum] = true

    RedactOverhead(hum)
    local conn = hum:GetPropertyChangedSignal("DisplayName"):Connect(function()
        if not isRedacting and isStreamerActive then
            RedactOverhead(hum)
        end
    end)
    table.insert(StreamerConns, conn)
end

local function HookPlLabel(lbl)
    if not (lbl:IsA("TextLabel") and (lbl.Name == "PlayerName" or lbl.Name == "DisplayName")) then return end
    if HookedObjects[lbl] then return end
    HookedObjects[lbl] = true

    local function Check()
        if not isStreamerActive or isRedacting then return end
        local raw = lbl.Text
        if raw and raw ~= "" then
            local orig = OriginalTexts[lbl]
            if not orig then
                OriginalTexts[lbl] = raw
                orig = raw
            end
            local redacted = RedactString(orig)
            if lbl.Text ~= redacted then
                isRedacting = true
                pcall(function() lbl.Text = redacted end)
                isRedacting = false
            end
        end
    end

    Check()
    local conn = lbl:GetPropertyChangedSignal("Text"):Connect(Check)
    table.insert(StreamerConns, conn)
end

local function HookPlayerList(pl)
    if not pl then return end
    for _, d in ipairs(pl:GetDescendants()) do
        HookPlLabel(d)
    end
    local conn = pl.DescendantAdded:Connect(function(desc)
        if desc:IsA("TextLabel") and (desc.Name == "PlayerName" or desc.Name == "DisplayName") then
            HookPlLabel(desc)
        end
    end)
    table.insert(StreamerConns, conn)
end

local function HookBillboardLabel(lbl)
    if not lbl:IsA("TextLabel") then return end
    if HookedObjects[lbl] then return end
    HookedObjects[lbl] = true

    local function Check()
        if not isStreamerActive or isRedacting then return end
        local raw = lbl.Text
        if raw and raw ~= "" then
            local char = lbl:FindFirstAncestorOfClass("Model")
            local p = char and Players:GetPlayerFromCharacter(char)
            local trueName = p and (p.DisplayName ~= "" and p.DisplayName or p.Name)
            if trueName then
                OriginalTexts[lbl] = trueName
            elseif not OriginalTexts[lbl] then
                OriginalTexts[lbl] = raw
            end
            local orig = OriginalTexts[lbl]
            local redacted = RedactString(orig)
            if lbl.Text ~= redacted then
                isRedacting = true
                pcall(function() lbl.Text = redacted end)
                isRedacting = false
            end
        end
    end

    Check()
    local conn = lbl:GetPropertyChangedSignal("Text"):Connect(Check)
    table.insert(StreamerConns, conn)
end

local function HookBillboard(gui)
    if not gui or not gui:IsA("BillboardGui") then return end
    for _, d in ipairs(gui:GetDescendants()) do
        if d:IsA("TextLabel") then
            HookBillboardLabel(d)
        end
    end
    local c = gui.DescendantAdded:Connect(function(desc)
        if desc:IsA("TextLabel") then
            HookBillboardLabel(desc)
        end
    end)
    table.insert(StreamerConns, c)
end

local function HookChatLabel(lbl)
    if not (lbl:IsA("TextLabel") and (lbl.Name == "PrefixText" or lbl.Name == "BodyText")) then return end
    if HookedObjects[lbl] then return end
    HookedObjects[lbl] = true

    local function Check()
        if not isStreamerActive or isRedacting then return end
        local raw = lbl.Text
        if raw and raw ~= "" then
            local orig = OriginalTexts[lbl]
            if not orig then
                OriginalTexts[lbl] = raw
                orig = raw
            end
            local redacted = RedactString(orig)
            if lbl.Text ~= redacted then
                isRedacting = true
                pcall(function() lbl.Text = redacted end)
                isRedacting = false
            end
        end
    end

    Check()
    local conn = lbl:GetPropertyChangedSignal("Text"):Connect(Check)
    table.insert(StreamerConns, conn)
end

local function HookExperienceChat(chat)
    if not chat then return end
    for _, d in ipairs(chat:GetDescendants()) do
        HookChatLabel(d)
    end
    local conn = chat.DescendantAdded:Connect(function(desc)
        if desc:IsA("TextLabel") and (desc.Name == "PrefixText" or desc.Name == "BodyText") then
            HookChatLabel(desc)
        end
    end)
    table.insert(StreamerConns, conn)
end

local function HookPeoplePageLabel(lbl)
    if not lbl:IsA("TextLabel") then return end
    if HookedObjects[lbl] then return end
    HookedObjects[lbl] = true

    local function Check()
        if not isStreamerActive or isRedacting then return end
        local raw = lbl.Text
        if raw and raw ~= "" then
            local orig = OriginalTexts[lbl]
            if not orig then
                OriginalTexts[lbl] = raw
                orig = raw
            end
            local redacted = RedactString(orig)
            if lbl.Text ~= redacted then
                isRedacting = true
                pcall(function() lbl.Text = redacted end)
                isRedacting = false
            end
        end
    end

    Check()
    local conn = lbl:GetPropertyChangedSignal("Text"):Connect(Check)
    table.insert(StreamerConns, conn)
end

local function HookPeoplePage(page)
    if not page then return end
    for _, d in ipairs(page:GetDescendants()) do
        HookPeoplePageLabel(d)
    end
    local conn = page.DescendantAdded:Connect(function(desc)
        if desc:IsA("TextLabel") then
            HookPeoplePageLabel(desc)
        end
    end)
    table.insert(StreamerConns, conn)
end

function StreamerMode.Enable()
    isStreamerActive = true
    for _, c in ipairs(StreamerConns) do c:Disconnect() end
    table.clear(StreamerConns)
    table.clear(HookedObjects)

    local function TrackStreamerPlayer(p)
        local function CheckChar(char)
            if not char then return end
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then HookHumanoid(hum) end
            for _, d in ipairs(char:GetDescendants()) do
                if d:IsA("BillboardGui") then
                    HookBillboard(d)
                elseif d:IsA("TextLabel") and d:FindFirstAncestorOfClass("BillboardGui") then
                    HookBillboardLabel(d)
                end
            end
            local c = char.DescendantAdded:Connect(function(desc)
                if desc:IsA("Humanoid") then
                    HookHumanoid(desc)
                elseif desc:IsA("BillboardGui") then
                    HookBillboard(desc)
                elseif desc:IsA("TextLabel") and desc:FindFirstAncestorOfClass("BillboardGui") then
                    HookBillboardLabel(desc)
                end
            end)
            table.insert(StreamerConns, c)
        end

        if p.Character then CheckChar(p.Character) end
        local cConn = p.CharacterAdded:Connect(CheckChar)
        table.insert(StreamerConns, cConn)
    end

    for _, p in ipairs(Players:GetPlayers()) do
        TrackStreamerPlayer(p)
    end

    local pAddedConn = Players.PlayerAdded:Connect(function(p)
        TrackStreamerPlayer(p)
        if config.streamer_mode then
            StreamerMode.Refresh()
        end
    end)
    table.insert(StreamerConns, pAddedConn)

    local pl = CoreGui:FindFirstChild("PlayerList")
    if pl then HookPlayerList(pl) end
    local plAddedConn = CoreGui.ChildAdded:Connect(function(child)
        if child.Name == "PlayerList" then HookPlayerList(child) end
    end)
    table.insert(StreamerConns, plAddedConn)

    local expChat = CoreGui:FindFirstChild("ExperienceChat")
    if expChat then HookExperienceChat(expChat) end
    local chatAddedConn = CoreGui.ChildAdded:Connect(function(child)
        if child.Name == "ExperienceChat" then HookExperienceChat(child) end
    end)
    table.insert(StreamerConns, chatAddedConn)

    local robloxGui = CoreGui:FindFirstChild("RobloxGui")
    if robloxGui then
        local peoplePage = robloxGui:FindFirstChild("peoplepage", true)
        if peoplePage then HookPeoplePage(peoplePage) end
        local pvi = robloxGui:FindFirstChild("PageViewInnerFrame", true)
        if pvi then
            local pviConn = pvi.ChildAdded:Connect(function(child)
                if child.Name == "peoplepage" then HookPeoplePage(child) end
            end)
            table.insert(StreamerConns, pviConn)
        end
        local shield = robloxGui:FindFirstChild("SettingsShield", true)
        if shield then
            local shieldConn = shield:GetPropertyChangedSignal("Visible"):Connect(function()
                if shield.Visible and isStreamerActive then
                    task.defer(function()
                        local pp = robloxGui:FindFirstChild("peoplepage", true)
                        if pp then
                            for _, d in ipairs(pp:GetDescendants()) do
                                HookPeoplePageLabel(d)
                            end
                        end
                    end)
                end
            end)
            table.insert(StreamerConns, shieldConn)
        end
    end
end

function StreamerMode.Refresh()
    for obj, origText in pairs(OriginalTexts) do
        if obj and obj.Parent then
            local redacted = RedactString(origText)
            if obj:IsA("Humanoid") then
                local raw = GetRawDisplayName(obj)
                if raw ~= redacted then
                    isRedacting = true
                    pcall(function() SetRawDisplayName(obj, redacted) end)
                    isRedacting = false
                end
            else
                local rawText = GetRawText(obj)
                if rawText ~= redacted then
                    isRedacting = true
                    pcall(function() SetRawText(obj, redacted) end)
                    isRedacting = false
                end
            end
        end
    end

    local pl = CoreGui:FindFirstChild("PlayerList")
    if pl then
        for _, d in ipairs(pl:GetDescendants()) do HookPlLabel(d) end
    end

    local expChat = CoreGui:FindFirstChild("ExperienceChat")
    if expChat then
        for _, d in ipairs(expChat:GetDescendants()) do HookChatLabel(d) end
    end

    local robloxGui = CoreGui:FindFirstChild("RobloxGui")
    local peoplePage = robloxGui and robloxGui:FindFirstChild("peoplepage", true)
    if peoplePage then
        for _, d in ipairs(peoplePage:GetDescendants()) do HookPeoplePageLabel(d) end
    end

    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then
            local hum = p.Character:FindFirstChildOfClass("Humanoid")
            if hum then HookHumanoid(hum) end
            for _, d in ipairs(p.Character:GetDescendants()) do
                if d:IsA("BillboardGui") then
                    HookBillboard(d)
                elseif d:IsA("TextLabel") and d:FindFirstAncestorOfClass("BillboardGui") then
                    HookBillboardLabel(d)
                end
            end
        end
    end
end

function StreamerMode.Disable()
    isStreamerActive = false
    for _, c in ipairs(StreamerConns) do c:Disconnect() end
    table.clear(StreamerConns)
    table.clear(HookedObjects)

    isRedacting = true
    for obj, origText in pairs(OriginalTexts) do
        if obj and obj.Parent then
            if obj:IsA("Humanoid") then
                pcall(function() SetRawDisplayName(obj, origText) end)
            else
                pcall(function() SetRawText(obj, origText) end)
            end
        end
    end
    isRedacting = false
    table.clear(OriginalTexts)
end

-- ============================================================================
-- Section 5: Personal Space Bubble Engine (Nearby Player Fade)
-- Binary state with smooth temporal fade on enter/exit (no distance falloff)
-- ============================================================================
local PersonalSpaceBubble = {}
local bubbleConn
local charAlphas = {}
local charInside = {}

local BUBBLE_TARGET_ALPHA = 0.85
local FADE_SPEED = 7
local HYSTERESIS_BUFFER = 1.0

local function StepToRadius(step)
    if not step or step <= 0 then return 0 end
    return 3 + (step - 1) * (12 / 9)
end

local function ApplyCharTransparency(char, alpha)
    for _, desc in ipairs(char:GetDescendants()) do
        if desc:IsA("BasePart") and desc.Name ~= "HumanoidRootPart" then
            pcall(function()
                desc.LocalTransparencyModifier = alpha
            end)
        end
    end
end

function PersonalSpaceBubble.Enable()
    if bubbleConn then
        bubbleConn:Disconnect()
        bubbleConn = nil
    end

    bubbleConn = RunService.RenderStepped:Connect(function(dt)
        local step = config.personal_space_bubble or 0
        if step <= 0 then
            PersonalSpaceBubble.Disable()
            return
        end

        local radius = StepToRadius(step)
        local exitRadius = radius + HYSTERESIS_BUFFER

        local lp = GetLocalPlayer()
        local myChar = lp and lp.Character
        local myRoot = myChar and (myChar:FindFirstChild("HumanoidRootPart") or myChar:FindFirstChild("Head"))
        if not myRoot then return end
        local myPos = myRoot.Position

        local activeChars = {}

        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= lp and p.Character then
                local char = p.Character
                local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
                if root then
                    activeChars[char] = true
                    local dist = (root.Position - myPos).Magnitude

                    local wasInside = charInside[char] or false
                    local isInside = false
                    if wasInside then
                        isInside = (dist <= exitRadius)
                    else
                        isInside = (dist <= radius)
                    end
                    charInside[char] = isInside

                    local targetAlpha = isInside and BUBBLE_TARGET_ALPHA or 0
                    local currentAlpha = charAlphas[char] or 0

                    if isInside or currentAlpha > 0 then
                        local lerpFactor = math.clamp(dt * FADE_SPEED, 0, 1)
                        local newAlpha = currentAlpha + (targetAlpha - currentAlpha) * lerpFactor

                        if math.abs(newAlpha - targetAlpha) < 0.008 then
                            newAlpha = targetAlpha
                        end

                        charAlphas[char] = newAlpha
                        ApplyCharTransparency(char, newAlpha)

                        if newAlpha == 0 and not isInside then
                            charAlphas[char] = nil
                            charInside[char] = nil
                        end
                    end
                end
            end
        end

        for char, _ in pairs(charAlphas) do
            if not activeChars[char] then
                charAlphas[char] = nil
                charInside[char] = nil
            end
        end
    end)
    Own(bubbleConn)
end

function PersonalSpaceBubble.Disable()
    if bubbleConn then
        bubbleConn:Disconnect()
        bubbleConn = nil
    end
    for char, _ in pairs(charAlphas) do
        if char and char.Parent then
            ApplyCharTransparency(char, 0)
        end
    end
    charAlphas = {}
    charInside = {}
end

-- ============================================================================
-- Section 6: Chat Enhancements (Timestamps & Mention Chimes)
-- ============================================================================
local function FormatTimestamp()
    local s = os.date("%I:%M %p"):gsub("^0", "")
    return s
end

local function PlayMentionChime()
    task.spawn(function()
        pcall(function()
            local sound = Instance.new("Sound")
            sound.SoundId = "rbxassetid://131039887376992"
            sound.Volume = 0.85
            sound.Parent = SoundService
            sound:Play()
            sound.Ended:Connect(function() sound:Destroy() end)
            task.delay(3, function()
                if sound and sound.Parent then sound:Destroy() end
            end)
        end)
    end)
end

local existingIncomingCallback
local currentWrappedCallback

local function WrapIncomingMessageCallback(originalFn)
    return function(message)
        local props
        if typeof(originalFn) == "function" then
            local ok, res = pcall(originalFn, message)
            if ok and typeof(res) == "Instance" and res:IsA("TextChatMessageProperties") then
                props = res
            end
        end
        if not props then
            props = Instance.new("TextChatMessageProperties")
        end

        local currentPrefix = props.PrefixText ~= "" and props.PrefixText or (message and message.PrefixText) or ""
        local currentText = props.Text ~= "" and props.Text or (message and message.Text) or ""

        if config.streamer_mode then
            if currentPrefix and currentPrefix ~= "" then
                currentPrefix = RedactString(currentPrefix)
            end
            if currentText and currentText ~= "" then
                currentText = RedactString(currentText)
            end
        end

        if config.chat_timestamps then
            local timeStr = FormatTimestamp()
            props.PrefixText = string.format("<font color='#A0A0A0'>[%s]</font> %s", timeStr, currentPrefix)
        else
            props.PrefixText = currentPrefix
        end
        props.Text = currentText

        if config.mention_chimes and message and message.TextSource then
            local lp = GetLocalPlayer()
            if lp and message.TextSource.UserId ~= lp.UserId then
                local text = message.Text or ""
                local namePat = lp.Name and BuildCaseInsensitivePattern(lp.Name)
                local dispPat = lp.DisplayName and BuildCaseInsensitivePattern(lp.DisplayName)
                if (namePat and text:find(namePat)) or (dispPat and text:find(dispPat)) then
                    PlayMentionChime()
                end
            end
        end

        return props
    end
end

-- Hook TextChatService
pcall(function()
    local TextChatService = game:GetService("TextChatService")
    if TextChatService then
        existingIncomingCallback = TextChatService.OnIncomingMessage
        currentWrappedCallback = WrapIncomingMessageCallback(existingIncomingCallback)
        TextChatService.OnIncomingMessage = currentWrappedCallback
    end
end)

-- ============================================================================
-- Section 7: Anti-AFK Engine
-- ============================================================================
local AntiAFK = {}
local afkConn

function AntiAFK.Enable()
    if afkConn then afkConn:Disconnect() afkConn = nil end
    local lp = GetLocalPlayer()
    if lp then
        afkConn = lp.Idled:Connect(function()
            local VirtualUser = game:GetService("VirtualUser")
            if VirtualUser then
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new(0, 0))
            end
        end)
        Own(afkConn)
    end
end

function AntiAFK.Disable()
    if afkConn then
        afkConn:Disconnect()
        afkConn = nil
    end
end

-- ============================================================================
-- Section 8: Universal Player Locator & ESP
-- Box adornments, 28-slot highlight pool, raycast tracers, team quick-toggle
-- ============================================================================
local Locator = {}
local MAX_HIGHLIGHTS = 28
local HighlightPool = {}

for i = 1, MAX_HIGHLIGHTS do
    local hl = Instance.new("Highlight")
    hl.Name = "VirtualHighlight_" .. i
    hl.FillTransparency = 0
    hl.OutlineTransparency = 0
    hl.Enabled = false
    hl.Parent = CoreGui
    HighlightPool[i] = Own(hl)
end

local TrackedPlayers = {}
local IndividuallyTrackedPlayers = {}
local TrackedTeams = {}
local PlayerListeners = {}
local UntrackPlayerInternal

local PlayerList = CoreGui:WaitForChild("PlayerList")

local function GetActualList()
    local actualList = PlayerList:FindFirstChild("OffsetUndoFrame", true)
    if actualList then return actualList end
    
    local c = PlayerList:FindFirstChild("Children")
    c = c and c:FindFirstChild("OffsetFrame")
    c = c and c:FindFirstChild("PlayerScrollList")
    c = c and c:FindFirstChild("SizeOffsetFrame")
    if not c then return nil end
    
    local container = (c:FindFirstChild("Column") and c.Column:FindFirstChild("Body")) or c:FindFirstChild("ScrollingFrameContainer")
    if not container then return nil end
    
    local clip = container:FindFirstChild("ScrollingFrameClippingFrame")
    local scroll = clip and clip:FindFirstChild("ScrollingFrame")
    return scroll and scroll:FindFirstChild("OffsetUndoFrame")
end

local function NormalizeTeamName(t)
    if typeof(t) == "Instance" and t:IsA("Team") then return t.Name end
    return tostring(t or "")
end

local function NormalizePlayerName(p)
    if typeof(p) == "Instance" and p:IsA("Player") then return p.Name end
    return tostring(p or "")
end

local function IsPlayerTracked(PlayerName)
    PlayerName = NormalizePlayerName(PlayerName)
    return TrackedPlayers[PlayerName] ~= nil
end

local function IsPlayerIndividuallyTracked(PlayerName)
    PlayerName = NormalizePlayerName(PlayerName)
    return IndividuallyTrackedPlayers[PlayerName] == true
end

local function IsTeamTracked(TeamName)
    TeamName = NormalizeTeamName(TeamName)
    return TrackedTeams[TeamName] == true
end

local function SetLeaderboardPlayerIcon(player, show)
    if not player then return end
    local actualList = GetActualList()
    if not actualList then return end
    
    local playerEntry = actualList:FindFirstChild("PlayerEntry_" .. player.UserId, true)
    if not playerEntry then return end
    
    local content = playerEntry:FindFirstChild("PlayerEntryContentFrame")
    local overlay = content and content:FindFirstChild("OverlayFrame")
    local nameFrame = overlay and overlay:FindFirstChild("NameFrame")
    if not nameFrame then return end
    
    local locIcon = nameFrame:FindFirstChild("LocatorIcon")
    local playerIcon = nameFrame:FindFirstChild("PlayerIcon")
    
    if show then
        if not locIcon then
            locIcon = Instance.new("ImageLabel")
            locIcon.Name = "LocatorIcon"
            locIcon.LayoutOrder = 0
            locIcon.Size = UDim2.new(0, 16, 0, 16)
            locIcon.BackgroundTransparency = 1
            locIcon.Image = "rbxassetid://83346450342441"
            locIcon.Parent = nameFrame
        end
        if playerIcon and playerIcon:IsA("ImageLabel") then
            playerIcon.Visible = false
        end
    else
        if locIcon then locIcon:Destroy() end
        if playerIcon and playerIcon:IsA("ImageLabel") then
            playerIcon.Visible = true
        end
    end
end

local function SetLeaderboardTeamIcon(teamName, show)
    teamName = NormalizeTeamName(teamName)
    local actualList = GetActualList()
    if not actualList then return end
    
    local teamlist = actualList:FindFirstChild("TeamList_" .. teamName)
    if not teamlist then return end
    
    local teamEntry = teamlist:FindFirstChild("TeamEntry")
    if not teamEntry then return end
    
    local nameFrame = teamEntry:FindFirstChild("NameFrame")
    local bgFrame = nameFrame and nameFrame:FindFirstChild("BGFrame")
    local overlayFrame = bgFrame and bgFrame:FindFirstChild("OverlayFrame")
    if not overlayFrame then return end
    
    local teamNameLbl = overlayFrame:FindFirstChild("TeamName")
    local locIcon = overlayFrame:FindFirstChild("TeamLocatorIcon")
    
    if show then
        local textX = (teamNameLbl and teamNameLbl.TextBounds.X > 0) and teamNameLbl.TextBounds.X or 48
        local posX = 16 + textX + 6
        
        if not locIcon then
            locIcon = Instance.new("ImageLabel")
            locIcon.Name = "TeamLocatorIcon"
            locIcon.Size = UDim2.new(0, 16, 0, 16)
            locIcon.AnchorPoint = Vector2.new(0, 0.5)
            locIcon.Position = UDim2.new(0, posX, 0.5, 0)
            locIcon.BackgroundTransparency = 1
            locIcon.Image = "rbxassetid://83346450342441"
            locIcon.ZIndex = 5
            locIcon.Parent = overlayFrame
        else
            locIcon.Position = UDim2.new(0, posX, 0.5, 0)
        end
    else
        if locIcon then locIcon:Destroy() end
    end
end

local function BuildCharacterBoxes(character, teamColor, parentFolder)
    local boxes = {}
    if not character or not character.Parent then return boxes end
    
    for _, part in ipairs(character:GetChildren()) do
        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and part.Transparency < 0.95 then
            local box = Instance.new("BoxHandleAdornment")
            box.Name = part.Name .. "_Adornment"
            box.Adornee = part
            box.AlwaysOnTop = true
            box.ZIndex = 10
            box.Size = part.Size
            box.Color3 = teamColor
            box.Transparency = 0
            box.Parent = parentFolder
            table.insert(boxes, box)
        end
    end
    return boxes
end

local function BuildBillboard(playerName, character, parentFolder)
    if not character or not character.Parent or not parentFolder then return nil end
    local head = character:FindFirstChild("Head") or character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
    if not head then return nil end
    
    local billboard = Instance.new("BillboardGui")
    billboard.Name = playerName .. "_Billboard"
    billboard.Size = UDim2.new(0, 200, 0, 50)
    billboard.StudsOffset = (head.Name == "Head") and Vector3.new(0, 1.8, 0) or Vector3.new(0, 3.5, 0)
    billboard.AlwaysOnTop = true
    billboard.Adornee = head
    billboard.Parent = parentFolder
    
    local textLabel = Instance.new("TextLabel")
    textLabel.Name = "NameLabel"
    textLabel.BackgroundTransparency = 1
    textLabel.Position = UDim2.new(0, 0, 0, 0)
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.Font = Enum.Font.SourceSansSemibold
    textLabel.TextSize = 18
    textLabel.TextColor3 = Color3.new(1, 1, 1)
    textLabel.TextStrokeTransparency = 0
    textLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    textLabel.TextYAlignment = Enum.TextYAlignment.Center
    textLabel.TextXAlignment = Enum.TextXAlignment.Center
    textLabel.Text = playerName
    textLabel.ZIndex = 10
    textLabel.Parent = billboard
    
    return billboard
end

local function ClearPlayerAdornments(entry)
    if entry.StreamConn then
        entry.StreamConn:Disconnect()
        entry.StreamConn = nil
    end
    for _, b in ipairs(entry.Boxes) do
        b:Destroy()
    end
    entry.Boxes = {}
    if entry.Billboard then
        entry.Billboard:Destroy()
        entry.Billboard = nil
    end
end

local function TrackPlayerInternal(player)
    local localPlayer = LocalPlayer or Players.LocalPlayer
    if player == localPlayer then return end
    local playerName = player.Name
    if TrackedPlayers[playerName] then return end
    
    local container = Instance.new("Folder")
    container.Name = playerName .. "Locate"
    container.Parent = CoreGui
    
    local tracerGui = Instance.new("ScreenGui")
    tracerGui.Name = playerName .. "TracerGui"
    tracerGui.IgnoreGuiInset = true
    tracerGui.Parent = CoreGui
    
    local tracerLine = Instance.new("Frame")
    tracerLine.Name = "Line"
    tracerLine.AnchorPoint = Vector2.new(0.5, 0.5)
    tracerLine.BorderSizePixel = 0
    tracerLine.BackgroundColor3 = player.TeamColor.Color
    tracerLine.ZIndex = 100
    tracerLine.Visible = false
    tracerLine.Parent = tracerGui
    
    local entry = {
        Player = player,
        Character = player.Character,
        TeamColor = player.TeamColor.Color,
        CurrentTeam = player.Team,
        Container = container,
        TracerGui = tracerGui,
        TracerLine = tracerLine,
        Boxes = {},
        Billboard = nil,
        CharConn = nil,
        CharRemovingConn = nil,
        StreamConn = nil,
    }
    TrackedPlayers[playerName] = entry
    
    local function SetupCharacter(char)
        if not char then return end
        entry.Character = char
        ClearPlayerAdornments(entry)
        
        task.spawn(function()
            local attempts = 0
            while not char.Parent and attempts < 60 do
                attempts = attempts + 1
                task.wait(0.05)
                if not IsPlayerTracked(playerName) or entry.Character ~= char then return end
            end
            if not char.Parent or not IsPlayerTracked(playerName) then return end
            
            entry.Boxes = BuildCharacterBoxes(char, entry.TeamColor, container)
            entry.Billboard = BuildBillboard(playerName, char, container)
            
            if (#entry.Boxes == 0 or not entry.Billboard) and char.Parent then
                entry.StreamConn = char.ChildAdded:Connect(function(child)
                    if not char.Parent or not IsPlayerTracked(playerName) then
                        if entry.StreamConn then
                            entry.StreamConn:Disconnect()
                            entry.StreamConn = nil
                        end
                        return
                    end
                    if child:IsA("BasePart") then
                        if not entry.Billboard and (child.Name == "Head" or child.Name == "HumanoidRootPart") then
                            entry.Billboard = BuildBillboard(playerName, char, container)
                        end
                        if child.Name ~= "HumanoidRootPart" and child.Transparency < 0.95 then
                            local box = Instance.new("BoxHandleAdornment")
                            box.Name = child.Name .. "_Adornment"
                            box.Adornee = child
                            box.AlwaysOnTop = true
                            box.ZIndex = 10
                            box.Size = child.Size
                            box.Color3 = entry.TeamColor
                            box.Transparency = 0
                            box.Parent = container
                            table.insert(entry.Boxes, box)
                        end
                    end
                end)
                task.delay(6, function()
                    if entry.StreamConn then
                        entry.StreamConn:Disconnect()
                        entry.StreamConn = nil
                    end
                end)
            end
        end)
    end
    
    if player.Character then SetupCharacter(player.Character) end
    
    entry.CharConn = player.CharacterAdded:Connect(function(newChar)
        if IsPlayerTracked(playerName) then
            SetupCharacter(newChar or player.Character)
        end
    end)
    
    entry.CharRemovingConn = player.CharacterRemoving:Connect(function()
        ClearPlayerAdornments(entry)
        entry.Character = nil
    end)
end

function UntrackPlayerInternal(playerName)
    local entry = TrackedPlayers[playerName]
    if not entry then return end
    
    if entry.CharConn then entry.CharConn:Disconnect() entry.CharConn = nil end
    if entry.CharRemovingConn then entry.CharRemovingConn:Disconnect() entry.CharRemovingConn = nil end
    if entry.StreamConn then entry.StreamConn:Disconnect() entry.StreamConn = nil end
    
    if entry.TracerGui then entry.TracerGui:Destroy() end
    if entry.Container then entry.Container:Destroy() end
    
    TrackedPlayers[playerName] = nil
end

local function UpdatePlayerTeamColor(player)
    local entry = TrackedPlayers[player.Name]
    if not entry then return end
    
    local newColor = player.TeamColor.Color
    if entry.TeamColor ~= newColor then
        entry.TeamColor = newColor
        entry.CurrentTeam = player.Team
        if entry.TracerLine then
            entry.TracerLine.BackgroundColor3 = newColor
        end
        for _, b in ipairs(entry.Boxes) do
            b.Color3 = newColor
        end
    end
end

local function ReevaluatePlayer(player)
    local localPlayer = LocalPlayer or Players.LocalPlayer
    if not player or not player.Parent or player == localPlayer then return end
    local playerName = player.Name
    local team = player.Team
    local teamName = team and team.Name or "Neutral"
    
    local isIndividuallyTracked = (IndividuallyTrackedPlayers[playerName] == true)
    local isTeamTracked = (TrackedTeams[teamName] == true)
    local shouldTrack = isIndividuallyTracked or isTeamTracked
    
    if shouldTrack then
        if not TrackedPlayers[playerName] then
            TrackPlayerInternal(player)
        else
            UpdatePlayerTeamColor(player)
        end
    else
        if TrackedPlayers[playerName] then
            UntrackPlayerInternal(playerName)
        end
    end
    
    SetLeaderboardPlayerIcon(player, isIndividuallyTracked)
end

function Locator.TrackPlayer(PlayerName)
    IndividuallyTrackedPlayers[PlayerName] = true
    local p = Players:FindFirstChild(PlayerName)
    if p then ReevaluatePlayer(p) end
end

function Locator.UntrackPlayer(PlayerName)
    IndividuallyTrackedPlayers[PlayerName] = nil
    local p = Players:FindFirstChild(PlayerName)
    if p then ReevaluatePlayer(p) end
end

-- Centralized Render Loop: Virtual Frustum Allocation & Tracers
local RayParams = RaycastParams.new()
RayParams.FilterType = Enum.RaycastFilterType.Exclude
RayParams.IgnoreWater = true

local rayFilter = {nil, nil}
local visibleCandidates = {}

local function SortCandidatesByDistance(a, b)
    return a.Distance < b.Distance
end

local RenderConnection = RunService.RenderStepped:Connect(function()
    local Camera = Workspace.CurrentCamera
    if not Camera then return end
    
    local camPos = Camera.CFrame.Position
    local viewportSize = Camera.ViewportSize
    local localPlayer = LocalPlayer or Players.LocalPlayer
    local myChar = localPlayer and localPlayer.Character
    local myRoot = myChar and (myChar:FindFirstChild("HumanoidRootPart") or myChar:FindFirstChild("Torso"))
    local inFirstPerson = (Camera.Focus.Position - camPos).Magnitude < 1
    
    local tracerStartPos
    if inFirstPerson or not myRoot then
        tracerStartPos = Vector2.new(viewportSize.X * 0.5, viewportSize.Y)
    else
        local root2D, onScreen = Camera:WorldToViewportPoint(myRoot.Position)
        tracerStartPos = Vector2.new(root2D.X, root2D.Y)
    end
    
    table.clear(visibleCandidates)
    rayFilter[1] = myChar
    
    for playerName, entry in pairs(TrackedPlayers) do
        local character = entry.Character
        local rootPart = character and (character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso") or character.PrimaryPart)
        local teamColor = entry.TeamColor
        
        if character and character.Parent and rootPart then
            local rootPos = rootPart.Position
            local camDist = (rootPos - camPos).Magnitude
            
            local head = character:FindFirstChild("Head")
            local bestAdornee = head or rootPart
            local bb = entry.Billboard
            
            if not bb or not bb.Parent then
                entry.Billboard = BuildBillboard(playerName, character, entry.Container)
            elseif bestAdornee and (bb.Adornee ~= bestAdornee or not bb.Adornee.Parent) then
                bb.Adornee = bestAdornee
            end
            
            if entry.Billboard and entry.Billboard.Adornee then
                local isHead = (entry.Billboard.Adornee.Name == "Head")
                local targetOffset = isHead and Vector3.new(0, 1.5, 0) or Vector3.new(0, 3.5, 0)
                if entry.Billboard.StudsOffset ~= targetOffset then
                    entry.Billboard.StudsOffset = targetOffset
                end
            end
            
            local screenPos, inFrustum = Camera:WorldToViewportPoint(rootPos)
            local isBehind = screenPos.Z < 0
            local onScreen = not isBehind and 
                             screenPos.X >= -150 and screenPos.X <= (viewportSize.X + 150) and 
                             screenPos.Y >= -150 and screenPos.Y <= (viewportSize.Y + 150)
            
            local boxTrans = config.locator_esp and (1 - math.clamp(camDist / 300, 0, 1)) or 1
            for _, box in ipairs(entry.Boxes) do
                if box and box.Parent then
                    box.Transparency = boxTrans
                    local realPart = box.Adornee
                    if realPart and realPart.Parent and box.Size ~= realPart.Size then
                        box.Size = realPart.Size
                    end
                end
            end
            
            if entry.Billboard then
                entry.Billboard.Enabled = config.locator_esp
                local nameLabel = entry.Billboard:FindFirstChild("NameLabel")
                if nameLabel then
                    if config.locator_distance then
                        nameLabel.Text = string.format("%s [%d studs]", playerName, math.floor(camDist))
                    else
                        nameLabel.Text = playerName
                    end
                end
            end
            
            local tracerLine = entry.TracerLine
            if tracerLine then
                if not config.locator_tracers then
                    tracerLine.Visible = false
                else
                    local targetScreenPos = Vector2.new(screenPos.X, screenPos.Y)
                    if isBehind then
                        local center = viewportSize * 0.5
                        targetScreenPos = center - (targetScreenPos - center)
                    end
                    
                    local isOffScreen = (not onScreen) or isBehind
                    local delta = targetScreenPos - tracerStartPos
                    local dist2D = delta.Magnitude
                    
                    if dist2D > 1 then
                        local dir = delta / dist2D
                        if isOffScreen then
                            targetScreenPos = tracerStartPos + (dir * 10000)
                            delta = targetScreenPos - tracerStartPos
                            dist2D = delta.Magnitude
                        end
                        
                        local isObstructed = false
                        if not isOffScreen and head and myChar then
                            local headPos = (head:IsA("BasePart") and head.Position) or (rootPart and rootPart.Position)
                            if headPos then
                                rayFilter[2] = character
                                RayParams.FilterDescendantsInstances = rayFilter
                                local rayHit = Workspace:Raycast(camPos, (headPos - camPos), RayParams)
                                if rayHit then isObstructed = true end
                            end
                        end
                        
                        local midPoint = (tracerStartPos + targetScreenPos) * 0.5
                        local angle = math.deg(math.atan2(delta.Y, delta.X))
                        
                        tracerLine.Size = UDim2.new(0, dist2D, 0, 1)
                        tracerLine.Position = UDim2.new(0, midPoint.X, 0, midPoint.Y)
                        tracerLine.Rotation = angle
                        tracerLine.Visible = true
                        
                        local tracerTransparency = (isOffScreen or isObstructed) and 0 or (1.3 - math.clamp(camDist / 100, 0, 1))
                        tracerLine.BackgroundTransparency = tracerTransparency
                    else
                        tracerLine.Visible = false
                    end
                end
            end
            
            if onScreen then
                table.insert(visibleCandidates, {
                    Character = character,
                    Distance = camDist,
                    TeamColor = teamColor,
                })
            end
        else
            if entry.TracerLine then
                entry.TracerLine.Visible = false
            end
        end
    end
    
    if not config.locator_esp then
        for i = 1, MAX_HIGHLIGHTS do
            local hl = HighlightPool[i]
            if hl.Adornee ~= nil then hl.Adornee = nil end
            if hl.Enabled then hl.Enabled = false end
        end
    else
        table.sort(visibleCandidates, SortCandidatesByDistance)
        
        for i = 1, MAX_HIGHLIGHTS do
            local candidate = visibleCandidates[i]
            local hl = HighlightPool[i]
            
            if candidate then
                if hl.Adornee ~= candidate.Character then
                    hl.Adornee = candidate.Character
                end
                if hl.FillColor ~= candidate.TeamColor then
                    hl.FillColor = candidate.TeamColor
                end
                
                hl.FillTransparency = (1 - math.clamp(candidate.Distance / 100, 0, 1)) * 0.9
                hl.OutlineTransparency = math.clamp(candidate.Distance / 100, 0, 1) * 0.5
                
                local tc = candidate.TeamColor
                local outlineColor = (tc.R * 0.299 + tc.G * 0.587 + tc.B * 0.114) > 0.5 and Color3.new(0, 0, 0) or Color3.new(1, 1, 1)
                if hl.OutlineColor ~= outlineColor then
                    hl.OutlineColor = outlineColor
                end
                
                if not hl.Enabled then
                    hl.Enabled = true
                end
            else
                if hl.Adornee ~= nil then
                    hl.Adornee = nil
                end
                if hl.Enabled then
                    hl.Enabled = false
                end
            end
        end
    end
end)
Own(RenderConnection)

local function ToggleTeamTracking(TeamName)
    TeamName = NormalizeTeamName(TeamName)
    local currentlyTracked = (TrackedTeams[TeamName] == true)
    local newTracked = not currentlyTracked
    
    if newTracked then
        TrackedTeams[TeamName] = true
    else
        TrackedTeams[TeamName] = nil
    end
    
    SetLeaderboardTeamIcon(TeamName, newTracked)
    
    local team = Teams:FindFirstChild(TeamName)
    if team then
        for _, p in ipairs(team:GetPlayers()) do
            ReevaluatePlayer(p)
        end
    elseif TeamName == "Neutral" then
        for _, p in ipairs(Players:GetPlayers()) do
            if p.Team == nil then
                ReevaluatePlayer(p)
            end
        end
    end
    
    for pName, entry in pairs(TrackedPlayers) do
        if entry.Player then
            ReevaluatePlayer(entry.Player)
        end
    end
end

local function HookTeamHeader(teamlist)
    local teamName = string.gsub(teamlist.Name, "TeamList_", "")
    SetLeaderboardTeamIcon(teamName, TrackedTeams[teamName] == true)
    
    local lastClickTime = 0
    local lastToggleTime = 0
    
    local function onTeamClicked()
        local now = os.clock()
        if now - lastToggleTime < 0.35 then return end
        local dt = now - lastClickTime
        if dt < 0.06 then return end
        if dt < 0.55 then
            lastToggleTime = now
            lastClickTime = 0
            ToggleTeamTracking(teamName)
        else
            lastClickTime = now
        end
    end
    
    local function hookEntry(teamEntry)
        if not teamEntry or not teamEntry:IsA("GuiObject") then return end
        if teamEntry:GetAttribute("LocatorEntryHooked") then return end
        teamEntry:SetAttribute("LocatorEntryHooked", true)
        
        teamEntry.Active = true
        Own(teamEntry.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                onTeamClicked()
            end
        end))
        for _, desc in ipairs(teamEntry:GetDescendants()) do
            if desc:IsA("GuiObject") then
                desc.Active = true
                Own(desc.InputBegan:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        onTeamClicked()
                    end
                end))
            end
        end
        Own(teamEntry.DescendantAdded:Connect(function(desc)
            if desc:IsA("GuiObject") then
                desc.Active = true
                Own(desc.InputBegan:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        onTeamClicked()
                    end
                end))
            end
        end))
        SetLeaderboardTeamIcon(teamName, TrackedTeams[teamName] == true)
    end
    
    for _, child in ipairs(teamlist:GetChildren()) do
        if not string.find(child.Name, "PlayerEntry", 1, true) and child:IsA("GuiObject") then
            hookEntry(child)
        end
    end
    
    Own(teamlist.ChildAdded:Connect(function(child)
        if not string.find(child.Name, "PlayerEntry", 1, true) and child:IsA("GuiObject") then
            hookEntry(child)
        end
    end))
    
    SetLeaderboardTeamIcon(teamName, TrackedTeams[teamName] == true)
end

local function HookLocatorPlayer(player)
    local localPlayer = LocalPlayer or Players.LocalPlayer
    if player == localPlayer or PlayerListeners[player] then return end
    
    local teamConn = player:GetPropertyChangedSignal("Team"):Connect(function()
        ReevaluatePlayer(player)
    end)
    local colorConn = player:GetPropertyChangedSignal("TeamColor"):Connect(function()
        UpdatePlayerTeamColor(player)
    end)
    
    PlayerListeners[player] = { teamConn, colorConn }
    Own(teamConn)
    Own(colorConn)
    ReevaluatePlayer(player)
end

local function UnhookLocatorPlayer(player)
    local conns = PlayerListeners[player]
    if conns then
        for _, c in ipairs(conns) do c:Disconnect() end
        PlayerListeners[player] = nil
    end
    IndividuallyTrackedPlayers[player.Name] = nil
    if TrackedPlayers[player.Name] then
        UntrackPlayerInternal(player.Name)
    end
end

for _, p in ipairs(Players:GetPlayers()) do HookLocatorPlayer(p) end
Own(Players.PlayerAdded:Connect(HookLocatorPlayer))
Own(Players.PlayerRemoving:Connect(UnhookLocatorPlayer))

-- ============================================================================
-- Section 9: Leaderboard DropDown Integration & Accordion Copy Panel
-- ============================================================================
local function SafeSetClipboard(text)
    pcall(function()
        if typeof(setclipboard) == "function" then
            setclipboard(text)
        elseif typeof(toclipboard) == "function" then
            toclipboard(text)
        end
    end)
end

local function Modification1(child)
    local DropDown = child
    if not DropDown or not DropDown:IsA("GuiObject") then return end
    local inner = DropDown:WaitForChild("InnerFrame", 5)
    if not inner then return end
    inner.Position = UDim2.new(0, 0, 0, 0)
    
    if DropDown:GetAttribute("LocatorHooked") then return end

    local oldBtn = inner:FindFirstChild("LocateButton")
    if oldBtn then oldBtn:Destroy() end
    local oldPanel = inner:FindFirstChild("CopyExpandPanel")
    if oldPanel then oldPanel:Destroy() end
    
    local inspectBtn = inner:WaitForChild("InspectButton", 5)
    if not inspectBtn then return end
    local LocateButton = inspectBtn:Clone()
    
    DropDown:SetAttribute("LocatorHooked", true)
    LocateButton.Parent = inner
    Own(LocateButton)
    
    if not LocateButton:FindFirstChild("Divider") then
        LocateButton.Image = ""
        LocateButton.BackgroundTransparency = 0.3
        local Divider = Instance.new("Frame")
        Divider.Name = "Divider"
        Divider.Parent = LocateButton
        Divider.AnchorPoint = Vector2.new(0, 1)
        Divider.BackgroundColor3 = Color3.fromRGB(208, 217, 251)
        Divider.BackgroundTransparency = 0.84
        Divider.BorderSizePixel = 0
        Divider.Position = UDim2.new(0, 0, 1, 0)
        Divider.Size = UDim2.new(1, 0, 0, 1)
        Divider.ZIndex = 3
    end
    
    local PlayerHeader = inner:WaitForChild("PlayerHeader")
    local Background = PlayerHeader:WaitForChild("Background")
    local TextContainerFrame = Background:WaitForChild("TextContainerFrame")
    local PlayerNameLbl = TextContainerFrame:WaitForChild("PlayerName")
    local DisplayNameLbl = TextContainerFrame:WaitForChild("DisplayName")
    
    PlayerHeader.LayoutOrder = -2
    LocateButton.LayoutOrder = 0
    LocateButton.Name = "LocateButton"
    if LocateButton.HoverBackground:FindFirstChild("Icon") then
        LocateButton.HoverBackground.Icon:Destroy()
    end
    
    local ImageIcon = Instance.new("ImageLabel")
    ImageIcon.Name = "Icon"
    ImageIcon.Size = UDim2.new(0, 36, 0, 36)
    ImageIcon.ImageRectOffset = Vector2.new(0, 0)
    ImageIcon.ImageRectSize = Vector2.new(0, 0)
    ImageIcon.Parent = LocateButton.HoverBackground
    ImageIcon.BackgroundTransparency = 1
    
    local function GetTargetPlayer()
        local rawText = PlayerNameLbl.Text
        local pName = rawText:sub(1, 1) == "@" and rawText:sub(2) or rawText
        local player = Players:FindFirstChild(pName)
        if not player then
            for _, p in ipairs(Players:GetPlayers()) do
                if p.DisplayName == rawText or p.Name == pName then
                    player = p
                    break
                end
            end
        end
        return player, pName
    end

    local function GetTargetInfo()
        local player, pName = GetTargetPlayer()
        return {
            player = player,
            cleanName = pName,
            displayName = DisplayNameLbl.Text,
        }
    end
    
    local function UpdateButtonUI()
        local _, pName = GetTargetPlayer()
        if IsPlayerIndividuallyTracked(pName) then
            ImageIcon.Image = "rbxassetid://93890392372456"
            LocateButton.HoverBackground:WaitForChild("Text").Text = "Untrack Player"
        else
            ImageIcon.Image = "rbxassetid://129354637755552"
            LocateButton.HoverBackground:WaitForChild("Text").Text = "Track Player"
        end
    end
    
    UpdateButtonUI()
    
    local HoverEnterListener = LocateButton.MouseEnter:Connect(function()
        LocateButton.HoverBackground.BackgroundColor3 = Color3.fromRGB(208, 217, 251)
        LocateButton.HoverBackground.BackgroundTransparency = 0.92
    end)
    local HoverLeaveListener = LocateButton.MouseLeave:Connect(function()
        LocateButton.HoverBackground.BackgroundTransparency = 1
    end)
    local HoldListener = LocateButton.MouseButton1Down:Connect(function()
        LocateButton.HoverBackground.BackgroundTransparency = 0.88
    end)
    
    local ActionListener = LocateButton.Activated:Connect(function()
        local player, pName = GetTargetPlayer()
        if IsPlayerIndividuallyTracked(pName) then
            IndividuallyTrackedPlayers[pName] = nil
        else
            IndividuallyTrackedPlayers[pName] = true
        end
        if player then ReevaluatePlayer(player) end
        UpdateButtonUI()
    end)

    local EXPAND_HEIGHT = 80

    local function GetBaseHeight()
        local h = 80
        for _, child in ipairs(inner:GetChildren()) do
            if child:IsA("GuiObject") and child.Name ~= "PlayerHeader" and child.Name ~= "CopyExpandPanel" and child.Visible then
                local btnH = child.AbsoluteSize.Y > 0 and child.AbsoluteSize.Y or 56
                h = h + btnH
            end
        end
        return h
    end

    local initialWidth = DropDown.Size.X.Offset > 0 and DropDown.Size.X.Offset or 304
    DropDown.Size = UDim2.fromOffset(initialWidth, GetBaseHeight())

    local panel = Instance.new("Frame")
    panel.Name = "CopyExpandPanel"
    panel.LayoutOrder = -1
    panel.Size = UDim2.new(1, 0, 0, 0)
    panel.BackgroundColor3 = Color3.fromRGB(18, 18, 21)
    panel.BackgroundTransparency = 0.3
    panel.BorderSizePixel = 0
    panel.ClipsDescendants = true
    panel.Visible = false
    panel.Parent = inner
    Own(panel)

    local bottomDiv = Instance.new("Frame")
    bottomDiv.Name = "BottomDivider"
    bottomDiv.AnchorPoint = Vector2.new(0, 1)
    bottomDiv.Position = UDim2.new(0, 0, 1, 0)
    bottomDiv.Size = UDim2.new(1, 0, 0, 1)
    bottomDiv.BackgroundColor3 = Color3.fromRGB(208, 217, 251)
    bottomDiv.BackgroundTransparency = 0.84
    bottomDiv.BorderSizePixel = 0
    bottomDiv.Parent = panel

    local row1 = Instance.new("Frame")
    row1.Name = "Row1"
    row1.Size = UDim2.new(1, -20, 0, 28)
    row1.Position = UDim2.new(0, 10, 0, 8)
    row1.BackgroundTransparency = 1
    row1.BorderSizePixel = 0
    row1.Parent = panel

    local row2 = Instance.new("Frame")
    row2.Name = "Row2"
    row2.Size = UDim2.new(1, -20, 0, 28)
    row2.Position = UDim2.new(0, 10, 0, 42)
    row2.BackgroundTransparency = 1
    row2.BorderSizePixel = 0
    row2.Parent = panel

    local function CreatePill(parentRow, isRight, text, callback)
        local pill = Instance.new("TextButton")
        pill.Name = "Pill_" .. text:gsub("%s+", "")
        pill.Size = UDim2.new(0.5, -4, 1, 0)
        pill.Position = isRight and UDim2.new(0.5, 4, 0, 0) or UDim2.new(0, 0, 0, 0)
        pill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        pill.BackgroundTransparency = 0.92
        pill.AutoButtonColor = false
        pill.Text = ""
        pill.Parent = parentRow

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = pill

        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(208, 217, 251)
        stroke.Transparency = 0.88
        stroke.Thickness = 1
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Parent = pill

        local label = Instance.new("TextLabel")
        label.Name = "Label"
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.BuilderSansBold
        label.Text = text
        label.TextColor3 = Color3.fromRGB(240, 240, 245)
        label.TextSize = 12
        label.TextXAlignment = Enum.TextXAlignment.Center
        label.TextYAlignment = Enum.TextYAlignment.Center
        label.Parent = pill

        pill.MouseEnter:Connect(function()
            pill.BackgroundTransparency = 0.84
            stroke.Transparency = 0.75
        end)
        pill.MouseLeave:Connect(function()
            pill.BackgroundTransparency = 0.92
            stroke.Transparency = 0.88
        end)
        pill.MouseButton1Down:Connect(function()
            pill.BackgroundTransparency = 0.76
        end)
        pill.MouseButton1Up:Connect(function()
            pill.BackgroundTransparency = 0.84
        end)

        pill.Activated:Connect(function()
            local info = GetTargetInfo()
            callback(info)
            local orig = label.Text
            label.Text = "Copied!"
            task.delay(1, function()
                if label and label.Parent then label.Text = orig end
            end)
        end)

        return pill
    end

    CreatePill(row1, false, "Copy User ID", function(target)
        if target.player then
            SafeSetClipboard(tostring(target.player.UserId))
        else
            SafeSetClipboard("Unknown")
        end
    end)

    CreatePill(row1, true, "Copy Profile Link", function(target)
        if target.player then
            SafeSetClipboard("https://www.roblox.com/users/" .. tostring(target.player.UserId) .. "/profile")
        end
    end)

    CreatePill(row2, false, "Copy Username", function(target)
        local uName = target.player and target.player.Name or target.cleanName
        SafeSetClipboard(uName)
    end)

    CreatePill(row2, true, "Copy Display Name", function(target)
        local dName = target.player and target.player.DisplayName or target.displayName
        SafeSetClipboard(dName)
    end)

    local isExpanded = (panel.Visible and panel.Size.Y.Offset > 0)
    local isAnimating = false

    local function ToggleExpand(forceState)
        if isAnimating then return end
        local targetState
        if forceState ~= nil then targetState = forceState else targetState = not isExpanded end
        if targetState == isExpanded then return end
        isExpanded = targetState
        isAnimating = true

        local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local width = DropDown.Size.X.Offset > 0 and DropDown.Size.X.Offset or 304
        local baseH = GetBaseHeight()

        if isExpanded then
            panel.Visible = true
            local panelTween = TweenService:Create(panel, tweenInfo, { Size = UDim2.new(1, 0, 0, EXPAND_HEIGHT) })
            local ddTween = TweenService:Create(DropDown, tweenInfo, { Size = UDim2.fromOffset(width, baseH + EXPAND_HEIGHT) })
            panelTween:Play()
            ddTween:Play()
            task.delay(0.22, function() isAnimating = false end)
            ddTween.Completed:Once(function() isAnimating = false end)
        else
            local panelTween = TweenService:Create(panel, tweenInfo, { Size = UDim2.new(1, 0, 0, 0) })
            local ddTween = TweenService:Create(DropDown, tweenInfo, { Size = UDim2.fromOffset(width, baseH) })
            panelTween:Play()
            ddTween:Play()
            task.delay(0.22, function()
                isAnimating = false
                if not isExpanded and panel and panel.Parent then panel.Visible = false end
            end)
            ddTween.Completed:Once(function()
                isAnimating = false
                if not isExpanded and panel and panel.Parent then panel.Visible = false end
            end)
        end
    end

    local lastToggleTick = 0
    local function SafeToggle()
        if os.clock() - lastToggleTick < 0.35 then return end
        lastToggleTick = os.clock()
        task.spawn(ToggleExpand)
    end

    local ddConns = {}
    local function TrackConn(conn)
        table.insert(ddConns, conn)
        return conn
    end

    if PlayerHeader:IsA("GuiButton") or PlayerHeader:IsA("TextButton") or PlayerHeader:IsA("ImageButton") then
        TrackConn(PlayerHeader.MouseButton2Click:Connect(SafeToggle))
        TrackConn(PlayerHeader.MouseButton2Down:Connect(SafeToggle))
    end

    TrackConn(PlayerHeader.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then SafeToggle() end
    end))

    for _, desc in ipairs(PlayerHeader:GetDescendants()) do
        if desc:IsA("GuiObject") then
            TrackConn(desc.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton2 then SafeToggle() end
            end))
        end
    end

    TrackConn(PlayerHeader.DescendantAdded:Connect(function(desc)
        if desc:IsA("GuiObject") then
            TrackConn(desc.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton2 then SafeToggle() end
            end))
        end
    end))

    TrackConn(UserInputService.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            if DropDown and DropDown.Parent and DropDown.Visible and PlayerHeader and PlayerHeader.Visible then
                local mousePos = UserInputService:GetMouseLocation()
                local inset, _ = GuiService:GetGuiInset()
                local adjPos = mousePos - inset
                local hPos = PlayerHeader.AbsolutePosition
                local hSize = PlayerHeader.AbsoluteSize
                if adjPos.X >= hPos.X and adjPos.X <= (hPos.X + hSize.X)
                    and adjPos.Y >= hPos.Y and adjPos.Y <= (hPos.Y + hSize.Y) then
                    SafeToggle()
                end
            end
        end
    end))
    
    TrackConn(DropDown:GetPropertyChangedSignal("Size"):Connect(function()
        if isAnimating then return end
        local expected = GetBaseHeight() + (isExpanded and EXPAND_HEIGHT or 0)
        if DropDown.Size.Y.Offset < expected then
            local w = DropDown.Size.X.Offset > 0 and DropDown.Size.X.Offset or 304
            DropDown.Size = UDim2.fromOffset(w, expected)
        end
    end))

    TrackConn(DropDown:GetPropertyChangedSignal("Visible"):Connect(function()
        if not DropDown.Visible then
            isExpanded = false
            isAnimating = false
            panel.Size = UDim2.new(1, 0, 0, 0)
            panel.Visible = false
            local baseH = GetBaseHeight()
            local w = DropDown.Size.X.Offset > 0 and DropDown.Size.X.Offset or 304
            DropDown.Size = UDim2.fromOffset(w, baseH)
        end
    end))
    
    TrackConn(PlayerNameLbl:GetPropertyChangedSignal("Text"):Connect(function()
        UpdateButtonUI()
        if isExpanded then
            task.spawn(function() ToggleExpand(false) end)
        end
    end))
    
    TrackConn(ActionListener)
    TrackConn(HoverLeaveListener)
    TrackConn(HoverEnterListener)
    TrackConn(HoldListener)

    local function DisconnectDD()
        for _, c in ipairs(ddConns) do
            if typeof(c) == "RBXScriptConnection" then c:Disconnect() end
        end
        table.clear(ddConns)
        if DropDown and DropDown:GetAttribute("LocatorHooked") then
            DropDown:SetAttribute("LocatorHooked", nil)
        end
        if isExpanded then
            panel.Size = UDim2.new(1, 0, 0, 0)
            panel.Visible = false
            isExpanded = false
        end
    end

    TrackConn(DropDown.AncestryChanged:Connect(function()
        if not DropDown:IsDescendantOf(game) then DisconnectDD() end
    end))
    Own(DisconnectDD)
end

local function Modification2()
    local ActualList = GetActualList()
    if not ActualList then
        local found = PlayerList:WaitForChild("OffsetUndoFrame", 10)
        ActualList = found or GetActualList()
    end
    if not ActualList then return end
    
    for _, teamlist in ipairs(ActualList:GetChildren()) do
        if teamlist:IsA("Frame") and string.find(teamlist.Name, "TeamList_", 1, true) then
            HookTeamHeader(teamlist)
        end
    end
    
    for _, player in ipairs(Players:GetPlayers()) do
        if IsPlayerIndividuallyTracked(player.Name) then
            SetLeaderboardPlayerIcon(player, true)
        end
    end
    
    Own(ActualList.DescendantAdded:Connect(function(desc)
        if desc.Name == "NameFrame" then
            local entry = desc:FindFirstAncestorWhichIsA("Frame")
            if entry and entry.Name:sub(1, 12) == "PlayerEntry_" then
                local userId = tonumber(entry.Name:sub(13))
                local player = userId and Players:GetPlayerByUserId(userId)
                if player and IsPlayerIndividuallyTracked(player.Name) then
                    SetLeaderboardPlayerIcon(player, true)
                end
            elseif entry and entry.Name == "TeamEntry" then
                local teamList = entry.Parent
                if teamList and teamList.Name:sub(1, 9) == "TeamList_" then
                    local teamName = teamList.Name:sub(10)
                    if IsTeamTracked(teamName) then
                        SetLeaderboardTeamIcon(teamName, true)
                    end
                end
            end
        end
    end))
    
    Own(PlayerList.DescendantAdded:Connect(function(child)
        if child.Name == "PlayerDropDown" then
            task.spawn(Modification1, child)
        end
    end))
    
    local existingDD = PlayerList:FindFirstChild("PlayerDropDown", true)
    if existingDD then
        task.spawn(Modification1, existingDD)
    end
    
    local ListenForNewTeams = ActualList.ChildAdded:Connect(function(child)
        if child:IsA("Frame") and string.find(child.Name, "TeamList_", 1, true) then
            HookTeamHeader(child)
        end
    end)
    Own(ListenForNewTeams)
end

local function RunStartup()
    local children = PlayerList:FindFirstChild("Children")
    if not children then return end
    task.spawn(Modification2)
end

Own(PlayerList.ChildAdded:Connect(function(child)
    if child.Name == "Children" then RunStartup() end
end))
if PlayerList:FindFirstChild("Children") then RunStartup() end

-- ============================================================================
-- Section 10: In-Game ESC Menu Settings Injection
-- ============================================================================
local function FindTargetPage()
    local robloxGui = CoreGui:FindFirstChild("RobloxGui")
    if not robloxGui then return nil end
    local pvi = robloxGui:FindFirstChild("PageViewInnerFrame", true)
    if pvi then
        local page = pvi:FindFirstChild("Page")
        if page and page:FindFirstChild("RowListLayout") and page:FindFirstChild("VolumeFrame") then
            return page
        end
    end
    for _, desc in ipairs(robloxGui:GetDescendants()) do
        if desc.Name == "Page" and desc:IsA("Frame") and desc:FindFirstChild("RowListLayout") and desc:FindFirstChild("VolumeFrame") then
            return desc
        end
    end
    return nil
end

local function InjectEnhancementSettings(page)
    if not page or not page:IsDescendantOf(game) then return end

    for _, child in ipairs(page:GetChildren()) do
        if child.Name:sub(1, 12) == "Enhancement_" then
            pcall(child.Destroy, child)
        end
    end

    local menuConns = {}
    local function TrackConn(c)
        table.insert(menuConns, c)
        return c
    end

    local nativeRow = page:FindFirstChild("Option to View Untranslated MessageFrame")
        or page:FindFirstChild("Automatic Chat TranslationFrame")
        or page:FindFirstChild("FullscreenFrame") 
        or page:FindFirstChild("Automatic TranslationsFrame") 
        or page:FindFirstChild("Shift Lock SwitchFrame")

    -- 1. Section Header: "Mod Settings"
    local modHeader = Instance.new("Frame")
    modHeader.Name = "Enhancement_Header"
    modHeader.Size = UDim2.new(1, 0, 0, 48)
    modHeader.BackgroundTransparency = 1
    modHeader.LayoutOrder = -100

    local headerTxt = Instance.new("TextLabel")
    headerTxt.Name = "Text"
    headerTxt.Size = UDim2.new(1, -20, 1, 0)
    headerTxt.Position = UDim2.new(0, 10, 0, 0)
    headerTxt.BackgroundTransparency = 1
    pcall(function() headerTxt.Font = Enum.Font.BuilderSansBold end)
    if headerTxt.Font ~= Enum.Font.BuilderSansBold then
        headerTxt.Font = Enum.Font.GothamBold
    end
    headerTxt.TextSize = 20
    headerTxt.TextColor3 = Color3.fromRGB(240, 240, 245)
    headerTxt.TextXAlignment = Enum.TextXAlignment.Left
    headerTxt.TextYAlignment = Enum.TextYAlignment.Center
    headerTxt.Text = "Mod Settings"
    headerTxt.Parent = modHeader

    modHeader.Parent = page

    -- 2. Native Row Hover Applicator
    local function ClearNativeHighlights()
        for _, child in ipairs(page:GetChildren()) do
            if child:IsA("GuiObject") and not child.Name:find("Enhancement_") then
                if child.BackgroundTransparency ~= 1 then
                    child.BackgroundTransparency = 1
                end
            end
        end
    end

    local activeHoveredRow = nil

    local function SetActiveRow(targetRow)
        activeHoveredRow = targetRow
        ClearNativeHighlights()
        for _, child in ipairs(page:GetChildren()) do
            if child.Name:find("Enhancement_Row_") then
                child.BackgroundTransparency = (child == targetRow) and 0 or 1
            end
        end
    end

    TrackConn(modHeader.MouseEnter:Connect(function()
        SetActiveRow(nil)
    end))

    local function ApplyNativeRowHover(row)
        if not row then return end
        row.AutoButtonColor = false
        row.BackgroundColor3 = Color3.fromRGB(35, 37, 39)
        row.BackgroundTransparency = 1
        if row:IsA("ImageButton") then row.ImageTransparency = 1 end

        local corner = row:FindFirstChildOfClass("UICorner")
        if not corner then
            corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 8)
            corner.Parent = row
        end

        TrackConn(row.MouseEnter:Connect(function()
            SetActiveRow(row)
        end))

        TrackConn(row.MouseLeave:Connect(function()
            if activeHoveredRow == row then
                task.delay(0.02, function()
                    if activeHoveredRow == row then
                        activeHoveredRow = nil
                        row.BackgroundTransparency = 1
                    end
                end)
            end
        end))

        for _, desc in ipairs(row:GetDescendants()) do
            if desc:IsA("GuiObject") then
                TrackConn(desc.MouseEnter:Connect(function()
                    SetActiveRow(row)
                end))
                TrackConn(desc.MouseLeave:Connect(function()
                    if activeHoveredRow == row then
                        task.delay(0.02, function()
                            if activeHoveredRow == row then
                                activeHoveredRow = nil
                                row.BackgroundTransparency = 1
                            end
                        end)
                    end
                end))
            end
        end
    end

    -- 3. Toggle Row Builder
    local function CreateToggleRow(id, labelText, defaultVal, callback, layoutOrder)
        local row
        if nativeRow and nativeRow:FindFirstChild("Selector") then
            row = nativeRow:Clone()
            local lbl = row:FindFirstChild("FullscreenLabel") or row:FindFirstChildWhichIsA("TextLabel", true)
            if lbl then
                lbl.Name = id .. "Label"
                lbl.Text = labelText
                lbl.TextSize = 17
                pcall(function() lbl.Font = Enum.Font.BuilderSansMedium end)
                if lbl.Font ~= Enum.Font.BuilderSansMedium then lbl.Font = Enum.Font.GothamMedium end
                lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
            end

            local selector = row:FindFirstChild("Selector")
            if selector then
                selector.ClipsDescendants = true

                local onLbl = selector:FindFirstChild("Selection1")
                local offLbl = selector:FindFirstChild("Selection2")
                local leftBtn = selector:FindFirstChild("LeftButton")
                local rightBtn = selector:FindFirstChild("RightButton")
                local autoBtn = selector:FindFirstChild("AutoSelectButton")

                local state = (defaultVal == true)
                local TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                local isTransitioning = false

                for _, l in ipairs({onLbl, offLbl}) do
                    if l then
                        l.TextSize = 17
                        pcall(function() l.Font = Enum.Font.BuilderSans end)
                        if l.Font ~= Enum.Font.BuilderSans then l.Font = Enum.Font.Gotham end
                        l.TextColor3 = Color3.fromRGB(255, 255, 255)
                    end
                end

                if onLbl then
                    onLbl.Text = "On"
                    onLbl.Position = state and UDim2.new(0, 32, 0, 0) or UDim2.new(0, 64, 0, 0)
                    onLbl.TextTransparency = state and 0 or 1
                    onLbl.Visible = state
                end
                if offLbl then
                    offLbl.Text = "Off"
                    offLbl.Position = (not state) and UDim2.new(0, 32, 0, 0) or UDim2.new(0, 64, 0, 0)
                    offLbl.TextTransparency = (not state) and 0 or 1
                    offLbl.Visible = not state
                end

                local function SlideTransition(toState, direction)
                    if isTransitioning then return end
                    isTransitioning = true

                    local currentLbl = state and onLbl or offLbl
                    local nextLbl = toState and onLbl or offLbl
                    state = toState

                    local outPos = (direction > 0) and UDim2.new(0, 0, 0, 0) or UDim2.new(0, 64, 0, 0)
                    local inStartPos = (direction > 0) and UDim2.new(0, 64, 0, 0) or UDim2.new(0, 0, 0, 0)
                    local inEndPos = UDim2.new(0, 32, 0, 0)

                    if nextLbl then
                        nextLbl.Position = inStartPos
                        nextLbl.TextTransparency = 1
                        nextLbl.Visible = true

                        TweenService:Create(nextLbl, TWEEN_INFO, {
                            Position = inEndPos,
                            TextTransparency = 0
                        }):Play()
                    end

                    if currentLbl then
                        local tweenOut = TweenService:Create(currentLbl, TWEEN_INFO, {
                            Position = outPos,
                            TextTransparency = 1
                        })
                        tweenOut:Play()
                    end

                    task.delay(0.16, function()
                        if currentLbl and currentLbl ~= nextLbl then
                            currentLbl.Visible = false
                        end
                        isTransitioning = false
                    end)

                    callback(state)
                end

                if leftBtn and leftBtn:IsA("GuiButton") then
                    TrackConn(leftBtn.Activated:Connect(function()
                        SlideTransition(not state, -1)
                    end))
                end
                if rightBtn and rightBtn:IsA("GuiButton") then
                    TrackConn(rightBtn.Activated:Connect(function()
                        SlideTransition(not state, 1)
                    end))
                end
                if autoBtn and autoBtn:IsA("GuiButton") then
                    TrackConn(autoBtn.Activated:Connect(function()
                        SlideTransition(not state, 1)
                    end))
                end
            end
        else
            row = Instance.new("ImageButton")
            row.Size = UDim2.new(1, 0, 0, 50)
            row.BackgroundTransparency = 1
            row.AutoButtonColor = false

            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.new(0.45, -20, 1, 0)
            lbl.Position = UDim2.new(0, 10, 0, 0)
            lbl.BackgroundTransparency = 1
            pcall(function() lbl.Font = Enum.Font.BuilderSansMedium end)
            if lbl.Font ~= Enum.Font.BuilderSansMedium then lbl.Font = Enum.Font.Gotham end
            lbl.TextSize = 16
            lbl.TextColor3 = Color3.fromRGB(240, 240, 245)
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.Text = labelText
            lbl.Parent = row

            local sel = Instance.new("Frame")
            sel.Name = "Selector"
            sel.Size = UDim2.new(0.55, 0, 1, 0)
            sel.Position = UDim2.new(0.45, 0, 0, 0)
            sel.BackgroundTransparency = 1
            sel.Parent = row

            local state = (defaultVal == true)
            local statusLbl = Instance.new("TextButton")
            statusLbl.Size = UDim2.new(1, -20, 0, 34)
            statusLbl.Position = UDim2.new(0, 10, 0.5, -17)
            statusLbl.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
            pcall(function() statusLbl.Font = Enum.Font.BuilderSansBold end)
            if statusLbl.Font ~= Enum.Font.BuilderSansBold then statusLbl.Font = Enum.Font.GothamBold end
            statusLbl.TextSize = 14
            statusLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
            statusLbl.Text = state and "<  On  >" or "<  Off  >"
            statusLbl.Parent = sel

            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 6)
            corner.Parent = statusLbl

            local function OnToggle()
                state = not state
                statusLbl.Text = state and "<  On  >" or "<  Off  >"
                callback(state)
            end
            TrackConn(statusLbl.Activated:Connect(OnToggle))
        end

        ApplyNativeRowHover(row)
        row.Name = "Enhancement_Row_" .. id
        row.LayoutOrder = layoutOrder
        row.Parent = page
        return row
    end

    -- 4. 10-Step Segmented Slider Builder (Cloned from Native VolumeFrame with Drag & Slide)
    local function CreateSliderRow(id, labelText, defaultVal, callback, layoutOrder)
        local nativeSlider = page:FindFirstChild("VolumeFrame")
        local row
        local currentStep = math.clamp(tonumber(defaultVal) or 0, 0, 10)

        if nativeSlider then
            row = nativeSlider:Clone()
            local lbl = row:FindFirstChild("VolumeLabel") or row:FindFirstChildWhichIsA("TextLabel", true)
            if lbl then
                lbl.Name = id .. "Label"
                lbl.Text = labelText
                lbl.TextSize = 17
                pcall(function() lbl.Font = Enum.Font.BuilderSansMedium end)
                if lbl.Font ~= Enum.Font.BuilderSansMedium then lbl.Font = Enum.Font.GothamMedium end
                lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
            end

            local slider = row:FindFirstChild("Slider")
            local stepsContainer = slider and slider:FindFirstChild("StepsContainer")
            local leftBtn = slider and slider:FindFirstChild("LeftButton")
            local rightBtn = slider and slider:FindFirstChild("RightButton")

            local INACTIVE_COLOR = Color3.fromRGB(57, 59, 61)
            local ACTIVE_COLOR = Color3.fromRGB(255, 255, 255)

            local function UpdateVisuals(step)
                currentStep = step
                if stepsContainer then
                    for i = 1, 10 do
                        local stepBtn = stepsContainer:FindFirstChild("Step" .. i)
                        if stepBtn then
                            local isActive = (i <= currentStep)
                            local col = isActive and ACTIVE_COLOR or INACTIVE_COLOR
                            stepBtn.BackgroundColor3 = col
                            stepBtn.BackgroundTransparency = 0
                            local filler = stepBtn:FindFirstChild("Filler")
                            if filler then
                                filler.BackgroundColor3 = col
                                filler.BackgroundTransparency = 0
                            end
                        end
                    end
                end
                if leftBtn then leftBtn.Visible = (currentStep > 0) end
                if rightBtn then rightBtn.Visible = (currentStep < 10) end
            end

            UpdateVisuals(currentStep)

            -- Drag & Slide Functionality (Matching Native Volume Slider)
            local isDragging = false
            local startX = 0
            local hasDragged = false
            local initialStepOnPress = currentStep

            local function UpdateFromX(xPos)
                if not stepsContainer then return end
                local left = stepsContainer.AbsolutePosition.X
                local width = stepsContainer.AbsoluteSize.X
                if width <= 0 then return end
                local relX = xPos - left
                local slotWidth = width / 10
                local newStep
                if relX <= slotWidth * 0.2 then
                    newStep = 0
                else
                    newStep = math.clamp(math.ceil(relX / slotWidth), 1, 10)
                end
                if newStep ~= currentStep then
                    UpdateVisuals(newStep)
                    callback(newStep)
                end
            end

            local function StartDrag(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    isDragging = true
                    startX = input.Position.X
                    hasDragged = false
                    initialStepOnPress = currentStep
                    UpdateFromX(input.Position.X)
                end
            end

            if stepsContainer then
                TrackConn(stepsContainer.InputBegan:Connect(StartDrag))
                for i = 1, 10 do
                    local stepBtn = stepsContainer:FindFirstChild("Step" .. i)
                    if stepBtn and stepBtn:IsA("GuiButton") then
                        TrackConn(stepBtn.InputBegan:Connect(StartDrag))
                        TrackConn(stepBtn.Activated:Connect(function()
                            if not hasDragged and i == 1 and initialStepOnPress == 1 then
                                UpdateVisuals(0)
                                callback(0)
                            end
                        end))
                    end
                end
            end

            if slider and slider:IsA("GuiButton") then
                TrackConn(slider.InputBegan:Connect(StartDrag))
            end

            TrackConn(UserInputService.InputChanged:Connect(function(input)
                if isDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                    if math.abs(input.Position.X - startX) > 3 then
                        hasDragged = true
                    end
                    UpdateFromX(input.Position.X)
                end
            end))

            TrackConn(UserInputService.InputEnded:Connect(function(input)
                if isDragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
                    isDragging = false
                end
            end))

            if leftBtn and leftBtn:IsA("GuiButton") then
                TrackConn(leftBtn.Activated:Connect(function()
                    if currentStep > 0 then
                        UpdateVisuals(currentStep - 1)
                        callback(currentStep)
                    end
                end))
            end

            if rightBtn and rightBtn:IsA("GuiButton") then
                TrackConn(rightBtn.Activated:Connect(function()
                    if currentStep < 10 then
                        UpdateVisuals(currentStep + 1)
                        callback(currentStep)
                    end
                end))
            end
        else
            row = Instance.new("ImageButton")
            row.Size = UDim2.new(1, 0, 0, 50)
            row.BackgroundTransparency = 1
            row.AutoButtonColor = false

            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.new(0.4, -20, 1, 0)
            lbl.Position = UDim2.new(0, 10, 0, 0)
            lbl.BackgroundTransparency = 1
            pcall(function() lbl.Font = Enum.Font.BuilderSansMedium end)
            if lbl.Font ~= Enum.Font.BuilderSansMedium then lbl.Font = Enum.Font.Gotham end
            lbl.TextSize = 17
            lbl.TextColor3 = Color3.fromRGB(240, 240, 245)
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.Text = labelText
            lbl.Parent = row

            local slider = Instance.new("Frame")
            slider.Name = "Slider"
            slider.Size = UDim2.new(0.6, 0, 1, 0)
            slider.Position = UDim2.new(0.4, 0, 0, 0)
            slider.BackgroundTransparency = 1
            slider.Parent = row

            local stepsContainer = Instance.new("Frame")
            stepsContainer.Name = "StepsContainer"
            stepsContainer.Size = UDim2.new(1, -100, 0, 24)
            stepsContainer.AnchorPoint = Vector2.new(0.5, 0.5)
            stepsContainer.Position = UDim2.new(0.5, 0, 0.5, 0)
            stepsContainer.BackgroundTransparency = 1
            stepsContainer.Parent = slider

            local stepButtons = {}
            local INACTIVE_COLOR = Color3.fromRGB(57, 59, 61)
            local ACTIVE_COLOR = Color3.fromRGB(255, 255, 255)

            local function UpdateVisuals(step)
                currentStep = step
                for j = 1, 10 do
                    if stepButtons[j] then
                        local isActive = (j <= currentStep)
                        stepButtons[j].BackgroundColor3 = isActive and ACTIVE_COLOR or INACTIVE_COLOR
                        stepButtons[j].BackgroundTransparency = 0
                    end
                end
            end

            local isDragging = false
            local startX = 0
            local hasDragged = false
            local initialStepOnPress = currentStep

            local function UpdateFromX(xPos)
                if not stepsContainer then return end
                local left = stepsContainer.AbsolutePosition.X
                local width = stepsContainer.AbsoluteSize.X
                if width <= 0 then return end
                local relX = xPos - left
                local slotWidth = width / 10
                local newStep
                if relX <= slotWidth * 0.2 then
                    newStep = 0
                else
                    newStep = math.clamp(math.ceil(relX / slotWidth), 1, 10)
                end
                if newStep ~= currentStep then
                    UpdateVisuals(newStep)
                    callback(newStep)
                end
            end

            local function StartDrag(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    isDragging = true
                    startX = input.Position.X
                    hasDragged = false
                    initialStepOnPress = currentStep
                    UpdateFromX(input.Position.X)
                end
            end

            TrackConn(stepsContainer.InputBegan:Connect(StartDrag))

            for i = 1, 10 do
                local stepBtn = Instance.new("TextButton")
                stepBtn.Name = "Step" .. i
                stepBtn.Size = UDim2.new(0.1, -4, 1, 0)
                stepBtn.Position = UDim2.new((i - 1) * 0.1, 2, 0, 0)
                stepBtn.Text = ""
                stepBtn.BackgroundColor3 = (i <= currentStep) and ACTIVE_COLOR or INACTIVE_COLOR
                stepBtn.BackgroundTransparency = 0
                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(0, 3)
                corner.Parent = stepBtn
                stepBtn.Parent = stepsContainer
                stepButtons[i] = stepBtn

                TrackConn(stepBtn.InputBegan:Connect(StartDrag))
                TrackConn(stepBtn.Activated:Connect(function()
                    if not hasDragged and i == 1 and initialStepOnPress == 1 then
                        UpdateVisuals(0)
                        callback(0)
                    end
                end))
            end

            TrackConn(UserInputService.InputChanged:Connect(function(input)
                if isDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                    if math.abs(input.Position.X - startX) > 3 then
                        hasDragged = true
                    end
                    UpdateFromX(input.Position.X)
                end
            end))

            TrackConn(UserInputService.InputEnded:Connect(function(input)
                if isDragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
                    isDragging = false
                end
            end))
        end

        ApplyNativeRowHover(row)
        row.Name = "Enhancement_Row_" .. id
        row.LayoutOrder = layoutOrder
        row.Parent = page
        return row
    end

    -- Construct Rows
    CreateToggleRow("StreamerMode", "Streamer Mode", config.streamer_mode, function(val)
        config.streamer_mode = val
        SaveConfig()
        if val then StreamerMode.Enable() else StreamerMode.Disable() end
    end, -90)

    CreateSliderRow("PersonalSpaceBubble", "Personal Space Bubble", config.personal_space_bubble or 0, function(val)
        config.personal_space_bubble = val
        SaveConfig()
        if val > 0 then PersonalSpaceBubble.Enable() else PersonalSpaceBubble.Disable() end
    end, -89)

    CreateToggleRow("LocatorTracers", "Locator Tracers", config.locator_tracers, function(val)
        config.locator_tracers = val
        SaveConfig()
    end, -88)

    CreateToggleRow("LocatorDistance", "Distance Readouts", config.locator_distance, function(val)
        config.locator_distance = val
        SaveConfig()
    end, -87)

    CreateToggleRow("ChatTimestamps", "Chat Timestamps", config.chat_timestamps, function(val)
        config.chat_timestamps = val
        SaveConfig()
    end, -86)

    CreateToggleRow("MentionChimes", "Mention Chimes", config.mention_chimes, function(val)
        config.mention_chimes = val
        SaveConfig()
    end, -85)

    CreateToggleRow("AntiAFK", "Anti-AFK", config.anti_afk, function(val)
        config.anti_afk = val
        SaveConfig()
        if val then AntiAFK.Enable() else AntiAFK.Disable() end
    end, -84)

    -- Divider
    local modDivider = Instance.new("Frame")
    modDivider.Name = "Enhancement_Divider"
    modDivider.Size = UDim2.new(1, 0, 0, 16)
    modDivider.BackgroundTransparency = 1
    modDivider.LayoutOrder = -1

    local line = Instance.new("Frame")
    line.Size = UDim2.new(1, -20, 0, 1)
    line.Position = UDim2.new(0, 10, 0.5, 0)
    line.BackgroundColor3 = Color3.fromRGB(80, 80, 85)
    line.BackgroundTransparency = 0.5
    line.BorderSizePixel = 0
    line.Parent = modDivider
    modDivider.Parent = page

    TrackConn(modDivider.MouseEnter:Connect(function() SetActiveRow(nil) end))

    local function CleanupMenu()
        for _, c in ipairs(menuConns) do
            if typeof(c) == "RBXScriptConnection" then c:Disconnect() end
        end
        table.clear(menuConns)
        for _, child in ipairs(page:GetChildren()) do
            if child.Name:sub(1, 12) == "Enhancement_" then
                pcall(child.Destroy, child)
            end
        end
    end
    Own(CleanupMenu)
end

local function SetupWatcher()
    local robloxGui = CoreGui:FindFirstChild("RobloxGui")
    if not robloxGui then return end

    local function ShouldRebuild(p)
        if not p then return false end
        local h = p:FindFirstChild("Enhancement_Header")
        if not h or #h:GetChildren() == 0 then return true end
        return false
    end

    local function TriggerFastInject()
        task.spawn(function()
            for i = 1, 40 do
                local p = FindTargetPage()
                if p and ShouldRebuild(p) then
                    InjectEnhancementSettings(p)
                    break
                elseif p and not ShouldRebuild(p) then
                    break
                end
                task.wait(0.025)
            end
        end)
    end

    local shield = robloxGui:FindFirstChild("SettingsShield", true)
    if shield then
        Own(shield:GetPropertyChangedSignal("Visible"):Connect(function()
            if shield.Visible then
                TriggerFastInject()
            end
        end))
    end

    local pvi = robloxGui:FindFirstChild("PageViewInnerFrame", true)
    if pvi then
        Own(pvi.ChildAdded:Connect(function(child)
            if child.Name == "Page" then
                TriggerFastInject()
            end
        end))
        local page = pvi:FindFirstChild("Page")
        if page then
            Own(page:GetPropertyChangedSignal("Visible"):Connect(function()
                if page.Visible and ShouldRebuild(page) then
                    InjectEnhancementSettings(page)
                end
            end))
            Own(page.ChildAdded:Connect(function(child)
                if child.Name == "VolumeFrame" or child.Name == "RowListLayout" then
                    if ShouldRebuild(page) then
                        InjectEnhancementSettings(page)
                    end
                end
            end))
        end
    end

    Own(robloxGui.DescendantAdded:Connect(function(desc)
        if desc.Name == "VolumeFrame" then
            local p = desc.Parent
            if p and p.Name == "Page" and ShouldRebuild(p) then
                InjectEnhancementSettings(p)
            end
        end
    end))

    Own(GuiService.MenuOpened:Connect(function()
        TriggerFastInject()
    end))

    task.spawn(function()
        while genv and genv.__EnhancementCleanup do
            task.wait(1.0)
            local p = FindTargetPage()
            if ShouldRebuild(p) then
                InjectEnhancementSettings(p)
            end
        end
    end)
end

-- ============================================================================
-- Section 11: System Sync, Initialization & Cleanup Export
-- ============================================================================
local function SyncWithSystems()
    if config.streamer_mode then
        StreamerMode.Enable()
    else
        StreamerMode.Disable()
    end

    if (config.personal_space_bubble or 0) > 0 then
        PersonalSpaceBubble.Enable()
    else
        PersonalSpaceBubble.Disable()
    end

    if config.anti_afk then
        AntiAFK.Enable()
    else
        AntiAFK.Disable()
    end
end

SyncWithSystems()
SetupWatcher()

local initPage = FindTargetPage()
if initPage then
    InjectEnhancementSettings(initPage)
end

local function FullSuiteCleanup()
    -- 1. Streamer Mode Cleanup
    if StreamerMode and StreamerMode.Disable then
        pcall(StreamerMode.Disable)
    end

    -- 2. Personal Space Bubble Cleanup
    if PersonalSpaceBubble and PersonalSpaceBubble.Disable then
        pcall(PersonalSpaceBubble.Disable)
    end

    -- 3. Anti-AFK Cleanup
    if AntiAFK and AntiAFK.Disable then
        pcall(AntiAFK.Disable)
    end

    -- 4. Locator Cleanup
    for pName, _ in pairs(TrackedPlayers) do
        pcall(UntrackPlayerInternal, pName)
    end
    table.clear(TrackedPlayers)
    table.clear(IndividuallyTrackedPlayers)
    table.clear(TrackedTeams)

    for player, conns in pairs(PlayerListeners) do
        if type(conns) == "table" then
            for _, c in ipairs(conns) do
                if typeof(c) == "RBXScriptConnection" then c:Disconnect() end
            end
        end
    end
    table.clear(PlayerListeners)

    -- 5. Leaderboard Cleanup
    local actualList = GetActualList()
    if actualList then
        for _, desc in ipairs(actualList:GetDescendants()) do
            if desc.Name == "LocatorIcon" or desc.Name == "TeamLocatorIcon" then
                desc:Destroy()
            elseif desc.Name == "PlayerIcon" and desc:IsA("ImageLabel") then
                desc.Visible = true
            end
        end
    end
    if PlayerList then
        for _, desc in ipairs(PlayerList:GetDescendants()) do
            if desc.Name == "LocateButton" or desc.Name == "CopyExpandPanel" or desc.Name == "InlineCopyPanel" then
                desc:Destroy()
            end
            if desc:GetAttribute("LocatorHooked") then
                desc:SetAttribute("LocatorHooked", nil)
            end
        end
    end

    -- 6. Clean Janitor (all connections and instances)
    for i = #Janitor, 1, -1 do
        local x = Janitor[i]
        if typeof(x) == "RBXScriptConnection" then
            x:Disconnect()
        elseif typeof(x) == "Instance" then
            pcall(x.Destroy, x)
        elseif type(x) == "function" then
            pcall(x)
        end
        Janitor[i] = nil
    end

    print("[RobloxEnhancement]: Suite fully cleaned up.")
end

if genv then
    genv.__EnhancementCleanup = FullSuiteCleanup
    genv.RobloxEnhancement = {
        StreamerMode = StreamerMode,
        PersonalSpaceBubble = PersonalSpaceBubble,
        Locator = Locator,
        AntiAFK = AntiAFK,
        Config = config,
        Cleanup = FullSuiteCleanup,
    }
end

print("[RobloxEnhancement]: Successfully loaded and initialized all enhancement modules!")

return {
    StreamerMode = StreamerMode,
    PersonalSpaceBubble = PersonalSpaceBubble,
    Locator = Locator,
    AntiAFK = AntiAFK,
    Config = config,
    Cleanup = FullSuiteCleanup,
}
