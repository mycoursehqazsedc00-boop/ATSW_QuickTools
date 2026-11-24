-- ATSW Quick Tools - Aux pricing (+ persistent price cache)
--
-- Shows each reagent's known price right on ATSW's reagent icons for
-- the selected recipe: vendor price if sold with unlimited stock,
-- otherwise Aux's Auction House value estimate - the same figures
-- Aux's own "Total Cost" label already uses, just broken out per
-- reagent instead of only as a sum.
--
-- Data source for WHICH reagents to price: atsw_tradeskilllist[*].
-- reagents[*] (confirmed directly from atsw.lua - the same table
-- ATSWInv_UpdateQueuedItemList() and ATSW_AddTradeSkillReagentLinks-
-- ToChatFrame() read), looked up via ATSW_GetTradeSkillListPos(id),
-- where "id" is the real Blizzard recipe index
-- ATSWFrame_SetSelection(id, wasClicked) is called with. No live
-- GetTradeSkill*/GetCraft* reagent calls of our own are needed.
--
-- Persistent price cache: every price this addon actually gets from
-- Aux is saved into atsw_qt_pricecache (item_id:suffix_id -> {price,
-- time}), a SavedVariable - which lives under
-- WTF/Account/.../SavedVariables/, not the client's WDB cache, so it
-- isn't affected by a WDB wipe. Whenever Aux doesn't have a live
-- answer (not loaded, or no data for that item yet), the last cached
-- price is shown instead, prefixed with "~" to mark it as not current.
-- Item links are parsed with Aux's own aux.util.info when available,
-- falling back to a small built-in parser otherwise, so the cache
-- still works for display even in a session where Aux hasn't loaded.

atsw_qt_pricecache = atsw_qt_pricecache or {}

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
	local cached = 0
	for _ in pairs(atsw_qt_pricecache) do cached = cached + 1 end
	if aux_info then
		return "Aux pricing: connected ("..cached.." price(s) cached)."
	end
	return "Aux pricing: Aux not found (or not loaded yet) - "..cached.." cached price(s) still usable."
end

-- item_id:suffix_id, via Aux's own parser if loaded, else a small
-- built-in fallback so cached prices can still be looked up and
-- displayed without Aux present this session.
local function ATSWQT_ParseLink(link)
	if aux_info and aux_info.parse_link then
		local ok, item_id, suffix_id = pcall(aux_info.parse_link, link)
		if ok and item_id and item_id > 0 then return item_id, suffix_id end
	end
	local _, _, item_id, suffix_id = string.find(link or "", "item:(%d+):%d*:(%-?%d*)")
	if item_id then return tonumber(item_id), tonumber(suffix_id) or 0 end
	local _, _, bare_id = string.find(link or "", "item:(%d+)")
	if bare_id then return tonumber(bare_id), 0 end
	return nil
end

-- Fallback money formatter for when Aux (and so aux.util.money) isn't
-- loaded - plain "Xg Ys" / "Ys Zc" / "Zc", no coin icons.
local function ATSWQT_FormatMoney(copper)
	copper = math.floor(copper or 0)
	local g = math.floor(copper / 10000)
	local s = math.floor(math.mod(copper, 10000) / 100)
	local c = math.mod(copper, 100)
	if g > 0 then return g.."g "..s.."s" end
	if s > 0 then return s.."s "..c.."c" end
	return c.."c"
end

local function ATSWQT_FormatPrice(copper)
	if aux_money and aux_money.to_string then
		local ok, text = pcall(aux_money.to_string, copper, false, true)
		if ok and text then return text end
	end
	return ATSWQT_FormatMoney(copper)
end

