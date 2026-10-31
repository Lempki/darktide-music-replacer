-- A fake of the engine and DMF surface the mod touches, so its modules load and run under plain LuaJIT.
-- FakeEngine.new() installs fresh globals and returns an engine object to drive the fakes and inspect what the mod did.
-- Call it at the start of every test, since the mod's modules keep their state at file level.

local FakeEngine = {}
FakeEngine.__index = FakeEngine

local MOD_NAME = "MusicReplacer"
local WWISE_GAME_SYNC_MANAGER = "scripts/managers/wwise_game_sync/wwise_game_sync_manager"
local WWISE_STATE_GROUP_COMBAT = "scripts/managers/wwise_game_sync/wwise_state_groups/wwise_state_group_combat"
local MISSION_TEMPLATES = "scripts/settings/mission/mission_templates"

-- Every Wwise state group starts at this value in the game.
local DEFAULT_GROUP_STATE = "None"

-- Matches the game's WwiseGameSyncManager._set_state, which ignores a repeat of the current state.
local function new_wwise_game_sync_manager(engine)
	local Manager = {}

	function Manager._set_state(self, group_name, new_state)
		if self._wwise_state_group_states[group_name] ~= new_state then
			self._wwise_state_group_states[group_name] = new_state
			Wwise.set_state(group_name, new_state)
		end
	end

	-- The game calls it as a level ends. Here it only gives the mod's hook something to run after.
	function Manager.on_gameplay_shutdown() end

	local states = setmetatable({}, { __index = function() return DEFAULT_GROUP_STATE end })

	engine.wwise_game_sync = setmetatable({ _wwise_state_group_states = states }, { __index = Manager })

	return Manager
end

-- Each widget's default from MusicReplacer_data.lua, by setting ID, read once per engine.
local function widget_defaults(engine)
	if not engine.defaults then
		engine.defaults = {}
		local data = engine.mod:io_dofile(MOD_NAME .. "/scripts/mods/" .. MOD_NAME .. "/MusicReplacer_data")

		local function collect(widgets)
			for _, widget in ipairs(widgets or {}) do
				if widget.default_value ~= nil then
					engine.defaults[widget.setting_id] = widget.default_value
				end
				collect(widget.sub_widgets)
			end
		end
		collect(data.options.widgets)
	end
	return engine.defaults
end

