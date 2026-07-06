-- Jumpscare.client.lua (LocalScript)
--
-- Plays a short, brutal jumpscare when the server tells this client
-- that the monster has caught them.
--
-- The visual is built from primitives (no image assets needed):
--   * Full-screen black overlay
--   * Two huge glowing red eyes that zoom toward the camera
--   * Jagged white teeth at the bottom
--   * A red flash at the peak
--   * Camera shake via Humanoid.CameraOffset
--   * Loud screech (SoundId is a placeholder for Paul to fill in)
--
-- Total duration ~1.2 seconds, then fades cleanly so the LOSE overlay
-- from GameUI.client.lua takes over.

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local SoundService     = game:GetService("SoundService")
local TweenService     = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared  = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local jumpscareRemote = Remotes.wait(Remotes.Names.MonsterJumpscare)

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ===== Sound =====
-- Replace the SoundId with any Roblox audio asset id (e.g. "rbxassetid://1234567")
-- to swap in your favorite horror screech. Empty id will play nothing.
local screech = Instance.new("Sound")
screech.Name = "JumpscareScreech"
screech.SoundId = ""             -- TODO: paste a screech asset id here
screech.Volume = 3
screech.RollOffMaxDistance = 1   -- 2D sound (we parent to SoundService)
screech.Parent = SoundService

-- ===== One-time GUI build (kept disabled until needed) =====

local gui = Instance.new("ScreenGui")
gui.Name = "JumpscareGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 200            -- above lose/win overlay (which is ~110)
gui.Enabled = false
gui.Parent = playerGui

-- Black backdrop
local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.new(1, 0, 1, 0)
backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
backdrop.BackgroundTransparency = 1
backdrop.BorderSizePixel = 0
backdrop.ZIndex = 200
backdrop.Parent = gui

-- Red flash overlay (sits above the face, used for the punchy flash)
local flash = Instance.new("Frame")
flash.Name = "Flash"
flash.Size = UDim2.new(1, 0, 1, 0)
flash.BackgroundColor3 = Color3.fromRGB(180, 0, 0)
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.ZIndex = 220
flash.Parent = gui

-- Holder that anchors the "face" in the middle and lets us scale it
local face = Instance.new("Frame")
face.Name = "Face"
face.AnchorPoint = Vector2.new(0.5, 0.5)
face.Position = UDim2.new(0.5, 0, 0.5, 0)
face.Size = UDim2.new(0, 50, 0, 50)   -- starts tiny; tween scales it up
face.BackgroundTransparency = 1
face.ZIndex = 210
face.Parent = gui

-- ----- Eyes -----
local function makeEye(side: number): (Frame, Frame)
	-- side = -1 (left) or +1 (right)
	local eye = Instance.new("Frame")
	eye.Name = "Eye_" .. (side < 0 and "L" or "R")
	eye.AnchorPoint = Vector2.new(0.5, 0.5)
	eye.Position = UDim2.new(0.5, side * 90, 0.45, 0)  -- scales with face
	eye.Size = UDim2.fromScale(0.32, 0.32)
	eye.BackgroundColor3 = Color3.fromRGB(255, 20, 20)
	eye.BorderSizePixel = 0
	eye.ZIndex = 211
	eye.Parent = face
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = eye
	local glow = Instance.new("UIStroke")
	glow.Color = Color3.fromRGB(255, 120, 120)
	glow.Thickness = 6
	glow.Transparency = 0.2
	glow.Parent = eye

	-- vertical slit pupil (black) inside each eye
	local pupil = Instance.new("Frame")
	pupil.Name = "Pupil"
	pupil.AnchorPoint = Vector2.new(0.5, 0.5)
	pupil.Position = UDim2.new(0.5, 0, 0.5, 0)
	pupil.Size = UDim2.fromScale(0.18, 0.7)
	pupil.BackgroundColor3 = Color3.fromRGB(10, 0, 0)
	pupil.BorderSizePixel = 0
	pupil.ZIndex = 212
	pupil.Parent = eye

	return eye, pupil
end

local leftEye  = makeEye(-1)
local rightEye = makeEye(1)

