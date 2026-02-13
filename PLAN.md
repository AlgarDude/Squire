# Squire - Pet Arming Script Plan

## Context
A MacroQuest Lua script that arms other players' pets with configurable equipment sets. Triggered by tells or manual commands. Handles three source types (direct-to-pet, summon-to-cursor, summon-bag), spell memorization, inventory management, and item cleanup.

## File Structure
```
C:\games\mq\lua\squire\
├── init.lua        -- UI, main loop, commands, events, settings, armPet orchestrator
├── utils.lua       -- waitFor, output, inventory management
├── casting.lua     -- spell memorization, source execution
├── delivery.lua    -- deliverDirect, deliverCursor, deliverBag, cleanupBag
└── presets/
    ├── live.lua
    └── emu_*.lua
```
- **Settings**: `mq.configDir .. '/Squire/' .. characterName .. '.lua'` (per character, via mq.pickle)

## Settings Structure
```lua
{
    triggerWord = "armpet",
    selectedSet = "Default",  -- currently selected set in UI, used as default when no set name provided
    tellAccess = "anyone",    -- "anyone", "group", "raid", or "whitelist"
    tellWhitelist = {},       -- player names allowed when tellAccess = "whitelist"
    allowMovement = false,    -- whether to move toward pets that are out of trade range (max 100 units from start)
    sets = {
        ["Default"] = {
            armor   = { enabled = false, sourceType = "direct", source = "spell", sourceName = "", itemId = 0, trashIds = {} },
            mask    = { enabled = false, sourceType = "direct", source = "spell", sourceName = "", itemId = 0, trashIds = {} },
            belt    = { enabled = false, sourceType = "direct", source = "spell", sourceName = "", itemId = 0, trashIds = {} },
            weapon1 = { enabled = false, sourceType = "direct", source = "spell", sourceName = "", itemId = 0, trashIds = {} },
            weapon2 = { enabled = false, sourceType = "direct", source = "spell", sourceName = "", itemId = 0, trashIds = {} },
        }
    }
}
```

## Preset System

### Folder Structure
```
C:\games\mq\lua\squire\presets\
├── live.lua              -- presets for Live/Test servers (Build ~= "EMU")
├── emu_servername.lua    -- presets for a specific EMU server (lowercase server name)
```

### Environment Detection
- `mq.TLO.MacroQuest.BuildName()` to detect EMU vs Live
- If EMU: load `presets/emu_<servername>.lua` (server name from `mq.TLO.EverQuest.Server()`, lowercased, spaces replaced with underscores)
- If Live/Test: load `presets/live.lua`

### Preset File Format
Each file returns a table of named sets. Each equipment slot contains a **priority list** of sources - the script tries each in order and uses the first one the character actually has available.
```lua
return {
    ["Mage Default"] = {
        armor = {
            { sourceName = "Grant Spectral Plate", source = "spell", sourceType = "direct" },
            { sourceName = "Grant Ethereal Plate", source = "spell", sourceType = "direct" },
        },
        mask = {
            { sourceName = "Summon Companion Mask", source = "aa", sourceType = "cursor", itemId = 12345, trashIds = {} },
        },
        belt = {
            { sourceName = "Grant Engraved Belt", source = "spell", sourceType = "direct" },
            { sourceName = "Belt Summoning Device", source = "item", sourceType = "bag", itemId = 67890, trashIds = {11111} },
        },
        weapon1 = { ... },
        weapon2 = { ... },
    },
    ["Necro Default"] = { ... },
}
```

### Resolution
- **On script start**: Automatically resolve all preset priority lists against character's current spells/AAs/items.
- **UI button "Re-resolve Presets"**: Allows manual re-resolution mid-session (e.g. after learning a new spell or buying an AA).
- For each slot's priority list, check availability:
  - `"spell"`: `Me.Book(sourceName)` exists
  - `"aa"`: `Me.AltAbility(sourceName).Rank() > 0` (character has it)
  - `"item"`: `FindItem("=" .. sourceName)()` exists in inventory
