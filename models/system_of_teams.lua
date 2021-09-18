---@class ST : module
local M = {}

local team_util = require("__EasyAPI__/models/team_util")

--#region Global data
---@type table<string, any>
local mod_data
---@type table<number, number>
local forces_researched

--- {[force index] = {[player index] = number}}
---@type table<number, table<number, number>>
local players_ranks

--- {[force index] = {[1-10] = {}}}
---@type table<number, table<number, table>>
local forces_ranks

---@type table<number, table<string, any>>
local forces_permissions

--- {force index = {[player index] = tick}}
---@type table<number, table<number, number>>
local invite_requests

---@type number
local void_surface_index

---@type number
local void_force_index

--- <event name, event id>
---@type table<string, number>
local custom_EasyAPI_events
--#endregion


--#region Constants
local call = remote.call
local match = string.match
local player_force_index = 1
local enemy_force_index = 2
local neutral_force_index = 3
local LABEL = {type = "label"}
local FLOW = {type = "flow"}
local EMPTY_WIDGET = {type = "empty-widget"}
local JOIN_TEAM_BUTTON = {type = "button", style = "zk_action_button_dark", caption = "join"}
local TITLEBAR_FLOW = {type = "flow", style = "flib_titlebar_flow"}
local DRAG_HANDLER = {type = "empty-widget", style = "flib_dialog_footer_drag_handle"}
local CLOSE_BUTTON = {
	hovered_sprite = "utility/close_black",
	clicked_sprite = "utility/close_black",
	sprite = "utility/close_white",
	style = "frame_action_button",
	type = "sprite-button",
	name = "ST_close"
}
--#endregion


--#region Settings
---@type number
local max_teams = settings.global["EAPI_max_teams"].value

---@type boolean
local allow_random_team_spawn = settings.global["ST_allow_random_team_spawn"].value

---@type boolean
local allow_rename_teams = settings.global["ST_allow_rename_teams"].value

---@type boolean
local allow_create_team = settings.global["EAPI_allow_create_team"].value

---@type boolean
local allow_abandon_team = settings.global["ST_allow_abandon_team"].value

---@type boolean
local allow_switch_team = settings.global["ST_allow_switch_team"].value

---@type boolean
local allow_bandits = settings.global["ST_allow_bandits"].value

---@type boolean
local allow_join_bandits_force = settings.global["ST_allow_join_bandits_force"].value

---@type boolean
local allow_join_player_force = settings.global["ST_allow_join_player_force"].value

---@type boolean
local allow_join_enemy_force = settings.global["ST_allow_join_enemy_force"].value

---@type boolean
local show_all_forces = settings.global["ST_show_all_forces"].value

---@type string
local default_surface = settings.global["ST_default_surface"].value

---@type number
local default_spawn_offset = settings.global["ST_default_spawn_offset"].value
--#endregion


--#region utils

---@type table<string, function>
local SPAWN_METHODS = {
	---@param c_pos function
	---@param d number #distance
	---@return table? #position
	["compact"] = function(c_pos, d)
		local position = c_pos({0, d})
			or c_pos({d, 0})
			or c_pos({-d, 0})
			or c_pos({0, -d})
		if position then return position end

		local step = d / default_spawn_offset
		for i = 2, step do
			local x = default_spawn_offset * i
			local y = d - default_spawn_offset * i
			position = c_pos({x, y})
			or c_pos({-x,-y})
			or c_pos({ x,-y})
			or c_pos({-x, y})
			if position then return position end
		end
	end,
	---@param c_pos function
	---@param d number #distance
	---@return table? #position
	["mini-web"] = function(c_pos, d)
		local position = c_pos({0, d})
			or c_pos({ d, 0})
			or c_pos({-d, 0})
			or c_pos({ 0,-d})
		return position
			or c_pos({ d, d})
			or c_pos({-d,-d})
			or c_pos({ d,-d})
			or c_pos({-d, d})
	end,
	---@param c_pos function
	---@param d number #distance
	---@return table? #position
	["web"] = function(c_pos, d)
		local position = c_pos({0, d})
			or c_pos({ d, 0})
			or c_pos({-d, 0})
			or c_pos({ 0,-d})
		if position then return position end

		local step = d / default_spawn_offset
		if step <= 1 then return end

		position = c_pos({d, d})
			or c_pos({-d,-d})
			or c_pos({ d,-d})
			or c_pos({-d, d})
		if position then return position end

		if step <= 3 then return end
		local x = (d - default_spawn_offset) * 0.5
		return c_pos({x, d})
			or c_pos({-x,-d})
			or c_pos({ x,-d})
			or c_pos({-x, d})
			or c_pos({ d, x})
			or c_pos({-d,-x})
			or c_pos({ d,-x})
			or c_pos({-d, x})
	end
}
local spawn_method = SPAWN_METHODS[settings.global["ST_spawn_method"].value]

