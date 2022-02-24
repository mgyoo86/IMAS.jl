import PhysicalConstants.CODATA2018 as PCs

"""
Structure with physics constants:

    μ_0 = 1.25663706212e-6
    c = 2.99792458e8
    ϵ_0 = 8.8541878128e-12
    k_B = 1.380649e-23
    e = 1.602176634e-19
    m_e = 9.1093837015e-31
    m_p = 1.67262192369e-27
    m_n = 1.67492749804e-27
    atm = 101325.0
    m_u = 1.6605390666e-27
"""
Base.@kwdef struct PhysicsConstants
    μ_0 :: Float64 = convert(Float64, PCs.μ_0).val
    c :: Float64 = convert(Float64, PCs.c_0).val
    ϵ_0 :: Float64 = convert(Float64, PCs.ε_0).val
    k_B :: Float64 = convert(Float64, PCs.k_B).val
    e :: Float64 = convert(Float64, PCs.e).val
    m_e :: Float64 =  convert(Float64, PCs.m_e).val
    m_p :: Float64 =  convert(Float64, PCs.m_p).val
    m_n :: Float64 =  convert(Float64, PCs.m_n).val
    atm :: Float64 = convert(Float64, PCs.atm).val
    m_u :: Float64 =  convert(Float64, PCs.m_u).val
end

constants = PhysicsConstants()
