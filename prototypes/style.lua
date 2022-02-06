local styles = data.raw["gui-style"].default

styles["bt_invites_frame"] = {
	type = "frame_style",
	left_padding = 6,
	right_margin = 10,
	minimal_width = 100,
	graphical_set = {
		base = {
			center = {position = {336, 0}, size = {1, 1}},
			opacity = 0.4,
			background_blur = true,
			background_blur_sigma = 0.5,
			blend_mode = "additive-soft-with-alpha"
		},
		shadow = default_glow(default_shadow_color, 0.5)
	}
}
