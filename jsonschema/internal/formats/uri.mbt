///|
/// `rfc3986_validator.validate_rfc3986(url, rule=rule)` (rfc3986-validator
/// 0.1.1): whether `url` matches the RFC 3986 `URI` or `URI_reference` rule.
///
/// Like the library (`re.match` with `$`), a single trailing newline is
/// accepted. Raises `ValueError` for other rules.
pub fn validate_rfc3986(url : String, rule~ : String) -> Bool raise LibError {
  let pattern = match rule {
    "URI" => rfc3986_uri_pattern
    "URI_reference" => rfc3986_uri_reference_pattern
    _ => raise ValueError("Invalid rule")
  }
  @regex.search(pattern, url) catch {
    e => raise ValueError("cannot match \{rule}: \{e}")
  }
}

///|
/// `rfc3987_syntax.is_valid_syntax(term, value)` (rfc3987-syntax 1.1.0) for
/// the `iri` and `iri_reference` terms: whether `value` is derivable from
/// the library's RFC 3987 grammar.
pub fn rfc3987_syntax_is_valid(term : String, value : String) -> Bool raise LibError {
  let pattern = match term {
    "iri" => rfc3987_syntax_iri_pattern
    "iri_reference" => rfc3987_syntax_iri_reference_pattern
    _ => raise ValueError("unsupported term \{term}")
  }
  @regex.search(pattern, value) catch {
    e => raise ValueError("cannot match \{term}: \{e}")
  }
}