---@param player PlayerIdentification
---@return SurfaceIdentification #SurfaceIdentification
local function get_team_game_surface(player)
	if default_surface == '' then
		local surface = player.surface
		if surface.index == void_surface_index then
			return game.get_surface(1)
		else
			return player.surface
		end
	else
		surface = game.get_surface(default_surface) or game.get_surface(1)
	end
end

---@param surface SurfaceIdentification
---@return table? #position
local function get_team_spawn_position(surface)
	local is_chunk_generated = surface.is_chunk_generated
	local spawn_offset = mod_data.spawn_offset
	local position
	-- Check position
	local c_pos = function(_position)
		if is_chunk_generated(_position) == false then
			return _position
		end
	end

	while position == nil do
		position = spawn_method(c_pos, spawn_offset)
		if position == nil then
			spawn_offset = spawn_offset + default_spawn_offset
		end
	end
	surface.request_to_generate_chunks(position, 2)
	position = surface.find_non_colliding_position("character", position, 100, 5)
	mod_data.spawn_offset = spawn_offset
	return position
end

local function count_forces_researched()
	for _, force in pairs(game.forces) do
		local researched_count = 0
		for _, tech in pairs(force.technologies) do
			if tech.researched then
				researched_count = researched_count + 1
			end
		end
		forces_researched[force.index] = researched_count
	end
	mod_data.last_check_researched_tick = game.tick
end

local function make_teams_header(table)
	local dummy
	dummy = table.add(EMPTY_WIDGET)
	dummy.style.horizontally_stretchable = true
	dummy.style.minimal_width = 80
	dummy = table.add(EMPTY_WIDGET)
	dummy.style.horizontally_stretchable = true
	dummy.style.minimal_width = 50
	dummy = table.add(EMPTY_WIDGET)
	dummy.style.horizontally_stretchable = true
	dummy.style.minimal_width = 60
	dummy = table.add(EMPTY_WIDGET)
	dummy.style.horizontally_stretchable = true
	dummy.style.minimal_width = 80
	table.add(EMPTY_WIDGET)

	local label_data = {type = "label", caption = {"team-name"}}
	table.add(label_data)
	label_data.caption = "Players"
	table.add(label_data)
	label_data.caption = "Leaders"
	table.add(label_data)
	label_data.caption = "Researched"
	table.add(label_data)
	table.add(EMPTY_WIDGET)
end

local function add_row_team(add, force, force_name, force_index, label_data)
	label_data.caption = force_name
	add(label_data)
	if #force.players > 0 then
		label_data.caption = #force.connected_players .. '/' .. #force.players
		add(label_data)
		label_data.caption = force.players[1].name
		add(label_data)
	else
		add(EMPTY_WIDGET)
		add(EMPTY_WIDGET)
	end
	label_data.caption = forces_researched[force_index]
	add(label_data)

	if allow_switch_team then
		local sub = add(FLOW)
		sub.name = force_name
		sub.add(JOIN_TEAM_BUTTON).name = "ST_join_team"
	else
		add(EMPTY_WIDGET)
	end
end

