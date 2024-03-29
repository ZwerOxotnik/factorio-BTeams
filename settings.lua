require("models/BetterCommands/control"):create_settings() -- Adds switchable commands

local runtime_settings = {
	{type = "int-setting",    name = "bt_team_cost", default_value = 0, minimal_value = 0, maximal_value = 400000},
	{type = "int-setting",    name = "bt_default_spawn_offset", default_value = 400, minimal_value = 50, maximal_value = 3000},
	{type = "int-setting",    name = "bt_delete_biters_radius_on_new_base", default_value = 400, minimal_value = 0, maximal_value = 3000},
	{type = "bool-setting",   name = "bt_allow_join_bandits_force", default_value = true},
	{type = "bool-setting",   name = "bt_allow_join_player_force", default_value = true},
	{type = "bool-setting",   name = "bt_allow_join_enemy_force", default_value = false},
	{type = "bool-setting",   name = "bt_allow_bandits", default_value = true},
	{type = "bool-setting",   name = "bt_allow_abandon_teams", default_value = true},
	{type = "bool-setting",   name = "bt_allow_switch_teams", default_value = true},
	{type = "bool-setting",   name = "bt_allow_rename_teams", default_value = true},
	{type = "bool-setting",   name = "bt_auto_set_base", default_value = true},
	{type = "bool-setting",   name = "bt_auto_create_teams_gui_for_new_players", default_value = true},
	{type = "bool-setting",   name = "bt_teleport_in_void_when_player_abandon_team", default_value = false},
	{type = "bool-setting",   name = "bt_teleport_in_void_when_player_kicked_from_team", default_value = false},
	{type = "bool-setting",   name = "bt_teleport_new_players_to_team_spawn_point", default_value = true},
	{type = "bool-setting",   name = "bt_show_all_forces", default_value = true},
	{type = "bool-setting",   name = "bt_create_main_base_entity", default_value = true},
	{type = "string-setting", name = "bt_default_surface", default_value = '', allow_blank = true, auto_trim = true},
	{type = "string-setting", name = "bt_spawn_method", default_value = "compact", allowed_values = {"compact", "web", "mini-web"}}
}
for _, setting in ipairs(runtime_settings) do
	setting.setting_type = "runtime-global"
end
data:extend(runtime_settings)


local runtime_per_user_settings = {
	{type = "bool-setting", name = "bt_ignore_invites", default_value = false},
}
for _, setting in ipairs(runtime_per_user_settings) do
	setting.setting_type = "runtime-per-user"
end
data:extend(runtime_per_user_settings)
