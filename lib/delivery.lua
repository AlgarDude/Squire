--[[
    Squire - delivery.lua
    Item delivery to pets via GiveWnd and navigation
]]

local mq = require('mq')
local utils = require('squire.lib.utils')
local casting = require('squire.lib.casting')

local delivery = {}

local giveWnd = mq.TLO.Window("GiveWnd")

-- Navigation

local startPosition = nil

delivery.navLoaded = mq.TLO.Plugin('MQ2Nav').IsLoaded()

local function distSqFromStart(y, x, z)
    if not startPosition then return 0 end
    local dy = y - startPosition.y
    local dx = x - startPosition.x
    local dz = z - startPosition.z
    return dy * dy + dx * dx + dz * dz
end

function delivery.navToPet(petSpawn)
    if not delivery.navLoaded then return false end
    if not petSpawn() or not petSpawn.ID() then return false end

    if not startPosition then
        startPosition = {
            y = mq.TLO.Me.Y(),
            x = mq.TLO.Me.X(),
            z = mq.TLO.Me.Z(),
        }
    end

    if distSqFromStart(petSpawn.Y(), petSpawn.X(), petSpawn.Z()) > 10000 then
        utils.output("\ayPet is beyond leash range (100 units from start). Skipping.")
        return false
    end

    local nav = mq.TLO.Navigation
    local navCmd = string.format("id %d dist=15", petSpawn.ID())
    if not nav.PathExists(navCmd)() then
        utils.output("\ayNo nav path to pet. Skipping.")
        return false
    end

    mq.cmdf("/nav %s", navCmd)
    mq.delay(1000, function() return nav.Active() end)

    mq.delay(15000, function()
        return not nav.Active() or (petSpawn.Distance3D() or 999) <= 20
    end)

    if nav.Active() then
        mq.cmd("/nav stop")
    end

    -- Wait for character to fully stop moving before casting
    mq.delay(2000, function() return not mq.TLO.Me.Moving() end)

    return (petSpawn.Distance3D() or 999) <= 20
end

function delivery.navToStart(allowMovement)
    if not startPosition then return end
    if not allowMovement then return end
    if not delivery.navLoaded then return end

    local nav = mq.TLO.Navigation
    local navCmd = string.format("locyxz %.2f %.2f %.2f", startPosition.y, startPosition.x, startPosition.z)
    if not nav.PathExists(navCmd)() then
        utils.output("\ayNo nav path back to start position.")
        return
    end

    mq.cmdf("/nav %s", navCmd)
    mq.delay(1000, function() return nav.Active() end)
    mq.delay(15000, function() return not nav.Active() end)

    if nav.Active() then
        mq.cmd("/nav stop")
    end
end

function delivery.clearStartPosition()
    startPosition = nil
end

-- GiveWnd Helpers

local function targetPet(petSpawn)
    petSpawn.DoTarget()
    mq.delay(1500, function() return mq.TLO.Target.ID() == petSpawn.ID() end)
    return mq.TLO.Target.ID() == petSpawn.ID()
end

local function handleRejections(givenItemIds)
    -- After Give click, cursor may have rejected items - loop until cursor clear
    local maxLoops = 8
    while mq.TLO.Cursor.ID() and maxLoops > 0 do
        maxLoops = maxLoops - 1
        local cursorId = mq.TLO.Cursor.ID()
        if givenItemIds[cursorId] then
            utils.debugOutput(" Destroying rejected item: %s (ID: %d)", mq.TLO.Cursor.Name() or "?", cursorId)
            mq.cmd("/destroy")
        else
            utils.output("\ayUnexpected item on cursor (ID: %d) after give - autoinventorying.", cursorId)
            mq.cmd("/autoinventory")
        end
        mq.delay(1500, function() return not mq.TLO.Cursor.ID() end)
    end
end

local function placeCursorItemInGiveWindow(petSpawn)
    -- First item opens GiveWnd, subsequent items fill the next slot
    if not giveWnd.Open() then
        mq.cmd("/nomodkey /click left target")
        mq.delay(3000, function() return giveWnd.Open() end)
        if not giveWnd.Open() then return false end
    else
        mq.cmd("/nomodkey /click left target")
        mq.delay(500)
    end
    return true
end

-- Batch Give (shared by cursor and bag methods)

