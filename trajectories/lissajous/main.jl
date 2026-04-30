using RobotGCode

DATA_FOLDER = "./data/lissajous"
mkpath(DATA_FOLDER)

X_MIN, X_MAX = -160., 160.
Y_MIN, Y_MAX = -170., 170.0
Z_MIN, Z_MAX = -94.0, -30.0

START = (-160.93, 200.0, 0.0)
SHALTER = (-160.93, 249.61, 0.0)

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

	return (x*2.0, y*2.0, z)
end

curve = fit_to_box(lissajous3d, (X_MIN, X_MAX), (Y_MIN, Y_MAX), (Z_MIN, Z_MAX))

curve_start = point_at(curve, 0.0)
curve_end = point_at(curve, 1.0)

shalter_to_curve = line_segment_3d(SHALTER, curve_start)
curve_to_shalter = line_segment_3d(curve_end, SHALTER)

curve = merged(shalter_to_curve, curve)
curve = merged(curve, curve_to_shalter)

points = discretize(curve; npoints=500)

fig = visualize_positions_3d(points)
display(fig)

generate_gcode(
    points[2:end, :] ./ 1000;
    ausgabe_datei = joinpath("/home/tsanda/nextcloud/Research Projects/MMR/Code/GCode Roboter/General_Trajectory/Files", "lissajous3d.gcode"),
    frame_time = 1.0,
    offset = (0.0, 0.0, 0.0),
    start = START,
    shalter = SHALTER,
)
