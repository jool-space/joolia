using SHA, Test

include("constants.jl")

@testset "Joolia zero-origin SHA buffering" begin
    @test bytes2hex(sha1(UInt8[])) ==
        "da39a3ee5e6b4b0d3255bfef95601890afd80709"
    @test bytes2hex(sha1("abc")) ==
        "a9993e364706816aba3e25717850c26c9cd0d89d"
    @test bytes2hex(sha256(UInt8[])) ==
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    @test bytes2hex(sha256("abc")) ==
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

    # Compare one-shot and split updates at both sides of the SHA-256 block
    # boundary. The split slices deliberately begin at storage position zero.
    for n in (0, 1, 55, 56, 63, 64, 65, 127, 128)
        data = fill(UInt8('a'), n)
        split = div(n, 2)
        ctx = SHA256_CTX()
        update!(ctx, data[0:split-1])
        update!(ctx, data[split:n-1])
        @test digest!(ctx) == sha256(data)
    end
end


function describe_hash(T::Type{S}) where {S <: SHA.SHA_CTX}
    if T <: SHA.SHA1_CTX return "SHA1" end
    if T <: SHA.SHA2_CTX return "SHA2-$(SHA.digestlen(T)*8)" end
    if T <: SHA.SHA3_CTX return "SHA3-$(SHA.digestlen(T)*8)" end
end

@debug("Loaded hash types: $(join(sort([describe_hash(t[2]) for t in sha_types]), ", ", " and "))")

@testset "Hashing" begin
    # First, test processing the data in one go
    @testset "Complete" begin
        for idx in eachindex(data)
            @testset "$(data_desc[idx])" begin
                for sha_idx in eachindex(sha_funcs)
                    sha_func = sha_funcs[sha_idx]
                    hash = bytes2hex(sha_func(deepcopy(data[idx])))
                    @test hash == answers[sha_func][idx]

                    # Test sha_(::AbstractString)
                    if data[idx] isa String
                        sub_str = deepcopy(data[idx]) |> SubString
                        @test bytes2hex(sha_func(sub_str)) == answers[sha_func][idx]
                    end
                end
            end
        end
    end

    # Do another test on the "so many a's" data where we chunk up the data into
    # two chunks, (sized appropriately to AVOID overflow from one update to another)
    # in order to test multiple update!() calls
    @testset "Chunked Properly" begin
        for sha_idx in eachindex(sha_funcs)
            ctx = sha_types[sha_funcs[sha_idx]]()
            SHA.update!(ctx, so_many_as_array[0:2*SHA.blocklen(typeof(ctx))-1])
            SHA.update!(ctx, so_many_as_array[2*SHA.blocklen(typeof(ctx)):end])
            hash = bytes2hex(SHA.digest!(ctx))
            @test hash == answers[sha_funcs[sha_idx]][end]
        end
    end

    # Do another test on the "so many a's" data where we chunk up the data into
    # three chunks, (sized appropriately to CAUSE overflow from one update to another)
    # in order to test multiple update!() calls as well as the overflow codepaths
    @testset "Chunked clumsily" begin
        for sha_idx in eachindex(sha_funcs)
            ctx = sha_types[sha_funcs[sha_idx]]()

            # Get indices awkwardly placed for the blocklength of this hash type
            idx0 = round(Int, 0.3*SHA.blocklen(typeof(ctx)))
            idx1 = round(Int, 1.7*SHA.blocklen(typeof(ctx)))
            idx2 = round(Int, 2.6*SHA.blocklen(typeof(ctx)))

            # Feed data in according to our dastardly blocking scheme
            SHA.update!(ctx, so_many_as_array[0:idx0-1])
            SHA.update!(ctx, so_many_as_array[idx0:2*idx0-1])
            SHA.update!(ctx, so_many_as_array[2*idx0:3*idx0-1])
            SHA.update!(ctx, so_many_as_array[3*idx0:4*idx0-1])
            SHA.update!(ctx, so_many_as_array[4*idx0:idx1-1])
            SHA.update!(ctx, so_many_as_array[idx1:idx2-1])
            SHA.update!(ctx, so_many_as_array[idx2:end])

            # Ensure the hash is the appropriate one
            hash = bytes2hex(SHA.digest!(ctx))
            @test hash == answers[sha_funcs[sha_idx]][end]
        end
    end

    # Test that the hash states cannot be updated after having been finalized,
    # but can still return the same digest
    @testset "Reuse" begin
        for sha_idx in eachindex(sha_funcs)
            ctx = sha_types[sha_funcs[sha_idx]]()
            update!(ctx, codeunits("abracadabra"))
            hash1 = digest!(ctx)

            # Cannot update after having been digested
            @test_throws Exception update!(ctx, codeunits("abc"))

            # But will still return the same digest twice
            hash2 = digest!(ctx)
            @test hash1 == hash2
        end
    end
