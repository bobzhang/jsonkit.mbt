///|
fn is_ascii_digit(c : Int) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_hex_digit(c : Int) -> Bool {
  (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

///|
/// Split a code point array on a separator.
fn split_cps(cps : ArrayView[Int], sep : Int) -> Array[Array[Int]] {
  let parts = [[]]
  for c in cps {
    if c == sep {
      parts.push([])
    } else {
      parts[parts.length() - 1].push(c)
    }
  }
  parts
}

///|
/// `ipaddress.IPv4Address._ip_int_from_string` (Python 3.13).
fn ipv4_int(cps : ArrayView[Int]) -> Int64 raise LibError {
  if cps.length() == 0 {
    raise AddressValueError("Address cannot be empty")
  }
  let octets = split_cps(cps, '.')
  if octets.length() != 4 {
    raise AddressValueError("Expected 4 octets")
  }
  let mut value = 0L
  for octet in octets {
    if octet.length() == 0 {
      raise AddressValueError("Empty octet not permitted")
    }
    if !octet.iter().all(is_ascii_digit) {
      raise AddressValueError("Only decimal digits permitted")
    }
    if octet.length() > 3 {
      raise AddressValueError("At most 3 characters permitted")
    }
    if octet.length() > 1 && octet[0] == '0' {
      raise AddressValueError("Leading zeros are not permitted")
    }
    let mut v = 0
    for c in octet {
      v = v * 10 + (c - '0')
    }
    if v > 255 {
      raise AddressValueError("Octet \{v} (> 255) not permitted")
    }
    value = (value << 8) | v.to_int64()
  }
  value
}

///|
/// `ipaddress.IPv4Address(address)`.
pub fn ipv4_address(address : String) -> Unit raise LibError {
  let cps = @unicodedata.code_points(address)
  if cps.contains('/') {
    raise AddressValueError("Unexpected '/'")
  }
  ignore(ipv4_int(cps))
}

///|
/// `ipaddress.IPv6Address(address)`; returns the scope id, if any.
pub fn ipv6_address(address : String) -> String? raise LibError {
  let cps = @unicodedata.code_points(address)
  if cps.contains('/') {
    raise AddressValueError("Unexpected '/'")
  }
  // _split_scope_id
  let (addr, scope_id) = match cps.search('%') {
    None => (cps[:], None)
    Some(i) => {
      let scope = cps[i + 1:]
      if scope.length() == 0 || scope.contains('%') {
        raise AddressValueError("Invalid IPv6 address")
      }
      (cps[:i], Some(@unicodedata.from_code_points(scope)))
    }
  }
  ipv6_check(addr)
  scope_id
}

///|
/// `IPv6Address._ip_int_from_string` (validation only).
fn ipv6_check(ip : ArrayView[Int]) -> Unit raise LibError {
  if ip.length() == 0 {
    raise AddressValueError("Address cannot be empty")
  }
  if ip.length() > 45 {
    raise AddressValueError("At most 45 characters expected")
  }
  // split(':', maxsplit=9)
  let parts : Array[Array[Int]] = [[]]
  for c in ip {
    if c == ':' && parts.length() < 10 {
      parts.push([])
    } else {
      parts[parts.length() - 1].push(c)
    }
  }
  if parts.length() < 3 {
    raise AddressValueError("At least 3 parts expected")
  }
  if parts[parts.length() - 1].contains('.') {
    let last = parts.pop().unwrap()
    let v = ipv4_int(last)
    parts.push(
      @unicodedata.code_points(((v >> 16) & 0xFFFFL).to_string(radix=16)),
    )
    parts.push(@unicodedata.code_points((v & 0xFFFFL).to_string(radix=16)))
  }
  if parts.length() > 9 {
    raise AddressValueError("At most 8 colons permitted")
  }
  let mut skip_index : Int? = None
  for i in 1..<(parts.length() - 1) {
    if parts[i].length() == 0 {
      if skip_index is Some(_) {
        raise AddressValueError("At most one '::' permitted")
      }
      skip_index = Some(i)
    }
  }
  let n = parts.length()
  let (parts_hi, parts_lo) = match skip_index {
    Some(skip) => {
      let mut hi = skip
      let mut lo = n - skip - 1
      if parts[0].length() == 0 {
        hi -= 1
        if hi != 0 {
          raise AddressValueError("Leading ':' only permitted as part of '::'")
        }
      }
      if parts[n - 1].length() == 0 {
        lo -= 1
        if lo != 0 {
          raise AddressValueError("Trailing ':' only permitted as part of '::'")
        }
      }
      if 8 - (hi + lo) < 1 {
        raise AddressValueError("Expected at most 7 other parts with '::'")
      }
      (hi, lo)
    }
    None => {
      if n != 8 {
        raise AddressValueError("Exactly 8 parts expected without '::'")
      }
      if parts[0].length() == 0 {
        raise AddressValueError("Leading ':' only permitted as part of '::'")
      }
      if parts[n - 1].length() == 0 {
        raise AddressValueError("Trailing ':' only permitted as part of '::'")
      }
      (n, 0)
    }
  }
  let check_hextet = (h : Array[Int]) => {
    if !h.iter().all(is_hex_digit) {
      raise AddressValueError("Only hex digits permitted")
    }
    if h.length() > 4 {
      raise AddressValueError("At most 4 characters permitted")
    }
    if h.length() == 0 {
      // int('', 16)
      raise AddressValueError("invalid literal for int() with base 16: ''")
    }
  }
  for i in 0..<parts_hi {
    check_hextet(parts[i])
  }
  for i in (n - parts_lo)..<n {
    check_hextet(parts[i])
  }
}
