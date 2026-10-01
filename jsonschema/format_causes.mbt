///|
/// The errors the built-in format checks raise to signal an invalid
/// instance (they become `FormatError` / `ValidationError` causes). Named
/// after the Python exception classes upstream's checks raise.
pub(all) suberror FormatCause {
  /// `ipaddress.AddressValueError` (`ipv4`, `ipv6`, draft 3 `ip-address`)
  AddressValueError(String)
  /// `idna.IDNAError` (`idn-hostname`)
  IDNAError(String)
  /// `jsonpointer.JsonPointerException` (`json-pointer`,
  /// `relative-json-pointer`)
  JsonPointerException(String)
  /// `isoduration.DurationParsingException` (`duration`)
  DurationParsingException(String)
  /// `re.PatternError` (`regex`)
  PatternError(String)
  /// A plain `ValueError` (`hostname`, `uri`, `iri`, `date`, `uuid`, ...)
  ValueError(String)
}

///|
pub impl Show for FormatCause with fn output(self, logger) {
  match self {
    AddressValueError(m)
    | IDNAError(m)
    | JsonPointerException(m)
    | DurationParsingException(m)
    | PatternError(m)
    | ValueError(m) => logger.write_string(m)
  }
}

///|
/// The Python class name of the error, e.g. `AddressValueError`.
pub fn FormatCause::class_name(self : FormatCause) -> String {
  match self {
    AddressValueError(_) => "AddressValueError"
    IDNAError(_) => "IDNAError"
    JsonPointerException(_) => "JsonPointerException"
    DurationParsingException(_) => "DurationParsingException"
    PatternError(_) => "PatternError"
    ValueError(_) => "ValueError"
  }
}

///|
/// `isinstance(error, ValueError)` (Python's hierarchy: address, IDNA and
/// duration errors are `ValueError`s).
pub fn FormatCause::is_value_error(self : FormatCause) -> Bool {
  self
  is (AddressValueError(_)
  | IDNAError(_)
  | DurationParsingException(_)
  | ValueError(_))
}

///|
/// Re-raise the internal libraries' errors as `FormatCause`s.
fn lift_cause(e : Error) -> Error {
  match e {
    @formats.AddressValueError(m) => AddressValueError(m)
    @formats.IDNAError(m) => IDNAError(m)
    @formats.JsonPointerException(m) => JsonPointerException(m)
    @formats.DurationParsingException(m) => DurationParsingException(m)
    @formats.ValueError(m) => ValueError(m)
    @regex.PatternError(m) => PatternError(m)
    other => other
  }
}

///|
fn is_value_error_cause(e : Error) -> Bool {
  e
  is (AddressValueError(_)
  | IDNAError(_)
  | DurationParsingException(_)
  | ValueError(_))
}

///|
fn is_address_value_error_cause(e : Error) -> Bool {
  e is AddressValueError(_)
}

///|
fn is_idna_error_cause(e : Error) -> Bool {
  e is IDNAError(_)
}

///|
fn is_json_pointer_cause(e : Error) -> Bool {
  e is JsonPointerException(_)
}

///|
fn is_duration_cause(e : Error) -> Bool {
  e is DurationParsingException(_)
}

///|
fn is_pattern_error_cause(e : Error) -> Bool {
  e is PatternError(_)
}
