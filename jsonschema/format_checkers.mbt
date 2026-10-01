// The format checks of `jsonschema._format`, with all of upstream's optional
// format dependencies (fqdn, idna, rfc3987, rfc3339-validator, webcolors,
// jsonpointer, uri-template, isoduration) ported in internal/formats.

///|
/// The format checker for draft 3.
pub let draft3_format_checker : FormatChecker = { checkers: Map([]) }

///|
/// The format checker for draft 4.
pub let draft4_format_checker : FormatChecker = { checkers: Map([]) }

///|
/// The format checker for draft 6.
pub let draft6_format_checker : FormatChecker = { checkers: Map([]) }

///|
/// The format checker for draft 7.
pub let draft7_format_checker : FormatChecker = { checkers: Map([]) }

///|
/// The format checker for draft 2019-09.
pub let draft201909_format_checker : FormatChecker = { checkers: Map([]) }

///|
/// The format checker for draft 2020-12.
pub let draft202012_format_checker : FormatChecker = { checkers: Map([]) }

///|
/// Upstream's `_checks_drafts`: register `func` under per-draft names in the
/// draft-specific checkers and (by its latest name) in the class registry.
fn checks_drafts(
  func : FormatCheckFn,
  name? : String,
  draft3? : String,
  draft4? : String,
  draft6? : String,
  draft7? : String,
  draft201909? : String,
  draft202012? : String,
  raises? : (Error) -> Bool = raises_nothing,
) -> Unit {
  let or_ = (a : String?, b : String?) => if a is Some(_) { a } else { b }
  let draft3 = or_(draft3, name)
  let draft4 = or_(draft4, name)
  let draft6 = or_(draft6, name)
  let draft7 = or_(draft7, name)
  let draft201909 = or_(draft201909, name)
  let draft202012 = or_(draft202012, name)
  let pairs = [
    (draft3, draft3_format_checker),
    (draft4, draft4_format_checker),
    (draft6, draft6_format_checker),
    (draft7, draft7_format_checker),
    (draft201909, draft201909_format_checker),
    (draft202012, draft202012_format_checker),
  ]
  for pair in pairs {
    if pair.0 is Some(format) {
      pair.1.checks(format, func, raises~)
    }
  }
  let latest = or_(
    draft202012,
    or_(draft201909, or_(draft7, or_(draft6, or_(draft4, draft3)))),
  )
  if latest is Some(format) {
    FormatChecker::cls_checks(format, func, raises~)
  }
}

///|
fn is_email(instance : Json) -> Bool raise {
  guard instance is String(s) else { return true }
  s.contains("@")
}

///|
fn is_ipv4(instance : Json) -> Bool raise {
  guard instance is String(s) else { return true }
  @formats.ipv4_address(s)
  true
}

///|
fn is_ipv6(instance : Json) -> Bool raise {
  guard instance is String(s) else { return true }
  let scope_id = @formats.ipv6_address(s)
  // `not getattr(address, "scope_id", "")`
  match scope_id {
    None => true
    Some(id) => id == ""
  }
}

///|
fn is_host_name(instance : Json) -> Bool raise {
  guard instance is String(s) else { return true }
  @formats.fqdn_is_valid(s, min_labels=1)
}

///|
fn is_idn_host_name(instance : Json) -> Bool raise {
  guard instance is String(s) else { return true }
  @formats.idna_encode(s)
  true
}

///|
fn is_iri(instance : Json) -> Bool raise {
  guard instance is String(s) else { return true }
  @formats.rfc3987_parse(s, rule="IRI")
  true
}

///|
fn is_iri_reference(instance : Json) -> Bool raise {
  guard instance is String(s) else { return true }
  @formats.rfc3987_parse(s, rule="IRI_reference")
  true
}

///|
fn is_uri(instance : Json) -> Bool raise {
  guard instance is String(s) else { return true }
  @formats.rfc3987_parse(s, rule="URI")
  true
}

///|
fn is_uri_reference(instance : Json) -> Bool raise {
  guard instance is String(s) else { return true }
  @formats.rfc3987_parse(s, rule="URI_reference")
  true
}

///|
fn is_datetime(instance : Json) -> Bool raise {
  guard instance is String(s) else { return true }
  @formats.validate_rfc3339(@formats.ascii_upper(s))
}

///|
fn is_time(instance : Json) -> Bool raise {
  guard instance is String(s) else { return true }
  is_datetime(Json::string("1970-01-01T" + s))
}

///|
fn is_regex(instance : Json) -> Bool raise {
  guard instance is String(s) else { return true }
  ignore(@regex.compile(s))
  true
}

///|
fn is_date(instance : Json) -> Bool raise {
  guard instance is String(s) else { return true }
  @formats.is_iso_date(s)
}

