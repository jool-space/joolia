# This file is a part of Julia. License is MIT: https://julialang.org/license

# Factorials

const _fact_table64 = let _fact_table64 = Vector{Int64}(undef, 21)
    _fact_table64[0] = 1
    for n in 1:20
        _fact_table64[n] = _fact_table64[n-1] * n
    end
    Tuple(_fact_table64)
end

const _fact_table128 = let _fact_table128 = Vector{UInt128}(undef, 35)
    _fact_table128[0] = 1
    for n in 1:34
        _fact_table128[n] = _fact_table128[n-1] * n
    end
    Tuple(_fact_table128)
end

function factorial_lookup(
    n::Union{Checked.SignedInt,Checked.UnsignedInt},
    table::Union{NTuple{21,Int64},NTuple{35,UInt128}}, lim::Int)
    idx = Int(n)
    idx < 0 && throw(DomainError(n, "`n` must not be negative."))
    idx > lim && throw(OverflowError(lazy"$n is too large to look up in the table; consider using `factorial(big($n))` instead"))
    idx == 0 && return one(n)
    f = getfield(table, idx)
    return oftype(n, f)
end

factorial(n::Int128) = factorial_lookup(n, _fact_table128, 33)
factorial(n::UInt128) = factorial_lookup(n, _fact_table128, 34)
factorial(n::Union{Int64,UInt64}) = factorial_lookup(n, _fact_table64, 20)

if Int === Int32
    factorial(n::Union{Int8,UInt8,Int16,UInt16}) = factorial(Int32(n))
    factorial(n::Union{Int32,UInt32}) = factorial_lookup(n, _fact_table64, 12)
else
    factorial(n::Union{Int8,UInt8,Int16,UInt16,Int32,UInt32}) = factorial(Int64(n))
end


# Basic functions for working with permutations

@inline function _foldoneto(op, acc, ::Val{N}) where N
    @assert N::Integer >= 0 "N must be non-negative"
    if @generated
        quote
            acc_0 = acc
            # Cartesian's generated callback variables are zero-origin, while
            # this private fold's callback deliberately receives 1:N.
            Base.Cartesian.@nexprs $N i -> acc_{i+1} = op(acc_i, i+1)
            return $(Symbol(:acc_, N))
        end
    else
        for i in 1:N
            acc = op(acc, i)
        end
        return acc
    end
end

"""
    isperm(v)::Bool

Return `true` if `v` is a valid permutation.

# Examples
```jldoctest
julia> isperm([0; 1])
true

julia> isperm([0; 2])
false
```
"""
isperm(A) = _isperm(A)

function _isperm(A)
    n = length(A)
    used = falses(n)
    for a in A
        (0 <= a < n) && (used[a] ⊻= true) || return false
    end
    true
end

isperm(p::Tuple{}) = true
isperm(p::Tuple{Int}) = p[0] == 0
isperm(p::Tuple{Int,Int}) = ((p[0] == 0) & (p[1] == 1)) | ((p[0] == 1) & (p[1] == 0))

function isperm(P::Tuple)
    valn = Val(length(P))
    _foldoneto(true, valn) do b,i
        s = _foldoneto(false, valn) do s, j
            s || P[j-1]==i-1
        end
        b&s
    end
end

isperm(P::Any32) = _isperm(P)

# swap columns i and j of a, in-place
function swapcols!(a::AbstractMatrix, i, j)
    i == j && return
    cols = axes(a,1)
    @boundscheck i in cols || throw(BoundsError(a, (:,i)))
    @boundscheck j in cols || throw(BoundsError(a, (:,j)))
    for k in axes(a,0)
        @inbounds a[k,i],a[k,j] = a[k,j],a[k,i]
    end
end

# swap rows i and j of a, in-place
function swaprows!(a::AbstractMatrix, i, j)
    i == j && return
    rows = axes(a,0)
    @boundscheck i in rows || throw(BoundsError(a, (:,i)))
    @boundscheck j in rows || throw(BoundsError(a, (:,j)))
    for k in axes(a,1)
        @inbounds a[i,k],a[j,k] = a[j,k],a[i,k]
    end
