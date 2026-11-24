-- Logs the bosses alive in the level, and never changes or silences anything.
-- It shows when each one appears, whom it targets, and when it is gone.
-- A boss's first damage is only known on the server, so the HP bar's boss_encounter_start, which context.lua logs, stands in for it.
-- The game's boss music and HP bar each follow rules of their own, so this is the evidence for following bosses more closely.
-- It logs what bosses.lua reads, so it reads nothing of its own.

local BossProbe = {}

local log_detail = function() end -- It does nothing unless BossProbe.init is given a real logger.

local tracked = {} -- Unit -> { id, breed, age, target, ever_targeted } for every boss seen and not yet gone.
local next_id = 0

-- ###########################################################################
-- Logging what changed
-- ###########################################################################

local function distance_text(boss)
	return boss.distance and string.format("%.0f m away", boss.distance) or "distance unknown"
end

-- Call with each read from Bosses.update while Detailed Logging is on.
-- Compares `bosses` with those of the read before, `elapsed` seconds ago, and logs every change.
function BossProbe.observe(bosses, elapsed)
	local present = {}

	for _, boss in ipairs(bosses) do
		present[boss.unit] = true
		local known = tracked[boss.unit]

		if not known then
			next_id = next_id + 1
			known = { id = next_id, breed = boss.breed, age = 0, target = boss.target }
			known.ever_targeted = boss.target ~= "nobody" and boss.target ~= "unknown"
			tracked[boss.unit] = known
			log_detail(string.format("[boss] #%d %s appeared: %s%s, %s, targets %s",
				known.id, boss.breed, boss.kind, boss.weakened and ", weakened" or "", distance_text(boss), boss.target))
		else
			known.age = known.age + elapsed

			if boss.target ~= known.target then
				known.target = boss.target
				if boss.target ~= "nobody" and boss.target ~= "unknown" then
					known.ever_targeted = true
				end
				log_detail(string.format("[boss] #%d %s targets %s, %s, %.1fs after it appeared",
					known.id, known.breed, boss.target, distance_text(boss), known.age))
			end
		end
	end

	for unit, known in pairs(tracked) do
		if not present[unit] then
			tracked[unit] = nil
			log_detail(string.format("[boss] #%d %s gone after %.1fs, %s",
				known.id, known.breed, known.age, known.ever_targeted and "it had targeted someone" or "it never targeted anyone"))
		end
	end
end

-- ###########################################################################
-- Public API
-- ###########################################################################

-- Call once from the main mod file's top level.
function BossProbe.init(detail_logger)
	log_detail = detail_logger or log_detail
end

return BossProbe
