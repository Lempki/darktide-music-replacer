-- Pins what session_probe.lua logs about the playing track's Windows audio session, and that it only reads.

local FakeEngine = require("tests.helpers.fake_engine")

-- A fake session_volume.lua whose sessions are `volumes`, pid -> volume, and which fails setup when `setup_error` is given.
local function new_session_volume(volumes, setup_error)
	local fake = { lookups = 0 }

	function fake.available() return setup_error == nil end
	function fake.error() return setup_error end
	function fake.get(pid)
		fake.lookups = fake.lookups + 1
		return volumes[pid]
	end
	function fake.set() error("the probe must never set a volume") end

	return fake
end

-- Returns a loaded session_probe.lua, the lines it logged, and the fake session_volume.lua.
local function load_probe(volumes, options)
	options = options or {}
	local engine = FakeEngine.new({ settings = { diagnostic_mode = options.diagnostic_mode ~= false } })
	local SessionProbe = engine:load("session_probe")
	local session_volume = new_session_volume(volumes, options.setup_error)
	local lines = {}
	SessionProbe.init(engine.mod, session_volume, function(line) lines[#lines + 1] = line end)

	return SessionProbe, lines, session_volume
end

describe("session_probe.lua", function()
	it("reports that Core Audio is available, then logs a new pid's session volume once", function()
		local SessionProbe, lines = load_probe({ [42] = 0.8 })

		for _ = 1, 20 do
			SessionProbe.update(0.1, 42)
		end

		assert_equal(#lines, 2)
		assert_equal(lines[1], "[session] Core Audio is available")
		assert_equal(lines[2]:find("[session] pid 42: session volume 0.80", 1, true) ~= nil, true, lines[2])
	end)

	it("keeps looking for a session that appears late", function()
		local volumes = {}
		local SessionProbe, lines, session_volume = load_probe(volumes)

		SessionProbe.update(0.1, 42)
		SessionProbe.update(0.3, 42)
		volumes[42] = 1
		SessionProbe.update(0.3, 42)

		assert_equal(session_volume.lookups, 3)
		assert_equal(lines[#lines]:find("session volume 1.00, found 0.70s after the pid arrived", 1, true) ~= nil, true, lines[#lines])
	end)

	it("gives up on a pid with no session after 5 seconds", function()
		local SessionProbe, lines, session_volume = load_probe({})

		for _ = 1, 100 do
			SessionProbe.update(0.1, 42)
		end

		assert_equal(lines[#lines]:find("[session] pid 42: no audio session found within 5s", 1, true) ~= nil, true, lines[#lines])
		assert_equal(session_volume.lookups <= 21, true, tostring(session_volume.lookups))
	end)

	it("probes again for the next track's pid", function()
		local SessionProbe, lines = load_probe({ [42] = 0.8, [43] = 0.5 })

		SessionProbe.update(0.1, 42)
		SessionProbe.update(0.1, nil)
		SessionProbe.update(0.1, 43)

		assert_equal(lines[#lines]:find("[session] pid 43: session volume 0.50", 1, true) ~= nil, true, lines[#lines])
	end)

	it("logs why Core Audio is unavailable, once, and looks nothing up", function()
		local SessionProbe, lines, session_volume = load_probe({ [42] = 1 }, { setup_error = "ffi is not available" })

		for _ = 1, 10 do
			SessionProbe.update(0.1, 42)
		end

		assert_deep_equal(lines, { "[session] Core Audio is unavailable: ffi is not available" })
		assert_equal(session_volume.lookups, 0)
	end)

	it("does nothing while Diagnostic Logging is off", function()
		local SessionProbe, lines, session_volume = load_probe({ [42] = 1 }, { diagnostic_mode = false })

		for _ = 1, 10 do
			SessionProbe.update(0.1, 42)
		end

		assert_deep_equal(lines, {})
		assert_equal(session_volume.lookups, 0)
	end)
end)
