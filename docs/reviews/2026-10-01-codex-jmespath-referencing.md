Found seven issues outside the documented differences. MoonBit outcomes were reproduced using existing JavaScript build artifacts; Python comparisons used vendored jmespath and CPython 3.13.5. No files changed.

1. **P1 — Large positive slice steps panic.** [jmespath/visitor.mbt:327](/Users/hongbozhang/git/jsonkit.mbt/jmespath/visitor.mbt:327)  
   Input: `search("[1::2147483647]", [0,1,2])`. Upstream returns `[1]`; MoonBit panics. After selecting index 1, `i += step` overflows to a negative index, which still satisfies `i < stop`. This occurs within the supported `Int` range, independently of documented token saturation.  
   **Upstream:** `upstream/jmespath.py/jmespath/visitor.py:218`, `visit_slice`.  
   **Fix:** Calculate iteration count first, use wider arithmetic, or check remaining distance before incrementing.

2. **P2 — Mixed integer/float summation differs from CPython.** [jmespath/functions.mbt:353](/Users/hongbozhang/git/jsonkit.mbt/jmespath/functions.mbt:353)  
   Input: `sum(@)` with data parsed by `loads("[1,1e16,-1e16]")`. Upstream returns `0.0`; MoonBit returns `1.0`. CPython performs the initial integer-to-float addition before entering compensated summation; the port compensates that addition too. `avg` inherits the discrepancy. The only integer here is exactly representable, so this is distinct from the documented large-integer approximation.  
   **Upstream:** `functions.py:281`, `_func_sum`, and `functions.py:169`, `_func_avg`.  
   **Fix:** Mirror CPython’s transition into the floating-point accumulation path.

3. **P2 — Stable mergesort does not reproduce Python sorting with `NaN`.** [jmespath/functions.mbt:385](/Users/hongbozhang/git/jsonkit.mbt/jmespath/functions.mbt:385)  
   Input: `sort(@)` with `loads("[1,0,NaN]")`. CPython 3.13.5 returns `[0,NaN,1]`; MoonBit returns `[0,1,NaN]`. Stability alone cannot guarantee equivalence when comparisons lack a total ordering. `sort_by` uses the same implementation.  
   **Upstream:** `functions.py:277`, `_func_sort`, and `functions.py:310`, `_func_sort_by`.  
   **Fix:** Reproduce the targeted CPython sorting algorithm for unordered values, or explicitly document this limitation.

4. **P2 — Container equality and membership lose Python’s identity shortcut.** [jmespath/pycompare.mbt:37](/Users/hongbozhang/git/jsonkit.mbt/jmespath/pycompare.mbt:37), [jmespath/functions.mbt:558](/Users/hongbozhang/git/jsonkit.mbt/jmespath/functions.mbt:558)  
   With data `loads("[NaN]")`, both `@ == @` and `contains(@, [0])` return `true` upstream and `false` here. Python container comparisons and membership accept identical objects before invoking numeric equality.  
   **Upstream:** `visitor.py:8`, `_equals`, and `functions.py:214`, `_func_contains`.  
   **Fix:** Add identity-aware comparison for containers, their elements, and membership. Preserve ordinary scalar `NaN != NaN`.

5. **P2 — String searches can match half a Unicode character.** [jmespath/functions.mbt:563](/Users/hongbozhang/git/jsonkit.mbt/jmespath/functions.mbt:563)  
   Expression `` contains('😀', `"\ud83d"`) `` returns `false` upstream but `true` here; `starts_with` has the same discrepancy. Native UTF-16 substring operations match the emoji’s leading surrogate, whereas Python compares code points.  
   **Upstream:** `functions.py:214`, `_func_contains`, and `_func_starts_with`/`_func_ends_with`.  
   **Fix:** Implement these operations over code-point sequences, including isolated surrogate values, rather than raw UTF-16 substrings.

6. **P2 — Numeric whitespace handling differs in both modules.** [referencing/resource.mbt:182](/Users/hongbozhang/git/jsonkit.mbt/referencing/resource.mbt:182), [jmespath/pynumber.mbt:237](/Users/hongbozhang/git/jsonkit.mbt/jmespath/pynumber.mbt:237)  
   For an opaque root `["hit"]`, lookup `#/%C2%A00` should return `"hit"`: percent-decoding produces NBSP followed by `0`, accepted by Python `int()`. MoonBit raises `PointerToNowhere`. Conversely, `` to_number(`"\u001c1"`) `` returns `1` here but `null` upstream: Python’s numeric parsers reject U+001C despite `str.isspace()` accepting it.  
   **Upstream:** `upstream/referencing/referencing/_core.py:267`; jmespath `functions.py:197`.  
   **Fix:** Use Python’s numeric-parser whitespace rules, separately from general string stripping. This is unrelated to the documented Unicode-digit limitation.

7. **P2 — API: custom anchors compare equal despite different resolution behavior.** [referencing/anchor.mbt:54](/Users/hongbozhang/git/jsonkit.mbt/referencing/anchor.mbt:54)  
   Create two `Anchor::custom` values with identical name, resource, and kind, but callbacks resolving to different contents. They compare equal because `resolve_impl` is ignored; registry equality inherits this.  
   **Upstream reference:** `referencing/typing.py`, `Anchor` protocol, permits custom implementations with their own equality; `_core.py:722` defines the simpler builtin anchor. This is a port API-design problem.  
   **Fix:** Include optional callback identity in equality, consistently with `Specification` and registry retriever equality.