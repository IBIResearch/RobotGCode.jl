
# ----------------------------------------------------------------------------
# TrueType font glyph sampling (quadratic Bézier curves)
# ----------------------------------------------------------------------------
#
# Goal
#   Provide a way to draw *any* Unicode codepoint supported by a bundled
#   TrueType (.ttf) font (default: ReliefSingleLineCAD-Regular.ttf).
#
# Approach
#   - Parse required SFNT tables: `cmap`, `head`, `maxp`, `loca`, `glyf`.
#   - Convert glyph outlines into line + quadratic Bézier segments.
#   - Build an arc-length-like parametrization for each glyph with t ∈ [0, 1].
#
# Notes
#   - This maps a Unicode *codepoint* to a glyph via `cmap`. For complex scripts
#     that require shaping (ligatures, combining marks, RTL), you would need a
#     shaper (e.g. HarfBuzz) on top. For single codepoints and simple Latin
#     text, `cmap` mapping is sufficient.


"""2D point."""
struct Point2
	x::Float64
	y::Float64
end

Point2(x::Real, y::Real) = Point2(Float64(x), Float64(y))

Base.:+(a::Point2, b::Point2) = Point2(a.x + b.x, a.y + b.y)
Base.:-(a::Point2, b::Point2) = Point2(a.x - b.x, a.y - b.y)
Base.:*(s::Real, p::Point2) = Point2(Float64(s) * p.x, Float64(s) * p.y)

@inline function _lerp(a::Point2, b::Point2, t::Float64)
	Point2((1 - t) * a.x + t * b.x, (1 - t) * a.y + t * b.y)
end

@inline function _midpoint(a::Point2, b::Point2)
	Point2(0.5 * (a.x + b.x), 0.5 * (a.y + b.y))
end

@inline function _dist(a::Point2, b::Point2)
	hypot(a.x - b.x, a.y - b.y)
end


abstract type Segment2D end

"""Straight line segment."""
struct LineSeg2D <: Segment2D
	p0::Point2
	p1::Point2
end

"""Quadratic Bézier segment (p0 → p2, control p1)."""
struct QuadSeg2D <: Segment2D
	p0::Point2
	p1::Point2
	p2::Point2
end

@inline function eval(seg::LineSeg2D, t::Float64)::Point2
	_lerp(seg.p0, seg.p1, t)
end

@inline function eval(seg::QuadSeg2D, t::Float64)::Point2
	# Quadratic Bézier: (1-t)^2 p0 + 2(1-t)t p1 + t^2 p2
	u = 1 - t
	w0 = u * u
	w1 = 2 * u * t
	w2 = t * t
	Point2(
		w0 * seg.p0.x + w1 * seg.p1.x + w2 * seg.p2.x,
		w0 * seg.p0.y + w1 * seg.p1.y + w2 * seg.p2.y,
	)
end

@inline function _end_point(seg::Segment2D)::Point2
	seg isa LineSeg2D && return (seg::LineSeg2D).p1
	seg isa QuadSeg2D && return (seg::QuadSeg2D).p2
	error("Unknown segment type $(typeof(seg))")
end

@inline function _start_point(seg::Segment2D)::Point2
	seg isa LineSeg2D && return (seg::LineSeg2D).p0
	seg isa QuadSeg2D && return (seg::QuadSeg2D).p0
	error("Unknown segment type $(typeof(seg))")
end


"""2D affine transform."""
struct Transform2D
	a::Float64
	b::Float64
	c::Float64
	d::Float64
	e::Float64
	f::Float64
end

Transform2D() = Transform2D(1.0, 0.0, 0.0, 1.0, 0.0, 0.0)

@inline function apply(tr::Transform2D, p::Point2)::Point2
	Point2(tr.a * p.x + tr.b * p.y + tr.e, tr.c * p.x + tr.d * p.y + tr.f)
end

@inline function compose(a::Transform2D, b::Transform2D)::Transform2D
	# Apply b first, then a:  a(b(p))
	Transform2D(
		a.a * b.a + a.b * b.c,
		a.a * b.b + a.b * b.d,
		a.c * b.a + a.d * b.c,
		a.c * b.b + a.d * b.d,
		a.a * b.e + a.b * b.f + a.e,
		a.c * b.e + a.d * b.f + a.f,
	)
