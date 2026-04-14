--[[
    Squire - utils.lua
    Utility functions: polling, output, settings, inventory management
]]

local mq = require('mq')

local utils = {}

local me = mq.TLO.Me

local displacedItem = nil
local lastSummonedItemId = nil

-- Polling

function utils.waitFor(conditionFunc, timeoutMs, checkIntervalMs, abortFunc)
    checkIntervalMs = checkIntervalMs or 100
    local elapsed = 0
    while elapsed < timeoutMs do
        if conditionFunc() then
            return true
        end
        if abortFunc and abortFunc() then
            return false
        end
        mq.delay(checkIntervalMs)
        elapsed = elapsed + checkIntervalMs
    end
    return false
end

-- Output

utils.debugMode = false

function utils.output(msg, ...)
    printf("\a-t[Squire]\aw " .. msg .. "\ax", ...)
end

function utils.debugOutput(msg, ...)
    if utils.debugMode then
        local t = mq.gettime()
        printf("\a-t[Squire] \a-y[DEBUG] \a-g[%.3f]\aw " .. msg .. "\ax", t / 1000, ...)
    end
end

function utils.announce(channel, msg, ...)
    if channel == "disabled" then return end
    local text = string.format("[Squire] " .. msg, ...)
    if channel == "dannet" then
        mq.cmdf("/dgt zone_%s_%s %s",
            (mq.TLO.EverQuest.Server() or ""):gsub(" ", ""),
            mq.TLO.Zone.ShortName() or "unknown",
            text)
    elseif channel == "e3bcs" then
        mq.cmdf("/e3bcza %s", text)
    elseif channel == "raid" then
        mq.cmdf("/rsay %s", text)
    elseif channel == "group" then
        mq.cmdf("/g %s", text)
    end
end

-- isFinished gates only "Finished arming." so reactive can suppress it when the queue has remaining entries.
function utils.announceQueueResult(channel, wasStopped, wasAborted, pauseReason, isFinished)
    if wasStopped then
        utils.announce(channel, "Arming stopped.")
    elseif wasAborted then
        utils.announce(channel, "Arming halted - attention needed.")
    elseif pauseReason then
        utils.announce(channel, "Arming paused - %s.", pauseReason)
    elseif isFinished then
        utils.announce(channel, "Finished arming.")
    end
end

-- Settings

local characterName = mq.TLO.Me.Name()
local serverName = mq.TLO.EverQuest.Server():gsub("%s+", "")

function utils.getSettingsPath()
    return mq.configDir .. "/Squire/" .. characterName .. "_" .. serverName .. "_" .. mq.TLO.Me.Class.ShortName() .. ".lua"
end

function utils.defaultSourceEntry()
    return {
        enabled = false,
        name = "",
        type = "spell",
        method = "cursor",
        clicky = false,
        clickyItem = nil,
        items = {},
        trashItems = {},
    }
end

local function defaultSettings()
    return {
        debugMode = false,
        triggerWord = "hit me bb",
        selectedSet = "",
        tellAccess = "disabled",
        tellAllowlist = {},
        tellDenylist = {},
        tellReplies = true,
        allowMovement = false,
        alwaysRequestArming = false,
        navDistance = 200,
        preQueueCommand = "/rgl pause",
        postQueueCommand = "/rgl unpause",
        announceArming = "disabled",
        reactiveMode = "page",
        welcomeDone = false,
        sets = {},
    }
end

function utils.saveSettings(settings)
    mq.pickle(utils.getSettingsPath(), settings)
end

function utils.loadSettings()
    local defaults = defaultSettings()
    local configData, err = loadfile(utils.getSettingsPath())
    if err or not configData then
        utils.saveSettings(defaults)
        return defaults
    end

    local settings = configData()

    -- Merge top-level keys from defaults
    for key, value in pairs(defaults) do
        if settings[key] == nil then
            settings[key] = value
        end
    end

    -- Merge defaults into each source entry
    for _, set in pairs(settings.sets) do
        if type(set) == "table" then
            for _, entry in ipairs(set) do
                local def = utils.defaultSourceEntry()
                for key, value in pairs(def) do
                    if entry[key] == nil then
                        entry[key] = value
                    end
                end
            end
        end
    end

    return settings
end

-- Spawn Helpers

function utils.isFamiliar(spawn)
    return (spawn.DisplayName() or ""):lower():find("familiar") ~= nil
end

-- Gating: hard blocks (external interruptions that should abort mid-arm)

local function hasXTargetHaters()
    local xtCount = me.XTarget() or 0
    for i = 1, xtCount do
        local xt = me.XTarget(i)
        if xt and (xt.ID() or 0) > 0 and not xt.Dead()
            and (xt.Type() or "Corpse") ~= "Corpse"
            and (xt.Aggressive() or (xt.TargetType() or ""):lower() == "auto hater") then
            return true
        end
    end
    return false
