using RobotGCode

DATA_FOLDER = "./data/spiral"
mkpath(DATA_FOLDER)

"""
	spiral(t; turns=6)

Archimedean spiral trajectory with:
- radius growing from 0 to 1
- x, y in [-1, 1]
- z in [0.0, 1.0]
- configurable number of turns
"""
function spiral(t; turns::Real=6, r_margin=0.1)
	t_clamped = clamp(float(t), 0.0, 1.0)
	theta = 2pi * turns * t_clamped
	radius = t_clamped + r_margin

	x = radius * cos(theta)
	y = radius * sin(theta)
	z = t_clamped

	return (x, y, z)
end

npoints = 400
points = discretize(spiral; npoints=npoints)

points[:, 1] .*= 0.18
points[:, 2] .*= 0.18
points[:, 3] .*= 0.13

fig = visualize_positions_3d(points; xlims=(-0.18, 0.18), ylims=(-0.18, 0.18), zlims=(0.0, 0.13))
display(fig)

generate_gcode(
	points;
	ausgabe_datei = joinpath(DATA_FOLDER, "spiral.gcode"),
	frame_time = 1.0,
	offset = (0.0, 0.0, 0.0),
)