end

@inline function transform(seg::LineSeg2D, tr::Transform2D)
	LineSeg2D(apply(tr, seg.p0), apply(tr, seg.p1))
end

@inline function transform(seg::QuadSeg2D, tr::Transform2D)
	QuadSeg2D(apply(tr, seg.p0), apply(tr, seg.p1), apply(tr, seg.p2))
end


"""A single continuous stroke (contour) parameterized by t∈[0,1]."""
struct StrokePath
	segments::Vector{Segment2D}
	seg_lengths::Vector{Float64}
	seg_cum_lengths::Vector{Float64}
	total_length::Float64
end

"""A glyph consisting of multiple strokes (contours)."""
struct GlyphPath
	strokes::Vector{StrokePath}
	stroke_lengths::Vector{Float64}
	stroke_cum_lengths::Vector{Float64}
	total_length::Float64
end

(p::StrokePath)(t::Real) = point_at(p, t)
(p::GlyphPath)(t::Real) = point_at(p, t)


@inline function _segment_length(seg::LineSeg2D)
	_dist(seg.p0, seg.p1)
end

function _segment_length(seg::QuadSeg2D; n::Int = 24)
	n >= 2 || throw(ArgumentError("n must be >= 2"))
	prev = eval(seg, 0.0)
	total = 0.0
	invn = 1.0 / n
	@inbounds for i in 1:n
		t = i * invn
		p = eval(seg, t)
		total += _dist(prev, p)
		prev = p
	end
	total
end

function _build_stroke_path(segments::Vector{Segment2D})
	seg_lengths = Float64[]
	seg_cum = Float64[]
	total = 0.0
	@inbounds for seg in segments
		len = seg isa LineSeg2D ? _segment_length(seg::LineSeg2D) : _segment_length(seg::QuadSeg2D)
		push!(seg_lengths, len)
		total += len
		push!(seg_cum, total)
	end
	StrokePath(segments, seg_lengths, seg_cum, total)
end

function _build_glyph_path(strokes::Vector{StrokePath})
	stroke_lengths = Float64[]
	stroke_cum = Float64[]
	total = 0.0
	@inbounds for s in strokes
		push!(stroke_lengths, s.total_length)
		total += s.total_length
		push!(stroke_cum, total)
	end
	GlyphPath(strokes, stroke_lengths, stroke_cum, total)
end


function point_at(path::StrokePath, t::Real)::Point2
	(0.0 <= t <= 1.0) || throw(DomainError(t, "t must be in [0,1]"))
	isempty(path.segments) && throw(ArgumentError("stroke has no segments"))

	if path.total_length == 0.0
		return _start_point(path.segments[1])
	end
	if t == 0.0
		return _start_point(path.segments[1])
	elseif t == 1.0
		return _end_point(path.segments[end])
	end

	target = Float64(t) * path.total_length
	idx = searchsortedfirst(path.seg_cum_lengths, target)
	idx = clamp(idx, 1, length(path.segments))
	prev_cum = idx == 1 ? 0.0 : path.seg_cum_lengths[idx - 1]
	seg_len = path.seg_lengths[idx]
	local_t = seg_len == 0.0 ? 0.0 : (target - prev_cum) / seg_len
	seg = path.segments[idx]
	if seg isa LineSeg2D
		return eval(seg::LineSeg2D, local_t)
	else
		return eval(seg::QuadSeg2D, local_t)
	end
end

function point_at(path::GlyphPath, t::Real)::Point2
	(0.0 <= t <= 1.0) || throw(DomainError(t, "t must be in [0,1]"))
	isempty(path.strokes) && throw(ArgumentError("glyph has no strokes"))

	if path.total_length == 0.0
		return _start_point(path.strokes[1].segments[1])
	end
	if t == 0.0
		return _start_point(path.strokes[1].segments[1])
	elseif t == 1.0
		laststroke = path.strokes[end]
		return _end_point(laststroke.segments[end])
	end

	target = Float64(t) * path.total_length
	sidx = searchsortedfirst(path.stroke_cum_lengths, target)
	sidx = clamp(sidx, 1, length(path.strokes))
	prev_cum = sidx == 1 ? 0.0 : path.stroke_cum_lengths[sidx - 1]
	slen = path.stroke_lengths[sidx]
	local_t = slen == 0.0 ? 0.0 : (target - prev_cum) / slen
	point_at(path.strokes[sidx], local_t)
