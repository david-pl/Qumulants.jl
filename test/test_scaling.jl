using Qumulants
using Test
using OrdinaryDiffEq

@testset "scaling" begin

order = 2
N_c = 1 #number of clusters
@cnumbers Δc κ Γ2 Γ3 Γ23 η ν3 ν2
Δ2 = [Parameter(Symbol(:Δ2_, i)) for i=1:N_c]
Δ3 = [Parameter(Symbol(:Δ3_, i)) for i=1:N_c]
Ω3 = [Parameter(Symbol(:Ω3_, i)) for i=1:N_c]
g = [Parameter(Symbol(:g_, i)) for i=1:N_c]
N = [Parameter(Symbol(:N_, i)) for i=1:N_c]

# Define hilbert space
hf = FockSpace(:cavity)
ha = [NLevelSpace(Symbol(:atoms, j),3) for j=1:N_c]
ha_c = [ClusterSpace(ha[j],N[j],order) for j=1:N_c]
h = ⊗(hf, ha_c...)
# Define the fundamental operators
@qnumbers a::Destroy(h,1)
S(i,j,c) = Transition(h,Symbol(:σ, c),i, j, 1+c) #c=cluster

# Hamiltonian
H = Δc*a'*a + sum(Δ2[c]*sum(S(2,2,c)) for c=1:N_c) + sum(Δ3[c]*sum(S(3,3,c)) for c=1:N_c) +
    sum(Ω3[c]*(sum(S(3,1,c)) + sum(S(1,3,c))) for c=1:N_c) + sum(g[c]*(a'*sum(S(1,2,c)) + a*sum(S(2,1,c))) for c=1:N_c)
H = qsimplify(H)
# Collapse operators
J = [a,[S(1,2,c) for c=1:N_c]..., [S(1,3,c) for c=1:N_c]..., [S(2,3,c) for c=1:N_c]..., [S(3,3,c) for c=1:N_c]..., [S(2,2,c) for c=1:N_c]..., a'a]
rates = [κ,[Γ2 for i=1:N_c]...,[Γ3 for i=1:N_c]...,[Γ23 for i=1:N_c]...,[ν3 for i=1:N_c]...,[ν2 for i=1:N_c]...,η]

# Derive equation for average photon number
ops = [a'a, S(2,2,1)[1], a'*S(1,2,1)[1]]
he_ops = heisenberg(ops,H,J;rates=rates)
# Custom filter function -- include only phase-invaraint terms
ϕ(x) = 0
ϕ(x::Destroy) = -1
ϕ(x::Create) = 1
function ϕ(t::Transition)
    if (t.i==1 && t.j==2) || (t.i==3 && t.j==2) || (t.i==:g && t.j==:e)
        -1
    elseif (t.i==2 && t.j==1) || (t.i==2 && t.j==3) || (t.i==:e && t.j==:g)
        1
    else
        0
    end
end
ϕ(avg::Average) = ϕ(avg.arguments[1])
function ϕ(t::QTerm)
    @assert t.f === (*)
    p = 0
    for arg in t.arguments
        p += ϕ(arg)
    end
    return p
end
phase_invariant(x) = iszero(ϕ(x))

he_avg = average(he_ops,2)
he_scale = complete(he_avg;filter_func=phase_invariant, order=order, multithread=false)
@test length(he_scale) == 9

ps = [Δc; κ; Γ2; Γ3; Γ23; η; ν3; ν2; Δ2; Δ3; Ω3; g; N]
meta_f = build_ode(he_scale, ps)
f = Meta.eval(meta_f)
u0 = zeros(ComplexF64, length(he_scale))

N0 = 1000/N_c
N_ = N0*[1.0 for c=1:N_c]

p0 = [ones(length(ps)-1); N_]
prob1 = ODEProblem(f,u0,(0.0,1.0),p0)
sol1 = solve(prob1, Tsit5(), reltol=1e-12, abstol=1e-12)

@test sol1.u[end][1] ≈ 0.0758608728203

## Two-level laser
M = 2
@cnumbers N
hf = FockSpace(:cavity)
ha = NLevelSpace(:atom, (:g,:e))
hc = ClusterSpace(ha, N, M)
h = tensor(hf, hc)

@qnumbers a::Destroy(h)
σ(i,j) = Transition(h,:σ,i,j)

@cnumbers Δ g κ γ ν

H = Δ*a'*a + g*sum(a'*σ(:g,:e)[i] + a*σ(:e,:g)[i] for i=1:M)
J = [a;[σ(:g,:e)[i] for i=1:M];[σ(:e,:g)[i] for i=1:M]]
rates = [κ; [γ for i=1:M]; [ν for i=1:M]]

he = heisenberg(a'*a, H, J; rates=rates)

# Complete
he_scaled = complete(average(he,2);filter_func=phase_invariant)

names = he_scaled.names
avg = average(σ(:e,:g)[1]*σ(:e,:e)[2])
@test isequal(average(σ(:e,:e)[1]*σ(:e,:g)[2]), Qumulants.substitute_redundants(avg,[Qumulants.ClusterAon(2,1),Qumulants.ClusterAon(2,2)],names))

@test Qumulants.lt_reference_order(σ(:e,:g)[1],σ(:g,:e)[2])
@test !Qumulants.lt_reference_order(σ(:g,:e)[1],σ(:e,:g)[2])

he_avg = average(he_scaled,2)
missed = find_missing(he_avg)
filter!(!phase_invariant, missed)
@test isequal(missed, find_missing(he_avg))

subs = Dict(missed .=> 0)
he_nophase = substitute(he_avg, subs)
@test isempty(find_missing(he_nophase))

ps = (Δ, g, γ, κ, ν, N)
f = generate_ode(he_nophase, ps)
p0 = (0, 1.5, 0.25, 1, 4, 7)
u0 = zeros(ComplexF64, length(he_scaled))
prob = ODEProblem(f, u0, (0.0, 50.0), p0)
sol = solve(prob, RK4(), abstol=1e-10, reltol=1e-10)

@test sol.u[end][1] ≈ 12.601868534

# Some abstract tests
M = 4
@cnumbers N
hc = FockSpace(:cavity)
hvib = FockSpace(:mode)
hcluster = ClusterSpace(hvib,N,M)
h = ⊗(hc, hcluster)
a = Destroy(h,:a,1)
b = Destroy(h,:b,2)

names = [:a,[Symbol(:b_,i) for i=1:M]]
scale_aons = [Qumulants.ClusterAon(2,i) for i=1:M]

avg = average(a*b[1]*b[2]*b[2])
avg_sub = Qumulants.substitute_redundants(avg, scale_aons, names)
@test isequal(average(a*b[1]*b[1]*b[2]), avg_sub)

avg = average(b[1]'*b[2]'*b[2])
avg_sub = Qumulants.substitute_redundants(avg, scale_aons, names)
@test isequal(avg_sub, average(b[1]'*b[1]*b[2]'))

avg = average(b[1]*b[1]*b[2]'*b[2])
avg_sub = Qumulants.substitute_redundants(avg, scale_aons, names)
@test isequal(avg_sub, average(b[1]'*b[1]*b[2]*b[2]))

avg = average(b[1]*b[2]'*b[3]*b[4]')
avg_sub = Qumulants.substitute_redundants(avg, scale_aons, names)
@test isequal(avg_sub, average(b[1]'*b[2]'*b[3]*b[4]))

# Test Holstein
M = 2
hc = FockSpace(:cavity)
hvib = FockSpace(:mode)
hcluster = ClusterSpace(hvib,N,M)
h = ⊗(hc, hcluster)
@cnumbers G Δ κ γ Ω
a = Destroy(h,:a,1)
b = Destroy(h,:b,2)

H = Δ*a'*a + G*sum(b[i] + b[i]' for i=1:M)*a'*a + Ω*(a+a')
J = [a,b]
rates = [κ,γ]
ops = [a,a'*a,a*a,b[1],a*b[1],a'*b[1],b[1]'*b[1],b[1]*b[1],b[1]'*b[2],b[1]*b[2]]
he = heisenberg(ops,H,J;rates=rates)

he_avg = average(he,2)
@test isempty(find_missing(he_avg))

ps = (G,Δ,κ,γ,Ω,N)
f = generate_ode(he_avg, ps)

u0 = zeros(ComplexF64, length(he_avg))
p0 = ones(length(ps))
prob = ODEProblem(f, u0, (0.0,1.0), p0)
sol = solve(prob, Tsit5())

# Test molecule
M = 2 # Order
# Prameters
@cnumbers λ ν Γ η Δ γ N
# Hilbert space
h_in = NLevelSpace(:internal, 2)
hv = FockSpace(:vib)
hc = ClusterSpace(hv, N, M)
h = ⊗(h_in, hc)
# Operators
σ(i,j) = Transition(h, :σ, i, j)
b = Destroy(h, :b)
# Hamiltonian
H0 = Δ*σ(2,2) + ν*sum(b_'*b_ for b_ in b)
H_holstein = -1*λ*sum((b_' + b_ for b_ in b))*σ(2,2)
Hl = η*(σ(1,2) + σ(2,1))
H = H0 + H_holstein + Hl
# Jumps
J = [σ(1,2), b]
rates = [γ,Γ]
# Equations
ops = [σ(2,2),σ(1,2),b[1],σ(1,2)*b[1],σ(2,1)*b[1],σ(2,2)*b[1],b[1]'*b[1],b[1]*b[1],b[1]'*b[2],b[1]*b[2]]
he = heisenberg(ops, H, J; rates=rates)
he_avg = average(he,2)
@test isempty(find_missing(he_avg))
ps = (Δ,η,γ,λ,ν,Γ,N)
# Generate function
f = generate_ode(he_avg,ps;check_bounds=true)
p0 = [ones(length(ps)-1); 4]
u0 = zeros(ComplexF64,length(he_avg))
prob1 = ODEProblem(f,u0,(0.0,1.0),p0)
sol1 = solve(prob1,Tsit5(),abstol=1e-12,reltol=1e-12)
bdb1 = get_solution(b[1]'b[1], sol1, he)[end]
σ22_1 = get_solution(σ(2,2), sol1, he)[end]
σ12_1 = get_solution(σ(1,2), sol1, he)[end]


## Two clusters
N_c = 2
N = cnumbers([Symbol(:N_, i) for i=1:N_c]...)
M = 2
hf = FockSpace(:cavity)
ha = NLevelSpace(:atom, (:g,:e))
hc = [ClusterSpace(ha, N[i], M) for i=1:N_c]
h = tensor(hf, hc...)

@qnumbers a::Destroy(h)
σ(i,j,c) = Transition(h,Symbol(:σ_, c),i,j,c+1)

@cnumbers κ
ν = cnumbers([Symbol(:ν_, c) for c=1:N_c]...)
γ = cnumbers([Symbol(:γ_, c) for c=1:N_c]...)
Δ = cnumbers([Symbol(:Δ_, c) for c=1:N_c]...)
g = cnumbers([Symbol(:g_, c) for c=1:N_c]...)

H = sum(Δ[c]*σ(:e,:e,c)[k] for c=1:N_c, k=1:M) + sum(g[c]*(a'*σ(:g,:e,c)[i] + a*σ(:e,:g,c)[i]) for i=1:M, c=1:N_c)
H = qsimplify(H)
J = [a;[σ(:g,:e,c) for c=1:N_c];[σ(:e,:g,c) for c=1:N_c]]
rates = [κ,γ...,ν...]

ops = [a'*a]
he = average(heisenberg(ops, H, J; rates=rates),2)

# Scale
he_scaled = complete(he; filter_func=phase_invariant)

@test isempty(find_missing(he_scaled))

ps = (κ, Δ..., g..., γ..., ν..., N...)
f = generate_ode(he_scaled, ps)
if N_c==2
    p0 = (1, [0 for i=1:N_c]..., [1.5 for i=1:N_c]..., [0.25 for i=1:N_c]..., [4 for i=1:N_c]..., 4, 3)
elseif N_c==3
    p0 = (1, [0 for i=1:N_c]..., [1.5 for i=1:N_c]..., [0.25 for i=1:N_c]..., [4 for i=1:N_c]..., 2, 3, 2)
end
u0 = zeros(ComplexF64, length(he_scaled))
prob = ODEProblem(f, u0, (0.0, 50.0), p0)
sol = solve(prob, RK4(), abstol=1e-10, reltol=1e-10)

@test sol.u[end][1] ≈ 12.601868534

end # testset