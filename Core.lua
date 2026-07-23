local addonName = ...

Actually = Actually or {}
local Addon = Actually

Addon.name = addonName or "Actually"
Addon.version = "0.1.0"
Addon.Modules = Addon.Modules or {}

function Addon:RegisterModule(name, module)
    assert(type(name) == "string" and type(module) == "table", "invalid module")
    self.Modules[name] = module
    return module
end

function Addon:Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff60d0ffActually:|r " .. tostring(message))
    end
end

function Addon:HandleSlash(input)
    local namespace, argument = string.match(tostring(input or ""), "^%s*(%S*)%s*(.-)%s*$")
    namespace = string.lower(namespace or "")
    if namespace == "arc" then
        local arc = self.Modules and self.Modules.RaidCooldowns
        if arc and arc.DebugCommands and type(arc.DebugCommands.Handle) == "function" then
            arc.DebugCommands:Handle(argument)
        else
            self:Print("Actually Raid Cooldowns is not available")
        end
    else
        self:Print("commands: /act arc <config|bundles|ui|spoof|state|peers|scan>")
    end
end

SlashCmdList.ACTUALLY_COMMAND = function(input) Addon:HandleSlash(input) end
SLASH_ACTUALLY_COMMAND1 = "/act"
SLASH_ACTUALLY_COMMAND2 = "/actually"