end


"""Return the exact stored arc length of a stroke."""
approx_length(path::StrokePath) = path.total_length

"""Return the exact stored total arc length of a glyph."""
approx_length(path::GlyphPath) = path.total_length

"""
	discretize(path::StrokePath; kwargs...)

Discretize a stroke path using the generic parametric curve API.
Returns an Nx2 matrix.
"""
function discretize(path::StrokePath; kwargs...)
	curve = ParametricCurve(t -> begin
		p = point_at(path, t)
		(p.x, p.y)
	end)
	discretize(curve; kwargs...)
end

"""
	discretize(path::GlyphPath; npoints=nothing, spacing=nothing, resolution=4097)

Discretize each stroke of a glyph path.
Returns one Nx2 matrix per stroke.
"""
function discretize(path::GlyphPath;
	npoints::Union{Nothing,Integer} = nothing,
	spacing::Union{Nothing,Real} = nothing,
	resolution::Integer = 4097,
)
	if (npoints === nothing) == (spacing === nothing)
		throw(ArgumentError("provide exactly one of npoints or spacing"))
	end

	if npoints !== nothing
		return [discretize(s; npoints = npoints, resolution = resolution) for s in path.strokes]
	end

	spacing_value = Float64(spacing)
	return [discretize(s; spacing = spacing_value, resolution = resolution) for s in path.strokes]
end

"""
	merged(path::StrokePath)

Convert a stroke path into a single 2D `ParametricCurve` on `t in [0,1]`.
"""
function merged(path::StrokePath)
	ParametricCurve(t -> begin
		p = point_at(path, t)
		(p.x, p.y)
	end)
end

"""
	merged(path::GlyphPath; resolution=4097)

Convert a multi-stroke glyph into one `ParametricCurve` on `t in [0,1]` by
connecting consecutive strokes with straight segments.
"""
function merged(path::GlyphPath; resolution::Integer = 4097)
	resolution >= 2 || throw(ArgumentError("resolution must be >= 2"))
	isempty(path.strokes) && throw(ArgumentError("glyph has no strokes"))

	curve = merged(path.strokes[1])
	@inbounds for i in 2:length(path.strokes)
		curve = merged(curve, merged(path.strokes[i]); resolution = resolution)
	end
	curve
end


"""Sample a stroke path into an N×2 matrix."""
function sample(path::StrokePath, n::Integer)
	discretize(path; npoints = n)
end

"""Sample a glyph path into one polyline per stroke."""
function sample_strokes(path::GlyphPath, n_per_stroke::Integer)
	discretize(path; npoints = n_per_stroke)
end


# ----------------------------------------------------------------------------
# Minimal TrueType parsing
# ----------------------------------------------------------------------------

@inline function _u16be(data::Vector{UInt8}, i::Int)
	(UInt16(data[i]) << 8) | UInt16(data[i + 1])
end

@inline function _i16be(data::Vector{UInt8}, i::Int)
	reinterpret(Int16, _u16be(data, i))
end

@inline function _u32be(data::Vector{UInt8}, i::Int)
	(UInt32(data[i]) << 24) | (UInt32(data[i + 1]) << 16) | (UInt32(data[i + 2]) << 8) | UInt32(data[i + 3])
end

@inline function _i8(data::Vector{UInt8}, i::Int)
	reinterpret(Int8, data[i])
end

@inline function _tag4(data::Vector{UInt8}, i::Int)
	String(Char.(data[i:(i + 3)]))
end

abstract type CmapSubtable end

struct CmapFormat4 <: CmapSubtable
	endCode::Vector{UInt16}
	startCode::Vector{UInt16}
	idDelta::Vector{Int16}
	idRangeOffset::Vector{UInt16}
	glyphIdArray::Vector{UInt16}
end

