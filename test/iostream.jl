# This file is a part of Julia. License is MIT: https://julialang.org/license

@testset "skipchars for IOStream" begin
    mktemp() do path, file
        function append_to_file(str)
            mark(file)
            print(file, str)
            flush(file)
            reset(file)
        end
        # test it doesn't error on eof
        @test eof(skipchars(isspace, file))

        # test it correctly skips
        append_to_file("    ")
        @test eof(skipchars(isspace, file))

        # test it correctly detects comment lines
        append_to_file("#    \n   ")
        @test eof(skipchars(isspace, file, linecomment='#'))

        # test it stops at the appropriate time
        append_to_file("   not a space")
        @test !eof(skipchars(isspace, file))
        @test read(file, Char) == 'n'

        # test it correctly ignores the contents of comment lines
        append_to_file("  #not a space \n   not a space")
        @test !eof(skipchars(isspace, file, linecomment='#'))
        @test read(file, Char) == 'n'

        # test it correctly handles unicode
        for (byte, char) in zip(1:4, ('@','߷','࿊','𐋺'))
            append_to_file("abcdef$char")
            @test ncodeunits(char) == byte
            @test !eof(skipchars(isletter, file))
            @test read(file, Char) == char
        end
    end
end

@testset "readbytes!" begin
    mktemp() do path, file
        function append_to_file(str)
            mark(file)
            print(file, str)
            flush(file)
            reset(file)
        end
        # Array
        append_to_file("aaaaaaaaaaaaaaaaa")
        # readbytes_some
        b = UInt8[0]
        readbytes!(file, b, all=false)
        @test String(b) == "a"
        # with resizing of b
        b = UInt8[]
        readbytes!(file, b, 2, all=false)
        @test String(b) == "aa"
        # readbytes_all with resizing
        b = UInt8[]
        readbytes!(file, b, 15)
        @test String(b) == "aaaaaaaaaaaaaa"

        # SubArray
        append_to_file("aaaaaaaaaaaaaaaaa")
        # readbytes_some
        b = view(UInt8[0, 0, 0], 2:2)
        readbytes!(file, b, all=false)
        @test String(b) == "a"
        b = view(UInt8[0, 0, 0], 2:3)
        readbytes!(file, b, 2, all=false)
        @test String(b) == "aa"
        b = view(UInt8[0, 0, 0], 1:3)
        readbytes!(file, b, 2, all=false)
        @test b == UInt8['a', 'a', 0]
        @test String(b[1:2]) == "aa"
        # with resizing of b
        b = view(UInt8[0, 0, 0], 1:0)
        @test_throws MethodError readbytes!(file, b, 2, all=false)
        @test isempty(b)
        # readbytes_all
        b = view(UInt8[0, 0, 0], 2:2)
        readbytes!(file, b)
        @test String(b) == "a"
        b = view(UInt8[0, 0, 0], 2:3)
        readbytes!(file, b, 2)
        @test String(b) == "aa"
        b = view(UInt8[0, 0, 0], 1:3)
        readbytes!(file, b, 2)
        @test b == UInt8['a', 'a', 0]
        @test String(b[1:2]) == "aa"
        #  with resizing of b
        b = view(UInt8[0, 0, 0], 1:0)
        @test_throws MethodError readbytes!(file, b, 2)
        @test !islocked(file.lock) # Issue #37218
        @test isempty(b)
    end
end

@testset "issue #18755" begin
    mktemp() do path, io
        write(io, zeros(UInt8, 131073))
        @test position(io) == 131073
        write(io, zeros(UInt8, 131073))
        @test position(io) == 262146
    end
end

@testset "issue #27951" begin
    a = UInt8[1 3; 2 4]
    s = view(a, [1,2], :)
    mktemp() do path, io
        write(io, s)
        seek(io, 0)
        b = Vector{UInt8}(undef, 4)
        @test readbytes!(io, b) == 4
        @test b == 0x01:0x04
    end
end

