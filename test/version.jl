# This file is a part of Julia. License is MIT: https://julialang.org/license

using Random

# Version components use zero-origin positions without changing numeric version ordering.
@testset "zero-origin version positions" begin
    b = Base.VersionBound("v1.2.3")
    @test b.t == (1, 2, 3)
    @test b[0] == 1
    @test b[2] == 3
    @test Base.VersionBound("*").n == 0
    v = VersionNumber("1.2.3-rc.4+build.5")
    @test v.prerelease == ("rc", UInt64(4))
    @test v.build == ("build", UInt64(5))
    @test Base.issupbuild(VersionNumber("1.2+"))
    r = Base.VersionRange("1 - 2")
    @test VersionNumber("1.0") in r
    @test VersionNumber("2.9") in r
    @test !(VersionNumber("3.0") in r)
    spec = Base.VersionSpec(["1", "2"])
    @test length(spec.ranges) == 1
    @test spec.ranges[0].upper[0] == 2
    dest = trues(5)
    Base.matches_spec_range!(dest, VersionNumber[VersionNumber("1"), VersionNumber("2"), VersionNumber("3")], Base.VersionSpec("2"), 3)
    @test dest == [false, true, false, true, true]
    @test VersionNumber("1.9") in Base.semver_spec("^1.2")
    @test !(VersionNumber("2.0") in Base.semver_spec("^1.2"))
    @test VersionNumber("0.2.5") in Base.semver_spec("~0.2.1")
    @test !(VersionNumber("0.3") in Base.semver_spec("~0.2.1"))
end

# parsing tests
@test v"2" == VersionNumber(2)
@test v"3.2" == VersionNumber(3, 2)
@test v"4.3.2" == VersionNumber(4, 3, 2)

@test v"2-" == VersionNumber(2, 0, 0, ("",), ())
@test v"3.2-" == VersionNumber(3, 2, 0, ("",), ())
@test v"4.3.2-" == VersionNumber(4, 3, 2, ("",), ())

@test v"2-1" == VersionNumber(2, 0, 0, (1,), ())
@test v"3.2-1" == VersionNumber(3, 2, 0, (1,), ())
@test v"4.3.2-1" == VersionNumber(4, 3, 2, (1,), ())

@test v"2-a" == VersionNumber(2, 0, 0, ("a",), ()) == v"2a"
@test v"3.2-a" == VersionNumber(3, 2, 0, ("a",), ()) == v"3.2a"
@test v"4.3.2-a" == VersionNumber(4, 3, 2, ("a",), ()) == v"4.3.2a"

@test v"2-a1" == VersionNumber(2, 0, 0, ("a1",), ()) == v"2a1"
@test v"3.2-a1" == VersionNumber(3, 2, 0, ("a1",), ()) == v"3.2a1"
@test v"4.3.2-a1" == VersionNumber(4, 3, 2, ("a1",), ()) == v"4.3.2a1"

@test v"2-1a" == VersionNumber(2, 0, 0, ("1a",), ())
@test v"3.2-1a" == VersionNumber(3, 2, 0, ("1a",), ())
@test v"4.3.2-1a" == VersionNumber(4, 3, 2, ("1a",), ())

@test v"2-a.1" == VersionNumber(2, 0, 0, ("a", 1), ()) == v"2a.1"
@test v"3.2-a.1" == VersionNumber(3, 2, 0, ("a", 1), ()) == v"3.2a.1"
@test v"4.3.2-a.1" == VersionNumber(4, 3, 2, ("a", 1), ()) == v"4.3.2a.1"

@test v"2-1.a" == VersionNumber(2, 0, 0, (1, "a"), ())
@test v"3.2-1.a" == VersionNumber(3, 2, 0, (1, "a"), ())
@test v"4.3.2-1.a" == VersionNumber(4, 3, 2, (1, "a"), ())

@test v"2+" == VersionNumber(2, 0, 0, (), ("",))
@test v"3.2+" == VersionNumber(3, 2, 0, (), ("",))
@test v"4.3.2+" == VersionNumber(4, 3, 2, (), ("",))

@test v"2+1" == VersionNumber(2, 0, 0, (), (1,))
@test v"3.2+1" == VersionNumber(3, 2, 0, (), (1,))
@test v"4.3.2+1" == VersionNumber(4, 3, 2, (), (1,))

@test v"2+a" == VersionNumber(2, 0, 0, (), ("a",))
@test v"3.2+a" == VersionNumber(3, 2, 0, (), ("a",))
@test v"4.3.2+a" == VersionNumber(4, 3, 2, (), ("a",))

@test v"2+a1" == VersionNumber(2, 0, 0, (), ("a1",))
@test v"3.2+a1" == VersionNumber(3, 2, 0, (), ("a1",))
@test v"4.3.2+a1" == VersionNumber(4, 3, 2, (), ("a1",))

@test v"2+1a" == VersionNumber(2, 0, 0, (), ("1a",))
@test v"3.2+1a" == VersionNumber(3, 2, 0, (), ("1a",))
@test v"4.3.2+1a" == VersionNumber(4, 3, 2, (), ("1a",))