struct CmapFormat12 <: CmapSubtable
	startCharCode::Vector{UInt32}
	endCharCode::Vector{UInt32}
	startGlyphID::Vector{UInt32}
end

"""Parsed TrueType font containing the data needed to obtain quadratic outlines."""
struct TrueTypeFont
	path::String
	data::Vector{UInt8}
	tables::Dict{String,Tuple{Int,Int}}  # tag => (offset1, length)
	unitsPerEm::Int
	indexToLocFormat::Int
	numGlyphs::Int
	loca::Vector{Int}                    # offsets (bytes) into glyf table, length numGlyphs+1
	cmap::CmapSubtable
	advanceWidths::Union{Nothing,Vector{Int}}  # per glyph, in font units
end


function _default_font_path()
	root = normpath(joinpath(@__DIR__, ".."))
	preferred = joinpath(root, "ReliefSingleLineCAD-Regular.ttf")
	if isfile(preferred)
		return preferred
	end
	ttf = filter(p -> endswith(lowercase(p), ".ttf"), readdir(root; join = true))
	isempty(ttf) && error("No .ttf font found in $root")
	return ttf[1]
end


"""\
	load_truetype_font(path=_default_font_path()) -> TrueTypeFont

Load a TrueType font and parse the tables required for glyph outline extraction.
"""
function load_truetype_font(path::AbstractString = _default_font_path())
	isfile(path) || throw(ArgumentError("Font file not found: $path"))
	data = read(path)
	length(data) >= 12 || throw(ArgumentError("Not a valid .ttf (too small): $path"))

	numTables = Int(_u16be(data, 5))
	dir_start = 13
	dir_len = 16 * numTables
	(dir_start + dir_len - 1) <= length(data) || throw(ArgumentError("Truncated table directory in $path"))

	tables = Dict{String,Tuple{Int,Int}}()
	@inbounds for t in 0:(numTables - 1)
		base = dir_start + 16 * t
		tag = _tag4(data, base)
		offset0 = Int(_u32be(data, base + 8))
		len = Int(_u32be(data, base + 12))
		offset1 = offset0 + 1
		tables[tag] = (offset1, len)
	end

	function table_range(tag::String)
		haskey(tables, tag) || throw(ArgumentError("Required table '$tag' not found in font $path"))
		(off, len) = tables[tag]
		(off, off + len - 1)
	end

	head_off, _ = tables["head"]
	unitsPerEm = Int(_u16be(data, head_off + 18))
	indexToLocFormat = Int(_i16be(data, head_off + 50))

	maxp_off, _ = tables["maxp"]
	numGlyphs = Int(_u16be(data, maxp_off + 4))

	# `loca` offsets into `glyf`
	loca_off, _ = tables["loca"]
	loca = Vector{Int}(undef, numGlyphs + 1)
	if indexToLocFormat == 0
		@inbounds for i in 0:numGlyphs
			loca[i + 1] = 2 * Int(_u16be(data, loca_off + 2 * i))
		end
	elseif indexToLocFormat == 1
		@inbounds for i in 0:numGlyphs
			loca[i + 1] = Int(_u32be(data, loca_off + 4 * i))
		end
	else
		throw(ArgumentError("Unsupported indexToLocFormat=$indexToLocFormat in $path"))
	end

	# cmap
	cmap_off, _ = tables["cmap"]
	cmap = _parse_cmap(data, cmap_off)

	# hmtx (optional but helpful for text layout)
	advanceWidths = _try_parse_hmtx(data, tables, numGlyphs)

	TrueTypeFont(String(path), data, tables, unitsPerEm, indexToLocFormat, numGlyphs, loca, cmap, advanceWidths)
end


