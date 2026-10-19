# Research: typeclass inspiration (Haskell `base`, `profunctors`, Scala cats, Bjarnason)

- **Date:** 2026-10-20
- **Lane:** phase1-research (researcher)
- **Companion note:** `trait-encoding.md`, which maps these classes onto Julia encodings.

## Question

1. What is the class hierarchy, and what are the stated laws, for:
   - Semigroup, Monoid
   - Functor, Applicative, Monad, Alternative
   - Foldable, Traversable
   - Contravariant, Bifunctor
   - Profunctor (`profunctors`)
   - Category, Arrow

   The sources are Haskell `base` and `profunctors`.
2. How does Scala cats encode typeclasses (implicits), and how are its exportable law kits
   (`cats-laws`, `cats-kernel-laws`, discipline) structured? They are the model for ChuiCore's
   exported kits.
3. What does Rúnar Bjarnason's "Constraints Liberate, Liberties Constrain" say, as it bears on
   choosing the weakest abstraction?

## Method

- **Fetching.** Pages were fetched on 2026-10-20 with WebFetch by a sub-lane (general-purpose
  agent, read-only, no file writes). That tool converts HTML to markdown and limits verbatim prose
  quotes to about 125 characters. Code and equations were quoted exactly.
- **Stripped equations.** Where the Hackage HTML conversion dropped the law equations, the sub-lane
  fetched the Haskell source the docs are built from. The source used is named per item.
- **Context7 (this lane).** `/typelevel/cats`, queried for Monoid laws, law testing and the
  implicit encoding. Those results agree with the fetched pages.
- **Versions.**
  - `base` 4.22.0.0: `hackage.haskell.org/package/base/docs/...` redirects there; it is built from
    ghc-internal-9.1401.0.
  - `profunctors` 5.6.3.
  - cats 2.13.0: from `"org.typelevel" %% "cats-laws" % "2.13.0"` on the lawtesting page.
  - discipline-core 1.5.0.

## Findings with sources

### Haskell `base` 4.22.0.0

The Hackage URLs are `https://hackage.haskell.org/package/base/docs/<Module>.html`.

| Class | Superclass | Minimal | Laws (as stated) | Source |
|---|---|---|---|---|
| Semigroup | none | `(<>) \| sconcat` | Associativity: `x <> (y <> z) = (x <> y) <> z`. If `sconcat` is defined instead: `sconcat (pure x) = x`; `sconcat (join xss) = sconcat (fmap sconcat xss)`. | Data-Semigroup |
| Monoid | Semigroup | `mempty \| mconcat` | Right identity `x <> mempty = x`; left identity `mempty <> x = x`; associativity; concatenation `mconcat = foldr (<>) mempty`. `mappend` is redundant (`= (<>)` since base-4.11). | Data-Monoid |
| Functor | none | `fmap` | Identity `fmap id == id`; composition `fmap (f . g) == fmap f . fmap g`. | Data-Functor |
| Applicative | Functor | `pure` and (`<*>` or `liftA2`) | Identity `pure id <*> v = v`; composition `pure (.) <*> u <*> v <*> w = u <*> (v <*> w)`; homomorphism `pure f <*> pure x = pure (f x)`; interchange `u <*> pure y = pure ($ y) <*> u`. Consequence: `fmap f x = pure f <*> x`. | Control-Applicative; equations from GHC master `ghc-internal/src/GHC/Internal/Base.hs` |
| Alternative | Applicative | `empty, (<\|>)` | "A monoid on applicative functors": `empty <\|> a == a`, `a <\|> empty == a`, `(<\|>)` associative. `some`/`many`, if defined, "should be the least solutions of" `some v = (:) <$> v <*> many v` and `many v = some v <\|> pure []`. | Control-Applicative |
| Monad | Applicative | `(>>=)` | Left identity `return a >>= k = k a`; right identity `m >>= return = m`; associativity `m >>= (\x -> k x >>= h) = (m >>= k) >>= h`. Coherence with Applicative: `pure = return`, `m1 <*> m2 = m1 >>= (\x1 -> m2 >>= (\x2 -> return (x1 x2)))`, which implies `fmap f xs = xs >>= return . f` and `(>>) = (*>)`. | Control-Monad, plus Base.hs |
| MonadPlus | Alternative, Monad | (defaults) | `mzero >>= f = mzero`; `v >> mzero = mzero`; `mzero = empty`, `mplus = (<\|>)`. | Control-Monad, plus Base.hs |
| Foldable | none | `foldMap \| foldr` | `foldr f z t = appEndo (foldMap (Endo . f) t) z` ("equivalent in value and strictness"); `foldl f z t = appEndo (getDual (foldMap (Dual . Endo . flip f) t)) z`; `fold = foldMap id`; `length = getSum . foldMap (Sum . const 1)`; `sum = getSum . foldMap' Sum`; `product = getProduct . foldMap' Product`. If also a Functor: `foldMap f = fold . fmap f`, hence `foldMap f . fmap g = foldMap (f . g)`. | Data-Foldable |
| Traversable | Functor, Foldable | `traverse \| sequenceA` | For an applicative transformation `t` (`t (pure x) = pure x`, `t (f <*> x) = t f <*> t x`): naturality `t . traverse f = traverse (t . f)`; identity `traverse Identity = Identity`; composition `traverse (Compose . fmap g . f) = Compose . fmap (traverse g) . traverse f`. Equivalent `sequenceA` laws. `fmap` should equal `fmapDefault` (identity applicative) and `foldMap` should equal `foldMapDefault` (constant applicative). | Data-Traversable |
| Contravariant | none | `contramap` | `contramap id = id`; `contramap (g . f) = contramap f . contramap g`. | Data-Functor-Contravariant |
| Bifunctor | `forall a. Functor (p a)` (since base-4.18) | `bimap \| first, second` | `second ≡ fmap`; `bimap id id ≡ id` (or `first id ≡ id`, `second id ≡ id`); if both are given, `bimap f g ≡ first f . second g`. By parametricity: `bimap (f . g) (h . i) ≡ bimap f h . bimap g i`, and the same for `first` and `second`. | Data-Bifunctor; equations from `base-4.22.0.0/docs/src/Data.Bifunctor.html` |
| Category | none | `id`, `(.)` | `f . id = f`; `id . f = f`; `f . (g . h) = (f . g) . h`. | Control-Category |
| Arrow | Category | `arr, (first \| (***))` | `arr id = id`; `arr (f >>> g) = arr f >>> arr g`; `first (arr f) = arr (first f)`; `first (f >>> g) = first f >>> first g`; `first f >>> arr fst = arr fst >>> f`; `first f >>> arr (id *** g) = arr (id *** g) >>> first f`; `first (first f) >>> arr assoc = arr assoc >>> first f`, where `assoc ((a,b),c) = (a,(b,c))`. ArrowChoice, ArrowApply and ArrowLoop each have their own laws. | Control-Arrow; equations from GHC master `GHC/Internal/Control/Arrow.hs` |

