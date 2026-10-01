# bobzhang/jsonschema

A faithful MoonBit port of [python-jsonschema](https://github.com/python-jsonschema/jsonschema):
JSON Schema validation for drafts 3, 4, 6, 7, 2019-09 and 2020-12, with the
same keyword semantics, error messages, error paths, `best_match` heuristics
and format checks as upstream (running with its `format-nongpl` extras
installed). `$ref`, `$dynamicRef` and `$recursiveRef` are resolved by
[`bobzhang/referencing`](../referencing).

The whole official JSON-Schema-Test-Suite runs in `suite/`, held to
*upstream's* recorded outcome for every test (including the handful of
cases where upstream itself disagrees with the suite).

## Validating

```mbt check
///|
test "validate" {
  let schema : Json = {
    "type": "object",
    "properties": { "price": { "type": "number", "minimum": 0 } },
    "required": ["name"],
  }
  @jsonschema.validate({ "name": "Eggs", "price": 34.99 }, schema)
  try @jsonschema.validate({ "name": "Eggs", "price": -1 }, schema) catch {
    @jsonschema.ValidationError(error) => {
      inspect(error.message, content="-1 is less than the minimum of 0")
      inspect(
        error,
        content=(
          #|-1 is less than the minimum of 0
          #|
          #|Failed validating 'minimum' in schema['properties']['price']:
          #|    {'type': 'number', 'minimum': 0}
          #|
          #|On instance['price']:
          #|    -1
        ),
      )
    }
    _ => fail("expected a ValidationError")
  } noraise {
    _ => fail("expected a ValidationError")
  }
}
```

`validate` checks the schema against its meta-schema first (raising
`SchemaError`), picks the validator class from `$schema` (defaulting to the
latest draft) and raises the `best_match` of the errors.

## Validators and lazy errors

A `ValidatorClass` (`draft7_validator`, `draft202012_validator`, ...) plays
the role of upstream's validator classes; `cls.new(schema)` creates a
`Validator`. `iter_errors` returns `Errors`, a lazy sequence: like upstream's
generators, nothing runs until it is consumed, and `is_valid` / `first`
stop at the first error.

```mbt check
///|
test "iter_errors" {
  let validator = @jsonschema.draft202012_validator.new({
    "items": { "type": "integer" },
    "maxItems": 2,
  })
  let errors = validator.iter_errors([1, "two", 3.5]).to_array()
  inspect(
    errors.map(e => "\{e.json_path()}: \{e.message}").join("\n"),
    content=(
      #|$[1]: 'two' is not of type 'integer'
      #|$[2]: 3.5 is not of type 'integer'
      #|$: [1, 'two', 3.5] is too long
    ),
  )
  inspect(validator.is_valid([1, 2]), content="true")
  let best = @jsonschema.best_match(errors.iter()).unwrap()
  inspect(best.message, content="[1, 'two', 3.5] is too long")
}
```

## Formats

Format validation is off unless a `FormatChecker` is given; each class's
`format_checker` holds the checks for its draft.

```mbt check
///|
test "formats" {
  let cls = @jsonschema.draft202012_validator
  let validator = cls.new(
    { "format": "ipv4" },
    format_checker=cls.format_checker,
  )
  inspect(validator.is_valid("127.0.0.1"), content="true")
  inspect(validator.is_valid("127.0.0.01"), content="false")
  inspect(cls.new({ "format": "ipv4" }).is_valid("nope"), content="true")
}
```

## Python numbers

MoonBit's `Json` stores every number as a `Double`. Python distinguishes
`1` from `1.0` (drafts 3 and 4 do not consider `1.0` an integer, and error
messages print `1.0`), so `@jsonschema.loads` parses JSON exactly like
Python's `json.loads`, recording the spelling of float-like numbers in
`Json::Number`'s `repr~`:

```mbt check
///|
test "loads" {
  let one_point_zero = @jsonschema.loads("1.0")
  inspect(
    @jsonschema.draft4_validator
    .new({ "type": "integer" })
    .is_valid(one_point_zero),
    content="false",
  )
  inspect(
    @jsonschema.draft7_validator
    .new({ "type": "integer" })
    .is_valid(one_point_zero),
    content="true",
  )
  inspect(
    @jsonschema.py_repr(@jsonschema.loads("[1.0, 1e400, 7]")),
    content="[1.0, inf, 7]",
  )
}
```

