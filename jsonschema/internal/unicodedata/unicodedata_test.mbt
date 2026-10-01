///|
test "properties" {
  inspect(@unicodedata.is_decimal('٣'.to_int()), content="true")
  inspect(@unicodedata.is_decimal('a'.to_int()), content="false")
  inspect(@unicodedata.is_printable(0x7f), content="false")
  inspect(@unicodedata.is_printable('é'.to_int()), content="true")
  inspect(@unicodedata.is_space(0x85), content="true")
  inspect(@unicodedata.bidirectional('a'.to_int()), content="L")
  inspect(@unicodedata.bidirectional(0x05D0), content="R")
  inspect(@unicodedata.combining(0x094D), content="9")
  inspect(@unicodedata.has_name(0), content="false")
  inspect(@unicodedata.has_name('a'.to_int()), content="true")
}

///|
test "nfc" {
  let s = @unicodedata.code_points("e\u{301}\u{1100}\u{1161}\u{11A8}")
  debug_inspect(@unicodedata.nfc(s), content="[233, 44033]")
  // singleton decomposition (ANGSTROM SIGN -> A WITH RING)
  debug_inspect(@unicodedata.nfc([0x212B]), content="[197]")
  // reordering of marks
  debug_inspect(@unicodedata.nfc([0x61, 0x0323, 0x0302]), content="[7853]")
}

///|
test "code points" {
  let s = "a\u{1F600}"
  debug_inspect(@unicodedata.code_points(s), content="[97, 128512]")
  inspect(@unicodedata.py_len(s), content="2")
  inspect(@unicodedata.from_code_points([97, 128512]) == s, content="true")
}
