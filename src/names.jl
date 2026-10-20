# Public, not exported (ADR-0005 §3). `public` is a ParseError on Julia 1.10, so it goes through
# Compat (a no-op there; ecosystem ADR-0006 §3–4). Used qualified (`ChuiCore.combine`) or through
# `using ChuiCore: combine`.

# Exported by Functors 0.4.12 (`fmap`) or TypeClasses 1.1.0 (`neutral`, `curry`, `pure`, `ap`), so
# the clash list keeps them public only (ADR-0005 §2).
@compat public neutral, curry, fmap, pure, ap, traverse, sequence

# Law kits (ADR-0007).
@compat public Law, ExactEq, default_eq

# The aggregation protocol (CC-004, CC-005) and the monoid family (ADR-0001 §1–2).
@compat public init, partial, combine, final, iscommutative, combineall, default_monoid
@compat public AlgebraClass, IsSemigroup, IsMonoid, NotAlgebra

# Built-in aggregators (CC-007).
@compat public Sum, Prod, Count, CountTrue, AnyM, AllM, Max, Min, Extrema, First, Last
@compat public Mean, Moments, ReduceM, MapM

# Constructor classes (ADR-0001 §3): the tag mapping, tags, styles and owned instance types.
@compat public constructorclass
@compat public NoTag, MaybeTag, ArrayTag, TupleTag, DictTag, PairTag, FunctionTag
@compat public IdentityTag, ZipVectorTag, PredicateTag
@compat public FunctorStyle, IsFunctor, NotFunctor
@compat public ApplicativeStyle, IsApplicative, NotApplicative
@compat public MonadStyle, IsMonad, NotMonad
@compat public AlternativeStyle, IsAlternative, NotAlternative
@compat public FoldableStyle, IsFoldable, NotFoldable
@compat public TraversableStyle, IsTraversable, NotTraversable
@compat public ContravariantStyle, IsContravariant, NotContravariant
@compat public BifunctorStyle, IsBifunctor, NotBifunctor
@compat public ProfunctorStyle, IsProfunctor, NotProfunctor
@compat public CategoryStyle, IsCategory, NotCategory
@compat public ArrowStyle, IsArrow, NotArrow
@compat public Identity, ZipVector, Predicate

# The transducer substrate (ADR-0003 §7): types, reducing functions, protocol, folds.
@compat public Transducer, Map, Filter, MapCat, Take, TakeWhile, Scan, Partition, Composed
@compat public R, Bottom, asrf, start, next, complete, isstateless
@compat public Reduced, reduced, unreduced, isreduced
@compat public foldxl, foldparts, foldxt, aggregate

# Recursion schemes (request R6; research recommendations 1–4).
@compat public Fix, project, cata, ana, hylo, para, apo, histo, futu, cataM, anaM, hyloM
@compat public Done, More, Attr, Emit

# Data types à la carte and the freer monad (research recommendations 5–6).
@compat public Coproduct, Inl, Inr, CoproductTag, inj, prj
@compat public Free, Pure, Impure, FreeTag, liftF, interpret, cohandler, foldfree

# Optics (ADR-0004, ADR-0008). `set`/`modify` are never exported: a bare `set` would clash with
# Accessors' export.
@compat public Lens, IndexLens, @lens, Prism, preview, review, set, modify

# Laziness (research recursion-schemes-free-laziness.md, recommendation 7; request R5).
@compat public Thunk, Lazy, force, isforced, @lazy, LazyTag

# The name-conflict banner (request R9).
@compat public binding_conflicts, conflict_banner
