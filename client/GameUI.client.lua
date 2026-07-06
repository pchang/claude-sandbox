-- GameUI.client.lua (LocalScript)
--
-- The HUD overlay during the game. Shows:
--   * Wheels in inventory  (e.g. "Wheels: 2")
--   * Wheels attached to the car (updates via WheelAttached events)
--   * Flashlight icon if held + "[F] Toggle" hint
--   * Current objective text at the top
--   * Brief popup when you pick something up

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared     = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes    = require(Shared:WaitForChild("Remotes"))

local inventoryRemote        = Remotes.wait(Remotes.Names.InventoryChanged)
local pickupCollectedRemote  = Remotes.wait(Remotes.Names.PickupCollected)
local wheelAttachedRemote    = Remotes.wait(Remotes.Names.WheelAttached)
local gameStateRemote        = Remotes.wait(Remotes.Names.GameStateChanged)
local playerReadyRemote      = Remotes.wait(Remotes.Names.PlayerReady)
local shopOpenRemote         = Remotes.wait(Remotes.Names.ShopOpen)
local shopBuyRemote          = Remotes.wait(Remotes.Names.ShopBuy)
local shopBuyResultRemote    = Remotes.wait(Remotes.Names.ShopBuyResult)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Build the screen GUI
local screen = Instance.new("ScreenGui")
screen.Name = "HorrorHUD"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.Parent = playerGui

-- Top objective banner
local objectiveLabel = Instance.new("TextLabel")
objectiveLabel.Name = "Objective"
objectiveLabel.Size = UDim2.new(1, 0, 0, 40)
objectiveLabel.Position = UDim2.new(0, 0, 0, 20)
objectiveLabel.BackgroundTransparency = 1
objectiveLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
objectiveLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
objectiveLabel.TextStrokeTransparency = 0
objectiveLabel.Font = Enum.Font.GothamBold
objectiveLabel.TextScaled = true
objectiveLabel.Text = "Find 4 wheels and fix the car"
objectiveLabel.Parent = screen

-- Bottom-left HUD: floating text only, no background rectangle.
-- Stroke makes them readable against any forest background.
local function makeFloatingLabel(name: string, yOffset: number, color: Color3): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.Name = name
	lbl.Size = UDim2.new(0, 280, 0, 26)
	lbl.Position = UDim2.new(0, 20, 1, yOffset)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = color
	lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	lbl.TextStrokeTransparency = 0
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 18
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Text = ""
	lbl.Parent = screen
	return lbl
end

local wheelsLabel = makeFloatingLabel("WheelsLabel", -64, Color3.fromRGB(230, 230, 230))
local coinsLabel  = makeFloatingLabel("CoinsLabel",  -36, Color3.fromRGB(255, 220, 110))
wheelsLabel.Text = "Wheels: 0   Attached: 0/4"
coinsLabel.Text  = "Coins: 0"

-- Centered popup for pickup feedback
local popup = Instance.new("TextLabel")
popup.Name = "PickupPopup"
popup.Size = UDim2.new(0, 400, 0, 50)
popup.Position = UDim2.new(0.5, -200, 0.7, 0)
popup.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
popup.BackgroundTransparency = 0.3
popup.TextColor3 = Color3.fromRGB(255, 255, 255)
popup.Font = Enum.Font.GothamBold
popup.TextSize = 22
popup.Text = ""
popup.TextTransparency = 1
popup.Parent = screen
local popupCorner = Instance.new("UICorner")
popupCorner.CornerRadius = UDim.new(0, 6)
popupCorner.Parent = popup

local function showPopup(text: string)
	popup.Text = text
	popup.TextTransparency = 0
	popup.BackgroundTransparency = 0.3
	-- Fade out
	task.delay(1.8, function()
		local fade = TweenService:Create(
			popup,
			TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ TextTransparency = 1, BackgroundTransparency = 1 }
		)
		fade:Play()
	end)
end

-- Local state mirrored from server
local state = {
	wheelsHeld = 0,
	wheelsAttached = 0,
	coins = 0,
	hasBoots = false,
	hasPowerJuice = false,
	hasGun = false,
	lifetimeWheels = 0,
	rank = "Bronze",
}

-- Forward declaration so the inventory event handler (registered below) can call
-- this function even though it's fully defined later in the file.
local setRankDisplay

