-- Pins the context catalog against the places that cannot read it, and its own consistency.

local FakeEngine = require("tests.helpers.fake_engine")

local function load_contexts()
	return FakeEngine.new():load("contexts")
end

describe("contexts.lua", function()
	it("lists the same audio folders as tools/build.ps1 puts in the release zip, in the same order", function()
		local Contexts = load_contexts()
		local folders = {}
		for _, context in ipairs(Contexts.list) do
			if context.folder then
				folders[#folders + 1] = context.id
			end
		end

		local file = assert(io.open("tools/build.ps1", "r"))
		local script = file:read("*a")
		file:close()
		local list = assert(script:match("%$AudioContexts = @%(([^)]*)%)"), "no $AudioContexts list in tools/build.ps1")
		local built = {}
		for name in list:gmatch("'([^']+)'") do
			built[#built + 1] = name
		end

		assert_deep_equal(built, folders)
	end)

	it("names every context once, and finds each by its name", function()
		local Contexts = load_contexts()
		local seen = {}

		for _, context in ipairs(Contexts.list) do
			assert_equal(seen[context.id], nil, "listed twice: " .. context.id)
			seen[context.id] = true
			assert_equal(Contexts.get(context.id), context)
		end

		assert_equal(Contexts.get("not_a_context"), nil)
		assert_equal(Contexts.get(nil), nil)
	end)

	it("ranks every context that resumes, since the resume rules compare ranks", function()
		for _, context in ipairs(load_contexts().list) do
			if context.resume then
				assert_equal(type(context.priority), "number", "no priority for " .. context.id)
			end
		end
	end)
end)
