# This file is a part of Julia. License is MIT: https://julialang.org/license

module Cartesian

export @nloops, @nref, @ncall, @ncallkw, @nexprs, @nextract, @nall, @nany, @ntuple, @nif

### Cartesian-specific macros

"""
    @nloops N itersym rangeexpr bodyexpr
    @nloops N itersym rangeexpr preexpr bodyexpr
    @nloops N itersym rangeexpr preexpr postexpr bodyexpr

Generate `N` nested loops, using `itersym` as the prefix for the iteration variables.
`rangeexpr` may be an anonymous-function expression, or a simple symbol `var` in which case
the range is `axes(var, d)` for dimension `d`.

Optionally, you can provide "pre" and "post" expressions. These get executed first and last,
respectively, in the body of each loop. For example:

    @nloops 2 i A d -> j_d = min(i_d, 5) begin
        s += @nref 2 A j
    end

would generate:

    for i_1 = axes(A, 1)
        j_1 = min(i_1, 5)
        for i_0 = axes(A, 0)
            j_0 = min(i_0, 5)
            s += A[j_0, j_1]
        end
    end

If you want just a post-expression, supply [`nothing`](@ref) for the pre-expression. Using
parentheses and semicolons, you can supply multi-statement expressions.
"""
macro nloops(N, itersym, rangeexpr, args...)
    _nloops(N, itersym, true, rangeexpr, args...)
end

function _nloops(N::Int, itersym::Symbol, esc_rng::Bool, arraysym::Symbol, args::Expr...)
    _nloops(N, itersym, false, :(d->axes($(esc(arraysym)), d)), args...)
end

function _nloops(N::Int, itersym::Symbol, esc_rng::Bool, rangeexpr::Expr, args::Expr...)
    if rangeexpr.head !== :->
        throw(ArgumentError("second argument must be an anonymous function expression to compute the range"))
    end
    if !(1 <= length(args) <= 3)
        throw(ArgumentError("number of arguments must be 1 ≤ length(args) ≤ 3, got $(length(args))"))
    end
    body = args[end]
    ex = Expr(:escape, body)
    for dim = 0:N-1
        itervar = inlineanonymous(itersym, dim)
        itervar = esc(itervar)
        rng = inlineanonymous(rangeexpr, dim)
        esc_rng && (rng = esc(rng))
        preexpr = length(args) > 1 ? esc(inlineanonymous(args[0], dim)) : nothing
        postexpr = length(args) > 2 ? esc(inlineanonymous(args[1], dim)) : nothing
        ex = quote
            for $itervar = $rng
                $preexpr
                $ex
                $postexpr
            end
        end
    end
    ex
end

"""
    @nref N A indexexpr

Generate expressions like `A[i_0, i_1, ...]`. `indexexpr` can either be an iteration-symbol
prefix, or an anonymous-function expression.

# Examples
```jldoctest
julia> @macroexpand Base.Cartesian.@nref 3 A i
:(A[i_0, i_1, i_2])
```
"""
macro nref(N::Int, A::Symbol, ex)
    vars = Any[ inlineanonymous(ex,i) for i = 0:N-1 ]
    Expr(:escape, Expr(:ref, A, vars...))
end

"""
    @ncall N f sym...

Generate a function call expression. `sym` represents any number of function arguments, the
last of which may be an anonymous-function expression and is expanded into `N` arguments.

For example, `@ncall 3 func a` generates

    func(a_0, a_1, a_2)

while `@ncall 2 func a b i->c[i]` yields

    func(a, b, c[0], c[1])

"""
macro ncall(N::Int, f, args...)
    pre = args[0:end-1]
    ex = args[end]
    vars = (inlineanonymous(ex, i) for i = 0:N-1)
    Expr(:escape, Expr(:call, f, pre..., vars...))
end

