# bobzhang/jmespath

A faithful MoonBit port of [jmespath.py](https://github.com/jmespath/jmespath.py)
1.1.0, the Python implementation of [JMESPath](https://jmespath.org), a query
language for JSON.

The port mirrors the upstream structure — lexer, Pratt parser with the same
binding powers, AST, `TreeInterpreter`, the function table with its
signature/type-checking machinery, and the exception classes with the same
messages — and reproduces Python's semantics: truthiness, `==` (where
`1 == 1.0`), ordering of numbers and strings, code-point based string
functions, `json.dumps` output for `to_string`, and so on.  Values are core
`Json`.

## Searching

```mbt check
///|
test "search" {
  let data : Json = {
    "people": [
      { "name": "alice", "age": 30 },
      { "name": "bob", "age": 25 },
      { "name": "carol", "age": 35 },
    ],
  }
  json_inspect(@jmespath.search("people[?age > `26`].name", data), content=[
    "alice", "carol",
  ])
  json_inspect(
    @jmespath.search("max_by(people, &age).name", data),
    content="carol",
  )
  json_inspect(
    @jmespath.search("people[*].{n: name, adult: age >= `18`} | [0]", data),
    content={ "n": "alice", "adult": true },
  )
}
```

`compile` parses once; the result can be evaluated many times.  Compiled
expressions are also kept in a small global cache, like upstream.

```mbt check
///|
test "compile" {
  let expr = @jmespath.compile("sort_by(@, &to_number(v))[*].k")
  json_inspect(expr.search([{ "k": "a", "v": "10" }, { "k": "b", "v": "9" }]), content=[
    "b", "a",
  ])
  inspect(expr.expression, content="sort_by(@, &to_number(v))[*].k")
}
```

## Errors

All errors are constructors of `JMESPathError`, named after the upstream
exception classes; `to_string()` gives the same text as Python's `str(e)`.

```mbt check
///|
test "errors" {
  try @jmespath.compile("foo]bar") catch {
    e =>
      inspect(
        e,
        content=(
          #|Unexpected token: ]: Parse error at column 3, token "]" (RBRACKET), for expression:
          #|"foo]bar"
          #|    ^
        ),
      )
  } noraise {
    _ => fail("expected a parse error")
  }
  try @jmespath.search("length(@)", Json::number(2.0)) catch {
    JMESPathTypeError(function_name~, actual_type~, ..) as e => {
      inspect(function_name, content="length")
      inspect(actual_type, content="number")
      inspect(
        e,
        content="In function length(), invalid type for value: 2, expected one of: ['string', 'array', 'object'], received: \"number\"",
      )
    }
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("expected a type error")
  }
}
```

## Custom functions

Upstream adds functions by subclassing `jmespath.functions.Functions` and
decorating `_func_<name>` methods with `@signature(...)`.  Here a `Functions`
table starts with the builtins and `register_function` adds entries; pass
it with `Options`.  Arguments are validated against the signature before
the implementation runs, and expression references arrive as
`Value::Expref`.

```mbt check
///|
test "custom functions" {
  let functions = @jmespath.Functions::new()
  functions.register_function(
    "count_if",
    [@jmespath.ArgSpec::new(["expref"]), @jmespath.ArgSpec::new(["array"])],
    args => {
      guard args is [Expref(expref), Data(Array(items))] else { Json::null() }
      let mut n = 0
      for item in items {
        if expref.visit(item) is True {
          n += 1
        }
      }
      Json::number(n.to_double())
    },
  )
  let options = @jmespath.Options::new(custom_functions=functions)
  json_inspect(
    @jmespath.search("count_if(&(@ > `1`), @)", [1, 2, 3], options~),
    content=2,
  )
  // The signature is enforced like for builtins.
  try @jmespath.search("count_if(@, @)", [1], options~) catch {
    e =>
      inspect(
        e,
        content="In function count_if(), invalid type for value: [1], expected one of: ['expref'], received: \"array\"",
      )
  } noraise {
    _ => fail("expected a type error")
  }
}
```

## Python numbers and `json` helpers

`loads` is a port of Python's `json.loads` (it accepts `NaN`/`Infinity` and
reports Python's error messages) and `dumps` of
`json.dumps(v, separators=(',', ':'))` (ASCII-only output).  `loads` keeps
the Python int/float distinction that core `Json` lacks (see below), so
`1.0` stays a float.

```mbt check
///|
test "python numbers" {
  let data = @jmespath.loads("{\"a\": 1, \"b\": 1.0, \"c\": \"\u{e9}\"}")
  inspect(
    @jmespath.dumps(@jmespath.search("[a, b, c]", data)),
    content="[1,1.0,\"\\u00e9\"]",
  )
  inspect(
    @jmespath.dumps(
      @jmespath.search("[to_string(b), avg(`[1, 2]`), sum(`[1, 2]`)]", data),
    ),
    content=(
      #|["1.0",1.5,3]
    ),
  )
}
```

## API overview

| jmespath.py                         | MoonBit                                   |
| ----------------------------------- | ----------------------------------------- |
| `jmespath.search(expr, data, opts)` | `@jmespath.search(expr, data, options?)`  |
| `jmespath.compile(expr)`            | `@jmespath.compile(expr)`                 |
| `ParsedResult.search(data, opts)`   | `ParsedResult::search(data, options?)`    |
| `ParsedResult._render_dot_file()`   | `ParsedResult::render_dot_file()`         |
| `parser.Parser().parse(expr)`       | `Parser::new().parse(expr)`               |
| `Parser.purge()`, `_MAX_SIZE`       | `Parser::purge()`, `parser_max_size`      |
| `lexer.Lexer().tokenize(expr)`      | `Lexer::new().tokenize(expr)` (`Token`)   |
| `ast.field(name)`, ...              | `Node::Field(name)`, ... (`Node::to_json` gives the dict form) |
| `visitor.TreeInterpreter(options)`  | `TreeInterpreter::new(options?)`          |
| `visitor.Options(custom_functions)` | `Options::new(custom_functions?)`         |
| `visitor._Expression`               | `Expression` (`Expression::visit(value)`) |
| `functions.Functions`, `@signature` | `Functions`, `ArgSpec`, `register_function` |
| `exceptions.*Error`                 | `JMESPathError::*Error` constructors      |

## Tests

* `compliance_*_test.mbt` are generated by `scripts/gen_compliance.py` from
  upstream's `tests/compliance/*.json` and `tests/legacy/*.json` (the raw
  fixture text is embedded and parsed with `loads`).  All 917 cases pass,
  including the benchmark cases (`bench: parse` cases are compiled only).
  Besides upstream's "raises a `ValueError`" check, error cases also check
  the exception class for the error category.
