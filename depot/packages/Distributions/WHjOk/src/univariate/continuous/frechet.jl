""" """ struct Frechet{T<:Real} <: ContinuousUnivariateDistribution
    α::T
    θ::T
    function Frechet{T}(α::T, θ::T) where T
        @check_args(Frechet, α > zero(α) && θ > zero(θ))
        new{T}(α, θ)
    end
end
Frechet(α::T, θ::T) where {T<:Real} = Frechet{T}(α, θ)
Frechet(α::Real, θ::Real) = Frechet(promote(α, θ)...)
Frechet(α::Integer, θ::Integer) = Frechet(Float64(α), Float64(θ))
Frechet(α::Real) = Frechet(α, 1.0)
Frechet() = Frechet(1.0, 1.0)
@distr_support Frechet 0.0 Inf
function convert(::Type{Frechet{T}}, α::S, θ::S) where {T <: Real, S <: Real}
    Frechet(T(α), T(θ))
end
function convert(::Type{Frechet{T}}, d::Frechet{S}) where {T <: Real, S <: Real}
    Frechet(T(d.α), T(d.θ))
end
shape(d::Frechet) = d.α
scale(d::Frechet) = d.θ
params(d::Frechet) = (d.α, d.θ)
@inline partype(d::Frechet{T}) where {T<:Real} = T
function mean(d::Frechet{T}) where T<:Real
    (α = d.α; α > 1 ? d.θ * gamma(1 - 1 / α) : T(Inf))
end
median(d::Frechet) = d.θ * logtwo^(-1 / d.α)
mode(d::Frechet) = (iα = -1/d.α; d.θ * (1 - iα) ^ iα)
function var(d::Frechet{T}) where T<:Real
    if d.α > 2
        iα = 1 / d.α
        return d.θ^2 * (gamma(1 - 2 * iα) - gamma(1 - iα)^2)
    else
        return T(Inf)
    end
end
function skewness(d::Frechet{T}) where T<:Real
    if d.α > 3
        iα = 1 / d.α
        g1 = gamma(1 - iα)
        g2 = gamma(1 - 2 * iα)
        g3 = gamma(1 - 3 * iα)
        return (g3 - 3g2 * g1 + 2 * g1^3) / ((g2 - g1^2)^1.5)
    else
        return T(Inf)
    end
end
function kurtosis(d::Frechet{T}) where T<:Real
    if d.α > 3
        iα = 1 / d.α
        g1 = gamma(1 - iα)
        g2 = gamma(1 - 2iα)
        g3 = gamma(1 - 3iα)
        g4 = gamma(1 - 4iα)
        return (g4 - 4g3 * g1 + 3 * g2^2) / ((g2 - g1^2)^2) - 6
    else
        return T(Inf)
    end
end
function entropy(d::Frechet)
    1 + MathConstants.γ / d.α + MathConstants.γ + log(d.θ / d.α)
end
function logpdf(d::Frechet{T}, x::Real) where T<:Real
    (α, θ) = params(d)
    if x > 0
        z = θ / x
        return log(α / θ) + (1 + α) * log(z) - z^α
    else
        return -T(Inf)
    end
end
pdf(d::Frechet, x::Real) = exp(logpdf(d, x))
cdf(d::Frechet{T}, x::Real) where {T<:Real} = x > 0 ? exp(-((d.θ / x) ^ d.α)) : zero(T)
ccdf(d::Frechet{T}, x::Real) where {T<:Real} = x > 0 ? -expm1(-((d.θ / x) ^ d.α)) : one(T)
logcdf(d::Frechet{T}, x::Real) where {T<:Real} = x > 0 ? -(d.θ / x) ^ d.α : -T(Inf)
logccdf(d::Frechet{T}, x::Real) where {T<:Real} = x > 0 ? log1mexp(-((d.θ / x) ^ d.α)) : zero(T)
quantile(d::Frechet, p::Real) = d.θ * (-log(p)) ^ (-1 / d.α)
cquantile(d::Frechet, p::Real) = d.θ * (-log1p(-p)) ^ (-1 / d.α)
invlogcdf(d::Frechet, lp::Real) = d.θ * (-lp)^(-1 / d.α)
invlogccdf(d::Frechet, lp::Real) = d.θ * (-log1mexp(lp))^(-1 / d.α)
function gradlogpdf(d::Frechet{T}, x::Real) where T<:Real
    (α, θ) = params(d)
    insupport(Frechet, x) ? -(α + 1) / x + α * (θ^α) * x^(-α-1)  : zero(T)
end
rand(d::Frechet) = rand(GLOBAL_RNG, d)
rand(rng::AbstractRNG, d::Frechet) = d.θ * randexp(rng) ^ (-1 / d.α)
