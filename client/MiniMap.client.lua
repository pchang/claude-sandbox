-- MiniMap.client.lua (LocalScript)
--
-- A simple north-up minimap in the top-right corner:
--   * White circle  = local player
--   * Red square    = the car
--   * Yellow circle = each cave (4 of them, fixed positions from GameConfig)
--
-- The monster is intentionally NOT shown.

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local Workspace        = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared      = ReplicatedStorage:WaitForChild("Shared")
local GameConfig  = require(Shared:WaitForChild("GameConfig"))
local Remotes     = require(Shared:WaitForChild("Remotes"))

local gameStateRemote = Remotes.wait(Remotes.Names.GameStateChanged)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ===== Layout constants =====

local MAP_SIZE_PX = 180
local PADDING_PX = 16
local WORLD_TO_PX = MAP_SIZE_PX / GameConfig.ForestSize  -- studs → pixels
local HALF_WORLD = GameConfig.ForestSize / 2

-- ===== Build the UI =====

local miniGui = Instance.new("ScreenGui")
miniGui.Name = "MiniMap"
miniGui.ResetOnSpawn = false
miniGui.IgnoreGuiInset = true
miniGui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Name = "MiniMapFrame"
frame.Size = UDim2.new(0, MAP_SIZE_PX, 0, MAP_SIZE_PX)
frame.Position = UDim2.new(1, -MAP_SIZE_PX - PADDING_PX, 0, PADDING_PX)
frame.BackgroundColor3 = Color3.fromRGB(20, 25, 22)
frame.BackgroundTransparency = 0.25
frame.BorderSizePixel = 0
frame.ZIndex = 30
frame.Parent = miniGui

local frameCorner = Instance.new("UICorner")
frameCorner.CornerRadius = UDim.new(0, 8)
frameCorner.Parent = frame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(80, 80, 90)
stroke.Thickness = 1.5
stroke.Transparency = 0.4
stroke.Parent = frame

-- Crosshair lines through center
local function makeAxisLine(horizontal: boolean)
	local line = Instance.new("Frame")
	if horizontal then
		line.Size = UDim2.new(1, 0, 0, 1)
		line.Position = UDim2.new(0, 0, 0.5, 0)
	else
		line.Size = UDim2.new(0, 1, 1, 0)
		line.Position = UDim2.new(0.5, 0, 0, 0)
	end
	line.BackgroundColor3 = Color3.fromRGB(80, 80, 90)
	line.BackgroundTransparency = 0.6
	line.BorderSizePixel = 0
	line.ZIndex = 31
	line.Parent = frame
end
makeAxisLine(true)
makeAxisLine(false)

-- ===== Coordinate conversion =====

local function worldToMiniMap(world: Vector3): (number, number)
	local mx = math.clamp((world.X + HALF_WORLD) * WORLD_TO_PX, 0, MAP_SIZE_PX)
	local my = math.clamp((world.Z + HALF_WORLD) * WORLD_TO_PX, 0, MAP_SIZE_PX)
	return mx, my
end

-- ===== Cave markers (static, since caves don't move) =====

for i, pos in ipairs(GameConfig.CavePositions) do
	local mx, my = worldToMiniMap(pos)
	local caveDot = Instance.new("Frame")
	caveDot.Name = "CaveMarker" .. i
	caveDot.Size = UDim2.new(0, 9, 0, 9)
	caveDot.AnchorPoint = Vector2.new(0.5, 0.5)
	caveDot.Position = UDim2.new(0, mx, 0, my)
	caveDot.BackgroundColor3 = Color3.fromRGB(255, 200, 60)   -- yellow/gold
	caveDot.BorderSizePixel = 0
	caveDot.ZIndex = 32
	caveDot.Parent = frame
	local caveDotCorner = Instance.new("UICorner")
	caveDotCorner.CornerRadius = UDim.new(1, 0)
	caveDotCorner.Parent = caveDot
end

-- ===== Car marker (red square) =====

local carDot = Instance.new("Frame")
carDot.Name = "CarMarker"
carDot.Size = UDim2.new(0, 10, 0, 10)
carDot.AnchorPoint = Vector2.new(0.5, 0.5)
carDot.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
carDot.BorderSizePixel = 0
carDot.ZIndex = 33
carDot.Parent = frame

-- ===== Player marker (white circle) =====

local playerDot = Instance.new("Frame")
playerDot.Name = "PlayerMarker"
playerDot.Size = UDim2.new(0, 8, 0, 8)
playerDot.AnchorPoint = Vector2.new(0.5, 0.5)
playerDot.BackgroundColor3 = Color3.fromRGB(240, 240, 240)
playerDot.BorderSizePixel = 0
playerDot.ZIndex = 34
playerDot.Parent = frame
local playerDotCorner = Instance.new("UICorner")
playerDotCorner.CornerRadius = UDim.new(1, 0)
playerDotCorner.Parent = playerDot

-- ===== Update loop =====

local function updateMarker(marker: Frame, world: Vector3)
	local mx, my = worldToMiniMap(world)
	marker.Position = UDim2.new(0, mx, 0, my)
end

RunService.Heartbeat:Connect(function()
	local character = player.Character
	if character then
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			updateMarker(playerDot, root.Position)
			playerDot.Visible = true
		else
			playerDot.Visible = false
		end
	else
		playerDot.Visible = false
	end

	local car = Workspace:FindFirstChild("BrokenCar")
	local body = car and car:FindFirstChild("Body") :: BasePart?
	if body then
		updateMarker(carDot, body.Position)
		carDot.Visible = true
	else
		carDot.Visible = false
	end
end)

-- Hide the minimap on the title screen / between rounds. Show during gameplay.
gameStateRemote.OnClientEvent:Connect(function(s)
	miniGui.Enabled = (s == "playing")
end)
miniGui.Enabled = false

print("[MiniMap] ready")