///|
fn is_draft3_time(instance : Json) -> Bool raise {
  guard instance is String(s) else { return true }
  @formats.strptime_hms(s)
  true
}

///|
fn is_css21_color(instance : Json) -> Bool raise {
  if instance is String(s) {
    @formats.css_color(s)
  }
  true
}

///|
fn is_json_pointer(instance : Json) -> Bool raise {
  guard instance is String(s) else { return true }
  @formats.json_pointer(s)
  true
}

///|
fn is_relative_json_pointer(instance : Json) -> Bool raise {
  guard instance is String(s) else { return true }
  @formats.relative_json_pointer(s)
}

///|
fn is_uri_template(instance : Json) -> Bool raise {
  guard instance is String(s) else { return true }
  @formats.uri_template_validate(s)
}

///|
fn is_duration(instance : Json) -> Bool raise {
  guard instance is String(s) else { return true }
  @formats.parse_duration(s)
  // FIXME upstream: See bolsote/isoduration#25 and bolsote/isoduration#21
  match s.get_char(s.length() - 1) {
    Some('D' | 'M' | 'Y' | 'W' | 'H' | 'S') => true
    _ => false
  }
}

///|
fn is_uuid(instance : Json) -> Bool raise {
  guard instance is String(s) else { return true }
  @formats.uuid_round_trips(s)
}

///|
fn is_regex_error(e : Error) -> Bool {
  e is @regex.PatternError(_)
}

///|
fn init {
  // Registration order mirrors `jsonschema/_format.py` (it matters for the
  // class-level registry, where draft 3's `time` replaces the RFC 3339 one).
  checks_drafts(is_email, name="email")
  checks_drafts(is_email, name="idn-email")
  checks_drafts(
    is_ipv4,
    draft3="ip-address",
    draft4="ipv4",
    draft6="ipv4",
    draft7="ipv4",
    draft201909="ipv4",
    draft202012="ipv4",
    raises=@formats.is_address_value_error,
  )
  checks_drafts(is_ipv6, name="ipv6", raises=@formats.is_address_value_error)
  checks_drafts(
    is_host_name,
    draft3="host-name",
    draft4="hostname",
    draft6="hostname",
    draft7="hostname",
    draft201909="hostname",
    draft202012="hostname",
    raises=@formats.is_value_error,
  )
  checks_drafts(
    is_idn_host_name,
    draft7="idn-hostname",
    draft201909="idn-hostname",
    draft202012="idn-hostname",
    raises=@formats.is_idna_error,
  )
  checks_drafts(
    is_iri,
    draft7="iri",
    draft201909="iri",
    draft202012="iri",
    raises=@formats.is_value_error,
  )
  checks_drafts(
    is_iri_reference,
    draft7="iri-reference",
    draft201909="iri-reference",
    draft202012="iri-reference",
    raises=@formats.is_value_error,
  )
  checks_drafts(is_uri, name="uri", raises=@formats.is_value_error)
  checks_drafts(
    is_uri_reference,
    draft6="uri-reference",
    draft7="uri-reference",
    draft201909="uri-reference",
    draft202012="uri-reference",
    raises=@formats.is_value_error,
  )
  checks_drafts(is_datetime, name="date-time")
  checks_drafts(is_time, draft7="time", draft201909="time", draft202012="time")
  checks_drafts(is_regex, name="regex", raises=is_regex_error)
  checks_drafts(
    is_date,
    draft3="date",
    draft7="date",
    draft201909="date",
    draft202012="date",
    raises=@formats.is_value_error,
  )
  checks_drafts(is_draft3_time, draft3="time", raises=@formats.is_value_error)
  checks_drafts(is_css21_color, draft3="color", raises=@formats.is_value_error)
  checks_drafts(
    is_json_pointer,
    draft6="json-pointer",
    draft7="json-pointer",
    draft201909="json-pointer",
    draft202012="json-pointer",
    raises=@formats.is_json_pointer_exception,
  )
  checks_drafts(
    is_relative_json_pointer,
    draft7="relative-json-pointer",
    draft201909="relative-json-pointer",
    draft202012="relative-json-pointer",
    raises=@formats.is_json_pointer_exception,
  )
  checks_drafts(
    is_uri_template,
    draft6="uri-template",
    draft7="uri-template",
    draft201909="uri-template",
    draft202012="uri-template",
  )
  checks_drafts(
    is_duration,
    draft201909="duration",
    draft202012="duration",
    raises=@formats.is_duration_parsing_exception,
  )
  checks_drafts(
    is_uuid,
    draft201909="uuid",
    draft202012="uuid",
    raises=@formats.is_value_error,
  )
}
