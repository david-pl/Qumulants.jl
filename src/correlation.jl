"""
    struct CorrelationFunction

Type representing the two-time first-order correlation function of two operators.
"""
struct CorrelationFunction{OP1,OP2,OP0,DE0,DE,S}
    op1::OP1
    op2::OP2
    op2_0::OP0
    de0::DE0
    de::DE
    steady_state::S
end

"""
    CorrelationFunction(op1,op2,de0;steady_state=false,add_subscript=0,mix_choice=maximum)

The first-order two-time correlation function of two operators.

The first-order two-time correlation function of `op1` and `op2` evolving under
the system `de0`. The keyword `steady_state` determines whether the original
system `de0` was evolved up to steady state. The arguments `add_subscript`
defines the subscript added to the name of `op2` representing the constant time.

Note that the correlation function is stored in the first index of the underlying
system of equations.
"""
function CorrelationFunction(op1,op2,de0::HeisenbergEquation; steady_state=false, add_subscript=0, filter_func=nothing, mix_choice=maximum, kwargs...)
    h1 = hilbert(op1)
    h2 = _new_hilbert(hilbert(op2), acts_on(op2))
    h = h1⊗h2

    H0 = de0.hamiltonian
    J0 = de0.jumps

    op1_ = _new_operator(op1, h)
    op2_ = _new_operator(op2, h, length(h.spaces); add_subscript=add_subscript)
    op2_0 = _new_operator(op2, h)
    H = _new_operator(H0, h)
    J = [_new_operator(j, h) for j in J0]
    lhs_new = [_new_operator(l, h) for l in de0.lhs]

    order_lhs = maximum(get_order(l) for l in de0.lhs)
    order_corr = get_order(op1_*op2_)
    order = max(order_lhs, order_corr)
    @assert order > 1
    op_ = op1_*op2_
    @assert get_order(op_) <= order

    he = heisenberg(op_,H,J;rates=de0.rates)
    de_ = average(he, order)
    de = _complete_corr(de_, length(h.spaces), lhs_new, order, steady_state; filter_func=filter_func, mix_choice=mix_choice, kwargs...)

    de0_ = HeisenbergEquation(lhs_new, [_new_operator(r, h) for r in de0.rhs], H, J, de0.rates)
    return CorrelationFunction(op1_, op2_, op2_0, de0_, de, steady_state)
end

"""
    initial_values(c::CorrelationFunction, u_end)

Find the vector containing the correct initial values when numerical solving
the time evolution for the correlation function.

When computing the correlation function of two operators in a system that has
been evolved up to a time `t_end`, such that its state is given by `u_end`, this
function provides the correct initial values in the right order that can be
used to solve the ordinary differential equation together with the function
generated by `generate_ode(c)`.

See also: [`CorrelationFunction`](@ref) [`generate_ode`](@ref)
"""
function initial_values(c::CorrelationFunction, u_end)
    a0 = c.op2_0
    a1 = c.op2
    subs = Dict(a1=>a0)
    ops = [SymbolicUtils.arguments(l)[1] for l in c.de.lhs]
    lhs = [average(substitute(op, subs)) for op in ops]
    u0 = complex(eltype(u_end))[]
    lhs0 = c.de0.lhs
    for l in lhs
        l_adj = _adjoint(l)
        if _in(l, lhs0)
            i = findfirst(isequal(l), lhs0)
            push!(u0, u_end[i])
        elseif _in(l_adj, lhs0)
            i = findfirst(isequal(l_adj), lhs0)
            push!(u0, conj(u_end[i]))
        elseif (l isa Number)
            push!(u0, l)
        else
            check = false
            for i=1:length(lhs0)
                l_ = substitute(l, Dict(lhs0[i] => u_end[i]))
                check = !isequal(l_, l)
                check && (push!(u0, l_); break)
            end
            check || error("Could not find initial value for $l !")
        end
    end
    return u0
end


"""
    struct Spectrum

Type representing the spectrum, i.e. the Fourier transform of a
[`CorrelationFunction`](@ref) in steady state.

To actually compute the spectrum at a frequency `ω`, construct the type on top
of a correlation function and call it with `Spectrum(c)(ω,usteady,p0)`.
"""
struct Spectrum
    corr
    Afunc
    bfunc
    cfunc
    A
    b
    c
end

