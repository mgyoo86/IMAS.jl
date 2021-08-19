import JSON
using Memoize

"""
    imas_load_dd(ids; imas_version=imas_version)

Read the IMAS data structures in the OMAS JSON format
"""
@memoize function imas_load_dd(ids)
    JSON.parsefile(joinpath(dirname(dirname(@__FILE__)), "data_structures", "$ids.json"))  # parse and transform data
end

"""
    imas_info(location::String)

Return information of a node in the IMAS data structure
"""
function imas_info(location::String)
    location = replace(location, r"\[[0-9]+\]$" => "[:]")
    location = replace(location, r"\[:\]$" => "")
    return imas_load_dd(split(location, ".")[1])[location]
end

"""
    struct_field_type(structure::DataType, field::Symbol)

Return the typeof of a given `field` witin a `structure`
"""
function struct_field_type(structure::DataType, field::Symbol)
    names = fieldnames(structure)
    index = findfirst(isequal(field), names)
    return structure.types[index]
end

#= === =#
#  FDS  #
#= === =#

abstract type FDS end

"""
    coordinates(fds::FDS, field::Symbol)

Returns two lists, one of coordinate names and the other with their values in the data structure
Coordinate value is `nothing` when the data does not have a coordinate
Coordinate value is `missing` if the coordinate is missing in the data structure
"""
function coordinates(fds::FDS, field::Symbol)
    coord_names = deepcopy(imas_info("$(f2u(fds)).$(field)")["coordinates"])
    coord_values = []
    for (k, coord) in enumerate(coord_names)
        if contains(coord, "...")
            push!(coord_values, nothing)
        else
            h = top(fds)
            coord = replace(coord, ":" => "1")
            for k in i2p(coord)
                if (typeof(k) <: Int) & (typeof(h) <: FDSvector)
                    if length(keys(h)) <= k
                        h = h[k]
                        # println('*',k)
                    else
                        # println('-',k)
                    end
                elseif (typeof(k) <: Symbol) & (typeof(h) <: FDS)
                    if hasfield(typeof(h), k)
                        h = getfield(h, k)
                        # println('*',k)
                    else
                        # println('-',k)
                    end
                else
                    # println('-',k)
                end
            end
            if (h === fds) | (h === missing)
                push!(coord_values, missing)
            else
                push!(coord_values, h)
            end
        end
    end
    return Dict(:names => coord_names, :values => coord_values)
end

function Base.getproperty(fds::FDS, field::Symbol)
    return getfield(fds, field)
end

function Base.setproperty!(fds::FDS, field::Symbol, v)
    if typeof(v) <: FDS
        setfield!(v, :_parent, WeakRef(fds))
    elseif typeof(v) <: AbstractFDArray
        setfield!(v, :_field, field)
    end

    # if the value is not an AbstractFDArray...
    if ! (typeof(v) <: AbstractFDArray)
        target_type = typeintersect(convertsion_types, struct_field_type(typeof(fds), field))
        # ...but the target should be one
        if target_type <: AbstractFDArray
            # figure out the coordinates
            coords = coordinates(fds, field)
            for (k, (c_name, c_value)) in enumerate(zip(coords[:names], coords[:values]))
                # do not allow assigning data before coordinates
                if c_value === missing
                    error("Assign data to `$c_name` before assigning `$(f2(fds)).$(field)`")
                end
                # generate indexes for data that does not have coordinates
                if c_value === nothing
                    coords[:values][k] = Vector{Float64}(collect(1.0:float(size(v)[k])))
                end
            end
            coords[:values] = Vector{Vector{Float64}}(coords[:values])
            # convert value to AbstractFDArray type
            if typeof(v) <: Function
                v = AnalyticalFDVector(WeakRef(fds), field, v)
            else
                v = NumericalFDVector(WeakRef(fds), field, coords[:values], v)
            end
        end
    end

    return setfield!(fds, field, v)
end

#= ========= =#
#  FDSvector  #
#= ========= =#

