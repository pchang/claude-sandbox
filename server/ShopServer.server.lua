-- ShopServer.server.lua (Script, server only)
--
-- Spawns a small wooden shop counter near the player spawn area. Players
-- press E on the counter to open the shop UI (handled client-side); when
-- they click a Buy button, the client fires the ShopBuy remote and we
-- validate / grant here.
--
-- Items:
--   * Boots       (100c)  → +6 WalkSpeed, persists across deaths
--   * PowerJuice  (500c)  → consumed on next monster catch (knock back instead)
--   * Gun         (1000c) → adds a Tool to Backpack; click to stun monster 45s
--                            with a 120s cooldown
--
-- Coin balance and item ownership live in PickupSpawner's inventory state,
-- accessed via _G.GameAPI (spendCoins, setItemOwned, hasItem, etc.).

local Workspace        = game:GetService("Workspace")
local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared      = ReplicatedStorage:WaitForChild("Shared")
local GameConfig  = require(Shared:WaitForChild("GameConfig"))
local Remotes     = require(Shared:WaitForChild("Remotes"))

local shopOpenRemote      = Remotes.get(Remotes.Names.ShopOpen)
local shopBuyRemote       = Remotes.get(Remotes.Names.ShopBuy)
local shopBuyResultRemote = Remotes.get(Remotes.Names.ShopBuyResult)
local gunFireResultRemote = Remotes.get(Remotes.Names.GunFireResult)

local ITEMS = {
	Boots      = { cost = GameConfig.BootsCost,      name = "Running Boots" },
	PowerJuice = { cost = GameConfig.PowerJuiceCost, name = "Power Juice"   },
	Gun        = { cost = GameConfig.GunCost,        name = "Glock"         },
}

-- (Shop is now opened from a button on the title screen — no in-world counter.)
-- We make sure no leftover shop model remains from older builds.
local existing = Workspace:FindFirstChild("Shop")
if existing then existing:Destroy() end

-- ===== Buy handler =====

shopBuyRemote.OnServerEvent:Connect(function(player, item)
	if typeof(item) ~= "string" then return end
	local cfg = ITEMS[item]
	if not cfg then
		shopBuyResultRemote:FireClient(player, { ok = false, reason = "unknown_item", item = item })
		return
	end

	-- Already owned?
	if _G.GameAPI.hasItem and _G.GameAPI.hasItem(player, item) then
		shopBuyResultRemote:FireClient(player, { ok = false, reason = "already_owned", item = item })
		return
	end

	-- Affordable?
	if not (_G.GameAPI.spendCoins and _G.GameAPI.spendCoins(player, cfg.cost)) then
		shopBuyResultRemote:FireClient(player, { ok = false, reason = "insufficient_coins", item = item })
		return
	end

	-- Grant ownership and apply effects
	_G.GameAPI.setItemOwned(player, item, true)

	if item == "Boots" then
		applyEffects(player)  -- defined below; updates WalkSpeed
	elseif item == "Gun" then
		giveGun(player)       -- defined below; adds Tool
	end
	-- PowerJuice is purely passive: just sets inv.hasPowerJuice = true

	shopBuyResultRemote:FireClient(player, { ok = true, item = item })
	print(string.format("[Shop] %s bought %s for %d coins", player.Name, cfg.name, cfg.cost))
end)

-- ===== Boots: speed bonus, persists across respawns =====

function applyEffects(player: Player)
	local character = player.Character
	if not character then return end
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	local hasBoots = _G.GameAPI.hasItem and _G.GameAPI.hasItem(player, "Boots")
	hum.WalkSpeed = GameConfig.WalkSpeed + (hasBoots and GameConfig.BootsSpeedBonus or 0)
end

-- Re-apply boots speed every time a player's character spawns
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		task.wait(0.4)  -- let other CharacterAdded handlers run first
		applyEffects(player)
		-- Re-give the gun on respawn if owned
		if _G.GameAPI.hasItem and _G.GameAPI.hasItem(player, "Gun") then
			giveGun(player)
		end
	end)
end)
-- Also handle players who joined before this script's connection went up
for _, p in ipairs(Players:GetPlayers()) do
	if p.Character then
		applyEffects(p)
	end
end

-- ===== Gun Tool =====

-- Per-player cooldown timestamps (os.clock). Survives respawns; reset on leave.
local gunCooldowns: { [Player]: number } = {}
Players.PlayerRemoving:Connect(function(p) gunCooldowns[p] = nil end)

function giveGun(player: Player)
	-- Don't double-give if a gun is already in their backpack or character
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then return end
	if backpack:FindFirstChild("Glock") then return end
	local character = player.Character
	if character and character:FindFirstChild("Glock") then return end

	local tool = Instance.new("Tool")
	tool.Name = "Glock"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ToolTip = "Stun the monster (45s · 2min cooldown)"

	-- Build the gun handle: a small black part shaped roughly like a Glock
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1.6, 1.0, 0.5)
	handle.Material = Enum.Material.SmoothPlastic
	handle.Color = Color3.fromRGB(15, 15, 15)
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	-- Stylize: add a slim slide on top to give silhouette
	local slide = Instance.new("Part")
	slide.Name = "Slide"
	slide.Size = Vector3.new(1.6, 0.4, 0.45)
	slide.Material = Enum.Material.SmoothPlastic
	slide.Color = Color3.fromRGB(25, 25, 25)
	slide.CanCollide = false
	slide.Massless = true
	slide.Parent = tool
	local slideWeld = Instance.new("WeldConstraint")
	slideWeld.Part0 = handle
	slideWeld.Part1 = slide
	slideWeld.Parent = handle
	slide.CFrame = handle.CFrame * CFrame.new(0, 0.7, 0)

	-- Grip below the slide
	local grip = Instance.new("Part")
	grip.Name = "Grip"
	grip.Size = Vector3.new(0.5, 1.1, 0.5)
	grip.Material = Enum.Material.SmoothPlastic
	grip.Color = Color3.fromRGB(15, 15, 15)
	grip.CanCollide = false
	grip.Massless = true
	grip.Parent = tool
	local gripWeld = Instance.new("WeldConstraint")
	gripWeld.Part0 = handle
	gripWeld.Part1 = grip
	gripWeld.Parent = handle
	grip.CFrame = handle.CFrame * CFrame.new(-0.5, -1.0, 0)

	-- Activation: stun the monster
	tool.Activated:Connect(function()
		local now = os.clock()
		local nextOk = gunCooldowns[player] or 0
		if now < nextOk then
			-- On cooldown — flash the result so the client can show feedback
			gunFireResultRemote:FireClient(player, { ok = false, reason = "cooldown", remaining = nextOk - now })
			return
		end
		gunCooldowns[player] = now + GameConfig.GunCooldown

		print(string.format("[Gun] %s fired the gun — stunning monster for %ds", player.Name, GameConfig.GunStunDuration))

		-- Stun the monster: pause for the configured duration, then resume.
		if _G.GameAPI.setMonsterPaused then
			_G.GameAPI.setMonsterPaused(true)
			task.delay(GameConfig.GunStunDuration, function()
				-- Only un-pause if we're still in PLAYING (don't override
				-- a round-end-induced pause).
				if _G.GameAPI.setMonsterPaused then
					_G.GameAPI.setMonsterPaused(false)
				end
			end)
		end

		gunFireResultRemote:FireAllClients({
			ok = true,
			shooterName = player.Name,
			stunSeconds = GameConfig.GunStunDuration,
			cooldownSeconds = GameConfig.GunCooldown,
		})
	end)

	tool.Parent = backpack
	print(string.format("[Shop] Gun added to %s's backpack", player.Name))
end