- First match becomes the active config for that slot; if none match, slot is disabled
- Resolved presets are stored in a separate runtime table (`presetSets` in init.lua), NOT in `settings.sets`. Only custom sets are persisted to the settings file. The UI combines both tables for display.
- Preset sets are read-only in the UI (user can duplicate one into an editable custom set to modify it)
- **Auto-class selection**: On first load (no saved settings yet), if a preset name contains the character's class (e.g. "Mage Default" for a Mage), auto-select it as the active set

## Module Pattern
Use simple module tables (`local M = {}; ... return M`), NOT the metatable/OOP pattern from rgmercs. Squire is a single-purpose script, not a plugin framework. Functions are plain module functions (`M.functionName()`), not methods with `self`.

## Script Organization (section by section)

### utils.lua — Utility & Inventory Functions
- **`waitFor(conditionFunc, timeoutMs, checkIntervalMs, abortFunc)`** - Generic polling helper (used 10+ times). Optional abort function returns true to bail early (for `stopRequested` during cooldown waits).
- **`output(msg, ...)`** - Formatted print with script name prefix
- **`getSettingsPath()`** - Returns config file path for current character
- **`saveSettings(settings)`** - mq.pickle to config dir
- **`loadSettings()`** - loadfile from config dir, merge with defaults for missing keys. Does NOT validate `selectedSet` — that happens after preset resolution (see init.lua startup order).
- **`defaultSlotConfig()`** - Returns a default slot config table
- **`getNumPackSlots()`** - Returns `mq.TLO.Me.NumBagSlots()` for dynamic pack slot count.
- **`findFreeTopSlot()`** - Scan pack1 through packN for an empty top-level slot. Returns slot number or nil.
- **`findBagWithSpace()`** - Scan containers for a free sub-slot. Returns packNumber and subSlotNumber, or nil.
- **`freeTopSlot()`** - Find BOTH a non-container top-level item AND a bag with space BEFORE picking anything up. Pick up item (`/itemnotify packN leftmouseup`), place into bag sub-slot (`/itemnotify in packM S leftmouseup`). NOT `/autoinventory`. Returns freed slot number, or `"abort"` if all top-level slots are containers, no bag has space, or cursor gets stuck.
- **`ensureFreeTopSlot()`** - Calls findFreeTopSlot; if a free slot exists, returns it. Otherwise calls freeTopSlot and returns its result (slot number or `"abort"`). Caller must propagate `"abort"` to halt all arming.
- **`clearCursor(needTopSlot)`** - If cursor has item: if `needTopSlot` false, `/autoinventory`; if true, place manually into bag sub-slot. If cursor cannot be cleared, returns `"abort"` — caller must propagate this up to halt all arming.

### casting.lua — Spell Memorization & Source Execution
- **`memorizeSpell(gemSlot, spellName)`** - Robust memorization (rgmercs pattern):
  1. Check `Me.Book(spellName)` exists - abort if not
  2. Check if already memorized in any gem - return that gem if so
  3. Issue `/memspell N "SpellName"`
  4. Verification loop (25s timeout, 100ms intervals): confirm gem loaded + ready, abort on combat/movement, process events each iteration
  5. Return success/failure
- **`prepareSpells(set)`** - Collect unique spell names from enabled slots. Assign gem slots from `Me.NumGems()` downward. Memorize each (does NOT save gems — that's `processQueue`'s job). Stores the resulting spellName → gemSlot mapping in a module-level `gemMap` table (also used by `useSource`). Returns gemMap or nil.
- **`restoreSpells(savedGems)`** - Re-memorize displaced spells. Called only after entire queue drains.
- **`useSource(slotConfig, abortFunc)`** - Dispatch by source:
  - `"spell"`: Look up gem slot from module-level `gemMap` using `slotConfig.sourceName`. Poll-wait for spell ready, then `/cast N`.
  - `"aa"`: Poll-wait for AA ready, then `/aa act name`
  - `"item"`: Poll-wait for item ready, then `/useitem name`
  - All: use `waitFor` with abort function for stop responsiveness during cooldown waits. Wait for cast/activation to complete. Return success/failure.

