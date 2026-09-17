# This file is a part of Julia. License is MIT: https://julialang.org/license

module LazyArtifacts

# reexport the Artifacts API
using Artifacts: Artifacts,
       artifact_exists, artifact_path, artifact_meta, artifact_hash,
       select_downloadable_artifacts, find_artifacts_toml, @artifact_str
export artifact_exists, artifact_path, artifact_meta, artifact_hash,
       select_downloadable_artifacts, find_artifacts_toml, @artifact_str

# define a function for satisfying lazy Artifact downloads
using Pkg.Artifacts: ensure_artifact_installed

# Precompile the `Val{LazyArtifacts}` flavour of `@artifact_str` dispatch so that
# JLL packages using `using LazyArtifacts` don't pay codegen cost at `__init__`.
precompile(Tuple{typeof(Artifacts._artifact_str), Module, String, SubString{String}, String,
                 Dict{String,Any}, Base.SHA1, Base.BinaryPlatforms.Platform, Val{LazyArtifacts}})
precompile(Tuple{typeof(Artifacts.__artifact_str), Module, String, SubString{String}, String,
                 Dict{String,Any}, Base.SHA1, Base.BinaryPlatforms.Platform, Val{LazyArtifacts}})

end
