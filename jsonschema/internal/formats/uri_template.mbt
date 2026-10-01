///|
fn ut_var_start(c : Int) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_'
}

///|
fn ut_variable(spec : ArrayView[Int]) -> Unit raise LibError {
  // `var_spec[0:1] not in Charset.VAR_START` (substring test: "" passes)
  if spec.length() > 0 && !ut_var_start(spec[0]) {
    raise ValueError("Bad variable")
  }
  let mut var_spec = spec
  match var_spec.search('=') {
    Some(i) => var_spec = var_spec[:i]
    None => ()
  }
  match var_spec.search(':') {
    Some(i) => {
      let max_length = var_spec[i + 1:]
      var_spec = var_spec[:i]
      if max_length.length() > 0 && max_length.length() < 4 {
        let mut v = 0
        for d in max_length {
          if !(d >= '0' && d <= '9') {
            raise ValueError("Bad variable")
          }
          v = v * 10 + (d - '0')
        }
        if v == 0 {
          raise ValueError("Bad variable")
        }
      } else {
        raise ValueError("Bad variable")
      }
    }
    None =>
      if var_spec.length() == 0 {
        // var_spec[-1] raises IndexError
        raise ValueError("Bad variable")
      } else if var_spec[var_spec.length() - 1] == '*' {
        var_spec = var_spec[:var_spec.length() - 1]
      } else if var_spec.length() >= 2 &&
        var_spec[var_spec.length() - 2] == '[' &&
        var_spec[var_spec.length() - 1] == ']' {
        var_spec = var_spec[:var_spec.length() - 2]
      }
  }
  let n = var_spec.length()
  for index = 0; index < n; {
    let c = var_spec[index]
    if c == '%' &&
      index + 2 < n &&
      is_hex_digit(var_spec[index + 1]) &&
      is_hex_digit(var_spec[index + 2]) {
      continue index + 3
    } else if ut_var_start(c) || c == '.' || c == '/' {
      continue index + 1
    } else {
      raise ValueError("Bad variable")
    }
  }
}

///|
fn ut_expression(variables : ArrayView[Int]) -> Unit raise LibError {
  let mut vars = variables
  if vars.length() > 0 &&
    vars[vars.length() - 1] is (',' | '.' | '/' | ';' | '&') {
    vars = vars[:vars.length() - 1]
  }
  for v in split_cps(vars, ',') {
    ut_variable(v)
  }
}

///|
/// `uri_template.validate(template)` (uri-template 1.3).
pub fn uri_template_validate(template : String) -> Bool {
  let cps = @unicodedata.code_points(template)
  // re.split(r'(\{[^\}]*\})', template)
  let parts : Array[(Bool, ArrayView[Int])] = []
  let mut start = 0
  let n = cps.length()
  for i = 0; i < n; {
    if cps[i] == '{' {
      let mut j = i + 1
      while j < n && cps[j] != '}' {
        j += 1
      }
      if j < n {
        parts.push((false, cps[start:i]))
        parts.push((true, cps[i:j + 1]))
        start = j + 1
        continue j + 1
      }
    }
    continue i + 1
  }
  parts.push((false, cps[start:]))
  try {
    for item in parts {
      let (is_expansion, part) = item
      if part.length() == 0 {
        continue
      }
      if is_expansion {
        let expansion = part[1:part.length() - 1]
        if simple_expansion(expansion) {
          ut_expression(expansion)
        } else {
          match part[1] {
            '+' | '#' | '.' | '/' | ';' | '?' | '&' =>
              ut_expression(expansion[1:])
            ',' =>
              if part[2] == '+' {
                ut_expression(expansion[2:])
              } else {
                ut_expression(expansion[1:])
              }
            _ => raise ValueError("Bad expansion")
          }
        }
      } else if part.contains('{') || part.contains('}') {
        raise ValueError("Bad expansion")
      }
    }
    true
  } catch {
    _ => false
  }
}

///|
/// `re.match('^([a-zA-Z0-9_]|%[0-9a-fA-F][0-9a-fA-F]).*$', expansion)`.
fn simple_expansion(e : ArrayView[Int]) -> Bool {
  let rest = if e.length() > 0 && ut_var_start(e[0]) {
    e[1:]
  } else if e.length() >= 3 &&
    e[0] == '%' &&
    is_hex_digit(e[1]) &&
    is_hex_digit(e[2]) {
    e[3:]
  } else {
    return false
  }
  // `.*$`: no newline, except possibly a single trailing one
  match rest.search('\n') {
    None => true
    Some(i) => i == rest.length() - 1
  }
}
