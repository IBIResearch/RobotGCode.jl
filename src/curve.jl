"""
	ParametricCurve(f)

Wrap a parametric curve function `f(t)` with `t in [0, 1]`.
The curve function must return a 1D point (tuple or vector) with a fixed dimension.
"""
struct ParametricCurve{F}
	f::F
end


@inline function _validated_t(t::Real)
	(0.0 <= t <= 1.0) || throw(DomainError(t, "t must be in [0,1]"))
	Float64(t)
end

function _point_to_vector(point)
	if point isa Tuple
		return Float64[Float64(x) for x in point]
	elseif point isa AbstractVector
		return Float64.(point)
	elseif point isa AbstractArray
		ndims(point) == 1 || throw(ArgumentError("curve point must be 1D, got ndims=$(ndims(point))"))
		return Float64.(vec(point))
	else
		throw(ArgumentError("curve point must be a tuple or vector, got $(typeof(point))"))
	end
end

function _validate_point_dimension(point::AbstractVector{<:Real}, expected::Integer)
	length(point) == expected || throw(ArgumentError("curve point dimension changed: expected $expected, got $(length(point))"))
	nothing
end

@inline function _row_distance(points::Matrix{Float64}, i::Int, j::Int)
	acc = 0.0
	@inbounds for k in axes(points, 2)
		d = points[i, k] - points[j, k]
		acc += d * d
	end
	sqrt(acc)
end

function _build_dense_curve_data(curve::ParametricCurve, resolution::Integer)
	resolution >= 2 || throw(ArgumentError("resolution must be >= 2"))

	ts = collect(range(0.0, 1.0, length = resolution))
	p0 = point_at(curve, ts[1])
	dim = length(p0)
	dim > 0 || throw(ArgumentError("curve points must have at least one coordinate"))

	points = Matrix{Float64}(undef, resolution, dim)
	@inbounds points[1, :] .= p0

	@inbounds for i in 2:resolution
		p = point_at(curve, ts[i])
		_validate_point_dimension(p, dim)
		points[i, :] .= p
	end

	cum_lengths = zeros(Float64, resolution)
	@inbounds for i in 2:resolution
		cum_lengths[i] = cum_lengths[i - 1] + _row_distance(points, i, i - 1)
	end

	return ts, cum_lengths, dim
end

@inline function _distance_to_t(target::Float64, ts::Vector{Float64}, cum_lengths::Vector{Float64})
	if target <= 0.0
		return ts[1]
	elseif target >= cum_lengths[end]
		return ts[end]
	end

	idx = searchsortedfirst(cum_lengths, target)
	idx = clamp(idx, 2, length(cum_lengths))

	d0 = cum_lengths[idx - 1]
	d1 = cum_lengths[idx]
	t0 = ts[idx - 1]
	t1 = ts[idx]

	d1 == d0 && return t0
	alpha = (target - d0) / (d1 - d0)
	t0 + alpha * (t1 - t0)
end

function _sample_uniform_t(curve::ParametricCurve, npoints::Integer)
	npoints >= 2 || throw(ArgumentError("npoints must be >= 2"))

	ts = collect(range(0.0, 1.0, length = npoints))
	p0 = point_at(curve, ts[1])
	dim = length(p0)
	points = Matrix{Float64}(undef, npoints, dim)
	@inbounds points[1, :] .= p0

	@inbounds for i in 2:npoints
		p = point_at(curve, ts[i])
		_validate_point_dimension(p, dim)
		points[i, :] .= p
	end

	points
end

function _sample_by_distances(curve::ParametricCurve, targets::Vector{Float64}, ts::Vector{Float64}, cum_lengths::Vector{Float64}, dim::Integer)
	n = length(targets)
	points = Matrix{Float64}(undef, n, dim)

	@inbounds for i in 1:n
		t = _distance_to_t(targets[i], ts, cum_lengths)
		p = point_at(curve, t)
		_validate_point_dimension(p, dim)
		points[i, :] .= p
	end

	points
end

"""
	point_at(curve, t)

Evaluate a parametric curve at parameter `t in [0, 1]`.
Returns a `Vector{Float64}`.
"""
function point_at(curve::ParametricCurve, t::Real)
	t_val = _validated_t(t)
	point = _point_to_vector(curve.f(t_val))
	isempty(point) && throw(ArgumentError("curve points must have at least one coordinate"))
	point
end

"""
	point_at(f, t)

Evaluate a raw parametric curve function `f(t)` at parameter `t in [0, 1]`.
"""
point_at(f::Function, t::Real) = point_at(ParametricCurve(f), t)

"""
	approx_length(curve; resolution=4097)

Approximate arc length of a parametric curve by dense sampling.
Higher `resolution` improves accuracy.
"""
function approx_length(curve::ParametricCurve; resolution::Integer = 4097)
	_, cum_lengths, _ = _build_dense_curve_data(curve, resolution)
	cum_lengths[end]
end

"""
	approx_length(f; resolution=4097)

Approximate arc length of a raw curve function `f(t)`.
"""
approx_length(f::Function; resolution::Integer = 4097) = approx_length(ParametricCurve(f); resolution)

"""
	discretize(curve; npoints=nothing, spacing=nothing, resolution=4097)

Discretize a parametric curve into an `NxD` matrix where each row is a point.

Choose exactly one mode:
- `npoints`: output exactly this number of points, approximately arc-length spaced.
- `spacing`: output points with approximately this Euclidean spacing along arc length.

`resolution` controls the dense sampling used to approximate arc length.
"""
function discretize(curve::ParametricCurve;
	npoints::Union{Nothing,Integer} = nothing,
	spacing::Union{Nothing,Real} = nothing,
	resolution::Integer = 4097,
)
	if (npoints === nothing) == (spacing === nothing)
		throw(ArgumentError("provide exactly one of npoints or spacing"))
	end

	ts, cum_lengths, dim = _build_dense_curve_data(curve, resolution)
	total_length = cum_lengths[end]

	if npoints !== nothing
		npoints >= 2 || throw(ArgumentError("npoints must be >= 2"))
		if total_length == 0.0
			return _sample_uniform_t(curve, npoints)
		end
		targets = collect(range(0.0, total_length, length = npoints))
		return _sample_by_distances(curve, targets, ts, cum_lengths, dim)
	end

	spacing_value = Float64(spacing)
	spacing_value > 0.0 || throw(ArgumentError("spacing must be > 0"))

	if total_length == 0.0
		return _sample_uniform_t(curve, 2)
	end

	targets = collect(0.0:spacing_value:total_length)
	if isempty(targets) || targets[end] < total_length
		push!(targets, total_length)
	end

	_sample_by_distances(curve, targets, ts, cum_lengths, dim)
end

"""
	discretize(f; kwargs...)

Discretize a raw curve function `f(t)`.
"""
discretize(f::Function; kwargs...) = discretize(ParametricCurve(f); kwargs...)