mutable struct FDSvector{T} <: AbstractVector{T}
    value::Vector{T}
    _parent::WeakRef
    function FDSvector(x::Vector{T}) where {T <: FDS}
        return new{T}(x, WeakRef(missing))
    end
end

function Base.getindex(x::FDSvector{T}, i::Int64) where {T <: FDS}
    x.value[i]
end

function Base.size(x::FDSvector{T}) where {T <: FDS}
    size(x.value)
end

function Base.length(x::FDSvector{T}) where {T <: FDS}
    length(x.value)
end

function Base.setindex!(x::FDSvector{T}, v, i::Int64) where {T <: FDS}
    x.value[i] = v
    v._parent = WeakRef(x)
end

import Base: push!, pop!

function push!(x::FDSvector{T}, v) where {T <: FDS}
    v._parent = WeakRef(x)
    push!(x.value, v)
end

function pop!(x::Vector{T}) where {T <: FDS}
    pop!(x.value)
end

function iterate(fds::FDSvector{T}) where {T <: FDS}
    return fds[1], 2
end

function iterate(fds::FDSvector{T}, state) where {T <: FDS}
    if isempty(state)
        nothing
    else
        fds[state], state + 1
    end
end

#= ======= =#
#  FDArray  #
#= ======= =#

using Interpolations

abstract type AbstractFDArray{T,N} <: AbstractArray{T,N} end
const AbstractFDVector = AbstractFDArray{T,1} where T

#= ================= =#
#  NumericalFDVector  #
#= ================= =#

struct NumericalFDVector <: AbstractFDVector{Float64}
    _parent::WeakRef
    _field::Symbol
    coord_values::Vector{Vector{Float64}}
    value::Vector{Float64}
end

Base.broadcastable(fdv::NumericalFDVector) = Base.broadcastable(fdv.value)

function Base.getindex(fdv::NumericalFDVector, i::Int64)
    fdv.value[i]
end

Base.size(p::NumericalFDVector) = size(p.value)

function Base.setindex!(fdv::NumericalFDVector, v, i::Int64)
    fdv.value[i] = v
end

function (fdv::NumericalFDVector)(y)
    LinearInterpolation(fdv.coord_values[1], fdv.value)(y)
end

#= ================== =#
#  AnalyticalFDVector  #
#= ================== =#

struct AnalyticalFDVector <: AbstractFDVector{Float64}
    _parent::WeakRef
    _field::Symbol
    func::Function
end

function coordinates(fdv::AbstractFDVector)
    return coordinates(fdv._parent.value, fdv._field)
end

function Base.broadcastable(fdv::AnalyticalFDVector)
    y = fdv.func(coordinates(fdv)[:values][1])
    Base.broadcastable(y)
end

function Base.getindex(fdv::AnalyticalFDVector, i::Int64)
    fdv.func(coordinates(fdv)[:values][1][i])
end

Base.size(fdv::AnalyticalFDVector) = size(coordinates(fdv)[:values][1])

function Base.setindex!(fdv::AnalyticalFDVector, v, i::Int64)
    error("Cannot setindex! of a AnalyticalFDVector")
end

function (fdv::AnalyticalFDVector)(y)
    fdv.func(y)
end

#= ===================== =#
#  FDS related functions  #
#= ===================== =#

"""
    f2u(fds::Union{FDS, FDSvector, DataType, Symbol, String})

Returns universal IMAS location of a given FDS
"""
function f2u(fds::Union{FDS,FDSvector})
    return f2u(typeof(fds))
end

function f2u(fds::DataType)
    return f2u(Base.typename(fds).name)
end

function f2u(fds::Symbol)
    return f2u(string(fds))
end

function f2u(fds::String)
    tmp = replace(fds, "___" => "[:].")
    tmp = replace(tmp, "__" => ".")
    imas_location = replace(tmp, r"_$" => "")
    return imas_location
end

"""
    function f2i(fds::Union{FDS,FDSvector})

Returns IMAS location of a given FDS
"""
function f2i(fds::Union{FDS,FDSvector})
    return f2i(fds, missing, nothing, Int)
