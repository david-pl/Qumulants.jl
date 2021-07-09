using QuantumCumulants
using ModelingToolkit, OrdinaryDiffEq
using Test

@testset "symmetrize" begin

# Implement example using x and p
struct Position <: QSym
    hilbert
    name
    aon
end

struct Momentum <: QSym
    hilbert
    name
    aon
end

for T ∈ [:Position,:Momentum]
    @eval Base.adjoint(op::($T)) = op
end

QuantumCumulants.ismergeable(::Position,::Momentum) = true
Base.:*(x::Position,p::Momentum) = p*x + im

h = FockSpace(:oscillator)
x = Position(h,:x,1)
p = Momentum(h,:p,1)

@cnumbers ω m
H = p^2/(2m) + 0.5m*ω^2*x^2

eqs = meanfield([x,p,x^2,p^2,p*x],H)

s_eqs = symmetrize(eqs)

@test all(st.arguments[1] isa Symmetrized for st ∈ s_eqs.states)
@test isempty(find_missing(s_eqs))

end # testset
