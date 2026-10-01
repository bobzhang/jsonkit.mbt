///|
/// `str(UUID(instance)) == instance.lower()`: raises `ValueError` for
/// strings `UUID` cannot parse.
pub fn uuid_round_trips(instance : String) -> Bool raise LibError {
  let cps = @unicodedata.code_points(instance)
  // UUID(hex): strip 'urn:' / 'uuid:', braces and dashes; 32 hex digits
  let s = instance.replace_all(old="urn:", new="").replace_all(old="uuid:", new="")
  let s = s.trim(chars="{}").to_owned().replace_all(old="-", new="")
  if @unicodedata.py_len(s) != 32 {
    raise ValueError("badly formed hexadecimal UUID string")
  }
  // int(hex, 16) also accepts a sign, underscores and surrounding
  // whitespace; such spellings never round-trip, so only exact hex matters.
  let lower = py_lower(cps)
  if lower.length() != 36 {
    return false
  }
  for i, c in lower {
    let ok = if i == 8 || i == 13 || i == 18 || i == 23 {
      c == '-'
    } else {
      (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')
    }
    if !ok {
      return false
    }
  }
  true
}

///|
/// `webcolors.name_to_hex(name)` / `webcolors.normalize_hex(name.lower())`
/// as used by python-jsonschema's draft 3 `color` checker: raises
/// `ValueError` if `instance` is neither a CSS3 color name nor a hex color.
pub fn css_color(instance : String) -> Unit raise LibError {
  let lower = @unicodedata.from_code_points(
    py_lower(@unicodedata.code_points(instance)),
  )
  if css3_color_names.contains(lower) {
    return
  }
  // _HEX_COLOR_RE = re.compile(r"^#([a-fA-F0-9]{3}|[a-fA-F0-9]{6})$")
  let body = if lower.has_suffix("\n") {
    lower.unsafe_substring(start=0, end=lower.length() - 1)
  } else {
    lower
  }
  let ok = body.has_prefix("#") &&
    (body.length() == 4 || body.length() == 7) &&
    body.iter().drop(1).all(c => is_hex_digit(c.to_int()))
  if !ok {
    raise ValueError("\{instance} is not a valid hexadecimal color value.")
  }
}
