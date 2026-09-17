# This file is a part of Julia. License is MIT: https://julialang.org/license

using Test
using Distributed

@testset "Joolia zero-origin Distributed helpers" begin
    head, tail = Distributed.head_and_tail([10, 20, 30], 2)
    @test firstindex(head) == 0 && head == [10, 20]
    @test collect(tail) == [30]
    empty_head, empty_tail = Distributed.head_and_tail(Int[], 2)
    @test isempty(empty_head) && isempty(collect(empty_tail))
    @test Distributed.parse_machine("127.0.0.1:80") == ("127.0.0.1", 80)
    @test Distributed.parse_connection_info("julia_worker:123#127.0.0.1") == ("127.0.0.1", UInt16(123))
    @test length(Distributed.msgtypes) == 9
    io = IOBuffer()
    serializer = Distributed.ClusterSerializer(io)
    Distributed.serialize_msg(serializer, Distributed.IdentifySocketAckMsg())
    @test io.data[0] == 2
    seekstart(io)
    @test Distributed.deserialize_msg(serializer) isa Distributed.IdentifySocketAckMsg
end

# only run these if Aqua is installed. i.e. Pkg.test has installed it, or it is provided as a shared package
if Base.locate_package(Base.PkgId(Base.UUID("4c88cf16-eb10-579e-8560-4a9242c79595"), "Aqua")) isa String
    @testset "Aqua.jl tests" begin
        include("aqua.jl")
    end
end

# Run the distributed test outside of the main driver since it needs its own
# set of dedicated workers.
include(joinpath(Sys.BINDIR, "..", "share", "julia", "test", "testenv.jl"))
disttestfile = joinpath(@__DIR__, "distributed_exec.jl")

@testset let cmd = `$test_exename $test_exeflags $disttestfile`
    @test success(pipeline(cmd; stdout=stdout, stderr=stderr)) && ccall(:jl_running_on_valgrind,Cint,()) == 0
end

include("managers.jl")