@testset "read!/write(::IO, A::StridedArray)" begin
    s1 = reshape(view(rand(UInt8, 16), 1:16), 2, 2, 2, 2)
    s2 = view(s1, 1:2, 1:2, 1:2, 1:2)
    s3 = view(s1, 1:2, 1:2, 1, 1:2)
    mktemp() do path, io
        b = Vector{UInt8}(undef, 17)
        for s::StridedArray in (s3, s1, s2)
            @test write(io, s) == length(s)
            seek(io, 0)
            @test readbytes!(io, b) == length(s)
            seek(io, 0)
            @test view(b, 1:length(s)) == vec(s)
            @test read!(io, fill!(deepcopy(s), 0)) == s
            seek(io, 0)
        end
    end
end

@test Base.open_flags(read=false, write=true, append=false) == (read=false, write=true, create=true, truncate=true, append=false)

@testset "issue #30978" begin
    mktemp() do path, io
        x = rand(UInt8, 100)
        write(path, x)
        # Should not throw OutOfMemoryError
        y = open(f -> read(f, typemax(Int)), path)
        @test x == y

        # Should resize y to right length
        y = zeros(UInt8, 99)
        open(f -> readbytes!(f, y, 101, all=true), path)
        @test x == y
        y = zeros(UInt8, 99)
        open(f -> readbytes!(f, y, 101, all=false), path)
        @test x == y

        # Should never shrink y below original size
        y = zeros(UInt8, 101)
        open(f -> readbytes!(f, y, 102, all=true), path)
        @test y == [x; 0]
        y = zeros(UInt8, 101)
        open(f -> readbytes!(f, y, 102, all=false), path)
        @test y == [x; 0]
    end
end

@testset "peek(::IOStream)" begin
    mktemp() do _, file
        @test_throws EOFError peek(file)
        mark(file)
        write(file, "Lávate las manos")
        flush(file)
        reset(file)
        @test peek(file) == 0x4c
    end
end

@testset "issue #36004" begin
    f = tempname()
    open(f, "w") do io
        write(io, "test")
    end
    open(f, "r") do io
        @test length(readavailable(io)) > 0
    end
end

@testset "inference" begin
    @test all(T -> T <: Union{UInt, Int}, Base.return_types(unsafe_write, (IO, Ptr{UInt8}, UInt)))
    @test all(T -> T === Bool, Base.return_types(eof, (IO,)))
end

@testset "fd" begin
    @test open(fd, tempname(), "w") isa RawFD
end

# File reads and delimiter copies start at byte zero and preserve unused buffer space.
@testset "zero-origin buffered file IO" begin
    mktemp() do path, io
        data = collect(UInt8(0):UInt8(255))
        write(io, data)
        flush(io)
        @test read(path) == data
        seekstart(io)
        b = fill(UInt8(0xaa), 258)
        @test readbytes!(io, b, 256) == 256
        @test b[0:255] == data && b[256:257] == UInt8[0xaa, 0xaa]
        @test eof(io) && position(io) == 256
        seekstart(io)
        b = UInt8[]
        @test readbytes!(io, b, 300) == 256 && b == data
        seekstart(io)
        b = fill(UInt8(0xaa), 8)
        @test readbytes!(io, b, 4; all=false) == 4 && b[0:3] == UInt8[0, 1, 2, 3] && b[4] == 0xaa
        for _ in 1:4
            @test read(path) == data
            GC.gc()
        end
    end
    mktemp() do path, io
        @test isempty(read(path))
        write(io, "abc|rest\nlast")
        flush(io)
        @test read(path, String) == "abc|rest\nlast"
        seekstart(io)
        out = IOBuffer(sizehint=1)
        copyuntil(out, io, UInt8('|'))
        @test position(out) == 3 && String(take!(out)) == "abc" && position(io) == 4
        seekstart(io)
        out = IOBuffer(; append=true)
        write(out, "xy")
        seekstart(out)
        copyuntil(out, io, UInt8('|'); keep=true)
        @test String(take!(out)) == "xyabc|"
        seekstart(io)
        @test readuntil(io, '|') == "abc" && readline(io) == "rest" && read(io, String) == "last"
    end
end
