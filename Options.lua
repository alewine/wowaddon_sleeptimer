--[[
	SleepTimer — Options.lua

	Self-contained options window.

	Built from bare CreateFrame calls and stock art rather than Blizzard's
	options templates or the Settings API: every template-based options panel
	eventually breaks when Blizzard retires the template, and nothing here
	depends on anything but frame types and texture files.

	Opening the window unlocks the alert frame; closing it locks it again.
]]

local ST = SleepTimer

local PANEL_W     = 356
local MARGIN      = 14
local ROW_H       = 20
local CAT_COLUMNS = 3

local refreshing = false

-- ------------------------------------------------------------- widgets ----

local function Backdrop(frame, r, g, b, a, borderAlpha)
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(r, g, b, a)

	if borderAlpha then
		for _, edge in ipairs({
			{ "TOPLEFT", "TOPRIGHT", nil, 1 },
			{ "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
			{ "TOPLEFT", "BOTTOMLEFT", 1, nil },
			{ "TOPRIGHT", "BOTTOMRIGHT", 1, nil },
		}) do
			local line = frame:CreateTexture(nil, "BORDER")
			line:SetColorTexture(0.35, 0.35, 0.35, borderAlpha)
			line:SetPoint(edge[1])
			line:SetPoint(edge[2])
			if edge[3] then line:SetWidth(edge[3]) end
			if edge[4] then line:SetHeight(edge[4]) end
		end
	end
	return bg
end

local function MakeCheckbox(parent, label, size, fontObject, onChange)
	local cb = CreateFrame("CheckButton", nil, parent)
	cb:SetSize(size, size)
	cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
	cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
	cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
	cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")

	local fs = cb:CreateFontString(nil, "OVERLAY", fontObject)
	fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	fs:SetText(label)
	cb.label = fs

	cb:SetScript("OnClick", function(self)
		if refreshing then return end
		onChange(self:GetChecked() and true or false)
	end)
	return cb
end

local function MakeButton(parent, label, width, onClick)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(width, 20)
	Backdrop(button, 0.18, 0.18, 0.18, 0.9, 0.8)

	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.12)

	local fs = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	fs:SetPoint("CENTER")
	fs:SetText(label)
	button.label = fs

	button:SetScript("OnClick", onClick)
	return button
end

-- --------------------------------------------------------------- panel ----

local panel
local widgets = {}

local function Refresh()
	if not panel then return end
	refreshing = true

	widgets.scale:SetValue(SleepTimerDB.scale)
	widgets.pulse:SetChecked(SleepTimerDB.pulse)

	if widgets.test then
		local testing = ST.IsTesting and ST:IsTesting()
		widgets.test.label:SetText(testing and "Stop" or "Test")
	end

	local categories = ST.GetCategories and ST:GetCategories() or {}
	for locType, checkbox in pairs(widgets.categories or {}) do
		checkbox:SetChecked(categories[locType] and true or false)
	end

	refreshing = false
end

