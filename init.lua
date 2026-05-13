--[[
    Squire - Pet Arming Script
    Arms other players' pets with configurable equipment sets.
    Usage: /lua run squire
]]

local mq = require('mq')
local imgui = require('ImGui')
local icons = require('mq.Icons')
local Set = require('mq.Set')
local utils = require('squire.lib.utils')
local casting = require('squire.lib.casting')
local delivery = require('squire.lib.delivery')
local reactive = require('squire.lib.reactive')

local version = "1.1.2"

-- Module-Level State

local me = mq.TLO.Me
local myClass = me.Class.ShortName()
local settings = {}
local presetSets = {}
local stopRequested = false
local aborted = false
local armHistory = {}
local queue = {}
local queuedNames = Set.new({})
local isArming = false
local showUI = true
local settingsDirty = false
local savedGems = nil
local statusText = "Idle"

-- Lookup Tables

local methods = {
    { key = "cursor", label = "Summon Single Item", },
    { key = "bag",    label = "Summon Bag", },
    { key = "direct", label = "Direct to Pet", },
    { key = "trade",  label = "Trade from Inventory", },
}

local sources = {
    { key = "spell", label = "Spell", },
    { key = "aa",    label = "AA", },
    { key = "item",  label = "Item", },
}

local tellAccessOptions = {
    { key = "disabled",   label = "Disabled", },
    { key = "anyone",     label = "Anyone", },
    { key = "group",      label = "Group Only", },
    { key = "raid",       label = "Raid Only", },
    { key = "fellowship", label = "Fellowship Only", },
    { key = "allowlist",  label = "Allow List", },
    { key = "denylist",   label = "Deny List", },
}

local rmOptions = {
    { key = "off",    label = "Manual Only",   tooltip = "Arm pets manually via buttons, tells, or commands.", },
    { key = "page",   label = "Page",          tooltip = "Report new pet summons to Squires for automatic arming.", },
    { key = "squire", label = "Squire",        tooltip = "Receive pet summon reports and arm pets when safe.", },
    { key = "both",   label = "Squire + Page", tooltip = "Report your own pet summons and arm others' pets.", },
}



-- UI Temp State

local showSettings = false
local showManageSets = false
local newSetName = ""
local renameSetName = ""
local manualPlayerName = ""
local pendingRemoveIdx = nil
local newSourceName = ""
local newSourceType = "spell"
local newSourceMethod = "cursor"
local showAddSource = false
local editingIdx = nil
local editSourceType = ""
local editSourceName = ""
local editSourceMethod = ""
local newSourceClicky = false
local newSourceClickyItem = nil
local editSourceClicky = false
local editSourceClickyItem = nil
local showHelp = false
local showWelcome = false
local welcomeDismissAll = true

-- Helpers

local function findIndex(tbl, key)
    for i, entry in ipairs(tbl) do
        if entry.key == key then return i end
    end
    return 1
end

local function petDisplayName(playerName)
    return playerName .. "'s"
end

local function joinArgs(args, startIdx)
    local parts = {}
    for i = startIdx, #args do
        table.insert(parts, args[i])
    end
    return #parts > 0 and table.concat(parts, " ") or nil
end

-- Preset System

local presetClassMap = {}
local presetAliasOf = {}

local function resolvePresets()
    presetSets = {}
    presetClassMap = {}
    presetAliasOf = {}

    local presetFile
    if mq.TLO.MacroQuest.BuildName():lower() == "emu" then
        local serverName = mq.TLO.EverQuest.Server()
        -- if we wish to deviate from this scheme later we can use a lookup table
        local fileSuffix = serverName:lower():gsub(" ", "")
        presetFile = "squire.presets." .. fileSuffix
    else
        presetFile = "squire.presets.live"
    end

    -- Clear cached module so re-resolve picks up changes
    package.loaded[presetFile] = nil
    local ok, rawPresets = pcall(require, presetFile)
    if not ok or not rawPresets then
        utils.output("No preset file found (%s). Continuing without presets.", presetFile)
        return
    end

    for _, definition in ipairs(rawPresets) do
        local classMatch = not definition.classes
        if definition.classes then
            for _, cls in ipairs(definition.classes) do
                if cls == myClass then
                    classMatch = true
                    break
                end
            end
        end

        if classMatch then
            local title = definition.title:gsub("Class", myClass)

            local resolvedSet = {}
            for _, group in ipairs(definition.effects) do
                local found = false
                for _, candidate in ipairs(group) do
                    local available = false
                    if candidate.type == "spell" then
                        available = me.Book(candidate.name)() ~= nil and (mq.TLO.Spell(candidate.name).Level() or 0) <= me.Level()
                    elseif candidate.type == "aa" then
                        available = (me.AltAbility(candidate.name).Rank() or 0) > 0
                    elseif candidate.type == "item" then
                        local item = mq.TLO.FindItem("=" .. candidate.name)
                        available = item() ~= nil and (item.Clicky.RequiredLevel() or 0) <= me.Level()
                    end

                    if available then
                        table.insert(resolvedSet, {
                            enabled = true,
                            name = candidate.name,
                            type = candidate.type,
                            method = candidate.method,
                            clicky = candidate.clicky or false,
                            clickyItem = candidate.clickyItem,
                            items = candidate.items or {},
                            trashItems = candidate.trashItems or {},
                            candidates = group,
                        })
                        found = true
                        break
                    end
                end
                if not found then
                    table.insert(resolvedSet, {
                        enabled = false,
                        name = "",
                        type = "",
                        method = "",
                        items = {},
                        trashItems = {},
                        candidates = group,
                    })
                end
            end
            presetClassMap[title] = definition.classes
            presetSets[title] = resolvedSet
            if definition.alias then
                presetAliasOf[title] = definition.alias
            end
        end
    end
end

local function getSet(setName)
    if settings.sets[setName] then return settings.sets[setName] end
    if presetSets[setName] then return presetSets[setName] end
    local lower = setName:lower()
    for name, set in pairs(settings.sets) do
        if name:lower() == lower then return set end
    end
    for name, set in pairs(presetSets) do
        if name:lower() == lower then return set end
        if presetAliasOf[name] and presetAliasOf[name]:lower() == lower then return set end
    end
    return nil
end

local function findPresetForClass(class)
    for presetName, classes in pairs(presetClassMap) do
        for _, cls in ipairs(classes) do
            if cls == class then return presetName end
        end
    end
end

local function isPresetSet(setName)
    return presetSets[setName] ~= nil
end

local function getAllSetNames(useAliases)
    local names = {}
    for name in pairs(settings.sets) do
        table.insert(names, name)
    end
    table.sort(names)

    -- Add presets not overridden by user sets (class filtering already done in resolvePresets)
    local presetNames = {}
    for name in pairs(presetSets) do
        if not settings.sets[name] then
            table.insert(presetNames, useAliases and (presetAliasOf[name] or name) or name)
        end
    end
    table.sort(presetNames)
    for _, name in ipairs(presetNames) do
        table.insert(names, name)
    end
    return names
end

-- Core Arm Logic

local function armPet(playerName, setName, fromTell, abortCheck, petCombat)
    if aborted then
        utils.output("\arArming halted. Use /squire reset to resume.")
        return false
    end

    -- Resolve set
    setName = setName or settings.selectedSet
    local set = getSet(setName)

    if not set then
        utils.output("\arSet '%s' not found.", setName)
        return true
    end

    -- Find pet
    local petSpawn = mq.TLO.Spawn("pc =" .. playerName).Pet

    if (petSpawn.ID() or 0) == 0 then
        utils.output("\ay%s does not have a pet.", playerName)
        return true, "skipped"
    end

    if utils.isFamiliar(petSpawn) then
        utils.output("\ay%s pet is a familiar. Skipping.", petDisplayName(playerName))
        return true, "skipped"
    end

    -- Range check
    if not delivery.ensureInRange(petSpawn, settings.allowMovement, abortCheck, settings.navDistance) then
        utils.output("\ay%s pet is out of range. Skipping.", petDisplayName(playerName))
        return true, "skipped"
    end

    -- Clear cursor
    local hasBagMethod = false
    for _, entry in ipairs(set) do
        if entry.enabled and entry.method == "bag" then
            hasBagMethod = true
            break
        end
    end
    local cursorResult, cursorReason = utils.clearCursor(hasBagMethod)
    if cursorResult == "abort" then
        utils.output("\arCursor stuck. Aborting.")
        return false, cursorReason
    end

    -- Free top slot for bag methods
    local freeSlot
    if hasBagMethod then
        freeSlot = utils.ensureFreeTopSlot()
        if freeSlot == "abort" then
            utils.output("\arCannot free a top-level slot. Aborting.")
            return false, "no free top-level inventory slot"
        end
    end

    local stopped = false
    local abortFunc = function()
        if stopRequested then stopped = true end
        return stopped or (abortCheck and abortCheck())
    end

    -- Prepare spells
    local spellResult = casting.prepareSpells(set, abortFunc)
    if spellResult == nil then
        utils.output("\arFailed to prepare spells for set '%s'.", setName)
        return false, string.format("failed to memorize spells for set '%s'", setName)
    elseif spellResult == false then
        return true, "aborted"
    end

    -- Execute delivery for each enabled source entry in order
    local results = {}
    local navParams = { allow = settings.allowMovement, abort = abortFunc, maxDist = settings.navDistance, }
    local petUnavailable = false

    for i, entry in ipairs(set) do
        if entry.enabled then
            if abortFunc() then break end

            -- Re-check pet existence
            if (petSpawn.ID() or 0) == 0 then
                utils.output("\ayPet no longer exists. Skipping remaining sources.")
                break
            end

            -- Re-check pet range
            if not delivery.ensureInRange(petSpawn, settings.allowMovement, abortFunc, settings.navDistance) then
                utils.output("\ayPet moved out of range. Skipping remaining sources.")
                break
            end

            -- Pet-in-combat: trade-based sources will fail on attacking pets, skip them
            if petCombat and entry.method ~= "direct" then
                utils.debugOutput("Skipping %s source '%s' (pet in combat)", entry.method, entry.name)
                results[i] = false
                -- Verify freeSlot if bag method
            elseif entry.method == "bag" and freeSlot and mq.TLO.InvSlot("pack" .. freeSlot).Item.ID() then
                utils.output("\arFree slot pack%d still occupied. Skipping %s.", freeSlot, entry.name)
                results[i] = false
            else
                local success = false
                local sourceUnavailable = false
                if entry.method == "direct" then
                    success = delivery.deliverDirect(entry, petSpawn, abortFunc, navParams)
                elseif entry.method == "cursor" then
                    success, sourceUnavailable = delivery.deliverCursor(entry, petSpawn, abortFunc, navParams)
                elseif entry.method == "bag" then
                    success, sourceUnavailable = delivery.deliverBag(entry, petSpawn, freeSlot, abortFunc, navParams)
                elseif entry.method == "trade" then
                    success, sourceUnavailable = delivery.deliverTrade(entry, petSpawn, navParams)
                end
                results[i] = success
                if sourceUnavailable then
                    petUnavailable = true
                    utils.output("\ayPet unavailable for giving. Skipping remaining sources.")
                    break
                end
                -- After a failed source, check abort before trying next source
                if not success and abortFunc() then break end
            end
        end
    end

    -- Report result
    local total, passed, failed = 0, 0, {}
    local wasAborted = false
    for i, entry in ipairs(set) do
        if entry.enabled then
            total = total + 1
            if results[i] == true then
                passed = passed + 1
            elseif results[i] == false then
                table.insert(failed, entry.name ~= "" and entry.name or ("Source " .. i))
            else
                wasAborted = true
            end
        end
    end

    table.insert(armHistory, 1, {
        timestamp = os.date("%H:%M:%S"),
        playerName = playerName,
        setName = setName,
        passed = passed,
        total = total,
        failed = failed,
        aborted = wasAborted,
    })
    if #armHistory > 50 then
        table.remove(armHistory)
    end

    local suffix = ""
    if wasAborted then suffix = " (ABORTED)" end
    if #failed > 0 then
        utils.debugOutput("Processed %d/%d sources for %s pet. (Set: %s) Failed: %s%s", passed, total, petDisplayName(playerName), setName, table.concat(failed, ", "), suffix)
    else
        utils.debugOutput("Processed %d/%d sources for %s pet. (Set: %s)%s", passed, total, petDisplayName(playerName), setName, suffix)
    end

    if fromTell and settings.tellReplies then
        if #failed > 0 then
            mq.cmdf("/tell %s Processed %d/%d sources for your pet. Failed: %s", playerName, passed, total, table.concat(failed, ", "))
        else
            mq.cmdf("/tell %s Processed %d/%d sources for your pet.", playerName, passed, total)
        end
    end

    if petUnavailable then
        return true, "pet_unavailable"
    end

    return true
