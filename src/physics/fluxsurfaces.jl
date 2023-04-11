using LinearAlgebra

"""
    ψ_interpolant(eqt::IMAS.equilibrium__time_slice)

Returns r, z, and ψ interpolant
"""
function ψ_interpolant(eqt::IMAS.equilibrium__time_slice)
    r = range(eqt.profiles_2d[1].grid.dim1[1], eqt.profiles_2d[1].grid.dim1[end], length=length(eqt.profiles_2d[1].grid.dim1))
    z = range(eqt.profiles_2d[1].grid.dim2[1], eqt.profiles_2d[1].grid.dim2[end], length=length(eqt.profiles_2d[1].grid.dim2))
    return r, z, Interpolations.cubic_spline_interpolation((r, z), eqt.profiles_2d[1].psi)
end

"""
    Br_Bz_vector_interpolant(PSI_interpolant, cc::COCOS, r::Vector{T}, z::Vector{T}) where {T<:Real}

Returns Br and Bz tuple evaluated at r and z starting from ψ interpolant
"""
function Br_Bz_vector_interpolant(PSI_interpolant, cc::COCOS, r::Vector{T}, z::Vector{T}) where {T<:Real}
    grad = [Interpolations.gradient(PSI_interpolant, r[k], z[k]) for k in 1:length(r)]
    Br = [cc.sigma_RpZ * grad[k][2] / r[k] / (2 * pi)^cc.exp_Bp for k in 1:length(r)]
    Bz = [-cc.sigma_RpZ * grad[k][1] / r[k] / (2 * pi)^cc.exp_Bp for k in 1:length(r)]
    return Br, Bz
end

"""
    Bp_vector_interpolant(PSI_interpolant, cc::COCOS, r::Vector{T}, z::Vector{T}) where {T<:Real}

Returns Bp evaluated at r and z starting from ψ interpolant
"""
function Bp_vector_interpolant(PSI_interpolant, cc::COCOS, r::Vector{T}, z::Vector{T}) where {T<:Real}
    Br, Bz = Br_Bz_vector_interpolant(PSI_interpolant, cc, r, z)
    return sqrt.(Br .^ 2.0 .+ Bz .^ 2.0)
end

"""
    find_psi_boundary(eqt; precision=1e-6, raise_error_on_not_open=true)

Find psi value of the last closed flux surface
"""
function find_psi_boundary(eqt; precision=1e-6, raise_error_on_not_open=true)
    dim1 = eqt.profiles_2d[1].grid.dim1
    dim2 = eqt.profiles_2d[1].grid.dim2
    PSI = eqt.profiles_2d[1].psi
    psi = eqt.profiles_1d.psi
    R0 = eqt.global_quantities.magnetic_axis.r
    Z0 = eqt.global_quantities.magnetic_axis.z
    find_psi_boundary(dim1, dim2, PSI, psi, R0, Z0; precision, raise_error_on_not_open)
end

function find_psi_boundary(dim1, dim2, PSI, psi, R0, Z0; precision=1e-6, raise_error_on_not_open)
    psirange_init = [psi[1] * 0.9 + psi[end] * 0.1, psi[end] + 0.5 * (psi[end] - psi[1])]

    dd = sqrt((dim1[2] - dim1[1])^2 + (dim2[2] - dim2[1])^2)

    pr, pz = flux_surface(dim1, dim2, PSI, psi, R0, Z0, psirange_init[1], true)
    if length(pr) == 0
        error("Flux surface at ψ=$(psirange_init[1]) is not closed")
    end

    pr, pz = flux_surface(dim1, dim2, PSI, psi, R0, Z0, psirange_init[end], true)
    if length(pr) > 0
        if raise_error_on_not_open
            error("Flux surface at ψ=$(psirange_init[end]) is not open")
        else
            return nothing
        end
    end

    psirange = deepcopy(psirange_init)
    for k in 1:100
        psimid = (psirange[1] + psirange[end]) / 2.0
        pr, pz = flux_surface(dim1, dim2, PSI, psi, R0, Z0, psimid, true)
        # closed flux surface
        if length(pr) > 0
            psirange[1] = psimid
            if (abs(psirange[end] - psirange[1]) / abs(psirange[end] + psirange[1]) / 2.0) < precision
                if any(abs.([(minimum(pr) - minimum(dim1)), (maximum(pr) - maximum(dim1)), (minimum(pz) - minimum(dim2)), (maximum(pz) - maximum(dim2))]) .< 2 * dd)
                    return psi[end]
                else
                    return psimid
                end
            end
            # open flux surface
        else
            psirange[end] = psimid
        end
    end

    error("Could not find closed boundary between ψ=$(psirange_init[1]) and ψ=$(psirange_init[end])")
end

