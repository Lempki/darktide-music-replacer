-- Checks that mission_probe.lua logs each mission once, as context.lua reports the missions to it.

local FakeEngine = require("tests.helpers.fake_engine")

describe("mission_probe.lua", function()
	it("logs a mission once when its name changes, and nothing while no level is loaded", function()
		local engine = FakeEngine.new()
		local Context = engine:load("context")
		local MissionProbe = engine:load("mission_probe")
		local lines = {}
		MissionProbe.init(function(line) lines[#lines + 1] = line end)
		Context.init(engine.mod)
		Context.on_mission_change(MissionProbe.on_mission_change)

		Context.update(engine.mod, 0.1)
		engine:set_mission("hub_ship")
		Context.update(engine.mod, 0.1)
		Context.update(engine.mod, 0.1)
		engine:set_mission(nil)
		Context.update(engine.mod, 0.1)
		engine:set_mission("lm_cooling", { mission_type = "repair" })
		Context.update(engine.mod, 0.1)

		assert_equal(#lines, 2, table.concat(lines, "\n"))
		assert_equal(lines[1]:find("[mission] name=hub_ship", 1, true), 1)
		assert_equal(lines[2]:find("[mission] name=lm_cooling type=repair", 1, true), 1)
	end)
end)
