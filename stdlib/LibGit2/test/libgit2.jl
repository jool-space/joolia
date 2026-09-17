# This file is a part of Julia. License is MIT: https://julialang.org/license

# Set HOME to control where the .gitconfig file may be found.
# Note: In Cygwin environments `git` will use HOME instead of USERPROFILE.
# Setting both environment variables ensures home was overridden.
mktempdir() do dir
    dir = realpath(dir)
    withenv("HOME" => dir, "USERPROFILE" => dir) do
        include("libgit2-tests.jl")
    end
end

# Generated constructors accept an ownerless native config pointer and close it safely.
@testset "zero-origin optional Git owner" begin
    @test hasmethod(LibGit2.GitConfig, Tuple{Ptr{Cvoid}})
    config = LibGit2.GitConfig()
    try
        @test config.owner === nothing
        @test !isempty(config)
    finally
        close(config)
    end
    @test isempty(config)
end
