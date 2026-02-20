--[[
    Squire - Live/Test Server Presets
    Array of preset definitions with title, classes, and ordered effects (priority groups).
    Each priority group is a list of candidates - first available source wins.
]]

-- Example: clicky bag entry for reference (remove or replace with real data)
-- local exampleSword = { id = 12345, name = "Summoned: Example Sword", icon = 592, }
local quelliousPouch = { id = 57261, name = "Pouch of Quellious", icon = 667, }
local phantomSatchel = { id = 17310, name = "Phantom Satchel", icon = 691, }
local phantomSatchel2 = { id = 57262, name = "Phantom Satchel", icon = 691, }

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
            { -- Armor
                {
                    name = "Grant Arcane Plate",
                    type = "spell",
                    method = "bag",
                    clicky = true,
                    clickyItem = { id = 177689, name = "Folded Pack of Arcane Plate", icon = 12575, },
                    items = {
                        { id = 177674, name = "Summoned: Arcane Plate Helm",        icon = 12562, },
                        { id = 177675, name = "Summoned: Arcane Plate Vambraces",   icon = 12564, },
                        { id = 177676, name = "Summoned: Arcane Plate Gauntlets",   icon = 12566, },
                        { id = 177677, name = "Summoned: Arcane Plate Boots",       icon = 12568, },
                        { id = 177678, name = "Summoned: Arcane Plate Bracers",     icon = 12565, },
                        { id = 177679, name = "Summoned: Arcane Plate Breastplate", icon = 12563, },
                        { id = 177680, name = "Summoned: Arcane Plate Greaves",     icon = 12567, },
                        { id = 177681, name = "Summoned: Arcane Belt",              icon = 5064, },
                    },
                    trashItems = {
                        { id = 177675, name = "Arcane Armor Pack", icon = 12578, },
                    },
                },
                {
                    name = "Grant the Alloy's Plate",
                    type = "spell",
                    method = "bag",
                    clicky = true,
                    clickyItem = { id = 159974, name = "Folded Pack of the Alloy's Plate", icon = 12575, },
                    items = {
                        { id = 159975, name = "Summoned: Etched Alloy Plate Helm",        icon = 12562, },
                        { id = 159976, name = "Summoned: Etched Alloy Plate Vambraces",   icon = 12564, },
                        { id = 159977, name = "Summoned: Etched Alloy Plate Gauntlets",   icon = 12566, },
                        { id = 159978, name = "Summoned: Etched Alloy Plate Boots",       icon = 12568, },
                        { id = 159979, name = "Summoned: Etched Alloy Plate Bracers",     icon = 12565, },
                        { id = 159980, name = "Summoned: Etched Alloy Plate Breastplate", icon = 12563, },
                        { id = 159981, name = "Summoned: Etched Alloy Plate Greaves",     icon = 12567, },
                        { id = 159982, name = "Summoned: Etched Alloy Belt",              icon = 719, },
                    },
                    trashItems = {
                        { id = 159960, name = "Phantom Armor Pack", icon = 12578, },
                    },
                },
                {
                    name = "Grant the Centien's Plate",
                    type = "spell",
                    method = "bag",
                    clicky = true,
                    clickyItem = { id = 124370, name = "Folded Pack of the Centien's Plate", icon = 1930, },
                    items = {
                        { id = 124371, name = "Etched Luclinite Plate Helm",        icon = 550, },
                        { id = 124372, name = "Etched Luclinite Plate Vambraces",   icon = 622, },
                        { id = 124373, name = "Etched Luclinite Plate Gauntlets",   icon = 531, },
                        { id = 124374, name = "Etched Luclinite Plate Boots",       icon = 524, },
                        { id = 124375, name = "Etched Luclinite Plate Bracers",     icon = 516, },
                        { id = 124376, name = "Etched Luclinite Plate Breastplate", icon = 624, },
                        { id = 124377, name = "Etched Luclinite Plate Greaves",     icon = 540, },
                        { id = 124378, name = "Summoned: Etched Luclinite Belt",    icon = 501, },
                    },
                    trashItems = {
                        phantomSatchel2,
                    },
                },
                {
                    name = "Grant Ocoenydd's Plate",
                    type = "spell",
                    method = "bag",
                    clicky = true,
                    clickyItem = { id = 150411, name = "Folded Pack of Ocoenydd's Plate", icon = 1930, },
                    items = {
                        { id = 150412, name = "Etched Iron Plate Helm",        icon = 550, },
                        { id = 150413, name = "Etched Iron Plate Vambraces",   icon = 622, },
                        { id = 150414, name = "Etched Iron Plate Gauntlets",   icon = 531, },
                        { id = 150415, name = "Etched Iron Plate Boots",       icon = 524, },
                        { id = 150416, name = "Etched Iron Plate Bracers",     icon = 516, },
                        { id = 150417, name = "Etched Iron Plate Breastplate", icon = 624, },
                        { id = 150418, name = "Etched Iron Plate Greaves",     icon = 540, },
                        { id = 150419, name = "Summoned: Etched Iron Belt",    icon = 501, },
                    },
                    trashItems = {
                        phantomSatchel2,
                    },
                },
                {
                    name = "Grant Wirn's Plate",
                    type = "spell",
                    method = "bag",
                    clicky = true,
                    clickyItem = { id = 76549, name = "Folded Pack of Wirn's Plate", icon = 1930, },
                    items = {
                        { id = 76541, name = "Magmaforged Plate Helm",        icon = 550, },
                        { id = 76542, name = "Magmaforged Plate Vambraces",   icon = 622, },
                        { id = 76543, name = "Magmaforged Plate Gauntlets",   icon = 531, },
                        { id = 76544, name = "Magmaforged Plate Boots",       icon = 524, },
                        { id = 76545, name = "Magmaforged Plate Bracers",     icon = 516, },
                        { id = 76546, name = "Magmaforged Plate Breastplate", icon = 624, },
                        { id = 76547, name = "Magmaforged Plate Greaves",     icon = 540, },
                        { id = 76548, name = "Summoned: Magmaforged Belt",    icon = 501, },
                    },
                    trashItems = {
                        phantomSatchel2,
                    },
                },
                {
                    name = "Grant Thassis' Plate",
                    type = "spell",
                    method = "bag",
                    clicky = true,
                    clickyItem = { id = 99807, name = "Folded Pack of Thalassic Plate", icon = 1935, },
                    items = {
                        { id = 99788, name = "Thalassic Plate Helm",        icon = 550, },
                        { id = 99789, name = "Thalassic Plate Vambraces",   icon = 622, },
                        { id = 99790, name = "Thalassic Plate Gauntlets",   icon = 531, },
                        { id = 99791, name = "Thalassic Plate Boots",       icon = 524, },
                        { id = 99792, name = "Thalassic Plate Bracers",     icon = 516, },
                        { id = 99793, name = "Thalassic Plate Breastplate", icon = 624, },
                        { id = 99794, name = "Thalassic Plate Greaves",     icon = 540, },
                        { id = 99795, name = "Summoned: Thalassic Belt",    icon = 501, },
                    },
                    trashItems = {
                        phantomSatchel2,
                    },
                },
                {
                    name = "Grant Frightforged Plate",
                    type = "spell",
                    method = "cursor",
                    items = {
                        { id = 76508, name = "Frightforged Plate Helm",        icon = 550, },
                        { id = 76509, name = "Frightforged Plate Vambraces",   icon = 622, },
                        { id = 76510, name = "Frightforged Plate Gauntlets",   icon = 531, },
                        { id = 76511, name = "Frightforged Plate Boots",       icon = 524, },
                        { id = 76512, name = "Frightforged Plate Bracers",     icon = 516, },
                        { id = 76513, name = "Frightforged Plate Breastplate", icon = 624, },
                        { id = 76514, name = "Frightforged Plate Greaves",     icon = 540, },
                        { id = 76515, name = "Summoned: Frightforged Belt",    icon = 501, },
                    },
                    trashItems = {
                        phantomSatchel2,
                    },
                },
                {
                    name = "Grant Manaforged Plate",
                    type = "spell",
                    method = "bag",
                    clicky = true,
                    clickyItem = { id = 64975, name = "Folded Pack of Manaforged Plate", icon = 1935, },
                    items = {
                        { id = 64956, name = "Manaforged Plate Helm",        icon = 550, },
                        { id = 64957, name = "Manaforged Plate Vambraces",   icon = 622, },
                        { id = 64958, name = "Manaforged Plate Gauntlets",   icon = 531, },
                        { id = 64959, name = "Manaforged Plate Boots",       icon = 524, },
                        { id = 64960, name = "Manaforged Plate Bracers",     icon = 516, },
                        { id = 64961, name = "Manaforged Plate Breastplate", icon = 624, },
                        { id = 64962, name = "Manaforged Plate Greaves",     icon = 540, },
                        { id = 64963, name = "Summoned: Manaforged Belt",    icon = 501, },
                    },
                    trashItems = {
                        phantomSatchel2,
                    },
                },
                {
                    name = "Grant Spectral Plate",
                    type = "spell",
                    method = "bag",
                    clicky = true,
                    clickyItem = { id = 57293, name = "Folded Pack of Spectral Plate", icon = 1937, },
                    items = {
                        { id = 57269, name = "Spectral Plate Helm",        icon = 550, },
                        { id = 57270, name = "Spectral Plate Vambraces",   icon = 622, },
                        { id = 57271, name = "Spectral Plate Gauntlets",   icon = 531, },
                        { id = 57272, name = "Spectral Plate Boots",       icon = 524, },
                        { id = 57273, name = "Spectral Plate Bracers",     icon = 516, },
                        { id = 57274, name = "Spectral Plate Breastplate", icon = 624, },
                        { id = 57275, name = "Spectral Plate Greaves",     icon = 540, },
                        { id = 57277, name = "Summoned: Spectral Belt",    icon = 501, },
                    },
                    trashItems = {
                        phantomSatchel2,
                    },
                },
                {
                    name = "Summon Plate of the Prime",
                    type = "spell",
                    method = "bag",
                    items = {
                        { id = 52714, name = "Prime Plate Helm",        icon = 550, },
                        { id = 52715, name = "Prime Plate Vambraces",   icon = 622, },
                        { id = 52716, name = "Prime Plate Gauntlets",   icon = 531, },
                        { id = 52717, name = "Prime Plate Boots",       icon = 524, },
                        { id = 52718, name = "Prime Plate Bracers",     icon = 516, },
                        { id = 52719, name = "Prime Plate Breastplate", icon = 624, },
                        { id = 52720, name = "Prime Plate Greaves",     icon = 540, },
                        { id = 52722, name = "Summoned: Prime Belt",    icon = 501, },
                    },
                    trashItems = {
                        phantomSatchel,
                    },
                },
                {
                    name = "Summon Plate of the Elements",
                    type = "spell",
                    method = "bag",
                    items = {
                        { id = 46980, name = "Eidolon Plate Helm",        icon = 550, },
                        { id = 46981, name = "Eidolon Plate Vambraces",   icon = 622, },
                        { id = 46982, name = "Eidolon Plate Gauntlets",   icon = 531, },
                        { id = 46983, name = "Eidolon Plate Boots",       icon = 524, },
                        { id = 46984, name = "Eidolon Plate Bracers",     icon = 516, },
                        { id = 46985, name = "Eidolon Plate Breastplate", icon = 624, },
                        { id = 46986, name = "Eidolon Plate Greaves",     icon = 540, },
                        { id = 46988, name = "Summoned: Lucid Belt",      icon = 501, },
                    },
                    trashItems = {
                        phantomSatchel,
                    },
                },
                {
                    name = "Summon Phantom Plate",
                    type = "spell",
                    method = "bag",
                    items = {
                        { id = 3419, name = "Phantom Plate Helm",      icon = 550, },
                        { id = 3420, name = "Phantom Breastplate",     icon = 624, },
                        { id = 3421, name = "Phantom Plate Vambraces", icon = 622, },
                        { id = 3422, name = "Phantom Plate Bracers",   icon = 516, },
                        { id = 3423, name = "Phantom Plate Gauntlets", icon = 531, },
                        { id = 3424, name = "Phantom Plate Greaves",   icon = 540, },
                        { id = 3425, name = "Phantom Plate Boots",     icon = 524, },
                    },
                    trashItems = {
                        phantomSatchel,
                    },
                },
                {
                    name = "Summon Phantom Chain",
                    type = "spell",
                    method = "bag",
                    items = {
                        { id = 3412, name = "Phantom Chain Coif",    icon = 625, },
                        { id = 3413, name = "Phantom Chain Coat",    icon = 538, },
                        { id = 3414, name = "Phantom Chain Sleeves", icon = 543, },
                        { id = 3415, name = "Phantom Chain Bracer",  icon = 620, },
                        { id = 3416, name = "Phantom Chain Gloves",  icon = 526, },
                        { id = 3417, name = "Phantom Chain Greaves", icon = 540, },
                        { id = 3418, name = "Phantom Chain Boots",   icon = 545, },
                    },
                    trashItems = {
                        phantomSatchel,
                    },
                },
                {
                    name = "Summon Phantom Leather",
                    type = "spell",
                    method = "cursor",
                    items = {
                        { id = 3405, name = "Phantom Leather Skullcap", icon = 640, },
                        { id = 3406, name = "Phantom Leather Tunic",    icon = 632, },
                        { id = 3407, name = "Phantom Leather Sleeves",  icon = 634, },
                        { id = 3408, name = "Phantom Leather Bracer",   icon = 637, },
                        { id = 3409, name = "Phantom Leather Gloves",   icon = 636, },
                        { id = 3410, name = "Phantom Leather Leggings", icon = 635, },
                        { id = 3411, name = "Phantom Leather Boots",    icon = 633, },
                    },
                    trashItems = {
                        phantomSatchel,
                    },
                },
            },
            { -- Heirlooms
                {
                    name = "Grant Arcane Heirlooms",
                    type = "spell",
                    method = "bag",
                    clicky = true,
                    clickyItem = { id = 177682, name = "Folded Pack of Arcane Heirlooms", icon = 12577, },
                    items = {
                        { id = 177683, name = "Arcane Satin Choker",    icon = 12569, },
                        { id = 177684, name = "Arcane Woven Shawl",     icon = 12570, },
                        { id = 177685, name = "Arcane Linked Bracelet", icon = 12571, },
                        { id = 177686, name = "Arcane Gold Ring",       icon = 12572, },
                        { id = 177687, name = "Arcane Ridged Earhoop",  icon = 12573, },
                        { id = 177688, name = "Arcane Jade Bracelet",   icon = 6634, },
                    },
                    trashItems = {
                        { id = 177671, name = "Arcane Heirloom Pack", icon = 12580, },
                    },
                },
                {
                    name = "Grant Ankexfen's Heirlooms",
                    type = "spell",
                    method = "bag",
                    clicky = true,
                    clickyItem = { id = 159983, name = "Folded Pack of Ankexfen Heirlooms", icon = 12577, },
                    items = {
                        { id = 159984, name = "Ankexfen Satin Choker",    icon = 12569, },
                        { id = 159985, name = "Ankexfen Woven Shawl",     icon = 12570, },
                        { id = 159986, name = "Ankexfen Linked Bracelet", icon = 12571, },
                        { id = 159987, name = "Ankexfen Gold Ring",       icon = 12572, },
                        { id = 159988, name = "Ankexfen Ridged Earhoop",  icon = 12573, },
                        { id = 159989, name = "Ankexfen Jade Bracelet",   icon = 6634, },
                    },
                    trashItems = {
                        { id = 159961, name = "Phantom Heirloom Pack", icon = 12580, },
                    },
                },
                {
                    name = "Grant the Diabo's Heirlooms",
                    type = "spell",
                    method = "bag",
                    clicky = true,
                    clickyItem = { id = 124379, name = "Folded Pack of the Diabo's Heirlooms", icon = 1934, },
                    items = {
                        { id = 124380, name = "Diabo's Satin Choker",    icon = 850, },
                        { id = 124381, name = "Diabo's Woven Shawl",     icon = 665, },
                        { id = 124382, name = "Diabo's Linked Bracelet", icon = 509, },
                        { id = 124383, name = "Diabo's Gold Ring",       icon = 873, },
                        { id = 124384, name = "Diabo's Ridged Earhoop",  icon = 756, },
                        { id = 124385, name = "Diabo's Jade Bracelet",   icon = 509, },
                    },
                    trashItems = {
                        phantomSatchel2,
                    },
                },
                {
                    name = "Grant Crystasia's Heirlooms",
                    type = "spell",
                    method = "bag",
                    clicky = true,
                    clickyItem = { id = 150423, name = "Folded Pack of Crystasia's Heirlooms", icon = 1934, },
                    items = {
                        { id = 150424, name = "Crystasia's Satin Choker",    icon = 850, },
                        { id = 150425, name = "Crystasia's Woven Shawl",     icon = 665, },
                        { id = 150426, name = "Crystasia's Linked Bracelet", icon = 509, },
                        { id = 150427, name = "Crystasia's Gold Ring",       icon = 873, },
                        { id = 150428, name = "Crystasia's Ridged Earhoop",  icon = 756, },
                        { id = 150429, name = "Crystasia's Jade Bracelet",   icon = 509, },
                    },
                    trashItems = {
                        phantomSatchel2,
                    },
                },
                {
                    name = "Grant Ioulin's Heirlooms",
                    type = "spell",
                    method = "bag",
                    clicky = true,
                    clickyItem = { id = 93698, name = "Folded Pack of Ioulin's Heirlooms", icon = 1934, },
                    items = {
                        { id = 93692, name = "Arcronite Satin Choker",    icon = 850, },
                        { id = 93693, name = "Arcronite Woven Shawl",     icon = 665, },
                        { id = 93694, name = "Arcronite Linked Bracelet", icon = 509, },
                        { id = 93695, name = "Arcronite Gold Ring",       icon = 873, },
                        { id = 93696, name = "Arcronite Ridged Earhoop",  icon = 756, },
                        { id = 93697, name = "Arcronite Jade Bracelet",   icon = 509, },
                    },
                    trashItems = {
                        phantomSatchel2,
                    },
                },
                {
                    name = "Grant Calix's Heirlooms",
                    type = "spell",
                    method = "bag",
                    clicky = true,
                    clickyItem = { id = 99808, name = "Folded Pack of Antius' Heirlooms", icon = 1932, },
                    items = {
                        { id = 99801, name = "Antius' Satin Choker",    icon = 850, },
                        { id = 99802, name = "Antius' Woven Shawl",     icon = 665, },
                        { id = 99803, name = "Antius' Linked Bracelet", icon = 509, },
                        { id = 99804, name = "Antius' Gold Ring",       icon = 873, },
                        { id = 99805, name = "Antius' Ridged Earhoop",  icon = 756, },
                        { id = 99806, name = "Antius' Jade Bracelet",   icon = 509, },
                    },
                    trashItems = {
                        phantomSatchel2,
                    },
                },
                {
                    name = "Grant Nint's Heirlooms",
                    type = "spell",
                    method = "bag",
                    clicky = true,
                    clickyItem = { id = 76528, name = "Folded Pack of Nint's Heirlooms", icon = 1932, },
                    items = {
                        { id = 76521, name = "Nint's Satin Choker",    icon = 850, },
                        { id = 76522, name = "Nint's Woven Shawl",     icon = 665, },
                        { id = 76523, name = "Nint's Linked Bracelet", icon = 509, },
                        { id = 76524, name = "Nint's Gold Ring",       icon = 873, },
                        { id = 76525, name = "Nint's Ridged Earhoop",  icon = 756, },
                        { id = 76526, name = "Nint's Jade Bracelet",   icon = 509, },
                    },
                    trashItems = {
                        phantomSatchel2,
                    },
                },
                {
                    name = "Grant Atleris' Heirlooms",
                    type = "spell",
                    method = "bag",
                    clicky = true,
                    clickyItem = { id = 64976, name = "Folded Pack of Atleris' Heirlooms", icon = 1932, },
                    items = {
                        { id = 64969, name = "Atleris' Satin Choker",    icon = 850, },
                        { id = 64970, name = "Atleris' Woven Shawl",     icon = 665, },
                        { id = 64971, name = "Atleris' Linked Bracelet", icon = 509, },
                        { id = 64972, name = "Atleris' Gold Ring",       icon = 873, },
                        { id = 64973, name = "Atleris' Ridged Earhoop",  icon = 756, },
                        { id = 64974, name = "Atleris' Jade Bracelet",   icon = 509, },
                    },
                    trashItems = {
                        phantomSatchel2,
                    },
                },
                {
                    name = "Grant Enibik's Heirlooms",
                    type = "spell",
                    method = "bag",
                    clicky = true,
                    clickyItem = { id = 57294, name = "Folded Pack of Enibik's Heirlooms", icon = 1938, },
                    items = {
                        { id = 57282, name = "Enibik's Satin Choker",    icon = 850, },
                        { id = 57283, name = "Enibik's Woven Shawl",     icon = 665, },
                        { id = 57284, name = "Enibik's Linked Bracelet", icon = 509, },
                        { id = 57285, name = "Enibik's Gold Ring",       icon = 873, },
                        { id = 57286, name = "Enibik's Ridged Earhoop",  icon = 756, },
                        { id = 57287, name = "Enibik's Jade Bracelet",   icon = 509, },
                    },
                    trashItems = {
                        phantomSatchel2,
                    },
                },
                {
                    name = "Summon Zabella's Heirlooms",
                    type = "spell",
                    method = "bag",
                    items = {
                        { id = 52835, name = "Zabella's Satin Choker",    icon = 850, },
                        { id = 52836, name = "Zabella's Woven Shawl",     icon = 665, },
                        { id = 52837, name = "Zabella's Linked Bracelet", icon = 509, },
                        { id = 52838, name = "Zabella's Gold Ring",       icon = 873, },
                        { id = 52839, name = "Zabella's Ridged Earhoop",  icon = 756, },
                        { id = 52840, name = "Zabella's Jade Bracelet",   icon = 509, },
                    },
                    trashItems = {
                        phantomSatchel,
                    },
                },
                {
                    name = "Summon Nastel's Heirlooms",
                    type = "spell",
                    method = "bag",
                    items = {
                        { id = 52727, name = "Nastel's Satin Choker",    icon = 850, },
                        { id = 52728, name = "Nastel's Woven Shawl",     icon = 665, },
                        { id = 52729, name = "Nastel's Linked Bracelet", icon = 509, },
                        { id = 52730, name = "Nastel's Gold Ring",       icon = 873, },
                        { id = 52731, name = "Nastel's Ridged Earhoop",  icon = 756, },
                        { id = 52732, name = "Nastel's Jade Bracelet",   icon = 509, },
                    },
                    trashItems = {
                        phantomSatchel,
                    },
                },
                {
                    name = "Summon Aenda's Trinkets",
                    type = "spell",
                    method = "bag",
                    items = {
                        { id = 52666, name = "Aenda's Satin Choker",    icon = 850, },
                        { id = 52667, name = "Aenda's Woven Shawl",     icon = 665, },
                        { id = 52668, name = "Aenda's Linked Bracelet", icon = 509, },
                        { id = 52669, name = "Aenda's Gold Ring",       icon = 873, },
                        { id = 52670, name = "Aenda's Ridged Earhoop",  icon = 756, },
                        { id = 52671, name = "Aenda's Jade Bracelet",   icon = 509, },
                    },
                    trashItems = {
                        phantomSatchel,
                    },
                },
                {
                    name = "Summon Pouch of Jerikor",
                    type = "spell",
                    method = "bag",
                    items = {
                        { id = 77511, name = "Calliav's Platinum Choker",  icon = 850, },
                        { id = 77512, name = "Calliav's Runed Mantle",     icon = 665, },
                        { id = 77513, name = "Calliav's Jeweled Bracelet", icon = 509, },
                        { id = 77514, name = "Calliav's Spiked Ring",      icon = 873, },
                        { id = 77515, name = "Calliav's Glowing Bauble",   icon = 756, },
                        { id = 77516, name = "Calliav's Steel Bracelet",   icon = 509, },
                    },
                    trashItems = {
                        phantomSatchel,
                    },
                },
                {
                    name = "Summon Jewelry Bag",
                    type = "spell",
                    method = "bag",
                    items = {
                        { id = 29796, name = "Jedah's Platinum Choker",       icon = 850, },
                        { id = 29797, name = "Tavee's Runed Mantle",          icon = 665, },
                        { id = 29798, name = "Gallenite's Sapphire Bracelet", icon = 509, },
                        { id = 29799, name = "Naki's Spiked Ring",            icon = 873, },
                        { id = 29800, name = "Jolum's Glowing Bauble",        icon = 756, },
                        { id = 59564, name = "Rallican's Steel Bracelet",     icon = 509, },
                    },
                    trashItems = {
                        phantomSatchel,
                    },
                },
            },
            { --Mask
                {
                    name = "Grant Visor of Usira",
                    type = "spell",
                    method = "cursor",
                    items = {
                        { id = 128395, name = "Summoned: Visor of Usira", icon = 3680, },
                    },
                },
                {
                    name = "Grant Visor of Shoen",
                    type = "spell",
                    method = "cursor",
                    items = {
                        { id = 106090, name = "Summoned: Visor of Shoen", icon = 770, },
                    },
                },
                {
                    name = "Grant Visor of Gobeker",
                    type = "spell",
                    method = "cursor",
                    items = {
                        { id = 76507, name = "Summoned: Visor of Gobeker", icon = 770, },
                    },
                },
                {
                    name = "Grant Visor of Vabtik",
                    type = "spell",
                    method = "cursor",
                    items = {
                        { id = 57276, name = "Summoned: Visor of Vabtik", icon = 770, },
                    },
                },
                {
                    name = "Summon Muzzle of Mowcha",
                    type = "spell",
                    method = "cursor",
                    items = {
                        { id = 46987, name = "Summoned: Muzzle of Mowcha", icon = 770, },
                    },
                },
                {
                    name = "Muzzle of Mardu",
                    type = "spell",
                    method = "cursor",
                    items = {
                        { id = 1348, name = "Summoned: Muzzle of Mardu", icon = 770, },
                    },
                },
            },
        },
    },
}
