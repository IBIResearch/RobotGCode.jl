using CairoMakie
using RobotGCode

input_file = joinpath(@__DIR__, "..", "data", "slow", "MMRTrajSlow.mmr")

mktempdir() do tempdir
    output_file = joinpath(tempdir, "tmp.gcode")

    generate_gcode(
        eingabe_datei = input_file,
        ausgabe_datei = output_file,
        frame_time = 1.0,
        offset = (0.0, 0.0, 110.0),
    )

    isfile(output_file) || error("expected gcode output file to be created")

    gcode = read(output_file, String)
    occursin("G21", gcode) || error("expected generated gcode to contain G21")
    occursin("M2", gcode) || error("expected generated gcode to contain M2")
end

mktempdir() do tempdir
    plot_file = joinpath(tempdir, "trajectory.png")
    fig = visualize_positions_3d([
        0.0  0.0  0.0;
        0.1  0.1  0.0;
        0.2  0.0  0.1;
    ]; savepath = plot_file)

    isfile(plot_file) || error("expected trajectory plot to be written")
    fig isa Figure || error("expected visualize_positions_3d to return a CairoMakie Figure")
end

# --- TrueType font glyph sampling ---
font_path = joinpath(@__DIR__, "..", "ReliefSingleLineCAD-Regular.ttf")
if isfile(font_path)
    font = load_truetype_font(font_path)
    gid_A = glyph_index(font, 'A')
    gid_A > 0 || error("expected glyph for 'A' to exist in the bundled font")

    pathA = glyph_path(font, 'A')
    isempty(pathA.strokes) && error("expected glyph path for 'A' to have strokes")

    gid_E = glyph_index(font, 'E')
    contours_E = glyph_segments(font, gid_E)
    if !isempty(contours_E) && !isempty(contours_E[1]) && contours_E[1][end] isa RobotGCode.LineSeg2D
        pathE = glyph_path(font, 'E')
        length(pathE.strokes[1].segments) == length(contours_E[1]) - 1 || error("expected glyph_path('E') to drop the last segment of the first stroke")
    end

    p0 = point_at(pathA, 0.0)
    p5 = point_at(pathA, 0.5)
    p1 = point_at(pathA, 1.0)
    all(isfinite, (p0.x, p0.y, p5.x, p5.y, p1.x, p1.y)) || error("expected finite glyph points")

    strokeA = pathA.strokes[1]
    stroke_len = approx_length(strokeA)
    stroke_len >= 0.0 || error("expected non-negative stroke length")

    stroke_points_by_count = discretize(strokeA; npoints = 25)
    size(stroke_points_by_count) == (25, 2) || error("expected stroke discretization by npoints to return 25x2 matrix")

    spacing = max(stroke_len / 8, 1e-4)
    stroke_points_by_spacing = discretize(strokeA; spacing = spacing)
    size(stroke_points_by_spacing, 2) == 2 || error("expected stroke discretization by spacing to preserve 2D points")
    size(stroke_points_by_spacing, 1) >= 2 || error("expected spacing discretization to return at least two points")

    glyph_strokes = discretize(pathA; npoints = 20)
    length(glyph_strokes) == length(pathA.strokes) || error("expected one discretized polyline per glyph stroke")
    all(size(poly, 2) == 2 for poly in glyph_strokes) || error("expected all discretized glyph polylines to be 2D")

    legacy_strokes = sample_strokes(pathA, 20)
    length(legacy_strokes) == length(glyph_strokes) || error("expected sample_strokes compatibility with discretize")

    # --- String to single ParametricCurve layout ---
    ibi_curve = string_curve(font, "IBI")
    p_ibi_start = point_at(ibi_curve, 0.0)
    p_ibi_end = point_at(ibi_curve, 1.0)

    glyph_I = glyph_path(font, 'I')
    curve_I = merged(glyph_I)
    p_I_start = point_at(curve_I, 0.0)
    all(isapprox.(p_ibi_start, p_I_start; atol = 1e-10)) || error("expected string curve to start at the first glyph start point")

    gid_I = glyph_index(font, 'I')
    gid_B = glyph_index(font, 'B')
    unit_scale = 1.0 / font.unitsPerEm
    x_shift_last_I = (advance_width(font, gid_I) + advance_width(font, gid_B)) * unit_scale
    shifted_last_I = RobotGCode.translated(glyph_I, (x_shift_last_I, 0.0))
    p_expected_ibi_end = point_at(merged(shifted_last_I), 1.0)
    all(isapprox.(p_ibi_end, p_expected_ibi_end; atol = 1e-8)) || error("expected string curve layout to use cumulative glyph advances")

    tight_curve = string_curve(font, "II")
    wide_curve = string_curve(font, "II"; letter_spacing = 0.25)
    p_tight_end = point_at(tight_curve, 1.0)
    p_wide_end = point_at(wide_curve, 1.0)
    isapprox(p_wide_end[1] - p_tight_end[1], 0.25; atol = 1e-8) || error("expected letter_spacing to increase horizontal distance between glyphs")
    isapprox(p_wide_end[2], p_tight_end[2]; atol = 1e-8) || error("expected letter_spacing to not change vertical placement")

    auto_font_curve = string_curve("I")
    p_auto_end = point_at(auto_font_curve, 1.0)
    all(isfinite, p_auto_end) || error("expected auto-font string curve endpoint to be finite")

    try
        string_curve(font, "")
        error("expected string_curve to reject empty text")
    catch err
        err isa ArgumentError || rethrow(err)
    end

    try
        string_curve(font, string(Char(0x10ffff)))
        error("expected string_curve to reject missing glyphs")
    catch err
        err isa ArgumentError || rethrow(err)
    end
