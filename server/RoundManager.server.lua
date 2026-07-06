-- RoundManager.server.lua (Script, server only)
--
-- The round state machine. Owns transitions between "playing", "lost",
-- and "won", and is the single place that orchestrates round restarts.
--
-- Other server scripts call into the API:
--   * Monster      -> _G.GameAPI.notifyCaught(player)
--   * CarSetup     -> _G.GameAPI.startEscape(player)   (when 4 wheels attached + E)
--   * (Internal)   -> handles the drive-away tween + win detection
--
-- The state is broadcast to clients via the GameStateChanged RemoteEvent
-- so the HUD can show a game-over / victory overlay.

local Players          = game:GetService("Players")
local Workspace        = game:GetService("Workspace")
local TweenService     = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared      = ReplicatedStorage:WaitForChild("Shared")
local GameConfig  = require(Shared:WaitForChild("GameConfig"))
local Remotes     = require(Shared:WaitForChild("Remotes"))

local stateRemote = Remotes.get(Remotes.Names.GameStateChanged)
local readyRemote = Remotes.get(Remotes.Names.PlayerReady)
local jumpscareRemote = Remotes.get(Remotes.Names.MonsterJumpscare)

local STATE = {
	LOBBY   = "lobby",    -- title screen showing; monster is despawned
	PLAYING = "playing",  -- round in progress
	LOST    = "lost",     -- monster caught a player
	WON     = "won",      -- car drove away
	RESTART = "restart",  -- transient: cleaning up before going back to LOBBY
}

local currentState = STATE.LOBBY
local currentRoundId = 1   -- bumps every restart so stale callbacks bail out

local function broadcast(state: string, detail: { [string]: any }?)
	stateRemote:FireAllClients(state, detail or {})
end

-- Push the current state to a single player. Used when someone joins mid-game.
local function pushStateTo(player: Player)
	stateRemote:FireClient(player, currentState, {})
end

Players.PlayerAdded:Connect(function(player)
	-- Wait briefly for the client UI to subscribe before pushing
	task.wait(1)
	pushStateTo(player)
end)

-- ===== Restart flow =====

-- Helper: kill+respawn every player so they re-enter at the SpawnLocation
local function respawnAllPlayers()
	for _, p in ipairs(Players:GetPlayers()) do
		-- LoadCharacter triggers the standard respawn path
		pcall(function() p:LoadCharacter() end)
	end
end

local function teardownToLobby()
	-- Tear everything down, then sit in LOBBY waiting for someone to press PLAY.
	if _G.GameAPI.despawnMonster      then _G.GameAPI.despawnMonster() end
	if _G.GameAPI.resetWheelsAttached then _G.GameAPI.resetWheelsAttached() end
	if _G.GameAPI.resetAllInventories then _G.GameAPI.resetAllInventories() end
	if _G.GameAPI.respawnPickups      then _G.GameAPI.respawnPickups() end
	if _G.GameAPI.rebuildCar          then _G.GameAPI.rebuildCar() end

	respawnAllPlayers()

	currentState = STATE.LOBBY
	broadcast(STATE.LOBBY, {})
	print("[Round] Returned to lobby")
end

local function startRound()
	if currentState ~= STATE.LOBBY then return end
	print("[Round] Starting round...")
	currentState = STATE.PLAYING
	broadcast(STATE.PLAYING, {})

	-- Ensure one wheel is placed in each cave at the start of every round.
	if _G.GameAPI.respawnPickups then _G.GameAPI.respawnPickups() end

	-- Spawn the monster after a brief grace period so players can orient
	task.spawn(function()
		task.wait(2)
		-- Bail if state changed during the wait (e.g., last player left)
		if currentState ~= STATE.PLAYING then return end
		if _G.GameAPI.setMonsterPaused then _G.GameAPI.setMonsterPaused(false) end
		if _G.GameAPI.respawnMonster   then _G.GameAPI.respawnMonster() end
	end)
end

-- A player clicked PLAY on the title screen
readyRemote.OnServerEvent:Connect(function(player)
	print(string.format("[Round] %s clicked PLAY", player.Name))
	startRound()
end)

local function endRound(newState: string, detail: { [string]: any }?)
	if currentState ~= STATE.PLAYING then return end  -- already ending
	currentState = newState
	currentRoundId += 1
	if _G.GameAPI.setMonsterPaused then _G.GameAPI.setMonsterPaused(true) end
	broadcast(newState, detail)

	task.spawn(function()
		task.wait(6)  -- let the result screen breathe
		currentState = STATE.RESTART
		broadcast(STATE.RESTART, {})
		task.wait(0.5)
		teardownToLobby()
	end)
end

