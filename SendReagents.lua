-- ATSW Quick Tools - Send reagents to chat
--
-- Adds a "Send Mats" button next to the queue ETA bar. Click it and
-- it posts one chat line per distinct reagent needed to finish the
-- whole queue (item link + total count).
--
-- Both the data and the send method are ATSW's own, not reinvented:
--   - Reagent totals come from atsw_queueditemlist (built by ATSW's
--     own ATSWInv_UpdateQueuedItemList(), which sums
--     atsw_tradeskilllist[*].reagents[*].count * atsw_queue[*].count -
--     the exact same numbers its own reagents-needed window uses),
--     with item links read from atsw_tradeskilllist[*].reagents[*].
--   - The channel to send to is worked out the same way ATSW's own
--     Shift+Left-Click "send reagents to chat" feature
--     (ATSW_AddTradeSkillReagentLinksToChatFrame in atsw.lua) does:
--     reading ChatFrameEditBox.chatType directly (plus WIM support),
--     then calling SendChatMessage - no ChatEdit_ActivateChat/
--     ChatEdit_SendText involved, since this client doesn't have them.
--
-- Because atsw_tradeskilllist only holds the currently-open
-- profession's recipes (ATSW rebuilds it fresh each time you switch
-- profession), this - like ATSW's own reagents window - can only
-- total reagents for queued items belonging to that profession. If
-- your queue spans more than one, switch to each and click
-- "Send Mats" separately to get all of them.

-- Rebuilds atsw_queueditemlist (name -> total count needed) and pairs
-- it with each reagent's item link from atsw_tradeskilllist.
local function ATSWQT_AggregateQueueReagents(onlyMissing)
	local items, totals = {}, {}

	if type(ATSWInv_UpdateQueuedItemList) == "function" then
		pcall(ATSWInv_UpdateQueuedItemList)
	end

	if type(atsw_queueditemlist) ~= "table" or type(atsw_tradeskilllist) ~= "table" then
		return items, totals
	end

	-- reagent name -> item link, from ATSW's own cached recipe data.
	local linkByName = {}
	for j = 1, table.getn(atsw_tradeskilllist) do
		local reagents = atsw_tradeskilllist[j] and atsw_tradeskilllist[j].reagents
		if reagents then
			for k = 1, table.getn(reagents) do
				local r = reagents[k]
				if r and r.name and r.link and not linkByName[r.name] then
					linkByName[r.name] = r.link
				end
			end
		end
	end

	for name, count in pairs(atsw_queueditemlist) do
		if type(count) == "number" and count > 0 then
			local skip = onlyMissing and type(atsw_qt_bought) == "table" and atsw_qt_bought[name]
			if not skip then
				local needed = count
				if onlyMissing and type(ATSWInv_GetItemCount) == "function" then
					local have = ATSWInv_GetItemCount(name) or 0
					needed = count - have
				end
				if needed > 0 then
					local display = linkByName[name] or ("["..name.."]")
					table.insert(items, { name = name, text = display, needed = needed })
				end
			end
		end
	end

	table.sort(items, function(a, b) return a.name < b.name end)
	local order = {}
	for i = 1, table.getn(items) do
		order[i] = items[i].text
		totals[items[i].text] = items[i].needed
	end

	return order, totals
end

-- ------------------------------------------------------------------
-- Paced sender - posts one line at a time on a short timer instead of
-- all at once in a loop, so a long materials list doesn't trip chat
-- spam throttling.
-- ------------------------------------------------------------------
local ATSWQT_chatSendQueue = {}
local ATSWQT_chatSendTimer = 0
local ATSWQT_CHAT_SEND_INTERVAL = 0.3

-- Same channel-detection ATSW's own Shift+Left-Click send-to-chat
-- uses (ATSW_AddTradeSkillReagentLinksToChatFrame in atsw.lua).
local function ATSWQT_DetermineChatTarget()
	local channel, chatnumber
	if WIM_EditBoxInFocus ~= nil then
		channel = "WHISPER"
		chatnumber = WIM_EditBoxInFocus:GetParent().theUser
	elseif ChatFrameEditBox then
		channel = ChatFrameEditBox.chatType
		if channel == "WHISPER" then
			if ChatFrameEditBox:IsVisible() then
				chatnumber = ChatFrameEditBox.tellTarget
			else
				channel = "SAY"
			end
		elseif channel == "CHANNEL" then
			chatnumber = ChatFrameEditBox.channelTarget
		end
	end
	return channel, chatnumber
end

-- atsw_qt_sendchannel (set via "/atswqt channel <value>") lets you
-- override the auto-detected channel if you ever need to.
local function ATSWQT_SendOneLine(msg)
	if atsw_qt_sendchannel then
		local ok = pcall(SendChatMessage, msg, atsw_qt_sendchannel.type, nil, atsw_qt_sendchannel.target)
		if ok then return true end
	end

	local channel, chatnumber = ATSWQT_DetermineChatTarget()
	if channel then
		local ok = pcall(SendChatMessage, msg, channel, nil, chatnumber)
		if ok then return true end
	end

	return pcall(SendChatMessage, msg, "SAY")
end

local ATSWQT_ChatSendFrame = CreateFrame("Frame")
ATSWQT_ChatSendFrame:Hide()
ATSWQT_ChatSendFrame:SetScript("OnUpdate", function()
	ATSWQT_chatSendTimer = ATSWQT_chatSendTimer + (arg1 or 0)
	if ATSWQT_chatSendTimer < ATSWQT_CHAT_SEND_INTERVAL then return end
	ATSWQT_chatSendTimer = 0

	local msg = table.remove(ATSWQT_chatSendQueue, 1)
	if msg then
		ATSWQT_SendOneLine(msg)
	end

	if table.getn(ATSWQT_chatSendQueue) == 0 then
		this:Hide()
	end
end)

function ATSWQT_SendReagentsToChat(onlyMissing)
	if ATSWQT_ChatSendFrame:IsShown() and table.getn(ATSWQT_chatSendQueue) > 0 then
		DEFAULT_CHAT_FRAME:AddMessage("ATSW Quick Tools: already sending reagent list, please wait...")
		return
	end

	local order, totals = ATSWQT_AggregateQueueReagents(onlyMissing)
	local count = table.getn(order)

	if count == 0 then
		DEFAULT_CHAT_FRAME:AddMessage(
			"ATSW Quick Tools: nothing to send ("..(onlyMissing and "no missing reagents" or "queue is empty")..", or its recipes aren't in the currently open profession window).")
		return
	end

	local header = onlyMissing
		and ("Missing materials for the queue ("..count.." item(s)):")
		or ("Materials needed for the queue ("..count.." item(s)):")
	ATSWQT_chatSendQueue = { header }
	for i = 1, count do
		local link = order[i]
		table.insert(ATSWQT_chatSendQueue, totals[link].."x "..link)
	end
	ATSWQT_chatSendTimer = 0
	ATSWQT_ChatSendFrame:Show()
	DEFAULT_CHAT_FRAME:AddMessage("ATSW Quick Tools: sending "..count.." reagent line(s)...")
end