-- Same "vendor price if unlimited, else Aux AH value" rule Aux's own
-- crafting-cost feature uses, so a live number here still adds up to
-- what ATSWReagentLabel/TradeSkillReagentLabel shows as the total.
-- When ignoreVendor is true (used for the crafted output's AH sell value),
-- skips vendor buy price and uses Aux's AH market value only.
-- Returns price, isLive (isLive is false for a cached fallback price).
local function ATSWQT_AuxUnitPrice(link, ignoreVendor)
	local item_id, suffix_id = ATSWQT_ParseLink(link)
	if not item_id or item_id == 0 then return nil end
	local key = item_id..":"..(suffix_id or 0)

	if aux_info and aux_history then
		if not ignoreVendor then
			local ok, _, vendorPrice, limited = pcall(aux_info.merchant_info, item_id)
			if ok and vendorPrice and not limited then
				atsw_qt_pricecache[key] = { price = vendorPrice, time = time() }
				return vendorPrice, true
			end
		end
		local ok2, value = pcall(aux_history.value, key)
		if ok2 and value and value > 0 then
			atsw_qt_pricecache[key] = { price = value, time = time() }
			return value, true
		end
	end

	local cached = atsw_qt_pricecache[key]
	if cached then
		return cached.price, false
	end
	return nil
end

-- id: the real Blizzard recipe index, as passed to
-- ATSWFrame_SetSelection(id, wasClicked) - see header comment.
function ATSWQT_RefreshReagentPrices(id)
	if not (id and atsw_tradeskilllist and type(ATSW_GetTradeSkillListPos) == "function") then return end

	local pos = ATSW_GetTradeSkillListPos(id)
	local entry = (pos and pos > 0) and atsw_tradeskilllist[pos]
	local reagents = (entry and entry.reagents) or {}
	local n = table.getn(reagents)

	local totalCost = 0
	local costComplete = (n > 0)

	for i = 1, 8 do
		local slot = getglobal("ATSWReagent"..i)
		if slot then
			local priceText = getglobal(slot:GetName().."ATSWQTPrice")
			if not priceText then
				priceText = slot:CreateFontString(slot:GetName().."ATSWQTPrice", "OVERLAY", "GameFontNormalSmall")
				priceText:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -4, 2)
			end

			local shown = false
			local r = reagents[i]
			if i <= n and r and r.link then
				local price, isLive = ATSWQT_AuxUnitPrice(r.link)
				if price then
					totalCost = totalCost + price * (r.count or 1)
					local text = ATSWQT_FormatPrice(price)
					if not isLive then text = "~"..text end
					priceText:SetText(text)
					priceText:Show()
					shown = true
				else
					costComplete = false
				end
			elseif i <= n then
				costComplete = false
			end
			if not shown then
				priceText:Hide()
			end
		end
	end

	if ATSWReagentLabel then
		local summary = getglobal("ATSWQT_CraftSummary")
		if not summary then
			summary = ATSWFrame:CreateFontString("ATSWQT_CraftSummary", "OVERLAY", "GameFontHighlightSmall")
			summary:SetPoint("LEFT", ATSWReagentLabel, "RIGHT", 10, 0)
		end

		if totalCost > 0 then
			local parts = (costComplete and "Cost: " or "Cost: >")..ATSWQT_FormatPrice(totalCost)
			if costComplete then
				local itemLink = type(ATSW_GetTradeSkillItemLink) == "function" and ATSW_GetTradeSkillItemLink(id) or nil
				if itemLink then
					local ahPrice, isLive = ATSWQT_AuxUnitPrice(itemLink, true)
					if ahPrice and ahPrice > 0 then
						local minMade = 1
						if type(ATSW_GetTradeSkillNumMade) == "function" then
							local m1, m2 = ATSW_GetTradeSkillNumMade(id)
							if m1 and m1 > 0 then
								minMade = m2 and ((m1 + m2) / 2) or m1
							end
						end
						local gross = math.floor(ahPrice * minMade)
						if atsw_qt_ahcut == true then
							gross = math.floor(gross * 0.95)
						end
						local profit = gross - totalCost
						local prefix = isLive and "" or "~"
						if profit >= 0 then
							parts = parts.."  |cff33ff99(+"..prefix..ATSWQT_FormatPrice(profit)..")|r"
						else
							parts = parts.."  |cffff5555(-"..prefix..ATSWQT_FormatPrice(-profit)..")|r"
						end
					end
				end
			end
			summary:SetText(parts)
			summary:Show()
		else
			summary:Hide()
		end
	end
end

-- Computes total reagent cost and estimated AH gross/profit across the
-- currently queued recipes belonging to the open profession.
function ATSWQT_GetQueueFinancials()
	if not (atsw_queue and atsw_tradeskilllist and type(ATSW_GetTradeSkillListPosByName) == "function") then
		return nil
	end
	local qn = table.getn(atsw_queue)
	if qn == 0 then return nil end

	local totalCost, totalGross = 0, 0
	local costComplete, grossComplete = true, true
	local matchedRecipes = 0

	for i = 1, qn do
		local job = atsw_queue[i]
		local pos = job and job.name and ATSW_GetTradeSkillListPosByName(job.name) or -1
		local entry = (pos and pos > 0) and atsw_tradeskilllist[pos]
		if entry then
			matchedRecipes = matchedRecipes + 1
			local qty = job.count or 1
			local reagents = entry.reagents or {}
			for j = 1, table.getn(reagents) do
				local r = reagents[j]
				local price = r and r.link and ATSWQT_AuxUnitPrice(r.link)
				if price then
					totalCost = totalCost + price * (r.count or 1) * qty
				else
					costComplete = false
				end
			end

			local ahPrice = entry.link and ATSWQT_AuxUnitPrice(entry.link, true)
			if ahPrice and ahPrice > 0 then
				local made = (entry.num and entry.num > 0) and entry.num or 1
				local gross = math.floor(ahPrice * made * qty)
				if atsw_qt_ahcut == true then
					gross = math.floor(gross * 0.95)
				end
				totalGross = totalGross + gross
			else
				grossComplete = false
			end
		end
	end

	if matchedRecipes == 0 then return nil end
	return {
		totalCost = totalCost,
		costComplete = costComplete,
		totalGross = totalGross,
		grossComplete = grossComplete,
		netProfit = (costComplete and grossComplete) and (totalGross - totalCost) or nil,
		ahCut = (atsw_qt_ahcut == true),
		formatPrice = ATSWQT_FormatPrice,
	}
end
