module PkgMisc
using ..Pkg
using Test
using Pkg.Types: PkgError
using UUIDs

# Test workers must inherit allocation tracking without shifting its enum value.
@testset "subprocess allocation tracking" begin
    flags = Pkg.Operations.gen_subprocess_flags(pwd(); coverage=false, julia_args=``)
    child = `$(Base.julia_cmd()) $flags -e 'print(Base.JLOptions().malloc_log)'`
    @test parse(Int, read(child, String)) == Base.JLOptions().malloc_log
end

@testset "inference" begin
    f1() = Pkg.Types.STDLIBS_BY_VERSION
    @inferred f1()
    f2() = Pkg.Types.UNREGISTERED_STDLIBS
    @inferred f2()
end

@testset "hashing" begin
    @test hash(Pkg.Types.Project()) == hash(Pkg.Types.Project())
    @test hash(Pkg.Types.VersionBound()) == hash(Pkg.Types.VersionBound())
    @test hash(Pkg.Resolve.Fixed(VersionNumber(0, 1, 0))) == hash(Pkg.Resolve.Fixed(VersionNumber(0, 1, 0)))

    hash(Pkg.Types.VersionSpec()) # hash isn't stable
    hash(Pkg.Types.PackageEntry()) # hash isn't stable because the internal `repo` field is a mutable struct
end

@testset "safe_realpath" begin
    realpath(Sys.BINDIR) == Pkg.safe_realpath(Sys.BINDIR)
    # issue #3085
    for p in ("", "some-non-existing-path", "some-non-existing-drive:")
        @test p == Pkg.safe_realpath(p)
    end
end

@testset "normalize_path_for_toml" begin
    # Test that relative paths with backslashes are normalized to forward slashes on Windows
    # and left unchanged on other platforms
    if Sys.iswindows()
        @test Pkg.normalize_path_for_toml("foo\\bar\\baz") == "foo/bar/baz"
        @test Pkg.normalize_path_for_toml("..\\parent\\dir") == "../parent/dir"
        @test Pkg.normalize_path_for_toml(".\\current") == "./current"
        # Absolute paths should not be normalized (they're platform-specific)
        @test Pkg.normalize_path_for_toml("C:\\absolute\\path") == "C:\\absolute\\path"
        @test Pkg.normalize_path_for_toml("\\\\network\\share") == "\\\\network\\share"
    else
        # On Unix-like systems, paths should be unchanged
        @test Pkg.normalize_path_for_toml("foo/bar/baz") == "foo/bar/baz"
        @test Pkg.normalize_path_for_toml("../parent/dir") == "../parent/dir"
        @test Pkg.normalize_path_for_toml("./current") == "./current"
        @test Pkg.normalize_path_for_toml("/absolute/path") == "/absolute/path"
    end
end

@test eltype([PackageSpec(a) for a in []]) == PackageSpec

@testset "PackageSpec version default" begin
    # Test that PackageSpec without explicit version gets set to VersionSpec("*")
    # This behavior is relied upon by BinaryBuilderBase.jl for dependency filtering
    # See: https://github.com/JuliaPackaging/BinaryBuilderBase.jl/blob/master/src/Prefix.jl
    ps = PackageSpec(name = "Example")
    @test ps.version == Pkg.Types.VersionSpec("*")

    # Test with UUID as well
    ps_uuid = PackageSpec(name = "Example", uuid = Base.UUID("7876af07-990d-54b4-ab0e-23690620f79a"))
    @test ps_uuid.version == Pkg.Types.VersionSpec("*")

    # Test that explicitly set version is preserved
    ps_versioned = PackageSpec(name = "Example", version = v"1.0.0")
    @test ps_versioned.version == v"1.0.0"

    # Test that explicitly set versionspec (string format) is preserved
    ps_versioned = PackageSpec(name = "Example", version = "1.0.0")
    @test ps_versioned.version == "1.0.0"
end