end

-- Queue & Processing

local function clearQueue()
    queue = {}
    queuedNames = Set.new({})
end

local function addToQueue(playerName, setName, fromTell)
    if aborted then
        utils.output("\arArming halted. Use /squire reset to resume.")
        return
    end

    local petSpawn = mq.TLO.Spawn("pc =" .. playerName).Pet
    if (petSpawn.ID() or 0) == 0 then
        utils.output("\ay%s does not have a pet.", playerName)
        if fromTell and settings.tellReplies then
            mq.cmdf("/tell %s You do not appear to have a pet.", playerName)
        end
        return
    end

    if utils.isFamiliar(petSpawn) then
        utils.output("\ay%s pet is a familiar. Skipping.", petDisplayName(playerName))
        if fromTell and settings.tellReplies then
            mq.cmdf("/tell %s Your pet appears to be a familiar.", playerName)
        end
        return
    end

    if (petSpawn.Distance3D() or 999) > settings.navDistance then
        utils.output("\ay%s pet is out of range. Skipping.", petDisplayName(playerName))
        if fromTell and settings.tellReplies then
            mq.cmdf("/tell %s Your pet is out of range.", playerName)
        end
        return
    end

    local resolvedSetName = setName or settings.selectedSet
    if not getSet(resolvedSetName) then
        local available = table.concat(getAllSetNames(true), ", ")
        utils.output("\arSet '%s' not found. Available sets: %s", resolvedSetName, available)
        if fromTell and settings.tellReplies then
            mq.cmdf('/tell %s Set "%s" not found. Available sets: %s', playerName, resolvedSetName, available)
        end
        return
    end

    if queuedNames:contains(playerName:lower()) then return end

    queuedNames:add(playerName:lower())
    table.insert(queue, {
        playerName = playerName,
        setName = setName,
        fromTell = fromTell or false,
    })

    if fromTell and settings.tellReplies then
        mq.cmdf('/tell %s You have been added to the queue.', playerName)
    end
end

