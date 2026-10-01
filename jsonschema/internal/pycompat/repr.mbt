///|
const HEX_DIGITS : String = "0123456789abcdef"

///|
fn write_hex(sb : StringBuilder, v : Int, width : Int) -> Unit {
  for i = width - 1; i >= 0; i = i - 1 {
    sb.write_char(HEX_DIGITS.get_char((v >> (4 * i)) & 0xF).unwrap())
  }
}

///|
/// Python `repr(s)` for a `str`.
pub fn repr_string(s : StringView) -> String {
  let sb = StringBuilder()
  write_repr_string(sb, s)
  sb.to_string()
}

///|
fn write_repr_string(sb : StringBuilder, s : StringView) -> Unit {
  let cps = @unicodedata.code_points(s)
  let has_single = cps.contains('\'')
  let has_double = cps.contains('"')
  let quote = if has_single && !has_double { '"' } else { '\'' }
  sb.write_char(quote)
  for cp in cps {
    if cp == quote.to_int() || cp == '\\' {
      sb.write_char('\\')
      sb.write_char(Int::unsafe_to_char(cp))
    } else if cp == '\t' {
      sb.write_string("\\t")
    } else if cp == '\n' {
      sb.write_string("\\n")
    } else if cp == '\r' {
      sb.write_string("\\r")
    } else if cp < 0x20 || cp == 0x7F {
      sb.write_string("\\x")
      write_hex(sb, cp, 2)
    } else if cp < 0x7F {
      sb.write_char(Int::unsafe_to_char(cp))
    } else if @unicodedata.is_printable(cp) {
      @unicodedata.write_code_point(sb, cp)
    } else if cp <= 0xFF {
      sb.write_string("\\x")
      write_hex(sb, cp, 2)
    } else if cp <= 0xFFFF {
      sb.write_string("\\u")
      write_hex(sb, cp, 4)
    } else {
      sb.write_string("\\U")
      write_hex(sb, cp, 8)
    }
  }
  sb.write_char(quote)
}

///|
/// Shortest round-trip decimal digits of a positive finite double, together
/// with the decimal point position: `d = 0.DIGITS * 10^decpt`.
fn shortest_digits(d : Double) -> (String, Int) {
  let s = d.to_string()
  let (mantissa, exp) = match s.find("e") {
    Some(i) => {
      let e = s.unsafe_substring(start=i + 1, end=s.length())
      let e = if e.has_prefix("+") {
        e.unsafe_substring(start=1, end=e.length())
      } else {
        e
      }
      (
        s.unsafe_substring(start=0, end=i),
        @string.parse_int(e) catch {
          _ => 0
        },
      )
    }
    None => (s, 0)
  }
  let (int_part, frac_part) = match mantissa.find(".") {
    Some(i) =>
      (
        mantissa.unsafe_substring(start=0, end=i),
        mantissa.unsafe_substring(start=i + 1, end=mantissa.length()),
      )
    None => (mantissa, "")
  }
  let mut digits = int_part + frac_part
  let mut decpt = int_part.length() + exp
  // strip leading zeros
  let mut lead = 0
  while lead < digits.length() - 1 && digits.code_unit_at(lead) == '0' {
    lead += 1
  }
  digits = digits.unsafe_substring(start=lead, end=digits.length())
  decpt -= lead
  // strip trailing zeros
  let mut end = digits.length()
  while end > 1 && digits.code_unit_at(end - 1) == '0' {
    end -= 1
  }
  digits = digits.unsafe_substring(start=0, end~)
  (digits, decpt)
}

///|
/// Python `repr(f)` for a `float`.
pub fn repr_float(d : Double) -> String {
  if d.is_nan() {
    return "nan"
  }
  if d.is_pos_inf() {
    return "inf"
  }
  if d.is_neg_inf() {
    return "-inf"
  }
  let negative = d < 0.0 || (d == 0.0 && 1.0 / d < 0.0)
  let sign = if negative { "-" } else { "" }
  if d == 0.0 {
    return sign + "0.0"
  }
  let (digits, decpt) = shortest_digits(d.abs())
  let n = digits.length()
  let body = if decpt <= -4 || decpt > 16 {
    let exp = decpt - 1
    let mant = if n == 1 {
      digits
    } else {
      digits.unsafe_substring(start=0, end=1) +
      "." +
      digits.unsafe_substring(start=1, end=n)
    }
    let e = exp.abs()
    let es = if e < 10 { "0" + e.to_string() } else { e.to_string() }
    mant + (if exp < 0 { "e-" } else { "e+" }) + es
  } else if decpt <= 0 {
    "0." + "0".repeat(-decpt) + digits
  } else if decpt >= n {
    digits + "0".repeat(decpt - n) + ".0"
  } else {
    digits.unsafe_substring(start=0, end=decpt) +
    "." +
    digits.unsafe_substring(start=decpt, end=n)
  }
  sign + body
}

///|
/// Python `repr(n)` for an `int` JSON number.
pub fn repr_int(j : Json) -> String {
  match j {
    Number(_, repr=Some(r)) if !repr_is_float(r) => normalize_int_token(r)
    Number(d, ..) =>
      if d.abs() < 9.0e15 {
        d.to_int64().to_string()
      } else {
        bigint_of_whole_double(d).to_string()
      }
    _ => ""
  }
}

///|
/// Python `repr(x)` of the Python object a JSON value stands for
/// (`json.loads` semantics): `None`, `True`, `'str'`, `[1, 2.0]`,
/// `{'a': 1}`.
pub fn repr(j : Json) -> String {
  let sb = StringBuilder()
  write_repr(sb, j)
  sb.to_string()
}

///|
pub fn write_repr(sb : StringBuilder, j : Json) -> Unit {
  match j {
    Null => sb.write_string("None")
    True => sb.write_string("True")
    False => sb.write_string("False")
    String(s) => write_repr_string(sb, s)
    Number(d, ..) =>
      if is_int(j) {
        sb.write_string(repr_int(j))
      } else {
        sb.write_string(repr_float(d))
      }
    Array(xs) => {
      sb.write_char('[')
      for i, x in xs {
        if i > 0 {
          sb.write_string(", ")
        }
        write_repr(sb, x)
      }
      sb.write_char(']')
    }
    Object(m) => {
      sb.write_char('{')
      let mut first = true
      for k, v in m {
        if !first {
          sb.write_string(", ")
        }
        first = false
        write_repr_string(sb, k)
        sb.write_string(": ")
        write_repr(sb, v)
      }
      sb.write_char('}')
    }
  }
}
