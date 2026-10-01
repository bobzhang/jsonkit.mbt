///|
fn is_leap(year : Int) -> Bool {
  year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

///|
/// `calendar.monthrange(year, month)[1]`.
fn days_in_month(year : Int, month : Int) -> Int {
  match month {
    2 => if is_leap(year) { 29 } else { 28 }
    4 | 6 | 9 | 11 => 30
    _ => 31
  }
}

///|
fn parse_ascii_int(s : String) -> Int {
  let mut v = 0
  for c in s {
    v = v * 10 + (c.to_int() - '0')
  }
  v
}

///|
/// `rfc3339_validator.validate_rfc3339(date_string)`.
pub fn validate_rfc3339(date_string : String) -> Bool raise {
  let pattern = @regex.compile(
    "(?a)^(\\d{4})-(0[1-9]|1[0-2])-(\\d{2})T(?:[01]\\d|2[0123]):(?:[0-5]\\d):(?:[0-5]\\d)(?:\\.\\d+)?(?:Z|[+-](?:[01]\\d|2[0123]):[0-5]\\d)$",
  )
  guard pattern.search_groups(date_string) is Some(groups) else {
    return false
  }
  let year = parse_ascii_int(groups[1].unwrap())
  let month = parse_ascii_int(groups[2].unwrap())
  let day = parse_ascii_int(groups[3].unwrap())
  if year == 0 {
    return false
  }
  1 <= day && day <= days_in_month(year, month)
}

///|
/// Python's `str.upper()` restricted to ASCII letters (sufficient for the
/// ASCII-only RFC 3339 grammar).
pub fn ascii_upper(s : String) -> String {
  let sb = StringBuilder()
  for c in s {
    if c >= 'a' && c <= 'z' {
      sb.write_char(Int::unsafe_to_char(c.to_int() - 32))
    } else {
      sb.write_char(c)
    }
  }
  sb.to_string()
}

///|
/// `bool(_RE_DATE.fullmatch(instance) and date.fromisoformat(instance))`:
/// raises `ValueError` for out-of-range dates.
pub fn is_iso_date(instance : String) -> Bool raise LibError {
  // ^\d{4}-\d{2}-\d{2}$ (re.ASCII), full match
  let cps = @unicodedata.code_points(instance)
  if cps.length() != 10 {
    return false
  }
  for i, c in cps {
    let ok = if i == 4 || i == 7 { c == '-' } else { c >= '0' && c <= '9' }
    if !ok {
      return false
    }
  }
  let year = parse_ascii_int(instance.unsafe_substring(start=0, end=4))
  let month = parse_ascii_int(instance.unsafe_substring(start=5, end=7))
  let day = parse_ascii_int(instance.unsafe_substring(start=8, end=10))
  if year < 1 {
    raise ValueError("year \{year} is out of range")
  }
  if month < 1 || month > 12 {
    raise ValueError("month must be in 1..12")
  }
  if day < 1 || day > days_in_month(year, month) {
    raise ValueError("day is out of range for month")
  }
  true
}

///|
/// `datetime.strptime(instance, "%H:%M:%S")`: raises `ValueError` when the
/// instance does not match.
pub fn strptime_hms(instance : String) -> Unit raise LibError {
  let pattern = @regex.compile(
    "(?ai)^(2[0-3]|[0-1]\\d|\\d):([0-5]\\d|\\d):(6[0-1]|[0-5]\\d|\\d)",
  ) catch {
    _ => panic()
  }
  let groups = pattern.search_groups(instance)
  guard groups is Some(groups) else {
    raise ValueError("time data does not match format '%H:%M:%S'")
  }
  if groups[0].unwrap().length() != instance.length() {
    raise ValueError("unconverted data remains")
  }
  if parse_ascii_int(groups[3].unwrap()) > 59 {
    raise ValueError("second must be in 0..59")
  }
}