-- ----- Mouth + jagged teeth -----
local mouth = Instance.new("Frame")
mouth.Name = "Mouth"
mouth.AnchorPoint = Vector2.new(0.5, 0.5)
mouth.Position = UDim2.new(0.5, 0, 1.05, 0)   -- below the eyes
mouth.Size = UDim2.fromScale(1.1, 0.45)
mouth.BackgroundColor3 = Color3.fromRGB(20, 0, 0)
mouth.BorderSizePixel = 0
mouth.ZIndex = 211
mouth.Parent = face
local mouthCorner = Instance.new("UICorner")
mouthCorner.CornerRadius = UDim.new(0, 8)
mouthCorner.Parent = mouth

-- Build jagged teeth out of rotated white squares pinned along the top of the mouth
local NUM_TEETH = 9
for i = 1, NUM_TEETH do
	local tooth = Instance.new("Frame")
	tooth.Name = "Tooth" .. i
	tooth.AnchorPoint = Vector2.new(0.5, 0)
	-- Spread evenly across the mouth
	local t = (i - 0.5) / NUM_TEETH
	tooth.Position = UDim2.new(t, 0, 0, -2)
	tooth.Size = UDim2.fromScale(0.09, 0.55)
	tooth.Rotation = 45
	tooth.BackgroundColor3 = Color3.fromRGB(230, 220, 200)
	tooth.BorderSizePixel = 0
	tooth.ZIndex = 212
	tooth.Parent = mouth
end

-- ===== Animation helpers =====

local camera = workspace.CurrentCamera

local function getHumanoid(): Humanoid?
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

-- Camera shake by jittering Humanoid.CameraOffset for `duration` seconds.
local function shakeCamera(duration: number, intensity: number)
	task.spawn(function()
		local hum = getHumanoid()
		local elapsed = 0
		local conn
		conn = RunService.RenderStepped:Connect(function(dt)
			elapsed += dt
			if elapsed >= duration or not hum or not hum.Parent then
				if conn then conn:Disconnect() end
				if hum and hum.Parent then
					hum.CameraOffset = Vector3.new(0, 0, 0)
				end
				return
			end
			-- Falloff so the shake eases out
			local k = 1 - (elapsed / duration)
			local mag = intensity * k
			hum.CameraOffset = Vector3.new(
				(math.random() - 0.5) * mag,
				(math.random() - 0.5) * mag,
				(math.random() - 0.5) * mag
			)
		end)
	end)
end

-- ===== Playback =====

local playing = false

local function playJumpscare()
	if playing then return end
	playing = true

	-- Reset visual state in case a previous run left it weird
	backdrop.BackgroundTransparency = 1
	flash.BackgroundTransparency = 1
	face.Size = UDim2.fromOffset(40, 40)
	gui.Enabled = true

	-- Sound
	if screech.SoundId ~= "" then
		screech.TimePosition = 0
		screech:Play()
	end

	-- Backdrop slams to black almost instantly
	TweenService:Create(backdrop, TweenInfo.new(0.05), {
		BackgroundTransparency = 0,
	}):Play()

	-- Face zooms aggressively
	local zoomTween = TweenService:Create(
		face,
		TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(900, 900) }
	)
	zoomTween:Play()

	-- Red flash pulse at the peak
	task.delay(0.15, function()
		TweenService:Create(flash, TweenInfo.new(0.1), {
			BackgroundTransparency = 0.25,
		}):Play()
		task.wait(0.12)
		TweenService:Create(flash, TweenInfo.new(0.25), {
			BackgroundTransparency = 1,
		}):Play()
	end)

	-- Camera shake throughout
	shakeCamera(0.9, 1.2)

	-- Hold the face for a moment, then fade everything out
	task.wait(0.85)
	local fadeInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(backdrop, fadeInfo, { BackgroundTransparency = 1 }):Play()
	-- Fade the face by tweening every descendant frame's transparency at once
	for _, d in ipairs(face:GetDescendants()) do
		if d:IsA("Frame") then
			TweenService:Create(d, fadeInfo, { BackgroundTransparency = 1 }):Play()
		elseif d:IsA("UIStroke") then
			TweenService:Create(d, fadeInfo, { Transparency = 1 }):Play()
		end
	end
	TweenService:Create(face, fadeInfo, { BackgroundTransparency = 1 }):Play()
	task.wait(0.4)

	gui.Enabled = false

	-- Reset transparencies for next run
	for _, d in ipairs(face:GetDescendants()) do
		if d:IsA("Frame") then d.BackgroundTransparency = 0 end
		if d:IsA("UIStroke") then d.Transparency = 0.2 end
	end

	playing = false
end

jumpscareRemote.OnClientEvent:Connect(playJumpscare)

print("[Jumpscare] ready")
