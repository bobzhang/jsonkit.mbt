// Port of upstream tests/test_parser.py.

///|
fn parse(
  expression : String,
) -> @jmespath.ParsedResult raise @jmespath.JMESPathError {
  @jmespath.Parser::new().parse(expression)
}

///|
fn assert_parsed_ast(
  expression : String,
  expected : @jmespath.Node,
) -> Unit raise {
  assert_eq(parse(expression).parsed, expected)
}

///|
test "parser: parse empty string raises exception" {
  try parse("") catch {
    EmptyExpressionError => ()
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("expected EmptyExpressionError")
  }
}

///|
test "parser: field" {
  assert_parsed_ast("foo", Field("foo"))
}

///|
test "parser: dot syntax" {
  assert_parsed_ast("foo.bar", Subexpression([Field("foo"), Field("bar")]))
}

///|
test "parser: multiple dots" {
  let parsed = parse("foo.bar.baz")
  json_inspect(
    parsed.search({ "foo": { "bar": { "baz": "correct" } } }),
    content="correct",
  )
}

///|
test "parser: index" {
  let parsed = parse("foo[1]")
  json_inspect(parsed.search({ "foo": ["zero", "one", "two"] }), content="one")
}

///|
test "parser: quoted subexpression" {
  assert_parsed_ast(
    "\"foo\".\"bar\"",
    Subexpression([Field("foo"), Field("bar")]),
  )
}

///|
test "parser: wildcard" {
  let parsed = parse("foo[*]")
  json_inspect(parsed.search({ "foo": ["zero", "one", "two"] }), content=[
    "zero", "one", "two",
  ])
}

///|
test "parser: wildcard with children" {
  let parsed = parse("foo[*].bar")
  json_inspect(parsed.search({ "foo": [{ "bar": "one" }, { "bar": "two" }] }), content=[
    "one", "two",
  ])
}

///|
test "parser: or expression" {
  let parsed = parse("foo || bar")
  json_inspect(parsed.search({ "foo": "foo" }), content="foo")
  json_inspect(parsed.search({ "bar": "bar" }), content="bar")
  json_inspect(parsed.search({ "foo": "foo", "bar": "bar" }), content="foo")
  json_inspect(parsed.search({ "bad": "bad" }), content=null)
}

///|
test "parser: complex or expression" {
  let parsed = parse("foo.foo || foo.bar")
  json_inspect(parsed.search({ "foo": { "foo": "foo" } }), content="foo")
  json_inspect(parsed.search({ "foo": { "bar": "bar" } }), content="bar")
  json_inspect(parsed.search({ "foo": { "baz": "baz" } }), content=null)
}

///|
test "parser: or repr" {
  assert_parsed_ast("foo || bar", OrExpression(Field("foo"), Field("bar")))
}

///|
test "parser: unicode literals escaped" {
  assert_parsed_ast("`\"\\u2713\"`", Literal("\u{2713}"))
}

///|
test "parser: multiselect" {
  let parsed = parse("foo.{bar: bar,baz: baz}")
  json_inspect(
    parsed.search({ "foo": { "bar": "bar", "baz": "baz", "qux": "qux" } }),
    content={ "bar": "bar", "baz": "baz" },
  )
}

///|
test "parser: multiselect subexpressions" {
  let parsed = parse("foo.{\"bar.baz\": bar.baz, qux: qux}")
  json_inspect(
    parsed.search({ "foo": { "bar": { "baz": "CORRECT" }, "qux": "qux" } }),
    content={ "bar.baz": "CORRECT", "qux": "qux" },
  )
}

///|
test "parser: multiselect with all quoted keys" {
  let parsed = parse("foo.{\"bar\": bar.baz, \"qux\": qux}")
  let result = parsed.search({
    "foo": { "bar": { "baz": "CORRECT" }, "qux": "qux" },
  })
  json_inspect(result, content={ "bar": "CORRECT", "qux": "qux" })
}

///|
test "parser: function call with and statement" {
  json_inspect(parse("f(@ && @)").parsed.to_json(), content={
    "type": "function_expression",
    "children": [
      {
        "type": "and_expression",
        "children": [
          { "type": "current", "children": [] },
          { "type": "current", "children": [] },
        ],
      },
    ],
    "value": "f",
  })
}

// TestErrorMessages