"""
    Spectrum(c::CorrelationFunction, ps=[]; kwargs...)

Create an instance of [`Spectrum`](@ref) corresponding to the Fourier transform
of the [`CorrelationFunction`](@ref) `c`.


Examples
========
```
julia> c = CorrelationFunction(a',a,de;steady_state=true)
⟨a′*a_0⟩

julia> S = Spectrum(c)
ℱ(⟨a′*a_0⟩)(ω)
```
"""
function Spectrum(c::CorrelationFunction, ps=[]; w=SymbolicUtils.Sym{Parameter}(:ω), kwargs...)
    c.steady_state || error("Cannot use Laplace transform when not in steady state! Use `CorrelationFunction(op1,op2,de0;steady_state=true)` or try computing the Fourier transform of the time evolution of the correlation function directly.")
    de = c.de
    de0 = c.de0
    A,b,c_,Afunc,bfunc,cfunc = _build_spec_func(w, de.lhs, de.rhs, c.op2_0, c.op2, de0.lhs, ps; kwargs...)
    return Spectrum(c, Afunc, bfunc, cfunc, A, b, c_)
end

"""
    (s::Spectrum)(ω::Real,usteady,ps=[];wtol=0)

From an instance of [`Spectrum`](@ref) `s`, actually compute the spectral power
density at the frequency `ω`. Numerically solves the equation `x=inv(A)*b` where
`x` is the vector containing the Fourier transformed correlation function, i.e.
the spectrum is given by `real(x[1])`.
`A` and `b` are a matrix and a vector, respectively, describing the linear system
of equations that needs to be solved to obtain the spectrum.
The tolerance `wtol=0` specifies in which range the frequency should be treated
as zero, i.e. whenever `abs(ω) <= wtol` the term proportional to `1/(im*ω)` is
neglected to avoid divergences.
"""
function (s::Spectrum)(ω::Real,usteady,ps=[];wtol=0)
    A = s.Afunc[1](ω,usteady,ps)
    b = s.bfunc[1](usteady,ps)
    if abs(ω) <= wtol
        b_ = b
    else
        c = s.cfunc[1](ω,usteady,ps)
        b_ = b .+ c
    end
    return 2*real(getindex(A \ b_, 1))
end

"""
    (s::Spectrum)(ω_ls,usteady,ps=[];wtol=0)

From an instance of [`Spectrum`](@ref) `s`, actually compute the spectral power
density at all frequencies in `ω_ls`.
"""
function (s::Spectrum)(ω_ls,usteady,ps=[];wtol=0)
    s_ = Vector{real(eltype(usteady))}(undef, length(ω_ls))
    A = s.Afunc[1](ω_ls[1],usteady,ps)
    b0 = s.bfunc[1](usteady,ps)
    b = copy(b0)
    c = s.cfunc[1](ω_ls[1],usteady,ps)

    if abs(ω_ls[1]) <= wtol
        s_[1] = 2*real(getindex(A \ b, 1))
    else
        s_[1] = 2*real(getindex(A \ (b .+ c), 1))
    end

    Afunc! = (A,ω) -> s.Afunc[2](A,ω,usteady,ps)
    cfunc! = (c,ω) -> s.cfunc[2](c,ω,usteady,ps)
    @inbounds for i=2:length(ω_ls)
        Afunc!(A,ω_ls[i])
        if abs(ω_ls[i]) <= wtol
            s_[i] = 2*real(getindex(A \ b0, 1))
        else
            cfunc!(c,ω_ls[i])
            @. b = b0 + c
            s_[i] = 2*real(getindex(A \ b, 1))
        end
    end

    return s_
end

### Auxiliary functions for CorrelationFunction
function MTK.ODESystem(c::CorrelationFunction; ps=nothing, iv=SymbolicUtils.Sym{Real}(:τ), kwargs...)
    if ps===nothing
        ps′ = []
        for r∈c.de.rhs
            MTK.collect_vars!([],ps′,r,iv)
        end
        unique!(ps′)
    else
        ps′ = ps
    end

    if c.steady_state
        steady_vals = c.de0.lhs
        avg = average(c.op2_0)
        avg_adj = _adjoint(avg)
        if _in(avg, steady_vals)
            idx = findfirst(isequal(avg), steady_vals)
            subs = Dict(average(c.op2) => steady_vals[idx])
            de = substitute(c.de, subs)
        elseif _in(avg_adj, steady_vals)
            idx = findfirst(isequal(avg_adj), steady_vals)
            subs = Dict(average(c.op2) => _adjoint(steady_vals[idx]))
            de = substitute(c.de, subs)
        else
            de = c.de
        end
        ps_ = [ps′..., steady_vals...]
    else
        avg = average(c.op2_0)
        if _in(avg, c.de0.lhs) || _in(_conj(avg), c.de0.lhs)
            ps_ = (ps′..., average(c.op2))
        else
            ps_ = ps′
        end
        de = c.de
    end

    return MTK.ODESystem(de; ps=ps_, iv=iv, kwargs...)
