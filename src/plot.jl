import PlotUtils
using RecipesBase
using LaTeXStrings

"""
    plot_pf_active_cx(pfa::pf_active)

Plots pf active cross-section
NOTE: Current plots are for the total current flowing in the coil (ie. it is multiplied by turns_with_sign)
"""
@recipe function plot_pf_active_cx(pfa::pf_active, what::Symbol=:cx; time=nothing, cname=:roma)

    if time === nothing
        time = global_time(pfa)
    end

    if what in [:cx, :coils_flux]
        label --> ""
        aspect --> :equal
        colorbar_title --> "PF currents [A]"

        currents = [get_time_array(c.current, :data, time) * c.element[1].turns_with_sign for c in pfa.coil]
        CURRENT = maximum(abs.(currents))

        # dummy markers to get the colorbar right
        if any(currents .!= 0.0)
            @series begin
                seriestype --> :scatter
                color --> cname
                clim --> (-CURRENT, CURRENT)
                marker_z --> [-CURRENT, CURRENT]
                [(NaN, NaN), (NaN, NaN)]
            end
        end

        # plot individual coils
        for c in pfa.coil
            current_color_index = (get_time_array(c.current, :data, time) * c.element[1].turns_with_sign + CURRENT) / (2 * CURRENT)
            @series begin
                if all(currents .== 0.0)
                    color --> :black
                else
                    color --> PlotUtils.cgrad(cname)[current_color_index]
                end
                c
            end
        end

    elseif what == :currents
        label --> "$(get_time_array(pfa.coil[1].current, :time, time)) s"
        currents = [get_time_array(c.current, :data, time) * c.element[1].turns_with_sign for c in pfa.coil]
        @series begin
            linestyle --> :dash
            marker --> :circle
            ["$k" for k = 1:length(currents)], currents
        end

        Imax = []
        for c in pfa.coil
            if !ismissing(c.b_field_max_timed, :data)
                b_max = get_time_array(c.b_field_max_timed, :data, time)
                # issue: IMAS does not have a way to store the current pf coil temperature
                #temperature = c.temperature[1]
                #Icrit = Interpolations.CubicSplineInterpolation((to_range(c.b_field_max), to_range(c.temperature)), c.current_limit_max * c.element[1].turns_with_sign)(b_max, temperature)
                Icrit = interp1d(c.b_field_max, c.current_limit_max[:, 1] * c.element[1].turns_with_sign)(b_max)
                push!(Imax, Icrit)
            else
                push!(Imax, NaN)
            end
        end

        if !all(isnan.(Imax))
            @series begin
                marker --> :cross
                label := "Max current"
                ["$k" for k = 1:length(currents)], Imax
            end
            @series begin
                marker --> :cross
                primary := false
                ["$k" for k = 1:length(currents)], -Imax
            end
        end

    else
        error("IMAS.pf_active `what` to plot can only be :cx or :currents")
    end

end

"""
    plot_coil_cx(coil::pf_active__coil; color = :gray)

Plots cross-section of individual coils
"""
@recipe function plot_coil_cx(coil::pf_active__coil; color=:black)
    if (coil.element[1].geometry.rectangle.width == 0.0) || (coil.element[1].geometry.rectangle.height == 0.0)
        @series begin
            color --> color
            linewidth --> 0.0
            seriestype --> :scatter
            markershape --> :star
            colorbar --> :right
            [(coil.element[1].geometry.rectangle.r, coil.element[1].geometry.rectangle.z)]
        end
    else
        r = coil.element[1].geometry.rectangle.r
        z = coil.element[1].geometry.rectangle.z
        Δr = coil.element[1].geometry.rectangle.width / 2.0
        Δz = coil.element[1].geometry.rectangle.height / 2.0
        @series begin
            seriestype --> :shape
            linewidth --> 0.5
            colorbar --> :right
            color --> color
            label --> ""
            [-Δr, Δr, Δr, -Δr, -Δr] .+ r, [-Δz, -Δz, Δz, Δz, -Δz] .+ z
        end
    end
