-- Pins how volume_sessions.lua follows the sliders through each process's audio session, and leaves Windows' saved volume at 1.

local FakeEngine = require("tests.helpers.fake_engine")

-- A fake session_volume.lua. `appear(pid)` makes a process's session findable, and `exit(pid)` ends its process.
local function new_session_volume()
	local fake = { sessions = {}, findable = {}, exited = {} }

	function fake.available() return true end

	function fake.open(pid)
		if not fake.findable[pid] then
			return nil
		end

		local session = { pid = pid, volumes = {}, closed = false }
		function session.set(self, volume) self.volumes[#self.volumes + 1] = volume end
		function session.close(self) self.closed = true end
		function session.process_ended(self) return fake.exited[self.pid] == true end

		fake.sessions[pid] = session
		return session
	end

	function fake.appear(pid) fake.findable[pid] = true end
	function fake.exit(pid) fake.exited[pid] = true end

	return fake
end

-- Returns a loaded volume_sessions.lua, its fake session_volume.lua, the logged lines, and a switch for the setting.
-- Each play_file_id is "play-<pid>", so the pid follows from it.
local function load_volume_sessions()
	local engine = FakeEngine.new()
	local VolumeSessions = engine:load("volume_sessions")
	local session_volume = new_session_volume()
	local lines = {}
	local setting = { enabled = true }

	VolumeSessions.init(session_volume, function(play_file_id)
		return tonumber(play_file_id:match("%d+"))
	end, function() return setting.enabled end, function(line) lines[#lines + 1] = line end)

	return VolumeSessions, session_volume, lines, setting
end

describe("volume_sessions.lua", function()
	it("sets a found session to the scale the sliders ask for", function()
		local VolumeSessions, session_volume = load_volume_sessions()
		VolumeSessions.track("play-7", 50)
		session_volume.appear(7)
		VolumeSessions.update(0.1)

		assert_equal(VolumeSessions.set_level("play-7", 25), true)

		assert_deep_equal(session_volume.sessions[7].volumes, { 1, 0.5 })
	end)

	it("applies a level set before the session appeared once it does", function()
		local VolumeSessions, session_volume = load_volume_sessions()
		VolumeSessions.track("play-7", 40)

		assert_equal(VolumeSessions.set_level("play-7", 10), true)
		session_volume.appear(7)
		VolumeSessions.update(0.3)

		assert_deep_equal(session_volume.sessions[7].volumes, { 0.25 })
	end)

	it("asks for a relaunch above the launch level, and not for a fraction of a percent above it", function()
		local VolumeSessions, session_volume = load_volume_sessions()
		VolumeSessions.track("play-7", 21)
		session_volume.appear(7)
		VolumeSessions.update(0.1)

		assert_equal(VolumeSessions.set_level("play-7", 21.4), true)
		assert_equal(VolumeSessions.set_level("play-7", 22), false)
	end)

	it("can raise a lowered track back up to its launch level", function()
		local VolumeSessions, session_volume = load_volume_sessions()
		VolumeSessions.track("play-7", 50)
		session_volume.appear(7)
		VolumeSessions.update(0.1)

		VolumeSessions.set_level("play-7", 10)
		assert_equal(VolumeSessions.set_level("play-7", 50), true)

		assert_deep_equal(session_volume.sessions[7].volumes, { 1, 0.2, 1 })
	end)

	it("asks for a relaunch for a track whose session never appeared within 5 seconds", function()
		local VolumeSessions, _, lines = load_volume_sessions()
		VolumeSessions.track("play-7", 50)

		for _ = 1, 60 do
			VolumeSessions.update(0.1)
		end

		assert_equal(VolumeSessions.set_level("play-7", 10), false)
		assert_equal(lines[#lines]:find("no audio session within 5s", 1, true) ~= nil, true, lines[#lines])
	end)

	it("tracks nothing with the setting off, so every change asks for a relaunch", function()
		local VolumeSessions, session_volume, _, setting = load_volume_sessions()
		setting.enabled = false
		session_volume.appear(7)

		VolumeSessions.track("play-7", 50)
		VolumeSessions.update(0.3)

		assert_equal(VolumeSessions.set_level("play-7", 10), false)
		assert_equal(session_volume.sessions[7], nil)
	end)

	it("holds a stopped track's session until its process exits, then sets it back to 1 and releases it", function()
		local VolumeSessions, session_volume = load_volume_sessions()
		VolumeSessions.track("play-7", 50)
		session_volume.appear(7)
		VolumeSessions.update(0.1)
		VolumeSessions.set_level("play-7", 10)
		local session = session_volume.sessions[7]

		VolumeSessions.retire("play-7")
		VolumeSessions.update(1)

		assert_equal(session.closed, false)
		assert_deep_equal(session.volumes, { 1, 0.2 })

		session_volume.exit(7)
		VolumeSessions.update(1)

		assert_equal(session.closed, true)
		assert_deep_equal(session.volumes, { 1, 0.2, 1 })
		assert_equal(VolumeSessions.set_level("play-7", 10), false)
	end)

	it("releases the session of a track that ended on its own", function()
		local VolumeSessions, session_volume = load_volume_sessions()
		VolumeSessions.track("play-7", 50)
		session_volume.appear(7)
		VolumeSessions.update(0.1)
		local session = session_volume.sessions[7]

		session_volume.exit(7)
		VolumeSessions.update(0.5)
		VolumeSessions.update(0.5)

		assert_equal(session.closed, true)
		assert_equal(session.volumes[#session.volumes], 1)
	end)

	it("releases every session at shutdown, setting back only those whose process has exited", function()
		local VolumeSessions, session_volume = load_volume_sessions()
		for _, pid in ipairs({ 7, 8 }) do
			VolumeSessions.track("play-" .. pid, 50)
			session_volume.appear(pid)
		end
		VolumeSessions.update(0.1)
		VolumeSessions.set_level("play-7", 10)
		VolumeSessions.set_level("play-8", 10)
		session_volume.exit(7)

		VolumeSessions.shutdown()

		assert_equal(session_volume.sessions[7].closed, true)
		assert_equal(session_volume.sessions[8].closed, true)
		assert_deep_equal(session_volume.sessions[7].volumes, { 1, 0.2, 1 })
		assert_deep_equal(session_volume.sessions[8].volumes, { 1, 0.2 })
	end)
end)