@testset "semver notation" begin
    @test Pkg.Types.semver_spec("^1.2.3") == Pkg.Types.VersionSpec("1.2.3-1")
    @test Pkg.Types.semver_spec("^1.2") == Pkg.Types.VersionSpec("1.2.0-1")
    @test Pkg.Types.semver_spec("^1") == Pkg.Types.VersionSpec("1.0.0-1")
    @test Pkg.Types.semver_spec("^0.2.3") == Pkg.Types.VersionSpec("0.2.3-0.2")
    @test Pkg.Types.semver_spec("^0.0.3") == Pkg.Types.VersionSpec("0.0.3-0.0.3")
    @test Pkg.Types.semver_spec("^0.0") == Pkg.Types.VersionSpec("0.0.0-0.0")
    @test Pkg.Types.semver_spec("^0") == Pkg.Types.VersionSpec("0.0.0-0")
    @test Pkg.Types.semver_spec("~1.2.3") == Pkg.Types.VersionSpec("1.2.3-1.2")
    @test Pkg.Types.semver_spec("~1.2") == Pkg.Types.VersionSpec("1.2.0-1.2")
    @test Pkg.Types.semver_spec("~1") == Pkg.Types.VersionSpec("1.0.0-1")
    @test Pkg.Types.semver_spec("1.2.3") == Pkg.Types.semver_spec("^1.2.3")
    @test Pkg.Types.semver_spec("1.2") == Pkg.Types.semver_spec("^1.2")
    @test Pkg.Types.semver_spec("1") == Pkg.Types.semver_spec("^1")
    @test Pkg.Types.semver_spec("0.0.3") == Pkg.Types.semver_spec("^0.0.3")
    @test Pkg.Types.semver_spec("0") == Pkg.Types.semver_spec("^0")

    @test Pkg.Types.semver_spec("0.0.3, 1.2") == Pkg.Types.VersionSpec(["0.0.3-0.0.3", "1.2.0-1"])
    @test Pkg.Types.semver_spec("~1.2.3, ~v1") == Pkg.Types.VersionSpec(["1.2.3-1.2", "1.0.0-1"])

    @test   v"1.5.2" in Pkg.Types.semver_spec("1.2.3")
    @test   v"1.2.3" in Pkg.Types.semver_spec("1.2.3")
    @test !(v"2.0.0" in Pkg.Types.semver_spec("1.2.3"))
    @test !(v"1.2.2" in Pkg.Types.semver_spec("1.2.3"))
    @test   v"1.2.99" in Pkg.Types.semver_spec("~1.2.3")
    @test   v"1.2.3" in Pkg.Types.semver_spec("~1.2.3")
    @test !(v"1.3" in Pkg.Types.semver_spec("~1.2.3"))
    @test  v"1.2.0" in Pkg.Types.semver_spec("1.2")
    @test  v"1.9.9" in Pkg.Types.semver_spec("1.2")
    @test !(v"2.0.0" in Pkg.Types.semver_spec("1.2"))
    @test !(v"1.1.9" in Pkg.Types.semver_spec("1.2"))
    @test   v"0.2.3" in Pkg.Types.semver_spec("0.2.3")
    @test !(v"0.3.0" in Pkg.Types.semver_spec("0.2.3"))
    @test !(v"0.2.2" in Pkg.Types.semver_spec("0.2.3"))
    @test   v"0.0.0" in Pkg.Types.semver_spec("0")
    @test  v"0.99.0" in Pkg.Types.semver_spec("0")
    @test !(v"1.0.0" in Pkg.Types.semver_spec("0"))
    @test  v"0.0.0" in Pkg.Types.semver_spec("0.0")
    @test  v"0.0.99" in Pkg.Types.semver_spec("0.0")
    @test !(v"0.1.0" in Pkg.Types.semver_spec("0.0"))

    @test Pkg.Types.semver_spec("<1.2.3") == Pkg.Types.VersionSpec("0.0.0 - 1.2.2")
    @test Pkg.Types.semver_spec("<1.2") == Pkg.Types.VersionSpec("0.0.0 - 1.1")
    @test Pkg.Types.semver_spec("<1") == Pkg.Types.VersionSpec("0.0.0 - 0")
    @test Pkg.Types.semver_spec("<2") == Pkg.Types.VersionSpec("0.0.0 - 1")
    @test Pkg.Types.semver_spec("<0.2.3") == Pkg.Types.VersionSpec("0.0.0 - 0.2.2")
    @test Pkg.Types.semver_spec("<2.0.3") == Pkg.Types.VersionSpec("0.0.0 - 2.0.2")
    @test   v"0.2.3" in Pkg.Types.semver_spec("<0.2.4")
    @test !(v"0.2.4" in Pkg.Types.semver_spec("<0.2.4"))

    @test Pkg.Types.semver_spec("=1.2.3") == Pkg.Types.VersionSpec("1.2.3")
    @test Pkg.Types.semver_spec("=1.2") == Pkg.Types.VersionSpec("1.2.0")
    @test Pkg.Types.semver_spec("  =1") == Pkg.Types.VersionSpec("1.0.0")
    @test   v"1.2.3" in Pkg.Types.semver_spec("=1.2.3")
    @test !(v"1.2.4" in Pkg.Types.semver_spec("=1.2.3"))
    @test !(v"1.2.2" in Pkg.Types.semver_spec("=1.2.3"))

    @test Pkg.Types.semver_spec("≥1.3.0") == Pkg.Types.semver_spec(">=1.3.0")

    @test Pkg.Types.semver_spec(">=   1.2.3") == Pkg.Types.VersionSpec("1.2.3-*")
    @test Pkg.Types.semver_spec(">=1.2  ") == Pkg.Types.VersionSpec("1.2.0-*")
    @test Pkg.Types.semver_spec("  >=  1") == Pkg.Types.VersionSpec("1.0.0-*")
    @test   v"1.0.0" in Pkg.Types.semver_spec(">=1")
    @test   v"0.0.1" in Pkg.Types.semver_spec(">=0")
    @test   v"1.2.3" in Pkg.Types.semver_spec(">=1.2.3")
    @test !(v"1.2.2" in Pkg.Types.semver_spec(">=1.2.3"))

    @test_throws ErrorException Pkg.Types.semver_spec("0.1.0-0.2.2")
    @test Pkg.Types.semver_spec("0.1.0 - 0.2.2") == Pkg.Types.VersionSpec("0.1.0 - 0.2.2")
    @test Pkg.Types.semver_spec("1.2.3 - 4.5.6") == Pkg.Types.semver_spec("1.2.3  - 4.5.6") == Pkg.Types.semver_spec("1.2.3 -  4.5.6") == Pkg.Types.semver_spec("1.2.3  -  4.5.6")
    @test Pkg.Types.semver_spec("0.0.1 - 0.0.2") == Pkg.Types.VersionSpec("0.0.1 - 0.0.2")
    @test Pkg.Types.semver_spec("0.0.1 - 0.1.0") == Pkg.Types.VersionSpec("0.0.1 - 0.1.0")
    @test Pkg.Types.semver_spec("0.0.1 - 0.1") == Pkg.Types.VersionSpec("0.0.1 - 0.1")
    @test Pkg.Types.semver_spec("0.0.1 - 1") == Pkg.Types.VersionSpec("0.0.1 - 1")
    @test Pkg.Types.semver_spec("0.1 - 0.2") == Pkg.Types.VersionSpec("0.1 - 0.2")
    @test Pkg.Types.semver_spec("0.1.0 - 0.2") == Pkg.Types.VersionSpec("0.1.0 - 0.2")
    @test Pkg.Types.semver_spec("0.1 - 0.2.0") == Pkg.Types.VersionSpec("0.1 - 0.2.0")
    @test Pkg.Types.semver_spec("0.1.0 - 0.2.0") == Pkg.Types.VersionSpec("0.1.0 - 0.2.0")
    @test Pkg.Types.semver_spec("0.1.1 - 0.2") == Pkg.Types.VersionSpec("0.1.1 - 0.2")
    @test Pkg.Types.semver_spec("0.1 - 0.2.1") == Pkg.Types.VersionSpec("0.1 - 0.2.1")
    @test Pkg.Types.semver_spec("0.1.1 - 0.2.1") == Pkg.Types.VersionSpec("0.1.1 - 0.2.1")
    @test Pkg.Types.semver_spec("1 - 2") == Pkg.Types.VersionSpec("1 - 2")
    @test Pkg.Types.semver_spec("1.0 - 2") == Pkg.Types.VersionSpec("1.0 - 2")
    @test Pkg.Types.semver_spec("1 - 2.0") == Pkg.Types.VersionSpec("1 - 2.0")
    @test Pkg.Types.semver_spec("1.0 - 2.0") == Pkg.Types.VersionSpec("1.0 - 2.0")
    @test Pkg.Types.semver_spec("1.0.0 - 2.0") == Pkg.Types.VersionSpec("1.0.0 - 2.0")
    @test Pkg.Types.semver_spec("1.0 - 2.0.0") == Pkg.Types.VersionSpec("1.0 - 2.0.0")
    @test Pkg.Types.semver_spec("1.0.0 - 2.0.0") == Pkg.Types.VersionSpec("1.0.0 - 2.0.0")
    @test Pkg.Types.semver_spec("1.0.1 - 2") == Pkg.Types.VersionSpec("1.0.1 - 2")
    @test Pkg.Types.semver_spec("1.0.1 - 2.0") == Pkg.Types.VersionSpec("1.0.1 - 2.0")
    @test Pkg.Types.semver_spec("1.0.1 - 2.0.0") == Pkg.Types.VersionSpec("1.0.1 - 2.0.0")
    @test Pkg.Types.semver_spec("1.0.1 - 2.0.1") == Pkg.Types.VersionSpec("1.0.1 - 2.0.1")
    @test Pkg.Types.semver_spec("1.0.1 - 2.1.0") == Pkg.Types.VersionSpec("1.0.1 - 2.1.0")
    @test Pkg.Types.semver_spec("1.0.1 - 2.1.1") == Pkg.Types.VersionSpec("1.0.1 - 2.1.1")
    @test Pkg.Types.semver_spec("1.1 - 2") == Pkg.Types.VersionSpec("1.1 - 2")
    @test Pkg.Types.semver_spec("1.1 - 2.0") == Pkg.Types.VersionSpec("1.1 - 2.0")
    @test Pkg.Types.semver_spec("1.1 - 2.0.0") == Pkg.Types.VersionSpec("1.1 - 2.0.0")
    @test Pkg.Types.semver_spec("1.1 - 2.0.1") == Pkg.Types.VersionSpec("1.1 - 2.0.1")
    @test Pkg.Types.semver_spec("1.1 - 2.1.0") == Pkg.Types.VersionSpec("1.1 - 2.1.0")
    @test Pkg.Types.semver_spec("1.1 - 2.1.1") == Pkg.Types.VersionSpec("1.1 - 2.1.1")
    @test Pkg.Types.semver_spec("1.1.0 - 2") == Pkg.Types.VersionSpec("1.1.0 - 2")
    @test Pkg.Types.semver_spec("1.1.0 - 2.0") == Pkg.Types.VersionSpec("1.1.0 - 2.0")
    @test Pkg.Types.semver_spec("1.1.0 - 2.0.0") == Pkg.Types.VersionSpec("1.1.0 - 2.0.0")
    @test Pkg.Types.semver_spec("1.1.0 - 2.0.1") == Pkg.Types.VersionSpec("1.1.0 - 2.0.1")
    @test Pkg.Types.semver_spec("1.1.0 - 2.1.0") == Pkg.Types.VersionSpec("1.1.0 - 2.1.0")
    @test Pkg.Types.semver_spec("1.1.0 - 2.1.1") == Pkg.Types.VersionSpec("1.1.0 - 2.1.1")
    @test Pkg.Types.semver_spec("1.1.1 - 2") == Pkg.Types.VersionSpec("1.1.1 - 2")
    @test Pkg.Types.semver_spec("1.1.1 - 2.0") == Pkg.Types.VersionSpec("1.1.1 - 2.0")
    @test Pkg.Types.semver_spec("1.1.1 - 2.0.0") == Pkg.Types.VersionSpec("1.1.1 - 2.0.0")
    @test Pkg.Types.semver_spec("1.1.1 - 2.0.1") == Pkg.Types.VersionSpec("1.1.1 - 2.0.1")
    @test Pkg.Types.semver_spec("1.1.1 - 2.1.0") == Pkg.Types.VersionSpec("1.1.1 - 2.1.0")
    @test Pkg.Types.semver_spec("1.1.1 - 2.1.1") == Pkg.Types.VersionSpec("1.1.1 - 2.1.1")

    @test Pkg.Types.semver_spec("0.1.0 - 0.2.2, 1.2") == Pkg.Types.VersionSpec(["0.1.0 - 0.2.2", "1.2.0-1"])
    @test Pkg.Types.semver_spec("0.1.0 - 0.2.2, >=1.2") == Pkg.Types.VersionSpec(["0.1.0 - 0.2.2", "1.2.0-*"])
    @test !(v"0.3" in Pkg.Types.semver_spec("0.1 - 0.2"))
    @test v"0.2.99" in Pkg.Types.semver_spec("0.1 - 0.2")
    @test v"0.3" in Pkg.Types.semver_spec("0.1 - 0")
    @test Pkg.Types.semver_spec(string(Pkg.Types.VersionSpec("1-2"))) == Pkg.Types.VersionSpec("1-2")

    @test_throws ErrorException Pkg.Types.semver_spec("^^0.2.3")
    @test_throws ErrorException Pkg.Types.semver_spec("^^0.2.3.4")
    @test_throws ErrorException Pkg.Types.semver_spec("0.0.0")
    @test_throws ErrorException Pkg.Types.semver_spec("0.7 1.0")

    @test Pkg.Types.isjoinable(Pkg.Pkg.Types.VersionBound((1, 5)), Pkg.Pkg.Types.VersionBound((1, 6)))
    @test !(Pkg.Types.isjoinable(Pkg.Pkg.Types.VersionBound((1, 5)), Pkg.Pkg.Types.VersionBound((1, 6, 0))))