end

function utils.getHardBlockReason()
    if me.CombatState() == "COMBAT" then return "in combat" end
    if hasXTargetHaters() then return "xtarget haters" end
    if me.Dead() then return "dead" end
    if me.Feigning() then return "feigning" end
    if mq.TLO.MacroQuest.GameState() ~= 'INGAME' then return "not in game" end
    if mq.TLO.Window("TradeWnd").Open() then return "trade window open" end
    if mq.TLO.Window("LootWnd").Open() then return "loot window open" end
    if mq.TLO.Window("MerchantWnd").Open() then return "merchant open" end
    if mq.TLO.Window("BigBankWnd").Open() then return "bank open" end
    return nil
end

function utils.shouldAbortArming()
    return utils.getHardBlockReason() ~= nil
end

-- Cursor Helpers

function utils.autoinventory()
    mq.cmd("/autoinventory")
    mq.delay(1500, function() return not mq.TLO.Cursor.ID() end)
end

function utils.destroyCursor()
    mq.cmd("/destroy")
    mq.delay(1500, function() return not mq.TLO.Cursor.ID() end)
end

-- Inventory

function utils.findFreeTopSlot()
    for i = 1, mq.TLO.Me.NumBagSlots() do
        local packSlot = mq.TLO.InvSlot("pack" .. i)
        if not packSlot.Item.ID() then
            return i
        end
    end
    return nil
end

function utils.findBagWithSpace()
    for i = 1, mq.TLO.Me.NumBagSlots() do
        local packSlot = mq.TLO.InvSlot("pack" .. i)
        if (packSlot.Item.Container() or 0) > 0 then
            for s = 1, packSlot.Item.Container() do
                if not packSlot.Item.Item(s).ID() then
                    return i, s
                end
            end
        end
    end
    return nil
end

function utils.freeTopSlot()
    -- First try: find a non-container top-level item to move into a bag
    local sourceSlot
    for i = 1, mq.TLO.Me.NumBagSlots() do
        local packSlot = mq.TLO.InvSlot("pack" .. i)
        if packSlot.Item.ID() and (packSlot.Item.Container() or 0) == 0 then
            sourceSlot = i
            utils.debugOutput("freeTopSlot: found non-container item in pack%d: %s", i, packSlot.Item.Name() or "?")
            break
        end
    end

    -- Second try: find an empty container to nest into another bag with space
    if not sourceSlot then
        utils.debugOutput("freeTopSlot: no non-container items, looking for empty containers")
        for i = 1, mq.TLO.Me.NumBagSlots() do
            local packSlot = mq.TLO.InvSlot("pack" .. i)
            local container = packSlot.Item.Container() or 0
            if container > 0 then
                local isEmpty = true
                for s = 1, container do
                    if packSlot.Item.Item(s).ID() then
                        isEmpty = false
                        break
                    end
                end
                if isEmpty then
                    sourceSlot = i
                    utils.debugOutput("freeTopSlot: found empty container in pack%d: %s (%d slots)", i, packSlot.Item.Name() or "?", container)
                    break
                end
            end
        end
    end

    if not sourceSlot then
        utils.output("\arNo movable top-level item or empty bag found. Cannot free a slot.")
        return "abort"
    end

    -- Find a bag with space BEFORE picking anything up (exclude source slot)
    local destPack, destSubSlot
    for i = 1, mq.TLO.Me.NumBagSlots() do
        if i ~= sourceSlot then
            local packSlot = mq.TLO.InvSlot("pack" .. i)
            if (packSlot.Item.Container() or 0) > 0 then
                for s = 1, packSlot.Item.Container() do
                    if not packSlot.Item.Item(s).ID() then
                        destPack = i
                        destSubSlot = s
                        break
                    end
                end
                if destPack then break end
            end
        end
    end
    if not destPack then
        utils.output("\arNo bag has a free sub-slot. Cannot free a top-level slot.")
        return "abort"
    end

    utils.debugOutput("freeTopSlot: moving pack%d -> pack%d slot %d", sourceSlot, destPack, destSubSlot)

    -- Pick up the item from the source slot (shiftkey grabs the full stack)
    mq.cmdf("/nomodkey /shiftkey /itemnotify pack%d leftmouseup", sourceSlot)
    mq.delay(3000, function() return (mq.TLO.Cursor.ID() or 0) > 0 end)
    if not mq.TLO.Cursor.ID() then
        utils.output("\arFailed to pick up item from pack%d.", sourceSlot)
        return "abort"
    end

    -- Place into destination bag sub-slot
    mq.cmdf("/nomodkey /itemnotify in pack%d %d leftmouseup", destPack, destSubSlot)
    mq.delay(3000, function() return not mq.TLO.Cursor.ID() end)
    if mq.TLO.Cursor.ID() then
        utils.output("\arFailed to place item into pack%d slot %d. Cursor stuck.", destPack, destSubSlot)
        return "abort"
    end

    displacedItem = { sourceSlot = sourceSlot, destPack = destPack, destSubSlot = destSubSlot, }
    utils.debugOutput("freeTopSlot: freed pack%d", sourceSlot)
    return sourceSlot
