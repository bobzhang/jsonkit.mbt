///|
/// Which upstream exception class an error stands for.
pub(all) enum ErrorKind {
  /// `jsonschema.exceptions.ValidationError`: an instance was invalid under a
  /// provided schema.
  Validation
  /// `jsonschema.exceptions.SchemaError`: a schema was invalid under its
  /// corresponding metaschema.
  Schema
} derive(Eq, Debug)

///|
/// A validation error (upstream's `_Error`, i.e. `ValidationError` or
/// `SchemaError` depending on `kind`).
///
/// Errors are mutable, like upstream's: validators fill in details
/// (`validator`, `validator_value`, `instance`, `schema`) as errors bubble up
/// and prepend to the relative paths.
///
/// The `validator`, `validator_value`, `instance` and `schema` fields are
/// `None` while unset (upstream's `_unset`); a Python `None` is represented
/// as `Some(Json::null())` (e.g. `validator` is `Some(null)` for errors
/// produced by a `false` schema).
pub struct ValidationError {
  kind : ErrorKind
  /// A human readable message explaining the error.
  message : String
  /// The path to the offending element within the instance, relative to
  /// the parent error (upstream's `path` / `relative_path`).
  path : Array[PathItem]
  /// The path to the failing keyword within the schema, relative to the
  /// parent error (upstream's `schema_path` / `relative_schema_path`).
  schema_path : Array[PathItem]
  /// Errors from subschemas (e.g. of `anyOf`) explaining this error.
  context : Array[ValidationError]
  /// The underlying error, e.g. from a format checker.
  cause : Error?
  /// The name of the failed keyword.
  mut validator : Json?
  /// The keyword's value in the schema.
  mut validator_value : Json?
  /// The instance that was being validated.
  mut instance : Json?
  /// The (sub)schema the keyword is in.
  mut schema : Json?
  /// The error this one is in the context of, if any.
  mut parent : ValidationError?
  priv mut type_checker : TypeChecker?
}

///|
/// Raised by validation: carries the `ValidationError` data.
pub(all) suberror JsonSchemaError {
  /// `jsonschema.exceptions.ValidationError`
  ValidationError(ValidationError)
  /// `jsonschema.exceptions.SchemaError`
  SchemaError(ValidationError)
}

///|
pub impl Show for JsonSchemaError with output(self, logger) {
  match self {
    ValidationError(e) | SchemaError(e) => logger.write_string(e.to_string())
  }
}

///|
/// Construct an error (`ValidationError(message, ...)` upstream).
pub fn ValidationError::new(
  message : String,
  validator? : Json,
  path? : ArrayView[PathItem] = [],
  cause? : Error,
  context? : ArrayView[ValidationError] = [],
  validator_value? : Json,
  instance? : Json,
  schema? : Json,
  schema_path? : ArrayView[PathItem] = [],
  parent? : ValidationError,
  type_checker? : TypeChecker,
  kind? : ErrorKind = Validation,
) -> ValidationError {
  let error = {
    kind,
    message,
    path: path.to_owned(),
    schema_path: schema_path.to_owned(),
    context: context.to_owned(),
    cause,
    validator,
    validator_value,
    instance,
    schema,
    parent,
    type_checker,
  }
  for e in error.context {
    e.parent = Some(error)
  }
  error
}

///|
/// `SchemaError.create_from(other)`: a copy of `other`'s contents as a
/// `SchemaError` (`kind=Schema`; the type checker is not copied).
pub fn ValidationError::create_from(
  other : ValidationError,
  kind? : ErrorKind = Schema,
) -> ValidationError {
  ValidationError::new(
    other.message,
    validator?=other.validator,
    path=other.path,
    cause?=other.cause,
    context=other.context,
    validator_value?=other.validator_value,
    instance?=other.instance,
    schema?=other.schema,
    schema_path=other.schema_path,
    parent?=other.parent,
    kind~,
  )
}

///|
/// The error as something that can be raised.
pub fn ValidationError::to_error(self : ValidationError) -> JsonSchemaError {
  match self.kind {
    Validation => ValidationError(self)
    Schema => SchemaError(self)
  }
}

///|
/// Upstream's class name for this error.
pub fn ValidationError::class_name(self : ValidationError) -> String {
  match self.kind {
    Validation => "ValidationError"
    Schema => "SchemaError"
  }
}

///|
/// `repr(error)`: `<ValidationError: 'message'>`.
pub fn ValidationError::repr(self : ValidationError) -> String {
  "<\{self.class_name()}: \{@pycompat.repr_string(self.message)}>"
}

///|
/// The failed keyword, when it is a string.
pub fn ValidationError::keyword(self : ValidationError) -> String? {
  match self.validator {
    Some(String(k)) => Some(k)
    _ => None
  }
}

///|
/// `relative_path`: same as `path`.
pub fn ValidationError::relative_path(self : ValidationError) -> Array[PathItem] {
  self.path
}

///|
/// `relative_schema_path`: same as `schema_path`.
pub fn ValidationError::relative_schema_path(
  self : ValidationError,
) -> Array[PathItem] {
  self.schema_path
}

///|
/// The path to the offending element within the instance, from the root of
/// the instance.
pub fn ValidationError::absolute_path(self : ValidationError) -> Array[PathItem] {
  match self.parent {
    None => self.path.copy()
    Some(parent) => parent.absolute_path() + self.path
  }
}

///|
/// The path to the failing keyword within the schema, from the root schema.
pub fn ValidationError::absolute_schema_path(
  self : ValidationError,
) -> Array[PathItem] {
  match self.parent {
    None => self.schema_path.copy()
    Some(parent) => parent.absolute_schema_path() + self.schema_path
  }
}

