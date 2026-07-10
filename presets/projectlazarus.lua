--[[
    Squire - Project Lazarus EMU Server Presets
    Array of preset definitions with title, classes, and ordered effects (priority groups).
    Each priority group is a list of candidates - first available source wins.
]]

local beltofmagikot = { id = 28594, name = "Summoned: Belt of Magi`Kot", icon = 501, }
local bladeofthekedge = { id = 28597, name = "Summoned: Blade of the Kedge", icon = 1343, }
local bladeofwalnan = { id = 28595, name = "Summoned: Blade of Walnan", icon = 1342, }
local crystalbelt = { id = 77510, name = "Summoned: Crystal Belt", icon = 501, }
local dagger = { id = 7305, name = "Summoned: Dagger", icon = 592, }
local daggerofthedeep = { id = 77509, name = "Summoned: Dagger of the Deep", icon = 1407, }
local elementalblanket = { id = 20075, name = "Elemental Blanket", icon = 665, }
local elementaldefender = { id = 3427, name = "Elemental Defender", icon = 1244, }
local enibiksheirlooms = { id = 57294, name = "Folded Pack of Enibik's Heirlooms", icon = 1938, }
local fang = { id = 7313, name = "Summoned: Snake Fang", icon = 801, }
local fireblade = { id = 77508, name = "Summoned: Fireblade", icon = 519, }
local girdleofmagikot = { id = 28598, name = "Summoned: Girdle of Magi`Kot", icon = 501, }
local handofixiblat = { id = 28596, name = "Summoned: Hand of Ixiblat", icon = 971, }
local jewelrybag = { id = 17310, name = "Phantom Satchel", icon = 691, }
local muzzleofmardu = { id = 1348, name = "Summoned: Muzzle of Mardu", icon = 770, }
local phantomchain = { id = 17310, name = "Phantom Satchel", icon = 691, }
local phantomleather = { id = 17310, name = "Phantom Satchel", icon = 691, }
local phantomplate = { id = 17310, name = "Phantom Satchel", icon = 691, }
local pouchofjerikor = { id = 17310, name = "Phantom Satchel", icon = 691, }
local spearofwarding = { id = 7309, name = "Summoned: Spear of Warding", icon = 776, }
local spectralarmaments = { id = 57295, name = "Folded Pack of Spectral Armaments", icon = 1930, }
local spectralplate = { id = 57293, name = "Folded Pack of Spectral Plate", icon = 1937, }
local staffofthenorthwind = { id = 77507, name = "Summoned: Staff of the North Wind", icon = 1282, }
local swordofrunes = { id = 5319, name = "Summoned: Sword of Runes", icon = 590, }

