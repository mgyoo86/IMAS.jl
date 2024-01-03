
"""
    area(coil::IMAS.pf_active__coil)

Returns cross sectional area of PF coils
"""
function area(coil::IMAS.pf_active__coil)
    return coil.element[1].geometry.rectangle.width * coil.element[1].geometry.rectangle.height
end

"""
    volume(coil::IMAS.pf_active__coil)

Returns volume of PF coils
"""
function volume(coil::IMAS.pf_active__coil)
    return area(coil) * 2π * coil.element[1].geometry.rectangle.r
end

"""
    is_ohmic_coil(coil::IMAS.pf_active__coil)

Returns true/false if coil is part of the OH
"""
function is_ohmic_coil(coil::IMAS.pf_active__coil)
    if isempty(coil.function)
        error("`$(location(coil)).function` is not set. You may need to run `IMAS.set_coils_function(dd.pf_active.coil)`.")
    end
    return findfirst(:flux, coil.function) !== nothing
end

"""
    set_coils_function(coils::IDSvector{<:IMAS.pf_active__coil})

Setup the pf_active.coil[:].function
"""
function set_coils_function(coils::IDSvector{<:IMAS.pf_active__coil})

    # set coil elements geometry_type attribute
    geometry_types = name_2_index(coils[1].element[1].geometry)
    for coil in coils
        for element in coil.element
            for geometry_type in keys(element.geometry)
                if geometry_type != :geometry_type && !ismissing(getproperty(element.geometry, geometry_type), :r)
                    element.geometry.geometry_type = geometry_types[geometry_type]
                    break
                end
            end
        end
    end

    # find innermost coil... that should be an OH!
    oh_min_radius = Inf
    for coil in coils
        for element in coil.element
            oute = outline(element)
            oh_min_radius = min(oh_min_radius, minimum(oute.r))
        end
    end

    # define as OH coils all the coils that share that minimum radial coordinate
    oh_does_shaping = true
    for coil in coils
        if isempty(coil.function)
            func = resize!(coil.function, :shaping; wipe=false)
            func.description = "PF"

            min_radius = Inf
            for element in coil.element
                oute = outline(element)
                min_radius = min(min_radius, minimum(oute.r))
            end

            if (!ismissing(coil, :name) && contains(uppercase(coil.name), "OH")) || min_radius == oh_min_radius
                func = resize!(coil.function, :flux; wipe=false)
                func.description = "OH"

                # here we assume that if some coils are labeled as OH and are not stacked vertically in the central solenoid
                # then the configuration is like in DIII-D where there are OH compensation coils designed to decouple the
                # flux-swing and the plasma shaping functionalities. This is really a DIII-D thing...
                if min_radius !== oh_min_radius
                    oh_does_shaping = false
                end
            end
        end

        for element in coil.element
            if isempty(element, :turns_with_sign)
                element.turns_with_sign = 1.0
            end
        end
    end

    if oh_does_shaping === false
        for coil in findall(:flux, coils)
            deleteat!(coil.function, :shaping)
        end
    end

    return coils
end


"""
    outline(element::IMAS.pf_active__coil___element{T})::IMAS.pf_active__coil___element___geometry__outline{T} where {T<:Real}

Returns pf_active__coil___element___geometry__outline independenty of geometry_type used to describe the coil element
"""
function outline(element::IMAS.pf_active__coil___element{T})::IMAS.pf_active__coil___element___geometry__outline{T} where {T<:Real}
    geometry_type = index_2_name(element.geometry)[element.geometry.geometry_type]

    # rectangle
    if geometry_type == :outline
        oute = element.geometry.outline

    elseif geometry_type == :rectangle
        r = element.geometry.rectangle.r
        z = element.geometry.rectangle.z
        Δr = element.geometry.rectangle.width / 2.0
        Δz = element.geometry.rectangle.height / 2.0
        oute = IMAS.pf_active__coil___element___geometry__outline()
        oute.r = [-Δr, Δr, Δr, -Δr] .+ r
        oute.z = [-Δz, -Δz, Δz, Δz] .+ z

    else
        error("pf_active geometry type `geometry_type` is not yet supported")
    end

    return oute
end