else
    @warn "Skipping font test: bundled .ttf not found" font_path
end

# --- Parametric curve discretization ---
line_curve = ParametricCurve(t -> (2.0 * t, -1.0, 0.5))
line_points = discretize(line_curve; npoints = 6)

size(line_points) == (6, 3) || error("expected npoints discretization to return a 6x3 matrix")
line_points[1, :] == [0.0, -1.0, 0.5] || error("expected first line point to be the start of the curve")
line_points[end, :] == [2.0, -1.0, 0.5] || error("expected last line point to be the end of the curve")

spacing_points = discretize(t -> (t, 0.0, 0.0); spacing = 0.2)
size(spacing_points, 2) == 3 || error("expected spacing discretization to preserve point dimension")
spacing_points[1, :] == [0.0, 0.0, 0.0] || error("expected first spacing point to be at t=0")
spacing_points[end, :] == [1.0, 0.0, 0.0] || error("expected last spacing point to be at t=1")

for i in 2:(size(spacing_points, 1) - 1)
    dist = spacing_points[i, 1] - spacing_points[i - 1, 1]
    abs(dist - 0.2) <= 1e-6 || error("expected interior spacing close to 0.2, got $dist")
end

circle_len = approx_length(t -> (cospi(2t), sinpi(2t)); resolution = 20_001)
abs(circle_len - 2 * pi) <= 2e-3 || error("expected approximated unit-circle length to be close to 2*pi")

# --- Curve merge with linear connector ---
first_curve = ParametricCurve(t -> (t, 0.0))
second_curve = ParametricCurve(t -> (2.0 + t, 1.0))
merged_curve = merged(first_curve, second_curve)

p_merged_start = point_at(merged_curve, 0.0)
p_merged_end = point_at(merged_curve, 1.0)
all(isapprox.(p_merged_start, [0.0, 0.0]; atol = 1e-12)) || error("expected merged curve to start at first curve start point")
all(isapprox.(p_merged_end, [3.0, 1.0]; atol = 1e-12)) || error("expected merged curve to end at second curve end point")

len_first = approx_length(first_curve)
len_connector = sqrt(2.0)
len_second = approx_length(second_curve)
len_total = len_first + len_connector + len_second

t_connector_start = len_first / len_total
t_connector_mid = (len_first + 0.5 * len_connector) / len_total
t_connector_end = (len_first + len_connector) / len_total

p_connector_start = point_at(merged_curve, t_connector_start)
p_connector_mid = point_at(merged_curve, t_connector_mid)
p_connector_end = point_at(merged_curve, t_connector_end)

all(isapprox.(p_connector_start, [1.0, 0.0]; atol = 1e-10)) || error("expected merged curve to reach first endpoint at connector start")
all(isapprox.(p_connector_mid, [1.5, 0.5]; atol = 1e-10)) || error("expected merged curve midpoint to lie on linear connector")
all(isapprox.(p_connector_end, [2.0, 1.0]; atol = 1e-10)) || error("expected merged curve to reach second startpoint at connector end")

