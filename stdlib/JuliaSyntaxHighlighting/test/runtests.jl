# This file is a part of Julia. License is MIT: https://julialang.org/license

using JuliaSyntaxHighlighting: JuliaSyntaxHighlighting, highlight, highlight!
using Test

@test isempty(Test.detect_closure_boxes(JuliaSyntaxHighlighting))

# We could go to the effort of testing each individual highlight face,
# however here we're aiming for the much lower bar of ensuring that
# `highlight` consistently returns a reasonable result.
# This also avoids testing as much of the particulars of JuliaSyntax.

sum1to8_highlighted = Base.AnnotatedString("sum(1:8)", [
    (0:2, :face, :julia_funcall),
    (3:3, :face, :julia_rainbow_paren_1),
    (4:4, :face, :julia_number),
    (5:5, :face, :julia_operator),
    (6:6, :face, :julia_number),
    (7:7, :face, :julia_rainbow_paren_1)
])

@test highlight("sum(1:8)") == sum1to8_highlighted
@test highlight(IOBuffer("sum(1:8)")) == sum1to8_highlighted
@test highlight(IOContext(IOBuffer("sum(1:8)"))) == sum1to8_highlighted

astr_sum1to8 = Base.AnnotatedString("sum(1:8)")
@test highlight!(astr_sum1to8) == sum1to8_highlighted
@test astr_sum1to8 == sum1to8_highlighted

# Ensure generic operators inside parse error nodes do not crash highlighting.
@test any(a -> a.region == 4:4 && a.value == :julia_operator,
          Base.annotations(highlight("1 2 / 3")))
@test any(a -> a.region == 4:5 && a.value == :julia_operator,
          Base.annotations(highlight("1 2 == 3")))
@test any(a -> a.region == 2:4 && a.value == :julia_operator,
          Base.annotations(highlight("1 <-- 2")))
@test any(a -> a.region == 2:5 && a.value == :julia_operator,
          Base.annotations(highlight("1 <--> 2")))

# Check for string indexing issues
@test Base.annotations(highlight(":π")) |> first |> first == 0:2

# Test that labeled break/continue labels are highlighted, but not the
# (possibly juxtaposed) break value
labeled_break = highlight("@label x begin\n  break x i * 3\nend")
anns = Base.annotations(labeled_break)
@test any(a -> a.region == 23:23 && a.value == :julia_label, anns)
@test all(a -> a.value != :julia_label || a.region == 23:23, anns)
@test any(a -> a.region == 9:13 && a.value == :julia_label,
          Base.annotations(highlight("continue outer")))
@test all(a -> a.value != :julia_label, Base.annotations(highlight("break")))

# Test unpaired parentheses (issue #17)
# Test consecutive unpaired closing parens and that depth counter resets properly
reset_after_unpaired = highlight("(()))) ()")
anns = Base.annotations(reset_after_unpaired)
@test anns[4].value == :julia_unpaired_parentheses  # First unpaired
@test anns[5].value == :julia_unpaired_parentheses  # Second unpaired
@test anns[6].value == :julia_rainbow_paren_1       # Opening after reset
@test anns[7].value == :julia_rainbow_paren_1       # Closing after reset


@testset "zero-origin boundaries" begin
    @test isempty(Base.annotations(highlight("")))

    unicode = highlight(":π")
    @test first(Base.annotations(unicode)).region == 0:2
    @test all(a -> first(a.region) >= 0 && last(a.region) < ncodeunits(":π"),
              Base.annotations(unicode))

    escaped = highlight("\"é\\n\"")
    anns = Base.annotations(escaped)
    @test first(anns).region == 0:0
    @test last(anns).region == 5:5
    @test any(a -> a.value == :julia_backslash_literal && a.region == 3:4, anns)
end