end

substitute(c::CorrelationFunction, args...; kwargs...) =
    CorrelationFunction(c.op1, c.op2, substitute(c.de0, args...; kwargs...), substitute(c.de, args...; kwargs...))

function _new_hilbert(h::ProductSpace, aon)
    if length(aon)==1
        return _new_hilbert(h.spaces[aon[1]], 0)
    else
        spaces = [_new_hilbert(h_, 0) for h_ in h.spaces[aon...]]
        return ProductSpace(spaces)
    end
end
_new_hilbert(h::FockSpace, aon) = FockSpace(Symbol(h.name, 0))
_new_hilbert(h::NLevelSpace, aon) = NLevelSpace(Symbol(h.name, 0), h.levels, h.GS)

function _new_operator(op::Destroy, h, aon=op.aon; add_subscript=nothing)
    if isnothing(add_subscript)
        Destroy(h, op.name, aon)
    else
        Destroy(h, Symbol(op.name, :_, add_subscript), aon)
    end
end
function _new_operator(op::Create, h, aon=op.aon; add_subscript=nothing)
    if isnothing(add_subscript)
        Create(h, op.name, aon)
    else
        Create(h, Symbol(op.name, :_, add_subscript), aon)
    end
end
function _new_operator(t::Transition, h, aon=t.aon; add_subscript=nothing)
    if isnothing(add_subscript)
        Transition(h, t.name, t.i, t.j, aon)
    else
        Transition(h, Symbol(t.name, :_, add_subscript), t.i, t.j, aon)
    end
end
_new_operator(x::Number, h, aon=nothing; kwargs...) = x
function _new_operator(t, h, aon=nothing; kwargs...)
    if SymbolicUtils.istree(t)
        args = []
        if isnothing(aon)
            for arg in SymbolicUtils.arguments(t)
                push!(args, _new_operator(arg, h; kwargs...))
            end
        else
            for arg in SymbolicUtils.arguments(t)
                push!(args, _new_operator(arg,h,aon; kwargs...))
            end
        end
        f = SymbolicUtils.operation(t)
        return f(args...)
    else
        return t
    end
end
function _new_operator(avg::SymbolicUtils.Term{<:AvgSym}, h, aon=nothing; kwargs...)
    op = SymbolicUtils.arguments(avg)[1]
    if isnothing(aon)
        _average(_new_operator(op, h; kwargs...))
    else
        _average(_new_operator(op, h, aon; kwargs...))
    end
end

