---@class BT : module
local M = {}


local team_util   = require("__EasyAPI__/models/team_util")
local force_util  = require("zk-lib/lualibs/control_stage/force-util")
local player_util = require("zk-lib/lualibs/control_stage/player-util")


--#region Global data
---@type table<string, any>
local _mod_data

--- {[force index] = count of researched techs}}
---@type table<uint, integer>
local _forces_researched

---@class force_settings
---@type table<uint, table<string, any>>
local _team_settings


---@class teams_main_base_structure_data
---@field force LuaForce
---@field entity LuaEntity

---@type table<uint, teams_main_base_structure_data>
local _teams_main_base_structure


---{[force index] = {player index}}
---@class first_team_players
---@type table<integer, integer[]>
local _first_team_players

--- {[force index] = {[player index] = tick}}
---@type table<uint, table<integer, integer>>
local _force_invite_requests

---TODO: add events
-- {[player index] = {[force index] = {invite id, LuaPlayer, tick of invitation}}}
---@class player_invite_requests
---@type table<uint, table<uint, table[]>>
--- [1] integer # Invite id
--- [2] LuaPlayer
--- [3] integer # Tick of invitation
local _player_invite_requests

---@type integer
local _void_surface_index

---@type integer
local _void_force_index
--#endregion


--#region Constants
local table = table
local tonumber = tonumber
local find = string.find
local call = remote.call
local player_force_index = 1
local enemy_force_index = 2
local neutral_force_index = 3
local DESTROY_PARAM = {raise_destroy = true} --[[@as LuaEntity.destroy_param]]
local LABEL = {type = "label"}
local FLOW = {type = "flow"}
local EMPTY_WIDGET = {type = "empty-widget"}
local JOIN_TEAM_BUTTON = {type = "button", style = "zk_action_button_dark", caption = {"gui-menu.continue-join-game-tooltip", ''}}
local TITLEBAR_FLOW = {type = "flow", style = "flib_titlebar_flow"}
local DRAG_HANDLER = {type = "empty-widget", style = "flib_dialog_footer_drag_handle"}
local SEARCH_BUTTON = {
	type = "sprite-button",
	name = "bt_search",
	style = "zk_action_button_dark",
	sprite = "utility/search_white",
	hovered_sprite = "utility/search_black",
	clicked_sprite = "utility/search_black"
}
local CLOSE_BUTTON = {
	hovered_sprite = "utility/close_black",
	clicked_sprite = "utility/close_black",
	sprite = "utility/close_white",
	style = "frame_action_button",
	type = "sprite-button",
	name = "bt_close"
}
--#endregion


--#region Settings
local _max_teams = settings.global["EAPI_max_teams"].value --[[@as integer]]
local _allow_rename_teams = settings.global["bt_allow_rename_teams"].value --[[@as boolean]]
local _allow_create_team = settings.global["EAPI_allow_create_team"].value --[[@as boolean]]
local _allow_abandon_teams = settings.global["bt_allow_abandon_teams"].value --[[@as boolean]]
local _allow_switch_teams = settings.global["bt_allow_switch_teams"].value --[[@as boolean]]
local _allow_bandits = settings.global["bt_allow_bandits"].value --[[@as boolean]]
local _allow_join_bandits_force = settings.global["bt_allow_join_bandits_force"].value --[[@as boolean]]
local _allow_join_player_force = settings.global["bt_allow_join_player_force"].value --[[@as boolean]]
local _allow_join_enemy_force = settings.global["bt_allow_join_enemy_force"].value --[[@as boolean]]
local _show_all_forces = settings.global["bt_show_all_forces"].value --[[@as boolean]]
local _default_surface = settings.global["bt_default_surface"].value --[[@as integer]]
local _default_spawn_offset = settings.global["bt_default_spawn_offset"].value --[[@as integer]]
--#endregion


--#region utils

---@param player table #LuaPlayer
---@return boolean
local function get_is_leader(player)
	local players = _first_team_players[player.force.index]
	if players then
		return (players[1] == player.index)
	else
		return false
	end
end

