-- Flashlight.client.lua (LocalScript)
--
-- An always-on PointLight attached to the player's head, so a soft circle of
-- light surrounds the player on every side. No toggle, no aim — just a glow
-- that makes the foggy forest navigable.

local Players = game:GetService("Players")

local player = Players.LocalPlayer

local function attachLightTo(character: Model)
	local head = character:WaitForChild("Head", 5)
	if not head then return end

	-- Clean up old lights from a previous life
	for _, child in ipairs(head:GetChildren()) do
		if child:IsA("SpotLight") or child:IsA("PointLight") then
			child:Destroy()
		end
	end

	-- Omnidirectional light → circular pool around the player
	local light = Instance.new("PointLight")
	light.Range = 18
	light.Brightness = 4.5
	light.Color = Color3.fromRGB(235, 235, 240)
	light.Shadows = true
	light.Enabled = true
	light.Parent = head
end

if player.Character then
	attachLightTo(player.Character)
end
player.CharacterAdded:Connect(function(character)
	task.wait(0.2)  -- let the head replicate
	attachLightTo(character)
end)
