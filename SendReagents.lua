-- ATSW Quick Tools - Send reagents to chat
--
-- Adds a "Send Mats" button next to the queue ETA bar. Click it and
-- it posts one chat line per distinct reagent needed to finish the
-- whole queue (item link + total count), to whatever chat channel
-- you'd currently land in if you just hit Enter and typed - it reuses
-- the chat edit box's own remembered channel (ChatEdit_ActivateChat/
-- ChatEdit_SendText) instead of guessing a channel index, so it's
-- always "whatever you were last chatting in": Say, a whisper, Guild,
-- a numbered channel, whatever.
--
-- This does NOT read ATSW's own "reagents needed" window (that code
-- isn't available to this addon) - it recomputes the same totals
-- itself, straight from atsw_queue plus the stock trade
-- skill/craft reagent APIs, the same way AuxPricing.lua looks up a
-- single recipe's reagents. Because of that, it can only resolve a
-- queued recipe's reagents while the profession that recipe belongs
-- to is the one currently open (GetTradeSkillInfo/GetCraftInfo only
-- expose the currently-loaded list) - in practice that's normally
-- true anyway, since you'd have that window open to look at the queue.

-- Finds a recipe's index (and whether it's a trade skill or a craft)
-- by name in whichever list is currently loaded.
local function ATSWQT_FindRecipeId(recipeName)
	if type(GetNumTradeSkills) == "function" then
		local ok, n = pcall(GetNumTradeSkills)
		if ok and n then
			for i = 1, n do
				local name, skillType = GetTradeSkillInfo(i)
				if name == recipeName and skillType ~= "header" then
					return "tradeskill", i
				end
			end
		end
	end
	if type(GetNumCraftSkills) == "function" then
		local ok, n = pcall(GetNumCraftSkills)
		if ok and n then
			for i = 1, n do
				local name, skillType = GetCraftInfo(i)
				if name == recipeName and skillType ~= "header" then
					return "craft", i
				end
			end
		end
	end
	return nil
end

-- Returns an ordered list of item links plus a link->total-count table,
-- summed across every entry currently in atsw_queue.
local function ATSWQT_AggregateQueueReagents()
	local order, totals = {}, {}
	if not atsw_queue then return order, totals end

	for qi = 1, table.getn(atsw_queue) do
		local entry = atsw_queue[qi]
		local needed = entry.count or 1
		local kind, id = ATSWQT_FindRecipeId(entry.name)
		if kind then
			local numReagents
			if kind == "tradeskill" then
				numReagents = GetTradeSkillNumReagents(id)
			else
				numReagents = GetCraftNumReagents(id)
			end
			for r = 1, (numReagents or 0) do
				local link, reagentCount
				if kind == "tradeskill" then
					link = GetTradeSkillReagentItemLink(id, r)
					local _, _, c = GetTradeSkillReagentInfo(id, r)
					reagentCount = c
				else
					link = GetCraftReagentItemLink(id, r)
					local _, _, c = GetCraftReagentInfo(id, r)
					reagentCount = c
				end
				if link then
					if not totals[link] then
						totals[link] = 0
						table.insert(order, link)
					end
					totals[link] = totals[link] + (reagentCount or 1) * needed
				end
			end
		end
	end

	return order, totals
end

-- ------------------------------------------------------------------
-- Paced sender - posts one line at a time on a short timer instead of
-- all at once in a loop, so a long materials list doesn't trip chat
-- spam throttling (or get a few lines silently dropped by it).
-- ------------------------------------------------------------------
local ATSWQT_chatSendQueue = {}
local ATSWQT_chatSendTimer = 0
local ATSWQT_CHAT_SEND_INTERVAL = 0.3

local ATSWQT_ChatSendFrame = CreateFrame("Frame")
ATSWQT_ChatSendFrame:Hide()
ATSWQT_ChatSendFrame:SetScript("OnUpdate", function(self, elapsed)
	ATSWQT_chatSendTimer = ATSWQT_chatSendTimer + (elapsed or 0)
	if ATSWQT_chatSendTimer < ATSWQT_CHAT_SEND_INTERVAL then return end
	ATSWQT_chatSendTimer = 0

	local msg = table.remove(ATSWQT_chatSendQueue, 1)
	if msg and DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox then
		local editBox = DEFAULT_CHAT_FRAME.editBox
		ChatEdit_ActivateChat(editBox)
		editBox:SetText(msg)
		ChatEdit_SendText(editBox, 0)
	end

	if table.getn(ATSWQT_chatSendQueue) == 0 then
		self:Hide()
		if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox and DEFAULT_CHAT_FRAME.editBox:IsShown() then
			ChatEdit_DeactivateChat(DEFAULT_CHAT_FRAME.editBox)
		end
	end
end)

function ATSWQT_SendReagentsToChat()
	local order, totals = ATSWQT_AggregateQueueReagents()
	local count = table.getn(order)

	if count == 0 then
		DEFAULT_CHAT_FRAME:AddMessage(
			"ATSW Quick Tools: nothing to send (queue is empty, or its recipes aren't in the "..
			"currently open profession window).")
		return
	end

	ATSWQT_chatSendQueue = {}
	for i = 1, count do
		local link = order[i]
		table.insert(ATSWQT_chatSendQueue, link.."  x"..totals[link])
	end
	ATSWQT_chatSendTimer = 0
	ATSWQT_ChatSendFrame:Show()
	DEFAULT_CHAT_FRAME:AddMessage("ATSW Quick Tools: sending "..count.." reagent line(s)...")
end
