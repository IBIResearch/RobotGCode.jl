using RobotGCode

DATA_FOLDER = "./data/meander"
mkpath(DATA_FOLDER)

"""
	meander(t; lanes=8)

3D meander trajectory with:
- x, y in [-1, 1]
- z in [0, 1]
- configurable number of horizontal lanes
"""
function meander(t; lanes::Int=8)
	lanes >= 2 || throw(ArgumentError("lanes must be >= 2"))

	τ = clamp(float(t), 0.0, 1.0)
	dy = 2.0 / (lanes - 1)

	# Length-weighted parameterization for near-constant feed speed.
	total_length = lanes * 2.0 + (lanes - 1) * dy
	s = τ * total_length

	for lane in 1:lanes
		y_lane = -1.0 + (lane - 1) * dy
		horizontal_length = 2.0

		if s <= horizontal_length || lane == lanes
			α = clamp(s / horizontal_length, 0.0, 1.0)
			x = isodd(lane) ? (-1.0 + 2.0 * α) : (1.0 - 2.0 * α)
			z = τ
			return (x, y_lane, z)
		end
		s -= horizontal_length

		if lane < lanes
			vertical_length = dy
			if s <= vertical_length
				β = clamp(s / vertical_length, 0.0, 1.0)
				x = isodd(lane) ? 1.0 : -1.0
				y = y_lane + β * dy
				z = τ
				return (x, y, z)
			end
			s -= vertical_length
		end
	end

	return (isodd(lanes) ? 1.0 : -1.0, 1.0, τ)
end

npoints = 800
points = discretize(meander; npoints=npoints)

points[:, 1] .*= 0.18
points[:, 2] .*= 0.18
points[:, 3] .*= 0.13

fig = visualize_positions_3d(points; xlims=(-0.18, 0.18), ylims=(-0.18, 0.18), zlims=(0.0, 0.13))
display(fig)

generate_gcode(
	points;
	ausgabe_datei = joinpath(DATA_FOLDER, "meander.gcode"),
	frame_time = 1.0,
	offset = (0.0, 0.0, 0.0),
)
