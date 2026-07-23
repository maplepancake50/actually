local ARC = Actually.Modules.RaidCooldowns

ARC.Defaults = {
    profile = {
        enabled = true,
        debug = false,
        ignoreSelf = false,
        hideWhileSolo = false,
        testUI = {
            shown = true,
            point = "CENTER",
            x = 0,
            y = 0,
        },
        spoofUI = {
            point = "CENTER",
            x = 320,
            y = 0,
            duration = 30,
        },
        configUI = {
            point = "CENTER",
            x = 0,
            y = 0,
        },
        spells = {},
        frames = {
            updateInterval = 0.1,
        },
    },
}
