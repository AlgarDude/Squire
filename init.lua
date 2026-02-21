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

local version = "0.9beta"

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
    { key = "anyone",     label = "Anyone", },
    { key = "group",      label = "Group Only", },
    { key = "raid",       label = "Raid Only", },
    { key = "fellowship", label = "Fellowship Only", },
    { key = "allowlist",  label = "Allow List", },
    { key = "denylist",   label = "Deny List", },
}

-- UI Temp State

local showSettings = false
local showEditSets = false
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

local function resolvePresets()
    presetSets = {}
    presetClassMap = {}

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
        end
    end
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

    -- Add presets not overridden by user sets (class filtering already done in resolvePresets)
    local presetNames = {}
    for name in pairs(presetSets) do
        if not settings.sets[name] then
            table.insert(presetNames, name)
        end
    end
    table.sort(presetNames)
    for _, name in ipairs(presetNames) do
        table.insert(names, name)
    end
    return names
end

-- Core Arm Logic

local function armPet(playerName, setName, fromTell)
    if aborted then
        utils.output("\arArming halted due to inventory error. Please resolve and use /squire reset.")
        return false
    end

    -- Resolve set
    setName = setName or settings.selectedSet
    local set = getSet(setName)

    if not set then
        utils.output("\arSet '%s' not found.", setName)
        if fromTell then
            mq.cmdf('/tell %s Set "%s" not found.', playerName, setName)
        end
        return true
    end

    -- Find pet
    local petSpawn = mq.TLO.Spawn("pc " .. playerName).Pet

    if not petSpawn() or not petSpawn.ID() or petSpawn.ID() == 0 then
        utils.output("\ay%s does not have a pet.", playerName)
        if fromTell then
            mq.cmdf("/tell %s You do not appear to have a pet.", playerName)
        end
        return true
    end

    -- Range check
    if (petSpawn.Distance3D() or 999) > 20 then
        if settings.allowMovement then
            if not delivery.navToPet(petSpawn) then
                utils.output("\ayCould not reach %s pet. Skipping.", petDisplayName(playerName))
                if fromTell then
                    mq.cmdf("/tell %s Your pet is out of range and I could not reach it.", playerName)
                end
                return true
            end
        else
            utils.output("\ay%s pet is out of range (%.0f). Skipping.", petDisplayName(playerName), petSpawn.Distance3D() or 999)
            if fromTell then
                mq.cmdf("/tell %s Your pet is out of range.", playerName)
            end
            return true
        end
    end

    -- Clear cursor
    local hasBagMethod = false
    for _, entry in ipairs(set) do
        if entry.enabled and entry.method == "bag" then
            hasBagMethod = true
            break
        end
    end
    local cursorResult = utils.clearCursor(hasBagMethod)
    if cursorResult == "abort" then
        utils.output("\arCursor stuck. Aborting.")
        return false
    end

    -- Free top slot for bag methods
    local freeSlot
    if hasBagMethod then
        freeSlot = utils.ensureFreeTopSlot()
        if freeSlot == "abort" then
            utils.output("\arCannot free a top-level slot. Aborting.")
            return false
        end
    end

    -- Prepare spells
    if not casting.prepareSpells(set) then
        utils.output("\arFailed to prepare spells for set '%s'.", setName)
        return false
    end

    -- Execute delivery for each enabled source entry in order
    local results = {}
    local abortFunc = function() return stopRequested end

    for i, entry in ipairs(set) do
        if entry.enabled then
            if stopRequested then break end

            -- Re-check pet existence
            if not petSpawn() then
                utils.output("\ayPet no longer exists. Skipping remaining sources.")
                break
            end

            -- Re-check pet range
            if (petSpawn.Distance3D() or 999) > 20 then
                if settings.allowMovement then
                    if not delivery.navToPet(petSpawn) then
                        utils.output("\ayPet moved out of range. Skipping remaining sources.")
                        break
                    end
                else
                    utils.output("\ayPet out of range. Skipping remaining sources.")
                    break
                end
            end

            -- Verify freeSlot if bag method
            if entry.method == "bag" and freeSlot and mq.TLO.InvSlot("pack" .. freeSlot).Item.ID() then
                utils.output("\arFree slot pack%d still occupied. Skipping %s.", freeSlot, entry.name)
                results[i] = false
            else
                local success = false
                if entry.method == "direct" then
                    success = delivery.deliverDirect(entry, petSpawn, abortFunc)
                elseif entry.method == "cursor" then
                    success = delivery.deliverCursor(entry, petSpawn, abortFunc)
                elseif entry.method == "bag" then
                    success = delivery.deliverBag(entry, petSpawn, freeSlot, abortFunc)
                elseif entry.method == "trade" then
                    success = delivery.deliverTrade(entry, petSpawn)
                end
                results[i] = success
            end
        end
    end

    -- Report result
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

    if #failed > 0 then
        utils.debugOutput("Processed %d/%d sources for %s pet. (Set: %s) Failed: %s", passed, total, petDisplayName(playerName), setName, table.concat(failed, ", "))
    else
        utils.debugOutput("Processed %d/%d sources for %s pet. (Set: %s)", passed, total, petDisplayName(playerName), setName)
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

