struct OTFlow <: AbstractLuxLayer
    d::Int          # Input dimension
    m::Int          # Hidden dimension
    r::Int          # Rank for low-rank approximation
end

# Constructor with default rank
OTFlow(d::Int, m::Int; r::Int=min(10,d)) = OTFlow(d, m, r)

# Initialize parameters and states
function Lux.initialparameters(rng::AbstractRNG, l::OTFlow)
    w = randn(rng, Float64, l.m) .* 0.01
    A = randn(rng, Float64, l.r, l.d + 1) .* 0.01
    b = zeros(Float64, l.d + 1)
    c = zero(Float64)
    K0 = randn(rng, Float64, l.m, l.d + 1) .* 0.01
    K1 = randn(rng, Float64, l.m, l.m) .* 0.01
    b0 = zeros(Float64, l.m)
    b1 = zeros(Float64, l.m)
    
    return (w=w, A=A, b=b, c=c, K0=K0, K1=K1, b0=b0, b1=b1)
end

Lux.initialstates(::AbstractRNG, ::OTFlow) = NamedTuple()

σ(x) = log(exp(x) + exp(-x))
σ′(x) = tanh(x)
σ′′(x) = 1 - tanh(x)^2

function resnet_forward(x::AbstractVector, t::Real, ps)
    s = vcat(x, t)
    u0 = σ.(ps.K0 * s .+ ps.b0)
    u1 = u0 .+ σ.(ps.K1 * u0 .+ ps.b1)  # h=1 as in paper
    return u1
end

function potential(x::AbstractVector, t::Real, ps)
    s = vcat(x, t)
    N = resnet_forward(x, t, ps)
    quadratic_term = 0.5 * s' * (ps.A' * ps.A) * s
    linear_term = ps.b' * s
    return ps.w' * N + quadratic_term + linear_term + ps.c
end

function gradient(x::AbstractVector, t::Real, ps, d::Int)
    s = vcat(x, t)
    u0 = σ.(ps.K0 * s .+ ps.b0)
    z1 = ps.w .+ ps.K1' * (σ′.(ps.K1 * u0 .+ ps.b1) .* ps.w)
    z0 = ps.K0' * (σ′.(ps.K0 * s .+ ps.b0) .* z1)
    
    grad = z0 + (ps.A' * ps.A) * s + ps.b
    return grad[1:d] 
end

function trace(x::AbstractVector, t::Real, ps, d::Int)
    s = vcat(x, t)
    u0 = σ.(ps.K0 * s .+ ps.b0)
    z1 = ps.w .+ ps.K1' * (σ′.(ps.K1 * u0 .+ ps.b1) .* ps.w)
    
    K0_E = ps.K0[:, 1:d]
    A_E = ps.A[:, 1:d]
    
    t0 = sum(σ′′.(ps.K0 * s .+ ps.b0) .* z1 .* (K0_E .^ 2))
    J = Diagonal(σ′.(ps.K0 * s .+ ps.b0)) * K0_E
    t1 = sum(σ′′.(ps.K1 * u0 .+ ps.b1) .* ps.w .* (ps.K1 * J) .^ 2)
    trace_A = tr(A_E' * A_E)
    
    return t0 + t1 + trace_A
end

function (l::OTFlow)(xt::Tuple{AbstractVector, Real}, ps, st)
    x, t = xt
    v = -gradient(x, t, ps, l.d)  # v = -∇Φ
    tr = -trace(x, t, ps, l.d)   # tr(∇v) = -tr(∇²Φ)
    return (v, tr), st
end

function simple_loss(x::AbstractVector, t::Real, l::OTFlow, ps)
    (v, tr), _ = l((x, t), ps, nothing)
    return sum(v.^2) / 2 - tr
end

function manual_gradient(x::AbstractVector, t::Real, l::OTFlow, ps)
    s = vcat(x, t)
    u0 = σ.(ps.K0 * s .+ ps.b0)
    u1 = u0 .+ σ.(ps.K1 * u0 .+ ps.b1)
    
    v = -gradient(x, t, ps, l.d)
    tr = -trace(x, t, ps, l.d)
    
    # Simplified gradients (not full implementation)
    grad_w = u1
    grad_A = (ps.A * s) * s'
    
    return (w=grad_w, A=grad_A, b=similar(ps.b), c=0.0, 
            K0=zeros(l.m, l.d+1), K1=zeros(l.m, l.m), 
            b0=zeros(l.m), b1=zeros(l.m))
end