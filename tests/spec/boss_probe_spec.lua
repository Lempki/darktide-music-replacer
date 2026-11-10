-- Checks that boss_probe.lua logs each boss's arrival, target changes, first damage, and departure once, from what the game reports.
-- The game is stood in for by a reader, since the probe's game reads need a running level.

local FakeEngine = require("tests.helpers.fake_engine")

-- Returns the probe, its log lines, how often it asked for minion sounds, and a table whose `bosses` the reader returns.
local function new_probe()
	local BossProbe = FakeEngine.new():load("boss_probe")
	local lines = {}
	local world = { bosses = {}, arrivals = 0 }
	BossProbe.init(function(line) lines[#lines + 1] = line end, {
		read = function() return world.bosses end,
		on_arrival = function() world.arrivals = world.arrivals + 1 end,
	})
	return BossProbe, lines, world
end

local function spawn(unit)
	return { unit = unit, breed = "chaos_spawn", kind = "monster", weakened = false, damaged = false, distance = 60, target = "nobody" }
end

describe("boss_probe.lua", function()
	it("logs a boss's arrival, its target, its first damage, and its departure, each once", function()
		local BossProbe, lines, world = new_probe()
		local boss = spawn("unit_a")
		world.bosses = { boss }

		BossProbe.update(0.25)
		BossProbe.update(0.25)
		boss.target = "you"
		boss.distance = 20
		BossProbe.update(0.25)
		boss.damaged = true
		BossProbe.update(0.25)
		BossProbe.update(0.25)
		world.bosses = {}
		BossProbe.update(0.25)

		assert_deep_equal(lines, {
			"[boss] #1 chaos_spawn appeared: monster, 60 m away, targets nobody",
			"[boss] #1 chaos_spawn targets you, 20 m away, 0.5s after it appeared",
			"[boss] #1 chaos_spawn first damaged, 20 m away, 0.8s after it appeared",
			"[boss] #1 chaos_spawn gone after 1.0s, it had targeted someone",
		})
		assert_equal(world.arrivals, 2)
	end)

	it("reads the game only a few times a second", function()
		local BossProbe, lines, world = new_probe()
		world.bosses = { spawn("unit_a") }

		BossProbe.update(0.25)
		world.bosses = {}
		BossProbe.update(0.1)

		assert_equal(#lines, 1)
	end)

	it("keeps its bosses while the game has nothing to read, as on a loading screen", function()
		local BossProbe, lines, world = new_probe()
		world.bosses = { spawn("unit_a") }
		BossProbe.update(0.25)

		world.bosses = nil
		BossProbe.update(0.25)

		assert_equal(#lines, 1)
	end)

	it("logs a failure to read the game once, and keeps trying", function()
		local BossProbe, lines = new_probe()
		local calls = 0
		BossProbe.init(function(line) lines[#lines + 1] = line end, {
			read = function()
				calls = calls + 1
				error("no side system", 0)
			end,
		})

		BossProbe.update(0.25)
		BossProbe.update(0.25)

		assert_deep_equal(lines, { "[boss] could not read the bosses: no side system" })
		assert_equal(calls, 2)
	end)
end)