///|
fn parse_error_message(expression : String) -> String {
  try parse(expression) catch {
    e => e.to_string()
  } noraise {
    _ => "ParseError not raised for bad expression: \{expression}"
  }
}

///|
test "parser: bad parse" {
  try parse("foo]baz") catch {
    e => assert_true(e.is_parse_error())
  } noraise {
    _ => fail("expected ParseError")
  }
}

///|
test "parser: bad parse error message" {
  assert_eq(
    parse_error_message("foo]baz"),
    "Unexpected token: ]: Parse error at column 3, " +
    "token \"]\" (RBRACKET), for expression:\n" +
    "\"foo]baz\"\n" +
    "    ^",
  )
}

///|
test "parser: bad parse error message with multiselect" {
  assert_eq(
    parse_error_message("foo.{bar: baz,bar: bar"),
    "Invalid jmespath expression: Incomplete expression:\n" +
    "\"foo.{bar: baz,bar: bar\"\n" +
    "                       ^",
  )
}

///|
test "parser: incomplete expression with missing paren" {
  assert_eq(
    parse_error_message("length(@,"),
    "Invalid jmespath expression: Incomplete expression:\n" +
    "\"length(@,\"\n" +
    "          ^",
  )
}

///|
test "parser: bad lexer values" {
  try parse("foo.\"bar") catch {
    LexerError(..) as e =>
      assert_eq(
        e.to_string(),
        "Bad jmespath expression: " +
        "Unclosed \" delimiter:\n" +
        "foo.\"bar\n" +
        "    ^",
      )
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("expected LexerError")
  }
}

///|
test "parser: bad unicode string" {
  // Upstream matches the regex 'Bad jmespath expression: Invalid \\uXXXX
  // escape.*\\uAZ12' (the text comes from Python's JSON parser).
  try parse("\"\\uAZ12\"") catch {
    LexerError(..) as e =>
      assert_eq(
        e.to_string(),
        "Bad jmespath expression: Invalid \\uXXXX escape:\n\"\\uAZ12\"\n^",
      )
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("expected LexerError")
  }
}

///|
test "parser: more error messages" {
  inspect(
    parse_error_message("foo.\"bar\"()"),
    content=(
      #|Quoted identifier not allowed for function names.: Parse error at column 0, token "(" (LPAREN), for expression:
      #|"foo."bar"()"
      #| ^
    ),
  )
  inspect(
    parse_error_message("foo.1"),
    content=(
      #|Expecting: ['quoted_identifier', 'unquoted_identifier', 'lbracket', 'lbrace'], got: number: Parse error at column 4, token "1" (NUMBER), for expression:
      #|"foo.1"
      #|     ^
    ),
  )
  inspect(
    parse_error_message("{1: a}"),
    content=(
      #|Expecting: ['quoted_identifier', 'unquoted_identifier'], got: number: Parse error at column 1, token "1" (NUMBER), for expression:
      #|"{1: a}"
      #|  ^
    ),
  )
  inspect(
    parse_error_message("[1].`2`(a)"),
    content=(
      #|Expecting: ['quoted_identifier', 'unquoted_identifier', 'lbracket', 'lbrace'], got: literal: Parse error at column 4, token "2" (LITERAL), for expression:
      #|"[1].`2`(a)"
      #|     ^
    ),
  )
  inspect(
    parse_error_message("@(a)"),
    content=(
      #|Invalid function name '@': Parse error at column 0, token "@" (CURRENT), for expression:
      #|"@(a)"
      #| ^
    ),
  )
  inspect(
    parse_error_message("a[:::]"),
    content=(
      #|syntax error: Parse error at column 4, token ":" (COLON), for expression:
      #|"a[:::]"
      #|     ^
    ),
  )
  inspect(
    parse_error_message("a{"),
    content=(
      #|invalid token: Parse error at column 1, token "{" (LBRACE), for expression:
      #|"a{"
      #|  ^
    ),
  )
  inspect(
    parse_error_message("😀.a]"),
    content=(
      #|Bad jmespath expression: Unknown token 😀:
      #|😀.a]
      #|^
    ),
  )
  inspect(
    parse_error_message("'😀'.a]"),
    content=(
      #|Unexpected token: ]: Parse error at column 5, token "]" (RBRACKET), for expression:
      #|"'😀'.a]"
      #|      ^
    ),
  )
  inspect(
    parse_error_message("'😀' | "),
    content=(
      #|Invalid jmespath expression: Incomplete expression:
      #|"'😀' | "
      #|       ^
    ),
  )
}

