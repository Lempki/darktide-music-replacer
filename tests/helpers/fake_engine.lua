-- A fake of the engine and DMF surface the mod touches, so its modules load and run under plain LuaJIT.
-- FakeEngine.new() installs fresh globals and returns an engine object to drive the fakes and inspect what the mod did.
-- Call it at the start of every test, since the mod's modules keep their state at file level.

local FakeEngine = {}
FakeEngine.__index = FakeEngine

local MOD_NAME = "MusicReplacer"
local WWISE_GAME_SYNC_MANAGER = "scripts/managers/wwise_game_sync/wwise_game_sync_manager"

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

	local states = setmetatable({}, { __index = function() return DEFAULT_GROUP_STATE end })

	engine.wwise_game_sync = setmetatable({ _wwise_state_group_states = states }, { __index = Manager })

	return Manager
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

	function mod:get(setting_id)
		return engine.settings[setting_id]
	end

	-- Unlike DMF, a load error is raised, so a broken module fails its spec instead of returning nil.
	function mod:io_dofile(path)
		local module_path = path:gsub("^" .. MOD_NAME .. "/", "")
		local file = package.searchpath(module_path, package.path)
		assert(file, "module not found: " .. path)

		return dofile(file)
	end

	for _, level in ipairs({ "echo", "info", "warning", "error" }) do
		mod[level] = function(_, message)
			engine.messages[#engine.messages + 1] = { level = level, text = message }
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
-- * `settings`: the values mod:get() returns, by setting id.
-- * `user_settings`: the values Application.user_setting() returns, by name, such as the volume sliders.
-- * `mods`: other mods get_mod() returns, by name.
-- * `backend`: a replacement for the fake Managers.backend.
-- * `lua`: the Mods.lua table, for example `{ os = fake_os }`. Empty by default.
function FakeEngine.new(options)
	options = options or {}

	local engine = setmetatable({
		settings = options.settings or {},
		user_settings = options.user_settings or {},
		hooks = {},
		messages = {},
		event_listeners = {},
		wwise_calls = {},
		url_requests = {},
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

	-- The game's BackendManager starts with _initialized false and sets it once its backend is up.
	local backend = options.backend or { _initialized = false }
	function backend:url_request(url)
		engine.url_requests[#engine.url_requests + 1] = url
	end

	Managers = {
		state = {},
		event = new_event_manager(engine),
		backend = backend,
	}

	CLASS = {
		WwiseWorld = {
			trigger_resource_event = function() end,
		},
	}

	Application = {
		user_setting = function(_, name) return engine.user_settings[name] end,
	}

	-- Mods.lua.io and Mods.lua.os are left out by default, so no spec reaches the real file system by accident.
	Mods = { lua = options.lua or {} }

	package.loaded[WWISE_GAME_SYNC_MANAGER] = new_wwise_game_sync_manager(engine)

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

function FakeEngine:initialize_backend()
	Managers.backend._initialized = true
end

-- Removes the game's backend, as at game exit.
function FakeEngine:tear_down_backend()
	Managers.backend = nil
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