end

# like permute!! applied to each column of a, in-place in a (overwriting p).
function permutecols!!(a::AbstractMatrix, p::AbstractVector{<:Integer})
    require_zero_based_indexing(a, p)
    # Zero is a valid permutation value, so track visited positions separately
    # instead of using a value sentinel. This also supports UInt8 permutations
    # of length 256 without negation or overflow.
    visited = falses(length(p))
    for start in eachindex(p)
        visited[start] && continue
        ptr = start
        next = p[ptr]
        while next != start
            swapcols!(a, ptr, next)
            visited[ptr] = true
            ptr = next
            next = p[ptr]
        end
        visited[ptr] = true
    end
    fill!(p, zero(eltype(p)))
    a
end

# Row and column permutations for AbstractMatrix
permutecols!(a::AbstractMatrix, p::AbstractVector{<:Integer}) =
    _permute!(a, p, Base.swapcols!)
permuterows!(a::AbstractMatrix, p::AbstractVector{<:Integer}) =
    _permute!(a, p, Base.swaprows!)
@inline function _permute!(a::AbstractMatrix, p::AbstractVector{<:Integer}, swapfun!::F) where {F}
    require_zero_based_indexing(a, p)
    visited = falses(length(p))
    for i in eachindex(p)
        visited[i] && continue
        j = i
        next = p[j]
        while next != i
            swapfun!(a, next, j)
            visited[j] = true
            j = next
            next = p[j]
        end
        visited[j] = true
    end
    a
end
invpermutecols!(a::AbstractMatrix, p::AbstractVector{<:Integer}) =
    _invpermute!(a, p, Base.swapcols!)
invpermuterows!(a::AbstractMatrix, p::AbstractVector{<:Integer}) =
    _invpermute!(a, p, Base.swaprows!)
@inline function _invpermute!(a::AbstractMatrix, p::AbstractVector{<:Integer}, swapfun!::F) where {F}
    require_zero_based_indexing(a, p)
    visited = falses(length(p))
    for i in eachindex(p)
        visited[i] && continue
        j = p[i]
        while j != i
            swapfun!(a, j, i)
            visited[j] = true
            j = p[j]
        end
        visited[i] = true
    end
    a
end

"""
    permute!(v, p)

Permute vector `v` according to permutation `p`, storing the result back into `v`.
No checking is done to verify that `p` is a permutation.

To return a new permutation, use `v[p]`. This is generally faster than `permute!(v, p)`;
it is even faster to write into a pre-allocated output array with `u .= @view v[p]`.
(Even though `permute!` overwrites `v` in-place, it internally requires some allocation.)

$(_DOCS_ALIASING_WARNING)

See also [`invpermute!`](@ref).

# Examples
```jldoctest
julia> A = [1, 1, 3, 4];

julia> perm = [1, 3, 2, 0];

julia> permute!(A, perm);

julia> A
4-element Vector{Int64}:
 1
 4
 3
 1
```
"""
permute!(v, p::AbstractVector) = (require_zero_based_indexing(v, p); v .= v[p])

"""
    invpermute!(v, p)

Like [`permute!`](@ref), but the inverse of the given permutation is applied.

Note that if you have a pre-allocated output array (e.g. `u = similar(v)`),
it is quicker to instead employ `u[p] = v`.  (`invpermute!` internally
allocates a copy of the data.)

$(_DOCS_ALIASING_WARNING)

# Examples
```jldoctest
julia> A = [1, 1, 3, 4];

julia> perm = [1, 3, 2, 0];

julia> invpermute!(A, perm);

julia> A
4-element Vector{Int64}:
 4
 1
 3
 1
```
"""
invpermute!(v, p::AbstractVector) = (require_zero_based_indexing(v, p); v[p] = v; v)

