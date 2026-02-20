<p align="center">
<img width="300" height="300" alt="Squire" src="resources/squire.png" />
</p>

**Squire** is your personal pet armory attendant - a Lua script that takes the ***tedious targeting***, ***fumbling with bags*** and ***spell-gem juggling*** out of arming pets and replaces it with **ONE CLICK**.

**"I WANT TO ARM AN ENTIRE RAID'S WORTH OF PETS AND I DON'T WANT CARPAL TUNNEL"** <sup>(we got you)</sup>

**Arm your pet. Arm their pet. Arm <ins>everybody's</ins> pet.**

&nbsp;

## Presets Make Pet-Arming Painless

- Squire ships with **preconfigured class presets** so you can start arming pets immediately - no setup required.*
- Presets are smart - they resolve what's actually available to your character and present only those options.
- Presets are ordered by priority, so Squire always picks the **best available** source for each category.
- Categories are organized logically: Weapons, Armor, Heirlooms, Masks - each as its own priority group.

<sup>* Presets are currently available for Magician on Live/Test servers, with more to come!</sup>

IMAGE_PLACEHOLDER_PRESET_SELECTOR

*Set selector with resolved preset entries*

&nbsp;

## Custom Sets for the Control Freaks

Not using a preset class? Want a specific loadout? Squire's set editor lets you build exactly what you want.

- Create custom sets with any combination of **spells, AAs, and items** as sources.
- Four delivery methods: **Direct to Pet**, **Cursor**, **Bag**, and **Trade** - covering every summoning style in the game.
- Bag method handles the entire clicky workflow automatically - summon the folded pack, place it, click it, unpack it, hand over the contents.
- Toggle individual sources on or off without deleting them.
- Reorder sources with drag controls to set your own priority.
- Sets are saved per-character and persist across sessions.

IMAGE_PLACEHOLDER_EDIT_SETS

*The Edit Sets window - add, remove, reorder and toggle sources*

&nbsp;

## Stupidly Simple Scoping

Squire arms pets with surgical precision or reckless abandon - your choice.

- `/squire arm self` - Arm your own pet.
- `/squire arm target` - Arm your target's pet.
- `/squire arm group` - Arm every pet in your group.
- `/squire arm raid` - Arm every pet in the raid. Yes, all of them.**
- `/squire arm PlayerName` - Arm a specific player's pet.
- Accepts **tells** from other players - they can request arming with a trigger word.
- Queues multiple requests and processes them in order.

<sup>** Squire will politely skip players who don't have a pet. It's not a monster.</sup>

&nbsp;

## Features for the Fastidious

- **Navigation**: Optionally auto-navigate to out-of-range pets (toggle in settings).
- **Spell Management**: Automatically memorizes needed spells, restores your spell bar when done.
- **Inventory Safety**: Frees a top-level inventory slot for bag operations, cleans up after itself.
- **Tell Access Control**: Allow list, deny list, or open access for tell-triggered arming.
- **Stop Anytime**: `/squire stop` halts the current operation immediately - mid-cast, mid-delivery, whenever.
- **Debug Logging**: Toggle debug mode for detailed operation history.
- **Arming History**: View recent results in the UI - who was armed, what succeeded, what failed.

IMAGE_PLACEHOLDER_MAIN_WINDOW

*Main window with status, controls, and arming history*