### delivery.lua — Item Delivery & Cleanup
- **`deliverDirect(slotConfig, petSpawn, abortFunc)`** - Target pet → use source → done.
- **`deliverCursor(slotConfig, petSpawn, abortFunc)`** - Use source → wait for cursor item → verify `Cursor.ID() == itemId` → target pet → `LeftClick()` → if item still on cursor (rejected), verify ID and `/destroy`.
- **`deliverBag(slotConfigs, petSpawn, freeSlot, abortFunc)`** - Use source → wait for bag on cursor → `/itemnotify packN leftmouseup` to place in known free slot → for each slotConfig in group: find item by ID in sub-slots → pick up → verify cursor ID → target pet → give → if rejected, verify and destroy → after all items delivered, cleanup.
  - Note: accepts multiple slotConfigs for bag dedup groups (e.g. weapon1 + weapon2 from same bag).
- **`cleanupBag(trashIds, freeSlot)`** - Read the bag's item ID from the inventory slot (e.g. `InvSlot(packN).Item.ID()`) before touching anything. For each remaining item in the bag: pick up → if ID in trashIds, `/destroy`; if NOT, `/autoinventory` with warning. After all sub-items are handled, pick up the bag itself, verify cursor ID matches the saved bag ID, and `/destroy` it last. This frees the top-level slot.

### init.lua — Orchestration, UI, Commands, Main Loop

> **Module-level state**: `startPosition`, `stopRequested`, `armHistory`, `settings`, `presetSets`, and queue state are module-level variables in init.lua. This keeps them accessible for the future Actor IPC and Custom TLO features without refactoring.

### Core Arm Logic
- **`armPet(playerName, setName)`** - Main orchestrator:
  1. Resolve set (use currently selected set in UI if setName nil; the selected set persists as the saved setting). Look up in both `settings.sets` and `presetSets`.
  2. Validate set exists and has enabled slots
  3. Analyze set: determine if any "bag" types exist, build bag dedup groups. Slots are grouped when they share the same `source` + `sourceName` (the thing that summons the bag). A single spell may produce a bag containing items for multiple slots (e.g. armor+mask+belt from one spell, or weapon1+weapon2 from one spell). Each group summons the bag once, then extracts all items.
  4. Find pet: if playerName is "self", use `Me.Pet`; otherwise `mq.TLO.Spawn("pc " .. playerName).Pet`
  5. Validate pet exists
  6. Range check: `pet.Distance3D() <= 20` (approximate trade range)
  7. If out of range:
     - If `allowMovement` enabled: check if pet is within leash range of `startPosition` using distance squared (`dx*dx + dy*dy + dz*dz <= 10000` for 100-unit leash). If yes, `/nav id ${pet.ID} dist=15` and wait for arrival. Use nav detection patterns from rgmercs movement module (`Navigation.Active`, `Navigation.PathExists`). If pet is beyond leash range, nav path doesn't exist, or nav fails, skip this pet (log message, continue queue).
     - If `allowMovement` disabled: skip this pet with a message (log + tell player if tell-triggered), continue queue.
     - **Skip, don't abort** — the queue continues to the next request regardless of why this pet was skipped.
  8. **Clear cursor**: If item on cursor, clear it appropriately using `clearCursor(hasBagTypes)` — needs to know if a free top-level slot will be required
  9. If bag types exist → ensureFreeTopSlot()
  10. prepareSpells() for all spell sources (gem saving already handled by processQueue)
  11. Build execution plan: reorder slots so bag-grouped items are adjacent. Process each unit (check `stopRequested` at top of each iteration):
     - Skip if not enabled
     - Re-check pet range before each item. If out of range and `allowMovement` enabled, re-nav if pet is within leash range of `startPosition` (distance squared: `dx*dx + dy*dy + dz*dz <= 10000`). If beyond leash, skip remaining items for this pet.
     - For bag groups: summon bag once, extract + deliver each grouped item, then cleanup (frees the top-level slot for the next bag source). **Cleanup always runs** even if deliveries are cut short (pet out of range, stop requested) — the bag must be destroyed to free the top-level slot.
     - For non-grouped slots: dispatch to deliverDirect/deliverCursor/deliverBag as normal
     - After placing summoned bag into free slot, verify it landed correctly before proceeding
     - If pet rejects item (still on cursor after give), verify ID and `/destroy`, continue
     - Report per-item success/failure
  12. (**Spell restoration happens after entire queue drains**, not here — see `processQueue`)
  13. Report overall result
  14. If triggered by tell, `/tell playerName` with result
  - **Returns**: `"success"`, `"partial"` (stopped mid-arm via `stopRequested`), `"skipped"` (pet out of range, no pet found), or `"abort"` (cursor stuck, critical inventory failure). On `"success"`, `"partial"`, or `"skipped"`, `processQueue` continues to the next request. On `"abort"`, `processQueue` halts the queue entirely and the script refuses further arm attempts until restarted.

