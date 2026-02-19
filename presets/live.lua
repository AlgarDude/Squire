--[[
    Squire - Live/Test Server Presets
    Array of preset definitions with title, classes, and ordered effects (priority groups).
    Each priority group is a list of candidates - first available source wins.
]]

-- Example: clicky bag entry for reference (remove or replace with real data)
-- local exampleSword = { id = 12345, name = "Summoned: Example Sword", icon = 592, }
-- local exampleTrash = { id = 12346, name = "Summoned: Example Hilt", icon = 593, }

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
                        { id = 177691, name = "Summoned: Arcane Fireblade", icon = 13948, },
                        { id = 177691, name = "Summoned: Arcane Fireblade", icon = 13948, },
                        { id = 177692, name = "Summoned: Arcane Iceblade",  icon = 13949, },
                        { id = 177692, name = "Summoned: Arcane Iceblade",  icon = 13949, },
                        { id = 177693, name = "Summoned: Arcane Rageblade", icon = 13951, },
                        { id = 177693, name = "Summoned: Arcane Rageblade", icon = 13951, },
                        { id = 177693, name = "Summoned: Arcane Mindblade", icon = 13952, },
                        { id = 177693, name = "Summoned: Arcane Mindblade", icon = 13952, },
                        { id = 177662, name = "Arcane Weapon Pack",         icon = 12579, },
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
                        { id = 159992, name = "Summoned: Heroic Fireblade", icon = 4030, },
                        { id = 159992, name = "Summoned: Heroic Fireblade", icon = 4030, },
                        { id = 159993, name = "Summoned: Heroic Iceblade",  icon = 4031, },
                        { id = 159993, name = "Summoned: Heroic Iceblade",  icon = 4031, },
                        { id = 159994, name = "Summoned: Heroic Rageblade", icon = 4033, },
                        { id = 159994, name = "Summoned: Heroic Rageblade", icon = 4033, },
                        { id = 159995, name = "Summoned: Heroic Mindblade", icon = 4034, },
                        { id = 159995, name = "Summoned: Heroic Mindblade", icon = 4034, },
                        { id = 159962, name = "Phantom Weapon Pack",        icon = 12579, },
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
                        { id = 124388, name = "Summoned: Shadewrought Fireblade", icon = 10980, },
                        { id = 124388, name = "Summoned: Shadewrought Fireblade", icon = 10980, },
                        { id = 124389, name = "Summoned: Shadewrought Ice Spear", icon = 10981, },
                        { id = 124389, name = "Summoned: Shadewrought Ice Spear", icon = 10981, },
                        { id = 124390, name = "Summoned: Shadewrought Rageaxe",   icon = 10982, },
                        { id = 124390, name = "Summoned: Shadewrought Rageaxe",   icon = 10982, },
                        { id = 124391, name = "Summoned: Shadewrought Mindmace",  icon = 10983, },
                        { id = 124391, name = "Summoned: Shadewrought Mindmace",  icon = 10983, },
                        { id = 57261,  name = "Pouch of Quellious",               icon = 667, },
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
                        { id = 150432, name = "Summoned: Silver Fireblade", icon = 3547, },
                        { id = 150432, name = "Summoned: Silver Fireblade", icon = 3547, },
                        { id = 150433, name = "Summoned: Silver Iceblade",  icon = 3548, },
                        { id = 150433, name = "Summoned: Silver Iceblade",  icon = 3548, },
                        { id = 150434, name = "Summoned: Silver Ragesword", icon = 3549, },
                        { id = 150434, name = "Summoned: Silver Ragesword", icon = 3549, },
                        { id = 150435, name = "Summoned: Silver Mindblade", icon = 3550, },
                        { id = 150435, name = "Summoned: Silver Mindblade", icon = 3550, },
                        { id = 57261,  name = "Pouch of Quellious",         icon = 667, },
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
                        { id = 99817, name = "Summoned: Gorstruck Fireblade", icon = 4770, },
                        { id = 99817, name = "Summoned: Gorstruck Fireblade", icon = 4770, },
                        { id = 99818, name = "Summoned: Gorstruck Iceblade",  icon = 4773, },
                        { id = 99818, name = "Summoned: Gorstruck Iceblade",  icon = 4773, },
                        { id = 99819, name = "Summoned: Gorstruck Ragesword", icon = 4772, },
                        { id = 99819, name = "Summoned: Gorstruck Ragesword", icon = 4772, },
                        { id = 99820, name = "Summoned: Gorstruck Mindblade", icon = 4771, },
                        { id = 99820, name = "Summoned: Gorstruck Mindblade", icon = 4771, },
                        { id = 57261, name = "Pouch of Quellious",            icon = 667, },
                    },
                },
            },
        },
    },
}
