--[[
    Squire - reactive.lua
    Reactive arming mode: page pet detection + squire queue processing via actor IPC
]]

local mq = require('mq')
local actors = require('actors')
local Set = require('mq.Set')
local utils = require('squire.lib.utils')
local casting = require('squire.lib.casting')
local delivery = require('squire.lib.delivery')

local reactive = {}

-- States

local me = mq.TLO.Me
local myName = me.DisplayName()
local myServer = mq.TLO.EverQuest.Server() or ""
local deps = {}
local actor = nil

-- Page State

local lastPetId = me.Pet.ID() or 0
local reBroadcastTimer = nil
local lastWeaponPollTime = 0
local awaitingArm = false
local awaitingArmTime = 0

-- Squire State

local reactiveQueue = {}
local reactiveQueuedNames = Set.new({})
local currentlyArming = nil
local preFired = false
local recentlyArmed = {}
local lastArmedPetId = {}
local lastZoneId = mq.TLO.Zone.ID() or 0
local savedGems = nil

-- Helpers

local function broadcast(content)
    if actor then
        content.server = myServer
        content.zoneId = mq.TLO.Zone.ID() or 0
        actor:send(content)
    end
end

local function clearQueue()
    reactiveQueue = {}
    reactiveQueuedNames = Set.new({})
end

local function removeFromReactiveQueue(playerName)
    if not playerName then return end
    local lower = playerName:lower()
    for i = #reactiveQueue, 1, -1 do
        local entry = reactiveQueue[i]
        if entry and entry.playerName and entry.playerName:lower() == lower then
            table.remove(reactiveQueue, i)
        end
    end
    reactiveQueuedNames:remove(lower)
end

-- Gating (Reactive Mode Only)

-- Soft blocks: temporary states that prevent starting a new pet but don't abort mid-arm
local function getBlockReason()
    return utils.getHardBlockReason()
        or (me.Casting.ID() and "casting")
        or (me.Moving() and "moving")
        or (mq.TLO.Cursor.ID() and "item on cursor")
        or (mq.TLO.Window("SpellBookWnd").Open() and "spellbook open")
        or (mq.TLO.Window("GiveWnd").Open() and "give window open")
        or nil
end

local function isSafeToArm()
    if deps.isArming() then return false end
    if deps.aborted() then return false end
    return getBlockReason() == nil
end

-- Actor Message Handler

local function handleMessage(message)
    local cmd = message.content and message.content.command
    if not cmd then return end

    local content = message.content
    if content.server ~= myServer then return end
    if content.zoneId ~= (mq.TLO.Zone.ID() or 0) then return end

    -- Global commands (handled regardless of mode)
    if cmd == "welcome_done" and content.senderName ~= myName then
        if deps.onWelcomeDone then deps.onWelcomeDone() end
        return
    end

    local mode = deps.settings.reactiveMode
    if mode == "off" then return end

    -- Squire role: arm, claim, release, done
    if mode == "squire" or mode == "both" then
        if cmd == "arm" then
            local lower = content.playerName and content.playerName:lower()
            local cooldown = lower and recentlyArmed[lower]
            local newPet = content.petId and lower and lastArmedPetId[lower] ~= content.petId
            if cooldown and mq.gettime() < cooldown and not newPet then
                utils.debugOutput("Reactive: ignoring arm for %s (cooldown)", content.playerName)
            elseif lower and not reactiveQueuedNames:contains(lower)
                and (not currentlyArming or currentlyArming:lower() ~= lower) then
                if cooldown then recentlyArmed[lower] = nil end
                reactiveQueuedNames:add(lower)
                table.insert(reactiveQueue, { playerName = content.playerName, petCombat = content.petCombat or false, })
                utils.debugOutput("Reactive: queued %s for arming", content.playerName)
            end
        elseif cmd == "claim" and content.squireName ~= myName then
            removeFromReactiveQueue(content.playerName)
        elseif cmd == "release" and content.squireName ~= myName then
            local lower = content.playerName and content.playerName:lower()
            if lower and not reactiveQueuedNames:contains(lower) then
                reactiveQueuedNames:add(lower)
                table.insert(reactiveQueue, { playerName = content.playerName, petCombat = content.petCombat or false, })
                utils.debugOutput("Reactive: %s released %s, re-queued", content.squireName, content.playerName)
            end
        elseif cmd == "done" and content.squireName ~= myName then
            removeFromReactiveQueue(content.playerName)
        end
    end

    -- Page role: done, aborted (only for own pet)
    if mode == "page" or mode == "both" then
        if content.playerName and content.playerName:lower() == myName:lower() then
            if cmd == "done" and content.squireName ~= myName then
                reBroadcastTimer = nil
                lastWeaponPollTime = mq.gettime()
                awaitingArm = false
                local r = content.results or {}
                utils.output("Pet armed (%d/%d passed).", r.passed or 0, r.total or 0)
            elseif cmd == "aborted" and content.squireName ~= myName then
                awaitingArm = false
                reBroadcastTimer = mq.gettime() + 5000
                utils.output("Pet arming interrupted - will retry.")
            end
        end
    end
