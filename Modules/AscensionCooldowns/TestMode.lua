local ACD = Actually.Modules.AscensionCooldowns
local TestMode = ACD:NewModule("TestMode")

function TestMode:Populate()
    local now = ACD:Now()
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
    ACD.Renderer:MarkDirty("test populate")
    ACD.Renderer:Reconcile()
end

function TestMode:Clear()
    self.active = false
    self.players = nil
    ACD.Renderer:MarkDirty("test clear")
    ACD.Renderer:Reconcile()
end

function TestMode:Toggle()
    if self.active then self:Clear() else self:Populate() end
    return self.active
end
