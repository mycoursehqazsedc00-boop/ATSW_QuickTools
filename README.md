# ATSW Quick Tools (Patched for WoW 1.12 / Turtle WoW)

> Companion addon for [AdvancedTradeSkillWindow](https://github.com/laytya/AdvancedTradeSkillWindow-vanilla) adding a Queue ETA bar, profession quick-switch bar, Aux reagent pricing & craft profit summary, paced "Send Mats" chat export, and "Bought" checkboxes.

## Client Mods Used
| Mod | Purpose in this addon | Required? |
|---|---|---|
| ClassicAPI | `GetSpellInfo(name)` DBC cast-time lookup, `hooksecurefunc` | Optional |
| Nampower | `GetCastInfo()` exact live cast-progress readout | Optional |
| UnitXP SP3 | `UnitXP("notify", "taskbarIcon")` OS taskbar flash on queue completion | Optional |

*(Also integrates with [Aux](https://github.com/wow-aux/aux-addon) when loaded for live vendor/AH pricing. All optional mods degrade gracefully when absent.)*

## Features
- **Queue ETA Bar:** Live progress bar and estimated remaining time (`M:SS`) for the active craft and full queue, with learned per-recipe cast times (`atsw_qt_recipetime`).
- **Profession Quick-Switch Bar:** One-click buttons above `ATSWFrame` for all known professions (including Turtle WoW's Jewelcrafting, Survival, Smelting) with an active gold highlight.
- **Aux Reagent Pricing & Craft Profit:** Displays per-reagent vendor/AH prices on `ATSWReagent1..8` (with persistent `atsw_qt_pricecache` fallback `~`) plus total craft cost and estimated AH profit/loss next to `ATSWReagentLabel`.
- **Paced "Send Mats" Button:** Sends sorted queue reagents (or Shift-Click for **missing reagents only**) to your active chat channel or pinned `/atswqt channel`, paced at `0.3s` per line.
- **Bought Checkboxes:** Marks reagents as bought on `ATSWReagentFrame` (`atsw_qt_bought`) with a **Clear Bought** button.

## What Was Added / Improved
- **Fixed Vanilla Lua 5.0 compatibility:** Replaced `...` in `ATSWQT_Hook` with `arg`/`unpack(arg)`, replaced `string.match` with `string.find`, and updated `OnUpdate`/`OnClick` handlers in `SendReagents.lua` and `BoughtReagents.lua` to use `this`/`arg1` so the addon runs cleanly without ClassicAPI.
- **Fixed UI overlaps & highlight:** Moved `ATSWQT_RFBought1..20` checkboxes to the right of the `Missing` column so they no longer overlap `Inventory`, moved reagent prices to `BOTTOMRIGHT` of each slot to avoid overlapping the row below, and added a gold `CheckedTexture` to `ATSWQT_ProfButtonTemplate`.
- **Improved performance & safety:** Consolidated `GetCastInfo()` into a single call per `0.2s` tick, guarded `ATSW_SpellcastStop` cast-time learning to active ATSW crafts, sorted "Send Mats" output alphabetically, and prevented double-click queue overwrites.
- **Added:** Craft Cost vs AH Profit summary in `AuxPricing.lua`, Shift-Click "Send Missing Mats" mode, **Clear Bought** button, UnitXP SP3 queue-completion notification (`/atswqt notify`), `/atswqt status`, and `/atswqt trace`.

## Usage
- `/atswqt` — Refresh profession bar, queue bar, and Aux status.
- `/atswqt status` — Print detected client mods, Aux cache count, and settings.
- `/atswqt notify [on|off]` — Toggle queue-completion sound and UnitXP taskbar flash.
- `/atswqt channel [say|party|raid|guild|officer|yell|# |auto]` — Pin or un-pin the "Send Mats" target channel.
- `/atswqt trace` — Toggle debug trace messages.

## Credits & License
- Original addon: `ATSW_QuickTools` / `AdvancedTradeSkillWindow` (`laytya`)
- License: Same as original addon.
