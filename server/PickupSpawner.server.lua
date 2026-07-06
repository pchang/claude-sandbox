-- PickupSpawner.server.lua (Script, server only)
--
-- Scatters 4 wheel pickups around the forest at random positions far enough
-- from the car spawn, plus 1 hidden flashlight far away. Each pickup has a
-- ProximityPrompt so the player presses E to grab it.
--
-- Maintains the per-player inventory on the server (authoritative — never
-- trust a client to claim it has a wheel) and exposes a small API via
-- _G.GameAPI so other server scripts (CarSetup, GameUI) can interact with it.
--
-- Inventory replication: whenever a player's inventory changes we fire the
-- InventoryChanged RemoteEvent to that player so the HUD can update.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

-- Persistent player stats via DataStore (Studio testing requires
-- "Enable Studio Access to API Services" in Game Settings → Security).
-- Stores { coins = N, lifetimeWheels = M } per player.
local statsStore       = DataStoreService:GetDataStore("PlayerStats_v4")
-- OrderedDataStore for the Platinum top-20 leaderboard (sorted by lifetimeWheels)
local wheelsLeaderboard = DataStoreService:GetOrderedDataStore("WheelsLeaderboard_v1")

local function statsKey(player: Player): string
	return "player_" .. tostring(player.UserId)
end

type Stats = { coins: number, lifetimeWheels: number }

local function loadStats(player: Player): Stats
	local ok, value = pcall(function()
		return statsStore:GetAsync(statsKey(player))
	end)
	if ok and typeof(value) == "table" then
		return {
			coins = typeof(value.coins) == "number" and value.coins or GameConfig.StartingCoins,
			lifetimeWheels = typeof(value.lifetimeWheels) == "number" and value.lifetimeWheels or 0,
		}
	end
	if not ok then
		warn("[Pickups] Failed to load stats for " .. player.Name .. ": " .. tostring(value))
	end
	-- No record: start fresh
	return { coins = GameConfig.StartingCoins, lifetimeWheels = 0 }
end

local function saveStats(player: Player, stats: Stats)
	-- Save main stats blob
	local ok, err = pcall(function()
		statsStore:SetAsync(statsKey(player), { coins = stats.coins, lifetimeWheels = stats.lifetimeWheels })
	end)
	if not ok then
		warn("[Pickups] Failed to save stats for " .. player.Name .. ": " .. tostring(err))
	end
	-- Mirror lifetimeWheels into the leaderboard (OrderedDataStore needs integer values)
	local ok2, err2 = pcall(function()
		wheelsLeaderboard:SetAsync(tostring(player.UserId), stats.lifetimeWheels)
	end)
	if not ok2 then
		warn("[Pickups] Failed to update leaderboard for " .. player.Name .. ": " .. tostring(err2))
	end
end

-- ===== Platinum top-20 cache =====
-- Set of UserIds currently in the top 20 lifetimeWheels. Refreshed every minute.
local platinumUserIds: { [number]: boolean } = {}

local function refreshPlatinumList()
	local ok, pages = pcall(function()
		-- false = descending; 20 = top N
		return wheelsLeaderboard:GetSortedAsync(false, 20)
	end)
	if not ok then
		warn("[Pickups] Failed to load Platinum leaderboard: " .. tostring(pages))
		return
	end
	local newSet: { [number]: boolean } = {}
	local entries = pages:GetCurrentPage()
	for _, entry in ipairs(entries) do
		local userId = tonumber(entry.key)
		-- entry.value is the lifetimeWheels count; only count Gold-eligible players
		if userId and typeof(entry.value) == "number" and entry.value >= 201 then
			newSet[userId] = true
		end
	end
	platinumUserIds = newSet
end

-- Initial load + periodic refresh
task.spawn(function()
	refreshPlatinumList()
	while true do
		task.wait(60)
		refreshPlatinumList()
	end
end)

local Shared       = ReplicatedStorage:WaitForChild("Shared")
local GameConfig   = require(Shared:WaitForChild("GameConfig"))
local Remotes      = require(Shared:WaitForChild("Remotes"))

local inventoryRemote        = Remotes.get(Remotes.Names.InventoryChanged)
local pickupCollectedRemote  = Remotes.get(Remotes.Names.PickupCollected)

-- Per-player inventory. Reset when player leaves so it doesn't grow forever.
-- Coins + lifetimeWheels persist across rounds & sessions; wheels-in-hand resets each round.
type Inventory = {
	wheels: number,
	coins: number,
	hasBoots: boolean,
	hasPowerJuice: boolean,
	hasGun: boolean,
	lifetimeWheels: number,   -- total wheels ever attached to a car by this player
}
local inventories: { [Player]: Inventory } = {}

local function newInventory(): Inventory
	return {
		wheels = 0,
		coins = GameConfig.StartingCoins,
		hasBoots = false,
		hasPowerJuice = false,
		hasGun = false,
		lifetimeWheels = 0,
	}
