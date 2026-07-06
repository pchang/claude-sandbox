-- Main.client.lua
-- Entry point for client-side game logic.
-- This script runs on each player's device only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")

print("[Client] Game client started for:", player.Name)

-- Example: wait for the character to load, then do something
local function onCharacterAdded(character)
	print("[Client] Character loaded:", character.Name)
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
