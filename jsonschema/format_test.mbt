// Ports of upstream's `jsonschema/tests/test_format.py`, plus a few checks
// of individual format checkers.

///|
suberror Boom {
  Boom(String)
  Bang(String)
}

///|
fn boom(thing : Json) -> Bool raise {
  if thing == Json::string("bang") {
    raise Bang("Bang!")
  }
  raise Boom("Boom!")
}

///|
test "it can validate no formats" {
  let checker = @jsonschema.FormatChecker::new(formats=[])
  inspect(checker.checkers.length(), content="0")
}

///|
test "it raises a key error for unknown formats" {
  try @jsonschema.FormatChecker::new(formats=["o noes"]) catch {
    @jsonschema.UnknownFormat(f) => inspect(f, content="o noes")
  } noraise {
    _ => fail("expected UnknownFormat")
  }
}

///|
test "it can register checkers" {
  let checker = @jsonschema.FormatChecker::new()
  let before = checker.checkers.keys().collect()
  checker.checks("boom", boom)
  let after = checker.checkers.keys().collect()
  assert_eq(after, before + ["boom"])
  // other checkers are unaffected
  assert_false(@jsonschema.FormatChecker::new().checkers.contains("boom"))
}

///|
test "it catches registered errors" {
  let checker = @jsonschema.FormatChecker::new()
  checker.checks("boom", boom, raises=e => e is Boom(_))
  try checker.check(12, "boom") catch {
    @jsonschema.FormatError(message~, cause~) as e => {
      inspect(message, content="12 is not a 'boom'")
      inspect(e, content="12 is not a 'boom'")
      assert_true(cause is Some(Boom("Boom!")))
    }
    _ => fail("expected FormatError")
  } noraise {
    _ => fail("expected FormatError")
  }
  // unregistered errors are not caught
  try checker.check("bang", "boom") catch {
    Bang(_) => ()
    _ => fail("expected Bang")
  } noraise {
    _ => fail("expected Bang")
  }
}

///|
test "format error causes become validation error causes" {
  let checker = @jsonschema.FormatChecker::new()
  checker.checks("boom", boom, raises=e => e is Boom(_))
  let validator = @jsonschema.draft4_validator.new(
    { "format": "boom" },
    format_checker=checker,
  )
  try validator.validate("BOOM") catch {
    @jsonschema.ValidationError(e) =>
      assert_true(e.cause is Some(Boom("Boom!")))
    _ => fail("expected ValidationError")
  } noraise {
    _ => fail("expected ValidationError")
  }
}

///|
test "format checkers come with defaults" {
  let checker = @jsonschema.FormatChecker::new()
  try checker.check("not-an-ipv4", "ipv4") catch {
    @jsonschema.FormatError(_) => ()
    _ => fail("expected FormatError")
  } noraise {
    _ => fail("expected FormatError")
  }
}

///|
test "repr" {
  let checker = @jsonschema.FormatChecker::new(formats=[])
  checker.checks("foo", _ => true)
  checker.checks("bar", _ => true)
  checker.checks("baz", _ => true)
  inspect(checker, content="<FormatChecker checkers=['bar', 'baz', 'foo']>")
}

///|
test "draft-specific checkers" {
  let names = (c : @jsonschema.FormatChecker) => {
    let keys = c.checkers.keys().collect()
    keys.sort_by(lexicographic)
    keys.join(" ")
  }
  inspect(
    names(@jsonschema.draft3_format_checker),
    content="color date date-time email host-name idn-email ip-address ipv6 regex time uri",
  )
  inspect(
    names(@jsonschema.draft4_format_checker),
    content="date-time email hostname idn-email ipv4 ipv6 regex uri",
  )
  inspect(
    names(@jsonschema.draft7_format_checker),
    content="date date-time email hostname idn-email idn-hostname ipv4 ipv6 iri iri-reference json-pointer regex relative-json-pointer time uri uri-reference uri-template",
  )
  inspect(
    names(@jsonschema.draft202012_format_checker),
    content="date date-time duration email hostname idn-email idn-hostname ipv4 ipv6 iri iri-reference json-pointer regex relative-json-pointer time uri uri-reference uri-template uuid",
  )
  // the class-level registry: draft 3's `time` was registered last
  let checker = @jsonschema.FormatChecker::new()
  assert_true(checker.conforms("12:00:00", "time"))
  assert_false(checker.conforms("12:00:00Z", "time"))
  assert_true(@jsonschema.draft7_format_checker.conforms("12:00:00Z", "time"))
}

///|
test "individual formats" {
  let c = @jsonschema.draft202012_format_checker
  let check = (instance : Json, format : String) => c.conforms(instance, format)
  // email is only an '@' check upstream
  assert_true(check("a@b", "email"))
  assert_false(check("ab", "email"))
  assert_true(check(12, "email"))
  // ipaddress rules
  assert_false(check("087.10.0.1", "ipv4"))
  assert_true(check("::ffff:1.2.3.4", "ipv6"))
  assert_false(check("fe80::1%eth0", "ipv6"))
  // Python's `$` accepts a trailing newline in rfc3987 / rfc3339 patterns
  assert_true(check("http://example.com\n", "uri"))
  assert_true(check("1963-06-19T08:30:06.283185Z\n", "date-time"))
  assert_false(check("1963-06-19\n", "date"))
  assert_true(check("P1D", "duration"))
  assert_false(check("PT1D", "duration"))
  assert_true(check("2EB2D0AF-1E84-46A8-8A1D-C1A6E2A2E8C2", "uuid"))
  assert_true(check("xn--ihqwcrb4cv8a8dqg056pqjye", "idn-hostname"))
  assert_true(check("{+var}/{x,y}", "uri-template"))
  assert_false(check("{", "uri-template"))
  assert_true(check("0/foo", "relative-json-pointer"))
  assert_false(check("/foo~2", "json-pointer"))
  assert_true(check("([abc])+\\s+$", "regex"))
  assert_false(check("^(abc]", "regex"))
  let d3 = @jsonschema.draft3_format_checker
  assert_true(d3.conforms("blac\u{212A}", "color"))
  assert_true(d3.conforms("#fff", "color"))
  assert_false(d3.conforms("#ffff", "color"))
  assert_true(d3.conforms("1:2:3", "time"))
  assert_false(d3.conforms("12:00:60", "time"))
}

///|
/// Lexicographic order of strings (MoonBit's `String` order compares
/// lengths first).
fn lexicographic(a : String, b : String) -> Int {
  for i in 0..<@cmp.minimum(a.length(), b.length()) {
    let c = a.code_unit_at(i).compare(b.code_unit_at(i))
    if c != 0 {
      return c
    }
  }
  a.length().compare(b.length())
}
