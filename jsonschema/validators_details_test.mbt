// Ports of `TestValidationErrorDetails` from upstream's
// `jsonschema/tests/test_validators.py`.

///|
fn path_repr(path : Array[@jsonschema.PathItem]) -> String {
  "[" + path.map(p => p.repr()).join(", ") + "]"
}

///|
fn opt_repr(j : Json?) -> String {
  match j {
    Some(v) => @jsonschema.py_repr(v)
    None => "<unset>"
  }
}

///|
/// Everything upstream's tests look at, one per line.
fn describe(e : @jsonschema.ValidationError) -> String {
  [
    "message: \{e.message}",
    "validator: \{opt_repr(e.validator)}",
    "validator_value: \{opt_repr(e.validator_value)}",
    "instance: \{opt_repr(e.instance)}",
    "schema: \{opt_repr(e.schema)}",
    "path: \{path_repr(e.path)}",
    "schema_path: \{path_repr(e.schema_path)}",
    "absolute_path: \{path_repr(e.absolute_path())}",
    "absolute_schema_path: \{path_repr(e.absolute_schema_path())}",
    "json_path: \{e.json_path()}",
    "context: \{e.context.length()}",
  ].join("\n")
}

///|
/// Upstream's `sorted_errors`: by `[str(e) for e in path]`, then schema path.
fn sorted_errors(
  errors : Array[@jsonschema.ValidationError],
) -> Array[@jsonschema.ValidationError] {
  let key = (e : @jsonschema.ValidationError) => {
    (e.path.map(p => p.to_string()), e.schema_path.map(p => p.to_string()))
  }
  let lex = (a : Array[String], b : Array[String]) => {
    for i in 0..<@cmp.minimum(a.length(), b.length()) {
      let c = a[i].compare(b[i])
      if c != 0 {
        return c
      }
    }
    a.length().compare(b.length())
  }
  let out = errors.copy()
  out.sort_by((x, y) => {
    let (p1, s1) = key(x)
    let (p2, s2) = key(y)
    let c = lex(p1, p2)
    if c != 0 {
      c
    } else {
      lex(s1, s2)
    }
  })
  out
}

///|
test "anyOf" {
  let schema : Json = { "anyOf": [{ "minimum": 20 }, { "type": "string" }] }
  let validator = @jsonschema.draft4_validator.new(schema)
  let errors = validator.iter_errors(5).to_array()
  inspect(errors.length(), content="1")
  let e = errors[0]
  assert_true(e.parent is None)
  inspect(
    describe(e),
    content=(
      #|message: 5 is not valid under any of the given schemas
      #|validator: 'anyOf'
      #|validator_value: [{'minimum': 20}, {'type': 'string'}]
      #|instance: 5
      #|schema: {'anyOf': [{'minimum': 20}, {'type': 'string'}]}
      #|path: []
      #|schema_path: ['anyOf']
      #|absolute_path: []
      #|absolute_schema_path: ['anyOf']
      #|json_path: $
      #|context: 2
    ),
  )
  let sorted = sorted_errors(e.context)
  let (e1, e2) = (sorted[0], sorted[1])
  assert_true(e1.parent is Some(p) && physical_equal(p, e))
  assert_true(e2.parent is Some(p) && physical_equal(p, e))
  inspect(
    describe(e1),
    content=(
      #|message: 5 is less than the minimum of 20
      #|validator: 'minimum'
      #|validator_value: 20
      #|instance: 5
      #|schema: {'minimum': 20}
      #|path: []
      #|schema_path: [0, 'minimum']
      #|absolute_path: []
      #|absolute_schema_path: ['anyOf', 0, 'minimum']
      #|json_path: $
      #|context: 0
    ),
  )
  inspect(
    describe(e2),
    content=(
      #|message: 5 is not of type 'string'
      #|validator: 'type'
      #|validator_value: 'string'
      #|instance: 5
      #|schema: {'type': 'string'}
      #|path: []
      #|schema_path: [1, 'type']
      #|absolute_path: []
      #|absolute_schema_path: ['anyOf', 1, 'type']
      #|json_path: $
      #|context: 0
    ),
  )
}

