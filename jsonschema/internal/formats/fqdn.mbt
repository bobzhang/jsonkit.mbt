// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// A port of the `fqdn` Python package (fqdn 1.5/1.6, by ypcrts and
// contributors, MPL-2.0). Unlike the rest of this module (MIT), this file is
// covered by the MPL-2.0.

///|
/// Whether a (lowercased) code point matches `[-A-Z\d]` under Python's
/// `re.IGNORECASE` (Unicode digits, and the case-insensitive aliases of
/// ASCII letters).
fn fqdn_label_char(c : Int) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  c == '-' ||
  @unicodedata.is_decimal(c) ||
  c == 0x131 || // LATIN SMALL LETTER DOTLESS I
  c == 0x17F || // LATIN SMALL LETTER LONG S
  c == 0x212A // KELVIN SIGN
}

///|
/// Python `str.lower()` restricted to what matters for ASCII-oriented
/// checks: ASCII letters, KELVIN SIGN (to `k`) and LATIN CAPITAL LETTER I
/// WITH DOT ABOVE (to `i` + COMBINING DOT ABOVE). Other code points either
/// lowercase to non-ASCII characters or are kept as-is.
pub fn py_lower(cps : ArrayView[Int]) -> Array[Int] {
  let out = []
  for c in cps {
    if c >= 'A' && c <= 'Z' {
      out.push(c + 32)
    } else if c == 0x212A {
      out.push('k')
    } else if c == 0x130 {
      out.push('i')
      out.push(0x307)
    } else {
      out.push(c)
    }
  }
  out
}

///|
/// `fqdn.FQDN(fqdn, min_labels=min_labels).is_valid` (fqdn 1.5).
///
/// Raises `ValueError` for the empty string, like upstream.
pub fn fqdn_is_valid(fqdn : String, min_labels~ : Int) -> Bool raise LibError {
  if fqdn.length() == 0 {
    raise ValueError("fqdn must be str")
  }
  let s = py_lower(@unicodedata.code_points(fqdn))
  let mut length = s.length()
  if s[s.length() - 1] == '.' {
    length -= 1
  }
  if length > 253 {
    return false
  }
  // ^((?![-])[-A-Z\d]{1,63}(?<!-)[.])*(?!-)[-A-Z\d]{1,63}(?<!-)[.]?$
  // where `$` also matches before a trailing newline.
  let body = if s[s.length() - 1] == '\n' { s[:s.length() - 1] } else { s[:] }
  let body = if body.length() > 0 && body[body.length() - 1] == '.' {
    body[:body.length() - 1]
  } else {
    body
  }
  let labels = split_cps(body, '.')
  for label in labels {
    if label.length() < 1 || label.length() > 63 {
      return false
    }
    if label[0] == '-' || label[label.length() - 1] == '-' {
      return false
    }
    if !label.iter().all(fqdn_label_char) {
      return false
    }
  }
  // labels_count
  let has_terminal_dot = s[s.length() - 1] == '.'
  let dots = s.iter().filter(c => c == '.').count()
  let count = dots + (if has_terminal_dot { 0 } else { 1 })
  count >= min_labels
}
