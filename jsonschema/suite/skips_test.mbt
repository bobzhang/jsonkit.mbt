// Ports of the skip functions of upstream's
// `jsonschema/tests/test_jsonschema_test_suite.py`.

///|
priv struct SuiteTest {
  subject : String
  case_description : String
  description : String
  schema : Json
  data : Json
  valid : Bool
}

///|
fn skip_when(
  test_ : SuiteTest,
  message : String,
  subject? : String,
  case_description? : String,
  description? : String,
) -> String? {
  if subject is Some(s) && s != test_.subject {
    return None
  }
  if case_description is Some(c) && c != test_.case_description {
    return None
  }
  if description is Some(d) && d != test_.description {
    return None
  }
  Some(message)
}

///|
fn first_skip(reasons : Array[() -> String?]) -> String? {
  for r in reasons {
    if r() is Some(m) {
      return Some(m)
    }
  }
  None
}

///|
fn ecmascript_regex(test_ : SuiteTest) -> String? {
  if test_.subject == "ecmascript-regex" {
    Some("ECMA regex support will be added in #1142.")
  } else {
    None
  }
}

///|
fn unicode_property_escape(test_ : SuiteTest) -> String? {
  if test_.case_description.contains("Unicode property escape") {
    Some("Unicode property escapes requires ECMA-like regexes.")
  } else {
    None
  }
}

///|
fn missing_format(
  checker : @jsonschema.FormatChecker,
) -> (SuiteTest) -> String? {
  test_ => match test_.schema {
    Object({ "format": String(format), .. }) =>
      if checker.checkers.contains(format) || test_.valid {
        None
      } else {
        Some("Format checker '\{format}' not found.")
      }
    Object({ "format": format, .. }) =>
      if test_.valid {
        None
      } else {
        Some("Format checker \{@jsonschema.py_repr(format)} not found.")
      }
    _ => None
  }
}

///|
fn complex_email_validation(test_ : SuiteTest) -> String? {
  if test_.subject != "email" && test_.subject != "idn-email" {
    return None
  }
  let message = "Complex email validation is (intentionally) unsupported."
  for description in [
    "an invalid domain", "an invalid IPv4-address-literal", "dot after local part is not valid",
    "dot before local part is not valid", "two subsequent dots inside local part are not valid",
    "domain is required", "local part is required", "two email addresses is not valid",
    "full \"From\" header is invalid", "unquoted space in local part is invalid",
    "a local part with a lone UTF-16 surrogate is invalid",
  ] {
    if skip_when(test_, message, description~) is Some(m) {
      return Some(m)
    }
  }
  None
}

///|
fn hostname_validation(test_ : SuiteTest) -> String? {
  if test_.subject != "hostname" {
    return None
  }
  let message = "Full hostname validation is not yet supported."
  if test_.case_description == "validation of A-label (punycode) host names" {
    return Some(message)
  }
  first_skip([
    () => skip_when(
      test_,
      message,
      case_description="validation of host names",
      description="trailing dot",
    ),
    () => skip_when(
      test_,
      message,
      case_description="validation of host names",
      description="contains \"--\" in the 3rd and 4th position",
    ),
  ])
}

///|
fn idn_hostname_validation(test_ : SuiteTest) -> String? {
  if test_.subject != "idn-hostname" {
    return None
  }
  let message = "Full idn-hostname validation is not yet supported."
  let separators = "validation of separators in internationalized host names"
  let names = "validation of internationalized host names"
  for pair in [
    (separators, "trailing dot"),
    (separators, "trailing ideographic full stop"),
    (separators, "trailing fullwidth full stop"),
    (separators, "trailing halfwidth ideographic full stop"),
    (names, "Bidi domain name with a digit-first label is invalid"),
    (names, "non-canonical Punycode that does not re-encode to itself is invalid"),
  ] {
    if skip_when(test_, message, case_description=pair.0, description=pair.1)
      is Some(m) {
      return Some(m)
    }
  }
  None
}

