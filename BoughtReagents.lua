-- ATSW Quick Tools - "mark reagent as bought" checkbox
--
-- Adds a small checkbox to each row of ATSW's own "reagents needed for
-- the queue" window (ATSWReagentFrame, populated by
-- ATSW_ShowNecessaryReagents() into rows named
-- ATSWRFReagent1.. ATSWRFReagent20 - confirmed directly from atsw.lua,
-- not guessed). Checking it dims that row's item name so it reads as
-- "handled" while you work through the list. Marks are kept in
-- atsw_qt_bought (name -> true), a SavedVariable, so they survive a
-- relog; they're keyed by reagent name rather than row number since
-- rows get reused for whatever's currently short.
--
-- Marks are never auto-cleared: once a reagent is fully supplied,
-- ATSW's own filtering removes it from the list (so its checkbox just
-- disappears with it), but the underlying mark is left in
-- atsw_qt_bought rather than pruned, since there's no fully reliable
-- way to tell "satisfied" apart from "not needed by whatever
-- profession happens to be open right now" from here. That's a few
-- stray string keys at most, not worth the risk of erasing a mark
-- that's still relevant.

atsw_qt_bought = atsw_qt_bought or {}

local ATSWQT_MAX_REAGENT_ROWS = 20

local function ATSWQT_UpdateReagentRow(i)
	local entry = atsw_necessaryitems and atsw_necessaryitems[i]
	local check = getglobal("ATSWQT_RFBought"..i)

	if not entry then
		if check then check:Hide() end
		return
	end

	local itemFS = getglobal("ATSWRFReagent"..i.."Item")

	if not check then
		local row = getglobal("ATSWRFReagent"..i)
		if not row then return end
		check = CreateFrame("CheckButton", "ATSWQT_RFBought"..i, row, "UICheckButtonTemplate")
		check:SetWidth(20)
		check:SetHeight(20)
		check:SetScript("OnClick", function()
			local nm = this.itemname
			if nm then
				if this:GetChecked() then
					atsw_qt_bought[nm] = true
				else
					atsw_qt_bought[nm] = nil
				end
			end
			if type(ATSWQT_RefreshReagentWindow) == "function" then
				ATSWQT_RefreshReagentWindow()
			end
		end)
	end

	check.itemname = entry.name
	local missingFS = getglobal("ATSWRFReagent"..i.."Missing")
	check:ClearAllPoints()
	if missingFS then
		check:SetPoint("LEFT", missingFS, "RIGHT", 8, 0)
	else
		local row = getglobal("ATSWRFReagent"..i)
		if row then
			check:SetPoint("RIGHT", row, "RIGHT", -4, 0)
		end
	end
	check:SetChecked(atsw_qt_bought[entry.name] and true or false)
	check:Show()

	if itemFS then
		if atsw_qt_bought[entry.name] then
			itemFS:SetTextColor(0.5, 0.5, 0.5)
		else
			itemFS:SetTextColor(1, 1, 1)
		end
	end
end

local function ATSWQT_EnsureClearBoughtButton()
	if ATSWQT_ClearBoughtButton or not ATSWReagentFrame then return end
	local btn = CreateFrame("Button", "ATSWQT_ClearBoughtButton", ATSWReagentFrame, "UIPanelButtonTemplate")
	btn:SetWidth(92)
	btn:SetHeight(20)
	if ATSWReagentFrameCloseButton then
		btn:SetPoint("RIGHT", ATSWReagentFrameCloseButton, "LEFT", -6, 0)
	else
		btn:SetPoint("TOPRIGHT", ATSWReagentFrame, "TOPRIGHT", -60, -14)
	end
	getglobal(btn:GetName().."Text"):SetText("Clear Bought")
	btn:SetScript("OnClick", function()
		atsw_qt_bought = {}
		ATSWQT_RefreshReagentWindow()
	end)
	ATSWQT_ClearBoughtButton = btn
end

function ATSWQT_RefreshReagentWindow()
	ATSWQT_EnsureClearBoughtButton()
	for i = 1, ATSWQT_MAX_REAGENT_ROWS do
		ATSWQT_UpdateReagentRow(i)
	end
end