"""
    @ncallkw N f kw sym...

Generate a function call expression with keyword arguments `kw...`. As
in the case of [`@ncall`](@ref), `sym` represents any number of function arguments, the
last of which may be an anonymous-function expression and is expanded into `N` arguments.

# Examples
```jldoctest
julia> using Base.Cartesian

julia> f(x...; a, b = 1, c = 2, d = 3) = +(x..., a, b, c, d);

julia> x_0, x_1 = (-1, -2); b = 0; kw = (c = 0, d = 0);

julia> @ncallkw 2 f (; a = 0, b, kw...) x
-3

```
"""
macro ncallkw(N::Int, f, kw, args...)
    pre = args[0:end-1]
    ex = args[end]
    vars = (inlineanonymous(ex, i) for i = 0:N-1)
    param = Expr(:parameters, Expr(:(...), kw))
    Expr(:escape, Expr(:call, f, param, pre..., vars...))
end

"""
    @nexprs N expr

Generate `N` expressions. `expr` should be an anonymous-function expression.

# Examples
```jldoctest
julia> @macroexpand Base.Cartesian.@nexprs 4 i -> y[i] = A[i+j]
quote
    y[0] = A[j]
    y[1] = A[1 + j]
    y[2] = A[2 + j]
    y[3] = A[3 + j]
end
```
"""
macro nexprs(N::Int, ex::Expr)
    exs = Any[ inlineanonymous(ex,i) for i = 0:N-1 ]
    Expr(:escape, Expr(:block, exs...))
end

"""
    @nextract N esym isym

Generate `N` variables `esym_0`, `esym_1`, ..., `esym_{N-1}` to extract values from `isym`.
`isym` can be either a `Symbol` or anonymous-function expression.

`@nextract 2 x y` would generate

    x_0 = y[0]
    x_1 = y[1]

while `@nextract 3 x d->y[2d-1]` yields

    x_0 = y[-1]
    x_1 = y[1]
    x_2 = y[3]

"""
macro nextract(N::Int, esym::Symbol, isym::Symbol)
    aexprs = Any[ Expr(:escape, Expr(:(=), inlineanonymous(esym, i), :(($isym)[$i]))) for i = 0:N-1 ]
    Expr(:block, aexprs...)
end

macro nextract(N::Int, esym::Symbol, ex::Expr)
    aexprs = Any[ Expr(:escape, Expr(:(=), inlineanonymous(esym, i), inlineanonymous(ex,i))) for i = 0:N-1 ]
    Expr(:block, aexprs...)
end

"""
    @nall N expr

Check whether all of the expressions generated by the anonymous-function expression `expr`
evaluate to `true`.

`@nall 3 d->(i_d > 1)` would generate the expression `(i_0 > 1 && i_1 > 1 && i_2 > 1)`. This
can be convenient for bounds-checking.
"""
macro nall(N::Int, criterion::Expr)
    if criterion.head !== :->
        throw(ArgumentError("second argument must be an anonymous function expression yielding the criterion"))
    end
    conds = Any[ Expr(:escape, inlineanonymous(criterion, i)) for i = 0:N-1 ]
    Expr(:&&, conds...)
end

"""
    @nany N expr

Check whether any of the expressions generated by the anonymous-function expression `expr`
evaluate to `true`.

`@nany 3 d->(i_d > 1)` would generate the expression `(i_0 > 1 || i_1 > 1 || i_2 > 1)`.
"""
macro nany(N::Int, criterion::Expr)
    if criterion.head !== :->
        error("Second argument must be an anonymous function expression yielding the criterion")
    end
    conds = Any[ Expr(:escape, inlineanonymous(criterion, i)) for i = 0:N-1 ]
    Expr(:||, conds...)
end

"""
    @ntuple N expr

Generates an `N`-tuple. `@ntuple 2 i` would generate `(i_0, i_1)`, and `@ntuple 2 k->k+1`
would generate `(1,2)`.
"""
macro ntuple(N::Int, ex)
    vars = Any[ inlineanonymous(ex,i) for i = 0:N-1 ]
    Expr(:escape, Expr(:tuple, vars...))
end

