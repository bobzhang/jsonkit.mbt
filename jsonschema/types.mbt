///|
/// A type-checking function: given the checker doing the checking and an
/// instance, whether the instance is of the type.
pub type TypeCheckFn = (TypeChecker, Json) -> Bool raise

///|
/// A `type` property checker (`jsonschema.TypeChecker`).
///
/// A `TypeChecker` performs type checking for a validator, converting
/// between the defined JSON Schema types and JSON values.  It is immutable:
/// `redefine`, `redefine_many` and `remove` each return a new checker.
pub struct TypeChecker {
  priv type_checkers : Map[String, TypeCheckFn]
}

///|
/// `TypeChecker(type_checkers)`.
pub fn TypeChecker::new(
  type_checkers? : ArrayView[(String, TypeCheckFn)] = [],
) -> TypeChecker {
  let m = Map([])
  for pair in type_checkers {
    m[pair.0] = pair.1
  }
  { type_checkers: m }
}

///|
/// Raised by `TypeChecker::is_type` / `remove` for unknown types
/// (`jsonschema.exceptions.UndefinedTypeCheck`).
pub suberror UndefinedTypeCheck {
  UndefinedTypeCheck(String)
}

///|
pub impl Show for UndefinedTypeCheck with output(self, logger) {
  let UndefinedTypeCheck(type_) = self
  logger.write_string(
    "Type \{@pycompat.repr_string(type_)} is unknown to this type checker",
  )
}

///|
/// `repr(checker)`: `<TypeChecker types={'array', 'boolean', ...}>`.
pub impl Show for TypeChecker with output(self, logger) {
  let names = self.type_checkers.keys().collect()
  names.sort()
  logger.write_string("<TypeChecker types={")
  logger.write_string(
    names.map(n => @pycompat.repr_string(n)).join(", "),
  )
  logger.write_string("}>")
}

///|
/// Two checkers are equal when they map the same types to the very same
/// functions.
pub impl Eq for TypeChecker with equal(self, other) {
  if self.type_checkers.length() != other.type_checkers.length() {
    return false
  }
  for k, f in self.type_checkers {
    match other.type_checkers.get(k) {
      Some(g) if physical_equal(f, g) => ()
      _ => return false
    }
  }
  true
}

///|
/// Check if the instance is of the appropriate type.
///
/// Raises `UndefinedTypeCheck` if `type_` is unknown to this object.
pub fn TypeChecker::is_type(
  self : TypeChecker,
  instance : Json,
  type_ : String,
) -> Bool raise {
  guard self.type_checkers.get(type_) is Some(f) else {
    raise UndefinedTypeCheck(type_)
  }
  f(self, instance)
}

///|
/// The names of the types known to this checker, in definition order.
pub fn TypeChecker::types(self : TypeChecker) -> Array[String] {
  self.type_checkers.keys().collect()
}

///|
/// Produce a new checker with the given type redefined.
pub fn TypeChecker::redefine(
  self : TypeChecker,
  type_ : String,
  f : TypeCheckFn,
) -> TypeChecker {
  self.redefine_many([(type_, f)])
}

///|
/// Produce a new checker with the given types redefined.
pub fn TypeChecker::redefine_many(
  self : TypeChecker,
  definitions : ArrayView[(String, TypeCheckFn)],
) -> TypeChecker {
  let m = self.type_checkers.copy()
  for pair in definitions {
    m[pair.0] = pair.1
  }
  { type_checkers: m }
}

///|
/// Produce a new checker with the given types forgotten.
///
/// Raises `UndefinedTypeCheck` if any given type is unknown to this object.
pub fn TypeChecker::remove(
  self : TypeChecker,
  types : ArrayView[String],
) -> TypeChecker raise UndefinedTypeCheck {
  let m = self.type_checkers.copy()
  for t in types {
    if !m.contains(t) {
      raise UndefinedTypeCheck(t)
    }
    m.remove(t)
  }
  { type_checkers: m }
}

///|
fn is_array(_ : TypeChecker, instance : Json) -> Bool raise {
  instance is Array(_)
}

///|
fn is_bool(_ : TypeChecker, instance : Json) -> Bool raise {
  instance is (True | False)
}

///|
/// Python `isinstance(instance, int)` excluding bools.
fn is_integer(_ : TypeChecker, instance : Json) -> Bool raise {
  @pycompat.is_int(instance)
}

///|
fn is_null(_ : TypeChecker, instance : Json) -> Bool raise {
  instance is Null
}

///|
/// Python `isinstance(instance, numbers.Number)` excluding bools.
fn is_number(_ : TypeChecker, instance : Json) -> Bool raise {
  instance is Number(_)
}

///|
fn is_object(_ : TypeChecker, instance : Json) -> Bool raise {
  instance is Object(_)
}

///|
fn is_string(_ : TypeChecker, instance : Json) -> Bool raise {
  instance is String(_)
}

///|
fn is_any(_ : TypeChecker, _ : Json) -> Bool raise {
  true
}

///|
/// draft6+ integers: Python ints, or floats for which `is_integer()` holds.
fn is_integer_or_integral_float(
  checker : TypeChecker,
  instance : Json,
) -> Bool raise {
  is_integer(checker, instance) ||
  (@pycompat.is_float(instance) &&
  @pycompat.is_whole(@pycompat.number_value(instance)))
}

///|
/// The type checker for draft 3.
///
/// Note: like upstream, `integer` means a Python `int`, so a JSON `1.0` is
/// not an integer under drafts 3 and 4 (see `loads` for how the distinction
/// is kept).
pub let draft3_type_checker : TypeChecker = TypeChecker::new(type_checkers=[
  ("any", is_any),
  ("array", is_array),
  ("boolean", is_bool),
  ("integer", is_integer),
  ("object", is_object),
  ("null", is_null),
  ("number", is_number),
  ("string", is_string),
])

///|
/// The type checker for draft 4.
pub let draft4_type_checker : TypeChecker = draft3_type_checker.remove(["any"]) catch {
  _ => panic()
}

///|
/// The type checker for draft 6.
pub let draft6_type_checker : TypeChecker = draft4_type_checker.redefine(
  "integer", is_integer_or_integral_float,
)

///|
/// The type checker for draft 7.
pub let draft7_type_checker : TypeChecker = draft6_type_checker

///|
/// The type checker for draft 2019-09.
pub let draft201909_type_checker : TypeChecker = draft7_type_checker

///|
/// The type checker for draft 2020-12.
pub let draft202012_type_checker : TypeChecker = draft201909_type_checker
