-- AudioAtmosphere.client.lua (LocalScript)
--
-- Atmospheric horror effects:
--   * Twig snap: when the monster comes within MonsterCloseDistance of the
--     local player, every TwigSnapCooldown seconds there's a TwigSnapChance
--     (default 85%) of playing a snap sound.
--   * Whispers: every 12-35 seconds (random) a phrase from GameConfig.WhisperLines
--     fades in on-screen and an accompanying whisper sound plays.
--
-- Sound effects need real asset IDs in GameConfig.TwigSnapSoundId / WhisperSoundId.
-- Without IDs, the on-screen text whispers still work — silent but creepy.
-- Both effects only fire while the round state is "playing".

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local SoundService     = game:GetService("SoundService")
local Workspace        = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService     = game:GetService("TweenService")

local Shared      = ReplicatedStorage:WaitForChild("Shared")
local GameConfig  = require(Shared:WaitForChild("GameConfig"))
local Remotes     = require(Shared:WaitForChild("Remotes"))

local gameStateRemote = Remotes.wait(Remotes.Names.GameStateChanged)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ===== Whisper UI: fading italic-ish text near the top of the screen =====

local atmosphereGui = Instance.new("ScreenGui")
atmosphereGui.Name = "AtmosphereGUI"
atmosphereGui.ResetOnSpawn = false
atmosphereGui.IgnoreGuiInset = true
atmosphereGui.Parent = playerGui

local whisperLabel = Instance.new("TextLabel")
whisperLabel.Name = "Whisper"
whisperLabel.Size = UDim2.new(0.8, 0, 0, 60)
whisperLabel.Position = UDim2.new(0.1, 0, 0.18, 0)
whisperLabel.BackgroundTransparency = 1
whisperLabel.Font = Enum.Font.PatrickHand
whisperLabel.TextSize = 30
whisperLabel.TextColor3 = Color3.fromRGB(210, 210, 230)
whisperLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
whisperLabel.TextStrokeTransparency = 0.4
whisperLabel.TextTransparency = 1
whisperLabel.Text = ""
whisperLabel.ZIndex = 60
whisperLabel.Parent = atmosphereGui

-- ===== Round-state mirror =====

local currentRoundState = "lobby"
gameStateRemote.OnClientEvent:Connect(function(s)
	if typeof(s) == "string" then
		currentRoundState = s
	end
end)

local function isPlaying(): boolean
	return currentRoundState == "playing"
end

-- ===== Sound helpers =====

-- Cheap sanity check: empty string or known-placeholder skip playback
local function hasSoundId(id: string?): boolean
	return typeof(id) == "string" and id ~= "" and id ~= "rbxassetid://0"
end

local function play2DSound(soundId: string, volume: number)
	if not hasSoundId(soundId) then return end
	local sound = Instance.new("Sound")
	-- Allow either bare numeric IDs or full "rbxassetid://..." strings
	if not string.find(soundId, "://") then
		soundId = "rbxassetid://" .. soundId
	end
	sound.SoundId = soundId
	sound.Volume = volume
	sound.Parent = SoundService   -- not parented in 3D space → plays in player's ears
	sound:Play()
	sound.Ended:Connect(function() sound:Destroy() end)
	-- Failsafe: clean up after 10s even if Ended didn't fire (preview audio etc.)
	task.delay(10, function()
		if sound and sound.Parent then sound:Destroy() end
	end)
end

-- ===== Whisper effect =====

local function showWhisperText(text: string)
	whisperLabel.Text = text
	whisperLabel.TextTransparency = 1
	whisperLabel.TextStrokeTransparency = 1
	-- Fade in, hold, fade out
	local fadeIn = TweenService:Create(
		whisperLabel,
		TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ TextTransparency = 0.15, TextStrokeTransparency = 0.4 }
	)
	fadeIn:Play()
	task.delay(2.8, function()
		local fadeOut = TweenService:Create(
			whisperLabel,
			TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ TextTransparency = 1, TextStrokeTransparency = 1 }
		)
		fadeOut:Play()
	end)
end

local function fireWhisper()
	local lines = GameConfig.WhisperLines
	if not lines or #lines == 0 then return end
	local phrase = lines[math.random(1, #lines)]
	showWhisperText(phrase)
	play2DSound(GameConfig.WhisperSoundId, 0.55)
end

task.spawn(function()
	while true do
		local delay = math.random(
			GameConfig.WhisperMinInterval or 12,
			GameConfig.WhisperMaxInterval or 35
		)
		task.wait(delay)
		if isPlaying() then
			fireWhisper()
		end
	end
end)

-- ===== Twig snap effect =====

local lastTwigTime = 0

local function tryTwigSnap()
	local now = os.clock()
	if now - lastTwigTime < (GameConfig.TwigSnapCooldown or 6) then return end

	-- 85% chance per opportunity
	if math.random() > (GameConfig.TwigSnapChance or 0.85) then return end

	lastTwigTime = now
	play2DSound(GameConfig.TwigSnapSoundId, 0.75)
end

-- Distance check loop (every 1.5s; cheap)
task.spawn(function()
	while true do
		task.wait(1.5)
		if not isPlaying() then continue end

		local character = player.Character
		if not character then continue end
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then continue end

		local monster = Workspace:FindFirstChild("Monster")
		if not monster then continue end
		local mRoot = monster:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not mRoot then continue end

		local distance = (root.Position - mRoot.Position).Magnitude
		if distance < (GameConfig.MonsterCloseDistance or 50) then
			tryTwigSnap()
		end
	end
end)

print("[Atmosphere] Audio system ready (sound IDs:",
	hasSoundId(GameConfig.TwigSnapSoundId) and "twig OK" or "twig MISSING",
	"|",
	hasSoundId(GameConfig.WhisperSoundId) and "whisper OK" or "whisper MISSING",
	")")