merged_from_functions = merged(t -> (t, 0.0), t -> (2.0 + t, 1.0))
p_fn_mid = point_at(merged_from_functions, t_connector_mid)
all(isapprox.(p_fn_mid, [1.5, 0.5]; atol = 1e-10)) || error("expected merged function overload to match ParametricCurve merge")

try
    merged(ParametricCurve(t -> (t, 0.0)), ParametricCurve(t -> (t, 0.0, 0.0)))
    error("expected merged to reject dimension mismatch")
catch err
    err isa ArgumentError || rethrow(err)
end

# --- GlyphPath merged into one curve with linear stroke connectors ---
p00 = RobotGCode.Point2(0.0, 0.0)
p10 = RobotGCode.Point2(1.0, 0.0)
p20 = RobotGCode.Point2(2.0, 0.0)
p21 = RobotGCode.Point2(2.0, 1.0)

stroke1 = RobotGCode.StrokePath(RobotGCode.Segment2D[RobotGCode.LineSeg2D(p00, p10)], [1.0], [1.0], 1.0)
stroke2 = RobotGCode.StrokePath(RobotGCode.Segment2D[RobotGCode.LineSeg2D(p20, p21)], [1.0], [1.0], 1.0)
glyph_two_strokes = RobotGCode.GlyphPath([stroke1, stroke2], [1.0, 1.0], [1.0, 2.0], 2.0)

glyph_curve = merged(glyph_two_strokes)

p_glyph_start = point_at(glyph_curve, 0.0)
p_glyph_conn_start = point_at(glyph_curve, 1.0 / 3.0)
p_glyph_conn_mid = point_at(glyph_curve, 0.5)
p_glyph_conn_end = point_at(glyph_curve, 2.0 / 3.0)
p_glyph_end = point_at(glyph_curve, 1.0)

all(isapprox.(p_glyph_start, [0.0, 0.0]; atol = 1e-12)) || error("expected merged glyph curve to start at first stroke start")
all(isapprox.(p_glyph_conn_start, [1.0, 0.0]; atol = 1e-12)) || error("expected merged glyph curve to reach first stroke end at connector start")
all(isapprox.(p_glyph_conn_mid, [1.5, 0.0]; atol = 1e-12)) || error("expected merged glyph connector midpoint to be linear")
all(isapprox.(p_glyph_conn_end, [2.0, 0.0]; atol = 1e-12)) || error("expected merged glyph curve to reach second stroke start at connector end")
all(isapprox.(p_glyph_end, [2.0, 1.0]; atol = 1e-12)) || error("expected merged glyph curve to end at last stroke end")

single_stroke_curve = merged(stroke1)
p_single_mid = point_at(single_stroke_curve, 0.4)
all(isapprox.(p_single_mid, [0.4, 0.0]; atol = 1e-12)) || error("expected merged(stroke) to parameterize the stroke itself")

reversed_stroke = RobotGCode.reversed(stroke1)
p_reversed_stroke_start = point_at(reversed_stroke, 0.0)
p_reversed_stroke_mid = point_at(reversed_stroke, 0.4)
p_reversed_stroke_end = point_at(reversed_stroke, 1.0)
isapprox(p_reversed_stroke_start.x, 1.0; atol = 1e-12) || error("expected reversed stroke to start at original stroke end x")
isapprox(p_reversed_stroke_start.y, 0.0; atol = 1e-12) || error("expected reversed stroke to start at original stroke end y")
isapprox(p_reversed_stroke_mid.x, 0.6; atol = 1e-12) || error("expected reversed stroke midpoint to traverse in opposite direction")
isapprox(p_reversed_stroke_mid.y, 0.0; atol = 1e-12) || error("expected reversed stroke midpoint y to remain unchanged")
isapprox(p_reversed_stroke_end.x, 0.0; atol = 1e-12) || error("expected reversed stroke to end at original stroke start x")
isapprox(p_reversed_stroke_end.y, 0.0; atol = 1e-12) || error("expected reversed stroke to end at original stroke start y")

