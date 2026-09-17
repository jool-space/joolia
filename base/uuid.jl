# This file is a part of Julia. License is MIT: https://julialang.org/license

"""
Represents a Universally Unique Identifier (UUID).
Can be built from one `UInt128` (all byte values), two `UInt64`, or four `UInt32`.
Conversion from a string will check the UUID validity.
"""
struct UUID
    value::UInt128
end
UUID(u::UUID) = u
UUID(u::NTuple{2, UInt64}) = UUID((UInt128(u[0]) << 64) | UInt128(u[1]))
UUID(u::NTuple{4, UInt32}) = UUID((UInt128(u[0]) << 96) | (UInt128(u[1]) << 64) |
                                  (UInt128(u[2]) << 32) | UInt128(u[3]))

function convert(::Type{NTuple{2, UInt64}}, uuid::UUID)
    bytes = uuid.value
    hi = UInt64((bytes >> 64) & 0xffffffffffffffff)
    lo = UInt64(bytes & 0xffffffffffffffff)
    return (hi, lo)
end

function convert(::Type{NTuple{4, UInt32}}, uuid::UUID)
    bytes = uuid.value
    hh = UInt32((bytes >> 96) & 0xffffffff)
    hl = UInt32((bytes >> 64) & 0xffffffff)
    lh = UInt32((bytes >> 32) & 0xffffffff)
    ll = UInt32(bytes & 0xffffffff)
    return (hh, hl, lh, ll)
end

UInt128(u::UUID) = u.value

let
    uuid_hash_seed = UInt === UInt64 ? 0xd06fa04f86f11b53 : 0x96a1f36d
    Base.hash(uuid::UUID, h::UInt) = hash(uuid_hash_seed, hash(convert(NTuple{2, UInt64}, uuid), h))
end

_crc32c(uuid::UUID, crc::UInt32=0x00000000) = _crc32c(uuid.value, crc)

let
@inline function uuid_kernel(s, i, u)
    _c = UInt32(@inbounds codeunit(s, i))
    d = __convert_digit(_c, UInt32(16))
    d >= 16 && return nothing
    u <<= 4
    return u | d
end

function Base.tryparse(::Type{UUID}, s::AbstractString)
    u = UInt128(0)
    ncodeunits(s) != 36 && return nothing
    for i in 0:7
        u = uuid_kernel(s, i, u)
        u === nothing && return nothing
    end
    @inbounds codeunit(s, 8) == UInt8('-') || return nothing
    for i in 9:12
        u = uuid_kernel(s, i, u)
        u === nothing && return nothing
    end
    @inbounds codeunit(s, 13) == UInt8('-') || return nothing
    for i in 14:17
        u = uuid_kernel(s, i, u)
        u === nothing && return nothing
    end
    @inbounds codeunit(s, 18) == UInt8('-') || return nothing
    for i in 19:22
        u = uuid_kernel(s, i, u)
        u === nothing && return nothing
    end
    @inbounds codeunit(s, 23) == UInt8('-') || return nothing
    for i in 24:35
        u = uuid_kernel(s, i, u)
        u === nothing && return nothing
    end
    return Base.UUID(u)
end
end

let
    @noinline throw_malformed_uuid(s) = throw(ArgumentError("Malformed UUID string: $(repr(s))"))
    function Base.parse(::Type{UUID}, s::AbstractString)
        uuid = tryparse(UUID, s)
        return uuid === nothing ? throw_malformed_uuid(s) : uuid
    end
end

UUID(s::AbstractString) = parse(UUID, s)

let groupings = [35:-1:24; 22:-1:19; 17:-1:14; 12:-1:9; 7:-1:0]
    global string
    function string(u::UUID)
        u = u.value
        str = Base._string_n(36)
        GC.@preserve str begin
            p = pointer(str)
            for i in groupings
                unsafe_store!(p, @inbounds(hex_chars[u & 0xf]), i)
                u >>= 4
            end
            unsafe_store!(p, UInt8('-'), 8)
            unsafe_store!(p, UInt8('-'), 13)
            unsafe_store!(p, UInt8('-'), 18)
            unsafe_store!(p, UInt8('-'), 23)
        end
        return str
    end
end

print(io::IO, u::UUID) = print(io, string(u))
show(io::IO, u::UUID) = print(io, UUID, "(\"", u, "\")")

isless(a::UUID, b::UUID) = isless(a.value, b.value)

# give UUID scalar behavior in broadcasting
Base.broadcastable(x::UUID) = Ref(x)