///|
/// `_JSON_PATH_COMPATIBLE_PROPERTY_PATTERN.match(elem)`:
/// `^[a-zA-Z][a-zA-Z0-9_]*$` (where `$` also matches before a final newline).
fn json_path_compatible(elem : String) -> Bool {
  let s = if elem.has_suffix("\n") {
    elem.unsafe_substring(start=0, end=elem.length() - 1)
  } else {
    elem
  }
  if s.length() == 0 {
    return false
  }
  for i, c in s {
    let ok = (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (i > 0 && ((c >= '0' && c <= '9') || c == '_'))
    if !ok {
      return false
    }
  }
  true
}

///|
/// A JSONPath expression for the offending element (e.g. `$.foo[0]`).
pub fn ValidationError::json_path(self : ValidationError) -> String {
  let sb = StringBuilder()
  sb.write_char('$')
  for elem in self.absolute_path() {
    match elem {
      Index(i) => sb.write_string("[\{i}]")
      Key(k) =>
        if json_path_compatible(k) {
          sb.write_char('.')
          sb.write_string(k)
        } else {
          let escaped = k.replace_all(old="\\", new="\\\\").replace_all(old="'", new="\\'")
          sb.write_string("['\{escaped}']")
        }
    }
  }
  sb.to_string()
}

///|
/// Upstream's `_set`: fill in details that are still unset.
fn ValidationError::set_unset(
  self : ValidationError,
  type_checker~ : TypeChecker,
  validator~ : Json,
  validator_value~ : Json,
  instance~ : Json,
  schema~ : Json,
) -> Unit {
  if self.type_checker is None {
    self.type_checker = Some(type_checker)
  }
  if self.validator is None {
    self.validator = Some(validator)
  }
  if self.validator_value is None {
    self.validator_value = Some(validator_value)
  }
  if self.instance is None {
    self.instance = Some(instance)
  }
  if self.schema is None {
    self.schema = Some(schema)
  }
}

///|
/// Upstream's `_matches_type`: whether the instance matches the `type` of the
/// schema the error is in.
fn ValidationError::matches_type(self : ValidationError) -> Bool {
  guard self.schema is Some(Object({ "type": expected, .. })) else {
    return false
  }
  guard self.type_checker is Some(checker) else { return false }
  let instance = self.instance.unwrap_or(Json::null())
  let check = (t : Json) => match t {
    String(name) => checker.is_type(instance, name) catch { _ => false }
    _ => false
  }
  match expected {
    String(_) => check(expected)
    Array(types) => types.iter().any(check)
    _ => false
  }
}

///|
/// Format something for an error message as prettily as we currently can.
fn pretty(thing : Json, prefix : String) -> String {
  let text = @pycompat.text_indent(@pycompat.pformat(thing, width=72), prefix)
  // .lstrip()
  let cps = @unicodedata.code_points(text)
  let mut i = 0
  while i < cps.length() && @unicodedata.is_space(cps[i]) {
    i += 1
  }
  @unicodedata.from_code_points(cps[i:])
}

///|
/// Python's `str.rstrip()`.
fn rstrip(s : String) -> String {
  let cps = @unicodedata.code_points(s)
  let mut n = cps.length()
  while n > 0 && @unicodedata.is_space(cps[n - 1]) {
    n -= 1
  }
  @unicodedata.from_code_points(cps[:n])
}

///|
/// `str(error)`: the message, followed (when the details are known) by the
/// failing keyword, schema and instance, exactly like upstream.
pub impl Show for ValidationError with output(self, logger) {
  guard self.validator is Some(validator) &&
    self.validator_value is Some(_) &&
    self.instance is Some(instance) &&
    self.schema is Some(schema) else {
    logger.write_string(self.message)
    return
  }
  let (word_schema, word_instance) = match self.kind {
    Validation => ("schema", "instance")
    Schema => ("metaschema", "schema")
  }
  let schema_path = format_as_index(
    word_schema,
    self.schema_path[:@cmp.maximum(self.schema_path.length() - 1, 0)],
  )
  let instance_path = format_as_index(word_instance, self.path)
  let prefix = " ".repeat(16)
  let indent = " ".repeat(12)
  let text = "\{indent}\{self.message}\n\n" +
    "\{indent}Failed validating \{@pycompat.repr(validator)} in \{schema_path}:\n" +
    "\{indent}    \{pretty(schema, prefix)}\n\n" +
    "\{indent}On \{instance_path}:\n" +
    "\{indent}    \{pretty(instance, prefix)}\n" +
    indent
  logger.write_string(@pycompat.text_dedent(rstrip(text)))
}

///|
/// Raised when a validator is asked to validate against an unknown type
/// (`jsonschema.exceptions.UnknownType`).
pub suberror UnknownType {
  UnknownType(type_~ : Json, instance~ : Json, schema~ : Json)
}

///|
pub impl Show for UnknownType with output(self, logger) {
  let UnknownType(type_~, instance~, schema~) = self
  let prefix = " ".repeat(16)
  let indent = " ".repeat(12)
  let text = "\{indent}Unknown type \{@pycompat.repr(type_)} for validator with schema:\n" +
    "\{indent}    \{pretty(schema, prefix)}\n\n" +
    "\{indent}While checking instance:\n" +
    "\{indent}    \{pretty(instance, prefix)}\n" +
    indent
  logger.write_string(@pycompat.text_dedent(rstrip(text)))
}

///|
/// Raised by `FormatChecker::check` when an instance does not conform
/// (`jsonschema.exceptions.FormatError`).
pub suberror FormatError {
  FormatError(message~ : String, cause~ : Error?)
}

///|
pub impl Show for FormatError with output(self, logger) {
  let FormatError(message~, ..) = self
  logger.write_string(message)
}
