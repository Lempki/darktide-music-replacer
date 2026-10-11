-- Checks that mission_probe.lua logs each mission once.

local FakeEngine = require("tests.helpers.fake_engine")

describe("mission_probe.lua", function()
	it("logs a mission once when its name changes, and nothing while no level is loaded", function()
		local engine = FakeEngine.new()
		local MissionProbe = engine:load("mission_probe")
		local lines = {}
		MissionProbe.init(function(line) lines[#lines + 1] = line end)

		MissionProbe.update()
		engine:set_mission("hub_ship")
		MissionProbe.update()
		MissionProbe.update()
		engine:set_mission(nil)
		MissionProbe.update()
		engine:set_mission("lm_cooling")
		MissionProbe.update()

		assert_equal(#lines, 2, table.concat(lines, "\n"))
		assert_equal(lines[1]:find("[mission] name=hub_ship", 1, true), 1)
		assert_equal(lines[2]:find("[mission] name=lm_cooling", 1, true), 1)
	end)
end)
