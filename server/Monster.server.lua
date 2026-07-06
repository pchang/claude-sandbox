-- Monster.server.lua (Script, server only)
--
-- The faceless humanoid that hunts the players.
-- Behavior is "weeping angel" style:
--   * If ANY player has the monster in their camera view, it FREEZES.
--   * If NOBODY can see it, it pathfinds toward the closest player at full speed.
--   * If it gets within MonsterCatchRadius of a player, prints "caught"
--     (the round-end logic plugs in here in the next phase).
--
-- Visibility is reported by clients via the MonsterVisibility RemoteEvent.
-- We trust the clients here (cheating in a co-op horror game just makes it
-- less scary for the cheater).

local Players          = game:GetService("Players")
local Workspace        = game:GetService("Workspace")
local RunService       = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared      = ReplicatedStorage:WaitForChild("Shared")
local GameConfig  = require(Shared:WaitForChild("GameConfig"))
local Remotes     = require(Shared:WaitForChild("Remotes"))

local visibilityRemote = Remotes.get(Remotes.Names.MonsterVisibility)

-- Per-player visibility flag. Default false. Cleared on leave.
local playersWatching: { [Player]: boolean } = {}
visibilityRemote.OnServerEvent:Connect(function(player, visible)
	if typeof(visible) ~= "boolean" then return end
	playersWatching[player] = visible
end)
Players.PlayerRemoving:Connect(function(player)
	playersWatching[player] = nil
end)

local function anyoneWatching(): boolean
	for _, v in pairs(playersWatching) do
		if v then return true end
	end
	return false
end

-- Find a random forest position at least minDist from every alive player
local function pickSpawnPosition(minDist: number): Vector3
	local half = GameConfig.ForestSize / 2 - 30
	for _ = 1, 60 do
		local x = math.random(-half, half)
		local z = math.random(-half, half)
		local pos = Vector3.new(x, 5, z)
		local farEnough = true
		for _, p in ipairs(Players:GetPlayers()) do
			local char = p.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and (root.Position - pos).Magnitude < minDist then
				farEnough = false
				break
			end
		end
		if farEnough then return pos end
	end
	return Vector3.new(half, 5, half)  -- fallback
end

-- Holds the per-monster animation handles built by buildMonster()
type MonsterRig = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	leftHip: Motor6D,
	rightHip: Motor6D,
	leftShoulder: Motor6D,
	rightShoulder: Motor6D,
	-- Base C0 transforms captured at construction time so we can layer
	-- swing rotations on top each frame.
	leftHipBase: CFrame,
	rightHipBase: CFrame,
	leftShoulderBase: CFrame,
	rightShoulderBase: CFrame,
}

-- Helper: create a Motor6D between part0 and part1, with the joint anchored
-- at jointWorldPos. C0/C1 are derived from the parts' current world poses
-- so visual position is preserved.
local function makeJoint(name: string, part0: BasePart, part1: BasePart, jointWorldPos: Vector3): Motor6D
	local jointCFrame = CFrame.new(jointWorldPos)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = part0.CFrame:ToObjectSpace(jointCFrame)
	m.C1 = part1.CFrame:ToObjectSpace(jointCFrame)
	m.Parent = part0
	return m
end