end
# TODO: Should rewrite these tests not to rely on internals like field names
@testset "union, isjoinable" begin
    @test sprint(print, Pkg.Types.VersionRange("0-0.3.2")) == "0 - 0.3.2"
    # test missing paths on union! and isjoinable
    # there's no == for VersionBound or VersionRange
    unified_vr = union!([Pkg.Types.VersionRange("1.5-2.8"), Pkg.Types.VersionRange("2.5-3")])[0]
    @test unified_vr.lower.t == (UInt32(1), UInt32(5), UInt32(0))
    @test unified_vr.upper.t == (UInt32(3), UInt32(0), UInt32(0))
    unified_vr = union!([Pkg.Types.VersionRange("2.5-3"), Pkg.Types.VersionRange("1.5-2.8")])[0]
    @test unified_vr.lower.t == (UInt32(1), UInt32(5), UInt32(0))
    @test unified_vr.upper.t == (UInt32(3), UInt32(0), UInt32(0))
    unified_vr = union!([Pkg.Types.VersionRange("1.5-2.2"), Pkg.Types.VersionRange("2.5-3")])[0]
    @test unified_vr.lower.t == (UInt32(1), UInt32(5), UInt32(0))
    @test unified_vr.upper.t == (UInt32(2), UInt32(2), UInt32(0))
    unified_vr = union!([Pkg.Types.VersionRange("1.5-2.2"), Pkg.Types.VersionRange("2.5-3")])[1]
    @test unified_vr.lower.t == (UInt32(2), UInt32(5), UInt32(0))
    @test unified_vr.upper.t == (UInt32(3), UInt32(0), UInt32(0))
    unified_vb = Pkg.Types.VersionBound(union!([v"1.5", v"1.6"])[0])
    @test unified_vb.t == (UInt32(1), UInt32(5), UInt32(0))
    unified_vb = Pkg.Types.VersionBound(union!([v"1.5", v"1.6"])[1])
    @test unified_vb.t == (UInt32(1), UInt32(6), UInt32(0))
    unified_vb = Pkg.Types.VersionBound(union!([v"1.5", v"1.5"])[0])
    @test unified_vb.t == (UInt32(1), UInt32(5), UInt32(0))
