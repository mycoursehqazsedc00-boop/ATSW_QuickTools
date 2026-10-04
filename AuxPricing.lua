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
	local _, _, item_id, suffix_id = string.find(link or "", "item:(%d+):%d+:%d+:%d+:%d+:%d+:(%-?%d+)")
	if item_id then return tonumber(item_id), tonumber(suffix_id) end
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
-- Returns price, isLive (isLive is false for a cached fallback price).
local function ATSWQT_AuxUnitPrice(link)
	local item_id, suffix_id = ATSWQT_ParseLink(link)
	if not item_id or item_id == 0 then return nil end
	local key = item_id..":"..(suffix_id or 0)

	if aux_info and aux_history then
		local ok, _, vendorPrice, limited = pcall(aux_info.merchant_info, item_id)
		if ok and vendorPrice and not limited then
			atsw_qt_pricecache[key] = { price = vendorPrice, time = time() }
			return vendorPrice, true
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

	for i = 1, 8 do
		local slot = getglobal("ATSWReagent"..i)
		if slot then
			local priceText = getglobal(slot:GetName().."ATSWQTPrice")
			if not priceText then
				priceText = slot:CreateFontString(slot:GetName().."ATSWQTPrice", "OVERLAY", "GameFontNormalSmall")
				priceText:SetPoint("TOP", slot, "BOTTOM", 0, -2)
			end

			local shown = false
			local r = reagents[i]
			if i <= n and r and r.link then
				local price, isLive = ATSWQT_AuxUnitPrice(r.link)
				if price then
					local text = ATSWQT_FormatPrice(price)
					if not isLive then text = "~"..text end
					priceText:SetText(text)
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