end

"""
    plot_eqcx(eqt::IMAS.equilibrium__time_slice; psi_levels=nothing, psi_levels_out=nothing, lcfs=false)

Plots equilibrium cross-section
"""
@recipe function plot_eqcx(eq::IMAS.equilibrium; psi_levels=nothing, psi_levels_out=nothing, lcfs=false, x_point=false)
    @series begin
        psi_levels --> psi_levels
        psi_levels_out --> psi_levels_out
        lcfs --> lcfs
        x_point --> x_point
        return eq.time_slice[]
    end
end

@recipe function plot_eqtcx(eqt::IMAS.equilibrium__time_slice; psi_levels_in=nothing, psi_levels_out=nothing, lcfs=false, x_point=false)
    label --> ""
    aspect_ratio --> :equal
    @series begin
        [], []
    end
    primary --> false

    if (length(eqt.profiles_2d) == 0) || ismissing(eqt.profiles_2d[1], :psi)
        # if there is no psi map then plot the boundary
        @series begin
            eqt.boundary.outline.r, eqt.boundary.outline.z
        end

    else
        # plot cx
        # handle psi levels
        psi__boundary_level = eqt.profiles_1d.psi[end]
        tmp = find_psi_boundary(eqt, raise_error_on_not_open=false) # do not trust eqt.profiles_1d.psi[end], and find boundary level that is closest to lcfs
        if tmp !== nothing
            psi__boundary_level = tmp
        end
        if lcfs
            psi_levels_in = [psi__boundary_level, psi__boundary_level]
            psi_levels_out = []
        else
            npsi = 11
            if psi_levels_in === nothing
                psi_levels_in = range(eqt.profiles_1d.psi[1], psi__boundary_level, length=npsi)
            elseif isa(psi_levels_in, Int)
                if psi_levels_in > 1
                    npsi = psi_levels_in
                    psi_levels_in = range(eqt.profiles_1d.psi[1], psi__boundary_level, length=psi_levels_in)
                else
                    psi_levels_in = []
                end
            end
            delta_psi = (psi__boundary_level - eqt.profiles_1d.psi[1])
            if psi_levels_out === nothing
                psi_levels_out = delta_psi .* range(0, 1, length=npsi) .+ psi__boundary_level
            elseif isa(psi_levels_out, Int)
                if psi_levels_out > 1
                    psi_levels_out = delta_psi / npsi .* collect(0:psi_levels_out) .+ psi__boundary_level
                else
                    psi_levels_out = []
                end
            end
        end
        psi_levels = unique(vcat(psi_levels_in, psi_levels_out))

        xlims --> eqt.profiles_2d[1].grid.dim1[1], eqt.profiles_2d[1].grid.dim1[end]
        ylims --> eqt.profiles_2d[1].grid.dim2[1], eqt.profiles_2d[1].grid.dim2[end]

        # @series begin
        #     seriestype --> :contour
        #     levels --> psi_levels
        #     eqt.profiles_2d[1].grid.dim1, eqt.profiles_2d[1].grid.dim2, transpose(eqt.profiles_2d[1].psi)
        # end
        for psi_level in psi_levels
            for (pr, pz) in IMAS.flux_surface(eqt, psi_level, nothing)
                @series begin
                    seriestype --> :path
                    if psi_level == psi__boundary_level
                        linewidth --> 2.0
                    elseif psi_level in psi_levels_in
                        linewidth --> 1.0
                    else
                        linewidth --> 0.5
                    end
                    pr, pz
                end
            end
        end

        @series begin
            seriestype --> :scatter
            markershape --> :cross
            [(eqt.global_quantities.magnetic_axis.r, eqt.global_quantities.magnetic_axis.z)]
        end

        if x_point
            for xp in eqt.boundary.x_point
                @series begin
                    primary --> false
                    xp
                end
            end
        end
    end

end

