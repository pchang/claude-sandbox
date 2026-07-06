-- WorldBuilder.server.lua (Script, runs on server only)
--
-- Procedurally generates the foggy forest:
--   * Sets dusk lighting + thick gray fog via Lighting service
--   * Spawns a large dirt-colored ground plate
--   * Scatters TreeCount trees randomly across the forest, avoiding
--     a clearing around the car spawn so it's accessible

local Lighting   = game:GetService("Lighting")
local Workspace  = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local WorldBuilder = {}

-- Cave positions are random per server, provided by PickupSpawner.
-- Falls back to the GameConfig values if the API isn't ready yet.
-- (Declared here at the top so any later function can reference it.)
local function getCavePositions(): { Vector3 }
	if _G.GameAPI and _G.GameAPI.getCavePositions then
		return _G.GameAPI.getCavePositions()
	end
	return GameConfig.CavePositions
end

-- Reusable: build a single tree (trunk + conical leaves) at a position.
local function buildTree(position: Vector3, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Tree"

	-- Slight random scale so trees feel natural
	local heightScale = 1 + (math.random() - 0.5) * 0.6  -- 0.7 to 1.3

	local trunk = Instance.new("Part")
	trunk.Name = "Trunk"
	trunk.Shape = Enum.PartType.Cylinder
	trunk.Size = Vector3.new(18 * heightScale, 2.5, 2.5)
	-- Cylinder's long axis is X, so rotate to stand upright
	trunk.CFrame = CFrame.new(position + Vector3.new(0, (18 * heightScale) / 2, 0))
		* CFrame.Angles(0, 0, math.rad(90))
	trunk.Anchored = true
	trunk.Material = Enum.Material.Wood
	trunk.Color = Color3.fromRGB(50, 35, 25)
	trunk.CastShadow = true
	trunk.Parent = model

	local leaves = Instance.new("Part")
	leaves.Name = "Leaves"
	leaves.Shape = Enum.PartType.Ball
	local leafSize = 12 + math.random() * 6
	leaves.Size = Vector3.new(leafSize, leafSize, leafSize)
	leaves.Position = position + Vector3.new(0, 18 * heightScale, 0)
	leaves.Anchored = true
	leaves.Material = Enum.Material.Grass
	-- Pine-needle dark green, slightly varied
	local g = 35 + math.random(0, 25)
	leaves.Color = Color3.fromRGB(15, g, 20)
	leaves.CastShadow = true
	leaves.Parent = model

	model.Parent = parent
	return model
end

-- Build invisible collidable walls around the perimeter so players stay in
local function buildBorders()
	local existing = Workspace:FindFirstChild("ForestBorders")
	if existing then existing:Destroy() end

	local folder = Instance.new("Folder")
	folder.Name = "ForestBorders"
	folder.Parent = Workspace

	local half = GameConfig.ForestSize / 2
	local h = GameConfig.BorderHeight
	local t = GameConfig.BorderThickness
	local len = GameConfig.ForestSize + t * 2

	local function makeWall(name: string, position: Vector3, size: Vector3)
		local wall = Instance.new("Part")
		wall.Name = name
		wall.Size = size
		wall.Position = position
		wall.Anchored = true
		wall.CanCollide = true
		wall.Transparency = 1            -- invisible but collidable
		wall.CastShadow = false
		wall.Parent = folder
	end

	makeWall("North", Vector3.new(0,         h / 2, -half - t / 2), Vector3.new(len, h, t))
	makeWall("South", Vector3.new(0,         h / 2,  half + t / 2), Vector3.new(len, h, t))
	makeWall("East",  Vector3.new( half + t / 2, h / 2, 0),         Vector3.new(t, h, len))
	makeWall("West",  Vector3.new(-half - t / 2, h / 2, 0),         Vector3.new(t, h, len))

	print("[WorldBuilder] Border walls placed")
end

-- One cave: ring of large rocks with a 5-stud entrance gap, capped with a
-- low rock slab as a roof. The wheel pickup is later placed at the center.
local function buildCave(centerXZ: Vector3, parent: Instance, caveIndex: number)
	local model = Instance.new("Model")
	model.Name = "Cave" .. caveIndex

	-- (No floor — players walk on the forest ground that's already there.)

	-- Roof: a wide flat slab over the cave
	local roof = Instance.new("Part")
	roof.Name = "Roof"
	roof.Size = Vector3.new(22, 1.5, 22)
	roof.Position = centerXZ + Vector3.new(0, 9.5, 0)
	roof.Anchored = true
	roof.Material = Enum.Material.Rock
	roof.Color = Color3.fromRGB(55, 50, 50)
	roof.Parent = model

	-- Ring of boulders. We pick an entrance angle and skip rocks near it.
	local entranceAngleDeg = math.random(0, 359)
	local entranceArc = 80  -- degrees of opening (wide enough to walk through comfortably)
	local rockCount = 14
	for i = 1, rockCount do
		local theta = (i - 1) * (360 / rockCount)
		local diff = ((theta - entranceAngleDeg + 540) % 360) - 180
		if math.abs(diff) < entranceArc / 2 then
			continue  -- this is the doorway, leave it open
		end

		local rad = math.rad(theta)
		local r = 9.5
		local px = centerXZ.X + math.cos(rad) * r
		local pz = centerXZ.Z + math.sin(rad) * r

		local boulder = Instance.new("Part")
		boulder.Name = "CaveRock"
		local sx = 4 + math.random() * 2
		local sy = 7 + math.random() * 2
		local sz = 4 + math.random() * 2
		boulder.Size = Vector3.new(sx, sy, sz)
		boulder.CFrame = CFrame.new(Vector3.new(px, sy / 2 + 1, pz))
			* CFrame.Angles(
				math.rad(math.random(-10, 10)),
				math.rad(math.random(0, 360)),
				math.rad(math.random(-10, 10))
			)
		boulder.Anchored = true
		boulder.Material = Enum.Material.Rock
		local v = 55 + math.random(0, 20)
		boulder.Color = Color3.fromRGB(v, v, v + math.random(0, 5))
		boulder.Parent = model
	end

	-- Soft glow inside the cave so the wheel within is visible.
	-- Lives on the roof since there's no floor anymore.
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(180, 200, 255)
	glow.Brightness = 0.8
	glow.Range = 16
	glow.Parent = roof

	model.Parent = parent
	return model
end

local function buildCaves()
	local existing = Workspace:FindFirstChild("Caves")
	if existing then existing:Destroy() end

	local folder = Instance.new("Folder")
	folder.Name = "Caves"
	folder.Parent = Workspace

	local positions = getCavePositions()
	for i, pos in ipairs(positions) do
		buildCave(pos, folder, i)
	end
	print(string.format("[WorldBuilder] Built %d caves at random positions", #positions))
end

local function buildGround()
	local ground = Workspace:FindFirstChild("ForestGround")
	if ground then ground:Destroy() end

	ground = Instance.new("Part")
	ground.Name = "ForestGround"
	ground.Anchored = true
	-- Add a generous margin so the player can't walk off the edge easily
	local size = GameConfig.ForestSize + 200
	ground.Size = Vector3.new(size, 2, size)
	ground.Position = Vector3.new(0, 0, 0)
	ground.Material = Enum.Material.Ground
	ground.Color = GameConfig.GroundColor
	ground.TopSurface = Enum.SurfaceType.Smooth
	ground.BottomSurface = Enum.SurfaceType.Smooth
	ground.Parent = Workspace
end

-- A scattered ground bush: low dome of dark green
local function buildBush(position: Vector3, parent: Instance): Part
	local bush = Instance.new("Part")
	bush.Name = "Bush"
	bush.Shape = Enum.PartType.Ball
	local s = 3 + math.random() * 3  -- 3 to 6 studs across
	bush.Size = Vector3.new(s, s * 0.55, s)  -- squashed dome
	bush.Position = position + Vector3.new(0, s * 0.2, 0)
	bush.Anchored = true
	bush.Material = Enum.Material.LeafyGrass
	-- Dark mossy green with random tinge
	local g = 45 + math.random(0, 30)
	bush.Color = Color3.fromRGB(20, g, 25)
	bush.CastShadow = true
	bush.CanCollide = false  -- player can walk through bushes
	bush.Parent = parent
	return bush
end

-- A mossy rock: gray block with random scale + slight rotation
local function buildRock(position: Vector3, parent: Instance): Part
	local rock = Instance.new("Part")
	rock.Name = "Rock"
	local sx = 2 + math.random() * 5
	local sy = 1.5 + math.random() * 3
	local sz = 2 + math.random() * 5
	rock.Size = Vector3.new(sx, sy, sz)
	rock.CFrame = CFrame.new(position + Vector3.new(0, sy / 2, 0))
		* CFrame.Angles(
			math.rad(math.random(-15, 15)),
			math.rad(math.random(0, 360)),
			math.rad(math.random(-15, 15))
		)
	rock.Anchored = true
	rock.Material = Enum.Material.Slate
	-- Gray with slight green moss tinge
	local v = 70 + math.random(0, 30)
	rock.Color = Color3.fromRGB(v, v + math.random(0, 8), v - math.random(0, 5))
	rock.CastShadow = true
	rock.Parent = parent
	return rock
end

-- Returns true if (x,z) is too close to the central clearing OR any cave
local function isBlockedSpot(x: number, z: number): boolean
	if math.sqrt(x * x + z * z) <= GameConfig.ClearingRadius then
		return true
	end
	for _, c in ipairs(getCavePositions()) do
		local dx, dz = x - c.X, z - c.Z
		if math.sqrt(dx * dx + dz * dz) <= GameConfig.CaveClearingRadius then
			return true
		end
	end
	return false
end

-- Generic scatterer used for trees, bushes, and rocks
local function scatter(count: number, builder: (Vector3, Instance) -> any, folder: Instance)
	local half = GameConfig.ForestSize / 2
	local placed = 0
	local attempts = 0
	local maxAttempts = count * 4

	while placed < count and attempts < maxAttempts do
		attempts += 1
		local x = math.random(-half, half)
		local z = math.random(-half, half)
		if not isBlockedSpot(x, z) then
			builder(Vector3.new(x, 1, z), folder)
			placed += 1
		end
	end
	return placed
end

local function buildForest()
	-- Reuse folders so re-runs don't double-up
	for _, name in ipairs({ "Trees", "Bushes", "Rocks" }) do
		local existing = Workspace:FindFirstChild(name)
		if existing then existing:Destroy() end
	end

	local treesFolder = Instance.new("Folder")
	treesFolder.Name = "Trees"
	treesFolder.Parent = Workspace

	local bushesFolder = Instance.new("Folder")
	bushesFolder.Name = "Bushes"
	bushesFolder.Parent = Workspace

	local rocksFolder = Instance.new("Folder")
	rocksFolder.Name = "Rocks"
	rocksFolder.Parent = Workspace

	local trees  = scatter(GameConfig.TreeCount,  buildTree,  treesFolder)
	local bushes = scatter(GameConfig.BushCount,  buildBush,  bushesFolder)
	local rocks  = scatter(GameConfig.RockCount,  buildRock,  rocksFolder)

	print(string.format(
		"[WorldBuilder] Placed %d trees, %d bushes, %d rocks",
		trees, bushes, rocks
	))
end

local function applyAtmosphere()
	Lighting.FogStart   = GameConfig.FogStart
	Lighting.FogEnd     = GameConfig.FogEnd
	Lighting.FogColor   = GameConfig.FogColor
	Lighting.Ambient    = GameConfig.AmbientColor
	Lighting.OutdoorAmbient = GameConfig.OutdoorAmbient
	Lighting.ClockTime  = GameConfig.ClockTime
	Lighting.Brightness = GameConfig.Brightness
	-- Disable global shadows softness change; keep defaults otherwise
end

function WorldBuilder.build()
	print("[WorldBuilder] Building forest world...")
	applyAtmosphere()
	buildGround()
	buildBorders()
	buildCaves()
	buildForest()
	print("[WorldBuilder] Done.")
end

-- Build the world immediately when this script runs
WorldBuilder.build()