"""
    flux_surfaces(eq::equilibrium; upsample_factor::Int=1)

Update flux surface averaged and geometric quantities in the equilibrium IDS
The original psi grid can be upsampled by a `upsample_factor` to get higher resolution flux surfaces
"""
function flux_surfaces(eq::equilibrium; upsample_factor::Int=1)
    for time_index in 1:length(eq.time_slice)
        flux_surfaces(eq.time_slice[time_index]; upsample_factor)
    end
    return eq
end

"""
    flux_surfaces(eqt::equilibrium__time_slice; upsample_factor::Int=1)

Update flux surface averaged and geometric quantities for a given equilibrum IDS time slice
The original psi grid can be upsampled by a `upsample_factor` to get higher resolution flux surfaces
"""
function flux_surfaces(eqt::equilibrium__time_slice; upsample_factor::Int=1)
    r0, b0 = vacuum_r0_b0(eqt)
    return flux_surfaces(eqt, b0, r0; upsample_factor)
end

"""
    flux_surfaces(eqt::equilibrium__time_slice, b0::Real, r0::Real; upsample_factor::Int=1)

Update flux surface averaged and geometric quantities for a given equilibrum IDS time slice, b0 and r0
The original psi grid can be upsampled by a `upsample_factor` to get higher resolution flux surfaces
"""
function flux_surfaces(eqt::equilibrium__time_slice, b0::Real, r0::Real; upsample_factor::Int=1)
    cc = cocos(11)

    r, z, PSI_interpolant = ψ_interpolant(eqt)
    PSI = eqt.profiles_2d[1].psi

    # upsampling for high-resolution r,z flux surface coordinates
    if upsample_factor > 1
        r = range(eqt.profiles_2d[1].grid.dim1[1], eqt.profiles_2d[1].grid.dim1[end], length=length(eqt.profiles_2d[1].grid.dim1) * upsample_factor)
        z = range(eqt.profiles_2d[1].grid.dim2[1], eqt.profiles_2d[1].grid.dim2[end], length=length(eqt.profiles_2d[1].grid.dim2) * upsample_factor)
        PSI = PSI_interpolant(r, z)
    end

    psi_sign = sign(eqt.profiles_1d.psi[end] - eqt.profiles_1d.psi[1])

    # find magnetic axis
    res = Optim.optimize(
        x -> PSI_interpolant(x[1], x[2]) * psi_sign,
        [r[Int(round(length(r) / 2))], z[Int(round(length(z) / 2))]],
        Optim.Newton(),
        Optim.Options(g_tol=1E-8);
        autodiff=:forward
    )
    eqt.global_quantities.magnetic_axis.r = res.minimizer[1]
    eqt.global_quantities.magnetic_axis.z = res.minimizer[2]
    psi_axis = PSI_interpolant(eqt.global_quantities.magnetic_axis.r, eqt.global_quantities.magnetic_axis.z)
    eqt.profiles_1d.psi = (eqt.profiles_1d.psi .- eqt.profiles_1d.psi[1]) ./ (eqt.profiles_1d.psi[end] - eqt.profiles_1d.psi[1]) .* (eqt.profiles_1d.psi[end] - psi_axis) .+ psi_axis

    for item in [
        :b_field_average,
        :b_field_max,
        :b_field_min,
        :elongation,
        :triangularity_lower,
        :triangularity_upper,
        :squareness_lower_inner,
        :squareness_lower_outer,
        :squareness_upper_inner,
        :squareness_upper_outer,
        :r_inboard,
        :r_outboard,
        :q,
        :surface,
        :dvolume_dpsi,
        :j_tor,
        :area,
        :volume,
        :gm1,
        :gm2,
        :gm4,
        :gm5,
        :gm8,
        :gm9,
        :phi,
        :trapped_fraction,
    ]
        setproperty!(eqt.profiles_1d, item, zeros(eltype(eqt.profiles_1d.psi), size(eqt.profiles_1d.psi)))
    end

    PR = []
    PZ = []
    LL = []
    FLUXEXPANSION = []
    INT_FLUXEXPANSION_DL = zeros(length(eqt.profiles_1d.psi))
    BPL = zeros(length(eqt.profiles_1d.psi))
    for (k, psi_level0) in reverse(collect(enumerate(eqt.profiles_1d.psi)))

        if k == 1 # on axis flux surface is a synthetic one
            eqt.profiles_1d.elongation[1] = eqt.profiles_1d.elongation[2] - (eqt.profiles_1d.elongation[3] - eqt.profiles_1d.elongation[2])
            eqt.profiles_1d.triangularity_upper[1] = 0.0
            eqt.profiles_1d.triangularity_lower[1] = 0.0

            a = (eqt.profiles_1d.r_outboard[2] - eqt.profiles_1d.r_inboard[2]) / 100.0
            b = eqt.profiles_1d.elongation[1] * a

            t = range(0, 2 * pi, length=17)
            pr = cos.(t) .* a .+ eqt.global_quantities.magnetic_axis.r
            pz = sin.(t) .* b .+ eqt.global_quantities.magnetic_axis.z

            # Extrema on array indices
            (imaxr, iminr, imaxz, iminz, r_at_max_z, max_z, r_at_min_z, min_z, z_at_max_r, max_r, z_at_min_r, min_r) = fluxsurface_extrema(pr, pz)

        else  # other flux surfaces
            # trace flux surface
            pr, pz, psi_level =
                flux_surface(r, z, PSI, eqt.profiles_1d.psi, eqt.global_quantities.magnetic_axis.r, eqt.global_quantities.magnetic_axis.z, psi_level0, true)
            if isempty(pr)
                error("IMAS: Could not trace closed flux surface $k out of $(length(eqt.profiles_1d.psi)) at ψ = $(psi_level)")
            end

            # Extrema on array indices
            (imaxr, iminr, imaxz, iminz, r_at_max_z, max_z, r_at_min_z, min_z, z_at_max_r, max_r, z_at_min_r, min_r) = fluxsurface_extrema(pr, pz)

            # accurate geometric quantities by finding geometric extrema as optimization problem
            w = 1E-4 # push away from magnetic axis
            function fx(x::AbstractVector{<:Real}, psi_level::Float64, eqt::IMAS.equilibrium__time_slice, w::Float64)
                try
                    (PSI_interpolant(x[1], x[2]) - psi_level)^2 - (x[1] - eqt.global_quantities.magnetic_axis.r)^2 * w
                catch
                    return 100
                end
            end
            function fz(x::AbstractVector{<:Real}, psi_level::Float64, eqt::IMAS.equilibrium__time_slice, w::Float64)
                try
                    (PSI_interpolant(x[1], x[2]) - psi_level)^2 - (x[2] - eqt.global_quantities.magnetic_axis.z)^2 * w
                catch
                    return 100
                end
            end
            res = Optim.optimize(x -> fx(x, psi_level, eqt, w), [max_r, z_at_max_r], Optim.Newton(), Optim.Options(g_tol=1E-8); autodiff=:forward)
            (max_r, z_at_max_r) = (res.minimizer[1], res.minimizer[2])
            res = Optim.optimize(x -> fx(x, psi_level, eqt, w), [min_r, z_at_min_r], Optim.Newton(), Optim.Options(g_tol=1E-8); autodiff=:forward)
            (min_r, z_at_min_r) = (res.minimizer[1], res.minimizer[2])
            if psi_level0 != eqt.profiles_1d.psi[end]
                res = Optim.optimize(x -> fz(x, psi_level, eqt, w), [r_at_max_z, max_z], Optim.Newton(), Optim.Options(g_tol=1E-8); autodiff=:forward)
                (r_at_max_z, max_z) = (res.minimizer[1], res.minimizer[2])
                res = Optim.optimize(x -> fz(x, psi_level, eqt, w), [r_at_min_z, min_z], Optim.Newton(), Optim.Options(g_tol=1E-8); autodiff=:forward)
                (r_at_min_z, min_z) = (res.minimizer[1], res.minimizer[2])
            end
            # p = plot(pr, pz, label = "")
            # plot!([max_r], [z_at_max_r], marker = :cicle)
            # plot!([min_r], [z_at_min_r], marker = :cicle)
            # plot!([r_at_max_z], [max_z], marker = :cicle)
            # plot!([r_at_min_z], [min_z], marker = :cicle)
            # display(p)

            # plasma boundary information
            if k == length(eqt.profiles_1d.psi)
                eqt.boundary.outline.r = pr
                eqt.boundary.outline.z = pz
            end
        end

        # geometric
        Rm = 0.5 * (max_r + min_r)
        a = 0.5 * (max_r - min_r)
        b = 0.5 * (max_z - min_z)
        eqt.profiles_1d.r_outboard[k] = max_r
        eqt.profiles_1d.r_inboard[k] = min_r
        eqt.profiles_1d.elongation[k] = b / a
        eqt.profiles_1d.triangularity_upper[k] = (Rm - r_at_max_z) / a
        eqt.profiles_1d.triangularity_lower[k] = (Rm - r_at_min_z) / a

        # Luce Squareness
        zetaou, zetaol, zetail, zetaiu = luce_squareness(pr, pz, r_at_max_z, max_z, r_at_min_z, min_z, z_at_max_r, max_r, z_at_min_r, min_r)
        eqt.profiles_1d.squareness_upper_outer[k] = zetaou
        eqt.profiles_1d.squareness_lower_outer[k] = zetaol
        eqt.profiles_1d.squareness_upper_inner[k] = zetail
        eqt.profiles_1d.squareness_lower_inner[k] = zetaiu

        # poloidal magnetic field (with sign)
        Br, Bz = Br_Bz_vector_interpolant(PSI_interpolant, cc, pr, pz)
        Bp2 = Br .^ 2.0 .+ Bz .^ 2.0
        Bp_abs = sqrt.(Bp2)
        Bp = (
            Bp_abs .* cc.sigma_rhotp * cc.sigma_RpZ .*
            sign.((pz .- eqt.global_quantities.magnetic_axis.z) .* Br .- (pr .- eqt.global_quantities.magnetic_axis.r) .* Bz)
        )

        # flux expansion
        dl = vcat(0.0, sqrt.(diff(pr) .^ 2 + diff(pz) .^ 2))
        ll = cumsum(dl)
        fluxexpansion = 1.0 ./ Bp_abs
        int_fluxexpansion_dl = integrate(ll, fluxexpansion)
        Bpl = integrate(ll, Bp)

        # save flux surface coordinates for later use
        pushfirst!(PR, pr)
        pushfirst!(PZ, pz)
        pushfirst!(LL, ll)
        pushfirst!(FLUXEXPANSION, fluxexpansion)
        INT_FLUXEXPANSION_DL[k] = int_fluxexpansion_dl
        BPL[k] = Bpl

        # trapped fraction
        Bt = eqt.profiles_1d.f[k] ./ pr
        Btot = sqrt.(Bp2 .+ Bt .^ 2)
        Bmin = minimum(Btot)
        Bmax = maximum(Btot)
        Bratio = Btot ./ Bmax
        avg_Btot = flxAvg(Btot, ll, fluxexpansion, int_fluxexpansion_dl)
        avg_Btot2 = flxAvg(Btot .^ 2, ll, fluxexpansion, int_fluxexpansion_dl)
        hf = flxAvg((1.0 .- sqrt.(1.0 .- Bratio) .* (1.0 .+ Bratio ./ 2.0)) ./ Bratio .^ 2, ll, fluxexpansion, int_fluxexpansion_dl)
        h = avg_Btot / Bmax
        h2 = avg_Btot2 / Bmax^2
        ftu = 1.0 - h2 / (h^2) * (1.0 - sqrt(1.0 - h) * (1.0 + 0.5 * h))
        ftl = 1.0 - h2 * hf
        eqt.profiles_1d.trapped_fraction[k] = 0.75 * ftu + 0.25 * ftl

        # Bavg
        eqt.profiles_1d.b_field_average[k] = avg_Btot

        # Bmax
        eqt.profiles_1d.b_field_max[k] = Bmax

        # Bmin
        eqt.profiles_1d.b_field_min[k] = Bmin

        # gm1 = <1/R^2>
        eqt.profiles_1d.gm1[k] = flxAvg(1.0 ./ pr .^ 2, ll, fluxexpansion, int_fluxexpansion_dl)

        # gm4 = <1/B^2>
        eqt.profiles_1d.gm4[k] = flxAvg(1.0 ./ Btot .^ 2, ll, fluxexpansion, int_fluxexpansion_dl)

        # gm5 = <B^2>
        eqt.profiles_1d.gm5[k] = avg_Btot2

        # gm8 = <R>
        eqt.profiles_1d.gm8[k] = flxAvg(pr, ll, fluxexpansion, int_fluxexpansion_dl)

        # gm9 = <1/R>
        eqt.profiles_1d.gm9[k] = flxAvg(1.0 ./ pr, ll, fluxexpansion, int_fluxexpansion_dl)

        # j_tor = <j_tor/R> / <1/R>
        eqt.profiles_1d.j_tor[k] =
            (
                -cc.sigma_Bp .* (eqt.profiles_1d.dpressure_dpsi[k] + eqt.profiles_1d.f_df_dpsi[k] * eqt.profiles_1d.gm1[k] / (4 * pi * 1e-7)) *
                (2.0 * pi)^cc.exp_Bp
            ) / eqt.profiles_1d.gm9[k]

        # dvolume_dpsi
        eqt.profiles_1d.dvolume_dpsi[k] = (cc.sigma_rhotp * cc.sigma_Bp * sign(flxAvg(Bp, ll, fluxexpansion, int_fluxexpansion_dl)) * int_fluxexpansion_dl * (2.0 * pi)^(1.0 - cc.exp_Bp))

        # surface area
        eqt.profiles_1d.surface[k] = 2 * pi * sum(pr .* dl)

        # q
        eqt.profiles_1d.q[k] = (
            cc.sigma_rhotp .* cc.sigma_Bp .* eqt.profiles_1d.dvolume_dpsi[k] .* eqt.profiles_1d.f[k] .* eqt.profiles_1d.gm1[k] ./
            ((2.0 * pi)^(2.0 - cc.exp_Bp))
        )

        # quantities calculated on the last closed flux surface
        if k == length(eqt.profiles_1d.psi)
            # ip
            eqt.global_quantities.ip = cc.sigma_rhotp * Bpl / (4e-7 * pi)

            # perimeter
            eqt.global_quantities.length_pol = ll[end]
        end
    end

    # integral quantities
    for k in 2:length(eqt.profiles_1d.psi)
        # area
        eqt.profiles_1d.area[k] = integrate(eqt.profiles_1d.psi[1:k], eqt.profiles_1d.dvolume_dpsi[1:k] .* eqt.profiles_1d.gm9[1:k]) ./ 2pi

        # volume
        eqt.profiles_1d.volume[k] = integrate(eqt.profiles_1d.psi[1:k], eqt.profiles_1d.dvolume_dpsi[1:k])

        # phi
        eqt.profiles_1d.phi[k] = cc.sigma_Bp * cc.sigma_rhotp * integrate(eqt.profiles_1d.psi[1:k], eqt.profiles_1d.q[1:k]) * (2.0 * pi)^(1.0 - cc.exp_Bp)
    end

    R = (eqt.profiles_1d.r_outboard[end] + eqt.profiles_1d.r_inboard[end]) / 2.0
    a = (eqt.profiles_1d.r_outboard[end] - eqt.profiles_1d.r_inboard[end]) / 2.0

    # vacuum magnetic field at the geometric center
    Btvac = b0 * r0 / R

    # average poloidal magnetic field
    Bpave = eqt.global_quantities.ip * (4.0 * pi * 1e-7) / eqt.global_quantities.length_pol

    # li
    Bp2v = integrate(eqt.profiles_1d.psi, BPL * (2.0 * pi)^(1.0 - cc.exp_Bp))
    eqt.global_quantities.li_3 = 2 * Bp2v / r0 / (eqt.global_quantities.ip * (4.0 * pi * 1e-7))^2

    # beta_tor
    avg_press = volume_integrate(eqt, eqt.profiles_1d.pressure)
    eqt.global_quantities.beta_tor = abs(avg_press / (Btvac^2 / 2.0 / 4.0 / pi / 1e-7) / eqt.profiles_1d.volume[end])

    # beta_pol
    eqt.global_quantities.beta_pol = abs(avg_press / eqt.profiles_1d.volume[end] / (Bpave^2 / 2.0 / 4.0 / pi / 1e-7))

    # beta_normal
    ip = eqt.global_quantities.ip / 1e6
    eqt.global_quantities.beta_normal = eqt.global_quantities.beta_tor / abs(ip / a / Btvac) * 100

    # rho_tor_norm
    rho = sqrt.(abs.(eqt.profiles_1d.phi ./ (pi * b0)))
    rho_meters = rho[end]
    eqt.profiles_1d.rho_tor = rho
    eqt.profiles_1d.rho_tor_norm = rho ./ rho_meters

    # phi 2D
    eqt.profiles_2d[1].phi =
        Interpolations.cubic_spline_interpolation(
            to_range(eqt.profiles_1d.psi) * psi_sign,
            eqt.profiles_1d.phi,
            extrapolation_bc=Interpolations.Line(),
        ).(eqt.profiles_2d[1].psi * psi_sign)

    # rho 2D in meters
    RHO = sqrt.(abs.(eqt.profiles_2d[1].phi ./ (pi * b0)))

    # gm2: <∇ρ²/R²>
    if false
        RHO_interpolant = Interpolations.cubic_spline_interpolation((r, z), RHO)
        for k in 1:length(eqt.profiles_1d.psi)
            tmp = [Interpolations.gradient(RHO_interpolant, PR[k][j], PZ[k][j]) for j in 1:length(PR[k])]
            dPHI2 = [j[1] .^ 2.0 .+ j[2] .^ 2.0 for j in tmp]
            eqt.profiles_1d.gm2[k] = flxAvg(dPHI2 ./ PR[k] .^ 2.0, LL[k], FLUXEXPANSION[k], INT_FLUXEXPANSION_DL[k])
        end
    else
        dRHOdR, dRHOdZ = gradient(collect(r), collect(z), RHO)
        dPHI2_interpolant = Interpolations.cubic_spline_interpolation((r, z), dRHOdR .^ 2.0 .+ dRHOdZ .^ 2.0)
        for k in 1:length(eqt.profiles_1d.psi)
            dPHI2 = dPHI2_interpolant.(PR[k], PZ[k])
            eqt.profiles_1d.gm2[k] = flxAvg(dPHI2 ./ PR[k] .^ 2.0, LL[k], FLUXEXPANSION[k], INT_FLUXEXPANSION_DL[k])
        end
    end

    # fix quantities on axis
    for quantity in [:gm2]
        eqt.profiles_1d.gm2[1] =
            Interpolations.cubic_spline_interpolation(
                to_range(eqt.profiles_1d.psi[2:end]) * psi_sign,
                getproperty(eqt.profiles_1d, quantity)[2:end],
                extrapolation_bc=Interpolations.Line(),
            ).(eqt.profiles_1d.psi[1] * psi_sign)
    end

    # find quantities on separatrix
    find_x_point!(eqt)

    return eqt
