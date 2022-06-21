function total_pressure_thermal(cp1d::IMAS.core_profiles__profiles_1d)
    pressure = cp1d.electrons.density .* cp1d.electrons.temperature
    for ion in cp1d.ion
        pressure += ion.density .* ion.temperature
    end
    return pressure * constants.e
end

function calc_beta_thermal_norm(dd::IMAS.dd)
    return calc_beta_thermal_norm(dd.equilibrium, dd.core_profiles.profiles_1d[])
end

function calc_beta_thermal_norm(eq::IMAS.equilibrium, cp1d::IMAS.core_profiles__profiles_1d)
    eqt = eq.time_slice[Float64(cp1d.time)]
    eq1d = eqt.profiles_1d
    pressure_thermal = cp1d.pressure_thermal
    rho = cp1d.grid.rho_tor_norm
    Bt = interp1d(eq.time, eq.vacuum_toroidal_field.b0, :constant).(eqt.time)
    Ip = eqt.global_quantities.ip
    volume_cp = interp1d(eq1d.rho_tor_norm, eq1d.volume).(rho)
    pressure_thermal_avg = integrate(volume_cp, pressure_thermal) / volume_cp[end]
    beta_tor_thermal = 2 * constants.μ_0 * pressure_thermal_avg / Bt^2
    beta_tor_thermal_norm = beta_tor_thermal * eqt.boundary.minor_radius * abs(Bt) / abs(Ip / 1e6) * 1.0e2
    return beta_tor_thermal_norm
end

"""
    ion_element(;ion_z::Union{Missing,Int}=missing, ion_symbol::Union{Missing,Symbol}=missing, ion_name::Union{Missing,String}=missing)

returns a `core_profiles__profiles_1d___ion` structure populated with the element information
"""
function ion_element(; ion_z::Union{Missing,Int}=missing, ion_symbol::Union{Missing,Symbol}=missing, ion_name::Union{Missing,String}=missing)
    ion = IMAS.core_profiles__profiles_1d___ion()
    element = resize!(ion.element, 1)[1]
    if !ismissing(ion_z)
        element_ion = elements[ion_z]
    elseif !ismissing(ion_symbol)
        # exceptions: isotopes & lumped (only exceptions allowed for symbols)
        if ion_symbol == :D
            element.z_n = 1
            element.a = 2
            ion.label = String(ion_symbol)
            return ion
        elseif ion_symbol == :T
            element.z_n = 1
            element.a = 3
            ion.label = String(ion_symbol)
            return ion
        elseif ion_symbol ∈ [:DT, :TD]
            element.z_n = 1
            element.a = 2.5
            ion.label = String(ion_symbol)
            return ion
        end
        element_ion = elements[ion_symbol]
    elseif !ismissing(ion_name)
        element_ion = elements[ion_name]
    else
        error("Specify either ion_z, ion_symbol or ion_name")
    end
    element.z_n = element_ion.number
    element.a = element_ion.atomic_mass.val # This sets the atomic mass to the average isotope mass with respect to the abundence of that isotope i.e Neon: 20.179
    ion.label = String(element_ion.symbol)
    return ion
end

function energy_thermal(dd::IMAS.dd)
    return energy_thermal(dd.core_profiles.profiles_1d[])
end

function energy_thermal(cp1d::IMAS.core_profiles__profiles_1d)
    return 3 / 2 * integrate(cp1d.grid.volume, cp1d.pressure_thermal)
end

function ne_vol_avg(dd::IMAS.dd)
    return ne_vol_avg(dd.core_profiles.profiles_1d[])
end

function ne_vol_avg(cp1d::IMAS.core_profiles__profiles_1d)
    return integrate(cp1d.grid.volume, cp1d.electrons.density) / cp1d.grid.volume[end]
end

function tau_e_thermal(dd::IMAS.dd)
    return tau_e_thermal(dd.core_profiles.profiles_1d[], dd.core_sources)
end

"""
    tau_e_thermal(cp1d::IMAS.core_profiles__profiles_1d, sources::IMAS.core_sources)

Evaluate thermal energy confinement time
"""
function tau_e_thermal(cp1d::IMAS.core_profiles__profiles_1d, sources::IMAS.core_sources)
    # power losses due to radiation shouldn't be subtracted from tau_e_thermal
    total_source = IMAS.total_sources(sources, cp1d)
    total_power_inside = total_source.electrons.power_inside[end] + total_source.total_ion_power_inside[end]
    return energy_thermal(cp1d) / (total_power_inside - radiation_losses(sources))
