-- Remotes.lua (ModuleScript)
-- Centralized RemoteEvent / RemoteFunction registry.
--
-- Server: require this and call Remotes.get(name) to fetch (creates if missing).
-- Client: require this and call Remotes.wait(name) to fetch (waits until server creates).
--
-- We do this in a module so naming is consistent between server and client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

-- Single folder under ReplicatedStorage that holds every RemoteEvent/Function
local FOLDER_NAME = "GameRemotes"

-- All known remote event names. Add new ones here as features are added.
Remotes.Names = {
	InventoryChanged   = "InventoryChanged",   -- Server -> Client : new inventory state (table)
	PickupCollected    = "PickupCollected",    -- Server -> Client : feedback ("you got a wheel")
	WheelAttached      = "WheelAttached",      -- Server -> All Clients : wheel slot N is now filled
	FlashlightToggle   = "FlashlightToggle",   -- (deprecated; flashlight removed)
	FlashlightState    = "FlashlightState",    -- (deprecated; flashlight removed)
	MonsterVisibility  = "MonsterVisibility",  -- Client -> Server : "I can/can't see the monster"
	GameStateChanged   = "GameStateChanged",   -- Server -> All Clients : round state ("lobby","playing","won","lost","restart")
	PlayerReady        = "PlayerReady",        -- Client -> Server : "I clicked PLAY"
	-- Shop
	ShopOpen           = "ShopOpen",           -- Server -> Client : "open the shop UI for this player"
	ShopBuy            = "ShopBuy",            -- Client -> Server : "buy item X"
	ShopBuyResult      = "ShopBuyResult",      -- Server -> Client : { ok, reason, item }
	-- Gun
	GunFireResult      = "GunFireResult",      -- Server -> All Clients : monster stunned by player X
	-- Jumpscare
	MonsterJumpscare   = "MonsterJumpscare",   -- Server -> Client : "the monster got you — play the jumpscare"
}

local function getOrCreateFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if folder then return folder end

	if RunService:IsServer() then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
		return folder
	else
		-- Client: wait for server to create it
		return ReplicatedStorage:WaitForChild(FOLDER_NAME, 30)
	end
end

--- Server-side: get or create a RemoteEvent by name.
function Remotes.get(name: string): RemoteEvent
	assert(RunService:IsServer(), "Remotes.get is server-only. Use Remotes.wait on the client.")
	local folder = getOrCreateFolder()
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing :: RemoteEvent
	end
	local re = Instance.new("RemoteEvent")
	re.Name = name
	re.Parent = folder
	return re
end

--- Client-side: wait for a RemoteEvent the server has created.
function Remotes.wait(name: string, timeout: number?): RemoteEvent
	local folder = getOrCreateFolder()
	local re = folder:WaitForChild(name, timeout or 30)
	assert(re and re:IsA("RemoteEvent"), "Remote not found: " .. name)
	return re :: RemoteEvent
end

--- Server: pre-create every named remote at startup so clients never race.
function Remotes.initAll()
	assert(RunService:IsServer(), "initAll is server-only.")
	for _, name in pairs(Remotes.Names) do
		Remotes.get(name)
	end
end

return Remotes
