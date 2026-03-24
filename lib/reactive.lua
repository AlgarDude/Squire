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

-- Helpers

local function broadcast(content)
    if actor then
        actor:send(content)
    end
end

local function removeFromReactiveQueue(playerName)
    if not playerName then return end
    local lower = playerName:lower()
    for i = #reactiveQueue, 1, -1 do
        if reactiveQueue[i].playerName:lower() == lower then
            table.remove(reactiveQueue, i)
        end
    end
    reactiveQueuedNames:remove(lower)
end

-- Gating (Reactive Mode Only)

-- Mid-arm abort: only checks external interruptions, not states caused by arming itself
-- (casting, cursor, moving, GiveWnd are all expected during arming)
local function shouldAbortArming()
    if me.CombatState() == "COMBAT" then return true end
    if me.Dead() then return true end
    if me.Feigning() then return true end
    if mq.TLO.MacroQuest.GameState() ~= 'INGAME' then return true end
    if mq.TLO.Window("TradeWnd").Open() then return true end
    if mq.TLO.Window("LootWnd").Open() then return true end
    if mq.TLO.Window("MerchantWnd").Open() then return true end
    if mq.TLO.Window("BigBankWnd").Open() then return true end
    return false
end

local function getBlockReason()
    if me.CombatState() == "COMBAT" then return "in combat" end
    if me.Dead() then return "dead" end
    if me.Feigning() then return "feigning" end
    if mq.TLO.MacroQuest.GameState() ~= 'INGAME' then return "not in game" end
    if me.Casting.ID() then return "casting" end
    if me.Moving() then return "moving" end
    if mq.TLO.Cursor.ID() then return "item on cursor" end
    if mq.TLO.Window("SpellBookWnd").Open() then return "spellbook open" end
    if mq.TLO.Window("TradeWnd").Open() then return "trade window open" end
    if mq.TLO.Window("LootWnd").Open() then return "loot window open" end
    if mq.TLO.Window("MerchantWnd").Open() then return "merchant open" end
    if mq.TLO.Window("BigBankWnd").Open() then return "bank open" end
    if mq.TLO.Window("GiveWnd").Open() then return "give window open" end
    return nil
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

    -- Global commands (handled regardless of mode)
    if cmd == "welcome_done" and message.content.senderName ~= myName then
        if deps.onWelcomeDone then deps.onWelcomeDone() end
        return
    end

    local content = message.content
    local mode = deps.settings.reactiveMode or "off"
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
                table.insert(reactiveQueue, { playerName = content.playerName, })
                utils.debugOutput("Reactive: queued %s for arming", content.playerName)
            end
        elseif cmd == "claim" and content.squireName ~= myName then
            removeFromReactiveQueue(content.playerName)
        elseif cmd == "release" and content.squireName ~= myName then
            local lower = content.playerName and content.playerName:lower()
            if lower and not reactiveQueuedNames:contains(lower) then
                reactiveQueuedNames:add(lower)
                table.insert(reactiveQueue, { playerName = content.playerName, })
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
        if not (me.Pet.DisplayName() or ""):lower():find("familiar") then
            if not awaitingArm and ((me.Pet.Primary() or 0) == 0 or (me.Pet.Secondary() or 0) == 0) then
                utils.output("Pet summoned - requesting arming.")
                broadcast({ command = 'arm', playerName = myName, petId = currentPetId, })
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
    if (me.Pet.DisplayName() or ""):lower():find("familiar") then return end
    if awaitingArm then
        if now - awaitingArmTime > 60000 then
            utils.debugOutput("Reactive: arm request timed out, retrying")
            awaitingArm = false
        else
            return
        end
    end
    if (me.Pet.Primary() or 0) == 0 or (me.Pet.Secondary() or 0) == 0 then
        broadcast({ command = 'arm', playerName = myName, petId = me.Pet.ID(), })
        awaitingArm = true
        awaitingArmTime = now
    end
end

local function checkReBroadcastTimer()
    if not reBroadcastTimer then return end
    if mq.gettime() >= reBroadcastTimer then
        reBroadcastTimer = nil
        if (me.Pet.ID() or 0) > 0 then
            broadcast({ command = 'arm', playerName = myName, petId = me.Pet.ID(), })
            awaitingArm = true
            awaitingArmTime = mq.gettime()
        end
    end
end

-- Squire Logic

local function saveCurrentGems()
    local gems = {}
    for i = 1, me.NumGems() do
        gems[i] = me.Gem(i)() or ""
    end
    return gems
end

