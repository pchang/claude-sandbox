-- Main.server.lua (Script, runs on server only)
--
-- The boot script. Responsibilities:
--   * Create every RemoteEvent up front so client scripts never race
--   * Spawn each player at the clearing next to the broken car
--   * Forward FlashlightToggle events to all clients (so others see the beam — used in Phase 2)
--
-- World setup, car setup, and pickup spawning are handled by their own
-- *.server.lua scripts which run automatically at server startup.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared     = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes    = require(Shared:WaitForChild("Remotes"))

-- Pre-create every named RemoteEvent so clients can WaitForChild safely
Remotes.initAll()

print("[Server] " .. GameConfig.GameName .. " v" .. GameConfig.Version .. " starting...")

-- Build a SpawnLocation at the configured spawn position (next to the car)
local existingSpawn = Workspace:FindFirstChild("ForestSpawn")
if existingSpawn then existingSpawn:Destroy() end

local spawnPart = Instance.new("SpawnLocation")
spawnPart.Name = "ForestSpawn"
spawnPart.Size = Vector3.new(8, 1, 8)
spawnPart.Position = GameConfig.PlayerSpawnPosition
spawnPart.Anchored = true
spawnPart.Material = Enum.Material.Slate
spawnPart.Color = Color3.fromRGB(60, 60, 70)
spawnPart.TopSurface = Enum.SurfaceType.Smooth
spawnPart.Neutral = true
spawnPart.Duration = 0  -- no forcefield on respawn
spawnPart.Parent = Workspace

Players.PlayerAdded:Connect(function(player)
	print("[Server] Player joined:", player.Name)
	-- Make sure they spawn at our SpawnLocation
	player.RespawnLocation = spawnPart
	-- Camera mode is controlled by GameUI.client.lua based on round state:
	--   * LOBBY (title screen)  → Classic (free camera + cursor)
	--   * PLAYING               → LockFirstPerson (immersive horror view)
	player.CharacterAdded:Connect(function(character)
		local hum = character:WaitForChild("Humanoid", 5)
		if hum then
			hum.WalkSpeed = GameConfig.WalkSpeed
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	print("[Server] Player left:", player.Name)
end)

print("[Server] Ready. Waiting for players...")