reversed_glyph = RobotGCode.reversed(glyph_two_strokes)
p_reversed_glyph_start = point_at(reversed_glyph, 0.0)
p_reversed_glyph_end = point_at(reversed_glyph, 1.0)
isapprox(p_reversed_glyph_start.x, 2.0; atol = 1e-12) || error("expected reversed glyph to start at original glyph end x")
isapprox(p_reversed_glyph_start.y, 1.0; atol = 1e-12) || error("expected reversed glyph to start at original glyph end y")
isapprox(p_reversed_glyph_end.x, 0.0; atol = 1e-12) || error("expected reversed glyph to end at original glyph start x")
isapprox(p_reversed_glyph_end.y, 0.0; atol = 1e-12) || error("expected reversed glyph to end at original glyph start y")

try
    merged(RobotGCode.GlyphPath(RobotGCode.StrokePath[], Float64[], Float64[], 0.0))
    error("expected merged glyph conversion to reject empty glyph")
catch err
    err isa ArgumentError || rethrow(err)
end

# --- Parametric curve transforms ---
base_curve = ParametricCurve(t -> (t, 2.0 * t, -1.0))

translated_curve = RobotGCode.translated(base_curve, (1.0, -2.0, 0.5))
pt_translated = point_at(translated_curve, 0.25)
all(isapprox.(pt_translated, [1.25, -1.5, -0.5]; atol = 1e-12)) || error("expected translated curve point to match fixed offset")

rotated_curve = RobotGCode.rotated(ParametricCurve(t -> (t, 0.0)), pi / 2)
pt_rotated = point_at(rotated_curve, 1.0)
all(isapprox.(pt_rotated, [0.0, 1.0]; atol = 1e-10)) || error("expected 90° rotation in XY plane")

scaled_curve = RobotGCode.scaled(ParametricCurve(t -> (t, -t)), 2.0)
pt_scaled = point_at(scaled_curve, 0.5)
all(isapprox.(pt_scaled, [1.0, -1.0]; atol = 1e-12)) || error("expected scaled curve point to double distance from origin")

zoomed_curve = RobotGCode.zoomed(ParametricCurve(t -> (0.25 * t, -0.5 * t)), 4.0)
pt_zoomed = point_at(zoomed_curve, 1.0)
all(isapprox.(pt_zoomed, [1.0, -2.0]; atol = 1e-12)) || error("expected zoomed alias to behave like scaled")

curve_3d = RobotGCode.with_z(ParametricCurve(t -> (t, -2.0 * t)), 0.25)
pt_curve_3d = point_at(curve_3d, 0.5)
all(isapprox.(pt_curve_3d, [0.5, -1.0, 0.25]; atol = 1e-12)) || error("expected with_z to append constant z coordinate")

curve_3d_points = discretize(curve_3d; npoints = 9)
size(curve_3d_points) == (9, 3) || error("expected with_z discretization to return Nx3 matrix")
all(isapprox.(curve_3d_points[:, 3], fill(0.25, 9); atol = 1e-12)) || error("expected with_z discretized points to keep constant z")

curve_3d_from_function = RobotGCode.with_z(t -> (2.0 * t, t^2), -0.1)
pt_curve_3d_from_function = point_at(curve_3d_from_function, 0.5)
all(isapprox.(pt_curve_3d_from_function, [1.0, 0.25, -0.1]; atol = 1e-12)) || error("expected with_z function overload to lift 2D curves")

reversed_curve = RobotGCode.reversed(base_curve)
for t in (0.0, 0.2, 0.5, 1.0)
    p_expected = point_at(base_curve, 1.0 - t)
    p_reversed = point_at(reversed_curve, t)
    all(isapprox.(p_reversed, p_expected; atol = 1e-12)) || error("expected reversed curve to evaluate at complementary parameter t=$(t)")
end

reversed_from_function = RobotGCode.reversed(t -> (t^2, t))
p_reversed_function = point_at(reversed_from_function, 0.3)
all(isapprox.(p_reversed_function, [0.49, 0.7]; atol = 1e-12)) || error("expected reversed function overload to traverse from end to start")

try
    RobotGCode.translated(ParametricCurve(t -> (t, t)), (1.0, 2.0, 3.0))
    error("expected translated to reject offset dimension mismatch")
catch err
    err isa ArgumentError || rethrow(err)
end

try
    RobotGCode.with_z(ParametricCurve(t -> (t, t, 0.0)), 0.0)
    error("expected with_z to reject non-2D curves")