@test v"2+a.1" == VersionNumber(2, 0, 0, (), ("a", 1))
@test v"3.2+a.1" == VersionNumber(3, 2, 0, (), ("a", 1))
@test v"4.3.2+a.1" == VersionNumber(4, 3, 2, (), ("a", 1))

@test v"2+1.a" == VersionNumber(2, 0, 0, (), (1, "a"))
@test v"3.2+1.a" == VersionNumber(3, 2, 0, (), (1, "a"))
@test v"4.3.2+1.a" == VersionNumber(4, 3, 2, (), (1, "a"))

# ArgumentErrors in constructor
@test_throws ArgumentError VersionNumber(4, 3, 2, ("nonalphanumeric!",), ())
@test_throws ArgumentError VersionNumber(4, 3, 2, ("nonalphanumeric!", 1), ())
@test_throws ArgumentError VersionNumber(4, 3, 2, (1, "nonalphanumeric!"), ())

@test_throws ArgumentError VersionNumber(4, 3, 2, ("", 1), ())
@test_throws ArgumentError VersionNumber(4, 3, 2, (1, ""), ())
@test_throws ArgumentError VersionNumber(4, 3, 2, ("",), ("",))
@test_throws ArgumentError VersionNumber(4, 3, 2, ("",), ("nonempty", 1))

@test_throws ArgumentError VersionNumber(4, 3, 2, (), ("nonalphanumeric!",))
@test_throws ArgumentError VersionNumber(4, 3, 2, (), ("nonalphanumeric!", 1))
@test_throws ArgumentError VersionNumber(4, 3, 2, (), (1, "nonalphanumeric!"))

@test_throws ArgumentError VersionNumber(4, 3, 2, (), ("", 1))

# parse()/tryparse()
@test parse(VersionNumber, "1.2.3") == v"1.2.3"
@test_throws ArgumentError parse(VersionNumber, "not a version")
@test tryparse(VersionNumber, "3.2.1") == v"3.2.1"
@test tryparse(VersionNumber, "not a version") === nothing

# show
io = IOBuffer()
show(io,v"4.3.2+1.a")
@test length(String(take!(io))) == 12

# construction from Int
@test VersionNumber(2) == v"2.0.0"

# construction from Tuple
@test VersionNumber((2,)) == v"2.0.0"
@test VersionNumber((3, 2)) == v"3.2.0"

# construction from AbstractString
@test VersionNumber("4.3.2+1.a") == v"4.3.2+1.a"

# construct from VersionNumber
let
    v = VersionNumber("1.2.3")
    @test VersionNumber(v) == v
end

# typemin and typemax
@test typemin(VersionNumber) == v"0-"
@test typemax(VersionNumber) == v"∞"
let ∞ = typemax(UInt32)
    @test typemin(VersionNumber) == VersionNumber(0, 0, 0, ("",), ())
    @test typemax(VersionNumber) == VersionNumber(∞, ∞, ∞, (), ("",))
end

# issupbuild
import Base.issupbuild
@test issupbuild(v"4.3.2+")
@test ~issupbuild(v"4.3.2")
@test ~issupbuild(v"4.3.2-")
@test ~issupbuild(v"4.3.2-a")
@test ~issupbuild(v"4.3.2-a1")
@test ~issupbuild(v"4.3.2-1")
@test ~issupbuild(v"4.3.2-a.1")
@test ~issupbuild(v"4.3.2-1a")
@test ~issupbuild(v"4.3.2+a")
@test ~issupbuild(v"4.3.2+a1")
@test ~issupbuild(v"4.3.2+1")
@test ~issupbuild(v"4.3.2+a.1")
@test ~issupbuild(v"4.3.2+1a")

# basic comparison
VersionNumber(2, 3, 1) == VersionNumber(Int8(2), UInt32(3), Int32(1)) == v"2.3.1"
@test v"2.3.0" < v"2.3.1" < v"2.4.8" < v"3.7.2"
@test v"0.6.0-" < v"0.6.0-dev" < v"0.6.0-dev.123" < v"0.6.0-dev.unknown" < v"0.6.0-pre" < v"0.6.0"

#lowerbound and upperbound
import Base: lowerbound, upperbound
@test lowerbound(v"4.3.2") == v"4.3.2-"
@test lowerbound(v"4.3.2-") == v"4.3.2-"
@test lowerbound(v"4.3.2+") == v"4.3.2-"
@test upperbound(v"4.3.2") == v"4.3.2+"
@test upperbound(v"4.3.2-") == v"4.3.2+"
@test upperbound(v"4.3.2+") == v"4.3.2+"

# advanced comparison & manipulation
import Base: thispatch, thisminor, thismajor,
             nextpatch, nextminor, nextmajor
