local runtime_settings = {
	{type = "int-setting",    name = "bt_default_spawn_offset", default_value = 400, minimal_value = 50, maximal_value = 3000},
	{type = "bool-setting",   name = "bt_allow_random_team_spawn", default_value = true},
	{type = "bool-setting",   name = "bt_allow_join_bandits_force", default_value = true},
	{type = "bool-setting",   name = "bt_allow_join_player_force", default_value = true},
	{type = "bool-setting",   name = "bt_allow_join_enemy_force", default_value = false},
	{type = "bool-setting",   name = "bt_allow_abandon_team", default_value = true},
	{type = "bool-setting",   name = "bt_allow_switch_team", default_value = true},
	{type = "bool-setting",   name = "bt_allow_rename_teams", default_value = true},
	{type = "bool-setting",   name = "bt_allow_bandits", default_value = true},
	{type = "bool-setting",   name = "bt_show_all_forces", default_value = true},
	{type = "string-setting", name = "bt_default_surface", default_value = '', allow_blank = true, auto_trim = true},
	{type = "string-setting", name = "bt_spawn_method", default_value = "compact", allowed_values = {"compact", "web", "mini-web"}}
}
for _, setting in pairs(runtime_settings) do
	setting.setting_type = "runtime-global"
end
data:extend(runtime_settings)
