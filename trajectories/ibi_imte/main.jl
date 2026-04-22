using RobotGCode

ibi = with_z(string_curve("  IBI"), 0.04)
imte = with_z(translated(string_curve("IMTE"), (0.0, -1.0)), 0.08)
curve = merged(ibi, imte)

npoints = 200
points = discretize(curve; npoints=npoints)

max_coordinates = maximum(points, dims=1)
min_coordinates = minimum(points, dims=1)

center = (max_coordinates .+ min_coordinates) ./ 2
center[3] = 0
range2d = maximum((max_coordinates .- min_coordinates)[1:2]) / 2

points .-= center
points[:, 1] ./= range2d
points[:, 2] ./= range2d

points[:, 1] .*= 0.18
points[:, 2] .*= 0.18

fig = visualize_positions_3d(points; xlims=(-0.18, 0.18), ylims=(-0.18, 0.18), zlims=(0.0, 0.13))
display(fig)