abstract type AbstractMixtureModel{VF<:VariateForm,VS<:ValueSupport,C<:Distribution} <: Distribution{VF, VS} end
struct MixtureModel{VF<:VariateForm,VS<:ValueSupport,C<:Distribution} <: AbstractMixtureModel{VF,VS,C}
    components::Vector{C}
    prior::Categorical
    function MixtureModel{VF,VS,C}(cs::Vector{C}, pri::Categorical) where {VF,VS,C}
        length(cs) == ncategories(pri) ||
            error("The number of components does not match the length of prior.")
        new{VF,VS,C}(cs, pri)
    end
end
const UnivariateMixture{S<:ValueSupport,   C<:Distribution} = AbstractMixtureModel{Univariate,S,C}
const MultivariateMixture{S<:ValueSupport, C<:Distribution} = AbstractMixtureModel{Multivariate,S,C}
const MatrixvariateMixture{S<:ValueSupport,C<:Distribution} = AbstractMixtureModel{Matrixvariate,S,C}
""" """ component_type(d::AbstractMixtureModel{VF,VS,C}) where {VF,VS,C} = C
""" """ components(d::AbstractMixtureModel)
""" """ probs(d::AbstractMixtureModel)
""" """ mean(d::AbstractMixtureModel)
""" """ insupport(d::AbstractMixtureModel, x::AbstractVector)
""" """ pdf(d::AbstractMixtureModel, x::Any)
""" """ logpdf(d::AbstractMixtureModel, x::Any)
""" """ rand(d::AbstractMixtureModel)
""" """ rand!(d::AbstractMixtureModel, r::AbstractArray)
""" """ MixtureModel(components::Vector{C}) where {C<:Distribution} =
    MixtureModel(components, Categorical(length(components)))
""" """ function MixtureModel(::Type{C}, params::AbstractArray) where C<:Distribution
    components = C[_construct_component(C, a) for a in params]
    MixtureModel(components)
end
function MixtureModel(components::Vector{C}, prior::Categorical) where C<:Distribution
    VF = variate_form(C)
    VS = value_support(C)
    MixtureModel{VF,VS,C}(components, prior)
end
MixtureModel(components::Vector{C}, p::Vector{Float64}) where {C<:Distribution} =
    MixtureModel(components, Categorical(p))
_construct_component(::Type{C}, arg) where {C<:Distribution} = C(arg)
_construct_component(::Type{C}, args::Tuple) where {C<:Distribution} = C(args...)
function MixtureModel(::Type{C}, params::AbstractArray, p::Vector{Float64}) where C<:Distribution
    components = C[_construct_component(C, a) for a in params]
    MixtureModel(components, p)
end
""" """ length(d::MultivariateMixture) = length(d.components[1])
size(d::MatrixvariateMixture) = size(d.components[1])
ncomponents(d::MixtureModel) = length(d.components)
components(d::MixtureModel) = d.components
component(d::MixtureModel, k::Int) = d.components[k]
probs(d::MixtureModel) = probs(d.prior)
params(d::MixtureModel) = ([params(c) for c in d.components], params(d.prior)[1])
partype(d::MixtureModel) = promote_type(partype(d.prior), map(partype, d.components)...)
minimum(d::MixtureModel) = minimum([minimum(dci) for dci in d.components])
maximum(d::MixtureModel) = maximum([maximum(dci) for dci in d.components])
function mean(d::UnivariateMixture)
    K = ncomponents(d)
    p = probs(d)
    m = 0.0
    for i = 1:K
        pi = p[i]
        if pi > 0.0
            c = component(d, i)
            m += mean(c) * pi
        end
    end
    return m
end
function mean(d::MultivariateMixture)
    K = ncomponents(d)
    p = probs(d)
    m = zeros(length(d))
    for i = 1:K
        pi = p[i]
        if pi > 0.0
            c = component(d, i)
            BLAS.axpy!(pi, mean(c), m)
        end
    end
    return m
end
""" """ function var(d::UnivariateMixture)
    K = ncomponents(d)
    p = probs(d)
    means = Vector{Float64}(undef, K)
    m = 0.0
    v = 0.0
    for i = 1:K
        pi = p[i]
        if pi > 0.0
            ci = component(d, i)
            means[i] = mi = mean(ci)
            m += pi * mi
            v += pi * var(ci)
        end
    end
    for i = 1:K
        pi = p[i]
        if pi > 0.0
            v += pi * abs2(means[i] - m)
        end
    end
    return v
