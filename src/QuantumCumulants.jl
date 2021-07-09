module QuantumCumulants

import SymbolicUtils
import SymbolicUtils: substitute

import Symbolics

import SciMLBase

import ModelingToolkit
const MTK = ModelingToolkit
import ModelingToolkit: ⊗ # just to avoid conflicts

using Combinatorics: partitions, combinations

export HilbertSpace, ProductSpace, ⊗, tensor,
        QSym, QTerm, @qnumbers,
        FockSpace, Destroy, Create,
        NLevelSpace, Transition,
        MeanfieldEquations,
        meanfield, commutator, acts_on,
        CNumber, Parameter, @cnumbers, cnumbers,
        Average, average, cumulant_expansion, get_order, cumulant,
        find_missing, complete, complete!, find_operators, fundamental_operators,
            unique_ops, unique_ops!,
        CorrelationFunction, Spectrum, correlation_u0, correlation_p0,
        Symmetrized, symmetrize,
        ClusterSpace,
        scale,
        transition_superscript

include("hilbertspace.jl")
include("qnumber.jl")
include("cnumber.jl")
include("fock.jl")
include("nlevel.jl")
include("equations.jl")
include("meanfield.jl")
include("average.jl")
include("utils.jl")
include("diffeq.jl")
include("correlation.jl")
include("symmetrize.jl")
include("cluster.jl")
include("scale.jl")
include("latexify_recipes.jl")
include("printing.jl")

@deprecate heisenberg(args...; kwargs...) meanfield(args...; kwargs...)

end # module