///|
test "type (draft 3)" {
  let schema : Json = {
    "type": [
      { "type": "integer" },
      { "type": "object", "properties": { "foo": { "enum": [2] } } },
    ],
  }
  let validator = @jsonschema.draft3_validator.new(schema)
  let errors = validator.iter_errors({ "foo": 1 }).to_array()
  inspect(errors.length(), content="1")
  let e = errors[0]
  inspect(
    describe(e),
    content=(
      #|message: {'foo': 1} is not of type {'type': 'integer'}, {'type': 'object', 'properties': {'foo': {'enum': [2]}}}
      #|validator: 'type'
      #|validator_value: [{'type': 'integer'}, {'type': 'object', 'properties': {'foo': {'enum': [2]}}}]
      #|instance: {'foo': 1}
      #|schema: {'type': [{'type': 'integer'}, {'type': 'object', 'properties': {'foo': {'enum': [2]}}}]}
      #|path: []
      #|schema_path: ['type']
      #|absolute_path: []
      #|absolute_schema_path: ['type']
      #|json_path: $
      #|context: 2
    ),
  )
  let sorted = sorted_errors(e.context)
  inspect(
    describe(sorted[0]),
    content=(
      #|message: {'foo': 1} is not of type 'integer'
      #|validator: 'type'
      #|validator_value: 'integer'
      #|instance: {'foo': 1}
      #|schema: {'type': 'integer'}
      #|path: []
      #|schema_path: [0, 'type']
      #|absolute_path: []
      #|absolute_schema_path: ['type', 0, 'type']
      #|json_path: $
      #|context: 0
    ),
  )
  inspect(
    describe(sorted[1]),
    content=(
      #|message: 1 is not one of [2]
      #|validator: 'enum'
      #|validator_value: [2]
      #|instance: 1
      #|schema: {'enum': [2]}
      #|path: ['foo']
      #|schema_path: [1, 'properties', 'foo', 'enum']
      #|absolute_path: ['foo']
      #|absolute_schema_path: ['type', 1, 'properties', 'foo', 'enum']
      #|json_path: $.foo
      #|context: 0
    ),
  )
}

///|
test "single nesting" {
  let instance : Json = { "foo": 2, "bar": [1], "baz": 15, "quux": "spam" }
  let schema : Json = {
    "properties": {
      "foo": { "type": "string" },
      "bar": { "minItems": 2 },
      "baz": { "maximum": 10, "enum": [2, 4, 6, 8] },
    },
  }
  let validator = @jsonschema.draft3_validator.new(schema)
  let errors = sorted_errors(validator.iter_errors(instance).to_array())
  inspect(
    errors
    .map(e => "\{path_repr(e.path)} \{e.json_path()} \{opt_repr(e.validator)}")
    .join("\n"),
    content=(
      #|['bar'] $.bar 'minItems'
      #|['baz'] $.baz 'enum'
      #|['baz'] $.baz 'maximum'
      #|['foo'] $.foo 'type'
    ),
  )
}

///|
test "multiple nesting" {
  let instance : Json = [1, { "foo": 2, "bar": { "baz": [1] } }, "quux"]
  let schema : Json = {
    "type": "string",
    "items": {
      "type": ["string", "object"],
      "properties": {
        "foo": { "enum": [1, 3] },
        "bar": {
          "type": "array",
          "properties": {
            "bar": { "required": true },
            "baz": { "minItems": 2 },
          },
        },
      },
    },
  }
  let validator = @jsonschema.draft3_validator.new(schema)
  let errors = sorted_errors(validator.iter_errors(instance).to_array())
  inspect(
    errors
    .map(e => {
      "\{path_repr(e.path)} \{e.json_path()} \{path_repr(e.schema_path)} \{opt_repr(e.validator)}"
    })
    .join("\n"),
    content=(
      #|[] $ ['type'] 'type'
      #|[0] $[0] ['items', 'type'] 'type'
      #|[1, 'bar'] $[1].bar ['items', 'properties', 'bar', 'type'] 'type'
      #|[1, 'bar', 'bar'] $[1].bar.bar ['items', 'properties', 'bar', 'properties', 'bar', 'required'] 'required'
      #|[1, 'bar', 'baz'] $[1].bar.baz ['items', 'properties', 'bar', 'properties', 'baz', 'minItems'] 'minItems'
      #|[1, 'foo'] $[1].foo ['items', 'properties', 'foo', 'enum'] 'enum'
    ),
  )
}

