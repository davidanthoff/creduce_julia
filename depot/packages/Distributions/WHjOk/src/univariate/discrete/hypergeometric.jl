""" """ struct Hypergeometric <: DiscreteUnivariateDistribution
    ns::Int     # number of successes in population
    nf::Int     # number of failures in population
    n::Int      # sample size
    function Hypergeometric(ns::Real, nf::Real, n::Real)
        @check_args(Hypergeometric, ns >= zero(ns) && nf >= zero(nf))
        @check_args(Hypergeometric, zero(n) <= n <= ns + nf)
        new(ns, nf, n)
    end
end
@distr_support Hypergeometric max(d.n - d.nf, 0) min(d.ns, d.n)
params(d::Hypergeometric) = (d.ns, d.nf, d.n)
mean(d::Hypergeometric) = d.n * d.ns / (d.ns + d.nf)
function var(d::Hypergeometric)
    N = d.ns + d.nf
    p = d.ns / N
    d.n * p * (1.0 - p) * (N - d.n) / (N - 1.0)
end
mode(d::Hypergeometric) = floor(Int, (d.n + 1) * (d.ns + 1) / (d.ns + d.nf + 2))
function modes(d::Hypergeometric)
    if (d.ns == d.nf) && mod(d.n, 2) == 1
        [(d.n-1)/2, (d.n+1)/2]
    else
        [mode(d)]
    end
end
skewness(d::Hypergeometric) = (d.nf-d.ns)*sqrt(d.ns+d.nf-1)*(d.ns+d.nf-2*d.n)/sqrt(d.n*d.ns*d.nf*(d.ns+d.nf-d.n))/(d.ns+d.nf-2)
function kurtosis(d::Hypergeometric)
    ns = Float64(d.ns)
    nf = Float64(d.nf)
    n = Float64(d.n)
    N = ns + nf
    a = (N-1) * N^2 * (N * (N+1) - 6*ns * (N-ns) - 6*n*(N-n)) + 6*n*ns*(nf)*(N-n)*(5*N-6)
    b = (n*ns*(N-ns) * (N-n)*(N-2)*(N-3))
    a/b
end
@_delegate_statsfuns Hypergeometric hyper ns nf n
rand(d::Hypergeometric) = convert(Int, StatsFuns.RFunctions.hyperrand(d.ns, d.nf, d.n))
struct RecursiveHypergeomProbEvaluator <: RecursiveProbabilityEvaluator
    ns::Float64
    nf::Float64
    n::Float64
end
RecursiveHypergeomProbEvaluator(d::Hypergeometric) = RecursiveHypergeomProbEvaluator(d.ns, d.nf, d.n)
nextpdf(s::RecursiveHypergeomProbEvaluator, p::Float64, x::Integer) =
    ((s.ns - x + 1) / x) * ((s.n - x + 1) / (s.nf - s.n + x)) * p
Base.broadcast!(::typeof(pdf), r::AbstractArray, d::Hypergeometric, rgn::UnitRange) =
    _pdf!(r, d, rgn, RecursiveHypergeomProbEvaluator(d))
function Base.broadcast(::typeof(pdf), d::Hypergeometric, X::UnitRange)
    r = similar(Array{promote_type(partype(d), eltype(X))}, axes(X))
    r .= pdf.(Ref(d),X)
end
