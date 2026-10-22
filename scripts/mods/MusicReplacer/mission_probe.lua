-- Logging-only probe for the current mission's identity.
-- It never changes or silences anything.
-- Useful for finding what separates mission types and game modes.

local MissionProbe = {}

local log = function() end -- No-op unless a real logger is passed to MissionProbe.init.

-- Returns the template's simple fields (strings, numbers and booleans) as one sorted "key=value" line.
-- Tables and functions are skipped, so the line stays short.
local function describe(mission)
	local keys = {}

	for key, value in pairs(mission) do
		local value_type = type(value)
		if value_type == "string" or value_type == "number" or value_type == "boolean" then
			keys[#keys + 1] = tostring(key)
		end
	end

	table.sort(keys)

	local parts = {}
	for _, key in ipairs(keys) do
		parts[#parts + 1] = string.format("%s=%s", key, tostring(mission[key]))
	end

	return table.concat(parts, ", ")
end

-- Call once from the main mod file's top level.
function MissionProbe.init(logger)
	log = logger or log
end

-- Pass to Context.on_mission_change, which reads the mission on every tick anyway.
-- Logs each mission once, the hub included, and nothing while no level is loaded.
function MissionProbe.on_mission_change(mission_name, mission)
	if not mission_name then
		return
	end

	log(string.format("[mission] name=%s type=%s | %s",
		mission_name, tostring(mission and mission.mission_type), mission and describe(mission) or "no template"))
end

return MissionProbe
