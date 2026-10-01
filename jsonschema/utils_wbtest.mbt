// Ports of upstream's `jsonschema/tests/test_utils.py` (and a few checks of
// the other `_utils` helpers).

///|
test "equal" {
  let nan = @double.not_a_number
  assert_true(equal(null, null))
  assert_true(equal(Json::number(nan), Json::number(nan)))
}

///|
test "dict equal" {
  let nan = Json::number(@double.not_a_number)
  assert_true(equal({ "a": "b", "c": "d" }, { "c": "d", "a": "b" }))
  assert_true(equal({ "a": nan, "c": "d" }, { "c": "d", "a": nan }))
  assert_false(equal({ "a": "b", "c": "d" }, { "c": "d", "x": "b" }))
  assert_false(equal({ "a": "b", "c": "d" }, { "c": "d", "a": "b", "x": "x" }))
  assert_false(equal({ "a": "b", "c": "d" }, { "c": "d", "a": "x" }))
  assert_true(equal({}, {}))
  assert_false(equal(null, { "a": "b", "c": "d" }))
  let d : Json = { "a": "b", "c": "d" }
  assert_true(equal(d, d))
  assert_true(
    equal({ "a": { "a": "b", "c": "d" }, "c": "d" }, {
      "c": "d",
      "a": { "a": "b", "c": "d" },
    }),
  )
  assert_false(
    equal({ "a": { "a": "b", "c": "d" }, "c": "d" }, {
      "c": "d",
      "a": { "a": "b", "c": "x" },
    }),
  )
  assert_true(
    equal({ "a": ["a", "b", "c", "d"], "c": "d" }, {
      "c": "d",
      "a": ["a", "b", "c", "d"],
    }),
  )
  assert_false(
    equal({ "a": ["a", "b", "c", "d"], "c": "d" }, {
      "c": "d",
      "a": ["b", "c", "d", "a"],
    }),
  )
}

///|
test "list equal" {
  let nan = Json::number(@double.not_a_number)
  assert_true(equal(["a", "b", "c"], ["a", "b", "c"]))
  assert_true(equal(["a", nan, "c"], ["a", nan, "c"]))
  assert_false(equal(["a", "b", "c"], ["b", "b", "a"]))
  assert_false(equal(["a", "b", "c"], ["a", "b"]))
  assert_false(equal(["a", "b"], ["a", "b", "c"]))
  assert_false(equal(["a", "b", null], ["a", "b", "c"]))
  assert_false(equal(["a", "b", null], [null, "b", "c"]))
  assert_true(equal(["a", null, "c"], ["a", null, "c"]))
  assert_true(equal([], []))
  assert_false(equal(null, []))
  assert_true(equal(["a", ["b", "c"], "d"], ["a", ["b", "c"], "d"]))
  assert_false(equal(["a", ["b", "c"], "d"], ["a", [], "c"]))
}

///|
test "Python numeric equality" {
  assert_true(equal(1, @pycompat.loads("1.0")))
  assert_false(equal(true, 1))
  assert_false(equal(false, 0))
  assert_true(equal([1, true], [@pycompat.loads("1.0"), true]))
}

///|
test "uniq" {
  let nan = Json::number(@double.not_a_number)
  let neg_nan = Json::number(
    @double.not_a_number
    .reinterpret_as_uint64()
    .lxor(0x8000000000000000UL)
    .reinterpret_as_double(),
  )
  assert_true(uniq([1, 2, 3]))
  assert_false(uniq([1, 2, 1]))
  // bool and int differ
  assert_true(uniq([true, 1]))
  assert_true(uniq([false, 0]))
  assert_false(uniq([true, true]))
  assert_false(uniq([false, false]))
  // sequences compare structurally
  assert_false(uniq([[1, 2], [1, 2]]))
  assert_true(uniq([[1, 2], [2, 1]]))
  // mappings ignore key order
  assert_false(
    uniq([{ "a": [1, 2], "b": { "c": 3 } }, { "b": { "c": 3 }, "a": [1, 2] }]),
  )
  // NaN falls back to brute force
  assert_false(uniq([nan, nan]))
  assert_true(uniq([nan, neg_nan]))
  assert_false(uniq([[nan], [nan]]))
  assert_true(uniq([[nan], [neg_nan]]))
  assert_false(uniq([{ "x": nan }, { "x": nan }]))
  assert_true(uniq([{ "x": nan }, { "x": neg_nan }]))
  // nested bool and int differ
  assert_true(uniq([[true], [1]]))
  assert_true(uniq([{ "k": true }, { "k": 1 }]))
  // 1 == 1.0
  assert_false(uniq([1, @pycompat.loads("1.0")]))
}

///|
test "format_as_index / extras_msg / ensure_list" {
  inspect(
    format_as_index("bar", [Index(1), Index(2), Key("foo")]),
    content="bar[1][2]['foo']",
  )
  inspect(format_as_index("bar", []), content="bar")
  debug_inspect(extras_msg(["foo"]), content="(\"'foo'\", \"was\")")
  debug_inspect(extras_msg([1, "a"]), content="(\"1, 'a'\", \"were\")")
  debug_inspect(ensure_list("a").length(), content="1")
  debug_inspect(ensure_list(["a", "b"]).length(), content="2")
}

///|
test "find_additional_properties" {
  let instance : Map[String, Json] = { "foo": 1, "bar": 2, "baz": 3, "quux": 4 }
  debug_inspect(
    find_additional_properties(instance, {
      "properties": { "foo": {} },
      "patternProperties": { "^b": {}, "x$": {} },
    }),
    content="[]",
  )
  debug_inspect(
    find_additional_properties(instance, { "properties": { "foo": {} } }),
    content="[\"bar\", \"baz\", \"quux\"]",
  )
}
