local ARC = Actually.Modules.RaidCooldowns
local TestMode = ARC:NewModule("TestMode")

function TestMode:Populate()
    local now = ARC:Now()
    self.players = {
        ["test:ready"] = {
            name = "Readyhealer",
            unit = nil,
            source = "TEST",
            spells = {
                [1180523] = { known = true, readyAt = 0, duration = 0, confidence = "TEST" },
            },
        },
        ["test:active"] = {
            name = "Cooldownuser",
            unit = nil,
            dead = false,
            source = "TEST",
            spells = {
                [1398258] = { known = true, readyAt = now + 73, duration = 120, target = "Main Tank", confidence = "TEST" },
                [1180270] = { known = true, readyAt = now + 18, duration = 45, confidence = "TEST" },
            },
        },
    }
    self.active = true
    ARC.Renderer:MarkDirty("test populate")
    ARC.Renderer:Reconcile()
end

function TestMode:Clear()
    self.active = false
    self.players = nil
    ARC.Renderer:MarkDirty("test clear")
    ARC.Renderer:Reconcile()
end

function TestMode:Toggle()
    if self.active then self:Clear() else self:Populate() end
    return self.active
end
