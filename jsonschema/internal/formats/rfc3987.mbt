///|
/// `rfc3987.parse(string, rule=rule)` (with the standard library `re`, as
/// upstream's tests run it): raises `ValueError` when `string` does not
/// match the RFC 3986 / RFC 3987 grammar rule.
///
/// `rule` is one of `"URI"`, `"URI_reference"`, `"IRI"`, `"IRI_reference"`.
pub fn rfc3987_parse(s : String, rule~ : String) -> Unit raise LibError {
  let body = match rule {
    "URI" => rfc3987_uri_pattern
    "URI_reference" => rfc3987_uri_reference_pattern
    "IRI" => rfc3987_iri_pattern
    "IRI_reference" => rfc3987_iri_reference_pattern
    _ => raise ValueError(rule)
  }
  let matched = @regex.search("^" + body + "$", s) catch {
    e => raise ValueError("cannot match \{rule}: \{e}")
  }
  if !matched {
    raise ValueError("\{s.escape()} is not a valid '\{rule}'.")
  }
}