end

"""
    flux_surface(eqt::equilibrium__time_slice, psi_level::Real)

Returns r,z coordiates of closed flux surface at given psi_level
"""
function flux_surface(eqt::equilibrium__time_slice, psi_level::Real)
    return flux_surface(eqt, psi_level, true)
end

"""
    flux_surface(eqt::equilibrium__time_slice, psi_level::Real, closed::Union{Nothing,Bool})

Returns r,z coordiates of open or closed flux surface at given psi_level

The `closed` parameter:
* nothing: return all contours
* true: all closed flux-surface that encircle the magnetic axis
* false: all open flux-surfaces
"""
function flux_surface(eqt::equilibrium__time_slice, psi_level::Real, closed::Union{Nothing,Bool})
    dim1 = eqt.profiles_2d[1].grid.dim1
    dim2 = eqt.profiles_2d[1].grid.dim2
    PSI = eqt.profiles_2d[1].psi
    psi = eqt.profiles_1d.psi
    R0 = eqt.global_quantities.magnetic_axis.r
    Z0 = eqt.global_quantities.magnetic_axis.z
    flux_surface(dim1, dim2, PSI, psi, R0, Z0, psi_level, closed)
end

function flux_surface(
    dim1::Union{AbstractVector,AbstractRange},
    dim2::Union{AbstractVector,AbstractRange},
    PSI::AbstractArray,
    psi::Union{AbstractVector,AbstractRange},
    R0::Real,
    Z0::Real,
    psi_level::Real,
    closed::Union{Nothing,Bool},
)

    if psi_level == psi[1]
        # handle on axis value as the first flux surface
        psi_level = psi[2]

    elseif psi_level == psi[end]
        # handle boundary by finding accurate lcfs psi
        psi__boundary_level = find_psi_boundary(dim1, dim2, PSI, psi, R0, Z0; raise_error_on_not_open=false)
        if psi__boundary_level !== nothing
            if abs(psi__boundary_level - psi_level) < abs(psi[end] - psi[end-1])
                psi_level = psi__boundary_level
            end
        end
    end

    # contouring routine
    cl = Contour.contour(dim1, dim2, PSI, psi_level)

    prpz = []
    if closed === nothing
        # if no open/closed check, then return all contours
        for line in Contour.lines(cl)
            pr, pz = Contour.coordinates(line)
            R0 = 0.5 * (maximum(pr) + minimum(pr))
            Z0 = 0.5 * (maximum(pz) + minimum(pz))
            reorder_flux_surface!(pr, pz, R0, Z0)
            push!(prpz, (pr, pz))
        end
        return prpz

    elseif closed
        # look for closed flux-surface
        for line in Contour.lines(cl)
            pr, pz = Contour.coordinates(line)
            # pick flux surface that close and contain magnetic axis
            if (pr[1] == pr[end]) && (pz[1] == pz[end]) && (PolygonOps.inpolygon((R0, Z0), collect(zip(pr, pz))) == 1)
                R0 = 0.5 * (maximum(pr) + minimum(pr))
                Z0 = 0.5 * (maximum(pz) + minimum(pz))
                reorder_flux_surface!(pr, pz, R0, Z0)
                return pr, pz, psi_level
            end
        end
        return [], [], psi_level

    elseif !closed
        # look for open flux-surfaces
        for line in Contour.lines(cl)
            pr, pz = Contour.coordinates(line)
            # pick flux surfaces that do not close
            if (pr[1] != pr[end]) || (pz[1] != pz[end])
                R0 = 0.5 * (maximum(pr) + minimum(pr))
                Z0 = 0.5 * (maximum(pz) + minimum(pz))
                reorder_flux_surface!(pr, pz, R0, Z0)
                push!(prpz, (pr, pz))
            end
        end
        return prpz
    end
