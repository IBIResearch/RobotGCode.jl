"""
	string_curve(font, text; letter_spacing=0.0, normalize=true, scale=1.0, flip_y=false, resolution=4097)

Convert one-line `text` into a single `ParametricCurve`.

Each glyph is laid out left-to-right using the font's advance width,
translated with `translated`, converted to a curve via `merged`, and then
connected into one continuous curve using `merged`.
"""
function string_curve(
	font::TrueTypeFont,
	text::AbstractString;
	letter_spacing::Real = 0.0,
	normalize::Bool = true,
	scale::Real = 1.0,
	flip_y::Bool = false,
	resolution::Integer = 4097,
)
	isempty(text) && throw(ArgumentError("text must not be empty"))
	resolution >= 2 || throw(ArgumentError("resolution must be >= 2"))

	tracking = Float64(letter_spacing)
	unit_scale = (normalize ? (1.0 / font.unitsPerEm) : 1.0) * Float64(scale)

	pen_x = 0.0
	pieces = ParametricCurve[]

	for c in text
		c == '\n' && throw(ArgumentError("multi-line text is not supported; pass one line at a time"))

		gid = glyph_index(font, c)
		if gid == 0
			if isspace(c)
				pen_x += font.unitsPerEm * unit_scale + tracking
				continue
			end
			cp = uppercase(string(UInt32(c), base = 16))
			throw(ArgumentError("No glyph for character '$c' (U+$cp) in font"))
		end

		path = glyph_path(font, c; normalize = normalize, scale = scale, flip_y = flip_y)

		if !isempty(path.strokes)
			shifted = translated(path, (pen_x, 0.0))
			push!(pieces, merged(shifted; resolution = resolution))
		end

		pen_x += advance_width(font, gid) * unit_scale + tracking
	end

	isempty(pieces) && throw(ArgumentError("text has no drawable glyph outlines"))

	curve = pieces[1]
	@inbounds for i in 2:length(pieces)
		curve = merged(curve, pieces[i]; resolution = resolution)
	end

	curve
end

"""
	string_curve(text; kwargs...)

Convenience overload using `load_truetype_font()`.
"""
function string_curve(text::AbstractString; kwargs...)
	font = load_truetype_font()
	string_curve(font, text; kwargs...)
end