///|
test "recursive" {
  let schema : Json = {
    "definitions": {
      "node": {
        "anyOf": [
          {
            "type": "object",
            "required": ["name", "children"],
            "properties": {
              "name": { "type": "string" },
              "children": {
                "type": "object",
                "patternProperties": {
                  "^.*$": { "$ref": "#/definitions/node" },
                },
              },
            },
          },
        ],
      },
    },
    "type": "object",
    "required": ["root"],
    "properties": { "root": { "$ref": "#/definitions/node" } },
  }
  let instance : Json = {
    "root": {
      "name": "root",
      "children": {
        "a": { "name": "a", "children": { "ab": { "name": "ab" } } },
      },
    },
  }
  let validator = @jsonschema.draft4_validator.new(schema)
  let errors = validator.iter_errors(instance).to_array()
  inspect(errors.length(), content="1")
  let e = errors[0]
  inspect(path_repr(e.absolute_path()), content="['root']")
  inspect(
    path_repr(e.absolute_schema_path()),
    content="['properties', 'root', 'anyOf']",
  )
  inspect(e.json_path(), content="$.root")
  inspect(e.context.length(), content="1")
  let e1 = e.context[0]
  inspect(path_repr(e1.absolute_path()), content="['root', 'children', 'a']")
  inspect(
    path_repr(e1.absolute_schema_path()),
    content="['properties', 'root', 'anyOf', 0, 'properties', 'children', 'patternProperties', '^.*$', 'anyOf']",
  )
  inspect(e1.json_path(), content="$.root.children.a")
  inspect(e1.context.length(), content="1")
  let e2 = e1.context[0]
  inspect(
    path_repr(e2.absolute_path()),
    content="['root', 'children', 'a', 'children', 'ab']",
  )
  inspect(
    path_repr(e2.absolute_schema_path()),
    content="['properties', 'root', 'anyOf', 0, 'properties', 'children', 'patternProperties', '^.*$', 'anyOf', 0, 'properties', 'children', 'patternProperties', '^.*$', 'anyOf']",
  )
  inspect(e2.json_path(), content="$.root.children.a.children.ab")
}

///|
fn paths_and_validators(errors : Array[@jsonschema.ValidationError]) -> String {
  sorted_errors(errors)
  .map(e => "\{path_repr(e.path)} \{e.json_path()} \{opt_repr(e.validator)}")
  .join("\n")
}

///|
test "additionalProperties / patternProperties / additionalItems paths" {
  let v = @jsonschema.draft3_validator.new({
    "additionalProperties": { "type": "integer", "minimum": 5 },
  })
  inspect(
    paths_and_validators(v.iter_errors({ "bar": "bar", "foo": 2 }).to_array()),
    content=(
      #|['bar'] $.bar 'type'
      #|['foo'] $.foo 'minimum'
    ),
  )
  let v = @jsonschema.draft3_validator.new({
    "patternProperties": {
      "bar": { "type": "string" },
      "foo": { "minimum": 5 },
    },
  })
  inspect(
    paths_and_validators(v.iter_errors({ "bar": 1, "foo": 2 }).to_array()),
    content=(
      #|['bar'] $.bar 'type'
      #|['foo'] $.foo 'minimum'
    ),
  )
  let v = @jsonschema.draft3_validator.new({
    "items": [],
    "additionalItems": { "type": "integer", "minimum": 5 },
  })
  inspect(
    paths_and_validators(v.iter_errors(["foo", 1]).to_array()),
    content=(
      #|[0] $[0] 'type'
      #|[1] $[1] 'minimum'
    ),
  )
  let v = @jsonschema.draft3_validator.new({
    "items": [{}],
    "additionalItems": { "type": "integer", "minimum": 5 },
  })
  inspect(
    paths_and_validators(v.iter_errors(["foo", "bar", 1]).to_array()),
    content=(
      #|[1] $[1] 'type'
      #|[2] $[2] 'minimum'
    ),
  )
}

