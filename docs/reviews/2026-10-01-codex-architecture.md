The module split is sound. The biggest architectural decisions are numeric fidelity, fallible lazy traversal, and dialect/resolver state. I inspected the local sources; no files were modified.

1. **Define and pin “faithful” before implementation.** Record upstream commits, CPython version, optional-dependency versions, and supported MoonBit backends. Separate Python behavioral compatibility from JSON Schema conformance: they sometimes disagree. Explicitly scope out arbitrary Python objects, introspection, and deprecated `_RefResolver` APIs if unsupported. Resolve these contracts before expanding phase 1.

2. **Core `Json` needs a numeric compatibility layer.** Its parser preserves `repr` for some out-of-range numbers, **not ordinary `1.0`**; core equality ignores `repr`. Thus it cannot reliably recover Python numeric types. [Local parser](/Users/hongbozhang/.moon/lib/core/json/lex_number.mbt:211).

   Draft 3/4 reject Python `1.0` as an integer; Draft 6+ accept it. For fidelity, preserve every numeric token at ingestion and distinguish arbitrary-precision integers from binary64 floats internally. Define behavior for programmatically constructed `Number(..., repr=None)`; lost provenance cannot be reconstructed. Centralize comparison, equality, hashing, arithmetic, and formatting. Test adjacent integers above `2^53`, overflow, underflow, negative zero, and nonfinite inputs. Do not replace Python’s `multipleOf` algorithm with decimal arithmetic or epsilon comparison without documenting the divergence.

3. **Isolate regex compatibility behind an interface.** Upstream uses Python `re.search`; JSON Schema’s ECMA expectations and `moonbitlang/regexp` are separate contracts. Pin and differential-test the actual engine: search versus full matching, `$` before trailing newline, Unicode `\d/\w`, flags, lookarounds, named groups, backreferences, and invalid-pattern errors. Current `regexp` documentation advertises backreferences, so assuming “RE2 limitations” would be incorrect. [Engine documentation](https://github.com/moonbitlang/regexp.mbt).

   Apply this consistently to `pattern`, `patternProperties`, and `format: regex`. Cache compilation, while preserving when observable failures occur.

4. **Centralize Unicode, equality, ordering, and rendering—but keep library-specific semantics.** Count code points for lengths; also audit JMESPath reversal, sorting, and lexer error positions. Test supplementary characters, combining sequences, and lone surrogates.

   JSON Schema equality recursively separates booleans from numbers. The cloned JMESPath comparator only special-cases scalar booleans/numbers before delegating nested equality to Python: blindly sharing one comparator changes behavior.

   Core `Map` already preserves insertion order. Preserve that through parsing and schema traversal; persistent hash-map iteration should not determine keyword order. Implement Python-style `repr` separately from JSON serialization, plus the actual `pformat(width=72, sort_dicts=False)` behavior for full exception strings. Numeric source spelling is not Python `repr`.

5. **Use a fallible pull stream for genuine generator semantics.** Current core `Iter[T]` stores a non-raising `() -> T?`. Reference retrieval and custom keywords can fail during consumption, so choose either a custom `ErrorStream.next() -> ValidationError? raise ...` or `Iter[Result[ValidationError, EvaluationFailure]]`, terminating after failure.

   Implement suspended traversal with closures/state machines and preferably an explicit frame stack. Keep validation failures distinct from evaluation exceptions. `is_valid` requests one error; instance `validate` raises the first. `best_match` consumes every top-level error, retaining the current candidate, then examines its context; reproduce the pinned version’s ranking.

   Callbacks returning `Continue/Stop` simplify synchronous early exit, but cannot provide resumable public iteration without extra machinery. Eager arrays simplify implementation but change retrieval timing, exception timing, memory use, and short-circuiting. Buffer where upstream does—particularly combinator contexts.

6. **Model dynamic validator classes as immutable descriptors.** Define `ValidatorDefinition` containing keyword handlers, metaschema, type checker, default format checker, identifier extraction, referencing specification, and applicable-keyword policy. A `Validator` instance contains its definition, schema, registry/resolver, and optional active format checker.

   Handlers retain `(validator, keywordValue, instance, schema) -> ErrorStream`. `create` constructs a definition; `extend` copies and overlays handlers, replacing matching names rather than automatically chaining them. `evolve` preserves instance configuration but reselects the definition through `$schema`. Centralize `descend` and error enrichment; distinguish unset metadata from explicit JSON null.

7. **Treat reference scope and evaluated locations as core architecture.** Preserve the resolver returned by lookup, subresource boundaries, dynamic scope, lazy registry crawling, and retrieval-updated registries. URI-only caching is insufficient for dynamic references. Test draft-specific `$ref` sibling rules and `unevaluatedProperties/Items` across combinators and references. URI tests need percent-decoding order, UTF-8 replacement, pointer `~0/~1`, empty fragments, queries, and non-hierarchical schemes. Keep retrieval injectable.

8. **Reorder formats and strengthen testing.** Build a thin end-to-end validator before completing every optional format dependency. Preserve formats being opt-in, unknown formats succeeding, and draft-specific checker sets; upstream email checking is merely an `@` check.

   Keep JMESPath independent; keep embedded metaschemas with jsonschema, including referenced vocabulary resources. Avoid package cycles by co-locating mutually dependent public types or injecting dialect lookup.

   Supplement compliance suites with upstream unit tests and differential tests of errors, paths, contexts, and retrieval traces. Embed raw fixture text using `#|`; Python load/dump regeneration can alter numeric spelling. Track fixture counts, skips, remote mappings, and generator reproducibility; run all supported backends.