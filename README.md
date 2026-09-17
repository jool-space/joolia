# joolia

A fork of Julia with zero-based collection positions and dimensions. Tuples,
arrays, strings, Memory, and Cartesian indexing start at zero. Colon ranges
remain inclusive, and arrays remain column-major.

Start the local build with:

```sh
./usr/bin/joolia --startup-file=no
```

This is an experimental port. The system image and interactive REPL work;
Pkg and several standard-library paths are still being ported. See
[the build notes](JOOLIA.md) and [validated coverage and limitations](JOOLIA_BASE_PORT.md).
The upstream `julia` executable name remains available for compatibility.

`.jo` is a candidate source-file extension; `.jl` conventions remain in place
while that decision is open. The links below still refer to upstream Julia.

## Resources

- **Homepage:** <https://julialang.org>
- **Install:** <https://julialang.org/downloads/>
- **Source code:** <https://github.com/JuliaLang/julia>
- **Documentation:** <https://docs.julialang.org>
- **Packages:** <https://julialang.org/packages/>
- **Discussion forum:** <https://discourse.julialang.org>
- **Zulip:** <https://julialang.zulipchat.com/>
- **Slack:** <https://julialang.slack.com> (get an invite from <https://julialang.org/slack/>)
- **YouTube:** <https://www.youtube.com/user/JuliaLanguage>
- **Code coverage:** <https://coveralls.io/r/JuliaLang/julia>


## Contributing to Julia

We welcome contributions from developers of all experience levels, including bug fixes,
documentation improvements, tests, and performance enhancements.

New contributors are encouraged to start by reading [CONTRIBUTING.md](https://github.com/JuliaLang/julia/blob/master/CONTRIBUTING.md).

> [!IMPORTANT]
> If your pull request contains substantive contributions from a generative AI tool, please disclose so with details, and review all changes before opening. This also applies to other content, such as issues, discussions, and comments.

### Learning Julia

- [**Learning resources**](https://julialang.org/learning/)

## Binary Installation

The recommended way of installing Julia is to use `juliaup` which will install
the latest stable `julia` for you and help keep it up to date. It can also let
you install and run different Julia versions simultaneously. Instructions for
this can be found [here](https://julialang.org/downloads/). If you want to manually
download specific Julia binaries, you can find those on the [Manual Downloads
page](https://julialang.org/downloads/manual-downloads/). The downloads page also provides
details on the [different tiers of
support](https://julialang.org/downloads/support) for OS and
platform combinations.

If everything works correctly, you will get a `julia` program and when you run
it in a terminal or command prompt, you will see a Julia banner and an
interactive prompt into which you can enter expressions for evaluation. You can
read about [getting
started](https://docs.julialang.org/en/v1/manual/getting-started/) in the
manual.

**Note**: Although some OS package managers provide Julia, such
installations are neither maintained nor endorsed by the Julia
project. They may be outdated, broken and/or unmaintained. We
recommend you use the official Julia binaries instead.

## Building Julia

First, make sure you have all the [required
dependencies](https://github.com/JuliaLang/julia/blob/master/doc/src/devdocs/build/build.md#required-build-tools-and-external-libraries) installed.
Then, acquire the source code by cloning the git repository:

    git clone https://github.com/JuliaLang/julia.git

and then use the command prompt to change into the resulting julia directory. By default, you will be building the latest unstable version of
Julia. However, most users should use the [most recent stable version](https://github.com/JuliaLang/julia/releases)
of Julia. You can get this version by running: (replace `[tag]` with the desired tag)

    git checkout [tag]

To build the `julia` executable, run `make` from within the julia directory.

Building Julia requires 2GiB of disk space and approximately 4GiB of virtual memory.

**Note:** The build process will fail badly if any of the build directory's parent directories have spaces or other shell meta-characters such as `$` or `:` in their names (this is due to a limitation in GNU make).

Once it is built, you can run the `julia` executable. From within the julia directory, run

    ./julia

Your first test of Julia determines whether your build is working
properly. From the julia
directory, type `make testall`. You should see output that
lists a series of running tests; if they complete without error, you
should be in good shape to start using Julia.

You can read about [getting
started](https://docs.julialang.org/en/v1/manual/getting-started/)
in the manual.

Detailed build instructions, should they be necessary,
are included in the [build documentation](https://github.com/JuliaLang/julia/blob/master/doc/src/devdocs/build/build.md).

### Uninstalling Julia

By default, Julia does not install anything outside the directory it was cloned
into and `~/.julia`. Julia and the vast majority of Julia packages can be
completely uninstalled by deleting these two directories.

## Source Code Organization

The Julia source code is organized as follows:

| Directory         | Contents                                                           |
| -                 | -                                                                  |
| `base/`           | source code for the Base module (part of Julia's standard library) |
| `cli/`            | source for the command line interface/REPL                         |
| `contrib/`        | miscellaneous scripts                                              |
| `deps/`           | external dependencies                                              |
| `doc/src/`        | source for the user manual                                         |
| `etc/`            | contains `startup.jl`                                              |
| `src/`            | source for Julia language core                                     |
| `stdlib/`         | source code for other standard library packages                    |
| `test/`           | test suites                                                        |

## Terminal, Editors and IDEs

The Julia REPL is quite powerful. See the section in the manual on
[the Julia REPL](https://docs.julialang.org/en/v1/stdlib/REPL/)
for more details.

On Windows, we highly recommend running Julia in a modern terminal,
such as [Windows Terminal from the Microsoft Store](https://aka.ms/terminal).

Support for editing Julia is available for many
[widely used editors](https://github.com/JuliaEditorSupport):
[Emacs](https://github.com/JuliaEditorSupport/julia-emacs),
[Vim](https://github.com/JuliaEditorSupport/julia-vim),
[Sublime Text](https://github.com/JuliaEditorSupport/Julia-sublime), and many
others.

For users who prefer IDEs, we recommend using VS Code with the
[julia-vscode](https://www.julia-vscode.org/) plugin.\
For notebook users, [Jupyter](https://jupyter.org/) notebook support is available through the
[IJulia](https://github.com/JuliaLang/IJulia.jl) package, and
the [Pluto.jl](https://github.com/fonsp/Pluto.jl) package provides Pluto notebooks.