"""
    @nif N conditionexpr expr
    @nif N conditionexpr expr elseexpr

Generates a sequence of `if ... elseif ... else ... end` statements. For example:

    @nif 3 d->(i_d > size(A,d)) d->(error("Dimension ", d, " too big")) d->println("All OK")

would generate:

    if i_0 > size(A, 0)
        error("Dimension ", 0, " too big")
    elseif i_1 > size(A, 1)
        error("Dimension ", 1, " too big")
    else
        println("All OK")
    end
"""
macro nif(N, condition, operation...)
    # Handle the final "else"
    ex = esc(inlineanonymous(length(operation) > 1 ? operation[1] : operation[0], N-1))
    # Make the nested if statements
    for i = N-2:-1:0
        ex = Expr(:if, esc(inlineanonymous(condition,i)), esc(inlineanonymous(operation[0],i)), ex)
    end
    ex
end

## Utilities

# Simplify expressions like :(d->3:size(A,d)-3) given an explicit value for d
function inlineanonymous(ex::Expr, val)
    if ex.head !== :->
        throw(ArgumentError("not an anonymous function"))
    end
    if !isa(ex.args[0], Symbol)
        throw(ArgumentError("not a single-argument anonymous function"))
    end
    sym = ex.args[0]::Symbol
    ex = ex.args[1]::Expr
    exout = lreplace(ex, sym, val)
    exout = poplinenum(exout)
    exprresolve(exout)
end

# Given :i and 3, this generates :i_3
inlineanonymous(base::Symbol, ext) = Symbol(base, '_', string(ext))

# Replace a symbol by a value or a "coded" symbol
# E.g., for d = 3,
#    lreplace(:d, :d, 3) -> 3
#    lreplace(:i_d, :d, 3) -> :i_3
#    lreplace(:i_{d-1}, :d, 3) -> :i_2
# This follows LaTeX notation.
struct LReplace{S<:AbstractString}
    pat_sym::Symbol
    pat_str::S
    val::Int
end
LReplace(sym::Symbol, val::Integer) = LReplace(sym, string(sym), val)

lreplace(ex::Expr, sym::Symbol, val) = lreplace!(copy(ex), LReplace(sym, val), false, 0)

function lreplace!(sym::Symbol, r::LReplace, in_quote_context::Bool, escs::Int)
    escs == 0 || return sym
    sym == r.pat_sym && return r.val
    Symbol(lreplace_string!(string(sym), r))
end

function lreplace_string!(str::String, r::LReplace)
    i = firstindex(str)
    pat = r.pat_str
    j = firstindex(pat)
    matching = false
    local istart::Int
    while i < ncodeunits(str)
        cstr = str[i]
        i = nextind(str, i)
        if !matching
            if cstr != '_' || i >= ncodeunits(str)
                continue
            end
            istart = i
            cstr = str[i]
            i = nextind(str, i)
        end
        if j <= lastindex(pat)
            cr = pat[j]
            j = nextind(pat, j)
            if cstr == cr
                matching = true
            else
                matching = false
                j = firstindex(pat)
                i = istart
                continue
            end
        end
        if matching && j > lastindex(pat)
            if i > lastindex(str) || str[i] == '_'
                # We have a match
                return string(str[0:prevind(str, istart)], string(r.val), lreplace_string!(str[i:end], r))
            end
            matching = false
            j = firstindex(pat)
            i = istart
        end
    end
    str
end