end

"""
    tau_e_h98(dd::IMAS.dd; time=dd.global_time)

H98y2 ITER elmy H-mode confinement time scaling
"""
function tau_e_h98(dd::IMAS.dd; time=dd.global_time)
    eqt = dd.equilibrium.time_slice[Float64(time)]
    cp1d = dd.core_profiles.profiles_1d[Float64(time)]

    total_source = IMAS.total_sources(dd.core_sources, cp1d)
    total_power_inside = total_source.electrons.power_inside[end] + total_source.total_ion_power_inside[end] - radiation_losses(dd.core_sources)
    isotope_factor =
        integrate(cp1d.grid.volume, sum([ion.density .* ion.element[1].a for ion in cp1d.ion if ion.element[1].z_n == 1])) / integrate(cp1d.grid.volume, sum([ion.density for ion in cp1d.ion if ion.element[1].z_n == 1]))

    tau98 = (
        0.0562 *
        abs(eqt.global_quantities.ip / 1e6)^0.93 *
        abs(get_time_array(dd.equilibrium.vacuum_toroidal_field, :b0, time))^0.15 *
        (total_power_inside / 1e6)^-0.69 *
        (ne_vol_avg(cp1d) / 1e19)^0.41 *
        isotope_factor^0.19 *
        dd.equilibrium.vacuum_toroidal_field.r0^1.97 *
        (dd.equilibrium.vacuum_toroidal_field.r0 / eqt.boundary.minor_radius)^-0.58 *
        eqt.boundary.elongation^0.78
    )
    return tau98
end

"""
    tau_e_ds03(dd::IMAS.dd; time=dd.global_time)

Petty's 2003 confinement time scaling
"""
function tau_e_ds03(dd::IMAS.dd; time=dd.global_time)
    eqt = dd.equilibrium.time_slice[Float64(time)]
    cp1d = dd.core_profiles.profiles_1d[Float64(time)]

    total_source = IMAS.total_sources(dd.core_sources, cp1d)
    total_power_inside = total_source.electrons.power_inside[end] + total_source.total_ion_power_inside[end] - radiation_losses(dd.core_sources)
    isotope_factor =
        integrate(cp1d.grid.volume, sum([ion.density .* ion.element[1].a for ion in cp1d.ion if ion.element[1].z_n == 1])) / integrate(cp1d.grid.volume, sum([ion.density for ion in cp1d.ion if ion.element[1].z_n == 1]))

    tauds03 = (
        0.028 *
        abs(eqt.global_quantities.ip / 1e6)^0.83 *
        abs(get_time_array(dd.equilibrium.vacuum_toroidal_field, :b0, time))^0.07 *
        (total_power_inside / 1e6)^-0.55 *
        (ne_vol_avg(cp1d) / 1e19)^0.49 *
        isotope_factor^0.14 *
        dd.equilibrium.vacuum_toroidal_field.r0^2.11 *
        (dd.equilibrium.vacuum_toroidal_field.r0 / eqt.boundary.minor_radius)^-0.30 *
        eqt.boundary.elongation^0.75
    )

    return tauds03
end

"""
    bunit(eqt::IMAS.equilibrium__time_slice)

Calculate bunit from equilibrium
"""
function bunit(eqt::IMAS.equilibrium__time_slice)
    eq1d = eqt.profiles_1d
    rmin = 0.5 * (eq1d.r_outboard - eq1d.r_inboard)
    phi = eq1d.phi
    return gradient(2pi * rmin, phi) ./ rmin
end

"""
    greenwald_density(eqt::IMAS.equilibrium__time_slice)

Simple greenwald line-averaged density limit
"""
function greenwald_density(eqt::IMAS.equilibrium__time_slice)
    return (eqt.global_quantities.ip / 1e6) / (pi * eqt.boundary.minor_radius^2) * 1e20
end

"""
    geometric_midplane_line_averaged_density(eqt::IMAS.equilibrium__time_slice, cp1d::IMAS.core_profiles__profiles_1d)

Calculates the line averaged density from a midplane horizantal line
"""
function geometric_midplane_line_averaged_density(eqt::IMAS.equilibrium__time_slice, cp1d::IMAS.core_profiles__profiles_1d)
    a_cp = IMAS.interp1d(eqt.profiles_1d.rho_tor_norm, (eqt.profiles_1d.r_outboard .- eqt.profiles_1d.r_inboard) / 2.0).(cp1d.grid.rho_tor_norm)
    return integrate(a_cp, cp1d.electrons.density) / a_cp[end]
end