end

function f2i(fds::Union{FDS,FDSvector}, child::Union{Missing,FDS,FDSvector}, path::Union{Nothing,Vector}, index::Int)
    if typeof(fds) <: FDS
        if typeof(fds._parent.value) <: FDSvector
            name = string(Base.typename(typeof(fds)).name) * "___"
        else
            name = string(Base.typename(typeof(fds)).name)
        end
    elseif typeof(fds) <: FDSvector
        name = string(Base.typename(eltype(fds)).name) * "___"
    end
    if path === nothing
        path = replace(name, "___" => "__:__")
        path = Vector{Any}(Vector{String}(split(path, "__")))
        path = [k == ":" ? 0 : k for k in path]
        index = length(path)
    end
    if typeof(fds) <: FDSvector
        ix = findfirst([k === child for k in fds.value])
        if ix !== nothing
            path[index] = ix
        end
    end
    if fds._parent.value === missing
        return p2i(path)
    else
        return f2i(fds._parent.value, fds, path, index - 1)
    end
end


"""
    i2p(imas_location::String)

Split IMAS location in its elements
"""
function i2p(imas_location::String)
    path = Any[]
    for s in split(imas_location, '.')
        if contains(s, '[')
            s, n = split(s, '[')
            n = strip(n, ']')
            push!(path, Symbol(s))
            if n == ":"
                push!(path, n)
            else
                push!(path, parse(Int, n))
            end
        else
            push!(path, Symbol(s))
        end
    end
    return path
end

"""
    p2i(path::Any[])

Combine list of IMAS location elements into a string
"""
function p2i(path::Vector{Any})
    str = String[]
    for k in path
        if typeof(k) <: Symbol
            push!(str, string(k))
        elseif typeof(k) <: Int
            push!(str, "[$(string(k))]")
        elseif (k == ":") | (k == ':') | (typeof(k) === Colon) 
            push!(str, "[:]")
        elseif typeof(k) <: String
            push!(str, k)
        end
    end
    return replace(join(str, "."), ".[" => "[")
end

import Base:keys

"""
    keys(fds::Union{FDS, FDSvector})

Returns list of fields with data in a FDS/FDSvector
"""
function Base.keys(fds::FDS)
    kkk = Symbol[]
    for k in fieldnames(typeof(fds))
        # hide the _parent field
        if k === :_parent
            continue
        end
        v = getfield(fds, k)
        # empty entries
        if v === missing
            continue
        # empty structures/arrays of structures (recursive)
        elseif typeof(v) <: Union{FDS,FDSvector}
            if length(keys(v)) > 0
                push!(kkk, k)
            end
        # entries with data
        else
            push!(kkk, k)
        end
    end
    return kkk
end

function Base.keys(fds::FDSvector)
    return collect(1:length(fds))
end

import Base:show

function Base.show(io::IO, fds::Union{FDS,FDSvector}, depth::Int)
    items = keys(fds)
    for (k, item) in enumerate(items)
        # arrays of structurs
        if typeof(fds) <: FDSvector
            printstyled("$(' '^depth)[$(item)]\n"; bold=true, color=:green)
            show(io, fds[item], depth + 1)
        # structures
        elseif typeof(getfield(fds, item)) <: Union{FDS,FDSvector}
            if (typeof(fds) <: dd)
                printstyled("$(' '^depth)$(uppercase(string(item)))\n"; bold=true)
            else
                printstyled("$(' '^depth)$(string(item))\n"; bold=true)
            end
            show(io, getfield(fds, item), depth + 1)
        # field
        else
            printstyled("$(' '^depth)$(item)")
            printstyled(" ➡ "; color=:red)
            printstyled("$(Base.summary(getfield(fds, item)))\n"; color=:blue)
        end
        if (typeof(fds) <: dd) & (k < length(items))
            println()
        end
    end
end

function Base.show(io::IO, fds::Union{FDS,FDSvector})
    return show(io, fds, 0)
end