///|
test "propertyNames / if-then / if-else" {
  let v = @jsonschema.draft7_validator.new({
    "propertyNames": { "not": { "const": "foo" } },
  })
  let errors = v.iter_errors({ "foo": 12 }).to_array()
  inspect(errors.length(), content="1")
  inspect(
    describe(errors[0]),
    content=(
      #|message: 'foo' should not be valid under {'const': 'foo'}
      #|validator: 'not'
      #|validator_value: {'const': 'foo'}
      #|instance: 'foo'
      #|schema: {'not': {'const': 'foo'}}
      #|path: []
      #|schema_path: ['propertyNames', 'not']
      #|absolute_path: []
      #|absolute_schema_path: ['propertyNames', 'not']
      #|json_path: $
      #|context: 0
    ),
  )
  let v = @jsonschema.draft7_validator.new({
    "if": { "const": 12 },
    "then": { "const": 13 },
  })
  let errors = v.iter_errors(12).to_array()
  inspect(errors.length(), content="1")
  inspect(
    "\{opt_repr(errors[0].validator)} \{errors[0].message} \{path_repr(errors[0].schema_path)} \{errors[0].json_path()}",
    content="'const' 13 was expected ['then', 'const'] $",
  )
  let v = @jsonschema.draft7_validator.new({
    "if": { "const": 12 },
    "else": { "const": 13 },
  })
  let errors = v.iter_errors(15).to_array()
  inspect(errors.length(), content="1")
  inspect(
    "\{opt_repr(errors[0].validator)} \{errors[0].message} \{path_repr(errors[0].schema_path)} \{errors[0].json_path()}",
    content="'const' 13 was expected ['else', 'const'] $",
  )
}

///|
test "boolean schema False" {
  let errors = @jsonschema.draft7_validator
    .new(false)
    .iter_errors(12)
    .to_array()
  inspect(errors.length(), content="1")
  inspect(
    describe(errors[0]),
    content=(
      #|message: False schema does not allow 12
      #|validator: None
      #|validator_value: None
      #|instance: 12
      #|schema: False
      #|path: []
      #|schema_path: []
      #|absolute_path: []
      #|absolute_schema_path: []
      #|json_path: $
      #|context: 0
    ),
  )
  let errors = @jsonschema.draft7_validator
    .new({ "properties": { "foo": false } })
    .iter_errors({ "foo": 12 })
    .to_array()
  inspect(errors.length(), content="1")
  inspect(
    describe(errors[0]),
    content=(
      #|message: False schema does not allow 12
      #|validator: None
      #|validator_value: None
      #|instance: 12
      #|schema: False
      #|path: ['foo']
      #|schema_path: ['properties', 'foo']
      #|absolute_path: ['foo']
      #|absolute_schema_path: ['properties', 'foo']
      #|json_path: $.foo
      #|context: 0
    ),
  )
}

///|
test "ref (via a registry; upstream uses a legacy RefResolver)" {
  let schema : Json = { "additionalProperties": { "type": "integer" } }
  let registry = @referencing.Registry::new().with_resource(
    "someRef",
    @referencing.draft7().create_resource(schema),
  )
  let validator = @jsonschema.draft7_validator.new(
    { "$ref": "someRef" },
    registry~,
  )
  let errors = validator.iter_errors({ "foo": "notAnInteger" }).to_array()
  inspect(errors.length(), content="1")
  inspect(
    describe(errors[0]),
    content=(
      #|message: 'notAnInteger' is not of type 'integer'
      #|validator: 'type'
      #|validator_value: 'integer'
      #|instance: 'notAnInteger'
      #|schema: {'type': 'integer'}
      #|path: ['foo']
      #|schema_path: ['additionalProperties', 'type']
      #|absolute_path: ['foo']
      #|absolute_schema_path: ['additionalProperties', 'type']
      #|json_path: $.foo
      #|context: 0
    ),
  )
}

