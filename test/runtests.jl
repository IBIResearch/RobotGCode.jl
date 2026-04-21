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

try
    discretize(t -> (t, t); npoints = 10, spacing = 0.1)
    error("expected discretize to reject using both npoints and spacing")
catch err
    err isa ArgumentError || rethrow(err)
end