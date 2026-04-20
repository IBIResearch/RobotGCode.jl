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