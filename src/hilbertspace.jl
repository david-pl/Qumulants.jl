abstract type HilbertSpace end
Base.:(==)(h1::HilbertSpace,h2::HilbertSpace) = false

struct ProductSpace{S} <: HilbertSpace
    spaces::S
end
Base.:(==)(h1::T,h2::T) where T<:ProductSpace = h1.spaces==h2.spaces
⊗(a::HilbertSpace,b::HilbertSpace) = ProductSpace([a,b])
⊗(a::HilbertSpace,b::ProductSpace) = ProductSpace([a;b.spaces])
⊗(a::ProductSpace,b::HilbertSpace) = ProductSpace([a.spaces;b])
⊗(a::ProductSpace,b::ProductSpace) = ProductSpace([a.spaces;b.spaces])

Base.isless(h1::HilbertSpace,h2::HilbertSpace) = isless(h1.name,h2.name)
Base.isless(h1::ProductSpace,h2::ProductSpace) = isless(h1.spaces,h2.spaces)
