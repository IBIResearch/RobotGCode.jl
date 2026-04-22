# RobotGCode

RobotGCode is a small Julia package for converting trajectory data into G-code for a robot or CNC-style motion system.

The package currently focuses on one workflow:

- read a trajectory from an HDF5 file, or
- accept a trajectory matrix directly in Julia,
- convert coordinates from meters to millimeters,
- write a `.gcode` file with absolute moves.

## Features

- Generate G-code from an HDF5 dataset at `trajectory/position`
- Accept in-memory trajectory matrices with shape `N x 3` or `3 x N`
- Apply a configurable coordinate offset
- Convert positions from meters to millimeters
- Emit a simple motion program with `G21`, `G90`, linear moves, a dwell, and `M2`

## Requirements

- Julia 1.10 or newer
- The `HDF5` package

The repository includes a `Project.toml` and `Manifest.toml`, so the easiest setup is to use the project environment from the repository root.

## Installation

From the repository root, start Julia and activate the project:

```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()
```

## Usage

### From an HDF5 file

```julia
using RobotGCode

generate_gcode(
	eingabe_datei = "data/slow/MMRTrajSlow.mmr",
	ausgabe_datei = "output.gcode",
	frame_time = 1.0,
	offset = (0.0, 0.0, 110.0),
)
```

### From a matrix

```julia
using RobotGCode

positions = [
	0.000  0.000  0.000;
	0.010  0.005  0.002;
	0.020  0.010  0.004;
]

generate_gcode(
	positions;
	ausgabe_datei = "output.gcode",
	frame_time = 1.0,
	offset = (0.0, 0.0, 110.0),
)
```

### Lift a 2D curve to 3D before discretizing

```julia
using RobotGCode

curve2d = string_curve("IMTE")
curve3d = with_z(curve2d, 0.0)
points = discretize(curve3d; npoints = 200)  # Nx3
```

## Input Format

The HDF5 input file must contain a dataset at:

```text
trajectory/position
```

The dataset should contain 3D positions in meters. Both of the following shapes are accepted:

- `N x 3` where each row is a point
- `3 x N` where each column is a point

## Output

The generated G-code:

- switches to millimeters with `G21`
- uses absolute positioning with `G90`
- moves through each trajectory point with `G1`
- inserts a short dwell at the end of the path
- terminates with `M2`

Coordinate values are converted from meters to millimeters before writing the file. The `offset` parameter lets you shift the trajectory into the robot's coordinate frame.

## Example Data

The `data/` folder contains example trajectories and generated G-code files for several motion types:

- `slow/`
- `spiral/`
- `circular/`
- `helix/`
- `meander/`
- `lissajous/`

The file `data/slow/MMRTrajSlow.mmr` is a sample HDF5 trajectory file that can be used immediately with `generate_gcode`.

## Project Structure

```text
src/RobotGCode.jl   # Package entry point and G-code generator
data/               # Example trajectories and generated outputs
test/               # Basic package tests
```

## Tests

Run the test suite from the repository root:

```julia
using Pkg
Pkg.activate(".")
Pkg.test()
```

## Notes

- The generator currently writes files directly and does not provide a command-line interface.
- If your robot uses a different axis convention, adjust the `offset` values before generating G-code.