function _parse_cmap(data::Vector{UInt8}, cmap_off::Int)::CmapSubtable
	version = _u16be(data, cmap_off)
	version == 0x0000 || throw(ArgumentError("Unsupported cmap version=$version"))
	numTables = Int(_u16be(data, cmap_off + 2))
	best_fmt12 = nothing
	best_fmt4 = nothing

	# Try to pick a Unicode subtable.
	# Prefer format 12 (covers non-BMP), else format 4.
	@inbounds for i in 0:(numTables - 1)
		rec = cmap_off + 4 + 8 * i
		platformID = Int(_u16be(data, rec))
		encodingID = Int(_u16be(data, rec + 2))
		sub_off0 = Int(_u32be(data, rec + 4))
		sub_off = cmap_off + sub_off0
		fmt = Int(_u16be(data, sub_off))

		is_unicode = (platformID == 0) || (platformID == 3 && (encodingID == 1 || encodingID == 10))
		is_unicode || continue

		if fmt == 12
			best_fmt12 = _parse_cmap_format12(data, sub_off)
		elseif fmt == 4
			best_fmt4 = _parse_cmap_format4(data, sub_off)
		end
	end

	best_fmt12 !== nothing && return best_fmt12
	best_fmt4 !== nothing && return best_fmt4
	throw(ArgumentError("No supported Unicode cmap subtable (format 4/12) found"))
end

function _parse_cmap_format4(data::Vector{UInt8}, off::Int)
	fmt = _u16be(data, off)
	fmt == 4 || throw(ArgumentError("Expected cmap format 4"))
	length_bytes = Int(_u16be(data, off + 2))
	segCount = Int(_u16be(data, off + 6)) ÷ 2

	endCode_off = off + 14
	endCode = Vector{UInt16}(undef, segCount)
	@inbounds for i in 0:(segCount - 1)
		endCode[i + 1] = _u16be(data, endCode_off + 2 * i)
	end

	startCode_off = endCode_off + 2 * segCount + 2
	startCode = Vector{UInt16}(undef, segCount)
	@inbounds for i in 0:(segCount - 1)
		startCode[i + 1] = _u16be(data, startCode_off + 2 * i)
	end

	idDelta_off = startCode_off + 2 * segCount
	idDelta = Vector{Int16}(undef, segCount)
	@inbounds for i in 0:(segCount - 1)
		idDelta[i + 1] = _i16be(data, idDelta_off + 2 * i)
	end

	idRangeOffset_off = idDelta_off + 2 * segCount
	idRangeOffset = Vector{UInt16}(undef, segCount)
	@inbounds for i in 0:(segCount - 1)
		idRangeOffset[i + 1] = _u16be(data, idRangeOffset_off + 2 * i)
	end

	glyphArray_off = idRangeOffset_off + 2 * segCount
	glyphArray_words = max(0, (length_bytes - (glyphArray_off - off)) ÷ 2)
	glyphIdArray = Vector{UInt16}(undef, glyphArray_words)
	@inbounds for i in 0:(glyphArray_words - 1)
		glyphIdArray[i + 1] = _u16be(data, glyphArray_off + 2 * i)
	end

	CmapFormat4(endCode, startCode, idDelta, idRangeOffset, glyphIdArray)
end

function _parse_cmap_format12(data::Vector{UInt8}, off::Int)
	fmt = _u16be(data, off)
	fmt == 12 || throw(ArgumentError("Expected cmap format 12"))
	nGroups = Int(_u32be(data, off + 12))
	startCharCode = Vector{UInt32}(undef, nGroups)
	endCharCode = Vector{UInt32}(undef, nGroups)
	startGlyphID = Vector{UInt32}(undef, nGroups)
	base = off + 16
	@inbounds for i in 0:(nGroups - 1)
		rec = base + 12 * i
		startCharCode[i + 1] = _u32be(data, rec)
		endCharCode[i + 1] = _u32be(data, rec + 4)
		startGlyphID[i + 1] = _u32be(data, rec + 8)
	end
	CmapFormat12(startCharCode, endCharCode, startGlyphID)
end


function _try_parse_hmtx(data::Vector{UInt8}, tables::Dict{String,Tuple{Int,Int}}, numGlyphs::Int)
	(haskey(tables, "hhea") && haskey(tables, "hmtx")) || return nothing
	hhea_off, _ = tables["hhea"]
	hmtx_off, _ = tables["hmtx"]
	numberOfHMetrics = Int(_u16be(data, hhea_off + 34))
	numberOfHMetrics = clamp(numberOfHMetrics, 0, numGlyphs)

	aw = Vector{Int}(undef, numGlyphs)
	# First: full metrics records
	@inbounds for gid in 0:(numberOfHMetrics - 1)
		rec = hmtx_off + 4 * gid
		aw[gid + 1] = Int(_u16be(data, rec))
	end
	# Remaining glyphs reuse last advance width
	if numberOfHMetrics > 0 && numberOfHMetrics < numGlyphs
		last_aw = aw[numberOfHMetrics]
		@inbounds for gid in numberOfHMetrics:(numGlyphs - 1)
			aw[gid + 1] = last_aw
		end
	end
	aw