local function BuildPanel()
	panel = CreateFrame("Frame", "SleepTimerOptions", UIParent)
	panel:SetWidth(PANEL_W)
	panel:SetFrameStrata("DIALOG")
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetClampedToScreen(true)

	local function RestorePanelPosition()
		local db = SleepTimerDB
		panel:ClearAllPoints()
		panel:SetPoint(db.optPoint or "CENTER", UIParent,
			db.optRelativePoint or "CENTER", db.optX or 0, db.optY or 120)
	end

	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local db = SleepTimerDB
		local point, _, relativePoint, x, y = self:GetPoint(1)
		db.optPoint, db.optRelativePoint, db.optX, db.optY = point, relativePoint, x, y
	end)

	RestorePanelPosition()
	Backdrop(panel, 0.06, 0.06, 0.07, 0.95, 1)

	tinsert(UISpecialFrames, "SleepTimerOptions")   -- Escape closes it

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", MARGIN, -MARGIN)
	title:SetText("SleepTimer")

	local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("LEFT", title, "RIGHT", 8, 0)
	hint:SetText("drag the alert to move it")

	local close = MakeButton(panel, "X", 20, function() panel:Hide() end)
	close:SetPoint("TOPRIGHT", -MARGIN, -MARGIN + 1)

	local y = -MARGIN - 24

	-- ---- scale ------------------------------------------------------------
	local scaleLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	scaleLabel:SetPoint("TOPLEFT", MARGIN, y)
	scaleLabel:SetText("Size")

	local scaleValue = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	scaleValue:SetPoint("TOPRIGHT", -MARGIN, y)
	scaleValue:SetTextColor(1, 0.82, 0)

	local scale = CreateFrame("Slider", nil, panel)
	scale:SetPoint("TOPLEFT", MARGIN, y - 14)
	scale:SetPoint("TOPRIGHT", -MARGIN, y - 14)
	scale:SetHeight(16)
	scale:SetOrientation("HORIZONTAL")
	scale:SetHitRectInsets(0, 0, -6, -6)
	scale:SetMinMaxValues(0.5, 3.0)
	scale:SetValueStep(0.05)
	if scale.SetObeyStepOnDrag then scale:SetObeyStepOnDrag(true) end
	scale:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")

	local track = scale:CreateTexture(nil, "BACKGROUND")
	track:SetColorTexture(0, 0, 0, 0.6)
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(4)

	scale:SetScript("OnValueChanged", function(self, value)
		scaleValue:SetText(("%.2f"):format(value))
		if refreshing then return end
		ST:SetScale(value)
	end)
	widgets.scale = scale
	y = y - 38

	-- ---- pulse ------------------------------------------------------------
	widgets.pulse = MakeCheckbox(panel, "Pulse the background each second", 20,
		"GameFontHighlightSmall", function(checked) ST:SetPulse(checked) end)
	widgets.pulse:SetPoint("TOPLEFT", MARGIN - 2, y)
	y = y - 26

	-- ---- categories -------------------------------------------------------
	local catHeading = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	catHeading:SetPoint("TOPLEFT", MARGIN, y)
	catHeading:SetText("Alert on")
	catHeading:SetTextColor(1, 0.82, 0)

	local note = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	note:SetPoint("LEFT", catHeading, "RIGHT", 6, 0)
	note:SetText("root, snare and silence still let you act")
	y = y - 18

	widgets.categories = {}

	local names = {}
	for locType in pairs(ST.GetCategories and ST:GetCategories() or {}) do
		names[#names + 1] = locType
	end
	table.sort(names)

	local columnWidth = (PANEL_W - MARGIN * 2) / CAT_COLUMNS
	local rows = math.ceil(#names / CAT_COLUMNS)

	for index, locType in ipairs(names) do
		local column = math.floor((index - 1) / rows)
		local row    = (index - 1) % rows

		local checkbox = MakeCheckbox(panel, locType, 16, "GameFontHighlightSmall",
			function(checked) ST:SetCategory(locType, checked) end)
		checkbox:SetPoint("TOPLEFT", MARGIN + column * columnWidth, y - row * ROW_H)
		checkbox.label:SetTextColor(0.85, 0.85, 0.85)
		widgets.categories[locType] = checkbox
	end

	y = y - rows * ROW_H - 10

	-- ---- actions ----------------------------------------------------------
	local buttonWidth = (PANEL_W - MARGIN * 2 - 12) / 3

	local test = MakeButton(panel, "Test", buttonWidth, function()
		ST:ToggleTest(8)
	end)
	test:SetPoint("TOPLEFT", MARGIN, y)
	widgets.test = test

	local recentre = MakeButton(panel, "Recentre", buttonWidth, function()
		ST:ResetPosition()
	end)
	recentre:SetPoint("LEFT", test, "RIGHT", 6, 0)

	local defaults = MakeButton(panel, "Defaults", buttonWidth, function()
		ST:SetScale(1.0)
		ST:SetPulse(true)
		ST:ResetPosition()
		Refresh()
	end)
	defaults:SetPoint("LEFT", recentre, "RIGHT", 6, 0)

	y = y - 20 - MARGIN
	panel:SetHeight(-y)

	-- Opening the window is what unlocks the alert frame.
	panel:SetScript("OnShow", function()
		Refresh()
		ST:SetEditMode(true)
	end)
	panel:SetScript("OnHide", function()
		ST:SetEditMode(false)
	end)

	panel:Hide()
end

-- ----------------------------------------------------------------- API ----

function ST:ToggleOptions()
	if not panel then BuildPanel() end
	if panel:IsShown() then
		panel:Hide()
	else
		panel:Show()
	end
end

function ST:RefreshOptions()
	Refresh()
end