@recipe function plot_x_point(x_point::IMAS.equilibrium__time_slice___boundary__x_point)
    @series begin
        seriestype := :scatter
        marker --> :circle
        markerstrokewidth --> 0
        label --> ""
        [(x_point.r, x_point.z)]
    end
end

function join_outlines(r1, z1, r2, z2)
    i1, i2 = minimum_distance_two_shapes(r1, z1, r2, z2; return_index=true)
    p(x1, x2) = vcat(x1[i1:end], x2[i2:end], x2[1:i2], x1[1:i1])
    return p(r1, r2), p(z1, z2)
end

@recipe function plot_pf_active_rail(rail::IMAS.build__pf_active__rail)
    if !ismissing(rail.outline, :r)
        @series begin
            color --> :gray
            linestyle --> :dash
            rail.outline.r, rail.outline.z
        end
    end
end

@recipe function plot_pf_active_rail(rails::IDSvector{IMAS.build__pf_active__rail})
    for (krail, rail) in enumerate(rails)
        if !ismissing(rail.outline, :r)
            @series begin
                label --> "Coil opt. rail"
                primary --> krail == 1 ? true : false
                rail
            end
        end
    end
end

"""
    plot_build_cx(bd::IMAS.build; cx=true, wireframe=false, only=nothing, exclude_layers=Symbol[])

Plot build cross-section
"""
@recipe function plot_build_cx(bd::IMAS.build; cx=true, wireframe=false, only=nothing, exclude_layers=Symbol[])
    legend_position --> :outerbottomright
    aspect_ratio --> :equal
    grid --> :none

    # cx
    if cx
        rmax = maximum(bd.layer[end].outline.r)

        # everything after first vacuum in _out_
        if ((only === nothing) || (:cryostat in only)) && (!(:cryostat in exclude_layers))
            for k in IMAS.get_build(bd, fs=_out_, return_only_one=false, return_index=true)[2:end]
                if !wireframe
                    @series begin
                        seriestype --> :shape
                        linewidth --> 0.0
                        color --> :lightgray
                        label --> (!wireframe ? "Cryostat" : "")
                        xlim --> [0, rmax]
                        join_outlines(
                            bd.layer[k].outline.r,
                            bd.layer[k].outline.z,
                            bd.layer[k-1].outline.r,
                            bd.layer[k-1].outline.z,
                        )
                    end
                end
                @series begin
                    seriestype --> :path
                    linewidth --> 1
                    color --> :black
                    label --> ""
                    xlim --> [0, rmax]
                    bd.layer[k].outline.r[1:end-1], bd.layer[k].outline.z[1:end-1]
                end
            end
        end

        # first vacuum in _out_
        if !wireframe
            k = IMAS.get_build(bd, fs=_out_, return_only_one=false, return_index=true)[1]
            @series begin
                seriestype --> :shape
                linewidth --> 0.0
                color --> :white
                label --> ""
                xlim --> [0, rmax]
                join_outlines(
                    bd.layer[k].outline.r,
                    bd.layer[k].outline.z,
                    IMAS.get_build(bd, type=_plasma_).outline.r,
                    IMAS.get_build(bd, type=_plasma_).outline.z,
                )
            end
            @series begin
                seriestype --> :path
                linewidth --> 1
                color --> :black
                label --> ""
                xlim --> [0, rmax]
                bd.layer[k].outline.r[1:end-1], bd.layer[k].outline.z[1:end-1]
            end
        end

        # axis of symmetry
        @series begin
            seriestype --> :path
            linewidth --> 1
            label --> ""
            linestyle --> :dash
            color --> :black
            [0.0, 0.0], [minimum(bd.layer[end].outline.z), maximum(bd.layer[end].outline.z)]
        end

        # all layers inside of the TF
        if ((only === nothing) || (:oh in only)) && (!(:oh in exclude_layers))
            for k in IMAS.get_build(bd, fs=_in_, return_only_one=false, return_index=true)
                layer = bd.layer[k]
                if layer.material != "Vacuum"
                    if !wireframe
                        @series begin
                            seriestype --> :shape
                            linewidth --> 0.0
                            color --> :gray
                            label --> (!wireframe ? layer.name : "")
                            xlim --> [0, rmax]
                            layer.outline.r, layer.outline.z
                        end
                    end
                    @series begin
                        seriestype --> :path
                        linewidth --> 0.5
                        color --> :black
                        label --> ""
                        xlim --> [0, rmax]
                        layer.outline.r, layer.outline.z
                    end
                end
            end
        end

        # all layers between the OH and the plasma
        for k in IMAS.get_build(bd, fs=_hfs_, return_only_one=false, return_index=true)
            l = bd.layer[k]
            l1 = bd.layer[k+1]
            poly = join_outlines(l.outline.r, l.outline.z, l1.outline.r, l1.outline.z)

            # setup labels and colors
            name = l.name
            color = :gray
            if l.type == Int(_gap_)
                name = ""
                color = :white
            elseif l.type == Int(_tf_)
                color = :green
            elseif l.type == Int(_shield_)
                color = :red
            elseif l.type == Int(_blanket_)
                color = :orange
            elseif l.type == Int(_wall_)
                color = :yellow
            elseif l.type == Int(_vessel_)
                color = :lightblue
            elseif l.type == Int(_cryostat_)
                color = :lightgray
            end
            for nm in ["inner", "outer", "vacuum", "hfs", "lfs", "gap"]
                name = replace(name, Regex("$(nm) ", "i") => "")
            end

            if ((only === nothing) || (Symbol(name) in only)) && (!(Symbol(name) in exclude_layers))
                if !wireframe
                    @series begin
                        seriestype --> :shape
                        linewidth --> 0.0
                        color --> color
                        label --> uppercasefirst(name)
                        xlim --> [0, rmax]
                        poly[1], poly[2]
                    end
                end
                @series begin
                    seriestype --> :path
                    linewidth --> 0.5
                    color --> :black
                    label --> ""
                    xlim --> [0, rmax]
                    l.outline.r, l.outline.z
                end
            end
        end

        # plasma
        if ((only === nothing) || (:plasma in only)) && (!(:plasma in exclude_layers))
            @series begin
                seriestype --> :path
                linewidth --> 1.0
                color --> :black
                label --> ""
                xlim --> [0, rmax]
                IMAS.get_build(bd, type=_plasma_).outline.r, IMAS.get_build(bd, type=_plasma_).outline.z
            end
        end

        if any([structure.type == Int(_divertor_) for structure in bd.structure])
            if ((only === nothing) || (:divertor in only)) && (!(:divertor in exclude_layers))
                for (k, index) in enumerate(findall(x -> x.type == Int(_divertor_), bd.structure))
                    if !wireframe
                        @series begin
                            seriestype --> :shape
                            linewidth --> 0.0
                            color --> :mediumpurple1
                            label --> (!wireframe && k == 1 ? "Divertor" : "")
                            xlim --> [0, rmax]
                            bd.structure[index].outline.r, bd.structure[index].outline.z
                        end
                    end
                    @series begin
                        seriestype --> :path
                        linewidth --> 0.5
                        color --> :black
                        label --> ""
                        xlim --> [0, rmax]
                        bd.structure[index].outline.r, bd.structure[index].outline.z
                    end
                end
            end
        end

    else  # not-cx

        @series begin
            seriestype --> :vline
            linewidth --> 2
            label --> ""
            linestyle --> :dash
            color --> :black
            [0]
        end

        at = 0
        for l in bd.layer
            @series begin
                if l.type == Int(_plasma_)
                    color --> :pink
                elseif l.type == Int(_gap_)
                    color --> :white
                elseif l.type == Int(_oh_)
                    color --> :gray
                elseif l.type == Int(_tf_)
                    color --> :green
                elseif l.type == Int(_shield_)
                    color --> :red
                elseif l.type == Int(_blanket_)
                    color --> :orange
                elseif l.type == Int(_wall_)
                    color --> :yellow
                elseif l.type == Int(_vessel_)
                    color --> :lightblue
                elseif l.type == Int(_cryostat_)
                    color --> :lightgray
                end
                seriestype --> :vspan
                if contains(l.name, "gap ")
                    label --> ""
                else
                    label --> l.name
                end
                alpha --> 0.2
                xlim --> [0, at]
                [at, at + l.thickness]
            end
            at += l.thickness
            @series begin
                seriestype --> :vline
                linewidth --> 0.5
                label --> ""
                color --> :black
                xlim --> [0, at]
                [at]
            end
        end
    end