-- Build the monster: a tall black humanoid silhouette with animated limbs.
--
-- Geometry (relative to root center):
--   torso center       y = -1            (size 2.4 × 4 × 1.4 → top y=1, bottom y=-3)
--   head center        y = +1.8          (sphere r=0.8 → bottom y=+1, touches torso top)
--   arm center         y = -1.0          (size 0.9 × 4 × 0.9 → top y=+1, bottom y=-3)
--   leg center         y = -4.7          (size 1.0 × 3.5 × 1.0 → top y=-2.95, bottom y=-6.45)
--
-- Lowest point of the body is therefore root.Y - 6.45.
-- For the feet to rest on the ground (top surface at y=1), we need
-- root.Y = 7.45. With a 2-tall HumanoidRootPart, root.bottom = root.Y - 1 = 6.45,
-- so HipHeight (root.bottom → ground) = 6.45 - 1 = 5.45.
local function buildMonster(): MonsterRig
	local model = Instance.new("Model")
	model.Name = "Monster"

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.CanCollide = false
	root.Anchored = false
	root.Massless = false
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Parent = model

	local function makeBodyPart(name: string, size: Vector3, offsetFromRoot: Vector3, isBall: boolean?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		if isBall then p.Shape = Enum.PartType.Ball end
		p.Color = GameConfig.MonsterColor
		p.Material = Enum.Material.SmoothPlastic
		p.Reflectance = 0
		p.CanCollide = false
		p.Anchored = false
		p.Massless = true
		p.CFrame = root.CFrame * CFrame.new(offsetFromRoot)
		p.Parent = model
		return p
	end

	local torso = makeBodyPart("Torso",     Vector3.new(2.4, 4, 1.4),  Vector3.new(0, -1, 0))
	local head  = makeBodyPart("Head",      Vector3.new(1.6, 1.6, 1.6),Vector3.new(0,  1.8, 0), true)
	local lArm  = makeBodyPart("LeftArm",   Vector3.new(0.9, 4, 0.9),  Vector3.new(-1.6, -1.0, 0))
	local rArm  = makeBodyPart("RightArm",  Vector3.new(0.9, 4, 0.9),  Vector3.new( 1.6, -1.0, 0))
	local lLeg  = makeBodyPart("LeftLeg",   Vector3.new(1.0, 3.5, 1.0),Vector3.new(-0.6, -4.7, 0))
	local rLeg  = makeBodyPart("RightLeg",  Vector3.new(1.0, 3.5, 1.0),Vector3.new( 0.6, -4.7, 0))

	-- Joints — Motor6Ds so we can animate swings. Joint world positions are
	-- chosen so animation rotates around the natural pivot (hip, shoulder, etc.)
	local rootPos = root.Position

	-- RootJoint (waist) — required for Humanoid; static
	local rootJoint = makeJoint("RootJoint", root, torso, rootPos + Vector3.new(0, -1, 0))
	-- (We don't animate the waist; rootJoint just holds the torso onto the root.)

	-- Neck — static
	makeJoint("Neck", torso, head, rootPos + Vector3.new(0, 1.0, 0))

	-- Shoulders — pivot at the top of each arm (root y +1.0 in Y, x ±1.6)
	local leftShoulder  = makeJoint("LeftShoulder",  root, lArm, rootPos + Vector3.new(-1.6, 1.0, 0))
	local rightShoulder = makeJoint("RightShoulder", root, rArm, rootPos + Vector3.new( 1.6, 1.0, 0))

	-- Hips — pivot at the top of each leg (root y -2.95, x ±0.6)
	local leftHip  = makeJoint("LeftHip",  root, lLeg, rootPos + Vector3.new(-0.6, -2.95, 0))
	local rightHip = makeJoint("RightHip", root, rLeg, rootPos + Vector3.new( 0.6, -2.95, 0))

	-- Suppress rootJoint warning (some Luau analyzers complain about unused locals)
	rootJoint.Name = "RootJoint"

	local humanoid = Instance.new("Humanoid")
	humanoid.WalkSpeed = GameConfig.MonsterSpeed
	humanoid.MaxHealth = math.huge
	humanoid.Health    = math.huge
	humanoid.HipHeight = 5.45      -- so the feet rest on the ground (see geometry note above)
	humanoid.DisplayName = " "     -- blank name above the monster (creepy nameless feel)
	humanoid.Parent = model

	model.PrimaryPart = root

	return {
		model = model,
		humanoid = humanoid,
		root = root,
		leftHip = leftHip,           rightHip = rightHip,
		leftShoulder = leftShoulder, rightShoulder = rightShoulder,
		leftHipBase  = leftHip.C0,   rightHipBase  = rightHip.C0,
		leftShoulderBase = leftShoulder.C0, rightShoulderBase = rightShoulder.C0,
	}
end

-- Pick the closest player's character root (or nil if none)
local function getClosestPlayerRoot(monsterRoot: BasePart): (BasePart?, Player?)
	local best: BasePart? = nil
	local bestPlayer: Player? = nil
	local bestDist = math.huge
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local d = (root.Position - monsterRoot.Position).Magnitude
			if d < bestDist then
				bestDist = d
				best = root
				bestPlayer = p
			end
		end
	end
	return best, bestPlayer
end

-- Track the active monster + its update connection so we can despawn cleanly
local activeMonster: Model? = nil
local activeConnection: RBXScriptConnection? = nil
local monsterPaused = false  -- RoundManager pauses the monster between rounds

local function despawnMonster()
	if activeConnection then
		activeConnection:Disconnect()
		activeConnection = nil
	end
	if activeMonster then
		activeMonster:Destroy()
		activeMonster = nil
	end
	-- Clear visibility flags so a new monster starts fresh
	for k, _ in pairs(playersWatching) do
		playersWatching[k] = false
	end
end

local function spawnMonster()
	despawnMonster()

	local rig = buildMonster()
	local model, humanoid, root = rig.model, rig.humanoid, rig.root
	local spawnPos = pickSpawnPosition(GameConfig.MonsterSpawnDistance)
	model:PivotTo(CFrame.new(spawnPos))
	model.Parent = Workspace
	activeMonster = model

	print("[Monster] Spawned at", spawnPos)

	-- ===== Walking animation loop =====
	-- When the monster is moving, swing legs and arms in opposing sine
	-- patterns. When stopped, smoothly relax to the rest pose.
	local walkPhase = 0
	local SWING_AMPLITUDE = 0.65          -- radians (~37°), exaggerated stalk
	local SWING_FREQUENCY = 4             -- radians/sec (~0.6 Hz cycle)
	local REST_LERP_SPEED = 6             -- how fast limbs return to rest

	local function animate(dt: number)
		-- Use horizontal velocity magnitude to detect movement
		local vel = root.AssemblyLinearVelocity
		local horizontalSpeed = math.sqrt(vel.X * vel.X + vel.Z * vel.Z)
		local moving = horizontalSpeed > 0.5

		if moving then
			walkPhase += dt * SWING_FREQUENCY
			local angle = math.sin(walkPhase) * SWING_AMPLITUDE
			local swing  = CFrame.Angles(angle, 0, 0)
			local oppose = CFrame.Angles(-angle, 0, 0)
			rig.leftHip.C0       = rig.leftHipBase       * swing
			rig.rightHip.C0      = rig.rightHipBase      * oppose
			rig.leftShoulder.C0  = rig.leftShoulderBase  * oppose
			rig.rightShoulder.C0 = rig.rightShoulderBase * swing
		else
			-- Lerp back toward rest pose
			local alpha = math.clamp(dt * REST_LERP_SPEED, 0, 1)
			rig.leftHip.C0       = rig.leftHip.C0:Lerp(rig.leftHipBase, alpha)
			rig.rightHip.C0      = rig.rightHip.C0:Lerp(rig.rightHipBase, alpha)
			rig.leftShoulder.C0  = rig.leftShoulder.C0:Lerp(rig.leftShoulderBase, alpha)
			rig.rightShoulder.C0 = rig.rightShoulder.C0:Lerp(rig.rightShoulderBase, alpha)
		end
	end

	-- Configure pathfinding agent
	local path = PathfindingService:CreatePath({
		AgentRadius   = 2,
		AgentHeight   = 8,
		AgentCanJump  = false,
		WaypointSpacing = 6,
	})

	-- Main pursuit loop: every 0.8s, recompute path to nearest player
	-- and start walking. If any player is looking, freeze.
	local catchRadius = GameConfig.MonsterCatchRadius
	local pursuitConnection: RBXScriptConnection? = nil

	local function freeze()
		humanoid.WalkSpeed = 0
		humanoid:MoveTo(root.Position)  -- cancel current movement
	end

	local function unfreeze()
		humanoid.WalkSpeed = GameConfig.MonsterSpeed
	end

	local lastPathTime = 0
	local currentWaypoints: { PathWaypoint } = {}
	local currentWaypointIndex = 1

	local function recomputePath(targetPos: Vector3)
		local ok, err = pcall(function()
			path:ComputeAsync(root.Position, targetPos)
		end)
		if not ok then
			warn("[Monster] Pathfinding failed:", err)
			currentWaypoints = {}
			return
		end
		if path.Status == Enum.PathStatus.Success then
			currentWaypoints = path:GetWaypoints()
			currentWaypointIndex = 2  -- skip the first (it's our current pos)
		else
			currentWaypoints = {}
		end
	end

	-- Update loop. Stored on activeConnection so we can stop it on despawn.
	activeConnection = RunService.Heartbeat:Connect(function(dt)
		if not root.Parent then return end                         -- monster destroyed

		-- Animate every frame (even when frozen, so limbs relax to rest pose)
		animate(dt)

		if monsterPaused then freeze() return end                  -- between rounds

		-- Catch detection
		local closestRoot, closestPlayer = getClosestPlayerRoot(root)
		if closestRoot and closestPlayer then
			local d = (closestRoot.Position - root.Position).Magnitude
			if d < catchRadius then
				if _G.GameAPI and _G.GameAPI.notifyCaught then
					_G.GameAPI.notifyCaught(closestPlayer)
				end
				return  -- skip the rest this frame; round manager will pause us
			end
		end

		-- Watching gate
		if anyoneWatching() then
			freeze()
			return
		end
		unfreeze()

		-- Periodically recompute path to the closest player.
		-- Tighter interval = monster reacts to player dodges much faster.
		local now = os.clock()
		if closestRoot and (now - lastPathTime > 0.65) then
			lastPathTime = now
			recomputePath(closestRoot.Position)
		end

		-- Walk toward the next waypoint
		if #currentWaypoints > 0 and currentWaypointIndex <= #currentWaypoints then
			local wp = currentWaypoints[currentWaypointIndex]
			humanoid:MoveTo(wp.Position)
			-- Advance when close enough
			if (root.Position - wp.Position).Magnitude < 4 then
				currentWaypointIndex += 1
			end
		elseif closestRoot then
			-- Fallback: walk straight at the player if we have no path
			humanoid:MoveTo(closestRoot.Position)
		end
	end)
end

-- Public API for the round manager
_G.GameAPI = _G.GameAPI or {}

function _G.GameAPI.respawnMonster()
	spawnMonster()
end

function _G.GameAPI.despawnMonster()
	despawnMonster()
end

function _G.GameAPI.setMonsterPaused(paused: boolean)
	monsterPaused = paused
end

-- The monster is no longer auto-spawned at boot. RoundManager calls
-- _G.GameAPI.respawnMonster() when a player clicks PLAY in the title screen.
