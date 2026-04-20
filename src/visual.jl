using CairoMakie

"""
	visualize_positions_3d(positions; title="3D Trajectory", savepath=nothing,
						   linewidth=2, markersize=8)

Visualize a trajectory as a 3D polyline with sample markers.

`positions` must be an `N×3` matrix where each row is a consecutive 3D point.
The plot colors points by sample index so the ordering is visible at a glance.
"""
function visualize_positions_3d(
	positions::AbstractMatrix{<:Real};
	title::AbstractString = "3D Trajectory",
	savepath::Union{Nothing,AbstractString} = nothing,
	linewidth::Real = 2,
	markersize::Real = 8,
)
	size(positions, 2) == 3 || throw(ArgumentError("positions must have size N×3"))
	npoints = size(positions, 1)
	npoints > 0 || throw(ArgumentError("positions must contain at least one row"))

	points = Float64.(positions)
	sample_index = 1:npoints

	fig = Figure(size = (1000, 750))
	ax = Axis3(
		fig[1, 1],
		title = title,
		xlabel = "X",
		ylabel = "Y",
		zlabel = "Z",
		aspect = :data,
	)

	lines!(
		ax,
		points[:, 1],
		points[:, 2],
		points[:, 3],
		color = sample_index,
		colormap = :viridis,
		linewidth = linewidth,
	)
	scatter!(
		ax,
		points[:, 1],
		points[:, 2],
		points[:, 3],
		color = sample_index,
		colormap = :viridis,
		markersize = markersize,
	)

	Colorbar(fig[1, 2], limits = (1, npoints), colormap = :viridis, label = "Sample index")

	if savepath !== nothing
		save(savepath, fig)
	end

	return fig
end
