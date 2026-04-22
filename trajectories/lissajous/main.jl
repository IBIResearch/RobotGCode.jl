using RobotGCode

DATA_FOLDER = "./data/lissajous"
mkpath(DATA_FOLDER)

"""
	lissajous3d(t; fx=5, fy=4, fz=3, phase_x=0.0, phase_y=0.0, phase_z=0.0)

3D Lissajous trajectory with:
- x, y in [-1, 1]
- z in [0, 1]
- configurable frequencies and phases
"""
function lissajous3d(
	t;
	fx::Real=4,
	fy::Real=5,
	fz::Real=3,
	phase_x::Real=pi/4,
	phase_y::Real=0.0,
	phase_z::Real=0.0,
)
	τ = clamp(float(t), 0.0, 1.0)
	θ = 2π * τ

	x = sin(fx * θ + phase_x)                # in [-1, 1]
	y = sin(fy * θ + phase_y)                # in [-1, 1]
	z = 0.5 * (1.0 + sin(fz * θ + phase_z))  # map to [0, 1]

	return (x, y, z)
end

npoints = 500
points = discretize(lissajous3d; npoints=npoints)

points[:, 1] .*= 0.18
points[:, 2] .*= 0.18
points[:, 3] .*= 0.13

fig = visualize_positions_3d(points; xlims=(-0.18, 0.18), ylims=(-0.18, 0.18), zlims=(0.0, 0.13))
display(fig)

generate_gcode(
	points;
	ausgabe_datei = joinpath(DATA_FOLDER, "lissajous.gcode"),
	frame_time = 1.0,
	offset = (0.0, 0.0, 0.0),
)
