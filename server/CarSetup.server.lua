-- CarSetup.server.lua (Script, server only)
--
-- Builds the broken-down car the players must fix to escape:
--   * Rusty body sitting in the central clearing
--   * 4 visible "wheel slot" attachment points (axle stubs)
--   * Each slot has a ProximityPrompt that, when triggered by a player
--     who has a wheel in their inventory, attaches the wheel.
--
-- The actual "do they have a wheel?" check + inventory mutation happens
-- inside PickupSpawner via a server-side state table accessed via _G.GameAPI.
-- (We use _G as a simple shared service registry between server scripts.)

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared       = ReplicatedStorage:WaitForChild("Shared")
local GameConfig   = require(Shared:WaitForChild("GameConfig"))
local Remotes      = require(Shared:WaitForChild("Remotes"))

local wheelAttachedRemote = Remotes.get(Remotes.Names.WheelAttached)

-- Wait until the inventory API is published by PickupSpawner
local function waitForInventoryAPI(timeout: number?)
	local start = os.clock()
	while not (_G.GameAPI and _G.GameAPI.takeWheelFromInventory) do
		if os.clock() - start > (timeout or 10) then
			warn("[CarSetup] GameAPI never appeared; wheel slots will not function")
			return nil
		end
		task.wait(0.1)
	end
	return _G.GameAPI
end

local function buildCarBody(): Model
	local model = Instance.new("Model")
	model.Name = "BrokenCar"

	-- Body: a stretched dark-red box, sitting low because no wheels
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(14, 4, 6)
	body.Anchored = true
	body.Material = Enum.Material.Metal
	body.Color = Color3.fromRGB(85, 25, 25)   -- rusty red
	body.CFrame = CFrame.new(GameConfig.CarPosition)
	body.Parent = model

	-- Cabin / roof
	local cabin = Instance.new("Part")
	cabin.Name = "Cabin"
	cabin.Size = Vector3.new(7, 3, 5.5)
	cabin.Anchored = true
	cabin.Material = Enum.Material.Metal
	cabin.Color = Color3.fromRGB(70, 20, 20)
	cabin.CFrame = CFrame.new(GameConfig.CarPosition + Vector3.new(-1, 3.5, 0))
	cabin.Parent = model

	-- Windshield
	local windshield = Instance.new("Part")
	windshield.Name = "Windshield"
	windshield.Size = Vector3.new(0.3, 2.5, 5)
	windshield.Anchored = true
	windshield.Material = Enum.Material.Glass
	windshield.Color = Color3.fromRGB(30, 30, 35)
	windshield.Transparency = 0.4
	windshield.CFrame = CFrame.new(GameConfig.CarPosition + Vector3.new(2.6, 3.4, 0))
	windshield.Parent = model

	model.PrimaryPart = body
	return model
end

local function buildWheelSlot(slotIndex: number, parentModel: Model): Part
	local slotOffset = GameConfig.WheelSlotOffsets[slotIndex]
	local worldPos = GameConfig.CarPosition + slotOffset

	-- Visible "axle stub" sticking out sideways from the car body.
	-- Cylinder's long axis is X by default; rotate around Y to point along Z.
	local stub = Instance.new("Part")
	stub.Name = "WheelSlot" .. slotIndex
	stub.Shape = Enum.PartType.Cylinder
	stub.Size = Vector3.new(2, 1.4, 1.4)  -- length × diameter × diameter
	stub.CFrame = CFrame.new(worldPos) * CFrame.Angles(0, math.rad(90), 0)
	stub.Anchored = true
	stub.Material = Enum.Material.Metal
	stub.Color = Color3.fromRGB(60, 60, 60)
	stub.Parent = parentModel

	-- Set up a ProximityPrompt for "Attach Wheel"
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "AttachPrompt"
	prompt.ActionText = "Attach Wheel"
	prompt.ObjectText = "Wheel Slot " .. slotIndex
	prompt.HoldDuration = 1.0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = stub

	-- Attribute lets us mark the slot filled without searching the model later
	stub:SetAttribute("Filled", false)

	prompt.Triggered:Connect(function(player)
		if stub:GetAttribute("Filled") then return end

		local api = _G.GameAPI
		if not (api and api.takeWheelFromInventory) then
			warn("[CarSetup] No inventory API; cannot attach wheel")
			return
		end

		local consumed = api.takeWheelFromInventory(player)
		if not consumed then
			-- Player doesn't have a wheel; ignore silently (UI handles feedback)
			return
		end

		-- Spawn an actual wheel mesh at this slot. Wheel axle (long axis X)
		-- needs to point along Z (sideways from car), so rotate around Y.
		local wheel = Instance.new("Part")
		wheel.Name = "Wheel" .. slotIndex
		wheel.Shape = Enum.PartType.Cylinder
		wheel.Size = Vector3.new(1.2, 4, 4)
		wheel.CFrame = CFrame.new(worldPos) * CFrame.Angles(0, math.rad(90), 0)
		wheel.Anchored = true
		wheel.Material = Enum.Material.Rubber
		wheel.Color = Color3.fromRGB(20, 20, 20)
		wheel.Parent = parentModel

		stub:SetAttribute("Filled", true)
		prompt.Enabled = false  -- can't re-attach

		print(string.format("[CarSetup] %s attached wheel to slot %d", player.Name, slotIndex))
		wheelAttachedRemote:FireAllClients(slotIndex, player.Name)

		-- Notify any system watching for "all 4 wheels attached".
		-- Pass the player so the round manager can credit them with the escape.
		if api.notifyWheelAttached then
			api.notifyWheelAttached(slotIndex, player)
		end
	end)

	return stub
end

-- Track the active car so we can rebuild on round restart
local activeCar: Model? = nil

local function build()
	-- Clean up any previous car
	local existing = Workspace:FindFirstChild("BrokenCar")
	if existing then existing:Destroy() end

	print("[CarSetup] Building broken car...")
	local car = buildCarBody()
	car.Parent = Workspace
	activeCar = car

	for i = 1, GameConfig.WheelCount do
		buildWheelSlot(i, car)
	end

	-- Wait for the inventory API in the background; doesn't block the slot creation
	task.spawn(function()
		waitForInventoryAPI(15)
		print("[CarSetup] Inventory API ready, wheel slots are functional")
	end)

	print("[CarSetup] Car ready with", GameConfig.WheelCount, "empty wheel slots")
end

build()

-- Public API
_G.GameAPI = _G.GameAPI or {}

function _G.GameAPI.rebuildCar()
	build()
end

function _G.GameAPI.getCar(): Model?
	return activeCar
end

--- All 4 wheels are on. Auto-trigger the escape sequence — no engine prompt.
--- Credit goes to the player who attached the final wheel.
function _G.GameAPI.notifyAllWheelsAttached(attachedBy: Player?)
	print("[CarSetup] All wheels attached — triggering automatic escape")
	if _G.GameAPI.startEscape then
		_G.GameAPI.startEscape(attachedBy)
	else
		warn("[CarSetup] No startEscape API; round manager not loaded")
	end
end
