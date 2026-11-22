-- ATSW Quick Tools
-- Adds to AdvancedTradeSkillWindow (ATSW), without editing its files:
--   1) A queue ETA bar - progress of the item currently being crafted,
--      plus an estimate of how long the whole queue will take.
--   2) A profession quick-switch bar - one click swaps ATSW to a
--      different known profession without closing the window.
--
-- Opportunistically uses (all optional, everything degrades gracefully
-- if a mod isn't loaded):
--   - ClassicAPI's GetSpellInfo(name)  -> real DBC cast time per recipe
--   - nampower's GetCastInfo()         -> exact remaining ms on the live cast
--   - ClassicAPI's hooksecurefunc      -> used if present, otherwise we
--                                          fall back to manual hooking so
--                                          this still works on a bare 1.12 client

-- ------------------------------------------------------------------
-- Small hook helper (works with or without ClassicAPI's hooksecurefunc)
-- ------------------------------------------------------------------
function ATSWQT_Hook(funcName, after)
	local original = getglobal(funcName)
	if type(original) ~= "function" then
		return
	end
	if type(hooksecurefunc) == "function" then
		hooksecurefunc(funcName, after)
	else
		setglobal(funcName, function(...)
			local args = arg
			original(unpack(args))
			after(unpack(args))
		end)
	end
end

-- ------------------------------------------------------------------
-- Client mod feature detection (populated at PLAYER_LOGIN)
-- ------------------------------------------------------------------
ATSWQT_Mods = {
	capi = false,
	np = false,
	xp3 = false,
}

ATSWQT_traceEnabled = false

function ATSWQT_Trace(msg)
	if ATSWQT_traceEnabled then
		DEFAULT_CHAT_FRAME:AddMessage("|cff99ccff[ATSWQT]|r "..tostring(msg))
	end
end

local function ATSWQT_DetectMods()
	ATSWQT_Mods.capi = (CLASSIC_API_VERSION ~= nil)
	ATSWQT_Mods.np = (type(GetNampowerVersion) == "function")
	ATSWQT_Mods.xp3 = pcall(UnitXP, "nop", "nop") and true or false
end

-- ------------------------------------------------------------------
-- Professions that open a craft/tradeskill window in ATSW.
--
-- Detection layers, so custom or server-added professions (this list
-- includes Turtle WoW's Jewelcrafting and Survival, plus vanilla's
-- easy-to-forget Smelting) show up without needing exact tab names:
--   1. Whatever the game itself lists under the spellbook's
--      "Professions" tab - covers any profession, stock or custom,
--      that's actually filed there.
--   2. The static list below, matched by name anywhere in the
--      spellbook - always runs too, not just as a fallback, so a
--      profession filed outside that tab on a given server still
--      gets picked up.
--   3. Anything actually seen opening a tradeskill/craft window before
--      (recorded in atsw_qt_seenprofessions, a SavedVariable) - a
--      permanent backstop that self-corrects the first time you open
--      a profession #1 and #2 both missed.
-- ------------------------------------------------------------------
local ATSWQT_PROFESSIONS_HINTS = {
	"Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering",
	"First Aid", "Leatherworking", "Tailoring", "Smelting",
	"Jewelcrafting", "Survival",
}

-- Shows up in the Professions tab but doesn't open a tradeskill
-- window (Fishing has no craft/recipe list).
local ATSWQT_PROFESSIONS_EXCLUDE = { Fishing = true }

atsw_qt_seenprofessions = atsw_qt_seenprofessions or {}

local ATSWQT_known = {}   -- populated by ATSWQT_ScanKnownProfessions()

local function ATSWQT_FindProfessionsTabRange()
	local numTabs = GetNumSpellTabs()
	for tab = 1, numTabs do
		local name, _, offset, numSpells = GetSpellTabInfo(tab)
		if name == "Professions" then
			return offset, numSpells
		end
	end
	return nil
end

local function ATSWQT_IconForSpellName(wanted)
	local i = 1
	while true do
		local name = GetSpellName(i, BOOKTYPE_SPELL)
		if not name then break end
		if name == wanted then return GetSpellTexture(i, BOOKTYPE_SPELL) end
		i = i + 1
	end
	return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Pure stock-API spellbook scan - works with no client mods at all.
local function ATSWQT_ScanKnownProfessions()
	ATSWQT_known = {}
	local seen = {}

	local function add(name, icon)
		if name and name ~= "" and not seen[name] and not ATSWQT_PROFESSIONS_EXCLUDE[name] then
			seen[name] = true
			table.insert(ATSWQT_known, { name = name, icon = icon })
		end
	end

	local offset, numSpells = ATSWQT_FindProfessionsTabRange()
	if offset then
		for i = offset + 1, offset + numSpells do
			add(GetSpellName(i, BOOKTYPE_SPELL), GetSpellTexture(i, BOOKTYPE_SPELL))
		end
	end

	-- Always also match the static list by name, anywhere in the
	-- spellbook - not just when the "Professions" tab search above
	-- comes up empty. Covers professions some servers file outside
	-- that tab (or under a differently-named one) even when other
	-- professions are found fine.
	do
		local i = 1
		while true do
			local name = GetSpellName(i, BOOKTYPE_SPELL)
			if not name then break end
			for _, prof in ipairs(ATSWQT_PROFESSIONS_HINTS) do
				if name == prof then add(name, GetSpellTexture(i, BOOKTYPE_SPELL)) end
			end
			i = i + 1
		end
	end

	for name in pairs(atsw_qt_seenprofessions) do
		if not seen[name] then
			add(name, ATSWQT_IconForSpellName(name))
		end
	end

	return ATSWQT_known
end

-- ------------------------------------------------------------------
-- Profession quick-switch bar
-- ------------------------------------------------------------------
local ATSWQT_profButtons = {}

local function ATSWQT_LayoutProfessionBar()
	if not ATSWQT_ProfessionBar then return end
	local count = table.getn(ATSWQT_known)
	local buttonSize, spacing = 30, 4
	local width = math.max(count * (buttonSize + spacing) + spacing, 40)
	ATSWQT_ProfessionBar:SetWidth(width)

	for i = 1, math.max(count, table.getn(ATSWQT_profButtons)) do
		local btn = ATSWQT_profButtons[i]
		if i <= count then
			local prof = ATSWQT_known[i]
			if not btn then
				btn = CreateFrame("CheckButton", "ATSWQT_ProfButton"..i, ATSWQT_ProfessionBar, "ATSWQT_ProfButtonTemplate")
				ATSWQT_profButtons[i] = btn
			end
			btn.professionName = prof.name
			getglobal(btn:GetName().."Icon"):SetTexture(prof.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
			btn:ClearAllPoints()
			btn:SetPoint("LEFT", ATSWQT_ProfessionBar, "LEFT", spacing + (i - 1) * (buttonSize + spacing), 0)
			btn:Show()
		elseif btn then
			btn:Hide()
		end
	end

	if count == 0 then
		ATSWQT_ProfessionBar:Hide()
	else
		ATSWQT_ProfessionBar:Show()
	end
end

function ATSWQT_RefreshProfessionBar()
	if atsw_selectedskill and atsw_selectedskill ~= "" then
		atsw_qt_seenprofessions[atsw_selectedskill] = true
	end
	ATSWQT_ScanKnownProfessions()
	ATSWQT_LayoutProfessionBar()
	ATSWQT_UpdateProfessionHighlight()
end

function ATSWQT_UpdateProfessionHighlight()
	for i = 1, table.getn(ATSWQT_profButtons) do
		local btn = ATSWQT_profButtons[i]
		if btn and btn:IsShown() then
			btn:SetChecked(btn.professionName == atsw_selectedskill)
		end
	end
end

function ATSWQT_ProfessionButton_OnClick(button)
	if button.professionName then
		CastSpellByName(button.professionName)
	end
end

function ATSWQT_ProfessionButton_OnEnter(button)
	GameTooltip:SetOwner(button, "ANCHOR_TOP")
	GameTooltip:SetText(button.professionName or "")
	GameTooltip:Show()
end

-- ------------------------------------------------------------------
-- Queue ETA estimation
-- ------------------------------------------------------------------
atsw_qt_recipetime = atsw_qt_recipetime or {}   -- SavedVariable: recipeName -> seconds, learned/measured over time
local ATSWQT_DEFAULT_CAST = 3.0
local ATSWQT_castStartTime = nil

-- Best-effort cast-time lookup for one recipe: measured value (from
-- actually crafting it) > ClassicAPI's DBC lookup > flat 3s default.
local function ATSWQT_GetCastSeconds(recipeName)
	local cached = atsw_qt_recipetime[recipeName]
	if cached then return cached end

	if type(GetSpellInfo) == "function" then
		local ok, _, _, _, _, _, _, castTime = pcall(GetSpellInfo, recipeName)
		-- castTime==0 is a real answer (a genuinely instant-cast recipe),
		-- so only fall through to the guess when the lookup itself failed
		-- (nil - spell not found / GetSpellInfo errored).
		if ok and castTime ~= nil then
			return castTime / 1000
		end
	end

	return ATSWQT_DEFAULT_CAST
end

local function ATSWQT_GetNampowerCastProgress()
	if not (ATSWQT_Mods.np and type(GetCastInfo) == "function") then
		return nil, nil
	end
	local ok, info = pcall(GetCastInfo)
	if ok and type(info) == "table" then
		local rem = info.castRemainingMs
		local dur = info.castDurationMs
		local remSec = (rem and rem > 0) and (rem / 1000) or nil
		local frac = (dur and dur > 0 and rem) and (1 - (rem / dur)) or nil
		return remSec, frac
	end
	return nil, nil
end

local function ATSWQT_RemainingOnCurrentCast(perItemSeconds, npRemaining)
	if npRemaining then
		return npRemaining
	end
	-- Fall back to timing it ourselves from SPELLCAST_START.
	if ATSWQT_castStartTime then
		return math.max(perItemSeconds - (GetTime() - ATSWQT_castStartTime), 0)
	end
	return perItemSeconds
end

local function ATSWQT_CurrentCastFraction(perItemSeconds, npFraction)
	if npFraction then
		return npFraction
	end
	if ATSWQT_castStartTime and perItemSeconds > 0 then
		return math.min((GetTime() - ATSWQT_castStartTime) / perItemSeconds, 1)
	end
	return 0
end

-- Seconds left to clear the whole queue.
local function ATSWQT_EstimateQueueSeconds(npRemaining)
	if not atsw_queue then return 0 end
	local total = 0
	local n = table.getn(atsw_queue)
	for i = 1, n do
		local entry = atsw_queue[i]
		local per = ATSWQT_GetCastSeconds(entry.name)
		local count = entry.count or 1
		if i == 1 and atsw_processing then
			local repeats = count
			if type(GetTradeskillRepeatCount) == "function" then
				local ok, r = pcall(GetTradeskillRepeatCount)
				if ok and r and r > 0 then repeats = r end
			end
			total = total + ATSWQT_RemainingOnCurrentCast(per, npRemaining) + per * math.max(repeats - 1, 0)
		else
			total = total + per * count
		end
	end
	return total
end

local function ATSWQT_FormatTime(seconds)
	seconds = math.floor(math.max(seconds, 0) + 0.5)
	local m = math.floor(seconds / 60)
	local s = seconds - m * 60
	if s < 10 then s = "0"..s end
	return m..":"..s
end

function ATSWQT_RefreshQueueBar()
	if not (ATSWQT_QueueBarBar and ATSWQT_QueueBarText) then return end
	local n = atsw_queue and table.getn(atsw_queue) or 0
	if n == 0 then
		ATSWQT_QueueBarBar:SetValue(0)
		ATSWQT_QueueBarText:SetText("Queue is empty")
		return
	end

	local npRemaining, npFraction = ATSWQT_GetNampowerCastProgress()
	local totalSeconds = ATSWQT_EstimateQueueSeconds(npRemaining)
	if atsw_processing then
		local per = ATSWQT_GetCastSeconds(atsw_queue[1].name)
		ATSWQT_QueueBarBar:SetValue(ATSWQT_CurrentCastFraction(per, npFraction))
		ATSWQT_QueueBarText:SetText(
			"Crafting "..atsw_queue[1].name.."  |  Queue ETA: "..ATSWQT_FormatTime(totalSeconds))
	else
		ATSWQT_QueueBarBar:SetValue(0)
		ATSWQT_QueueBarText:SetText(
			n.." item(s) queued  |  Est. time: "..ATSWQT_FormatTime(totalSeconds))
	end
end

local ATSWQT_elapsedSinceUpdate = 0
function ATSWQT_QueueBar_OnUpdate(elapsed)
	if not (ATSWFrame and ATSWFrame:IsVisible()) then return end
	ATSWQT_elapsedSinceUpdate = ATSWQT_elapsedSinceUpdate + (elapsed or 0)
	if ATSWQT_elapsedSinceUpdate < 0.2 then return end
	ATSWQT_elapsedSinceUpdate = 0
	ATSWQT_RefreshQueueBar()
end

-- ------------------------------------------------------------------
-- Hooks into ATSW's existing functions (no edits to ATSW's own files).
-- Installed from PLAYER_LOGIN (below), not here at file-load time:
-- addon files can load in either order, so ATSW's functions might not
-- exist yet the instant this file runs. By PLAYER_LOGIN every addon's
-- files have executed, so this is safe regardless of load order.
-- ------------------------------------------------------------------
function ATSWQT_InstallHooks()
	ATSWQT_Hook("ATSW_ShowWindow", function()
		ATSWQT_RefreshProfessionBar()
		ATSWQT_RefreshQueueBar()
	end)

	ATSWQT_Hook("ATSWFrame_UpdateQueue", function()
		ATSWQT_RefreshQueueBar()
	end)

	ATSWQT_Hook("ATSWFrame_SetSelection", function(id, wasClicked)
		ATSWQT_UpdateProfessionHighlight()
		if type(ATSWQT_RefreshReagentPrices) == "function" then
			ATSWQT_RefreshReagentPrices(id)
		end
	end)

local ATSWQT_wasProcessing = false

local function ATSWQT_NotifyQueueFinished()
	if atsw_qt_notify == false then return end
	if ATSWQT_Mods.xp3 then
		pcall(UnitXP, "notify", "taskbarIcon")
	end
	PlaySound("ReadyCheck")
	ATSWQT_Trace("Queue finished notification sent.")
end

	ATSWQT_Hook("ATSW_ProcessIt", function()
		ATSWQT_castStartTime = GetTime()
		ATSWQT_wasProcessing = true
	end)

	ATSWQT_Hook("ATSW_SpellcastStart", function()
		ATSWQT_castStartTime = GetTime()
	end)

	ATSWQT_Hook("ATSW_SpellcastStop", function()
		-- Learn/refine this recipe's real cast time from what we just measured,
		-- only when ATSW was actually crafting so unrelated casts don't pollute it.
		if (atsw_processing or ATSWQT_wasProcessing) and ATSWQT_castStartTime and atsw_processingname and atsw_processingname ~= "" then
			local measured = GetTime() - ATSWQT_castStartTime
			if measured > 0.3 and measured < 30 then
				atsw_qt_recipetime[atsw_processingname] = measured
				ATSWQT_Trace("Learned cast time for "..atsw_processingname..": "..string.format("%.2fs", measured))
			end
		end
		ATSWQT_castStartTime = nil
		if ATSWQT_wasProcessing and (not atsw_processing) and (not atsw_queue or table.getn(atsw_queue) == 0) then
			ATSWQT_wasProcessing = false
			ATSWQT_NotifyQueueFinished()
		end
		ATSWQT_RefreshQueueBar()
	end)

	ATSWQT_Hook("ATSW_SpellcastInterrupted", function()
		ATSWQT_castStartTime = nil
		ATSWQT_wasProcessing = false
		ATSWQT_RefreshQueueBar()
	end)

	ATSWQT_Hook("ATSW_DeleteQueue", function()
		ATSWQT_RefreshQueueBar()
	end)

	ATSWQT_Hook("ATSW_ShowNecessaryReagents", function()
		if type(ATSWQT_RefreshReagentWindow) == "function" then
			ATSWQT_RefreshReagentWindow()
		end
	end)
end

-- ------------------------------------------------------------------
-- Creates the two real bar frames from the virtual templates in
-- QuickTools.xml, parenting/anchoring them to the real ATSWFrame
-- object (not by name) - see the comment at the top of that file for
-- why that matters. Safe to call more than once; only creates once.
-- ------------------------------------------------------------------
function ATSWQT_CreateBars()
	if not ATSWFrame then return false end

	if not ATSWQT_ProfessionBar then
		ATSWQT_ProfessionBar = CreateFrame("Frame", "ATSWQT_ProfessionBar", ATSWFrame, "ATSWQT_ProfessionBarTemplate")
		ATSWQT_ProfessionBar:SetPoint("BOTTOMLEFT", ATSWFrame, "TOPLEFT", 10, 2)
		ATSWQT_ProfessionBar:Show()
	end

	if not ATSWQT_QueueBarBar then
		ATSWQT_QueueBarBar = CreateFrame("StatusBar", "ATSWQT_QueueBarBar", ATSWFrame, "ATSWQT_QueueBarTemplate")
		ATSWQT_QueueBarBar:SetPoint("TOPLEFT", ATSWFrame, "BOTTOMLEFT", 10, -4)
		ATSWQT_QueueBarBar:Show()
		ATSWQT_QueueBarText = getglobal("ATSWQT_QueueBarBarText")
	end

	if not ATSWQT_SendReagentsButton and type(ATSWQT_SendReagentsToChat) == "function" then
		ATSWQT_SendReagentsButton = CreateFrame("Button", "ATSWQT_SendReagentsButton", ATSWQT_QueueBarBar, "UIPanelButtonTemplate")
		ATSWQT_SendReagentsButton:SetWidth(90)
		ATSWQT_SendReagentsButton:SetHeight(22)
		ATSWQT_SendReagentsButton:SetPoint("LEFT", ATSWQT_QueueBarBar, "RIGHT", 6, 0)
		getglobal(ATSWQT_SendReagentsButton:GetName().."Text"):SetText("Send Mats")
		ATSWQT_SendReagentsButton:SetScript("OnClick", function()
			ATSWQT_SendReagentsToChat(IsShiftKeyDown())
		end)
		ATSWQT_SendReagentsButton:SetScript("OnEnter", function()
			GameTooltip:SetOwner(this, "ANCHOR_TOP")
			GameTooltip:SetText("Send Queue Reagents")
			GameTooltip:AddLine("Click: send all reagents in queue", 1, 1, 1)
			GameTooltip:AddLine("Shift-Click: send only missing reagents", 0.8, 0.9, 1)
			GameTooltip:Show()
		end)
		ATSWQT_SendReagentsButton:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		ATSWQT_SendReagentsButton:Show()
	end

	return true
end

-- ------------------------------------------------------------------
-- /atswqt channel <...> - pins (or clears) which channel "Send Mats"
-- uses, for clients where auto-detecting the chat box's current
-- channel isn't reliable. See SendReagents.lua for how this is read.
-- ------------------------------------------------------------------
function ATSWQT_SetSendChannel(input)
	input = (input and string.lower(input)) or ""

	if input == "" then
		if atsw_qt_sendchannel then
			local label = atsw_qt_sendchannel.type..(atsw_qt_sendchannel.target and (" "..atsw_qt_sendchannel.target) or "")
			DEFAULT_CHAT_FRAME:AddMessage("ATSW Quick Tools: Send Mats channel is pinned to "..label..
				". Use /atswqt channel <say|party|raid|guild|officer|yell|#> to change it, or /atswqt channel auto to un-pin.")
		else
			DEFAULT_CHAT_FRAME:AddMessage("ATSW Quick Tools: Send Mats is auto-detecting your current channel. "..
				"Use /atswqt channel <say|party|raid|guild|officer|yell|#> to pin one instead.")
		end
		return
	end

	if input == "auto" then
		atsw_qt_sendchannel = nil
		DEFAULT_CHAT_FRAME:AddMessage("ATSW Quick Tools: Send Mats will auto-detect your current channel again.")
		return
	end

	local named = { say = "SAY", party = "PARTY", raid = "RAID", guild = "GUILD", officer = "OFFICER", yell = "YELL" }
	if named[input] then
		atsw_qt_sendchannel = { type = named[input] }
		DEFAULT_CHAT_FRAME:AddMessage("ATSW Quick Tools: Send Mats pinned to "..named[input]..".")
		return
	end

	local num = tonumber(input)
	if num then
		atsw_qt_sendchannel = { type = "CHANNEL", target = num }
		DEFAULT_CHAT_FRAME:AddMessage("ATSW Quick Tools: Send Mats pinned to channel #"..num..".")
		return
	end

	DEFAULT_CHAT_FRAME:AddMessage("ATSW Quick Tools: didn't understand \""..input..
		"\" - try say, party, raid, guild, officer, yell, or a channel number.")
end

-- ------------------------------------------------------------------
-- Slash command: manual refresh, in case a profession is learned
-- mid-session and the auto-refresh on window-open hasn't run yet.
-- Also handles "/atswqt channel ..." (see above).
-- ------------------------------------------------------------------
SLASH_ATSWQT1 = "/atswqt"
SlashCmdList["ATSWQT"] = function(msg)
	local _, _, cmd, rest = string.find(msg or "", "^%s*(%S*)%s*(.-)%s*$")
	cmd = string.lower(cmd or "")
	if cmd == "channel" then
		ATSWQT_SetSendChannel(rest)
		return
	elseif cmd == "trace" then
		ATSWQT_traceEnabled = not ATSWQT_traceEnabled
		DEFAULT_CHAT_FRAME:AddMessage("ATSW Quick Tools: trace "..(ATSWQT_traceEnabled and "|cff33ff99ON|r" or "|cffff6666OFF|r"))
		return
	elseif cmd == "notify" then
		local arg = string.lower(rest or "")
		if arg == "on" then
			atsw_qt_notify = true
		elseif arg == "off" then
			atsw_qt_notify = false
		else
			atsw_qt_notify = (atsw_qt_notify == false) and true or false
		end
		DEFAULT_CHAT_FRAME:AddMessage("ATSW Quick Tools: queue-finish notify "..(atsw_qt_notify ~= false and "|cff33ff99ON|r" or "|cffff6666OFF|r"))
		return
	elseif cmd == "status" then
		local learned = 0
		for _ in pairs(atsw_qt_recipetime) do learned = learned + 1 end
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ATSW Quick Tools v"..ATSWQT_GetVersion().."|r")
		DEFAULT_CHAT_FRAME:AddMessage("  Mods: ClassicAPI="..tostring(ATSWQT_Mods.capi)..", Nampower="..tostring(ATSWQT_Mods.np)..", UnitXP="..tostring(ATSWQT_Mods.xp3))
		DEFAULT_CHAT_FRAME:AddMessage("  Professions="..table.getn(ATSWQT_known)..", LearnedRecipes="..learned..", Notify="..tostring(atsw_qt_notify ~= false))
		if type(ATSWQT_AuxStatus) == "function" then
			DEFAULT_CHAT_FRAME:AddMessage("  "..ATSWQT_AuxStatus())
		end
		return
	end

	local created = ATSWQT_CreateBars()
	ATSWQT_RefreshProfessionBar()
	ATSWQT_RefreshQueueBar()
	local chatmsg = "ATSW Quick Tools: refreshed ("..table.getn(ATSWQT_known).." known profession(s))."
	if not created then
		chatmsg = chatmsg.."  |cffff3333ATSWFrame not found.|r"
	end
	if type(ATSWQT_AuxStatus) == "function" then
		chatmsg = chatmsg.."  "..ATSWQT_AuxStatus()
	end
	DEFAULT_CHAT_FRAME:AddMessage(chatmsg)
end

-- ------------------------------------------------------------------
-- Version, read from the .toc so the login message always shows which
-- copy is actually loaded (handy for spotting a stale install).
-- ------------------------------------------------------------------
function ATSWQT_GetVersion()
	if type(GetAddOnMetadata) == "function" then
		local ok, v = pcall(GetAddOnMetadata, "ATSW_QuickTools", "Version")
		if ok and v and v ~= "" then return v end
	end
	return "?"
end

-- ------------------------------------------------------------------
-- Everything below runs from PLAYER_LOGIN (fires after every addon's
-- files have executed, so this works no matter which addon's folder
-- happened to load first) instead of at file-load time.
-- ------------------------------------------------------------------
local ATSWQT_InitFrame = CreateFrame("Frame")
ATSWQT_InitFrame:RegisterEvent("PLAYER_LOGIN")
ATSWQT_InitFrame:SetScript("OnEvent", function()
	ATSWQT_DetectMods()
	if atsw_qt_notify == nil then
		atsw_qt_notify = true
	end
	local found = ATSWQT_CreateBars()
	ATSWQT_InstallHooks()
	ATSWQT_RefreshProfessionBar()
	if type(ATSWQT_InitAuxPricing) == "function" then
		ATSWQT_InitAuxPricing()
	end

	-- One-line self-check so a silent failure is visible instead of
	-- just "the bars don't show up": if ATSW itself wasn't found,
	-- everything else in this addon is a no-op by design.
	if found then
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ATSW Quick Tools|r v"..ATSWQT_GetVersion().." loaded, AdvancedTradeSkillWindow found.")
	else
		DEFAULT_CHAT_FRAME:AddMessage("|cffff3333ATSW Quick Tools|r v"..ATSWQT_GetVersion().." loaded, but AdvancedTradeSkillWindow (ATSWFrame) was NOT found - check that addon is enabled and its folder loaded without errors.")
	end
end)
