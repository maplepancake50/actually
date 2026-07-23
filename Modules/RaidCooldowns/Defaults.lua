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
            scale = 1,
            locked = true,
        },
        spoofUI = {
            point = "CENTER",
            x = 320,
            y = 0,
        },
        configUI = {
            point = "CENTER",
            x = 0,
            y = 0,
        },
        requests = {
            timeout = 8,
            sound = true,
            autoFailover = true,
        },
        automation = {
            failureMemory = true,
            spreadAssignments = true,
            stageAdvancePolicy = "any",
        },
        alertUI = {
            point = "CENTER",
            x = 0,
            y = 140,
            scale = 1,
        },
        requestUI = {
            point = "CENTER",
            x = 0,
            y = 140,
        },
        bundleAlertUI = {
            point = "CENTER",
            x = 0,
            y = 150,
        },
        bundleSummaryUI = {
            point = "TOP",
            x = 0,
            y = -180,
        },
        bundleUI = {
            point = "CENTER",
            x = 0,
            y = 0,
            scale = 1,
            locked = true,
        },
        cooldownBundles = {},
        commanderUI = {
            shown = true,
            point = "CENTER",
            x = -330,
            y = 0,
            scale = 1,
            locked = true,
        },
        commanderConfigUI = {
            point = "CENTER",
            x = 0,
            y = 0,
        },
        commandPlans = {},
        commanderProgress = {},
        spells = {},
        frames = {
            updateInterval = 0.1,
        },
    },
}
