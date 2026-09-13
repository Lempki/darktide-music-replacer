-- Tracks the pieces of game state relevant to music selection and resolves them into a single `resolved_context` string. Knows nothing about audio files or playback -- see library.lua for file lookup and MusicReplacer.lua for wiring it all together.
--
-- Non-obvious resolution rules (see darktide_music_replacer_briefing.md for the full investigation behind these):
--	* `music_zone`, not `music_game_state`, distinguishes the hub from a mission -- `music_game_state` settles to "mission" for both.
--	* "boss active" is the OR of two independent, loosely-correlated signals: Wwise's `music_combat == "boss"`, and an open boss_encounter_start...end window. Neither alone is reliable for every boss type, and either can get stuck independently -- a real zone change force-clears both as a recovery mechanism. BOSS_BREED_TIMEOUT_SECONDS is a time-based backstop for whatever that doesn't catch.
--	* `music_combat` flips on/off every few seconds during real combat, not just Psykhanium-style flicker. `mission_combat` holds for `combat_hold_seconds` (a mod setting) after combat quiets, so a lull doesn't drop to `mission_explore` -- entering combat stays instant.

local Context = {}

local WwiseGameSyncManager = require("scripts/managers/wwise_game_sync/wwise_game_sync_manager")

-- ###########################################################################
-- State
-- ###########################################################################

local wwise_combat_state = nil -- Current value of the "music_combat" state group.
local music_zone = nil -- Current value of the "music_zone" state group.
local active_boss_breed = nil -- Breed name while a boss encounter is open, else nil.
local active_boss_breed_age = 0 -- Seconds since active_boss_breed was last set.

local suppress_music_combat = false -- See Context.set_suppress_music_combat.

local resolved_context = nil -- Last computed context string, e.g. "hub".
local change_listeners = {}
local listeners_registered = false
local diagnostic_log = function() end -- No-op unless a real logger is passed to Context.init.

-- Generous upper bound on any real boss encounter -- a safety net against active_boss_breed getting stuck, not a design target.
local BOSS_BREED_TIMEOUT_SECONDS = 180

-- Fallback if mod:get() ever returns nil -- the real value is the combat_hold_seconds mod setting.
local COMBAT_HOLD_SECONDS_DEFAULT = 8

local combat_hold_remaining = 0 -- Seconds left before mission_combat may fall back to mission_explore.

-- ###########################################################################
-- Resolution
-- ###########################################################################

local function is_boss_active()
	return wwise_combat_state == "boss" or active_boss_breed ~= nil
end

local function is_combat_active()
	return wwise_combat_state == "normal" or wwise_combat_state == "horde_low" or wwise_combat_state == "horde_high"
end

local function resolve(mod)
	if is_boss_active() then
		return "mission_boss"
	end

	if music_zone == "hub" then
		return "hub"
	end

	if music_zone == nil then
		-- Not in the hub or a mission yet (main menu, loading, etc.).
		return nil
	end

	if is_combat_active() then
		combat_hold_remaining = mod:get("combat_hold_seconds") or COMBAT_HOLD_SECONDS_DEFAULT
		return "mission_combat"
	end

	if combat_hold_remaining > 0 then
		return "mission_combat" -- Still within the hold window since combat last went inactive.
	end

	return "mission_explore"
end

local function recompute(mod)
	local new_context = resolve(mod)

	if new_context == resolved_context then
		return
	end

	local old_context = resolved_context
	resolved_context = new_context

	for _, listener in ipairs(change_listeners) do
		local ok, err = pcall(listener, resolved_context, old_context, active_boss_breed)
		if not ok then
			mod:error("[MusicReplacer] context change listener failed: " .. tostring(err))
		end
	end
end

-- ###########################################################################
-- Public API
-- ###########################################################################

