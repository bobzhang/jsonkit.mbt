// Port of jmespath/__init__.py.

///|
/// The version of jmespath.py this package is a port of.
pub let version : String = "1.1.0"

///|
/// Compiles a JMESPath expression (`jmespath.compile`).
///
/// ```mbt check
/// test {
///   let parsed = @jmespath.compile("foo.bar")
///   json_inspect(parsed.search({ "foo": { "bar": "baz" } }), content="baz")
/// }
/// ```
pub fn compile(expression : String) -> ParsedResult raise JMESPathError {
  Parser::new().parse(expression)
}

///|
/// Evaluates a JMESPath expression against `data` (`jmespath.search`).
///
/// ```mbt check
/// test {
///   let data : Json = { "foo": [{ "a": 1 }, { "a": 2 }, { "b": 3 }] }
///   json_inspect(@jmespath.search("foo[*].a", data), content=[1, 2])
/// }
/// ```
pub fn search(
  expression : String,
  data : Json,
  options? : Options,
) -> Json raise JMESPathError {
  Parser::new().parse(expression).search(data, options?)
}