---@param table table #GUIelement
---@param player PlayerIdentification
---@param teams? table
local function update_teams_table(table, player, teams)
	table.clear()
	make_teams_header(table)
	local p_force_index = player.force.index
	local label_data = {type = "label"}
	local forces = game.forces
	local add = table.add
	if show_all_forces then
		local prohibit_forces = {
			[player_force_index] = not allow_join_player_force or nil,
			[enemy_force_index] = not allow_join_enemy_force or nil,
			[neutral_force_index] = true,
			[p_force_index] = true,
			[void_force_index] = true
		}
		if mod_data.bandits_force_index and not allow_join_bandits_force then
			prohibit_forces[mod_data.bandits_force_index] = true
		end
		for force_name, force in pairs(forces) do
			local force_index = force.index
			if not prohibit_forces[force_index] then
				add_row_team(add, force, force_name, force_index, label_data)
			end
		end
	else
		if teams == nil then
			teams = call("EasyAPI", "get_teams")
		end
		for force_index, force_name in pairs(teams) do
			if p_force_index ~= force_index then
				local force = forces[force_index]
				add_row_team(add, force, force_name, force_index, label_data)
			end
		end
	end
end

local function destroy_team_gui(player)
	local ST_show_team_frame = player.gui.ST_show_team_frame
	if ST_show_team_frame then
		ST_show_team_frame.destroy()
		return
	end
end

