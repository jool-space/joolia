macro R1_16(j, T)

    ww = (:a, :b, :c, :d, :e, :f, :g, :h)

    a = ww[(81 - j) % 8]
    b = ww[(82 - j) % 8]
    c = ww[(83 - j) % 8]
    d = ww[(84 - j) % 8]
    e = ww[(85 - j) % 8]
    f = ww[(86 - j) % 8]
    g = ww[(87 - j) % 8]
    h = ww[(88 - j) % 8]

    if T == 512
        Sigma0 = :Sigma0_512
        Sigma1 = :Sigma1_512
        K = :K512
    elseif T == 256
        Sigma0 = :Sigma0_256
        Sigma1 = :Sigma1_256
        K = :K256
    end

    return esc(quote
        # We byteswap every input byte
        v = bswap(unsafe_load(pbuf, $j-1))
        unsafe_store!(pbuf, v, $j-1)

        # Apply the SHA-256 compression function to update a..h
        T1 = $h + $Sigma1($e) + Ch($e, $f, $g) + $K[$j-1] + v
        $h = $Sigma0($a) + Maj($a, $b, $c)
        $d += T1
        $h += T1
    end)
end

macro R17_80(j, T)

    ww = (:a, :b, :c, :d, :e, :f, :g, :h)

    a = ww[(81 - j) % 8]
    b = ww[(82 - j) % 8]
    c = ww[(83 - j) % 8]
    d = ww[(84 - j) % 8]
    e = ww[(85 - j) % 8]
    f = ww[(86 - j) % 8]
    g = ww[(87 - j) % 8]
    h = ww[(88 - j) % 8]

    if T == 512
        Sigma0 = :Sigma0_512
        Sigma1 = :Sigma1_512
        sigma0 = :sigma0_512
        sigma1 = :sigma1_512
        K = :K512
    elseif T == 256
        Sigma0 = :Sigma0_256
        Sigma1 = :Sigma1_256
        sigma0 = :sigma0_256
        sigma1 = :sigma1_256
        K = :K256
    end

    return esc(quote
        s0 = unsafe_load(pbuf, mod($j, 16))
        s0 = $sigma0(s0)
        s1 = unsafe_load(pbuf, mod($j + 13, 16))
        s1 = $sigma1(s1)

        # Apply the SHA-256 compression function to update a..h
        v = unsafe_load(pbuf, mod($j - 1, 16)) + s1 + unsafe_load(pbuf, mod($j + 8, 16)) + s0
        unsafe_store!(pbuf, v, mod($j - 1, 16))
        T1 = $h + $Sigma1($e) + Ch($e, $f, $g) + $K[$j-1] + v
        $h = $Sigma0($a) + Maj($a, $b, $c)
        $d += T1
        $h += T1
    end)
end

macro R_init(T)
    expr = :()
    for i in 1:16
        expr = :($expr; @R1_16($i, $T))
    end
    return esc(expr)
end

macro R_end(T)

    if T == 256
        n_rounds = 64
    elseif T == 512
        n_rounds = 80
    end

    expr = :()
    for i in 17:n_rounds
        expr = :($expr; @R17_80($i, $T))
    end

    return esc(expr)
end

@generated function transform!(context::Union{SHA2_224_CTX, SHA2_256_CTX,
                                              SHA2_384_CTX, SHA2_512_CTX,
                                              SHA2_512_224_CTX, SHA512_256_CTX})
    if context <: Union{SHA2_224_CTX,SHA2_256_CTX}
        T = 256
    elseif context <: Union{SHA2_384_CTX,SHA2_512_CTX,SHA2_512_224_CTX,SHA512_256_CTX}
        T = 512
    end

    return quote
        pbuf = buffer_pointer(context)
        # Initialize registers with the previous intermediate values (our state)
        a, b, c, d, e, f, g, h = context.state

        # Initial Rounds
        @R_init($T)

        # Other Rounds
        @R_end($T)

        # Compute the current intermediate hash value
        @inbounds begin
            context.state[0] += a
            context.state[1] += b
            context.state[2] += c
            context.state[3] += d
            context.state[4] += e
            context.state[5] += f
            context.state[6] += g
            context.state[7] += h
        end
    end
end