return 
{
    -- To add presets for Project Lazarus, follow the eqmight.lua file as an example.
    -- Define shared item tables at the top, then reference them in your effects.
	{
	title = "Class Preset (Lazarus)",
		classes = { "MAG", },
		effects = 
		{
			{ -- Weapons
				{
				name = "Grant Spectral Armaments",
				type = "spell",
				method = "bag",
				clicky = true,
				clickyItem = { id = 57295, name = "Folded Pack of Spectral Armaments", icon = 1930, },
				items = 
					{
						-- Modify the commented lines to switch items from the pack
						{ id = 57279, name = "Summoned: Fist of Flame", icon = 2962, },
						{ id = 57279, name = "Summoned: Fist of Flame", icon = 2962, },
						-- { id = 57280, name = "Summoned: Orb of Chilling Water", icon = 4134, },
						-- { id = 57280, name = "Summoned: Orb of Chilling Water", icon = 4134, },
						-- { id = 57288, name = "Summoned: Buckler of Draining Defense", icon = 4719, },
						-- { id = 150276, name = "Summoned: Short Sword of Warding", icon = 3368, },
						-- { id = 57296, name = "Summoned: Mace of Temporal Distortion", icon = 4658, },
						-- { id = 150277, name = "Summoned: Spear of Maliciousness", icon = 2623, },
						-- { id = 150332, name = "Summoned: Wand of Dismissal", icon = 3556, },
						-- { id = 150333, name = "Summoned: Tendon Carver", icon = 6885, },
					},
				trashItems = 
					{
						{ id = 57261, name = "Pouch of Quellious", icon = 667, },
					},
				},
				{
				name = "Summon Dagger of the Deep",
				type = "spell",
				method = "cursor",
				items = 
					{
						{ id = 77509, name = "Summoned: Dagger of the Deep", icon = 1407, },
						{ id = 77509, name = "Summoned: Dagger of the Deep", icon = 1407, },
					},
				},
				{
				name = "Summon Staff of the North Wind",
				type = "spell",
				method = "cursor",
				items = 
					{
						{ id = 77507, name = "Summoned: Staff of the North Wind", icon = 1282, },
						{ id = 77507, name = "Summoned: Staff of the North Wind", icon = 1282, },
					},
				},
				{
				name = "Summon Fireblade",
				type = "spell",
				method = "cursor",
				items = 
					{
						{ id = 77508, name = "Summoned: Fireblade", icon = 519, },
						{ id = 77508, name = "Summoned: Fireblade", icon = 519, },
					},
				},
				{
				name = "Blade of The Kedge",
				type = "spell",
				method = "cursor",
				items = 
					{
						{ id = 28597, name = "Summoned: Blade of the Kedge", icon = 1343, },
						{ id = 28597, name = "Summoned: Blade of the Kedge", icon = 1343, },
					},
				},
				{
				name = "Fist of Ixiblat",
				type = "spell",
				method = "cursor",
				items = 
					{
						{ id = 28596, name = "Summoned: Hand of Ixiblat", icon = 971, },
						{ id = 28596, name = "Summoned: Hand of Ixiblat", icon = 971, },
					},
				},
				{
				name = "Blade of Walnan",
				type = "spell",
				method = "cursor",
				items = 
					{
						{ id = 28595, name = "Summoned: Blade of Walnan", icon = 1342, },
						{ id = 28595, name = "Summoned: Blade of Walnan", icon = 1342, },
					},
				},
				{
				name = "Sword of Runes",
				type = "spell",
				method = "cursor",
				items = 
					{
						{ id = 5319, name = "Summoned: Sword of Runes", icon = 590, },
						{ id = 5319, name = "Summoned: Sword of Runes", icon = 590, },
					},
				},
				{
				name = "Spear of Warding",
				type = "spell",
				method = "cursor",
				items = 
					{
						{ id = 7309, name = "Summoned: Spear of Warding", icon = 776, },
						{ id = 7309, name = "Summoned: Spear of Warding", icon = 776, },
					},
				},
				{
				name = "Summon Fang",
				type = "spell",
				method = "cursor",
				items = 
					{
						{ id = 7313, name = "Summoned: Snake Fang", icon = 801, },
						{ id = 7313, name = "Summoned: Snake Fang", icon = 801, },
					},
				},
				{
				name = "Summon Dagger",
				type = "spell",
				method = "cursor",
				items = 
					{
						{ id = 7305, name = "Summoned: Dagger", icon = 592, },
						{ id = 7305, name = "Summoned: Dagger", icon = 592, },
					},
				},
			},
			{ -- Mask
				{
				name = "Muzzle of Mardu",
				type = "spell",
				method = "cursor",
				items = 
					{
						{ id = 1348, name = "Summoned: Muzzle of Mardu", icon = 770, },
					},
				},
			},
			{ -- Belt
				{
				name = "Summon Crystal Belt",
				type = "spell",
				method = "cursor",
				items = 
					{
						{ id = 77510, name = "Summoned: Crystal Belt", icon = 501, },
					},
				},
				{
				name = "Girdle of Magi`Kot",
				type = "spell",
				method = "cursor",
				items = 
					{
						{ id = 28598, name = "Summoned: Girdle of Magi`Kot", icon = 501, },
					},
				},
				{
				name = "Belt of Magi`Kot",
				type = "spell",
				method = "cursor",
				items = 
					{
						{ id = 28594, name = "Summoned: Belt of Magi`Kot", icon = 501, },
					},
				},
			},
			{ -- Jewelry
				{
				name = "Grant Enibik's Heirlooms",
				type = "spell",
				method = "direct",
				items = 
					{
						{ id = 57294, name = "Folded Pack of Enibik's Heirlooms", icon = 1938, },
					},
				},
				{
				name = "Pouch of Jerikor",
				type = "spell",
				method = "cursor",
				items = 
					{
						{ id = 17310, name = "Phantom Satchel", icon = 691, },
					},
				},
				{
				name = "Summon Jewelry Bag",
				type = "spell",
				method = "cursor",
				items = 
					{
						{ id = 17310, name = "Phantom Satchel", icon = 691, },
					},
				},
			},
			{ -- Armor
				{
				name = "Grant Spectral Plate",
				type = "spell",
				method = "direct",
				items = 
					{
						{ id = 57293, name = "Folded Pack of Spectral Plate", icon = 1937, },
					},
				},
				{
				name = "Summon Phantom Plate",
				type = "spell",
				method = "cursor",
				items = 
					{
						{ id = 17310, name = "Phantom Satchel", icon = 691, },
					},
				},
				{
				name = "Summon Phantom Chain",
				type = "spell",
				method = "cursor",
				items = 
					{
						{ id = 17310, name = "Phantom Satchel", icon = 691, },
					},
				},
				{
				name = "Summon Phantom Leather",
				type = "spell",
				method = "cursor",
				items = 
					{
						{ id = 17310, name = "Phantom Satchel", icon = 691, },
					},
				},
			},
			{ -- Back
				{
				name = "Summon Elemental Blanket",
				type = "spell",
				method = "cursor",
				items = 
					{
						{ id = 20075, name = "Elemental Blanket", icon = 665, },
					},
				},
				{
				name = "Summon Elemental Defender",
				type = "spell",
				method = "cursor",
				items = 
					{
						{ id = 3427, name = "Elemental Defender", icon = 1244, },
					},
				},
			},
		},
	},
}