catch err
    err isa ArgumentError || rethrow(err)
end

try
    discretize(t -> (t, t); npoints = 10, spacing = 0.1)
    error("expected discretize to reject using both npoints and spacing")
catch err
    err isa ArgumentError || rethrow(err)
end

# --- Font path transforms (ibi_imte-style flow) ---
if isfile(font_path)
    path_d = glyph_path(font, 'd')
    isempty(path_d.strokes) && error("expected glyph path for 'd' to have strokes")

    t_probe = 0.37
    p_raw = point_at(path_d, t_probe)

    translated_path = RobotGCode.translated(path_d, (0.25, -0.1))
    p_translated = point_at(translated_path, t_probe)
    isapprox(p_translated.x, p_raw.x + 0.25; atol = 1e-10) || error("expected glyph x translation to match")
    isapprox(p_translated.y, p_raw.y - 0.1; atol = 1e-10) || error("expected glyph y translation to match")

    rotated_path = RobotGCode.rotated(path_d, pi / 2)
    p_rotated = point_at(rotated_path, t_probe)
    isapprox(p_rotated.x, -p_raw.y; atol = 1e-8) || error("expected glyph rotation x to match 90° rotation")
    isapprox(p_rotated.y, p_raw.x; atol = 1e-8) || error("expected glyph rotation y to match 90° rotation")

    scaled_path = RobotGCode.scaled(path_d, 1.5)
    p_scaled = point_at(scaled_path, t_probe)
    isapprox(p_scaled.x, 1.5 * p_raw.x; atol = 1e-10) || error("expected glyph x scaling to match factor")
    isapprox(p_scaled.y, 1.5 * p_raw.y; atol = 1e-10) || error("expected glyph y scaling to match factor")

    zoomed_path = RobotGCode.zoomed(path_d, 0.75)
    p_zoomed = point_at(zoomed_path, t_probe)
    isapprox(p_zoomed.x, 0.75 * p_raw.x; atol = 1e-10) || error("expected glyph zoom x scaling to match factor")
    isapprox(p_zoomed.y, 0.75 * p_raw.y; atol = 1e-10) || error("expected glyph zoom y scaling to match factor")

    reversed_path = RobotGCode.reversed(path_d)
    p_reversed_start = point_at(reversed_path, 0.0)
    p_reversed_end = point_at(reversed_path, 1.0)
    p_raw_start = point_at(path_d, 0.0)
    p_raw_end = point_at(path_d, 1.0)
    isapprox(p_reversed_start.x, p_raw_end.x; atol = 1e-10) || error("expected reversed glyph path to start at original end x")
    isapprox(p_reversed_start.y, p_raw_end.y; atol = 1e-10) || error("expected reversed glyph path to start at original end y")
    isapprox(p_reversed_end.x, p_raw_start.x; atol = 1e-10) || error("expected reversed glyph path to end at original start x")
    isapprox(p_reversed_end.y, p_raw_start.y; atol = 1e-10) || error("expected reversed glyph path to end at original start y")

    p_reversed_probe = point_at(reversed_path, t_probe)
    p_raw_complement = point_at(path_d, 1.0 - t_probe)
    isapprox(p_reversed_probe.x, p_raw_complement.x; atol = 1e-8) || error("expected reversed glyph x traversal to match complementary parameter")
    isapprox(p_reversed_probe.y, p_raw_complement.y; atol = 1e-8) || error("expected reversed glyph y traversal to match complementary parameter")

    npoints_per_stroke = 40
    transformed_strokes = discretize(rotated_path; npoints = npoints_per_stroke)
    length(transformed_strokes) == length(path_d.strokes) || error("expected one discretized transformed polyline per stroke")
    all(size(poly) == (npoints_per_stroke, 2) for poly in transformed_strokes) || error("expected transformed glyph discretization to keep N x 2 shape")

    transformed_curve_3d = RobotGCode.with_z(merged(rotated_path), 0.0)
    transformed_points_3d = discretize(transformed_curve_3d; npoints = 4 * npoints_per_stroke)
    size(transformed_points_3d, 2) == 3 || error("expected transformed lifted curve discretization to be 3D-compatible")
    all(isapprox.(transformed_points_3d[:, 3], 0.0; atol = 1e-12)) || error("expected transformed lifted curve discretization to keep z=0")
end