-- ===== API hooks =====

_G.GameAPI = _G.GameAPI or {}

--- Called by Monster.server.lua when a player gets caught.
--- If the player has Power Juice, consume it and knock them away instead of
--- ending the round. Otherwise the round ends.
function _G.GameAPI.notifyCaught(player: Player)
	if _G.GameAPI.consumePowerJuice and _G.GameAPI.consumePowerJuice(player) then
		print(string.format("[Round] %s's Power Juice saved them!", player.Name))

		-- Knock the player away from the monster.
		local char = player.Character
		local pRoot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local monster = Workspace:FindFirstChild("Monster")
		local mRoot = monster and monster:FindFirstChild("HumanoidRootPart") :: BasePart?
		if pRoot and mRoot then
			local away = (pRoot.Position - mRoot.Position)
			if away.Magnitude < 0.5 then
				away = Vector3.new(1, 0, 0)
			end
			away = (away * Vector3.new(1, 0, 1)).Unit  -- horizontal only
			pRoot.CFrame = CFrame.new(pRoot.Position + away * GameConfig.PowerJuiceKnockback + Vector3.new(0, 4, 0))
		end
		-- Briefly pause the monster so it can't immediately catch them again
		if _G.GameAPI.setMonsterPaused then
			_G.GameAPI.setMonsterPaused(true)
			task.delay(2, function()
				if currentState == STATE.PLAYING and _G.GameAPI.setMonsterPaused then
					_G.GameAPI.setMonsterPaused(false)
				end
			end)
		end
		return
	end

	print(string.format("[Round] %s was caught by the monster!", player.Name))
	-- Fire jumpscare on the caught client BEFORE flipping the round to LOST,
	-- so the screech plays before the lose-screen overlay takes the focus.
	jumpscareRemote:FireClient(player)
	endRound(STATE.LOST, { caughtPlayerName = player.Name })
end

--- Called by CarSetup automatically when the 4th wheel snaps on.
--- Plays the drive-away cinematic, then ends the round as WON.
--- `player` may be nil if called without crediting anyone.
function _G.GameAPI.startEscape(player: Player?)
	if currentState ~= STATE.PLAYING then return end
	if _G.GameAPI.getWheelsAttached and _G.GameAPI.getWheelsAttached() < GameConfig.WheelCount then
		return  -- guardrail; should never happen
	end

	local who = player and player.Name or "Someone"
	print(string.format("[Round] %s fixed the car — driving away!", who))

	-- Pause the monster during the cinematic so it can't catch the driver
	if _G.GameAPI.setMonsterPaused then _G.GameAPI.setMonsterPaused(true) end

	local car = _G.GameAPI.getCar and _G.GameAPI.getCar()
	if car then
		-- Tween the car forward (positive X is the direction the car faces)
		-- past the forest edge over a few seconds. We move all car parts in lockstep.
		local body = car:FindFirstChild("Body") :: BasePart?
		if body then
			local startCFrame = body.CFrame
			local endCFrame   = startCFrame + Vector3.new(GameConfig.ForestSize / 2 + 80, 0, 0)
			local tweenInfo   = TweenInfo.new(5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

			-- Tween every descendant Part by the same delta CFrame.
			-- We compute their offsets from the body once, then update every frame.
			local parts: { BasePart } = {}
			local offsets: { CFrame } = {}
			for _, d in ipairs(car:GetDescendants()) do
				if d:IsA("BasePart") then
					table.insert(parts, d)
					table.insert(offsets, body.CFrame:ToObjectSpace(d.CFrame))
				end
			end

			-- Use a NumberValue we can tween, then apply the lerp manually each step
			local progress = Instance.new("NumberValue")
			progress.Value = 0
			local conn
			conn = progress:GetPropertyChangedSignal("Value"):Connect(function()
				local lerped = startCFrame:Lerp(endCFrame, progress.Value)
				for i, part in ipairs(parts) do
					part.CFrame = lerped * offsets[i]
				end
			end)
			local tween = TweenService:Create(progress, tweenInfo, { Value = 1 })
			tween:Play()
			tween.Completed:Wait()
			if conn then conn:Disconnect() end
			progress:Destroy()
		end
	end

	endRound(STATE.WON, { escapedPlayerName = who })
end

-- Reset state when the last player leaves so the next session starts clean
Players.PlayerRemoving:Connect(function()
	if #Players:GetPlayers() <= 1 then
		currentState = STATE.LOBBY
	end
end)

-- Initial broadcast: server starts in LOBBY waiting for someone to press PLAY
task.spawn(function()
	task.wait(1)
	broadcast(STATE.LOBBY, {})
	print("[Round] Manager ready (LOBBY)")
end)
