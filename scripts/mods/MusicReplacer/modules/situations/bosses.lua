-- Reads the bosses alive in the level a few times a second: each one's breed, kind, distance from the player, and target.
-- It knows nothing about music, and only reports what the game sends to every player.
-- Enemy AI runs on the server, so that is the alive enemies, their boss extension, and their target.

local Bosses = {}

-- The bosses are read a few times a second, which is often enough to order arrivals and follow distances.
local POLL_SECONDS = 0.25

-- The tags the game gives its bosses, in the order that names a boss's kind when it has several.
-- A daemonhost is a witch and a monster at once, and the game's boss music leaves witches out.
local BOSS_TAGS = { "witch", "lord", "captain", "cultist_captain", "monster" }

local log = function() end -- It does nothing unless Bosses.init is given a real logger.
local read_bosses -- Reads the game, as set below, or stands in for it in the specs.

local poll_seconds_left = 0
local reported_failures = {} -- Error text -> true, so a failure that repeats every poll is logged once.

-- ###########################################################################
-- Reading the game
-- ###########################################################################

local function breed_name(unit)
	local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
	local breed = unit_data_extension and unit_data_extension:breed()
	return breed and breed.name or "unknown"
end

-- Who `target_unit` is, as the log names it. Players are never named, since logs are shared in bug reports.
local function describe_target(target_unit, player_unit)
	if target_unit == player_unit then
		return "you"
	end

	local player_unit_spawn = Managers.state.player_unit_spawn
	local owner = player_unit_spawn and player_unit_spawn:owner(target_unit)
	if owner then
		return owner:is_human_controlled() and "a teammate" or "a bot"
	end

	return breed_name(target_unit)
end

-- The boss's target, as the game syncs it to every player: "nobody", someone, or "unknown" for a boss with no such field.
local function read_target(unit, player_unit)
	local unit_spawner = Managers.state.unit_spawner
	local game_session = Managers.state.game_session and Managers.state.game_session:game_session()
	local game_object_id = unit_spawner and game_session and unit_spawner:game_object_id(unit)
	if not game_object_id or not GameSession.has_game_object_field(game_session, game_object_id, "target_unit_id") then
		return "unknown"
	end

	local target_id = GameSession.game_object_field(game_session, game_object_id, "target_unit_id")
	if not target_id or target_id == NetworkConstants.invalid_game_object_id then
		return "nobody"
	end

	local target_unit = unit_spawner:unit(target_id)
	return target_unit and describe_target(target_unit, player_unit) or "unknown"
end

-- The distance between two positions, or nil when the engine refuses one, so the rest of the boss still gets read.
local function measure_distance(from, to)
	local ok, distance = pcall(Vector3.distance, from, to)
	return ok and distance or nil
end

-- Every boss alive now, or nil while the player has no unit to measure from, as on a loading screen.
local function read_bosses_from_game()
	-- The level comes first, since asking for the local player before the network is up crashes the game, as on the title screen.
	-- That crash happens in the engine, so the pcall around this reader cannot catch it.
	local extension_manager = Managers.state and Managers.state.extension
	if not extension_manager or not extension_manager:has_system("side_system") then
		return nil
	end

	local player = Managers.player and Managers.player:local_player(1)
	local player_unit = player and player.player_unit
	if not player_unit then
		return nil
	end

	local side = extension_manager:system("side_system").side_by_unit[player_unit]
	if not side then
		return nil
	end

	local bosses = {}
	local listed = {}
	-- POSITION_LOOKUP holds vectors that only stay valid within the game's own update, so the mod asks each unit for its position.
	local player_position = Unit.world_position(player_unit, 1)

	for _, tag in ipairs(BOSS_TAGS) do
		local units = side:alive_units_by_tag("enemy", tag)
		for index = 1, units.size do
			local unit = units[index]
			if not listed[unit] then
				listed[unit] = true

				local boss_extension = ScriptUnit.has_extension(unit, "boss_system")
				local position = Unit.world_position(unit, 1)
				bosses[#bosses + 1] = {
					unit = unit,
					breed = breed_name(unit),
					kind = tag,
					weakened = boss_extension and boss_extension:is_weakened() == true or false,
					distance = measure_distance(position, player_position),
					target = read_target(unit, player_unit),
				}
			end
		end
	end

	return bosses
end

read_bosses = read_bosses_from_game

-- ###########################################################################
-- Public API
-- ###########################################################################

-- Call once from the main mod file's top level.
-- `options.read()`, if given, stands in for the game in the specs.
function Bosses.init(logger, options)
	log = logger or log
	options = options or {}
	read_bosses = options.read or read_bosses_from_game
end

-- Call every update.
-- Returns the bosses alive now and the seconds since the last read, each time it reads them, else nil.
-- Each boss is { unit, breed, kind, weakened, distance, target }, with a nil distance when the engine refused to measure it.
-- It also returns nil while there is nothing to read, as on a loading screen.
-- A failure to read the game is logged once for each kind, and it tries again at the next read.
function Bosses.update(dt)
	poll_seconds_left = poll_seconds_left - dt
	if poll_seconds_left > 0 then
		return nil
	end
	local elapsed = POLL_SECONDS - poll_seconds_left
	poll_seconds_left = POLL_SECONDS

	local ok, bosses = pcall(read_bosses)
	if not ok then
		local text = tostring(bosses)
		if not reported_failures[text] then
			reported_failures[text] = true
			log("[boss] could not read the bosses: " .. text)
		end
		return nil
	end

	if not bosses then
		return nil
	end
	return bosses, elapsed
end

return Bosses