local function refreshHUD()
	wheelsLabel.Text = string.format(
		"Wheels: %d   Attached: %d/%d",
		state.wheelsHeld, state.wheelsAttached, GameConfig.WheelCount
	)
	coinsLabel.Text = string.format("Coins: %d", state.coins)

	-- Update objective dynamically
	if state.wheelsAttached >= GameConfig.WheelCount then
		objectiveLabel.Text = "ESCAPE!  Get in the car and drive away"
		objectiveLabel.TextColor3 = Color3.fromRGB(120, 255, 140)
	elseif state.wheelsHeld > 0 then
		objectiveLabel.Text = "Bring wheels to the car  (E to attach)"
		objectiveLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
	else
		objectiveLabel.Text = "Find 4 wheels in the caves to fix the car"
		objectiveLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	end
end

-- Server now sends the full inventory state as a single table
inventoryRemote.OnClientEvent:Connect(function(inv)
	if typeof(inv) ~= "table" then return end
	state.wheelsHeld     = inv.wheels or 0
	state.coins          = inv.coins or 0
	state.hasBoots       = inv.hasBoots or false
	state.hasPowerJuice  = inv.hasPowerJuice or false
	state.hasGun         = inv.hasGun or false
	state.lifetimeWheels = inv.lifetimeWheels or 0
	state.rank           = inv.rank or "Bronze"
	refreshHUD()
	-- Update title-screen rank badge if present (defined below)
	if setRankDisplay then setRankDisplay(state.rank, state.lifetimeWheels) end
	-- If shop UI is open, refresh its buttons (defined below)
	if refreshShop then refreshShop() end
end)

pickupCollectedRemote.OnClientEvent:Connect(function(kind: string)
	if kind == "wheel" then
		showPopup("+ Wheel collected")
	end
end)

wheelAttachedRemote.OnClientEvent:Connect(function(slotIndex: number, byPlayerName: string)
	state.wheelsAttached += 1
	refreshHUD()
	if byPlayerName == player.Name then
		showPopup(string.format("You attached wheel %d  (%d/%d)", slotIndex, state.wheelsAttached, GameConfig.WheelCount))
	else
		showPopup(string.format("%s attached a wheel  (%d/%d)", byPlayerName, state.wheelsAttached, GameConfig.WheelCount))
	end
end)

refreshHUD()

-- ========== Full-screen overlay for game-over / victory / restart ==========

local overlay = Instance.new("Frame")
overlay.Name = "StateOverlay"
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel = 0
overlay.Visible = false
overlay.ZIndex = 50
overlay.Parent = screen

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, 0, 0, 100)
title.Position = UDim2.new(0, 0, 0.35, 0)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextSize = 64
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
title.TextStrokeTransparency = 0
title.Text = ""
title.ZIndex = 51
title.Parent = overlay

local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.Size = UDim2.new(1, 0, 0, 40)
subtitle.Position = UDim2.new(0, 0, 0.5, 20)
subtitle.BackgroundTransparency = 1
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 22
subtitle.TextColor3 = Color3.fromRGB(220, 220, 220)
subtitle.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
subtitle.TextStrokeTransparency = 0
subtitle.Text = ""
subtitle.ZIndex = 51
subtitle.Parent = overlay

local function showOverlay(opts: { titleText: string, subtitleText: string, color: Color3, fadeTo: number })
	title.Text = opts.titleText
	title.TextColor3 = opts.color
	subtitle.Text = opts.subtitleText
	overlay.BackgroundTransparency = 1
	title.TextTransparency = 1
	subtitle.TextTransparency = 1
	overlay.Visible = true

	local fade = TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	TweenService:Create(overlay, fade, { BackgroundTransparency = opts.fadeTo }):Play()
	TweenService:Create(title, fade, { TextTransparency = 0, TextStrokeTransparency = 0 }):Play()
	TweenService:Create(subtitle, fade, { TextTransparency = 0, TextStrokeTransparency = 0 }):Play()
end

