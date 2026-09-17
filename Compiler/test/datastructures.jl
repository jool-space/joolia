# This file is a part of Julia. License is MIT: https://julialang.org/license

# Check compiler data structures without requiring an already-built system image.
if Core.Intrinsics.not_int(Core.isdefined(Base, :end_base_include))
    Core.eval(Core.Main, :(module JooliaCompilerFoundationTests
    const CC = Base.Compiler
    const checks = Base.RefValue(0)
    function check(ok::Bool, label::String)
        ok || throw(ErrorException(label))
        checks[] += 1
    end
    optimizer_probe(x) = x
    variadic_probe(x,ys...) = ys
    expanded_variadic_probe(x,y,zs...) = zs
    ir_child_frame_probe(x::Int) = x + 1
    ir_parent_frame_probe(x::Int) = ir_child_frame_probe(x)
    function run()
        check(CC.anymap(identity, Any[2,3]) == Any[2,3], "compiler anymap positions")
        check(isempty(CC.anymap(identity, Any[])), "empty compiler anymap")
        check(CC.count_const_size((1,:x)) > 0, "constant field traversal")
        check(CC.sort!([3,1,2]) == [1,2,3], "compiler insertion sort")
        check(CC.sort!([2,2,1]) == [1,2,2], "compiler sort duplicates")
        check(isempty(CC.sort!(Int[])), "compiler sort empty")
        check(CC.searchsortedfirst([2,4,6],2) == 0, "compiler search first position")
        check(CC.searchsortedlast([2,4,6],1) == -1, "compiler search before first")
        check(CC.searchsortedfirst([2,4,6],7) == 3, "compiler search after last")
        check(CC.nth_union_component(Union{Int,String},0) === Int || CC.nth_union_component(Union{Int,String},0) === String, "union first component")
        check(CC.nth_union_component(Union{Int,String},0) !== CC.nth_union_component(Union{Int,String},1), "union distinct components")
        check(CC.find_tfunc(Core.throw) == 0, "builtin table first position")
        intr = Core.Intrinsics.add_int
        idx = reinterpret(Int32,intr)
        check(CC.T_IFUNC[idx][2] isa Function, "intrinsic table and tuple positions")
        body = Any[Expr(:call,identity,Core.SSAValue(1)),Core.ReturnNode(Core.SSAValue(1))]
        uses = CC.find_ssavalue_uses(body,2)
        check(collect(Int,uses[1]) == [1,2], "SSA IDs translated to storage")
        check(isempty(uses[2]), "SSA no uses")
        emptyuses = CC.find_ssavalue_uses(Any[],0)
        check(emptyuses.offsets == [0] && isempty(emptyuses.data), "empty SSA use storage")
        check(length(CC.VALID_EXPR_HEADS[:call]) > 1, "expression argument bounds remain counts")
        L = CC.fallback_lattice
        invoke_args = Any[:invoke,:f,:sig,:x,:y]
        invoke_rewritten = CC.invoke_rewrite(invoke_args)
        check(invoke_rewritten == Any[:f,:x,:y], "invoke rewrite removes signature")
        check(CC.invoke_rewrite(Any[:invoke,:f,:sig]) == Any[:f], "invoke rewrite handles zero arguments")
        check(CC.getfield_tfunc(L, Tuple, Int) === Any, "getfield generic tuple integer index")
        check(CC.getfield_tfunc(L, Tuple{Vararg{Int}}, CC.Const(0)) === Int, "getfield vararg tuple first index")
        check(CC.getfield_tfunc(L, Tuple{Vararg{Int}}, CC.Const(1)) === Int, "getfield vararg tuple second index")
        check(CC.getfield_tfunc(L, Tuple{String,Vararg{Int}}, CC.Const(1)) === Int, "getfield trailing vararg tuple index")
        check(CC.datatype_min_ninitialized(NamedTuple{(:x,),Tuple{Int}}) == 1, "NamedTuple initialized field count")
        check(CC.datatype_min_ninitialized(NamedTuple{(),Tuple{}}) == 0, "empty NamedTuple initialized field count")
        nt_unknown = (NamedTuple{names,Tuple{Int}} where names)
        check(CC.datatype_min_ninitialized(nt_unknown) == 1, "open NamedTuple initialized field count")
        r = CC.isdefined_tfunc(L, nt_unknown, CC.Const(0))
        check(r isa CC.Const && Core.getfield(r, :val) === true, "open NamedTuple first field is defined")
        r = CC.isdefined_tfunc(L, nt_unknown, CC.Const(1))
        check(r === Bool || (r isa CC.Const && Core.getfield(r, :val) === false), "open NamedTuple upper field is not known defined")
        check(!CC._fieldtype_nothrow(Tuple{Vararg{Int}}, false, true, CC.Const(0)), "fieldtype vararg tuple may throw")
        r = CC.fieldtype_tfunc(L, CC.Const(Tuple{Vararg{Int}}), CC.Const(0))
        check(r isa CC.Const && Core.getfield(r, :val) === Int, "fieldtype vararg tuple first index")
        check(CC.try_compute_fieldidx(Pair{Int,Int}, :first) == 0, "field symbol starts at zero")
        check(CC.try_compute_fieldidx(Pair{Int,Int}, 0) == 0, "field zero is valid")
        check(CC.try_compute_fieldidx(Pair{Int,Int}, -1) === nothing, "negative field is invalid")
        check(CC.try_compute_fieldidx(Pair{Int,Int}, 2) === nothing, "field upper bound is invalid")
        check(CC._fieldtype_nothrow(Pair{Int,Int}, true, true, CC.Const(0)), "fieldtype zero is infallible")
        check(!CC._fieldtype_nothrow(Pair{Int,Int}, true, true, CC.Const(-1)), "fieldtype negative can throw")
        check(!CC._fieldtype_nothrow(Pair{Int,Int}, true, true, CC.Const(2)), "fieldtype upper bound can throw")
        r = CC.isdefined_tfunc(L, CC.Const((17,29)), CC.Const(0))
        check(r isa CC.Const && Core.getfield(r, :val) === true, "isdefined tuple zero")
        r = CC.isdefined_tfunc(L, CC.Const((17,29)), CC.Const(-1))
        check(r isa CC.Const && Core.getfield(r, :val) === false, "isdefined tuple negative")
        r = CC.isdefined_tfunc(L, CC.Const((17,29)), CC.Const(2))
        check(r isa CC.Const && Core.getfield(r, :val) === false, "isdefined tuple upper bound")
        r = CC.isdefined_tfunc(L, CC.Const(Pair{Int,Int}(17,29)), CC.Const(0))
        check(r isa CC.Const && Core.getfield(r, :val) === true, "isdefined struct zero")
        r = CC.isdefined_tfunc(L, CC.Const(Pair{Int,Int}(17,29)), CC.Const(1))
        check(r isa CC.Const && Core.getfield(r, :val) === true, "isdefined struct last")
        r = CC.isdefined_tfunc(L, CC.Const(Pair{Int,Int}(17,29)), CC.Const(-1))
        check(r isa CC.Const && Core.getfield(r, :val) === false, "isdefined struct negative")
        r = CC.isdefined_tfunc(L, CC.Const(Pair{Int,Int}(17,29)), CC.Const(2))
        check(r isa CC.Const && Core.getfield(r, :val) === false, "isdefined struct upper bound")
        r = CC.getfield_tfunc(L, CC.Const(Pair{Int,Int}(17,29)), CC.Const(1))
        check(r isa CC.Const && Core.getfield(r, :val) === 29, "getfield struct last")
        check(CC.getfield_tfunc(L, CC.Const(Pair{Int,Int}(17,29)), CC.Const(-1)) === CC.Bottom, "getfield struct negative")
        check(CC.getfield_tfunc(L, CC.Const(Pair{Int,Int}(17,29)), CC.Const(2)) === CC.Bottom, "getfield struct upper bound")
        r = CC.getfield_tfunc(L, CC.Const((17,29)), CC.Const(0))
        check(r isa CC.Const && Core.getfield(r, :val) === 17, "getfield tuple zero")
        ps = Core.PartialStruct(L, Tuple{Int,Int}, Any[CC.Const(17), CC.Const(29)])
        r = CC.getfield_tfunc(L, ps, CC.Const(0))
        check(r isa CC.Const && Core.getfield(r, :val) === 17, "getfield partial struct zero")
        # The final zero-origin field of a partial tuple may be a Vararg marker.
        va_type = Tuple{Type,Vararg{Type}}
        va_partial = Core.PartialStruct(L, va_type, Any[Type, Vararg{Type}])
        va_precise = Core.PartialStruct(L, va_type, Any[CC.Const(Int), Vararg{Type}])
        check(CC.:(⊑)(L, va_partial, va_partial), "partial Vararg tuple reflexivity")
        check(CC.:(⊑)(L, va_precise, va_partial), "partial Vararg tuple precision")
        check(!CC.:(⊑)(L, va_partial, va_precise), "partial Vararg tuple rejects lost precision")
        check(CC.:(⊑)(L, CC.Const((Int,Float64)), va_partial), "constant tuple unwraps final Vararg")
        check(!CC.:(⊑)(L, CC.Const((Int,:bad)), va_partial), "constant tuple rejects final Vararg mismatch")
        fixed_partial = Core.PartialStruct(L, Tuple{Int,Int}, Any[CC.Const(17),Int])
        check(CC.:(⊑)(L, CC.Const((17,29)), fixed_partial), "constant tuple last partial field")
        check(!CC.:(⊑)(L, CC.Const((18,29)), fixed_partial), "constant tuple partial field mismatch")
        r = CC.tuple_tfunc(L, Any[])
        check(r isa CC.Const && Core.getfield(r, :val) === (), "empty tuple inference")
        r = CC.tuple_tfunc(L, Any[CC.Const(17), CC.Const(29)])
        check(r isa CC.Const && Core.getfield(r, :val) === (17,29), "tuple constant positions")
        check(CC.memoryref_tfunc(L, Memory{Int}) === MemoryRef{Int}, "memoryref element type")
        check(CC.memoryref_builtin_common_nothrow(Any[Memory{Int}, CC.Const(0), CC.Const(false)]), "memoryref inbounds zero")
        check(!CC.memoryref_builtin_common_nothrow(Any[Memory{Int}, CC.Const(0), CC.Const(true)]), "memoryref checked bounds remain unknown")
        check(!CC.memoryref_builtin_common_nothrow(Any[Memory{Int}, CC.Const(-1), CC.Const(true)]), "memoryref negative index")
        check(CC.pointerref_tfunc(L, Ptr{Int}, CC.Const(0), CC.Const(1)) === Int, "pointerref zero offset")
        check(CC.pointerref_tfunc(L, Ptr{Int}, CC.Const(-1), CC.Const(1)) === Int, "pointerref signed offset")
        emptyheap = Int[]
        check(CC.heapify!(emptyheap, CC.Forward) === emptyheap && isempty(emptyheap), "empty heap")
        singleton = Int[9]
        CC.heapify!(singleton, CC.Forward)
        check(CC.heappop!(singleton, CC.Forward) == 9 && isempty(singleton), "singleton heap")
        heap = Int[201 - i for i in 0:201]
        CC.heapify!(heap, CC.Forward)
        heapok = true
        for i in 0:201
            heapok &= CC.heappop!(heap, CC.Forward) == i
        end
        check(heapok && isempty(heap), "large heap ordering")
        heap = Int[]
        for i in 201:-1:0
            CC.heappush!(heap, i, CC.Forward)
        end
        heapok = true
        for i in 0:201
            heapok &= CC.heappop!(heap, CC.Forward) == i
        end
        check(heapok && isempty(heap), "large heap push ordering")
        ds = CC.EscapeAnalysis.IntDisjointSet{Int}(4)
        check(length(ds) == 4 && CC.EscapeAnalysis.num_groups(ds) == 4, "union-find initial counts")
        check(ds.parents[0] == 1 && ds.parents[1] == 2 && ds.parents[3] == 4, "union-find IDs remain one-origin")
        check(CC.EscapeAnalysis.find_root!(ds, 1) == 1 && CC.EscapeAnalysis.find_root!(ds, 4) == 4, "union-find initial roots")
        check(CC.EscapeAnalysis.union!(ds, 1, 2) == 1 && CC.EscapeAnalysis.union!(ds, 3, 4) == 3, "union-find unions")
        check(CC.EscapeAnalysis.in_same_set(ds, 1, 2) && !CC.EscapeAnalysis.in_same_set(ds, 1, 3), "union-find set membership")
        check(CC.EscapeAnalysis.union!(ds, 1, 3) == 1 && CC.EscapeAnalysis.find_root!(ds, 4) == 1 && CC.EscapeAnalysis.num_groups(ds) == 1, "union-find path compression")
        new_id = CC.EscapeAnalysis.push!(ds)
        check(new_id == 5 && CC.EscapeAnalysis.find_root!(ds, new_id) == 5 && CC.EscapeAnalysis.num_groups(ds) == 2, "union-find push ID")
        ea = CC.EscapeAnalysis
        short_alias = ea.IndexableFields(2)
        long_alias = ea.IndexableFields(3)
        push!(short_alias.infos[0], :short0)
        push!(short_alias.infos[1], :short1)
        push!(long_alias.infos[0], :long0)
        push!(long_alias.infos[1], :long1)
        push!(long_alias.infos[2], :long2)
        short_escape = ea.EscapeInfo(true, false, Base.BitSet(), short_alias, Base.BitSet())
        long_escape = ea.EscapeInfo(true, false, Base.BitSet(), long_alias, Base.BitSet())
        join_escape = ea.:(⊔ₑ)
        merged_lr = join_escape(short_escape, long_escape)
        merged_rl = join_escape(long_escape, short_escape)
        check(length(merged_lr.AliasInfo.infos) == 3 && length(merged_rl.AliasInfo.infos) == 3, "alias join retains longer IndexableFields")
        check(merged_lr.AliasInfo.infos[0] == merged_rl.AliasInfo.infos[0] && merged_lr.AliasInfo.infos[1] == merged_rl.AliasInfo.infos[1], "alias join is operand-order independent")
        check(:short0 in merged_lr.AliasInfo.infos[0] && :long0 in merged_lr.AliasInfo.infos[0] && :short1 in merged_lr.AliasInfo.infos[1] && :long1 in merged_lr.AliasInfo.infos[1], "alias join unions shared indexed data")
        check(:long2 in merged_lr.AliasInfo.infos[2] && merged_lr.AliasInfo.infos[2] == merged_rl.AliasInfo.infos[2], "alias join preserves longer tail data")
        foreign = Expr(:foreigncall, QuoteNode(:callee), Cvoid, Core.svec(Int), 0,
                       QuoteNode(:ccall), Core.SSAValue(1), Core.SSAValue(2), Core.SSAValue(3))
        preserved = CC.form_new_preserves(foreign, [2], Any[Core.SSAValue(4)])
        check(preserved.head === :foreigncall && preserved.args[0:5] == foreign.args[0:5], "foreigncall preserves retain metadata and operands")
        check(preserved.args[6:end] == Any[Core.SSAValue(3),Core.SSAValue(4)], "foreigncall replaces only selected GC roots")
        foreign0 = Expr(:foreigncall, QuoteNode(:callee), Cvoid, Core.svec(), 0,
                        QuoteNode(:ccall), Core.SSAValue(1))
        preserved0 = CC.form_new_preserves(foreign0, [1], Any[])
        check(length(preserved0.args) == 5 && preserved0.args == foreign0.args[0:4], "zero-argument foreigncall preserves metadata")
        aliases = [0,1,1,2]
        CC.clear_slot_aliases!(aliases,1)
        check(aliases == [0,0,0,2], "clear aliases by native slot ID")
        aliases = [0,0,0]
        CC.update_alias_table!(aliases,Expr(:(=),Core.SlotNumber(3),Core.SlotNumber(1)),Any[])
        check(aliases == [0,0,1], "alias assignment to last slot")
        CC.update_alias_table!(aliases,Expr(:(=),Core.SlotNumber(2),Core.SSAValue(1)),Any[Core.SlotNumber(3)])
        check(aliases == [0,1,1], "alias assignment follows SSA and root slot")
        CC.update_alias_table!(aliases,Core.NewvarNode(Core.SlotNumber(1)),Any[])
        check(aliases == [0,0,0], "new variable clears dependent aliases")
        aliases = [0,1,2]
        check(CC.intersect_alias_tables!(aliases,[0,1,1]) && aliases == [0,1,0], "alias merge at control-flow join")
        check(!CC.intersect_alias_tables!(aliases,[0,1,0]), "unchanged alias merge")
        check(!CC.intersect_alias_tables!(Int[],Int[]), "empty alias merge")
        state = CC.VarState[CC.VarState(Any,7,false),CC.VarState(Any,8,false)]
        cnd = CC.Conditional(2,8,Int,String)
        check(CC.conditional_valid(cnd,state), "conditional validity at last slot")
        check(!CC.conditional_valid(CC.Conditional(2,7,Int,String),state), "stale conditional definition")
        refinement = CC.conditional_change(L,state,cnd,:then)
        check(refinement isa CC.StateRefinement && refinement.slot == 2 && refinement.newtyp === Int, "conditional native slot refinement")
        CC.strefine1!(state,refinement)
        check(state[0].typ === Any && state[1].typ === Int && state[1].ssadef == 8, "refinement changes only target storage")
        state = CC.VarState[CC.VarState(Any,7,false),CC.VarState(Any,8,false)]
        CC.apply_refinement!(L,Core.SlotNumber(1),Int,state,nothing,[0,1])
        check(state[0].typ === Int && state[1].typ === Int, "slot refinement propagates to alias")
        cnd = CC.conditional_argtype(L,Bool,Tuple{Int,String},Any[Any,Any],1)
        check(cnd.slot == 1 && cnd.thentype === Int, "signature fields translate native argument IDs")
        stream = CC.InstructionStream(2)
        stream[1][:stmt] = Core.ReturnNode(10)
        stream[2][:stmt] = Core.ReturnNode(20)
        check(stream.stmt[0].val == 10 && stream.stmt[1].val == 20, "instruction IDs translate once into raw storage")
        check(iterate(stream)[0].idx == 1 && iterate(stream,1)[0].idx == 2 && iterate(stream,2) === nothing, "instruction iteration preserves native IDs")
        effects_ir = CC.IRCode()
        flags = CC.stmt_effect_flags(L,Expr(:call,Core.getfield,QuoteNode((10,20)),0),Int,effects_ir)
        check(flags[2], "getfield zero effect analysis visits both operands")
        flags = CC.new_expr_effect_flags(L,Any[Pair{Int,Int},1,2],effects_ir)
        check(flags == (false,true,true), "new expression effect analysis uses zero-based fields")
        push!(effects_ir.sptypes,CC.VarState(CC.Const(Int),0,false))
        check(CC.stmt_effect_flags(L,Expr(:static_parameter,1),Type{Int},effects_ir) == (true,true,true), "static parameter native ID translation")
        parent_compact = CC.IncrementalCompact(CC.IRCode())
        nested_compact = CC.IncrementalCompact(parent_compact,CC.IRCode(),1)
        nested_step = iterate(nested_compact)
        check(nested_step[0][0] == (1=>1) && nested_step[0][1] isa Core.ReturnNode && iterate(nested_compact) === nothing, "nested compaction starts at native instruction one")
        compacted = CC.compact!(CC.IRCode())
        check(length(compacted.stmts) == 1 && compacted[Core.SSAValue(1)][:stmt] isa Core.ReturnNode && compacted[Core.SSAValue(1)][:stmt].val === nothing, "IR compaction Pair components and native instruction IDs")
        # Inserting a refinement for the current typeassert must rename its native SSA ID.
        assert_stream = CC.InstructionStream(3)
        assert_stream[1][:stmt] = Expr(:call, Core.typeassert, Core.Argument(2), Int)
        assert_stream[2][:stmt] = Expr(:call, GlobalRef(Base, :identity), Core.SSAValue(1))
        assert_stream[3][:stmt] = Core.ReturnNode(Core.SSAValue(2))
        for i in 1:3
            assert_stream[i][:type] = Int
            assert_stream[i][:line] = CC.NoLineUpdate
            assert_stream[i][:info] = CC.NoCallInfo()
            assert_stream[i][:flag] = UInt32(0)
        end
        assert_ir = CC.IRCode(assert_stream,
            CC.CFG(CC.BasicBlock[CC.BasicBlock(CC.StmtRange(1,3),Int[0],Int[])],Int[4]),
            CC.DebugInfoStream(assert_stream.line),Any[Any,Any],Expr[],CC.VarState[])
        assert_compact = CC.IncrementalCompact(assert_ir)
        assert_step = iterate(assert_compact)
        CC.canonicalize_typeassert!(assert_compact,1,assert_step[0][1])
        check(assert_compact.ssa_rename[0] == Core.SSAValue(2), "typeassert refinement renames current SSA")
        for _ in assert_compact; end
        assert_result = CC.complete(assert_compact)
        CC.verify_ir(assert_result)
        check(assert_result[Core.SSAValue(3)][:stmt].args[1] == Core.SSAValue(2), "typeassert users consume inserted refinement")
        va_ir = CC.IRCode()
        va_compact = CC.IncrementalCompact(va_ir)
        va_args = Any[11,22,33]
        va_fixed = CC.fix_va_argexprs!(CC.InsertHere(va_compact), va_compact, va_args, 2, CC.NoLineUpdate)
        va_tuple_ssa = va_fixed[1]
        va_tuple_stmt = va_compact[va_tuple_ssa][:stmt]
        check(length(va_fixed) == 2 && va_fixed[0] === 11, "variadic fixup preserves first fixed argument")
        check(va_tuple_stmt isa Expr && va_tuple_stmt.args[0] === CC.TOP_TUPLE && va_tuple_stmt.args[1] === 22 && va_tuple_stmt.args[2] === 33, "variadic fixup packs complete tail")
        dstream = CC.InstructionStream(4)
        dstream[1][:stmt] = Core.GotoIfNot(true, 3)
        dstream[2][:stmt] = Core.GotoIfNot(false, 4)
        dstream[3][:stmt] = Core.ReturnNode(30)
        dstream[4][:stmt] = Core.ReturnNode(40)
        for d in 1:4
            dstream[d][:type] = Any
            dstream[d][:line] = CC.NoLineUpdate
        end
        dblocks = CC.BasicBlock[
            CC.BasicBlock(CC.StmtRange(1,1), Int[0], Int[2,3]),
            CC.BasicBlock(CC.StmtRange(2,2), Int[1], Int[3,4]),
            CC.BasicBlock(CC.StmtRange(3,3), Int[1,2], Int[]),
            CC.BasicBlock(CC.StmtRange(4,4), Int[2], Int[])]
        dir = CC.IRCode(dstream, CC.CFG(dblocks, Int[2,3,4,5]), CC.DebugInfoStream(dstream.line), Any[], Expr[], CC.VarState[])
        CC.verify_ir(dir)
        # Block-start vectors include the entry block; their insertion position is already the native block ID.
        check(CC.block_for_inst(dblocks, 1) == 1 && CC.block_for_inst(dblocks, 4) == 4, "block vector lookup first and last native IDs")
        lookup_blocks = CC.BasicBlock[CC.BasicBlock(CC.StmtRange(1,3)), CC.BasicBlock(CC.StmtRange(4,7))]
        check(CC.block_for_inst(lookup_blocks, 3) == 1 && CC.block_for_inst(lookup_blocks, 4) == 2 && CC.block_for_inst(lookup_blocks, 7) == 2, "block vector lookup preserves boundaries")
        lookup_compact = CC.IncrementalCompact(CC.copy(dir))
        for _ in lookup_compact; end
        check(CC.block_for_inst(lookup_compact, Core.SSAValue(1)) == 1 && CC.block_for_inst(lookup_compact, Core.SSAValue(4)) == 4, "compacted block lookup preserves native IDs")
        ddom = CC.construct_domtree(dir)
        dsorted = CC.domsort_ssa!(dir, ddom)
        CC.verify_ir(dsorted)
        check(length(dsorted.stmts) == 5, "domsort critical-edge reorder inserts one goto")
        check(dsorted[Core.SSAValue(1)][:stmt] isa Core.GotoIfNot && dsorted[Core.SSAValue(1)][:stmt].dest == 5, "domsort renames branch destination")
        check(dsorted[Core.SSAValue(2)][:stmt] isa Core.GotoIfNot && dsorted[Core.SSAValue(2)][:stmt].dest == 4, "domsort preserves reordered branch edge")
        domsort_gotos = 0
        for di = 1:length(dsorted.stmts)
            domsort_gotos += dsorted[Core.SSAValue(di)][:stmt] isa Core.GotoNode
        end
        check(domsort_gotos > 0, "domsort inserts critical-edge goto")
        dcompacted = CC.compact!(dsorted)
        CC.verify_ir(dcompacted)
        check(length(dcompacted.cfg.blocks) == length(dsorted.cfg.blocks), "compaction preserves reordered CFG blocks")
        inline_state = CC.CFGInliningState(dir)
        inline_state.new_cfg_blocks = CC.BasicBlock[
            CC.BasicBlock(CC.StmtRange(1,1), Int[], Int[]),
            CC.BasicBlock(CC.StmtRange(1,1), Int[], Int[]),
            CC.BasicBlock(CC.StmtRange(1,1), Int[], Int[])]
        inline_state.first_bb = 1
        inline_state.bb_rename[0] = 1
        CC.finish_cfg_inline!(inline_state)
        check(inline_state.new_cfg_blocks[3].preds[0] == 3, "CFG inline maps split predecessor to generated tail")
        check(inline_state.new_cfg_blocks[4].preds[0] == 3 && inline_state.new_cfg_blocks[4].preds[1] == 4, "CFG inline preserves multiple split predecessors")
        for condition in (true, false)
            guard_stream = CC.InstructionStream(2)
            guard_stream[1][:stmt] = Expr(:throw_undef_if_not, :guarded_variable, condition)
            guard_stream[1][:type] = Nothing
            guard_stream[2][:stmt] = Core.ReturnNode(10)
            guard_stream[2][:type] = Int
            guard_ir = CC.IRCode(guard_stream,
                CC.CFG(CC.BasicBlock[CC.BasicBlock(CC.StmtRange(1,2), Int[], Int[])], Int[3]),
                CC.DebugInfoStream(guard_stream.line), Any[], Expr[], CC.VarState[])
            guard_result = CC.compact!(guard_ir)
            CC.verify_ir(guard_result)
            check(length(guard_result.stmts) == (condition ? 1 : 2), "compaction folds only a true undefined-variable guard")
        end
        pending_stream = CC.InstructionStream(2)
        pending_stream[1][:stmt] = Expr(:call, Core.tuple, 10)
        pending_stream[1][:type] = Any
        pending_stream[2][:stmt] = Core.ReturnNode(20)
        pending_stream[2][:type] = Int
        pending_ir = CC.IRCode(pending_stream,
            CC.CFG(CC.BasicBlock[CC.BasicBlock(CC.StmtRange(1,2), Int[], Int[])], Int[3]),
            CC.DebugInfoStream(pending_stream.line), Any[], Expr[], CC.VarState[])
        pending_compact = CC.IncrementalCompact(pending_ir)
        pending_first = CC.insert_node!(pending_compact, Core.SSAValue(2),
            CC.NewInstruction(Expr(:call, Core.tuple, 11), Any, CC.NoLineUpdate))
        pending_second = CC.insert_node!(pending_compact, Core.SSAValue(2),
            CC.NewInstruction(Expr(:call, Core.tuple, pending_first), Any, CC.NoLineUpdate))
        pending_ir[Core.SSAValue(2)][:stmt] = Core.ReturnNode(pending_second)
        check(!CC.already_inserted(pending_compact, pending_first) && !CC.already_inserted(pending_compact, pending_second), "pending insertions are not ready before drain")
        for _ in pending_compact
        end
        check(CC.already_inserted(pending_compact, pending_first) && CC.already_inserted(pending_compact, pending_second), "pending insertions become ready after drain")
        pending_result = CC.finish(pending_compact)
        CC.verify_ir(pending_result)
        pending_second_stmt = pending_result[Core.SSAValue(3)][:stmt]
        check(pending_first isa CC.OldSSAValue && pending_second isa CC.OldSSAValue && length(pending_result.stmts) == 4, "pending insertions retain both native IDs")
        check(pending_second_stmt isa Expr && pending_second_stmt.args[1] isa Core.SSAValue && pending_second_stmt.args[1].id == 2, "pending insertion remaps prior pending reference")
        sroa_stream = CC.InstructionStream(3)
        sroa_stream[1][:stmt] = Expr(:new, Tuple{Int,Int}, 11, 22)
        sroa_stream[1][:type] = Tuple{Int,Int}
        sroa_stream[2][:stmt] = Expr(:call, Core.getfield, Core.SSAValue(1), 0)
        sroa_stream[2][:type] = Int
        sroa_stream[3][:stmt] = Core.ReturnNode(Core.SSAValue(2))
        sroa_stream[3][:type] = Int
        sroa_cfg = CC.CFG(CC.BasicBlock[CC.BasicBlock(CC.StmtRange(1,3), Int[], Int[])], Int[4])
        sroa_input = CC.IRCode(sroa_stream, sroa_cfg, CC.DebugInfoStream(sroa_stream.line), Any[], Expr[], CC.VarState[])
        CC.verify_ir(sroa_input)
        sroa_result = CC.sroa_pass!(sroa_input)
        CC.verify_ir(sroa_result)
        sroa_has_getfield = false
        for si = 1:length(sroa_result.stmts)
            ss = sroa_result[Core.SSAValue(si)][:stmt]
            sroa_has_getfield |= ss isa Expr && ss.head === :call && ss.args[0] === Core.getfield
        end
        check(!sroa_has_getfield, "SROA removes tuple getfield")
        pass_ir = CC.sroa_pass!(CC.IRCode())
        check(pass_ir isa CC.IRCode && length(pass_ir.stmts) == 1, "SROA pass handles minimal IR")
        pass_ir, pass_changed = CC.adce_pass!(pass_ir)
        check(pass_ir isa CC.IRCode && pass_changed isa Bool, "ADCE pass returns IR and change flag")
        pass_ir = CC.cfg_simplify!(pass_ir)
        CC.verify_ir(pass_ir)
        check(pass_ir isa CC.IRCode && length(pass_ir.cfg.blocks) == 1, "CFG simplify pass preserves minimal IR")
        di = CC.DebugInfoStream(Int32[10,0,0,20,0,0,20,0,0])
        di.def = :joolia_test
        debug = Core.DebugInfo(di,3)
        check(CC.getdebugidx(debug,1) == (Int32(10),Int32(0),Int32(0)), "debug native PC into zero-origin triples")
        check(CC.changed_lineinfo(debug,2,1) && !CC.changed_lineinfo(debug,3,2), "debug line change tuple positions")
        world = CC.get_world_counter()
        match = CC._methods_by_ftype(Tuple{typeof(optimizer_probe),Bool},1,world)[0]
        vamatch = CC._methods_by_ftype(Tuple{typeof(variadic_probe),Int},1,world)[0]
        vami = CC.specialize_method(vamatch)
        check(length(CC.most_general_argtypes(vamatch.method,vami.specTypes)) == 2, "empty vararg cache signature avoids uninitialized tail")
        va = CC.va_process_argtypes(L,Any[CC.Const(variadic_probe),CC.Const(1)],UInt(3),true,vami)
        check(length(va) == 3 && va[2] isa CC.Const && va[2].val == (), "empty vararg tuple occupies last native slot")
        va = CC.va_process_argtypes(L,Any[CC.Const(variadic_probe),CC.Const(1),CC.Const(20),CC.Const(30)],UInt(3),true,vami)
        check(va[2] isa CC.Const && va[2].val == (20,30), "vararg packing retains first tail argument")
        vamatch = CC._methods_by_ftype(Tuple{typeof(expanded_variadic_probe),Int,Int},1,world)[0]
        va = CC.most_general_argtypes(vamatch.method,Tuple{typeof(expanded_variadic_probe),Vararg{Int}})
        check(length(va) == 4 && va[1] === Int && va[2] === Int && CC.isvarargtype(va[3]), "vararg expansion preserves trailing Vararg marker")
        mi = CC.specialize_method(match)
        interp = CC.NativeInterpreter(world)
        frame = CC.InferenceState(CC.InferenceResult(mi),:no,interp)
        phi_first = Core.PhiNode(Int32[1], Any[17])
        phi_first_type = CC.abstract_eval_phi(interp, phi_first, CC.StatementState(nothing, false), frame)
        check(phi_first_type isa CC.Const && Core.getfield(phi_first_type, :val) === 17, "abstract eval phi retains first assigned value")
        order = Int[]
        dependency = CC.Future{Any}()
        push!(frame.tasks,(_, _) -> (push!(order,3); true))
        push!(frame.tasks,function (_, frame)
            push!(frame.tasks,(_, _) -> (dependency[] = :ready; push!(order,1); true))
            push!(frame.tasks,(_, _) -> (check(dependency[] === :ready,"deferred child consumes resolved Future"); push!(order,2); true))
            true
        end)
        while CC.doworkloop(interp,frame); end
        check(order == [1,2,3], "deferred work runs children before older siblings")
        # Reprocessing a call may schedule a real inference child.  The child is
        # appended to the parent's zero-origin callstack while its frameid stays
        # a one-origin depth; reprocess_instruction! must resume that child.
        world = CC.get_world_counter()
        parent_match = only(Base._methods_by_ftype(Tuple{typeof(ir_parent_frame_probe),Int}, 1, world))
        parent_mi = CC.specialize_method(parent_match)
        parent_src = CC.retrieve_code_info(parent_mi, world)
        parent_irsv = CC.IRInterpretationState(CC.NativeInterpreter(world), CC.SpecInfo(parent_src),
            CC.inflate_ir(parent_src, parent_mi), parent_mi, Any[Int], UInt(1), world)
        parent_irsv.ir[Core.SSAValue(1)][:type] = CC.Const(ir_child_frame_probe)
        parent_irsv.ir[Core.SSAValue(2)][:stmt].args[1] = Core.Argument(1)
        parent_rt, parent_effects = CC.ir_abstract_constant_propagation(parent_irsv.interp, parent_irsv)
        check(parent_rt === Int && parent_effects isa Tuple{Bool,Bool} && isempty(parent_irsv.callstack) && parent_irsv.frameid == 0,
            "IR reprocessing drains an actual child frame")
        src = CC.retrieve_code_info(mi,world)
        src.code = Any[Core.GotoIfNot(true,3),Expr(:call,Core.throw,QuoteNode(ErrorException("probe"))),Core.ReturnNode(1)]
        src.ssavaluetypes = Any[Any,Union{},Any]
        src.ssaflags = zeros(UInt32,3)
        src.debuginfo = debug
        opt = CC.OptimizationState(mi,src,interp)
        ir = CC.convert_to_ircode!(src,opt)
        check(length(ir.stmts) == 4 && length(ir.debuginfo.codelocs) == 12, "unreachable insertion grows code and debug metadata together")
        check(ir[Core.SSAValue(3)][:stmt] isa Core.ReturnNode && !isdefined(ir[Core.SSAValue(3)][:stmt],:val), "unreachable inserted immediately after throwing call")
        check(ir[Core.SSAValue(1)][:stmt].dest == 4 && last(ir.cfg.blocks[1].stmts) == 3, "insertion renumbers native branch and block endpoints")
        Core.println("joolia compiler foundation checks passed: ", checks[])
    end
    run()
    end))
    ccall(:jl_exit, Core.Cvoid, (Core.Int32,), Core.Int32(0))