end

@recipe function plot_core_sources(cs::IMAS.core_sources; integrated=false)
    for source in cs.source
        @series begin
            integrated := integrated
            source
        end
    end
    dd = top_dd(cs)
    if dd !== missing
        @series begin
            integrated := integrated
            name := "total"
            linewidth := 2
            color := :black
            total_sources(dd)
        end
    end
end

@recipe function plot_source(source::IMAS.core_sources__source; integrated=false)
    @series begin
        name := source.identifier.name
        integrated := integrated
        source.profiles_1d[]
    end
end

@recipe function plot_source1d(cs1d::IMAS.core_sources__source___profiles_1d; name="", integrated=false)
    layout := (1, 4)
    size := (1100, 290)

    @series begin
        subplot := 1
        color := objectid(cs1d) % Int
        title := "Electron Power"
        if !ismissing(cs1d.electrons, :energy)
            tot = integrate(cs1d.grid.volume, cs1d.electrons.energy)
            label --> "$name " * @sprintf("[%.3g MW]", tot / 1E6)
        end
        if !integrated && !ismissing(cs1d.electrons, :energy)
            cs1d.electrons, :energy
        elseif integrated && !ismissing(cs1d.electrons, :power_inside)
            cs1d.electrons, :power_inside
        else
            label --> ""
            [NaN], [NaN]
        end
    end

    @series begin
        subplot := 2
        color := objectid(cs1d) % Int
        title := "Ion Power"
        if !ismissing(cs1d, :total_ion_energy)
            tot = integrate(cs1d.grid.volume, cs1d.total_ion_energy)
            label --> "$name " * @sprintf("[%.3g MW]", tot / 1E6)
        end
        if !integrated && !ismissing(cs1d, :total_ion_energy)
            cs1d, :total_ion_energy
        elseif integrated && !ismissing(cs1d, :total_ion_power_inside)
            cs1d, :total_ion_power_inside
        else
            label --> ""
            [NaN], [NaN]
        end
    end

    @series begin
        subplot := 3
        color := objectid(cs1d) % Int
        title := "Electron Particle"
        if !ismissing(cs1d.electrons, :particles)
            tot = integrate(cs1d.grid.volume, cs1d.electrons.particles)
            label --> "$name " * @sprintf("[%.3g s⁻¹]", tot)
        end
        if !integrated && !ismissing(cs1d.electrons, :particles)
            cs1d.electrons, :particles
        elseif integrated && !ismissing(cs1d.electrons, :particles_inside)
            cs1d.electrons, :particles_inside
        else
            label --> ""
            [NaN], [NaN]
        end
    end

    @series begin
        subplot := 4
        color := objectid(cs1d) % Int
        title := "Parallel Current"
        if !ismissing(cs1d, :j_parallel)
            tot = integrate(cs1d.grid.area, cs1d.j_parallel)
            label --> "$name " * @sprintf("[%.3g MA]", tot / 1E6)
        end
        if !integrated && !ismissing(cs1d, :j_parallel)
            cs1d, :j_parallel
        elseif integrated && !ismissing(cs1d, :current_parallel_inside)
            cs1d, :current_parallel_inside
        else
            label --> ""
            [NaN], [NaN]
        end
    end
