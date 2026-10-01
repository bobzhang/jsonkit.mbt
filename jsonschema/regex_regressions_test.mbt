// Regressions from review: `pattern` must behave like Python's `re.search`.

///|
test "pattern: case-insensitive negated class" {
  let v = @jsonschema.draft202012_validator.new({ "pattern": "(?i)^[^a]+$" })
  assert_false(v.is_valid("a"))
  assert_false(v.is_valid("A"))
  assert_true(v.is_valid("b"))
}

///|
test "pattern: scoped case-sensitivity" {
  let v = @jsonschema.draft202012_validator.new({ "pattern": "(?i)(?-i:a)" })
  assert_false(v.is_valid("A"))
  assert_true(v.is_valid("a"))
}

///|
test "pattern: $ is zero-width before a final newline" {
  let v = @jsonschema.draft202012_validator.new({ "pattern": "a$\n" })
  assert_true(v.is_valid("a\n"))
  let v = @jsonschema.draft202012_validator.new({ "pattern": "^a$" })
  assert_true(v.is_valid("a\n"))
  assert_false(v.is_valid("a\nb"))
  // word boundaries are Unicode and do not trip over astral characters
  let v = @jsonschema.draft202012_validator.new({ "pattern": "\\bfoo" })
  assert_true(v.is_valid("\u{1F600}foo"))
  assert_false(v.is_valid("éfoo"))
  // lookaround works
  let v = @jsonschema.draft202012_validator.new({
    "pattern": "^(?!x)\\w+(?<=z)$",
  })
  assert_true(v.is_valid("abz"))
  assert_false(v.is_valid("xbz"))
}
