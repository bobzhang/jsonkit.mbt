# jsonkit.mbt

Faithful MoonBit ports of Python JSON tooling, organized as a `moon.work`
workspace of three modules:

| Module | Port of | Highlights |
|---|---|---|
| [`bobzhang/jmespath`](jmespath) | [jmespath.py](https://github.com/jmespath/jmespath.py) | All 917 compliance cases + 390 differential cases checked byte-for-byte against CPython |
| [`bobzhang/referencing`](referencing) | [python-jsonschema/referencing](https://github.com/python-jsonschema/referencing) | `$ref`/`$dynamicRef`/`$recursiveRef` engine for drafts 3–2020-12, the full referencing-suite, and a CPython-faithful `urllib.parse` port (`referencing/urllib`) |
| [`bobzhang/jsonschema`](jsonschema) | [python-jsonschema](https://github.com/python-jsonschema/jsonschema) | Validators for drafts 3, 4, 6, 7, 2019-09, 2020-12 with upstream's error messages, `best_match`, `ErrorTree` and format checkers; matches upstream's outcome on all 9,943 JSON-Schema-Test-Suite tests |

`jsonschema` depends on `referencing`; `jmespath` is standalone. All
modules use MoonBit's core `Json` as the value type. Each module's README
has usage examples (checked by `moon test`) and a "Differences from
upstream" section.

## Development

```bash
moon check
```

Tests are run per package (sub-packages are not included in their parent's run):

```bash
for p in jmespath referencing referencing/urllib referencing/jsonschema jsonschema jsonschema/suite jsonschema/specifications jsonschema/internal/pycompat jsonschema/internal/regex jsonschema/internal/unicodedata; do moon test $p; done
```

The generated test files (compliance suites, differential tests, embedded
metaschemas, Unicode tables) are produced by the Python scripts in each
module's `scripts/` directory from the upstream sources. To fetch those at
the pinned commits:

```bash
./scripts/fetch_upstream.sh
```

Reviews of the port by an independent model are kept in [docs/reviews](docs/reviews).
