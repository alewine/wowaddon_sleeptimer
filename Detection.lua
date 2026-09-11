--[[
	SleepTimer — Detection.lua

	Anniversary 2.5.6 exposes C_LossOfControl, so there is no hand-maintained
	spell table here and no UNIT_AURA scanning. The client reports each active
	control effect with its type, spell, icon and remaining time; this file
	filters those by category and hands the most relevant one to the display.
]]

local ST = SleepTimer

-- Categories reported by C_LossOfControl. Defaults to genuine loss of
-- control: things that take your character away from you. Root, snare,
-- silence and interrupt are real problems but you are still driving, so they
-- are off by default. Toggle with /st cat <TYPE>.
local DEFAULT_CATEGORIES = {
	STUN             = true,
	STUN_MECHANIC    = true,
	FEAR             = true,
	FEAR_MECHANIC    = true,
	CONFUSE          = true,
	CHARM            = true,
	POSSESS          = true,
	SLEEP            = true,
	HORROR           = true,
	BANISH           = true,
	SHACKLE_UNDEAD   = true,

	ROOT             = false,
	SNARE            = false,
	DAZE             = false,
	DISARM           = false,
	SILENCE          = false,
	PACIFY           = false,
	PACIFYSILENCE    = false,
	SCHOOL_INTERRUPT = false,
}

local function Categories()
	SleepTimerDB.categories = SleepTimerDB.categories or {}
	for locType, enabled in pairs(DEFAULT_CATEGORIES) do
		if SleepTimerDB.categories[locType] == nil then
			SleepTimerDB.categories[locType] = enabled
		end
	end
	return SleepTimerDB.categories
end

-- Pick the effect that keeps control away the longest. A 2s stun landing on
-- top of a 6s fear should not shorten the countdown to 2s — the question the
-- frame answers is "when do I get control back", not "what hit me last".
local function BestActiveEffect()
	if not C_LossOfControl or not C_LossOfControl.GetActiveLossOfControlData then
		return nil
	end

	local categories = Categories()
	local count = C_LossOfControl.GetActiveLossOfControlDataCount
		and C_LossOfControl.GetActiveLossOfControlDataCount() or 0

	local best, bestRemaining = nil, -1

	for index = 1, count do
		local data = C_LossOfControl.GetActiveLossOfControlData(index)
		if type(data) == "table" and categories[data.locType] then
			local remaining
			if data.timeRemaining then
				remaining = data.timeRemaining
			elseif data.startTime and data.duration and data.duration > 0 then
				remaining = (data.startTime + data.duration) - GetTime()
			end

			-- No finite duration sorts above any timed effect: it is the one
			-- that is still holding you when everything else has run out.
			local rank = remaining or math.huge

			if rank > bestRemaining then
				best, bestRemaining = data, rank
			end
		end
	end

	return best, (bestRemaining >= 0 and bestRemaining ~= math.huge) and bestRemaining or nil
end

local function Refresh()
	local data, remaining = BestActiveEffect()

	if not data then
		ST:Clear()
		return
	end

	ST:Trigger(
		data.spellID,
		data.displayText or data.spellID and tostring(data.spellID) or "Controlled",
		data.iconTexture,
		data.duration,
		remaining and (GetTime() + remaining) or nil
	)
end

ST.Refresh  = Refresh
ST.OnExpire = Refresh

function ST:GetCategories()
	return Categories()
end

function ST:SetCategory(locType, enabled)
	locType = (locType or ""):upper()
	local categories = Categories()
	if categories[locType] == nil then return nil end
	categories[locType] = enabled and true or false
	Refresh()
	return categories[locType]
end

function ST:ToggleCategory(locType)
	locType = (locType or ""):upper()
	local categories = Categories()
	if categories[locType] == nil then return nil end
	categories[locType] = not categories[locType]
	Refresh()
	return categories[locType]
end

-- ---------------------------------------------------------------- test ----

-- One representative spell per category. Names and icons are looked up from
-- the client's own spell data rather than hardcoded, so they come back
-- localised and with whatever art this build actually ships.
local SAMPLE_SPELL = {
	STUN             = 853,    -- Hammer of Justice
	STUN_MECHANIC    = 5211,   -- Bash
	FEAR             = 5782,   -- Fear
	FEAR_MECHANIC    = 5246,   -- Intimidating Shout
	CONFUSE          = 118,    -- Polymorph
	CHARM            = 605,    -- Mind Control
	POSSESS          = 1098,   -- Enslave Demon
	SLEEP            = 2637,   -- Hibernate
	HORROR           = 6789,   -- Death Coil
	BANISH           = 710,    -- Banish
	SHACKLE_UNDEAD   = 9484,   -- Shackle Undead
	ROOT             = 339,    -- Entangling Roots
	SNARE            = 116,    -- Frostbolt
	DAZE             = 1604,   -- Dazed
	DISARM           = 676,    -- Disarm
	SILENCE          = 15487,  -- Silence
	PACIFYSILENCE    = 1330,   -- Garrote - Silence
	SCHOOL_INTERRUPT = 2139,   -- Counterspell
	-- PACIFY has no clean TBC example; it falls back to the category name.
}

local function SpellInfo(spellID)
	if not spellID then return nil end

	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(spellID)
		if info then return info.name, info.iconID end
	end

	if _G.GetSpellInfo then
		local name, _, icon = _G.GetSpellInfo(spellID)
		return name, icon
	end
end

local lastTested

-- Picks from the categories that are actually switched on, so the test
-- previews what you will really see rather than always showing a sheep.
function ST:RandomTestEffect()
	local categories = Categories()

	local pool = {}
	for locType, enabled in pairs(categories) do
		if enabled then pool[#pool + 1] = locType end
	end
	if #pool == 0 then return nil end

	table.sort(pool)   -- pairs() order is undefined; keep the draw reproducible

	local locType = pool[math.random(#pool)]
	if #pool > 1 and locType == lastTested then
		-- One reroll, so repeated clicks tend to show something new.
		locType = pool[math.random(#pool)]
	end
	lastTested = locType

	local name, icon = SpellInfo(SAMPLE_SPELL[locType])
	return SAMPLE_SPELL[locType],
		name or locType,
		icon or "Interface\\Icons\\INV_Misc_QuestionMark",
		locType
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("LOSS_OF_CONTROL_ADDED")
watcher:RegisterEvent("LOSS_OF_CONTROL_UPDATE")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:SetScript("OnEvent", Refresh)
