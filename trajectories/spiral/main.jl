using RobotGCode

DATA_FOLDER = "./data/spiral"
mkpath(DATA_FOLDER)

X_MIN, X_MAX = -160., 160.
Y_MIN, Y_MAX = -170., 170.0
Z_MIN, Z_MAX = -94.0, -30.0

START = (-160.93, 200.0, 0.0)
SHALTER = (-160.93, 249.61, 0.0)

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

	return (x, y, z*0.3)
end


curve = fit_to_box(spiral, (X_MIN, X_MAX), (Y_MIN, Y_MAX), (Z_MIN, Z_MAX))

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
    ausgabe_datei = joinpath("/home/tsanda/nextcloud/Research Projects/MMR/Code/GCode Roboter/General_Trajectory/Files", "spiral.gcode"),
    frame_time = 1.0,
    offset = (0.0, 0.0, 0.0),
    start = START,
    shalter = SHALTER,
)