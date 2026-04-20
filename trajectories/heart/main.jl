using RobotGCode

DATA_FOLDER = "./data/heart"
mkpath(DATA_FOLDER)

X_MIN, X_MAX = -18.0, 18.0  # cm
Y_MIN, Y_MAX = -18.0, 18.0  # cm
Z = 6 # cm


function heart_curve(num_points::Integer, z=0.0)
    """
    Generate a 3D heart curve using parametric equations.
    The classic heart shape is created using trigonometric functions.
    
    Returns an N×3 matrix where each row is [x, y, z] in meters.
    """
    points = zeros(num_points, 3)
    
    for i in 1:num_points
        # Parameter t ranges from 0 to 2π
        t = 2π * (i - 1) / (num_points - 1)
        
        # Parametric equations for heart curve (scaled for robot)
        x = 16 * sin(t)^3
        y = 13 * cos(t) - 5 * cos(2*t) - 2 * cos(3*t) - cos(4*t)
        
        # Scale from arbitrary units to meters (divide by ~100 for reasonable robot size)
        points[i, 1] = x / 100.0
        points[i, 2] = y / 100.0
        points[i, 3] = z
    end
    
    return points
end


positions = heart_curve(500)
fig = visualize_positions_3d(positions)
display(fig)

positions[:, 1] ./= maximum(positions[:, 1])
positions[:, 1] .*= (X_MAX - X_MIN) / 2 / 100
positions[:, 2] ./= maximum(positions[:, 2])
positions[:, 2] .*= (Y_MAX - Y_MIN) / 2 / 100
positions[:, 3] .+= Z / 100

generate_gcode(
    positions;
    ausgabe_datei = joinpath(DATA_FOLDER, "heart.gcode"),
    frame_time = 1.0,
    offset = (0.0, 0.0, 0.0),
)
