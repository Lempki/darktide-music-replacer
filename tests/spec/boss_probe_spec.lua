-- Checks that boss_probe.lua logs each boss's arrival, target changes, and departure once, from the bosses it is given.

local FakeEngine = require("tests.helpers.fake_engine")

-- Returns the probe and its log lines.
local function new_probe()
	local BossProbe = FakeEngine.new():load("boss_probe")
	local lines = {}
	BossProbe.init(function(line) lines[#lines + 1] = line end)
	return BossProbe, lines
end

local function spawn(unit)
	return { unit = unit, breed = "chaos_spawn", kind = "monster", weakened = false, distance = 60, target = "nobody" }
end

describe("boss_probe.lua", function()
	it("logs a boss's arrival, its target, and its departure, each once", function()
		local BossProbe, lines = new_probe()
		local boss = spawn("unit_a")

		BossProbe.observe({ boss }, 0.25)
		BossProbe.observe({ boss }, 0.25)
		boss.target = "you"
		boss.distance = 20
		BossProbe.observe({ boss }, 0.25)
		BossProbe.observe({ boss }, 0.25)
		BossProbe.observe({}, 0.25)

		assert_deep_equal(lines, {
			"[boss] #1 chaos_spawn appeared: monster, 60 m away, targets nobody",
			"[boss] #1 chaos_spawn targets you, 20 m away, 0.5s after it appeared",
			"[boss] #1 chaos_spawn gone after 0.8s, it had targeted someone",
		})
	end)

	it("names a weakened boss and a distance the engine refused", function()
		local BossProbe, lines = new_probe()
		local boss = spawn("unit_a")
		boss.weakened = true
		boss.distance = nil

		BossProbe.observe({ boss }, 0.25)

		assert_deep_equal(lines, { "[boss] #1 chaos_spawn appeared: monster, weakened, distance unknown, targets nobody" })
	end)
end)
