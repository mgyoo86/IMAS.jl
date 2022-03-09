using Revise
using IMAS
import IMASDD
using Test

do_plot = true
if do_plot
    using Plots
end

@testset "flux_surfaces" begin
    filename = joinpath(dirname(dirname(pathof(IMASDD))), "sample", "D3D_eq_ods.json")
    dd = IMAS.json2imas(filename; verbose = false)

    dd_orig = deepcopy(dd)

    IMAS.flux_surfaces(dd.equilibrium)

    ids_orig = dd_orig.equilibrium
    ids = dd.equilibrium

    diff(ids_orig, ids; tol = 1E-1, plot_function = do_plot ? plot : nothing)
end