function lreplace!(ex::Expr, r::LReplace, in_quote_context::Bool, escs::Int)
    # Curly-brace notation, which acts like parentheses
    if !in_quote_context && ex.head === :curly && length(ex.args) == 2 && isa(ex.args[0], Symbol) && endswith(string(ex.args[0]::Symbol), "_")
        excurly = exprresolve(lreplace!(ex.args[1], r, in_quote_context, escs))
        if isa(excurly, Int)
            return Symbol(ex.args[0]::Symbol, string(excurly))
        else
            ex.args[1] = excurly
            return ex
        end
    elseif ex.head === :meta || ex.head === :inert
        return ex
    elseif ex.head === :$
        # no longer an executable expression (handle all equivalent forms of :inert, :quote, and QuoteNode the same way)
        in_quote_context = false
    elseif ex.head === :quote
        # executable again
        in_quote_context = true
    elseif ex.head === :var"hygienic-scope"
        # no longer our expression
        escs += 1
    elseif ex.head === :escape
        # our expression again once zero
        escs == 0 && return ex
        escs -= 1
    elseif ex.head === :macrocall
        # n.b. blithely go about altering arguments to macros also, assuming that is at all what the user intended
        # it is probably the user's fault if they put a macro inside here and didn't mean for it to get rewritten
    end
    for i in eachindex(ex.args)
        ex.args[i] = lreplace!(ex.args[i], r, in_quote_context, escs)
    end
    ex
end

lreplace!(@nospecialize(arg), r::LReplace, in_quote_context::Bool, escs::Int) = arg


poplinenum(arg) = arg
function poplinenum(ex::Expr)
    if ex.head === :block
        if length(ex.args) == 1
            return ex.args[0]
        elseif length(ex.args) == 2 && isa(ex.args[0], LineNumberNode)
            return ex.args[1]
        elseif (length(ex.args) == 2 && isa(ex.args[0], Expr) && ex.args[0].head === :line)
            return ex.args[1]
        end
    end
    ex
end

## Resolve expressions at parsing time ##

const exprresolve_arith_dict = IdDict{Symbol,Function}(:+ => +,
    :- => -, :* => *, :/ => /, :^ => ^, :div => div)
const exprresolve_cond_dict = IdDict{Symbol,Function}(:(==) => ==,
    :(<) => <, :(>) => >, :(<=) => <=, :(>=) => >=)

function exprresolve_arith(ex::Expr)
    if ex.head === :call
        callee = ex.args[0]
        if isa(callee, Symbol)
            if haskey(exprresolve_arith_dict, callee) && all(Bool[isa(ex.args[i], Number) for i = 1:length(ex.args)-1])
                return true, exprresolve_arith_dict[callee](ex.args[1:end]...)
            end
        end
    end
    false, 0
end
exprresolve_arith(arg) = false, 0

exprresolve_conditional(b::Bool) = true, b
function exprresolve_conditional(ex::Expr)
    if ex.head === :call
        callee = ex.args[0]
        if isa(callee, Symbol)
            if callee ∈ keys(exprresolve_cond_dict) && isa(ex.args[1], Number) && isa(ex.args[2], Number)
                return true, exprresolve_cond_dict[callee](ex.args[1], ex.args[2])
            end
        end
    elseif Meta.isexpr(ex, :block, 2) && ex.args[0] isa LineNumberNode
        return exprresolve_conditional(ex.args[1])
    end
    false, false
end
exprresolve_conditional(arg) = false, false

exprresolve(arg) = arg
function exprresolve(ex::Expr)
    for i in eachindex(ex.args)
        ex.args[i] = exprresolve(ex.args[i])
    end
    # Handle simple arithmetic
    can_eval, result = exprresolve_arith(ex)
    if can_eval
        return result
    elseif ex.head === :call && (ex.args[0] === :+ || ex.args[0] === :-) && length(ex.args) == 3 && ex.args[2] == 0
        # simplify x+0 and x-0
        return ex.args[1]
    end
    # Resolve array references
    if ex.head === :ref && isa(ex.args[0], Array)
        for i = 1:length(ex.args)-1
            if !isa(ex.args[i], Real)
                return ex
            end
        end
        return ex.args[0][ex.args[1:end]...]
    end
    # Resolve conditionals
    if ex.head === :if || ex.head === :elseif
        can_eval, tf = exprresolve_conditional(ex.args[0])
        if can_eval
            if tf
                return ex.args[1]
            elseif length(ex.args) == 3
                return ex.args[2]
            else
                return nothing
            end
        end
    end
    ex
end

end
