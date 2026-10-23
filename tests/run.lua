-- A minimal spec runner, so the tests need nothing but LuaJIT.
-- Usage: luajit tests/run.lua [spec files...]
-- With no arguments it runs every *_spec.lua under tests/spec.
-- Exits with 1 when any spec fails, or when it finds no spec to run.

-- The repository root is the folder above this script's own, wherever it is run from.
local REPO_ROOT = (arg[0]:match("^(.*)[/\\][^/\\]*$") or ".") .. "/.."

package.path = REPO_ROOT .. "/?.lua;" .. package.path

local IS_WINDOWS = package.config:sub(1, 1) == "\\"

-- ###########################################################################
-- Assertions
-- ###########################################################################

local function show(value)
	if type(value) == "string" then
		return string.format("%q", value)
	end

	return tostring(value)
end

function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(string.format("%sexpected %s, got %s", message and message .. ": " or "", show(expected), show(actual)), 2)
	end
end

-- Describes the first difference between two values and where it is, or returns nil when they are deeply equal.
local function find_difference(actual, expected, path)
	if type(actual) ~= "table" or type(expected) ~= "table" then
		if actual ~= expected then
			return string.format("at %s: expected %s, got %s", path, show(expected), show(actual))
		end

		return nil
	end

	for key, value in pairs(expected) do
		local difference = find_difference(actual[key], value, path .. "[" .. show(key) .. "]")
		if difference then
			return difference
		end
	end

	for key, value in pairs(actual) do
		if expected[key] == nil then
			return string.format("at %s[%s]: expected nil, got %s", path, show(key), show(value))
		end
	end

	return nil
end

function assert_deep_equal(actual, expected, message)
	local difference = find_difference(actual, expected, "value")
	if difference then
		error((message and message .. ": " or "") .. difference, 2)
	end
end

-- ###########################################################################
-- Registration
-- ###########################################################################

local tests = {}
local describe_stack = {}

function describe(name, body)
	describe_stack[#describe_stack + 1] = name
	body()
	describe_stack[#describe_stack] = nil
end

function it(name, body)
	local full_name = table.concat(describe_stack, " ") .. " " .. name
	tests[#tests + 1] = { name = full_name, body = body }
end

-- ###########################################################################
-- Discovery and running
-- ###########################################################################

-- Both commands list the specs in name order, so every system runs them in the same order.
local function find_spec_files()
	local spec_dir = REPO_ROOT .. "/tests/spec"
	local command = IS_WINDOWS
		and string.format('dir /b /s /o:n "%s\\*_spec.lua" 2>nul', spec_dir:gsub("/", "\\"))
		or string.format('find "%s" -name "*_spec.lua" | sort', spec_dir)

	local files = {}
	local pipe = io.popen(command)
	for line in pipe:lines() do
		files[#files + 1] = line
	end
	pipe:close()

	return files
end

local spec_files = #arg > 0 and { unpack(arg) } or find_spec_files()
local failures = 0
local test_count = 0

for _, file in ipairs(spec_files) do
	tests = {}
	local ok, err = pcall(dofile, file)

	-- A file that fails to load counts as one failure, and the tests it registered before the error still run.
	if not ok then
		failures = failures + 1
		print(string.format("FAIL %s (load error)\n     %s", file, tostring(err)))
	end

	for _, test in ipairs(tests) do
		test_count = test_count + 1
		local passed, test_err = pcall(test.body)

		if passed then
			print("ok   " .. test.name)
		else
			failures = failures + 1
			print(string.format("FAIL %s\n     %s", test.name, tostring(test_err)))
		end
	end
end

print(string.format("\n%d spec file(s), %d test(s), %d failure(s)", #spec_files, test_count, failures))

-- Finding nothing means the search went wrong, which must not pass as a green run.
if test_count == 0 then
	print("No specs were found to run.")
	os.exit(1)
end

os.exit(failures == 0 and 0 or 1)
