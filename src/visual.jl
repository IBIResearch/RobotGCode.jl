using CairoMakie

"""
	visualize_positions_3d(positions; title="3D Trajectory", savepath=nothing,
						   linewidth=2, markersize=8,
						   xlims=nothing, ylims=nothing, zlims=nothing)

Visualize a trajectory as a 3D polyline with sample markers.

`positions` must be an `N×3` matrix where each row is a consecutive 3D point.
The plot colors points by sample index so the ordering is visible at a glance.
Use `xlims`, `ylims`, and `zlims` to override automatic axis limits.
Each limit must be a `(min, max)` tuple with `min < max`.
"""
function visualize_positions_3d(
	positions::AbstractMatrix{<:Real};
	title::AbstractString = "3D Trajectory",
	savepath::Union{Nothing,AbstractString} = nothing,
	linewidth::Real = 2,
	markersize::Real = 8,
	xlims::Union{Nothing,Tuple{<:Real,<:Real}} = nothing,
	ylims::Union{Nothing,Tuple{<:Real,<:Real}} = nothing,
	zlims::Union{Nothing,Tuple{<:Real,<:Real}} = nothing,
)
	size(positions, 2) == 3 || throw(ArgumentError("positions must have size N×3"))
	npoints = size(positions, 1)
	npoints > 0 || throw(ArgumentError("positions must contain at least one row"))

	points = Float64.(positions)
	sample_index = 1:npoints
	xlim_values = nothing
	ylim_values = nothing
	zlim_values = nothing

	if xlims !== nothing
		xlims[1] < xlims[2] || throw(ArgumentError("xlims must satisfy min < max"))
		xlim_values = (Float64(xlims[1]), Float64(xlims[2]))
	end
	if ylims !== nothing
		ylims[1] < ylims[2] || throw(ArgumentError("ylims must satisfy min < max"))
		ylim_values = (Float64(ylims[1]), Float64(ylims[2]))
	end
	if zlims !== nothing
		zlims[1] < zlims[2] || throw(ArgumentError("zlims must satisfy min < max"))
		zlim_values = (Float64(zlims[1]), Float64(zlims[2]))
	end

	visible = trues(npoints)
	if xlim_values !== nothing
		visible .&= (points[:, 1] .>= xlim_values[1]) .& (points[:, 1] .<= xlim_values[2])
	end
	if ylim_values !== nothing
		visible .&= (points[:, 2] .>= ylim_values[1]) .& (points[:, 2] .<= ylim_values[2])
	end
	if zlim_values !== nothing
		visible .&= (points[:, 3] .>= zlim_values[1]) .& (points[:, 3] .<= zlim_values[2])
	end

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
	if any(visible)
		scatter!(
			ax,
			points[visible, 1],
			points[visible, 2],
			points[visible, 3],
			color = sample_index[visible],
			colormap = :viridis,
			markersize = markersize,
		)
	elseif xlim_values !== nothing || ylim_values !== nothing || zlim_values !== nothing
		@warn "No points fall inside the requested axis limits; skipping scatter markers to avoid a CairoMakie clipping error."
	end

	if xlim_values !== nothing
		xlims!(ax, xlim_values...)
	end
	if ylim_values !== nothing
		ylims!(ax, ylim_values...)
	end
	if zlim_values !== nothing
		zlims!(ax, zlim_values...)
	end

	Colorbar(fig[1, 2], limits = (1, npoints), colormap = :viridis, label = "Sample index")

	if savepath !== nothing
		save(savepath, fig)
	end

	return fig
end