end

include("setup_Compiler.jl")

@testset "CachedMethodTable" begin
    # cache result should be separated per `limit` and `sig`
    # https://github.com/JuliaLang/julia/pull/46799
    interp = Compiler.NativeInterpreter()
    table = Compiler.method_table(interp)
    sig = Tuple{typeof(*), Any, Any}
    result1 = Compiler.findall(sig, table; limit=-1)
    result2 = Compiler.findall(sig, table; limit=Compiler.InferenceParams().max_methods)
    @test result1 !== nothing && !Compiler.isempty(result1)
    @test result2 === nothing
end

@testset "BitSetBoundedMinPrioritySet" begin
    bsbmp = Compiler.BitSetBoundedMinPrioritySet(5)
    Compiler.push!(bsbmp, 2)
    Compiler.push!(bsbmp, 2)
    iterateok = true
    cnt = 0
    @eval Compiler for v in $bsbmp
        if cnt == 0
            iterateok &= v == 2
        elseif cnt == 1
            iterateok &= v == 5
        else
            iterateok = false
        end
        cnt += 1
    end
    @test iterateok
    @test Compiler.popfirst!(bsbmp) == 2
    Compiler.push!(bsbmp, 1)
    @test Compiler.popfirst!(bsbmp) == 1
    @test Compiler.isempty(bsbmp)
