using RobotGCode

font = load_truetype_font()          # auto-finds bundled .ttf
path = glyph_path(font, '')         # GlyphPath, callable with t∈[0,1]

strokes = sample_strokes(path, 200)
strokes = vcat(strokes...)
strokes3d = hcat(strokes, zeros(size(strokes, 1)))
fig = visualize_positions_3d(strokes3d)
display(fig)