end


"""Return the glyph index (gid) for a Unicode codepoint. Returns 0 if missing."""
function glyph_index(font::TrueTypeFont, codepoint::Integer)
	cp = UInt32(codepoint)
	glyph_index(font.cmap, cp)
end

glyph_index(font::TrueTypeFont, c::Char) = glyph_index(font, UInt32(c))

function glyph_index(cmap::CmapFormat12, cp::UInt32)
	# Groups are sorted by startCharCode.
	idx = searchsortedlast(cmap.startCharCode, cp)
	idx < 1 && return 0
	cp <= cmap.endCharCode[idx] || return 0
	Int(cmap.startGlyphID[idx] + (cp - cmap.startCharCode[idx]))
end

function glyph_index(cmap::CmapFormat4, cp::UInt32)
	cp > 0xFFFF && return 0
	c = UInt16(cp)
	i = searchsortedfirst(cmap.endCode, c)
	i > length(cmap.endCode) && return 0
	c < cmap.startCode[i] && return 0

	ro = Int(cmap.idRangeOffset[i])
	if ro == 0
		return Int(UInt16(c + reinterpret(UInt16, cmap.idDelta[i])))
	end

	segCount = length(cmap.endCode)
	# Index in glyphIdArray (0-based) from spec derivation.
	idx0 = (ro ÷ 2) + Int(c - cmap.startCode[i]) - (segCount - i + 1)
	if idx0 < 0 || idx0 >= length(cmap.glyphIdArray)
		return 0
	end
	glyph = cmap.glyphIdArray[idx0 + 1]
	glyph == 0 && return 0
	Int(UInt16(glyph + reinterpret(UInt16, cmap.idDelta[i])))
end


"""Advance width for a glyph id in font units (falls back to unitsPerEm)."""
function advance_width(font::TrueTypeFont, gid::Integer)
	0 <= gid < font.numGlyphs || throw(ArgumentError("gid out of range"))
	font.advanceWidths === nothing && return font.unitsPerEm
	font.advanceWidths[Int(gid) + 1]
end


"""\
	glyph_segments(font, gid; transform=Transform2D()) -> Vector{Vector{Segment2D}}

Return contours for a glyph as vectors of segments (LineSeg2D and QuadSeg2D).
"""
function glyph_segments(font::TrueTypeFont, gid::Integer; transform::Transform2D = Transform2D())
	0 <= gid < font.numGlyphs || throw(ArgumentError("gid out of range"))
	data = font.data
	glyf_off, _ = font.tables["glyf"]
	start_off = font.loca[Int(gid) + 1]
	end_off = font.loca[Int(gid) + 2]
	start_off == end_off && return Vector{Vector{Segment2D}}()
	gpos = glyf_off + start_off

	numberOfContours = Int(_i16be(data, gpos))
	# skip bbox (8 bytes)
	if numberOfContours >= 0
		_simple_glyph_segments(data, gpos, numberOfContours, transform)
	else
		_compound_glyph_segments(font, gpos, transform)
	end
end


struct _TTPoint
	p::Point2
	on::Bool
end