end

function flxAvg(input::AbstractVector{T}, ll::AbstractVector{T}, fluxexpansion::AbstractVector{T}, int_fluxexpansion_dl::T)::T where {T<:Real}
    return integrate(ll, input .* fluxexpansion) / int_fluxexpansion_dl
end

"""
    volume_integrate(eqt::IMAS.equilibrium__time_slice, what::AbstractVector{T})::AbstractVector{T} where {T<:Real}

Integrate quantity over volume
"""
function volume_integrate(eqt::IMAS.equilibrium__time_slice, what::AbstractVector{T})::T where {T<:Real}
    return integrate(eqt.profiles_1d.psi, eqt.profiles_1d.dvolume_dpsi .* what)
end

"""
    volume_integrate(eqt::IMAS.equilibrium__time_slice, what::AbstractVector{T})::AbstractVector{T} where {T<:Real}

Cumulative integrate quantity over volume
"""
function cumlul_volume_integrate(eqt::IMAS.equilibrium__time_slice, what::AbstractVector{T})::AbstractVector{T} where {T<:Real}
    return cumul_integrate(eqt.profiles_1d.psi, eqt.profiles_1d.dvolume_dpsi .* what)
end

"""
    surface_integrate(eqt::IMAS.equilibrium__time_slice, what::AbstractVector{T})::AbstractVector{T} where {T<:Real}

Integrate quantity over surface
"""
function surface_integrate(eqt::IMAS.equilibrium__time_slice, what::AbstractVector{T})::T where {T<:Real}
    return integrate(eqt.profiles_1d.psi, eqt.profiles_1d.dvolume_dpsi .* what .* eqt.profiles_1d.gm9) ./ 2pi