end

function utils.restoreDisplacedItem()
    if not displacedItem then return end
    if mq.TLO.Cursor.ID() then
        utils.debugOutput("restoreDisplacedItem: cursor occupied, skipping")
        return
    end

    local info = displacedItem
    displacedItem = nil

    -- Verify the item is still where we put it
    local destSlot = mq.TLO.InvSlot("pack" .. info.destPack)
    if not destSlot.Item.Item(info.destSubSlot).ID() then
        utils.debugOutput("restoreDisplacedItem: nothing in pack%d slot %d, skipping", info.destPack, info.destSubSlot)
        return
    end

    -- Verify the original slot is free
    if mq.TLO.InvSlot("pack" .. info.sourceSlot).Item.ID() then
        utils.debugOutput("restoreDisplacedItem: pack%d is occupied, skipping", info.sourceSlot)
        return
    end

    utils.debugOutput("restoreDisplacedItem: moving pack%d slot %d -> pack%d",
        info.destPack, info.destSubSlot, info.sourceSlot)

    -- Pick up from destination sub-slot
    mq.cmdf("/nomodkey /shiftkey /itemnotify in pack%d %d leftmouseup", info.destPack, info.destSubSlot)
    mq.delay(3000, function() return (mq.TLO.Cursor.ID() or 0) > 0 end)
    if not mq.TLO.Cursor.ID() then
        utils.debugOutput("restoreDisplacedItem: failed to pick up item, aborting restore")
        return
    end

    -- Place back into original top-level slot
    mq.cmdf("/nomodkey /itemnotify pack%d leftmouseup", info.sourceSlot)
    mq.delay(3000, function() return not mq.TLO.Cursor.ID() end)
    if mq.TLO.Cursor.ID() then
        utils.debugOutput("restoreDisplacedItem: failed to place item, autoinventorying")
        mq.cmd("/autoinventory")
        mq.delay(3000, function() return not mq.TLO.Cursor.ID() end)
        return
    end

    utils.debugOutput("restoreDisplacedItem: restored item to pack%d", info.sourceSlot)
end

function utils.setLastSummonedItemId(id)
    lastSummonedItemId = id
end

function utils.getLastSummonedItemId()
    return lastSummonedItemId
end

function utils.clearLastSummonedItemId()
    lastSummonedItemId = nil
end

function utils.ensureFreeTopSlot()
    local freeSlot = utils.findFreeTopSlot()
    if freeSlot then
        utils.debugOutput("ensureFreeTopSlot: pack%d already free", freeSlot)
        return freeSlot
    end
    utils.debugOutput("ensureFreeTopSlot: no free top slot, attempting to free one")
    return utils.freeTopSlot()
end

function utils.clearCursor(needTopSlot)
    if not mq.TLO.Cursor.ID() then return end
    local cursorName = mq.TLO.Cursor.Name() or "unknown item"
    utils.debugOutput("clearCursor: %s (ID: %d), needTopSlot=%s", cursorName, mq.TLO.Cursor.ID(), tostring(needTopSlot))

    if not needTopSlot then
        mq.cmd("/autoinventory")
        mq.delay(3000, function() return not mq.TLO.Cursor.ID() end)
        if mq.TLO.Cursor.ID() then
            utils.output("\arFailed to autoinventory cursor item.")
            return "abort", string.format("failed to autoinventory '%s'", cursorName)
        end
        return nil
    end

    -- Need a top-level slot free, so place cursor item into a bag sub-slot
    local destPack, destSubSlot = utils.findBagWithSpace()
    if not destPack then
        utils.output("\arCannot clear cursor: no bag has a free sub-slot.")
        return "abort", string.format("'%s' on cursor, no free bag slot to place it", cursorName)
    end

    mq.cmdf("/nomodkey /itemnotify in pack%d %d leftmouseup", destPack, destSubSlot)
    mq.delay(3000, function() return not mq.TLO.Cursor.ID() end)
    if mq.TLO.Cursor.ID() then
        utils.output("\arFailed to place cursor item into pack%d slot %d.", destPack, destSubSlot)
        return "abort", string.format("failed to place '%s' into pack%d slot %d", cursorName, destPack, destSubSlot)
    end

    return nil
end

return utils
