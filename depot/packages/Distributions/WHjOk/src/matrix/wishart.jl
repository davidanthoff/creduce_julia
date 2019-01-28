"""
    Wishart(nu, S)
The [Wishart distribution](http://en.wikipedia.org/wiki/Wishart_distribution) is a
multidimensional generalization of the Chi-square distribution, which is characterized by
a degree of freedom ν, and a base matrix S.
"""
struct Wishart{T<:Real, ST<:AbstractPDMat} <: ContinuousMatrixDistribution
    df::T     # degree of freedom
    S::ST           # the scale matrix
    c0::T     # the logarithm of normalizing constant in pdf
end
function Wishart(df::T, S::AbstractPDMat{T}) where T<:Real
    p = dim(S)
    df > p - 1 || error("dpf should be greater than dim - 1.")
    c0 = _wishart_c0(df, S)
    R = Base.promote_eltype(T, c0)
    prom_S = convert(AbstractArray{T}, S)
    Wishart{R, typeof(prom_S)}(R(df), prom_S, R(c0))
end
function Wishart(df::Real, S::AbstractPDMat)
    T = Base.promote_eltype(df, S)
    Wishart(T(df), convert(AbstractArray{T}, S))
end
Wishart(df::Real, S::Matrix) = Wishart(df, PDMat(S))
Wishart(df::Real, S::Cholesky) = Wishart(df, PDMat(S))
function _wishart_c0(df::Real, S::AbstractPDMat)
    h_df = df / 2
    p = dim(S)
    h_df * (logdet(S) + p * typeof(df)(logtwo)) + logmvgamma(p, h_df)
end
insupport(::Type{Wishart}, X::Matrix) = isposdef(X)
insupport(d::Wishart, X::Matrix) = size(X) == size(d) && isposdef(X)
dim(d::Wishart) = dim(d.S)
size(d::Wishart) = (p = dim(d); (p, p))
params(d::Wishart) = (d.df, d.S, d.c0)
@inline partype(d::Wishart{T}) where {T<:Real} = T
function convert(::Type{Wishart{T}}, d::Wishart) where T<:Real
    P = AbstractMatrix{T}(d.S)
    Wishart{T, typeof(P)}(T(d.df), P, T(d.c0))
end
function convert(::Type{Wishart{T}}, df, S::AbstractPDMat, c0) where T<:Real
    P = AbstractMatrix{T}(S)
    Wishart{T, typeof(P)}(T(df), P, T(c0))
end
show(io::IO, d::Wishart) = show_multline(io, d, [(:df, d.df), (:S, Matrix(d.S))])
mean(d::Wishart) = d.df * Matrix(d.S)
function mode(d::Wishart)
    r = d.df - dim(d) - 1.0
    if r > 0.0
        return Matrix(d.S) * r
    else
        error("mode is only defined when df > p + 1")
    end
end
function meanlogdet(d::Wishart)
    p = dim(d)
    df = d.df
    v = logdet(d.S) + p * logtwo
    for i = 1:p
        v += digamma(0.5 * (df - (i - 1)))
    end
    return v
end
function entropy(d::Wishart)
    p = dim(d)
    df = d.df
    d.c0 - 0.5 * (df - p - 1) * meanlogdet(d) + 0.5 * df * p
end
function _logpdf(d::Wishart, X::AbstractMatrix)
    df = d.df
    p = dim(d)
    Xcf = cholesky(X)
    0.5 * ((df - (p + 1)) * logdet(Xcf) - tr(d.S \ X)) - d.c0
end
function rand(d::Wishart)
    Z = unwhiten!(d.S, _wishart_genA(dim(d), d.df))
    Z * Z'
end
function _wishart_genA(p::Int, df::Real)
    A = zeros(p, p)
    for i = 1:p
        @inbounds A[i,i] = sqrt(rand(Chisq(df - i + 1.0)))
    end
    for j = 1:p-1, i = j+1:p
        @inbounds A[i,j] = randn()
    end
    return A
end
