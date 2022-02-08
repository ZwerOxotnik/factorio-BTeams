-- Recommended to know about https://lua-api.factorio.com/latest/LuaCommandProcessor.html#LuaCommandProcessor.add_command

--[[
Returns tables of commands without functions as command "settings". All parameters are optional!
  Contains:
    name :: string: The name of your /command. (default: key of the table)
    description :: string or LocalisedString: The description of your command. (default: nil)
    is_allowed_empty_args :: boolean: Ignores empty parameters in commands, otherwise stops the command. (default: true)
    input_type :: string: filter for parameters by type of input. (default: nil)
      possible variants:
        "player" - Stops execution if can't find a player by parameter
        "team" - Stops execution if can't find a team (force) by parameter
    allow_for_server :: boolean: Allow execution of a command from a server (default: false)
    only_for_admin :: boolean: The command can be executed only by admins (default: false)
		default_value :: boolean: default value for settings (default: true)
]]--
---@type table<string, table>
return {
	open_team_gui = {name = "open-team-gui"},
	open_teams_gui = {name = "open-teams-gui"},
	accept_team_invite = {name = "accept-team-invite", is_allowed_empty_args = false},
	show_team_invites = {name = "show-team-invites"},
	invite_in_team = {name = "invite-in-team", input_type = "player"},
	kick_teammate = {name = "kick-teammate", input_type = "player"},
	join_team = {name = "join-team", input_type = "team"},
	set_base = {name = "set-base"},
	abandon_team = {name = "abandon-team"},
}