---@type table<string, fun(c_pos: function, d: number): table?>
local SPAWN_METHODS = {
	---@param c_pos function
	---@param d number #distance
	---@return table? #position
	["compact"] = function(c_pos, d)
		local position = c_pos({0, d})
			or c_pos({ d, 0})
			or c_pos({-d, 0})
			or c_pos({ 0,-d})
		if position then return position end

		local step = d / _default_spawn_offset
		for i = 2, step do
			local x = _default_spawn_offset * i
			local y = d - _default_spawn_offset * i
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

		local step = d / _default_spawn_offset
		if step <= 1 then return end

		position = c_pos({d, d})
			or c_pos({-d,-d})
			or c_pos({ d,-d})
			or c_pos({-d, d})
		if position then return position end

		if step <= 3 then return end
		local x = (d - _default_spawn_offset) * 0.5
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
_spawn_method = SPAWN_METHODS[settings.global["bt_spawn_method"].value]


---@param player LuaPlayer
function abandon_team(player)
	local prev_force = player.force

	if settings.global["bt_teleport_in_void_when_player_abandon_team"].value then
		if prev_force.name == "void" then return end
		player.ticks_to_respawn = nil -- respawn
		player.force = "void"
		player.teleport({player.index * 150, 0}, game.get_surface(_void_surface_index))
	else
		if prev_force.name == "player" then return end
		player.ticks_to_respawn = nil -- respawn
		-- WIP
		player.force = "player"
	end

	if #prev_force.players == 0 then
		local forces = game.forces
		if prev_force == forces.neutral then return end
		if prev_force == forces.enemy then return end
		if prev_force == forces.player then return end
		if _void_force_index and prev_force.index == _void_force_index then return end
		if _mod_data.bandits_force_index and prev_force.index == _mod_data.bandits_force_index then return end

		if call("EasyAPI", "find_team", prev_force.index) and
		   call("EasyAPI", "is_team_deletable", prev_force.index)
		then
			game.merge_forces(prev_force, forces.neutral)
		end
	end
end


---@param player table #LuaPlayer
---@return table #LuaSurface
local function get_team_game_surface(player)
	if _default_surface == '' then
		local surface = player.surface
		if surface.index == _void_surface_index then
			return game.get_surface(1)
		else
			return player.surface
		end
	else
		return game.get_surface(_default_surface) or game.get_surface(1)
	end
end


---@param surface table #LuaSurface
---@param team table #LuaForce
---@return table? #position
local function get_team_spawn_position(surface, team)
	local is_chunk_generated = surface.is_chunk_generated
	local spawn_offset = _mod_data.spawn_offset
	local position

	local spawn_filter = {
		position = nil,
		limit = 1,
		radius = 300,
		force = {team, "enemy", "neutral"},
		invert = true
	}

	-- Check position
	local find_entities_filtered = surface.find_entities_filtered
	local c_pos = function(pos)
		if is_chunk_generated(pos) == false then
			spawn_filter.position = pos
			if #find_entities_filtered(spawn_filter) == 0 then
				return pos
			end
		end
	end

	while position == nil do
		position = _spawn_method(c_pos, spawn_offset)
		if position == nil then
			spawn_offset = spawn_offset + _default_spawn_offset
		end
	end
	surface.request_to_generate_chunks(position, 2) -- Perhaps, it should be 9 insted of 2
	position = surface.find_non_colliding_position(
		"character", position, 100, 5
	)
	_mod_data.spawn_offset = spawn_offset
	return position
end


---@param player table #LuaPlayer
local function set_team_base(player)
	local target_surface = get_team_game_surface(player)
	--TODO: improve!
	if target_surface.index == _void_surface_index then
		--TODO: change message
		player.print("It's not possible to create bases in void surface")
	end

	local player_force = player.force
	if call("EasyAPI", "has_team_base_by_index", player_force.index) then
		player_force.print("Your team has a base already", {1, 0, 0})
		return
	end

	if _mod_data.bandits_force_index and player_force.index == _mod_data.bandits_force_index then
		player_force.print("Your team can't have a base", {1, 0, 0})
		return
	end

	local new_position
	if settings.global["bt_auto_set_base"].value then
		new_position = get_team_spawn_position(target_surface, player_force)
		if new_position == nil then
			player.print("no suitable place found for base. Try again later.")
			return
		end
	else
		local near_team_entities = target_surface.find_entities_filtered({
			position = player.position,
			limit = 1,
			radius = 300,
			force = {player_force, "enemy", "neutral"},
			invert = true
		}) -- TODO: change
		if #near_team_entities == 0 then
			new_position = player.position
		else
			player.print("There are enemies nearby")
			return
		end
	end

	player_force.set_spawn_position(new_position, target_surface)
	call("EasyAPI", "change_team_base", player_force, target_surface, new_position)

	local no_biters_radius = settings.global["bt_delete_biters_radius_on_new_base"].value
	if no_biters_radius > 0 then
		local enemies = target_surface.find_entities_filtered{
			position = new_position,
			radius = no_biters_radius,
			force = "enemy"
		}
		local DESTROY_TYPE = {raise_destroy = true}
		-- TODO: improve because it won't delete in non-loaded chunks
		for i=#enemies, 1, -1 do
			enemies[i].destroy(DESTROY_TYPE)
		end
	end


	if settings.global["bt_create_main_base_entity"].value then
		-- TODO: create silo
		local entity = _teams_main_base_structure[player_force.index]
		if not (entity and entity.valid) then
			entity = target_surface.create_entity{
				name = "rocket-silo",
				position = new_position,
				force = player_force
			} -- perhaps, wrong position
			local id = script.register_on_entity_destroyed(entity)
			_teams_main_base_structure[id] = {
				force  = player_force,
				entity = entity
			}
		end
	end

	player_util.teleport_safely(player, target_surface, new_position)

	--TODO: change message
	game.print(
		"New base has been established in the game",
		{1, 1, 0}
	)
	player_force.print(
		"Your team's base established at [gps=" .. new_position.x .. "," .. new_position.y .. "," .. target_surface.name .. "]",
		{1, 1, 0}
	)
end


local function count_forces_researched()
	for _, force in pairs(game.forces) do
		_forces_researched[force.index] = force_util.count_techs(force)
	end
	_mod_data.last_check_researched_tick = game.tick
end


local function make_teams_header(table)
	local add = table.add
	local style
	style = add(EMPTY_WIDGET).style
	style.horizontally_stretchable = true
	style.minimal_width = 80
	style = add(EMPTY_WIDGET).style
	style.horizontally_stretchable = true
	style.minimal_width = 50
	style = add(EMPTY_WIDGET).style
	style.horizontally_stretchable = true
	style.minimal_width = 60
	style = add(EMPTY_WIDGET).style
	style.horizontally_stretchable = true
	style.minimal_width = 80
	add(EMPTY_WIDGET)

	local caption = {"team-name"}
	local label_data = {type = "label", caption = caption}
	add(label_data)
	caption[1] = "gui-browse-games.players"
	label_data.caption = caption
	add(label_data)
	label_data.caption = "Leaders"
	add(label_data)
	caption[1] = "gui-technology-preview.status-researched"
	label_data.caption = caption
	add(label_data)
	add(EMPTY_WIDGET)
end

local function add_row_team(add, force, force_name, force_index, label_data)
	label_data.caption = force_name
	add(label_data)
	if #force.players > 0 then
		label_data.caption = #force.connected_players .. '/' .. #force.players
		add(label_data)
		local player_index = _first_team_players[force.index][1]
		if player_index then
			label_data.caption = game.get_player(player_index).name
			add(label_data)
		else
			add(EMPTY_WIDGET)
		end
	else
		add(EMPTY_WIDGET)
		add(EMPTY_WIDGET)
	end
	label_data.caption = _forces_researched[force_index]
	add(label_data)

	if _allow_switch_teams then
		local bandits_force_index = _mod_data.bandits_force_index
		if #force.players == 0 or
			force_index == player_force_index or
			force_index == enemy_force_index or
			(bandits_force_index and force_index == bandits_force_index)
		then
			local sub = add(FLOW)
			sub.name = force_name
			sub.add(JOIN_TEAM_BUTTON).name = "bt_join_team"
		else
			add(EMPTY_WIDGET)
		end
	else
		add(EMPTY_WIDGET)
	end
end

local function add_row_force(add, force, force_name, force_index, label_data, teams)
	label_data.caption = force_name
	add(label_data)
	if #force.players > 0 then
		label_data.caption = #force.connected_players .. '/' .. #force.players
		add(label_data)
		add(EMPTY_WIDGET)
	else
		add(EMPTY_WIDGET)
		add(EMPTY_WIDGET)
	end
	label_data.caption = _forces_researched[force_index]
	add(label_data)

	if _allow_switch_teams then
		local bandits_force_index = _mod_data.bandits_force_index
		if #force.players == 0 or
			force_index == player_force_index or
			force_index == enemy_force_index or
			(bandits_force_index and force_index == bandits_force_index)
		then
			local sub = add(FLOW)
			sub.name = force_name -- Perhaps, it's not neccesary
			if teams[force_index] then
				sub.add(JOIN_TEAM_BUTTON).name = "bt_join_team"
			end
		else
			add(EMPTY_WIDGET)
		end
	else
		add(EMPTY_WIDGET)
	end
end

---@param table_gui table #GUIelement
---@param player table #LuaPlayer
---@param teams? table
local function update_teams_table(table_gui, player, teams)
	table_gui.clear()
	make_teams_header(table_gui)
	local p_force_index = player.force.index
	local label_data = {type = "label"}
	local forces = game.forces
	local add = table_gui.add

	if teams == nil then
		teams = call("EasyAPI", "get_teams")
	end
	if not _show_all_forces then
		for force_index, force_name in pairs(teams) do
			if p_force_index ~= force_index then
				local force = forces[force_index]
				add_row_team(add, force, force_name, force_index, label_data)
			end
		end
		return
	end

	local prohibit_forces = {
		[player_force_index] = not _allow_join_player_force or nil,
		[enemy_force_index] = not _allow_join_enemy_force or nil,
		[neutral_force_index] = true,
		[p_force_index] = true,
		[_void_force_index] = true
	}
	if _mod_data.bandits_force_index and not _allow_join_bandits_force then
		prohibit_forces[_mod_data.bandits_force_index] = true
	end
	for force_name, force in pairs(forces) do
		local force_index = force.index
		if not prohibit_forces[force_index] then
			add_row_force(add, force, force_name, force_index, label_data, teams)
		end
	end
end

function M.destroy_team_gui(player)
	local bt_show_team_frame = player.gui.screen.bt_show_team_frame
	if bt_show_team_frame then
		bt_show_team_frame.destroy()
		return
	end
end

--TODO: change (it's too raw etc)
local function switch_team_gui(player)
	local screen = player.gui.screen
	if screen.bt_show_team_frame then
		screen.bt_show_team_frame.destroy()
		return
	end

	local main_frame = screen.add{type = "frame", name = "bt_show_team_frame", direction = "vertical"}
	local top_flow = main_frame.add(TITLEBAR_FLOW)
	top_flow.add{
		type = "label",
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
	local force_name = force.name
	local is_leader = get_is_leader(player)
	local flow1 = shallow_frame.add(FLOW)
	flow1.add(LABEL).caption = {'', "Team name", {"colon"}}
	if _allow_rename_teams and is_leader then
		flow1.add{type = "textfield", name = "bt_force_name", text = force_name}.style.width = 100
		local button = flow1.add{type = "button", name = "bt_rename_team", style = "zk_action_button_dark", caption = ">"}
		button.style.font = "default-dialog-button"
		button.style.top_padding = -4
		button.style.width = 30
	else
		local label = flow1.add(LABEL)
		label.name = "bt_force_name"
		label.caption = force_name
	end
	if _allow_abandon_teams then
		local button = flow1.add(JOIN_TEAM_BUTTON)
		button.name = "bt_abandon_team"
		button.caption = "abandon"
		button.style.maximal_width = 0
	end

	if is_leader then
		local flow3 = shallow_frame.add(FLOW)
		flow3.style.top_padding = 4
		flow3.add{type = "textfield", name = "bt_team_player"}.style.width = 171
		flow3.add(SEARCH_BUTTON)

		local flow4 = shallow_frame.add(FLOW)
		flow4.name = "bt_flow_with_player_actions"
		flow4.style.top_padding = 4

		local dropdown = flow4.add{type = "drop-down", name = "bt_found_team_players"}
		local found_players = {}
		for index, _player in pairs(game.players) do
			if index ~= player_index then
				found_players[#found_players+1] = _player.name
			end
		end
		if #found_players > 0 then
			dropdown.items = found_players
			dropdown.selected_index = 1
		end

		-- flow4.add{type = "button", name = "bt_promote", style = "zk_action_button_dark", caption = {"gui-player-management.promote"}}.style.maximal_width = 0
		-- flow4.add{type = "button", name = "bt_demote", style = "zk_action_button_dark", caption = {"gui-player-management.demote"}}.style.maximal_width = 0
		local invite_button = flow4.add{type = "button", name = "bt_invite", style = "zk_action_button_dark", caption = "Invite"}
		invite_button.style.maximal_width = 0
		local kick_button = flow4.add{type = "button", name = "bt_kick_player", style = "zk_action_button_dark", caption = {"gui-player-management.kick"}}
		kick_button.style.maximal_width = 0
		if #found_players == 0 then
			invite_button.visible = false
			kick_button.visible = false
			dropdown.visible = false
		else
			if game.get_player(found_players[dropdown.selected_index]).force == player.force then
				invite_button.visible = false
			else
				kick_button.visible = false
			end
		end

		-- local f_invite_requests = force_invite_requests[force_index]
		-- if #f_invite_requests > 0 then
		-- 	local flow5 = shallow_frame.add(FLOW)
		-- 	flow5.style.top_padding = 4
		-- 	flow5.add(LABEL).caption = {'', "Invites (" .. #f_invite_requests  .. ')', {"colon"}}

		-- 	local items = {}
		-- 	local size = 0
		-- 	for _player_index in pairs(force_invite_requests[force_index]) do
		-- 		local _player = game.get_player(_player_index)
		-- 		if player.valid then
		-- 			size = size + 1
		-- 			items[size] = _player.name
		-- 		end
		-- 	end
		-- 	flow5.add{type = "drop-down", name = "bt_invites", items = items}
		-- 	flow5.add{type = "button", name = "bt_assign_leader", style = "zk_action_button_dark", caption = "accept"}
		-- end
	end

	main_frame.force_auto_center()
end

function M.destroy_teams_frame(player)
	local bt_teams_frame = player.gui.screen.bt_teams_frame
	if bt_teams_frame then
		bt_teams_frame.destroy()
		return
	end
end

local function switch_teams_gui(player)
	local screen = player.gui.screen
	if screen.bt_teams_frame then
		screen.bt_teams_frame.destroy()
		return
	end

	local main_frame = screen.add{type = "frame", name = "bt_teams_frame", direction = "vertical"}
	local top_flow = main_frame.add(TITLEBAR_FLOW)
	top_flow.add{type = "label",
		style = "frame_title",
		caption = "Teams",
		ignored_by_interaction = true
	}
	top_flow.add(DRAG_HANDLER).drag_target = main_frame
	top_flow.add{
		type = "sprite-button",
		name = "bt_refresh_teams_table",
		style = "frame_action_button",
		sprite = "refresh_white_icon"
	}
	top_flow.add(CLOSE_BUTTON)

	local shallow_frame = main_frame.add{type = "frame", name = "shallow_frame", style = "inside_shallow_frame", direction = "vertical"}
	shallow_frame.style.padding = 12

	local teams = call("EasyAPI", "get_teams")
	if _allow_create_team and #game.forces < 64 and #teams < _max_teams then
		local create_team_flow = shallow_frame.add{type = "flow"}
		create_team_flow.add{type = "label", caption = {'', "Create team", {"colon"}}}
		create_team_flow.add{type = "textfield", name = "team_name"}
		local button = create_team_flow.add{type = "button", name = "bt_create_team", style = "zk_action_button_dark", caption = ">"}
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

	if _mod_data.last_check_researched_tick > game.tick + 36000 then
		count_forces_researched()
	end
	update_teams_table(teams_table, player, teams)

	main_frame.force_auto_center()
end

local left_anchor = {gui = defines.relative_gui_type.controller_gui, position = defines.relative_gui_position.left}
local function create_left_relative_gui(player)
	local relative = player.gui.relative
	if relative.bt_buttons then
		relative.bt_buttons.destroy()
	end
	local main_table = relative.add{type = "table", name = "bt_buttons", anchor = left_anchor, column_count = 2}
	-- main_table.style.vertical_align = "center"
	main_table.style.horizontal_spacing = 0
	main_table.style.vertical_spacing = 0
	main_table.add{type = "sprite-button", sprite = "bt_customize_team", style="slot_button", name = "bt_customize_team"}
	main_table.add{type = "sprite-button", sprite = "bt_teams", style="slot_button", name = "bt_teams"}
end

--#endregion


--#region Functions of events


---@param event on_player_created
function M.on_player_created(event)
	local player_index = event.player_index
	local player = game.get_player(player_index)
	if not (player and player.valid) then return end

	_player_invite_requests[player_index] = {}
	create_left_relative_gui(player)
end


---@param event on_forces_merging
function M.on_forces_merging(event)
	local source = event.source
	for _, player in pairs(source.connected_players) do
		if player.valid then
			M.destroy_team_gui(player)
			M.destroy_teams_frame(player)
		end
	end

	source_index = source.index
	for player_index, player in pairs(game.players) do
		if player.valid then
			_player_invite_requests[player_index][source_index] = nil
		end
	end
end


---@param event on_forces_merged
function M.on_forces_merged(event)
	local index = event.source_index
	_team_settings[index] = nil
	_forces_researched[index] = nil
	_first_team_players[index] = nil
	_force_invite_requests[index] = nil
end


local mod_settings = {
	["EAPI_allow_create_team"] = function(value) _allow_create_team = value end,
	["EAPI_max_teams"] = function(value) _max_teams = value end,
	["bt_allow_abandon_teams"] = function(value) _allow_abandon_teams = value end,
	["bt_allow_rename_teams"] = function(value) _allow_rename_teams = value end,
	["bt_allow_switch_teams"] = function(value) _allow_switch_teams = value end,
	["bt_allow_bandits"] = function(value)
		_allow_bandits = value
		if _allow_bandits then
			--TODO: improve (in some cases it can't be created)
			if game.forces.bandits == nil then
				local force = game.create_force("bandits")
				_mod_data.bandits_force_index = force.index
				call("EasyAPI", "add_team", force)
			end
		end
	end,
	["bt_allow_join_bandits_force"] = function(value) _allow_join_bandits_force = value end,
	["bt_allow_join_player_force"] = function(value) _allow_join_player_force = value end,
	["bt_allow_join_enemy_force"] = function(value) _allow_join_enemy_force = value end,
	["bt_show_all_forces"] = function(value) _show_all_forces = value end,
	["bt_default_surface"] = function(value) _default_surface = value end,
	["bt_default_spawn_offset"] = function(value)
		_default_spawn_offset = value
		_mod_data.spawn_offset = math.floor(_mod_data.spawn_offset/value) * value
	end,
	["bt_spawn_method"] = function(value) _spawn_method = SPAWN_METHODS[value] end
}
---@param event on_runtime_mod_setting_changed
function M.on_runtime_mod_setting_changed(event)
	local setting_name = event.setting
	local f = mod_settings[setting_name]
	if f then f(settings.global[setting_name].value) end
end

local GUIS = {
	bt_close = function(element)
		element.parent.parent.destroy()
	end,
	bt_search = function(element, player)
		local parent = element.parent
		local text = parent.bt_team_player.text

		if #text > 30 then
			player.print({"gui-auth-server.username-too-long"})
			return
		end

		local found_players = {}
		local search_pattern = text:gsub("%-", "%%-")
		search_pattern = ".+" .. search_pattern .. ".+"
		local player_index = player.index
		for target_index, target in pairs(game.players) do
			if target_index ~= player_index then
				if find(target.name, search_pattern) then
					found_players[#found_players+1] = target.name
				end
			end
		end

		local flow = parent.parent.bt_flow_with_player_actions
		local dropdown = flow.bt_found_team_players
		local kick_button = flow.bt_kick_player
		local invite_button = flow.bt_invite
		dropdown.items = found_players
		if #found_players > 0 then
			flow.visible = true
			dropdown.visible = true
			dropdown.selected_index = 1
			if game.get_player(found_players[1]).force == player.force then
				invite_button.visible = false
				kick_button.visible = true
			else
				invite_button.visible = true
				kick_button.visible = false
			end
		else
			flow.visible = false
			dropdown.items = {}
		end
	end,
	--TODO: add localization
	bt_kick_player = function(element, player)
		local drop_down = element.parent.bt_found_team_players
		if drop_down.selected_index == 0 then return end

		if get_is_leader(player) == false then
			player.print("You're not a leader in this team")
			return
		end

		local player_name = drop_down.items[drop_down.selected_index]
		local target = game.get_player(player_name)
		if not (target and target.index) then
			player.print({"player-doesnt-exist", player_name})
			return
		elseif player.force ~= target.force then
			player.print("Player \"" .. target.name .. "\" in another team already.")
			return
		end


		if settings.global["bt_teleport_in_void_when_player_kicked_from_team"].value then
			player.ticks_to_respawn = nil -- respawn
			target.force = "void"
			target.teleport({player.index * 150, 0}, game.get_surface(_void_surface_index))
		else
			player.ticks_to_respawn = nil -- respawn
			-- WIP
			target.force = "player"
		end

		if target.connected then
			player.force.print("Player \"" .. target.name .. "\" have been kicked by \"" .. player.name .. "\" from your team", {1, 1, 0})
			target.print("You have been kicked by \"" .. player.name .. "\" from team \"" .. player.force.name .. "\"", {1, 1, 0})
		end
	end,
	--TODO: add localization
	bt_invite = function(element, player)
		local drop_down = element.parent.bt_found_team_players
		if drop_down.selected_index == 0 then return end

		local player_name = drop_down.items[drop_down.selected_index]
		local target = game.get_player(player_name)
		if not (target and target.index) then
			player.print({"player-doesnt-exist", player_name})
			return
		elseif target.mod_settings["bt_ignore_invites"].value then
			player.print("Player \"" .. target.name .. "\" ignores invites in teams.")
			return
		end

		local player_force = player.force
		if player_force == target.force then
			player.print("Player \"" .. target.name .. "\" in your team already.")
			return
		end
		local target_invites = _player_invite_requests[target.index]
		local invite = target_invites[player_force.index]
		if invite == nil then
			_mod_data.last_invite_id = _mod_data.last_invite_id + 1
			target_invites[player_force.index] = {
				_mod_data.last_invite_id,
				player,
				game.tick
			}
		elseif invite[2] == player then
			invite[3] = game.tick
			return
		end

		player.print("You invited \"" .. target.name .. "\" in your team")
		if target.connected then
			target.print("Player \"" .. player.name .. "\" invited you in team \"" .. player_force.name .. "\". (In order to accept, write: /accept-team-invite " .. _mod_data.last_invite_id .. ")")
		end
	end,
	bt_customize_team = function(element, player)
		local force_index = player.force.index
		if _team_settings[force_index] == nil then
			player.print("This force doesn't support this action")
			return
		end
		switch_team_gui(player)
	end,
	bt_teams = function(element, player)
		switch_teams_gui(player)
	end,
	bt_refresh_teams_table = function(element, player)
		update_teams_table(element.parent.parent.shallow_frame.table_frame.teams_table, player)
	end,
	bt_create_team = function(element, player)
		if not _allow_create_team then
			player.print("Players can't create teams by map settings")
			return
		end

		local parent = element.parent
		local team_name = parent.team_name.text
		local new_team = team_util.create_team(team_name, player)
		if not (new_team and new_team.valid) then
			--TODO: change message
			player.print({"error.error-message-box-title"}, {1, 0, 0})
			return
		end

		local prev_force = player.force
		parent.parent.parent.destroy()
		player.ticks_to_respawn = nil -- respawn
		player.force = new_team
		if #prev_force.players == 0 then
			local prev_force_index = prev_force.index
			local bandits_force_index = _mod_data.bandits_force_index
			if prev_force_index == _void_force_index or
				prev_force_index == player_force_index or
				prev_force_index == enemy_force_index or
				prev_force_index == neutral_force_index or
				(bandits_force_index and prev_force_index == bandits_force_index)
			then
				--TODO: Improve
			else
				if call("EasyAPI", "find_team", prev_force.index) and
				   call("EasyAPI", "is_team_deletable", prev_force.index)
				then
					game.merge_forces(prev_force, game.forces.enemy)
				end
			end
		end

		set_team_base(player)
	end,
	bt_abandon_team = function(element, player)
		abandon_team(player)
		player.gui.screen.bt_show_team_frame.destroy()
	end,
	bt_join_team = function(element, player)
		local force = game.forces[element.parent.name]
		if not (force and force.valid) then
			player.print({"error.error-message-box-title"}, {1, 0, 0})
			return
		end

		if player.controller_type == defines.controllers.editor then
			player.toggle_map_editor()
		end
		player.ticks_to_respawn = nil -- respawn
		player.force = force
		local surface = get_team_game_surface(player)
		local f_spawn_position = force.get_spawn_position(surface)
		local character = player.character
		if character == nil then
			player.teleport(f_spawn_position, surface)
		else
			local new_position = surface.find_non_colliding_position(
				character.name, f_spawn_position, 50, 1
			)
			if new_position then
				player.teleport(new_position, surface)
			else
				player.print({"gui-text-tags.gps-invalid"})
			end
		end
		player.gui.screen.bt_teams_frame.destroy() --TODO: change
	end
}
---@param event on_gui_click
function M.on_gui_click(event)
	local element = event.element
	if not (element and element.valid) then return end

	local f = GUIS[element.name]
	if f then
		f(element, game.get_player(event.player_index))
	end
end


---@param event on_gui_elem_changed
function M.on_gui_elem_changed(event)
	local element = event.element
	if not (element and element.valid) then return end
	local player = game.get_player(event.player_index)
	if not (player and player.valid) then return end

	if element.name ~= "bt_found_team_players" then return end

	local parent = element.parent
	local player_name = element.items[element.selected_index]
	local target = game.get_player(player_name)
	if not (target and target.index) then
		player.print({"player-doesnt-exist", player_name})
		return
	elseif target.force == player.force then
		parent.bt_invite.visible = false
		parent.bt_kick_player.visible = true
	else
		parent.bt_invite.visible = true
		parent.bt_kick_player.visible = false
	end
end


---@param event on_force_created
function M.on_force_created(event)
	local force = event.force
	if not force.valid then return end

	local researched_count = 0
	for _, tech in pairs(force.technologies) do
		if tech.researched then
			researched_count = researched_count + 1
		end
	end
	_forces_researched[force.index] = researched_count
end


---@param event on_player_joined_game
function M.on_player_joined_game(event)
	local player_index = event.player_index
	local player = game.get_player(player_index)
	if not (player and player.valid) then return end

	M.destroy_team_gui(player)
	M.destroy_teams_frame(player)

	if player.online_time < 60 * 10 then
		if settings.global["bt_auto_create_teams_gui_for_new_players"].value then
			local screen = player.gui.screen
			if screen.bt_teams_frame == nil then
				switch_teams_gui(player)
			end
		end
	end

	if #_player_invite_requests[player_index] > 0 then
		if player.mod_settings["bt_ignore_invites"].value then
			--TODO: add localization
			player.print("You have " .. #_player_invite_requests[player_index] .. " invites in teams")
		end
	end
end


---@param event on_player_left_game
function M.on_player_left_game(event)
	local player = game.get_player(event.player_index)
	if not (player and player.valid) then return end

	M.destroy_team_gui(player)
	M.destroy_teams_frame(player)
end


---@param event on_entity_destroyed
function M.on_entity_destroyed(event)
	local data = _teams_main_base_structure[event.registration_number]
	if not data then return end

	local force = data.force
	local is_base = call("EasyAPI", "has_team_base_by_index", force.index)
	if not is_base then
		_teams_main_base_structure[event.registration_number] = nil
		return
	end

	script.raise_event(call("EasyAPI", "get_event_name", "on_team_lost"), {
		force = force
	})
	call("EasyAPI", "remove_team", force.index, false)
	_teams_main_base_structure[event.registration_number] = nil
end


---@param event on_pre_player_removed
local function on_pre_player_removed(event)
	-- local force_index = game.get_player(event.player_index).force.index
	--TODO: delete invite in invite_requests etc
end

local function on_new_team(event)
	local index = event.force.index
	_team_settings[index] = {}
	_first_team_players[index] = {}
	_force_invite_requests[index] = {}
end

local function on_pre_deleted_team(event)
	local force = event.force
	local index = force.index
	_team_settings[index] = nil
	_first_team_players[index] = nil
	_force_invite_requests[index] = nil

	for id, data in pairs(_teams_main_base_structure) do
		local entity = data.entity
		if not data.force.valid then
			_teams_main_base_structure[id] = nil
			if entity.valid then
				entity.destroy(DESTROY_PARAM)
			end
		elseif not entity.valid then
			_teams_main_base_structure[id] = nil
		elseif data.force == force then
			_teams_main_base_structure[id] = nil
			data.destroy(DESTROY_PARAM)
		end
	end
end

--#endregion


--#region Pre-game stage

local function add_remote_interface()
	-- https://lua-api.factorio.com/latest/LuaRemote.html
	remote.remove_interface("BTeams") -- For safety
	remote.add_interface("BTeams", {
		get_mod_data = function()
			return _mod_data
		end,
		change_setting = function(type, name, value)
			settings[type][name] = {value = value}
		end,
		get_bandits_force_index = function()
			return _mod_data.bandits_force_index
		end,
		get_spawn_offset = function()
			return _mod_data.spawn_offset
		end,
		show_teams_gui = function(player)
			local screen = player.gui.screen
			if screen.bt_teams_frame then
				switch_teams_gui(player)
			end
			switch_teams_gui(player)
		end,
		destroy_team_gui    = M.destroy_team_gui,
		destroy_teams_frame = M.destroy_teams_frame,
	})
end

local function link_data()
	_mod_data = global.ST
	_team_settings = _mod_data.force_settings
	_first_team_players = _mod_data.first_team_players
	_forces_researched = _mod_data.forces_researched
	_player_invite_requests = _mod_data.player_invite_requests
	_force_invite_requests = _mod_data.force_invite_requests
	_teams_main_base_structure = _mod_data.teams_main_base
	_void_surface_index = call("EasyAPI", "get_void_surface_index")
	_void_force_index = call("EasyAPI", "get_void_force_index")
end

local function update_global_data()
	global.ST = global.ST or {}
	_mod_data = global.ST
	_mod_data.forces_researched = {}
	_mod_data.teams_main_base = _mod_data.teams_main_base or {}
	_mod_data.spawn_offset = _mod_data.spawn_offset or _default_spawn_offset
	_mod_data.force_settings = _mod_data.force_settings or {
		[player_force_index] = {},
		[enemy_force_index] = {},
		[neutral_force_index] = {}
	}
	_mod_data.first_team_players = _mod_data.first_team_players or {
		[player_force_index] = {},
		[enemy_force_index] = {},
		[neutral_force_index] = {}
	}
	_mod_data.last_invite_id = _mod_data.last_invite_id or 0
	_mod_data.player_invite_requests = _mod_data.player_invite_requests or {}
	_mod_data.force_invite_requests = _mod_data.force_invite_requests or {
		[player_force_index] = {},
		[enemy_force_index] = {},
		[neutral_force_index] = {}
	}

	link_data()

	count_forces_researched()

	for player_index, player in pairs(game.players) do
		if player.valid then
			_player_invite_requests[player_index] = _player_invite_requests[player_index] or {}

			local relative = player.gui.relative
			if relative.bt_buttons == nil then
				create_left_relative_gui(player)
			end
			M.destroy_teams_frame(player)
			M.destroy_team_gui(player)
		end
	end

	for force_index in pairs(_team_settings) do
		if game.forces[force_index] == nil then
			_team_settings[force_index] = nil
		end
	end

	for id, entity in pairs(_teams_main_base_structure) do
		if not entity.valid then
			_teams_main_base_structure[id] = nil
		end
	end

	for force_index, players_list in pairs(_first_team_players) do
		if game.forces[force_index] == nil then
			_team_settings[force_index] = nil
		else
			for i=#players_list, 1, -1 do
				local player = game.get_player(players_list[i])
				if not (player and player.valid) then
					table.remove(players_list, i)
				end
			end
		end
	end

	for force_index, players_data in pairs(_force_invite_requests) do
		if game.forces[force_index] == nil then
			_force_invite_requests[force_index] = nil
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
	script.on_event(call("EasyAPI", "get_event_name", "on_new_team"), on_new_team)
	script.on_event(call("EasyAPI", "get_event_name", "on_pre_deleted_team"), on_pre_deleted_team)
	script.on_event(call("EasyAPI", "get_event_name", "on_player_joined_team"), function(event)
		local player_index = event.player_index
		local player = game.get_player(player_index)
		if not (player and player.valid) then return end

		local player_force = player.force
		if settings.global["bt_teleport_new_players_to_team_spawn_point"].value then
			local surface = player.surface
			local f_spawn_position = player_force.get_spawn_position(surface)
			local character = player.character
			if character == nil then
				player.teleport(f_spawn_position, surface)
			else
				local new_position = surface.find_non_colliding_position(
					character.name, f_spawn_position, 50, 1
				)
				if new_position then
					player.teleport(new_position, surface)
				else
					player.print({"gui-text-tags.gps-invalid"})
				end
			end
		end

		local force_index = player_force.index
		local bandits_force_index = _mod_data.bandits_force_index
		if force_index ~= player_force_index and
			force_index ~= enemy_force_index and
			force_index ~= neutral_force_index and
			force_index ~= _void_force_index and
			(bandits_force_index == nil or force_index ~= bandits_force_index)
		then
			local players_list = _first_team_players[force_index]
			local is_new = true
			for i = 1, #players_list do
				if players_list[i] == player_index then
					is_new = false
					break
				end
			end

			if is_new then
				players_list[#players_list+1] = player_index
			end
		end

		local prev_force = event.prev_force
		if not (prev_force and prev_force.valid) then return end
		local players_list = _first_team_players[prev_force.index]
		if players_list then
			for i = 1, #players_list do
				if players_list[i] == player_index then
					table.remove(players_list)
					break
				end
			end
		end
	end)
	-- script.on_event(call("EasyAPI", "get_event_name", "on_player_left_team"), function(event)
	-- end)
	-- custom_events.on_team_invited
	-- custom_events.on_player_accepted_invite
end

M.on_init = function()
	team_util.on_init()
	handle_custom_events()
	update_global_data()
end
M.on_load = function()
	team_util.on_load()
	handle_custom_events()
	link_data()
end
M.on_configuration_changed = update_global_data
M.add_remote_interface = add_remote_interface

--#endregion


M.events = {
	[defines.events.on_runtime_mod_setting_changed] = M.on_runtime_mod_setting_changed,
	-- [defines.events.on_game_created_from_scenario] = on_game_created_from_scenario,
	[defines.events.on_forces_merged] = M.on_forces_merged,
	[defines.events.on_forces_merging] = M.on_forces_merging,
	[defines.events.on_gui_click] = M.on_gui_click,
	[defines.events.on_gui_elem_changed] = M.on_gui_elem_changed,
	[defines.events.on_player_created] = M.on_player_created,
	[defines.events.on_force_created] = M.on_force_created,
	[defines.events.on_player_joined_game] = M.on_player_joined_game,
	[defines.events.on_player_left_game] = M.on_player_left_game,
	[defines.events.on_player_removed] = function(event)
		local player_index = event.player_index
		_player_invite_requests[player_index] = nil

		for _, players_list in pairs(_first_team_players) do
			for i=#players_list, 1, -1 do
				if players_list[i] == player_index then
					table.remove(players_list, i)
				end
			end
		end
	end,
	[defines.events.on_game_created_from_scenario] = function(event)
		if _allow_bandits then
			--TODO: recheck and improve
			if game.forces.bandits == nil then
				local force = game.create_force("bandits")
				_mod_data.bandits_force_index = force.index
				call("EasyAPI", "add_team", force)
			end
		end
	end,
	[defines.events.on_player_changed_force] = function(event)
		-- Perphaps, it's not so good
		_player_invite_requests[event.player_index] = {}
	end,
	[defines.events.on_entity_destroyed] = M.on_entity_destroyed,
	-- [defines.events.on_pre_player_removed] = on_pre_player_removed
}


M.commands = {
	open_team_gui = function(cmd)
		switch_team_gui(game.get_player(cmd.player_index))
	end,
	open_teams_gui = function(cmd)
		switch_teams_gui(game.get_player(cmd.player_index))
	end,
	--TODO: add localization
	accept_team_invite = function(cmd)
		local player_index = cmd.player_index
		local player = game.get_player(player_index)

		local id = tonumber(cmd.parameter)
		if id == nil then
			local new_team = game.forces[cmd.parameter]
			if not (new_team and new_team.valid) then
				--TODO: change message
				player.print({"error.error-message-box-title"}, {1, 0, 0})
				return
			end

			local invites = _player_invite_requests[player_index]
			local invite = invites[new_team.index]
			if invite == nil then
				--TODO: change message
				player.print("Team \"" .. new_team.name .. "\" didn't send any invites to you.")
				return
			else
				local inviter = invite[2]
				local inviter_name = "?"
				if inviter.valid then
					inviter_name = inviter.name
				end
				if player.force.index ~= _mod_data.bandits_force_index
					and player.force.index ~= _void_force_index then
					player.force.print("Player \"" .. inviter_name .. "\" added player \"" .. player.name .. "\" in team \"" .. new_team.name .. "\"")
				end
				player.ticks_to_respawn = nil -- respawn
				player.force = new_team
				player.force.print("Player \"" .. inviter_name .. "\" added player \"" .. player.name .. "\" in your team")
				_player_invite_requests[player_index] = {}
			end
		else
			local invites = _player_invite_requests[player_index]
			for force_index, invite in pairs(invites) do
				if invite[1] == id then
					local inviter = invite[2]
					local new_team = game.forces[force_index]
					local inviter_name = "?"
					if inviter.valid then
						inviter_name = inviter.name
					end
					if player.force.index ~= _mod_data.bandits_force_index then
						player.force.print("Player \"" .. inviter_name .. "\" added player \"" .. player.name .. "\" in team \"" .. new_team.name .. "\"")
					end
					player.ticks_to_respawn = nil -- respawn
					player.force = new_team
					player.force.print("Player \"" .. inviter_name .. "\" added player \"" .. player.name .. "\" in your team")
					_player_invite_requests[player_index] = {}
					break
				end
			end
		end
	end,
	--TODO: add localization
	show_team_invites = function(cmd)
		local player_index = cmd.player_index
		local player = game.get_player(player_index)
		local invites = _player_invite_requests[player_index]
		local key = next(invites)
		if key == nil then
			player.print("You don't have any invites")
			return
		end

		local message = "Invites:\n"
		for force_index, invite in pairs(invites) do
			local force = game.forces[force_index]
			local inviter = invite[2]
			local inviter_name = "?"
			if inviter.valid then
				inviter_name = inviter.name
			end
			message = message .. invite[1] .. ". In team \"" .. force.name .. "\" by player\"" .. inviter_name .. "\"\n"
		end
		player.print(message)
	end,
	abandon_team = function(cmd)
		local player = game.get_player(cmd.player_index)
		abandon_team(player)
	end,
	invite_in_team = function(cmd)
		local player = game.get_player(cmd.player_index)
		player.print("WIP. Use GUI instead.")
	end,
	join_team = function(cmd)
		local player = game.get_player(cmd.player_index)
		player.print("WIP. Use GUI instead.")
	end,
	kick_teammate = function(cmd)
		local player = game.get_player(cmd.player_index)
		if get_is_leader(player) == false then
			player.print("You're not a leader in this team")
			return
		end

		local target = game.get_player(cmd.parameter)
		if not (target and target.valid) then
			player.print({"player-doesnt-exist", cmd.parameter})
		elseif player.force ~= target.force then
			player.print("Player \"" .. target.name .. "\" in another team already.")
			return
		end

		if settings.global["bt_teleport_in_void_when_player_kicked_from_team"].value then
			player.ticks_to_respawn = nil -- respawn
			target.force = "void"
			target.teleport({player.index * 150, 0}, game.get_surface(_void_surface_index))
		else
			player.ticks_to_respawn = nil -- respawn
			-- WIP
			target.force = "player"
		end

		if target.connected then
			player.force.print("Player \"" .. target.name .. "\" have been kicked by \"" .. player.name .. "\" from your team", {1, 1, 0})
			target.print("You have been kicked by \"" .. player.name .. "\" from team \"" .. player.force.name .. "\"", {1, 1, 0})
		end
	end,
	set_base = function(cmd)
		set_team_base(game.get_player(cmd.player_index))
	end
}


return M