function _complete_corr(de,aon0,lhs_new,order,steady_state; mix_choice=maximum, filter_func=nothing, kwargs...)
    lhs = de.lhs
    rhs = de.rhs

    H = de.hamiltonian
    J = de.jumps
    rates = de.rates

    order_lhs = maximum(get_order.(lhs))
    order_rhs = maximum(get_order.(rhs))
    if order isa Nothing
        order_ = max(order_lhs, order_rhs)
    else
        order_ = order
    end
    maximum(order_) >= order_lhs || error("Cannot form cumulant expansion of derivative; you may want to use a higher order!")

    vs_ = copy(lhs)
    rhs_ = [cumulant_expansion(r, order_) for r in rhs]
    missed = unique_ops(find_missing(rhs_, vs_))
    filter!(SymbolicUtils.sym_isa(AvgSym),missed)

    function _filter_aon(x) # Filter values that act only on Hilbert space representing system at time t0
        aon = acts_on(x)
        if aon0 in aon
            length(aon)==1 && return false
            return true
        end
        if steady_state # Include terms without t0-dependence only if the system is not in steady state
            return !(_in(x, lhs_new) || _in(_adjoint(x), lhs_new))
        else
            return true
        end
    end
    filter!(_filter_aon, missed)
    isnothing(filter_func) || filter!(filter_func, missed) # User-defined filter

    while !isempty(missed)
        ops = [SymbolicUtils.arguments(m)[1] for m in missed]
        he = isempty(J) ? heisenberg(ops,H; kwargs...) : heisenberg(ops,H,J;rates=rates, kwargs...)
        he_avg = average(he,order_;mix_choice=mix_choice, kwargs...)
        rhs_ = [rhs_;he_avg.rhs]
        vs_ = [vs_;he_avg.lhs]
        missed = unique_ops(find_missing(rhs_,vs_))
        filter!(SymbolicUtils.sym_isa(AvgSym),missed)
        filter!(_filter_aon, missed)
        isnothing(filter_func) || filter!(filter_func, missed) # User-defined filter
    end

    if !isnothing(filter_func)
        # Find missing values that are filtered by the custom filter function,
        # but still occur on the RHS; set those to 0
        missed = unique_ops(find_missing(rhs_, vs_))
        filter!(SymbolicUtils.sym_isa(AvgSym),missed)
        filter!(!filter_func, missed)
        subs = Dict(missed .=> 0)
        rhs_ = [substitute(r, subs) for r in rhs_]
    end
    return HeisenbergEquation(vs_, rhs_, H, J, rates)
end


### Auxiliary functions for Spectrum

function _build_spec_func(ω, lhs, rhs, a1, a0, steady_vals, ps=[])
    s = Dict(a0=>a1)
    ops = [SymbolicUtils.arguments(l)[1] for l in lhs]

    b = [average(qsimplify(substitute(op, s))) for op in ops] # Initial values
    c = [qsimplify(c_ / (1.0im*ω)) for c_ in _find_independent(rhs, a0)]
    aon0 = acts_on(a0)
    @assert length(aon0)==1
    rhs_ = _find_dependent(rhs, aon0[1])
    Ax = [im*ω*lhs[i] - rhs_[i] for i=1:length(lhs)] # Element-wise form of A*x

    # Substitute <a0> by steady-state average <a>
    s_avg = Dict(average(a0) => average(a1))
    Ax = [substitute(A, s_avg) for A∈Ax]
    c = [substitute(c_, s_avg) for c_∈c]

    # Compute symbolic A column-wise by substituting unit vectors into element-wise form of A*x
    A = Matrix{Any}(undef, length(Ax), length(Ax))
    for i=1:length(Ax)
        subs_vals = zeros(length(Ax))
        subs_vals[i] = 1
        subs = Dict(lhs .=> subs_vals)
        A_i = [qsimplify(substitute(Ax[j],subs)) for j=1:length(Ax)]
        A[:,i] = A_i
    end

    # Substitute conjugates
    vs_adj = map(_conj, steady_vals)
    filter!(x->!_in(x,steady_vals), vs_adj)
    A = [substitute_conj(A_,vs_adj) for A_∈A]
    c = [substitute_conj(c_,vs_adj) for c_∈c]

    # Build functions
    Afunc = build_function(A, ω, steady_vals, ps; expression=false)
    bfunc = build_function(b, steady_vals, ps; expression=false)
    cfunc = build_function(c, ω, steady_vals, ps; expression=false)

    return A, b, c, Afunc, bfunc, cfunc
end

_find_independent(rhs::Vector, a0) = [_find_independent(r, a0) for r in rhs]
function _find_independent(r, a0)
    if SymbolicUtils.is_operation(+)(r)
        args_ind = []
        aon0 = acts_on(a0)
        for arg in SymbolicUtils.arguments(r)
            aon = acts_on(arg)
            (aon0 in acts_on(arg) && length(aon)>1) || push!(args_ind, arg)
        end
        isempty(args_ind) && return 0
        return +(args_ind...)
    else
        return 0
    end
end

_find_dependent(rhs::Vector, a0) = [_find_dependent(r, a0) for r in rhs]
function _find_dependent(r, a0)
    if SymbolicUtils.is_operation(+)(r)
        args = []
        for arg in SymbolicUtils.arguments(r)
            aon = acts_on(arg)
            (a0 in aon) && length(aon)>1 && push!(args, arg)
        end
        isempty(args) && return 0
        return +(args...)
    else
        return 0
    end
end