local function hideOverlay()
	local fade = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	TweenService:Create(overlay, fade, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(title, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	TweenService:Create(subtitle, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(0.6, function() overlay.Visible = false end)
end

-- ========== Title screen with PLAY button ==========

local titleScreen = Instance.new("Frame")
titleScreen.Name = "TitleScreen"
titleScreen.Size = UDim2.new(1, 0, 1, 0)
titleScreen.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
titleScreen.BackgroundTransparency = 0     -- fully opaque (hides game world)
titleScreen.BorderSizePixel = 0
titleScreen.Visible = true                 -- visible by default until a state arrives
titleScreen.ZIndex = 100
titleScreen.Parent = screen

local titleHeader = Instance.new("TextLabel")
titleHeader.Name = "TitleHeader"
titleHeader.Size = UDim2.new(1, 0, 0, 100)
titleHeader.Position = UDim2.new(0, 0, 0.28, 0)
titleHeader.BackgroundTransparency = 1
titleHeader.Font = Enum.Font.GothamBlack
titleHeader.TextSize = 72
titleHeader.TextColor3 = Color3.fromRGB(230, 230, 230)
titleHeader.TextStrokeColor3 = Color3.fromRGB(60, 0, 0)
titleHeader.TextStrokeTransparency = 0.4
titleHeader.Text = "LOST IN THE FOREST"
titleHeader.ZIndex = 101
titleHeader.Parent = titleScreen

local titleSub = Instance.new("TextLabel")
titleSub.Name = "TitleSub"
titleSub.Size = UDim2.new(1, 0, 0, 30)
titleSub.Position = UDim2.new(0, 0, 0.42, 0)
titleSub.BackgroundTransparency = 1
titleSub.Font = Enum.Font.Gotham
titleSub.TextSize = 18
titleSub.TextColor3 = Color3.fromRGB(180, 180, 180)
titleSub.Text = "Find 4 wheels in the caves. Don't let the monster see you."
titleSub.ZIndex = 101
titleSub.Parent = titleScreen

local playButton = Instance.new("TextButton")
playButton.Name = "PlayButton"
playButton.Size = UDim2.new(0, 220, 0, 70)
playButton.Position = UDim2.new(0.5, -110, 0.55, 0)
playButton.BackgroundColor3 = Color3.fromRGB(140, 30, 30)
playButton.BorderSizePixel = 0
playButton.Font = Enum.Font.GothamBlack
playButton.TextSize = 36
playButton.TextColor3 = Color3.fromRGB(255, 255, 255)
playButton.Text = "PLAY"
playButton.AutoButtonColor = true
playButton.ZIndex = 101
playButton.Parent = titleScreen

local playCorner = Instance.new("UICorner")
playCorner.CornerRadius = UDim.new(0, 10)
playCorner.Parent = playButton

-- SHOP button on the title screen (replaces the in-world shop counter)
local titleShopButton = Instance.new("TextButton")
titleShopButton.Name = "ShopButton"
titleShopButton.Size = UDim2.new(0, 180, 0, 50)
titleShopButton.Position = UDim2.new(0.5, -90, 0.68, 0)
titleShopButton.BackgroundColor3 = Color3.fromRGB(70, 70, 80)
titleShopButton.BorderSizePixel = 0
titleShopButton.Font = Enum.Font.GothamBold
titleShopButton.TextSize = 22
titleShopButton.TextColor3 = Color3.fromRGB(255, 220, 110)
titleShopButton.Text = "SHOP"
titleShopButton.AutoButtonColor = true
titleShopButton.ZIndex = 101
titleShopButton.Parent = titleScreen

local titleShopCorner = Instance.new("UICorner")
titleShopCorner.CornerRadius = UDim.new(0, 8)
titleShopCorner.Parent = titleShopButton

-- ===== Rank badge on the title screen =====
-- Four icons (one for each rank) sit in a centered container; we show one at a
-- time based on the player's current rank, with a text label to the right.
local rankRow = Instance.new("Frame")
rankRow.Name = "RankRow"
rankRow.Size = UDim2.new(0, 320, 0, 40)
rankRow.Position = UDim2.new(0.5, -160, 0.80, 0)
rankRow.BackgroundTransparency = 1
rankRow.ZIndex = 101
rankRow.Parent = titleScreen

local iconHolder = Instance.new("Frame")
iconHolder.Name = "Icon"
iconHolder.Size = UDim2.new(0, 36, 0, 36)
iconHolder.Position = UDim2.new(0, 0, 0.5, -18)
iconHolder.BackgroundTransparency = 1
iconHolder.ZIndex = 102
iconHolder.Parent = rankRow

-- Bronze: brown filled square
local bronzeIcon = Instance.new("Frame")
bronzeIcon.Size = UDim2.new(0, 26, 0, 26)
bronzeIcon.Position = UDim2.new(0.5, -13, 0.5, -13)
bronzeIcon.BackgroundColor3 = Color3.fromRGB(150, 90, 45)   -- brown
bronzeIcon.BorderSizePixel = 0
bronzeIcon.ZIndex = 103
bronzeIcon.Visible = false
bronzeIcon.Parent = iconHolder

-- Silver: light gray filled circle
local silverIcon = Instance.new("Frame")
silverIcon.Size = UDim2.new(0, 28, 0, 28)
silverIcon.Position = UDim2.new(0.5, -14, 0.5, -14)
silverIcon.BackgroundColor3 = Color3.fromRGB(210, 210, 220)  -- light gray
silverIcon.BorderSizePixel = 0
silverIcon.ZIndex = 103
silverIcon.Visible = false
silverIcon.Parent = iconHolder
local silverCorner = Instance.new("UICorner")
silverCorner.CornerRadius = UDim.new(1, 0)
silverCorner.Parent = silverIcon

-- Gold: 4-tipped star, built from two perpendicular crossed bars.
-- Avoids font/Unicode rendering variance; renders the same on every machine.
local function buildFourTipStar(parent: GuiObject, sizePx: number, color: Color3, baseZ: number): Frame
	local star = Instance.new("Frame")
	star.Size = UDim2.new(1, 0, 1, 0)
	star.BackgroundTransparency = 1
	star.ZIndex = baseZ
	star.Parent = parent

	local thickness = math.max(3, math.floor(sizePx * 0.18))

	local vBar = Instance.new("Frame")
	vBar.Size = UDim2.new(0, thickness, 0, sizePx)
	vBar.AnchorPoint = Vector2.new(0.5, 0.5)
	vBar.Position = UDim2.new(0.5, 0, 0.5, 0)
	vBar.BackgroundColor3 = color
	vBar.BorderSizePixel = 0
	vBar.ZIndex = baseZ + 1
	vBar.Parent = star

	local hBar = Instance.new("Frame")
	hBar.Size = UDim2.new(0, sizePx, 0, thickness)
	hBar.AnchorPoint = Vector2.new(0.5, 0.5)
	hBar.Position = UDim2.new(0.5, 0, 0.5, 0)
	hBar.BackgroundColor3 = color
	hBar.BorderSizePixel = 0
	hBar.ZIndex = baseZ + 1
	hBar.Parent = star

	return star
end

local goldIcon = buildFourTipStar(iconHolder, 28, Color3.fromRGB(255, 215, 60), 103)
goldIcon.Visible = false

-- Platinum: teal "V"
local platinumIcon = Instance.new("TextLabel")
platinumIcon.Size = UDim2.new(1, 0, 1, 0)
platinumIcon.BackgroundTransparency = 1
platinumIcon.Font = Enum.Font.GothamBlack
platinumIcon.TextSize = 32
platinumIcon.TextColor3 = Color3.fromRGB(80, 220, 200)    -- teal
platinumIcon.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
platinumIcon.TextStrokeTransparency = 0.6
platinumIcon.Text = "V"
platinumIcon.ZIndex = 103
platinumIcon.Visible = false
platinumIcon.Parent = iconHolder

local rankLabel = Instance.new("TextLabel")
rankLabel.Name = "RankText"
rankLabel.Size = UDim2.new(1, -48, 1, 0)
rankLabel.Position = UDim2.new(0, 48, 0, 0)
rankLabel.BackgroundTransparency = 1
rankLabel.Font = Enum.Font.GothamBold
rankLabel.TextSize = 18
rankLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
rankLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
rankLabel.TextStrokeTransparency = 0.5
rankLabel.TextXAlignment = Enum.TextXAlignment.Left
rankLabel.Text = "Rank: Bronze  ·  0 wheels attached"
rankLabel.ZIndex = 102
rankLabel.Parent = rankRow

setRankDisplay = function(rank: string, lifetimeWheels: number)
	bronzeIcon.Visible   = (rank == "Bronze")
	silverIcon.Visible   = (rank == "Silver")
	goldIcon.Visible     = (rank == "Gold")
	platinumIcon.Visible = (rank == "Platinum")

	-- Color the text by rank for a bit of extra visual punch
	local color = Color3.fromRGB(220, 220, 220)
	if rank == "Silver" then     color = Color3.fromRGB(220, 220, 230)
	elseif rank == "Gold" then   color = Color3.fromRGB(255, 215, 60)
	elseif rank == "Platinum" then color = Color3.fromRGB(80, 220, 200)
	end
	rankLabel.TextColor3 = color
	rankLabel.Text = string.format("Rank: %s  ·  %d wheels attached", rank, lifetimeWheels)
end

-- ===== "rank difficulty" button =====
local rankInfoButton = Instance.new("TextButton")
rankInfoButton.Name = "RankInfoButton"
rankInfoButton.Size = UDim2.new(0, 200, 0, 36)
rankInfoButton.Position = UDim2.new(0.5, -100, 0.87, 0)
rankInfoButton.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
rankInfoButton.BorderSizePixel = 0
rankInfoButton.Font = Enum.Font.GothamBold
rankInfoButton.TextSize = 16
rankInfoButton.TextColor3 = Color3.fromRGB(230, 230, 230)
rankInfoButton.Text = "rank difficulty"
rankInfoButton.AutoButtonColor = true
rankInfoButton.ZIndex = 101
rankInfoButton.Parent = titleScreen

local rankInfoCorner = Instance.new("UICorner")
rankInfoCorner.CornerRadius = UDim.new(0, 6)
rankInfoCorner.Parent = rankInfoButton

-- ===== Rank-difficulty info panel (opens on click) =====
local rankPanel = Instance.new("Frame")
rankPanel.Name = "RankPanel"
rankPanel.Size = UDim2.new(0, 460, 0, 360)
rankPanel.Position = UDim2.new(0.5, -230, 0.5, -180)
rankPanel.BackgroundColor3 = Color3.fromRGB(20, 18, 16)
rankPanel.BorderSizePixel = 0
rankPanel.Visible = false
rankPanel.ZIndex = 130                    -- above title (100) and shop (120)
rankPanel.Parent = screen

local rankPanelCorner = Instance.new("UICorner")
rankPanelCorner.CornerRadius = UDim.new(0, 12)
rankPanelCorner.Parent = rankPanel

local rankPanelHeader = Instance.new("TextLabel")
rankPanelHeader.Size = UDim2.new(1, -60, 0, 50)
rankPanelHeader.Position = UDim2.new(0, 16, 0, 8)
rankPanelHeader.BackgroundTransparency = 1
rankPanelHeader.Font = Enum.Font.GothamBlack
rankPanelHeader.TextSize = 24
rankPanelHeader.TextColor3 = Color3.fromRGB(255, 220, 100)
rankPanelHeader.TextXAlignment = Enum.TextXAlignment.Left
rankPanelHeader.Text = "RANK DIFFICULTY"
rankPanelHeader.ZIndex = 131
rankPanelHeader.Parent = rankPanel

local rankPanelClose = Instance.new("TextButton")
rankPanelClose.Size = UDim2.new(0, 36, 0, 36)
rankPanelClose.Position = UDim2.new(1, -44, 0, 8)
rankPanelClose.BackgroundColor3 = Color3.fromRGB(80, 30, 30)
rankPanelClose.BorderSizePixel = 0
rankPanelClose.Font = Enum.Font.GothamBlack
rankPanelClose.TextSize = 22
rankPanelClose.TextColor3 = Color3.fromRGB(255, 255, 255)
rankPanelClose.Text = "X"
rankPanelClose.ZIndex = 132
rankPanelClose.Parent = rankPanel
local rankPanelCloseCorner = Instance.new("UICorner")
rankPanelCloseCorner.CornerRadius = UDim.new(0, 6)
rankPanelCloseCorner.Parent = rankPanelClose

rankPanelClose.MouseButton1Click:Connect(function()
	rankPanel.Visible = false
end)

-- One row per rank with icon + requirement
local RANK_INFO = {
	{ key = "Bronze",   reqText = "0 – 100 wheels attached",   nameColor = Color3.fromRGB(220, 165, 110) },
	{ key = "Silver",   reqText = "101 – 200 wheels attached", nameColor = Color3.fromRGB(220, 220, 230) },
	{ key = "Gold",     reqText = "201+ wheels attached",      nameColor = Color3.fromRGB(255, 215, 60) },
	{ key = "Platinum", reqText = "Top 20 Gold players",        nameColor = Color3.fromRGB(80, 220, 200) },
}

for i, r in ipairs(RANK_INFO) do
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -32, 0, 60)
	row.Position = UDim2.new(0, 16, 0, 60 + (i - 1) * 70)
	row.BackgroundColor3 = Color3.fromRGB(40, 35, 32)
	row.BorderSizePixel = 0
	row.ZIndex = 131
	row.Parent = rankPanel
	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 8)
	rowCorner.Parent = row

	-- Icon container
	local iconBox = Instance.new("Frame")
	iconBox.Size = UDim2.new(0, 50, 0, 50)
	iconBox.Position = UDim2.new(0, 8, 0.5, -25)
	iconBox.BackgroundTransparency = 1
	iconBox.ZIndex = 132
	iconBox.Parent = row

	if r.key == "Bronze" then
		local b = Instance.new("Frame")
		b.Size = UDim2.new(0, 30, 0, 30)
		b.Position = UDim2.new(0.5, -15, 0.5, -15)
		b.BackgroundColor3 = Color3.fromRGB(150, 90, 45)
		b.BorderSizePixel = 0
		b.ZIndex = 133
		b.Parent = iconBox
	elseif r.key == "Silver" then
		local s = Instance.new("Frame")
		s.Size = UDim2.new(0, 32, 0, 32)
		s.Position = UDim2.new(0.5, -16, 0.5, -16)
		s.BackgroundColor3 = Color3.fromRGB(210, 210, 220)
		s.BorderSizePixel = 0
		s.ZIndex = 133
		s.Parent = iconBox
		local sc = Instance.new("UICorner")
		sc.CornerRadius = UDim.new(1, 0)
		sc.Parent = s
	elseif r.key == "Gold" then
		buildFourTipStar(iconBox, 40, Color3.fromRGB(255, 215, 60), 133)
	elseif r.key == "Platinum" then
		local p = Instance.new("TextLabel")
		p.Size = UDim2.new(1, 0, 1, 0)
		p.BackgroundTransparency = 1
		p.Font = Enum.Font.GothamBlack
		p.TextSize = 36
		p.TextColor3 = Color3.fromRGB(80, 220, 200)
		p.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		p.TextStrokeTransparency = 0.6
		p.Text = "V"
		p.ZIndex = 133
		p.Parent = iconBox
	end

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(0.5, 0, 0, 24)
	nameLbl.Position = UDim2.new(0, 70, 0, 8)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font = Enum.Font.GothamBold
	nameLbl.TextSize = 18
	nameLbl.TextColor3 = r.nameColor
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.Text = r.key
	nameLbl.ZIndex = 132
	nameLbl.Parent = row

	local reqLbl = Instance.new("TextLabel")
	reqLbl.Size = UDim2.new(1, -80, 0, 24)
	reqLbl.Position = UDim2.new(0, 70, 0, 30)
	reqLbl.BackgroundTransparency = 1
	reqLbl.Font = Enum.Font.Gotham
	reqLbl.TextSize = 14
	reqLbl.TextColor3 = Color3.fromRGB(180, 180, 180)
	reqLbl.TextXAlignment = Enum.TextXAlignment.Left
	reqLbl.Text = r.reqText
	reqLbl.ZIndex = 132
	reqLbl.Parent = row
end

rankInfoButton.MouseButton1Click:Connect(function()
	rankPanel.Visible = true
end)

local function setTitleScreenVisible(visible: boolean)
	titleScreen.Visible = visible
	-- Hide HUD elements while the title is up
	objectiveLabel.Visible = not visible
	wheelsLabel.Visible    = not visible
	coinsLabel.Visible     = not visible

	-- Camera is always Classic third-person now.
	-- Title screen: free cursor for clicking buttons.
	-- Gameplay: also free cursor (no first-person mouse lock).
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 25
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true

	-- Freeze movement during the title screen so the player doesn't walk blind.
	-- When unfreezing, factor in the boots bonus from local inventory state so
	-- we don't stomp the speed value the server applied.
	local character = player.Character
	if character then
		local hum = character:FindFirstChildOfClass("Humanoid")
		if hum then
			if visible then
				hum.WalkSpeed = 0
				hum.JumpPower = 0
			else
				local bonus = state.hasBoots and GameConfig.BootsSpeedBonus or 0
				hum.WalkSpeed = GameConfig.WalkSpeed + bonus
				hum.JumpPower = 50
			end
		end
	end
end

-- Re-apply the freeze + camera mode if the character respawns during LOBBY
player.CharacterAdded:Connect(function()
	task.wait(0.4)
	if titleScreen.Visible then
		setTitleScreenVisible(true)
	end
end)

-- Initialize: at script load, the title screen is visible by default, so
-- explicitly apply lobby state (Classic camera, free cursor, frozen movement).
-- Without this, the camera waits for the first state event from the server.
setTitleScreenVisible(true)
-- Show a default Bronze badge until the server's first inventory event arrives
setRankDisplay("Bronze", 0)

playButton.MouseButton1Click:Connect(function()
	-- Optimistically hide locally for snappy feedback; server will confirm
	playButton.AutoButtonColor = false
	playButton.BackgroundColor3 = Color3.fromRGB(80, 20, 20)
	playButton.Text = "..."
	playerReadyRemote:FireServer()
end)
-- (titleShopButton's click handler is wired below, after setShopVisible is defined)

gameStateRemote.OnClientEvent:Connect(function(roundState: string, detail: { [string]: any }?)
	detail = detail or {}
	if roundState == "lobby" then
		hideOverlay()
		-- Reset Play button (in case we're returning from a finished round)
		playButton.Text = "PLAY"
		playButton.AutoButtonColor = true
		playButton.BackgroundColor3 = Color3.fromRGB(140, 30, 30)
		setTitleScreenVisible(true)
		-- Reset HUD mirror so it's clean when the next round starts
		state.wheelsHeld = 0
		state.wheelsAttached = 0
		refreshHUD()
	elseif roundState == "playing" then
		setTitleScreenVisible(false)
		hideOverlay()
		state.wheelsHeld = 0
		state.wheelsAttached = 0
		refreshHUD()
	elseif roundState == "lost" then
		local who = (detail.caughtPlayerName or "Someone") :: string
		showOverlay({
			titleText    = "GAME OVER",
			subtitleText = who .. " was caught by the monster.",
			color        = Color3.fromRGB(255, 60, 60),
			fadeTo       = 0.15,
		})
	elseif roundState == "won" then
		local who = (detail.escapedPlayerName or "You") :: string
		showOverlay({
			titleText    = "ESCAPED",
			subtitleText = who .. " drove the car out of the forest.",
			color        = Color3.fromRGB(120, 255, 140),
			fadeTo       = 0.15,
		})
	elseif roundState == "restart" then
		-- Brief transition; server immediately follows with "lobby"
		showOverlay({
			titleText    = "Returning to lobby...",
			subtitleText = "",
			color        = Color3.fromRGB(220, 220, 220),
			fadeTo       = 0.6,
		})
	end
end)

-- ========== Shop UI ==========
-- Triggered by ProximityPrompt on the shop counter (server fires ShopOpen).
-- A simple panel with three items, each with a BUY button. Once owned the
-- button changes to "OWNED" and is disabled.

local shopFrame = Instance.new("Frame")
shopFrame.Name = "ShopFrame"
shopFrame.Size = UDim2.new(0, 460, 0, 380)
shopFrame.Position = UDim2.new(0.5, -230, 0.5, -190)
shopFrame.BackgroundColor3 = Color3.fromRGB(20, 18, 16)
shopFrame.BorderSizePixel = 0
shopFrame.Visible = false
-- Above the title screen (ZIndex 100/101) so it renders on top of it
shopFrame.ZIndex = 120
shopFrame.Parent = screen

local shopCorner = Instance.new("UICorner")
shopCorner.CornerRadius = UDim.new(0, 12)
shopCorner.Parent = shopFrame

local shopHeader = Instance.new("TextLabel")
shopHeader.Size = UDim2.new(0.5, 0, 0, 50)
shopHeader.Position = UDim2.new(0, 16, 0, 0)
shopHeader.BackgroundTransparency = 1
shopHeader.Font = Enum.Font.GothamBlack
shopHeader.TextSize = 30
shopHeader.TextColor3 = Color3.fromRGB(255, 220, 100)
shopHeader.TextXAlignment = Enum.TextXAlignment.Left
shopHeader.Text = "SHOP"
shopHeader.ZIndex = 121
shopHeader.Parent = shopFrame

-- Coin balance, top-right of the shop header
local shopCoinsLabel = Instance.new("TextLabel")
shopCoinsLabel.Name = "ShopCoinsLabel"
shopCoinsLabel.Size = UDim2.new(0.5, -60, 0, 50)
shopCoinsLabel.Position = UDim2.new(0.5, 0, 0, 0)
shopCoinsLabel.BackgroundTransparency = 1
shopCoinsLabel.Font = Enum.Font.GothamBold
shopCoinsLabel.TextSize = 22
shopCoinsLabel.TextColor3 = Color3.fromRGB(255, 220, 110)
shopCoinsLabel.TextXAlignment = Enum.TextXAlignment.Right
shopCoinsLabel.Text = "Coins: 0"
shopCoinsLabel.ZIndex = 121
shopCoinsLabel.Parent = shopFrame

local shopClose = Instance.new("TextButton")
shopClose.Size = UDim2.new(0, 36, 0, 36)
shopClose.Position = UDim2.new(1, -44, 0, 8)
shopClose.BackgroundColor3 = Color3.fromRGB(80, 30, 30)
shopClose.BorderSizePixel = 0
shopClose.Font = Enum.Font.GothamBlack
shopClose.TextSize = 22
shopClose.TextColor3 = Color3.fromRGB(255, 255, 255)
shopClose.Text = "X"
shopClose.ZIndex = 122
shopClose.Parent = shopFrame
local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 6)
closeCorner.Parent = shopClose

-- Item card factory
local SHOP_ITEMS = {
	{ key = "Boots",      label = "Running Boots", desc = "Move faster.",           cost = GameConfig.BootsCost },
	{ key = "PowerJuice", label = "Power Juice",   desc = "Survive one monster catch.", cost = GameConfig.PowerJuiceCost },
}
local itemButtons: { [string]: TextButton } = {}

for i, def in ipairs(SHOP_ITEMS) do
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, -32, 0, 86)
	card.Position = UDim2.new(0, 16, 0, 60 + (i - 1) * 96)
	card.BackgroundColor3 = Color3.fromRGB(40, 35, 32)
	card.BorderSizePixel = 0
	card.ZIndex = 121
	card.Parent = shopFrame
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 8)
	cardCorner.Parent = card

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(0.6, 0, 0, 28)
	nameLbl.Position = UDim2.new(0, 14, 0, 10)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font = Enum.Font.GothamBold
	nameLbl.TextSize = 20
	nameLbl.TextColor3 = Color3.fromRGB(240, 240, 240)
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.Text = def.label
	nameLbl.ZIndex = 122
	nameLbl.Parent = card

	local descLbl = Instance.new("TextLabel")
	descLbl.Size = UDim2.new(0.6, 0, 0, 40)
	descLbl.Position = UDim2.new(0, 14, 0, 38)
	descLbl.BackgroundTransparency = 1
	descLbl.Font = Enum.Font.Gotham
	descLbl.TextSize = 14
	descLbl.TextWrapped = true
	descLbl.TextColor3 = Color3.fromRGB(180, 180, 180)
	descLbl.TextXAlignment = Enum.TextXAlignment.Left
	descLbl.TextYAlignment = Enum.TextYAlignment.Top
	descLbl.Text = def.desc
	descLbl.ZIndex = 122
	descLbl.Parent = card

	local buyBtn = Instance.new("TextButton")
	buyBtn.Size = UDim2.new(0, 130, 0, 50)
	buyBtn.Position = UDim2.new(1, -146, 0.5, -25)
	buyBtn.BackgroundColor3 = Color3.fromRGB(60, 100, 50)
	buyBtn.BorderSizePixel = 0
	buyBtn.Font = Enum.Font.GothamBold
	buyBtn.TextSize = 16
	buyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	buyBtn.Text = string.format("BUY  %d", def.cost)
	buyBtn.ZIndex = 122
	buyBtn.Parent = card
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 6)
	btnCorner.Parent = buyBtn
	itemButtons[def.key] = buyBtn

	buyBtn.MouseButton1Click:Connect(function()
		shopBuyRemote:FireServer(def.key)
	end)