end

@testset "printing of stdlib paths, issue #605" begin
    path = Pkg.Types.stdlib_path("Test")
    @test Pkg.pathrepr(path) == "`@stdlib/Test`"
end

@testset "stdlib_resolve!" begin
    a = Pkg.Types.PackageSpec(name = "Markdown")
    b = Pkg.Types.PackageSpec(uuid = UUID("9abbd945-dff8-562f-b5e8-e1ebf5ef1b79"))
    Pkg.Types.stdlib_resolve!([a, b])
    @test a.uuid == UUID("d6f4376e-aef5-505a-96c1-9c027394607a")
    @test b.name == "Profile"

    x = Pkg.Types.PackageSpec(name = "Markdown", uuid = UUID("d6f4376e-aef5-505a-96c1-9c027394607a"))
    Pkg.Types.stdlib_resolve!([x])
    @test x.name == "Markdown"
    @test x.uuid == UUID("d6f4376e-aef5-505a-96c1-9c027394607a")
end

@testset "PkgError printing" begin
    err = Pkg.Types.PkgError("foobar")
    @test occursin("Pkg.Types.PkgError(\"foobar\")", sprint(show, err))
    @test sprint(showerror, err) == "foobar"
end

@testset "range_compressed_versionspec" begin
    pool = [v"1.0.0", v"1.1.0", v"1.2.0", v"1.2.1", v"2.0.0", v"2.0.1", v"3.0.0", v"3.1.0"]
    @test (
        Pkg.Resolve.range_compressed_versionspec(pool)
            == Pkg.Resolve.range_compressed_versionspec(pool, pool)
            == Pkg.Types.VersionSpec("1.0.0-3.1.0")
    )

    @test isequal(
        Pkg.Resolve.range_compressed_versionspec(pool, [v"1.2.0", v"1.2.1", v"2.0.0", v"2.0.1", v"3.0.0"]),
        Pkg.Types.VersionSpec("1.2.0-3.0.0")
    )

    @test isequal(  # subset has 1.x and 3.x, but not 2.x
        Pkg.Resolve.range_compressed_versionspec(
            pool, [v"1.0.0", v"1.1.0", v"1.2.0", v"1.2.1", v"3.0.0", v"3.1.0"]
        ),
        Pkg.Types.VersionSpec([Pkg.Types.VersionRange(v"1.0.0", v"1.2.1"), Pkg.Types.VersionRange(v"3.0.0", v"3.1.0")])
    )

    @test Pkg.Resolve.range_compressed_versionspec(pool, [v"1.1.0"]) == Pkg.Types.VersionSpec("1.1.0")
