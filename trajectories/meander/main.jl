using RobotGCode

DATA_FOLDER = "./data/meander"
mkpath(DATA_FOLDER)

X_MIN, X_MAX = -160., 160.
Y_MIN, Y_MAX = -170., 170.0
Z_MIN, Z_MAX = -94.0, -30.0

START = (-160.93, 200.0, 0.0)
SHALTER = (-160.93, 249.61, 0.0)

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
			return (x, y_lane, z*0.3)
		end
		s -= horizontal_length

		if lane < lanes
			vertical_length = dy
			if s <= vertical_length
				β = clamp(s / vertical_length, 0.0, 1.0)
				x = isodd(lane) ? 1.0 : -1.0
				y = y_lane + β * dy
				z = τ
				return (x, y, z*0.3)
			end
			s -= vertical_length
		end
	end

	return (isodd(lanes) ? 1.0 : -1.0, 1.0, τ*0.3)
end

curve = fit_to_box(meander, (X_MIN, X_MAX), (Y_MIN, Y_MAX), (Z_MIN, Z_MAX))

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
    ausgabe_datei = joinpath("/home/tsanda/nextcloud/Research Projects/MMR/Code/GCode Roboter/General_Trajectory/Files", "meander.gcode"),
    frame_time = 1.0,
    offset = (0.0, 0.0, 0.0),
    start = START,
    shalter = SHALTER,
)
