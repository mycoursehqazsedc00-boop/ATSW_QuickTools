# ATSW Quick Tools (Patched for WoW 1.12 / Turtle WoW)

> Companion addon for [AdvancedTradeSkillWindow](https://github.com/mycoursehqazsedc00-boop/AdvancedTradeSkillWindow) adding a Queue ETA bar, profession quick-switch bar, Aux reagent pricing & craft profit summary, paced "Send Mats" chat export, and "Bought" checkboxes.

Repository: [https://github.com/mycoursehqazsedc00-boop/ATSW_QuickTools](https://github.com/mycoursehqazsedc00-boop/ATSW_QuickTools)
Required Base Addon: [https://github.com/mycoursehqazsedc00-boop/AdvancedTradeSkillWindow](https://github.com/mycoursehqazsedc00-boop/AdvancedTradeSkillWindow)

## Client Mods Used
| Mod | Purpose in this addon | Required? |
|---|---|---|
| ClassicAPI | `GetSpellInfo(name)` DBC cast-time lookup, `hooksecurefunc` | Optional |
| Nampower | `GetCastInfo()` exact live cast-progress readout & ping-free cast-time learning (`castDurationMs`) | Optional |
| UnitXP SP3 | `UnitXP("notify", "taskbarIcon")` OS taskbar flash on queue completion | Optional |

*(Also integrates with [Aux](https://github.com/wow-aux/aux-addon) when loaded for live vendor/AH pricing. All optional mods degrade gracefully when absent.)*

## Features
- **Queue ETA Bar & Hover Financials:** Live progress bar and estimated remaining time (`M:SS`) for the active craft and full queue (idle-gated `OnUpdate`, paused `Continue` indicator, ping-free Nampower cast-time learning), plus a hover tooltip showing total Queue Reagent Cost, estimated AH Gross, and Net Profit.
- **Profession Quick-Switch Bar:** One-click buttons above `ATSWFrame` for all known professions (including Turtle WoW's Jewelcrafting, Survival, Smelting) with an active gold highlight and automatic `SKILL_LINES_CHANGED` refresh.
- **Aux Reagent Pricing & Craft Profit:** Displays per-reagent vendor/AH prices on `ATSWReagent1..8` (with persistent `atsw_qt_pricecache` fallback `~`) plus total craft cost and estimated AH profit/loss next to `ATSWReagentLabel` (optional 5% AH cut via `/atswqt ahcut`).
- **Paced "Send Mats" Button:** Sends sorted queue reagents (or Shift-Click for **missing reagents only**, automatically skipping items marked Bought) to your active chat channel or pinned `/atswqt channel`, paced at `0.3s` per line.
- **Synchronized Bought Checkboxes:** Marks reagents as bought on both `ATSWReagentFrame` and the AH `ATSWShoppingListFrame` (`atsw_qt_bought`), synced in real time with a **Clear Bought** button.

## What Was Added / Improved
- **Synergy Callback Bus:** Subscribes to `ATSW_RegisterCallback` (`PROFESSION_CHANGED`, `QUEUE_UPDATED`, `SELECTION_CHANGED`, `QUEUE_STARTED`, `QUEUE_PAUSED`, `CAST_START`, `CAST_STOP`, `QUEUE_FINISHED`, `QUEUE_INTERRUPTED`, `REAGENTS_UPDATED`) when paired with patched ATSW, with automatic `ATSWQT_Hook` fallback for upstream ATSW.
- **Fixed Vanilla Lua 5.0 compatibility:** Replaced `...` in `ATSWQT_Hook` with `arg`/`unpack(arg)` (preserving return values), replaced `string.match` with `string.find`, and updated `OnUpdate`/`OnClick` handlers in `SendReagents.lua` and `BoughtReagents.lua` to use `this`/`arg1` so the addon runs cleanly without ClassicAPI.
- **Fixed bugs:** Fixed `ATSWQT_NotifyQueueFinished` never firing on normal queue completion, filtered `atsw_qt_seenprofessions` to the current character's spellbook so alt/unlearned professions never appear, fixed `CheckButton` highlight desync on click, prevented false green profit when reagent costs are incomplete, forced AH market price (ignoring vendor buy price) for crafted outputs, and added `[name]` fallback in `SendReagents.lua` for uncached reagents.
- **Improved performance & QoL:** Idle-gated `ATSWQT_QueueBar_OnUpdate` (0 CPU when not crafting), learned exact ping-free cast times from Nampower `GetCastInfo().castDurationMs`, synced Bought checkboxes to `ATSWShoppingListFrame` (AH) and Shift-Click `Send Mats`, added Queue Cost/Profit hover tooltip, `/atswqt ahcut` 5% AH fee toggle, and `SKILL_LINES_CHANGED` auto-refresh.

## Usage
- `/atswqt` — Refresh profession bar, queue bar, and Aux status.
- `/atswqt status` — Print detected client mods, bridge mode (`CallbackBus`/`Hooks`), Aux cache count, and settings.
- `/atswqt notify [on|off]` — Toggle queue-completion sound and UnitXP taskbar flash.
- `/atswqt ahcut [on|off]` — Toggle 5% Auction House fee deduction in profit estimates.
- `/atswqt channel [say|party|raid|guild|officer|yell|# |auto]` — Pin or un-pin the "Send Mats" target channel.
- `/atswqt trace` — Toggle debug trace messages.

## Credits & License
- Original addon: `ATSW_QuickTools` / [AdvancedTradeSkillWindow](https://github.com/mycoursehqazsedc00-boop/AdvancedTradeSkillWindow) (`laytya`, `Rene Schneider`)
- Fork / patches: [ATSW_QuickTools](https://github.com/mycoursehqazsedc00-boop/ATSW_QuickTools)
- License: Same as original addon.
