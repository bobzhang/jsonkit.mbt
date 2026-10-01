///|
/// Generated from CPython 3.13 `re` behaviour.
let regex_subjects : Array[String] = [
  "", "a", "aaa", "abc", "ABC", "bar", "foobar", "foo bar", "fo", "f\no", "123",
  "\u{661}\u{662}\u{663}", "a\n", "abab", "x", "xy", "xxxy", "aab", "{foo}", "a{",
  "\u{e9}", "\u{c9}", "\u{ff}\u{100}", "a b", " ", "\u{3000}", "\t", "user@example.com",
  "b\na", "ab\n", "\u{11f}", "a_1", "\u{2028}", "abc\n", "\u{b}",
]

///|
let regex_cases : Array[(String, Array[Bool]?)] = [
  (
    "^a*$",
    Some([
      true, true, true, false, false, false, false, false, false, false, false, false,
      true, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false,
    ]),
  ),
  (
    "a+",
    Some([
      false, true, true, true, false, true, true, true, false, false, false, false,
      true, true, false, false, false, true, false, true, false, false, false, true,
      false, false, false, true, true, true, false, true, false, true, false,
    ]),
  ),
  (
    "^[a-m]",
    Some([
      false, true, true, true, false, true, true, true, true, true, false, false,
      true, true, false, false, false, true, false, true, false, false, false, true,
      false, false, false, false, true, true, false, true, false, true, false,
    ]),
  ),
  (
    "^\\d+$",
    Some([
      false, false, false, false, false, false, false, false, false, false, true,
      true, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false,
    ]),
  ),
  (
    "^\\w+$",
    Some([
      false, true, true, true, true, true, true, false, true, false, true, true,
      true, true, true, true, true, true, false, false, true, true, true, false,
      false, false, false, false, false, true, true, true, false, true, false,
    ]),
  ),
  (
    "\\s",
    Some([
      false, false, false, false, false, false, false, true, false, true, false,
      false, true, false, false, false, false, false, false, false, false, false,
      false, true, true, true, true, false, true, true, false, false, true, true,
      true,
    ]),
  ),
  (
    "^.*bar$",
    Some([
      false, false, false, false, false, true, true, true, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false,
    ]),
  ),
  (
    "f.*o",
    Some([
      false, false, false, false, false, false, true, true, true, false, false, false,
      false, false, false, false, false, false, true, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false,
    ]),
  ),
  (
    "f.o",
    Some([
      false, false, false, false, false, false, true, true, false, false, false,
      false, false, false, false, false, false, false, true, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false,
    ]),
  ),
  (
    "^[0-9]{2,}$",
    Some([
      false, false, false, false, false, false, false, false, false, false, true,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false,
    ]),
  ),
  (
    "^\u{e1}",
    Some([
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false,
    ]),
  ),
  (
    "[]a]",
    Some([
      false, true, true, true, false, true, true, true, false, false, false, false,
      true, true, false, false, false, true, false, true, false, false, false, true,
      false, false, false, true, true, true, false, true, false, true, false,
    ]),
  ),
  (
    "[^]a]",
    Some([
      false, false, false, true, true, true, true, true, true, true, true, true,
      true, true, true, true, true, true, true, true, true, true, true, true, true,
      true, true, true, true, true, true, true, true, true, true,
    ]),
  ),
  (
    "a{,2}b",
    Some([
      false, false, false, true, false, true, true, true, false, false, false, false,
      false, true, false, false, false, true, false, false, false, false, false,
      true, false, false, false, false, true, true, false, false, false, true, false,
    ]),
  ),
  (
    "a{2}",
    Some([
      false, false, true, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, true, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false,
    ]),
  ),
  (
    "a{",
    Some([
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, true, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false,
    ]),
  ),
  (
    "{foo}",
    Some([
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, true, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false,
    ]),
  ),
  (
    "x{1,3}?y",
    Some([
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, true, true, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false,
    ]),
  ),
  (
    "(a)\\1",
    Some([
      false, false, true, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, true, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false,
    ]),
  ),
  (
    "(?P<x>ab)(?P=x)",
    Some([
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, true, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false,
    ]),
  ),
  (
    "(?i)abc",
    Some([
      false, false, false, true, true, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      true, false,
    ]),
  ),
  (
    "(?i:ab)c",
    Some([
      false, false, false, true, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      true, false,
    ]),
  ),
  (
    "(?x) a b # comment",
    Some([
      false, false, false, true, false, false, false, false, false, false, false,
      false, false, true, false, false, false, true, false, false, false, false,
      false, false, false, false, false, false, false, true, false, false, false,
      true, false,
    ]),
  ),
  (
    "^\\x41B\\U00000043$",
    Some([
      false, false, false, false, true, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false,
    ]),
  ),
  (
    "\\0",
    Some([
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false,
    ]),
  ),
  (
    "[\\d-]",
    Some([
      false, false, false, false, false, false, false, false, false, false, true,
      true, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, true, false,
      false, false,
    ]),
  ),
  (
    "[a\\-z]",
    Some([
      false, true, true, true, false, true, true, true, false, false, false, false,
      true, true, false, false, false, true, false, true, false, false, false, true,
      false, false, false, true, true, true, false, true, false, true, false,
    ]),
  ),
  (
    "^(?:a|b)+$",
    Some([
      false, true, true, false, false, false, false, false, false, false, false,
      false, true, true, false, false, false, true, false, false, false, false, false,
      false, false, false, false, false, false, true, false, false, false, false,
      false,
    ]),
  ),
  (
    "^(a|bc)*$",
    Some([
      true, true, true, true, false, false, false, false, false, false, false, false,
      true, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, true,
      false,
    ]),
  ),
  (
    "\\bfoo\\b",
    Some([
      false, false, false, false, false, false, false, true, false, false, false,
      false, false, false, false, false, false, false, true, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false,
    ]),
  ),
  (
    "^$",
    Some([
      true, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false,
    ]),
  ),
  (
    "$",
    Some([
      true, true, true, true, true, true, true, true, true, true, true, true, true,
      true, true, true, true, true, true, true, true, true, true, true, true, true,
      true, true, true, true, true, true, true, true, true,
    ]),
  ),
  (
    "a$",
    Some([
      false, true, true, false, false, false, false, false, false, false, false,
      false, true, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, true, false, false, false, false,
      false, false,
    ]),
  ),
  (
    "^\\n?$",
    Some([
      true, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false,
    ]),
  ),
  (
    "[\\w.-]+@[\\w-]+",
    Some([
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, true, false, false, false, false, false,
      false, false,
    ]),
  ),
  (
    "(?s)a.b",
    Some([
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, true, false, false, false, false,
      false, true, false, false, false, false, false, false, false, false, false,
      false, false,
    ]),
  ),
  (
    "a.b",
    Some([
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, true, false, false, false, false,
      false, true, false, false, false, false, false, false, false, false, false,
      false, false,
    ]),
  ),
  (
    "(?m)^b",
    Some([
      false, false, false, false, false, true, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, true, false, false, false, false,
      false, false,
    ]),
  ),
  (
    "\\Aa",
    Some([
      false, true, true, true, false, false, false, false, false, false, false, false,
      true, true, false, false, false, true, false, true, false, false, false, true,
      false, false, false, false, false, true, false, true, false, true, false,
    ]),
  ),
  (
    "a\\Z",
    Some([
      false, true, true, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, true, false, false, false, false,
      false, false,
    ]),
  ),
  (
    "[^\\W\\d]",
    Some([
      false, true, true, true, true, true, true, true, true, true, false, false,
      true, true, true, true, true, true, true, true, true, true, true, true, false,
      false, false, true, true, true, true, true, false, true, false,
    ]),
  ),
  (
    "\\.",
    Some([
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, true, false, false, false, false, false,
      false, false,
    ]),
  ),
  (
    "\\$",
    Some([
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false,
    ]),
  ),
  (
    "[.]",
    Some([
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, true, false, false, false, false, false,
      false, false,
    ]),
  ),
  (
    "a|",
    Some([
      true, true, true, true, true, true, true, true, true, true, true, true, true,
      true, true, true, true, true, true, true, true, true, true, true, true, true,
      true, true, true, true, true, true, true, true, true,
    ]),
  ),
  (
    "|a",
    Some([
      true, true, true, true, true, true, true, true, true, true, true, true, true,
      true, true, true, true, true, true, true, true, true, true, true, true, true,
      true, true, true, true, true, true, true, true, true,
    ]),
  ),
  (
    "(?:)",
    Some([
      true, true, true, true, true, true, true, true, true, true, true, true, true,
      true, true, true, true, true, true, true, true, true, true, true, true, true,
      true, true, true, true, true, true, true, true, true,
    ]),
  ),
  ("a**", None),
  ("*a", None),
  (
    "(?<=a)b",
    Some([
      false, false, false, true, false, false, false, false, false, false, false,
      false, false, true, false, false, false, true, false, false, false, false,
      false, false, false, false, false, false, false, true, false, false, false,
      true, false,
    ]),
  ),
  (
    "(?=a)",
    Some([
      false, true, true, true, false, true, true, true, false, false, false, false,
      true, true, false, false, false, true, false, true, false, false, false, true,
      false, false, false, true, true, true, false, true, false, true, false,
    ]),
  ),
  ("\\p{Letter}", None),
  ("\\c", None),
  ("[z-a]", None),
  ("(", None),
  (")", None),
  ("[", None),
  ("a{3,2}", None),
  ("(?P<1>a)", None),
  ("\\1", None),
  ("(a)(?P=b)", None),
  (
    "(?i)\u{e9}",
    Some([
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, true, true,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false,
    ]),
  ),
  (
    "\u{e9}",
    Some([
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, true, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false,
    ]),
  ),
  (
    "[\u{100}-\u{17f}]+",
    Some([
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      true, false, false, false, false, false, false, false, true, false, false,
      false, false,
    ]),
  ),
  (
    "^\\S+$",
    Some([
      false, true, true, true, true, true, true, false, true, false, true, true,
      true, true, true, true, true, true, true, true, true, true, true, false, false,
      false, false, true, false, true, true, true, false, true, false,
    ]),
  ),
  (
    "\\W",
    Some([
      false, false, false, false, false, false, false, true, false, true, false,
      false, true, false, false, false, false, false, true, true, false, false, false,
      true, true, true, true, true, true, true, false, false, true, true, true,
    ]),
  ),
  (
    "\\D",
    Some([
      false, true, true, true, true, true, true, true, true, true, false, false,
      true, true, true, true, true, true, true, true, true, true, true, true, true,
      true, true, true, true, true, true, true, true, true, true,
    ]),
  ),
  (
    "([abc])+\\s+$",
    Some([
      false, false, false, false, false, false, false, false, false, false, false,
      false, true, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, true, false, false, false,
      true, false,
    ]),
  ),
  ("^(abc]", None),
  (
    "^[a-zA-Z][a-zA-Z0-9_]*$",
    Some([
      false, true, true, true, true, true, true, false, true, false, false, false,
      true, true, true, true, true, true, false, false, false, false, false, false,
      false, false, false, false, false, true, false, true, false, true, false,
    ]),
  ),
  (
    "(?#comment)x",
    Some([
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, true, true, true, false, false, false, false, false, false,
      false, false, false, false, true, false, false, false, false, false, false,
      false,
    ]),
  ),
  ("x(?i)", None),
  (
    "[[:alpha:]]",
    Some([
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false,
    ]),
  ),
  (
    "\\N{LATIN SMALL LETTER A}",
    Some([
      false, true, true, true, false, true, true, true, false, false, false, false,
      true, true, false, false, false, true, false, true, false, false, false, true,
      false, false, false, true, true, true, false, true, false, true, false,
    ]),
  ),
  ("(a)|\\2", None),
  (
    "a{1000}",
    Some([
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false,
    ]),
  ),
  (
    "(?a)\\w+",
    Some([
      false, true, true, true, true, true, true, true, true, true, true, false, true,
      true, true, true, true, true, true, true, false, false, false, true, false,
      false, false, true, true, true, false, true, false, true, false,
    ]),
  ),
  (
    "[\\s\\S]",
    Some([
      false, true, true, true, true, true, true, true, true, true, true, true, true,
      true, true, true, true, true, true, true, true, true, true, true, true, true,
      true, true, true, true, true, true, true, true, true,
    ]),
  ),
  (
    "^\\t",
    Some([
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, true, false, false, false, false, false, false,
      false, false,
    ]),
  ),
  (
    "\\v",
    Some([
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, true,
    ]),
  ),
  (
    "\\a",
    Some([
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false, false, false, false, false, false, false, false, false, false,
      false, false,
    ]),
  ),
]
