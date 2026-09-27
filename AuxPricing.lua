-- ATSW Quick Tools - Aux pricing
--
-- Shows each reagent's Aux-known price (vendor price if it's sold by a
-- vendor with unlimited stock, otherwise Aux's Auction House value
-- estimate) right on ATSW's reagent icons for the selected recipe -
-- the same figures Aux itself already uses for its own "Total Cost"
-- label, just broken out per reagent instead of only as a sum.
--
-- Why this is possible without editing Aux or ATSW:
-- Aux's own core/crafting.lua already contains a compatibility line
-- for ATSW:
--     if ATSWReagentLabel then ATSWReagentLabel:SetText(...) end
-- inside its TradeSkillFrame_SetSelection hook. That confirms two
-- things we rely on: (1) ATSW keeps Blizzard's stock tradeskill/craft
-- selection state in sync (GetTradeSkillSelectionIndex() etc. are
-- valid) even though ATSW draws its own list, and (2) ATSW's reagent
-- display globals follow the exact same naming as Blizzard's own
-- TradeSkillReagent1-8 with "TradeSkill" swapped for "ATSW". This file
-- assumes ATSWReagent1..ATSWReagent8 exist the same way; if that guess
-- is wrong on your ATSW build, run "/atswqt aux" for a quick check -
-- the queue bar / profession bar / total-cost label are unaffected
-- either way.
--
-- Requires Aux's package system (the global module()/require()
-- functions from Aux's libs/package.lua) to be loaded. Does nothing,
-- silently, if Aux isn't installed.

local aux_info, aux_history, aux_money

function ATSWQT_InitAuxPricing()
	if type(require) ~= "function" then
		return false -- Aux (or its package system) isn't loaded at all
	end
	local ok1, info = pcall(require, "aux.util.info")
	local ok2, history = pcall(require, "aux.core.history")
	local ok3, money = pcall(require, "aux.util.money")
	if ok1 and ok2 and ok3 and info and history and money
			and info.parse_link and history.value and money.to_string then
		aux_info, aux_history, aux_money = info, history, money
		return true
	end
	return false
end

function ATSWQT_AuxStatus()
	if not aux_info then
		ATSWQT_InitAuxPricing()
	end
	if aux_info then
		return "Aux pricing: connected."
	end
	return "Aux pricing: Aux not found (or not loaded yet)."
end

-- Same "vendor price if unlimited, else Aux AH value" rule Aux's own
-- crafting-cost feature uses, so our per-line numbers add up to the
-- same total ATSWReagentLabel/TradeSkillReagentLabel already shows.
local function ATSWQT_AuxUnitPrice(link)
	if not (aux_info and aux_history) then return nil end
	local item_id, suffix_id = aux_info.parse_link(link)
	if not item_id or item_id == 0 then return nil end
	local ok, _, vendorPrice, limited = pcall(aux_info.merchant_info, item_id)
	if ok and vendorPrice and not limited then
		return vendorPrice
	end
	local ok2, value = pcall(aux_history.value, item_id..":"..(suffix_id or 0))
	if ok2 then return value end
	return nil
end

-- Figures out which reagent API is live right now: regular trade
-- skills use GetTradeSkill*, Enchanting (and a couple of other
-- "craft"-style windows) use GetCraft*. Whichever one reports a
-- selected recipe with reagents wins.
local function ATSWQT_ActiveReagentSource()
	if type(GetTradeSkillSelectionIndex) == "function" then
		local id = GetTradeSkillSelectionIndex()
		if id and id > 0 then
			local ok, n = pcall(GetTradeSkillNumReagents, id)
			if ok and n and n > 0 then
				return "tradeskill", id, n
			end
		end
	end
	if type(GetCraftSelectionIndex) == "function" then
		local id = GetCraftSelectionIndex()
		if id and id > 0 then
			local ok, n = pcall(GetCraftNumReagents, id)
			if ok and n and n > 0 then
				return "craft", id, n
			end
		end
	end
	return nil
end

function ATSWQT_RefreshReagentPrices()
	if not (aux_info and aux_history and aux_money) then return end

	local kind, id, n = ATSWQT_ActiveReagentSource()
	for i = 1, 8 do
		local slot = getglobal("ATSWReagent"..i)
		if slot then
			local priceText = getglobal(slot:GetName().."ATSWQTPrice")
			if not priceText then
				priceText = slot:CreateFontString(slot:GetName().."ATSWQTPrice", "OVERLAY", "GameFontNormalSmall")
				priceText:SetPoint("TOP", slot, "BOTTOM", 0, -2)
			end

			local shown = false
			if kind and i <= n then
				local link
				if kind == "tradeskill" then
					link = GetTradeSkillReagentItemLink(id, i)
				else
					link = GetCraftReagentItemLink(id, i)
				end
				local price = link and ATSWQT_AuxUnitPrice(link)
				if price then
					priceText:SetText(aux_money.to_string(price, false, true))
					priceText:Show()
					shown = true
				end
			end
			if not shown then
				priceText:Hide()
			end
		end
	end
end
