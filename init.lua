--[[
    Squire - Pet Arming Script
    Arms other players' pets with configurable equipment sets.
    Usage: /lua run squire
]]

local mq = require('mq')
local imgui = require('ImGui')
local icons = require('mq.Icons')
local utils = require('squire.utils')
local casting = require('squire.casting')
local delivery = require('squire.delivery')

-- Module-Level State

local settings = {}
local presetSets = {}
local startPosition = nil
local stopRequested = false
local aborted = false
local armHistory = {}
local queue = {}
local isArming = false
local showUI = true
local settingsDirty = false
local savedGems = nil
local statusText = "Idle"

local methodTypes = { "direct", "cursor", "bag" }
local methodLabels = { "Direct to Pet", "Summon to Cursor", "Summon Bag" }
local sourceTypes = { "spell", "aa", "item" }
local sourceLabels = { "Spell", "AA", "Item" }

-- EMU server name -> preset file suffix
local emuServers = {
    ["EQ Might"] = "eqmight",
    ["Project Lazarus"] = "projectlazarus",
}

local tellAccessOptions = { "anyone", "group", "raid", "allowlist", "denylist" }
local tellAccessLabels = { "Anyone", "Group Only", "Raid Only", "Allow List", "Deny List" }

-- UI temp state
local showSettings = false
local showEditSets = false
local newSetName = ""
local renameSetName = ""
local manualPlayerName = ""
local pendingRemoveIdx = nil
local newSourceName = ""
local newSourceType = "spell"
local newSourceMethod = "direct"
local showAddSource = false
local editingIdx = nil
local editSourceType = ""
local editSourceName = ""
local editSourceMethod = ""
local showHelp = false

-- Preset System

local presetClassMap = {}

local function resolvePresets()
    presetSets = {}
    presetClassMap = {}

    local isEmu = mq.TLO.MacroQuest.BuildName():lower() == "emu"
    local presetFile
    if isEmu then
        local serverName = mq.TLO.EverQuest.Server()
        local fileSuffix = emuServers[serverName]
        if not fileSuffix then
            fileSuffix = serverName:lower():gsub(" ", "")
            utils.output("\ayServer '%s' not in emuServers table - trying '%s'. Add it to emuServers in init.lua.", serverName, fileSuffix)
        end
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

    local me = mq.TLO.Me
    local myShortName = me.Class.ShortName()
    for _, definition in ipairs(rawPresets) do
        local title = definition.title:gsub("Class", myShortName)
        if definition.classes then
            presetClassMap[title] = definition.classes
        end

        local resolvedSet = {}
        for _, group in ipairs(definition.effects) do
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
                        items = candidate.items or {},
                        trashItems = candidate.trashItems or {},
                        candidates = group,
                    })
                    break
                end
            end
        end
        presetSets[title] = resolvedSet
    end

    local presetCount = 0
    for _ in pairs(presetSets) do presetCount = presetCount + 1 end
end

local function getSet(setName)
    return settings.sets[setName] or presetSets[setName]
end

local function isPresetSet(setName)
    return presetSets[setName] ~= nil
end

local function getAllSetNames()
    local names = {}
    for name in pairs(settings.sets) do
        table.insert(names, name)
    end
    table.sort(names)

    -- Only show presets matching this character's class, skip user-set name collisions
    local myClass = mq.TLO.Me.Class.ShortName()
    local presetNames = {}
    for name in pairs(presetSets) do
        if not settings.sets[name] then
            local classes = presetClassMap[name]
            if not classes then
                table.insert(presetNames, name)
            else
                for _, cls in ipairs(classes) do
                    if cls == myClass then
                        table.insert(presetNames, name)
                        break
                    end
                end
            end
        end
    end
    table.sort(presetNames)
    for _, name in ipairs(presetNames) do
        table.insert(names, name)
    end
    return names
end

-- Navigation Helpers

local function distSqFromStart(y, x, z)
    if not startPosition then return 0 end
    local dy = y - startPosition.y
    local dx = x - startPosition.x
    local dz = z - startPosition.z
    return dy * dy + dx * dx + dz * dz
end

local function navToPet(petSpawn)
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

local function returnToStart()
    if not startPosition then return end
    if not settings.allowMovement then return end

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

-- Core Arm Logic

