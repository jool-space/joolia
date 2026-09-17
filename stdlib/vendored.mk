# External stdlibs are ordinary tracked source trees. Keep build/install state
# under the build prefix, so clean and distclean cannot delete vendored sources.
define stdlib-vendored
get-$1 extract-$1 configure-$1 compile-$1: $$(SRCDIR)/$1/Project.toml
checksum-$1:
install-$1: $$(build_prefix)/manifest/$$(VERSDIR)/$1
reinstall-$1:
	+$$(MAKE) uninstall-$1
	+$$(MAKE) install-$1
uninstall-$1: uninstall-$$(VERSDIR)/$1
clean-$1 distclean-$1: uninstall-$1
version-check-$1: version-check-$$(VERSDIR)/$1
install-$$(VERSDIR)/$1: install-$1

UNINSTALL_$$(VERSDIR)/$1 := $1 symlink-uninstaller $$(build_datarootdir)/julia/stdlib

# Depending on this rule file also replaces links left by the extracted-source
# workflow when upgrading an existing build directory.
$$(build_prefix)/manifest/$$(VERSDIR)/$1: $$(SRCDIR)/vendored.mk $$(SRCDIR)/Makefile $$(SRCDIR)/$1/Project.toml | $$(DIRS)
	-+[ ! \( -e $$(build_datarootdir)/julia/stdlib/$$(VERSDIR)/$1 -o -h $$(build_datarootdir)/julia/stdlib/$$(VERSDIR)/$1 \) ] || $$(MAKE) uninstall-$1
ifeq ($$(BUILD_OS), WINNT)
	cmd //C mklink //J $$(call mingw_to_dos,$$(build_datarootdir)/julia/stdlib/$$(VERSDIR)/$1,) $$(call mingw_to_dos,$$(SRCDIR)/$1,)
else ifneq (,$$(findstring CYGWIN,$$(BUILD_OS)))
	cmd /C mklink /J $$(call cygpath_w,$$(build_datarootdir)/julia/stdlib/$$(VERSDIR)/$1) $$(call cygpath_w,$$(SRCDIR)/$1)
else ifdef JULIA_VAGRANT_BUILD
	cp -R $$(SRCDIR)/$1 $$(build_datarootdir)/julia/stdlib/$$(VERSDIR)/$1
else
	ln -s $$(SRCDIR)/$1 $$(build_datarootdir)/julia/stdlib/$$(VERSDIR)/$1
endif
	echo '$$(UNINSTALL_$$(VERSDIR)/$1)' > $$@
.PHONY: $(addsuffix -$1,get extract configure compile checksum install reinstall uninstall clean distclean version-check)
endef
