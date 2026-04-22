using RobotGCode

font = load_truetype_font()          # auto-finds bundled .ttf
# path = glyph_path(font, 'E')         # GlyphPath with parameter domain t in [0,1]
# curve = merged(path.strokes[1])
curve = string_curve("IMTE")

npoints_per_stroke = 200
points2d = discretize(curve; npoints = npoints_per_stroke)
points = hcat(points2d, zeros(size(points2d, 1)))
fig = visualize_positions_3d(points)
display(fig)