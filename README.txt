ATSW Quick Tools
================

A small companion addon for AdvancedTradeSkillWindow (ATSW) that adds:

1. Queue ETA bar (below the ATSW window)
   - While idle: "N item(s) queued | Est. time: M:SS"
   - While crafting: a filling progress bar for the item currently being
     made, plus "Crafting <name> | Queue ETA: M:SS" for the whole queue.
   - Per-recipe cast time is looked up three ways, best available wins:
       1. Learned from actually crafting it once (stored in
          atsw_qt_recipetime, a SavedVariable, so it improves over
          multiple sessions).
       2. ClassicAPI's GetSpellInfo(name) DBC lookup, if ClassicAPI is
          loaded.
       3. A flat 3-second guess otherwise.
   - If nampower is loaded, the current item's progress uses its
     GetCastInfo() for an exact, real-time remaining-ms readout instead
     of our own stopwatch.

2. Profession quick-switch bar (above the ATSW window)
   - One button per profession you actually know. Detection is
     layered: first it reads whatever the game itself lists under the
     spellbook's "Professions" tab (this picks up custom/server-added
     professions - Jewelcrafting, Survival, Smelting, etc. - the same
     way it picks up the standard ones, no extra work needed); then it
     also remembers any profession window you've actually opened
     before (saved across sessions), as a backstop in case something
     is filed outside that tab on your server.
   - Click a button to jump straight to that profession's list inside
     ATSW - same as clicking its spellbook icon, but without needing to
     close/reopen the window.
   - Works even with zero client mods installed - it's a plain
     spellbook scan (GetSpellTabInfo/GetSpellName).

3. Per-reagent Aux prices (on the reagent icons for whichever recipe
   is selected)
   - If Aux (the AH addon) is installed, each reagent icon gets a small
     price underneath it: the vendor price if it's sold with unlimited
     stock, otherwise Aux's Auction House value estimate - exactly the
     same rule Aux's own "Total Cost" label already uses, so the lines
     add up to that total.
   - This piggybacks on a compatibility line Aux itself already ships
     (`if ATSWReagentLabel then ... end` in its core/crafting.lua),
     which is how we know ATSW's reagent slots are very likely named
     ATSWReagent1.. ATSWReagent8, mirroring Blizzard's own
     TradeSkillReagent1..8. Run "/atswqt aux" to check whether Aux was
     found; if the per-reagent numbers don't show up even though that
     says "connected", your ATSW build names those slots differently
     and I'd need to see that bit of atsw.xml/atsw.lua to match it
     exactly.
   - Does nothing if Aux isn't installed.

Install
-------
1. Drop the "ATSW_QuickTools" folder into Interface/AddOns, alongside
   your existing "AdvancedTradeSkillWindow" folder (same level, not
   inside it).
2. Make sure both AdvancedTradeSkillWindow and this addon are ticked
   on in the AddOns list at the character-select screen.
3. Restart/reload UI (/reload).

Troubleshooting: don't see the bars at all
-------------------------------------------
On login/reload you should see a chat line:
    ATSW Quick Tools loaded, AdvancedTradeSkillWindow found.
in green. If that line is missing entirely, this addon itself didn't
load - check its checkbox in the AddOns list.

If instead the line shows in red ("...was NOT found"), this addon
loaded fine but couldn't find ATSW's main window - almost always
because AdvancedTradeSkillWindow itself isn't enabled, or errored out
before creating its frame. Check it's ticked on too, and consider
turning on Lua error popups (/console scriptErrors 1, or an
error-catching addon like BugSack) to see if it's throwing an error.

Either way, running "/atswqt" re-runs the same check on demand and
also reports Aux's connection status.

Still to do: the "mark reagent as bought" checkbox
---------------------------------------------------
Not in this build. ATSW's own "reagents needed for the whole queue"
window (the one with Inv/Bank/Twink/Merchant columns and the existing
shift-click-to-search-AH behavior) lives in code I don't have anymore
in this conversation - the atsw.lua/atsw.xml upload got replaced by
Aux's source when you sent this last file. To add a checkbox or
strikethrough per row there without guessing wrong names and shipping
something that silently does nothing, I need either:
  - that file re-uploaded (same as the first time), or
  - just the function that builds/updates that specific window, plus
    its XML block (search atsw.lua for whatever's around the
    ATSW_REAGENTFRAMETITLE / ATSW_REAGENTBUTTON language strings).
Send either of those and I'll wire the checkbox in the same
non-invasive way as everything else here.

Notes / known limits
---------------------
- Nothing in AdvancedTradeSkillWindow's own files is modified - this
  only hooks its already-public functions (ATSW_ShowWindow,
  ATSWFrame_UpdateQueue, ATSW_ProcessIt, ATSW_SpellcastStart/Stop/
  Interrupted, ATSWFrame_SetSelection, ATSW_DeleteQueue), so it should
  survive future ATSW updates as long as those function names stay the
  same.
- The ETA is an estimate, not a guarantee - server lag, a full bag
  forcing a stop, or getting interrupted will all throw it off; it
  recalculates continuously so it self-corrects within a second or two.
- Recipes with no real spellbook entry (rare edge cases some servers
  have) fall back to the flat 3-second guess until you've crafted one
  and it gets measured.
- The Aux price annotations read Aux's own data (vendor scans + AH
  history) through its module system - they don't scan the AH
  themselves, so a price only shows once Aux has actually seen that
  item before (on a vendor or in a completed AH scan).
