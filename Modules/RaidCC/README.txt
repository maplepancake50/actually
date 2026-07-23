Actually Raid CC
=================

This is a module of the Actually addon. Install or update the complete Actually
folder at Interface\AddOns\Actually. TurboPlates should also be installed.

Open Game Menu > Interface > AddOns > Actually Raid CC and select:

    Enable Raid CC Mode

The saved preference only becomes active while the character is in a raid.
While active, the module enables friendly and enemy player nameplates, replaces
visible non-self raid-member TurboPlates with names, and shows an arrow for
Cyclone or Shadowfury. Leaving the raid or clearing the checkbox restores the
previous nameplate CVar values and TurboPlates presentation.

TurboPlates compatibility fields
--------------------------------

The module does not access TurboPlates' private namespace. It recognises these
fields on the original world nameplate:

    myPlate             full TurboPlates frame (hidden/restored)
    liteContainer       lightweight TurboPlates frame (hidden/restored)
    liteQuestIcon       external lite icon (hidden only)
    _isLite             read-only display-mode selector
    _unit               read-only active unit token
    _turboTrackedUnit   read-only TurboPlates tracking token
    _turboTrackedGUID   read-only TurboPlates tracking GUID

The verified name FontStrings are:

    liteContainer.liteNameText
    myPlate.nameText

If none of the three recognised frame fields exists, the plate is not altered.

Tracked spell IDs
-----------------

    33786  Cyclone
    30283  Shadowfury rank 1
    30413  Shadowfury rank 2
    30414  Shadowfury rank 3
    47846  Shadowfury rank 4
    47847  Shadowfury rank 5

Spell-name matching is also used because Ascension may expose remapped aura IDs.
These IDs match TurboPlates 1.4.5's own TurboDebuffs catalogue.

Verified TurboPlates integration
--------------------------------

The integration was audited against the installed TurboPlates 1.4.5 source.
TurboPlates receives NamePlateManager.UnitAdded and UnitRemoved from the global
EventRegistry. Actually registers the same callbacks after TurboPlates and keeps
NAME_PLATE_UNIT_ADDED/REMOVED as a fallback. Existing plates are discovered with
C_NamePlateManager.EnumerateActiveNamePlates().

TurboPlates creates myPlate on the original frame, then normally reparents it to
WorldFrame for movement optimisation. Its child health bars, castbars, auras,
TurboDebuff, icons, and highlights are therefore all suppressed with myPlate.
The liteContainer stays on the original nameplate and owns liteNameText,
liteGuildText, the raid icon, healer icon, damaged-health bar, highlight, and
lite TurboDebuff. liteQuestIcon is the only audited lite visual outside that
container, so it is suppressed separately.
