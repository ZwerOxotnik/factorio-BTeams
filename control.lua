if script.level.campaign_name then return end -- Don't init if it's a campaign

local event_handler = require("__zk-lib__/static-libs/lualibs/event_handler_vZO.lua")


---@type table<string, module>
local modules = {}
modules.better_commands = require("models/BetterCommands/control")
modules.BTeams = require("models/BTeams")


modules.better_commands:handle_custom_commands(modules.BTeams) -- adds commands

event_handler.add_libraries(modules)


-- This is a part of "gvv", "Lua API global Variable Viewer" mod. https://mods.factorio.com/mod/gvv
-- It makes possible gvv mod to read sandboxed variables in the map or other mod if following code is inserted at the end of empty line of "control.lua" of each.
if script.active_mods["gvv"] then require("__gvv__.gvv")() end
