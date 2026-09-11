--[[
	SleepTimer — Core.lua

	Display layer. Owns the alert frame, its layout, the countdown and the
	one-second pulse. Knows nothing about auras or spells.

	Detection plugs in through:
		SleepTimer:Trigger(spellID, name, iconTexture, duration, expirationTime)
		SleepTimer:Clear()

	Proportions are fixed. Overall scale is the only size control, so the
	alert always looks the same shape and only its footprint changes.
]]

local ADDON = ...

SleepTimer = SleepTimer or {}
local ST = SleepTimer

-- ----------------------------------------------------------- constants ----

local ICON_SIZE      = 56     -- icon is square and spans the full content height
local NAME_FONT      = 18
local TIMER_FONT     = 24
local TEXT_GAP       = 12     -- space between icon and text column
local TEXT_WIDTH     = 150    -- fixed: the alert never changes size
local NAME_FONT_MIN  = 11     -- names shrink to fit rather than widening the box
local TIMER_LIFT     = 6      -- digits ride this far above the bottom edge
local BG_PADDING     = 8      -- backdrop inset around the content
local BG_ALPHA       = 0.85

local UPDATE_THROTTLE = 0.05
local PULSE_DECAY     = 0.45
local PULSE_PEAK      = 0.5

local DEFAULTS = {
	point         = "CENTER",
	relativePoint = "CENTER",
	x             = 0,
	y             = 150,
	scale         = 1.0,
	pulse         = true,

	-- options window position
	optPoint         = "CENTER",
	optRelativePoint = "CENTER",
	optX             = 0,
	optY             = 120,
}

-- --------------------------------------------------------------- state ----

local active   = nil
local editMode = false
local testing  = false

-- Forward declarations: Clear() is defined above the edit-mode section but
-- calls into it. Without these the names would compile as globals and be nil
-- at runtime — the local defined later is a different binding entirely.
local SyncOptions, ApplyInteractivity, ShowPlaceholder, Print

-- ---------------------------------------------------------------- frame ----

local frame = CreateFrame("Frame", "SleepTimerFrame", UIParent)
frame:SetPoint("CENTER")
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:RegisterForDrag("LeftButton")
frame:Hide()

ST.frame = frame

local bg = frame:CreateTexture(nil, "BACKGROUND")
bg:SetPoint("TOPLEFT", -BG_PADDING, BG_PADDING)
bg:SetPoint("BOTTOMRIGHT", BG_PADDING, -BG_PADDING)
bg:SetColorTexture(0, 0, 0, 1)
bg:SetAlpha(BG_ALPHA)

-- Pulse rides on top of the backdrop rather than modulating it, so the icon
-- and text keep a constant opacity while only the colour washes in.
local pulseTex = frame:CreateTexture(nil, "BORDER")
pulseTex:SetAllPoints(bg)
pulseTex:SetColorTexture(0.75, 0.15, 0.15, 1)
pulseTex:SetAlpha(0)

