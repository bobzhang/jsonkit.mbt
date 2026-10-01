// A port of the parts of `idna.core` (idna 3.x) used by
// `idna.encode(s)` with its default arguments (no UTS #46 mapping).

///|
const IDNA_MAX_INPUT_LENGTH : Int = 1024

///|
fn is_dot(c : Int) -> Bool {
  c is ('.' | 0x3002 | 0xFF0E | 0xFF61)
}

///|
fn bidi(cp : Int) -> String {
  @unicodedata.bidirectional(cp)
}

///|
fn check_bidi(label : Array[Int]) -> Unit raise LibError {
  if label.length() > IDNA_MAX_INPUT_LENGTH {
    raise IDNAError("Label too long")
  }
  let mut bidi_label = false
  for cp in label {
    let direction = bidi(cp)
    if direction == "" {
      raise IDNAError("Unknown directionality in label")
    }
    if direction is ("R" | "AL" | "AN") {
      bidi_label = true
    }
  }
  if !bidi_label {
    return
  }
  // Bidi rule 1
  let rtl = match bidi(label[0]) {
    "R" | "AL" => true
    "L" => false
    _ =>
      raise IDNAError(
        "First codepoint in label must be directionality L, R or AL",
      )
  }
  let mut valid_ending = false
  let mut number_type : String? = None
  for cp in label {
    let direction = bidi(cp)
    if rtl {
      // Bidi rule 2
      if !(direction
        is ("R" | "AL" | "AN" | "EN" | "ES" | "CS" | "ET" | "ON" | "BN" | "NSM")) {
        raise IDNAError(
          "Invalid direction for codepoint in a right-to-left label",
        )
      }
      // Bidi rule 3
      if direction is ("R" | "AL" | "EN" | "AN") {
        valid_ending = true
      } else if direction != "NSM" {
        valid_ending = false
      }
      // Bidi rule 4
      if direction is ("AN" | "EN") {
        match number_type {
          None => number_type = Some(direction)
          Some(t) =>
            if t != direction {
              raise IDNAError(
                "Can not mix numeral types in a right-to-left label",
              )
            }
        }
      }
    } else {
      // Bidi rule 5
      if !(direction is ("L" | "EN" | "ES" | "CS" | "ET" | "ON" | "BN" | "NSM")) {
        raise IDNAError(
          "Invalid direction for codepoint in a left-to-right label",
        )
      }
      // Bidi rule 6
      if direction is ("L" | "EN") {
        valid_ending = true
      } else if direction != "NSM" {
        valid_ending = false
      }
    }
  }
  if !valid_ending {
    raise IDNAError("Label ends with illegal codepoint directionality")
  }
}

///|
/// `_combining_class`: raises (a `ValueError` upstream) for unnamed code
/// points of class 0.
fn combining_class(cp : Int) -> Int? {
  let v = @unicodedata.combining(cp)
  if v == 0 && !@unicodedata.has_name(cp) {
    None
  } else {
    Some(v)
  }
}

///|
fn valid_contextj(label : Array[Int], pos : Int) -> Bool raise LibError {
  let virama = (cp : Int) => {
    match combining_class(cp) {
      Some(v) => v == 9
      None => raise IDNAError("Unknown codepoint adjacent to joiner")
    }
  }
  let cp_value = label[pos]
  if cp_value == 0x200C {
    if pos > 0 && virama(label[pos - 1]) {
      return true
    }
    let mut ok = false
    for i = pos - 1; i >= 0; i = i - 1 {
      let jt = @unicodedata.idna_joining_type(label[i])
      if jt == Some("T") {
        continue
      }
      if jt is Some("L" | "D") {
        ok = true
      }
      break
    }
    if !ok {
      return false
    }
    ok = false
    for i in (pos + 1)..<label.length() {
      let jt = @unicodedata.idna_joining_type(label[i])
      if jt == Some("T") {
        continue
      }
      if jt is Some("R" | "D") {
        ok = true
      }
      break
    }
    return ok
  }
  if cp_value == 0x200D {
    return pos > 0 && virama(label[pos - 1])
  }
  false
}

///|
fn valid_contexto(label : Array[Int], pos : Int) -> Bool {
  let cp_value = label[pos]
  let n = label.length()
  if cp_value == 0x00B7 {
    return 0 < pos &&
      pos < n - 1 &&
      label[pos - 1] == 0x6C &&
      label[pos + 1] == 0x6C
  }
  if cp_value == 0x0375 {
    if pos < n - 1 && n > 1 {
      return @unicodedata.idna_is_script(label[pos + 1], "Greek")
    }
    return false
  }
  if cp_value == 0x05F3 || cp_value == 0x05F4 {
    if pos > 0 {
      return @unicodedata.idna_is_script(label[pos - 1], "Hebrew")
    }
    return false
  }
  if cp_value == 0x30FB {
    for cp in label {
      if cp == 0x30FB {
        continue
      }
      if @unicodedata.idna_is_script(cp, "Hiragana") ||
        @unicodedata.idna_is_script(cp, "Katakana") ||
        @unicodedata.idna_is_script(cp, "Han") {
        return true
      }
    }
    return false
  }
  if cp_value >= 0x660 && cp_value <= 0x669 {
    return !label.iter().any(cp => cp >= 0x6F0 && cp <= 0x6F9)
  }
  if cp_value >= 0x6F0 && cp_value <= 0x6F9 {
    return !label.iter().any(cp => cp >= 0x660 && cp <= 0x669)
  }
  false
}

