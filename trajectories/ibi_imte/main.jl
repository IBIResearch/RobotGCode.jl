using RobotGCode

ibi = with_z(string_curve("IBI"), 0.0)
imte = with_z(string_curve("IMTE"), 0.0)
curve = merged(ibi, imte)

npoints_per_stroke = 200
points = discretize(curve; npoints = npoints_per_stroke)
fig = visualize_positions_3d(points)
display(fig)