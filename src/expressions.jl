using Trapz
expressions = Dict{String,Function}()

#= =========== =#
# Core Profiles #
#= =========== =#
expressions["core_profiles.profiles_1d[:].electrons.pressure"] =
    (rho_tor_norm; electrons, _...) -> electrons.temperature .* electrons.density * 1.60218e-19

expressions["core_profiles.profiles_1d[:].electrons.density"] =
    (rho_tor_norm; electrons, _...) -> electrons.pressure ./ (electrons.temperature * 1.60218e-19)

expressions["core_profiles.profiles_1d[:].electrons.temperature"] =
    (rho_tor_norm; electrons, _...) -> electrons.pressure ./ (electrons.density * 1.60218e-19)

#= ========= =#
# Equilibrium #
#= ========= =#
expressions["equilibrium.time_slice[:].global_quantities.energy_mhd"] =
    (;time_slice, _...) -> 3 / 2 * trapz(time_slice.profiles_1d.volume, time_slice.profiles_1d.pressure)


expressions["equilibrium.time_slice[:].boundary.geometric_axis"] =
    (;time_slice, _...) -> (time_slice.profiles_1d.r_outboard[end] + time_slice.profiles_1d.r_inboard[end]) * 0.5

    
expressions["equilibrium.time_slice[:].boundary.minor_radius"] =
    (;time_slice, _...) -> (time_slice.profiles_1d.r_outboard[end] - time_slice.profiles_1d.r_inboard[end]) * 0.5


expressions["equilibrium.time_slice[:].boundary.elongation"] =
    (;time_slice, _...) -> (time_slice.boundary.elongation_lower + time_slice.boundary.elongation_upper) * 0.5

expressions["equilibrium.time_slice[:].boundary.elongation_lower"] =
    (;time_slice, _...) -> time_slice.profiles_1d.elongation[end] # <======= IMAS 3.30.0 limitation

expressions["equilibrium.time_slice[:].boundary.elongation_upper"] =
    (;time_slice, _...) -> time_slice.profiles_1d.elongation[end] # <======= IMAS 3.30.0 limitation


expressions["equilibrium.time_slice[:].boundary.triangularity"] =
    (;time_slice, _...) -> (time_slice.boundary.triangularity_lower + time_slice.boundary.triangularity_upper) * 0.5

expressions["equilibrium.time_slice[:].boundary.triangularity_lower"] =
    (;time_slice, _...) -> time_slice.profiles_1d.triangularity_lower[end]

expressions["equilibrium.time_slice[:].boundary.triangularity_upper"] =
    (;time_slice, _...) -> time_slice.profiles_1d.triangularity_upper[end]


expressions["equilibrium.time_slice[:].boundary.squareness_lower_inner"] =
    (;time_slice, _...) -> time_slice.profiles_1d.squareness_lower_inner[end]

expressions["equilibrium.time_slice[:].boundary.squareness_upper_inner"] =
    (;time_slice, _...) -> time_slice.profiles_1d.squareness_upper_inner[end]

expressions["equilibrium.time_slice[:].boundary.squareness_lower_outer"] =
    (;time_slice, _...) -> time_slice.profiles_1d.squareness_lower_outer[end]

expressions["equilibrium.time_slice[:].boundary.squareness_upper_outer"] =
    (;time_slice, _...) -> time_slice.profiles_1d.squareness_upper_outer[end]