end

@recipe function plot_core_profiles(cp::IMAS.core_profiles)
    @series begin
        return cp.profiles_1d[]
    end
end

@recipe function plot_core_profiles(cpt::IMAS.core_profiles__profiles_1d)
    layout := (1, 3)
    size := (1100, 290)

    # temperatures
    @series begin
        subplot := 1
        label --> "e"
        ylim --> (0, Inf)
        cpt.electrons, :temperature
    end
    for ion in cpt.ion
        @series begin
            subplot := 1
            label --> ion.label
            linestyle --> :dash
            ylim --> (0, Inf)
            ion, :temperature
        end
    end

    # densities
    @series begin
        subplot := 2
        label --> "e"
        ylim --> (0.0, Inf)
        cpt.electrons, :density
    end
    for ion in cpt.ion
        @series begin
            Z = ion.element[1].z_n
            subplot := 2
            if Z == 1.0
                label --> ion.label
            else
                label --> "$(ion.label) × " * @sprintf("%.3g", Z)
            end
            linestyle --> :dash
            ylim --> (0.0, Inf)
            ion, :density, Z
        end
    end

    # rotation
    @series begin
        subplot := 3
        label --> ""
        cpt, :rotation_frequency_tor_sonic
    end

end

@recipe function plot_solid_mechanics(stress::Union{IMAS.solid_mechanics__center_stack__stress__hoop,IMAS.solid_mechanics__center_stack__stress__radial,IMAS.solid_mechanics__center_stack__stress__vonmises})
    smcs = parent(parent(stress))
    r_oh = smcs.grid.r_oh
    r_tf = smcs.grid.r_tf
    r_pl = missing
    if !ismissing(smcs.grid, :r_pl)
        r_pl = smcs.grid.r_pl
    end

    @series begin
        r_oh, stress.oh ./ 1E6
    end
    @series begin
        primary := false
        r_tf, stress.tf ./ 1E6
    end
    if r_pl !== missing
        @series begin
            primary := false
            r_pl, stress.pl ./ 1E6
        end
    end