// TestParserWildcards

///|
let wildcard_data : Json = {
  "foo": [
    { "bar": [{ "baz": "one" }, { "baz": "two" }] },
    { "bar": [{ "baz": "three" }, { "baz": "four" }, { "baz": "five" }] },
  ],
}

///|
test "parser: multiple index wildcards" {
  json_inspect(parse("foo[*].bar[*].baz").search(wildcard_data), content=[
    ["one", "two"],
    ["three", "four", "five"],
  ])
}

///|
test "parser: wildcard mix with indices" {
  json_inspect(parse("foo[*].bar[0].baz").search(wildcard_data), content=[
    "one", "three",
  ])
}

///|
test "parser: wildcard mix last" {
  json_inspect(parse("foo[0].bar[*].baz").search(wildcard_data), content=[
    "one", "two",
  ])
}

///|
test "parser: indices out of bounds" {
  json_inspect(parse("foo[*].bar[2].baz").search(wildcard_data), content=[
    "five",
  ])
}

///|
test "parser: root indices" {
  json_inspect(parse("[0]").search(["one", "two"]), content="one")
}

///|
test "parser: root wildcard" {
  let data : Json = {
    "top1": { "foo": "bar" },
    "top2": { "foo": "baz" },
    "top3": { "notfoo": "notfoo" },
  }
  // Map keeps insertion order, so no need to sort like upstream.
  json_inspect(parse("*.foo").search(data), content=["bar", "baz"])
  json_inspect(parse("*.notfoo").search(data), content=["notfoo"])
}

///|
test "parser: only wildcard" {
  let data : Json = { "foo": "a", "bar": "b", "baz": "c" }
  json_inspect(parse("*").search(data), content=["a", "b", "c"])
}

///|
test "parser: escape sequences" {
  json_inspect(
    parse("\"foo\\tbar\"").search({ "foo\tbar": "baz" }),
    content="baz",
  )
  json_inspect(
    parse("\"foo\\nbar\"").search({ "foo\nbar": "baz" }),
    content="baz",
  )
  json_inspect(
    parse("\"foo\\bbar\"").search({ "foo\u{8}bar": "baz" }),
    content="baz",
  )
  json_inspect(
    parse("\"foo\\fbar\"").search({ "foo\u{c}bar": "baz" }),
    content="baz",
  )
  json_inspect(
    parse("\"foo\\rbar\"").search({ "foo\rbar": "baz" }),
    content="baz",
  )
}

///|
test "parser: consecutive escape sequences" {
  json_inspect(
    parse("\"foo\\\\nbar\"").search({ "foo\\nbar": "baz" }),
    content="baz",
  )
  json_inspect(
    parse("\"foo\\n\\t\\rbar\"").search({ "foo\n\t\rbar": "baz" }),
    content="baz",
  )
}

///|
test "parser: escape sequence at end of string not allowed" {
  try parse("foobar\\") catch {
    e => assert_true(e.is_value_error())
  } noraise {
    _ => fail("expected an error")
  }
}

///|
test "parser: wildcard with multiselect" {
  let parsed = parse("foo.*.{a: a, b: b}")
  let data : Json = {
    "foo": {
      "one": {
        "a": { "c": "CORRECT", "d": "other" },
        "b": { "c": "ALSOCORRECT", "d": "other" },
      },
      "two": {
        "a": { "c": "CORRECT", "d": "other" },
        "c": { "c": "WRONG", "d": "other" },
      },
    },
  }
  guard parsed.search(data) is Array(matched) else { fail("expected a list") }
  assert_eq(matched.length(), 2)
  for item in matched {
    guard item is Object(item) else { fail("expected an object") }
    assert_true(item.contains("a"))
    assert_true(item.contains("b"))
  }
}

// TestMergedLists

///|
let merged_lists_data : Json = {
  "foo": [
    [["one", "two"], ["three", "four"]],
    [["five", "six"], ["seven", "eight"]],
    [["nine"], ["ten"]],
  ],
}

///|
test "parser: merge with indices" {
  json_inspect(parse("foo[][0]").search(merged_lists_data), content=[
    "one", "three", "five", "seven", "nine", "ten",
  ])
}

