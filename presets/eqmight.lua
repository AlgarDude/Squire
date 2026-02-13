--[[
    Squire - EQ Might EMU Server Presets
    Array of preset definitions with title, classes, and ordered effects (priority groups).
    Each priority group is a list of candidates — first available source wins.
]]

local toxicEdge = { id = 148732, name = "Summoned: Toxic Edge", icon = 1407, }
local ixiblat = { id = 28596, name = "Summoned: Hand of Ixiblat", icon = 971, }
local crystalBelt = { id = 77510, name = "Summoned: Crystal Belt", icon = 501, }


return {
  {
    title = "Default",
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
          items = { { id = 1348, }, },
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
    title = "Magician",
    classes = { "MAG", },
    effects = {
      { -- Weapons
        {
          name = "Artifact of Toxic Edge",
          type = "item",
          method = "cursor",
          items = { { id = 148732, name = "Summoned: Toxic Edge", icon = 1407, }, { id = 148732, name = "Summoned: Toxic Edge", icon = 1407, }, },
        },
        {
          name = "Legendary Toxic Edge Earring",
          type = "item",
          method = "cursor",
          items = { { id = 148732, }, { id = 148732, }, },
        },
        {
          name = "Toxic Edge Earring",
          type = "item",
          method = "cursor",
          items = { { id = 148732, }, { id = 148732, }, },
        },
        {
          name = "Legendary Gloves of Strongboom",
          type = "item",
          method = "cursor",
          items = { { id = 28596, }, { id = 28596, }, },
        },
        {
          name = "Gloves of Strongboom",
          type = "item",
          method = "cursor",
          items = { { id = 28596, }, { id = 28596, }, },
        },
        {
          name = "Gloves of Ixiblat",
          type = "item",
          method = "cursor",
          items = { { id = 28596, }, { id = 28596, }, },
        },
      },
      { -- Mask
        {
          name = "Mask of Mardu",
          type = "item",
          method = "cursor",
          items = { { id = 1348, }, },
        },
      },
      { -- Belt
        {
          name = "Legendary Goblin Mask of Stability",
          type = "item",
          method = "cursor",
          items = { { id = 77510, }, },
        },
        {
          name = "Goblin Mask of Stability",
          type = "item",
          method = "cursor",
          items = { { id = 77510, }, },
        },
      },
    },
  },
}
