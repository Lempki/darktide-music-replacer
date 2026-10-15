-- Drives context.lua through the fake engine and records every context it resolves.
-- The sequence methods set the music states in the order the game sets them, so the specs exercise real transitions.
-- Time only passes through wait() and tick(), in steps no longer than one game frame.

local FakeEngine = require("tests.helpers.fake_engine")

local Harness = {}
Harness.__index = Harness

-- The defaults of the mod's own settings.
local DEFAULT_SETTINGS = { combat_hold_seconds = 8, horde_hold_seconds = 3, meat_grinder_music = false, daemonhost_boss_music = false, captain_boss_music = false }

local FRAME_SECONDS = 0.1

-- Settings not given fall back to the mod's defaults.
function Harness.new(settings)
	local merged = {}
	for key, value in pairs(DEFAULT_SETTINGS) do
		merged[key] = value
	end
	for key, value in pairs(settings or {}) do
		merged[key] = value
	end

	local engine = FakeEngine.new({ settings = merged })
	local Context = engine:load("context")
	Context.init(engine.mod)

	local harness = setmetatable({ engine = engine, Context = Context, changes = {}, settings = merged }, Harness)

	Context.on_change(function(new_context)
		harness.changes[#harness.changes + 1] = tostring(new_context)
	end)

	-- The first update registers the boss event callbacks, as in the game.
	harness:tick(0)

	return harness
end

-- ###########################################################################
-- Single steps
-- ###########################################################################

function Harness:current()
	return (self.Context.current())
end

function Harness:state(group_name, value)
	self.engine:set_state(group_name, value)
end

function Harness:tick(dt)
	self.Context.update(self.engine.mod, dt)
end

function Harness:wait(seconds)
	local remaining = seconds
	while remaining > 1e-9 do
		local step = math.min(FRAME_SECONDS, remaining)
		self:tick(step)
		remaining = remaining - step
	end
end

-- Sets the mission name and lets an update read it, or removes the mission manager when the name is nil.
-- As in the game, the hub_ship template is the hub, and an op_ mission is an Operation.
function Harness:mission(name)
	local fields = nil
	if name == "hub_ship" then
		fields = { is_hub = true }
	elseif name and name:find("^op_") then
		fields = { mission_type = "operations" }
	end

	self.engine:set_mission(name, fields)
	self:tick(0)
end

-- Changes a setting and re-resolves, as the mod does from on_setting_changed.
function Harness:set_setting(setting_id, value)
	self.settings[setting_id] = value
	self.Context.refresh(self.engine.mod)
end

-- Returns a new fake boss unit for boss_start() and boss_end().
function Harness:new_boss(breed_name)
	return { extension = { _breed = { name = breed_name } } }
end

function Harness:boss_start(boss)
	self.engine:fire_event("boss_encounter_start", boss, boss.extension)
end

function Harness:boss_end(boss)
	self.engine:fire_event("boss_encounter_end", boss, boss.extension)
end

-- Forgets the contexts recorded so far, so a spec can check only what follows.
function Harness:clear_changes()
	self.changes = {}
end

-- ###########################################################################
-- Sequences in the game's order
-- ###########################################################################

-- First launch: title, main menu, loading, then the hub zone and the hub_ship mission.
function Harness:cold_start_to_hub()
	self:state("music_game_state", "title")
	self:state("music_game_state", "main_menu")
	self:state("music_game_state", "loading")
	self:wait(30)
	self:state("music_zone", "hub")
	self:mission("hub_ship")
	self:wait(10)
	self:state("music_game_state", "mission")
end

-- Uses the mission board, then leaves the hub for a loading screen.
-- The zone goes to "None" one step before the game state goes to loading.
function Harness:leave_hub()
	self:state("music_game_state", "mission_board")
	self:wait(5)
	self:state("music_game_state", "mission")
	self:state("music_game_state", "mission_ready")
	self:wait(2)
	self:state("music_game_state", "mission")
	self:state("music_zone", "None")
	self:state("music_game_state", "loading")
	self:mission(nil)
end

-- Loadout, briefing, intro, then the mission itself.
-- A zone, when given, arrives during the briefing together with the mission name.
-- A zoneless mission gets its name during the briefing and keeps the zone at "None".
function Harness:enter_mission(name, zone)
	self:wait(1)
	self:state("music_game_state", "loadout")
	self:wait(50)
	self:state("music_game_state", "loading")
	self:state("music_game_state", "mission_briefing")
	self:wait(30)
	if zone then
		self:state("music_zone", zone)
	end
	self:mission(name)
	self:wait(7)
	self:state("music_game_state", "mission_intro")
	self:wait(5)
	self:state("music_game_state", "mission")
end

-- Victory, the transient return to "mission", the score screen, then the loading screen.
-- A zoneless mission has no zone line here.
function Harness:end_with_victory(zone)
	self:state("music_game_state", "victory")
	self:wait(7)
	self:state("music_game_state", "mission")
	if zone then
		self:state("music_zone", "None")
	end
	self:state("music_game_state", "game_score_win")
	self:wait(39)
	self:state("music_game_state", "None")
	self:state("music_game_state", "loading")
	self:mission(nil)
end

-- Defeat, the transient return to "mission", the score screen, then the loading screen.
function Harness:end_with_defeat()
	self:state("music_game_state", "defeat")
	self:wait(7)
	self:state("music_game_state", "mission")
	self:state("music_zone", "None")
	self:state("music_game_state", "game_score_lose")
	self:wait(35)
	self:state("music_game_state", "None")
	self:state("music_game_state", "loading")
	self:mission(nil)
end

-- The loading screen ends in the hub.
function Harness:arrive_in_hub()
	self:wait(9)
	self:state("music_zone", "hub")
	self:mission("hub_ship")
	self:wait(10)
	self:state("music_game_state", "mission")
end

-- A debrief cutscene after the loading screen, with the hub zone arriving partway through.
function Harness:debrief_cutscene_to_hub()
	self:state("music_game_state", "cinematic")
	self:wait(10)
	self:state("music_zone", "hub")
	self:mission("hub_ship")
	self:wait(45)
	self:state("music_game_state", "mission")
end

return Harness