Numbers without a recorded spelling count as ints when they are whole.

## Extending

```mbt check
///|
test "extend" {
  let even : @jsonschema.KeywordFn = (_, value, instance, _) => {
    @jsonschema.Errors::new(yield_ => {
      if value is True && instance is Number(n, ..) && n % 2.0 != 0.0 {
        return yield_(
          @jsonschema.ValidationError::new(
            "\{@jsonschema.py_repr(instance)} is odd",
          ),
        )
      }
      true
    })
  }
  let cls = @jsonschema.draft202012_validator.extend_with(validators=[
    ("even", even),
  ])
  let errors = cls.new({ "even": true }).iter_errors(3).to_array()
  inspect(errors[0].message, content="3 is odd")
  debug_inspect(errors[0].schema_path, content="[Key(\"even\")]")
}
```

## Packages

| package | upstream |
| --- | --- |
| `bobzhang/jsonschema` | `jsonschema` (`validators`, `_keywords`, `_legacy_keywords`, `_types`, `_format`, `_utils`, `exceptions`) |
| `bobzhang/jsonschema/specifications` | `jsonschema-specifications` (meta-schemas, parsed lazily) |
| `bobzhang/jsonschema/internal/pycompat` | `json.loads`, `repr`, `pprint.pformat`, `reprlib`, `textwrap`, Python numerics |
| `bobzhang/jsonschema/internal/regex` | `re`: a port of CPython's parser, run on MoonBit core's `@string.Regex` or, for constructs it lacks, a backtracking matcher following `sre` |
| `bobzhang/jsonschema/internal/formats` | `ipaddress`, `fqdn`, `idna`, `rfc3986-validator`, `rfc3987-syntax`, `rfc3339-validator`, `isoduration`, `jsonpointer`, `uri-template`, `webcolors` |
| `bobzhang/jsonschema/internal/unicodedata` | the `unicodedata` / `idna` tables these need |

## Licenses

The module is MIT-licensed, except `internal/formats/fqdn.mbt`, a port of
`fqdn`, which stays under the MPL-2.0. See `NOTICE` for the third-party
works (python-jsonschema, CPython, the Unicode data, the format-checking
libraries, the JSON-Schema-Test-Suite, ...) this module derives from.

`scripts/` regenerates the embedded data (`gen_unicodedata.py`,
`gen_format_data.py`, `gen_specifications.py`) and the suite tests
(`suite_oracle.py` records upstream's outcomes, `gen_suite.py` writes
`suite/gen_*_test.mbt`).

## Deviations from upstream

* Format checks follow upstream's `format-nongpl` configuration:
  `uri` / `uri-reference` use rfc3986-validator and `iri` /
  `iri-reference` use rfc3987-syntax (not the GPL `rfc3987` package).

* Draft 3 / 4 `integer`: needs `loads` (or `Json::number(x, repr="1.0")`)
  to tell `1.0` from `1`; whole numbers without a spelling are ints.
* Regular expressions: `\N{...}` escapes are rejected (no Unicode name
  table). Everything else -- including lookaround, atomic groups, possessive
  quantifiers, conditionals, backreferences, Unicode `\b` and CPython's
  case-insensitive equivalences -- follows CPython 3.13's `re`
  (differentially tested against it). Lone surrogates in subjects are
  never matched by character classes.
* No network access: the default registry holds the meta-schemas only
  (upstream fetches unknown remote `$ref`s with a deprecation warning).
* Unresolvable references raise `bobzhang/referencing` errors directly
  (`@referencing.is_unresolvable`), not upstream's `_WrappedReferencingError`.
* No deprecation warnings (e.g. for unknown `$schema`s); the deprecated
  `RefResolver` API is not ported.
* `extend` is `ValidatorClass::extend_with` (`extend` is reserved in
  MoonBit); validator classes are values (`draft7_validator`), not types.
* Built-in format checks raise the public `FormatCause` errors
  (`AddressValueError`, `IDNAError`, ... named after upstream's exception
  classes), available as `ValidationError::cause`.
* Python-level crashes upstream would hit (e.g. `OverflowError` in
  `multipleOf` for ints too large for a float) are raised as `PythonError`.
* Values Python allows but JSON cannot hold (non-string keys, tuples,
  `Decimal`) are out of scope.
