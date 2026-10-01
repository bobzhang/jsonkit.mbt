///|
fn py_type_name(j : Json) -> String {
  match j {
    Null => "NoneType"
    True | False => "bool"
    String(_) => "str"
    Array(_) => "list"
    Object(_) => "dict"
    Number(_) => if is_int(j) { "int" } else { "float" }
  }
}

///|
test "differential: repr / pformat / loads against CPython" {
  for case in pycompat_cases {
    let (src, expected_repr, expected_pformat, expected_type) = case
    let j = loads(src)
    assert_eq(py_type_name(j), expected_type)
    assert_eq(repr(j), expected_repr)
    assert_eq(pformat(j, width=72), expected_pformat)
  }
}

///|
test "loads errors" {
  let bad = [
    "", "[1,]", "{\"a\" 1}", "01", "\"\\x\"", "[1] x", "'a'", "\"a\nb\"",
  ]
  for b in bad {
    let ok = try {
      ignore(loads(b))
      true
    } catch {
      _ => false
    }
    assert_false(ok, msg=b)
  }
}

///|
test "dedent / indent" {
  inspect(
    text_dedent("    a\n      b\n\n    c"),
    content=(
      #|a
      #|  b
      #|
      #|c
    ),
  )
  inspect(text_indent("a\n\nb", "  "), content="  a\n\n  b")
}

///|
test "multipleOf" {
  inspect(multiple_of_failed(loads("10"), loads("2")), content="false")
  inspect(multiple_of_failed(loads("7"), loads("2")), content="true")
  inspect(multiple_of_failed(loads("0.0075"), loads("0.0001")), content="false")
  inspect(multiple_of_failed(loads("0.00751"), loads("0.0001")), content="true")
  inspect(
    multiple_of_failed(loads("1e308"), loads("0.123456789")),
    content="true",
  )
  inspect(multiple_of_failed(loads("4.5"), loads("2")), content="true")
  inspect(
    multiple_of_failed(loads("12391239123912391239123912391239"), loads("3")),
    content="false",
  )
}

///|
test "compare numbers" {
  inspect(
    compare_numbers(
      loads("18446744073709551615"),
      loads("18446744073709551616"),
    ),
    content="Some(-1)",
  )
  inspect(compare_numbers(loads("1"), loads("1.0")), content="Some(0)")
  inspect(compare_numbers(loads("NaN"), loads("1.0")), content="None")
  inspect(
    compare_numbers(loads("9007199254740993"), loads("9007199254740992.0")),
    content="Some(1)",
  )
}
