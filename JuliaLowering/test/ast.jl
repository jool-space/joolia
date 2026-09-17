let node = JS.newleaf(LineNumberNode(1), K"Value", nothing)
    @test node.value === nothing
end

@testset "assert_syntaxtree" begin
    st = parsestmt(SyntaxTree, "function foo end")
    @test JuliaLowering.assert_syntaxtree(st) === nothing

    bad_st = JuliaSyntax.newleaf(st, K"Identifier")
    @test_throws "needs value" JuliaLowering.assert_syntaxtree(bad_st)
    @test_throws "needs value" show(bad_st)

    bad_st = JuliaSyntax.newleaf(st, K"code_info")
    @test_throws "unrecognized leaf kind" JuliaLowering.assert_syntaxtree(bad_st)

    setfield!(bad_st, :children, SyntaxList(bad_st))
    @test_throws "cycle detected" JuliaLowering.assert_syntaxtree(bad_st)

    cyc_1 = JuliaSyntax.newnode(st, K"block", SyntaxList())
    cyc_2 = JuliaSyntax.newnode(st, K"block", SyntaxList(cyc_1))
    setfield!(cyc_1, :children, SyntaxList(cyc_2))
    @test_throws "cycle detected" JuliaLowering.assert_syntaxtree(cyc_1)
    @test_throws "cycle detected" JuliaLowering.assert_syntaxtree(cyc_2)
end

@testset "zero-origin AST positions" begin
    st = @ast_ [K"call" [K"parameters"] [K"Identifier" "x"]]
    @test firstindex(st) == 0
    @test lastindex(st) == 1
    @test kind(st[0]) == K"parameters"
    @test kind(st[1]) == K"Identifier"
    @test JuliaLowering.find_parameters_ind(children(st)) == 0
    @test JuliaLowering.has_parameters(st)

    plain = @ast_ [K"call" [K"Identifier" "x"]]
    @test JuliaLowering.find_parameters_ind(children(plain)) == -1
    @test !JuliaLowering.has_parameters(plain)

    empty = @ast_ [K"call" [K"parameters"]]
    @test isempty(JuliaLowering.remove_empty_parameters(children(empty)))
end

@testset "flatten_blocks" begin
    let
        st = @ast_ [K"block"]
        @test JuliaLowering.flatten_blocks(st) ≈
            @ast_ [K"block"]

        st = @ast_ [K"block" 1::K"Value"]
        @test JuliaLowering.flatten_blocks(st) ≈
            @ast_ [K"block" 1::K"Value"]

        st = @ast_ [K"block" 1::K"Value" [K"block" 1::K"Value"]]
        @test JuliaLowering.flatten_blocks(st) ≈
            @ast_ [K"block" 1::K"Value" 1::K"Value"]

        st = @ast_ [K"inert" [K"block" 1::K"Value" [K"block" 1::K"Value"]]]
        @test JuliaLowering.flatten_blocks(st) ≈
            @ast_ [K"inert" [K"block" 1::K"Value" [K"block" 1::K"Value"]]]

        st = @ast_ [K"block" 1::K"Value" [K"block"]]
        @test JuliaLowering.flatten_blocks(st) ≈
            @ast_ [K"block" 1::K"Value" (::K"nothing")]

        st = @ast_ [K"block" 1::K"Value" [K"block"] 1::K"Value"]
        @test JuliaLowering.flatten_blocks(st) ≈
            @ast_ [K"block" 1::K"Value" 1::K"Value"]

        st = @ast_ [K"block" [K"inert" [K"block" 1::K"Value" [K"block" 1::K"Value"]]]]
        @test JuliaLowering.flatten_blocks(st) ≈
            @ast_ [K"block" [K"inert" [K"block" 1::K"Value" [K"block" 1::K"Value"]]]]

        # repeat with call wrapper
        st = @ast_ [K"call" [K"block"]]
        @test JuliaLowering.flatten_blocks(st) ≈
            @ast_ [K"call" [K"block"]]

        st = @ast_ [K"call" [K"block" 1::K"Value"]]
        @test JuliaLowering.flatten_blocks(st) ≈
            @ast_ [K"call" [K"block" 1::K"Value"]]

        st = @ast_ [K"call" [K"block" 1::K"Value" [K"block" 1::K"Value"]]]
        @test JuliaLowering.flatten_blocks(st) ≈
            @ast_ [K"call" [K"block" 1::K"Value" 1::K"Value"]]

        st = @ast_ [K"call" [K"inert" [K"block" 1::K"Value" [K"block" 1::K"Value"]]]]
        @test JuliaLowering.flatten_blocks(st) ≈
            @ast_ [K"call" [K"inert" [K"block" 1::K"Value" [K"block" 1::K"Value"]]]]

        st = @ast_ [K"call" [K"block" 1::K"Value" [K"block"]]]
        @test JuliaLowering.flatten_blocks(st) ≈
            @ast_ [K"call" [K"block" 1::K"Value" (::K"nothing")]]

        st = @ast_ [K"call" [K"block" 1::K"Value" [K"block"] 1::K"Value"]]
        @test JuliaLowering.flatten_blocks(st) ≈
            @ast_ [K"call" [K"block" 1::K"Value" 1::K"Value"]]

        st = @ast_ [K"call" [K"block" [K"inert" [K"block" 1::K"Value" [K"block" 1::K"Value"]]]]]
        @test JuliaLowering.flatten_blocks(st) ≈
            @ast_ [K"call" [K"block" [K"inert" [K"block" 1::K"Value" [K"block" 1::K"Value"]]]]]
    end
end
