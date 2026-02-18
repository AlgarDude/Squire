--[[
    Squire - Live/Test Server Presets
    Array of preset definitions with title, classes, and ordered effects (priority groups).
    Each priority group is a list of candidates - first available source wins.
]]

-- Example: clicky bag entry for reference (remove or replace with real data)
-- local exampleSword = { id = 12345, name = "Summoned: Example Sword", icon = 592, }
-- local exampleTrash = { id = 12346, name = "Summoned: Example Hilt", icon = 593, }

return {
    -- To add presets for live servers, follow the eqmight.lua file as an example.
    -- Define shared item tables at the top, then reference them in your effects.
    --
    -- Example clicky bag entry (a spell that summons a clicky, which produces a bag):
    --
    -- {
    --   name = "Grant Spectral Armaments",
    --   type = "spell",
    --   method = "bag",
    --   clicky = true,
    --   clickyItem = { id = 99999, name = "Spectral Armaments Catalyst", icon = 594, },
    --   items = { exampleSword, exampleSword, },
    --   trashItems = { exampleTrash, },
    -- },
    --
    -- Example trade entry (give an item already in your inventory):
    --
    -- {
    --   name = "Blackened Acrylia Blade",
    --   type = "item",
    --   method = "trade",
    -- },
}
