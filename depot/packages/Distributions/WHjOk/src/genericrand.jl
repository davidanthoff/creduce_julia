""" """ rand(s::Sampleable)
""" """ rand!(s::Sampleable, A::AbstractArray)
function _rand!(s::Sampleable{Univariate}, A::AbstractArray)
    for i in 1:length(A)
        @inbounds A[i] = rand(s)
    end
    return A
end
rand!(s::Sampleable{Univariate}, A::AbstractArray) = _rand!(s, A)
rand(s::Sampleable{Univariate}, dims::Dims) =
    _rand!(s, Array{eltype(s)}(undef, dims))
rand(s::Sampleable{Univariate}, dims::Int...) =
    _rand!(s, Array{eltype(s)}(undef, dims))
function _rand!(s::Sampleable{Multivariate}, A::AbstractMatrix)
    for i = 1:size(A,2)
        _rand!(s, view(A,:,i))
    end
    return A
end
function rand!(s::Sampleable{Multivariate}, A::AbstractVector)
    length(A) == length(s) ||
        throw(DimensionMismatch("Output size inconsistent with sample length."))
    _rand!(s, A)
end
function rand!(s::Sampleable{Multivariate}, A::AbstractMatrix)
    size(A,1) == length(s) ||
        throw(DimensionMismatch("Output size inconsistent with sample length."))
    _rand!(s, A)
end
rand(s::Sampleable{Multivariate}) =
    _rand!(s, Vector{eltype(s)}(undef, length(s)))
rand(s::Sampleable{Multivariate}, n::Int) =
    _rand!(s, Matrix{eltype(s)}(undef, length(s), n))
function _rand!(s::Sampleable{Matrixvariate}, X::AbstractArray{M}) where M<:Matrix
    for i in 1:length(X)
        X[i] = rand(s)
    end
    return X
end
rand!(s::Sampleable{Matrixvariate}, X::AbstractArray{M}) where {M<:Matrix} =
    _rand!(s, X)
rand(s::Sampleable{Matrixvariate}, n::Int) =
    rand!(s, Vector{Matrix{eltype(s)}}(n))
""" """ sampler(d::Distribution) = d
