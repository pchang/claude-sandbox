-- MonsterVision.client.lua (LocalScript)
--
-- Watches for the monster and reports to the server whether the local player
-- can currently see it. The server uses this to freeze the monster when
-- ANY player is looking at it (the weeping-angel mechanic).
--
-- Detection rules:
--   * Distance must be inside the fog (otherwise it's not visible anyway)
--   * Monster must be inside the camera's view cone (dot-product check)
--   * Line of sight must be clear (raycast — trees, rocks block the view)

local Workspace        = game:GetService("Workspace")
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared      = ReplicatedStorage:WaitForChild("Shared")
local GameConfig  = require(Shared:WaitForChild("GameConfig"))
local Remotes     = require(Shared:WaitForChild("Remotes"))

local visibilityRemote = Remotes.wait(Remotes.Names.MonsterVisibility)

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- Cosine of half-FOV used as the "in view" threshold.
-- Roblox default FOV is 70°, so half is 35° (cos ≈ 0.819).
-- We use 0.85 (cos ~32°) so ONLY a direct stare freezes the monster.
-- Peripheral glances no longer count → the player has to truly track it.
local IN_VIEW_DOT = 0.85

local REPORT_INTERVAL = 0.15  -- send updates ~7x/second
local lastReportTime = 0
local lastReportedVisible: boolean? = nil  -- nil so the first real value always sends

local function findMonsterRoot(): BasePart?
	local monster = Workspace:FindFirstChild("Monster")
	if not monster then return nil end
	local root = monster:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then return root end
	return nil
end

local function isVisible(monsterRoot: BasePart): boolean
	if not camera then return false end
	local origin = camera.CFrame.Position
	local toMonster = monsterRoot.Position - origin
	local distance = toMonster.Magnitude
	if distance < 1 then return true end                       -- right on top of us
	if distance > GameConfig.FogEnd then return false end      -- swallowed by fog

	local direction = toMonster.Unit
	if camera.CFrame.LookVector:Dot(direction) < IN_VIEW_DOT then
		return false
	end

	-- Occlusion check: shoot a ray from camera to monster, ignore our own char
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignoreList: { Instance } = {}
	if player.Character then table.insert(ignoreList, player.Character) end
	params.FilterDescendantsInstances = ignoreList

	local hit = Workspace:Raycast(origin, direction * (distance + 2), params)
	if not hit then
		-- No hit at all — usually means we're looking past it; treat as not visible
		return false
	end
	-- Visible only if the first thing the ray touched is the monster itself
	return hit.Instance:IsDescendantOf(monsterRoot.Parent :: Instance)
end

local function reportIfChanged(visible: boolean)
	if visible == lastReportedVisible then return end
	lastReportedVisible = visible
	visibilityRemote:FireServer(visible)
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now - lastReportTime < REPORT_INTERVAL then return end
	lastReportTime = now

	-- Camera can be replaced (e.g. on respawn); refresh ref
	camera = Workspace.CurrentCamera

	local root = findMonsterRoot()
	if not root then
		reportIfChanged(false)  -- no monster = not visible
		return
	end
	reportIfChanged(isVisible(root))
end)
