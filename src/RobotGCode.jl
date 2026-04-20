module RobotGCode

export generate_gcode, visualize_positions_3d

"""
G-Code Generator aus HDF5-Trajektoriendatei
=============================================
Liest Positionen aus einer HDF5-Datei und erzeugt einen G-Code.

HDF5-Struktur:
  Gruppe  : trajectory
  Dataset : position
  Format  : 2D-Array [N x 3]  → N Punkte, Spalten: x, y, z  (in Metern)

Ablauf:
  Fährt aus aktueller Position zur ersten Position aus der Datei und fährt dann alle weiteren Positionen der Reihe nach ab. An letzter Position wartet er für 3 Sekunden.

Abhängigkeiten:
  Pkg.add("HDF5")
"""

using HDF5

include("visual.jl")

function generate_gcode(
    positionen_m::Matrix{Float64};
    ausgabe_datei::String  = "output.gcode",
    frame_time::Float64 = 1,        # Framezeit in s
    offset::Tuple{Float64, Float64, Float64} = (0.0, 0.0, -110.0),  # Optionaler Offset in mm (x, y, z)
    eingabe_name::String = ""
)
    # Sicherstellen dass das Array die Form [N x 3] hat
    if size(positionen_m, 1) == 3 && size(positionen_m, 2) != 3
        positionen_m = positionen_m'     # transponieren falls [3 x N]
    end

    n_punkte = size(positionen_m, 1)
    println("  Punkte gefunden : $n_punkte")
    println("  Framezeit       : $frame_time s")

    # Meter → Millimeter
    positionen_mm = positionen_m .* 1000.0

    lines = String[]

    # --- Header ---
    push!(lines, "; ============================================")
    push!(lines, "; G-Code aus HDF5-Trajektoriendatei – Julia")
    push!(lines, "; Eingabe  : $eingabe_name")
    push!(lines, "; Gruppe   : trajectory/position")
    push!(lines, "; Punkte   : $n_punkte")
    push!(lines, "; Frame Time : $(frame_time) s")
    push!(lines, "; ============================================")
    push!(lines, "")

    # --- Initialisierung ---
    push!(lines, "G21       ; Einheiten: Millimeter")
    push!(lines, "G90       ; Absolute Koordinaten")
    push!(lines, "")

    # --- Alle Positionen abfahren (direkt von aktueller Position) ---
    push!(lines, "; Trajektorie abfahren (direkt von aktueller Position)")
    for i in 1:n_punkte
        if i != 1
            lastx = round(positionen_mm[i-1, 1] - offset[1], digits=3) #x and z axis must be inverted because of the robot coordinate system
            lasty = -round(positionen_mm[i-1, 2] - offset[2], digits=3)
            lastz = -round(positionen_mm[i-1, 3] - offset[3], digits=3)
        else
            vorschub = 20.0 # mm/s 
        end

        x = round(positionen_mm[i, 1] - offset[1], digits=3)
        y = -round(positionen_mm[i, 2] - offset[2], digits=3)
        z = -round(positionen_mm[i, 3] - offset[3], digits=3)

        # Vorschub aus Distanz zum vorherigen Punkt berechnen und durch Framezeit als Parameter teilen
        if i != 1
            vorschub = (sqrt((x - lastx)^2 + (y - lasty)^2 + (z - lastz)^2) / frame_time)  # in mm/s
        end

        push!(lines, "G1 X$(x) Y$(y) Z$(z) F$(vorschub)")
    end
    push!(lines, "")

    # --- 3 Sekunden warten an der letzten Position ---
    push!(lines, "; 6 Sekunden warten an der letzten Position")
    push!(lines, "G4 P0.1") #Angabe in Minuten, 0.1 min = 6 s
    push!(lines, "")

    # --- Ende ---
    push!(lines, "; === Programm Ende ===")
    push!(lines, "M2")
    push!(lines, "")

    # --- Datei schreiben ---
    open(ausgabe_datei, "w") do f
        for line in lines
            println(f, line)
        end
    end

    println("✓ G-Code gespeichert: $ausgabe_datei")
end

function generate_gcode(;
    eingabe_datei::String  = "input.h5",
    ausgabe_datei::String  = "output.gcode",
    frame_time::Float64 = 1,        # Framezeit in s
    offset::Tuple{Float64, Float64, Float64} = (0.0, 0.0, -110.0)  # Optionaler Offset in mm (x, y, z)
)

    # --- HDF5 einlesen ---
    println("Lese HDF5-Datei: $eingabe_datei")
    positionen_m = h5open(eingabe_datei, "r") do f
        read(f, "trajectory/position")   # Shape: [3 x N] oder [N x 3]
    end

    generate_gcode(positionen_m; ausgabe_datei, frame_time, offset, eingabe_name=eingabe_datei)
end

end # module RobotGCode
