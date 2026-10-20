# Constructor classes (ADR-0001 §3). Owned by sub-lane p2-classes; this entry file includes the
# area's other files.

include("core.jl")        # tags, constructorclass, styles, dispatching operations
include("owned.jl")       # Identity, ZipVector, Predicate, internal Compose
include("instances.jl")   # instances on Base types
include("class_laws.jl")  # law tables of the class kits
