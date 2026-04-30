function _as_float_vector(value, name::AbstractString)
	if value isa Tuple || value isa AbstractVector
		out = Float64[Float64(x) for x in value]
		isempty(out) && throw(ArgumentError("$name must not be empty"))
		return out
	end
	throw(ArgumentError("$name must be a tuple or vector, got $(typeof(value))"))
end

function _center_vector(center, dim::Integer)
	if center === nothing
		return zeros(Float64, dim)
	end
	ctr = _as_float_vector(center, "center")
	length(ctr) == dim || throw(ArgumentError("center dimension mismatch: expected $dim, got $(length(ctr))"))
	ctr
end

function _point2(value, name::AbstractString)
	if value isa Point2
		return value
	end
	v = _as_float_vector(value, name)
	length(v) == 2 || throw(ArgumentError("$name must be 2D for font paths"))
	Point2(v[1], v[2])
end

function _transform_stroke(path::StrokePath, tr::Transform2D)
	segs = Segment2D[transform(seg, tr) for seg in path.segments]
	_build_stroke_path(segs)
end

function _transform_glyph(path::GlyphPath, tr::Transform2D)
	strokes = StrokePath[_transform_stroke(s, tr) for s in path.strokes]
	_build_glyph_path(strokes)
end

function _reversed_segment(seg::Segment2D)
	if seg isa LineSeg2D
		s = seg::LineSeg2D
		return LineSeg2D(s.p1, s.p0)
	elseif seg isa QuadSeg2D
		s = seg::QuadSeg2D
		return QuadSeg2D(s.p2, s.p1, s.p0)
	end
	throw(ArgumentError("unsupported segment type $(typeof(seg))"))
end

"""
	translated(curve, offset)

Return a translated copy of a curve/path by adding a fixed `offset`.
"""
function translated(curve::ParametricCurve, offset)
	p0 = point_at(curve, 0.0)
	off = _as_float_vector(offset, "offset")
	length(off) == length(p0) || throw(ArgumentError("offset dimension mismatch: expected $(length(p0)), got $(length(off))"))

	ParametricCurve(t -> begin
		p = point_at(curve, t)
		p .+ off
	end)
end

translated(f::Function, offset) = translated(ParametricCurve(f), offset)

function translated(path::StrokePath, offset)
	off = _point2(offset, "offset")
	tr = Transform2D(1.0, 0.0, 0.0, 1.0, off.x, off.y)
	_transform_stroke(path, tr)
end

function translated(path::GlyphPath, offset)
	off = _point2(offset, "offset")
	tr = Transform2D(1.0, 0.0, 0.0, 1.0, off.x, off.y)
	_transform_glyph(path, tr)
end

"""
	with_z(curve, z=0.0)

Lift a 2D curve into 3D by appending a constant `z` coordinate.
"""
function with_z(curve::ParametricCurve, z::Real = 0.0)
	p0 = point_at(curve, 0.0)
	length(p0) == 2 || throw(ArgumentError("with_z expects a 2D curve, got dimension $(length(p0))"))
	z_value = Float64(z)

	ParametricCurve(t -> begin
		p = point_at(curve, t)
		length(p) == 2 || throw(ArgumentError("curve point dimension changed: expected 2, got $(length(p))"))
		(p[1], p[2], z_value)
	end)
end

with_z(f::Function, z::Real = 0.0) = with_z(ParametricCurve(f), z)

"""
	rotated(curve, angle; center=nothing, axes=(1,2))

Return a rotated copy of a curve/path.

For `ParametricCurve`, rotation is in the plane defined by `axes`.
For font paths, rotation is always in 2D.
"""
function rotated(curve::ParametricCurve, angle::Real; center = nothing, axes::Tuple{Int,Int} = (1, 2))
	i, j = axes
	i != j || throw(ArgumentError("rotation axes must be different"))
	i >= 1 && j >= 1 || throw(ArgumentError("rotation axes must be >= 1"))

	p0 = point_at(curve, 0.0)
	dim = length(p0)
	i <= dim && j <= dim || throw(ArgumentError("rotation axes $(axes) out of range for dimension $dim"))
	ctr = _center_vector(center, dim)

	a = Float64(angle)
	c = cos(a)
	s = sin(a)

	ParametricCurve(t -> begin
		p = point_at(curve, t)
		q = copy(p)

		xi = p[i] - ctr[i]
		xj = p[j] - ctr[j]

		q[i] = ctr[i] + c * xi - s * xj
		q[j] = ctr[j] + s * xi + c * xj
		q
	end)
