--[[
    Squire - casting.lua
    Spell memorization, gem management, and source execution (spell/AA/item)
]]

local mq = require('mq')
local utils = require('squire.utils')

local casting = {}

local gemMap = {}

-- Spell Memorization

function casting.memorizeSpell(gemSlot, spellName)
    local me = mq.TLO.Me

    if not me.Book(spellName)() then
        utils.output("\ar%s is not in spellbook.", spellName)
        return false
    end

    -- Already memorized somewhere? Return that gem.
    for i = 1, me.NumGems() do
        if me.Gem(i)() == spellName then
            utils.debugOutput("Spell '%s' already in gem %d", spellName, i)
            return i
        end
    end

    if me.CombatState():lower() == "combat" then
        utils.output("\arCannot memorize %s during combat.", spellName)
        return false
    end

    utils.debugOutput("Memorizing %s in gem %d...", spellName, gemSlot)
    mq.cmdf('/memspell %d "%s"', gemSlot, spellName)

    local maxWait = 25000
    while maxWait > 0 do
        if me.Gem(gemSlot)() == spellName and me.SpellReady(gemSlot)() then
            utils.debugOutput("Memorized %s in gem %d.", spellName, gemSlot)
            return gemSlot
        end

        if me.CombatState():lower() == "combat" or me.Casting() or me.Moving() then
            utils.output("\arMemorization of %s interrupted.", spellName)
            return false
        end

        mq.delay(100)
        mq.doevents()
        maxWait = maxWait - 100
    end

    utils.output("\arTimed out memorizing %s.", spellName)
    return false
end

-- Spell Preparation

function casting.prepareSpells(set)
    gemMap = {}

    local spellNames = {}
    local seen = {}
    for _, entry in ipairs(set) do
        if entry.enabled and entry.type == "spell" and entry.name ~= "" then
            if not seen[entry.name] then
                seen[entry.name] = true
                table.insert(spellNames, entry.name)
            end
        end
    end

    if #spellNames == 0 then
        return gemMap
    end

    local nextGem = mq.TLO.Me.NumGems()
    for _, spellName in ipairs(spellNames) do
        if nextGem < 1 then
            utils.output("\arNot enough gem slots for all spells.")
            return nil
        end
        local result = casting.memorizeSpell(nextGem, spellName)
        if not result then
            utils.output("\arFailed to prepare spell: %s", spellName)
            return nil
        end
        gemMap[spellName] = result
        if result == nextGem then
            nextGem = nextGem - 1
        end
    end

    return gemMap
end

-- Spell Restoration

function casting.restoreSpells(savedGems)
    for gemSlot, spellName in pairs(savedGems) do
        if spellName ~= "" and mq.TLO.Me.Gem(gemSlot)() ~= spellName then
            casting.memorizeSpell(gemSlot, spellName)
        end
    end
end

-- Source Execution

local function waitForCastComplete(abortFunc)
    -- Wait for casting to start (up to 1s)
    mq.delay(1000, function() return mq.TLO.Me.Casting() ~= nil end)

    -- Wait for casting to finish
    utils.waitFor(function() return not mq.TLO.Me.Casting() end, 30000, 100, abortFunc)
end

function casting.useSource(entry, abortFunc)
    if entry.type == "spell" then
        local gem = gemMap[entry.name]
        if not gem then
            utils.output("\arNo gem mapped for spell: %s", entry.name)
            return false
        end

        if not utils.waitFor(function() return mq.TLO.Me.SpellReady(gem)() end, 30000, 100, abortFunc) then
            utils.output("\arSpell %s not ready in time.", entry.name)
            return false
        end

        utils.debugOutput("Casting spell '%s' from gem %d", entry.name, gem)
        mq.cmdf("/cast %d", gem)
        waitForCastComplete(abortFunc)
        return true
    elseif entry.type == "aa" then
        if not utils.waitFor(function() return mq.TLO.Me.AltAbilityReady(entry.name)() end, 30000, 100, abortFunc) then
            utils.output("\arAA %s not ready in time.", entry.name)
            return false
        end

        utils.debugOutput("Using AA '%s'", entry.name)
        mq.cmdf("/aa act %s", entry.name)
        waitForCastComplete(abortFunc)
        return true
    elseif entry.type == "item" then
        if not utils.waitFor(function() return mq.TLO.Me.ItemReady(entry.name)() end, 30000, 100, abortFunc) then
            utils.output("\arItem %s not ready in time.", entry.name)
            return false
        end

        utils.debugOutput("Using item '%s'", entry.name)
        mq.cmdf('/useitem "%s"', entry.name)
        waitForCastComplete(abortFunc)
        return true
    end

    utils.output("\arUnknown source type: %s", entry.type)
    return false
end

return casting