local function armPet(playerName, setName, fromTell)
    if aborted then
        utils.output("\arArming halted due to inventory error. Please resolve and restart the script.")
        return false
    end

    -- 1. Resolve set
    setName = setName or settings.selectedSet
    local set = getSet(setName)

    if not set then
        utils.output("\arSet '%s' not found.", setName)
        if fromTell then
            mq.cmdf('/tell %s Set "%s" not found.', playerName, setName)
        end
        return true
    end

    -- 2. Validate set has enabled entries
    local hasEnabled = false
    local hasBagMethod = false
    for _, entry in ipairs(set) do
        if entry.enabled then
            hasEnabled = true
            if entry.method == "bag" then
                hasBagMethod = true
            end
        end
    end
    if not hasEnabled then
        utils.output("\aySet '%s' has no enabled sources.", setName)
        return true
    end

    -- 3. Find pet
    local petSpawn
    if playerName:lower() == "self" then
        petSpawn = mq.TLO.Me.Pet
    else
        petSpawn = mq.TLO.Spawn("pc " .. playerName).Pet
    end

    if not petSpawn() or not petSpawn.ID() or petSpawn.ID() == 0 then
        utils.output("\ay%s does not have a pet.", playerName)
        if fromTell then
            mq.cmdf("/tell %s You do not appear to have a pet.", playerName)
        end
        return true
    end

    -- 4. Range check
    local petDist = petSpawn.Distance3D() or 999
    if petDist > 20 then
        if settings.allowMovement then
            if not navToPet(petSpawn) then
                utils.output("\ayCould not reach %s's pet. Skipping.", playerName)
                if fromTell then
                    mq.cmdf("/tell %s Your pet is out of range and I could not reach it.", playerName)
                end
                return true
            end
        else
            utils.output("\ay%s's pet is out of range (%.0f). Skipping.", playerName, petDist)
            if fromTell then
                mq.cmdf("/tell %s Your pet is out of range.", playerName)
            end
            return true
        end
    end

    -- 5. Clear cursor
    local cursorResult = utils.clearCursor(hasBagMethod)
    if cursorResult == "abort" then
        utils.output("\arCursor stuck. Aborting.")
        return false
    end

    -- 6. Free top slot for bag methods
    local freeSlot
    if hasBagMethod then
        freeSlot = utils.ensureFreeTopSlot()
        if freeSlot == "abort" then
            utils.output("\arCannot free a top-level slot. Aborting.")
            return false
        end
    end

    -- 7. Prepare spells
    if not casting.prepareSpells(set) then
        utils.output("\arFailed to prepare spells for set '%s'.", setName)
        return false
    end

    -- 8. Execute delivery for each enabled source entry in order
    local results = {}
    local stopped = false

    local function abortFunc()
        return stopRequested
    end

    for i, entry in ipairs(set) do
        if not entry.enabled then goto continue end

        if stopRequested then
            stopped = true
            break
        end

        -- Re-check pet range
        if not petSpawn() or (petSpawn.Distance3D() or 999) > 20 then
            if settings.allowMovement then
                if not navToPet(petSpawn) then
                    utils.output("\ayPet moved out of range. Skipping remaining sources.")
                    break
                end
            else
                utils.output("\ayPet out of range. Skipping remaining sources.")
                break
            end
        end

        -- Verify freeSlot if bag method
        if entry.method == "bag" then
            if mq.TLO.InvSlot("pack" .. freeSlot).Item.ID() then
                utils.output("\arFree slot pack%d still occupied. Skipping %s.", freeSlot, entry.name)
                results[i] = false
                goto continue
            end
        end

        local success = false
        if entry.method == "direct" then
            success = delivery.deliverDirect(entry, petSpawn, abortFunc)
        elseif entry.method == "cursor" then
            success = delivery.deliverCursor(entry, petSpawn, abortFunc)
        elseif entry.method == "bag" then
            success = delivery.deliverBag(entry, petSpawn, freeSlot, abortFunc)
        end
        results[i] = success

        ::continue::
    end

    -- 9. Report result
    local total, passed, failed = 0, 0, {}
    for i, entry in ipairs(set) do
        if entry.enabled and results[i] ~= nil then
            total = total + 1
            if results[i] then
                passed = passed + 1
            else
                table.insert(failed, entry.name ~= "" and entry.name or ("Source " .. i))
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
    })
    if #armHistory > 50 then
        table.remove(armHistory)
    end

    local displayName = playerName:lower() == "self" and "my" or (playerName .. "'s")
    if #failed > 0 then
        utils.debugOutput("Processed %d/%d sources for %s pet. (Set: %s) Failed: %s", passed, total, displayName, setName, table.concat(failed, ", "))
    else
        utils.debugOutput("Processed %d/%d sources for %s pet. (Set: %s)", passed, total, displayName, setName)
    end

    if fromTell then
        if #failed > 0 then
            mq.cmdf("/tell %s Processed %d/%d sources for your pet. Failed: %s", playerName, passed, total, table.concat(failed, ", "))
        else
            mq.cmdf("/tell %s Processed %d/%d sources for your pet.", playerName, passed, total)
        end
    end

    return true
