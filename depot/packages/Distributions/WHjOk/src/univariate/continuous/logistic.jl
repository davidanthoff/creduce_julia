""" """ struct Logistic{T<:Real} <: ContinuousUnivariateDistribution
    μ::T
    θ::T
    Logistic{T}(μ::T, θ::T) where {T} = (@check_args(Logistic, θ > zero(θ)); new{T}(μ, θ))
end
Logistic(μ::T, θ::T) where {T<:Real} = Logistic{T}(μ, θ)
Logistic(μ::Real, θ::Real) = Logistic(promote(μ, θ)...)
Logistic(μ::Integer, θ::Integer) = Logistic(Float64(μ), Float64(θ))
Logistic(μ::Real) = Logistic(μ, 1.0)
Logistic() = Logistic(0.0, 1.0)
@distr_support Logistic -Inf Inf
function convert(::Type{Logistic{T}}, μ::S, θ::S) where {T <: Real, S <: Real}
    Logistic(T(μ), T(θ))
end
function convert(::Type{Logistic{T}}, d::Logistic{S}) where {T <: Real, S <: Real}
    Logistic(T(d.μ), T(d.θ))
end
location(d::Logistic) = d.μ
scale(d::Logistic) = d.θ
params(d::Logistic) = (d.μ, d.θ)
@inline partype(d::Logistic{T}) where {T<:Real} = T
mean(d::Logistic) = d.μ
median(d::Logistic) = d.μ
mode(d::Logistic) = d.μ
std(d::Logistic) = π * d.θ / sqrt3
var(d::Logistic) = (π * d.θ)^2 / 3
skewness(d::Logistic{T}) where {T<:Real} = zero(T)
kurtosis(d::Logistic{T}) where {T<:Real} = T(6)/5
entropy(d::Logistic) = log(d.θ) + 2
zval(d::Logistic, x::Real) = (x - d.μ) / d.θ
xval(d::Logistic, z::Real) = d.μ + z * d.θ
pdf(d::Logistic, x::Real) = (e = exp(-zval(d, x)); e / (d.θ * (1 + e)^2))
logpdf(d::Logistic, x::Real) = (u = -abs(zval(d, x)); u - 2*log1pexp(u) - log(d.θ))
cdf(d::Logistic, x::Real) = logistic(zval(d, x))
ccdf(d::Logistic, x::Real) = logistic(-zval(d, x))
logcdf(d::Logistic, x::Real) = -log1pexp(-zval(d, x))
logccdf(d::Logistic, x::Real) = -log1pexp(zval(d, x))
quantile(d::Logistic, p::Real) = xval(d, logit(p))
cquantile(d::Logistic, p::Real) = xval(d, -logit(p))
invlogcdf(d::Logistic, lp::Real) = xval(d, -logexpm1(-lp))
invlogccdf(d::Logistic, lp::Real) = xval(d, logexpm1(-lp))
function gradlogpdf(d::Logistic, x::Real)
    e = exp(-zval(d, x))
    ((2e) / (1 + e) - 1) / d.θ
end
mgf(d::Logistic, t::Real) = exp(t * d.μ) / sinc(d.θ * t)
function cf(d::Logistic, t::Real)
    a = (π * t) * d.θ
    a == zero(a) ? complex(one(a)) : cis(t * d.μ) * (a / sinh(a))
end
rand(d::Logistic) = rand(GLOBAL_RNG, d)
rand(rng::AbstractRNG, d::Logistic) = quantile(d, rand(rng))