end

local function getInventory(player: Player): Inventory
	local inv = inventories[player]
	if not inv then
		inv = newInventory()
		inventories[player] = inv
	end
	return inv
end

-- Compute the player's rank based on their lifetimeWheels and the Platinum cache.
--   0 - 100:    Bronze
--   101 - 200:  Silver
--   201+ AND in top 20: Platinum
--   201+:       Gold
local function computeRank(player: Player): string
	local inv = getInventory(player)
	local w = inv.lifetimeWheels or 0
	if w <= 100 then return "Bronze"
	elseif w <= 200 then return "Silver"
	elseif platinumUserIds[player.UserId] then return "Platinum"
	else return "Gold" end
end

local function pushInventory(player: Player)
	local inv = getInventory(player)
	-- Send the full state table plus the computed rank
	inventoryRemote:FireClient(player, {
		wheels         = inv.wheels,
		coins          = inv.coins,
		hasBoots       = inv.hasBoots,
		hasPowerJuice  = inv.hasPowerJuice,
		hasGun         = inv.hasGun,
		lifetimeWheels = inv.lifetimeWheels,
		rank           = computeRank(player),
	})
end

Players.PlayerAdded:Connect(function(player)
	-- Load saved stats from the DataStore (background, doesn't block join).
	task.spawn(function()
		local saved = loadStats(player)
		local inv = getInventory(player)
		inv.coins = saved.coins
		inv.lifetimeWheels = saved.lifetimeWheels
		pushInventory(player)
		print(string.format("[Pickups] Loaded stats for %s: %d coins, %d lifetimeWheels (rank %s)",
			player.Name, saved.coins, saved.lifetimeWheels, computeRank(player)))
	end)

	-- Push on character spawn too, in case the client UI loads later
	player.CharacterAdded:Connect(function()
		task.wait(0.5)  -- let the client UI script connect first
		pushInventory(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	-- Save stats before dropping inventory so progress isn't lost.
	local inv = inventories[player]
	if inv then
		saveStats(player, { coins = inv.coins, lifetimeWheels = inv.lifetimeWheels })
		print(string.format("[Pickups] Saved stats for %s on leave: %d coins, %d lifetimeWheels",
			player.Name, inv.coins, inv.lifetimeWheels))
	end
	inventories[player] = nil
end)

-- Save every online player's stats on server shutdown.
game:BindToClose(function()
	if RunService:IsStudio() then
		-- Studio's BindToClose can be flaky; just save synchronously
		for player, inv in pairs(inventories) do
			saveStats(player, { coins = inv.coins, lifetimeWheels = inv.lifetimeWheels })
		end
		return
	end
	local pending = 0
	for player, inv in pairs(inventories) do
		pending += 1
		task.spawn(function()
			saveStats(player, { coins = inv.coins, lifetimeWheels = inv.lifetimeWheels })
			pending -= 1
		end)
	end
	local started = os.clock()
	while pending > 0 and os.clock() - started < 25 do
		task.wait(0.1)
	end
end)

-- The wheel for cave i goes at the center of cave i, just above ground.
-- Caves are at fixed positions in GameConfig.CavePositions.
local function caveWheelPosition(caveIndex: number): Vector3
	local cavePos = GameConfig.CavePositions[caveIndex]
	return Vector3.new(cavePos.X, 2.5, cavePos.Z)
end

local function buildWheelPickup(index: number, parent: Folder): Part
	local wheel = Instance.new("Part")
	wheel.Name = "WheelPickup" .. index
	wheel.Shape = Enum.PartType.Cylinder
	wheel.Size = Vector3.new(1.2, 4, 4)
	wheel.Position = caveWheelPosition(index)
	wheel.CFrame = CFrame.new(wheel.Position) * CFrame.Angles(0, 0, math.rad(90))
	wheel.Anchored = true
	wheel.Material = Enum.Material.Rubber
	wheel.Color = Color3.fromRGB(25, 25, 25)
	wheel.Parent = parent

	-- Subtle glow so they're not impossible to spot in the fog
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(180, 200, 255)
	glow.Brightness = 0.5
	glow.Range = 8
	glow.Parent = wheel

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick up wheel"
	prompt.ObjectText = "Tire"
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = GameConfig.WheelPickupRadius
	prompt.Parent = wheel

	prompt.Triggered:Connect(function(player)
		local inv = getInventory(player)
		-- We allow players to carry multiple wheels (so one player can fix the car)
		inv.wheels += 1
		wheel:Destroy()
		pushInventory(player)
		pickupCollectedRemote:FireClient(player, "wheel")
		print(string.format("[Pickups] %s picked up a wheel (now has %d)", player.Name, inv.wheels))
	end)

	return wheel
end

-- (Flashlight is granted at spawn — no world pickup is created.)

-- Track wheels attached to the car (for win-condition detection)
local wheelsAttached = 0

-- Public API for other server scripts.
_G.GameAPI = _G.GameAPI or {}

--- Atomically take 1 wheel from a player's inventory. Returns true on success.
function _G.GameAPI.takeWheelFromInventory(player: Player): boolean
	local inv = inventories[player]
	if not inv or inv.wheels < 1 then return false end
	inv.wheels -= 1
	pushInventory(player)
	return true
end

--- Read-only: get a player's current inventory snapshot.
function _G.GameAPI.getInventory(player: Player): Inventory
	return getInventory(player)
end

--- Notify that a wheel was attached to the car (called by CarSetup).
function _G.GameAPI.notifyWheelAttached(slotIndex: number, attachedBy: Player?)
	wheelsAttached += 1
	-- Reward the attacher with coins + bump their lifetime counter (drives rank)
	if attachedBy then
		local inv = getInventory(attachedBy)
		inv.coins += GameConfig.CoinsPerWheelAttached
		inv.lifetimeWheels += 1

		-- Update the leaderboard so Platinum membership can recompute next refresh
		task.spawn(function()
			local ok, err = pcall(function()
				wheelsLeaderboard:SetAsync(tostring(attachedBy.UserId), inv.lifetimeWheels)
			end)
			if not ok then
				warn("[Pickups] Leaderboard update failed: " .. tostring(err))
			end
		end)

		pushInventory(attachedBy)
		print(string.format("[Pickups] +%d coins to %s (now %d), lifetimeWheels %d",
			GameConfig.CoinsPerWheelAttached, attachedBy.Name, inv.coins, inv.lifetimeWheels))
	end
	print(string.format("[Pickups] %d / %d wheels now on the car", wheelsAttached, GameConfig.WheelCount))
	if wheelsAttached >= GameConfig.WheelCount then
		print("[Pickups] All wheels attached!")
		if _G.GameAPI.notifyAllWheelsAttached then
			_G.GameAPI.notifyAllWheelsAttached(attachedBy)
		end
	end
end

--- Read-only: how many wheels are on the car.
function _G.GameAPI.getWheelsAttached(): number
	return wheelsAttached
end

--- Reset the wheels-attached counter (called by RoundManager on restart).
function _G.GameAPI.resetWheelsAttached()
	wheelsAttached = 0
end

--- Reset every player's inventory between rounds.
--- Wheels go back to 0; COINS and PURCHASED ITEMS persist (so the shop works).
function _G.GameAPI.resetAllInventories()
	for player, inv in pairs(inventories) do
		inv.wheels = 0
		-- coins, hasBoots, hasPowerJuice, hasGun all persist
		pushInventory(player)
	end
end

--- Add coins (used by future systems if any, plus admin).
function _G.GameAPI.addCoins(player: Player, amount: number)
	local inv = getInventory(player)
	inv.coins += amount
	pushInventory(player)
end

--- Atomically spend coins. Returns true on success, false if insufficient.
function _G.GameAPI.spendCoins(player: Player, amount: number): boolean
	local inv = getInventory(player)
	if inv.coins < amount then return false end
	inv.coins -= amount
	pushInventory(player)
	return true
end

--- Set ownership of a shop item. Item names: "Boots", "PowerJuice", "Gun".
function _G.GameAPI.setItemOwned(player: Player, item: string, owned: boolean)
	local inv = getInventory(player)
	if item == "Boots" then       inv.hasBoots = owned
	elseif item == "PowerJuice" then inv.hasPowerJuice = owned
	elseif item == "Gun" then      inv.hasGun = owned
	else return end
	pushInventory(player)
end

--- Read whether a player owns an item.
function _G.GameAPI.hasItem(player: Player, item: string): boolean
	local inv = getInventory(player)
	if item == "Boots" then       return inv.hasBoots
	elseif item == "PowerJuice" then return inv.hasPowerJuice
	elseif item == "Gun" then      return inv.hasGun
	end
	return false
end

--- Consume the player's PowerJuice if they have it. Returns true if consumed.
function _G.GameAPI.consumePowerJuice(player: Player): boolean
	local inv = getInventory(player)
	if not inv.hasPowerJuice then return false end
	inv.hasPowerJuice = false
	pushInventory(player)
	return true
end

--- Re-spawn the wheel pickups in the world (called by RoundManager on restart).
function _G.GameAPI.respawnPickups()
	-- Hold a forward reference; defined below
end

local function spawnAll()
	local existing = Workspace:FindFirstChild("Pickups")
	if existing then existing:Destroy() end

	local folder = Instance.new("Folder")
	folder.Name = "Pickups"
	folder.Parent = Workspace

	for i = 1, GameConfig.WheelCount do
		local wheel = buildWheelPickup(i, folder)
		print(string.format("[Pickups] Wheel %d spawned at %s", i, tostring(wheel.Position)))
	end
end

-- Now that spawnAll exists, wire it as the public respawn API.
function _G.GameAPI.respawnPickups()
	spawnAll()
end

spawnAll()
