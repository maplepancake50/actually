# actually

actually is an Ascension/WoW 3.3.5 utility-spell tier-list prototype.

## Current milestone: tier-list profiles and sharing

The catalogue starts empty and is populated in game using real spell IDs.
Drag added spell cards between the S, A, B, C, D, and Pool rows. The Pool
scrolls independently, while ranked rows expand as cards wrap and the ranked
board scrolls when needed. Assignments and ordering persist across logout and
`/reload` through `ActuallyDB`.

Commands:

- `/actually` or `/act` toggles the board.
- `/actually reset` returns every card to the Pool.
- `/actually pet` shows or hides the pet.
- `/actually pet reset` returns the pet to its default position.
- `/actually pet sneeze` previews the sneeze animation.
- `/actually pet emote` previews a passive emote.

The board starts closed. The nerd-face minimap button also toggles it and can
be dragged around the minimap; its position persists between sessions.

Use **Save As** to create personal tier-list profiles. **Select Tier List**
switches profiles, while the highlighted **Official Tier List** view is kept
read-only until officer synchronization is enabled. **Import / Export** copies
complete lists—including spell IDs, categories, tiers, and ordering—through a
portable text string.

The Actually pet floats over the game UI and can be dragged anywhere on
screen. Its position and visibility persist between sessions.

The filter bar searches the current curated catalogue by case-insensitive
spell name or exact/partial spell ID. Category filtering and search affect
visibility only; manually arranged tier order remains intact.

Use **Add Spell** in the board header to add a missing spell without editing
Lua. Enter its numeric spell ID, verify the client-resolved icon, name, native
description/cooldown tooltip, choose a category, and add it to the Pool.
Right-click an added spell for a context menu with a confirmed delete action.

## Install for testing

Clone or copy this repository as:

`F:\Ascension Launcher\resources\client\Interface\AddOns\actually`

Then launch or reload the client, enable **actually** in the addon list, and
enter `/actually`.

## In-game checkpoint

Confirm these before the next module begins:

1. The board opens without Lua errors.
2. A spell added by ID appears in the scrollable Pool.
3. Cards can move between tiers and can be reordered within a tier.
4. Tooltips appear on hover.
5. Placements survive `/reload` and relogging.
6. A tier expands cleanly when it contains more than one line of cards.
7. Right-click deletion removes a spell and its saved placement.
8. Reset returns all cards to the Pool.
