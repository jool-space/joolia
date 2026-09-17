SRCDIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
JULIAHOME := $(abspath $(SRCDIR)/..)
BUILDDIR := .
include $(JULIAHOME)/Make.inc
VERSDIR := v$(shell cut -d. -f1-2 < $(JULIAHOME)/VERSION)
STDLIBDIR := $(build_datarootdir)/julia/stdlib/$(VERSDIR)
# TODO: this Makefile ignores BUILDDIR, except for computing JULIA_EXECUTABLE

export JULIA_DEPOT_PATH := $(build_prefix)/share/julia
export JULIA_LOAD_PATH := @$(PATHSEP)@stdlib
unexport JULIA_PROJECT :=
unexport JULIA_BINDIR :=

# used by JuliaLowering_stdlibs.jl test (invokes `make` for JL sysimage)
export MAKE
export BUILDROOT
export JULIA_BUILD_MODE

TESTGROUPS = unicode strings compiler Compiler JuliaSyntax JuliaLowering
TESTS = all default stdlib $(TESTGROUPS) \
		$(patsubst $(STDLIBDIR)/%/,%,$(dir $(wildcard $(STDLIBDIR)/*/.))) \
		$(filter-out runtests testdefs relocatedepot, \
			$(patsubst $(SRCDIR)/%.jl,%,$(wildcard $(SRCDIR)/*.jl))) \
		$(foreach group,$(TESTGROUPS), \
			$(patsubst $(SRCDIR)/%.jl,%,$(wildcard $(SRCDIR)/$(group)/*.jl)))
# run `make print-TESTS` to see a list of all tests that can be run

EMBEDDING_ARGS := "JULIA=$(JULIA_EXECUTABLE)" "BIN=$(SRCDIR)/embedding" "CC=$(CC)"

GCEXT_ARGS := "JULIA=$(JULIA_EXECUTABLE)" "BIN=$(SRCDIR)/gcext" "CC=$(CC)"

TEST_JULIA_OPTIONS := --check-bounds=yes --startup-file=no --depwarn=error
TEST_SCRIPT_OPTIONS := --buildroot=$(call cygpath_w,$(BUILDROOT))

.PHONY: default
default:

.PHONY: $(TESTS)
$(TESTS):
	+@cd $(SRCDIR) && \
	$(call PRINT_JULIA, $(call spawn,$(JULIA_EXECUTABLE)) $(TEST_JULIA_OPTIONS) ./runtests.jl $(TEST_SCRIPT_OPTIONS) $@)

# --output-ji selects the existing no-sysimage bootstrap path. The Core-only
# branch of core.jl exits after testing, before any image is serialized.
.PHONY: core-bootstrap
core-bootstrap:
	@cd $(JULIAHOME)/base && JULIA_NUM_THREADS=1 JULIA_TEST_FAILFAST=1 \
	$(call spawn,$(JULIA_EXECUTABLE)) --startup-file=no --check-bounds=yes --compile=min \
		--output-ji $(build_private_libdir)/core-test-unused.ji $(SRCDIR)/core.jl
	@cd $(JULIAHOME)/base && JULIA_NUM_THREADS=1 JULIA_TEST_FAILFAST=1 \
	$(call spawn,$(JULIA_EXECUTABLE)) --startup-file=no --check-bounds=yes --compile=all \
		--output-ji $(build_private_libdir)/core-test-unused.ji $(SRCDIR)/core.jl

# Test the exact Base_compiler.jl prefix before the Julia compiler is loaded.
# The generated driver closes its Base module and runs the existing array tests'
# bootstrap branch; production bootstrap control flow remains unchanged.
.PHONY: base-foundation
base-foundation:
	@mkdir -p $(build_private_libdir)
	@sed '/^include(strcat(DATAROOT, "julia\/Compiler\/src\/Compiler.jl"))/,$$d' $(JULIAHOME)/base/Base_compiler.jl > $(build_private_libdir)/base-foundation-test.jl
	@printf '\nend # module Base\nCore.include(Core.Main, "$(SRCDIR)/arrayops.jl")\n' >> $(build_private_libdir)/base-foundation-test.jl
	@cd $(JULIAHOME)/base && JULIA_NUM_THREADS=1 JULIA_TEST_FAILFAST=1 \
	$(call spawn,$(JULIA_EXECUTABLE)) --startup-file=no --check-bounds=yes --compile=min \
		--output-ji $(build_private_libdir)/base-test-unused.ji $(build_private_libdir)/base-foundation-test.jl
	@cd $(JULIAHOME)/base && JULIA_NUM_THREADS=1 JULIA_TEST_FAILFAST=1 \
	$(call spawn,$(JULIA_EXECUTABLE)) --startup-file=no --check-bounds=yes --compile=all \
		--output-ji $(build_private_libdir)/base-test-unused.ji $(build_private_libdir)/base-foundation-test.jl

.PHONY: compiler-foundation
compiler-foundation:
	@mkdir -p $(build_private_libdir)
	@sed '/^# Enable compiler/,$$d' $(JULIAHOME)/base/Base_compiler.jl > $(build_private_libdir)/compiler-foundation-test.jl
	@printf '\nend # module Base\nCore.include(Core.Main, "$(JULIAHOME)/Compiler/test/datastructures.jl")\n' >> $(build_private_libdir)/compiler-foundation-test.jl
	@cd $(JULIAHOME)/base && JULIA_NUM_THREADS=1 JULIA_TEST_FAILFAST=1 \
	$(call spawn,$(JULIA_EXECUTABLE)) --startup-file=no --check-bounds=yes --compile=min \
		--output-ji $(build_private_libdir)/compiler-test-unused.ji $(build_private_libdir)/compiler-foundation-test.jl --dataroot $(build_datarootdir)/
	@cd $(JULIAHOME)/base && JULIA_NUM_THREADS=1 JULIA_TEST_FAILFAST=1 \
	$(call spawn,$(JULIA_EXECUTABLE)) --startup-file=no --check-bounds=yes --compile=all \
		--output-ji $(build_private_libdir)/compiler-test-unused.ji $(build_private_libdir)/compiler-foundation-test.jl --dataroot $(build_datarootdir)/

.PHONY: strings-foundation
strings-foundation:
	@mkdir -p $(build_private_libdir)
	@sed '/^# Enable compiler/,$$d' $(JULIAHOME)/base/Base_compiler.jl > $(build_private_libdir)/strings-foundation-test.jl
	@printf '\nend # module Base\nCore.include(Core.Main, "$(SRCDIR)/strings/basic.jl")\n' >> $(build_private_libdir)/strings-foundation-test.jl
	@cd $(JULIAHOME)/base && JULIA_NUM_THREADS=1 JULIA_TEST_FAILFAST=1 \
	$(call spawn,$(JULIA_EXECUTABLE)) --startup-file=no --check-bounds=yes --compile=min \
		--output-ji $(build_private_libdir)/strings-test-unused.ji $(build_private_libdir)/strings-foundation-test.jl --dataroot $(build_datarootdir)/
	@cd $(JULIAHOME)/base && JULIA_NUM_THREADS=1 JULIA_TEST_FAILFAST=1 \
	$(call spawn,$(JULIA_EXECUTABLE)) --startup-file=no --check-bounds=yes --compile=all \
		--output-ji $(build_private_libdir)/strings-test-unused.ji $(build_private_libdir)/strings-foundation-test.jl --dataroot $(build_datarootdir)/

# Test the Dict implementation with the compiler prefix, before full Base is loaded.
.PHONY: dict-foundation
dict-foundation:
	@mkdir -p $(build_private_libdir)
	@sed '/^# Enable compiler/,$$d' $(JULIAHOME)/base/Base_compiler.jl > $(build_private_libdir)/dict-foundation-test.jl
	@printf '\nend # module Base\nCore.include(Core.Main, "$(SRCDIR)/dict.jl")\n' >> $(build_private_libdir)/dict-foundation-test.jl
	@cd $(JULIAHOME)/base && JULIA_NUM_THREADS=1 JULIA_TEST_FAILFAST=1 \
	$(call spawn,$(JULIA_EXECUTABLE)) --startup-file=no --check-bounds=yes --compile=min \
		--output-ji $(build_private_libdir)/dict-test-unused.ji $(build_private_libdir)/dict-foundation-test.jl --dataroot $(build_datarootdir)/
	@cd $(JULIAHOME)/base && JULIA_NUM_THREADS=1 JULIA_TEST_FAILFAST=1 \
	$(call spawn,$(JULIA_EXECUTABLE)) --startup-file=no --check-bounds=yes --compile=all \
		--output-ji $(build_private_libdir)/dict-test-unused.ji $(build_private_libdir)/dict-foundation-test.jl --dataroot $(build_datarootdir)/

# Test Broadcast axes, tuple positions, and materialization before the compiler is loaded.
.PHONY: broadcast-foundation
broadcast-foundation:
	@mkdir -p $(build_private_libdir)
	@sed '/^# Enable compiler/,$$d' $(JULIAHOME)/base/Base_compiler.jl > $(build_private_libdir)/broadcast-foundation-test.jl
	@printf '\nend # module Base\nCore.include(Core.Main, "$(SRCDIR)/broadcast.jl")\n' >> $(build_private_libdir)/broadcast-foundation-test.jl
	@cd $(JULIAHOME)/base && JULIA_NUM_THREADS=1 JULIA_TEST_FAILFAST=1 \
	$(call spawn,$(JULIA_EXECUTABLE)) --startup-file=no --check-bounds=yes --compile=min \
		--output-ji $(build_private_libdir)/broadcast-test-unused.ji $(build_private_libdir)/broadcast-foundation-test.jl --dataroot $(build_datarootdir)/
	@cd $(JULIAHOME)/base && JULIA_NUM_THREADS=1 JULIA_TEST_FAILFAST=1 \
	$(call spawn,$(JULIA_EXECUTABLE)) --startup-file=no --check-bounds=yes --compile=all \
		--output-ji $(build_private_libdir)/broadcast-test-unused.ji $(build_private_libdir)/broadcast-foundation-test.jl --dataroot $(build_datarootdir)/

# Test the IOBuffer and generic IO byte-position contract before the compiler is loaded.
.PHONY: io-foundation
io-foundation:
	@mkdir -p $(build_private_libdir)
	@sed '/^# Enable compiler/,$$d' $(JULIAHOME)/base/Base_compiler.jl > $(build_private_libdir)/io-foundation-test.jl
	@printf '\nend # module Base\nCore.include(Base, "$(JULIAHOME)/base/multimedia.jl")\nCore.eval(Base, :(using .Multimedia))\nCore.include(Core.Main, "$(SRCDIR)/iobuffer.jl")\n' >> $(build_private_libdir)/io-foundation-test.jl
	@cd $(JULIAHOME)/base && JULIA_NUM_THREADS=1 JULIA_TEST_FAILFAST=1 \
	$(call spawn,$(JULIA_EXECUTABLE)) --startup-file=no --check-bounds=yes --compile=min \
		--output-ji $(build_private_libdir)/io-test-unused.ji $(build_private_libdir)/io-foundation-test.jl --dataroot $(build_datarootdir)/
	@cd $(JULIAHOME)/base && JULIA_NUM_THREADS=1 JULIA_TEST_FAILFAST=1 \
	$(call spawn,$(JULIA_EXECUTABLE)) --startup-file=no --check-bounds=yes --compile=all \
		--output-ji $(build_private_libdir)/io-test-unused.ji $(build_private_libdir)/io-foundation-test.jl --dataroot $(build_datarootdir)/

.PHONY: install-revise-deps
install-revise-deps:
	$(call PRINT_JULIA, $(call spawn,$(JULIA_EXECUTABLE)) $(TEST_JULIA_OPTIONS) ./runtests.jl $(TEST_SCRIPT_OPTIONS) --revise --help-list install_revise_deps)

.PHONY: $(addprefix revise-, $(TESTS))
$(addprefix revise-, $(TESTS)): revise-% :
	@cd $(SRCDIR) && \
    $(call PRINT_JULIA, $(call spawn,$(JULIA_EXECUTABLE)) $(TEST_JULIA_OPTIONS) ./runtests.jl $(TEST_SCRIPT_OPTIONS) --revise $*)

.PHONY: relocatedepot
relocatedepot:
	@rm -rf $(SRCDIR)/relocatedepot
	@cd $(SRCDIR) && \
	$(call PRINT_JULIA, $(call spawn,$(JULIA_EXECUTABLE)) $(TEST_JULIA_OPTIONS) ./runtests.jl $(TEST_SCRIPT_OPTIONS) $@)
	@mkdir $(SRCDIR)/relocatedepot
	@cp -R $(build_datarootdir)/julia $(SRCDIR)/relocatedepot
	@cp -R $(SRCDIR)/RelocationTestPkg1 $(SRCDIR)/relocatedepot
	@cp -R $(SRCDIR)/RelocationTestPkg2 $(SRCDIR)/relocatedepot
	@cp -R $(SRCDIR)/RelocationTestPkg3 $(SRCDIR)/relocatedepot
	@cp -R $(SRCDIR)/RelocationTestPkg4 $(SRCDIR)/relocatedepot
	@cd $(SRCDIR) && \
	$(call PRINT_JULIA, $(call spawn,RELOCATEDEPOT="" $(JULIA_EXECUTABLE)) $(TEST_JULIA_OPTIONS) ./runtests.jl $(TEST_SCRIPT_OPTIONS) $@)

.PHONY: revise-relocatedepot
revise-relocatedepot: revise-% :
	@rm -rf $(SRCDIR)/relocatedepot
	@cd $(SRCDIR) && \
	$(call PRINT_JULIA, $(call spawn,$(JULIA_EXECUTABLE)) $(TEST_JULIA_OPTIONS) ./runtests.jl $(TEST_SCRIPT_OPTIONS) --revise $*)
	@mkdir $(SRCDIR)/relocatedepot
	@cp -R $(build_datarootdir)/julia $(SRCDIR)/relocatedepot
	@cp -R $(SRCDIR)/RelocationTestPkg1 $(SRCDIR)/relocatedepot
	@cp -R $(SRCDIR)/RelocationTestPkg2 $(SRCDIR)/relocatedepot
	@cp -R $(SRCDIR)/RelocationTestPkg3 $(SRCDIR)/relocatedepot
	@cp -R $(SRCDIR)/RelocationTestPkg4 $(SRCDIR)/relocatedepot
	@cd $(SRCDIR) && \
	$(call PRINT_JULIA, $(call spawn,RELOCATEDEPOT="" $(JULIA_EXECUTABLE)) $(TEST_JULIA_OPTIONS) ./runtests.jl $(TEST_SCRIPT_OPTIONS) --revise $*)

.PHONY: embedding
embedding:
	@$(MAKE) -C $(SRCDIR)/$@ check $(EMBEDDING_ARGS)

.PHONY: gcext
gcext:
	@$(MAKE) -C $(SRCDIR)/$@ check $(GCEXT_ARGS)

.PHONY: clangsa
clangsa:
	@$(MAKE) -C $(SRCDIR)/$@

.PHONY: clean
clean:
	@$(MAKE) -C embedding $@ $(EMBEDDING_ARGS)
	@$(MAKE) -C gcext $@ $(GCEXT_ARGS)
	@$(MAKE) -C llvmpasses $@
