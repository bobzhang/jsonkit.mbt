// Port of upstream tests/test_lexer.py.

///|
fn tokenize(
  expression : String,
) -> Array[@jmespath.Token] raise @jmespath.JMESPathError {
  @jmespath.Lexer::new().tokenize(expression)
}

///|
/// The expected tokens only need to specify the type and value; every
/// tokenization must end in eof, which is checked and stripped.
fn assert_tokens(
  actual : Array[@jmespath.Token],
  expected : Array[(String, @jmespath.TokenValue)],
) -> Unit raise {
  let stripped = actual.map(t => (t.type_, t.value))
  assert_eq(stripped.last().map(t => t.0), Some("eof"))
  stripped.pop() |> ignore
  assert_eq(stripped, expected)
}

///|
test "lexer: empty string" {
  try tokenize("") catch {
    EmptyExpressionError => ()
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("expected EmptyExpressionError")
  }
}

///|
test "lexer: field" {
  assert_tokens(tokenize("foo"), [("unquoted_identifier", Str("foo"))])
}

///|
test "lexer: number" {
  assert_tokens(tokenize("24"), [("number", Int(24))])
}

///|
test "lexer: negative number" {
  assert_tokens(tokenize("-24"), [("number", Int(-24))])
}

///|
test "lexer: quoted identifier" {
  assert_tokens(tokenize("\"foobar\""), [("quoted_identifier", Str("foobar"))])
}

///|
test "lexer: json escaped value" {
  assert_tokens(tokenize("\"\u{2713}\""), [("quoted_identifier", Str("\u{2713}"))])
  assert_tokens(tokenize("\"\\u2713\""), [("quoted_identifier", Str("\u{2713}"))])
}

///|
test "lexer: number expressions" {
  assert_tokens(tokenize("foo.bar.baz"), [
    ("unquoted_identifier", Str("foo")),
    ("dot", Str(".")),
    ("unquoted_identifier", Str("bar")),
    ("dot", Str(".")),
    ("unquoted_identifier", Str("baz")),
  ])
}

///|
test "lexer: space separated" {
  assert_tokens(tokenize("foo.bar[*].baz | a || b"), [
    ("unquoted_identifier", Str("foo")),
    ("dot", Str(".")),
    ("unquoted_identifier", Str("bar")),
    ("lbracket", Str("[")),
    ("star", Str("*")),
    ("rbracket", Str("]")),
    ("dot", Str(".")),
    ("unquoted_identifier", Str("baz")),
    ("pipe", Str("|")),
    ("unquoted_identifier", Str("a")),
    ("or", Str("||")),
    ("unquoted_identifier", Str("b")),
  ])
}

///|
test "lexer: literal" {
  assert_tokens(tokenize("`[0, 1]`"), [("literal", Literal([0, 1]))])
}

///|
test "lexer: literal string" {
  assert_tokens(tokenize("`foobar`"), [("literal", Literal("foobar"))])
}

///|
test "lexer: literal number" {
  assert_tokens(tokenize("`2`"), [("literal", Literal(2))])
}

///|
test "lexer: literal with invalid json" {
  try tokenize("`foo\"bar`") catch {
    LexerError(..) => ()
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("expected LexerError")
  }
}

///|
test "lexer: literal with empty string" {
  assert_tokens(tokenize("``"), [("literal", Literal(""))])
}

///|
test "lexer: position information" {
  assert_eq(tokenize("foo"), [
    { type_: "unquoted_identifier", value: Str("foo"), start: 0, end: 3 },
    { type_: "eof", value: Str(""), start: 3, end: 3 },
  ])
}

///|
test "lexer: position multiple tokens" {
  assert_eq(tokenize("foo.bar"), [
    { type_: "unquoted_identifier", value: Str("foo"), start: 0, end: 3 },
    { type_: "dot", value: Str("."), start: 3, end: 4 },
    { type_: "unquoted_identifier", value: Str("bar"), start: 4, end: 7 },
    { type_: "eof", value: Str(""), start: 7, end: 7 },
  ])
}

///|
test "lexer: adds quotes when invalid json" {
  assert_eq(tokenize("`{{}`"), [
    { type_: "literal", value: Literal("{{}"), start: 0, end: 4 },
    { type_: "eof", value: Str(""), start: 5, end: 5 },
  ])
}

///|
test "lexer: unknown character" {
  try tokenize("foo[0^]") catch {
    LexerError(lexer_position~, lexer_value~, message~, ..) => {
      assert_eq(lexer_position, 5)
      assert_eq(lexer_value, "^")
      assert_eq(message, "Unknown token ^")
    }
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("expected LexerError")
  }
}

///|
test "lexer: bad first character" {
  try tokenize("^foo[0]") catch {
    LexerError(..) => ()
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("expected LexerError")
  }
}

///|
test "lexer: unknown character with identifier" {
  try tokenize("foo-bar") catch {
    LexerError(message~, ..) => assert_true(message.contains("Unknown token"))
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("expected LexerError")
  }
}

///|
test "lexer: positions count code points" {
  // Python indexes strings by code point; a supplementary character is one
  // position, not two UTF-16 units.
  let tokens = tokenize("'😀'.a")
  assert_eq(tokens.map(t => (t.type_, t.start, t.end)), [
    ("literal", 0, 3),
    ("dot", 3, 4),
    ("unquoted_identifier", 4, 5),
    ("eof", 5, 5),
  ])
  try tokenize("'😀' ^") catch {
    LexerError(lexer_position~, ..) => assert_eq(lexer_position, 4)
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("expected LexerError")
  }
}

///|
test "lexer: operators and their quirky end positions" {
  assert_eq(tokenize("a<=b").map(t => (t.type_, t.start, t.end)), [
    ("unquoted_identifier", 0, 1),
    ("lte", 1, 2),
    ("unquoted_identifier", 3, 4),
    ("eof", 4, 4),
  ])
  assert_tokens(tokenize("!a != b == c && &d [? []"), [
    ("not", Str("!")),
    ("unquoted_identifier", Str("a")),
    ("ne", Str("!=")),
    ("unquoted_identifier", Str("b")),
    ("eq", Str("==")),
    ("unquoted_identifier", Str("c")),
    ("and", Str("&&")),
    ("expref", Str("&")),
    ("unquoted_identifier", Str("d")),
    ("filter", Str("[?")),
    ("flatten", Str("[]")),
  ])
}

///|
test "lexer: error messages" {
  let err = (expression : String) => {
    try tokenize(expression) catch {
      e => e.to_string()
    } noraise {
      _ => "no error"
    }
  }
  inspect(err("a = b"), content="Bad jmespath expression: Unknown token '=':\nNone\n  ^")
  inspect(err("a ="), content="Bad jmespath expression: Unknown token '=':\nNone\n  ^")
  inspect(err("-"), content="Bad jmespath expression: Unknown token '-':\nNone\n^")
  inspect(
    err("\"abc"),
    content="Bad jmespath expression: Unclosed \" delimiter:\nNone\n^",
  )
}