end

@recipe function plot_solid_mechanics(stress::Union{IMAS.solid_mechanics__center_stack__stress}; linewidth=1)

    legend_position --> :outerbottomright
    ylabel --> "Stresses [MPa]"
    xlabel --> "Radius [m]"

    @series begin
        label := "Von Mises"
        linewidth := linewidth + 2
        stress.vonmises
    end
    @series begin
        label := "Hoop"
        linewidth := linewidth + 1
        stress.hoop
    end
    @series begin
        label := "Radial"
        linewidth := linewidth + 2
        stress.radial
    end

    smcs = parent(stress)
    for radius in [smcs.grid.r_oh[1], smcs.grid.r_oh[end], smcs.grid.r_tf[1], smcs.grid.r_tf[end]]
        @series begin
            seriestype --> :vline
            linewidth --> 2
            label --> ""
            linestyle --> :dash
            color --> :black
            [radius]
        end
    end
end
@recipe function plot_balance_of_plant(bop::IMAS.balance_of_plant; linewidth=2)

    size --> (800, 600)
    legend_position --> :outertopright
    ylabel --> "Electricity [Watts Electric]"
    xlabel --> "Time [s]"

    @series begin
        label := "Net electric"
        linewidth := linewidth + 2
        color := "Black"
        bop, :power_electric_net
    end

    @series begin
        label := "Electricity generated"
        linewidth := linewidth + 1
        linestyle --> :dash
        color := "Black"
        bop.thermal_cycle, :power_electric_generated
    end

    for sys in bop.power_electric_plant_operation.system
        @series begin
            label := string(sys.name)
            linewidth := linewidth
            sys, :power
        end
    end
end