end

@testset "basic heap functionality" begin
    v = [2,3,1]
    @test Compiler.heapify!(v, Compiler.Forward) === v
    @test Compiler.heappop!(v, Compiler.Forward) === 1
    @test Compiler.heappush!(v, 4, Compiler.Forward) === v
    @test Compiler.heappop!(v, Compiler.Forward) === 2
    @test Compiler.heappop!(v, Compiler.Forward) === 3
    @test Compiler.heappop!(v, Compiler.Forward) === 4
end

@testset "randomized heap correctness tests" begin
    order = Compiler.By(x -> -x[2])
    for i in 1:6
        heap = Tuple{Int, Int}[(rand(1:i), rand(1:i)) for _ in 1:2i]
        mock = copy(heap)
        @test Compiler.heapify!(heap, order) === heap
        sort!(mock, by=last)

        for _ in 1:6i
            if rand() < .5 && !isempty(heap)
                # The first entries may differ because heaps are not stable
                @test last(Compiler.heappop!(heap, order)) === last(pop!(mock))
            else
                new = (rand(1:i), rand(1:i))
                Compiler.heappush!(heap, new, order)
                push!(mock, new)
                sort!(mock, by=last)
            end
        end
    end
end

@testset "searchsorted" begin
    @test Compiler.searchsorted([1, 1, 2, 2, 3, 3], 0) === Compiler.UnitRange(1, 0)
    @test Compiler.searchsorted([1, 1, 2, 2, 3, 3], 1) === Compiler.UnitRange(1, 2)
    @test Compiler.searchsorted([1, 1, 2, 2, 3, 3], 2) === Compiler.UnitRange(3, 4)
    @test Compiler.searchsorted([1, 1, 2, 2, 3, 3], 4) === Compiler.UnitRange(7, 6)
    @test Compiler.searchsorted([1, 1, 2, 2, 3, 3], 2.5; lt=<) === Compiler.UnitRange(5, 4)

    @test Compiler.searchsorted(Compiler.UnitRange(1, 3), 0) === Compiler.UnitRange(1, 0)
    @test Compiler.searchsorted(Compiler.UnitRange(1, 3), 1) === Compiler.UnitRange(1, 1)
    @test Compiler.searchsorted(Compiler.UnitRange(1, 3), 2) === Compiler.UnitRange(2, 2)
    @test Compiler.searchsorted(Compiler.UnitRange(1, 3), 4) === Compiler.UnitRange(4, 3)

    @test Compiler.searchsorted([1:10;], 1, by=(x -> x >= 5)) === Compiler.UnitRange(1, 4)
    @test Compiler.searchsorted([1:10;], 10, by=(x -> x >= 5)) === Compiler.UnitRange(5, 10)
    @test Compiler.searchsorted([1:5; 1:5; 1:5], 1, 6, 10, Compiler.Forward) === Compiler.UnitRange(6, 6)
    @test Compiler.searchsorted(fill(1, 15), 1, 6, 10, Compiler.Forward) === Compiler.UnitRange(6, 10)

    for (rg,I) in Any[(Compiler.UnitRange(49, 57),   47:59),
                      (Compiler.StepRange(1, 2, 17), -1:19)]
        rg_r = Compiler.reverse(rg)
        rgv, rgv_r = Compiler.collect(rg), Compiler.collect(rg_r)
        for i = I
            @test Compiler.searchsorted(rg,i) === Compiler.searchsorted(rgv,i)
            @test Compiler.searchsorted(rg_r,i,rev=true) === Compiler.searchsorted(rgv_r,i,rev=true)
        end
    end
end

@testset "basic sort" begin
    v = [3,1,2]
    @test v == [3,1,2]
    @test Compiler.sort!(v) === v == [1,2,3]
    @test Compiler.sort!(v, by = x -> -x) === v == [3,2,1]
    @test Compiler.sort!(v, by = x -> -x, < = >) === v == [1,2,3]
end

@testset "randomized sorting tests" begin
    for n in [0, 1, 3, 10, 30, 100, 300], k in [0, 30, 2n]
        v = rand(-1:k, n)
        for by in [identity, x -> -x, x -> x^2 + .1x], lt in [<, >]
            @test sort(v; by, lt) == Compiler.sort!(copy(v); by, < = lt)
        end
    end
end