///|
fn check_label(label : Array[Int]) -> Unit raise LibError {
  if label.length() > IDNA_MAX_INPUT_LENGTH {
    raise IDNAError("Label too long")
  }
  if label.length() == 0 {
    raise IDNAError("Empty Label")
  }
  if label.length() > 254 {
    raise IDNAError("Label too long")
  }
  // check_nfc
  if @unicodedata.nfc(label) != label {
    raise IDNAError("Label must be in Normalization Form C")
  }
  // check_hyphen_ok
  if label.length() >= 4 && label[2] == '-' && label[3] == '-' {
    raise IDNAError("Label has disallowed hyphens in 3rd and 4th position")
  }
  if label[0] == '-' || label[label.length() - 1] == '-' {
    raise IDNAError("Label must not start or end with a hyphen")
  }
  // check_initial_combiner
  if @unicodedata.is_mark(label[0]) {
    raise IDNAError("Label begins with an illegal combining character")
  }
  for pos, cp in label {
    if @unicodedata.idna_is_pvalid(cp) {
      continue
    }
    if @unicodedata.idna_is_contextj(cp) {
      if !valid_contextj(label, pos) {
        raise IDNAError("Joiner not allowed")
      }
    } else if @unicodedata.idna_is_contexto(cp) {
      if !valid_contexto(label, pos) {
        raise IDNAError("Codepoint not allowed")
      }
    } else {
      raise IDNAError("Codepoint not allowed")
    }
  }
  check_bidi(label)
}

///|
/// `idna.ulabel` for an ASCII label.
fn ulabel_ascii(label : Array[Int]) -> Unit raise LibError {
  if label.length() > IDNA_MAX_INPUT_LENGTH {
    raise IDNAError("Label too long")
  }
  let lower = label.map(c => if c >= 'A' && c <= 'Z' { c + 32 } else { c })
  if lower.length() >= 4 &&
    lower[0] == 'x' &&
    lower[1] == 'n' &&
    lower[2] == '-' &&
    lower[3] == '-' {
    let rest = lower[4:].to_owned()
    if rest.length() == 0 {
      raise IDNAError("Malformed A-label, no Punycode eligible content found")
    }
    if rest[rest.length() - 1] == '-' {
      raise IDNAError("A-label must not end with a hyphen")
    }
    let decoded = punycode_decode(@unicodedata.from_code_points(rest))
    if @unicodedata.code_points(punycode_encode(decoded)) != rest {
      raise IDNAError(
        "A-label is not the canonical Punycode encoding of its U-label",
      )
    }
    check_label(decoded)
  } else {
    check_label(lower)
  }
}

///|
/// `idna.alabel(label)`; returns the encoded length.
fn alabel(label : Array[Int]) -> Int raise LibError {
  if label.length() > IDNA_MAX_INPUT_LENGTH {
    raise IDNAError("Label too long")
  }
  if label.iter().all(c => c < 0x80) {
    ulabel_ascii(label)
    if label.length() > 63 {
      raise IDNAError("Label too long")
    }
    return label.length()
  }
  check_label(label)
  let encoded = 4 + punycode_encode(label).length()
  if encoded > 63 {
    raise IDNAError("Label too long")
  }
  encoded
}

///|
/// `idna.encode(s)` (default arguments): raises `IDNAError` for names that
/// are not valid IDNA 2008 host names.
pub fn idna_encode(s : String) -> Unit raise LibError {
  let cps = @unicodedata.code_points(s)
  if cps.length() > IDNA_MAX_INPUT_LENGTH {
    raise IDNAError("Domain too long")
  }
  if cps.length() > 254 {
    raise IDNAError("Domain too long")
  }
  let labels : Array[Array[Int]] = [[]]
  for c in cps {
    if is_dot(c) {
      labels.push([])
    } else {
      labels[labels.length() - 1].push(c)
    }
  }
  if labels.length() == 1 && labels[0].length() == 0 {
    raise IDNAError("Empty domain")
  }
  let mut trailing_dot = false
  if labels[labels.length() - 1].length() == 0 {
    labels.pop() |> ignore
    trailing_dot = true
  }
  let mut total = 0
  for i, label in labels {
    let n = alabel(label)
    if n == 0 {
      raise IDNAError("Empty label")
    }
    total += n + (if i > 0 { 1 } else { 0 })
  }
  if trailing_dot {
    total += 1
  }
  if total > 253 + (if trailing_dot { 1 } else { 0 }) {
    raise IDNAError("Domain too long")
  }
}