local function batchGive(petSpawn, itemFuncs, abortFunc)
    -- itemFuncs = list of { id = number, getItem = function() -> bool }
    -- getItem puts the item on cursor, returns true on success
    -- Groups into batches of 4, gives each batch via GiveWnd
    local allSuccess = true

    for batchStart = 1, #itemFuncs, 4 do
        if abortFunc and abortFunc() then
            allSuccess = false
            break
        end

        local batchEnd = math.min(batchStart + 3, #itemFuncs)
        utils.debugOutput(" Batch %d-%d of %d", batchStart, batchEnd, #itemFuncs)
        local givenIds = {}
        local batchCount = 0

        for i = batchStart, batchEnd do
            if abortFunc and abortFunc() then
                allSuccess = false
                break
            end

            local itemFunc = itemFuncs[i]
            local ok = itemFunc.getItem()
            if ok and mq.TLO.Cursor.ID() ~= itemFunc.id then
                utils.output("\arWrong item on cursor (expected %d, got %d). Autoinventorying.", itemFunc.id, mq.TLO.Cursor.ID() or 0)
                mq.cmd("/autoinventory")
                mq.delay(1500, function() return not mq.TLO.Cursor.ID() end)
                ok = false
            end
            if ok and not placeCursorItemInGiveWindow(petSpawn) then
                utils.output("\arFailed to open GiveWnd. Autoinventorying cursor item.")
                mq.cmd("/autoinventory")
                mq.delay(1500, function() return not mq.TLO.Cursor.ID() end)
                ok = false
            end
            if ok then
                utils.debugOutput("Placed in trade: %s (ID: %d)", mq.TLO.Cursor.Name() or "?", itemFunc.id)
                givenIds[itemFunc.id] = true
                batchCount = batchCount + 1
            else
                allSuccess = false
            end
        end

        -- Click Give if we placed any items
        if batchCount > 0 and giveWnd.Open() then
            utils.debugOutput(" Clicking Give (%d items in batch)", batchCount)
            mq.cmd("/notify GiveWnd GVW_Give_Button leftmouseup")
            mq.delay(5000, function() return not giveWnd.Open() end)
            if giveWnd.Open() then
                utils.output("\arGiveWnd did not close after clicking Give.")
                allSuccess = false
            end
            handleRejections(givenIds)
        end
    end

    return allSuccess
end

-- Direct Delivery

function delivery.deliverDirect(entry, petSpawn, abortFunc)
    utils.debugOutput(" deliverDirect: %s", entry.name)
    if not targetPet(petSpawn) then
        utils.output("\arFailed to target pet for direct delivery of %s.", entry.name)
        return false
    end

    if not casting.useSource(entry, abortFunc) then
        utils.output("\arFailed to use source: %s", entry.name)
        return false
    end

    return true
end

-- Cursor Delivery

function delivery.deliverCursor(entry, petSpawn, abortFunc)
    utils.debugOutput(" deliverCursor: %s (%d items)", entry.name, #entry.items)
    if not targetPet(petSpawn) then
        utils.output("\arFailed to target pet for cursor delivery of %s.", entry.name)
        return false
    end

    -- Build item functions: each cast produces one item on cursor
    local itemFuncs = {}
    for _, item in ipairs(entry.items) do
        table.insert(itemFuncs, {
            id = item.id,
            getItem = function()
                if not casting.useSource(entry, abortFunc) then
                    utils.output("\arFailed to use source: %s", entry.name)
                    return false
                end
                mq.delay(5000, function() return (mq.TLO.Cursor.ID() or 0) > 0 end)
                if not mq.TLO.Cursor.ID() then
                    utils.output("\arNo item appeared on cursor after %s.", entry.name)
                    return false
                end
                return true
            end,
        })
    end

    return batchGive(petSpawn, itemFuncs, abortFunc)
end

-- Bag Delivery

local function findItemInBag(packSlot, itemId)
    local container = mq.TLO.InvSlot("pack" .. packSlot).Item.Container()
    if not container or container == 0 then
        return nil
    end

    for s = 1, container do
        if mq.TLO.InvSlot("pack" .. packSlot).Item.Item(s).ID() == itemId then
            return s
        end
    end
    return nil
end

function delivery.deliverBag(entry, petSpawn, freeSlot, abortFunc)
    utils.debugOutput(" deliverBag: %s (%d items, freeSlot=pack%d)", entry.name, #entry.items, freeSlot)
    -- Cast once to produce the bag
    if not casting.useSource(entry, abortFunc) then
        utils.output("\arFailed to use source: %s", entry.name)
        return false
    end

    -- Wait for bag on cursor
    mq.delay(5000, function() return (mq.TLO.Cursor.ID() or 0) > 0 end)
    if not mq.TLO.Cursor.ID() then
        utils.output("\arNo bag appeared on cursor after %s.", entry.name)
        return false
    end

    -- Place bag into free top slot
    mq.cmdf("/nomodkey /itemnotify pack%d leftmouseup", freeSlot)
    mq.delay(1500, function() return not mq.TLO.Cursor.ID() end)
    if mq.TLO.Cursor.ID() then
        utils.output("\arFailed to place bag into pack%d.", freeSlot)
        return false
    end

    if not mq.TLO.InvSlot("pack" .. freeSlot).Item.ID() then
        utils.output("\arBag not found in pack%d after placement.", freeSlot)
        return false
    end

    utils.debugOutput(" Bag placed in pack%d: %s (ID: %d)", freeSlot,
        mq.TLO.InvSlot("pack" .. freeSlot).Item.Name() or "?",
        mq.TLO.InvSlot("pack" .. freeSlot).Item.ID())

    -- Let inventory settle before accessing bag contents (TLO reports data before client is ready)
    local settleStart = mq.gettime()
    mq.delay(1000, function()
        return mq.gettime() - settleStart >= 300
            and mq.TLO.InvSlot("pack" .. freeSlot).Item.Item(1).ID()
    end)
    utils.debugOutput(" Inventory settled after %dms", mq.gettime() - settleStart)

    -- Target pet for giving
    if not targetPet(petSpawn) then
        utils.output("\arFailed to target pet for bag delivery of %s.", entry.name)
        delivery.cleanupBag(entry, freeSlot)
        return false
    end

    -- Build item functions: each picks up from bag sub-slot
    local itemFuncs = {}
    for _, item in ipairs(entry.items) do
        table.insert(itemFuncs, {
            id = item.id,
            getItem = function()
                local subSlot = findItemInBag(freeSlot, item.id)
                if not subSlot then
                    utils.output("\arCould not find item ID %d in pack%d.", item.id, freeSlot)
                    return false
                end
                utils.debugOutput(" Picking up %s (ID: %d) from pack%d slot %d", item.name or "?", item.id, freeSlot, subSlot)
                mq.cmdf("/nomodkey /itemnotify in pack%d %d leftmouseup", freeSlot, subSlot)
                mq.delay(1500, function() return (mq.TLO.Cursor.ID() or 0) > 0 end)
                if not mq.TLO.Cursor.ID() then
                    utils.output("\arFailed to pick up item from pack%d slot %d.", freeSlot, subSlot)
                    return false
                end
                return true
            end,
        })
    end

    local success = batchGive(petSpawn, itemFuncs, abortFunc)

    delivery.cleanupBag(entry, freeSlot)

    return success
end

-- Bag Cleanup

function delivery.cleanupBag(entry, freeSlot)
    local bagId = mq.TLO.InvSlot("pack" .. freeSlot).Item.ID()
    if not bagId then
        utils.debugOutput(" cleanupBag: pack%d already empty, nothing to clean", freeSlot)
        return
    end
    utils.debugOutput(" cleanupBag: pack%d (bag ID: %d)", freeSlot, bagId)

    -- Build trash ID lookup from entry
    local trashIds = {}
    if entry.trashItems then
        for _, trash in ipairs(entry.trashItems) do
            trashIds[trash.id] = true
        end
    end
    -- Also treat all wanted item IDs as trash during cleanup (leftovers the pet rejected)
    if entry.items then
        for _, item in ipairs(entry.items) do
            trashIds[item.id] = true
        end
    end

    local container = mq.TLO.InvSlot("pack" .. freeSlot).Item.Container()
    if not container or container == 0 then
        -- Not a container, just destroy it
        mq.cmdf("/nomodkey /itemnotify pack%d leftmouseup", freeSlot)
        mq.delay(1500, function() return (mq.TLO.Cursor.ID() or 0) > 0 end)
        if mq.TLO.Cursor.ID() then
            if mq.TLO.Cursor.ID() == bagId then
                mq.cmd("/destroy")
                mq.delay(1500, function() return not mq.TLO.Cursor.ID() end)
            else
                utils.output("\arUnexpected cursor item during cleanup (expected bag ID %d, got %d).", bagId, mq.TLO.Cursor.ID())
            end
        end
        return
    end

    -- Handle each remaining sub-item
    for s = 1, container do
        local subItemId = mq.TLO.InvSlot("pack" .. freeSlot).Item.Item(s).ID()
        if subItemId then
            mq.cmdf("/nomodkey /itemnotify in pack%d %d leftmouseup", freeSlot, s)
            mq.delay(1500, function() return (mq.TLO.Cursor.ID() or 0) > 0 end)
            if not mq.TLO.Cursor.ID() then
                utils.output("\arFailed to pick up sub-item from pack%d slot %d during cleanup.", freeSlot, s)
            else
                if trashIds[mq.TLO.Cursor.ID()] then
                    utils.debugOutput("Destroying cleanup item: %s (ID: %d)", mq.TLO.Cursor.Name() or "?", mq.TLO.Cursor.ID())
                    mq.cmd("/destroy")
                    mq.delay(1500, function() return not mq.TLO.Cursor.ID() end)
                else
                    utils.output("\ayUnexpected item in bag (ID: %d) - autoinventorying.", mq.TLO.Cursor.ID())
                    mq.cmd("/autoinventory")
                    mq.delay(1500, function() return not mq.TLO.Cursor.ID() end)
                end
            end
        end
    end

    -- Destroy the bag itself last to free the top-level slot
    mq.cmdf("/nomodkey /itemnotify pack%d leftmouseup", freeSlot)
    mq.delay(1500, function() return (mq.TLO.Cursor.ID() or 0) > 0 end)
    if not mq.TLO.Cursor.ID() then
        utils.output("\arFailed to pick up bag from pack%d during cleanup.", freeSlot)
        return
    end

    if mq.TLO.Cursor.ID() == bagId then
        utils.debugOutput("Destroying bag: %s (ID: %d)", mq.TLO.Cursor.Name() or "?", bagId)
        mq.cmd("/destroy")
        mq.delay(1500, function() return not mq.TLO.Cursor.ID() end)
    else
        utils.output("\arUnexpected cursor item when destroying bag (expected ID %d, got %d). Not destroying.", bagId, mq.TLO.Cursor.ID())
    end
end

return delivery
