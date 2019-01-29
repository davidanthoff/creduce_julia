abstract type AbstractMvTDist <: ContinuousMultivariateDistribution end
struct GenericMvTDist{T<:Real, Cov<:AbstractPDMat} <: AbstractMvTDist
    df::T # non-integer degrees of freedom allowed
    dim::Int
    zeromean::Bool
    μ::Vector{T}
    Σ::Cov
    function GenericMvTDist{T,Cov}(df::T, dim::Int, zmean::Bool, μ::Vector{T}, Σ::AbstractPDMat{T}) where {T,Cov}
      df > zero(df) || error("df must be positive")
      new{T,Cov}(df, dim, zmean, μ, Σ)
    end
end
function GenericMvTDist(df::T, μ::Vector{T}, Σ::Cov, zmean::Bool) where {Cov<:AbstractPDMat, T<:Real}
    d = length(μ)
    dim(Σ) == d || throw(DimensionMismatch("The dimensions of μ and Σ are inconsistent."))
    R = Base.promote_eltype(T, Σ)
    S = convert(AbstractArray{R}, Σ)
    GenericMvTDist{R, typeof(S)}(R(df), d, zmean, convert(AbstractArray{R}, μ), S)
end
function GenericMvTDist(df::T, μ::Vector{S}, Σ::Cov, zmean::Bool) where {Cov<:AbstractPDMat, T<:Real, S<:Real}
    R = promote_type(T, S)
    GenericMvTDist(R(df), Vector{R}(μ), Σ, zmean)
end
GenericMvTDist(df::Real, μ::Vector{S}, Σ::Cov) where {Cov<:AbstractPDMat, S<:Real} = GenericMvTDist(df, μ, Σ, allzeros(μ))
GenericMvTDist(df::T, Σ::Cov) where {Cov<:AbstractPDMat, T<:Real} = GenericMvTDist(df, zeros(dim(Σ)), Σ, true)
function convert(::Type{GenericMvTDist{T}}, d::GenericMvTDist) where T<:Real
    S = convert(AbstractArray{T}, d.Σ)
    GenericMvTDist{T, typeof(S)}(T(d.df), d.dim, d.zeromean, convert(AbstractArray{T}, d.μ), S)
end
function convert(::Type{GenericMvTDist{T}}, df, dim, zeromean, μ::Union{Vector, ZeroVector}, Σ::AbstractPDMat) where T<:Real
    S = convert(AbstractArray{T}, Σ)
    GenericMvTDist{T, typeof(S)}(T(df), dim, zeromean, convert(AbstractArray{T}, μ), S)
end
const IsoTDist  = GenericMvTDist{Float64, ScalMat{Float64}}
const DiagTDist = GenericMvTDist{Float64, PDiagMat{Float64,Vector{Float64}}}
const MvTDist = GenericMvTDist{Float64, PDMat{Float64,Matrix{Float64}}}
MvTDist(df::Real, μ::Vector{Float64}, C::PDMat) = GenericMvTDist(df, μ, C)
MvTDist(df::Real, C::PDMat) = GenericMvTDist(df, C)
MvTDist(df::Real, μ::Vector{Float64}, Σ::Matrix{Float64}) = GenericMvTDist(df, μ, PDMat(Σ))
MvTDist(df::Float64, Σ::Matrix{Float64}) = GenericMvTDist(df, PDMat(Σ))
DiagTDist(df::Float64, μ::Vector{Float64}, C::PDiagMat) = GenericMvTDist(df, μ, C)
DiagTDist(df::Float64, C::PDiagMat) = GenericMvTDist(df, C)
DiagTDist(df::Float64, μ::Vector{Float64}, σ::Vector{Float64}) = GenericMvTDist(df, μ, PDiagMat(abs2.(σ)))
IsoTDist(df::Float64, μ::Vector{Float64}, C::ScalMat) = GenericMvTDist(df, μ, C)
IsoTDist(df::Float64, C::ScalMat) = GenericMvTDist(df, C)
IsoTDist(df::Float64, μ::Vector{Float64}, σ::Real) = GenericMvTDist(df, μ, ScalMat(length(μ), abs2(Float64(σ))))
IsoTDist(df::Float64, d::Int, σ::Real) = GenericMvTDist(df, ScalMat(d, abs2(Float64(σ))))
mvtdist(df::Real, μ::Vector, C::AbstractPDMat) = GenericMvTDist(df, μ, C)
mvtdist(df::Real, C::AbstractPDMat) = GenericMvTDist(df, C)
mvtdist(df::Real, μ::Vector, σ::Real) = GenericMvTDist(df, μ, ScalMat(length(μ), abs2(σ)))
mvtdist(df::Real, d::Int, σ::Real) = GenericMvTDist(df, μ, ScalMat(d, abs2(σ)))
mvtdist(df::Real, μ::Vector, σ::Vector) = GenericMvTDist(df, μ, PDiagMat(abs2.(σ)))
mvtdist(df::Real, μ::Vector, Σ::Matrix) = GenericMvTDist(df, μ, PDMat(Σ))
mvtdist(df::Real, Σ::Matrix) = GenericMvTDist(df, PDMat(Σ))
mvtdist(df::Float64, μ::Vector{Float64}, σ::Real) = IsoTDist(df, μ, Float64(σ))
mvtdist(df::Float64, d::Int, σ::Float64) = IsoTDist(d, σ)
mvtdist(df::Float64, μ::Vector{Float64}, σ::Vector{Float64}) = DiagTDist(df, μ, σ)
mvtdist(df::Float64, μ::Vector{Float64}, Σ::Matrix{Float64}) = MvTDist(df, μ, Σ)
mvtdist(df::Float64, Σ::Matrix{Float64}) = MvTDist(df, Σ)
length(d::GenericMvTDist) = d.dim
mean(d::GenericMvTDist) = d.df>1 ? d.μ : NaN
mode(d::GenericMvTDist) = d.μ
modes(d::GenericMvTDist) = [mode(d)]
var(d::GenericMvTDist) = d.df>2 ? (d.df/(d.df-2))*diag(d.Σ) : Float64[NaN for i = 1:d.dim]
scale(d::GenericMvTDist) = Matrix(d.Σ)
cov(d::GenericMvTDist) = d.df>2 ? (d.df/(d.df-2))*Matrix(d.Σ) : NaN*ones(d.dim, d.dim)
invscale(d::GenericMvTDist) = Matrix(inv(d.Σ))
invcov(d::GenericMvTDist) = d.df>2 ? ((d.df-2)/d.df)*Matrix(inv(d.Σ)) : NaN*ones(d.dim, d.dim)
logdet_cov(d::GenericMvTDist) = d.df>2 ? logdet((d.df/(d.df-2))*d.Σ) : NaN
params(d::GenericMvTDist) = (d.df, d.μ, d.Σ)
@inline partype(d::GenericMvTDist{T}) where {T<:Real} = T
function entropy(d::GenericMvTDist)
    hdf, hdim = 0.5*d.df, 0.5*d.dim
    shdfhdim = hdf+hdim
    0.5*logdet(d.Σ)+hdim*log(d.df*pi)+lbeta(hdim, hdf)-lgamma(hdim)+shdfhdim*(digamma(shdfhdim)-digamma(hdf))
