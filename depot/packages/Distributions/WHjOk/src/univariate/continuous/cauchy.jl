""" """ struct Cauchy{T<:Real} <: ContinuousUnivariateDistribution
    μ::T
    σ::T
    function Cauchy{T}(μ::T, σ::T) where T
        @check_args(Cauchy, σ > zero(σ))
        new{T}(μ, σ)
    end
end
Cauchy(μ::T, σ::T) where {T<:Real} = Cauchy{T}(μ, σ)
Cauchy(μ::Real, σ::Real) = Cauchy(promote(μ, σ)...)
Cauchy(μ::Integer, σ::Integer) = Cauchy(Float64(μ), Float64(σ))
Cauchy(μ::Real) = Cauchy(μ, 1.0)
Cauchy() = Cauchy(0.0, 1.0)
@distr_support Cauchy -Inf Inf
function convert(::Type{Cauchy{T}}, μ::Real, σ::Real) where T<:Real
    Cauchy(T(μ), T(σ))
end
function convert(::Type{Cauchy{T}}, d::Cauchy{S}) where {T <: Real, S <: Real}
    Cauchy(T(d.μ), T(d.σ))
end
location(d::Cauchy) = d.μ
scale(d::Cauchy) = d.σ
params(d::Cauchy) = (d.μ, d.σ)
@inline partype(d::Cauchy{T}) where {T<:Real} = T
mean(d::Cauchy{T}) where {T<:Real} = T(NaN)
median(d::Cauchy) = d.μ
mode(d::Cauchy) = d.μ
var(d::Cauchy{T}) where {T<:Real} = T(NaN)
skewness(d::Cauchy{T}) where {T<:Real} = T(NaN)
kurtosis(d::Cauchy{T}) where {T<:Real} = T(NaN)
entropy(d::Cauchy) = log4π + log(d.σ)
zval(d::Cauchy, x::Real) = (x - d.μ) / d.σ
xval(d::Cauchy, z::Real) = d.μ + z * d.σ
pdf(d::Cauchy, x::Real) = 1 / (π * scale(d) * (1 + zval(d, x)^2))
logpdf(d::Cauchy, x::Real) = - (log1psq(zval(d, x)) + logπ + log(d.σ))
function cdf(d::Cauchy, x::Real)
    μ, σ = params(d)
    invπ * atan(x - μ, σ) + 1//2
end
function ccdf(d::Cauchy, x::Real)
    μ, σ = params(d)
    invπ * atan(μ - x, σ) + 1//2
end
function quantile(d::Cauchy, p::Real)
    μ, σ = params(d)
    μ + σ * tan(π * (p - 1//2))
end
function cquantile(d::Cauchy, p::Real)
    μ, σ = params(d)
    μ + σ * tan(π * (1//2 - p))
end
mgf(d::Cauchy{T}, t::Real) where {T<:Real} = t == zero(t) ? one(T) : T(NaN)
cf(d::Cauchy, t::Real) = exp(im * (t * d.μ) - d.σ * abs(t))
function fit(::Type{Cauchy}, x::AbstractArray{T}) where T<:Real
    l, m, u = quantile(x, [0.25, 0.5, 0.75])
    Cauchy(m, (u - l) / 2)
end