end

"""
    surface_integrate(eqt::IMAS.equilibrium__time_slice, what::AbstractVector{T})::AbstractVector{T} where {T<:Real}

Cumulative integrate quantity over surface
"""
function cumlul_surface_integrate(eqt::IMAS.equilibrium__time_slice, what::AbstractVector{T})::AbstractVector{T} where {T<:Real}
    return cumul_integrate(eqt.profiles_1d.psi, eqt.profiles_1d.dvolume_dpsi .* what .* eqt.profiles_1d.gm9) ./ 2pi
end

"""
    find_x_point!(eqt::IMAS.equilibrium__time_slice)::eqt.boundary.x_point

Firnd X-points on the last closed flux surface
"""
function find_x_point!(eqt::IMAS.equilibrium__time_slice)::IDSvector{<:IMAS.equilibrium__time_slice___boundary__x_point}
    rlcfs, zlcfs = flux_surface(eqt, eqt.profiles_1d.psi[end], true)
    ll = sqrt((maximum(zlcfs) - minimum(zlcfs)) * (maximum(rlcfs) - minimum(rlcfs))) / 5.0
    private = flux_surface(eqt, eqt.profiles_1d.psi[end], false)
    Z0 = sum(zlcfs) / length(zlcfs)
    empty!(eqt.boundary.x_point)
    for (pr, pz) in private
        if sign(pz[1] - Z0) != sign(pz[end] - Z0)
            # open flux surface does not encicle the plasma
            continue
        elseif minimum_distance_two_shapes(pr, pz, rlcfs, zlcfs) > ll
            # secondary Xpoint far away
            continue
        elseif (sum(pz) < Z0)
            index = argmax(pz)
        elseif (sum(pz) > Z0)
            # upper private region
            index = argmin(pz)
        else
            continue
        end
        indexcfs = argmin((rlcfs .- pr[index]) .^ 2 .+ (zlcfs .- pz[index]) .^ 2)
        resize!(eqt.boundary.x_point, length(eqt.boundary.x_point) + 1)
        eqt.boundary.x_point[end].r = (pr[index] + rlcfs[indexcfs]) / 2.0
        eqt.boundary.x_point[end].z = (pz[index] + zlcfs[indexcfs]) / 2.0
    end

    cc = cocos(11)
    r, z, PSI_interpolant = ψ_interpolant(eqt)
    # refine x-point location
    for rz in eqt.boundary.x_point
        res = Optim.optimize(
            x -> Bp_vector_interpolant(PSI_interpolant, cc, [rz.r + x[1]], [rz.z + x[2]])[1],
            [0.0, 0.0],
            Optim.NelderMead(),
            Optim.Options(g_tol=1E-8),
        )
        rz.r += res.minimizer[1]
        rz.z += res.minimizer[2]
    end

    return eqt.boundary.x_point
