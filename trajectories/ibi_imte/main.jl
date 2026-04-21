using RobotGCode

font = load_truetype_font()          # auto-finds bundled .ttf
path = glyph_path(font, 'd')         # GlyphPath with parameter domain t in [0,1]

npoints_per_stroke = 200
strokes = discretize(path; npoints = npoints_per_stroke)
strokes2d = vcat(strokes...)
strokes3d = hcat(strokes2d, zeros(size(strokes2d, 1)))
fig = visualize_positions_3d(strokes3d)
display(fig)