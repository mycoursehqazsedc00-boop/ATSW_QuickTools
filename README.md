# ATSW Quick Tools

A companion addon for [AdvancedTradeSkillWindow](https://github.com/laytya/AdvancedTradeSkillWindow-vanilla) (ATSW) on WoW vanilla/1.12. It hooks ATSW's already-public functions rather than editing its files, so it should keep working across ATSW updates as long as those function names stay the same.

## Features

### Queue ETA bar
Sits below the ATSW window.

- Idle: `N item(s) queued | Est. time: M:SS`
- Crafting: a filling progress bar for the item currently being made, plus `Crafting <name> | Queue ETA: M:SS` for the whole queue.
- Per-recipe cast time is resolved in order of preference:
  1. Learned from actually crafting it once (saved in `atsw_qt_recipetime`, so it gets more accurate across sessions).
  2. [ClassicAPI](https://github.com/brues-code/ClassicAPI)'s `GetSpellInfo(name)` DBC lookup, if loaded.
  3. A flat 3-second guess otherwise.
- If [nampower](https://github.com/brues-code/nampower) is loaded, the current item's progress uses its `GetCastInfo()` for an exact, real-time remaining-ms readout instead of our own stopwatch.

### Profession quick-switch bar
Sits above the ATSW window. One button per profession you actually know — click to jump straight to that profession's list inside ATSW (same as clicking its spellbook icon), without closing/reopening the window.

Detection is layered so custom/server-added professions (Jewelcrafting, Survival, Smelting, etc.) show up without needing their exact names hardcoded:

1. Whatever the game itself lists under the spellbook's **Professions** tab.
2. A static name list, checked anywhere in the spellbook (currently includes `Jewelcrafting` and `Survival` explicitly, for servers that file them outside that tab).
3. Anything you've actually opened a tradeskill/craft window for before — remembered permanently (`atsw_qt_seenprofessions`) as a backstop.

Works with zero client mods — it's a plain spellbook scan (`GetSpellTabInfo`/`GetSpellName`).

### Per-reagent Aux prices
On the reagent icons for whichever recipe is selected, if [Aux](https://github.com/wow-aux/aux-addon) (the AH addon) is installed: each reagent gets a small price underneath it — vendor price if sold with unlimited stock, otherwise Aux's Auction House value estimate. This is the same rule Aux's own "Total Cost" label already uses, so the per-line numbers add up to that total.

This piggybacks on a compatibility line Aux itself already ships (`if ATSWReagentLabel then ... end` in its `core/crafting.lua`) for the total, and reads the per-slot reagent icons directly — confirmed from `atsw.lua` itself to be `ATSWReagent1`..`ATSWReagent8`, each with `Name`/`Count` children, mirroring Blizzard's own `TradeSkillReagent1..8`. The reagent data itself (name/count/item link) comes straight from `atsw_tradeskilllist[*].reagents[*]` — the same already-resolved table ATSW's own queue/chat features read — rather than any live `GetTradeSkill*`/`GetCraft*` reagent calls of our own, so it's correct regardless of which of those two APIs the selected profession actually uses. Run `/atswqt aux` to check whether Aux was found, and how many prices are cached.

**Persistent price cache.** Every price this addon gets from Aux is saved into `atsw_qt_pricecache` (a SavedVariable, keyed by item), which lives under `WTF/Account/.../SavedVariables/` — a different place from the client's `WDB` cache, so it survives a WDB wipe. When Aux doesn't have a live answer (not loaded this session, or no data yet for that item), the last cached price is shown instead, prefixed with `~` to mark it as not current. Item links are parsed with Aux's own code when it's loaded, falling back to a small built-in parser otherwise — so cached prices still display even in a session where Aux itself hasn't loaded.

### "Send Mats" button
Next to the queue ETA bar. Posts one chat line per distinct reagent needed to finish the **whole** queue (item link + total count).

The totals are ATSW's own, not re-derived: it rebuilds and reads `atsw_queueditemlist` (the same table `ATSWInv_UpdateQueuedItemList()` builds for ATSW's internal use), pairing each reagent with its item link from `atsw_tradeskilllist`. Because that list only holds the currently-open profession's recipes (ATSW rebuilds it fresh each time you switch profession), this — like ATSW's own reagents-needed window — can only total reagents for queued items belonging to that profession. If your queue spans more than one, switch to each and click "Send Mats" separately.

Where it sends is worked out the same way ATSW's own Shift+Left-Click "send reagents to chat" feature does (`ATSW_AddTradeSkillReagentLinksToChatFrame` in `atsw.lua`): reading `ChatFrameEditBox.chatType` directly (with WIM support), then calling `SendChatMessage` — no `ChatEdit_ActivateChat`/`ChatEdit_SendText`, since not every client exposes those. `/atswqt channel <say|party|raid|guild|officer|yell|#>` (see [Slash commands](#slash-commands)) pins an explicit channel instead, if you ever need to override auto-detection.

Lines are paced one every ~0.3s instead of sent all at once, so a long materials list doesn't trip chat spam throttling.

### "Bought" checkbox on the reagents-needed window
A small checkbox next to each row of ATSW's own "reagents needed for the queue" window (`ATSWReagentFrame`, rows `ATSWRFReagent1`..`ATSWRFReagent20`). Check one off after buying that material and its name dims, so the list reads as "handled" while you work through it.

Marks are kept by reagent name (`atsw_qt_bought`, a SavedVariable) rather than by row number, since rows get reused for whatever's currently short — and they persist across a relog. They're never auto-cleared: once a reagent is fully supplied, ATSW's own filtering removes it from the list (so its checkbox disappears with it), but the mark itself is left in `atsw_qt_bought` rather than pruned, since there's no fully reliable way from here to tell "satisfied" apart from "not needed by whatever profession happens to be open right now."

## Requirements

| Addon | Required? | What it's used for |
|---|---|---|
| [AdvancedTradeSkillWindow](https://github.com/laytya/AdvancedTradeSkillWindow-vanilla) | **Required** | Everything hooks into it |
| [ClassicAPI](https://github.com/brues-code/ClassicAPI) | Optional | Real per-recipe cast times, `hooksecurefunc` |
| [nampower](https://github.com/brues-code/nampower) | Optional | Exact live cast-progress readout |
| [Aux](https://github.com/wow-aux/aux-addon) | Optional | Per-reagent price annotations |

Everything degrades gracefully when an optional addon isn't present.

## Install

1. Drop the `ATSW_QuickTools` folder into `Interface/AddOns`, alongside `AdvancedTradeSkillWindow` (same level, not inside it).
2. Tick on both `AdvancedTradeSkillWindow` and `ATSW Quick Tools` in the AddOns list at the character-select screen.
3. `/reload` (or relog).

## Slash commands

- `/atswqt` — re-runs the profession scan and queue refresh, and prints Aux's connection status.
- `/atswqt channel` — shows whether "Send Mats" is currently auto-detecting your channel or pinned to one.
- `/atswqt channel <say|party|raid|guild|officer|yell|#>` — pins "Send Mats" to that channel (a number joins a numbered custom channel).
- `/atswqt channel auto` — un-pins it, back to auto-detecting.

## Troubleshooting

**Bars don't show up at all.** On login/reload you should see a chat line:

```
ATSW Quick Tools loaded, AdvancedTradeSkillWindow found.
```

in green.

- **Missing entirely** → this addon itself didn't load. Check its checkbox in the AddOns list.
- **Shows in red** (`...was NOT found`) → this addon loaded, but couldn't find ATSW's main window. Almost always means `AdvancedTradeSkillWindow` itself isn't enabled, or errored out before creating its frame. Check it's ticked on, and consider `/console scriptErrors 1` (or an error-catching addon like BugSack) to see if it's throwing an error.

Either way, `/atswqt` re-runs the same check on demand.

## Known limitations

- The ETA is an estimate, not a guarantee — server lag, a full bag forcing a stop, or an interrupt will throw it off; it recalculates continuously so it self-corrects within a second or two.
- Recipes with no real spellbook entry (rare, some servers have these) fall back to the flat 3-second guess until you've crafted one and it gets measured.
- Aux price annotations read Aux's own data (vendor scans + AH history) through its module system — they don't scan the AH themselves, so a price only shows once Aux has actually seen that item before.
- "Send Mats" can only resolve reagents for the currently-open profession (see above).

## File layout

```
ATSW_QuickTools/
├── ATSW_QuickTools.toc   # addon manifest
├── QuickTools.xml        # frame templates (profession buttons, queue bar)
├── QuickTools.lua        # queue ETA + profession bar logic, hook installation
├── AuxPricing.lua        # per-reagent Aux price annotations
├── SendReagents.lua      # "Send Mats" chat export
├── BoughtReagents.lua    # "bought" checkbox on the reagents-needed window
└── README.md
```

## How it hooks ATSW

No files in `AdvancedTradeSkillWindow` are edited. This addon only hooks functions ATSW already exposes globally: `ATSW_ShowWindow`, `ATSWFrame_UpdateQueue`, `ATSW_ProcessIt`, `ATSW_SpellcastStart`/`Stop`/`Interrupted`, `ATSWFrame_SetSelection`, `ATSW_DeleteQueue`, `ATSW_ShowNecessaryReagents`. Hook installation and bar creation are deferred to `PLAYER_LOGIN` rather than done at file-load time, since addon load order between two separate addons isn't otherwise guaranteed.
