///|
/// `isoduration.parser.util.is_number`: `[+\-0-9.,eE]`.
fn iso_is_number(c : Int) -> Bool {
  c is ('+' | '-' | '.' | ',' | 'e' | 'E') || (c >= '0' && c <= '9')
}

///|
/// `ch.isalpha() and ch.lower() != "e"`.
fn iso_is_letter(c : Int) -> Bool {
  @unicodedata.is_alpha(c) && c != 'e' && c != 'E'
}

///|
/// `Decimal(tmp_value)` for strings over `[+\-0-9.eE]`; returns whether the
/// value is non-zero.
fn iso_decimal(s : Array[Int]) -> Bool raise LibError {
  // [+-]? (digits ('.' digits?)? | '.' digits) ([eE] [+-]? digits)?
  let n = s.length()
  let mut i = 0
  if i < n && s[i] is ('+' | '-') {
    i += 1
  }
  let mut digits = 0
  let mut nonzero = false
  while i < n && s[i] >= '0' && s[i] <= '9' {
    if s[i] != '0' {
      nonzero = true
    }
    digits += 1
    i += 1
  }
  if i < n && s[i] == '.' {
    i += 1
    while i < n && s[i] >= '0' && s[i] <= '9' {
      if s[i] != '0' {
        nonzero = true
      }
      digits += 1
      i += 1
    }
  }
  if digits == 0 {
    raise DurationParsingException("Value could not be parsed as decimal")
  }
  if i < n && s[i] is ('e' | 'E') {
    i += 1
    if i < n && s[i] is ('+' | '-') {
      i += 1
    }
    let start = i
    while i < n && s[i] >= '0' && s[i] <= '9' {
      i += 1
    }
    if i == start {
      raise DurationParsingException("Value could not be parsed as decimal")
    }
  }
  if i != n {
    raise DurationParsingException("Value could not be parsed as decimal")
  }
  nonzero
}

///|
/// `parse_designator`: pops designators until `target`.
fn iso_designator(designators : Array[Int], target : Int) -> Unit raise LibError {
  while designators.length() > 0 {
    let key = designators.remove(0)
    if key == target {
      return
    }
  }
  raise DurationParsingException(
    "Wrong designator, or designator in the wrong order",
  )
}

///|
/// `isoduration.parse_duration(duration_str)`: raises
/// `DurationParsingException` for strings it cannot parse.
///
/// The `arrow`-based datetime-style duration path (`P0003-06-04T12:30:05`)
/// is approximated: such strings never end in a designator, so python-
/// jsonschema rejects them whether or not `arrow` can parse them.
pub fn parse_duration(duration_str : String) -> Unit raise LibError {
  let cps = @unicodedata.code_points(duration_str)
  if cps.length() < 2 {
    raise DurationParsingException("No duration information provided")
  }
  let mut beginning = 1
  let first = cps[0]
  if first == '+' || first == '-' {
    beginning += 1
  }
  if beginning - 1 >= cps.length() || cps[beginning - 1] != 'P' {
    raise DurationParsingException("No prefix provided")
  }
  let date_str = cps[beginning:].to_owned()
  // parse_date_duration
  let designators : Array[Int] = ['Y', 'M', 'D', 'W']
  let mut any_nonzero = false
  let tmp_value : Array[Int] = []
  for idx, ch in date_str {
    if ch == 'T' {
      if tmp_value.length() > 0 && tmp_value == date_str[:idx].to_owned() {
        raise DurationParsingException(
          "Value could not be parsed as datetime",
        )
      }
      let time_str = date_str[idx + 1:]
      if time_str.length() == 0 {
        raise DurationParsingException("Wanted time, no time provided")
      }
      parse_time_duration(time_str)
      return
    }
    if iso_is_letter(ch) {
      iso_designator(designators, ch)
      let nonzero = iso_decimal(tmp_value)
      if ch == 'W' && any_nonzero {
        raise DurationParsingException(
          "Week is incompatible with any other date designator",
        )
      }
      if nonzero {
        any_nonzero = true
      }
      tmp_value.clear()
      continue
    }
    if iso_is_number(ch) {
      tmp_value.push(if ch == ',' { '.' } else { ch })
      continue
    }
    raise DurationParsingException("Token not recognizable")
  }
}

///|
fn parse_time_duration(time_str : ArrayView[Int]) -> Unit raise LibError {
  let designators : Array[Int] = ['H', 'M', 'S']
  let tmp_value : Array[Int] = []
  for ch in time_str {
    if iso_is_letter(ch) {
      iso_designator(designators, ch)
      ignore(iso_decimal(tmp_value))
      tmp_value.clear()
      continue
    }
    if iso_is_number(ch) {
      tmp_value.push(if ch == ',' { '.' } else { ch })
      continue
    }
    raise DurationParsingException("Token not recognizable")
  }
}
