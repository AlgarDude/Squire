--[[
    Squire - Live/Test Server Presets
    Array of preset definitions with title, classes, and ordered effects (priority groups).
    Each priority group is a list of candidates - first available source wins.
]]

-- Example: clicky bag entry for reference (remove or replace with real data)
-- local exampleSword = { id = 12345, name = "Summoned: Example Sword", icon = 592, }
local quelliousPouch = { id = 57261, name = "Pouch of Quellious", icon = 667, }
local phantomSatchel = { id = 17310, name = "Phantom Satchel", icon = 691, }

return {
    {
        title = "Class Preset (Live)",
        classes = { "MAG", },
        effects = {
            { -- Weapons
                {
                    name = "Grant Arcane Armaments",
                    type = "spell",
                    method = "bag",
                    clicky = true,
                    clickyItem = { id = 177689, name = "Folded Pack of Arcane Armaments", icon = 12576, },
                    items = {
                        { id = 177690, name = "Summoned: Arcane Shortsword", icon = 13950, },
                        { id = 177690, name = "Summoned: Arcane Shortsword", icon = 13950, },
                    },
                    trashItems = {
                        { id = 177662, name = "Arcane Weapon Pack", icon = 12579, },
                    },
                },
                {
                    name = "Grant Goliath's Armaments",
                    type = "spell",
                    method = "bag",
                    clicky = true,
                    clickyItem = { id = 159990, name = "Folded Pack of Goliath's Armaments", icon = 12576, },
                    items = {
                        { id = 159991, name = "Summoned: Heroic Shortsword", icon = 4029, },
                        { id = 159991, name = "Summoned: Heroic Shortsword", icon = 4029, },
                    },
                    trashItems = {
                        { id = 159962, name = "Phantom Weapon Pack", icon = 12579, },
                    },
                },
                {
                    name = "Grant Shak Dathor's Armaments",
                    type = "spell",
                    method = "bag",
                    clicky = true,
                    clickyItem = { id = 124386, name = "Folded Pack of Shak Dathor's Armaments", icon = 1933, },
                    items = {
                        { id = 124387, name = "Summoned: Shadewrought Staff", icon = 10979, },
                        { id = 124387, name = "Summoned: Shadewrought Staff", icon = 10979, },
                    },
                    trashItems = {
                        quelliousPouch,
                    },
                },
                {
                    name = "Grant Yalrek's Armaments",
                    type = "spell",
                    method = "bag",
                    clicky = true,
                    clickyItem = { id = 150430, name = "Folded Pack of Yalrek's Armaments", icon = 1933, },
                    items = {
                        { id = 150431, name = "Summoned: Silver Shortsword", icon = 3546, },
                        { id = 150431, name = "Summoned: Silver Shortsword", icon = 3546, },
                    },
                    trashItems = {
                        quelliousPouch,
                    },
                },
                {
                    name = "Grant Wirn's Armaments",
                    type = "spell",
                    method = "bag",
                    clicky = true,
                    clickyItem = { id = 93699, name = "Folded Pack of Wirn's Armaments", icon = 1933, },
                    items = {
                        { id = 99816, name = "Summoned: Gorstruck Shortsword", icon = 4769, },
                        { id = 99816, name = "Summoned: Gorstruck Shortsword", icon = 4769, },
                    },
                    trashItems = {
                        quelliousPouch,
                    },
                },
                {
                    name = "Grant Thassis's Armaments",
                    type = "spell",
                    method = "bag",
                    clicky = true,
                    clickyItem = { id = 99809, name = "Folded Pack of Thalassic Armaments", icon = 1931, },
                    items = {
                        { id = 99796, name = "Summoned: Thalassic Shortsword", icon = 4769, },
                        { id = 99796, name = "Summoned: Thalassic Shortsword", icon = 4769, },
                    },
                    trashItems = {
                        quelliousPouch,
                    },
                },
                {
                    name = "Grant Frightforged Armaments",
                    type = "spell",
                    method = "bag",
                    clicky = true,
                    clickyItem = { id = 76529, name = "Folded Pack of Frightforged Armaments", icon = 1931, },
                    items = {
                        { id = 76516, name = "Summoned: Frightforged Shortsword", icon = 4769, },
                        { id = 76516, name = "Summoned: Frightforged Shortsword", icon = 4769, },
                    },
                    trashItems = {
                        quelliousPouch,
                    },
                },
                {
                    name = "Grant Manaforged Armaments",
                    type = "spell",
                    method = "bag",
                    clicky = true,
                    clickyItem = { id = 64977, name = "Folded Pack of Manaforged Armaments", icon = 1931, },
                    items = {
                        { id = 64964, name = "Summoned: Manaforged Shortsword", icon = 4029, },
                        { id = 64964, name = "Summoned: Manaforged Shortsword", icon = 4029, },
                    },
                    trashItems = {
                        quelliousPouch,
                    },
                },
                {
                    name = "Grant Spectral Armaments",
                    type = "spell",
                    method = "bag",
                    clicky = true,
                    clickyItem = { id = 57295, name = "Folded Pack of Spectral Armaments", icon = 1930, },
                    items = {
                        { id = 57278, name = "Summoned: Spectral Shortsword", icon = 3546, },
                        { id = 57278, name = "Summoned: Spectral Shortsword", icon = 3546, },
                    },
                    trashItems = {
                        quelliousPouch,
                    },
                },
                {
                    name = "Summon Ethereal Armaments",
                    type = "spell",
                    method = "bag",
                    items = {
                        { id = 52833, name = "Summoned: Winterbane", icon = 1773, },
                        { id = 52833, name = "Summoned: Winterbane", icon = 1773, },
                    },
                    trashItems = {
                        quelliousPouch,
                    },
                },
                {
                    name = "Summon Prime Armaments",
                    type = "spell",
                    method = "bag",
                    items = {
                        { id = 52833, name = "Summoned: Winterbane", icon = 1773, },
                        { id = 52833, name = "Summoned: Winterbane", icon = 1773, },
                    },
                    trashItems = {
                        quelliousPouch,
                    },
                },
                {
                    name = "Summon Elemental Armaments",
                    type = "spell",
                    method = "bag",
                    items = {
                        { id = 52664, name = "Summoned: Icefall Icicle", icon = 1816, },
                        { id = 52664, name = "Summoned: Icefall Icicle", icon = 1816, },
                    },
                    trashItems = {
                        quelliousPouch,
                    },
                },
                {
                    name = "Summon Fang",
                    type = "spell",
                    method = "cursor",
                    items = { { id = 7313, name = "Summoned: Snake Fang", icon = 801, }, },
                },
                {
                    name = "Summon Dagger",
                    type = "spell",
                    method = "cursor",
                    items = { { id = 7305, name = "Summoned: Dagger", icon = 592, }, },
                },
            },
        },
    },
}