* `differential_test.mbt` is generated by `scripts/gen_differential.py`,
  which runs a few hundred extra expressions through upstream jmespath.py
  and records the exact outcome (`json.dumps` of the result, or the
  exception class and message); the port must match byte for byte.
* `lexer_test.mbt`, `parser_test.mbt`, `search_test.mbt`,
  `functions_test.mbt` and `custom_functions_test.mbt` port the upstream
  unit tests.  Skipped: `test_can_max_datetimes` (Python `datetime`
  values), `test_can_handle_long_ints` (Python 2 `long`),
  `test_can_handle_decimals_as_numeric_type` (`decimal.Decimal`; a large
  integer test replaces it) and `test_thread_safety_of_cache` (no threads).
  `dict_cls=OrderedDict` tests run without the option, since `Map` is
  ordered.

## Differences from jmespath.py

* **int vs float.** Core `Json` has no int/float distinction.  This port
  treats a number as a Python float when its `repr` field looks like a float
  literal (`1.0`, `1e3`, `Infinity`, `NaN`) or its value is not integral,
  and as an int otherwise.  `loads`, literals in expressions and the
  builtins (`avg`, `to_number`, `sum`, `abs`, `ceil`, `floor`) maintain the
  marker, so `to_string`, `type`-error messages, etc. match Python.  Data
  parsed with `@json.parse` (or built with `Json::number`) carries no
  marker, so an integral float such as `1.0` there behaves as the int `1`
  (only observable in `to_string` and error messages).  Ints beyond 2^53
  are stored as doubles; their exact digits are kept for display when they
  come from `loads`/`to_number`, but arithmetic on them is approximate.
* **Expression references** (`&expr`) can only be used directly as function
  arguments.  Upstream evaluates `&expr` anywhere to an `_Expression` object
  (e.g. `[&a]` or `not_null(&a)` return one); here such uses raise
  `TypeError`, because a JSON value cannot hold an expression.
  `to_string(&a)` returns `"<jmespath.visitor._Expression object>"` without
  the memory address.
* **Number tokens** in expressions (indices, slices) saturate at the `Int`
  range instead of being arbitrary precision; out-of-range indices behave
  the same.
* **Builtin Python exceptions** leaking from upstream's interpreter are
  modelled as `ValueError` (slice step 0, `ceil(NaN)`, `dict.update`
  length errors), `TypeError` (ordering a number against a string,
  `'in <string>'`, `dict.update` errors) and `OverflowError`
  (`ceil(Infinity)`) constructors with the same messages.  `merge` follows
  `dict.update` for its unchecked arguments, except that pairs with
  non-string keys (which JSON objects cannot hold) raise `TypeError`.
* **Options** has no `dict_cls`: `Map` always preserves insertion order,
  which is what `dict_cls=OrderedDict` gives upstream.
* **Custom functions** are registered with `Functions::register_function`
  instead of subclass methods; implementations receive the argument array
  (no `self`) and must raise `JMESPathError`.  Unknown type names in a
  signature match nothing (upstream raises `KeyError` at call time).
* **Parser cache**: a global insertion-ordered map evicting its oldest entry
  when it reaches `parser_max_size` (512); `Parser(lookahead=2)` has no
  arguments.  The lexer returns an array instead of a generator and emits
  no `PendingDeprecationWarning` for JEP-12 style literals.
* **Graphviz**: `render_dot_file` renders `slice` nodes without children
  (upstream crashes on them).
* **Python details approximated**: `repr()` of strings (printability of
  non-ASCII characters), and `to_number`/`int()`/`float()` accept ASCII
  digits only (Python also accepts other Unicode decimal digits).
  `sum` emulates CPython >= 3.12 (Neumaier-compensated float summation).
