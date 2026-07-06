-- GameConfig.lua (ModuleScript)
-- Shared configuration for the forest horror game.
-- Tweak any of these to rebalance the game.
-- Import with: local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local GameConfig = {}

-- Identity
GameConfig.GameName = "Lost in the Forest"
GameConfig.Version  = "0.1.0"

-- Forest / world
GameConfig.ForestSize        = 1000      -- studs (width = depth)
GameConfig.TreeCount         = 600       -- how many trees to scatter
GameConfig.BushCount         = 350       -- low green bushes for ground cover
GameConfig.RockCount         = 180       -- mossy gray rocks
GameConfig.GroundColor       = Color3.fromRGB(40, 35, 28)   -- damp dirt
GameConfig.ClearingRadius    = 35        -- empty area around the car (no trees/bushes/rocks)

-- Atmosphere / lighting (without a flashlight, the world has to be navigable)
GameConfig.FogStart          = 20
GameConfig.FogEnd            = 130       -- thick fog: can't see past 130 studs
GameConfig.FogColor          = Color3.fromRGB(120, 125, 130)
GameConfig.AmbientColor      = Color3.fromRGB(75, 75, 85)
GameConfig.OutdoorAmbient    = Color3.fromRGB(100, 105, 110)
GameConfig.ClockTime         = 18.0      -- dusk, slightly brighter than before
GameConfig.Brightness        = 0.7

-- Car (the goal)
-- Body is 14×4×6, so center at Y=3 puts the bottom flush with the ground top (Y=1).
GameConfig.CarPosition       = Vector3.new(0, 3, 0)
GameConfig.WheelSlotOffsets  = {                            -- relative to car
	Vector3.new( 6,  0,  3),   -- front-right
	Vector3.new( 6,  0, -3),   -- front-left
	Vector3.new(-6,  0,  3),   -- rear-right
	Vector3.new(-6,  0, -3),   -- rear-left
}
GameConfig.WheelCount        = 4

-- Caves: 4 fixed positions roughly in the four quadrants of the forest.
-- Each cave hides one wheel.
GameConfig.CavePositions = {
	Vector3.new( 350, 1,  350),
	Vector3.new(-350, 1,  350),
	Vector3.new( 350, 1, -350),
	Vector3.new(-350, 1, -350),
}
GameConfig.CaveClearingRadius = 18  -- no trees/bushes/rocks within this radius of a cave

-- Coin economy
GameConfig.CoinsPerWheelAttached = 5
GameConfig.StartingCoins         = 0       -- new players start with this

-- Shop
GameConfig.ShopPosition          = Vector3.new(35, 3, 60)   -- near spawn
GameConfig.BootsCost             = 100
GameConfig.BootsSpeedBonus       = 6      -- WalkSpeed 16 → 22 with boots
GameConfig.PowerJuiceCost        = 500
GameConfig.PowerJuiceKnockback   = 60     -- studs to fling player when juice triggers
GameConfig.GunCost               = 1000
GameConfig.GunStunDuration       = 45     -- seconds the monster freezes for
GameConfig.GunCooldown           = 120    -- seconds between shots

-- Pickups
GameConfig.WheelPickupRadius      = 6      -- how close to grab (ProximityPrompt range)

-- Flashlight
GameConfig.FlashlightRange     = 60
GameConfig.FlashlightAngle     = 50
GameConfig.FlashlightBrightness = 4
GameConfig.FlashlightColor     = Color3.fromRGB(255, 240, 200)

-- Monster (Phase 2)
GameConfig.MonsterSpeed        = 22    -- studs/sec when chasing (player walks at 16, with boots 22)
GameConfig.MonsterCatchRadius  = 5    -- a step bigger so it doesn't need to be face-to-face
GameConfig.MonsterColor        = Color3.fromRGB(0, 0, 0)
GameConfig.MonsterSpawnDistance = 250  -- min distance from any player at spawn

-- Atmospheric audio (twig snaps when monster is close + random whispers).
-- Fill in real asset IDs from Studio's Toolbox → Audio (search "twig snap",
-- "whisper", etc). Format: "rbxassetid://NUMBER" or just "NUMBER".
GameConfig.TwigSnapSoundId      = ""        -- e.g. "rbxassetid://12345678"
GameConfig.WhisperSoundId       = ""        -- e.g. "rbxassetid://87654321"
GameConfig.MonsterCloseDistance = 50        -- twig snap triggers within this radius
GameConfig.TwigSnapChance       = 0.85      -- 85% per opportunity
GameConfig.TwigSnapCooldown     = 6         -- min seconds between twig snaps
GameConfig.WhisperMinInterval   = 12        -- random whisper every 12–35s
GameConfig.WhisperMaxInterval   = 35
GameConfig.WhisperLines = {
	"look behind you",
	"always watching",
	"don't stop running",
	"it sees you",
	"behind you",
	"you can't escape",
	"i'm right here",
	"closer than you think",
	"don't turn around",
	"shhh",
	"i hear you breathing",
	"so close now",
}

-- Player
-- Spawn pad is 1 thick. Y=1.5 places its bottom flush with ground top (Y=1).
GameConfig.PlayerSpawnPosition = Vector3.new(0, 1.5, 60)
GameConfig.WalkSpeed           = 16

-- Border walls (invisible) around the forest perimeter so players can't escape
GameConfig.BorderHeight    = 50
GameConfig.BorderThickness = 4

return GameConfig