end

@testset "SHA-512/t" begin
    # https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Standards-and-Guidelines/documents/examples/SHA512_224.pdf
    @test sha2_512_224("abc") |> bytes2hex ==
        "4634270f707b6a54daae7530460842e20e37ed265ceee9a43e8924aa"
    @test sha2_512_224("abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu") |> bytes2hex ==
        "23fec5bb94d60b23308192640b0c453335d664734fe40e7268674af9"
    # https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Standards-and-Guidelines/documents/examples/SHA512_256.pdf
    @test sha2_512_256("abc") |> bytes2hex ==
        "53048e2681941ef99b2e29b76b4c7dabe4c2d0c634fc6d46e0e2f13107e7af23"
    @test sha2_512_256("abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu") |> bytes2hex ==
        "3928e184fb8690f840da3988121d31be65cb9d3ef83ee6146feac861e19b563a"
end

@testset "SHA3" begin
    @test sha3_512("0" ^ 70) |> bytes2hex ==
        "1ec3e5ebb442c09e7ab7a1ee18edfa1a9ec771ad243e3e3d65cad1730416109a0890e29f9314babd7ab018a246b2f9639af29ee09aec2352a2f94dc12a2f6109"
    # test `digest!` branch: @assert  usedspace == blocklen(T) - 1
    @test sha3_512("0" ^ 71) |> bytes2hex ==
        "2bdaca04f78ae216331557358d124c0b79305735e5a65fa91a8d6504c92fe1a780ee992a5f0233dad0b79875333a40d1c26d435684442492ad1e3166ef19809b"
    @test sha3_512("0" ^ 72) |> bytes2hex ==
        "69eb8ccde4eec57d5e78512bf29081dc15d3ca650d5bf15cc9c0dfd7d7c477c067504fb99c7c787df248a9897cbeaeafeae563e855205660363dd700e1d43eee"
end

@testset "HMAC" begin
    # test hmac correctness using the examples from Wikipedia:
    # https://en.wikipedia.org/wiki/Hash-based_message_authentication_code#Examples
    for (key, msg, fun, hash) in hmac_data
        digest = bytes2hex(fun(Vector{UInt8}(key), Vector{UInt8}(msg)))
        @test digest == hash
        digest = bytes2hex(fun(Vector{UInt8}(key), IOBuffer(msg)))
        @test digest == hash
        digest = bytes2hex(fun(Vector{UInt8}(key), SubString(msg)))
        @test digest == hash
    end

    # help function for test: only accept `HMAC_CTX{SHA2_256_CTX}`
    Base.:(==)(x::SHA2_256_CTX, y::SHA2_256_CTX) =
        x.state==y.state && x.bytecount==y.bytecount && x.buffer==y.buffer
    Base.:(==)(x::HMAC_CTX{SHA2_256_CTX}, y::HMAC_CTX{SHA2_256_CTX}) =
        x.outer==y.outer && x.context==y.context

    # Test if branch in `HMAC_CTX` constructor: 
    key0 = sha256(zeros(UInt8, 128))
    key = zeros(UInt8, 128)
    blocksize = 64
    # test with looong key
    @assert length(key) > blocksize

    s0 = HMAC_CTX(SHA2_256_CTX(), key0, blocksize)
    s1 = HMAC_CTX(SHA2_256_CTX(), key, blocksize)
    @test s0 == s1
