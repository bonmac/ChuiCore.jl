# Shared fixtures of the optics tests (ADR-0004): small immutable structs, a closed sum type
# (ADR-0002: a `Union` alias of plain structs) and types that need `constructorof`.

@testmodule OpticsFixtures begin
    using ConstructionBase: ConstructionBase

    struct Inner
        x::Int
        y::Float64
    end
    struct Outer
        a::Inner
        tag::Symbol
    end
    bump(i::Inner) = Inner(i.x + 1, i.y)
    struct Point
        a::Int
        b::Int
    end

    # A closed sum type: a `Union` of plain structs.
    struct Circle
        r::Float64
    end
    struct Rect
        w::Float64
        h::Float64
    end
    const Shape = Union{Circle, Rect}

    # A phantom parameter: `Base.typename(T).wrapper` (`Tagged`) cannot rebuild it.
    struct Tagged{U}
        x::Int
    end
    # The same shape with the owner's `constructorof` (ADR-0004 Context, ADR-0008).
    struct TaggedOk{U}
        x::Int
    end
    ConstructionBase.constructorof(::Type{TaggedOk{U}}) where {U} = TaggedOk{U}

    # A struct that defines `constructorof` (for the Accessors interop test).
    struct Box
        a::Int
        b::String
    end
    ConstructionBase.constructorof(::Type{Box}) = Box
end
