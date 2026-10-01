///|
/// `jsonpointer.JsonPointer(pointer)`: raises `JsonPointerException` for
/// invalid pointers.
pub fn json_pointer(pointer : String) -> Unit raise LibError {
  // _RE_INVALID_ESCAPE = re.compile('(~[^01]|~$)')
  let n = pointer.length()
  for i in 0..<n {
    if pointer.code_unit_at(i) == '~' {
      if i + 1 >= n || !(pointer.code_unit_at(i + 1) is ('0' | '1')) {
        raise JsonPointerException("Found invalid escape")
      }
    }
  }
  if n > 0 && pointer.code_unit_at(0) != '/' {
    raise JsonPointerException("Location must start with /")
  }
}

///|
/// python-jsonschema's `is_relative_json_pointer` body.
pub fn relative_json_pointer(instance : String) -> Bool raise LibError {
  if instance.length() == 0 {
    return false
  }
  // instance.lstrip(string.digits)
  let mut i = 0
  while i < instance.length() && instance.code_unit_at(i) is ('0'..='9') {
    i += 1
  }
  let prefix = instance.unsafe_substring(start=0, end=i)
  let rest = instance.unsafe_substring(start=i, end=instance.length())
  if prefix.length() == 0 {
    return false
  }
  if prefix.length() > 1 && prefix.code_unit_at(0) == '0' {
    return false
  }
  if rest == "#" {
    return true
  }
  json_pointer(rest)
  true
}
