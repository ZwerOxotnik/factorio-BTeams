using PlotlyJS

default_spawn_offset = 400
V_x = []
V_y = []

function add_point(V)
  push!(V_x, V[1])
  push!(V_y, V[2])
end


for i = 1:12
  # d - distance
  d = default_spawn_offset * i
  add_point([0, d])
	add_point([d, 0])
	add_point([-d, 0])
	add_point([0, -d])
  step = d/default_spawn_offset
  if step > 2
    for j = 1:step
      x = default_spawn_offset * j
      y = d - default_spawn_offset * j
      add_point([ x, y])
      add_point([-x,-y])
      add_point([ x,-y])
      add_point([-x, y])
    end
  end
end

fig = plot([
  scatter(x=V_x, y=V_y, mode="markers", name="Spawn points")
])
savefig(fig, "compact.jpeg")