end

-- Refresh button states based on current inventory + coin balance
function refreshShop()
	shopCoinsLabel.Text = string.format("Coins: %d", state.coins)
	for _, def in ipairs(SHOP_ITEMS) do
		local btn = itemButtons[def.key]
		if not btn then continue end
		local owned = (def.key == "Boots" and state.hasBoots)
			or (def.key == "PowerJuice" and state.hasPowerJuice)
			or (def.key == "Gun" and state.hasGun)
		if owned then
			btn.Text = "OWNED"
			btn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
			btn.AutoButtonColor = false
			btn.Active = false
		elseif state.coins < def.cost then
			btn.Text = string.format("BUY  %d", def.cost)
			btn.BackgroundColor3 = Color3.fromRGB(80, 50, 50)
			btn.AutoButtonColor = false
			btn.Active = false
		else
			btn.Text = string.format("BUY  %d", def.cost)
			btn.BackgroundColor3 = Color3.fromRGB(60, 100, 50)
			btn.AutoButtonColor = true
			btn.Active = true
		end
	end
end

local function setShopVisible(visible: boolean)
	shopFrame.Visible = visible
	-- Camera stays Classic + cursor free regardless of shop state, so we just
	-- refresh the shop contents when it opens.
	if visible then refreshShop() end
end

shopClose.MouseButton1Click:Connect(function() setShopVisible(false) end)

-- Open the shop when the SHOP button on the title screen is clicked
titleShopButton.MouseButton1Click:Connect(function()
	setShopVisible(true)
end)

-- (Legacy) the server can still fire ShopOpen, currently unused
shopOpenRemote.OnClientEvent:Connect(function()
	setShopVisible(true)
end)

shopBuyResultRemote.OnClientEvent:Connect(function(result)
	if result and result.ok then
		showPopup("Purchased: " .. (result.item or ""))
	elseif result and not result.ok then
		if result.reason == "insufficient_coins" then
			showPopup("Not enough coins")
		elseif result.reason == "already_owned" then
			showPopup("Already owned")
		end
	end
end)

-- Close the shop when a round ends — but NOT on "lobby", since the shop is
-- now opened from the title screen (which itself shows during lobby).
gameStateRemote.OnClientEvent:Connect(function(s)
	if s == "lost" or s == "won" or s == "restart" then
		setShopVisible(false)
	end
end)

print("[GameUI] HUD ready")