### Set Validation & Arm History
- **`validateSet(setName)`** - Checks each enabled slot in the set without arming:
  - `"spell"`: `Me.Book(sourceName)` exists? Report pass/fail.
  - `"aa"`: `Me.AltAbility(sourceName).Rank() > 0`? Report pass/fail.
  - `"item"`: `FindItem("=" .. sourceName)()` exists? Report pass/fail.
  - Outputs results to chat and returns a summary table.
- **`armHistory`** - Module-level table (not persisted to settings). Stores recent arm results:
  - Each entry: `{ timestamp, playerName, setName, results = { armor = true/false, mask = true/false, ... } }`
  - Capped at ~50 entries (oldest dropped)
  - `armPet` appends to this after completing (step 13)

### Event & Command Handling
- **Tell event**: `mq.event('squireRequest', "#1# tells you, '#2#'", callback)`
  - Note: tell format may vary across servers (especially EMU). The event pattern may need adjustment per server — could be made configurable in a future update.
  - **Access check**: Before processing, verify sender is allowed based on `tellAccess` setting:
    - `"anyone"`: allow all
    - `"group"`: sender must be in current group
    - `"raid"`: sender must be in current raid
    - `"whitelist"`: sender must be in `tellWhitelist`
    - If denied: ignore silently (don't respond)
  - Parse message: check if starts with triggerWord
  - Extract optional set name after trigger word
  - Queue the arm request (don't arm inside event callback)
- **Bind**: `mq.bind('/squire', callback)`
  - `arm PlayerName [SetName]` - queue arm request for a single player's pet
  - `arm self [SetName]` - queue arm request for your own pet (`Me.Pet`)
  - `group [SetName]` - queue arm requests for all pets in the player's current group (iterates group members, skips those without pets)
  - `raid [SetName]` - queue arm requests for all pets in the player's current raid (iterates raid members, skips those without pets)
  - `stop` - clear the request queue and abort current arm operation
  - `show` - toggle UI
  - `help` - print commands
- **Group/Raid logic**: These are local-only commands (no tell responses). Iterate `Me.Group.Member(N)` or `Raid.Member(N)`, collect members who have pets, queue an arm request for each. Pets out of range are skipped with a message (no tell sent).
- **Stop logic**: `/squire stop` sets a `stopRequested` flag. `processQueue` checks this flag before each queued request. `armPet` checks it at the top of each slot iteration in the delivery loop — if set, skips remaining slots and returns. On stop: clears the queue, handles any cursor items (`/autoinventory`), and spell restoration proceeds normally when processQueue finishes.
- **Abort logic**: If `armPet` returns `"abort"` (cursor stuck, critical inventory failure), `processQueue` clears the queue and sets a module-level `aborted` flag. While `aborted` is true, the script refuses all new arm attempts (commands, tells, UI buttons) with a message: `"[Squire] Arming halted due to inventory error. Please resolve and restart the script."` Spell restoration and return-to-start still execute.
- **Queue deduplication**: Before adding a request, check if the same player name is already in the queue. Drop duplicates silently.
- **Request queue**: Simple table, processed in main loop one at a time. A **batch** begins when the queue transitions from empty to non-empty — at that point, `processQueue()` saves the entire spell bar (all gem slots) AND the player's current position (`Me.Y()`, `Me.X()`, `Me.Z()`) as `startPosition`. It then processes requests one at a time. If new requests arrive mid-batch, they join the current batch (queue is still non-empty). Spell restoration (`restoreSpells()`) and return-to-start (`/nav locyxz Y X Z`) only happen when the queue is fully empty. `prepareSpells` relies on this — it only memorizes, never saves. Outputs progress: `[Squire] Arming pet 3/12: Jobob's pet...`

### ImGui UI
```
Window: "Squire"
├── Set Management Row
│   ├── Combo: Select active set (preset sets prefixed with "[P] ", custom sets shown plain)
│   ├── Button: New (popup for name input)
│   ├── Button: Copy (duplicate a preset into an editable custom set)
│   ├── Button: Delete (with confirmation, disabled for presets)
│   └── Button: Rename (popup for name input, disabled for presets)
├── Equipment Slots (TreeNode for each: Armor, Mask, Belt, Weapon1, Weapon2)
│   ├── Checkbox: Enabled
│   ├── Combo: Source Type (Direct to Pet / Summon to Cursor / Summon Bag)
│   │     Tooltip: "Direct: effect places item on pet. Cursor: item appears on your cursor, traded to pet. Bag: summons a bag, item extracted and traded."
│   ├── Combo: Source (Spell / AA / Item)
│   │     Tooltip: "Spell: memorized and cast. AA: alternate ability activated. Item: inventory clicky used."
│   ├── InputText: Source Name
│   │     Tooltip: "Exact name of the spell, AA, or item to use."
│   ├── InputInt: Item ID          ← HIDDEN when Source Type is "Direct" (not needed)
│   │     Tooltip: "ID of the pet equipment item. For Cursor: verifies correct item on cursor. For Bag: identifies which item to extract."
│   └── InputText: Trash Item IDs  ← HIDDEN unless Source Type is "Bag" (only relevant for bag cleanup)
│         Tooltip: "Item IDs to destroy after arming (e.g. leftover bag contents). Comma-separated."
├── Status Bar
│   └── Text: Current state (Idle / "Arming pet 3/12: Jobob's pet" / "Waiting for cooldown: Summon Armor (12s)")
├── Settings Section
│   ├── InputText: Trigger Word
│   ├── Combo: Tell Access (Anyone / Group Only / Raid Only / Whitelist)
│   ├── InputText: Whitelist (comma-separated names, shown only when Whitelist selected)
│   ├── Checkbox: Allow Movement (move up to 100 units toward out-of-range pets)
│   └── Button: Re-resolve Presets (re-checks spells/AAs/items for preset priority lists)
├── Manual Arm Section
│   ├── InputText: Player Name
│   ├── Combo: Set to use
│   ├── Button: Arm          (arms named player's pet)
│   ├── Button: Arm Self     (arms your own pet)
│   ├── Button: Arm Group    (arms all group pets)
│   ├── Button: Arm Raid     (arms all raid pets)
│   ├── Button: Validate Set (checks all sources exist without arming)
│   └── Button: Stop         (visible when arming, clears queue and aborts)
├── Arm History Log (scrollable, most recent first)
│   └── Each entry: [timestamp] PlayerName (SetName) - Armor:✓ Mask:✓ Belt:✗ Weapon1:✓ Weapon2:✓
```

All changes set a `settingsDirty` flag. The main loop (or render function) checks this flag each frame and writes to disk if set, then clears it. This avoids excessive disk writes during rapid UI edits.
Equipment slot fields are disabled (read-only) while an arm operation is in progress.

### Startup Order
1. Load settings (`loadSettings()`)
2. Resolve presets (build `presetSets` from preset files)
3. Validate `selectedSet` — check it exists in `settings.sets` OR `presetSets`; fall back to first available if not found
4. Auto-class selection (first load only, no saved settings)
5. Check if MQ2Nav plugin is loaded (`mq.TLO.Plugin('mq2nav').IsLoaded()`). If not loaded and `allowMovement` is true, force `allowMovement = false` and warn: `"[Squire] MQ2Nav not loaded — Allow Movement disabled."`
6. Register UI, bind, event (see below)

### Main Loop
```lua
mq.imgui.init('Squire', renderUI)
mq.bind('/squire', commandHandler)
mq.event('squireRequest', "#1# tells you, '#2#'", eventHandler)

while mq.TLO.MacroQuest.GameState() == 'INGAME' do
    mq.doevents()
    processQueue()  -- process one queued arm request if not already arming
    mq.delay(100)
end
```

## Key Safety Checks
1. **Cursor clear at start** - before any arming, ensure cursor is empty (clear appropriately based on whether a top-level slot is needed)
2. **Always verify Cursor.ID()** before `/destroy` - never destroy an unexpected item
3. **Range check before EACH item** - pet may have moved between items
4. **Spell memorization verification loop** - confirm gem loaded and ready
5. **Spell restoration** - always restore original spells after arming (success or failure)
6. **Free slot validation** - abort if can't free a top-level slot for bag types
7. **Top-level slot is a bag check** - warn and abort, don't try to move bags
8. **Bag cleanup between steps** - destroy bag contents and bag itself before next bag source, freeing the top-level slot
9. **Book check** - verify spell is in spellbook before attempting memorize
10. **AA ready check** - verify AA is available before activation
11. **Item ready check** - verify item exists and recast timer is up
12. **Pet exists check** - verify the player actually has a pet before proceeding
13. **Combat/aggro check** - don't memorize spells during combat with aggro
14. **Movement leash** - never navigate beyond 100 units from `startPosition`; if pet is beyond leash range, skip
15. **Return to start** - always navigate back to `startPosition` after queue drains (success, failure, or stop)

## Implementation Order
1. **utils.lua** — waitFor, output, settings load/save, inventory management
2. **casting.lua** — memorizeSpell, prepareSpells, restoreSpells, useSource
3. **delivery.lua** — deliverDirect, deliverCursor, deliverBag, cleanupBag
4. **init.lua** — armPet orchestrator, validateSet, armHistory
5. **init.lua** — event & command handling, processQueue, stop logic
6. **init.lua** — ImGui UI (sets, equipment slots, status, arm controls, history log)
7. **init.lua** — main loop
8. **presets/** — preset file(s) with example sets

## Verification
- Test with `/squire show` to verify UI renders
- Configure a test set with one item
- Test `/squire arm CharName` to verify arm flow
- Test tell triggering by having another character send a tell
- Verify settings persist across script restarts
- Test bag type with inventory slot management
- Verify cursor ID checks prevent accidental item destruction

## Planned Future Enhancements
> **Note**: Actor IPC and Custom TLO support are confirmed planned features. Write all code with these in mind — keep state in individual module-level variables (not grouped into a state table) so actors and TLO registration can read them directly without refactoring.

- **Cooldown display per source** — Show remaining cooldown time next to each equipment slot in the UI (spell gem timer, AA timer, item timer)
- **Actor-based IPC** — Register a message actor (`actors.register`) so external scripts (e.g. rgmercs modules) can send commands to Squire and receive state updates. Messages would support: `arm` (request arm — accepts a single player name OR a list of player names to all be queued), `stop`, `status` (query current state: idle/arming/queued count/cooldown info). This enables combat automation systems to send a single message with all peers who have pets, and then poll Squire's state actor to know when it's done.
- **Custom TLO** — Register a custom TLO (e.g. `Squire.State`, `Squire.QueueCount`, `Squire.IsArming`, `Squire.CurrentTarget`) so macros and other Lua scripts can query Squire's state directly via TLO access without needing actors.
