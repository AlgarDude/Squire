--[[
    Squire - EQ Might EMU Server Presets
    Array of preset definitions with title, classes, and ordered effects (priority groups).
    Each priority group is a list of candidates — first available source wins.
]]

local toxicEdge = { id = 148732, name = "Summoned: Toxic Edge", icon = 1407, }
local ixiblat = { id = 28596, name = "Summoned: Hand of Ixiblat", icon = 971, }
local crystalBelt = { id = 77510, name = "Summoned: Crystal Belt", icon = 501, }
local phantomSatchel = { id = 17310, name = "Phantom Satchel", icon = 691, }
local marduMask = { id = 1348, name = "Summoned: Muzzle of Mardu", icon = 770, }
local mowchaMask = { id = 46987, name = "Summoned: Muzzle of Mowcha", icon = 770, }
local walnanBlade = { id = 28595, name = "Summoned: Blade of Walnan", icon = 1342, }

return {
  {
    title = "Class Preset (EQM)",
    classes = { "ENC", "NEC", },
    effects = {
      { -- Weapons
        {
          name = "Artifact of Toxic Edge",
          type = "item",
          method = "cursor",
          items = { toxicEdge, toxicEdge, },
        },
        {
          name = "Legendary Toxic Edge Earring",
          type = "item",
          method = "cursor",
          items = { toxicEdge, toxicEdge, },
        },
        {
          name = "Toxic Edge Earring",
          type = "item",
          method = "cursor",
          items = { toxicEdge, toxicEdge, },
        },
        {
          name = "Legendary Gloves of Strongboom",
          type = "item",
          method = "cursor",
          items = { ixiblat, ixiblat, },
        },
        {
          name = "Gloves of Strongboom",
          type = "item",
          method = "cursor",
          items = { ixiblat, ixiblat, },
        },
        {
          name = "Gloves of Ixiblat",
          type = "item",
          method = "cursor",
          items = { ixiblat, ixiblat, },
        },
      },
      { -- Mask
        {
          name = "Mask of Mardu",
          type = "item",
          method = "cursor",
          items = { marduMask, },
        },
        {
          name = "Muzzle of Mardu",
          type = "spell",
          method = "cursor",
          items = { marduMask, },
        },
      },
      { -- Belt
        {
          name = "Legendary Goblin Mask of Stability",
          type = "item",
          method = "cursor",
          items = { crystalBelt, },
        },
        {
          name = "Goblin Mask of Stability",
          type = "item",
          method = "cursor",
          items = { crystalBelt, },
        },
      },
    },
  },
  {
    title = "Class Preset (EQM)",
    classes = { "BST", },
    effects = {
      { -- Weapons
        {
          name = "Legendary Gloves of Strongboom",
          type = "item",
          method = "cursor",
          items = { ixiblat, ixiblat, },
        },
        {
          name = "Gloves of Strongboom",
          type = "item",
          method = "cursor",
          items = { ixiblat, ixiblat, },
        },
        {
          name = "Gloves of Ixiblat",
          type = "item",
          method = "cursor",
          items = { ixiblat, ixiblat, },
        },
      },
      { -- Mask
        {
          name = "Mask of Mardu",
          type = "item",
          method = "cursor",
          items = { marduMask, },
        },
      },
      { -- Belt
        {
          name = "Legendary Goblin Mask of Stability",
          type = "item",
          method = "cursor",
          items = { crystalBelt, },
        },
        {
          name = "Goblin Mask of Stability",
          type = "item",
          method = "cursor",
          items = { crystalBelt, },
        },
      },
    },
  },
  {
    title = "Class Preset (EQM)",
    classes = { "MAG", },
    effects = {
      { -- Weapons
        {
          name = "Artifact of Toxic Edge",
          type = "item",
          method = "cursor",
          items = { toxicEdge, toxicEdge, },
        },
        {
          name = "Legendary Toxic Edge Earring",
          type = "item",
          method = "cursor",
          items = { toxicEdge, toxicEdge, },
        },
        {
          name = "Toxic Edge Earring",
          type = "item",
          method = "cursor",
          items = { toxicEdge, toxicEdge, },
        },
        {
          name = "Artifact of Baat",
          type = "item",
          method = "cursor",
          items = {
            { id = 148864, name = "Summoned: Hand of Baat", icon = 2611, },
            { id = 148864, name = "Summoned: Hand of Baat", icon = 2611, },
          },
        },
        {
          name = "Summon Dagger of the Deep",
          type = "spell",
          method = "cursor",
          items = {
            { id = 77509, name = "Summoned: Dagger of the Deep", icon = 1407, },
          },
        },
        {
          name = "Legendary Gloves of Strongboom",
          type = "item",
          method = "cursor",
          items = { ixiblat, ixiblat, },
        },
        {
          name = "Gloves of Strongboom",
          type = "item",
          method = "cursor",
          items = { ixiblat, ixiblat, },
        },
        {
          name = "Gloves of Ixiblat",
          type = "item",
          method = "cursor",
          items = { ixiblat, ixiblat, },
        },
        {
          name = "Legendary Gloves of Bladecalling",
          type = "item",
          method = "cursor",
          items = { walnanBlade, walnanBlade, },
        },
        {
          name = "Blade of Walnan",
          type = "spell",
          method = "cursor",
          items = { walnanBlade, walnanBlade, },
        },
        {
          name = "Summon Fang",
          type = "spell",
          method = "cursor",
          items = {
            { id = 7313, name = "Summoned: Snake Fang", icon = 801, },
          },
        },
        {
          name = "Summon Dagger",
          type = "spell",
          method = "cursor",
          items = {
            { id = 7305, name = "Summoned: Dagger", icon = 592, },
          },
        },
      },
      { -- Armor
        {
          name = "Ancestral Girdle of the High Summoner",
          type = "item",
          method = "cursor",
          items = { phantomSatchel, },
        },
        {
          name = "Ancient Girdle of the High Summoner",
          type = "item",
          method = "cursor",
          items = { phantomSatchel, },
        },
        {
          name = "Girdle of the High Summoner",
          type = "item",
          method = "cursor",
          items = { phantomSatchel, },
        },
        {
          name = "Summon Plate of the Elements",
          type = "spell",
          method = "cursor",
          items = { phantomSatchel, },
        },
        {
          name = "Summon Phantom Plate",
          type = "spell",
          method = "cursor",
          items = { phantomSatchel, },
        },
        {
          name = "Summon Phantom Chain",
          type = "spell",
          method = "cursor",
          items = { phantomSatchel, },
        },
        {
          name = "Summon Phantom Leather",
          type = "spell",
          method = "cursor",
          items = { phantomSatchel, },
        },
      },
      { -- Mask
        {
          name = "Mightforged Mask of Mowcha",
          type = "item",
          method = "cursor",
          items = { mowchaMask, },
        },
        {
          name = "Legendary Mask of Mowcha",
          type = "item",
          method = "cursor",
          items = { mowchaMask, },
        },
        {
          name = "Ancient Mask of Mowcha",
          type = "item",
          method = "cursor",
          items = { mowchaMask, },
        },
        {
          name = "Summon Muzzle of Mowcha",
          type = "spell",
          method = "cursor",
          items = { mowchaMask, },
        },
        {
          name = "Miranda's Mask",
          type = "item",
          method = "cursor",
          items = {
            { id = 151096, name = "Summoned: Muzzle of Miranda", icon = 770, },
          },
        },
        {
          name = "Mask of Mardu",
          type = "item",
          method = "cursor",
          items = { marduMask, },
        },
        {
          name = "Muzzle of Mardu",
          type = "spell",
          method = "cursor",
          items = { marduMask, },
        },
      },
      { -- Belt
        {
          name = "Legendary Goblin Mask of Stability",
          type = "item",
          method = "cursor",
          items = { crystalBelt, },
        },
        {
          name = "Goblin Mask of Stability",
          type = "item",
          method = "cursor",
          items = { crystalBelt, },
        },
        {
          name = "Summon Crystal Belt",
          type = "spell",
          method = "cursor",
          items = { crystalBelt, },
        },
        {
          name = "Girdle of Magi`Kot",
          type = "spell",
          method = "cursor",
          items = {
            { id = 28598, name = "Summoned: Girdle of Magi`Kot", icon = 501, },
          },
        },
        {
          name = "Belt of Magi`Kot",
          type = "spell",
          method = "cursor",
          items = {
            { id = 28594, name = "Summoned: Belt of Magi`Kot", icon = 501, },
          },
        },
      },
    },
  },
}
