--[[
    Squire - Live/Test Server Presets
    Array of preset definitions with title, classes, and ordered effects (priority groups).
    Each priority group is a list of candidates — first available source wins.
]]

return {
    -- Example preset (uncomment and fill in with real spell/AA/item names):
    --[[
    {
        title = "Mage Default",
        classes = { "MAG" },
        effects = {
            -- Priority group 1: Armor (bag method — one cast produces 7 pieces)
            {
                { name = "Grant Spectral Plate", type = "spell", method = "bag",
                  items = { { id = 123 }, { id = 124 }, { id = 125 }, { id = 126 }, { id = 127 }, { id = 128 }, { id = 129 } },
                  trashItems = { { id = 999 } } },
                { name = "Grant Ethereal Plate", type = "spell", method = "bag",
                  items = { { id = 200 }, { id = 201 }, { id = 202 }, { id = 203 }, { id = 204 }, { id = 205 }, { id = 206 } },
                  trashItems = { { id = 998 } } },
            },
            -- Priority group 2: Weapons (bag method)
            {
                { name = "Grant Spectral Armaments", type = "spell", method = "bag",
                  items = { { id = 131 }, { id = 133 } },
                  trashItems = { { id = 132 } } },
            },
            -- Priority group 3: Mask (cursor method — AA summons to cursor)
            {
                { name = "Summon Companion Mask", type = "aa", method = "cursor",
                  items = { { id = 130 } } },
            },
            -- Priority group 4: Belt (direct method — spell targets pet)
            {
                { name = "Grant Engraved Belt", type = "spell", method = "direct" },
            },
        },
    },
    ]]
}
