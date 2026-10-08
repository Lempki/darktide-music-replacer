-- Checks the runner's own assertions.

local function fails(body)
	return not pcall(body)
end

describe("assert_equal", function()
	it("passes on equal values", function()
		assert_equal(1, 1)
		assert_equal("hub", "hub")
		assert_equal(nil, nil)
	end)

	it("fails on different values", function()
		assert_equal(fails(function() assert_equal(1, 2) end), true)
		assert_equal(fails(function() assert_equal("1", 1) end), true)
		assert_equal(fails(function() assert_equal(nil, false) end), true)
	end)
end)

describe("assert_deep_equal", function()
	it("passes on tables with the same contents", function()
		assert_deep_equal({ 1, { a = "b" } }, { 1, { a = "b" } })
	end)

	it("fails on a missing, extra, or different key", function()
		assert_equal(fails(function() assert_deep_equal({ 1 }, { 1, 2 }) end), true)
		assert_equal(fails(function() assert_deep_equal({ 1, 2 }, { 1 }) end), true)
		assert_equal(fails(function() assert_deep_equal({ a = { b = 1 } }, { a = { b = 2 } }) end), true)
	end)

	it("names the path of the first difference", function()
		local _, err = pcall(assert_deep_equal, { a = { b = 1 } }, { a = { b = 2 } })
		assert_equal(err:find('value["a"]["b"]', 1, true) ~= nil, true, err)
	end)
end)
