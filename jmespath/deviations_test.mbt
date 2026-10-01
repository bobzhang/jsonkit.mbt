// Behaviour that intentionally differs from jmespath.py (see README).

///|
fn outcome(expression : String, data : Json) -> String {
  try @jmespath.search(expression, data) catch {
    e => "error: \{e}"
  } noraise {
    v => @jmespath.dumps(v)
  }
}

///|
test "deviation: expression references outside function arguments" {
  inspect(
    outcome("&a", {}),
    content="error: expression references can only be used as function arguments",
  )
  inspect(
    outcome("[&a]", {}),
    content="error: expression references can only be used as function arguments",
  )
  inspect(
    outcome("not_null(&a)", {}),
    content="error: expression references can only be used as function arguments (in not_null())",
  )
  inspect(
    outcome("to_array(&a)", {}),
    content="error: expression references can only be used as function arguments (in to_array())",
  )
  // Upstream includes the object's memory address.
  inspect(
    outcome("to_string(&a)", {}),
    content=(
      #|"\"<jmespath.visitor._Expression object>\""
    ),
  )
}

///|
test "deviation: numbers from @json.parse have no float marker" {
  let parsed = @json.parse("[1.0, 1.5]")
  inspect(outcome("to_string(@)", parsed), content="\"[1,1.5]\"")
  // `loads` keeps Python's int/float distinction.
  let loaded = @jmespath.loads("[1.0, 1.5]")
  inspect(outcome("to_string(@)", loaded), content="\"[1.0,1.5]\"")
  // Values built in MoonBit can opt in through the `repr` field.
  inspect(
    outcome("to_string(@)", Json::number(2.0, repr="2.0")),
    content="\"2.0\"",
  )
}

///|
test "deviation: graphviz rendering of slices and literals" {
  inspect(
    @jmespath.compile("foo[1:2]").render_dot_file(),
    content=(
      #|digraph AST {
      #|projection1 [label="projection()"]
      #|  projection1 -> index_expression2
      #|index_expression2 [label="index_expression()"]
      #|  index_expression2 -> field3
      #|field3 [label="field(foo)"]
      #|  index_expression2 -> slice4
      #|slice4 [label="slice()"]
      #|  projection1 -> identity5
      #|identity5 [label="identity()"]
      #|}
    ),
  )
  inspect(
    @jmespath.compile("`[1, \"a\"]` | [0]").render_dot_file(),
    content=(
      #|digraph AST {
      #|pipe1 [label="pipe()"]
      #|  pipe1 -> literal2
      #|literal2 [label="literal([1, 'a'])"]
      #|  pipe1 -> index_expression3
      #|index_expression3 [label="index_expression()"]
      #|  index_expression3 -> identity4
      #|identity4 [label="identity()"]
      #|  index_expression3 -> index5
      #|index5 [label="index(0)"]
      #|}
    ),
  )
}

///|
test "slice node dict form" {
  json_inspect(@jmespath.compile("[::-1]").parsed.to_json(), content={
    "type": "projection",
    "children": [
      {
        "type": "index_expression",
        "children": [
          { "type": "identity", "children": [] },
          { "type": "slice", "children": [null, null, -1] },
        ],
      },
      { "type": "identity", "children": [] },
    ],
  })
}
