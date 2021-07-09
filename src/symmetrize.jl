"""
    Symmetrized <: QSym
    Symmetrized(op::QNumber)

A [`QSym`](@ref) representing the symmetrized expression of an operator given by
`S(x) = 0.5*(x + dagger(x))`, where `S` is the symmetrization operator.
"""
struct Symmetrized{T} <: QSym
    operator::T
    function Symmetrized(operator::T) where T<:QNumber
        new{T}(operator)
    end
end
Symmetrized(x::Average) = _average(Symmetrized(x.arguments[1]))
Base.adjoint(s::Symmetrized) = s
Base.isequal(s1::Symmetrized, s2::Symmetrized) = isequal(s1.operator, s2.operator)

for f ∈ [:hilbert, :acts_on]
    @eval $(f)(s::Symmetrized) = $(f)(s.operator)
end

function Base.getproperty(s::Symmetrized, field::Symbol)
    if field === :name
        _get_name(s.operator)
    else
        return getfield(s, field)
    end
end

# Generate a name when necessary
_get_name(x::QSym) = x.name
_get_name(x::QMul) = Symbol(map(_get_name, x.args_nc)...)


"""
    symmetrize(eqs)

Compute the equations that follow symmetric ordering of operators out of a set
of equations that uses normal ordering. This is done by taking the equation of
an operator `x` adding `adjoint(x)` to it and dividing by 2. Operators are wrapped
as [`Symmetrized`](@ref) to avoid repeated application of normal-ordered commutation
relations.
"""
function symmetrize(eqs::MeanfieldEquations)
    lhs = eqs.states
    rhs = getfield.(eqs.equations, :rhs)

    # Substitute normal ordering by symmetric one
    lhs_sym = Symmetrized.(lhs)
    subs = Dict(lhs .=> lhs_sym)
    rhs_sym = [substitute(r, subs) for r ∈ rhs]

    # Compute correct form of equations by adding the adjoint
    rhs_sym = [Symbolics.simplify(0.5*r + 0.5*_conj(r)) for r ∈ rhs_sym]

    eqs_sym = lhs_sym .~ rhs_sym

    varmap = make_varmap(lhs_sym, eqs.iv)

    return MeanfieldEquations(eqs_sym,
                                eqs.operator_equations,
                                lhs_sym,
                                eqs.operators,
                                eqs.hamiltonian,
                                eqs.jumps,
                                eqs.rates,
                                eqs.iv,
                                varmap,
                                eqs.order
                                )
end