@recipe function plot_neutron_wall_loading_cx(nwl::IMAS.neutronics__time_slice___wall_loading, component::Symbol=:norm; cx=true)
    neutronics = top_ids(nwl)
    if component == :norm
        nflux = sqrt.(nwl.flux_r .^ 2.0 .+ nwl.flux_z .^ 2.0)
    elseif component == :r
        nflux = nwl.flux_r
    elseif component == :z
        nflux = nwl.flux_z
    end
    nflux = nflux ./ 1E6

    if cx
        seriestype --> :path
        line_z --> vcat(nflux, nflux[1])
        aspect_ratio --> :equal
        linewidth --> 8
        label --> ""
        if component == :norm
            clim --> (0.0, maximum(nflux))
        else
            linecolor --> :seismic
        end
        colorbar_title --> "\nWall neutron flux [MW/m²]"
        vcat(neutronics.first_wall.r, neutronics.first_wall.r[1]), vcat(neutronics.first_wall.z, neutronics.first_wall.z[1])

    else
        wall_r = neutronics.first_wall.r
        index = vcat(argmax(wall_r)+1:length(wall_r), 1:argmax(wall_r))
        wall_r = wall_r[index]
        wall_z = neutronics.first_wall.z
        wall_z = wall_z[index]
        d = sqrt.(IMAS.diff(vcat(wall_r, wall_r[1])) .^ 2.0 .+ IMAS.diff(vcat(wall_z, wall_z[1])) .^ 2.0)
        l = cumsum(d)
        legend_position --> :top

        avg = sum(nflux[index] .* d) / sum(d)
        xlabel --> "Clockwise distance along wall [m]"
        ylabel --> "Wall neutron flux [MW/m²]"
        @series begin
            label --> ""
            l, nflux[index]
        end
        @series begin
            seriestype := :hline
            style --> :dash
            label --> @sprintf("Max: %3.3f [MW/m²]", maximum(nflux))
            [maximum(nflux)]
        end
        @series begin
            seriestype := :hline
            style --> :dash
            label --> @sprintf("Avg: %3.3f [MW/m²]", avg)
            [avg]
        end
        @series begin
            seriestype := :hline
            style --> :dash
            label --> @sprintf("Min: %3.3f [MW/m²]", minimum(nflux))
            [minimum(nflux)]
        end
    end
end

#= ================ =#
#  generic plotting  #
#= ================ =#
@recipe function plot_field(ids::IMAS.IDS, field::Symbol, norm::Real=1.0)
    coords = coordinates(ids, field)
    @series begin
        xlabel --> nice_field(i2p(coords[:names][1])[end]) * nice_units(units(coords[:names][1]))
        ylabel --> nice_units(units(ids, field))
        title --> nice_field(field)

        if endswith(coords[:names][1], "rho_tor_norm")
            xlim --> (0.0, 1.0)
        end

        xvalue = coords[:values][1]
        yvalue = getproperty(ids, field) * norm

        # plot 1D Measurements with ribbon
        if (eltype(yvalue) <: Measurement) && !((eltype(xvalue) <: Measurement))
            ribbon := Measurements.uncertainty.(yvalue)
            yvalue = Measurements.value.(yvalue)
        end

        xvalue, yvalue
    end
end

#= ================== =#
#  handling of labels  #
#= ================== =#
nice_field_symbols = Dict()
nice_field_symbols["rho_tor_norm"] = L"\rho"
nice_field_symbols["psi"] = L"\psi"
nice_field_symbols["rotation_frequency_tor_sonic"] = "Rotation"

function nice_field(field::String)
    if field in keys(nice_field_symbols)
        field = nice_field_symbols[field]
    else
        field = replace(field, r"_tor" => " toroidal")
        field = replace(field, r"_pol" => " poloidal")
        field = uppercasefirst(replace(field, "_" => " "))
    end
    return field
end

function nice_field(field::Symbol)
    nice_field(String(field))
end

function nice_units(units::String)
    if units == "-"
        units = ""
    end
    if length(units) > 0
        units = replace(units, r"\^([-+]?[0-9]+)" => s"^{\1}")
        units = replace(units, "." => s"\\,")
        units = L"[%$units]"
        units = " " * units
    end
    return units
end