///|
fn duration_validation(test_ : SuiteTest) -> String? {
  if test_.subject != "duration" {
    return None
  }
  let message = "Strict RFC 3339 duration validation is not yet supported."
  for description in [
    "fractional duration is not allowed by RFC 3339 ABNF", "hours and seconds cannot appear without minutes",
    "years and days cannot appear without months",
  ] {
    if skip_when(test_, message, description~) is Some(m) {
      return Some(m)
    }
  }
  None
}

///|
fn leap_second(test_ : SuiteTest) -> String? {
  let message = "Leap seconds are unsupported."
  for pair in [
    ("time", "a valid time string with leap second"),
    ("time", "a valid time string with leap second, Zulu"),
    ("time", "a valid time string with leap second with offset"),
    ("time", "valid leap second, positive time-offset"),
    ("time", "valid leap second, negative time-offset"),
    ("time", "valid leap second, large positive time-offset"),
    ("time", "valid leap second, large negative time-offset"),
    ("time", "valid leap second, zero time-offset"),
    ("date-time", "a valid date-time with a leap second, UTC"),
    ("date-time", "a valid date-time with a leap second, with minus offset"),
  ] {
    if skip_when(test_, message, subject=pair.0, description=pair.1) is Some(m) {
      return Some(m)
    }
  }
  None
}

///|
fn vocabulary_skip(test_ : SuiteTest) -> String? {
  skip_when(
    test_,
    "Vocabulary support is still in-progress.",
    subject="vocabulary",
    description="no validation: invalid number, but it still validates",
  )
}

///|
/// The `skip=` argument of each upstream test class.
fn skip_for(class_name : String) -> (SuiteTest) -> String? {
  match class_name {
    "TestDraft3" =>
      test_ => first_skip([
        () => ecmascript_regex(test_),
        () => missing_format(@jsonschema.draft3_format_checker)(test_),
        () => complex_email_validation(test_),
      ])
    "TestDraft4" =>
      test_ => first_skip([
        () => ecmascript_regex(test_),
        () => leap_second(test_),
        () => missing_format(@jsonschema.draft4_format_checker)(test_),
        () => complex_email_validation(test_),
        () => hostname_validation(test_),
      ])
    "TestDraft6" =>
      test_ => first_skip([
        () => ecmascript_regex(test_),
        () => leap_second(test_),
        () => missing_format(@jsonschema.draft6_format_checker)(test_),
        () => complex_email_validation(test_),
        () => hostname_validation(test_),
      ])
    "TestDraft7" =>
      test_ => first_skip([
        () => ecmascript_regex(test_),
        () => leap_second(test_),
        () => missing_format(@jsonschema.draft7_format_checker)(test_),
        () => complex_email_validation(test_),
        () => hostname_validation(test_),
        () => idn_hostname_validation(test_),
      ])
    "TestDraft201909" => vocabulary_skip
    "TestDraft201909Format" =>
      test_ => first_skip([
        () => complex_email_validation(test_),
        () => hostname_validation(test_),
        () => idn_hostname_validation(test_),
        () => ecmascript_regex(test_),
        () => leap_second(test_),
        () => missing_format(@jsonschema.draft201909_format_checker)(test_),
        () => duration_validation(test_),
      ])
    "TestDraft202012" =>
      test_ => first_skip([
        () => vocabulary_skip(test_),
        () => unicode_property_escape(test_),
      ])
    "TestDraft202012Format" =>
      test_ => first_skip([
        () => complex_email_validation(test_),
        () => hostname_validation(test_),
        () => idn_hostname_validation(test_),
        () => ecmascript_regex(test_),
        () => leap_second(test_),
        () => missing_format(@jsonschema.draft202012_format_checker)(test_),
        () => duration_validation(test_),
      ])
    _ => _ => None
  }
}
