using RobotGCode

"""
    helix(t; turns=3)

Helix trajectory with:
- x, y in [-1, 1] (unit circle)
- z in [0, 1]
- configurable number of turns
"""
function helix(t; turns::Real=3)
    τ = clamp(float(t), 0.0, 1.0)
    θ = 2π * turns * τ

    x = cos(θ)      # in [-1, 1]
    y = sin(θ)      # in [-1, 1]
    z = τ           # in [0, 1]

    return (x, y, z)
end