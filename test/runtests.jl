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
else
    @warn "Skipping font test: bundled .ttf not found" font_path
end