-- Edit outline. Four thin bars: a single texture anchored corner to corner
-- is a filled rectangle, not an outline, and buries the whole alert.
local editEdges = {}
for _, edge in ipairs({
	{ "TOPLEFT",    "TOPRIGHT",    nil, 2 },
	{ "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 },
	{ "TOPLEFT",    "BOTTOMLEFT",  2,   nil },
	{ "TOPRIGHT",   "BOTTOMRIGHT", 2,   nil },
}) do
	local line = frame:CreateTexture(nil, "OVERLAY")
	line:SetColorTexture(1, 0.5, 0, 0.9)
	line:SetPoint(edge[1], bg, edge[1])
	line:SetPoint(edge[2], bg, edge[2])
	if edge[3] then line:SetWidth(edge[3]) end
	if edge[4] then line:SetHeight(edge[4]) end
	line:Hide()
	editEdges[#editEdges + 1] = line
end

local function ShowEditBorder(show)
	for _, line in ipairs(editEdges) do
		line:SetShown(show)
	end
end

local icon = frame:CreateTexture(nil, "ARTWORK")
icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)   -- crop the stock icon border

local textCol = CreateFrame("Frame", nil, frame)

local nameText = textCol:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
nameText:SetJustifyH("CENTER")
nameText:SetWordWrap(false)

local timerText = textCol:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
timerText:SetJustifyH("CENTER")

local function LayoutFrame()
	icon:SetSize(ICON_SIZE, ICON_SIZE)
	icon:ClearAllPoints()
	icon:SetPoint("TOPLEFT", 0, 0)

	frame:SetSize(ICON_SIZE + TEXT_GAP + TEXT_WIDTH, ICON_SIZE)

	local timerFile, _, timerFlags = GameFontNormalHuge:GetFont()
	timerText:SetFont(timerFile, TIMER_FONT, timerFlags)

	-- The text column spans exactly the icon, so the cap height of the name
	-- lines up with the top of the icon and the baseline of the timer with
	-- its bottom.
	textCol:ClearAllPoints()
	textCol:SetPoint("TOPLEFT", icon, "TOPRIGHT", TEXT_GAP, 0)
	textCol:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

	-- A font string is taller than the glyphs inside it: there is ascent
	-- space above the caps and descent space below the baseline. Nudging by
	-- a fraction of the font size aligns what the eye sees, not what the
	-- bounding boxes say.
	local nameNudge = math.floor(NAME_FONT * 0.16 + 0.5)

	nameText:ClearAllPoints()
	nameText:SetPoint("TOP", textCol, "TOP", 0, nameNudge)
	nameText:SetWidth(TEXT_WIDTH)

	timerText:ClearAllPoints()
	-- Digits carry no descenders, so a bottom-flush anchor leaves the empty
	-- descent band under them and the block reads as sitting too low. Lifting
	-- evens out the space above and below the number.
	timerText:SetPoint("BOTTOM", textCol, "BOTTOM", 0, TIMER_LIFT)
	timerText:SetWidth(TEXT_WIDTH)

	frame:SetScale(SleepTimerDB and SleepTimerDB.scale or 1)
end

local function RestorePosition()
	local db = SleepTimerDB
	frame:ClearAllPoints()
	frame:SetPoint(db.point, UIParent, db.relativePoint, db.x, db.y)
end

local function SavePosition()
	local db = SleepTimerDB
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	db.point, db.relativePoint, db.x, db.y = point, relativePoint, x, y
end

-- --------------------------------------------------------------- timer ----

local elapsedSinceDraw = 0

local function FormatRemaining(remaining)
	if remaining >= 10 then
		return ("%d"):format(remaining)
	end
	return ("%.1f"):format(remaining)
end

-- Drop trailing bytes UTF-8-safely: a plain sub() can slice a multi-byte
-- character in half and leave a broken glyph.
local function TrimOneCharacter(text)
	local index = #text
	while index > 1 do
		local byte = text:byte(index)
		if byte < 0x80 or byte >= 0xC0 then break end   -- not a continuation byte
		index = index - 1
	end
	return text:sub(1, index - 1)
end

-- The alert is a fixed size, so the name adapts to the box instead of the
-- box adapting to the name: shrink the font first, and only truncate if the
-- name still will not fit at the smallest readable size.
local function FitName(name)
	name = name or ""

	local file, _, flags = GameFontNormalLarge:GetFont()
	local size = NAME_FONT

	nameText:SetWidth(0)   -- unbounded, so GetStringWidth measures the real text
	nameText:SetFont(file, size, flags)
	nameText:SetText(name)

	while size > NAME_FONT_MIN and nameText:GetStringWidth() > TEXT_WIDTH do
		size = size - 1
		nameText:SetFont(file, size, flags)
	end

	if nameText:GetStringWidth() > TEXT_WIDTH then
		local trimmed = name
		while #trimmed > 1 and nameText:GetStringWidth() > TEXT_WIDTH do
			trimmed = TrimOneCharacter(trimmed)
			nameText:SetText(trimmed .. "...")
		end
	end

	nameText:SetWidth(TEXT_WIDTH)
end

local lastWholeSecond, pulseStart

local function StartPulse()
	if not SleepTimerDB or not SleepTimerDB.pulse then return end
	pulseStart = GetTime()
end

local function DrawPulse(now)
	if not pulseStart then
		pulseTex:SetAlpha(0)
		return
	end

	local progress = (now - pulseStart) / PULSE_DECAY
	if progress >= 1 then
		pulseStart = nil
		pulseTex:SetAlpha(0)
		return
	end

	local fade = 1 - progress
	pulseTex:SetAlpha(PULSE_PEAK * fade * fade)   -- sharp hit, quick decay
end

frame:SetScript("OnUpdate", function(self, elapsed)
	if not active then return end

	elapsedSinceDraw = elapsedSinceDraw + elapsed
	if elapsedSinceDraw < UPDATE_THROTTLE then return end
	elapsedSinceDraw = 0

	local now = GetTime()

	if not active.expirationTime then
		DrawPulse(now)
		return
	end

	local remaining = active.expirationTime - now
	if remaining <= 0 then
		ST:Clear(true)
		return
	end

	local wholeSecond = math.ceil(remaining)
	if wholeSecond ~= lastWholeSecond then
		lastWholeSecond = wholeSecond
		StartPulse()
	end

	DrawPulse(now)
	timerText:SetText(FormatRemaining(remaining))
end)

-- ----------------------------------------------------------- public API ----

function ST:Trigger(spellID, name, iconTexture, duration, expirationTime)
	if expirationTime and expirationTime <= GetTime() then return end

	active = {
		spellID        = spellID,
		name           = name or "Unknown",
		icon           = iconTexture,
		duration       = duration,
		expirationTime = expirationTime,
	}

	icon:SetTexture(iconTexture or "Interface\\Icons\\INV_Misc_QuestionMark")

	local remaining = expirationTime and (expirationTime - GetTime()) or nil
	FitName(active.name)
	timerText:SetText(remaining and FormatRemaining(remaining) or "")

	lastWholeSecond = remaining and math.ceil(remaining) or nil
	pulseStart      = nil
	StartPulse()

	elapsedSinceDraw = UPDATE_THROTTLE
	frame:Show()
end

function ST:Clear(expired)
	active = nil

	local wasTesting = testing
	testing = false

	if editMode then
		ApplyInteractivity()
		ShowPlaceholder()   -- back to something grabbable
	else
		frame:Hide()
	end

	if wasTesting then
		SyncOptions()       -- flip the button back to "Test"
	end

	-- One effect ending does not mean control is back: something longer may
	-- still be running. Let the detection layer look again.
	if expired and ST.OnExpire then ST.OnExpire() end
end

function ST:IsActive()
	return active ~= nil
end

-- ----------------------------------------------------------- edit mode ----

-- The frame is draggable only while the options window is open AND no test
-- is running: a test is there to be looked at, and a stray click-drag during
-- one would move the frame instead.
function ApplyInteractivity()
	local movable = editMode and not testing
	frame:EnableMouse(movable)
	ShowEditBorder(movable)
end

function ShowPlaceholder()
	icon:SetTexture("Interface\\Icons\\Spell_Nature_Polymorph")
	FitName("Polymorph")
	timerText:SetText("8.0")
	pulseTex:SetAlpha(0)
	frame:Show()
end

-- The frame is movable exactly while the options window is open. There is no
-- separate lock: closing the window locks it.
function ST:SetEditMode(enabled)
	editMode = enabled and true or false

	if not editMode and testing then
		testing = false   -- closing the window ends any test in progress
	end

	ApplyInteractivity()

	if editMode then
		if not active then ShowPlaceholder() end
		frame:Show()
	elseif not active then
		frame:Hide()
	end
end

function ST:IsEditMode()
	return editMode
end

function SyncOptions()
	if ST.RefreshOptions then ST:RefreshOptions() end
end

-- ---------------------------------------------------------------- test ----

function ST:IsTesting()
	return testing
end

function ST:StartTest(seconds)
	seconds = tonumber(seconds) or 8

	local spellID, name, iconTexture
	if ST.RandomTestEffect then
		spellID, name, iconTexture = ST:RandomTestEffect()
	end

	if not name then
		Print("no effect categories are enabled — nothing to preview.")
		return
	end

	testing = true
	ApplyInteractivity()
	ST:Trigger(spellID, name, iconTexture, seconds, GetTime() + seconds)
	SyncOptions()
end

function ST:StopTest()
	if not testing then return end
	testing = false
	ST:Clear()
	ApplyInteractivity()
	SyncOptions()
end

function ST:ToggleTest(seconds)
	if testing then
		ST:StopTest()
	else
		ST:StartTest(seconds)
	end
end

function ST:SetScale(scale)
	scale = tonumber(scale)
	if not scale then return false end
	scale = math.max(0.5, math.min(3.0, scale))
	SleepTimerDB.scale = scale
	frame:SetScale(scale)
	SyncOptions()
	return scale
end

function ST:SetPulse(enabled)
	SleepTimerDB.pulse = enabled and true or false
	if not SleepTimerDB.pulse then
		pulseTex:SetAlpha(0)
	end
	SyncOptions()
	return SleepTimerDB.pulse
end

function ST:ResetPosition()
	SleepTimerDB.point         = DEFAULTS.point
	SleepTimerDB.relativePoint = DEFAULTS.relativePoint
	SleepTimerDB.x             = DEFAULTS.x
	SleepTimerDB.y             = DEFAULTS.y
	RestorePosition()
end

frame:SetScript("OnDragStart", function(self)
	if not editMode then return end
	self:StartMoving()
end)

frame:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	SavePosition()
end)