///|
test "prefixItems" {
  let v = @jsonschema.draft202012_validator.new({
    "prefixItems": [{ "type": "string" }, {}, {}, { "maximum": 3 }],
  })
  let errors = v.iter_errors([1, 2, "foo", 5]).to_array()
  inspect(errors.length(), content="2")
  inspect(
    describe(errors[0]),
    content=(
      #|message: 1 is not of type 'string'
      #|validator: 'type'
      #|validator_value: 'string'
      #|instance: 1
      #|schema: {'type': 'string'}
      #|path: [0]
      #|schema_path: ['prefixItems', 0, 'type']
      #|absolute_path: [0]
      #|absolute_schema_path: ['prefixItems', 0, 'type']
      #|json_path: $[0]
      #|context: 0
    ),
  )
  inspect(
    describe(errors[1]),
    content=(
      #|message: 5 is greater than the maximum of 3
      #|validator: 'maximum'
      #|validator_value: 3
      #|instance: 5
      #|schema: {'maximum': 3}
      #|path: [3]
      #|schema_path: ['prefixItems', 3, 'maximum']
      #|absolute_path: [3]
      #|absolute_schema_path: ['prefixItems', 3, 'maximum']
      #|json_path: $[3]
      #|context: 0
    ),
  )
  let v = @jsonschema.draft202012_validator.new({
    "items": { "type": "string" },
    "prefixItems": [{}],
  })
  let errors = v.iter_errors(["foo", 2, "bar", 4, "baz"]).to_array()
  inspect(
    errors
    .map(e => {
      "\{e.message} \{path_repr(e.absolute_path())} \{path_repr(e.schema_path)} \{e.json_path()}"
    })
    .join("\n"),
    content=(
      #|2 is not of type 'string' [1] ['items', 'type'] $[1]
      #|4 is not of type 'string' [3] ['items', 'type'] $[3]
    ),
  )
}

///|
test "contains details" {
  let v = @jsonschema.draft202012_validator.new({
    "contains": { "type": "string" },
    "maxContains": 2,
  })
  let errors = v.iter_errors(["foo", 2, "bar", 4, "baz", "quux"]).to_array()
  inspect(errors.length(), content="1")
  inspect(
    describe(errors[0]),
    content=(
      #|message: Too many items match the given schema (expected at most 2)
      #|validator: 'maxContains'
      #|validator_value: 2
      #|instance: ['foo', 2, 'bar', 4, 'baz', 'quux']
      #|schema: {'contains': {'type': 'string'}, 'maxContains': 2}
      #|path: []
      #|schema_path: ['contains']
      #|absolute_path: []
      #|absolute_schema_path: ['contains']
      #|json_path: $
      #|context: 0
    ),
  )
  let v = @jsonschema.draft202012_validator.new({
    "contains": { "type": "string" },
    "minContains": 2,
  })
  let errors = v.iter_errors(["foo", 2, 4]).to_array()
  inspect(errors.length(), content="1")
  inspect(
    "\{errors[0].message} | \{opt_repr(errors[0].validator)} | \{opt_repr(errors[0].validator_value)} | \{path_repr(errors[0].schema_path)}",
    content="Too few items match the given schema (expected at least 2 but only 1 matched) | 'minContains' | 2 | ['contains']",
  )
  let errors = v.iter_errors([2, 4]).to_array()
  inspect(errors.length(), content="1")
  inspect(
    "\{errors[0].message} | \{opt_repr(errors[0].validator)} | \{opt_repr(errors[0].validator_value)} | \{path_repr(errors[0].schema_path)}",
    content="[2, 4] does not contain items matching the given schema | 'contains' | {'type': 'string'} | ['contains']",
  )
}

///|
test "ref sibling" {
  let v = @jsonschema.draft202012_validator.new({
    "$defs": { "foo": { "required": ["bar"] } },
    "properties": { "aprop": { "$ref": "#/$defs/foo", "required": ["baz"] } },
  })
  let errors = v.iter_errors({ "aprop": {} }).to_array()
  inspect(errors.length(), content="2")
  inspect(
    describe(errors[0]),
    content=(
      #|message: 'bar' is a required property
      #|validator: 'required'
      #|validator_value: ['bar']
      #|instance: {}
      #|schema: {'required': ['bar']}
      #|path: ['aprop']
      #|schema_path: ['properties', 'aprop', 'required']
      #|absolute_path: ['aprop']
      #|absolute_schema_path: ['properties', 'aprop', 'required']
      #|json_path: $.aprop
      #|context: 0
    ),
  )
  inspect(
    describe(errors[1]),
    content=(
      #|message: 'baz' is a required property
      #|validator: 'required'
      #|validator_value: ['baz']
      #|instance: {}
      #|schema: {'$ref': '#/$defs/foo', 'required': ['baz']}
      #|path: ['aprop']
      #|schema_path: ['properties', 'aprop', 'required']
      #|absolute_path: ['aprop']
      #|absolute_schema_path: ['properties', 'aprop', 'required']
      #|json_path: $.aprop
      #|context: 0
    ),
  )
}