end

replstr(x) = sprint((io, x) -> show(IOContext(io, :limit => true), MIME("text/plain"), x), x)
@testset "REPL" begin
    for idx in eachindex(ctxs)
        @test typeof(copy(ctxs[idx]())) == typeof(ctxs[idx]())
        @test replstr(ctxs[idx]()) == shws[idx]
    end
end

@testset "Type-checking" begin
    for f in sha_funcs
        @test_throws MethodError f(UInt32[0x23467, 0x324775])
    end
end

@testset "codecov" begin
    # Table 3: Input block sizes for HMAC
    #   https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.202.pdf
    #        SHA3-224 -256 -384 -512
    block_size = [144, 136, 104, 72]
    byte_count = 2 * sizeof(SHA.state_type(SHA.SHA3_CTX))
    sha3_types = [SHA.SHA3_224_CTX, SHA.SHA3_256_CTX, SHA.SHA3_384_CTX, SHA.SHA3_512_CTX]
    @test [ SHA.short_blocklen(T) for T in sha3_types ] == (block_size .- byte_count)
end

@testset "SHAKE" begin
    # test some official testvectors from https://csrc.nist.gov/Projects/Cryptographic-Algorithm-Validation-Program/Secure-Hashing
    @testset "shake128" begin
        for (k,v) in SHA128test
            @test SHA.shake128(hex2bytes(k[0]),k[1]) == hex2bytes(v)
        end
        @test SHA.shake128(b"",UInt(16)) == hex2bytes("7f9c2ba4e88f827d616045507605853e")
        @test SHA.shake128(codeunits("0" ^ 167), UInt(32)) == hex2bytes("ff60b0516fb8a3d4032900976e98b5595f57e9d4a88a0e37f7cc5adfa3c47da2")
    end

    @testset "shake256" begin
        for (k,v) in SHA256test
            @test SHA.shake256(hex2bytes(k[0]),k[1]) == hex2bytes(v)
        end
        @test SHA.shake256(b"",UInt(32)) == hex2bytes("46b9dd2b0ba88d13233b3feb743eeb243fcd52ea62b81b82b50c27646ed5762f")
        @test SHA.shake256(codeunits("0"^135),UInt(32)) == hex2bytes("ab11f61b5085a108a58670a66738ea7a8d8ce23b7c57d64de83eaafb10923cf8")
    end
end

