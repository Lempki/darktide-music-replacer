-- Checks that bosses.lua reads the game a few times a second, and only where there is a level to read.
-- The game is stood in for by a reader, since the game reads need a running level.

local FakeEngine = require("tests.helpers.fake_engine")

-- Returns the module, its log lines, and a table whose `bosses` the reader returns.
local function new_bosses()
	local Bosses = FakeEngine.new():load("bosses")
	local lines = {}
	local world = { bosses = {} }
	Bosses.init(function(line) lines[#lines + 1] = line end, {
		read = function() return world.bosses end,
	})
	return Bosses, lines, world
end

local function spawn(unit)
	return { unit = unit, breed = "chaos_spawn", kind = "monster", weakened = false, distance = 60, target = "nobody" }
end

describe("bosses.lua", function()
	-- Asking for the local player before the network is up crashes the game, which no pcall catches.
	it("reads no player outside a level, as on the title screen", function()
		local engine = FakeEngine.new()
		local asked_for_player = false
		rawset(Managers, "player", {
			local_player = function()
				asked_for_player = true
			end,
		})
		local Bosses = engine:load("bosses")
		Bosses.init(function() end)

		assert_equal(Bosses.update(0.25), nil)
		assert_equal(asked_for_player, false)
	end)

	it("returns the bosses and the seconds since the last read", function()
		local Bosses, _, world = new_bosses()
		local boss = spawn("unit_a")
		world.bosses = { boss }

		Bosses.update(0.25)
		Bosses.update(0.2)
		local bosses, elapsed = Bosses.update(0.1)

		assert_deep_equal(bosses, { boss })
		assert_equal(math.floor(elapsed * 100 + 0.5), 30)
	end)

	it("reads the game only a few times a second", function()
		local Bosses, _, world = new_bosses()
		world.bosses = { spawn("unit_a") }

		Bosses.update(0.25)
		local bosses = Bosses.update(0.1)

		assert_equal(bosses, nil)
	end)

	it("returns nothing while the game has nothing to read, as on a loading screen", function()
		local Bosses, _, world = new_bosses()
		world.bosses = nil

		assert_equal(Bosses.update(0.25), nil)
	end)

	it("logs a failure to read the game once, and keeps trying", function()
		local Bosses, lines = new_bosses()
		local calls = 0
		Bosses.init(function(line) lines[#lines + 1] = line end, {
			read = function()
				calls = calls + 1
				error("no side system", 0)
			end,
		})

		Bosses.update(0.25)
		Bosses.update(0.25)

		assert_deep_equal(lines, { "[boss] could not read the bosses: no side system" })
		assert_equal(calls, 2)
	end)
end)
