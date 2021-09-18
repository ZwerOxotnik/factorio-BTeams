using PlotlyJS

default_spawn_offset = 400
V_x = []
V_y = []

# Push spawn points
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

  step = d / default_spawn_offset
  if (step <= 1) continue end

  add_point([ d, d])
  add_point([-d,-d])
  add_point([ d,-d])
  add_point([-d, d])

  if (step <= 3) continue end
  y = (d - default_spawn_offset) * 0.5
  add_point([ d, y])
  add_point([-d,-y])
  add_point([ d,-y])
  add_point([-d, y])
  add_point([ y, d])
  add_point([-y,-d])
  add_point([ y,-d])
  add_point([-y, d])
end

fig = plot([
  scatter(x=V_x, y=V_y, mode="markers", name="Spawn points")
])
savefig(fig, "web.jpeg")