# Independent digests cover padding boundaries and streaming updates.
@testset "zero-origin SHA padding reference vectors" begin
    vectors = [
        (0, sha1, SHA1_CTX, "da39a3ee5e6b4b0d3255bfef95601890afd80709"),
        (0, sha256, SHA256_CTX, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
        (0, sha512, SHA512_CTX, "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e"),
        (1, sha1, SHA1_CTX, "5ba93c9db0cff93f52b521d7420e43f6eda2784f"),
        (1, sha256, SHA256_CTX, "6e340b9cffb37a989ca544e6bb780a2c78901d3fb33738768511a30617afa01d"),
        (1, sha512, SHA512_CTX, "b8244d028981d693af7b456af8efa4cad63d282e19ff14942c246e50d9351d22704a802a71c3580b6370de4ceb293c324a8423342557d4e5c38438f0e36910ee"),
        (54, sha1, SHA1_CTX, "cfae6d86a767b9c700b5081a54265fb2fe0f6fd9"),
        (54, sha256, SHA256_CTX, "675f28acc0b90a72d1c3a570fe83ac565555db358cf01826dc8eefb2bf7ca0f3"),
        (54, sha512, SHA512_CTX, "6d7644db575c5c238da02cc4259996cf163a3a3b5eccc4fc62442ddf01aa05ef0c4edbe3e6d220df189c984aa55726a4922efe004832f2d8887f0b8a9267db40"),
        (55, sha1, SHA1_CTX, "8ae2d46729cfe68ff927af5eec9c7d1b66d65ac2"),
        (55, sha256, SHA256_CTX, "463eb28e72f82e0a96c0a4cc53690c571281131f672aa229e0d45ae59b598b59"),
        (55, sha512, SHA512_CTX, "6856647f269c2ee3d8128f0b25427659d880641ef343300dd3cd4679168f58d6527fda70b4ebc854e2065e172b7d58c1536992c0810599259ba84a2b40c65414"),
        (56, sha1, SHA1_CTX, "636e2ec698dac903498e648bd2f3af641d3c88cb"),
        (56, sha256, SHA256_CTX, "da2ae4d6b36748f2a318f23e7ab1dfdf45acdc9d049bd80e59de82a60895f562"),
        (56, sha512, SHA512_CTX, "8b12b2f6fe400a51d29656e2b8c42a1bbfe6fcf3e425da430db05d1a2dda14790dee20fa8b22d8762afffe4988a5c98a4430d22a17e41e23d90fa61ab75671a9"),
        (57, sha1, SHA1_CTX, "7cb1330f35244b57437539253304ea78a6b7c443"),
        (57, sha256, SHA256_CTX, "2fe741af801cc238602ac0ec6a7b0c3a8a87c7fc7d7f02a3fe03d1c12eac4d8f"),
        (57, sha512, SHA512_CTX, "92cb9f2e4eee07c7b32b06cf4917fbe54365f55247cc9b5bc4478d9fada52b07d1c302b3959d0ca9a75a629653ea7c245a8fbba2a265cda4ea70ac5a860a6f3d"),
        (63, sha1, SHA1_CTX, "6d942da0c4392b123528f2905c713a3ce28364bd"),
        (63, sha256, SHA256_CTX, "29af2686fd53374a36b0846694cc342177e428d1647515f078784d69cdb9e488"),
        (63, sha512, SHA512_CTX, "9dc9c5598e55dc42955695320839788e353f1d7f6ba74df74c80a8a52f463c0697f57f68835d1418f4ce9b6530cd79bd0f4c6f7e13c93feb1218c0b65c2c0561"),
        (64, sha1, SHA1_CTX, "c6138d514ffa2135bfce0ed0b8fac65669917ec7"),
        (64, sha256, SHA256_CTX, "fdeab9acf3710362bd2658cdc9a29e8f9c757fcf9811603a8c447cd1d9151108"),
        (64, sha512, SHA512_CTX, "ee4320ebaf3fdb4f2c832b137200c08e235e0fa7bbd0eb1740c7063ba8a0d151da77e003398e1714a955d475b05e3e950b639503b452ec185de4229bc4873949"),
        (65, sha1, SHA1_CTX, "69bd728ad6e13cd76ff19751fde427b00e395746"),
        (65, sha256, SHA256_CTX, "4bfd2c8b6f1eec7a2afeb48b934ee4b2694182027e6d0fc075074f2fabb31781"),
        (65, sha512, SHA512_CTX, "02856cef735f9acec6b9e33f0fbc8f9804d2aa54187f382b8ae842e5d3696c07459aad2a5aed25ea5e117eb1c7ba35da6a7a8adce9e6afe3ad79e9fa42d5bba8"),
        (110, sha1, SHA1_CTX, "670f7a869e90ce86e0a18232a9d4b1f97c1c77d0"),
        (110, sha256, SHA256_CTX, "a47a551b01e55aaaa015531a4fa26a666f1ebd4ba4573898de712b8b5e0ca7e9"),
        (110, sha512, SHA512_CTX, "51f2ba331c24541efec042cc66398d388348c4fedc3f77a4ddfda39752ae2880c68e0465c15b07abfd93e16ba635ae7ca7d7e144018ade57607de8643992f50b"),
        (111, sha1, SHA1_CTX, "bc544e24573d592290fdaff8ecf3f7f2b00cd483"),
        (111, sha256, SHA256_CTX, "60780e9451bdc43cf4530ffc95cbb0c4eb24dae2c39f55f334d679e076c08065"),
        (111, sha512, SHA512_CTX, "a1a111449b198d9b1f538bad7f3fc1022b3a5b1a5e90a0bc860de8512746cbc31599e6c834de3a3235327af0b51ff57bf7acf1974a73014d9c3953812edc7c8d"),
        (112, sha1, SHA1_CTX, "e4ce142d09a84a8645338dd6535cbfaaf800d320"),
        (112, sha256, SHA256_CTX, "09373f127d34e61dbbaa8bc4499c87074f2ddb10e1b465f506d7d70a15011979"),
        (112, sha512, SHA512_CTX, "c5fbd731d19d2ae1180f001be72c2c1aaba1d7b094b3748880e24593b8e117a750e11c1bd867cc2f96dace8c8b74abd2d5c4f236be444e77d30d1916174070b9"),
        (113, sha1, SHA1_CTX, "1c26461e26eb697ccc36a98714ee70caaa87a84e"),
        (113, sha256, SHA256_CTX, "13aaa9b5fb739cdb0e2af99d9ac0a409390adc4d1cb9b41f1ef94f8552060e92"),
        (113, sha512, SHA512_CTX, "61b2e77db697dfe5571fff3ed06bd60c41e1e7b7c08a80de01cb16526d9a9a52d690dfbe792278a60f6e2b4c57a97c729773f26e258d2393890c985d645f6715"),
        (127, sha1, SHA1_CTX, "89d7312a903f65cd2b3e34a975e55dbea9033353"),
        (127, sha256, SHA256_CTX, "92ca0fa6651ee2f97b884b7246a562fa71250fedefe5ebf270d31c546bfea976"),
        (127, sha512, SHA512_CTX, "eab89674feaa34e27aebeeff3c0a4d70070bb872d5e9f186cf1dbbdee517b6e35724d629ff025a5b07185e911ada7e3c8acf830aa0e4f71777bd2d44f504f7f0"),
        (128, sha1, SHA1_CTX, "e6434bc401f98603d7eda504790c98c67385d535"),
        (128, sha256, SHA256_CTX, "471fb943aa23c511f6f72f8d1652d9c880cfa392ad80503120547703e56a2be5"),
        (128, sha512, SHA512_CTX, "1dffd5e3adb71d45d2245939665521ae001a317a03720a45732ba1900ca3b8351fc5c9b4ca513eba6f80bc7b1d1fdad4abd13491cb824d61b08d8c0e1561b3f7"),
        (129, sha1, SHA1_CTX, "3352e41cc30b40ae80108970492b21014049e625"),
        (129, sha256, SHA256_CTX, "5099c6a56203f9687f7d33f4bfdf576d31dc91f6b695ecea38b2770c87631135"),
        (129, sha512, SHA512_CTX, "1d9da57fbbdab09afb3506ab2d223d06109d65c1c8ad197f50138f714bc4c3f2fe5787922639c680acad1c651f955990425954ce2cba0c5cc83f2667d878eb0f"),
        (255, sha1, SHA1_CTX, "47defa228fbd72b6de16bf15fb5ddd0d95f00cab"),
        (255, sha256, SHA256_CTX, "857df204175f077a9986709897f00ee0bcc0449585248e4b42498337e9329999"),
        (255, sha512, SHA512_CTX, "e9746a5516961da1fdc8e6c59350cd147b7d80c120cc7ed621399faeb2462c28f34217a13009a8e6a721f538356db9a9b64d9a5412e0fd07d24cac1315d95548"),
        (256, sha1, SHA1_CTX, "d761175408c7032430f9e22f87ce8417be700f73"),
        (256, sha256, SHA256_CTX, "5bc31b283cef0072274e97d74916552954c935794536cab632641e5ea071379d"),
        (256, sha512, SHA512_CTX, "7ff1cd1e9773a4b7ba1f40e642db0d879bd5f6cc151a7d3401a0bc7778b8270c108b530fb195f2383f4cec8cf05778e6af4db56811673371674cec1524488f83"),
    ]
    for (n, hash, Context, expected) in vectors
        data = UInt8[mod(i, 251) for i in 0:n-1]
        @test bytes2hex(hash(data)) == expected
        for split in unique([0, div(n, 2), n])
            ctx = Context()
            update!(ctx, data[0:split-1])
            update!(ctx, data[split:end])
            @test bytes2hex(digest!(ctx)) == expected
        end
    end
end