**Profunctor** (`profunctors` 5.6.3, `https://hackage.haskell.org/package/profunctors/docs/Data-Profunctor.html`;
equations from https://raw.githubusercontent.com/ekmett/profunctors/master/src/Data/Profunctor/Internal.hs):
- Superclass: `class (forall a. Functor (p a)) => Profunctor p`.
- Minimal: `dimap | (lmap, rmap)`.
- Laws: `dimap id id ≡ id`; `lmap id ≡ id`, `rmap id ≡ id`; and `dimap f g ≡ lmap f . rmap g`
  when both are given.
- By parametricity: `dimap (f . g) (h . i) ≡ dimap g h . dimap f i`;
  `lmap (f . g) ≡ lmap g . lmap f`; `rmap (f . g) ≡ rmap f . rmap g`.

**The hierarchy, as a Julia kit set would mirror it:**
- `Semigroup ⊂ Monoid`
- `Functor ⊂ Applicative ⊂ Monad`
- `Applicative ⊂ Alternative`, and `(Alternative, Monad) ⊂ MonadPlus`
- `(Functor, Foldable) ⊂ Traversable`
- `Category ⊂ Arrow`
- Contravariant stands alone. Bifunctor and Profunctor carry a quantified Functor superclass on
  their last argument.

**Points that matter for ChuiCore:**
- **Minimal definitions with defaults.** Most classes have alternative minimal sets, such as
  `foldMap | foldr` and `traverse | sequenceA`, with the rest derived. The derived methods are
  themselves laws: Foldable's `foldr = ... foldMap`, and Traversable's `fmap = fmapDefault`. A
  Julia kit should check that a type's overridden fast paths agree with the derived definitions.
  That is the kind of law that catches real bugs.
- **Alternative's laws are only the monoid laws.** The base 4.22 page states the monoid laws on
  `empty`/`<|>` plus the `some`/`many` least-solution condition. It does **not** state
  distributivity, left catch or left zero. ChuiCore should not export those as Alternative laws
  without its own decision.
- **Foldable's laws are relational.** They relate the methods to `foldMap`; there is no free
  theorem. This fits Julia, where `foldl`/`mapreduce` are Base's and a kit checks agreement
  between them.

### Scala cats 2.13.0

**Encoding** (`https://typelevel.org/cats/typeclasses.html`, `.../typeclasses/monoid.html`,
`.../semigroup.html`; also Context7 `/typelevel/cats` docs/typeclasses.md):
- **Shape.** A typeclass is a parameterised trait: `trait Semigroup[A] { def combine(x: A, y: A): A }`
  and `trait Monoid[A] extends Semigroup[A] { def empty: A }`.
- **Instances are values.** `implicit val intAdditionMonoid: Monoid[Int] = new Monoid[Int] { def
  empty = 0; def combine(x: Int, y: Int) = x + y }`.
- **Use sites** take the instance as an implicit parameter, `def combineAll[A](list:
  List[A])(implicit A: Monoid[A]): A`, or as a context bound `[A : Monoid]` with the summoner
  `Monoid[A]` (`implicitly`).
- **Laws** as stated: `combine(x, combine(y, z)) = combine(combine(x, y), z)` and
  `combine(x, empty) = combine(empty, x) = x`.
- **Typeclasses vs subtyping.**
  - With subtyping, `empty` can only be reached through a value, so an empty list gives nothing to
    call it on. A typeclass instance supplies `empty` from the type alone.
  - `Monoid[Pair[A, B]]` is derivable from `Monoid[A]` and `Monoid[B]`, so `Pair` is a Monoid only
    when its parameters are.
- **Relevance.** cats names the operations `combine` and `empty`, and makes the instance an
  explicit value. ChuiCore's `combine(m, a, b)` is the cats call with the implicit made explicit
  (Julia has no implicits); see `trait-encoding.md` F2 and F5.

**Law kits** (`https://typelevel.org/cats/typeclasses/lawtesting.html`, plus sources on GitHub
`typelevel/cats` main):
- **Two layers.**
  - *Laws*: functions that return `IsEq[A]` (an `lhs <-> rhs` pair).
  - *Tests / RuleSet*: bundles laws with ScalaCheck `Arbitrary` generators and an `Eq`.
- **`FunctorLaws[F[_]]`** (`laws/src/main/scala/cats/laws/FunctorLaws.scala`):
  `covariantIdentity(fa) = fa.map(identity) <-> fa` and
  `covariantComposition(fa, f, g) = fa.map(f).map(g) <-> fa.map(f.andThen(g))`. It extends
  `InvariantLaws`.
- **`MonoidLaws[A] extends SemigroupLaws[A]`**
  (`kernel-laws/shared/src/main/scala/cats/kernel/laws/MonoidLaws.scala`):
  - `leftIdentity`
  - `rightIdentity`
  - `repeat0`: `combineN(x, 0) <-> empty`
  - `collect0`: `combineAll(Nil) <-> empty`
  - `combineAll`: `combineAll(xs) <-> (empty +: xs).reduce(combine)`
  - `isId`

  The kit therefore also checks the derived methods (`combineN`, `combineAll`, `isEmpty`) against
  the primitive ones.
- **`FunctorTests[F[_]]`** (`laws/.../discipline/FunctorTests.scala`):
  - `def functor[A: Arbitrary, B: Arbitrary, C: Arbitrary](implicit ArbFA, CogenA, ..., EqFA, EqFC): RuleSet`
    returns `DefaultRuleSet(name = "functor", parent = Some(invariant[A, B, C]),
    "covariant identity" -> forAll(...), ...)`.
  - `FunctorTests[F: Functor]` takes the instance.
- **Usage.** `checkAll("Tree.FunctorLaws", FunctorTests[Tree].functor[Int, Int, String])` and
  `checkAll("Tree[Int].SemigroupLaws", SemigroupTests[Tree[Int]].semigroup)`. Kernel classes'
  kits live in `cats.kernel.laws.discipline.*`. Users must supply `Eq[Tree[A]]` and
  `Arbitrary[Tree[A]]`.
- **discipline** (`typelevel/discipline`; README, 1.5.0, "Flexible law checking for Scala"; and
  `core/src/main/scala/org/typelevel/discipline/Laws.scala`):
  - `trait Laws` is "a wrapper around scalacheck's `Properties`".
  - `trait RuleSet { name; bases; parents; props; final def all: Properties }`.
  - Parents are the same kind of class (Monoid → Semigroup), and bases are other classes.
    Duplicate properties within a kind are removed, so a shared law is checked once.
  - Integrations exist for MUnit, ScalaTest and Specs2.

**What carries over to ChuiCore's exported kits.**
- One kit per class.
- The kit takes the instance (or type), a generator, and an equality, and returns or runs named
  laws.
- A child kit runs its parent's laws (the Monoid kit runs the Semigroup kit).
- Derived methods are checked against primitives.
- The kit is test-framework-agnostic at the law layer, with a thin runner for the
  framework (`@testitem`/`@testset` here).

Julia has no `Arbitrary`/`Cogen` typeclasses, so generators are passed explicitly. For classes
with function arguments (Functor composition), the kit needs a generator of functions too: cats
gets those from `Cogen`. UNVERIFIED: how to generate random functions in Julia (e.g. via
Supposition.jl or PropCheck.jl) was not researched here.

### Rúnar Bjarnason, "Constraints Liberate, Liberties Constrain"

- **Primary source.** The talk video, `https://www.youtube.com/watch?v=GqmsQeSzMdw`, titled
  "Constraints Liberate, Liberties Constrain — Runar Bjarnason". YouTube's oEmbed endpoint gives
  the channel as **Scala World**. The upload date and description could not be read, and the video
  content was not watched.
- **Venue and date (secondary).** A third-party ScalaWorld 2015 recap deck,
  `https://speakerdeck.com/ajantis/scalaworld-2015-recap`, lists the conference as September 20-22,
  2015, Lake District, UK. Its slide 24 is titled with the talk and quotes:
  - "Premature loss of precision is the root of all evil"
  - "Reach for the least powerful abstraction"
  - "Detonate as late as possible"
- **Thesis (secondary).** An abstract quoted at `https://huffduffer.com/rbright/346594`
  (huffduffed 2016-07-23, linking the video); it is likely, but unconfirmed, to be the talk's own
  description:
  > "restraint and precision are usually better than power and flexibility. A constraint on
  > component design leads to freedom and power when putting those components together into
  > systems."
- **How it bears on ChuiCore** (this lane's reading, applying the quoted thesis):
  - **The constraint on a type is a promise to its users.** A type that is only a Functor
    promises less, so more types satisfy it and more code can accept it. A function that needs
    only `Foldable` should not demand `Traversable` or `Monad`.
  - **Parse with an Applicative, not a Monad.** Applicative composition keeps the structure
    statically inspectable; this is the "describe now, detonate late" point, which the brief's
    free-monad and interpreter scope also relies on. For ChuiFrames's plans this argues for
    Applicative (static, analysable) over Monad (dynamic) wherever a plan does not need the result
    of one step to choose the next.
  - **For aggregators:** declare the weakest structure that holds. A *Semigroup* when there is no
    identity (Max, First). A *Monoid* when there is. `iscommutative` (CC-005) is an extra
    constraint that unlocks unordered parallel merges. That is the same "constraint liberates the
    caller" trade, and it supports keeping Semigroup and Monoid as separate classes with separate
    kits, rather than faking identities (`typemin`) to force everything into Monoid. See
    `trait-encoding.md` F6.

## UNVERIFIED

- The Applicative, Monad, MonadPlus, Arrow and Profunctor law equations came from the GHC master
  and `profunctors` master sources, not from the exact base-4.22.0.0 or profunctors-5.6.3 tags.
  The Hackage pages for those versions were fetched, but their equations were stripped in
  conversion. Wording may differ slightly from the tagged release; the laws themselves are
  long-standing.
- The Traversable "purity" law implied by naturality: its equation was stripped and not recovered.
- The exact prose of the Hackage pages: quotes were limited to fragments by the fetch tool.
- Bjarnason's talk content: the video was not watched. The thesis comes from a secondary abstract
  (huffduffer) and an attendee's recap slide. No speaker slides or transcript were found.
- Whether ScalaWorld 2015 is the recording in the YouTube video: inferred from the channel name
  plus the recap deck, not confirmed by the video page.
- The discipline README does not itself mention `checkAll`; its usage comes from the cats
  lawtesting page.
- Random-function generation for Julia law kits (the analogue of cats' `Cogen`): not researched.
- The ArrowChoice, ArrowApply and ArrowLoop law lists were fetched (see the fetch lane's report)
  but are not reproduced in full here; check them before writing an ArrowChoice kit.

## Also noticed

- The base 4.22 Bifunctor and Profunctor classes now have a quantified-constraint superclass,
  `forall a. Functor (p a)`. A Julia Bifunctor kit can therefore check `second ≡ map`-style
  coherence where `map` on the second argument already exists.
- TypeClasses.jl (Julia, JuliaFunctional) already uses the cats/Haskell vocabulary `combine`,
  `neutral`, `orelse` (⊘, for Alternative), `ap` and `flatmap`, and documents the laws in
  docstrings, but ships no law-test kit. See `trait-encoding.md` F9.