"""
    invperm(v)

Return the inverse permutation of `v`.
If `B = A[v]`, then `A == B[invperm(v)]`.

See also [`sortperm`](@ref), [`invpermute!`](@ref), [`isperm`](@ref), [`permutedims`](@ref).

# Examples
```jldoctest
julia> p = (1, 2, 0);

julia> invperm(p)
(2, 0, 1)

julia> v = [3; 0; 2; 1];

julia> invperm(v)
4-element Vector{Int64}:
 1
 3
 2
 0

julia> A = ['a','b','c','d'];

julia> B = A[v]
4-element Vector{Char}:
 'd': ASCII/Unicode U+0064 (category Ll: Letter, lowercase)
 'a': ASCII/Unicode U+0061 (category Ll: Letter, lowercase)
 'c': ASCII/Unicode U+0063 (category Ll: Letter, lowercase)
 'b': ASCII/Unicode U+0062 (category Ll: Letter, lowercase)

julia> B[invperm(v)]
4-element Vector{Char}:
 'a': ASCII/Unicode U+0061 (category Ll: Letter, lowercase)
 'b': ASCII/Unicode U+0062 (category Ll: Letter, lowercase)
 'c': ASCII/Unicode U+0063 (category Ll: Letter, lowercase)
 'd': ASCII/Unicode U+0064 (category Ll: Letter, lowercase)
```
"""
function invperm(a::AbstractVector)
    require_zero_based_indexing(a)
    b = similar(a)
    n = length(a)
    used = falses(n)
    @inbounds for (i, j) in enumerate(a)
        ((0 <= j < n) && !used[j]) ||
            throw(ArgumentError("argument is not a permutation"))
        used[j] = true
        b[j] = i
    end
    b
end

function invperm(p::Union{Tuple{},Tuple{Int},Tuple{Int,Int}})
    isperm(p) || throw(ArgumentError("argument is not a permutation"))
    p  # in dimensions 0-2, every permutation is its own inverse
end

function invperm(P::Tuple)
    valn = Val(length(P))
    ntuple(valn) do i
        s = _foldoneto(nothing, valn) do s, j
            s !== nothing && return s
            P[j-1]==i && return j-1
            nothing
        end
        s === nothing && throw(ArgumentError("argument is not a permutation"))
        s
    end
end

invperm(P::Any32) = Tuple(invperm(collect(P)))

#XXX This function should be moved to Combinatorics.jl but is currently used by Base.DSP.
"""
    nextprod(factors::Union{Tuple,AbstractVector}, n)

Next integer greater than or equal to `n` that can be written as ``\\prod k_i^{p_i}`` for integers
``p_1``, ``p_2``, etcetera, for factors ``k_i`` in `factors`.

# Examples
```jldoctest
julia> nextprod((2, 3), 105)
108

julia> 2^2 * 3^3
108
```

!!! compat "Julia 1.6"
    The method that accepts a tuple requires Julia 1.6 or later.
"""
function nextprod(a::Union{Tuple{Vararg{Integer}},AbstractVector{<:Integer}}, x::Real)
    if x > typemax(Int)
        throw(ArgumentError("unsafe for x > typemax(Int), got $x"))
    end
    k = length(a)
    v = fill(1, k)                    # current value of each counter
    mx = map(a -> nextpow(a,x), a)   # maximum value of each counter
    v[0] = mx[0]                      # start at first case that is >= x
    p::widen(Int) = mx[0]             # initial value of product in this case
    best = p
    icarry = 0

    while v[k-1] < mx[k-1]
        if p >= x
            best = p < best ? p : best  # keep the best found yet
            carrytest = true
            while carrytest
                p = div(p, v[icarry])
                v[icarry] = 1
                icarry += 1
                p *= a[icarry]
                v[icarry] *= a[icarry]
                carrytest = v[icarry] > mx[icarry] && icarry < k-1
            end
            if p < x
                icarry = 0
            end
        else
            while p < x
                p *= a[0]
                v[0] *= a[0]
            end
        end
    end
    # might overflow, but want predictable return type
    return mx[k-1] < best ? Int(mx[k-1]) : Int(best)
end
