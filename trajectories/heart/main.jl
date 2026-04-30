using RobotGCode

DATA_FOLDER = "./data/heart"
mkpath(DATA_FOLDER)

# Robot workspace bounds (mm) in the robot coordinate frame.
X_MIN, X_MAX = -160., 160.
Y_MIN, Y_MAX = -170., 170.
Z = -25.0

START = (-160.93, 200.0, 0.0)
SHALTER = (-160.93, 249.61, 0.0)


"""
    heart2d(t)

Classic heart curve in 2D parameterized on `t ∈ [0, 1]`.

The raw curve is in arbitrary units; use `fit_to_box` to scale/translate it
into your robot workspace.
"""
function heart2d(t)
    τ = clamp(float(t), 0.0, 1.0)
    θ = 2π * τ

    x = 16 * sin(θ)^3
    y = 13 * cos(θ) - 5 * cos(2θ) - 2 * cos(3θ) - cos(4θ)

    return (x, y)
end

curve2d = fit_to_box(heart2d, (X_MIN, X_MAX), (Y_MIN, Y_MAX))
curve3d = with_z(curve2d, Z)

heart_start = point_at(curve3d, 0.0)
heart_end = point_at(curve3d, 1.0)

shalter_to_heart = line_segment_3d(SHALTER, heart_start)
heart_to_shalter = line_segment_3d(heart_end, SHALTER)

curve3d = merged(shalter_to_heart, with_z(curve2d, Z))
curve3d = merged(curve3d, heart_to_shalter)

points = discretize(curve3d; npoints=150)

fig = visualize_positions_3d(points)
display(fig)

generate_gcode(
    points[2:end, :] ./ 1000;
    ausgabe_datei = joinpath("/home/tsanda/nextcloud/Research Projects/MMR/Code/GCode Roboter/General_Trajectory/Files", "heart150.gcode"),
    frame_time = 1.0,
    offset = (0.0, 0.0, 0.0),
    start = START,
    shalter = SHALTER,
)