end

"""
    fluxsurface_extrema(pr::AbstractVector{T}, pz::AbstractVector{T}) where {T<:Real}

Returns extrema indexes and values of R,Z flux surfaces vectors
    imaxr, iminr,
    imaxz, iminz,
    r_at_max_z, max_z,
    r_at_min_z, min_z,
    z_at_max_r, max_r,
    z_at_min_r, min_r
"""
function fluxsurface_extrema(pr::AbstractVector{T}, pz::AbstractVector{T}) where {T<:Real}
    _, imaxr = findmax(pr)
    _, iminr = findmin(pr)
    _, imaxz = findmax(pz)
    _, iminz = findmin(pz)
    r_at_max_z, max_z = pr[imaxz], pz[imaxz]
    r_at_min_z, min_z = pr[iminz], pz[iminz]
    z_at_max_r, max_r = pz[imaxr], pr[imaxr]
    z_at_min_r, min_r = pz[iminr], pr[iminr]
    return (imaxr, iminr, imaxz, iminz,
        r_at_max_z, max_z,
        r_at_min_z, min_z,
        z_at_max_r, max_r,
        z_at_min_r, min_r)
end

"""
    luce_squareness(pr::AbstractVector{T}, pz::AbstractVector{T}, r_at_max_z::T, max_z::T, r_at_min_z::T, min_z::T, z_at_max_r::T, max_r::T, z_at_min_r::T, min_r::T) where {T<:Real}

Squareness from: "An analytic functional form for characterization and generation of axisymmetric plasma boundaries"
T.C. Luce, Plasma Phys. Control. Fusion 55 (2013) http://dx.doi.org/10.1088/0741-3335/55/9/095009

Returns: zetaou, zetaol, zetail, zetaiu
"""
function luce_squareness(
    pr::AbstractVector{T}, pz::AbstractVector{T},
    r_at_max_z::T, max_z::T,
    r_at_min_z::T, min_z::T,
    z_at_max_r::T, max_r::T,
    z_at_min_r::T, min_r::T) where {T<:Real}

    # zetaou
    PO = (r_at_max_z, z_at_max_r)
    PE = (max_r, max_z)
    PD = IMAS.intersection([PO[1], PE[1]], [PO[2], PE[2]], pr, pz; as_list_of_points=true)[1]
    PC = (cos(pi / 4.0) * (PE[1] - PO[1]) + PO[1], sin(pi / 4.0) * (PE[2] - PO[2]) + PO[2])
    zetaou = (norm(PD .- PO) - norm(PC .- PO)) / norm(PE .- PC)

    # zetaol
    PO = (r_at_min_z, z_at_max_r)
    PE = (max_r, min_z)
    PD = IMAS.intersection([PO[1], PE[1]], [PO[2], PE[2]], pr, pz; as_list_of_points=true)[1]
    PC = (cos(pi / 4.0) * (PE[1] - PO[1]) + PO[1], sin(pi / 4.0) * (PE[2] - PO[2]) + PO[2])
    zetaol = (norm(PD .- PO) - norm(PC .- PO)) / norm(PE .- PC)

    # zetaiu
    PO = (r_at_max_z, z_at_min_r)
    PE = (min_r, max_z)
    PD = IMAS.intersection([PO[1], PE[1]], [PO[2], PE[2]], pr, pz; as_list_of_points=true)[1]
    PC = (cos(pi / 4.0) * (PE[1] - PO[1]) + PO[1], sin(pi / 4.0) * (PE[2] - PO[2]) + PO[2])
    zetaiu = (norm(PD .- PO) - norm(PC .- PO)) / norm(PE .- PC)

    # zetail
    PO = (r_at_min_z, z_at_min_r)
    PE = (min_r, min_z)
    PD = IMAS.intersection([PO[1], PE[1]], [PO[2], PE[2]], pr, pz; as_list_of_points=true)[1]
    PC = (cos(pi / 4.0) * (PE[1] - PO[1]) + PO[1], sin(pi / 4.0) * (PE[2] - PO[2]) + PO[2])
    zetail = (norm(PD .- PO) - norm(PC .- PO)) / norm(PE .- PC)

    return zetaou, zetaol, zetail, zetaiu