end
insupport(d::AbstractMvTDist, x::AbstractVector{T}) where {T<:Real} =
    length(d) == length(x) && allfinite(x)
function sqmahal(d::GenericMvTDist, x::AbstractVector{T}) where T<:Real
    z = d.zeromean ? x : x - d.μ
    invquad(d.Σ, z)
end
function sqmahal!(r::AbstractArray, d::GenericMvTDist, x::AbstractMatrix{T}) where T<:Real
    z = d.zeromean ? x : x .- d.μ
    invquad!(r, d.Σ, z)
end
sqmahal(d::AbstractMvTDist, x::AbstractMatrix{T}) where {T<:Real} = sqmahal!(Vector{T}(undef, size(x, 2)), d, x)
function mvtdist_consts(d::AbstractMvTDist)
    hdf = 0.5 * d.df
    hdim = 0.5 * d.dim
    shdfhdim = hdf + hdim
    v = lgamma(shdfhdim) - lgamma(hdf) - hdim*log(d.df) - hdim*log(pi) - 0.5*logdet(d.Σ)
    return (shdfhdim, v)
end
function _logpdf(d::AbstractMvTDist, x::AbstractVector{T}) where T<:Real
    shdfhdim, v = mvtdist_consts(d)
    v - shdfhdim * log1p(sqmahal(d, x) / d.df)
end
function _logpdf!(r::AbstractArray, d::AbstractMvTDist, x::AbstractMatrix{T}) where T<:Real
    sqmahal!(r, d, x)
    shdfhdim, v = mvtdist_consts(d)
    for i = 1:size(x, 2)
        r[i] = v - shdfhdim * log1p(r[i] / d.df)
    end
    return r
end
_pdf!(r::AbstractArray, d::AbstractMvTDist, x::AbstractMatrix{T}) where {T<:Real} = exp!(_logpdf!(r, d, x))
function gradlogpdf(d::GenericMvTDist, x::AbstractVector{T}) where T<:Real
    z::Vector{T} = d.zeromean ? x : x - d.μ
    prz = invscale(d)*z
    -((d.df + d.dim) / (d.df + dot(z, prz))) * prz
end
function _rand!(d::GenericMvTDist, x::AbstractVector{T}) where T<:Real
    chisqd = Chisq(d.df)
    y = sqrt(rand(chisqd)/(d.df))
    unwhiten!(d.Σ, randn!(x))
    broadcast!(/, x, x, y)
    if !d.zeromean
        broadcast!(+, x, x, d.μ)
    end
    x
end
function _rand!(d::GenericMvTDist, x::AbstractMatrix{T}) where T<:Real
    cols = size(x,2)
    chisqd = Chisq(d.df)
    y = Matrix{T}(undef, 1, cols)
    unwhiten!(d.Σ, randn!(x))
    rand!(chisqd, y)
    y = sqrt.(y/(d.df))
    broadcast!(/, x, x, y)
    if !d.zeromean
        broadcast!(+, x, x, d.μ)
    end
    x
end