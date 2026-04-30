using RobotGCode

DATA_FOLDER = "./data/helix"
mkpath(DATA_FOLDER)

X_MIN, X_MAX = -160.93, 189.070
Y_MIN, Y_MAX = -172.602, 178.123
Z_MIN, Z_MAX = -94.0, -30.0

START = (-160.93, 200.0, 0.0)
SHALTER = (-160.93, 249.61, 0.0)

"""
    helix(t; turns=3)

Helix trajectory with:
- x, y in [-1, 1] (unit circle)
- z in [0, 1]
- configurable number of turns
"""
function helix(t; turns::Real=3)
    τ = clamp(float(t), 0.0, 1.0)
    θ = 2π * turns * τ

    x = cos(θ)      # in [-1, 1]
    y = sin(θ)      # in [-1, 1]
    z = τ           # in [0, 1]

    return (x, y, z*0.5)
end

curve = fit_to_box(helix, (X_MIN, X_MAX), (Y_MIN, Y_MAX), (Z_MIN, Z_MAX))

helix_start = point_at(curve, 0.0)
helix_end = point_at(curve, 1.0)

shalter_to_helix = line_segment_3d(SHALTER, helix_start)
helix_to_shalter = line_segment_3d(helix_end, SHALTER)

curve = merged(shalter_to_helix, curve)
curve = merged(curve, helix_to_shalter)

points = discretize(curve; npoints=500)

fig = visualize_positions_3d(points)
display(fig)

generate_gcode(
    points[2:end, :] ./ 1000;
    ausgabe_datei = joinpath("/home/tsanda/nextcloud/Research Projects/MMR/Code/GCode Roboter/General_Trajectory/Files", "helix.gcode"),
    frame_time = 1.0,
    offset = (0.0, 0.0, 0.0),
    start = START,
    shalter = SHALTER,
)