end

-- Page Logic

local function pollPetId()
    local currentPetId = me.Pet.ID() or 0

    if lastPetId > 0 and currentPetId == 0 then
        awaitingArm = false
    elseif lastPetId == 0 and currentPetId > 0 then
        if not utils.isFamiliar(me.Pet) then
            if not awaitingArm and ((me.Pet.Primary() or 0) == 0 or (me.Pet.Secondary() or 0) == 0 or deps.settings.alwaysRequestArming) then
                utils.output("Pet summoned - requesting arming.")
                broadcast({ command = 'arm', playerName = myName, petId = currentPetId, petCombat = me.Pet.Combat() or false, })
                awaitingArm = true
                awaitingArmTime = mq.gettime()
            end
        end
    end

    lastPetId = currentPetId
end

local function pollPetWeapons()
    local now = mq.gettime()
    if now - lastWeaponPollTime < 10000 then return end
    lastWeaponPollTime = now

    if (me.Pet.ID() or 0) == 0 then return end
    if utils.isFamiliar(me.Pet) then return end
    if awaitingArm then
        if now - awaitingArmTime > 60000 then
            utils.debugOutput("Reactive: arm request timed out, retrying")
            awaitingArm = false
        else
            return
        end
    end
    if (me.Pet.Primary() or 0) == 0 or (me.Pet.Secondary() or 0) == 0 then
        broadcast({ command = 'arm', playerName = myName, petId = me.Pet.ID(), petCombat = me.Pet.Combat() or false, })
        awaitingArm = true
        awaitingArmTime = now
    end
end

local function checkReBroadcastTimer()
    if not reBroadcastTimer then return end
    if mq.gettime() >= reBroadcastTimer then
        reBroadcastTimer = nil
        if (me.Pet.ID() or 0) > 0 then
            broadcast({ command = 'arm', playerName = myName, petId = me.Pet.ID(), petCombat = me.Pet.Combat() or false, })
            awaitingArm = true
            awaitingArmTime = mq.gettime()
        end
    end
end

-- Squire Logic

