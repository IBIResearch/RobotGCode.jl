using RobotGCode

DATA_FOLDER = "./data/helix"
mkpath(DATA_FOLDER)

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

    return (x, y, z)
end

npoints = 200
points = discretize(helix; npoints=npoints)

points[:, 1] .*= 0.18
points[:, 2] .*= 0.18
points[:, 3] .*= 0.13

fig = visualize_positions_3d(points; xlims=(-0.18, 0.18), ylims=(-0.18, 0.18), zlims=(0.0, 0.13))
display(fig)

generate_gcode(
    points;
    ausgabe_datei = joinpath(DATA_FOLDER, "helix.gcode"),
    frame_time = 1.0,
    offset = (0.0, 0.0, 0.0),
)