end

rotated(f::Function, angle::Real; kwargs...) = rotated(ParametricCurve(f), angle; kwargs...)

function rotated(path::StrokePath, angle::Real; center = (0.0, 0.0))
	ctr = _point2(center, "center")
	a = Float64(angle)
	c = cos(a)
	s = sin(a)

	to_origin = Transform2D(1.0, 0.0, 0.0, 1.0, -ctr.x, -ctr.y)
	rot = Transform2D(c, -s, s, c, 0.0, 0.0)
	back = Transform2D(1.0, 0.0, 0.0, 1.0, ctr.x, ctr.y)
	tr = compose(back, compose(rot, to_origin))

	_transform_stroke(path, tr)
end

function rotated(path::GlyphPath, angle::Real; center = (0.0, 0.0))
	ctr = _point2(center, "center")
	a = Float64(angle)
	c = cos(a)
	s = sin(a)

	to_origin = Transform2D(1.0, 0.0, 0.0, 1.0, -ctr.x, -ctr.y)
	rot = Transform2D(c, -s, s, c, 0.0, 0.0)
	back = Transform2D(1.0, 0.0, 0.0, 1.0, ctr.x, ctr.y)
	tr = compose(back, compose(rot, to_origin))

	_transform_glyph(path, tr)
end

"""
	scaled(curve, factor; center=nothing)

Return a scaled copy of a curve/path around `center`.
"""
function scaled(curve::ParametricCurve, factor::Real; center = nothing)
	s = Float64(factor)
	s > 0.0 || throw(ArgumentError("factor must be > 0"))

	p0 = point_at(curve, 0.0)
	dim = length(p0)
	ctr = _center_vector(center, dim)

	ParametricCurve(t -> begin
		p = point_at(curve, t)
		ctr .+ s .* (p .- ctr)
	end)
end

"""
	fit_to_box(curve, (x_min, x_max), (y_min, y_max), (z_min, z_max); resolution=4097)
	fit_to_box(curve, limits...; resolution=4097)

Return a transformed copy of `curve` that fits inside the provided
axis-aligned bounding box.

- Centers are aligned (curve bbox center -> target bbox center).
- Scaling is uniform across all coordinates to preserve shape.
- The scale factor is chosen as large as possible while still fitting in the
  target box (i.e. the most restrictive axis hits its limits).

The curve bounding box is approximated by sampling `resolution` values of `t`.
Increase `resolution` if you need a tighter fit.
"""
function fit_to_box(curve::ParametricCurve, limits::Vararg{Tuple{<:Real,<:Real}}; resolution::Integer = 4097)
	target_dim = length(limits)
	target_dim > 0 || throw(ArgumentError("provide at least one (min, max) limit tuple"))

	bbox = bounding_box(curve; resolution = resolution)
	curve_dim = length(bbox)
	target_dim == curve_dim || throw(ArgumentError("target box dimension mismatch: curve is $curve_dim D, got $target_dim limits"))

	cur_mins = Vector{Float64}(undef, curve_dim)
	cur_maxs = Vector{Float64}(undef, curve_dim)
	target_mins = Vector{Float64}(undef, curve_dim)
	target_maxs = Vector{Float64}(undef, curve_dim)

	@inbounds for k in 1:curve_dim
		(cur_lo, cur_hi) = bbox[k]
		cur_mins[k] = cur_lo
		cur_maxs[k] = cur_hi

		(tgt_lo_raw, tgt_hi_raw) = limits[k]
		tgt_lo = Float64(tgt_lo_raw)
		tgt_hi = Float64(tgt_hi_raw)
		tgt_lo < tgt_hi || throw(ArgumentError("limit #$k must satisfy min < max, got ($tgt_lo_raw, $tgt_hi_raw)"))
		target_mins[k] = tgt_lo
		target_maxs[k] = tgt_hi
	end

	cur_center = 0.5 .* (cur_mins .+ cur_maxs)
	target_center = 0.5 .* (target_mins .+ target_maxs)
	cur_ranges = cur_maxs .- cur_mins
	target_ranges = target_maxs .- target_mins

	scale = Inf
	has_extent = false
	@inbounds for k in 1:curve_dim
		r = cur_ranges[k]
		if r > 0.0
			has_extent = true
			scale = min(scale, target_ranges[k] / r)
		end
	end

	# Degenerate curve (all points identical): just translate the point to the target center.
	if !has_extent
		offset = target_center .- cur_center
		return translated(curve, offset)
	end

	isfinite(scale) || throw(ArgumentError("failed to compute a finite scale factor"))
	scale > 0.0 || throw(ArgumentError("computed non-positive scale factor $scale"))

	scaled_curve = scaled(curve, scale; center = cur_center)
	offset = target_center .- cur_center
	translated(scaled_curve, offset)
