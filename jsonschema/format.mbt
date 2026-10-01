///|
/// A format-checking function: whether the instance conforms. It may raise
/// to signal non-conformance (see `FormatChecker::checks`'s `raises`).
pub type FormatCheckFn = (Json) -> Bool raise

///|
/// A registered format check: the function, and which errors it raises to
/// signal an invalid instance (upstream's `raises` exception types).
pub struct FormatCheck {
  func : FormatCheckFn
  raises : (Error) -> Bool
}

///|
/// A `format` property checker (`jsonschema.FormatChecker`).
///
/// JSON Schema does not mandate that the `format` property actually do any
/// validation. If validation is desired however, instances of this type can
/// be hooked into validators to enable format validation.
///
/// `FormatChecker`s always return `true` when asked about formats that they
/// do not know how to validate.
pub struct FormatChecker {
  checkers : Map[String, FormatCheck]
}

///|
fn raises_nothing(_ : Error) -> Bool {
  false
}

///|
/// Upstream's (deprecated, global) class-level registry
/// `FormatChecker.checkers`, which `FormatChecker::new()` copies.
let class_checkers : Map[String, FormatCheck] = Map([])

///|
/// `FormatChecker(formats)`: a checker for the given formats, taken from the
/// class-level registry (all of them when `formats` is omitted).
///
/// Raises `UnknownFormat` (upstream: `KeyError`) for formats not in the
/// registry.
pub fn FormatChecker::new(
  formats? : ArrayView[String],
) -> FormatChecker raise UnknownFormat {
  let checkers = Map([])
  match formats {
    None => for k, v in class_checkers { checkers[k] = v }
    Some(formats) =>
      for k in formats {
        match class_checkers.get(k) {
          Some(v) => checkers[k] = v
          None => raise UnknownFormat(k)
        }
      }
  }
  { checkers, }
}

///|
/// Raised by `FormatChecker::new` for unknown formats (upstream: `KeyError`).
pub suberror UnknownFormat {
  UnknownFormat(String)
} derive(Debug)

///|
/// `repr(checker)`: `<FormatChecker checkers=['date', 'email', ...]>`.
pub impl Show for FormatChecker with output(self, logger) {
  let names = self.checkers.keys().collect()
  names.sort_by(py_str_compare)
  logger.write_string("<FormatChecker checkers=[")
  logger.write_string(names.map(n => @pycompat.repr_string(n)).join(", "))
  logger.write_string("]>")
}

///|
/// Register `func` as validating a new format.
///
/// `raises` decides which errors raised by `func` signal an invalid
/// instance; such an error becomes the `cause` of the resulting
/// `FormatError` (and thereby of the `ValidationError`).
pub fn FormatChecker::checks(
  self : FormatChecker,
  format : String,
  func : FormatCheckFn,
  raises? : (Error) -> Bool = raises_nothing,
) -> Unit {
  self.checkers[format] = { func, raises }
}

///|
/// Upstream's deprecated `FormatChecker.cls_checks`: register a check in the
/// class-level registry copied by future `FormatChecker::new()` calls.
pub fn FormatChecker::cls_checks(
  format : String,
  func : FormatCheckFn,
  raises? : (Error) -> Bool = raises_nothing,
) -> Unit {
  class_checkers[format] = { func, raises }
}

///|
/// Check whether the instance conforms to the given format.
///
/// Raises `FormatError` if it does not; errors raised by the check that are
/// not covered by its `raises` propagate unchanged.
pub fn FormatChecker::check(
  self : FormatChecker,
  instance : Json,
  format : String,
) -> Unit raise {
  guard self.checkers.get(format) is Some({ func, raises }) else { return }
  let mut cause : Error? = None
  let result = func(instance) catch {
    e =>
      if raises(e) {
        cause = Some(e)
        false
      } else {
        raise e
      }
  }
  if !result {
    raise FormatError(
      message="\{@pycompat.repr(instance)} is not a \{@pycompat.repr_string(format)}",
      cause~,
    )
  }
}

///|
/// Whether the instance conforms to the given format.
pub fn FormatChecker::conforms(
  self : FormatChecker,
  instance : Json,
  format : String,
) -> Bool raise {
  self.check(instance, format) catch {
    FormatError(_) => return false
    e => raise e
  }
  true
}