-- Register a function to be called whenever resolved_context changes: listener(new_context, old_context, boss_breed_or_nil)
function Context.on_change(listener)
	change_listeners[#change_listeners + 1] = listener
end

function Context.current()
	return resolved_context, active_boss_breed
end

-- Whether to force native music_combat back to "None" for as long as a boss encounter is open.
-- External toggle, not automatic -- the caller should only enable this once a replacement boss track is confirmed available.
-- Applied continuously, not just on the first "-> boss" transition, since music_combat can flap normal<->None all fight without ever settling on "boss".
function Context.set_suppress_music_combat(should_suppress)
	suppress_music_combat = should_suppress
end

-- Wire up the Wwise state hook.
-- Call once from the main mod file's top level. `log`, if given, receives a line for every raw music_zone/music_combat transition and boss event -- much higher volume than Context.on_change, meant for diagnosing state issues, not everyday use.
function Context.init(mod, log)
	diagnostic_log = log or diagnostic_log

	mod:hook(WwiseGameSyncManager, "_set_state", function(func, self, group_name, new_state)
		local current = self._wwise_state_group_states and self._wwise_state_group_states[group_name]
		local is_transition = current ~= new_state

		func(self, group_name, new_state) -- call original; keeps the manager's own cache coherent

		if not is_transition then
			return
		end

		if group_name == "music_combat" then
			wwise_combat_state = new_state
			diagnostic_log(string.format("[raw] music_combat: %s -> %s", tostring(current), tostring(new_state)))

			if suppress_music_combat and new_state ~= "None" then
				Wwise.set_state("music_combat", "None")
			end
		elseif group_name == "music_zone" then
			diagnostic_log(string.format("[raw] music_zone: %s -> %s", tostring(music_zone), tostring(new_state)))
			music_zone = new_state

			-- A real zone change force-clears both is_boss_active() signals (either can get stuck alone -- see top-of-file note).
			-- Safe for a real cross-zone encounter: this is our own tracked copy of wwise_combat_state, and self-corrects on the next real transition.
			-- A still-open active_boss_breed independently keeps is_boss_active() true regardless.
			wwise_combat_state = nil
			active_boss_breed = nil
			combat_hold_remaining = 0 -- A new zone starts fresh, not mid-hold from the last one.
		else
			return
		end

		recompute(mod)
	end)

	-- Managers.event:register wants a STRING method name looked up on `context`, not a function reference -- passing a function registers fine but crashes the game the moment the event fires.
	function mod.on_boss_start(self, unit, boss_extension)
		local breed = boss_extension and boss_extension._breed
		active_boss_breed = breed and breed.name or "<unknown>"
		active_boss_breed_age = 0
		diagnostic_log(string.format("[raw] boss_encounter_start breed=%s", active_boss_breed))
		recompute(mod)
	end

	function mod.on_boss_end(self, unit, boss_extension)
		diagnostic_log("[raw] boss_encounter_end")
		active_boss_breed = nil
		recompute(mod)
	end
end

-- Call from the main mod file's mod.update.
-- Managers.event doesn't exist at mod-load time, so listeners are registered lazily once it is.
-- Also advances the BOSS_BREED_TIMEOUT_SECONDS watchdog every tick.
function Context.update(mod, dt)
	if active_boss_breed then
		active_boss_breed_age = active_boss_breed_age + dt

		if active_boss_breed_age > BOSS_BREED_TIMEOUT_SECONDS then
			diagnostic_log(string.format(
				"[raw] active_boss_breed watchdog: forcing clear after %ss stuck (breed was %s)",
				BOSS_BREED_TIMEOUT_SECONDS, tostring(active_boss_breed)))
			active_boss_breed = nil
			active_boss_breed_age = 0
			recompute(mod)
		end
	end

	if combat_hold_remaining > 0 then
		combat_hold_remaining = math.max(combat_hold_remaining - dt, 0)

		if combat_hold_remaining == 0 then
			-- Also re-affirms the hold if combat is still active, since nothing else re-checks resolve() while the raw state is unchanged.
			recompute(mod)
		end
	end

	if listeners_registered then
		return
	end

	if Managers and Managers.event then
		Managers.event:register(mod, "boss_encounter_start", "on_boss_start")
		Managers.event:register(mod, "boss_encounter_end", "on_boss_end")
		listeners_registered = true
	end
end

-- Call from the main mod file's mod.on_unload.
function Context.shutdown(mod)
	if listeners_registered and Managers and Managers.event then
		Managers.event:unregister(mod, "boss_encounter_start")
		Managers.event:unregister(mod, "boss_encounter_end")
	end

	listeners_registered = false
end

return Context