end
function cov(d::MultivariateMixture)
    K = ncomponents(d)
    p = probs(d)
    m = zeros(length(d))
    md = zeros(length(d))
    V = zeros(length(d),length(d))
    for i = 1:K
        pi = p[i]
        if pi > 0.0
            c = component(d, i)
            BLAS.axpy!(pi, mean(c), m)
            BLAS.axpy!(pi, cov(c), V)
        end
    end
    for i = 1:K
        pi = p[i]
        if pi > 0.0
            c = component(d, i)
            md = mean(c) - m
            BLAS.axpy!(pi, md*md', V)
        end
    end
    return V
end
function show(io::IO, d::MixtureModel)
    K = ncomponents(d)
    pr = probs(d)
    println(io, "MixtureModel{$(component_type(d))}(K = $K)")
    Ks = min(K, 8)
    for i = 1:Ks
        @printf(io, "components[%d] (prior = %.4f): ", i, pr[i])
        println(io, component(d, i))
    end
    if Ks < K
        println(io, "The rest are omitted ...")
    end
end
function insupport(d::AbstractMixtureModel, x::AbstractVector)
    K = ncomponents(d)
    p = probs(d)
    @assert length(p) == K
    for i = 1:K
        @inbounds pi = p[i]
        if pi > 0.0 && insupport(component(d, i), x)
            return true
        end
    end
    return false
end
function _cdf(d::UnivariateMixture, x::Real)
    K = ncomponents(d)
    p = probs(d)
    @assert length(p) == K
    r = 0.0
    for i = 1:K
        @inbounds pi = p[i]
        if pi > 0.0
            c = component(d, i)
            r += pi * cdf(c, x)
        end
    end
    return r
end
cdf(d::UnivariateMixture{Continuous}, x::Float64) = _cdf(d, x)
cdf(d::UnivariateMixture{Discrete}, x::Int) = _cdf(d, x)
function _mixpdf1(d::AbstractMixtureModel, x)
    K = ncomponents(d)
    p = probs(d)
    @assert length(p) == K
    v = 0.0
    for i = 1:K
        @inbounds pi = p[i]
        if pi > 0.0
            c = component(d, i)
            v += pdf(c, x) * pi
        end
    end
    return v
end
function _mixpdf!(r::AbstractArray, d::AbstractMixtureModel, x)
    K = ncomponents(d)
    p = probs(d)
    @assert length(p) == K
    fill!(r, 0.0)
    t = Array{Float64}(undef, size(r))
    for i = 1:K
        @inbounds pi = p[i]
        if pi > 0.0
            if d isa UnivariateMixture
                t .= pdf.(component(d, i), x)
            else
                pdf!(t, component(d, i), x)
            end
            BLAS.axpy!(pi, t, r)
        end
    end
    return r
end
function _mixlogpdf1(d::AbstractMixtureModel, x)
    K = ncomponents(d)
    p = probs(d)
    @assert length(p) == K
    lp = Vector{Float64}(undef, K)
    m = -Inf   # m <- the maximum of log(p(cs[i], x)) + log(pri[i])
    for i = 1:K
        @inbounds pi = p[i]
        if pi > 0.0
            lp_i = logpdf(component(d, i), x) + log(pi)
            @inbounds lp[i] = lp_i
            if lp_i > m
                m = lp_i
            end
        end
    end
    v = 0.0
    @inbounds for i = 1:K
        if p[i] > 0.0
            v += exp(lp[i] - m)
        end
    end
    return m + log(v)
end
function _mixlogpdf!(r::AbstractArray, d::AbstractMixtureModel, x)
    K = ncomponents(d)
    p = probs(d)
    @assert length(p) == K
    n = length(r)
    Lp = Matrix{Float64}(undef, n, K)
    m = fill(-Inf, n)
    for i = 1:K
        @inbounds pi = p[i]
        if pi > 0.0
            lpri = log(pi)
            lp_i = view(Lp, :, i)
            if d isa UnivariateMixture
                lp_i .= logpdf.(component(d, i), x)
            else
                logpdf!(lp_i, component(d, i), x)
            end
            for j = 1:n
                lp_i[j] += lpri
                if lp_i[j] > m[j]
                    m[j] = lp_i[j]
                end
            end
        end
    end
    fill!(r, 0.0)
    @inbounds for i = 1:K
        if p[i] > 0.0
            lp_i = view(Lp, :, i)
            for j = 1:n
                r[j] += exp(lp_i[j] - m[j])
            end
        end
    end
    @inbounds for j = 1:n
        r[j] = log(r[j]) + m[j]
    end
    return r
end
pdf(d::UnivariateMixture{Continuous}, x::Real) = _mixpdf1(d, x)
pdf(d::UnivariateMixture{Discrete}, x::Int) = _mixpdf1(d, x)
logpdf(d::UnivariateMixture{Continuous}, x::Real) = _mixlogpdf1(d, x)
logpdf(d::UnivariateMixture{Discrete}, x::Int) = _mixlogpdf1(d, x)
_pdf!(r::AbstractArray, d::UnivariateMixture{Discrete}, x::UnitRange) = _mixpdf!(r, d, x)
_pdf!(r::AbstractArray, d::UnivariateMixture, x::AbstractArray) = _mixpdf!(r, d, x)
_logpdf!(r::AbstractArray, d::UnivariateMixture, x::AbstractArray) = _mixlogpdf!(r, d, x)
_pdf(d::MultivariateMixture, x::AbstractVector) = _mixpdf1(d, x)
_logpdf(d::MultivariateMixture, x::AbstractVector) = _mixlogpdf1(d, x)
_pdf!(r::AbstractArray, d::MultivariateMixture, x::AbstractMatrix) = _mixpdf!(r, d, x)
_lodpdf!(r::AbstractArray, d::MultivariateMixture, x::AbstractMatrix) = _mixlogpdf!(r, d, x)
function _cwise_pdf1!(r::AbstractVector, d::AbstractMixtureModel, x)
    K = ncomponents(d)
    length(r) == K || error("The length of r should match the number of components.")
    for i = 1:K
        r[i] = pdf(component(d, i), x)
    end
    r
end
function _cwise_logpdf1!(r::AbstractVector, d::AbstractMixtureModel, x)
    K = ncomponents(d)
    length(r) == K || error("The length of r should match the number of components.")
    for i = 1:K
        r[i] = logpdf(component(d, i), x)
    end
    r
end
function _cwise_pdf!(r::AbstractMatrix, d::AbstractMixtureModel, X)
    K = ncomponents(d)
    n = size(X, ndims(X))
    size(r) == (n, K) || error("The size of r is incorrect.")
    for i = 1:K
        if d isa UnivariateMixture
            view(r,:,i) .= pdf.(Ref(component(d, i)), X)
        else
            pdf!(view(r,:,i),component(d, i), X)
        end
    end
    r
end
function _cwise_logpdf!(r::AbstractMatrix, d::AbstractMixtureModel, X)
    K = ncomponents(d)
    n = size(X, ndims(X))
    size(r) == (n, K) || error("The size of r is incorrect.")
    for i = 1:K
        if d isa UnivariateMixture
            view(r,:,i) .= logpdf.(Ref(component(d, i)), X)
        else
            logpdf!(view(r,:,i), component(d, i), X)            
        end
    end
    r
end
componentwise_pdf!(r::AbstractVector, d::UnivariateMixture, x::Real) = _cwise_pdf1!(r, d, x)
componentwise_pdf!(r::AbstractVector, d::MultivariateMixture, x::AbstractVector) = _cwise_pdf1!(r, d, x)
componentwise_pdf!(r::AbstractMatrix, d::UnivariateMixture, x::AbstractVector) = _cwise_pdf!(r, d, x)
componentwise_pdf!(r::AbstractMatrix, d::MultivariateMixture, x::AbstractMatrix) = _cwise_pdf!(r, d, x)
componentwise_logpdf!(r::AbstractVector, d::UnivariateMixture, x::Real) = _cwise_logpdf1!(r, d, x)
componentwise_logpdf!(r::AbstractVector, d::MultivariateMixture, x::AbstractVector) = _cwise_logpdf1!(r, d, x)
componentwise_logpdf!(r::AbstractMatrix, d::UnivariateMixture, x::AbstractVector) = _cwise_logpdf!(r, d, x)
componentwise_logpdf!(r::AbstractMatrix, d::MultivariateMixture, x::AbstractMatrix) = _cwise_logpdf!(r, d, x)
componentwise_pdf(d::UnivariateMixture, x::Real) = componentwise_pdf!(Vector{Float64}(undef, ncomponents(d)), d, x)
componentwise_pdf(d::UnivariateMixture, x::AbstractVector) = componentwise_pdf!(Matrix{Float64}(undef, length(x), ncomponents(d)), d, x)
componentwise_pdf(d::MultivariateMixture, x::AbstractVector) = componentwise_pdf!(Vector{Float64}(undef, ncomponents(d)), d, x)
componentwise_pdf(d::MultivariateMixture, x::AbstractMatrix) = componentwise_pdf!(Matrix{Float64}(undef, size(x,2), ncomponents(d)), d, x)
componentwise_logpdf(d::UnivariateMixture, x::Real) = componentwise_logpdf!(Vector{Float64}(undef, ncomponents(d)), d, x)
componentwise_logpdf(d::UnivariateMixture, x::AbstractVector) = componentwise_logpdf!(Matrix{Float64}(undef, length(x), ncomponents(d)), d, x)
componentwise_logpdf(d::MultivariateMixture, x::AbstractVector) = componentwise_logpdf!(Vector{Float64}(undef, ncomponents(d)), d, x)
componentwise_logpdf(d::MultivariateMixture, x::AbstractMatrix) = componentwise_logpdf!(Matrix{Float64}(undef, size(x,2), ncomponents(d)), d, x)
struct MixtureSampler{VF,VS,Sampler} <: Sampleable{VF,VS}
    csamplers::Vector{Sampler}
    psampler::AliasTable
end
function MixtureSampler(d::MixtureModel{VF,VS}) where {VF,VS}
    csamplers = map(sampler, d.components)
    psampler = sampler(d.prior)
    MixtureSampler{VF,VS,eltype(csamplers)}(csamplers, psampler)
end
rand(d::MixtureModel) = rand(component(d, rand(d.prior)))
rand(s::MixtureSampler) = rand(s.csamplers[rand(s.psampler)])
_rand!(s::MixtureSampler{Multivariate}, x::AbstractVector) = _rand!(s.csamplers[rand(s.psampler)], x)
sampler(d::MixtureModel) = MixtureSampler(d)