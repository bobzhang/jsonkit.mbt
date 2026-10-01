///|
/// Python's `ipaddress.IPv4Address` string validation (strict: exactly four
/// decimal octets, no leading zeros, each at most 255).
fn is_ipv4_address(s : String) -> Bool {
  if s == "" || s.contains("/") {
    return false
  }
  let octets = split_all(s, ".")
  if octets.length() != 4 {
    return false
  }
  for octet in octets {
    if octet == "" || octet.length() > 3 {
      return false
    }
    for i in 0..<octet.length() {
      if !is_ascii_digit(octet[i]) {
        return false
      }
    }
    if octet != "0" && octet[0] == '0' {
      return false
    }
    let mut value = 0
    for i in 0..<octet.length() {
      value = value * 10 + (octet[i].to_int() - '0'.to_int())
    }
    if value > 255 {
      return false
    }
  }
  true
}

///|
fn is_hextet(s : String) -> Bool {
  if s == "" || s.length() > 4 {
    return false
  }
  for i in 0..<s.length() {
    if !is_ascii_hex(s[i]) {
      return false
    }
  }
  true
}

///|
/// Python's `ipaddress.IPv6Address` string validation, including an optional
/// `%scope_id` suffix and an embedded trailing IPv4 address.
fn is_ipv6_address(s : String) -> Bool {
  let (addr, has_scope, scope_id) = partition(s, "%")
  if has_scope && (scope_id == "" || scope_id.contains("%")) {
    return false
  }
  if addr == "" || addr.contains("/") {
    return false
  }
  let hextet_count = 8
  let parts = split_all(addr, ":")
  if parts.length() < 3 {
    return false
  }
  if parts[parts.length() - 1].contains(".") {
    let v4 = parts.pop().unwrap()
    if !is_ipv4_address(v4) {
      return false
    }
    // Two hextets stand in for the IPv4 address.
    parts.push("0")
    parts.push("0")
  }
  if parts.length() > hextet_count + 1 {
    return false
  }
  let mut skip_index : Int? = None
  for i in 1..<(parts.length() - 1) {
    if parts[i] == "" {
      if skip_index is Some(_) {
        return false
      }
      skip_index = Some(i)
    }
  }
  let (parts_hi, parts_lo) = match skip_index {
    Some(skip) => {
      let mut parts_hi = skip
      let mut parts_lo = parts.length() - skip - 1
      if parts[0] == "" {
        parts_hi -= 1
        if parts_hi != 0 {
          return false
        }
      }
      if parts[parts.length() - 1] == "" {
        parts_lo -= 1
        if parts_lo != 0 {
          return false
        }
      }
      if hextet_count - (parts_hi + parts_lo) < 1 {
        return false
      }
      (parts_hi, parts_lo)
    }
    None => {
      if parts.length() != hextet_count {
        return false
      }
      if parts[0] == "" || parts[parts.length() - 1] == "" {
        return false
      }
      (parts.length(), 0)
    }
  }
  for i in 0..<parts_hi {
    if !is_hextet(parts[i]) {
      return false
    }
  }
  for i in (parts.length() - parts_lo)..<parts.length() {
    if !is_hextet(parts[i]) {
      return false
    }
  }
  true
}