local function processReactiveQueue()
    if #reactiveQueue == 0 then return end
    if not isSafeToArm() then return end
    if not deps.getSet(deps.settings.selectedSet) then return end

    deps.setIsArming(true)
    if not savedGems then
        savedGems = casting.saveCurrentGems()
    end
    local haltReason = nil
    local pauseReason = nil

    local processed = 0

    while #reactiveQueue > 0 do
        if deps.stopRequested() or deps.aborted() then break end

        local currentMode = deps.settings.reactiveMode
        if currentMode ~= "squire" and currentMode ~= "both" then
            clearQueue()
            break
        end

        if getBlockReason() then break end

        local entry = reactiveQueue[1]
        if not entry then break end
        currentlyArming = entry.playerName

        broadcast({ command = 'claim', playerName = entry.playerName, squireName = myName, })

        table.remove(reactiveQueue, 1)
        reactiveQueuedNames:remove(entry.playerName:lower())
        processed = processed + 1
        deps.setStatusText(string.format("Arming %s's pet (reactive %d/%d)...",
            entry.playerName, processed, processed + #reactiveQueue))

        -- Pre-check: skip if pet missing/unreachable before firing pre-command
        local petSpawn = mq.TLO.Spawn("pc =" .. entry.playerName).Pet
        if (petSpawn.ID() or 0) == 0
            or utils.isFamiliar(petSpawn)
            or (petSpawn.Distance3D() or 999) > 100 then
            currentlyArming = nil
            broadcast({ command = 'done', playerName = entry.playerName, squireName = myName, })
            recentlyArmed[entry.playerName:lower()] = mq.gettime() + 5000
        else
            if not preFired then
                if deps.settings.preQueueCommand ~= "" then
                    mq.cmdf("%s", deps.settings.preQueueCommand)
                end
                utils.announce(deps.settings.announceArming, "Arming pets - please hold.")
                preFired = true
            end

            local abortFired = false
            local abortCheck = function()
                abortFired = abortFired or utils.shouldAbortArming()
                return abortFired
            end

            local result, status = deps.armPet(entry.playerName, nil, false, abortCheck, entry.petCombat)

            if status == "skipped" and not abortFired then
                currentlyArming = nil
                broadcast({ command = 'done', playerName = entry.playerName, squireName = myName, })
                recentlyArmed[entry.playerName:lower()] = mq.gettime() + 5000
            elseif not result then
                -- Inventory/preparation error - status has the reason from armPet
                haltReason = status or "unknown error"
                deps.setAborted(true)
                utils.output("\arHALTED while arming %s's pet: %s", entry.playerName, haltReason)
                mq.cmdf("/dgt [Squire] %s HALTED arming %s's pet: %s - /squire reset to resume", myName, entry.playerName, haltReason)
                broadcast({ command = 'release', playerName = entry.playerName, squireName = myName, petCombat = entry.petCombat, })
                broadcast({ command = 'aborted', playerName = entry.playerName, squireName = myName, reason = 'inventory', })
                currentlyArming = nil
                break
            elseif status == "pet_unavailable" or status == "aborted" or abortFired or deps.stopRequested() then
                -- Mid-pet environmental abort, pet unavailable, or user stop
                local reason = 'stopped'
                if abortFired then
                    reason = 'environment'
                    pauseReason = utils.getHardBlockReason() or "environmental block"
                elseif status == "pet_unavailable" then
                    reason = 'pet_unavailable'
                end
                broadcast({ command = 'release', playerName = entry.playerName, squireName = myName, petCombat = entry.petCombat, })
                broadcast({
                    command = 'aborted',
                    playerName = entry.playerName,
                    squireName = myName,
                    reason = reason,
                })
                currentlyArming = nil
                break
            else
                -- Success
                local doneMsg = { command = 'done', playerName = entry.playerName, squireName = myName, }
                local hist = deps.getLatestHistory()
                if hist and hist.playerName == entry.playerName and hist.total then
                    doneMsg.results = { passed = hist.passed, failed = #(hist.failed or {}), total = hist.total, }
                end
                broadcast(doneMsg)
                recentlyArmed[entry.playerName:lower()] = mq.gettime() + 5000
                local armedPet = mq.TLO.Spawn("pc =" .. entry.playerName).Pet
                if armedPet() then
                    lastArmedPetId[entry.playerName:lower()] = armedPet.ID()
                end

                -- Squire + Page local shortcut for self-arm
                if (currentMode == "page" or currentMode == "both") and entry.playerName:lower() == myName:lower() then
                    reBroadcastTimer = nil
                    lastWeaponPollTime = mq.gettime()
                    awaitingArm = false
                    if hist and hist.total then
                        utils.output("Pet armed (%d/%d passed).", hist.passed, hist.total)
                    end
                end

                currentlyArming = nil
            end
        end
    end

    -- Capture state before cleanup -- external events (reset button, /squire reset) can
    -- mutate stopRequested/aborted during mq.delay calls in the cleanup code below.
    local wasStopped = deps.stopRequested()
    local wasAborted = deps.aborted()
    local canCleanup = not wasStopped

    -- Cursor safety net: destroy summoned junk, autoinventory anything else
    if canCleanup and mq.TLO.Cursor.ID() then
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
            local reason = string.format("'%s' stuck on cursor after cleanup", cursorName)
            haltReason = reason
            utils.output("\arHALTED: %s", reason)
            mq.cmdf("/dgt [Squire] %s HALTED: %s - /squire reset to resume", myName, reason)
            deps.setAborted(true)
            wasAborted = true
        end
    end

    -- isTerminal computed after cursor cleanup (cursor-stuck sets wasAborted)
    local isTerminal = #reactiveQueue == 0 or wasStopped or wasAborted

    -- Restore/nav only on terminal exits to avoid churn on temporary blocks
    if canCleanup and isTerminal then
        if not mq.TLO.Cursor.ID() then
            utils.restoreDisplacedItem()
        end

        if savedGems then
            casting.restoreSpells(savedGems, function() return deps.stopRequested() end)
        end

        delivery.navToStart(deps.settings.allowMovement)
    end

    -- Pre/post commands must always pair (e.g., /rgl pause must always get /rgl unpause)
    if preFired then
        if deps.settings.postQueueCommand ~= "" then
            mq.cmdf("%s", deps.settings.postQueueCommand)
        end
        utils.announceQueueResult(deps.settings.announceArming, wasStopped, wasAborted, pauseReason, isTerminal)
        preFired = false
    end

    -- Terminal exits: clear persistent state.
    -- Temporary blocks (queue still has items): preserve state so next tick resumes cleanly.
    if isTerminal then
        savedGems = nil
        utils.clearLastSummonedItemId()
        delivery.clearStartPosition()
    end

    deps.setIsArming(false)

    if wasAborted then
        if wasStopped then
            deps.setStatusText("HALTED - user stopped")
        else
            deps.setStatusText(string.format("HALTED - %s", haltReason or "unknown error"))
        end
    elseif pauseReason then
        deps.setStatusText(string.format("HALTED - %s", pauseReason))
    else
        deps.setStatusText("Idle")
    end
end

-- Public API

function reactive.init(d)
    deps = d
    actor = actors.register('squire', handleMessage)
end

function reactive.tick()
    local mode = deps.settings.reactiveMode
    if mode == "off" then return end

    -- Zone change: clear abort state and flush queue, let pages re-request
    local currentZoneId = mq.TLO.Zone.ID() or 0
    if currentZoneId ~= lastZoneId then
        lastZoneId = currentZoneId
        if #reactiveQueue > 0 then
            utils.debugOutput("Reactive: zone changed, flushing %d queued requests", #reactiveQueue)
            for _, entry in ipairs(reactiveQueue) do
                broadcast({ command = 'release', playerName = entry.playerName, squireName = myName, petCombat = entry.petCombat, })
                broadcast({ command = 'aborted', playerName = entry.playerName, squireName = myName, reason = 'zoned', })
            end
            reactiveQueue = {}
            reactiveQueuedNames = Set.new({})
        end
        if deps.aborted() and not deps.stopRequested() then
            utils.debugOutput("Reactive: zone changed, clearing abort state")
            deps.setAborted(false)
            deps.setStatusText("Idle")
        end
    end

    if mode == "page" or mode == "both" then
        pollPetId()
        pollPetWeapons()
        checkReBroadcastTimer()
    end

    if mode == "squire" or mode == "both" then
        processReactiveQueue()
    end
end

function reactive.onStop()
    utils.debugOutput("Reactive: stop requested (arming=%s, queue=%d)", tostring(currentlyArming), #reactiveQueue)
    if currentlyArming then
        broadcast({ command = 'release', playerName = currentlyArming, squireName = myName, })
        broadcast({ command = 'aborted', playerName = currentlyArming, squireName = myName, reason = 'stopped', })
        currentlyArming = nil
    end
    clearQueue()
    reBroadcastTimer = nil
    awaitingArm = false
    recentlyArmed = {}
    lastArmedPetId = {}
end

function reactive.onReset()
    utils.debugOutput("Reactive: reset")
end

function reactive.onModeChange(oldMode, newMode)
    if (oldMode == "page" or oldMode == "both") and newMode ~= "page" and newMode ~= "both" then
        lastPetId = me.Pet.ID() or 0
        reBroadcastTimer = nil
        lastWeaponPollTime = 0
        awaitingArm = false
    end

    if (oldMode == "squire" or oldMode == "both") and newMode ~= "squire" and newMode ~= "both" then
        clearQueue()
    end

    if (newMode == "page" or newMode == "both") and oldMode ~= "page" and oldMode ~= "both" then
        lastPetId = me.Pet.ID() or 0
        lastWeaponPollTime = mq.gettime()
    end
end

function reactive.getQueueCount()
    return #reactiveQueue
end

function reactive.getBlockReason()
    if deps.isArming() then return "already arming" end
    if deps.aborted() then return "halted" end
    if not deps.getSet(deps.settings.selectedSet) then return "no set selected" end
    return getBlockReason()
end

function reactive.broadcastWelcomeDone()
    broadcast({ command = 'welcome_done', senderName = myName, })
end

function reactive.updateSettings(newSettings)
    deps.settings = newSettings
end

return reactive