end

fit_to_box(curve::ParametricCurve, limits::AbstractVector{<:Tuple{<:Real,<:Real}}; kwargs...) = fit_to_box(curve, limits...; kwargs...)

fit_to_box(f::Function, limits...; kwargs...) = fit_to_box(ParametricCurve(f), limits...; kwargs...)

scaled(f::Function, factor::Real; kwargs...) = scaled(ParametricCurve(f), factor; kwargs...)

function scaled(path::StrokePath, factor::Real; center = (0.0, 0.0))
	s = Float64(factor)
	s > 0.0 || throw(ArgumentError("factor must be > 0"))
	ctr = _point2(center, "center")

	to_origin = Transform2D(1.0, 0.0, 0.0, 1.0, -ctr.x, -ctr.y)
	scl = Transform2D(s, 0.0, 0.0, s, 0.0, 0.0)
	back = Transform2D(1.0, 0.0, 0.0, 1.0, ctr.x, ctr.y)
	tr = compose(back, compose(scl, to_origin))

	_transform_stroke(path, tr)
end

function scaled(path::GlyphPath, factor::Real; center = (0.0, 0.0))
	s = Float64(factor)
	s > 0.0 || throw(ArgumentError("factor must be > 0"))
	ctr = _point2(center, "center")

	to_origin = Transform2D(1.0, 0.0, 0.0, 1.0, -ctr.x, -ctr.y)
	scl = Transform2D(s, 0.0, 0.0, s, 0.0, 0.0)
	back = Transform2D(1.0, 0.0, 0.0, 1.0, ctr.x, ctr.y)
	tr = compose(back, compose(scl, to_origin))

	_transform_glyph(path, tr)
end

"""
	reversed(curve)

Return a copy of a curve/path that traverses from end to start.
"""
function reversed(curve::ParametricCurve)
	ParametricCurve(t -> point_at(curve, 1.0 - t))
end

reversed(f::Function) = reversed(ParametricCurve(f))

function reversed(path::StrokePath)
	n = length(path.segments)
	segs = Vector{Segment2D}(undef, n)
	@inbounds for i in 1:n
		segs[i] = _reversed_segment(path.segments[n - i + 1])
	end
	_build_stroke_path(segs)
end

function reversed(path::GlyphPath)
	n = length(path.strokes)
	strokes = Vector{StrokePath}(undef, n)
	@inbounds for i in 1:n
		strokes[i] = reversed(path.strokes[n - i + 1])
	end
	_build_glyph_path(strokes)
end

"""
	zoomed(curve, factor; kwargs...)

Alias for `scaled`.
"""
zoomed(curve, factor::Real; kwargs...) = scaled(curve, factor; kwargs...)

