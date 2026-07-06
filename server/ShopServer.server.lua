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

local ITEMS = {
	Boots      = { cost = GameConfig.BootsCost,      name = "Running Boots" },
	PowerJuice = { cost = GameConfig.PowerJuiceCost, name = "Power Juice"   },
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
	end)
end)
-- Also handle players who joined before this script's connection went up
for _, p in ipairs(Players:GetPlayers()) do
	if p.Character then
		applyEffects(p)
	end
end

