///|
/// All errors raised by this library (Python's `referencing.exceptions`, plus
/// `referencing.jsonschema.UnknownDialect`).
///
/// Python models these as an exception class hierarchy where
/// `PointerToNowhere`, `NoSuchAnchor` and `InvalidAnchor` are subclasses of
/// `Unresolvable`; use `ReferencingError::is_unresolvable` to test for
/// "an `Unresolvable` or any subclass thereof".
///
/// `Show` renders the same text as Python's `str(error)`.
pub(all) suberror ReferencingError {
  /// The given URI is not present in a registry.
  NoSuchResource(reference~ : String)
  /// A resource has no internal ID, but one is needed.
  NoInternalID(resource~ : Resource)
  /// The given URI is not present in a registry, and retrieving it failed.
  /// `cause` is the error raised by the retrieval function (Python's
  /// `__cause__`); it does not take part in equality.
  Unretrievable(reference~ : String, cause~ : Error?)
  /// Attempting to detect the appropriate `Specification` failed.
  CannotDetermineSpecification(contents~ : Json)
  /// A reference was unresolvable.
  Unresolvable(reference~ : String)
  /// A JSON Pointer leads to a part of a document that does not exist.
  /// (An `Unresolvable`.)
  PointerToNowhere(reference~ : String, resource~ : Resource)
  /// An anchor does not exist within a particular resource.
  /// (An `Unresolvable`.)
  NoSuchAnchor(reference~ : String, resource~ : Resource, anchor~ : String)
  /// An anchor which could never exist in a resource was dereferenced.
  /// (An `Unresolvable`.)
  InvalidAnchor(reference~ : String, resource~ : Resource, anchor~ : String)
  /// A dialect identifier was found for a dialect unknown by this library
  /// (Python's `referencing.jsonschema.UnknownDialect`).
  UnknownDialect(uri~ : String)
}

///|
/// Whether this error is an `Unresolvable` or one of its "subclasses"
/// (`PointerToNowhere`, `NoSuchAnchor`, `InvalidAnchor`), i.e. whether
/// Python's `except referencing.exceptions.Unresolvable` would catch it.
pub fn ReferencingError::is_unresolvable(self : ReferencingError) -> Bool {
  self
  is (Unresolvable(..) | PointerToNowhere(..) | NoSuchAnchor(..) | InvalidAnchor(..))
}

///|
/// The `ref` carried by the error, if it has one.
pub fn ReferencingError::reference(self : ReferencingError) -> String? {
  match self {
    NoSuchResource(reference~)
    | Unretrievable(reference~, ..)
    | Unresolvable(reference~)
    | PointerToNowhere(reference~, ..)
    | NoSuchAnchor(reference~, ..)
    | InvalidAnchor(reference~, ..) => Some(reference)
    NoInternalID(..) | CannotDetermineSpecification(..) | UnknownDialect(..) =>
      None
  }
}

///|
/// Structural equality (as upstream's attrs-based `__eq__`), where errors of
/// different kinds are never equal and an `Unretrievable`'s cause is ignored.
pub impl Eq for ReferencingError with equal(self, other) {
  match (self, other) {
    (NoSuchResource(reference=a), NoSuchResource(reference=b)) => a == b
    (NoInternalID(resource=a), NoInternalID(resource=b)) => a == b
    (Unretrievable(reference=a, ..), Unretrievable(reference=b, ..)) => a == b
    (CannotDetermineSpecification(contents=a), CannotDetermineSpecification(contents=b)) =>
      a == b
    (Unresolvable(reference=a), Unresolvable(reference=b)) => a == b
    (PointerToNowhere(reference=a, resource=r), PointerToNowhere(reference=b, resource=s)) =>
      a == b && r == s
    (
      NoSuchAnchor(reference=a, resource=r, anchor=x),
      NoSuchAnchor(reference=b, resource=s, anchor=y),
    ) => a == b && r == s && x == y
    (
      InvalidAnchor(reference=a, resource=r, anchor=x),
      InvalidAnchor(reference=b, resource=s, anchor=y),
    ) => a == b && r == s && x == y
    (UnknownDialect(uri=a), UnknownDialect(uri=b)) => a == b
    _ => false
  }
}

///|
/// Renders exactly what Python's `str(error)` renders.
pub impl Show for ReferencingError with output(self, logger) {
  match self {
    // KeyError subclasses: str() is the repr() of the single argument
    NoSuchResource(reference~) | Unretrievable(reference~, ..) =>
      logger.write_string(py_str_repr(reference))
    NoInternalID(resource~) => logger.write_string(resource.to_string())
    CannotDetermineSpecification(contents~) =>
      logger.write_string(py_str(contents))
    Unresolvable(reference~) => logger.write_string(reference)
    PointerToNowhere(reference~, resource~) => {
      logger.write_string(
        "\{py_str_repr(reference)} does not exist within \{py_repr(resource.contents)}",
      )
      if reference == "/" {
        logger.write_string(
          ". The pointer '/' is a valid JSON Pointer but it points to an empty string property ''. If you intended to point to the entire resource, you should use '#'.",
        )
      }
    }
    NoSuchAnchor(anchor~, resource~, ..) =>
      logger.write_string(
        "\{py_str_repr(anchor)} does not exist within \{py_repr(resource.contents)}",
      )
    InvalidAnchor(anchor~, ..) =>
      logger.write_string(
        "'#\{anchor}' is not a valid anchor, neither as a plain name anchor nor as a JSON Pointer. You may have intended to use '#/\{anchor}', as the slash is required *before each segment* of a JSON pointer.",
      )
    UnknownDialect(uri~) => logger.write_string(uri)
  }
}
