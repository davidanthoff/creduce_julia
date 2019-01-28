""" """ struct Poisson{T<:Real} <: DiscreteUnivariateDistribution
    λ::T
    Poisson{T}(λ::Real) where {T} = (@check_args(Poisson, λ >= zero(λ)); new{T}(λ))
end
Poisson(λ::T) where {T<:Real} = Poisson{T}(λ)
Poisson(λ::Integer) = Poisson(Float64(λ))
Poisson() = Poisson(1.0)
@distr_support Poisson 0 (d.λ == zero(typeof(d.λ)) ? 0 : Inf)
convert(::Type{Poisson{T}}, λ::S) where {T <: Real, S <: Real} = Poisson(T(λ))
convert(::Type{Poisson{T}}, d::Poisson{S}) where {T <: Real, S <: Real} = Poisson(T(d.λ))
params(d::Poisson) = (d.λ,)
@inline partype(d::Poisson{T}) where {T<:Real} = T
rate(d::Poisson) = d.λ
mean(d::Poisson) = d.λ
mode(d::Poisson) = floor(Int,d.λ)
function modes(d::Poisson)
    λ = d.λ
    isinteger(λ) ? [round(Int, λ) - 1, round(Int, λ)] : [floor(Int, λ)]
end
var(d::Poisson) = d.λ
skewness(d::Poisson) = one(typeof(d.λ)) / sqrt(d.λ)
kurtosis(d::Poisson) = one(typeof(d.λ)) / d.λ
function entropy(d::Poisson{T}) where T<:Real
    λ = rate(d)
    if λ == zero(T)
        return zero(T)
    elseif λ < 50
        s = zero(T)
        λk = one(T)
        for k = 1:100
            λk *= λ
            s += λk * lgamma(k + 1) / gamma(k + 1)
        end
        return λ * (1 - log(λ)) + exp(-λ) * s
    else
        return log(2 * pi * ℯ * λ)/2 -
               (1 / (12 * λ)) -
               (1 / (24 * λ * λ)) -
               (19 / (360 * λ * λ * λ))
    end
end
@_delegate_statsfuns Poisson pois λ
rand(d::Poisson) = convert(Int, StatsFuns.RFunctions.poisrand(d.λ))
struct RecursivePoissonProbEvaluator <: RecursiveProbabilityEvaluator
    λ::Float64
end
RecursivePoissonProbEvaluator(d::Poisson) = RecursivePoissonProbEvaluator(rate(d))
nextpdf(s::RecursivePoissonProbEvaluator, p::Float64, x::Integer) = p * s.λ / x
Base.broadcast!(::typeof(pdf), r::AbstractArray, d::Poisson, rgn::UnitRange) =
    _pdf!(r, d, rgn, RecursivePoissonProbEvaluator(d))
function Base.broadcast(::typeof(pdf), d::Poisson, X::UnitRange)
    r = similar(Array{promote_type(partype(d), eltype(X))}, axes(X))
    r .= pdf.(Ref(d),X)
end
function mgf(d::Poisson, t::Real)
    λ = rate(d)
    return exp(λ * (exp(t) - 1))
end
function cf(d::Poisson, t::Real)
    λ = rate(d)
    return exp(λ * (cis(t) - 1))
end
struct PoissonStats <: SufficientStats
    sx::Float64   # (weighted) sum of x
    tw::Float64   # total sample weight
end
suffstats(::Type{Poisson}, x::AbstractArray{T}) where {T<:Integer} = PoissonStats(sum(x), length(x))
function suffstats(::Type{Poisson}, x::AbstractArray{T}, w::AbstractArray{Float64}) where T<:Integer
    n = length(x)
    n == length(w) || throw(DimensionMismatch("Inconsistent array lengths."))
    sx = 0.
    tw = 0.
    for i = 1 : n
        @inbounds wi = w[i]
        @inbounds sx += x[i] * wi
        tw += wi
    end
    PoissonStats(sx, tw)
end
fit_mle(::Type{Poisson}, ss::PoissonStats) = Poisson(ss.sx / ss.tw)
