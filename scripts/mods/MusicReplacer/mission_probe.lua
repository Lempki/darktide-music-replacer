-- Logging-only probe for the current mission's identity.
-- It never changes or silences anything.
-- Useful for finding what separates mission types and game modes.

local MissionProbe = {}

local log = function() end -- No-op unless a real logger is passed to MissionProbe.init.

local last_mission_name = nil
local failed = false -- Set after an error, so a broken lookup is reported once and not every tick.

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

-- Logs the current mission once each time its name changes, including the hub.
-- Defined once, so the per-frame pcall below creates no new function.
local function check_mission()
	local mission_manager = Managers.state and Managers.state.mission
	local mission_name = mission_manager and mission_manager:mission_name() or nil

	if mission_name == last_mission_name then
		return
	end

	last_mission_name = mission_name

	if not mission_name then
		return
	end

	local mission = mission_manager:mission()

	log(string.format("[mission] name=%s type=%s | %s",
		mission_name, tostring(mission and mission.mission_type), mission and describe(mission) or "no template"))
end

-- Call from the main mod file's mod.update.
-- Managers.state.mission does not exist before a level is loaded, so nothing is logged until it does.
function MissionProbe.update()
	if failed then
		return
	end

	local ok, err = pcall(check_mission)

	if not ok then
		failed = true
		log(string.format("[mission] probe failed: %s", tostring(err)))
	end
end

return MissionProbe