local function new_mod(engine)
	local mod = { name = MOD_NAME }

	-- DMF keeps one hook per method for each mod, so a second install on the same method is an error here.
	function mod:hook(object, method, handler)
		assert(type(object) == "table", "the fake mod:hook only takes a table, not an object path")

		for _, hook in ipairs(engine.hooks) do
			if hook.object == object and hook.method == method then
				error("second hook on method " .. method, 2)
			end
		end

		local original = object[method]
		assert(type(original) == "function", "no method to hook: " .. tostring(method))

		object[method] = function(...)
			return handler(original, ...)
		end
		engine.hooks[#engine.hooks + 1] = { object = object, method = method }
	end

	-- Like DMF's, a safe hook runs after the original with the same arguments, and cannot change what the original returns.
	function mod:hook_safe(object, method, handler)
		self:hook(object, method, function(original, ...)
			local results = { original(...) }
			handler(...)
			return unpack(results)
		end)
	end

	-- DMF writes every widget's default into the settings before the mod's script runs, so a setting never set reads as its default.
	function mod:get(setting_id)
		local value = engine.settings[setting_id]
		if value == nil then
			value = widget_defaults(engine)[setting_id]
		end
		return value
	end

	-- DMF returns the string in the game's language, formatted with any arguments.
	-- The fake marks the ID and the arguments instead, so a spec can see which was asked for.
	function mod:localize(text_id, ...)
		if select("#", ...) == 0 then
			return "<" .. text_id .. ">"
		end

		local arguments = {}
		for index = 1, select("#", ...) do
			arguments[index] = tostring(select(index, ...))
		end
		return "<" .. text_id .. ": " .. table.concat(arguments, ", ") .. ">"
	end

	function mod:get_metadata(key)
		return engine.metadata[key]
	end

	-- DMF keeps these through a mod reload. Here they last as long as the engine.
	function mod:persistent_table(name)
		engine.persistent_tables[name] = engine.persistent_tables[name] or {}
		return engine.persistent_tables[name]
	end

	-- Unlike DMF, a load error is raised, so a broken module fails its spec instead of returning nil.
	-- A module named in the engine's `modules` option is returned instead of loading the real file.
	function mod:io_dofile(path)
		local stand_in = engine.modules[path:match("([^/]+)$")]
		if stand_in then
			return stand_in
		end

		local module_path = path:gsub("^" .. MOD_NAME .. "/", "")
		local file = package.searchpath(module_path, package.path)
		assert(file, "module not found: " .. path)

		return dofile(file)
	end

	-- Like DMF, formats the message with its arguments, and replaces a message that fails to format with the formatting error.
	-- notify is DMF's toast notification, which it formats the same way.
	for _, level in ipairs({ "echo", "info", "warning", "error", "notify" }) do
		mod[level] = function(_, message, ...)
			local ok, text = pcall(string.format, tostring(message), ...)
			engine.messages[#engine.messages + 1] = { level = level, text = ok and text or "(logging) string.format: " .. text }
		end
	end

	return mod
end

local function new_event_manager(engine)
	local events = {}

	function events:register(object, event_name, method_name)
		engine.event_listeners[#engine.event_listeners + 1] = { object = object, event_name = event_name, method_name = method_name }
	end

	function events:unregister(object, event_name)
		for index = #engine.event_listeners, 1, -1 do
			local listener = engine.event_listeners[index]
			if listener.object == object and listener.event_name == event_name then
				table.remove(engine.event_listeners, index)
			end
		end
	end

	return events
end

-- Options:
-- * `settings`: the values mod:get() returns, by setting ID.
-- * `user_settings`: the values Application.user_setting() returns, by name, such as the volume sliders.
-- * `mods`: other mods get_mod() returns, by name.
-- * `lua`: the Mods.lua table, for example `{ os = fake_os }`. Empty by default.
-- * `modules`: stand-ins for the mod's own modules, by file name, which mod:io_dofile() returns instead of the real ones.
-- * `metadata`: the values mod:get_metadata() returns, such as the version.
function FakeEngine.new(options)
	options = options or {}

	local engine = setmetatable({
		settings = options.settings or {},
		user_settings = options.user_settings or {},
		hooks = {},
		messages = {},
		event_listeners = {},
		wwise_calls = {},
		started_events = {},
		stopped_events = {},
		modules = options.modules or {},
		metadata = options.metadata or {},
		persistent_tables = {},
		mission_templates = {},
	}, FakeEngine)

	engine.mod = new_mod(engine)

	local mods = { [MOD_NAME] = engine.mod }
	for name, other_mod in pairs(options.mods or {}) do
		mods[name] = other_mod
	end

	get_mod = function(name)
		return mods[name]
	end

	Wwise = {
		set_state = function(group_name, state)
			engine.wwise_calls[#engine.wwise_calls + 1] = { group_name, state }
		end,
	}

	Managers = {
		state = {},
		event = new_event_manager(engine),
	}

	-- Like the engine, starting an event returns a playing ID and a source ID.
	local last_event_id = 0
	WwiseWorld = {
		trigger_resource_event = function(_, event_name)
			last_event_id = last_event_id + 1
			engine.started_events[#engine.started_events + 1] = event_name
			return last_event_id, 1000 + last_event_id
		end,
		stop_event = function(_, playing_id)
			engine.stopped_events[#engine.stopped_events + 1] = playing_id
		end,
	}

	CLASS = { WwiseWorld = WwiseWorld }

	Application = {
		user_setting = function(_, name) return engine.user_settings[name] end,
	}

	-- Mods.lua.io and Mods.lua.os are left out by default, so no spec reaches the real file system by accident.
	Mods = { lua = options.lua or {} }

	package.loaded[WWISE_GAME_SYNC_MANAGER] = new_wwise_game_sync_manager(engine)

	-- The game's combat state group class, with the one method the mod hooks.
	package.loaded[WWISE_STATE_GROUP_COMBAT] = { on_gameplay_shutdown = function() end }

	-- The game's mission templates by mission name, filled by set_mechanism_mission().
	package.loaded[MISSION_TEMPLATES] = engine.mission_templates

	return engine
end

-- Loads a fresh copy of a module from scripts/mods/MusicReplacer, the way the mod itself does.
function FakeEngine:load(module_name)
	return self.mod:io_dofile(MOD_NAME .. "/scripts/mods/" .. MOD_NAME .. "/" .. module_name)
end

-- Sets a Wwise state group the way the game does, through any hooks the mod installed.
function FakeEngine:set_state(group_name, state)
	self.wwise_game_sync:_set_state(group_name, state)
end

-- Sets a state group without going through any hook, as the game does while DMF has the mod's hooks disabled.
function FakeEngine:set_state_unseen(group_name, state)
	self.wwise_game_sync._wwise_state_group_states[group_name] = state
	Wwise.set_state(group_name, state)
end

-- Sets every listed group again to the value it already has, as the game does on every tick.
function FakeEngine:reassert_states(group_names)
	for _, group_name in ipairs(group_names) do
		self:set_state(group_name, self.wwise_game_sync._wwise_state_group_states[group_name])
	end
end

-- Returns the value Wwise last received for a state group, from the game or from the mod.
-- That is the value the player hears, while the game's own manager may still hold the real one.
function FakeEngine:wwise_state(group_name)
	for index = #self.wwise_calls, 1, -1 do
		local call = self.wwise_calls[index]
		if call[1] == group_name then
			return call[2]
		end
	end

	return DEFAULT_GROUP_STATE
end

-- Sets the current mission name, or removes the mission manager when the name is nil, as before a level loads.
-- `fields`, if given, are added to the mission template, for example `{ is_hub = true }`.
function FakeEngine:set_mission(name, fields)
	if name == nil then
		Managers.state.mission = nil
		return
	end

	local template = { name = name }
	for key, value in pairs(fields or {}) do
		template[key] = value
	end

	Managers.state.mission = {
		mission_name = function() return name end,
		mission = function() return template end,
	}
end

-- Sets the mission the game's mechanism data names, as the client learns it on the way into a mission, with its template.
-- `fields`, if given, are added to the template, as in set_mission().
function FakeEngine:set_mechanism_mission(name, fields)
	local template = { name = name }
	for key, value in pairs(fields or {}) do
		template[key] = value
	end

	self.mission_templates[name] = template
	Managers.mechanism = {
		mechanism_data = function() return { mission_name = name } end,
	}
end

-- Fires an event to every listener registered through Managers.event, which looks up the callback by method name.
function FakeEngine:fire_event(event_name, ...)
	for _, listener in ipairs(self.event_listeners) do
		if listener.event_name == event_name then
			listener.object[listener.method_name](listener.object, ...)
		end
	end
end

return FakeEngine