@test v"1.2.3" == thispatch(v"1.2.3-")
@test v"1.2.3" == thispatch(v"1.2.3-pre")
@test v"1.2.3" == thispatch(v"1.2.3")
@test v"1.2.3" == thispatch(v"1.2.3+post")
@test v"1.2.3" == thispatch(v"1.2.3+")

@test v"1.2" == thisminor(v"1.2.3-")
@test v"1.2" == thisminor(v"1.2.3-pre")
@test v"1.2" == thisminor(v"1.2.3")
@test v"1.2" == thisminor(v"1.2.3+post")
@test v"1.2" == thisminor(v"1.2.3+")

@test v"1" == thismajor(v"1.2.3-")
@test v"1" == thismajor(v"1.2.3-pre")
@test v"1" == thismajor(v"1.2.3")
@test v"1" == thismajor(v"1.2.3+post")
@test v"1" == thismajor(v"1.2.3+")

@test v"1.2.3" == nextpatch(v"1.2.3-")
@test v"1.2.3" == nextpatch(v"1.2.3-pre")
@test v"1.2.4" == nextpatch(v"1.2.3")
@test v"1.2.4" == nextpatch(v"1.2.3+post")
@test v"1.2.4" == nextpatch(v"1.2.3+")

@test v"1.2" == nextminor(v"1.2-")
@test v"1.2" == nextminor(v"1.2-pre")
@test v"1.3" == nextminor(v"1.2")
@test v"1.3" == nextminor(v"1.2+post")
@test v"1.3" == nextminor(v"1.2+")

@test v"1.3" == nextminor(v"1.2.3-")
@test v"1.3" == nextminor(v"1.2.3-pre")
@test v"1.3" == nextminor(v"1.2.3")
@test v"1.3" == nextminor(v"1.2.3+post")
@test v"1.3" == nextminor(v"1.2.3+")

@test v"1" == nextmajor(v"1-")
@test v"1" == nextmajor(v"1-pre")
@test v"2" == nextmajor(v"1")
@test v"2" == nextmajor(v"1+post")
@test v"2" == nextmajor(v"1+")

@test v"2" == nextmajor(v"1.2-")
@test v"2" == nextmajor(v"1.2-pre")
@test v"2" == nextmajor(v"1.2")
@test v"2" == nextmajor(v"1.2+post")
@test v"2" == nextmajor(v"1.2+")

@test v"2" == nextmajor(v"1.2.3-")
@test v"2" == nextmajor(v"1.2.3-pre")
@test v"2" == nextmajor(v"1.2.3")
@test v"2" == nextmajor(v"1.2.3+post")
@test v"2" == nextmajor(v"1.2.3+")

for major=0:3, minor=0:3, patch=0:3
    a = VersionNumber(major,minor,patch,("",),())
    b = VersionNumber(major,minor,patch,("pre",),())
    c = VersionNumber(major,minor,patch,(),())
    d = VersionNumber(major,minor,patch,(),("post",))
    e = VersionNumber(major,minor,patch,(),("",))
    @test a < b < c < d < e
    for x in [a,b,c,d,e]
        @test thispatch(x) == VersionNumber(major,minor,patch)
        @test thisminor(x) == VersionNumber(major,minor,0)
        @test thismajor(x) == VersionNumber(major,0,0)
        @test x < nextpatch(x) <= nextminor(x) <= nextmajor(x)
        @test x < thispatch(x) ? nextpatch(x) == thispatch(x) : thispatch(x) < nextpatch(x)
        @test x < thisminor(x) ? nextminor(x) == thisminor(x) : thisminor(x) < nextminor(x)
        @test x < thismajor(x) ? nextmajor(x) == thismajor(x) : thismajor(x) < nextmajor(x)
    end
end

# VersionNumber has the promised fields
let v = v"4.2.1-1.x+a.9"
    @test v.major isa Integer
    @test v.minor isa Integer
    @test v.patch isa Integer
    @test v.prerelease isa Tuple{Vararg{Union{Integer, AbstractString}}}
    @test v.build isa Tuple{Vararg{Union{Integer, AbstractString}}}
end

# julia_version.h version test
@test VERSION.major == ccall(:jl_ver_major, Cint, ())
@test VERSION.minor == ccall(:jl_ver_minor, Cint, ())
@test VERSION.patch == ccall(:jl_ver_patch, Cint, ())

# test construction with non-Int and non-String components
@test_throws MethodError VersionNumber()
@test VersionNumber(true) == v"1"
@test VersionNumber(true, 0x2) == v"1.2"
@test VersionNumber(true, 0x2, Int128(3)) == v"1.2.3"
@test VersionNumber(true, 0x2, Int128(3)) == v"1.2.3"
@test VersionNumber(true, 0x2, Int128(3), (GenericString("rc"), 0x1)) == v"1.2.3-rc.1"
@test VersionNumber(true, 0x2, Int128(3), (GenericString("rc"), 0x1)) == v"1.2.3-rc.1"
@test VersionNumber(true, 0x2, Int128(3), (), (GenericString("sp"), 0x2)) == v"1.2.3+sp.2"