local function processQueue()
    if isArming or #queue == 0 then return end

    if not savedGems then
        savedGems = casting.saveCurrentGems()
    end

    isArming = true

    if settings.preQueueCommand ~= "" then
        mq.cmdf("%s", settings.preQueueCommand)
    end

    -- Deferred from a prior paused queue: restore anything left in a temp slot
    -- before the new queue potentially displaces something else.
    utils.restoreDisplacedItem()

    utils.announce(settings.announceArming, "Arming pets - please hold.")

    local processed = 0
    local pauseReason = nil
    local haltReason = nil
    local abortFired = false
    local abortCheck = function()
        if not abortFired and utils.shouldAbortArming() then
            abortFired = true
            pauseReason = utils.getHardBlockReason() or "environmental block"
        end
        return abortFired
    end

    while #queue > 0 do
        if stopRequested then
            clearQueue()
            break
        end

        if abortCheck() then
            clearQueue()
            break
        end

        local request = table.remove(queue, 1)
        queuedNames:remove(request.playerName:lower())
        processed = processed + 1
        statusText = string.format("Arming pet %d/%d: %s pet...", processed, processed + #queue, petDisplayName(request.playerName))

        local petCombat = request.playerName == me.DisplayName() and (me.Pet.Combat() or false) or false
        local result, status = armPet(request.playerName, request.setName, request.fromTell, abortCheck, petCombat)

        if abortFired then
            clearQueue()
            break
        elseif not result then
            aborted = true
            haltReason = status or "unknown error"
            clearQueue()
            break
        end
    end

    -- Capture state before cleanup -- external events (reset button, /squire reset) can
    -- mutate stopRequested/aborted during mq.delay calls in the cleanup code below.
    local wasStopped = stopRequested
    local wasAborted = aborted

    -- Safe cleanup (no item pickup): runs unless user explicitly stopped.
    -- Item pickup (/itemnotify pack... leftmouseup) while casting can DC on EMU,
    -- so on pause we only do /autoinventory or /destroy here and defer pickup ops.
    if not wasStopped then
        if mq.TLO.Cursor.ID() then
            local cursorName = mq.TLO.Cursor.Name() or "unknown item"
            local cursorId = mq.TLO.Cursor.ID()
            if mq.TLO.Cursor.NoRent() and cursorId == utils.getLastSummonedItemId() then
                utils.debugOutput("Cleanup: destroying summoned item '%s' (ID: %d)", cursorName, cursorId)
                utils.destroyCursor()
            else
                utils.debugOutput("Cleanup: autoinventorying '%s' (ID: %d)", cursorName, cursorId)
                mq.cmd("/autoinventory")
                mq.delay(3000, function() return not mq.TLO.Cursor.ID() end)
            end
            if mq.TLO.Cursor.ID() then
                haltReason = string.format("'%s' stuck on cursor after cleanup", cursorName)
                utils.output("\arHALTED: %s", haltReason)
                aborted = true
                wasAborted = true
            end
        end
    end

    -- Pickup / spell restore / nav: skip on pause (casting may be live).
    if not wasStopped and not pauseReason then
        if not mq.TLO.Cursor.ID() then
            utils.restoreDisplacedItem()
        end

        if savedGems then
            casting.restoreSpells(savedGems, function() return stopRequested end)
        end

        delivery.navToStart(settings.allowMovement)
    end

    delivery.clearStartPosition()

    if settings.postQueueCommand ~= "" then
        mq.cmdf("%s", settings.postQueueCommand)
    end
    utils.announceQueueResult(settings.announceArming, wasStopped, wasAborted, pauseReason, true)

    -- Preserve savedGems only on pure pause (not stopped, not aborted) for next-queue recovery.
    if wasStopped or wasAborted or not pauseReason then
        savedGems = nil
    end
    utils.clearLastSummonedItemId()

    isArming = false
    stopRequested = false
    if wasAborted then
        if wasStopped then
            statusText = "HALTED - user stopped"
        else
            statusText = string.format("HALTED - %s", haltReason or "unknown error")
        end
    elseif pauseReason then
        statusText = string.format("HALTED - %s", pauseReason)
    else
        statusText = "Idle"
    end
end

-- Access Check

local function isAllowedSender(senderName)
    if settings.tellAccess == "anyone" then
        return true
    elseif settings.tellAccess == "group" then
        for i = 1, 5 do
            local member = mq.TLO.Group.Member(i)
            if member() and (member.DisplayName() or ""):lower() == senderName:lower() then
                return true
            end
        end
        return false
    elseif settings.tellAccess == "raid" then
        for i = 1, mq.TLO.Raid.Members() or 0 do
            local member = mq.TLO.Raid.Member(i)
            if member() and (member.DisplayName() or ""):lower() == senderName:lower() then
                return true
            end
        end
        return false
    elseif settings.tellAccess == "fellowship" then
        if me.Fellowship.ID() == 0 then return false end
        local member = me.Fellowship.Member(senderName)
        return member() ~= nil
    elseif settings.tellAccess == "allowlist" then
        for _, name in ipairs(settings.tellAllowlist) do
            if name:lower() == senderName:lower() then
                return true
            end
        end
        return false
    elseif settings.tellAccess == "denylist" then
        for _, name in ipairs(settings.tellDenylist) do
            if name:lower() == senderName:lower() then
                utils.output("\ay%s is on the deny list. Ignoring request.", senderName)
                return false
            end
        end
        return true
    end
    return false
end

local function registerTellEvent()
    mq.event('squireRequest', "#1# tells you, '#2#'", function(line, sender, message)
        if not message then return end
        if sender:lower() == me.DisplayName():lower() then return end
        local trimmed = message:gsub("^%s+", ""):gsub("%s+$", "")
        local triggerLower = settings.triggerWord:lower()

        if triggerLower == "" or trimmed:lower():find(triggerLower, 1, true) ~= 1 then return end
        if not isAllowedSender(sender) then return end

        local afterTrigger = trimmed:sub(#settings.triggerWord + 1):gsub("^%s+", ""):gsub("%s+$", "")
        addToQueue(sender, afterTrigger ~= "" and afterTrigger or nil, true)
    end)
end

local function unregisterTellEvent()
    mq.unevent('squireRequest')
end

-- Command System

local function queuePetOwners(getMember, startIndex, count, setName)
    for i = startIndex, count do
        local member = getMember(i)
        if member() and (member.Pet.ID() or 0) > 0 then
            addToQueue(member.DisplayName(), setName, false)
        end
    end
end

local commandOrder = { "help", "stop", "reset", "show", "hide", "debug", "arm", "mode", "tellaccess", }
local commandsExpanded = nil

local commands
commands = {
    arm = {
        usage = "/squire arm <scope> [set]",
        about = "Arm pets (self/target/group/raid/PlayerName)",
        handler = function(args)
            local scope = args[2] and args[2]:lower() or ""
            local setName = joinArgs(args, 3)

            if scope == "self" then
                addToQueue(me.DisplayName(), setName, false)
            elseif scope == "target" then
                local t = mq.TLO.Target
                if not t() or t.Type() ~= "PC" then
                    utils.output("\ayTarget is not a PC.")
                elseif (t.Pet.ID() or 0) == 0 then
                    utils.output("\ay%s does not have a pet.", t.DisplayName())
                else
                    addToQueue(t.DisplayName(), setName, false)
                end
            elseif scope == "group" then
                queuePetOwners(mq.TLO.Group.Member, 0, (mq.TLO.Group.GroupSize() or 1) - 1, setName)
            elseif scope == "raid" then
                queuePetOwners(mq.TLO.Raid.Member, 1, mq.TLO.Raid.Members() or 0, setName)
            elseif scope ~= "" then
                addToQueue(args[2], setName, false)
            else
                utils.output("Usage: /squire arm <self|target|group|raid|PlayerName> [SetName]")
            end
        end,
    },
    stop = {
        usage = "/squire stop",
        about = "Stop the current operation",
        handler = function(args)
            stopRequested = true
            aborted = true
            clearQueue()
            reactive.onStop()
            if not isArming then
                statusText = "HALTED - user stopped"
            end
            utils.output("Stop requested.")
        end,
    },
    mode = {
        usage = "/squire mode [off|page|squire|both]",
        about = "Set reactive arming mode",
        handler = function(args)
            local validModes = { off = "Manual Only", page = "Page", squire = "Squire", both = "Squire + Page", }
            local mode = args[2] and args[2]:lower() or ""
            if mode == "" then
                local label = validModes[settings.reactiveMode] or "Off"
                utils.output("Reactive mode: %s (off, page, squire, both)", label)
                return
            end
            if not validModes[mode] then
                utils.output("Unknown mode. Options: off, page, squire, both")
                return
            end
            if mode == settings.reactiveMode then
                utils.output("Reactive mode already set to %s.", validModes[mode])
                return
            end
            local oldMode = settings.reactiveMode
            settings.reactiveMode = mode
            settingsDirty = true
            reactive.onModeChange(oldMode, mode)
            utils.output("Reactive mode set to: %s", validModes[mode])
        end,
    },
    show = {
        usage = "/squire show",
        about = "Show the UI",
        handler = function(args)
            showUI = true
        end,
    },
    hide = {
        usage = "/squire hide",
        about = "Hide the UI",
        handler = function(args)
            if showWelcome then
                utils.output("Please complete the welcome setup first.")
                return
            end
            showUI = false
        end,
    },
    debug = {
        usage = "/squire debug [on|off]",
        about = "Toggle debug logging",
        handler = function(args)
            local arg = args[2] and args[2]:lower() or ""
            local prev = settings.debugMode
            if arg == "on" then
                settings.debugMode = true
            elseif arg == "off" then
                settings.debugMode = false
            else
                settings.debugMode = not settings.debugMode
            end
            if settings.debugMode ~= prev then
                settingsDirty = true
                utils.output("Debug mode: %s", settings.debugMode and "ON" or "OFF")
            end
        end,
    },
    tellaccess = {
        usage = "/squire tellaccess [mode]",
        about = "Set tell access mode (disabled, anyone, group, raid, fellowship, allowlist, denylist)",
        handler = function(args)
            local keys = {}
            for _, opt in ipairs(tellAccessOptions) do table.insert(keys, opt.key) end
            local mode = args[2] and args[2]:lower() or ""
            if mode == "" then
                local current = findIndex(tellAccessOptions, settings.tellAccess)
                utils.output("Tell access: %s (%s)", tellAccessOptions[current].label, table.concat(keys, ", "))
                return
            end
            for _, opt in ipairs(tellAccessOptions) do
                if opt.key == mode then
                    local wasDisabled = settings.tellAccess == "disabled"
                    settings.tellAccess = opt.key
                    settingsDirty = true
                    if opt.key == "disabled" then
                        unregisterTellEvent()
                    elseif wasDisabled then
                        registerTellEvent()
                    end
                    utils.output("Tell access set to: %s", opt.label)
                    return
                end
            end
            utils.output("Unknown mode. Options: %s", table.concat(keys, ", "))
        end,
    },
    reset = {
        usage = "/squire reset",
        about = "Resume after a halt or error",
        handler = function(args)
            aborted = false
            stopRequested = false
            statusText = "Idle"
            reactive.onReset()
            utils.output("Reset complete. Ready to arm.")
        end,
    },
    help = {
        usage = "/squire help",
        about = "Print the command list to chat",
        handler = function(args)
            utils.output("Commands: /squire ...")
            for _, name in ipairs(commandOrder) do
                if name ~= "help" then
                    local cmd = commands[name]
                    local shortUsage = cmd.usage:gsub("^/squire ", "")
                    utils.output("  %s - %s", shortUsage, cmd.about)
                end
            end
        end,
    },
}

local function commandHandler(...)
    local args = { ..., }
    local cmd = args[1] and args[1]:lower() or "help"
    local found = commands[cmd]
    if found then
        found.handler(args)
    else
        utils.output("Unknown command: %s. Try /squire help", cmd)
    end
end

-- ImGui UI

local animItems = mq.FindTextureAnimation("A_DragItem")
local animSpells = mq.FindTextureAnimation("A_SpellIcons")
local bgTexture = mq.CreateTexture(mq.luaDir .. "/squire/resources/squire.png")
local logoTexture = mq.CreateTexture(mq.luaDir .. "/squire/resources/algar_60.png")
local shieldTexture = mq.CreateTexture(mq.luaDir .. "/squire/resources/shieldicon.png")

local headColor = ImVec4(0.6, 0.85, 1.0, 1.0)
local bodyColor = ImVec4(0.78, 0.74, 0.6, 1.0)

local function renderItemIcon(icon)
    local iconPos = imgui.GetCursorScreenPosVec()
    imgui.Dummy(16, 16)
    animItems:SetTextureCell(icon - 500)
    imgui.GetWindowDrawList():AddTextureAnimation(animItems, iconPos, ImVec2(16, 16))
    imgui.SameLine()
end

local function renderWindowBg(fixedHeight)
    if not bgTexture then return end
    local startPos = imgui.GetCursorPosVec()
    local availW = imgui.GetContentRegionAvail()
    local availH = fixedHeight and (fixedHeight - startPos.y) or select(2, imgui.GetContentRegionAvail())
    local imgSize = math.min(availW, availH)
    local offsetX = (availW - imgSize) * 0.5
    local offsetY = (availH - imgSize) * 0.5
    local winPos = imgui.GetWindowPosVec()
    local pMin = ImVec2(winPos.x + startPos.x + offsetX, winPos.y + startPos.y + offsetY)
    local pMax = ImVec2(pMin.x + imgSize, pMin.y + imgSize)
    imgui.GetWindowDrawList():AddImage(bgTexture:GetTextureID(), pMin, pMax,
        ImVec2(0, 0), ImVec2(1, 1), IM_COL32(255, 255, 255, 30))
end

local function renderToggle(id, value)
    local width, height = 26, 14
    local radius = height * 0.5
    local pos = imgui.GetCursorScreenPosVec()
    pos.y = pos.y + (imgui.GetFrameHeight() * 0.5) - (height * 0.5) - imgui.GetStyle().FramePadding.y

    imgui.InvisibleButton(id, width, height)
    local clicked = imgui.IsItemClicked()
    if clicked then value = not value end

    local drawList = imgui.GetWindowDrawList()
    local onColor = ImVec4(0, 0.8, 0, 1)
    local offColor = ImVec4(0.8, 0, 0, 1)
    local t = value and 1.0 or 0.0

    drawList:AddRectFilled(ImVec2(pos.x, pos.y), ImVec2(pos.x + width, pos.y + height),
        imgui.GetColorU32(value and onColor or offColor), height * 0.5)
    drawList:AddCircleFilled(ImVec2(pos.x + radius + t * (width - height), pos.y + radius),
        radius * 0.8, imgui.GetColorU32(1, 1, 1, 1), 0)

    return value, clicked
end

-- Two-pass header controls (pre-render claims clicks, post-render draws visuals)
local function renderSourceHeaderControls(currentSet, idx, headerCursorPos, headerScreenPos, preRender, editable)
    local startingPos = imgui.GetCursorPosVec()
    local yOffset = imgui.GetStyle().FramePadding.y
    local entry = currentSet[idx]
    local suffix = preRender and "_pre" or ""

    -- Source icon overlay (post-render only, skip for trade - no source casting)
    if not preRender and entry.name ~= "" and entry.method ~= "trade" then
        local iconCell, iconAnim
        if entry.type == "item" then
            local item = mq.TLO.FindItem("=" .. entry.name)
            if item() then
                iconCell = (item.Icon() or 500) - 500
                iconAnim = animItems
            end
        elseif entry.type == "spell" then
            local spell = mq.TLO.Spell(entry.name)
            if spell() then
                iconCell = spell.SpellIcon()
                iconAnim = animSpells
            end
        elseif entry.type == "aa" then
            local aa = me.AltAbility(entry.name)
            if aa() and aa.Spell() then
                iconCell = aa.Spell.SpellIcon()
                iconAnim = animSpells
            end
        end
        if iconCell and iconAnim then
            local drawList = imgui.GetWindowDrawList()
            iconAnim:SetTextureCell(iconCell)
            drawList:AddTextureAnimation(iconAnim, ImVec2(headerScreenPos.x + 22, headerScreenPos.y + 2), ImVec2(16, 16))
        end
    end

    imgui.SetCursorPos(imgui.GetWindowWidth() - 160, headerCursorPos.y + yOffset)

    imgui.PushID("##hdr_ctrl_" .. idx .. suffix)

    if editable then
        local _, toggled = renderToggle("##enable", entry.enabled)
        if preRender and toggled then
            entry.enabled = not entry.enabled
            settingsDirty = true
        end
    else
        imgui.BeginDisabled()
        renderToggle("##enable", entry.enabled)
        imgui.EndDisabled()
    end

    if editable then
        imgui.SameLine()
        if idx > 1 then
            if imgui.SmallButton(icons.FA_CHEVRON_UP) and preRender then
                currentSet[idx], currentSet[idx - 1] = currentSet[idx - 1], currentSet[idx]
                settingsDirty = true
            end
        else
            imgui.InvisibleButton("##up_spacer", 22, 1)
        end

        imgui.SameLine()
        if idx < #currentSet then
            if imgui.SmallButton(icons.FA_CHEVRON_DOWN) and preRender then
                currentSet[idx], currentSet[idx + 1] = currentSet[idx + 1], currentSet[idx]
                settingsDirty = true
            end
        else
            imgui.InvisibleButton("##dn_spacer", 22, 1)
        end

        imgui.SameLine()
        if imgui.SmallButton(icons.FA_PENCIL) and preRender then
            editingIdx = idx
            editSourceType = entry.type
            editSourceName = entry.name
            editSourceMethod = entry.method
            editSourceClicky = entry.clicky
            editSourceClickyItem = entry.clickyItem and { id = entry.clickyItem.id, name = entry.clickyItem.name, icon = entry.clickyItem.icon, } or nil
        end

        imgui.SameLine()
        if imgui.SmallButton(icons.FA_TRASH) and preRender then
            pendingRemoveIdx = idx
        end
    end

    imgui.PopID()
    imgui.SetCursorPos(startingPos.x, startingPos.y)
    if not preRender then
        imgui.Dummy(0, 0)
    end
end

local function renderWelcome()
    imgui.SetNextWindowSize(ImVec2(440, 460), ImGuiCond.Always)
    local titleStr = string.format("Squire v%s by Algar###SquireWelcome", version)
    local shouldDraw = imgui.Begin(titleStr, nil, bit32.bor(ImGuiWindowFlags.NoCollapse, ImGuiWindowFlags.NoResize))
    if shouldDraw then
        renderWindowBg()

        -- Introduction
        imgui.PushStyleColor(ImGuiCol.Text, headColor)
        imgui.SetWindowFontScale(1.15)
        imgui.Text("Welcome to Squire!")
        imgui.SetWindowFontScale(1.0)
        imgui.PopStyleColor()
        imgui.Spacing()

        imgui.PushStyleColor(ImGuiCol.Text, bodyColor)
        imgui.TextWrapped("Squire arms pets with summoned gear. " ..
            "It can summon gear on command, when a tell is received, or automatically, as you see fit.")
        imgui.Spacing()
        imgui.TextWrapped("Any pet class can run Squire to monitor and report if their pet needs arming.")
        imgui.PopStyleColor()

        imgui.NewLine()

        -- Getting Started
        imgui.PushStyleColor(ImGuiCol.Text, headColor)
        imgui.Text("Getting Started")
        imgui.PopStyleColor()
        imgui.Spacing()

        imgui.PushStyleColor(ImGuiCol.Text, bodyColor)
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("Select your mode below. You can change this later.")
        imgui.Spacing()

        imgui.Indent()
        imgui.SetNextItemWidth(200)
        local rmLabel = "Manual Only"
        for _, rm in ipairs(rmOptions) do
            if rm.key == settings.reactiveMode then
                rmLabel = rm.label
                break
            end
        end
        if imgui.BeginCombo("##welcomeMode", rmLabel) then
            for _, rm in ipairs(rmOptions) do
                if imgui.Selectable(rm.label, rm.key == settings.reactiveMode) then
                    local oldMode = settings.reactiveMode
                    settings.reactiveMode = rm.key
                    settingsDirty = true
                    reactive.onModeChange(oldMode, rm.key)
                end
                if rm.tooltip and imgui.IsItemHovered() then
                    imgui.SetTooltip(rm.tooltip)
                end
            end
            imgui.EndCombo()
        end
        for _, rm in ipairs(rmOptions) do
            if rm.key == settings.reactiveMode then
                imgui.TextColored(0.5, 0.7, 0.5, 1, rm.tooltip)
                break
            end
        end
        imgui.Unindent()

        imgui.Spacing()
        if settings.selectedSet ~= "" then
            imgui.Bullet()
            imgui.SameLine()
            imgui.TextWrapped("A preset equipment set '%s' has been selected for your class.", settings.selectedSet)
            imgui.Spacing()
        end
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("'Manage Sets' to customize the gear Squire hands out.")
        imgui.Spacing()
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("Configure behavior or see a command list by clicking the options cog.")
        imgui.Spacing()
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("Type /squire show to open the UI at any time.")
        imgui.Spacing()
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("Type /squire help for a full list of commands.")
        imgui.PopStyleColor()

        -- Footer: Dismiss All + Continue
        imgui.NewLine()
        imgui.Separator()
        imgui.Spacing()

        local checkLabel = "Dismiss for all characters"
        local checkW = imgui.CalcTextSize(checkLabel) + imgui.GetFrameHeight() + imgui.GetStyle().ItemInnerSpacing.x
        imgui.SetCursorPosX((imgui.GetWindowWidth() - checkW) * 0.5)
        welcomeDismissAll = imgui.Checkbox(checkLabel, welcomeDismissAll)
        imgui.Spacing()

        local btnWidth = 100
        imgui.SetCursorPosX((imgui.GetWindowWidth() - btnWidth) * 0.5)
        imgui.PushStyleVar(ImGuiStyleVar.FramePadding, 12, 4)
        if imgui.Button("Continue", btnWidth, 0) then
            settings.welcomeDone = true
            settingsDirty = true
            showWelcome = false
            if welcomeDismissAll then
                reactive.broadcastWelcomeDone()
            end
            if settings.reactiveMode == "page" then
                showUI = false
                utils.output("Started in Page mode - UI hidden. Type /squire show to reopen.")
            end
        end
        imgui.PopStyleVar()
    end
    imgui.End()
end

-- Per-Window Render Functions

local function renderMainWindow()
    imgui.SetNextWindowSize(ImVec2(400, 420), ImGuiCond.FirstUseEver)
    imgui.SetNextWindowSizeConstraints(ImVec2(400, 420), ImVec2(800, 2000))
    local prevShowUI = showUI
    local shouldDraw
    showUI, shouldDraw = imgui.Begin("Squire - Arm Thy Pet!", showUI)
    if not showUI and prevShowUI then
        utils.output("Window closed. Use \ag/squire show\ax to reopen.")
    end
    if shouldDraw then
        renderWindowBg()
        local contentStartPos = imgui.GetCursorPosVec()
        local pageOnly = settings.reactiveMode == "page"

        -- Status
        imgui.Text("Status:")
        imgui.SameLine()
        if pageOnly then
            imgui.TextColored(0.4, 0.8, 1, 1, "Monitoring")
        elseif aborted then
            imgui.TextColored(1, 0, 0, 1, "HALTED")
            imgui.SameLine()
            if imgui.SmallButton("Reset") then
                aborted = false
                stopRequested = false
                statusText = "Idle"
                reactive.onReset()
            end
            imgui.TextColored(1, 0, 0, 1, statusText)
        elseif isArming then
            imgui.TextColored(1, 1, 0, 1, statusText)
        else
            local displayStatus = statusText
            local queueCount = reactive.getQueueCount()
            if statusText == "Idle" and queueCount > 0 then
                local reason = reactive.getBlockReason()
                displayStatus = string.format("Idle (%d queued - %s)",
                    queueCount, reason or "waiting")
            end
            imgui.TextColored(0, 1, 0, 1, displayStatus)
        end

        -- Set selector + Manage Sets button
        if pageOnly then imgui.BeginDisabled() end
        imgui.Text("Current Set:")
        imgui.SameLine()
        imgui.SetNextItemWidth(200)
        local comboLabel = settings.selectedSet ~= "" and settings.selectedSet or "No Sets Found"
        if settings.selectedSet == "" then imgui.PushStyleColor(ImGuiCol.Text, ImVec4(0.5, 0.5, 0.5, 1.0)) end
        if imgui.BeginCombo("##SetCombo", comboLabel) then
            for _, name in ipairs(getAllSetNames()) do
                if imgui.Selectable(name, name == settings.selectedSet) then
                    settings.selectedSet = name
                    settingsDirty = true
                    editingIdx = nil
                    showAddSource = false
                    pendingRemoveIdx = nil
                end
            end
            imgui.EndCombo()
        end
        if settings.selectedSet == "" then imgui.PopStyleColor() end
        imgui.SameLine()
        if imgui.Button("Manage") then
            showManageSets = not showManageSets
        end

        imgui.SeparatorText("Arming")

        -- Arm Controls
        if isArming then imgui.BeginDisabled() end
        imgui.PushStyleVar(ImGuiStyleVar.FramePadding, 8, 6)
        if imgui.Button("My Pet") then
            addToQueue(me.DisplayName(), nil, false)
        end
        imgui.SameLine()
        if imgui.Button("Target's Pet") then
            commandHandler("arm", "target")
        end
        imgui.SameLine()
        if imgui.Button("Group Pets") then
            commandHandler("arm", "group")
        end
        imgui.SameLine()
        if imgui.Button("Raid Pets") then
            commandHandler("arm", "raid")
        end
        imgui.PopStyleVar()

        imgui.Text("Arm a player's pet:")
        imgui.SameLine()
        imgui.SetNextItemWidth(150)
        manualPlayerName = imgui.InputTextWithHint("##PlayerName", "Player Name", manualPlayerName)
        imgui.SameLine()
        if imgui.Button("Arm") and manualPlayerName ~= "" then
            addToQueue(manualPlayerName, nil, false)
        end
        if isArming then imgui.EndDisabled() end
        if pageOnly then imgui.EndDisabled() end

        if isArming then
            if imgui.Button("Stop") then
                commandHandler("stop")
            end
        end

        if imgui.CollapsingHeader("History") then
            local _, availY = imgui.GetContentRegionAvail()
            imgui.BeginChild("##HistoryScroll", ImVec2(0, availY - imgui.GetFrameHeightWithSpacing()), 0)
            for _, histEntry in ipairs(armHistory) do
                imgui.TextColored(0.4, 0.8, 0.4, 1, "[%s]", histEntry.timestamp)
                imgui.SameLine(0, 4)
                if #histEntry.failed > 0 then
                    imgui.TextWrapped("Processed %d/%d sources for %s pet. (Set: %s) Failed: %s%s",
                        histEntry.passed, histEntry.total, petDisplayName(histEntry.playerName), histEntry.setName,
                        table.concat(histEntry.failed, ", "), histEntry.aborted and " (ABORTED)" or "")
                else
                    imgui.TextWrapped("Processed %d/%d sources for %s pet. (Set: %s)%s",
                        histEntry.passed, histEntry.total, petDisplayName(histEntry.playerName), histEntry.setName,
                        histEntry.aborted and " (ABORTED)" or "")
                end
            end
            if #armHistory == 0 then
                imgui.TextDisabled("No history yet.")
            end
            imgui.EndChild()
        end

        -- Cog icon in upper right (drawn last so it's on top)
        local btnSize = imgui.CalcTextSize(icons.FA_COGS) + imgui.GetStyle().FramePadding.x * 2
        imgui.SetCursorPos(imgui.GetWindowWidth() - btnSize - imgui.GetStyle().WindowPadding.x, contentStartPos.y)
        if imgui.SmallButton(icons.FA_COGS) then
            showSettings = not showSettings
        end
        if imgui.IsItemHovered() then imgui.SetTooltip("Settings and Commands") end
    end
    imgui.End()
end

local function renderSettingsWindow()
    local settingsHeight = commandsExpanded and 620 or 440
    imgui.SetNextWindowSize(ImVec2(420, settingsHeight), ImGuiCond.Always)
    local settingsDraw
    showSettings, settingsDraw = imgui.Begin("Squire Settings###SquireSettings", showSettings, ImGuiWindowFlags.NoResize)
    if settingsDraw then
        renderWindowBg(440)
        local changed

        imgui.SetNextItemWidth(200)
        local rmLabel = "Manual Only"
        for _, rm in ipairs(rmOptions) do
            if rm.key == settings.reactiveMode then
                rmLabel = rm.label
                break
            end
        end
        if imgui.BeginCombo("##reactiveMode", rmLabel) then
            for _, rm in ipairs(rmOptions) do
                if imgui.Selectable(rm.label, rm.key == settings.reactiveMode) then
                    local oldMode = settings.reactiveMode
                    settings.reactiveMode = rm.key
                    settingsDirty = true
                    reactive.onModeChange(oldMode, rm.key)
                end
                if rm.tooltip and imgui.IsItemHovered() then
                    imgui.SetTooltip(rm.tooltip)
                end
            end
            imgui.EndCombo()
        end
        imgui.SameLine()
        imgui.Text("Mode")

        if (settings.reactiveMode == "squire" or settings.reactiveMode == "both")
            and (settings.selectedSet == "" or not getSet(settings.selectedSet)) then
            imgui.TextColored(1, 0.3, 0.3, 1, "No set selected - reactive arming disabled.")
        end

        local pageOnly = settings.reactiveMode == "page"
        if pageOnly then imgui.BeginDisabled() end

        imgui.Separator()

        local taIndex = findIndex(tellAccessOptions, settings.tellAccess)
        imgui.SetNextItemWidth(200)
        if imgui.BeginCombo("##tellAccess", tellAccessOptions[taIndex].label) then
            for _, opt in ipairs(tellAccessOptions) do
                if imgui.Selectable(opt.label, opt.key == settings.tellAccess) then
                    local wasDisabled = settings.tellAccess == "disabled"
                    settings.tellAccess = opt.key
                    settingsDirty = true
                    if opt.key == "disabled" then
                        unregisterTellEvent()
                    elseif wasDisabled then
                        registerTellEvent()
                    end
                end
            end
            imgui.EndCombo()
        end
        imgui.SameLine()
        imgui.Text("Tell Access")
        if imgui.IsItemHovered(ImGuiHoveredFlags.AllowWhenDisabled) then
            imgui.SetTooltip("Who can request arming via tell.")
        end
        imgui.SameLine()
        local startX = imgui.GetCursorPosX()
        local endX = imgui.GetWindowWidth() - imgui.GetStyle().WindowPadding.x
        local checkboxWidth = imgui.GetFrameHeight() + imgui.GetStyle().ItemInnerSpacing.x + imgui.CalcTextSize("Tell Replies")
        imgui.SetCursorPosX(startX + (endX - startX - checkboxWidth) / 2)
        settings.tellReplies, changed = imgui.Checkbox("Tell Replies", settings.tellReplies)
        if imgui.IsItemHovered(ImGuiHoveredFlags.AllowWhenDisabled) then
            imgui.SetTooltip("Reply to players who request arming.")
        end
        if changed then settingsDirty = true end

        if settings.tellAccess == "allowlist" then
            local alStr = table.concat(settings.tellAllowlist, ", ")
            imgui.SetNextItemWidth(350)
            alStr, changed = imgui.InputTextWithHint("##allowList", "Player1, Player2", alStr)
            if changed then
                settings.tellAllowlist = {}
                for name in alStr:gmatch("([^,]+)") do
                    local trimmed = name:gsub("^%s+", ""):gsub("%s+$", "")
                    if trimmed ~= "" then
                        table.insert(settings.tellAllowlist, trimmed)
                    end
                end
                settingsDirty = true
            end
            imgui.SameLine()
            imgui.Text("Allow List")
            if imgui.IsItemHovered(ImGuiHoveredFlags.AllowWhenDisabled) then
                imgui.SetTooltip("Only react to keywords from the listed players.")
            end
        end

        if settings.tellAccess == "denylist" then
            local dlStr = table.concat(settings.tellDenylist, ", ")
            imgui.SetNextItemWidth(350)
            dlStr, changed = imgui.InputTextWithHint("##denyList", "Player1, Player2", dlStr)
            if changed then
                settings.tellDenylist = {}
                for name in dlStr:gmatch("([^,]+)") do
                    local trimmed = name:gsub("^%s+", ""):gsub("%s+$", "")
                    if trimmed ~= "" then
                        table.insert(settings.tellDenylist, trimmed)
                    end
                end
                settingsDirty = true
            end
            imgui.SameLine()
            imgui.Text("Deny List")
            if imgui.IsItemHovered(ImGuiHoveredFlags.AllowWhenDisabled) then
                imgui.SetTooltip("Will not react to keywords from the listed players.")
            end
        end

        imgui.SetNextItemWidth(200)
        local tw
        tw, changed = imgui.InputTextWithHint("##triggerWord", "e.g. squire", settings.triggerWord)
        if changed then
            settings.triggerWord = tw
            settingsDirty = true
        end
        imgui.SameLine()
        imgui.Text("Tell Trigger")
        if imgui.IsItemHovered(ImGuiHoveredFlags.AllowWhenDisabled) then
            local example = settings.triggerWord ~= "" and settings.triggerWord or "squire"
            imgui.SetTooltip("Keyword in a tell that triggers arming.\nExample: /tell YourName %s [Set Name]", example)
        end

        imgui.Separator()

        local announceOptions = {
            { key = "disabled", label = "Disabled", },
            { key = "group",    label = "Group", },
            { key = "raid",     label = "Raid", },
            { key = "dannet",   label = "DanNet", },
            { key = "e3bcs",    label = "E3BCS", },
        }
        local aaIndex = findIndex(announceOptions, settings.announceArming)
        imgui.SetNextItemWidth(200)
        if imgui.BeginCombo("##announceArming", announceOptions[aaIndex].label) then
            for _, opt in ipairs(announceOptions) do
                if imgui.Selectable(opt.label, opt.key == settings.announceArming) then
                    settings.announceArming = opt.key
                    settingsDirty = true
                end
            end
            imgui.EndCombo()
        end
        imgui.SameLine()
        imgui.Text("Announce Arming")
        if imgui.IsItemHovered(ImGuiHoveredFlags.AllowWhenDisabled) then
            imgui.SetTooltip("Announce when arming starts and finishes.")
        end

        imgui.SetNextItemWidth(200)
        local pqc
        pqc, changed = imgui.InputTextWithHint("##preQueueCmd", "/echo Arming started", settings.preQueueCommand)
        if changed then
            settings.preQueueCommand = pqc
            settingsDirty = true
        end
        imgui.SameLine()
        imgui.Text("Pre-Queue Command")
        if imgui.IsItemHovered(ImGuiHoveredFlags.AllowWhenDisabled) then
            imgui.SetTooltip("Execute this command before arming is started.")
        end

        imgui.SetNextItemWidth(200)
        local poqc
        poqc, changed = imgui.InputTextWithHint("##postQueueCmd", "/echo Arming complete", settings.postQueueCommand)
        if changed then
            settings.postQueueCommand = poqc
            settingsDirty = true
        end
        imgui.SameLine()
        imgui.Text("Post-Queue Command")
        if imgui.IsItemHovered(ImGuiHoveredFlags.AllowWhenDisabled) then
            imgui.SetTooltip("Execute this command once arming is complete (or aborted).")
        end

        imgui.Separator()

        if not delivery.navLoaded then imgui.BeginDisabled() end
        settings.allowMovement, changed = imgui.Checkbox("Nav to Pets", settings.allowMovement)
        if imgui.IsItemHovered(ImGuiHoveredFlags.AllowWhenDisabled) then
            if delivery.navLoaded then
                imgui.SetTooltip("Allow this PC to move to arm a pet. Will return to the original location when complete.")
            else
                imgui.SetTooltip("MQ2Nav is not loaded - navigation features are unavailable.")
            end
        end
        if changed then settingsDirty = true end
        imgui.SameLine(0, 30)
        local targetRight = 200 + imgui.GetStyle().WindowPadding.x
        imgui.SetNextItemWidth(targetRight - imgui.GetCursorPosX())
        local nd
        nd, changed = imgui.InputInt("##navDistance", settings.navDistance, 0, 0)
        if changed then
            settings.navDistance = math.max(10, math.min(500, nd))
            settingsDirty = true
        end
        imgui.SameLine()
        imgui.Text("Max Distance")
        if imgui.IsItemHovered(ImGuiHoveredFlags.AllowWhenDisabled) then
            imgui.SetTooltip("Maximum distance (in units) Squire will navigate to reach a pet.")
        end
        if not delivery.navLoaded then
            settings.allowMovement = false
            imgui.EndDisabled()
        end

        if pageOnly then imgui.EndDisabled() end

        local pageActive = settings.reactiveMode == "page" or settings.reactiveMode == "both"
        if not pageActive then imgui.BeginDisabled() end
        settings.alwaysRequestArming, changed = imgui.Checkbox("My Pet Appears Armed When Summoned", settings.alwaysRequestArming)
        if imgui.IsItemHovered(ImGuiHoveredFlags.AllowWhenDisabled) then
            imgui.SetTooltip(
                "Squire checks for visible weapons to determine if a pet needs arming.\nIf your pet appears armed when summoned (e.g., enchanter animations),\ncheck this option to request arming in page mode anyway.\nDoes not affect the current pet.")
        end
        if changed then settingsDirty = true end
        if not pageActive then imgui.EndDisabled() end

        local prevArmInCombat = settings.armInCombat
        settings.armInCombat, changed = imgui.Checkbox("Limited Combat Arming", settings.armInCombat)
        if imgui.IsItemHovered() then
            imgui.SetTooltip("Allows limited arming under combat conditions. Can cause undesirable behavior.")
        end
        if changed then
            if settings.armInCombat and not prevArmInCombat then
                settings.armInCombat = false
                imgui.OpenPopup("ArmInCombatConfirm##Settings")
            else
                settingsDirty = true
            end
        end

        imgui.SetNextWindowSize(ImVec2(440, 0), ImGuiCond.Appearing)
        if imgui.BeginPopup("ArmInCombatConfirm##Settings") then
            imgui.PushTextWrapPos(420)
            imgui.TextWrapped("Allows limited arming under combat conditions.")
            imgui.Spacing()
            imgui.TextWrapped(
                "Squire is unable to trade with attacking pets. Trade-based sources (cursor, bag, trade) are skipped if the pet is attacking - only direct-to-pet sources (spells, AAs, clickies targeting the pet) will run.")
            imgui.Spacing()
            imgui.TextWrapped(
                "Mixed-source sets may result in repeated arming, a pet not receiving all items, or other undesirable behavior. This option is largely aimed at servers where all sources are direct-to-pet types, or automation where pets aren't sent in to attack automatically.")
            imgui.Spacing()
            imgui.TextWrapped("Are you sure you wish to use this feature?")
            imgui.PopTextWrapPos()
            imgui.Spacing()
            if imgui.Button("Enable") then
                settings.armInCombat = true
                settingsDirty = true
                imgui.CloseCurrentPopup()
            end
            imgui.SameLine()
            if imgui.Button("Close##ArmInCombat") then
                imgui.CloseCurrentPopup()
            end
            imgui.EndPopup()
        end

        settings.debugMode, changed = imgui.Checkbox("Debug Logging", settings.debugMode)
        if changed then settingsDirty = true end

        imgui.NewLine()
        imgui.PushStyleColor(ImGuiCol.Text, headColor)
        commandsExpanded = imgui.CollapsingHeader("Commands: /squire ...")
        imgui.PopStyleColor()
        if commandsExpanded then
            local cmdUsageColor = ImVec4(0.5, 0.72, 0.85, 1.0)
            imgui.PushTextWrapPos(0)
            for _, name in ipairs(commandOrder) do
                local cmd = commands[name]
                local shortUsage = cmd.usage:gsub("^/squire ", "")
                imgui.Indent(10)
                imgui.PushStyleColor(ImGuiCol.Text, cmdUsageColor)
                imgui.Text("%s", shortUsage)
                imgui.PopStyleColor()
                imgui.SameLine(0, 0)
                imgui.PushStyleColor(ImGuiCol.Text, bodyColor)
                imgui.Text(" - %s", cmd.about)
                imgui.PopStyleColor()
                imgui.Unindent(10)
            end
            imgui.PopTextWrapPos()
        end

        -- Logo and credits at bottom
        imgui.SetCursorPosY(imgui.GetWindowHeight() - 75 - imgui.GetStyle().WindowPadding.y)
        local blockY = imgui.GetCursorPosY()
        if logoTexture then
            imgui.SetCursorPosY(blockY + 10)
            imgui.Image(logoTexture:GetTextureID(), ImVec2(60, 60))
            imgui.SameLine(0, 2)
        end
        imgui.BeginGroup()
        if shieldTexture then
            imgui.SetCursorPosY(blockY + 13)
            local shieldPos = imgui.GetCursorScreenPosVec()
            imgui.Dummy(23, 20)
            imgui.GetWindowDrawList():AddImage(shieldTexture:GetTextureID(),
                shieldPos, ImVec2(shieldPos.x + 23, shieldPos.y + 20),
                ImVec2(0, 0), ImVec2(1, 1), IM_COL32(0, 153, 153, 255))
            imgui.SameLine(0, 1)
        end
        imgui.SetWindowFontScale(1.3)
        imgui.SetCursorPosY(blockY + 13)
        imgui.TextColored(0.0, 0.6, 0.6, 1.0, "Squire")
        imgui.SetWindowFontScale(1.0)
        imgui.SameLine(0, 4)
        imgui.SetCursorPosY(blockY + 17)
        imgui.Text("v" .. version .. " by")
        imgui.SameLine(0, 4)
        imgui.SetCursorPosY(blockY + 13)
        imgui.SetWindowFontScale(1.3)
        imgui.TextColored(1.0, 0.5, 0.0, 1.0, "Algar")
        imgui.SetWindowFontScale(1.0)
        imgui.SetCursorPosY(imgui.GetCursorPosY() - 3)
        imgui.SetCursorPosX(imgui.GetCursorPosX() + 6)
        imgui.Text("See my other projects at:")
        imgui.SetCursorPosY(imgui.GetCursorPosY() - 3)
        imgui.SetCursorPosX(imgui.GetCursorPosX() + 6)
        imgui.TextColored(0.4, 0.6, 1.0, 1, "https://www.github.com/AlgarDude")
        if imgui.IsItemHovered() then
            imgui.SetTooltip("Click to copy URL")
        end
        if imgui.IsItemClicked() then
            imgui.SetClipboardText("https://www.github.com/AlgarDude")
        end
        imgui.EndGroup()
    end
    imgui.End()
end

local function renderManageSetsWindow()
    imgui.SetNextWindowSize(ImVec2(520, 450), ImGuiCond.FirstUseEver)
    imgui.SetNextWindowSizeConstraints(ImVec2(520, 200), ImVec2(800, 2000))
    local manageSetsDraw
    showManageSets, manageSetsDraw = imgui.Begin("Manage Sets###SquireEditSets", showManageSets)
    if manageSetsDraw then
        renderWindowBg()
        local isPreset = isPresetSet(settings.selectedSet)

        -- Row 1: Set selector + right-aligned Rescan/Help
        imgui.Text("Set:")
        imgui.SameLine()
        imgui.SetNextItemWidth(200)
        if imgui.BeginCombo("##EditSetCombo", settings.selectedSet) then
            for _, name in ipairs(getAllSetNames()) do
                if imgui.Selectable(name .. "##edit", name == settings.selectedSet) then
                    settings.selectedSet = name
                    settingsDirty = true
                    editingIdx = nil
                    showAddSource = false
                    pendingRemoveIdx = nil
                end
            end
            imgui.EndCombo()
        end

        local refreshWidth = imgui.CalcTextSize(icons.FA_REFRESH) + imgui.GetStyle().FramePadding.x * 2
        local helpWidth = imgui.CalcTextSize(icons.FA_QUESTION_CIRCLE) + imgui.GetStyle().FramePadding.x * 2
        local spacing = imgui.GetStyle().ItemSpacing.x
        imgui.SameLine(imgui.GetContentRegionAvail() - refreshWidth - helpWidth - spacing + imgui.GetCursorPosX())
        if imgui.Button(icons.FA_REFRESH .. "##Rescan") then
            resolvePresets()
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip("Updates the preset by rechecking your current spells, AAs, and items.")
        end
        imgui.SameLine()
        if imgui.SmallButton(icons.FA_QUESTION_CIRCLE .. "##Help") then
            showHelp = true
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip("Help")
        end

        -- Row 2: New Copy Rename Delete
        if imgui.Button("New") then
            newSetName = ""
            imgui.OpenPopup("NewSetPopup##Edit")
        end
        imgui.SameLine()
        if imgui.Button("Copy") then
            newSetName = ""
            imgui.OpenPopup("CopySetPopup##Edit")
        end
        imgui.SameLine()
        if isPreset then imgui.BeginDisabled() end
        if imgui.Button("Rename") then
            renameSetName = settings.selectedSet
            imgui.OpenPopup("RenameSetPopup##Edit")
        end
        imgui.SameLine()
        if imgui.Button("Delete") then
            imgui.OpenPopup("DeleteSetPopup##Edit")
        end
        if isPreset then imgui.EndDisabled() end

        -- New popup
        if imgui.BeginPopup("NewSetPopup##Edit") then
            imgui.Text("New Set Name:")
            newSetName = imgui.InputTextWithHint("##NewSetName", "Set Name", newSetName)
            if imgui.Button("Create") and newSetName ~= "" then
                if not settings.sets[newSetName] and not presetSets[newSetName] then
                    settings.sets[newSetName] = {}
                    settings.selectedSet = newSetName
                    settingsDirty = true
                end
                imgui.CloseCurrentPopup()
            end
            imgui.SameLine()
            if imgui.Button("Cancel##New") then
                imgui.CloseCurrentPopup()
            end
            imgui.EndPopup()
        end

        -- Copy popup
        if imgui.BeginPopup("CopySetPopup##Edit") then
            imgui.Text("Copy '%s' as:", settings.selectedSet)
            newSetName = imgui.InputTextWithHint("##CopySetName", "Set Name", newSetName)
            if imgui.Button("Copy##Confirm") and newSetName ~= "" then
                if not settings.sets[newSetName] and not presetSets[newSetName] then
                    local sourceSet = getSet(settings.selectedSet)
                    if sourceSet then
                        local newSet = {}
                        for _, entry in ipairs(sourceSet) do
                            if entry.name ~= "" then
                                local copy = {
                                    enabled = entry.enabled,
                                    name = entry.name,
                                    type = entry.type,
                                    method = entry.method,
                                    clicky = entry.clicky,
                                    clickyItem = entry.clickyItem and { id = entry.clickyItem.id, name = entry.clickyItem.name, icon = entry.clickyItem.icon, } or nil,
                                    items = {},
                                    trashItems = {},
                                }
                                for _, item in ipairs(entry.items) do
                                    table.insert(copy.items, { id = item.id, name = item.name, icon = item.icon, })
                                end
                                for _, trash in ipairs(entry.trashItems or {}) do
                                    table.insert(copy.trashItems, { id = trash.id, name = trash.name, icon = trash.icon, })
                                end
                                table.insert(newSet, copy)
                            end
                        end
                        settings.sets[newSetName] = newSet
                        settings.selectedSet = newSetName
                        settingsDirty = true
                    end
                end
                imgui.CloseCurrentPopup()
            end
            imgui.SameLine()
            if imgui.Button("Cancel##Copy") then
                imgui.CloseCurrentPopup()
            end
            imgui.EndPopup()
        end

        -- Rename popup
        if imgui.BeginPopup("RenameSetPopup##Edit") then
            imgui.Text("Rename '%s' to:", settings.selectedSet)
            renameSetName = imgui.InputTextWithHint("##RenameSetName", "Set Name", renameSetName)
            if imgui.Button("Rename##Confirm") and renameSetName ~= "" and renameSetName ~= settings.selectedSet then
                if not settings.sets[renameSetName] and not presetSets[renameSetName] then
                    settings.sets[renameSetName] = settings.sets[settings.selectedSet]
                    settings.sets[settings.selectedSet] = nil
                    settings.selectedSet = renameSetName
                    settingsDirty = true
                end
                imgui.CloseCurrentPopup()
            end
            imgui.SameLine()
            if imgui.Button("Cancel##Rename") then
                imgui.CloseCurrentPopup()
            end
            imgui.EndPopup()
        end

        -- Delete popup
        if imgui.BeginPopup("DeleteSetPopup##Edit") then
            imgui.Text("Delete '%s'?", settings.selectedSet)
            if imgui.Button("Yes, Delete") then
                settings.sets[settings.selectedSet] = nil
                local remaining = getAllSetNames()
                settings.selectedSet = remaining[1] or ""
                settingsDirty = true
                imgui.CloseCurrentPopup()
            end
            imgui.SameLine()
            if imgui.Button("Cancel##Delete") then
                imgui.CloseCurrentPopup()
            end
            imgui.EndPopup()
        end

        -- Source entries
        local currentSet = getSet(settings.selectedSet)
        if currentSet then
            local editable = not isPreset and not isArming

            imgui.SeparatorText("Sources")

            for i, entry in ipairs(currentSet) do
                imgui.PushID("##source_" .. i)

                local headerScreenPos = imgui.GetCursorScreenPosVec()
                local headerCursorPos = imgui.GetCursorPosVec()

                -- Pre-render: functional click targets (drawn before header to claim clicks)
                renderSourceHeaderControls(currentSet, i, headerCursorPos, headerScreenPos, true, editable)

                -- Build display name
                local unresolved = entry.name == "" and entry.candidates
                local displayName
                if unresolved then
                    displayName = "(No Source Found)"
                else
                    displayName = entry.name ~= "" and entry.name or "(unnamed)"
                    if entry.items and #entry.items > 0 then
                        displayName = displayName .. string.format(" (%d item%s)", #entry.items, #entry.items > 1 and "s" or "")
                    end
                end

                if unresolved then imgui.PushStyleColor(ImGuiCol.Text, ImVec4(0.5, 0.5, 0.5, 1.0)) end
                local headerOpen = imgui.CollapsingHeader("       " .. displayName .. "###header")
                if unresolved then imgui.PopStyleColor() end

                -- Post-render: visible controls + icon overlay (drawn after header)
                renderSourceHeaderControls(currentSet, i, headerCursorPos, headerScreenPos, false, editable)

                -- Expanded content: item management
                if headerOpen and entry.method ~= "direct" and not unresolved then
                    imgui.Indent()

                    if entry.clicky and entry.clickyItem then
                        imgui.Text("Clicky:")
                        imgui.SameLine()
                        if entry.clickyItem.icon then
                            renderItemIcon(entry.clickyItem.icon)
                        end
                        imgui.Text(entry.clickyItem.name)
                        imgui.Spacing()
                    end

                    imgui.Text("Items to Give:")
                    local removeItemIdx = nil
                    for j, item in ipairs(entry.items) do
                        imgui.PushID("##item_" .. j)
                        if item.icon then renderItemIcon(item.icon) end
                        local itemLabel = item.name and item.name ~= "" and item.name or string.format("[ID: %d]", item.id)
                        imgui.Text(itemLabel)
                        if editable then
                            imgui.SameLine()
                            if imgui.SmallButton(icons.FA_TRASH) then
                                removeItemIdx = j
                            end
                        end
                        imgui.PopID()
                    end
                    if removeItemIdx then
                        table.remove(entry.items, removeItemIdx)
                        settingsDirty = true
                    end
                    if editable then
                        local hasCursor = mq.TLO.Cursor.ID()
                        if not hasCursor then imgui.BeginDisabled() end
                        if imgui.SmallButton("Add from Cursor##trade") then
                            local cursor = mq.TLO.Cursor
                            table.insert(entry.items, {
                                id = cursor.ID(),
                                name = cursor.Name() or "",
                                icon = cursor.Icon(),
                            })
                            settingsDirty = true
                        end
                        if not hasCursor then
                            imgui.EndDisabled()
                            if imgui.IsItemHovered(ImGuiHoveredFlags.AllowWhenDisabled) then
                                imgui.SetTooltip("Place an item on your cursor, then click to capture.")
                            end
                        end
                    end

                    if entry.method == "bag" or entry.method == "cursor" then
                        imgui.Spacing()
                        imgui.Text("Items to Discard:")
                        local removeTrashIdx = nil
                        for j, trash in ipairs(entry.trashItems) do
                            imgui.PushID("##trash_" .. j)
                            if trash.icon then renderItemIcon(trash.icon) end
                            local trashLabel = trash.name and trash.name ~= "" and trash.name or string.format("[ID: %d]", trash.id)
                            imgui.Text(trashLabel)
                            if editable then
                                imgui.SameLine()
                                if imgui.SmallButton(icons.FA_TRASH) then
                                    removeTrashIdx = j
                                end
                            end
                            imgui.PopID()
                        end
                        if removeTrashIdx then
                            table.remove(entry.trashItems, removeTrashIdx)
                            settingsDirty = true
                        end
                        if editable then
                            local hasCursor = mq.TLO.Cursor.ID()
                            if not hasCursor then imgui.BeginDisabled() end
                            if imgui.SmallButton("Add from Cursor##discard") then
                                local cursor = mq.TLO.Cursor
                                table.insert(entry.trashItems, {
                                    id = cursor.ID(),
                                    name = cursor.Name() or "",
                                    icon = cursor.Icon(),
                                })
                                settingsDirty = true
                            end
                            if not hasCursor then
                                imgui.EndDisabled()
                                if imgui.IsItemHovered(ImGuiHoveredFlags.AllowWhenDisabled) then
                                    imgui.SetTooltip("Place an item on your cursor, then click to capture.")
                                end
                            end
                        end
                    end

                    imgui.Unindent()
                end

                if headerOpen and entry.candidates and (#entry.candidates > 1 or unresolved) then
                    imgui.Indent()
                    imgui.Separator()
                    if unresolved then
                        imgui.TextColored(1, 0.6, 0, 1, "None of these sources are available:")
                    else
                        imgui.Text("Priority List:")
                    end
                    for _, candidate in ipairs(entry.candidates) do
                        local label = string.format("%s (%s)", candidate.name, candidate.type)
                        if candidate.name == entry.name then
                            imgui.TextColored(0.4, 0.9, 0.4, 1, label)
                        else
                            imgui.TextDisabled(label)
                        end
                    end
                    imgui.Unindent()
                end

                imgui.PopID()
            end

            if editable then
                -- Delete confirmation popup
                if pendingRemoveIdx and (pendingRemoveIdx > #currentSet or pendingRemoveIdx < 1) then
                    pendingRemoveIdx = nil
                end
                if pendingRemoveIdx and not imgui.IsPopupOpen("DeleteSource##Edit") then
                    imgui.OpenPopup("DeleteSource##Edit")
                end
                if imgui.BeginPopup("DeleteSource##Edit") then
                    local entryName = pendingRemoveIdx and currentSet[pendingRemoveIdx]
                        and currentSet[pendingRemoveIdx].name or ""
                    if entryName == "" then entryName = "Source " .. (pendingRemoveIdx or 0) end
                    imgui.Text("Remove '%s'?", entryName)
                    if imgui.Button("Yes, Remove") then
                        table.remove(currentSet, pendingRemoveIdx)
                        settingsDirty = true
                        editingIdx = nil
                        pendingRemoveIdx = nil
                        imgui.CloseCurrentPopup()
                    end
                    imgui.SameLine()
                    if imgui.Button("Cancel##RemoveSource") then
                        pendingRemoveIdx = nil
                        imgui.CloseCurrentPopup()
                    end
                    imgui.EndPopup()
                end

                imgui.Separator()
                if imgui.Button("Add Source") then
                    newSourceName = ""
                    newSourceType = "spell"
                    newSourceMethod = "cursor"
                    newSourceClicky = false
                    newSourceClickyItem = nil
                    showAddSource = true
                end
            end
        end
    end
    imgui.End()
end

local function renderAddSourceWindow()
    local currentSet = getSet(settings.selectedSet)
    if not currentSet or isPresetSet(settings.selectedSet) or isArming then
        showAddSource = false
        return
    end
    imgui.SetNextWindowSize(ImVec2(350, 180), ImGuiCond.FirstUseEver)
    local addOpen, addDraw = imgui.Begin("Add Source###SquireAddSource", showAddSource)
    if not addOpen then
        showAddSource = false
    end
    if addDraw then
        local nmIdx = findIndex(methods, newSourceMethod)
        imgui.Text("Method:")
        imgui.SameLine()
        imgui.SetNextItemWidth(180)
        if imgui.BeginCombo("##newMethod", methods[nmIdx].label) then
            for _, m in ipairs(methods) do
                if imgui.Selectable(m.label, m.key == newSourceMethod) then
                    newSourceMethod = m.key
                end
            end
            imgui.EndCombo()
        end

        if newSourceMethod ~= "trade" then
            local nsIdx = findIndex(sources, newSourceType)
            imgui.Text("Source Type:")
            imgui.SameLine()
            imgui.SetNextItemWidth(180)
            if imgui.BeginCombo("##newType", sources[nsIdx].label) then
                for _, src in ipairs(sources) do
                    if imgui.Selectable(src.label, src.key == newSourceType) then
                        newSourceType = src.key
                    end
                end
                imgui.EndCombo()
            end

            imgui.Text(sources[nsIdx].label .. " Name:")
        else
            imgui.Text("Item Name:")
        end
        imgui.SameLine()
        imgui.SetNextItemWidth(350)
        newSourceName = imgui.InputTextWithHint("##newName", "Exact In-Game Name", newSourceName)

        if newSourceMethod == "bag" then
            newSourceClicky = imgui.Checkbox("Source produces clicky item", newSourceClicky)
            if newSourceClicky then
                imgui.Text("Clicky Item:")
                imgui.SameLine()
                if newSourceClickyItem then
                    if newSourceClickyItem.icon then renderItemIcon(newSourceClickyItem.icon) end
                    imgui.Text(newSourceClickyItem.name)
                    imgui.SameLine()
                    if imgui.SmallButton(icons.FA_TRASH .. "##clearClicky") then
                        newSourceClickyItem = nil
                    end
                else
                    local hasCursor = mq.TLO.Cursor.ID()
                    if not hasCursor then imgui.BeginDisabled() end
                    if imgui.SmallButton("Add from Cursor##clicky") then
                        newSourceClickyItem = {
                            id = mq.TLO.Cursor.ID(),
                            name = mq.TLO.Cursor.Name() or "",
                            icon = mq.TLO.Cursor.Icon(),
                        }
                    end
                    if not hasCursor then
                        imgui.EndDisabled()
                        if imgui.IsItemHovered(ImGuiHoveredFlags.AllowWhenDisabled) then
                            imgui.SetTooltip("Place the clicky item on your cursor, then click to capture.")
                        end
                    end
                end
            end
        end

        imgui.Spacing()
        if imgui.Button("Create") and newSourceName ~= "" then
            local newEntry = utils.defaultSourceEntry()
            newEntry.enabled = true
            newEntry.name = newSourceName
            newEntry.type = newSourceMethod == "trade" and "item" or newSourceType
            newEntry.method = newSourceMethod
            newEntry.clicky = newSourceClicky
            newEntry.clickyItem = newSourceClickyItem
            table.insert(currentSet, newEntry)
            settingsDirty = true
            showAddSource = false
            newSourceClicky = false
            newSourceClickyItem = nil
        end
        imgui.SameLine()
        if imgui.Button("Cancel##AddSource") then
            showAddSource = false
        end
    end
    imgui.End()
end

local function renderEditSourceWindow()
    local currentSet = getSet(settings.selectedSet)
    local entry = currentSet and currentSet[editingIdx]
    if not entry or isPresetSet(settings.selectedSet) or isArming then
        editingIdx = nil
        return
    end
    imgui.SetNextWindowSize(ImVec2(350, 205), ImGuiCond.FirstUseEver)
    local editOpen, editDraw = imgui.Begin("Edit Source###SquireEditSource", editingIdx ~= nil)
    if not editOpen then
        editingIdx = nil
    end
    if editDraw then
        local mIdx = findIndex(methods, editSourceMethod)
        imgui.Text("Method:")
        imgui.SameLine()
        imgui.SetNextItemWidth(180)
        if imgui.BeginCombo("##editMethod", methods[mIdx].label) then
            for _, m in ipairs(methods) do
                if imgui.Selectable(m.label, m.key == editSourceMethod) then
                    editSourceMethod = m.key
                end
            end
            imgui.EndCombo()
        end

        if editSourceMethod ~= "trade" then
            local tIdx = findIndex(sources, editSourceType)
            imgui.Text("Source Type:")
            imgui.SameLine()
            imgui.SetNextItemWidth(180)
            if imgui.BeginCombo("##editType", sources[tIdx].label) then
                for _, src in ipairs(sources) do
                    if imgui.Selectable(src.label, src.key == editSourceType) then
                        editSourceType = src.key
                    end
                end
                imgui.EndCombo()
            end

            imgui.Text(sources[tIdx].label .. " Name:")
        else
            imgui.Text("Item Name:")
        end
        imgui.SameLine()
        imgui.SetNextItemWidth(350)
        editSourceName = imgui.InputTextWithHint("##editName", "Exact In-Game Name", editSourceName)

        if editSourceMethod == "bag" then
            editSourceClicky = imgui.Checkbox("Source produces clicky item", editSourceClicky)
            if editSourceClicky then
                imgui.Text("Clicky Item:")
                imgui.SameLine()
                if editSourceClickyItem then
                    if editSourceClickyItem.icon then renderItemIcon(editSourceClickyItem.icon) end
                    imgui.Text(editSourceClickyItem.name)
                    imgui.SameLine()
                    if imgui.SmallButton(icons.FA_TRASH .. "##clearClicky") then
                        editSourceClickyItem = nil
                    end
                else
                    local hasCursor = mq.TLO.Cursor.ID()
                    if not hasCursor then imgui.BeginDisabled() end
                    if imgui.SmallButton("Add from Cursor##clicky") then
                        editSourceClickyItem = {
                            id = mq.TLO.Cursor.ID(),
                            name = mq.TLO.Cursor.Name() or "",
                            icon = mq.TLO.Cursor.Icon(),
                        }
                    end
                    if not hasCursor then
                        imgui.EndDisabled()
                        if imgui.IsItemHovered(ImGuiHoveredFlags.AllowWhenDisabled) then
                            imgui.SetTooltip("Place the clicky item on your cursor, then click to capture.")
                        end
                    end
                end
            end
        end

        imgui.Spacing()
        if imgui.Button("Save") then
            entry.type = editSourceMethod == "trade" and "item" or editSourceType
            entry.name = editSourceName
            entry.method = editSourceMethod
            entry.clicky = editSourceClicky
            entry.clickyItem = editSourceClickyItem
            settingsDirty = true
            editingIdx = nil
        end
        imgui.SameLine()
        if imgui.Button("Cancel##EditSource") then
            editingIdx = nil
        end
    end
    imgui.End()
end

local function renderHelpWindow()
    imgui.SetNextWindowSize(ImVec2(575, 600), ImGuiCond.FirstUseEver)
    imgui.SetNextWindowSizeConstraints(ImVec2(575, 600), ImVec2(800, 2000))
    local helpDraw
    showHelp, helpDraw = imgui.Begin("Squire Help###SquireHelp", showHelp)
    if helpDraw then
        renderWindowBg()

        imgui.PushStyleColor(ImGuiCol.Text, headColor)
        imgui.SeparatorText("Glossary")
        imgui.PopStyleColor()
        imgui.Spacing()
        imgui.PushStyleColor(ImGuiCol.Text, bodyColor)
        imgui.Bullet()
        imgui.TextWrapped("Source - A spell, AA, or clickie that makes gear for a pet")
        imgui.Bullet()
        imgui.TextWrapped("Set - A list of sources to give a pet")
        imgui.Bullet()
        imgui.TextWrapped("Preset - A ready-made set that picks the best sources you have")
        imgui.PopStyleColor()

        imgui.NewLine()
        imgui.PushStyleColor(ImGuiCol.Text, headColor)
        imgui.SeparatorText("Delivery Methods")
        imgui.PopStyleColor()
        imgui.Spacing()
        imgui.PushStyleColor(ImGuiCol.Text, bodyColor)
        imgui.BulletText(methods[1].label)
        imgui.Indent()
        imgui.TextWrapped("Places an item on your cursor. Squire gives it to the pet. " ..
            "Unwanted byproducts can be listed in \"Items to Discard\".")
        imgui.Unindent()
        imgui.Spacing()
        imgui.BulletText(methods[2].label)
        imgui.Indent()
        imgui.TextWrapped(
            "Places a bag on your cursor. Squire gives the pet \"Items to Give\" " ..
            "from the bag, and destroys \"Items to Discard\".")
        imgui.Unindent()
        imgui.Spacing()
        imgui.BulletText(methods[3].label)
        imgui.Indent()
        imgui.TextWrapped("Equips an item directly on the pet. No items to set up.")
        imgui.Unindent()
        imgui.Spacing()
        imgui.BulletText(methods[4].label)
        imgui.Indent()
        imgui.TextWrapped("Trade an item already in your inventory to the pet. One item per entry.")
        imgui.Unindent()
        imgui.PopStyleColor()

        imgui.NewLine()
        imgui.PushStyleColor(ImGuiCol.Text, headColor)
        imgui.SeparatorText("How to Add Items")
        imgui.PopStyleColor()
        imgui.Spacing()
        imgui.PushStyleColor(ImGuiCol.Text, bodyColor)
        imgui.Indent()
        imgui.TextWrapped("1. Click \"Add Source\" at the bottom of the \"Manage Sets\" window.")
        imgui.Spacing()
        imgui.TextWrapped("2. Pick the source type (Spell, AA, or Item) and enter the exact in-game name.")
        imgui.Spacing()
        imgui.TextWrapped("3. Choose the delivery method (see above).")
        imgui.Spacing()
        imgui.TextWrapped(
            "4. Cursor or Bag methods: Anything the pet should receive should be added to \"Items to Give\". " ..
            "Put the summoned item on your cursor and click \"Add from Cursor\".")
        imgui.Spacing()
        imgui.TextWrapped(
            "5. Cursor or Bag methods: Anything that should be cleaned up afterwards should be " ..
            "added to \"Items to Discard\". For bags, include the bag itself. " ..
            "Any temporary items in a bag will be destroyed with it and do not need to be listed.")
        imgui.Unindent()
        imgui.PopStyleColor()
    end
    imgui.End()
end

-- Render Dispatcher

local function renderUI()
    if mq.TLO.MacroQuest.GameState() ~= 'INGAME' then return end
    if not showUI and not showWelcome then return end

    imgui.PushStyleVar(ImGuiStyleVar.FrameRounding, 4)
    imgui.PushStyleVar(ImGuiStyleVar.WindowRounding, 6)
    imgui.PushStyleVar(ImGuiStyleVar.ChildRounding, 4)
    imgui.PushStyleVar(ImGuiStyleVar.PopupRounding, 4)
    imgui.PushStyleVar(ImGuiStyleVar.GrabRounding, 4)

    if showWelcome then
        renderWelcome()
        imgui.PopStyleVar(5)
        return
    end

    renderMainWindow()
    if showSettings then renderSettingsWindow() end
    if showManageSets then renderManageSetsWindow() end
    if showAddSource then renderAddSourceWindow() end
    if editingIdx then renderEditSourceWindow() end
    if showHelp then renderHelpWindow() end

    imgui.PopStyleVar(5)
end

-- Startup

local function startup()
    settings = utils.loadSettings()
    utils.bindConfig(settings)
    resolvePresets()

    if not getSet(settings.selectedSet) then
        settings.selectedSet = next(settings.sets) or ""
        settingsDirty = true
    end

    -- Auto-class selection on first load (no user sets, default selectedSet)
    if next(settings.sets) == nil and settings.selectedSet == "" then
        local preset = findPresetForClass(myClass)
        if preset then
            settings.selectedSet = preset
            settingsDirty = true
            utils.output("Auto-selected preset '%s' based on class.", preset)
        end
    end

    if not delivery.navLoaded then
        utils.output("\ayMQ2Nav not loaded - navigation features disabled.")
    end

    if settings.allowMovement and not delivery.navLoaded then
        settings.allowMovement = false
        settingsDirty = true
    end

    if settingsDirty then
        utils.saveSettings(settings)
        settingsDirty = false
    end

    reactive.init({
        settings = settings,
        isArming = function() return isArming end,
        setIsArming = function(v) isArming = v end,
        aborted = function() return aborted end,
        setAborted = function(v) aborted = v end,
        stopRequested = function() return stopRequested end,
        armPet = armPet,
        getSet = getSet,
        setStatusText = function(v) statusText = v end,
        getLatestHistory = function() return armHistory[1] end,
        onWelcomeDone = function()
            if not settings.welcomeDone then
                settings.welcomeDone = true
                settingsDirty = true
                showWelcome = false
                utils.output("Welcome dismissed by another character.")
            end
        end,
    })

    if not settings.welcomeDone then
        showWelcome = true
    elseif settings.reactiveMode == "page" then
        showUI = false
        utils.output("Started in Page mode - UI hidden. Type /squire show to reopen.")
    end

    utils.output("v%s by \aoAlgar\ax (\a-tgithub.com/AlgarDude/Squire\ax)", version)
    utils.output("Use \ag/squire help\ax for a list of commands.")
end

-- Main

startup()

mq.imgui.init('Squire', renderUI)
mq.bind('/squire', commandHandler)

if settings.tellAccess ~= "disabled" then
    registerTellEvent()
end

utils.output("Running.")

while mq.TLO.MacroQuest.GameState() == 'INGAME' do
    mq.doevents()

    -- Detect persona class change
    if not isArming and me.Class.ShortName() ~= myClass then
        local oldTellAccess = settings.tellAccess
        myClass = me.Class.ShortName()
        settings = utils.loadSettings()
        reactive.updateSettings(settings)
        resolvePresets()
        if settings.tellAccess ~= oldTellAccess then
            if settings.tellAccess == "disabled" then
                unregisterTellEvent()
            elseif oldTellAccess == "disabled" then
                registerTellEvent()
            end
        end
        if not getSet(settings.selectedSet) then
            settings.selectedSet = findPresetForClass(myClass) or next(settings.sets) or ""
        end
        settingsDirty = true
    end

    if settingsDirty then
        utils.saveSettings(settings)
        settingsDirty = false
    end

    processQueue()
    reactive.tick()
    mq.delay(100)
end

utils.output("No longer in game, exiting.")
