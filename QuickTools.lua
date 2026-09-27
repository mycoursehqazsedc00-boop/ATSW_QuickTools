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
			original(...)
			after(...)
		end)
	end
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

local function ATSWQT_RemainingOnCurrentCast(perItemSeconds)
	-- Prefer nampower's live, exact timer if it's loaded.
	if type(GetCastInfo) == "function" then
		local ok, info = pcall(GetCastInfo)
		if ok and type(info) == "table" and info.castRemainingMs and info.castRemainingMs > 0 then
			return info.castRemainingMs / 1000
		end
	end
	-- Fall back to timing it ourselves from SPELLCAST_START.
	if ATSWQT_castStartTime then
		return math.max(perItemSeconds - (GetTime() - ATSWQT_castStartTime), 0)
	end
	return perItemSeconds
end

local function ATSWQT_CurrentCastFraction(perItemSeconds)
	if type(GetCastInfo) == "function" then
		local ok, info = pcall(GetCastInfo)
		if ok and type(info) == "table" and info.castDurationMs and info.castDurationMs > 0 and info.castRemainingMs then
			return 1 - (info.castRemainingMs / info.castDurationMs)
		end
	end
	if ATSWQT_castStartTime and perItemSeconds > 0 then
		return math.min((GetTime() - ATSWQT_castStartTime) / perItemSeconds, 1)
	end
	return 0
end

-- Seconds left to clear the whole queue.
local function ATSWQT_EstimateQueueSeconds()
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
			total = total + ATSWQT_RemainingOnCurrentCast(per) + per * math.max(repeats - 1, 0)
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

	local totalSeconds = ATSWQT_EstimateQueueSeconds()
	if atsw_processing then
		local per = ATSWQT_GetCastSeconds(atsw_queue[1].name)
		ATSWQT_QueueBarBar:SetValue(ATSWQT_CurrentCastFraction(per))
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

	ATSWQT_Hook("ATSWFrame_SetSelection", function()
		ATSWQT_UpdateProfessionHighlight()
		if type(ATSWQT_RefreshReagentPrices) == "function" then
			ATSWQT_RefreshReagentPrices()
		end
	end)

	ATSWQT_Hook("ATSW_ProcessIt", function()
		ATSWQT_castStartTime = GetTime()
	end)

	ATSWQT_Hook("ATSW_SpellcastStart", function()
		ATSWQT_castStartTime = GetTime()
	end)

	ATSWQT_Hook("ATSW_SpellcastStop", function()
		-- Learn/refine this recipe's real cast time from what we just measured,
		-- so future ETA estimates for it get more accurate over time.
		if ATSWQT_castStartTime and atsw_processingname and atsw_processingname ~= "" then
			local measured = GetTime() - ATSWQT_castStartTime
			if measured > 0.3 and measured < 30 then
				atsw_qt_recipetime[atsw_processingname] = measured
			end
		end
		ATSWQT_castStartTime = nil
		ATSWQT_RefreshQueueBar()
	end)

	ATSWQT_Hook("ATSW_SpellcastInterrupted", function()
		ATSWQT_castStartTime = nil
		ATSWQT_RefreshQueueBar()
	end)

	ATSWQT_Hook("ATSW_DeleteQueue", function()
		ATSWQT_RefreshQueueBar()
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

	return true
end

-- ------------------------------------------------------------------
-- Slash command: manual refresh, in case a profession is learned
-- mid-session and the auto-refresh on window-open hasn't run yet.
-- ------------------------------------------------------------------
SLASH_ATSWQT1 = "/atswqt"
SlashCmdList["ATSWQT"] = function()
	local created = ATSWQT_CreateBars()
	ATSWQT_RefreshProfessionBar()
	ATSWQT_RefreshQueueBar()
	local msg = "ATSW Quick Tools: refreshed ("..table.getn(ATSWQT_known).." known profession(s))."
	if not created then
		msg = msg.."  |cffff3333ATSWFrame not found.|r"
	end
	if type(ATSWQT_AuxStatus) == "function" then
		msg = msg.."  "..ATSWQT_AuxStatus()
	end
	DEFAULT_CHAT_FRAME:AddMessage(msg)
end

-- ------------------------------------------------------------------
-- Everything below runs from PLAYER_LOGIN (fires after every addon's
-- files have executed, so this works no matter which addon's folder
-- happened to load first) instead of at file-load time.
-- ------------------------------------------------------------------
local ATSWQT_InitFrame = CreateFrame("Frame")
ATSWQT_InitFrame:RegisterEvent("PLAYER_LOGIN")
ATSWQT_InitFrame:SetScript("OnEvent", function()
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
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ATSW Quick Tools|r loaded, AdvancedTradeSkillWindow found.")
	else
		DEFAULT_CHAT_FRAME:AddMessage("|cffff3333ATSW Quick Tools|r loaded, but AdvancedTradeSkillWindow (ATSWFrame) was NOT found - check that addon is enabled and its folder loaded without errors.")
	end
end)