end

"""
    symmetrize_equilibrium!(eqt::IMAS.equilibrium__time_slice)

Update equilibrium time slice in place to be symmetric with respect to its magnetic axis.

This is done by averaging the upper and lower parts of the equilibrium.

Flux surfaces should re-traced after this operation.

NOTE: Use with care! This operation will change the flux surfaces (LCFS included) and as such quantities may change
"""
function symmetrize_equilibrium!(eqt::IMAS.equilibrium__time_slice)
    r, z, PSI_interpolant = ψ_interpolant(eqt)

    Z1 = (maximum(z) + minimum(z)) / 2.0
    Z0 = eqt.global_quantities.magnetic_axis.z
    zz = z .- Z1 .+ Z0
    zz = LinRange(max(minimum(z), minimum(zz)), min(maximum(z), maximum(zz)), length(z))

    psi = PSI_interpolant(r, zz)

    eqt.profiles_2d[1].grid.dim2 = zz
    eqt.profiles_2d[1].psi = (psi[1:end, end:-1:1] .+ psi) ./ 2.0
end

"""
    vacuum_r0_b0(eqt::IMAS.equilibrium__time_slice) 

Returns vacuum R0 and B0
"""
function vacuum_r0_b0(eqt::IMAS.equilibrium__time_slice)
    eq = top_ids(IMAS.equilibrium__time_slice())
    if eq !== nothing
        r0 = eq.vacuum_toroidal_field.r0
        b0 = get_time_array(eq.vacuum_toroidal_field, :b0, eqt.time)
    else
        r0 = eqt.boundary.geometric_axis.r
        b0 = eqt.profiles_1d.f[end] / r0
    end
    return r0, b0
end
