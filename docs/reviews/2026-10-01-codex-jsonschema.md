Found seven issues outside the README’s documented deviations. Upstream results were reproduced using the vendored Python code; MoonBit outcomes below follow directly from source. `moon test` was blocked because the sandbox cannot create even `/private/tmp` build files. No repository files were modified.

1. **P1 — Case-insensitive negated classes accept excluded ASCII characters.**  
   [parser.mbt:511](/Users/hongbozhang/git/jsonkit.mbt/jsonschema/internal/regex/parser.mbt:511), [emit.mbt:120](/Users/hongbozhang/git/jsonkit.mbt/jsonschema/internal/regex/emit.mbt:120).  
   **Input:** schema `{"pattern":"(?i)^[^a]+$"}`, instance `"a"`. Upstream rejects; the port accepts. The parser complements `{a}` before case folding; the resulting set includes `A`, whose fold adds the excluded `a` back. This exceeds the documented Unicode folding limitation: ordinary ASCII is wrong.  
   **Upstream:** `_keywords.py:215`, `pattern`, delegates to `re.search`.  
   **Fix:** retain class negation in the AST, fold the positive class first, then complement; prevent the engine’s global case flag from folding the complemented result again.

2. **P2 — `uniqueItems` conflates distinct huge integers.**  
   [utils.mbt:176](/Users/hongbozhang/git/jsonkit.mbt/jsonschema/utils.mbt:176).  
   **Input:** schema `{"uniqueItems":true}`; instance loaded from `"[" + "1" + "0"*309 + ",1" + "0"*310 + "]"`—two distinct integer tokens. Upstream accepts; the port rejects. Both backing doubles overflow to infinity, and `uniq_key` checks `d.is_inf()` before consulting the preserved integer spelling, producing identical `ninf;` keys. Nested arrays and objects inherit this bug.  
   **Upstream:** `_utils.py:160`, `_uniq_key`; `_keywords.py:206`, `uniqueItems`.  
   **Fix:** canonicalize Python integers through `is_int`/`int_value` before handling floating-point infinity.

3. **P2 — Scoped disabling of case-insensitivity is ignored.**  
   [emit.mbt:112](/Users/hongbozhang/git/jsonkit.mbt/jsonschema/internal/regex/emit.mbt:112), [regex.mbt:32](/Users/hongbozhang/git/jsonkit.mbt/jsonschema/internal/regex/regex.mbt:32).  
   **Input:** schema `{"pattern":"(?i)(?-i:a)"}`, instance `"A"`. Upstream rejects; the port accepts. The AST correctly records a case-sensitive literal, but emission produces plain `a` while compiling the entire expression with flag `i`.  
   **Upstream:** `_keywords.py:215`, `pattern` / Python `re.search`.  
   **Fix:** emit explicit case scopes for literals and classes, including disabled scopes, or compile without global `i` and implement each AST node’s flag locally.

4. **P2 — `$` consumes input instead of remaining a zero-width assertion.**  
   [emit.mbt:127](/Users/hongbozhang/git/jsonkit.mbt/jsonschema/internal/regex/emit.mbt:127).  
   **Input:** schema `{"pattern":"a$\\n"}`, instance `"a\n"`. Upstream accepts; the port rejects. Translating `$` to `(?:\n?$)` moves the cursor to the absolute end, leaving no newline for the following token. Captures containing `$` can also incorrectly include the newline.  
   **Upstream:** `_keywords.py:215`, `pattern` / Python’s end assertion.  
   **Fix:** implement a zero-width “end or immediately before the final newline” assertion in the matcher.

5. **P2 — `multipleOf` changes arithmetic exceptions into validation results.**  
   [number.mbt:177](/Users/hongbozhang/git/jsonkit.mbt/jsonschema/internal/pycompat/number.mbt:177).  
   **Input:** schema loaded from `{"multipleOf":1.0}`, instance loaded from `"1" + "0"*400`. Upstream raises `OverflowError` during integer-to-float conversion; the port takes its rational fallback and reports valid. With `loads("NaN")` or `loads("Infinity")`, upstream raises `ValueError` or `OverflowError`, while the port yields an ordinary validation error.  
   **Upstream:** `_keywords.py:167`, `multipleOf`; only overflow converting an already-computed quotient is caught.  
   **Fix:** make the helper raising, distinguish operand-conversion overflow from quotient overflow, and propagate equivalent arithmetic errors during consumption.

6. **P2 — Compiled regexes accumulate permanently.**  
   [regex.mbt:21](/Users/hongbozhang/git/jsonkit.mbt/jsonschema/internal/regex/regex.mbt:21).  
   **Trigger:** validate against 100,000 schemas with distinct patterns such as `^review0$`, `^review1$`, etc., then discard their validators. The global map retains every pattern and compiled program, including cached unsupported-pattern results.  
   **Upstream:** `_keywords.pattern` uses CPython `re._compile`, whose caches are bounded; the inspected Python runtime caps them at 512 and 256 entries.  
   **Fix:** use a bounded eviction cache or validator-owned compiled patterns. This matters for long-running services accepting schemas dynamically.

7. **P2 — Built-in format causes cannot be inspected through the public API.**  
   [exceptions.mbt:37](/Users/hongbozhang/git/jsonkit.mbt/jsonschema/exceptions.mbt:37), [formats/errors.mbt:4](/Users/hongbozhang/git/jsonkit.mbt/jsonschema/internal/formats/errors.mbt:4).  
   **Input:** validate `"nope"` against `{"format":"ipv4"}` with the draft’s format checker. The cause is an `AddressValueError`, but its type, constructors, and `class_name` method belong to an `internal` package unavailable to external MoonBit modules. The facade exposes only `Error?`, preventing typed handling of built-in causes.  
   **Upstream:** `_format.FormatChecker.check` preserves an inspectable exception in `cause`.  
   **Fix:** expose public cause types or a public structured cause-inspection API while retaining arbitrary custom errors.