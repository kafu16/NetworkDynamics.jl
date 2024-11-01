module NetworkDynamics
using Graphs: Graphs, AbstractGraph, SimpleEdge, edges, vertices, ne, nv,
              SimpleGraph, SimpleDiGraph, add_edge!, has_edge
using TimerOutputs: TimerOutputs, @timeit_debug, @timeit

using ArgCheck: @argcheck
using PreallocationTools: PreallocationTools, DiffCache, get_tmp
using SciMLBase: SciMLBase
using Base.Threads: @threads
using NNlib: NNlib
using KernelAbstractions: KernelAbstractions, @kernel, @index, @Const, get_backend
using Atomix: Atomix
using Polyester: Polyester
using Mixers: Mixers
using LinearAlgebra: LinearAlgebra, UniformScaling
using SparseArrays: sparse
using DocStringExtensions: FIELDS, TYPEDEF
using StyledStrings: StyledStrings, @styled_str
using RecursiveArrayTools: DiffEqArray
using FastClosures: @closure
using ForwardDiff: ForwardDiff
using Printf: @sprintf

@static if VERSION ≥ v"1.11.0-0"
    using Base: AnnotatedIOBuffer, AnnotatedString
else
    using StyledStrings: AnnotatedIOBuffer, AnnotatedString
end

using Base: @propagate_inbounds
using InteractiveUtils: subtypes

import SymbolicIndexingInterface as SII
using StaticArrays: StaticArrays, SVector

include("utils.jl")

export ODEVertex, StaticVertex, StaticEdge, ODEEdge, UnifiedVertex, UnifiedEdge
export Symmetric, AntiSymmetric, Directed, Fiducial
export StateMask
export dim, sym, pdim, psym, obssym, depth, hasinputsym, inputsym, coupling
export metadata, symmetadata
include("component_functions.jl")

export Network
export SequentialExecution, KAExecution, ThreadedExecution, PolyesterExecution, SparseAggregator
include("network_structure.jl")

export NaiveAggregator, KAAggregator, SequentialAggregator,
       PolyesterAggregator, ThreadedAggregator
include("aggregators.jl")
include("gbufs.jl")
include("construction.jl")
include("coreloop.jl")

# XXX: have both, s[:] and uflat(s) ?
export VIndex, EIndex, VPIndex, EPIndex, NWState, NWParameter, uflat, pflat
export vidxs, eidxs, vpidxs, epidxs
export save_parameters!
include("symbolicindexing.jl")

export has_metadata, get_metadata, set_metadata!
export has_default, get_default, set_default!
export has_guess, get_guess, set_guess!
export has_init, get_init, set_init!
export has_bounds, get_bounds, set_bounds!
export has_graphelement, get_graphelement, set_graphelement!
include("metadata.jl")

using NonlinearSolve: AbstractNonlinearSolveAlgorithm, NonlinearFunction
using NonlinearSolve: NonlinearLeastSquaresProblem, NonlinearProblem
using SteadyStateDiffEq: SteadyStateProblem, SteadyStateDiffEqAlgorithm, SSRootfind
export find_fixpoint, initialize_component!, init_residual
include("initialization.jl")

include("show.jl")

export chk_component
include("doctor.jl")

#=
using StyledStrings
s1 = styled"{bright_red:brred} {bright_green:brgreen} {bright_yellow:bryellow} {bright_blue:brblue} {bright_magenta:brmagenta} {bright_cyan:brcyan} {bright_black:brblack} {bright_white:brwhite}";
s2 = styled"{red:  red} {green:  green} {yellow:  yellow} {blue:  blue} {magenta:  magenta} {cyan:  cyan} {black:  black} {white:  white}";
println(s1, "\n", s2)
=#
const ND_FACES = [
    :NetworkDynamics_inactive => StyledStrings.Face(foreground=:bright_black),
    :NetworkDynamics_defaultval => StyledStrings.Face(weight=:light),
    :NetworkDynamics_guessval => StyledStrings.Face(foreground=:bright_black, weight=:light),
    :NetworkDynamics_fordstsrc => StyledStrings.Face(foreground=:bright_blue),
    :NetworkDynamics_fordst => StyledStrings.Face(foreground=:bright_yellow),
    :NetworkDynamics_forsrc => StyledStrings.Face(foreground=:bright_magenta),
    :NetworkDynamics_forlayer => StyledStrings.Face(foreground=:bright_blue),
]

__init__() = foreach(StyledStrings.addface!, ND_FACES)

function reloadfaces!()
    StyledStrings.resetfaces!()
    for (k,v) in NetworkDynamics.ND_FACES
        delete!(StyledStrings.FACES.default, k)
    end
    foreach(StyledStrings.addface!, NetworkDynamics.ND_FACES)
end
# NetworkDynamics.reloadfaces!()

using PrecompileTools: @setup_workload, @compile_workload
@setup_workload begin
    @compile_workload begin
        # include("precompile_workload.jl")
    end
end

end