end

@testset "versionspec with v" begin
    v = Pkg.Types.VersionSpec("v1.2.3")
    @test !(v"1.2.2" in v)
    @test   v"1.2.3" in v
    @test !(v"1.2.4" in v)
end

@testset "atomic_toml_write" begin
    mktempdir() do dir
        path = joinpath(dir, "Foo.toml")
        Pkg.atomic_toml_write(path, Dict("a" => "b"))
        @test Pkg.TOML.parsefile(path) == Dict("a" => "b")
        # no temporary files or directories are left behind
        @test readdir(dir) == ["Foo.toml"]

        # files are written with the default permissions of the process, not with
        # `mktemp`'s 0o600, since e.g. registry files may need to be readable by others
        reference = joinpath(dir, "reference")
        close(open(reference, "w"))
        @test filemode(path) & 0o777 == filemode(reference) & 0o777

        private_path = joinpath(dir, "Private.toml")
        Pkg.atomic_toml_write(private_path, Dict("a" => "b"), private = true)
        # Windows has no real file modes, `chmod` there only toggles the read-only bit
        if !Sys.iswindows()
            @test filemode(private_path) & 0o777 == 0o600

            # the permissions of an existing file are preserved
            chmod(path, 0o664)
            Pkg.atomic_toml_write(path, Dict("a" => "c"))
            @test filemode(path) & 0o777 == 0o664
            @test Pkg.TOML.parsefile(path) == Dict("a" => "c")
        end
    end
