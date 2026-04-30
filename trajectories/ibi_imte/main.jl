using RobotGCode

X_MIN, X_MAX = -150., 150.
Y_MIN, Y_MAX = -170., 170.
Z = -35.0

START = (-160.93, 200.0, 0.0)
SHALTER = (-160.93, 249.61, 0.0)

curve = merged(
    string_curve("  IBI"),
    translated(string_curve("IMTE"), (0.0, -1.0))
)
curve = fit_to_box(curve, (X_MIN, X_MAX), (Y_MIN, Y_MAX))
curve = with_z(curve, Z)


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
    ausgabe_datei = joinpath("/home/tsanda/nextcloud/Research Projects/MMR/Code/GCode Roboter/General_Trajectory/Files", "ibi_imte.gcode"),
    frame_time = 1.0,
    offset = (0.0, 0.0, 0.0),
    start = START,
    shalter = SHALTER,
)