function _contour_to_segments(points::Vector{_TTPoint})
	isempty(points) && return Segment2D[]

	# Ensure we start with an on-curve point (insert implicit if needed).
	pts = points
	if !pts[1].on
		start = _midpoint(pts[end].p, pts[1].p)
		pts = [_TTPoint(start, true); pts]
	end

	# Insert implicit on-curve points between consecutive off-curve points.
	expanded = _TTPoint[]
	push!(expanded, pts[1])
	@inbounds for i in 2:length(pts)
		prev = expanded[end]
		cur = pts[i]
		if !prev.on && !cur.on
			push!(expanded, _TTPoint(_midpoint(prev.p, cur.p), true))
		end
		push!(expanded, cur)
	end

	# Close contour by appending the first point.
	closed = [expanded; expanded[1]]

	segs = Segment2D[]
	prev_on = closed[1].p
	i = 2
	while i <= length(closed)
		pt = closed[i]
		if pt.on
			push!(segs, LineSeg2D(prev_on, pt.p))
			prev_on = pt.p
			i += 1
		else
			control = pt.p
			i + 1 <= length(closed) || break
			endpoint = closed[i + 1]
			endpoint.on || error("Internal error: expected on-curve endpoint")
			push!(segs, QuadSeg2D(prev_on, control, endpoint.p))
			prev_on = endpoint.p
			i += 2
		end
	end
	segs
end


function _simple_glyph_segments(data::Vector{UInt8}, gpos::Int, numberOfContours::Int, tr::Transform2D)
	# Layout after header (10 bytes): endPtsOfContours, instructions, flags, coords
	pos = gpos + 10

	endPts = Vector{Int}(undef, numberOfContours)
	@inbounds for i in 1:numberOfContours
		endPts[i] = Int(_u16be(data, pos))
		pos += 2
	end
	nPoints = endPts[end] + 1

	instructionLength = Int(_u16be(data, pos))
	pos += 2 + instructionLength

	# flags (with repeats)
	flags = Vector{UInt8}(undef, nPoints)
	fi = 1
	while fi <= nPoints
		f = data[pos]
		pos += 1
		flags[fi] = f
		fi += 1
		if (f & 0x08) != 0
			rep = Int(data[pos])
			pos += 1
			@inbounds for _ in 1:rep
				flags[fi] = f
				fi += 1
			end
		end
	end

	# x coordinates (deltas)
	xs = Vector{Int}(undef, nPoints)
	x = 0
	@inbounds for i in 1:nPoints
		f = flags[i]
		if (f & 0x02) != 0
			dx = Int(data[pos])
			pos += 1
			if (f & 0x10) != 0
				x += dx
			else
				x -= dx
			end
		else
			if (f & 0x10) != 0
				# same x
			else
				x += Int(_i16be(data, pos))
				pos += 2
			end
		end
		xs[i] = x
	end

	# y coordinates (deltas)
	ys = Vector{Int}(undef, nPoints)
	y = 0
	@inbounds for i in 1:nPoints
		f = flags[i]
		if (f & 0x04) != 0
			dy = Int(data[pos])
			pos += 1
			if (f & 0x20) != 0
				y += dy
			else
				y -= dy
			end
		else
			if (f & 0x20) != 0
				# same y
			else
				y += Int(_i16be(data, pos))
				pos += 2
			end
		end
		ys[i] = y
	end

	# Build contours
	contours = Vector{Vector{Segment2D}}()
	start = 1
	@inbounds for c in 1:numberOfContours
		stop = endPts[c] + 1
		pts = Vector{_TTPoint}(undef, stop - start + 1)
		for i in start:stop
			on = (flags[i] & 0x01) != 0
			pts[i - start + 1] = _TTPoint(apply(tr, Point2(xs[i], ys[i])), on)
		end
		push!(contours, _contour_to_segments(pts))
		start = stop + 1
	end
	contours
end


function _f2dot14(data::Vector{UInt8}, pos::Int)
	v = reinterpret(Int16, _u16be(data, pos))
	Float64(v) / 16384.0
end