-- Queue & Processing

local function addToQueue(playerName, setName, fromTell)
    if aborted then
        utils.output("\arArming halted due to inventory error. Please resolve and use /squire reset.")
        return
    end

    if queuedNames:contains(playerName:lower()) then return end

    queuedNames:add(playerName:lower())
    table.insert(queue, {
        playerName = playerName,
        setName = setName,
        fromTell = fromTell or false,
    })
end

local function saveCurrentGems()
    local gems = {}
    for i = 1, me.NumGems() do
        gems[i] = me.Gem(i)() or ""
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
            queuedNames = Set.new({})
            break
        end

        local request = table.remove(queue, 1)
        queuedNames:remove(request.playerName:lower())
        processed = processed + 1
        statusText = string.format("Arming pet %d/%d: %s pet...", processed, processed + #queue, petDisplayName(request.playerName))

        local result = armPet(request.playerName, request.setName, request.fromTell)

        if not result then
            aborted = true
            queue = {}
            queuedNames = Set.new({})
            break
        end
    end

    -- Cleanup: clear cursor if anything is on it
    if mq.TLO.Cursor.ID() then
        mq.cmd("/autoinventory")
        mq.delay(3000, function() return not mq.TLO.Cursor.ID() end)
        if mq.TLO.Cursor.ID() then
            utils.output("\arCursor still stuck after autoinventory. Aborting.")
            aborted = true
        end
    end

    -- Restore spells when queue is empty
    if savedGems then
        casting.restoreSpells(savedGems)
        savedGems = nil
    end

    delivery.navToStart(settings.allowMovement)
    delivery.clearStartPosition()

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
    elseif settings.tellAccess == "fellowship" then
        if me.Fellowship.ID() == 0 then return false end
        local member = me.Fellowship.Member(senderName)
        return member() ~= nil
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

-- Command System

local function queuePetOwners(getMember, count, setName)
    for i = 1, count do
        local member = getMember(i)
        if member() and member.Name() then
            local memberSpawn = mq.TLO.Spawn("pc " .. member.Name())
            if memberSpawn() and memberSpawn.Pet() and memberSpawn.Pet.ID() > 0 then
                addToQueue(member.Name(), setName, false)
            end
        end
    end
end

local commandOrder = { "arm", "stop", "show", "hide", "debug", "reset", "help", }

local commands
commands = {
    arm = {
        usage = "/squire arm <scope> [set]",
        about = "Arm pets (self/target/group/raid/PlayerName)",
        handler = function(args)
            local scope = args[2] and args[2]:lower() or ""
            local setName = joinArgs(args, 3)

            if scope == "self" then
                addToQueue(me.Name(), setName, false)
            elseif scope == "target" then
                local t = mq.TLO.Target
                if not t() or t.Type() ~= "PC" then
                    utils.output("\ayTarget is not a PC.")
                elseif not t.Pet() or t.Pet.ID() == 0 then
                    utils.output("\ay%s does not have a pet.", t.Name())
                else
                    addToQueue(t.Name(), setName, false)
                end
            elseif scope == "group" then
                queuePetOwners(mq.TLO.Group.Member, (mq.TLO.Group.GroupSize() or 1) - 1, setName)
            elseif scope == "raid" then
                queuePetOwners(mq.TLO.Raid.Member, mq.TLO.Raid.Members() or 0, setName)
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
            queue = {}
            queuedNames = Set.new({})
            utils.output("Stop requested. Clearing queue.")
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
            showUI = false
        end,
    },
    debug = {
        usage = "/squire debug [on|off]",
        about = "Toggle debug logging",
        handler = function(args)
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
        end,
    },
    reset = {
        usage = "/squire reset",
        about = "Clear aborted state and reset status",
        handler = function(args)
            aborted = false
            statusText = "Idle"
            utils.output("Reset complete. Ready to arm.")
        end,
    },
    help = {
        usage = "/squire help",
        about = "Show this help",
        handler = function(args)
            utils.output("Commands:")
            for _, name in ipairs(commandOrder) do
                local cmd = commands[name]
                utils.output("  %s - %s", cmd.usage, cmd.about)
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

local function renderWindowBg()
    if not bgTexture then return end
    local startPos = imgui.GetCursorPosVec()
    local availW, availH = imgui.GetContentRegionAvail()
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
            editSourceClicky = entry.clicky or false
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

local function renderUI()
    if not showUI then return end

    imgui.PushStyleVar(ImGuiStyleVar.FrameRounding, 4)
    imgui.PushStyleVar(ImGuiStyleVar.WindowRounding, 6)
    imgui.PushStyleVar(ImGuiStyleVar.ChildRounding, 4)
    imgui.PushStyleVar(ImGuiStyleVar.PopupRounding, 4)
    imgui.PushStyleVar(ImGuiStyleVar.GrabRounding, 4)

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
            addToQueue(me.Name(), nil, false)
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

        if isArming then
            if imgui.Button("Stop") then
                stopRequested = true
                queue = {}
                queuedNames = Set.new({})
                utils.output("Stop requested. Clearing queue.")
            end
        end

        if imgui.CollapsingHeader("History") then
            local _, availY = imgui.GetContentRegionAvail()
            imgui.BeginChild("##HistoryScroll", ImVec2(0, availY - imgui.GetFrameHeightWithSpacing()), 0)
            for _, histEntry in ipairs(armHistory) do
                imgui.TextColored(0.4, 0.8, 0.4, 1, string.format("[%s]", histEntry.timestamp))
                imgui.SameLine(0, 4)
                if #histEntry.failed > 0 then
                    imgui.TextWrapped(string.format("Processed %d/%d sources for %s pet. (Set: %s) Failed: %s",
                        histEntry.passed, histEntry.total, petDisplayName(histEntry.playerName), histEntry.setName,
                        table.concat(histEntry.failed, ", ")))
                else
                    imgui.TextWrapped(string.format("Processed %d/%d sources for %s pet. (Set: %s)",
                        histEntry.passed, histEntry.total, petDisplayName(histEntry.playerName), histEntry.setName))
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

    -- Settings Window
    if showSettings then
        imgui.SetNextWindowSize(ImVec2(445, 465), ImGuiCond.FirstUseEver)
        imgui.SetNextWindowSizeConstraints(ImVec2(445, 465), ImVec2(800, 2000))
        local settingsDraw
        showSettings, settingsDraw = imgui.Begin("Squire Settings###SquireSettings", showSettings)
        if settingsDraw then
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
                local example = settings.triggerWord ~= "" and settings.triggerWord or "squire"
                imgui.SetTooltip(string.format("If you receive a tell with this keyword, you will arm the sender's pet.\nTell example: /tell YourName %s [Set Name]", example))
            end
            if changed then
                settings.triggerWord = tw
                settingsDirty = true
            end

            local taIndex = findIndex(tellAccessOptions, settings.tellAccess)
            imgui.Text("Tell Access:")
            imgui.SameLine()
            imgui.SetNextItemWidth(150)
            if imgui.BeginCombo("##tellAccess", tellAccessOptions[taIndex].label) then
                for _, opt in ipairs(tellAccessOptions) do
                    if imgui.Selectable(opt.label, opt.key == settings.tellAccess) then
                        settings.tellAccess = opt.key
                        settingsDirty = true
                    end
                end
                imgui.EndCombo()
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

            if not delivery.navLoaded then imgui.BeginDisabled() end
            settings.allowMovement, changed = imgui.Checkbox("Allow Movement", settings.allowMovement)
            if imgui.IsItemHovered(ImGuiHoveredFlags.AllowWhenDisabled) then
                if delivery.navLoaded then
                    imgui.SetTooltip("Allow this PC to move up to 100 feet to arm a pet. Will return to the original location when complete.")
                else
                    imgui.SetTooltip("MQ2Nav is not loaded - navigation features are unavailable.")
                end
            end
            if changed then
                settingsDirty = true
            end
            if not delivery.navLoaded then
                settings.allowMovement = false
                imgui.EndDisabled()
            end
            imgui.SameLine(0, 30)
            settings.debugMode, changed = imgui.Checkbox("Debug Logging", settings.debugMode)
            if changed then
                utils.debugMode = settings.debugMode
                settingsDirty = true
            end

            local headColor = ImVec4(0.6, 0.85, 1.0, 1.0)
            local bodyColor = ImVec4(0.78, 0.74, 0.6, 1.0)

            imgui.NewLine()
            imgui.PushStyleColor(ImGuiCol.Text, headColor)
            imgui.SeparatorText("Commands")
            imgui.PopStyleColor()
            imgui.Spacing()
            local _, availY = imgui.GetContentRegionAvail()
            imgui.BeginChild("##CommandsScroll", ImVec2(0, availY - 80), 0)
            imgui.PushStyleColor(ImGuiCol.Text, bodyColor)
            for _, name in ipairs(commandOrder) do
                local cmd = commands[name]
                imgui.Bullet()
                imgui.TextWrapped(string.format("%s - %s", cmd.usage, cmd.about))
            end
            imgui.PopStyleColor()
            imgui.EndChild()

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

    -- Manage Sets Window
    if showEditSets then
        imgui.SetNextWindowSize(ImVec2(520, 450), ImGuiCond.FirstUseEver)
        imgui.SetNextWindowSizeConstraints(ImVec2(520, 200), ImVec2(800, 2000))
        local editSetsDraw
        showEditSets, editSetsDraw = imgui.Begin("Manage Sets###SquireEditSets", showEditSets)
        if editSetsDraw then
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
                imgui.Text(string.format("Copy '%s' as:", settings.selectedSet))
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
                                        clicky = entry.clicky or false,
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
                imgui.Text(string.format("Rename '%s' to:", settings.selectedSet))
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
                imgui.Text(string.format("Delete '%s'?", settings.selectedSet))
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
                                local iconPos = imgui.GetCursorScreenPosVec()
                                imgui.Dummy(16, 16)
                                local drawList = imgui.GetWindowDrawList()
                                animItems:SetTextureCell(entry.clickyItem.icon - 500)
                                drawList:AddTextureAnimation(animItems, iconPos, ImVec2(16, 16))
                                imgui.SameLine()
                            end
                            imgui.Text(entry.clickyItem.name)
                            imgui.Spacing()
                        end

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

                        if entry.method == "bag" or entry.method == "cursor" then
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
                        imgui.Text(string.format("Remove '%s'?", entryName))
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

    -- Add Source Window
    if showAddSource then
        local currentSet = getSet(settings.selectedSet)
        if not currentSet or isPresetSet(settings.selectedSet) or isArming then
            showAddSource = false
        else
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
                imgui.SetNextItemWidth(250)
                newSourceName = imgui.InputTextWithHint("##newName", "Exact In-Game Name", newSourceName)

                if newSourceMethod == "bag" then
                    newSourceClicky = imgui.Checkbox("Source produces clicky item", newSourceClicky)
                    if newSourceClicky then
                        imgui.Text("Clicky Item:")
                        imgui.SameLine()
                        if newSourceClickyItem then
                            if newSourceClickyItem.icon then
                                local iconPos = imgui.GetCursorScreenPosVec()
                                imgui.Dummy(16, 16)
                                local drawList = imgui.GetWindowDrawList()
                                animItems:SetTextureCell(newSourceClickyItem.icon - 500)
                                drawList:AddTextureAnimation(animItems, iconPos, ImVec2(16, 16))
                                imgui.SameLine()
                            end
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
    end

    -- Edit Source Window
    if editingIdx then
        local currentSet = getSet(settings.selectedSet)
        local entry = currentSet and currentSet[editingIdx]
        if not entry or isPresetSet(settings.selectedSet) or isArming then
            editingIdx = nil
        else
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
                imgui.SetNextItemWidth(250)
                editSourceName = imgui.InputTextWithHint("##editName", "Exact In-Game Name", editSourceName)

                if editSourceMethod == "bag" then
                    editSourceClicky = imgui.Checkbox("Source produces clicky item", editSourceClicky)
                    if editSourceClicky then
                        imgui.Text("Clicky Item:")
                        imgui.SameLine()
                        if editSourceClickyItem then
                            if editSourceClickyItem.icon then
                                local iconPos = imgui.GetCursorScreenPosVec()
                                imgui.Dummy(16, 16)
                                local drawList = imgui.GetWindowDrawList()
                                animItems:SetTextureCell(editSourceClickyItem.icon - 500)
                                drawList:AddTextureAnimation(animItems, iconPos, ImVec2(16, 16))
                                imgui.SameLine()
                            end
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
    end

    -- Help Window
    if showHelp then
        imgui.SetNextWindowSize(ImVec2(575, 600), ImGuiCond.FirstUseEver)
        imgui.SetNextWindowSizeConstraints(ImVec2(575, 600), ImVec2(800, 2000))
        local helpDraw
        showHelp, helpDraw = imgui.Begin("Squire Help###SquireHelp", showHelp)
        if helpDraw then
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
        local found = false
        for presetName, classes in pairs(presetClassMap) do
            for _, class in ipairs(classes) do
                if class == myClass then
                    settings.selectedSet = presetName
                    settingsDirty = true
                    utils.output("Auto-selected preset '%s' based on class.", presetName)
                    found = true
                    break
                end
            end
            if found then break end
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

    utils.output("by \aoAlgar\ax (\a-tgithub.com/AlgarDude/Squire\ax)")
    utils.output("Use \ag/squire help\ax for a list of commands.")
end

-- Main

startup()

mq.imgui.init('Squire', renderUI)
mq.bind('/squire', commandHandler)
mq.event('squireRequest', "#1# tells you, '#2#'", function(line, sender, message)
    if not message then return end
    local trimmed = message:gsub("^%s+", ""):gsub("%s+$", "")
    local triggerLower = settings.triggerWord:lower()

    if trimmed:lower():find(triggerLower, 1, true) ~= 1 then return end
    if not isAllowedSender(sender) then return end

    local afterTrigger = trimmed:sub(#settings.triggerWord + 1):gsub("^%s+", ""):gsub("%s+$", "")
    addToQueue(sender, afterTrigger ~= "" and afterTrigger or nil, true)
end)

while mq.TLO.MacroQuest.GameState() == 'INGAME' do
    mq.doevents()

    -- Detect persona class change
    if not isArming and me.Class.ShortName() ~= myClass then
        myClass = me.Class.ShortName()
        settings = utils.loadSettings()
        resolvePresets()
        if not getSet(settings.selectedSet) then
            settings.selectedSet = next(settings.sets) or ""
        end
        settingsDirty = true
    end

    if settingsDirty then
        utils.saveSettings(settings)
        settingsDirty = false
    end

    processQueue()
    mq.delay(100)
end
