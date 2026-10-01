///|
/// Errors raised by the ports of the libraries python-jsonschema delegates
/// format checking to, named after the Python exception classes.
pub suberror LibError {
  /// `ipaddress.AddressValueError` (a `ValueError`)
  AddressValueError(String)
  /// `idna.IDNAError` (a `UnicodeError`, itself a `ValueError`)
  IDNAError(String)
  /// `jsonpointer.JsonPointerException`
  JsonPointerException(String)
  /// `isoduration.DurationParsingException` (a `ValueError`)
  DurationParsingException(String)
  /// A plain `ValueError`
  ValueError(String)
}

///|
pub impl Show for LibError with output(self, logger) {
  match self {
    AddressValueError(m)
    | IDNAError(m)
    | JsonPointerException(m)
    | DurationParsingException(m)
    | ValueError(m) => logger.write_string(m)
  }
}

///|
/// The Python class name of the error.
pub fn LibError::class_name(self : LibError) -> String {
  match self {
    AddressValueError(_) => "AddressValueError"
    IDNAError(_) => "IDNAError"
    JsonPointerException(_) => "JsonPointerException"
    DurationParsingException(_) => "DurationParsingException"
    ValueError(_) => "ValueError"
  }
}

///|
/// `isinstance(error, ValueError)`.
pub fn is_value_error(error : Error) -> Bool {
  error
  is (AddressValueError(_)
  | IDNAError(_)
  | DurationParsingException(_)
  | ValueError(_))
}

///|
/// `isinstance(error, ipaddress.AddressValueError)`.
pub fn is_address_value_error(error : Error) -> Bool {
  error is AddressValueError(_)
}

///|
/// `isinstance(error, (idna.IDNAError, UnicodeError))`.
pub fn is_idna_error(error : Error) -> Bool {
  error is IDNAError(_)
}

///|
/// `isinstance(error, jsonpointer.JsonPointerException)`.
pub fn is_json_pointer_exception(error : Error) -> Bool {
  error is JsonPointerException(_)
}

///|
/// `isinstance(error, isoduration.DurationParsingException)`.
pub fn is_duration_parsing_exception(error : Error) -> Bool {
  error is DurationParsingException(_)
}