///|
test "parser: trailing merged operator" {
  json_inspect(parse("foo[]").search(merged_lists_data), content=[
    ["one", "two"],
    ["three", "four"],
    ["five", "six"],
    ["seven", "eight"],
    ["nine"],
    ["ten"],
  ])
}

// TestParserCaching (test_thread_safety_of_cache is skipped: no threads).

///|
test "parser: compile lots of expressions" {
  let p = @jmespath.Parser::new()
  let compiled = []
  let compiled2 = []
  for i in 0..<=@jmespath.parser_max_size {
    compiled.push(p.parse("foo\{i}"))
  }
  assert_true(@jmespath.Parser::cache_size() <= @jmespath.parser_max_size)
  // Rerun the test and half of these entries should be from the cache but
  // they should still be equal to compiled.
  for i in 0..<=@jmespath.parser_max_size {
    compiled2.push(p.parse("foo\{i}"))
  }
  assert_eq(compiled.length(), compiled2.length())
  assert_eq(compiled.map(e => e.parsed), compiled2.map(e => e.parsed))
}

///|
test "parser: cache purge" {
  let p = @jmespath.Parser::new()
  let first = p.parse("foo")
  let cached = p.parse("foo")
  @jmespath.Parser::purge()
  let second = p.parse("foo")
  assert_eq(first.parsed, second.parsed)
  assert_eq(first.parsed, cached.parsed)
}

// TestParserAddsExpressionAttribute

///|
test "parser: expression available from parser" {
  assert_eq(parse("foo.bar").expression, "foo.bar")
}

// TestParsedResultAddsOptions

///|
test "parser: can have ordered dict" {
  // Upstream passes Options(dict_cls=OrderedDict); `Map` is always ordered.
  let result = parse("{a: a, b: b, c: c}").search({
    "c": "c",
    "b": "b",
    "a": "a",
  })
  guard result is Object(map) else { fail("expected an object") }
  assert_eq(map.keys().collect(), ["a", "b", "c"])
}

// TestRenderGraphvizFile

///|
test "parser: dot file rendered" {
  assert_eq(
    parse("foo").render_dot_file(),
    "digraph AST {\nfield1 [label=\"field(foo)\"]\n}",
  )
}

///|
test "parser: dot file subexpr" {
  assert_eq(
    parse("foo.bar").render_dot_file(),
    "digraph AST {\n" +
    "subexpression1 [label=\"subexpression()\"]\n" +
    "  subexpression1 -> field2\n" +
    "field2 [label=\"field(foo)\"]\n" +
    "  subexpression1 -> field3\n" +
    "field3 [label=\"field(bar)\"]\n}",
  )
}

// Extra AST shape checks (mirroring upstream's parser behaviour).

///|
test "parser: ast shapes" {
  assert_parsed_ast(
    "foo[0][1]",
    IndexExpression([Field("foo"), Index(0), Index(1)]),
  )
  assert_parsed_ast(
    "foo[1:2]",
    Projection(
      IndexExpression([Field("foo"), Slice(Some(1), Some(2), None)]),
      Identity,
    ),
  )
  assert_parsed_ast(
    "foo[?a > `1`].b",
    FilterProjection(
      Field("foo"),
      Field("b"),
      Comparator("gt", Field("a"), Literal(1)),
    ),
  )
  assert_parsed_ast(
    "*.a | [0]",
    Pipe(
      ValueProjection(Identity, Field("a")),
      IndexExpression([Identity, Index(0)]),
    ),
  )
  assert_parsed_ast(
    "sort_by(@, &a)",
    FunctionExpression("sort_by", [Current, Expref(Field("a"))]),
  )
  assert_parsed_ast(
    "!a.b",
    Subexpression([NotExpression(Field("a")), Field("b")]),
  )
  assert_parsed_ast("a[].b", Projection(Flatten(Field("a")), Field("b")))
  // Upstream quirk: a missing comma between hash entries is accepted.
  assert_parsed_ast(
    "{a: b c: d}",
    MultiSelectDict([KeyValPair("a", Field("b")), KeyValPair("c", Field("d"))]),
  )
  inspect(
    parse("foo[?a == `1`]"),
    content="{'type': 'filter_projection', 'children': [{'type': 'field', 'children': [], 'value': 'foo'}, {'type': 'identity', 'children': []}, {'type': 'comparator', 'children': [{'type': 'field', 'children': [], 'value': 'a'}, {'type': 'literal', 'value': 1, 'children': []}], 'value': 'eq'}]}",
  )
}