function _compound_glyph_segments(font::TrueTypeFont, gpos::Int, tr::Transform2D)
	data = font.data
	pos = gpos + 10
	contours = Vector{Vector{Segment2D}}()

	ARG_1_AND_2_ARE_WORDS = UInt16(0x0001)
	ARGS_ARE_XY_VALUES = UInt16(0x0002)
	WE_HAVE_A_SCALE = UInt16(0x0008)
	MORE_COMPONENTS = UInt16(0x0020)
	WE_HAVE_AN_X_AND_Y_SCALE = UInt16(0x0040)
	WE_HAVE_A_TWO_BY_TWO = UInt16(0x0080)
	WE_HAVE_INSTRUCTIONS = UInt16(0x0100)

	flags = UInt16(0)
	while true
		flags = _u16be(data, pos)
		pos += 2
		comp_gid = Int(_u16be(data, pos))
		pos += 2

		if (flags & ARG_1_AND_2_ARE_WORDS) != 0
			arg1 = Int(_i16be(data, pos))
			arg2 = Int(_i16be(data, pos + 2))
			pos += 4
		else
			arg1 = Int(_i8(data, pos))
			arg2 = Int(_i8(data, pos + 1))
			pos += 2
		end

		if (flags & ARGS_ARE_XY_VALUES) == 0
			throw(ArgumentError("Composite glyph uses ARGS_ARE_POINTS (not supported yet)"))
		end
		dx = Float64(arg1)
		dy = Float64(arg2)

		# component transform
		a = 1.0; b = 0.0; c = 0.0; d = 1.0
		if (flags & WE_HAVE_A_SCALE) != 0
			s = _f2dot14(data, pos)
			pos += 2
			a = s; d = s
		elseif (flags & WE_HAVE_AN_X_AND_Y_SCALE) != 0
			sx = _f2dot14(data, pos)
			sy = _f2dot14(data, pos + 2)
			pos += 4
			a = sx; d = sy
		elseif (flags & WE_HAVE_A_TWO_BY_TWO) != 0
			a = _f2dot14(data, pos)
			b = _f2dot14(data, pos + 2)
			c = _f2dot14(data, pos + 4)
			d = _f2dot14(data, pos + 6)
			pos += 8
		end
		comp_tr = Transform2D(a, b, c, d, dx, dy)
		combined = compose(tr, comp_tr)

		for contour in glyph_segments(font, comp_gid; transform = combined)
			push!(contours, contour)
		end

		(flags & MORE_COMPONENTS) != 0 || break
	end

	if (flags & WE_HAVE_INSTRUCTIONS) != 0
		instr_len = Int(_u16be(data, pos))
		pos += 2 + instr_len
	end
	contours
end


"""\
	glyph_path(font, char_or_codepoint; normalize=true, scale=1.0, translate=Point2(0,0), flip_y=false)

Build a parameterized path for the glyph corresponding to a Unicode character.

- `normalize=true` divides font units by `unitsPerEm` (so typical glyph height ~ 1).
- `scale` is an extra multiplier applied after normalization.
"""
function glyph_path(
	font::TrueTypeFont,
	char_or_codepoint;
	normalize::Bool = true,
	scale::Real = 1.0,
	translate::Point2 = Point2(0.0, 0.0),
	flip_y::Bool = false,
)
	cp = char_or_codepoint isa Char ? UInt32(char_or_codepoint) : UInt32(char_or_codepoint)
	gid = glyph_index(font, cp)
	gid == 0 && throw(ArgumentError("No glyph for codepoint U+$(uppercase(string(cp, base=16))) in font"))

	contours = glyph_segments(font, gid)
	s = (normalize ? (1.0 / font.unitsPerEm) : 1.0) * Float64(scale)
	ysign = flip_y ? -1.0 : 1.0

	strokes = StrokePath[]
	for contour in contours
		segs = Segment2D[]
		for seg in contour
			if seg isa LineSeg2D
				ls = seg::LineSeg2D
				p0 = Point2(ls.p0.x * s + translate.x, ysign * ls.p0.y * s + translate.y)
				p1 = Point2(ls.p1.x * s + translate.x, ysign * ls.p1.y * s + translate.y)
				push!(segs, LineSeg2D(p0, p1))
			else
				qs = seg::QuadSeg2D
				p0 = Point2(qs.p0.x * s + translate.x, ysign * qs.p0.y * s + translate.y)
				p1 = Point2(qs.p1.x * s + translate.x, ysign * qs.p1.y * s + translate.y)
				p2 = Point2(qs.p2.x * s + translate.x, ysign * qs.p2.y * s + translate.y)
				push!(segs, QuadSeg2D(p0, p1, p2))
			end
		end
		push!(strokes, _build_stroke_path(segs))
	end
	_build_glyph_path(strokes)
end