end

-- Set Validation


-- Queue & Processing

local function addToQueue(playerName, setName, fromTell)
    if aborted then
        utils.output("\arArming halted due to inventory error. Please resolve and restart the script.")
        return
    end

    for _, entry in ipairs(queue) do
        if entry.playerName:lower() == playerName:lower() then
            return
        end
    end

    table.insert(queue, {
        playerName = playerName,
        setName = setName,
        fromTell = fromTell or false,
    })
end

local function saveCurrentGems()
    local gems = {}
    for i = 1, mq.TLO.Me.NumGems() do
        gems[i] = mq.TLO.Me.Gem(i)() or ""
    end
    return gems
end

local function processQueue()
    if isArming or #queue == 0 then return end

    if not savedGems then
        savedGems = saveCurrentGems()
    end

    isArming = true
    local processed = 0

    while #queue > 0 do
        if stopRequested then
            queue = {}
            break
        end

        local request = table.remove(queue, 1)
        processed = processed + 1
        local displayName = request.playerName:lower() == "self" and "My" or (request.playerName .. "'s")
        statusText = string.format("Arming pet %d/%d: %s pet...", processed, processed + #queue, displayName)

        local result = armPet(request.playerName, request.setName, request.fromTell)

        if not result then
            aborted = true
            queue = {}
            break
        end
    end

    -- Cleanup: clear cursor if anything is on it
    if mq.TLO.Cursor.ID() then
        mq.cmd("/autoinventory")
        mq.delay(3000, function() return not mq.TLO.Cursor.ID() end)
    end

    -- Restore spells when queue is empty
    if savedGems then
        casting.restoreSpells(savedGems)
        savedGems = nil
    end

    returnToStart()
    startPosition = nil

    isArming = false
    stopRequested = false
    statusText = aborted and "HALTED - inventory error" or "Idle"
end

-- Access Check

local function isAllowedSender(senderName)
    if settings.tellAccess == "anyone" then
        return true
    elseif settings.tellAccess == "group" then
        for i = 1, 5 do
            local member = mq.TLO.Group.Member(i)
            if member() and member.Name():lower() == senderName:lower() then
                return true
            end
        end
        return false
    elseif settings.tellAccess == "raid" then
        for i = 1, mq.TLO.Raid.Members() or 0 do
            local member = mq.TLO.Raid.Member(i)
            if member() and member.Name():lower() == senderName:lower() then
                return true
            end
        end
        return false
    elseif settings.tellAccess == "allowlist" then
        for _, name in ipairs(settings.tellAllowlist or {}) do
            if name:lower() == senderName:lower() then
                return true
            end
        end
        return false
    elseif settings.tellAccess == "denylist" then
        for _, name in ipairs(settings.tellDenylist or {}) do
            if name:lower() == senderName:lower() then
                utils.output("\ay%s is on the deny list. Ignoring request.", senderName)
                return false
            end
        end
        return true
    end
    return false
end

-- Event Handler

local function eventHandler(line, sender, message)
    if not message then return end
    local trimmed = message:gsub("^%s+", ""):gsub("%s+$", "")
    local triggerLower = settings.triggerWord:lower()

    if trimmed:lower():find(triggerLower, 1, true) ~= 1 then return end
    if not isAllowedSender(sender) then return end

    local afterTrigger = trimmed:sub(#settings.triggerWord + 1):gsub("^%s+", ""):gsub("%s+$", "")
    local setName = afterTrigger ~= "" and afterTrigger or nil

    addToQueue(sender, setName, true)
end

-- Command Handler

local function joinArgs(args, startIdx)
    local parts = {}
    for i = startIdx, #args do
        table.insert(parts, args[i])
    end
    return #parts > 0 and table.concat(parts, " ") or nil
end

local function commandHandler(...)
    local args = { ... }
    local cmd = args[1] and args[1]:lower() or "help"

    if cmd == "arm" then
        local target = args[2] or ""
        local setName = joinArgs(args, 3)

        if target:lower() == "self" then
            addToQueue("self", setName, false)
        elseif target:lower() == "target" then
            local t = mq.TLO.Target
            if not t() or t.Type() ~= "PC" then
                utils.output("\ayTarget is not a PC.")
            elseif not t.Pet() or t.Pet.ID() == 0 then
                utils.output("\ay%s does not have a pet.", t.Name())
            else
                addToQueue(t.Name(), setName, false)
            end
        elseif target ~= "" then
            addToQueue(target, setName, false)
        else
            utils.output("Usage: /squire arm <PlayerName|self|target> [SetName]")
        end

    elseif cmd == "group" then
        local setName = joinArgs(args, 2)

        local groupSize = mq.TLO.Group.GroupSize() or 0
        for i = 1, groupSize - 1 do
            local member = mq.TLO.Group.Member(i)
            if member() and member.Name() then
                local memberSpawn = mq.TLO.Spawn("pc " .. member.Name())
                if memberSpawn() and memberSpawn.Pet() and memberSpawn.Pet.ID() > 0 then
                    addToQueue(member.Name(), setName, false)
                end
            end
        end

    elseif cmd == "raid" then
        local setName = joinArgs(args, 2)

        local raidMembers = mq.TLO.Raid.Members() or 0
        for i = 1, raidMembers do
            local member = mq.TLO.Raid.Member(i)
            if member() and member.Name() then
                local memberSpawn = mq.TLO.Spawn("pc " .. member.Name())
                if memberSpawn() and memberSpawn.Pet() and memberSpawn.Pet.ID() > 0 then
                    addToQueue(member.Name(), setName, false)
                end
            end
        end

    elseif cmd == "stop" then
        stopRequested = true
        queue = {}
        utils.output("Stop requested. Clearing queue.")

    elseif cmd == "show" then
        showUI = true

    elseif cmd == "hide" then
        showUI = false

    elseif cmd == "debug" then
        local arg = args[2] and args[2]:lower() or ""
        local prev = utils.debugMode
        if arg == "on" then
            utils.debugMode = true
        elseif arg == "off" then
            utils.debugMode = false
        else
            utils.debugMode = not utils.debugMode
        end
        if utils.debugMode ~= prev then
            settings.debugMode = utils.debugMode
            settingsDirty = true
            utils.output("Debug mode: %s", utils.debugMode and "ON" or "OFF")
        end

    elseif cmd == "help" then
        utils.output("Commands:")
        utils.output("  /squire arm <PlayerName|self|target> [SetName]")
        utils.output("  /squire group [SetName]")
        utils.output("  /squire raid [SetName]")
        utils.output("  /squire stop")
        utils.output("  /squire show")
        utils.output("  /squire hide")
        utils.output("  /squire debug [on|off]")
        utils.output("  /squire help")

    else
        utils.output("Unknown command: %s. Try /squire help", cmd)
    end
end

-- ImGui UI

local animItems = mq.FindTextureAnimation("A_DragItem")
local animSpells = mq.FindTextureAnimation("A_SpellIcons")
local bgTexture = mq.CreateTexture(mq.TLO.Lua.Dir() .. "/squire/resources/squire.png")

local function renderWindowBg()
    if not bgTexture then return end
    local startPos = imgui.GetCursorPosVec()
    local availW, availH = imgui.GetContentRegionAvail()
    local imgSize = math.min(availW, availH)
    local offsetX = (availW - imgSize) * 0.5
    local offsetY = (availH - imgSize) * 0.5
    imgui.SetCursorPos(startPos.x + offsetX, startPos.y + offsetY)
    imgui.Image(bgTexture:GetTextureID(), ImVec2(imgSize, imgSize),
        ImVec2(0, 0), ImVec2(1, 1), ImVec4(1, 1, 1, 0.12))
    imgui.SetCursorPos(startPos.x, startPos.y)
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
-- See rgmercs clickies.lua:RenderClickyControls for reference pattern.
local function renderSourceHeaderControls(currentSet, idx, headerCursorPos, headerScreenPos, preRender, editable)
    local startingPos = imgui.GetCursorPosVec()
    local yOffset = imgui.GetStyle().FramePadding.y
    local entry = currentSet[idx]
    local suffix = preRender and "_pre" or ""

    -- Source icon overlay (post-render only)
    if not preRender and entry.name ~= "" then
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
            local aa = mq.TLO.Me.AltAbility(entry.name)
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
        if imgui.SmallButton(icons.FA_PENCIL) then
            editingIdx = idx
            editSourceType = entry.type
            editSourceName = entry.name
            editSourceMethod = entry.method
        end

        imgui.SameLine()
        if imgui.SmallButton(icons.FA_TRASH) and preRender then
            pendingRemoveIdx = idx
        end
    end

    imgui.PopID()
    imgui.SetCursorPos(startingPos.x, startingPos.y)
end

local function renderUI()
    if not showUI then return end

    imgui.PushStyleVar(ImGuiStyleVar.FrameRounding, 4)
    imgui.PushStyleVar(ImGuiStyleVar.WindowRounding, 6)
    imgui.PushStyleVar(ImGuiStyleVar.ChildRounding, 4)
    imgui.PushStyleVar(ImGuiStyleVar.PopupRounding, 4)
    imgui.PushStyleVar(ImGuiStyleVar.GrabRounding, 4)

    imgui.SetNextWindowSize(ImVec2(400, 400), ImGuiCond.FirstUseEver)
    imgui.SetNextWindowSizeConstraints(ImVec2(400, 400), ImVec2(800, 2000))
    local prevShowUI = showUI
    local shouldDraw
    showUI, shouldDraw = imgui.Begin("Squire", showUI)
    if not showUI and prevShowUI then
        utils.output("Window closed. Use \ag/squire show\ax to reopen.")
    end
    if not shouldDraw then
        imgui.End()
        imgui.PopStyleVar(5)
        return
    end

    renderWindowBg()
    local contentStartPos = imgui.GetCursorPosVec()
    local allNames = getAllSetNames()

    -- Status
    imgui.Text("Status:")
    imgui.SameLine()
    if aborted then
        imgui.TextColored(1, 0, 0, 1, statusText)
    elseif isArming then
        imgui.TextColored(1, 1, 0, 1, statusText)
    else
        imgui.TextColored(0, 1, 0, 1, statusText)
    end

    -- Set selector + Manage Sets button
    imgui.Text("Current Set:")
    imgui.SameLine()
    imgui.SetNextItemWidth(200)
    local comboLabel = settings.selectedSet ~= "" and settings.selectedSet or "No Sets Found"
    if settings.selectedSet == "" then imgui.PushStyleColor(ImGuiCol.Text, ImVec4(0.5, 0.5, 0.5, 1.0)) end
    if imgui.BeginCombo("##SetCombo", comboLabel) then
        for _, name in ipairs(allNames) do
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
        showEditSets = not showEditSets
    end

    imgui.SeparatorText("Arming")

    -- Arm Controls
    if isArming then imgui.BeginDisabled() end
    imgui.PushStyleVar(ImGuiStyleVar.FramePadding, 8, 6)
    if imgui.Button("My Pet") then
        addToQueue("self", nil, false)
    end
    imgui.SameLine()
    if imgui.Button("Target's Pet") then
        commandHandler("arm", "target")
    end
    imgui.SameLine()
    if imgui.Button("Group Pets") then
        commandHandler("group")
    end
    imgui.SameLine()
    if imgui.Button("Raid Pets") then
        commandHandler("raid")
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

    if isArming then
        if imgui.Button("Stop") then
            stopRequested = true
            queue = {}
            utils.output("Stop requested. Clearing queue.")
        end
    end

    if imgui.CollapsingHeader("History") then
        local _, availY = imgui.GetContentRegionAvail()
        imgui.BeginChild("##HistoryScroll", ImVec2(0, availY - imgui.GetFrameHeightWithSpacing()), 0)
        for _, histEntry in ipairs(armHistory) do
            local displayName = histEntry.playerName:lower() == "self" and "my" or (histEntry.playerName .. "'s")
            imgui.TextColored(0.4, 0.8, 0.4, 1, string.format("[%s]", histEntry.timestamp))
            imgui.SameLine(0, 4)
            if #histEntry.failed > 0 then
                imgui.TextWrapped(string.format("Processed %d/%d sources for %s pet. (Set: %s) Failed: %s",
                    histEntry.passed, histEntry.total, displayName, histEntry.setName,
                    table.concat(histEntry.failed, ", ")))
            else
                imgui.TextWrapped(string.format("Processed %d/%d sources for %s pet. (Set: %s)",
                    histEntry.passed, histEntry.total, displayName, histEntry.setName))
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
    if imgui.IsItemHovered() then imgui.SetTooltip("Settings") end

    imgui.End()

    -- Settings Window
    if showSettings then
        imgui.SetNextWindowSize(ImVec2(350, 200), ImGuiCond.FirstUseEver)
        showSettings = imgui.Begin("Squire Settings###SquireSettings", showSettings)
        if showSettings then
            renderWindowBg()
            local changed

            imgui.Text("Trigger Word:")
            if imgui.IsItemHovered() then
                imgui.SetTooltip("If you receive a tell with this keyword, you will arm the sender's pet.")
            end
            imgui.SameLine()
            imgui.SetNextItemWidth(150)
            local tw
            tw, changed = imgui.InputTextWithHint("##triggerWord", "e.g. squire", settings.triggerWord)
            if imgui.IsItemHovered() then
                imgui.SetTooltip("If you receive a tell with this keyword, you will arm the sender's pet.")
            end
            if changed then
                settings.triggerWord = tw
                settingsDirty = true
            end

            local taIndex = 1
            for i, opt in ipairs(tellAccessOptions) do
                if opt == settings.tellAccess then taIndex = i break end
            end
            imgui.Text("Tell Access:")
            imgui.SameLine()
            imgui.SetNextItemWidth(150)
            local newTaIdx, taChanged = imgui.Combo("##tellAccess", taIndex, tellAccessLabels)
            if taChanged then
                settings.tellAccess = tellAccessOptions[newTaIdx]
                settingsDirty = true
            end

            if settings.tellAccess == "allowlist" then
                imgui.Text("Allow List:")
                if imgui.IsItemHovered() then
                    imgui.SetTooltip("If Allow List is selected, you will only react to keywords from the listed players.")
                end
                imgui.SameLine()
                local alStr = table.concat(settings.tellAllowlist or {}, ", ")
                imgui.SetNextItemWidth(250)
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
            end

            if settings.tellAccess == "denylist" then
                imgui.Text("Deny List:")
                if imgui.IsItemHovered() then
                    imgui.SetTooltip("If Deny List is selected, you will not react to keywords from the listed players.")
                end
                imgui.SameLine()
                local dlStr = table.concat(settings.tellDenylist or {}, ", ")
                imgui.SetNextItemWidth(250)
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
            end

            settings.allowMovement, changed = imgui.Checkbox("Allow Movement", settings.allowMovement)
            if imgui.IsItemHovered() then
                imgui.SetTooltip("Allow this PC to move up to 100 feet to arm a pet. Will return to the original location when complete.")
            end
            if changed then
                if settings.allowMovement and not mq.TLO.Plugin("mq2nav").IsLoaded() then
                    settings.allowMovement = false
                    utils.output("\ayMQ2Nav not loaded - Allow Movement cannot be enabled.")
                end
                settingsDirty = true
            end

            settings.debugMode, changed = imgui.Checkbox("Debug Logging", settings.debugMode)
            if changed then
                utils.debugMode = settings.debugMode
                settingsDirty = true
            end
        end
        imgui.End()
    end

    -- Manage Sets Window
    if showEditSets then
        imgui.SetNextWindowSize(ImVec2(520, 450), ImGuiCond.FirstUseEver)
        imgui.SetNextWindowSizeConstraints(ImVec2(520, 200), ImVec2(800, 2000))
        showEditSets = imgui.Begin("Manage Sets###SquireEditSets", showEditSets)
        if showEditSets then
            renderWindowBg()
            local allNames = getAllSetNames()
            local isPreset = isPresetSet(settings.selectedSet)

            -- Row 1: Set selector + right-aligned Rescan/Help
            imgui.Text("Set:")
            imgui.SameLine()
            imgui.SetNextItemWidth(200)
            if imgui.BeginCombo("##EditSetCombo", settings.selectedSet) then
                for _, name in ipairs(allNames) do
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
                                local copy = {
                                    enabled = entry.enabled,
                                    name = entry.name,
                                    type = entry.type,
                                    method = entry.method,
                                    items = {},
                                    trashItems = {},
                                }
                                for _, item in ipairs(entry.items) do
                                    table.insert(copy.items, { id = item.id, name = item.name, icon = item.icon })
                                end
                                for _, trash in ipairs(entry.trashItems or {}) do
                                    table.insert(copy.trashItems, { id = trash.id, name = trash.name, icon = trash.icon })
                                end
                                table.insert(newSet, copy)
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
                    local firstSet = next(settings.sets) or next(presetSets)
                    settings.selectedSet = firstSet or ""
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
                    local displayName = entry.name ~= "" and entry.name or "(unnamed)"
                    if entry.items and #entry.items > 0 then
                        displayName = displayName .. string.format(" (%d item%s)", #entry.items, #entry.items > 1 and "s" or "")
                    end

                    local headerOpen = imgui.CollapsingHeader("       " .. displayName .. "###header")

                    -- Post-render: visible controls + icon overlay (drawn after header)
                    renderSourceHeaderControls(currentSet, i, headerCursorPos, headerScreenPos, false, editable)

                    -- Expanded content: item management
                    if headerOpen and entry.method ~= "direct" then
                        imgui.Indent()

                        imgui.Text("Items to Give:")
                        local removeItemIdx = nil
                        for j, item in ipairs(entry.items) do
                            imgui.PushID("##item_" .. j)
                            if item.icon then
                                local iconPos = imgui.GetCursorScreenPosVec()
                                imgui.Dummy(16, 16)
                                local drawList = imgui.GetWindowDrawList()
                                animItems:SetTextureCell(item.icon - 500)
                                drawList:AddTextureAnimation(animItems, iconPos, ImVec2(16, 16))
                                imgui.SameLine()
                            end
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

                        if entry.method == "bag" then
                            imgui.Spacing()
                            imgui.Text("Items to Discard:")
                            local removeTrashIdx = nil
                            for j, trash in ipairs(entry.trashItems) do
                                imgui.PushID("##trash_" .. j)
                                if trash.icon then
                                    local iconPos = imgui.GetCursorScreenPosVec()
                                    imgui.Dummy(16, 16)
                                    local drawList = imgui.GetWindowDrawList()
                                    animItems:SetTextureCell(trash.icon - 500)
                                    drawList:AddTextureAnimation(animItems, iconPos, ImVec2(16, 16))
                                    imgui.SameLine()
                                end
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

                    if headerOpen and entry.candidates and #entry.candidates > 1 then
                        imgui.Indent()
                        imgui.Separator()
                        imgui.Text("Priority List:")
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
                        newSourceMethod = "direct"
                        showAddSource = true
                    end
                end
            end
        end
        imgui.End()
    end

    -- Add Source Window
    if showAddSource then
        local currentSet = getSet(settings.selectedSet)
        if not currentSet or isPresetSet(settings.selectedSet) or isArming then
            showAddSource = false
        else
            imgui.SetNextWindowSize(ImVec2(350, 180), ImGuiCond.FirstUseEver)
            local addOpen, shouldDraw = imgui.Begin("Add Source###SquireAddSource", showAddSource)
            if not addOpen then
                showAddSource = false
            end
            if shouldDraw then
                local nsIdx = 1
                for t, st in ipairs(sourceTypes) do
                    if st == newSourceType then nsIdx = t break end
                end
                imgui.Text("Source Type:")
                imgui.SameLine()
                imgui.SetNextItemWidth(180)
                if imgui.BeginCombo("##newType", sourceLabels[nsIdx]) then
                    for t, label in ipairs(sourceLabels) do
                        if imgui.Selectable(label, t == nsIdx) then
                            newSourceType = sourceTypes[t]
                        end
                    end
                    imgui.EndCombo()
                end

                local nsLabel = sourceLabels[nsIdx] .. " Name:"
                imgui.Text(nsLabel)
                imgui.SameLine()
                imgui.SetNextItemWidth(250)
                newSourceName = imgui.InputTextWithHint("##newName", "Exact In-Game Name", newSourceName)

                local nmIdx = 1
                for m, mt in ipairs(methodTypes) do
                    if mt == newSourceMethod then nmIdx = m break end
                end
                imgui.Text("Method:")
                imgui.SameLine()
                imgui.SetNextItemWidth(180)
                if imgui.BeginCombo("##newMethod", methodLabels[nmIdx]) then
                    for m, label in ipairs(methodLabels) do
                        if imgui.Selectable(label, m == nmIdx) then
                            newSourceMethod = methodTypes[m]
                        end
                    end
                    imgui.EndCombo()
                end

                imgui.Spacing()
                if imgui.Button("Create") and newSourceName ~= "" then
                    local newEntry = utils.defaultSourceEntry()
                    newEntry.enabled = true
                    newEntry.name = newSourceName
                    newEntry.type = newSourceType
                    newEntry.method = newSourceMethod
                    table.insert(currentSet, newEntry)
                    settingsDirty = true
                    showAddSource = false
                end
                imgui.SameLine()
                if imgui.Button("Cancel##AddSource") then
                    showAddSource = false
                end
            end
            imgui.End()
        end
    end

    -- Edit Source Window
    if editingIdx then
        local currentSet = getSet(settings.selectedSet)
        local entry = currentSet and currentSet[editingIdx]
        if not entry or isPresetSet(settings.selectedSet) or isArming then
            editingIdx = nil
        else
            imgui.SetNextWindowSize(ImVec2(350, 180), ImGuiCond.FirstUseEver)
            local editOpen, shouldDraw = imgui.Begin("Edit Source###SquireEditSource", true)
            if not editOpen then
                editingIdx = nil
            end
            if shouldDraw then
                local tIdx = 1
                for t, st in ipairs(sourceTypes) do
                    if st == editSourceType then tIdx = t break end
                end
                imgui.Text("Source Type:")
                imgui.SameLine()
                imgui.SetNextItemWidth(180)
                if imgui.BeginCombo("##editType", sourceLabels[tIdx]) then
                    for t, label in ipairs(sourceLabels) do
                        if imgui.Selectable(label, t == tIdx) then
                            editSourceType = sourceTypes[t]
                        end
                    end
                    imgui.EndCombo()
                end

                imgui.Text(sourceLabels[tIdx] .. " Name:")
                imgui.SameLine()
                imgui.SetNextItemWidth(250)
                editSourceName = imgui.InputTextWithHint("##editName", "Exact In-Game Name", editSourceName)

                local mIdx = 1
                for m, mt in ipairs(methodTypes) do
                    if mt == editSourceMethod then mIdx = m break end
                end
                imgui.Text("Method:")
                imgui.SameLine()
                imgui.SetNextItemWidth(180)
                if imgui.BeginCombo("##editMethod", methodLabels[mIdx]) then
                    for m, label in ipairs(methodLabels) do
                        if imgui.Selectable(label, m == mIdx) then
                            editSourceMethod = methodTypes[m]
                        end
                    end
                    imgui.EndCombo()
                end

                imgui.Spacing()
                if imgui.Button("Save") then
                    entry.type = editSourceType
                    entry.name = editSourceName
                    entry.method = editSourceMethod
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
    end

    -- Help Window
    if showHelp then
        imgui.SetNextWindowSize(ImVec2(575, 600), ImGuiCond.FirstUseEver)
        imgui.SetNextWindowSizeConstraints(ImVec2(575, 600), ImVec2(800, 2000))
        showHelp = imgui.Begin("Squire Help###SquireHelp", showHelp)
        if showHelp then
            renderWindowBg()

            local headColor = ImVec4(0.6, 0.85, 1.0, 1.0)
            local bodyColor = ImVec4(0.78, 0.74, 0.6, 1.0)

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
            imgui.BulletText(methodLabels[1])
            imgui.Indent()
            imgui.TextWrapped("Equips an item directly on the pet. No items to set up.")
            imgui.Unindent()
            imgui.Spacing()
            imgui.BulletText(methodLabels[2])
            imgui.Indent()
            imgui.TextWrapped("Places an item on your cursor. Squire gives it to the pet.")
            imgui.Unindent()
            imgui.Spacing()
            imgui.BulletText(methodLabels[3])
            imgui.Indent()
            imgui.TextWrapped(
                "Places a bag on your cursor. Squire gives the pet \"Items to Give\" " ..
                "from the bag, and destroys \"Items to Discard\".")
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
                "5. Bag method only: Anything that should be cleaned up afterwards (including the bag) " ..
                "should be added to \"Items to Discard\".")
            imgui.Unindent()
            imgui.PopStyleColor()
        end
        imgui.End()
    end

    imgui.PopStyleVar(5)
end

-- Startup

local function startup()
    settings = utils.loadSettings()
    utils.debugMode = settings.debugMode
    resolvePresets()

    if not getSet(settings.selectedSet) then
        local firstSet = next(settings.sets)
        if firstSet then
            settings.selectedSet = firstSet
        else
            settings.selectedSet = ""
        end
        settingsDirty = true
    end

    -- Auto-class selection on first load (no user sets, default selectedSet)
    if next(settings.sets) == nil and settings.selectedSet == "" then
        local myClass = mq.TLO.Me.Class.ShortName()
        for presetName, classes in pairs(presetClassMap) do
            for _, cls in ipairs(classes) do
                if cls == myClass then
                    settings.selectedSet = presetName
                    settingsDirty = true
                    utils.output("Auto-selected preset '%s' based on class.", presetName)
                    goto classFound
                end
            end
        end
        ::classFound::
    end

    if settings.allowMovement and not mq.TLO.Plugin("mq2nav").IsLoaded() then
        settings.allowMovement = false
        settingsDirty = true
        utils.output("\ayMQ2Nav not loaded - Allow Movement disabled.")
    end

    if settingsDirty then
        utils.saveSettings(settings)
        settingsDirty = false
    end

    utils.output("by \aoAlgar\ax (\a-tgithub.com/AlgarDude/Squire\ax)")
    utils.output("Use \ag/squire help\ax for a list of commands.")
end

-- Main

startup()

mq.imgui.init('Squire', renderUI)
mq.bind('/squire', commandHandler)
mq.event('squireRequest', "#1# tells you, '#2#'", eventHandler)

while mq.TLO.MacroQuest.GameState() == 'INGAME' do
    mq.doevents()

    if settingsDirty then
        utils.saveSettings(settings)
        settingsDirty = false
    end

    processQueue()
    mq.delay(100)
end