-- TODO: change (it's too raw etc)
local function show_team_gui(player)
	local screen = player.gui.screen
	if screen.ST_show_team_frame then
		screen.ST_show_team_frame.destroy()
		return
	end

	local main_frame = screen.add{type = "frame", name = "ST_show_team_frame", direction = "vertical"}
	local top_flow = main_frame.add(TITLEBAR_FLOW)
	top_flow.add{type = "label",
		style = "frame_title",
		caption = "Your team",
		ignored_by_interaction = true
	}
	top_flow.add(DRAG_HANDLER).drag_target = main_frame
	top_flow.add(CLOSE_BUTTON)

	local shallow_frame = main_frame.add{type = "frame", name = "shallow_frame", style = "inside_shallow_frame", direction = "vertical"}
	shallow_frame.style.padding = 12

	local force = player.force
	local player_index = player.index
	local force_index = force.index
	local force_name = force.name
	local rank = players_ranks[force_index][player_index] or 1
	local is_leader = (rank >= 9) -- TODO: recheck
	local flow = shallow_frame.add(FLOW)
	flow.add(LABEL).caption = {'', "Team name", {"colon"}}
	if allow_rename_teams and is_leader then
		flow.add{type = "textfield", name = "ST_force_name", text = force_name}
		local button = flow.add{type = "button", name = "ST_rename_team", style = "zk_action_button_dark", caption = ">"}
		button.style.font = "default-dialog-button"
		button.style.top_padding = -4
		button.style.width = 30
	else
		local label = flow.add(LABEL)
		label.name = "ST_force_name"
		label.caption = force_name
	end
	if allow_abandon_team then
		local button = flow.add(JOIN_TEAM_BUTTON)
		button.name = "ST_abandon_team"
		button.caption = "abandon"
	end

	if is_leader then
		local f_connected_players = force.connected_players
		if #f_connected_players > 1 then
			local flow = shallow_frame.add(FLOW)
			flow.add(LABEL).caption = {'', "Online players", {"colon"}}

			local items = {}
			local size = 0
			for _, o_player in pairs(force.connected_players) do
				if o_player.valid and o_player.index ~= player_index then
					size = size + 1
					items[size] = o_player.name
				end
			end
			flow.add{type = "drop-down", name = "ST_online_team_players", items = items}
			flow.add(LABEL).caption = {'', "Rank", {"colon"}}
			flow.add(LABEL)
			flow.add{type = "button",name = "ST_promote", style = "zk_action_button_dark", caption = "Promote"}
			flow.add{type = "button", name = "ST_demote", style = "zk_action_button_dark", caption = "Demote"}
			flow.add{type = "button", name = "ST_kick_player", style = "zk_action_button_dark", caption = "kick"}
		end

		local flow2 = shallow_frame.add(FLOW)
		flow2.add{type = "textfield", name = "ST_team_player"}
		flow2.add{type = "button", name = "ST_promote", style = "zk_action_button_dark", caption = "Promote"}
		flow2.add{type = "button", name = "ST_demote", style = "zk_action_button_dark", caption = "Demote"}
		flow2.add{type = "button", name = "ST_invite", style = "zk_action_button_dark", caption = "Invite"}
		flow2.add{type = "button", name = "ST_kick_player", style = "zk_action_button_dark", caption = "kick"}

		local f_invite_requests = invite_requests[force_index]
		if #f_invite_requests > 0 then
			local flow3 = shallow_frame.add(FLOW)
			flow3.add(LABEL).caption = {'', "Invites (" .. #f_invite_requests  .. ')', {"colon"}}

			local items = {}
			local size = 0
			for _player_index in pairs(invite_requests[force_index]) do
				local _player = game.get_player(_player_index)
				if player.valid then
					size = size + 1
					items[size] = _player.name
				end
			end
			flow3.add{type = "drop-down", name = "ST_invites", items = items}
			flow3.add{type = "button", name = "ST_assign_leader", style = "zk_action_button_dark", caption = "accept"}
		end
	end


	main_frame.force_auto_center()
end

local function destroy_teams_frame(player)
	local ST_teams_frame = player.gui.ST_teams_frame
	if ST_teams_frame then
		ST_teams_frame.destroy()
		return
	end
end

local function create_teams_gui(player)
	local screen = player.gui.screen
	if screen.ST_teams_frame then
		screen.ST_teams_frame.destroy()
		return
	end

	local main_frame = screen.add{type = "frame", name = "ST_teams_frame", direction = "vertical"}
	local top_flow = main_frame.add(TITLEBAR_FLOW)
	top_flow.add{type = "label",
		style = "frame_title",
		caption = "Teams",
		ignored_by_interaction = true
	}
	top_flow.add(DRAG_HANDLER).drag_target = main_frame
	top_flow.add{
		type = "sprite-button",
		name = "ST_refresh_teams_table",
		style = "frame_action_button",
		sprite = "refresh_white_icon"
	}
	top_flow.add(CLOSE_BUTTON)

	local shallow_frame = main_frame.add{type = "frame", name = "shallow_frame", style = "inside_shallow_frame", direction = "vertical"}
	shallow_frame.style.padding = 12

	local teams = call("EasyAPI", "get_teams")
	if allow_create_team and #game.forces < 64 and #teams < max_teams then
		local create_team_flow = shallow_frame.add{type = "flow"}
		create_team_flow.add{type = "label", caption = {'', "Create team", {"colon"}}}
		create_team_flow.add{type = "textfield", name = "team_name"}
		local button = create_team_flow.add{type = "button", name = "ST_create_team", style = "zk_action_button_dark", caption = ">"}
		button.style.font = "default-dialog-button"
		button.style.top_padding = -4
		button.style.width = 30
	end

	local table_frame = shallow_frame.add{type = "frame", name = "table_frame", style = "deep_frame_in_shallow_frame", direction = "vertical"}
	table_frame.style.top_margin = 10
	local teams_table = table_frame.add{type = "table", name = "teams_table", column_count = 5}
	teams_table.style.column_alignments[1] = "center"
	teams_table.style.column_alignments[2] = "center"
	teams_table.style.column_alignments[3] = "center"
	teams_table.style.column_alignments[4] = "center"
	teams_table.draw_horizontal_lines = true
	teams_table.draw_vertical_lines = true
	teams_table.style.top_margin = -3

	if mod_data.last_check_researched_tick > game.tick + 36000 then
		count_forces_researched()
	end
	update_teams_table(teams_table, player, teams)

	main_frame.force_auto_center()
end

local left_anchor = {gui = defines.relative_gui_type.controller_gui, position = defines.relative_gui_position.left}
local function create_left_relative_gui(player)
	local relative = player.gui.relative
	if relative.ST_buttons then
		relative.ST_buttons.destroy()
	end
	local main_table = relative.add{type = "table", name = "ST_buttons", anchor = left_anchor, column_count = 2}
	-- main_table.style.vertical_align = "center"
	main_table.style.horizontal_spacing = 0
	main_table.style.vertical_spacing = 0
	main_table.add{type = "sprite-button", sprite = "ST_customize_team", style="slot_button", name = "ST_customize_team"}
	main_table.add{type = "sprite-button", sprite = "ST_teams", style="slot_button", name = "ST_teams"}
end

--#endregion


--#region Functions of events

local function on_player_created(event)
	local player = game.get_player(event.player_index)
	create_left_relative_gui(player)
end

local function on_forces_merging(event)
	for _, player in pairs(event.source.connected_players) do
		if player.valid then
			destroy_team_gui(player)
			destroy_teams_frame(player)
		end
	end
end

local function on_forces_merged(event)
	local index = event.source_index
	forces_permissions[index] = nil
	forces_researched[index] = nil
	invite_requests[index] = nil
	players_ranks[index] = nil
	forces_ranks[index] = nil
end

local EAPI_settings = {
	["EAPI_allow_create_team"] = function(value) allow_create_team = value end,
	["EAPI_max_teams"] = function(value) max_teams = value end
}
local mod_settings = {
	["ST_allow_random_team_spawn"] = function(value) allow_random_team_spawn = value end,
	["ST_allow_abandon_team"] = function(value) allow_abandon_team = value end,
	["ST_allow_rename_teams"] = function(value) allow_rename_teams = value end,
	["ST_allow_switch_team"] = function(value) allow_switch_team = value end,
	["ST_allow_bandits"] = function(value)
		allow_bandits = value
		if allow_bandits then
			if game.forces.bandits == nil then
				mod_data.bandits_force_index = game.create_force("bandits").index
			end
		end
	end,
	["ST_allow_join_bandits_force"] = function(value) allow_join_bandits_force = value end,
	["ST_allow_join_player_force"] = function(value) allow_join_player_force = value end,
	["ST_allow_join_enemy_force"] = function(value) allow_join_enemy_force = value end,
	["ST_show_all_forces"] = function(value) show_all_forces = value end,
	["ST_default_surface"] = function(value) default_surface = value end,
	["ST_default_spawn_offset"] = function(value)
		default_spawn_offset = value
		mod_data.spawn_offset = math.floor(mod_data.spawn_offset/value) * value
	end,
	["ST_spawn_method"] = function(value) spawn_method = SPAWN_METHODS[value] end
}
local function on_runtime_mod_setting_changed(event)
	-- if event.setting_type ~= "runtime-global" then return end
	local setting_name = event.setting
	if match(setting_name, "^ST_") then
		local f = mod_settings[setting_name]
		if f then f(settings.global[setting_name].value) end
	elseif match(setting_name, "^EAPI_") then
		local f = EAPI_settings[setting_name]
		if f then f(settings.global[setting_name].value) end
	end
end

local GUIS = {
	ST_close = function(element)
		element.parent.parent.destroy()
	end,
	ST_customize_team = function(element, player)
		local force_index = player.force.index
		if forces_permissions[force_index] == nil then
			player.print("This force doesn't support this action")
			return
		end
		show_team_gui(player)
	end,
	ST_teams = function(element, player)
		create_teams_gui(player)
	end,
	ST_refresh_teams_table = function(element, player)
		update_teams_table(element.parent.parent.shallow_frame.table_frame.teams_table, player)
	end,
	ST_create_team = function(element, player)
		if not allow_create_team then
			player.print("ERROR-1")
			return
		end

		local parent = element.parent
		local team_name = parent.team_name.text
		local new_team = team_util.create_team(team_name, player)
		if not (new_team and new_team.valid) then
			return
		end
		local is_solo_team = true
		if #player.force.players > 1 then
			is_solo_team = false
		end
		parent.parent.parent.destroy()
		player.force = new_team

		-- if is_solo_team then return end -- TODO: change
		if not allow_random_team_spawn then return end

		local surface = get_team_game_surface(player)
		local position = get_team_spawn_position(surface)
		if position then
			player.teleport(position, surface)
			local DESTROY_TYPE = {raise_destroy = true}
			for _, entity in pairs(surface.find_enemy_units(position, 200, new_team)) do
				entity.destroy(DESTROY_TYPE)
			end
			new_team.set_spawn_position(position, surface)
		end
	end,
	ST_abandon_team = function(element, player)
		player.force = "void"
		player.teleport({player.index * 150, 0}, game.get_surface(void_surface_index))
		player.gui.screen.ST_show_team_frame.destroy()
	end,
	ST_join_team = function(element, player)
		local force = game.forces[element.parent.name]
		if not (force and force.valid) then
			player.print("ERROR")
			return
		end

		player.force = force
		local surface = get_team_game_surface(player)
		local position = force.get_spawn_position(surface)
		player.teleport(position, surface)
		player.gui.screen.ST_teams_frame.destroy() -- TODO: change
	end
}
local function on_gui_click(event)
	local player = game.get_player(event.player_index)
	local element = event.element
	-- if element.get_mod() ~= "system_of_teams" then return end

	if match(element.name, "^ST_") then
		local f = GUIS[element.name]
		if f then f(element, player) end
	end
end

local function on_force_created(event)
	local force = event.force
	local researched_count = 0
	for _, tech in pairs(force.technologies) do
		if tech.researched then
			researched_count = researched_count + 1
		end
	end
	forces_researched[force.index] = researched_count
end

local function on_player_joined_game(event)
	local player = game.get_player(event.player_index)
	destroy_team_gui(player)
	destroy_teams_frame(player)
end

local function on_player_left_game(event)
	local player = game.get_player(event.player_index)
	destroy_team_gui(player)
	destroy_teams_frame(player)
end

local function on_pre_player_removed(event)
	local player_index = event.player_index
	local force_index = game.get_player(event.player_index).force.index
	players_ranks[force_index][player_index] = nil
	-- TODO: delete invite in invite_requests etc
end

local function on_new_team(event)
	local index = event.force.index
	forces_permissions[index] = {}
	invite_requests[index] = {}
	players_ranks[index] = {}
	forces_ranks[index] = {}
end

local function on_pre_deleted_team(event)
	local index = event.force.index
	forces_permissions[index] = nil
	invite_requests[index] = nil
	players_ranks[index] = nil
	forces_ranks[index] = nil
end

local function on_player_joined_team(event)
	if #event.force.players == 1 then
		local force_index = event.force.index
		if mod_data.bandits_force_index and force_index == mod_data.bandits_force_index then
			return
		end
		players_ranks[force_index] = {[event.player_index] = 10}
	end
end

--#endregion


--#region Pre-game stage

local function set_filters()
	-- local filters = {
	-- 	{filter = "type", mode = "or", type = "container"},
	-- 	{filter = "type", mode = "or", type = "logistic-container"},
	-- }
	-- script.set_event_filter(defines.events.on_entity_died, filters)
end

local function add_remote_interface()
	-- https://lua-api.factorio.com/latest/LuaRemote.html
	remote.remove_interface("system_of_teams") -- For safety
	remote.add_interface("system_of_teams", {
		get_mod_data = function()
			return mod_data
		end,
		get_bandits_force_index = function()
			return mod_data.bandits_force_index
		end,
		get_spawn_offset = function()
			return mod_data.spawn_offset
		end,
		get_players_ranks = function()
			return players_ranks
		end,
		get_forces_ranks = function()
			return forces_ranks
		end
	})
end

local function link_data()
	mod_data = global.ST
	forces_permissions = mod_data.forces_permissions
	forces_researched = mod_data.forces_researched
	invite_requests = mod_data.invite_requests
	players_ranks = mod_data.players_ranks
	forces_ranks = mod_data.forces_ranks
	custom_EasyAPI_events = team_util.custom_events
	void_surface_index = call("EasyAPI", "get_void_surface_index")
	void_force_index = call("EasyAPI", "get_void_force_index")
end

local function update_global_data()
	global.ST = global.ST or {}
	mod_data = global.ST
	mod_data.forces_researched = {}
	mod_data.spawn_offset = mod_data.spawn_offset or default_spawn_offset
	mod_data.forces_permissions = mod_data.forces_permissions or {}
	mod_data.invite_requests = mod_data.invite_requests or {}
	mod_data.players_ranks = mod_data.players_ranks or {}
	mod_data.forces_ranks = mod_data.forces_ranks or {}

	link_data()

	if allow_bandits then
		if game.forces.bandits == nil then
			mod_data.bandits_force_index = game.create_force("bandits").index
		end
	end

	count_forces_researched()

	for _, player in pairs(game.players) do
		if player.valid then
			local relative = player.gui.relative
			if relative.ST_buttons == nil then
				create_left_relative_gui(player)
			end
			destroy_teams_frame(player)
			destroy_team_gui(player)
		end
	end

	for force_index in pairs(forces_ranks) do
		if game.forces[force_index] == nil then
			forces_ranks[force_index] = nil
		end
	end

	for force_index in pairs(forces_permissions) do
		if game.forces[force_index] == nil then
			forces_permissions[force_index] = nil
		end
	end

	for force_index, players_data in pairs(players_ranks) do
		if game.forces[force_index] == nil then
			players_ranks[force_index] = nil
		else
			for player_index in pairs(players_data) do
				local player = game.get_player(player_index)
				if not (player and player.valid) then
					players_data[player_index] = nil
				end
			end
		end
	end

	for force_index, players_data in pairs(invite_requests) do
		if game.forces[force_index] == nil then
			invite_requests[force_index] = nil
		else
			for player_index in pairs(players_data) do
				local player = game.get_player(player_index)
				if not (player and player.valid) then
					players_data[player_index] = nil
				end
			end
		end
	end
end

local function handle_custom_events()
	script.on_event(custom_EasyAPI_events.on_new_team, on_new_team)
	script.on_event(custom_EasyAPI_events.on_pre_deleted_team, on_pre_deleted_team)
	script.on_event(custom_EasyAPI_events.on_player_joined_team, on_player_joined_team)
	-- script.on_event(custom_EasyAPI_events.on_player_left_team, on_player_left_team)
	-- custom_events.on_team_invited
	-- custom_events.on_player_accepted_invite
end

M.on_init = function()
	team_util.on_init()
	update_global_data()
	handle_custom_events()
	set_filters()
end
M.on_load = function()
	team_util.on_load()
	link_data()
	handle_custom_events()
	set_filters()
end
M.on_configuration_changed = update_global_data
M.add_remote_interface = add_remote_interface

--#endregion


M.events = {
	[defines.events.on_runtime_mod_setting_changed] = on_runtime_mod_setting_changed,
	-- [defines.events.on_game_created_from_scenario] = on_game_created_from_scenario,
	[defines.events.on_forces_merged] = on_forces_merged,
	[defines.events.on_forces_merging] = on_forces_merging,
	[defines.events.on_gui_click] = function(event)
		on_gui_click(event)
		-- pcall(on_gui_click, event)
	end,
	[defines.events.on_player_created] = function(event)
		pcall(on_player_created, event)
	end,
	[defines.events.on_force_created] = function(event)
		pcall(on_force_created, event)
	end,
	[defines.events.on_player_joined_game] = function(event)
		pcall(on_player_joined_game, event)
	end,
	[defines.events.on_player_left_game] = function(event)
		pcall(on_player_left_game, event)
	end,
	[defines.events.on_pre_player_removed] = function(event)
		pcall(on_pre_player_removed, event)
	end
}


return M
