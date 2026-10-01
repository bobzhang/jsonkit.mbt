///|
const PUNY_CAP : Int64 = 0x7FFFFFFFFFFF

///|
fn puny_t(j : Int, bias : Int) -> Int {
  let res = 36 * (j + 1) - bias
  if res < 1 {
    1
  } else if res > 26 {
    26
  } else {
    res
  }
}

///|
fn puny_adapt(delta : Int64, first : Bool, numchars : Int) -> Int {
  let mut delta = if first { delta / 700L } else { delta / 2L }
  delta += delta / numchars.to_int64()
  let mut divisions = 0
  while delta > 455L {
    delta = delta / 35L
    divisions += 36
  }
  divisions + (36L * delta / (delta + 38L)).to_int()
}

///|
/// Python's `str.encode("punycode")` (RFC 3492) over code points.
pub fn punycode_encode(text : ArrayView[Int]) -> String {
  let digits = "abcdefghijklmnopqrstuvwxyz0123456789"
  let sb = StringBuilder()
  let mut basic = 0
  for c in text {
    if c < 0x80 {
      sb.write_char(Int::unsafe_to_char(c))
      basic += 1
    }
  }
  let extended = text.iter().filter(c => c >= 0x80).collect()
  extended.sort()
  if basic > 0 {
    sb.write_char('-')
  }
  let mut n = 0x80
  let mut delta = 0L
  let mut bias = 72
  let mut handled = basic
  let mut first = true
  let total = text.length()
  let mut idx = 0
  while handled < total {
    // next smallest code point >= n
    while idx < extended.length() && extended[idx] < n {
      idx += 1
    }
    let m = extended[idx]
    delta = delta + (m - n).to_int64() * (handled + 1).to_int64()
    n = m
    for c in text {
      if c < n {
        delta += 1L
      }
      if c == n {
        let mut q = delta
        for j = 0; ; j = j + 1 {
          let t = puny_t(j, bias)
          if q < t.to_int64() {
            break
          }
          let d = t.to_int64() + (q - t.to_int64()) % (36 - t).to_int64()
          sb.write_char(digits.get_char(d.to_int()).unwrap())
          q = (q - t.to_int64()) / (36 - t).to_int64()
        }
        sb.write_char(digits.get_char(q.to_int()).unwrap())
        bias = puny_adapt(delta, first, handled + 1)
        first = false
        delta = 0L
        handled += 1
      }
    }
    delta += 1L
    n += 1
  }
  sb.to_string()
}

///|
/// Python's `bytes.decode("punycode")` (strict) over an ASCII label.
pub fn punycode_decode(text : String) -> Array[Int] raise LibError {
  let cps = @unicodedata.code_points(text)
  let mut pos_dash = -1
  for i, c in cps {
    if c == '-' {
      pos_dash = i
    }
  }
  let (base, extended) = if pos_dash == -1 {
    ([], cps)
  } else {
    (cps[:pos_dash].to_owned(), cps[pos_dash + 1:].to_owned())
  }
  // .upper()
  let extended = extended.map(c => if c >= 'a' && c <= 'z' { c - 32 } else { c })
  let base = base
  let mut ch = 0x80L
  let mut pos = -1L
  let mut bias = 72
  let mut extpos = 0
  while extpos < extended.length() {
    // decode_generalized_number
    let mut result = 0L
    let mut w = 1L
    let mut j = 0
    let mut p = extpos
    for ;; {
      if p >= extended.length() {
        raise IDNAError("incomplete punycode string")
      }
      let c = extended[p]
      p += 1
      let digit = if c >= 0x41 && c <= 0x5A {
        c - 0x41
      } else if c >= 0x30 && c <= 0x39 {
        c - 22
      } else {
        raise IDNAError("Invalid extended code point")
      }
      let t = puny_t(j, bias)
      result = result + digit.to_int64() * w
      if result > PUNY_CAP {
        result = PUNY_CAP
      }
      if digit < t {
        break
      }
      w = w * (36 - t).to_int64()
      if w > PUNY_CAP {
        w = PUNY_CAP
      }
      j += 1
    }
    let delta = result
    pos = pos + delta + 1L
    if pos > PUNY_CAP {
      pos = PUNY_CAP
    }
    let len1 = (base.length() + 1).to_int64()
    ch = ch + pos / len1
    if ch > 0x10FFFFL {
      raise IDNAError("Invalid character")
    }
    pos = pos % len1
    base.insert(pos.to_int(), ch.to_int())
    bias = puny_adapt(delta, extpos == 0, base.length())
    extpos = p
  }
  base
}
