--[[
    Squire - utils.lua
    Utility functions: polling, output, settings, inventory management
]]

local mq = require('mq')

local utils = {}

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
        items = {},
        trashItems = {},
    }
end

local function defaultSettings()
    return {
        debugMode = false,
        triggerWord = "armpet",
        selectedSet = "",
        tellAccess = "anyone",
        tellAllowlist = {},
        tellDenylist = {},
        allowMovement = false,
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
    for setName, set in pairs(settings.sets) do
        if type(set) == "table" then
            for i, entry in ipairs(set) do
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
        local containerSlots = packSlot.Item.Container()
        if containerSlots and containerSlots > 0 then
            for s = 1, containerSlots do
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
        if packSlot.Item.ID() and (not packSlot.Item.Container() or packSlot.Item.Container() == 0) then
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
            local container = packSlot.Item.Container()
            if container and container > 0 then
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
            local containerSlots = packSlot.Item.Container()
            if containerSlots and containerSlots > 0 then
                for s = 1, containerSlots do
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

    -- Pick up the item from the source slot
    mq.cmdf("/nomodkey /itemnotify pack%d leftmouseup", sourceSlot)
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

    utils.debugOutput("freeTopSlot: freed pack%d", sourceSlot)
    return sourceSlot
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
    if not mq.TLO.Cursor.ID() then
        return nil
    end
    utils.debugOutput("clearCursor: %s (ID: %d), needTopSlot=%s", mq.TLO.Cursor.Name() or "?", mq.TLO.Cursor.ID(), tostring(needTopSlot))

    if not needTopSlot then
        mq.cmd("/autoinventory")
        mq.delay(3000, function() return not mq.TLO.Cursor.ID() end)
        if mq.TLO.Cursor.ID() then
            utils.output("\arFailed to autoinventory cursor item.")
            return "abort"
        end
        return nil
    end

    -- Need a top-level slot free, so place cursor item into a bag sub-slot
    local destPack, destSubSlot = utils.findBagWithSpace()
    if not destPack then
        utils.output("\arCannot clear cursor: no bag has a free sub-slot.")
        return "abort"
    end

    mq.cmdf("/nomodkey /itemnotify in pack%d %d leftmouseup", destPack, destSubSlot)
    mq.delay(3000, function() return not mq.TLO.Cursor.ID() end)
    if mq.TLO.Cursor.ID() then
        utils.output("\arFailed to place cursor item into pack%d slot %d.", destPack, destSubSlot)
        return "abort"
    end

    return nil
end

return utils
