-- Utils.lua (ModuleScript)
-- General-purpose utility functions shared across server and client.
-- Import with: local Utils = require(ReplicatedStorage.Shared.Utils)

local Utils = {}

--- Clamp a number between min and max
function Utils.clamp(value: number, min: number, max: number): number
	return math.max(min, math.min(max, value))
end

--- Round a number to the nearest integer
function Utils.round(value: number): number
	return math.floor(value + 0.5)
end

--- Check if a value exists in a table
function Utils.tableContains(t: {any}, value: any): boolean
	for _, v in ipairs(t) do
		if v == value then return true end
	end
	return false
end

--- Shallow-copy a table
function Utils.shallowCopy(t: {[any]: any}): {[any]: any}
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = v
	end
	return copy
end

--- Format seconds into MM:SS display string
function Utils.formatTime(seconds: number): string
	local mins = math.floor(seconds / 60)
	local secs = math.floor(seconds % 60)
	return string.format("%02d:%02d", mins, secs)
end

return Utils