end

end # module

# Depot selection uses the first collection position while preserving scalar paths and errors.
@testset "zero-origin depot selection" begin
    @test Pkg.depots1("/tmp/single") == "/tmp/single"
    @test Pkg.depots1(["/tmp/first"]) == "/tmp/first"
    @test Pkg.depots1(["/tmp/first", "/tmp/second"]) == "/tmp/first"
    @test_throws Pkg.Types.PkgError Pkg.depots1(String[])
end


# Package tests must execute in a child process and propagate both success and failure.
@testset "zero-origin local package lifecycle" begin
    mktempdir() do root
        project = joinpath(root, "JooliaPkgSmoke")
        depot = joinpath(root, "depot")
        mkpath(joinpath(project, "src"))
        mkpath(joinpath(project, "test"))
        mkpath(joinpath(depot, "registries", "Local"))
        write(joinpath(depot, "registries", "Local", "Registry.toml"), """
            name = "Local"
            uuid = "835dc3ed-f4c8-4d14-ac32-ddf2a0123456"
            repo = "file://$root"
            [packages]
            """)
        write(joinpath(project, "Project.toml"), """
            name = "JooliaPkgSmoke"
            uuid = "835dc3ed-f4c8-4d14-ac32-ddf2a0123457"
            version = "0.1.0"
            [extras]
            Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"
            LinearAlgebra = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"
            [targets]
            test = ["Test", "LinearAlgebra"]
            """)
        write(joinpath(project, "src", "JooliaPkgSmoke.jl"), "module JooliaPkgSmoke\nfirstvalue(x) = x[0]\nend\n")
        testfile = joinpath(project, "test", "runtests.jl")
        write(testfile, """
            using Test, LinearAlgebra, JooliaPkgSmoke
            @testset "zero-origin package tests" begin
                @test JooliaPkgSmoke.firstvalue([17, 23]) == 17
                @test JooliaPkgSmoke.firstvalue((17, 23)) == 17
                @test size(ones(3, 4), 0) == 3
                @test ones(3, 4) * ones(4, 5) == fill(4.0, 3, 5)
                @test_throws BoundsError (17,)[1]
            end
            """)
        original_depot = copy(DEPOT_PATH)
        original_project = Base.active_project()
        try
            empty!(DEPOT_PATH)
            push!(DEPOT_PATH, depot)
            withenv("JULIA_DEPOT_PATH" => depot, "JULIA_PKG_OFFLINE" => "true", "JULIA_PKG_PRECOMPILE_AUTO" => "0") do
                Pkg.activate(project)
                Pkg.instantiate(; update_registry=false, allow_autoprecomp=false)
                @test isfile(joinpath(project, "Manifest.toml"))
                Pkg.test(; allow_reresolve=false)
                write(testfile, "using Test\n@testset \"intentional failure\" begin\n@test false\nend\n")
                @test_throws Pkg.Types.PkgError Pkg.test(; allow_reresolve=false)
            end
        finally
            empty!(DEPOT_PATH)
            append!(DEPOT_PATH, original_depot)
            original_project === nothing ? Pkg.activate() : Pkg.activate(dirname(original_project))
        end
    end
end