local function processReactiveQueue()
    if #reactiveQueue == 0 then return end
    if not isSafeToArm() then return end
    if not deps.getSet(deps.settings.selectedSet) then return end

    local mode = deps.settings.reactiveMode or "off"
    deps.setIsArming(true)
    preFired = false
    local savedGems = saveCurrentGems()
    local haltReason = nil

    local processed = 0

    while #reactiveQueue > 0 do
        if deps.stopRequested() or deps.aborted() then break end

        local currentMode = deps.settings.reactiveMode or "off"
        if currentMode ~= "squire" and currentMode ~= "both" then
            reactiveQueue = {}
            reactiveQueuedNames = Set.new({})
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
        local petSpawn = mq.TLO.Spawn("pc " .. entry.playerName).Pet
        if (petSpawn.ID() or 0) == 0
            or (petSpawn.DisplayName() or ""):lower():find("familiar")
            or (petSpawn.Distance3D() or 999) > 100 then
            currentlyArming = nil
            broadcast({ command = 'done', playerName = entry.playerName, squireName = myName, })
            recentlyArmed[entry.playerName:lower()] = mq.gettime() + 5000
        else
            if not preFired and deps.settings.preQueueCommand ~= "" then
                mq.cmdf("%s", deps.settings.preQueueCommand)
                preFired = true
            end

            local abortFired = false
            local abortCheck = function()
                abortFired = abortFired or shouldAbortArming()
                return abortFired
            end

            local result, status = deps.armPet(entry.playerName, nil, false, abortCheck)

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
                broadcast({ command = 'release', playerName = entry.playerName, squireName = myName, })
                broadcast({ command = 'aborted', playerName = entry.playerName, squireName = myName, reason = 'inventory', })
                currentlyArming = nil
                break
            elseif abortFired or deps.stopRequested() then
                -- Mid-pet environmental abort or user stop
                broadcast({ command = 'release', playerName = entry.playerName, squireName = myName, })
                broadcast({
                    command = 'aborted',
                    playerName = entry.playerName,
                    squireName = myName,
                    reason = abortFired and 'environment' or 'stopped',
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
                local armedPet = mq.TLO.Spawn("pc " .. entry.playerName).Pet
                if armedPet() then
                    lastArmedPetId[entry.playerName:lower()] = armedPet.ID()
                end

                -- Squire + Page local shortcut for self-arm
                if (mode == "page" or mode == "both") and entry.playerName:lower() == myName:lower() then
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

    -- Cleanup
    local canCleanup = not deps.stopRequested() and not shouldAbortArming()

    if canCleanup then
        if mq.TLO.Cursor.ID() then
            local cursorName = mq.TLO.Cursor.Name() or "unknown item"
            mq.cmd("/autoinventory")
            mq.delay(3000, function() return not mq.TLO.Cursor.ID() end)
            if mq.TLO.Cursor.ID() then
                local reason = string.format("'%s' stuck on cursor after cleanup", cursorName)
                haltReason = reason
                utils.output("\arHALTED: %s", reason)
                mq.cmdf("/dgt [Squire] %s HALTED: %s - /squire reset to resume", myName, reason)
                deps.setAborted(true)
            end
        end

        if not mq.TLO.Cursor.ID() then
            utils.restoreDisplacedItem()
        end

        casting.restoreSpells(savedGems)

        delivery.navToStart(deps.settings.allowMovement)

        if preFired and deps.settings.postQueueCommand ~= "" then
            mq.cmdf("%s", deps.settings.postQueueCommand)
        end
    end

    delivery.clearStartPosition()
    preFired = false

    local wasAborted = deps.aborted()
    local wasStopped = deps.stopRequested()
    deps.setIsArming(false)

    if wasAborted then
        if wasStopped then
            deps.setStatusText("HALTED - user stopped")
        else
            deps.setStatusText(string.format("HALTED - %s", haltReason or "unknown error"))
        end
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
    local mode = deps.settings.reactiveMode or "off"
    if mode == "off" then return end

    -- Zone change: clear abort state and flush queue, let pages re-request
    local currentZoneId = mq.TLO.Zone.ID() or 0
    if currentZoneId ~= lastZoneId then
        lastZoneId = currentZoneId
        if #reactiveQueue > 0 then
            utils.debugOutput("Reactive: zone changed, flushing %d queued requests", #reactiveQueue)
            for _, entry in ipairs(reactiveQueue) do
                broadcast({ command = 'release', playerName = entry.playerName, squireName = myName, })
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
    if currentlyArming then
        broadcast({ command = 'release', playerName = currentlyArming, squireName = myName, })
        broadcast({ command = 'aborted', playerName = currentlyArming, squireName = myName, reason = 'stopped', })
        currentlyArming = nil
    end
    reactiveQueue = {}
    reactiveQueuedNames = Set.new({})
    reBroadcastTimer = nil
    awaitingArm = false
    recentlyArmed = {}
    lastArmedPetId = {}
end

function reactive.onReset()
    -- Reactive resumes naturally on next tick when aborted clears
end

function reactive.onModeChange(oldMode, newMode)
    if (oldMode == "page" or oldMode == "both") and newMode ~= "page" and newMode ~= "both" then
        lastPetId = me.Pet.ID() or 0
        reBroadcastTimer = nil
        lastWeaponPollTime = 0
        awaitingArm = false
    end

    if (oldMode == "squire" or oldMode == "both") and newMode ~= "squire" and newMode ~= "both" then
        reactiveQueue = {}
        reactiveQueuedNames = Set.new({})
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
    return getBlockReason()
end

function reactive.isPageOnly()
    local mode = deps and deps.settings.reactiveMode or "off"
    return mode == "page"
end

function reactive.broadcastWelcomeDone()
    broadcast({ command = 'welcome_done', senderName = myName, })
end

function reactive.updateSettings(newSettings)
    if deps then
        deps.settings = newSettings
    end
end

return reactive