-- --------------------------------------------------------------- slash ----

function Print(msg)
	print("|cff66ccffSleepTimer|r: " .. msg)
end

local function HandleSlash(input)
	local cmd, arg = input:lower():match("^(%S*)%s*(.-)$")

	if cmd == "" then
		if ST.ToggleOptions then
			ST:ToggleOptions()
		else
			Print("options window failed to load.")
		end

	elseif cmd == "scale" then
		local applied = ST:SetScale(arg)
		Print(applied and ("scale set to %.2f."):format(applied)
			or "usage: |cffffff00/st scale 1.25|r (0.5–3.0)")

	elseif cmd == "pulse" then
		local state = ST:SetPulse(not SleepTimerDB.pulse)
		Print(("pulse %s."):format(state and "on" or "off"))

	elseif cmd == "test" then
		ST:ToggleTest(tonumber(arg))

	elseif cmd == "reset" then
		ST:ResetPosition()
		Print("position reset to centre.")

	else
		Print("|cffffff00/st|r opens the options window.")
		print("  |cffffff00/st scale <0.5-3.0>|r, |cffffff00/st pulse|r, |cffffff00/st test [secs]|r, |cffffff00/st reset|r")
	end
end

SLASH_SLEEPTIMER1 = "/sleeptimer"
SLASH_SLEEPTIMER2 = "/st"
SlashCmdList["SLEEPTIMER"] = HandleSlash

-- ------------------------------------------------------------------ init ----

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, addonName)
	if addonName ~= ADDON then return end
	self:UnregisterEvent("ADDON_LOADED")

	SleepTimerDB = SleepTimerDB or {}
	for key, value in pairs(DEFAULTS) do
		if SleepTimerDB[key] == nil then
			SleepTimerDB[key] = value
		end
	end

	-- Settings retired in earlier versions.
	SleepTimerDB.locked   = nil
	SleepTimerDB.iconSize = nil
	SleepTimerDB.vPad     = nil
	SleepTimerDB.bgAlpha  = nil

	LayoutFrame()
	RestorePosition()
end)
