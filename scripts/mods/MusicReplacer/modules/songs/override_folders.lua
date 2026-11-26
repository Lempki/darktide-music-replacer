-- Ranks a situation's override folders against what the game reports now.
-- A folder's name is one condition, such as "chaos_spawn", or several joined by "+", such as "chaos_spawn+havoc".
-- A folder applies while every one of its conditions holds.
-- A folder with more conditions wins over one with fewer.
-- Between folders with as many conditions, their conditions are compared one by one from the most specific, and the more specific one wins.
-- So "chaos_spawn+spillway" wins over "chaos_spawn+havoc", since a mission's code is more specific than a game mode.

local OverrideFolders = {}

local SEPARATOR = "+"

-- The ranks of `name`'s conditions, most specific first, from `rank_of`, which maps each condition that holds to its rank.
-- Nil when a condition does not hold, or when the name has an empty or repeated condition, as "chaos_spawn++havoc" or "havoc+havoc" do.
local function ranks_of(name, rank_of)
	local ranks = {}
	local seen = {}
	local start = 1

	while start <= #name + 1 do
		local stop = name:find(SEPARATOR, start, true) or #name + 1
		local condition = name:sub(start, stop - 1)
		local rank = rank_of[condition]
		if condition == "" or seen[condition] or not rank then
			return nil
		end

		seen[condition] = true
		ranks[#ranks + 1] = rank
		start = stop + 1
	end

	table.sort(ranks)
	return ranks
end

-- True when the folder with `ranks` wins over the one with `other_ranks`.
local function wins_over(ranks, other_ranks)
	if #ranks ~= #other_ranks then
		return #ranks > #other_ranks
	end

	for index = 1, #ranks do
		if ranks[index] ~= other_ranks[index] then
			return ranks[index] < other_ranks[index]
		end
	end
	return false
end

-- The names in `names` that apply now, best first.
-- `names` are the override folders' names in lowercase, and `keys` are the conditions that hold now, most specific first.
function OverrideFolders.matching(names, keys)
	local rank_of = {}
	for index, key in ipairs(keys) do
		local condition = key:lower()
		if not rank_of[condition] then
			rank_of[condition] = index
		end
	end

	local matches = {}
	for _, name in ipairs(names) do
		local ranks = ranks_of(name, rank_of)
		if ranks then
			matches[#matches + 1] = { name = name, ranks = ranks }
		end
	end

	table.sort(matches, function(first, second)
		return wins_over(first.ranks, second.ranks)
	end)

	local ordered = {}
	for index, match in ipairs(matches) do
		ordered[index] = match.name
	end
	return ordered
end

return OverrideFolders
